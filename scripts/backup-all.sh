#!/usr/bin/env bash
set -euo pipefail

umask 077

timestamp="$(date +%Y%m%d_%H%M%S)"
backup_root="/opt/velveta/backups"
target_dir="${backup_root}/${timestamp}"

mkdir -p "${target_dir}/prod" "${target_dir}/system"

if docker ps --format '{{.Names}}' | grep -qx 'frappe-db-1'; then
  docker exec frappe-db-1 mariadb-dump -uroot -ptshMGh8eyfeQeVCBup9DmB4fYgQYqtcq --all-databases > "${target_dir}/prod/prod-frappe-db.sql"
fi

if docker volume inspect frappe_sites >/dev/null 2>&1; then
  docker run --rm \
    -v frappe_sites:/src:ro \
    -v "${target_dir}/prod:/backup" \
    alpine:3.20 \
    sh -lc 'tar -czf /backup/prod-frappe-sites-volume.tgz -C /src .'
fi

tar -czf "${target_dir}/system/nginx-config.tgz" -C "/opt/velveta" nginx
tar \
  --exclude='infra-prod/.git' \
  -czf "${target_dir}/system/infra-config.tgz" \
  -C "/opt/velveta" infra-prod

if [ -d "/opt/actions-runner-frontendx" ]; then
  tar -czf "${target_dir}/system/actions-runner-frontendx.tgz" -C /opt actions-runner-frontendx
fi

if [ -d "/opt/actions-runner-ecommerce" ]; then
  tar -czf "${target_dir}/system/actions-runner-ecommerce.tgz" -C /opt actions-runner-ecommerce
fi

if [ -f /etc/systemd/system/actions.runner.ibober89-ecommerce.vm519642-ecommerce.service ]; then
  cp /etc/systemd/system/actions.runner.ibober89-ecommerce.vm519642-ecommerce.service "${target_dir}/system/"
fi

if [ -f /etc/systemd/system/actions.runner.ibober89-frontendX.vm519642-frontendx.service ]; then
  cp /etc/systemd/system/actions.runner.ibober89-frontendX.vm519642-frontendx.service "${target_dir}/system/"
fi

ln -sfn "${target_dir}" "${backup_root}/latest"

find "${backup_root}" -mindepth 1 -maxdepth 1 -type d -mtime +1 -exec rm -rf {} +
