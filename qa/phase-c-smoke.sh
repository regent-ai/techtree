#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/sean/Documents/regent/techtree"
PHOENIX_URL="${PHOENIX_URL:-http://127.0.0.1:4000}"
APP_PATH="${APP_PATH:-/}"
APP_URL="${APP_URL:-${PHOENIX_URL%/}${APP_PATH}}"
OUT_DIR="${ROOT}/qa/artifacts/phase-c"
AB_HOME="${ROOT}/qa/.agent-browser-home"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.58.2}"
APP_READY_TIMEOUT_SEC="${APP_READY_TIMEOUT_SEC:-45}"
STATE_FILE="${OUT_DIR}/frontpage-state.json"
FIXTURE_FILE="${OUT_DIR}/frontpage-fixture.json"

mkdir -p "${OUT_DIR}" "${AB_HOME}"

ab() {
  HOME="${AB_HOME}" agent-browser "$@"
}

cleanup() {
  ab close >/dev/null 2>&1 || true
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command '${cmd}'. install it and rerun." >&2
    exit 1
  fi
}

ensure_playwright_browser() {
  local browser_bin

  browser_bin=$(
    find "${AB_HOME}/Library/Caches/ms-playwright" \
      -path "*chromium_headless_shell*/chrome-headless-shell-mac-arm64/chrome-headless-shell" \
      -print -quit 2>/dev/null || true
  )

  if [[ -z "${browser_bin}" ]]; then
    echo "Installing Playwright Chromium into ${AB_HOME} ..."
    HOME="${AB_HOME}" npx -y "playwright@${PLAYWRIGHT_VERSION}" install chromium
  fi
}

wait_for_http_ready() {
  local timeout_sec="$1"
  local start_ts
  local now_ts
  local elapsed
  local code

  start_ts="$(date +%s)"
  while true; do
    code="$(curl -sS --max-time 5 -o /dev/null -w "%{http_code}" "${APP_URL}" || true)"
    if [[ "${code}" =~ ^[234][0-9][0-9]$ ]]; then
      return 0
    fi

    now_ts="$(date +%s)"
    elapsed=$((now_ts - start_ts))
    if [[ ${elapsed} -ge ${timeout_sec} ]]; then
      echo "ASSERT FAIL: app not reachable at ${APP_URL} after ${timeout_sec}s (last HTTP code=${code:-none})" >&2
      exit 1
    fi

    sleep 1
  done
}

wait_for_page_load() {
  if ab wait --load networkidle >/dev/null 2>&1; then
    return 0
  fi

  if ab wait --load domcontentloaded >/dev/null 2>&1; then
    return 0
  fi

  ab wait 500 >/dev/null 2>&1 || true
  return 0
}

assert_contains() {
  local file="$1"
  local expected="$2"
  local label="$3"

  if ! rg -Fq "${expected}" "${file}"; then
    echo "ASSERT FAIL: ${label}" >&2
    echo "Expected to find: ${expected}" >&2
    echo "In file: ${file}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  local label="$3"

  if rg -Fq "${unexpected}" "${file}"; then
    echo "ASSERT FAIL: ${label}" >&2
    echo "Unexpected: ${unexpected}" >&2
    echo "In file: ${file}" >&2
    exit 1
  fi
}

capture_state() {
  ab eval '(() => {
    const page = document.querySelector("#frontpage-home-page");
    const graph = document.querySelector("#frontpage-home-graph");
    const grid = document.querySelector("#frontpage-home-grid");
    const agentPanel = document.querySelector("#frontpage-agent-panel");
    const humanPanel = document.querySelector("#frontpage-human-panel");
    const selectedNode = document.querySelector("#frontpage-selected-node");
    const selectedTitle = selectedNode?.querySelector("h2")?.textContent?.replace(/\s+/g, " ").trim() || "";
    return {
      hasFrontpage: !!page,
      hasIntroModal: !!document.querySelector("#frontpage-intro-modal"),
      hasBriefing: !!document.querySelector("#frontpage-home-briefing"),
      hasGraph: !!graph,
      hasGrid: !!grid,
      introOpen: page?.dataset.introOpen || "",
      topOpen: page?.dataset.topOpen || "",
      viewMode: page?.dataset.viewMode || "",
      dataMode: page?.dataset.dataMode || "",
      graphActive: graph?.dataset.active || "",
      gridActive: grid?.dataset.active || "",
      agentPanelOpen: agentPanel?.dataset.panelOpen || "",
      humanPanelOpen: humanPanel?.dataset.panelOpen || "",
      selectedNodeId: graph?.dataset.selectedNodeId || "",
      selectedTitle,
      gridNodeIds: (grid?.dataset.gridNodeIds || "").split(",").filter(Boolean),
      agentComposerDisabled: !!document.querySelector("#frontpage-agent-panel input[disabled]"),
      humanComposerDisabled: !!document.querySelector("#frontpage-human-panel input[disabled]"),
      hasLegacyDetailCard: !!document.querySelector("#detailCard"),
      hasLegacyTrollboxAccess: !!document.querySelector("#trollboxAccess"),
      hasLegacyJoinButton: !!document.querySelector("#trollboxJoin")
    };
  })()' > "${STATE_FILE}"
}

wait_for_state_value() {
  local jq_expr="$1"
  local expected="$2"
  local label="$3"
  local attempts="${4:-30}"
  local delay_ms="${5:-150}"
  local i
  local actual

  for ((i = 1; i <= attempts; i++)); do
    capture_state
    actual="$(jq -r "${jq_expr}" "${STATE_FILE}")"
    if [[ "${actual}" == "${expected}" ]]; then
      return 0
    fi
    ab wait "${delay_ms}" >/dev/null 2>&1 || true
  done

  echo "ASSERT FAIL: ${label} (expected ${expected}, got ${actual})" >&2
  cat "${STATE_FILE}" >&2 || true
  exit 1
}

trap cleanup EXIT

require_cmd curl
require_cmd rg
require_cmd jq
require_cmd npx
require_cmd agent-browser

ab close >/dev/null 2>&1 || true
ensure_playwright_browser
wait_for_http_ready "${APP_READY_TIMEOUT_SEC}"

ab --allow-file-access open "${APP_URL}"
wait_for_page_load
capture_state
cp "${STATE_FILE}" "${FIXTURE_FILE}"

if ! jq -e . "${FIXTURE_FILE}" >/dev/null 2>&1; then
  echo "ASSERT FAIL: frontpage fixture extraction produced invalid JSON (${FIXTURE_FILE})" >&2
  exit 1
fi

[[ "$(jq -r '.hasFrontpage' "${FIXTURE_FILE}")" == "true" ]] || { echo "ASSERT FAIL: #frontpage-home-page missing" >&2; exit 1; }
[[ "$(jq -r '.hasIntroModal' "${FIXTURE_FILE}")" == "true" ]] || { echo "ASSERT FAIL: #frontpage-intro-modal missing" >&2; exit 1; }
[[ "$(jq -r '.hasBriefing' "${FIXTURE_FILE}")" == "true" ]] || { echo "ASSERT FAIL: #frontpage-home-briefing missing" >&2; exit 1; }
[[ "$(jq -r '.hasGraph' "${FIXTURE_FILE}")" == "true" ]] || { echo "ASSERT FAIL: #frontpage-home-graph missing" >&2; exit 1; }
[[ "$(jq -r '.hasGrid' "${FIXTURE_FILE}")" == "true" ]] || { echo "ASSERT FAIL: #frontpage-home-grid missing" >&2; exit 1; }
[[ "$(jq -r '.hasLegacyDetailCard' "${FIXTURE_FILE}")" == "false" ]] || { echo "ASSERT FAIL: legacy #detailCard should not exist" >&2; exit 1; }
[[ "$(jq -r '.hasLegacyTrollboxAccess' "${FIXTURE_FILE}")" == "false" ]] || { echo "ASSERT FAIL: legacy #trollboxAccess should not exist" >&2; exit 1; }
[[ "$(jq -r '.hasLegacyJoinButton' "${FIXTURE_FILE}")" == "false" ]] || { echo "ASSERT FAIL: legacy #trollboxJoin should not exist" >&2; exit 1; }
[[ "$(jq -r '.introOpen' "${FIXTURE_FILE}")" == "true" ]] || { echo "ASSERT FAIL: intro should start open" >&2; exit 1; }
[[ "$(jq -r '.viewMode' "${FIXTURE_FILE}")" == "graph" ]] || { echo "ASSERT FAIL: initial view mode should be graph" >&2; exit 1; }
[[ "$(jq -r '.dataMode' "${FIXTURE_FILE}")" == "live" ]] || { echo "ASSERT FAIL: initial data mode should be live" >&2; exit 1; }
[[ -n "$(jq -r '.selectedTitle' "${FIXTURE_FILE}")" ]] || { echo "ASSERT FAIL: selected node title should be populated" >&2; exit 1; }

ab snapshot -i > "${OUT_DIR}/00-baseline.snapshot.txt"
ab screenshot "${OUT_DIR}/01-landing.png"
ab get text body > "${OUT_DIR}/01-body.txt"
assert_contains "${OUT_DIR}/01-body.txt" "TechTree Homepage" "homepage heading should render"
assert_contains "${OUT_DIR}/01-body.txt" "All agents start here:" "intro command header should render"
assert_contains "${OUT_DIR}/01-body.txt" "Agent trollbox" "agent trollbox panel should render"
assert_contains "${OUT_DIR}/01-body.txt" "Human trollbox" "human trollbox panel should render"
assert_contains "${OUT_DIR}/01-body.txt" "Connect Privy" "frontpage should prompt anonymous humans to sign in before posting"
assert_contains "${OUT_DIR}/01-body.txt" "Connect Privy to post into the canonical global room." "frontpage should explain the anonymous trollbox gate"
assert_not_contains "${OUT_DIR}/01-body.txt" "membership:" "legacy membership state should not render on the frontpage"
assert_not_contains "${OUT_DIR}/01-body.txt" "Join request pending" "legacy join flow should not render on the frontpage"

ab click "#frontpage-intro-enter"
wait_for_state_value '.introOpen' "false" "enter should dismiss the intro modal"
ab screenshot "${OUT_DIR}/02-intro-dismissed.png"

ab click "#frontpage-view-grid"
wait_for_state_value '.viewMode' "grid" "grid toggle should activate the infinite grid"
wait_for_state_value '.gridActive' "true" "grid shell should be active in grid mode"
wait_for_state_value '.graphActive' "false" "graph shell should become inactive in grid mode"
ab get text "#frontpage-home-briefing" > "${OUT_DIR}/03-grid-briefing.txt"
assert_contains "${OUT_DIR}/03-grid-briefing.txt" "Infinite seed lattice" "briefing should describe the grid view after toggle"
ab screenshot "${OUT_DIR}/03-grid.png"

ab eval 'document.querySelector("#frontpage-top-toggle")?.click()'
wait_for_state_value '.topOpen' "false" "briefing toggle should collapse the top drawer"
ab screenshot "${OUT_DIR}/04-top-collapsed.png"

ab click "#frontpage-agent-panel [data-panel-close]"
wait_for_state_value '.agentPanelOpen' "false" "agent panel toggle should collapse the agent trollbox"
ab click "#frontpage-human-panel [data-panel-close]"
wait_for_state_value '.humanPanelOpen' "false" "human panel toggle should collapse the human trollbox"
capture_state
[[ "$(jq -r '.agentComposerDisabled' "${STATE_FILE}")" == "true" ]] || { echo "ASSERT FAIL: agent composer should remain disabled on the frontpage" >&2; exit 1; }
[[ "$(jq -r '.humanComposerDisabled' "${STATE_FILE}")" == "true" ]] || { echo "ASSERT FAIL: human composer should stay gated before Privy sign-in" >&2; exit 1; }
ab screenshot "${OUT_DIR}/05-panels-collapsed.png"

cat > "${OUT_DIR}/99-assertions.txt" <<'EOF'
phase-c smoke assertions passed:
- current HomeLive shell renders the intro modal, briefing drawer, graph shell, grid shell, and both corner trollbox panels
- removed legacy selectors (#detailCard, #trollboxAccess, #trollboxJoin) stay absent on the root route
- intro dismissal updates the live root page state without leaving /
- graph -> grid toggle updates the active stage and briefing copy to the infinite-grid presentation
- briefing and both trollbox panels collapse independently via the current frontpage controls
- anonymous humans see a Privy sign-in prompt before posting into the human trollbox
- the human trollbox composer stays gated until Privy sign-in is completed
EOF
