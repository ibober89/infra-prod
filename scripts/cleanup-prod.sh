#!/usr/bin/env bash
set -Eeuo pipefail

lock_file=/run/velveta-cleanup.lock
exec 9>"${lock_file}"
if ! flock -n 9; then
  echo "Velveta cleanup is already running; exiting."
  exit 0
fi

if pgrep -f 'Runner\.Worker|docker build|buildkit|buildx|build-prod-frappe-image\.sh' >/dev/null; then
  echo "A deploy/build job is active; skipping cleanup."
  exit 0
fi

echo "== Disk before cleanup =="
df -h / /opt || true
docker system df || true

echo "== Docker cleanup =="
docker container prune -f || true
docker image prune -f || true
docker builder prune -af --filter 'until=12h' || true

echo "== Runner update cleanup =="
for runner_root in "/opt/actions-runner-ecommerce" "/opt/actions-runner-frontendx"; do
  [ -d "${runner_root}" ] || continue

  mkdir -p "${runner_root}/_work/_update"
  rm -rf "${runner_root}/_work/_update"/*
  chown -R "github-runner:github-runner" "${runner_root}/_work/_update" || true

  active_bin="$(readlink -f "${runner_root}/bin" || true)"
  active_externals="$(readlink -f "${runner_root}/externals" || true)"

  find "${runner_root}" -maxdepth 1 -mindepth 1 -type d \( -name 'bin.*' -o -name 'externals.*' \) -print0 |
    while IFS= read -r -d '' path; do
      real_path="$(readlink -f "${path}" || true)"
      if [ "${real_path}" != "${active_bin}" ] && [ "${real_path}" != "${active_externals}" ]; then
        rm -rf "${path}"
      fi
    done
done

echo "== Backup retention cleanup =="
find "/opt/velveta/backups" -mindepth 1 -maxdepth 1 -type d -mtime +1 -exec rm -rf {} +

echo "== Journal cleanup =="
journalctl --vacuum-time=7d --vacuum-size=300M || true

echo "== Disk after cleanup =="
df -h / /opt || true
docker system df || true
