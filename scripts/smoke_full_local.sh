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

source_env() {
  [[ -f "${ROOT_DIR}/.env.local" ]] || fail "missing .env.local; copy .env.example to .env.local first"

  set -a
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/.env.local"
  set +a
}

require_env() {
  local key="$1"
  local value="${!key:-}"

  [[ -n "${value}" ]] || fail "missing required env: ${key}"
}

resolve_chain_rpc_url() {
  case "${TECHTREE_CHAIN_ID}" in
    31337)
      printf '%s\n' "${ANVIL_RPC_URL:-}"
      ;;
    8453)
      printf '%s\n' "${BASE_MAINNET_RPC_URL:-${BASE_RPC_URL:-}}"
      ;;
    *)
      fail "TECHTREE_CHAIN_ID must be 8453 for Techtree mainnet smoke"
      ;;
  esac
}

autoskill_env_names() {
  case "${TECHTREE_CHAIN_ID}" in
    8453)
      printf '%s %s %s\n' \
        AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT \
        AUTOSKILL_BASE_MAINNET_USDC_TOKEN \
        AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS
      ;;
    *)
      fail "paid settlement checks require TECHTREE_CHAIN_ID=8453"
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

assert_http_ok() {
  local name="$1"
  local url="$2"
  local response

  response="$(curl -fsS "${url}")"
  [[ "${response}" == *'"ok":true'* ]] || fail "${name} did not return ok=true"
}

assert_http_text() {
  local name="$1"
  local url="$2"
  local expected="$3"
  local response

  response="$(curl -fsS "${url}")"
  [[ "${response}" == "${expected}" ]] || fail "${name} did not return ${expected}"
}

check_compose_service() {
  local service="$1"
  local running

  running="$(docker compose -f "${COMPOSE_FILE}" ps --services --status running)"
  printf '%s\n' "${running}" | grep -qx "${service}" || {
    fail "docker compose service ${service} is not running"
  }
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

check_lighthouse_upload() {
  local temp_file
  local response
  local storage_type="${LIGHTHOUSE_STORAGE_TYPE:-annual}"

  temp_file="$(mktemp "${TMPDIR:-/tmp}/techtree-lighthouse-smoke.XXXXXX.txt")"
  LIGHTHOUSE_SMOKE_TEMP_FILE="${temp_file}"
  trap 'rm -f "${LIGHTHOUSE_SMOKE_TEMP_FILE:-}"' EXIT

  printf 'techtree smoke %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${temp_file}"

  response="$(
    curl -fsS \
      -X POST \
      "${LIGHTHOUSE_BASE_URL%/}/api/v0/add" \
      -H "authorization: Bearer ${LIGHTHOUSE_API_KEY}" \
      -H "x-storage-type: ${storage_type}" \
      -F "file=@${temp_file};type=text/plain"
  )"

  [[ "${response}" == *'"Hash"'* || "${response}" == *'"hash"'* ]] || {
    fail "lighthouse upload smoke did not return a CID"
  }
}

cd "${ROOT_DIR}"

command -v docker >/dev/null 2>&1 || fail "missing required command: docker"
command -v curl >/dev/null 2>&1 || fail "missing required command: curl"
docker compose version >/dev/null 2>&1 || fail "docker compose is required"

source_env
command -v "${CAST_BIN:-cast}" >/dev/null 2>&1 || {
  fail "missing required command: ${CAST_BIN:-cast}"
}
require_env TECHTREE_CHAIN_ID
require_env SIWA_INTERNAL_URL
require_env REGISTRY_CONTRACT_ADDRESS
require_env REGISTRY_WRITER_PRIVATE_KEY
[[ "${TECHTREE_CHAIN_ID}" =~ ^[0-9]+$ ]] || fail "TECHTREE_CHAIN_ID must be a positive integer"
require_autoskill_env

log "checking docker compose infra"
check_compose_service postgres

log "checking postgres"
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  pg_isready -U postgres -d tech_tree_dev >/dev/null 2>&1 || {
  fail "postgres is not ready"
}

log "checking phoenix health"
assert_http_ok "phoenix /health" "http://127.0.0.1:${PORT:-4001}/health"

log "checking SIWA health"
assert_http_text "shared siwa /healthz" "${SIWA_INTERNAL_URL%/}/healthz" "ok"

log "checking chain RPC and registry contract"
check_chain_contract

log "checking Lighthouse upload"
check_lighthouse_upload

log "checking Privy config presence"
[[ -n "${PRIVY_APP_ID:-}" && -n "${PRIVY_VERIFICATION_KEY:-}" ]] || {
  fail "Privy config is missing from .env.local"
}

printf 'Full local parity smoke passed.\n'
