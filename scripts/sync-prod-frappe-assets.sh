#!/usr/bin/env bash
set -euo pipefail

: "${FRAPPE_COMPOSE_FILE:=/opt/velveta/prod/frappe/docker-compose.frappe.yml}"
: "${SITE_NAME:=erp.velvetacare.com}"
: "${FRAPPE_APPS:=frappe erpnext payments ecommerce blog}"
: "${RUN_BENCH_BUILD:=0}"

docker compose -f "${FRAPPE_COMPOSE_FILE}" exec -T backend bash -lc "
  set -euo pipefail
  cd /home/frappe/frappe-bench
  if [ '${RUN_BENCH_BUILD}' = '1' ]; then
    export PATH=/home/frappe/.nvm/versions/node/v24.13.0/bin:\$PATH
    bench build --production
  fi

  cd /home/frappe/frappe-bench/sites/assets
  for app in ${FRAPPE_APPS}; do
    source_dir=\"/home/frappe/frappe-bench/apps/\${app}/\${app}/public\"
    target_dir=\"/home/frappe/frappe-bench/sites/assets/\${app}\"
    tmp_dir=\"/home/frappe/frappe-bench/sites/assets/.\${app}.sync.\$\$\"

    if [ ! -d \"\${source_dir}\" ]; then
      echo \"Skipping missing app public directory: \${source_dir}\"
      continue
    fi

    rm -rf \"\${tmp_dir}\"
    mkdir -p \"\${tmp_dir}\"
    cp -a \"\${source_dir}/.\" \"\${tmp_dir}/\"
    rm -rf \"\${target_dir}\"
    mv \"\${tmp_dir}\" \"\${target_dir}\"
  done

  python - <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path('assets.json')
assets_root = Path('/home/frappe/frappe-bench/sites')

if not manifest_path.exists():
    sys.stderr.write('Missing sites/assets/assets.json\n')
    sys.exit(1)

missing = []
for logical_name, asset_path in json.loads(manifest_path.read_text(encoding='utf-8')).items():
    if isinstance(asset_path, str) and asset_path.startswith('/assets/'):
        candidate = assets_root / asset_path.lstrip('/')
        if not candidate.exists():
            missing.append(f'{logical_name} -> {asset_path}')

if missing:
    sys.stderr.write('Missing production assets referenced by assets.json:\n')
    sys.stderr.write('\n'.join(missing[:50]))
    sys.stderr.write('\n')
    sys.exit(1)
PY

  bench --site ${SITE_NAME} clear-cache
  bench --site ${SITE_NAME} clear-website-cache
"

docker compose -f "${FRAPPE_COMPOSE_FILE}" restart backend frontend websocket queue-short queue-long scheduler
