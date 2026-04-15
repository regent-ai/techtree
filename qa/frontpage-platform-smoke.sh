#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/sean/Documents/regent/techtree"
PHOENIX_URL="${PHOENIX_URL:-http://127.0.0.1:4001}"
OUT_DIR="${ROOT}/qa/artifacts/frontpage-platform"
AB_HOME="${ROOT}/qa/.agent-browser-home"
SESSION="${AGENT_BROWSER_SESSION:-fp-plat-smoke}"

mkdir -p "${OUT_DIR}" "${AB_HOME}"

ab() {
  HOME="${AB_HOME}" AGENT_BROWSER_SESSION="${SESSION}" agent-browser "$@"
}

cleanup() {
  ab close >/dev/null 2>&1 || true
}

wait_for_ready() {
  local attempts="${1:-45}"
  local i

  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS "${PHOENIX_URL}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "app did not become ready at ${PHOENIX_URL}" >&2
  return 1
}

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! rg -Fq "${expected}" "${file}"; then
    echo "missing expected text: ${expected}" >&2
    echo "file: ${file}" >&2
    return 1
  fi
}

trap cleanup EXIT

wait_for_ready

ab open "${PHOENIX_URL}/"
ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
ab get text body > "${OUT_DIR}/frontpage-body.txt"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Start with the guided setup. Let the live tree open below."
assert_contains "${OUT_DIR}/frontpage-body.txt" "Start TechTree from your terminal"
assert_contains "${OUT_DIR}/frontpage-body.txt" "pnpm add -g @regentlabs/cli"
assert_contains "${OUT_DIR}/frontpage-body.txt" "regent techtree start"
assert_contains "${OUT_DIR}/frontpage-body.txt" "regent techtree bbh run solve ./run --agent openclaw"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Connect Privy"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Sign in before you post in the public room."
assert_contains "${OUT_DIR}/frontpage-body.txt" "BBH branch"

ab click "#frontpage-install-agent-hermes"
ab wait 250 >/dev/null 2>&1 || true
ab get text "#frontpage-install-command" > "${OUT_DIR}/frontpage-hermes-command.txt"
assert_contains "${OUT_DIR}/frontpage-hermes-command.txt" "regent techtree bbh run solve ./run --agent hermes"

ab click "#frontpage-chat-tab-agent"
ab wait 250 >/dev/null 2>&1 || true
ab get text "#frontpage-agent-chatbox" > "${OUT_DIR}/frontpage-agent-chat.txt"
assert_contains "${OUT_DIR}/frontpage-agent-chat.txt" "Read only"

ab click "#frontpage-view-grid"
ab wait 350 >/dev/null 2>&1 || true
ab get text "#frontpage-tree-path" > "${OUT_DIR}/frontpage-grid-briefing.txt"
assert_contains "${OUT_DIR}/frontpage-grid-briefing.txt" "cube field"

ab open "${PHOENIX_URL}/platform"
ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
ab get text body > "${OUT_DIR}/platform-home-body.txt"
assert_contains "${OUT_DIR}/platform-home-body.txt" "Regent Platform"
assert_contains "${OUT_DIR}/platform-home-body.txt" "One shell, many surfaces"
assert_contains "${OUT_DIR}/platform-home-body.txt" "Privy Login"

ab open "${PHOENIX_URL}/platform/explorer"
ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
ab get text body > "${OUT_DIR}/platform-explorer-body.txt"
assert_contains "${OUT_DIR}/platform-explorer-body.txt" "Explorer"
assert_contains "${OUT_DIR}/platform-explorer-body.txt" "World Map"
assert_contains "${OUT_DIR}/platform-explorer-body.txt" "Privy Login"

ab open "${PHOENIX_URL}/platform/creator"
ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
ab get text body > "${OUT_DIR}/platform-creator-body.txt"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Creator"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Choose a launch candidate"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Privy Login"

echo "frontpage/platform smoke passed"
