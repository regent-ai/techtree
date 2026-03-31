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
assert_contains "${OUT_DIR}/frontpage-body.txt" "Install Regent once"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Install in 1 command"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Star on GitHub"
assert_contains "${OUT_DIR}/frontpage-body.txt" "pnpm add -g @regentlabs/cli"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Connect Privy"
assert_contains "${OUT_DIR}/frontpage-body.txt" "Connect Privy to post into the public webapp chatbox."

ab eval '(() => {
  const modal = document.querySelector("#frontpage-intro-modal");
  return {
    ready: modal?.dataset.ready || "",
    visible: modal?.dataset.visible || ""
  };
})()' > "${OUT_DIR}/frontpage-modal-initial.json"

assert_contains "${OUT_DIR}/frontpage-modal-initial.json" '"visible": "true"'

ab click "#frontpage-intro-persist"
ab wait 150 >/dev/null 2>&1 || true
ab click "#frontpage-intro-enter"
ab wait 350 >/dev/null 2>&1 || true

ab eval '(() => {
  const modal = document.querySelector("#frontpage-intro-modal");
  const checkbox = document.querySelector("#frontpage-intro-persist");
  return {
    visible: modal?.dataset.visible || "",
    checked: checkbox?.checked || false
  };
})()' > "${OUT_DIR}/frontpage-modal-dismissed.json"

assert_contains "${OUT_DIR}/frontpage-modal-dismissed.json" '"visible": "false"'
assert_contains "${OUT_DIR}/frontpage-modal-dismissed.json" '"checked": true'

ab open "${PHOENIX_URL}/"
ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
ab eval '(() => {
  const modal = document.querySelector("#frontpage-intro-modal");
  return {
    visible: modal?.dataset.visible || ""
  };
})()' > "${OUT_DIR}/frontpage-modal-reload.json"

assert_contains "${OUT_DIR}/frontpage-modal-reload.json" '"visible": "false"'

ab click "#frontpage-reopen-intro"
ab wait 350 >/dev/null 2>&1 || true
ab eval '(() => {
  const modal = document.querySelector("#frontpage-intro-modal");
  return {
    visible: modal?.dataset.visible || ""
  };
})()' > "${OUT_DIR}/frontpage-modal-reopen.json"

assert_contains "${OUT_DIR}/frontpage-modal-reopen.json" '"visible": "true"'

ab click "#frontpage-intro-enter"
ab wait 250 >/dev/null 2>&1 || true

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
assert_contains "${OUT_DIR}/platform-explorer-body.txt" "World Map"
assert_contains "${OUT_DIR}/platform-explorer-body.txt" "Privy Login"

ab open "${PHOENIX_URL}/platform/creator"
ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
ab get text body > "${OUT_DIR}/platform-creator-body.txt"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Creator"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Choose a launch candidate"
assert_contains "${OUT_DIR}/platform-creator-body.txt" "Privy Login"

echo "frontpage/platform smoke passed"
