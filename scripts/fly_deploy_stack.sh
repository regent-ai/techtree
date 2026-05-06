#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
BUILD_CONTEXT_DIR="$ROOT_DIR/.fly-build"
cd "$ROOT_DIR"

export PATH="${HOME}/.fly/bin:${PATH}"

if ! command -v flyctl >/dev/null 2>&1; then
  echo "flyctl not found. Install with: curl -L https://fly.io/install.sh | sh"
  exit 1
fi

if ! flyctl auth whoami >/dev/null 2>&1; then
  echo "Fly auth missing. Run: flyctl auth login"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate deploy secrets"
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required to stage Phoenix build dependencies"
  exit 1
fi

CAST_BIN="${CAST_BIN:-cast}"

if ! command -v "$CAST_BIN" >/dev/null 2>&1; then
  echo "${CAST_BIN} is required to verify Base mainnet contracts before deploy"
  exit 1
fi

require_env() {
  local name="$1"

  if [[ -z "${!name:-}" ]]; then
    echo "missing required environment variable: ${name}"
    exit 1
  fi
}

STACK_PREFIX="${FLY_STACK_PREFIX:-techtree}"
PHOENIX_APP="${FLY_PHOENIX_APP:-$STACK_PREFIX}"
DB_NAME="${FLY_MPG_NAME:-${STACK_PREFIX}-db}"
REGION="${FLY_REGION:-sjc}"
PLAN="${FLY_MPG_PLAN:-development}"
ORG="${FLY_ORG:-regent}"

PHOENIX_HOST="${FLY_PHOENIX_HOST:-${PHOENIX_APP}.fly.dev}"
SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(mix phx.gen.secret)}"
INTERNAL_SHARED_SECRET="${INTERNAL_SHARED_SECRET:-$(openssl rand -hex 32)}"
SIWA_PORT="${SIWA_PORT:-4100}"
SIWA_SERVER_APP="${FLY_SIWA_SERVER_APP:-siwa-server}"
SIWA_INTERNAL_URL="${SIWA_INTERNAL_URL:-http://${SIWA_SERVER_APP}.flycast:${SIWA_PORT}}"
TECHTREE_CHAIN_ID="${TECHTREE_CHAIN_ID:-8453}"
TECHTREE_P2P_ENABLED="${TECHTREE_P2P_ENABLED:-false}"
TECHTREE_HOME_UNICORN_HERO_ENABLED="${TECHTREE_HOME_UNICORN_HERO_ENABLED:-false}"
PROMEX_METRICS_ENABLED="${PROMEX_METRICS_ENABLED:-false}"

if [[ "$TECHTREE_CHAIN_ID" != "8453" ]]; then
  echo "public beta deploy is Base mainnet only; set TECHTREE_CHAIN_ID=8453"
  exit 1
fi

if [[ "$TECHTREE_P2P_ENABLED" != "false" ]]; then
  echo "first prod deploy is local-only transport; set TECHTREE_P2P_ENABLED=false"
  exit 1
fi

apps_org_args=()
mpg_org_args=()
if [[ -n "$ORG" ]]; then
  apps_org_args=(--org "$ORG")
  mpg_org_args=(--org "$ORG")
fi

ensure_app() {
  local app_name="$1"

  if ! flyctl status --app "$app_name" >/dev/null 2>&1; then
    echo "Creating Fly app: $app_name"
    flyctl apps create "$app_name" --yes "${apps_org_args[@]}"
  fi
}

ensure_postgres() {
  if ! flyctl mpg status "$DB_NAME" >/dev/null 2>&1; then
    echo "Creating Managed Postgres cluster: $DB_NAME"
    flyctl mpg create -n "$DB_NAME" --plan "$PLAN" --region "$REGION" "${mpg_org_args[@]}"
  fi
}

stage_build_dependency() {
  local source_dir="$1"
  local target_dir="$2"
  local label="$3"

  if [[ ! -d "$source_dir" ]]; then
    echo "missing required ${label} checkout: ${source_dir}"
    exit 1
  fi

  mkdir -p "$target_dir"
  rsync -a --delete \
    --exclude .git \
    --exclude _build \
    --exclude deps \
    --exclude node_modules \
    "$source_dir"/ "$target_dir"/
}

prepare_phoenix_build_context() {
  echo "Staging Phoenix build dependencies"
  stage_build_dependency "$WORKSPACE_DIR/elixir-utils" "$BUILD_CONTEXT_DIR/elixir-utils" "elixir-utils"
  stage_build_dependency "$WORKSPACE_DIR/design-system" "$BUILD_CONTEXT_DIR/design-system" "design-system"
}

attach_postgres() {
  local attach_output

  echo "Attaching managed Postgres cluster to $PHOENIX_APP"
  if ! attach_output="$(flyctl mpg attach "$DB_NAME" --app "$PHOENIX_APP" 2>&1)"; then
    if echo "$attach_output" | grep -Eiq "already attached|already exists|already has"; then
      echo "Managed Postgres already attached to $PHOENIX_APP, continuing."
    else
      echo "$attach_output"
      exit 1
    fi
  fi
}

require_prod_env() {
  require_env DATABASE_DIRECT_URL
  require_env SIWA_INTERNAL_URL
  require_env PRIVY_APP_ID
  require_env PRIVY_VERIFICATION_KEY
  require_env LIGHTHOUSE_API_KEY
  require_env BASE_MAINNET_RPC_URL
  require_env REGISTRY_CONTRACT_ADDRESS
  require_env REGISTRY_WRITER_PRIVATE_KEY
  require_env AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT
  require_env AUTOSKILL_BASE_MAINNET_USDC_TOKEN
  require_env AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS
}

verify_mainnet_contracts() {
  local chain_id
  local registry_code
  local settlement_code
  local usdc_code
  local writer_address
  local writer_authorized
  local writer_balance

  chain_id="$("$CAST_BIN" chain-id --rpc-url "$BASE_MAINNET_RPC_URL")"
  if [[ "$chain_id" != "8453" ]]; then
    echo "BASE_MAINNET_RPC_URL resolved chain ${chain_id}; expected 8453"
    exit 1
  fi

  registry_code="$("$CAST_BIN" code "$REGISTRY_CONTRACT_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL")"
  if [[ -z "$registry_code" || "$registry_code" == "0x" ]]; then
    echo "no contract code found at REGISTRY_CONTRACT_ADDRESS=${REGISTRY_CONTRACT_ADDRESS}"
    exit 1
  fi

  settlement_code="$("$CAST_BIN" code "$AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT" --rpc-url "$BASE_MAINNET_RPC_URL")"
  if [[ -z "$settlement_code" || "$settlement_code" == "0x" ]]; then
    echo "no contract code found at AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT=${AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT}"
    exit 1
  fi

  usdc_code="$("$CAST_BIN" code "$AUTOSKILL_BASE_MAINNET_USDC_TOKEN" --rpc-url "$BASE_MAINNET_RPC_URL")"
  if [[ -z "$usdc_code" || "$usdc_code" == "0x" ]]; then
    echo "no token code found at AUTOSKILL_BASE_MAINNET_USDC_TOKEN=${AUTOSKILL_BASE_MAINNET_USDC_TOKEN}"
    exit 1
  fi

  writer_address="$("$CAST_BIN" wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY")"
  writer_balance="$("$CAST_BIN" balance "$writer_address" --wei --rpc-url "$BASE_MAINNET_RPC_URL")"
  if ! [[ "$writer_balance" =~ ^[0-9]+$ ]] || (( writer_balance <= 0 )); then
    echo "registry writer ${writer_address} needs Base ETH for gas"
    exit 1
  fi

  writer_authorized="$(
    "$CAST_BIN" call \
      "$REGISTRY_CONTRACT_ADDRESS" \
      "publishers(address)(bool)" \
      "$writer_address" \
      --rpc-url "$BASE_MAINNET_RPC_URL"
  )"
  if [[ "$writer_authorized" != "true" ]]; then
    echo "registry writer ${writer_address} is not authorized on ${REGISTRY_CONTRACT_ADDRESS}"
    exit 1
  fi
}

set_phoenix_secrets() {
  flyctl secrets set \
    --app "$PHOENIX_APP" \
    PHX_SERVER=true \
    PHX_HOST="$PHOENIX_HOST" \
    SECRET_KEY_BASE="$SECRET_KEY_BASE" \
    DATABASE_DIRECT_URL="$DATABASE_DIRECT_URL" \
    PORT=8080 \
    INTERNAL_SHARED_SECRET="$INTERNAL_SHARED_SECRET" \
    SIWA_INTERNAL_URL="$SIWA_INTERNAL_URL" \
    PRIVY_APP_ID="$PRIVY_APP_ID" \
    PRIVY_VERIFICATION_KEY="$PRIVY_VERIFICATION_KEY" \
    LIGHTHOUSE_API_KEY="$LIGHTHOUSE_API_KEY" \
    TECHTREE_ETHEREUM_MODE=rpc \
    TECHTREE_CHAIN_ID="$TECHTREE_CHAIN_ID" \
    TECHTREE_P2P_ENABLED="$TECHTREE_P2P_ENABLED" \
    TECHTREE_HOME_UNICORN_HERO_ENABLED="$TECHTREE_HOME_UNICORN_HERO_ENABLED" \
    PROMEX_METRICS_ENABLED="$PROMEX_METRICS_ENABLED" \
    BASE_MAINNET_RPC_URL="$BASE_MAINNET_RPC_URL" \
    REGISTRY_CONTRACT_ADDRESS="$REGISTRY_CONTRACT_ADDRESS" \
    REGISTRY_WRITER_PRIVATE_KEY="$REGISTRY_WRITER_PRIVATE_KEY" \
    AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT="$AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT" \
    AUTOSKILL_BASE_MAINNET_USDC_TOKEN="$AUTOSKILL_BASE_MAINNET_USDC_TOKEN" \
    AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS="$AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS"
}

deploy_app() {
  local app_name="$1"
  local config_path="$2"

  echo "Deploying $app_name with $config_path"
  flyctl deploy --app "$app_name" --config "$config_path" --remote-only --yes
}

ensure_app "$PHOENIX_APP"

ensure_postgres
attach_postgres
require_prod_env
verify_mainnet_contracts

set_phoenix_secrets

prepare_phoenix_build_context
deploy_app "$PHOENIX_APP" "fly.phoenix.toml"

echo
echo "Fly stack deployed."
echo "Phoenix:   https://${PHOENIX_HOST}"
echo "Shared SIWA: ${SIWA_INTERNAL_URL}"
