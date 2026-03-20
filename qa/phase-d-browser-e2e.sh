#!/usr/bin/env bash
set -uo pipefail

ROOT="/Users/sean/Documents/regent/techtree"
PHOENIX_URL="${PHOENIX_URL:-http://127.0.0.1:4000}"
APP_PATH="${APP_PATH:-/}"
APP_URL="${APP_URL:-${PHOENIX_URL%/}${APP_PATH}}"
QA_DIR="${ROOT}/qa"
OUT_DIR="${QA_DIR}/artifacts/final"
LOG_DIR="${OUT_DIR}/logs"
AB_HOME="${QA_DIR}/.agent-browser-home"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.58.2}"
IOS_DEVICE="${IOS_DEVICE:-iPhone 15 Pro}"
REQUIRE_DESKTOP="${REQUIRE_DESKTOP:-1}"
REQUIRE_IOS="${REQUIRE_IOS:-0}"
APP_READY_TIMEOUT_SEC="${APP_READY_TIMEOUT_SEC:-45}"
RUN_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
STATUS_FILE="${OUT_DIR}/${RUN_STAMP}.status.tsv"
SUMMARY_FILE="${OUT_DIR}/${RUN_STAMP}.summary.md"
AB_SESSION="pdd-${RUN_STAMP:9:6}"
AB_SESSION_IOS="pdi-${RUN_STAMP:9:6}"
FIXTURE_FILE="${OUT_DIR}/${RUN_STAMP}.fixture.json"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

DESKTOP_ENABLED=1
DESKTOP_REASON=""

IOS_ENABLED=0
IOS_REASON="not checked"
IOS_DEVICE_SELECTED=""

RESULT_ROWS=()
SELECTED_NODE_TITLE=""
SELECTED_NODE_ID=""
BASE_GRID_NODE_ID=""
BASE_GRID_NODE_TITLE=""
BASE_AGENT_MESSAGE=""
BASE_HUMAN_MESSAGE=""

mkdir -p "${OUT_DIR}" "${LOG_DIR}" "${AB_HOME}"

ab() {
  HOME="${AB_HOME}" AGENT_BROWSER_SESSION="${AB_SESSION}" agent-browser "$@"
}

ab_ios() {
  HOME="${AB_HOME}" AGENT_BROWSER_SESSION="${AB_SESSION_IOS}" agent-browser -p ios --device "${IOS_DEVICE_SELECTED}" "$@"
}

cleanup() {
  ab close >/dev/null 2>&1 || true
  if [[ -n "${IOS_DEVICE_SELECTED}" ]]; then
    ab_ios close >/dev/null 2>&1 || true
  else
    HOME="${AB_HOME}" AGENT_BROWSER_SESSION="${AB_SESSION_IOS}" agent-browser -p ios close >/dev/null 2>&1 || true
  fi
}

require_cmd() {
  local cmd="$1"

  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command '${cmd}'. install it and rerun." >&2
    return 1
  fi
}

wait_for_http_ready() {
  local timeout_sec="$1"
  local probe_log="${LOG_DIR}/${RUN_STAMP}.http-probe.log"
  local start_ts
  local now_ts
  local elapsed
  local code

  start_ts="$(date +%s)"
  : > "${probe_log}"

  while true; do
    code="$(curl -sS --max-time 5 -o /dev/null -w "%{http_code}" "${APP_URL}" 2>>"${probe_log}" || true)"
    if [[ "${code}" =~ ^[234][0-9][0-9]$ ]]; then
      return 0
    fi

    now_ts="$(date +%s)"
    elapsed=$((now_ts - start_ts))
    if [[ ${elapsed} -ge ${timeout_sec} ]]; then
      echo "Timed out waiting for app readiness at ${APP_URL} after ${timeout_sec}s (last HTTP code=${code:-none}; log=$(basename "${probe_log}"))" >&2
      return 1
    fi

    sleep 1
  done
}

wait_for_page_load_desktop() {
  if ab wait --load networkidle >/dev/null 2>&1; then
    return 0
  fi

  if ab wait --load domcontentloaded >/dev/null 2>&1; then
    return 0
  fi

  ab wait 500 >/dev/null 2>&1 || true
  return 0
}

wait_for_page_load_ios() {
  if ab_ios wait --load networkidle >/dev/null 2>&1; then
    return 0
  fi

  if ab_ios wait --load domcontentloaded >/dev/null 2>&1; then
    return 0
  fi

  ab_ios wait 700 >/dev/null 2>&1 || true
  return 0
}

assert_contains() {
  local file="$1"
  local expected="$2"
  local label="$3"
  if ! rg -Fq "${expected}" "${file}"; then
    echo "ASSERT FAIL: ${label}" >&2
    echo "Expected: ${expected}" >&2
    echo "File: ${file}" >&2
    return 1
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  local label="$3"
  if rg -Fq "${unexpected}" "${file}"; then
    echo "ASSERT FAIL: ${label}" >&2
    echo "Unexpected: ${unexpected}" >&2
    echo "File: ${file}" >&2
    return 1
  fi
}

capture_state_desktop() {
  ab eval '(() => {
    const page = document.querySelector("#frontpage-home-page");
    const graph = document.querySelector("#frontpage-home-graph");
    const grid = document.querySelector("#frontpage-home-grid");
    const selectedNode = document.querySelector("#frontpage-selected-node");
    const agentPanel = document.querySelector("#frontpage-agent-panel");
    const humanPanel = document.querySelector("#frontpage-human-panel");
    const agentMessages = Array.from(document.querySelectorAll("#frontpage-agent-panel .chat-bubble")).map((el) =>
      (el.textContent || "").replace(/\s+/g, " ").trim()
    ).filter(Boolean);
    const humanMessages = Array.from(document.querySelectorAll("#frontpage-human-panel .chat-bubble")).map((el) =>
      (el.textContent || "").replace(/\s+/g, " ").trim()
    ).filter(Boolean);
    return {
      introOpen: page?.dataset.introOpen || "",
      topOpen: page?.dataset.topOpen || "",
      viewMode: page?.dataset.viewMode || "",
      dataMode: page?.dataset.dataMode || "",
      graphActive: graph?.dataset.active || "",
      gridActive: grid?.dataset.active || "",
      selectedNodeId: graph?.dataset.selectedNodeId || "",
      selectedNodeTitle: selectedNode?.querySelector("h2")?.textContent?.replace(/\s+/g, " ").trim() || "",
      agentPanelOpen: agentPanel?.dataset.panelOpen || "",
      humanPanelOpen: humanPanel?.dataset.panelOpen || "",
      agentComposerDisabled: !!document.querySelector("#frontpage-agent-panel input[disabled]"),
      humanComposerDisabled: !!document.querySelector("#frontpage-human-panel input[disabled]"),
      agentMessages,
      humanMessages,
      hasLegacyDetailCard: !!document.querySelector("#detailCard"),
      hasLegacyTrollboxAccess: !!document.querySelector("#trollboxAccess"),
      hasLegacyNodeSearch: !!document.querySelector("#nodeSearch"),
      hasLegacyCommentsList: !!document.querySelector("#commentsList"),
      gridNodeIds: (grid?.dataset.gridNodeIds || "").split(",").filter(Boolean)
    };
  })()'
}

capture_state_ios() {
  ab_ios eval '(() => {
    const page = document.querySelector("#frontpage-home-page");
    const graph = document.querySelector("#frontpage-home-graph");
    const grid = document.querySelector("#frontpage-home-grid");
    return {
      introOpen: page?.dataset.introOpen || "",
      topOpen: page?.dataset.topOpen || "",
      viewMode: page?.dataset.viewMode || "",
      graphActive: graph?.dataset.active || "",
      gridActive: grid?.dataset.active || "",
      hasLegacyDetailCard: !!document.querySelector("#detailCard"),
      hasLegacyTrollboxAccess: !!document.querySelector("#trollboxAccess")
    };
  })()'
}

wait_for_state_value_desktop() {
  local jq_expr="$1"
  local expected="$2"
  local outfile="$3"
  local attempts="${4:-40}"
  local delay_ms="${5:-150}"
  local i
  local actual=""

  for ((i = 1; i <= attempts; i++)); do
    capture_state_desktop > "${outfile}"
    actual="$(jq -r "${jq_expr}" "${outfile}")"
    if [[ "${actual}" == "${expected}" ]]; then
      return 0
    fi
    ab wait "${delay_ms}" >/dev/null 2>&1 || true
  done

  echo "ASSERT FAIL: desktop state ${jq_expr} never became ${expected} (last=${actual})" >&2
  cat "${outfile}" >&2 || true
  return 1
}

wait_for_state_value_ios() {
  local jq_expr="$1"
  local expected="$2"
  local outfile="$3"
  local attempts="${4:-60}"
  local delay_ms="${5:-180}"
  local i
  local actual=""

  for ((i = 1; i <= attempts; i++)); do
    capture_state_ios > "${outfile}"
    actual="$(jq -r "${jq_expr}" "${outfile}")"
    if [[ "${actual}" == "${expected}" ]]; then
      return 0
    fi
    ab_ios wait "${delay_ms}" >/dev/null 2>&1 || true
  done

  echo "ASSERT FAIL: ios state ${jq_expr} never became ${expected} (last=${actual})" >&2
  cat "${outfile}" >&2 || true
  return 1
}

wait_for_selector_desktop() {
  local selector="$1"
  local attempts="${2:-40}"
  local delay_ms="${3:-150}"
  local selector_json
  local i

  selector_json="$(jq -Rn --arg s "${selector}" '$s')"

  for ((i = 1; i <= attempts; i++)); do
    if [[ "$(ab eval "document.querySelector(${selector_json}) ? true : false")" == "true" ]]; then
      return 0
    fi
    ab wait "${delay_ms}" >/dev/null 2>&1 || true
  done

  echo "ASSERT FAIL: desktop selector never appeared: ${selector}" >&2
  return 1
}

wait_for_selector_ios() {
  local selector="$1"
  local attempts="${2:-60}"
  local delay_ms="${3:-180}"
  local selector_json
  local i

  selector_json="$(jq -Rn --arg s "${selector}" '$s')"

  for ((i = 1; i <= attempts; i++)); do
    if [[ "$(ab_ios eval "document.querySelector(${selector_json}) ? true : false")" == "true" ]]; then
      return 0
    fi
    ab_ios wait "${delay_ms}" >/dev/null 2>&1 || true
  done

  echo "ASSERT FAIL: ios selector never appeared: ${selector}" >&2
  return 1
}

ensure_playwright_browser() {
  local browser_bin

  browser_bin=$(
    find "${AB_HOME}/Library/Caches/ms-playwright" \
      -path "*chromium_headless_shell*/chrome-headless-shell-mac-arm64/chrome-headless-shell" \
      -print -quit 2>/dev/null || true
  )

  if [[ -n "${browser_bin}" ]]; then
    return 0
  fi

  echo "Playwright Chromium not found in ${AB_HOME}; installing playwright@${PLAYWRIGHT_VERSION} browser runtime..."
  HOME="${AB_HOME}" npx -y "playwright@${PLAYWRIGHT_VERSION}" install chromium
}

extract_desktop_fixture() {
  local fixture_log="${LOG_DIR}/${RUN_STAMP}.desktop-fixture.log"

  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}" > "${fixture_log}" 2>&1
  wait_for_page_load_desktop >> "${fixture_log}" 2>&1 || true
  capture_state_desktop > "${FIXTURE_FILE}"
  ab close >> "${fixture_log}" 2>&1 || true

  if ! jq -e . "${FIXTURE_FILE}" >/dev/null 2>&1; then
    echo "desktop fixture extraction failed: invalid fixture JSON (see $(basename "${fixture_log}"))" >&2
    return 1
  fi

  if [[ "$(jq -r '.hasLegacyDetailCard' "${FIXTURE_FILE}")" != "false" ]]; then
    echo "desktop fixture extraction failed: legacy #detailCard is still present (see $(basename "${fixture_log}"))" >&2
    return 1
  fi

  if [[ "$(jq -r '.hasLegacyTrollboxAccess' "${FIXTURE_FILE}")" != "false" ]]; then
    echo "desktop fixture extraction failed: legacy #trollboxAccess is still present (see $(basename "${fixture_log}"))" >&2
    return 1
  fi

  SELECTED_NODE_TITLE="$(jq -r '.selectedNodeTitle' "${FIXTURE_FILE}")"
  SELECTED_NODE_ID="$(jq -r '.selectedNodeId' "${FIXTURE_FILE}")"
  BASE_GRID_NODE_ID="$(jq -r '.gridNodeIds[0] // empty' "${FIXTURE_FILE}")"
  BASE_AGENT_MESSAGE="$(jq -r '.agentMessages[0] // empty' "${FIXTURE_FILE}")"
  BASE_HUMAN_MESSAGE="$(jq -r '.humanMessages[0] // empty' "${FIXTURE_FILE}")"

  if [[ -z "${SELECTED_NODE_TITLE}" || -z "${SELECTED_NODE_ID}" || -z "${BASE_GRID_NODE_ID}" ]]; then
    echo "desktop fixture extraction failed: unable to derive deterministic frontpage state (see ${FIXTURE_FILE})" >&2
    return 1
  fi
}

probe_desktop_daemon() {
  local probe_log="${LOG_DIR}/${RUN_STAMP}.desktop-probe.log"
  local tools_log="${LOG_DIR}/${RUN_STAMP}.preflight-tools.log"

  {
    require_cmd curl
    require_cmd rg
    require_cmd jq
    require_cmd npx
    require_cmd agent-browser
  } > "${tools_log}" 2>&1 || {
    DESKTOP_ENABLED=0
    DESKTOP_REASON="missing required browser tooling (see $(basename "${tools_log}"))"
    return 1
  }

  if ! wait_for_http_ready "${APP_READY_TIMEOUT_SEC}" >> "${probe_log}" 2>&1; then
    DESKTOP_ENABLED=0
    DESKTOP_REASON="app URL unreachable (${APP_URL}); readiness timeout ${APP_READY_TIMEOUT_SEC}s"
    return 1
  fi

  ab close >/dev/null 2>&1 || true
  if ! ab --allow-file-access open "${APP_URL}" > "${probe_log}" 2>&1; then
    DESKTOP_ENABLED=0
    if rg -Fq "ERR_CONNECTION_REFUSED" "${probe_log}"; then
      DESKTOP_REASON="app URL refused connection (${APP_URL}) (see $(basename "${probe_log}"))"
    elif rg -Fq "ERR_NAME_NOT_RESOLVED" "${probe_log}"; then
      DESKTOP_REASON="app URL DNS resolution failed (${APP_URL}) (see $(basename "${probe_log}"))"
    else
      DESKTOP_REASON="agent-browser desktop probe failed (see $(basename "${probe_log}"))"
    fi
    return 1
  fi

  wait_for_page_load_desktop >> "${probe_log}" 2>&1 || true
  ab close >> "${probe_log}" 2>&1 || true

  if ! extract_desktop_fixture >> "${probe_log}" 2>&1; then
    DESKTOP_ENABLED=0
    DESKTOP_REASON="frontpage fixture preflight failed (see $(basename "${probe_log}"))"
    return 1
  fi

  return 0
}

detect_ios_device() {
  local device_log="${LOG_DIR}/${RUN_STAMP}.ios-device-list.log"

  if ! command -v xcrun >/dev/null 2>&1; then
    IOS_ENABLED=0
    IOS_REASON="xcrun not found"
    return 0
  fi

  if ! command -v appium >/dev/null 2>&1; then
    IOS_ENABLED=0
    IOS_REASON="appium not found (install appium to enable iOS matrix)"
    return 0
  fi

  if ! HOME="${AB_HOME}" agent-browser device list > "${device_log}" 2>&1; then
    IOS_ENABLED=0
    IOS_REASON="agent-browser device list failed"
    return 0
  fi

  if rg -Fq "${IOS_DEVICE}" "${device_log}"; then
    IOS_ENABLED=1
    IOS_REASON="ok"
    IOS_DEVICE_SELECTED="${IOS_DEVICE}"
    return 0
  fi

  IOS_DEVICE_SELECTED="$(sed -nE 's/^[[:space:]]*[^A-Za-z0-9]*((iPhone|iPad)[^()]+).*/\1/p' "${device_log}" | sed -n '1p' | sed 's/[[:space:]]*$//')"
  if [[ -n "${IOS_DEVICE_SELECTED}" ]]; then
    IOS_ENABLED=1
    IOS_REASON="requested device unavailable; using ${IOS_DEVICE_SELECTED}"
    return 0
  fi

  IOS_ENABLED=0
  IOS_REASON="no iOS simulator devices found"
}

record_result() {
  local case_id="$1"
  local platform="$2"
  local status="$3"
  local artifacts="$4"
  local notes="$5"

  RESULT_ROWS+=("${case_id}|${platform}|${status}|${artifacts}|${notes}")
  printf "%s\t%s\t%s\t%s\t%s\n" "${case_id}" "${platform}" "${status}" "${artifacts}" "${notes}" >> "${STATUS_FILE}"

  case "${status}" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
  esac
}

run_case() {
  local case_id="$1"
  local platform="$2"
  local description="$3"
  local artifacts="$4"
  local case_fn="$5"
  local case_log="${LOG_DIR}/${case_id}.log"

  echo "[${case_id}] ${description}"
  if "${case_fn}" > "${case_log}" 2>&1; then
    echo "[${case_id}] PASS"
    record_result "${case_id}" "${platform}" "PASS" "${artifacts}" "log=$(basename "${case_log}")"
  else
    echo "[${case_id}] FAIL (see ${case_log})"
    record_result "${case_id}" "${platform}" "FAIL" "${artifacts}" "log=$(basename "${case_log}")"
  fi
}

skip_case() {
  local case_id="$1"
  local platform="$2"
  local description="$3"
  local artifacts="$4"
  local reason="$5"
  local case_log="${LOG_DIR}/${case_id}.log"

  {
    echo "[${case_id}] ${description}"
    echo "SKIPPED: ${reason}"
  } > "${case_log}"

  echo "[${case_id}] SKIP (${reason})"
  record_result "${case_id}" "${platform}" "SKIP" "${artifacts}" "${reason}; log=$(basename "${case_log}")"
}

case_e2e_01() {
  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop
  capture_state_desktop > "${OUT_DIR}/e2e-01-state.json"
  ab screenshot "${OUT_DIR}/e2e-01-desktop-landing.png"
  ab get text body > "${OUT_DIR}/e2e-01-body.txt"
  assert_contains "${OUT_DIR}/e2e-01-body.txt" "TechTree Homepage" "desktop landing should render the frontpage heading"
  assert_contains "${OUT_DIR}/e2e-01-body.txt" "All agents start here:" "desktop landing should render the intro command"
  assert_contains "${OUT_DIR}/e2e-01-body.txt" "Agent trollbox" "desktop landing should render the agent trollbox chrome"
  assert_contains "${OUT_DIR}/e2e-01-body.txt" "Human trollbox" "desktop landing should render the human trollbox chrome"
  assert_contains "${OUT_DIR}/e2e-01-body.txt" "Connect Privy" "desktop landing should advertise the anonymous trollbox sign-in gate"
  assert_contains "${OUT_DIR}/e2e-01-body.txt" "Connect Privy to post into the canonical global room." "desktop landing should explain the human posting gate"
  assert_not_contains "${OUT_DIR}/e2e-01-body.txt" "membership:" "desktop landing should not expose legacy membership labels"
  assert_not_contains "${OUT_DIR}/e2e-01-body.txt" "Join request pending" "desktop landing should not expose the removed join flow"
  [[ "$(jq -r '.introOpen' "${OUT_DIR}/e2e-01-state.json")" == "true" ]] || return 1
  [[ "$(jq -r '.viewMode' "${OUT_DIR}/e2e-01-state.json")" == "graph" ]] || return 1
  [[ "$(jq -r '.dataMode' "${OUT_DIR}/e2e-01-state.json")" == "live" ]] || return 1
  [[ "$(jq -r '.agentPanelOpen' "${OUT_DIR}/e2e-01-state.json")" == "true" ]] || return 1
  [[ "$(jq -r '.humanPanelOpen' "${OUT_DIR}/e2e-01-state.json")" == "true" ]] || return 1
  [[ "$(jq -r '.hasLegacyDetailCard' "${OUT_DIR}/e2e-01-state.json")" == "false" ]] || return 1
  [[ "$(jq -r '.hasLegacyTrollboxAccess' "${OUT_DIR}/e2e-01-state.json")" == "false" ]] || return 1
  [[ "$(jq -r '.hasLegacyNodeSearch' "${OUT_DIR}/e2e-01-state.json")" == "false" ]] || return 1
  [[ "$(jq -r '.hasLegacyCommentsList' "${OUT_DIR}/e2e-01-state.json")" == "false" ]] || return 1
  ab close
}

case_e2e_02() {
  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop
  ab click "#frontpage-intro-enter"
  wait_for_state_value_desktop '.introOpen' "false" "${OUT_DIR}/e2e-02-state.json" 50 140
  ab click "#frontpage-view-grid"
  wait_for_state_value_desktop '.viewMode' "grid" "${OUT_DIR}/e2e-02-state.json" 50 140
  wait_for_state_value_desktop '.gridActive' "true" "${OUT_DIR}/e2e-02-state.json" 50 140
  wait_for_state_value_desktop '.graphActive' "false" "${OUT_DIR}/e2e-02-state.json" 50 140
  ab get text "#frontpage-home-briefing" > "${OUT_DIR}/e2e-02-briefing.txt"
  assert_contains "${OUT_DIR}/e2e-02-briefing.txt" "Infinite seed lattice" "desktop grid switch should update the briefing copy"
  assert_contains "${OUT_DIR}/e2e-02-briefing.txt" "Front door defaults" "desktop briefing should stay visible after intro dismissal"
  ab screenshot "${OUT_DIR}/e2e-02-desktop-grid.png"
  ab close
}

case_e2e_03() {
  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop
  ab click "#frontpage-intro-enter"
  wait_for_state_value_desktop '.introOpen' "false" "${OUT_DIR}/e2e-03-state.json" 50 140
  ab click "#frontpage-view-grid"
  wait_for_state_value_desktop '.viewMode' "grid" "${OUT_DIR}/e2e-03-state.json" 50 140
  wait_for_selector_desktop ".fp-grid-item[data-node-id='${BASE_GRID_NODE_ID}']" 80 160
  ab eval "document.querySelector('.fp-grid-item[data-node-id=\"${BASE_GRID_NODE_ID}\"]')?.click()"
  wait_for_selector_desktop "#frontpage-grid-return" 80 160
  ab get text "#frontpage-home-grid" > "${OUT_DIR}/e2e-03-grid-body.txt"
  ab screenshot "${OUT_DIR}/e2e-03-grid-drilldown.png"
  assert_not_contains "${OUT_DIR}/e2e-03-grid-body.txt" "undefined" "desktop grid should not render undefined text after drilldown"
  assert_not_contains "${OUT_DIR}/e2e-03-grid-body.txt" "null" "desktop grid should not render null text after drilldown"
  ab close
}

case_e2e_04() {
  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop
  ab click "#frontpage-intro-enter"
  wait_for_state_value_desktop '.introOpen' "false" "${OUT_DIR}/e2e-04-state.json" 50 140
  ab eval 'document.querySelector("#frontpage-top-toggle")?.click()'
  wait_for_state_value_desktop '.topOpen' "false" "${OUT_DIR}/e2e-04-state.json" 40 140
  ab click '#frontpage-agent-panel [data-panel-close]'
  wait_for_state_value_desktop '.agentPanelOpen' "false" "${OUT_DIR}/e2e-04-state.json" 40 140
  ab click '#frontpage-human-panel [data-panel-close]'
  wait_for_state_value_desktop '.humanPanelOpen' "false" "${OUT_DIR}/e2e-04-state.json" 40 140
  ab click '#frontpage-agent-panel [data-panel-restore]'
  wait_for_state_value_desktop '.agentPanelOpen' "true" "${OUT_DIR}/e2e-04-state.json" 40 140
  ab click '#frontpage-human-panel [data-panel-restore]'
  wait_for_state_value_desktop '.humanPanelOpen' "true" "${OUT_DIR}/e2e-04-state.json" 40 140
  ab get text "#frontpage-agent-panel" > "${OUT_DIR}/e2e-04-agent-panel.txt"
  ab get text "#frontpage-human-panel" > "${OUT_DIR}/e2e-04-human-panel.txt"
  assert_contains "${OUT_DIR}/e2e-04-agent-panel.txt" "Agent trollbox" "desktop agent panel should restore cleanly"
  assert_contains "${OUT_DIR}/e2e-04-human-panel.txt" "Human trollbox" "desktop human panel should restore cleanly"
  assert_contains "${OUT_DIR}/e2e-04-human-panel.txt" "Connect Privy" "desktop human panel should remain read-only before sign-in"
  capture_state_desktop > "${OUT_DIR}/e2e-04-panel-state.json"
  [[ "$(jq -r '.agentComposerDisabled' "${OUT_DIR}/e2e-04-panel-state.json")" == "true" ]] || return 1
  [[ "$(jq -r '.humanComposerDisabled' "${OUT_DIR}/e2e-04-panel-state.json")" == "true" ]] || return 1
  ab screenshot "${OUT_DIR}/e2e-04-trollbox-panels.png"
  ab close
}

case_e2e_05() {
  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop
  ab set media dark
  ab wait 250
  ab screenshot "${OUT_DIR}/e2e-05-dark.png"
  ab get text body > "${OUT_DIR}/e2e-05-body.txt"
  assert_contains "${OUT_DIR}/e2e-05-body.txt" "TechTree Homepage" "desktop dark-mode render should still load the homepage content"
  assert_not_contains "${OUT_DIR}/e2e-05-body.txt" "detailCard" "desktop dark-mode render should not regress to legacy selectors"
  ab close
}

case_e2e_06() {
  ab_ios close >/dev/null 2>&1 || true
  ab_ios --allow-file-access open "${APP_URL}"
  wait_for_page_load_ios
  capture_state_ios > "${OUT_DIR}/e2e-06-ios-state.json"
  ab_ios screenshot "${OUT_DIR}/e2e-06-ios-landing.png"
  ab_ios get text body > "${OUT_DIR}/e2e-06-ios-body.txt"
  assert_contains "${OUT_DIR}/e2e-06-ios-body.txt" "TechTree Homepage" "ios landing should render the frontpage heading"
  assert_contains "${OUT_DIR}/e2e-06-ios-body.txt" "All agents start here:" "ios landing should render the intro command"
  [[ "$(jq -r '.introOpen' "${OUT_DIR}/e2e-06-ios-state.json")" == "true" ]] || return 1
  [[ "$(jq -r '.viewMode' "${OUT_DIR}/e2e-06-ios-state.json")" == "graph" ]] || return 1
  [[ "$(jq -r '.hasLegacyDetailCard' "${OUT_DIR}/e2e-06-ios-state.json")" == "false" ]] || return 1
  [[ "$(jq -r '.hasLegacyTrollboxAccess' "${OUT_DIR}/e2e-06-ios-state.json")" == "false" ]] || return 1
  ab_ios close
}

case_e2e_07() {
  ab_ios close >/dev/null 2>&1 || true
  ab_ios --allow-file-access open "${APP_URL}"
  wait_for_page_load_ios
  ab_ios tap "#frontpage-intro-enter"
  wait_for_state_value_ios '.introOpen' "false" "${OUT_DIR}/e2e-07-ios-state.json" 80 180
  ab_ios tap "#frontpage-view-grid"
  wait_for_state_value_ios '.viewMode' "grid" "${OUT_DIR}/e2e-07-ios-state.json" 80 180
  wait_for_state_value_ios '.gridActive' "true" "${OUT_DIR}/e2e-07-ios-state.json" 80 180
  wait_for_selector_ios ".fp-grid-item[data-node-id='${BASE_GRID_NODE_ID}']" 100 200
  ab_ios eval "document.querySelector('.fp-grid-item[data-node-id=\"${BASE_GRID_NODE_ID}\"]')?.click()"
  wait_for_selector_ios "#frontpage-grid-return" 100 200
  ab_ios get text "#frontpage-home-grid" > "${OUT_DIR}/e2e-07-ios-grid-body.txt"
  assert_not_contains "${OUT_DIR}/e2e-07-ios-grid-body.txt" "undefined" "ios grid should not render undefined text after drilldown"
  assert_not_contains "${OUT_DIR}/e2e-07-ios-grid-body.txt" "null" "ios grid should not render null text after drilldown"
  ab_ios screenshot "${OUT_DIR}/e2e-07-ios-grid-drilldown.png"
  ab_ios close
}

case_e2e_08() {
  ab_ios close >/dev/null 2>&1 || true
  ab_ios --allow-file-access open "${APP_URL}"
  wait_for_page_load_ios
  ab_ios tap "#frontpage-intro-enter"
  wait_for_state_value_ios '.introOpen' "false" "${OUT_DIR}/e2e-08-ios-state.json" 80 180
  ab_ios eval 'document.querySelector("#frontpage-top-toggle")?.click()'
  wait_for_state_value_ios '.topOpen' "false" "${OUT_DIR}/e2e-08-ios-state.json" 80 180
  ab_ios tap '#frontpage-agent-panel [data-panel-close]'
  wait_for_selector_ios "#frontpage-agent-panel[data-panel-open='false']" 80 180
  ab_ios tap '#frontpage-human-panel [data-panel-close]'
  wait_for_selector_ios "#frontpage-human-panel[data-panel-open='false']" 80 180
  ab_ios screenshot "${OUT_DIR}/e2e-08-ios-panels.png"
  ab_ios close
}

write_summary() {
  {
    echo "# Phase D Browser E2E Summary"
    echo
    echo "- Run stamp (UTC): ${RUN_STAMP}"
    echo "- Isolated HOME: ${AB_HOME}"
    echo "- App URL: ${APP_URL}"
    echo "- Playwright version: ${PLAYWRIGHT_VERSION}"
    echo "- Require desktop: ${REQUIRE_DESKTOP}"
    echo "- Require iOS: ${REQUIRE_IOS}"
    echo "- Desktop readiness: $([[ ${DESKTOP_ENABLED} -eq 1 ]] && echo enabled || echo disabled) ${DESKTOP_REASON}"
    echo "- iOS readiness: $([[ ${IOS_ENABLED} -eq 1 ]] && echo enabled || echo disabled) ${IOS_REASON}"
    if [[ ${DESKTOP_ENABLED} -eq 1 ]]; then
      echo "- Fixture file: ${FIXTURE_FILE}"
      echo "- Selected node fixture: ${SELECTED_NODE_ID} (${SELECTED_NODE_TITLE})"
      echo "- Grid node fixture: ${BASE_GRID_NODE_ID}"
      echo "- Agent message fixture: ${BASE_AGENT_MESSAGE}"
      echo "- Human message fixture: ${BASE_HUMAN_MESSAGE}"
    fi
    if [[ ${IOS_ENABLED} -eq 1 ]]; then
      echo "- iOS device: ${IOS_DEVICE_SELECTED}"
    fi
    echo
    echo "| Case | Platform | Status | Artifacts | Notes |"
    echo "|---|---|---|---|---|"

    local row
    for row in "${RESULT_ROWS[@]}"; do
      IFS='|' read -r case_id platform status artifacts notes <<< "${row}"
      echo "| ${case_id} | ${platform} | ${status} | ${artifacts} | ${notes} |"
    done

    echo
    echo "PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT}"
    echo
    echo "Log directory: ${LOG_DIR}"
    echo "Status TSV: ${STATUS_FILE}"
  } > "${SUMMARY_FILE}"
}

trap cleanup EXIT

printf "case\tplatform\tstatus\tartifacts\tnotes\n" > "${STATUS_FILE}"

echo "Phase D matrix run ${RUN_STAMP}"

echo "Bootstrapping Playwright runtime in isolated HOME..."
if ! ensure_playwright_browser; then
  DESKTOP_ENABLED=0
  DESKTOP_REASON="playwright chromium bootstrap failed"
  echo "Desktop preflight failed: ${DESKTOP_REASON}"
fi

if [[ ${DESKTOP_ENABLED} -eq 1 ]]; then
  echo "Probing agent-browser desktop daemon..."
  if ! probe_desktop_daemon; then
    echo "Desktop preflight failed: ${DESKTOP_REASON}"
  fi
fi

echo "Checking iOS simulator readiness..."
detect_ios_device

echo "Desktop enabled=${DESKTOP_ENABLED}; iOS enabled=${IOS_ENABLED} (${IOS_REASON})"

if [[ ${DESKTOP_ENABLED} -eq 1 ]]; then
  run_case "E2E-01" "desktop" "Desktop landing contract" "e2e-01-desktop-landing.png,e2e-01-body.txt,e2e-01-state.json" case_e2e_01
  run_case "E2E-02" "desktop" "Desktop intro dismissal and grid switch" "e2e-02-desktop-grid.png,e2e-02-briefing.txt,e2e-02-state.json" case_e2e_02
  run_case "E2E-03" "desktop" "Desktop grid direct drilldown" "e2e-03-grid-drilldown.png,e2e-03-grid-body.txt" case_e2e_03
  run_case "E2E-04" "desktop" "Desktop briefing and trollbox panel toggles" "e2e-04-trollbox-panels.png,e2e-04-agent-panel.txt,e2e-04-human-panel.txt,e2e-04-panel-state.json" case_e2e_04
  run_case "E2E-05" "desktop" "Desktop dark-mode render" "e2e-05-dark.png,e2e-05-body.txt" case_e2e_05
else
  skip_case "E2E-01" "desktop" "Desktop landing contract" "e2e-01-desktop-landing.png,e2e-01-body.txt,e2e-01-state.json" "${DESKTOP_REASON}"
  skip_case "E2E-02" "desktop" "Desktop intro dismissal and grid switch" "e2e-02-desktop-grid.png,e2e-02-briefing.txt,e2e-02-state.json" "${DESKTOP_REASON}"
  skip_case "E2E-03" "desktop" "Desktop grid direct drilldown" "e2e-03-grid-drilldown.png,e2e-03-grid-body.txt" "${DESKTOP_REASON}"
  skip_case "E2E-04" "desktop" "Desktop briefing and trollbox panel toggles" "e2e-04-trollbox-panels.png,e2e-04-agent-panel.txt,e2e-04-human-panel.txt,e2e-04-panel-state.json" "${DESKTOP_REASON}"
  skip_case "E2E-05" "desktop" "Desktop dark-mode render" "e2e-05-dark.png,e2e-05-body.txt" "${DESKTOP_REASON}"
fi

if [[ ${IOS_ENABLED} -eq 1 ]]; then
  run_case "E2E-06" "ios" "iOS landing contract" "e2e-06-ios-landing.png,e2e-06-ios-body.txt,e2e-06-ios-state.json" case_e2e_06
  run_case "E2E-07" "ios" "iOS grid direct drilldown" "e2e-07-ios-grid-drilldown.png,e2e-07-ios-grid-body.txt,e2e-07-ios-state.json" case_e2e_07
  run_case "E2E-08" "ios" "iOS briefing and panel toggles" "e2e-08-ios-panels.png,e2e-08-ios-state.json" case_e2e_08
else
  skip_case "E2E-06" "ios" "iOS landing contract" "e2e-06-ios-landing.png,e2e-06-ios-body.txt,e2e-06-ios-state.json" "${IOS_REASON}"
  skip_case "E2E-07" "ios" "iOS grid direct drilldown" "e2e-07-ios-grid-drilldown.png,e2e-07-ios-grid-body.txt,e2e-07-ios-state.json" "${IOS_REASON}"
  skip_case "E2E-08" "ios" "iOS briefing and panel toggles" "e2e-08-ios-panels.png,e2e-08-ios-state.json" "${IOS_REASON}"
fi

write_summary

echo "Summary: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT}"
echo "Summary file: ${SUMMARY_FILE}"

if [[ ${REQUIRE_DESKTOP} -eq 1 && ${DESKTOP_ENABLED} -ne 1 ]]; then
  echo "FAIL: desktop matrix required but unavailable (${DESKTOP_REASON})"
  exit 1
fi

if [[ ${REQUIRE_IOS} -eq 1 && ${IOS_ENABLED} -ne 1 ]]; then
  echo "FAIL: iOS matrix required but unavailable (${IOS_REASON})"
  exit 1
fi

if [[ ${FAIL_COUNT} -gt 0 ]]; then
  exit 1
fi

exit 0
