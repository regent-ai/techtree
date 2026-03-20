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
  [[ -f "${ROOT_DIR}/.env" ]] || fail "missing .env; copy .env.full.example to .env first"

  set -a
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/.env"
  set +a
}

resolve_chain_rpc_url() {
  case "${TECHTREE_CHAIN_ID}" in
    11155111)
      printf '%s\n' "${ETHEREUM_SEPOLIA_RPC_URL:-${ANVIL_RPC_URL:-}}"
      ;;
    31337)
      printf '%s\n' "${ANVIL_RPC_URL:-}"
      ;;
    *)
      printf '%s\n' "${ETHEREUM_MAINNET_RPC_URL:-${ETHEREUM_RPC_URL:-}}"
      ;;
  esac
}

dragonfly_ping() {
  local response

  exec 3<>/dev/tcp/127.0.0.1/6379 || return 1
  printf '*1\r\n$4\r\nPING\r\n' >&3
  IFS= read -r -t 2 response <&3 || true
  exec 3<&-
  exec 3>&-

  [[ "${response}" == "+PONG" ]]
}

assert_http_ok() {
  local name="$1"
  local url="$2"
  local response

  response="$(curl -fsS "${url}")"
  [[ "${response}" == *'"ok":true'* ]] || fail "${name} did not return ok=true"
}

check_compose_service() {
  local service="$1"
  local running

  running="$(docker compose -f "${COMPOSE_FILE}" ps --services --status running)"
  printf '%s\n' "${running}" | grep -qx "${service}" || {
    fail "docker compose service ${service} is not running"
  }
}

check_siwa_nonce() {
  local response
  local port="${PORT:-4000}"

  response="$(
    curl -fsS \
      -X POST \
      "http://127.0.0.1:${port}/v1/agent/siwa/nonce" \
      -H 'content-type: application/json' \
      -d "{\"walletAddress\":\"0x1111111111111111111111111111111111111111\",\"chainId\":${TECHTREE_CHAIN_ID},\"audience\":\"techtree\"}"
  )"

  [[ "${response}" == *'"ok":true'* && "${response}" == *'"code":"nonce_issued"'* ]] || {
    fail "phoenix to SIWA nonce flow did not return nonce_issued"
  }
}

check_chain_contract() {
  local chain_id
  local code
  local rpc_url
  local writer_address
  local writer_balance

  rpc_url="$(resolve_chain_rpc_url)"
  [[ -n "${rpc_url}" ]] || fail "missing chain-specific Ethereum RPC URL for TECHTREE_CHAIN_ID=${TECHTREE_CHAIN_ID}"

  chain_id="$("${CAST_BIN:-cast}" chain-id --rpc-url "${rpc_url}")"
  [[ "${chain_id}" == "${TECHTREE_CHAIN_ID}" ]] || {
    fail "configured TECHTREE_CHAIN_ID=${TECHTREE_CHAIN_ID} but RPC resolved ${chain_id}"
  }

  code="$("${CAST_BIN:-cast}" code "${REGISTRY_CONTRACT_ADDRESS}" --rpc-url "${rpc_url}")"
  [[ -n "${code}" && "${code}" != "0x" ]] || {
    fail "no contract code found at REGISTRY_CONTRACT_ADDRESS=${REGISTRY_CONTRACT_ADDRESS}"
  }

  writer_address="$("${CAST_BIN:-cast}" wallet address --private-key "${REGISTRY_WRITER_PRIVATE_KEY}")"
  writer_balance="$("${CAST_BIN:-cast}" balance "${writer_address}" --wei --rpc-url "${rpc_url}")"

  [[ "${writer_balance}" =~ ^[0-9]+$ ]] || {
    fail "could not read writer balance for ${writer_address}"
  }

  (( writer_balance > 0 )) || {
    fail "writer wallet ${writer_address} has zero balance on the configured RPC"
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
[[ "${TECHTREE_CHAIN_ID}" =~ ^[0-9]+$ ]] || fail "TECHTREE_CHAIN_ID must be a positive integer"

log "checking docker compose infra"
check_compose_service postgres
check_compose_service dragonfly

log "checking postgres"
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  pg_isready -U postgres -d tech_tree_dev >/dev/null 2>&1 || {
  fail "postgres is not ready"
}

log "checking dragonfly"
dragonfly_ping || fail "dragonfly did not answer PING on localhost:6379"

log "checking phoenix health"
assert_http_ok "phoenix /health" "http://127.0.0.1:${PORT:-4000}/health"

log "checking SIWA health"
assert_http_ok "siwa /health" "http://127.0.0.1:${SIWA_PORT:-4100}/health"

log "checking phoenix to SIWA nonce flow"
check_siwa_nonce

log "checking Ethereum RPC and registry contract"
check_chain_contract

log "checking Lighthouse upload"
check_lighthouse_upload

log "checking Privy config presence"
[[ -n "${PRIVY_APP_ID:-}" && -n "${PRIVY_VERIFICATION_KEY:-}" ]] || {
  fail "Privy config is missing from .env"
}

printf 'Full local parity smoke passed.\n'
