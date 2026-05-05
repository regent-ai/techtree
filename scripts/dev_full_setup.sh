#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.full.yml"

log() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

source_env() {
  [[ -f "${ROOT_DIR}/.env.local" ]] || {
    cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env.local"
    fail "created .env.local from .env.example; fill the required secrets, run direnv allow, and rerun"
  }

  set -a
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/.env.local"
  set +a
}

require_env() {
  local key="$1"
  local value="${!key:-}"

  if [[ -z "${value}" ]]; then
    fail "missing required env: ${key}"
  fi

  case "${value}" in
    replace_with_*|your_*|*base64_key_material*)
      fail "replace the placeholder value for ${key} in .env.local"
      ;;
  esac
}

resolve_chain_rpc_url() {
  case "${TECHTREE_CHAIN_ID}" in
    84532)
      printf '%s\n' "${BASE_SEPOLIA_RPC_URL:-${ANVIL_RPC_URL:-}}"
      ;;
    31337)
      printf '%s\n' "${ANVIL_RPC_URL:-}"
      ;;
    *)
      printf '%s\n' "${BASE_MAINNET_RPC_URL:-${BASE_RPC_URL:-}}"
      ;;
  esac
}

autoskill_env_names() {
  case "${TECHTREE_CHAIN_ID}" in
    84532)
      printf '%s %s %s\n' \
        AUTOSKILL_BASE_SEPOLIA_SETTLEMENT_CONTRACT \
        AUTOSKILL_BASE_SEPOLIA_USDC_TOKEN \
        AUTOSKILL_BASE_SEPOLIA_TREASURY_ADDRESS
      ;;
    8453)
      printf '%s %s %s\n' \
        AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT \
        AUTOSKILL_BASE_MAINNET_USDC_TOKEN \
        AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS
      ;;
    *)
      fail "paid settlement checks require TECHTREE_CHAIN_ID=8453 or 84532"
      ;;
  esac
}

require_autoskill_env() {
  local settlement_var
  local usdc_var
  local treasury_var

  read -r settlement_var usdc_var treasury_var < <(autoskill_env_names)
  require_env "${settlement_var}"
  require_env "${usdc_var}"
  require_env "${treasury_var}"
}

wait_for_postgres() {
  local attempt

  for attempt in $(seq 1 30); do
    if docker compose -f "${COMPOSE_FILE}" exec -T postgres \
      pg_isready -U postgres -d tech_tree_dev >/dev/null 2>&1; then
      return 0
    fi

    sleep 2
  done

  fail "postgres did not become ready in docker compose"
}

check_chain_contract() {
  local chain_id
  local code
  local rpc_url
  local settlement_code
  local settlement_contract
  local settlement_var
  local usdc_code
  local usdc_token
  local usdc_var
  local writer_authorized
  local writer_address
  local writer_balance

  rpc_url="$(resolve_chain_rpc_url)"
  [[ -n "${rpc_url}" ]] || fail "missing chain-specific RPC URL for TECHTREE_CHAIN_ID=${TECHTREE_CHAIN_ID}"

  chain_id="$("${CAST_BIN:-cast}" chain-id --rpc-url "${rpc_url}")"
  [[ "${chain_id}" == "${TECHTREE_CHAIN_ID}" ]] || {
    fail "configured TECHTREE_CHAIN_ID=${TECHTREE_CHAIN_ID} but RPC resolved ${chain_id}"
  }

  code="$("${CAST_BIN:-cast}" code "${REGISTRY_CONTRACT_ADDRESS}" --rpc-url "${rpc_url}")"
  [[ -n "${code}" && "${code}" != "0x" ]] || {
    fail "no contract code found at REGISTRY_CONTRACT_ADDRESS=${REGISTRY_CONTRACT_ADDRESS}"
  }

  read -r settlement_var usdc_var _treasury_var < <(autoskill_env_names)
  settlement_contract="${!settlement_var:-}"
  usdc_token="${!usdc_var:-}"

  settlement_code="$("${CAST_BIN:-cast}" code "${settlement_contract}" --rpc-url "${rpc_url}")"
  [[ -n "${settlement_code}" && "${settlement_code}" != "0x" ]] || {
    fail "no contract code found at ${settlement_var}=${settlement_contract}"
  }

  usdc_code="$("${CAST_BIN:-cast}" code "${usdc_token}" --rpc-url "${rpc_url}")"
  [[ -n "${usdc_code}" && "${usdc_code}" != "0x" ]] || {
    fail "no token code found at ${usdc_var}=${usdc_token}"
  }

  writer_address="$("${CAST_BIN:-cast}" wallet address --private-key "${REGISTRY_WRITER_PRIVATE_KEY}")"
  writer_balance="$("${CAST_BIN:-cast}" balance "${writer_address}" --wei --rpc-url "${rpc_url}")"

  [[ "${writer_balance}" =~ ^[0-9]+$ ]] || {
    fail "could not read writer balance for ${writer_address}"
  }

  (( writer_balance > 0 )) || {
    fail "writer wallet ${writer_address} has zero balance on the configured RPC"
  }

  writer_authorized="$(
    "${CAST_BIN:-cast}" call \
      "${REGISTRY_CONTRACT_ADDRESS}" \
      "publishers(address)(bool)" \
      "${writer_address}" \
      --rpc-url "${rpc_url}"
  )"

  [[ "${writer_authorized}" == "true" ]] || {
    fail "registry writer ${writer_address} is not authorized on REGISTRY_CONTRACT_ADDRESS=${REGISTRY_CONTRACT_ADDRESS}"
  }
}

cd "${ROOT_DIR}"

require_command docker
require_command mix
require_command bun
require_command curl
docker compose version >/dev/null 2>&1 || fail "docker compose is required"

source_env
require_command "${CAST_BIN:-cast}"

require_env SECRET_KEY_BASE
require_env INTERNAL_SHARED_SECRET
require_env PRIVY_APP_ID
require_env PRIVY_VERIFICATION_KEY
require_env SIWA_SHARED_SECRET
require_env SIWA_RECEIPT_SECRET
require_env LIGHTHOUSE_API_KEY
require_env TECHTREE_CHAIN_ID
require_env REGISTRY_CONTRACT_ADDRESS
require_env REGISTRY_WRITER_PRIVATE_KEY
[[ "${TECHTREE_CHAIN_ID}" =~ ^[0-9]+$ ]] || fail "TECHTREE_CHAIN_ID must be a positive integer"
require_autoskill_env

[[ "${SIWA_SHARED_SECRET}" == "${SIWA_HMAC_SECRET:-}" ]] || {
  fail "SIWA_SHARED_SECRET and SIWA_HMAC_SECRET must match in .env.local"
}

log "starting local infra"
docker compose -f "${COMPOSE_FILE}" up -d postgres

log "waiting for postgres"
wait_for_postgres

log "checking chain RPC and registry contract"
check_chain_contract

log "running mix setup"
mix setup

log "running services typecheck"
(
  cd services
  bun run typecheck
)

cat <<'EOF'

Full local parity setup is ready.

Start the full local stack with:
  ./scripts/dev_full_start.sh

Then verify the stack with:
  bash scripts/smoke_full_local.sh
EOF
