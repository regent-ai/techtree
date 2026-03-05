#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="/Users/sean/.fly/bin:$PATH"

if ! command -v flyctl >/dev/null 2>&1; then
  echo "flyctl not found. Install with: curl -L https://fly.io/install.sh | sh"
  exit 1
fi

if ! flyctl auth whoami >/dev/null 2>&1; then
  echo "Fly auth missing. Run: flyctl auth login"
  exit 1
fi

APP_NAME="${FLY_APP_NAME:-techtree-regent}"
DB_NAME="${FLY_MPG_NAME:-${APP_NAME}-db}"
REGION="${FLY_REGION:-iad}"
PLAN="${FLY_MPG_PLAN:-development}"
ORG="${FLY_ORG:-}"

apps_org_args=()
mpg_org_args=()
if [[ -n "$ORG" ]]; then
  apps_org_args=(--org "$ORG")
  mpg_org_args=(--org "$ORG")
fi

if ! flyctl status --app "$APP_NAME" >/dev/null 2>&1; then
  echo "Creating Fly app: $APP_NAME"
  flyctl apps create "$APP_NAME" --yes "${apps_org_args[@]}"
fi

if ! flyctl mpg status "$DB_NAME" >/dev/null 2>&1; then
  echo "Creating Managed Postgres cluster: $DB_NAME"
  flyctl mpg create -n "$DB_NAME" --plan "$PLAN" --region "$REGION" "${mpg_org_args[@]}"
fi

echo "Attaching managed Postgres cluster to app"
attach_output=""
if ! attach_output="$(flyctl mpg attach "$DB_NAME" --app "$APP_NAME" 2>&1)"; then
  if echo "$attach_output" | grep -Eiq "already attached|already exists|already has"; then
    echo "Managed Postgres already attached to $APP_NAME, continuing."
  else
    echo "$attach_output"
    exit 1
  fi
fi

if [[ -z "${SECRET_KEY_BASE:-}" ]]; then
  echo "SECRET_KEY_BASE is not set in environment. Generating one for this deploy."
  SECRET_KEY_BASE="$(mix phx.gen.secret)"
fi

flyctl secrets set \
  --app "$APP_NAME" \
  PHX_SERVER=true \
  PHX_HOST="${APP_NAME}.fly.dev" \
  SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  PORT=8080 \
  DRAGONFLY_ENABLED=false

echo "Deploying app: $APP_NAME"
flyctl deploy --app "$APP_NAME" --config fly.toml --remote-only --yes

echo "Deployment complete: https://${APP_NAME}.fly.dev"
