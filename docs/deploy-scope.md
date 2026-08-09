# Deploy Scope

Production deploys are being prepared for scope-aware execution. The first
phase is advisory only: the detector reports which path a change should take,
while the existing full-image deploy remains the safe behavior.

Modes:

- `full_image`: rebuild the Frappe image and run the existing apply flow.
- `ecommerce_fast`: update the custom app, run required migrate/build steps,
  and restart without rebuilding vendor layers.
- `edge_nginx`: deploy and reload the outer nginx config only.
- `compose_required`: update compose/env files and recreate affected services.
- `runner_required`: update runner service configuration.
- `docs_only`: no production runtime deploy should be needed.

Rules live in `deploy-rules.json`. Unknown files intentionally force
`full_image` until they are classified.
