#!/usr/bin/env bash
set -euo pipefail

: "${APPS_JSON_PATH:=/opt/velveta/prod/frappe/apps.json}"
: "${FRAPPE_IMAGE_ROOT:=/opt/velveta/prod/frappe/image}"
: "${FRAPPE_IMAGE_TAG:=velveta-frappe-prod:16}"
: "${FRAPPE_REPO_URL:=https://github.com/frappe/frappe}"
: "${FRAPPE_REPO_BRANCH:=version-16}"

if [[ ! -f "${APPS_JSON_PATH}" ]]; then
  echo "Missing apps.json at ${APPS_JSON_PATH}" >&2
  exit 1
fi

APPS_JSON_BASE64="$(base64 -w 0 "${APPS_JSON_PATH}")"

github_pat_file="${GITHUB_PAT_FILE:-/opt/velveta/infra-prod/.secrets/github_runner_pat}"
github_pat=""
if [[ -f "${github_pat_file}" ]]; then
  github_pat="$(tr -d '\n' < "${github_pat_file}")"
fi

APP_SOURCES_FINGERPRINT="$(
  APPS_JSON_PATH="${APPS_JSON_PATH}" GITHUB_PAT="${github_pat}" python3 <<'PY'
import json
import os
import subprocess
import sys
from urllib.parse import urlparse

apps_json_path = os.environ["APPS_JSON_PATH"]
github_pat = os.environ.get("GITHUB_PAT", "").strip()

with open(apps_json_path, "r", encoding="utf-8") as f:
    apps = json.load(f)

fingerprints = []

for app in apps:
    url = app["url"]
    branch = app["branch"]
    remote = url

    parsed = urlparse(url)
    if github_pat and parsed.scheme == "https" and parsed.netloc == "github.com":
        remote = f"https://oauth2:{github_pat}@github.com{parsed.path}"

    result = subprocess.run(
        ["git", "ls-remote", remote, branch],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        sys.stderr.write(
            f"Failed to resolve remote ref for {url}@{branch}: {result.stderr.strip()}\n"
        )
        sys.exit(result.returncode)

    line = next((ln for ln in result.stdout.splitlines() if ln.strip()), "")
    sha = line.split()[0] if line else "missing"
    fingerprints.append(f"{url}@{branch}={sha}")

print("|".join(fingerprints))
PY
)"

docker_build_args=(
  --build-arg=FRAPPE_PATH="${FRAPPE_REPO_URL}"
  --build-arg=FRAPPE_BRANCH="${FRAPPE_REPO_BRANCH}"
  --build-arg=APPS_JSON_BASE64="${APPS_JSON_BASE64}"
  --build-arg=APP_SOURCES_FINGERPRINT="${APP_SOURCES_FINGERPRINT}"
  --tag="${FRAPPE_IMAGE_TAG}"
  --file="${FRAPPE_IMAGE_ROOT}/Containerfile"
)

if [[ -f "${github_pat_file}" ]]; then
  docker_build_args+=(--secret "id=github_pat,src=${github_pat_file}")
fi

docker build "${docker_build_args[@]}" "${FRAPPE_IMAGE_ROOT}"
