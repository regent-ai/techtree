#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/sean/Documents/regent/techtree"
PHOENIX_URL="${PHOENIX_URL:-http://127.0.0.1:4001}"
OUT_DIR="${ROOT}/qa/artifacts/bbh-wall"
AB_HOME="${ROOT}/qa/.agent-browser-home"
SESSION="${AGENT_BROWSER_SESSION:-bbh-wall-smoke}"

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

ab open "${PHOENIX_URL}/bbh"
ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
ab get text body > "${OUT_DIR}/bbh-wall-body.txt"

assert_contains "${OUT_DIR}/bbh-wall-body.txt" "Three-lane wall"
assert_contains "${OUT_DIR}/bbh-wall-body.txt" "Wall feed"
assert_contains "${OUT_DIR}/bbh-wall-body.txt" "Pinned drilldown"
assert_contains "${OUT_DIR}/bbh-wall-body.txt" "Benchmark ledger"
assert_contains "${OUT_DIR}/bbh-wall-body.txt" "Practice"
assert_contains "${OUT_DIR}/bbh-wall-body.txt" "Proving"
assert_contains "${OUT_DIR}/bbh-wall-body.txt" "Challenge"
assert_contains "${OUT_DIR}/bbh-wall-body.txt" "--lane climb / benchmark / challenge"

ab eval '(() => {
  const firstCapsule = document.querySelector("#bbh-wall-grid .bbh-capsule");
  const currentBestRun = document.querySelector("#bbh-wall-drilldown a[href^=\"/bbh/runs/\"]");
  return {
    firstCapsuleId: firstCapsule?.id || "",
    currentBestRunHref: currentBestRun?.getAttribute("href") || "",
    currentUrl: window.location.href
  };
})()' > "${OUT_DIR}/bbh-wall-state.json"

FIRST_CAPSULE_ID="$(jq -r '.firstCapsuleId' "${OUT_DIR}/bbh-wall-state.json")"
RUN_HREF="$(jq -r '.currentBestRunHref' "${OUT_DIR}/bbh-wall-state.json")"
CURRENT_URL="$(jq -r '.currentUrl' "${OUT_DIR}/bbh-wall-state.json")"

if [[ -n "${FIRST_CAPSULE_ID}" && "${FIRST_CAPSULE_ID}" != "null" ]]; then
  ab click "#${FIRST_CAPSULE_ID}"
  ab wait 300 >/dev/null 2>&1 || true
  ab get text "#bbh-wall-drilldown" > "${OUT_DIR}/bbh-drilldown.txt"
  ab eval 'window.location.search' > "${OUT_DIR}/bbh-wall-query.json"
  assert_contains "${OUT_DIR}/bbh-drilldown.txt" "Pinned focus survives refresh"
  assert_contains "${OUT_DIR}/bbh-wall-query.json" "focus="
  assert_contains "${OUT_DIR}/bbh-drilldown.txt" "Current best run"
  assert_contains "${OUT_DIR}/bbh-drilldown.txt" "Latest validated run"

  if [[ -n "${CURRENT_URL}" && "${CURRENT_URL}" != "null" ]]; then
    ab open "${CURRENT_URL}"
    ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
    ab get text "#bbh-wall-drilldown" > "${OUT_DIR}/bbh-drilldown-refresh.txt"
    assert_contains "${OUT_DIR}/bbh-drilldown-refresh.txt" "Pinned focus survives refresh"
  fi

  if [[ -n "${RUN_HREF}" && "${RUN_HREF}" != "null" ]]; then
    ab open "${PHOENIX_URL}${RUN_HREF}"
    ab wait --load networkidle >/dev/null 2>&1 || ab wait 500 >/dev/null 2>&1 || true
    ab get text body > "${OUT_DIR}/bbh-run-body.txt"
    assert_contains "${OUT_DIR}/bbh-run-body.txt" "Benchmark ledger boundary"
  fi
else
  assert_contains "${OUT_DIR}/bbh-wall-body.txt" "No active capsules yet."
fi

echo "bbh wall smoke passed"
