#!/usr/bin/env bash
set -euo pipefail

: "${PROD_ROOT:=/opt/velveta/prod}"
: "${FRAPPE_COMPOSE_FILE:=/opt/velveta/prod/docker-compose.frappe.yml}"
: "${SITE_NAME:=erp.velvetacare.com}"
MARKER_FILE="${PROD_ROOT}/.fresh-bootstrap-complete"

cd "${PROD_ROOT}"

if [[ ! -f "${MARKER_FILE}" ]]; then
  docker compose -f "${FRAPPE_COMPOSE_FILE}" down --remove-orphans || true
  docker volume rm -f frappe_db-data frappe_sites frappe_logs frappe_redis-queue-data || true
fi

docker compose -f "${FRAPPE_COMPOSE_FILE}" up -d db redis-cache redis-queue configurator
docker compose -f "${FRAPPE_COMPOSE_FILE}" up --abort-on-container-exit --exit-code-from create-site create-site
docker compose -f "${FRAPPE_COMPOSE_FILE}" up -d
docker compose -f "${FRAPPE_COMPOSE_FILE}" exec -T backend \
  bash -lc "test -f sites/${SITE_NAME}/site_config.json && bench --site ${SITE_NAME} migrate"
touch "${MARKER_FILE}"
