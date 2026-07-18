#!/usr/bin/env bash
set -euo pipefail

: "${APPS_JSON_PATH:=/opt/velveta/prod/frappe/apps.json}"
: "${FRAPPE_IMAGE_ROOT:=/opt/velveta/prod/frappe/image}"
: "${FRAPPE_IMAGE_TAG:=velveta-frappe-prod:16}"
: "${FRAPPE_REPO_URL:=https://github.com/frappe/frappe}"
: "${FRAPPE_REPO_BRANCH:=version-16}"
: "${FRAPPE_REPO_COMMIT:=}"
: "${FRAPPE_DOTENV_PATH:=/opt/velveta/prod/frappe/.env}"

if [[ ! -f "${APPS_JSON_PATH}" ]]; then
  echo "Missing apps.json at ${APPS_JSON_PATH}" >&2
  exit 1
fi

if [[ -z "${FRAPPE_REPO_COMMIT}" ]]; then
  echo "FRAPPE_REPO_COMMIT is required for production builds. Refusing to build branch head ${FRAPPE_REPO_URL}@${FRAPPE_REPO_BRANCH}." >&2
  exit 1
fi

if [[ "${GITHUB_REPOSITORY:-}" == "ibober89/ecommerce" && "${GITHUB_REF_NAME:-}" != "main" ]]; then
  echo "Production ecommerce builds must be triggered from main, not ${GITHUB_REF_NAME:-unknown}." >&2
  exit 1
fi

effective_apps_json_path="${APPS_JSON_PATH}"
generated_apps_json_path=""
normalized_apps_json_path=""
github_pat_file="${GITHUB_PAT_FILE:-/opt/velveta/infra-prod/.secrets/github_runner_pat}"
github_pat=""
if [[ -f "${github_pat_file}" ]]; then
  github_pat="$(tr -d '\n' < "${github_pat_file}")"
fi

if [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_SHA:-}" ]]; then
  generated_apps_json_path="$(mktemp)"
  APPS_JSON_PATH="${APPS_JSON_PATH}" \
  GENERATED_APPS_JSON_PATH="${generated_apps_json_path}" \
  GITHUB_REPOSITORY="${GITHUB_REPOSITORY}" \
  GITHUB_SHA="${GITHUB_SHA}" \
  GITHUB_REF_NAME="${GITHUB_REF_NAME:-}" \
  python3 <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import urlparse

source = Path(os.environ["APPS_JSON_PATH"])
target = Path(os.environ["GENERATED_APPS_JSON_PATH"])
repo = os.environ["GITHUB_REPOSITORY"].strip().lower()
sha = os.environ["GITHUB_SHA"].strip()
ref_name = os.environ.get("GITHUB_REF_NAME", "").strip()


def repo_from_url(url: str) -> str:
    parsed = urlparse(url)
    path = parsed.path.strip("/")
    if path.endswith(".git"):
        path = path[:-4]
    return path.lower()


apps = json.loads(source.read_text(encoding="utf-8"))
updated = False

for app in apps:
    if repo_from_url(app.get("url", "")) == repo:
        if repo == "ibober89/ecommerce" and ref_name != "main":
            sys.stderr.write(
                f"ERROR: production ecommerce builds must use main, not {ref_name or 'unknown'}.\n"
            )
            sys.exit(1)
        app["commit"] = sha
        if ref_name:
            app["branch"] = ref_name
        updated = True

target.write_text(json.dumps(apps, indent=2) + "\n", encoding="utf-8")

if updated:
    print(f"Using GitHub Actions commit override for {repo}: {sha}")
else:
    print(f"No apps.json entry matched GitHub repository {repo}; using apps.json unchanged.")
PY
  effective_apps_json_path="${generated_apps_json_path}"
fi

normalized_apps_json_path="$(mktemp)"
APPS_JSON_PATH="${effective_apps_json_path}" \
NORMALIZED_APPS_JSON_PATH="${normalized_apps_json_path}" \
GITHUB_PAT="${github_pat}" \
python3 <<'PY'
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse

source = Path(os.environ["APPS_JSON_PATH"])
target = Path(os.environ["NORMALIZED_APPS_JSON_PATH"])
github_pat = os.environ.get("GITHUB_PAT", "").strip()


def resolve_remote(url: str) -> str:
    parsed = urlparse(url)
    if github_pat and parsed.scheme == "https" and parsed.netloc == "github.com":
        return f"https://oauth2:{github_pat}@github.com{parsed.path}"
    return url


def repo_from_url(url: str) -> str:
	parsed = urlparse(url)
	path = parsed.path.strip("/")
	if path.endswith(".git"):
		path = path[:-4]
	return path.lower()


def assert_fetchable_commit(url: str, commit: str) -> None:
	with tempfile.TemporaryDirectory() as tmp:
		subprocess.run(["git", "-C", tmp, "init", "-q"], check=True)
		result = subprocess.run(
			["git", "-C", tmp, "fetch", "--depth=1", resolve_remote(url), commit],
			capture_output=True,
			text=True,
			check=False,
		)
		if result.returncode != 0:
			sys.stderr.write(
				f"ERROR: pinned commit is not fetchable for {url}: {commit}.\n"
			)
			if result.stderr:
				sys.stderr.write(result.stderr)
			sys.exit(result.returncode)


apps = json.loads(source.read_text(encoding="utf-8"))

for app in apps:
	parsed_repo = repo_from_url(app.get("url", ""))
	branch = (app.get("branch") or "").strip()
	if parsed_repo == "ibober89/ecommerce" and branch != "main":
		sys.stderr.write(f"ERROR: production ecommerce app must be pinned to main, not {branch or 'missing'}.\n")
		sys.exit(1)
	commit = (app.get("commit") or "").strip()
	if not commit:
		sys.stderr.write(f"ERROR: missing pinned commit for {app['url']}@{app.get('branch', '')}.\n")
		sys.exit(1)
	assert_fetchable_commit(app["url"], commit)

target.write_text(json.dumps(apps, indent=2) + "\n", encoding="utf-8")
PY
effective_apps_json_path="${normalized_apps_json_path}"
trap '[[ -n "${generated_apps_json_path:-}" ]] && rm -f "${generated_apps_json_path}"; [[ -n "${normalized_apps_json_path:-}" ]] && rm -f "${normalized_apps_json_path}"' EXIT

APPS_JSON_PATH="${effective_apps_json_path}"
APPS_JSON_BASE64="$(base64 -w 0 "${APPS_JSON_PATH}")"

APP_SOURCES_FINGERPRINT="$(
  APPS_JSON_PATH="${APPS_JSON_PATH}" GITHUB_PAT="${github_pat}" FRAPPE_REPO_URL="${FRAPPE_REPO_URL}" FRAPPE_REPO_BRANCH="${FRAPPE_REPO_BRANCH}" FRAPPE_REPO_COMMIT="${FRAPPE_REPO_COMMIT}" python3 <<'PY'
import json
import os
import subprocess
import sys
from urllib.parse import urlparse

apps_json_path = os.environ["APPS_JSON_PATH"]
github_pat = os.environ.get("GITHUB_PAT", "").strip()
frappe_repo_url = os.environ["FRAPPE_REPO_URL"]
frappe_repo_branch = os.environ["FRAPPE_REPO_BRANCH"]
frappe_repo_commit = os.environ.get("FRAPPE_REPO_COMMIT", "").strip()

if not frappe_repo_commit:
    sys.stderr.write(
        f"ERROR: FRAPPE_REPO_COMMIT is required for {frappe_repo_url}@{frappe_repo_branch}.\n"
    )
    sys.exit(1)

with open(apps_json_path, "r", encoding="utf-8") as f:
    apps = json.load(f)

fingerprints = []


def resolve_remote(url: str) -> str:
    parsed = urlparse(url)
    if github_pat and parsed.scheme == "https" and parsed.netloc == "github.com":
        return f"https://oauth2:{github_pat}@github.com{parsed.path}"
    return url


def resolve_branch_sha(url: str, branch: str) -> str:
    result = subprocess.run(
        ["git", "ls-remote", resolve_remote(url), branch],
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
    return line.split()[0] if line else "missing"


fingerprints.append(f"{frappe_repo_url}@{frappe_repo_branch}={frappe_repo_commit}")

for app in apps:
    url = app["url"]
    branch = app["branch"]
    sha = (app.get("commit") or "").strip()
    if not sha:
        sys.stderr.write(f"ERROR: missing pinned commit for {url}@{branch}.\n")
        sys.exit(1)
    fingerprints.append(f"{url}@{branch}={sha}")

print("|".join(fingerprints))
PY
)"

docker_build_args=(
  --build-arg=FRAPPE_PATH="${FRAPPE_REPO_URL}"
  --build-arg=FRAPPE_BRANCH="${FRAPPE_REPO_BRANCH}"
  --build-arg=FRAPPE_COMMIT="${FRAPPE_REPO_COMMIT}"
  --build-arg=APPS_JSON_BASE64="${APPS_JSON_BASE64}"
  --build-arg=APP_SOURCES_FINGERPRINT="${APP_SOURCES_FINGERPRINT}"
  --tag="${FRAPPE_IMAGE_TAG}"
  --file="${FRAPPE_IMAGE_ROOT}/Containerfile"
)

if [[ -f "${github_pat_file}" ]]; then
  docker_build_args+=(--secret "id=github_pat,src=${github_pat_file}")
fi

previous_image_id=""
if docker image inspect "${FRAPPE_IMAGE_TAG}" >/dev/null 2>&1; then
  previous_image_id="$(docker image inspect "${FRAPPE_IMAGE_TAG}" --format '{{.Id}}')"
fi

docker build "${docker_build_args[@]}" "${FRAPPE_IMAGE_ROOT}"

new_image_id="$(docker image inspect "${FRAPPE_IMAGE_TAG}" --format '{{.Id}}')"
image_fingerprint="$(docker image inspect "${FRAPPE_IMAGE_TAG}" --format '{{ index .Config.Labels "org.velveta.app-sources-fingerprint" }}')"

if [[ "${image_fingerprint}" != "${APP_SOURCES_FINGERPRINT}" ]]; then
  echo "Built image fingerprint does not match expected app sources fingerprint." >&2
  echo "expected=${APP_SOURCES_FINGERPRINT}" >&2
  echo "actual=${image_fingerprint}" >&2
  exit 1
fi

python3 - "${FRAPPE_DOTENV_PATH}" "${APP_SOURCES_FINGERPRINT}" "${new_image_id}" <<'PY'
from pathlib import Path
import sys

dotenv_path = Path(sys.argv[1])
fingerprint = sys.argv[2]
image_id = sys.argv[3]

lines = []
if dotenv_path.exists():
    lines = dotenv_path.read_text(encoding="utf-8").splitlines()

updates = {
    "FRAPPE_DEPLOY_FINGERPRINT": fingerprint,
    "FRAPPE_IMAGE_ID": image_id,
}

seen = set()
new_lines = []
for line in lines:
    if "=" in line:
        key, _ = line.split("=", 1)
        if key in updates:
            new_lines.append(f"{key}={updates[key]}")
            seen.add(key)
            continue
    new_lines.append(line)

for key, value in updates.items():
    if key not in seen:
        new_lines.append(f"{key}={value}")

dotenv_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
PY

echo "App sources fingerprint: ${APP_SOURCES_FINGERPRINT}"
echo "Previous image id: ${previous_image_id:-<none>}"
echo "New image id: ${new_image_id}"
