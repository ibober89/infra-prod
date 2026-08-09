# Ecommerce Fast Deploy Notes

Date: 2026-08-10

## Goal

Make ecommerce production deploys smarter so small app changes do not rebuild the full Frappe image every time.

## Current Design

Deploy scope is detected by:

- `/opt/velveta/infra-prod/scripts/detect-deploy-scope.py`
- `/opt/velveta/infra-prod/deploy-rules.json`

For ecommerce:

- `pyproject.toml` or `requirements*.txt` => `full_image`
- `ecommerce/overrides/**` => `full_image` because it can affect other apps/core behavior
- DocTypes, patches, fixtures => migrate required
- public/templates/www assets => asset build required
- normal ecommerce code/version/docs => restart required
- workflow files => runner update, not full image

## What Changed

Infra:

- `infra-prod` commit `6d7dfaa`
- Ecommerce workflow changes are classified as `runner_required`, not `full_image`.

Ecommerce:

- `0.0.225`: prod workflow started using deploy scope as a decision-maker.
- `0.0.226`: fast deploy changed from `git reset` inside containers to copying checked-out source into containers, because prod image does not include `.git` in `apps/ecommerce`.
- `0.0.227`: fast deploy now runs `./env/bin/python -m pip install -e apps/ecommerce` after copying source, because Frappe app version/About can depend on Python package metadata, not only the source file.
- `0.0.228`: ecommerce source is synced once to `/opt/velveta/prod/apps/ecommerce` and mounted into Frappe containers, instead of being copied separately into every running container.

## Observed Problems

1. Source copy alone updated `/home/frappe/frappe-bench/apps/ecommerce/ecommerce/__init__.py`, but About did not update immediately.

Reason:

- Source file showed `0.0.226`.
- `frappe.utils.change_log.get_versions()` needed package/runtime metadata refresh.
- `pip install -e apps/ecommerce` fixed the metadata path.

2. `git fetch/reset` inside prod containers failed as a deploy method.

Reason:

- Prod image has app source copied in.
- `/home/frappe/frappe-bench/apps/ecommerce` is not a git repository inside the container.

3. `bench list-apps` can be misleading during this flow.

Observed:

- `pip show ecommerce` and `frappe.utils.change_log.get_versions()` showed the updated version.
- `bench list-apps` still showed an older `UNVERSIONED` value in one check.

For UI/About, prefer checking:

```bash
bench --site erp.velvetacare.com execute frappe.utils.change_log.get_versions
```

## Current Fast Deploy Flow

When detector says ecommerce source is relevant:

1. Sync checked-out ecommerce source once to `/opt/velveta/prod/apps/ecommerce`.
2. Mount that host path into Frappe services at `/home/frappe/frappe-bench/apps/ecommerce`.
3. Refresh editable package metadata in Python containers:
   - `backend`
   - `queue-long`
   - `queue-short`
   - `scheduler`
4. Run migrate only if detector says `migrate=true`.
5. Run asset sync/build only if detector says `asset_build=true`.
6. Restart app services.
7. Restart edge proxy.

The shared app path is seeded from the image during fresh production initialization if it does not already contain ecommerce source.

## Verification Commands

Check detector for a commit range:

```bash
/opt/velveta/infra-prod/scripts/detect-deploy-scope.py \
  --repo ibober89/ecommerce \
  --repo-root /opt/velveta/dev/frappe-bench/apps/ecommerce \
  --base <old_commit> \
  --head <new_commit> \
  --format json
```

Check production source version:

```bash
docker compose -f /opt/velveta/prod/frappe/docker-compose.frappe.yml exec -T backend \
  bash -lc "sed -n '1p' /home/frappe/frappe-bench/apps/ecommerce/ecommerce/__init__.py"
```

Check production package metadata:

```bash
docker compose -f /opt/velveta/prod/frappe/docker-compose.frappe.yml exec -T backend \
  bash -lc "cd /home/frappe/frappe-bench; ./env/bin/python -m pip show ecommerce"
```

Check the version used by About:

```bash
docker compose -f /opt/velveta/prod/frappe/docker-compose.frappe.yml exec -T backend \
  bash -lc "cd /home/frappe/frappe-bench; bench --site erp.velvetacare.com execute frappe.utils.change_log.get_versions"
```

Check if full image rebuild happened:

```bash
docker inspect frappe-backend-1 --format "Created={{.Created}} Image={{.Image}}"
```

If created time did not change, stack was not recreated from a new image.

## Known Weak Points

- The shared host source path becomes the runtime source of truth for ecommerce.
- If the shared host source path is deleted or corrupted, all mounted containers are affected.
- `pip install -e` in multiple containers adds time.
- A full image rebuild still bakes ecommerce into the image, but the host mount overrides that path at runtime.
- Full image is still required for dependency changes, base image changes, and vendor/core-impact patches.

## Better Future Design

Preferred next step:

- Move other custom apps to the same shared-source pattern if they need fast deploys.
- Reduce `pip install -e` repetition, possibly by using a shared virtualenv strategy or a smaller app-layer image.
- Keep full image rebuild only for base dependencies and vendor/core-impact changes.

Alternative:

- Build a small app layer image separate from the base Frappe image.
- Rebuild only the ecommerce app layer for app-only changes.

Do not edit upstream apps directly:

- Frappe
- ERPNext
- payments
- drive
- writer
- blog

Use ecommerce hooks, overrides, patches, or infra patching with explicit reason instead.
