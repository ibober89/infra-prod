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

docker_build_args=(
  --build-arg=FRAPPE_PATH="${FRAPPE_REPO_URL}"
  --build-arg=FRAPPE_BRANCH="${FRAPPE_REPO_BRANCH}"
  --build-arg=APPS_JSON_BASE64="${APPS_JSON_BASE64}"
  --tag="${FRAPPE_IMAGE_TAG}"
  --file="${FRAPPE_IMAGE_ROOT}/Containerfile"
)

github_pat_file="${GITHUB_PAT_FILE:-/opt/velveta/infra-prod/.secrets/github_runner_pat}"
if [[ -f "${github_pat_file}" ]]; then
  docker_build_args+=(--secret "id=github_pat,src=${github_pat_file}")
fi

docker build "${docker_build_args[@]}" "${FRAPPE_IMAGE_ROOT}"
