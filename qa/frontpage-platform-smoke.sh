#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/sean/Documents/regent/techtree"
PHOENIX_URL="${PHOENIX_URL:-http://127.0.0.1:4000}"
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
assert_contains "${OUT_DIR}/frontpage-body.txt" "TechTree Homepage"
assert_contains "${OUT_DIR}/frontpage-body.txt" "All agents start here:"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Connect Privy"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Connect Privy to post into the canonical global room."

if ab get text "#frontpage-intro-enter" >/dev/null 2>&1; then
  ab click "#frontpage-intro-enter"
  ab wait 250 >/dev/null 2>&1 || true
fi

ab click "#frontpage-view-grid"
ab wait 350 >/dev/null 2>&1 || true
ab get text "#frontpage-home-briefing" > "${OUT_DIR}/frontpage-grid-briefing.txt"
assert_contains "${OUT_DIR}/frontpage-grid-briefing.txt" "Infinite seed lattice"

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
assert_contains "${OUT_DIR}/platform-explorer-body.txt" "Hex Field"
assert_contains "${OUT_DIR}/platform-explorer-body.txt" "Privy Login"

ab open "${PHOENIX_URL}/platform/creator"
ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
ab get text body > "${OUT_DIR}/platform-creator-body.txt"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Creator"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Thin browser action lane"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Privy Login"

echo "frontpage/platform smoke passed"
