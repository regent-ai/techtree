#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.full.yml"
PIDS=()

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

cleanup() {
  local status="${1:-0}"
  trap - EXIT INT TERM

  if ((${#PIDS[@]} > 0)); then
    log "stopping local app processes"

    for pid in "${PIDS[@]}"; do
      if kill -0 "${pid}" >/dev/null 2>&1; then
        kill "${pid}" >/dev/null 2>&1 || true
      fi
    done

    wait "${PIDS[@]}" >/dev/null 2>&1 || true
  fi

  exit "${status}"
}

start_processes() {
  log "starting Phoenix"
  (
    cd "${ROOT_DIR}"
    set -a
    # shellcheck source=/dev/null
    source "${ROOT_DIR}/.env.local"
    set +a
    exec mix phx.server
  ) &
  PIDS+=("$!")

  log "starting SIWA sidecar"
  (
    cd "${ROOT_DIR}/services"
    set -a
    # shellcheck source=/dev/null
    source "${ROOT_DIR}/.env.local"
    set +a
    exec bun run dev:siwa
  ) &
  PIDS+=("$!")
}

watch_processes() {
  local pid
  local status

  while true; do
    for pid in "${PIDS[@]}"; do
      if ! kill -0 "${pid}" >/dev/null 2>&1; then
        if wait "${pid}"; then
          status=0
        else
          status=$?
        fi

        fail "process ${pid} exited with status ${status}"
      fi
    done

    sleep 1
  done
}

cd "${ROOT_DIR}"

command -v docker >/dev/null 2>&1 || fail "missing required command: docker"
command -v mix >/dev/null 2>&1 || fail "missing required command: mix"
command -v bun >/dev/null 2>&1 || fail "missing required command: bun"
docker compose version >/dev/null 2>&1 || fail "docker compose is required"

source_env

log "starting local infra"
docker compose -f "${COMPOSE_FILE}" up -d postgres

log "waiting for postgres"
wait_for_postgres

trap 'cleanup $?' EXIT INT TERM

start_processes
watch_processes
