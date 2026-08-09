#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import subprocess
import sys
from pathlib import Path


DEFAULT_RULES_PATH = Path(__file__).resolve().parents[1] / "deploy-rules.json"


def run_git(repo_root: Path, args: list[str]) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout


def changed_files(repo_root: Path, base: str, head: str) -> list[str]:
    if not base or set(base) == {"0"}:
        output = run_git(repo_root, ["diff-tree", "--no-commit-id", "--name-only", "-r", head])
    else:
        output = run_git(repo_root, ["diff", "--name-only", f"{base}..{head}"])
    return sorted(path for path in output.splitlines() if path.strip())


def matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def classify(paths: list[str], repo_rules: dict[str, list[str]]) -> dict[str, object]:
    hits: dict[str, list[str]] = {name: [] for name in repo_rules}
    unmatched: list[str] = []

    for path in paths:
        matched_any = False
        for name, patterns in repo_rules.items():
            if matches(path, patterns):
                hits[name].append(path)
                matched_any = True
        if not matched_any:
            unmatched.append(path)

    full_image = bool(hits.get("full_image") or hits.get("vendor_patch"))
    if full_image:
        mode = "full_image"
    elif hits.get("compose_required"):
        mode = "compose_required"
    elif hits.get("edge_nginx") and not any(
        hits.get(name)
        for name in ("migrate_required", "asset_build_required", "restart_required")
    ):
        mode = "edge_nginx"
    elif any(hits.get(name) for name in ("migrate_required", "asset_build_required", "restart_required")):
        mode = "ecommerce_fast"
    elif hits.get("runner_required"):
        mode = "runner_required"
    elif paths and not unmatched:
        mode = "docs_only"
    else:
        mode = "full_image"
        full_image = True

    return {
        "mode": mode,
        "full_image": full_image,
        "migrate": bool(hits.get("migrate_required") or full_image),
        "asset_build": bool(hits.get("asset_build_required") or full_image),
        "restart": bool(hits.get("restart_required") or full_image),
        "edge_nginx": bool(hits.get("edge_nginx")),
        "compose": bool(hits.get("compose_required")),
        "runner": bool(hits.get("runner_required")),
        "hits": {key: value for key, value in hits.items() if value},
        "unmatched": unmatched,
    }


def write_github_output(summary: dict[str, object]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with open(output_path, "a", encoding="utf-8") as output:
        for key in ("mode", "full_image", "migrate", "asset_build", "restart", "edge_nginx", "compose", "runner"):
            value = summary[key]
            if isinstance(value, bool):
                value = str(value).lower()
            output.write(f"{key}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify deployment scope from changed files.")
    parser.add_argument("--repo", required=True, help="Repository name, for example ibober89/ecommerce")
    parser.add_argument("--repo-root", default=".", help="Git repository root to diff")
    parser.add_argument("--base", default=os.environ.get("GITHUB_EVENT_BEFORE", ""))
    parser.add_argument("--head", default=os.environ.get("GITHUB_SHA", "HEAD"))
    parser.add_argument("--rules", default=str(DEFAULT_RULES_PATH))
    parser.add_argument("--format", choices=("summary", "json", "env"), default="summary")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    rules = json.loads(Path(args.rules).read_text(encoding="utf-8"))
    repo_rules = rules.get("repositories", {}).get(args.repo)
    if repo_rules is None:
        raise SystemExit(f"No deploy rules found for repository {args.repo}")

    paths = changed_files(repo_root, args.base, args.head)
    summary = classify(paths, repo_rules)
    summary["repo"] = args.repo
    summary["base"] = args.base
    summary["head"] = args.head
    summary["changed_files"] = paths

    write_github_output(summary)

    if args.format == "json":
        print(json.dumps(summary, indent=2, sort_keys=True))
    elif args.format == "env":
        for key in ("mode", "full_image", "migrate", "asset_build", "restart", "edge_nginx", "compose", "runner"):
            value = summary[key]
            if isinstance(value, bool):
                value = str(value).lower()
            print(f"DEPLOY_{key.upper()}={value}")
    else:
        print(f"Deploy scope for {args.repo}: {summary['mode']}")
        print(f"Changed files: {len(paths)}")
        for key in ("full_image", "migrate", "asset_build", "restart", "edge_nginx", "compose", "runner"):
            print(f"{key}: {summary[key]}")
        if summary["hits"]:
            print("Matched rules:")
            for name, matched in summary["hits"].items():
                print(f"  {name}:")
                for path in matched:
                    print(f"    - {path}")
        if summary["unmatched"]:
            print("Unmatched files force full_image until rules are updated:")
            for path in summary["unmatched"]:
                print(f"  - {path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
