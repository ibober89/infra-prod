#!/bin/bash

set -euo pipefail

ASSETS_ROOT="/home/frappe/frappe-bench/sites/assets"

sync_app_assets() {
  local app="$1"
  local source_dir="/home/frappe/frappe-bench/apps/${app}/${app}/public"
  local target_dir="${ASSETS_ROOT}/${app}"

  if [[ ! -d "${source_dir}" ]]; then
    return 0
  fi

  rm -rf "${target_dir}"
  mkdir -p "${target_dir}"
  cp -a "${source_dir}/." "${target_dir}/"
}

for app in frappe erpnext payments ecommerce; do
  sync_app_assets "${app}"
done

if [[ -z "$BACKEND" ]]; then
  echo "BACKEND defaulting to 0.0.0.0:8000"
  export BACKEND=0.0.0.0:8000
fi
if [[ -z "$SOCKETIO" ]]; then
  echo "SOCKETIO defaulting to 0.0.0.0:9000"
  export SOCKETIO=0.0.0.0:9000
fi
if [[ -z "$UPSTREAM_REAL_IP_ADDRESS" ]]; then
  echo "UPSTREAM_REAL_IP_ADDRESS defaulting to 127.0.0.1"
  export UPSTREAM_REAL_IP_ADDRESS=127.0.0.1
fi
if [[ -z "$UPSTREAM_REAL_IP_HEADER" ]]; then
  echo "UPSTREAM_REAL_IP_HEADER defaulting to X-Forwarded-For"
  export UPSTREAM_REAL_IP_HEADER=X-Forwarded-For
fi
if [[ -z "$UPSTREAM_REAL_IP_RECURSIVE" ]]; then
  echo "UPSTREAM_REAL_IP_RECURSIVE defaulting to off"
  export UPSTREAM_REAL_IP_RECURSIVE=off
fi
if [[ -z "$FRAPPE_SITE_NAME_HEADER" ]]; then
  echo 'FRAPPE_SITE_NAME_HEADER defaulting to $host'
  export FRAPPE_SITE_NAME_HEADER='$host'
fi
if [[ -z "$PROXY_READ_TIMEOUT" ]]; then
  echo "PROXY_READ_TIMEOUT defaulting to 120"
  export PROXY_READ_TIMEOUT=120
fi
if [[ -z "$CLIENT_MAX_BODY_SIZE" ]]; then
  echo "CLIENT_MAX_BODY_SIZE defaulting to 50m"
  export CLIENT_MAX_BODY_SIZE=50m
fi

envsubst '${BACKEND}
  ${SOCKETIO}
  ${UPSTREAM_REAL_IP_ADDRESS}
  ${UPSTREAM_REAL_IP_HEADER}
  ${UPSTREAM_REAL_IP_RECURSIVE}
  ${FRAPPE_SITE_NAME_HEADER}
  ${PROXY_READ_TIMEOUT}
  ${CLIENT_MAX_BODY_SIZE}' \
  </templates/nginx/frappe.conf.template >/etc/nginx/conf.d/frappe.conf

nginx -g 'daemon off;'
