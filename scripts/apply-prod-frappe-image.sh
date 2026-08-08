#!/usr/bin/env bash
set -euo pipefail

: "${PROD_ROOT:=/opt/velveta/prod/frappe}"
: "${FRAPPE_COMPOSE_FILE:=/opt/velveta/prod/frappe/docker-compose.frappe.yml}"
: "${SITE_NAME:=erp.velvetacare.com}"
: "${FRAPPE_ASSETS_VOLUME:=frappe_assets}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${PROD_ROOT}"

docker compose -f "${FRAPPE_COMPOSE_FILE}" down --remove-orphans
docker volume rm -f "${FRAPPE_ASSETS_VOLUME}" >/dev/null 2>&1 || true

docker compose -f "${FRAPPE_COMPOSE_FILE}" up -d db redis-cache redis-queue configurator
docker compose -f "${FRAPPE_COMPOSE_FILE}" up --abort-on-container-exit --exit-code-from create-site create-site
docker compose -f "${FRAPPE_COMPOSE_FILE}" up -d

docker compose -f "${FRAPPE_COMPOSE_FILE}" exec -T backend bash -lc "
  set -euo pipefail
  cd /home/frappe/frappe-bench
  test -f sites/${SITE_NAME}/site_config.json
  for app in payments blog drive writer; do
    bench --site ${SITE_NAME} list-apps | awk '{print \$1}' | grep -qx \"\${app}\" || bench --site ${SITE_NAME} install-app \"\${app}\"
  done
  bench --site ${SITE_NAME} migrate
  bench --site ${SITE_NAME} execute ecommerce.printing.sync_sales_print_formats.sync_sales_print_formats
  bench --site ${SITE_NAME} execute ecommerce.patches.ensure_hepsijet_shipping_rates.execute
  bench --site ${SITE_NAME} clear-cache
"

FRAPPE_COMPOSE_FILE="${FRAPPE_COMPOSE_FILE}" SITE_NAME="${SITE_NAME}" "${SCRIPT_DIR}/sync-prod-frappe-assets.sh"
