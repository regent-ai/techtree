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

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

DESKTOP_ENABLED=1
DESKTOP_REASON=""

IOS_ENABLED=0
IOS_REASON="not checked"
IOS_DEVICE_SELECTED=""

RESULT_ROWS=()

FIXTURE_FILE="${OUT_DIR}/${RUN_STAMP}.fixture.json"
BASE_NODE_ID=""
BASE_NODE_TITLE=""
ALT_NODE_ID=""
ALT_NODE_TITLE=""
COMMENTS_NODE_ID=""
COMMENTS_NODE_TITLE=""
TROLLBOX_PRESENT=0

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

wait_for_contains_desktop() {
  local selector="$1"
  local expected="$2"
  local outfile="$3"
  local attempts="${4:-40}"
  local delay_ms="${5:-150}"

  local i
  for ((i = 1; i <= attempts; i++)); do
    ab get text "${selector}" > "${outfile}"
    if rg -Fq "${expected}" "${outfile}"; then
      return 0
    fi
    ab wait "${delay_ms}"
  done

  echo "ASSERT FAIL: desktop selector ${selector} never contained '${expected}'" >&2
  cat "${outfile}" >&2 || true
  return 1
}

LAST_WAIT_MATCH=""

wait_for_any_contains_desktop() {
  local selector="$1"
  local outfile="$2"
  local attempts="${3:-40}"
  local delay_ms="${4:-150}"
  shift 4
  local expected_values=("$@")

  local i
  local expected
  LAST_WAIT_MATCH=""

  for ((i = 1; i <= attempts; i++)); do
    ab get text "${selector}" > "${outfile}"
    for expected in "${expected_values[@]}"; do
      if rg -Fq "${expected}" "${outfile}"; then
        LAST_WAIT_MATCH="${expected}"
        return 0
      fi
    done
    ab wait "${delay_ms}"
  done

  echo "ASSERT FAIL: desktop selector ${selector} never matched expected states: ${expected_values[*]}" >&2
  cat "${outfile}" >&2 || true
  return 1
}

wait_for_contains_ios() {
  local selector="$1"
  local expected="$2"
  local outfile="$3"
  local attempts="${4:-60}"
  local delay_ms="${5:-180}"

  local i
  for ((i = 1; i <= attempts; i++)); do
    ab_ios get text "${selector}" > "${outfile}"
    if rg -Fq "${expected}" "${outfile}"; then
      return 0
    fi
    ab_ios wait "${delay_ms}"
  done

  echo "ASSERT FAIL: ios selector ${selector} never contained '${expected}'" >&2
  cat "${outfile}" >&2 || true
  return 1
}

wait_for_any_contains_ios() {
  local selector="$1"
  local outfile="$2"
  local attempts="${3:-60}"
  local delay_ms="${4:-180}"
  shift 4
  local expected_values=("$@")

  local i
  local expected
  LAST_WAIT_MATCH=""

  for ((i = 1; i <= attempts; i++)); do
    ab_ios get text "${selector}" > "${outfile}"
    for expected in "${expected_values[@]}"; do
      if rg -Fq "${expected}" "${outfile}"; then
        LAST_WAIT_MATCH="${expected}"
        return 0
      fi
    done
    ab_ios wait "${delay_ms}"
  done

  echo "ASSERT FAIL: ios selector ${selector} never matched expected states: ${expected_values[*]}" >&2
  cat "${outfile}" >&2 || true
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
  local node_count

  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}" > "${fixture_log}" 2>&1
  wait_for_page_load_desktop >> "${fixture_log}" 2>&1 || true
  ab eval 'JSON.stringify((() => {
    const nodes = Array.from(document.querySelectorAll("[data-node-id]")).map((el) => {
      const title = (el.textContent || "").replace(/\s+/g, " ").trim();
      return { id: el.getAttribute("data-node-id"), title };
    }).filter((n) => n.id && n.title);
    return {
      nodes,
      hasSearch: !!document.querySelector("#nodeSearch"),
      hasDetailCard: !!document.querySelector("#detailCard"),
      hasCommentsList: !!document.querySelector("#commentsList"),
      hasTrollbox: !!document.querySelector("#trollboxAccess")
    };
  })())' > "${FIXTURE_FILE}" 2>>"${fixture_log}"
  ab close >> "${fixture_log}" 2>&1 || true

  if ! jq -e . "${FIXTURE_FILE}" >/dev/null 2>&1; then
    echo "desktop fixture extraction failed: invalid fixture JSON (see $(basename "${fixture_log}"))" >&2
    return 1
  fi

  if [[ "$(jq -r '.hasDetailCard' "${FIXTURE_FILE}")" != "true" ]]; then
    echo "desktop fixture extraction failed: #detailCard missing in live app (see $(basename "${fixture_log}"))" >&2
    return 1
  fi

  node_count="$(jq -r '.nodes | length' "${FIXTURE_FILE}")"
  if [[ "${node_count}" -lt 1 ]]; then
    echo "desktop fixture extraction failed: no [data-node-id] elements found (see $(basename "${fixture_log}"))" >&2
    return 1
  fi

  BASE_NODE_ID="$(jq -r '.nodes[0].id // empty' "${FIXTURE_FILE}")"
  BASE_NODE_TITLE="$(jq -r '.nodes[0].title // empty' "${FIXTURE_FILE}")"
  ALT_NODE_ID="$(jq -r '.nodes[1].id // .nodes[0].id // empty' "${FIXTURE_FILE}")"
  ALT_NODE_TITLE="$(jq -r '.nodes[1].title // .nodes[0].title // empty' "${FIXTURE_FILE}")"
  COMMENTS_NODE_ID="${ALT_NODE_ID}"
  COMMENTS_NODE_TITLE="${ALT_NODE_TITLE}"
  TROLLBOX_PRESENT="$(jq -r '.hasTrollbox | if . then 1 else 0 end' "${FIXTURE_FILE}")"

  if [[ -z "${BASE_NODE_ID}" || -z "${BASE_NODE_TITLE}" || -z "${ALT_NODE_ID}" || -z "${ALT_NODE_TITLE}" ]]; then
    echo "desktop fixture extraction failed: unable to derive deterministic node fixtures (see ${FIXTURE_FILE})" >&2
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
    DESKTOP_REASON="live page fixture preflight failed (see $(basename "${probe_log}"))"
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
  ab screenshot "${OUT_DIR}/e2e-01-desktop-landing.png"
  ab get text "#detailCard" > "${OUT_DIR}/e2e-01-detail.txt"
  assert_contains "${OUT_DIR}/e2e-01-detail.txt" "${BASE_NODE_TITLE}" "default selected node detail should match live first node title"
  ab close
}

case_e2e_02() {
  local search_query

  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop

  search_query="$(printf "%s" "${ALT_NODE_TITLE}" | cut -d' ' -f1)"
  if [[ -n "${search_query}" ]]; then
    ab fill "#nodeSearch" "${search_query}"
  fi

  ab click "[data-node-id='${ALT_NODE_ID}']"
  wait_for_contains_desktop "#detailCard" "${ALT_NODE_TITLE}" "${OUT_DIR}/e2e-02-detail.txt" 50 120
  ab screenshot "${OUT_DIR}/e2e-02-desktop-skill.png"
  ab get text "#detailCard" > "${OUT_DIR}/e2e-02-detail.txt"
  assert_contains "${OUT_DIR}/e2e-02-detail.txt" "${ALT_NODE_TITLE}" "selected live node detail after search"
  ab close
}

case_e2e_03() {
  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop
  ab click "[data-node-id='${COMMENTS_NODE_ID}']"
  wait_for_contains_desktop "#detailCard" "${COMMENTS_NODE_TITLE}" "${OUT_DIR}/e2e-03-detail.txt" 50 120
  ab screenshot "${OUT_DIR}/e2e-03-comments.png"
  ab get text "#commentsList" > "${OUT_DIR}/e2e-03-comments.txt"
  assert_not_contains "${OUT_DIR}/e2e-03-comments.txt" "undefined" "comments pane should not render undefined content"
  assert_not_contains "${OUT_DIR}/e2e-03-comments.txt" "null" "comments pane should not render null literals"
  ab close
}

case_e2e_04() {
  local post_text="phase-d desktop matrix ping"
  local membership_file="${OUT_DIR}/e2e-04-access-member.txt"

  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop
  ab click "[data-node-id='${ALT_NODE_ID}']"
  wait_for_contains_desktop "#detailCard" "${ALT_NODE_TITLE}" "${OUT_DIR}/e2e-04-detail.txt" 50 120
  ab click "#trollboxJoin"

  wait_for_any_contains_desktop \
    "#trollboxAccess" \
    "${membership_file}" \
    60 \
    150 \
    "membership: member" \
    "membership: pending" \
    "state: join_pending"

  if [[ "${LAST_WAIT_MATCH}" == "membership: member" ]]; then
    ab fill "#trollboxInput" "${post_text}"
    ab click "#trollboxSend"
    wait_for_contains_desktop "#trollboxFeed" "${post_text}" "${OUT_DIR}/e2e-04-trollbox-feed.txt" 40 120
    ab get text "#trollboxFeed" > "${OUT_DIR}/e2e-04-trollbox-feed.txt"
    assert_contains "${OUT_DIR}/e2e-04-trollbox-feed.txt" "${post_text}" "desktop trollbox post visible after membership grant"
  else
    assert_contains "${membership_file}" "pending" "desktop trollbox join should transition to pending when membership grant is unavailable"
    printf "membership state remained pending; compose assertion intentionally gated\n" > "${OUT_DIR}/e2e-04-trollbox-feed.txt"
  fi

  ab screenshot "${OUT_DIR}/e2e-04-trollbox-compose.png"
  ab close
}

case_e2e_05() {
  ab close >/dev/null 2>&1 || true
  ab --allow-file-access open "${APP_URL}"
  wait_for_page_load_desktop
  ab set media dark
  ab wait 250
  ab screenshot "${OUT_DIR}/e2e-05-dark.png"
  ab close
}

case_e2e_06() {
  ab_ios close >/dev/null 2>&1 || true
  ab_ios --allow-file-access open "${APP_URL}"
  wait_for_page_load_ios
  ab_ios screenshot "${OUT_DIR}/e2e-06-ios-landing.png"
  ab_ios get text "#detailCard" > "${OUT_DIR}/e2e-06-ios-detail.txt"
  assert_contains "${OUT_DIR}/e2e-06-ios-detail.txt" "${BASE_NODE_TITLE}" "ios default selected node detail should match live first node title"
  ab_ios close
}

case_e2e_07() {
  local search_query

  ab_ios close >/dev/null 2>&1 || true
  ab_ios --allow-file-access open "${APP_URL}"
  wait_for_page_load_ios
  search_query="$(printf "%s" "${ALT_NODE_TITLE}" | cut -d' ' -f1)"
  if [[ -n "${search_query}" ]]; then
    ab_ios fill "#nodeSearch" "${search_query}"
  fi
  ab_ios tap "[data-node-id='${ALT_NODE_ID}']"
  wait_for_contains_ios "#detailCard" "${ALT_NODE_TITLE}" "${OUT_DIR}/e2e-07-ios-detail.txt" 70 160
  ab_ios screenshot "${OUT_DIR}/e2e-07-ios-meta.png"
  ab_ios get text "#detailCard" > "${OUT_DIR}/e2e-07-ios-detail.txt"
  assert_contains "${OUT_DIR}/e2e-07-ios-detail.txt" "${ALT_NODE_TITLE}" "ios selected live node detail after search"
  ab_ios close
}

case_e2e_08() {
  local post_text="phase-d ios matrix ping"
  local membership_file="${OUT_DIR}/e2e-08-access-member.txt"

  ab_ios close >/dev/null 2>&1 || true
  ab_ios --allow-file-access open "${APP_URL}"
  wait_for_page_load_ios
  ab_ios tap "[data-node-id='${ALT_NODE_ID}']"
  wait_for_contains_ios "#detailCard" "${ALT_NODE_TITLE}" "${OUT_DIR}/e2e-08-detail.txt" 70 160
  ab_ios tap "#trollboxJoin"

  wait_for_any_contains_ios \
    "#trollboxAccess" \
    "${membership_file}" \
    80 \
    180 \
    "membership: member" \
    "membership: pending" \
    "state: join_pending"

  if [[ "${LAST_WAIT_MATCH}" == "membership: member" ]]; then
    ab_ios fill "#trollboxInput" "${post_text}"
    ab_ios tap "#trollboxSend"
    wait_for_contains_ios "#trollboxFeed" "${post_text}" "${OUT_DIR}/e2e-08-ios-feed.txt" 60 180
    ab_ios get text "#trollboxFeed" > "${OUT_DIR}/e2e-08-ios-feed.txt"
    assert_contains "${OUT_DIR}/e2e-08-ios-feed.txt" "${post_text}" "ios trollbox post visible after membership grant"
  else
    assert_contains "${membership_file}" "pending" "ios trollbox join should transition to pending when membership grant is unavailable"
    printf "membership state remained pending; compose assertion intentionally gated\n" > "${OUT_DIR}/e2e-08-ios-feed.txt"
  fi

  ab_ios screenshot "${OUT_DIR}/e2e-08-ios-trollbox.png"
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
      echo "- Base node fixture: ${BASE_NODE_ID} (${BASE_NODE_TITLE})"
      echo "- Alt node fixture: ${ALT_NODE_ID} (${ALT_NODE_TITLE})"
      echo "- Trollbox present: ${TROLLBOX_PRESENT}"
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
  run_case "E2E-01" "desktop" "Desktop default scheme" "e2e-01-desktop-landing.png,e2e-01-detail.txt" case_e2e_01
  run_case "E2E-02" "desktop" "Desktop search + selection" "e2e-02-desktop-skill.png,e2e-02-detail.txt" case_e2e_02
  run_case "E2E-03" "desktop" "Desktop comments/read path" "e2e-03-comments.png,e2e-03-comments.txt,e2e-03-detail.txt" case_e2e_03
  run_case "E2E-04" "desktop" "Desktop trollbox compose" "e2e-04-trollbox-compose.png,e2e-04-access-member.txt,e2e-04-trollbox-feed.txt" case_e2e_04
  run_case "E2E-05" "desktop" "Desktop dark-mode render" "e2e-05-dark.png" case_e2e_05
else
  skip_case "E2E-01" "desktop" "Desktop default scheme" "e2e-01-desktop-landing.png,e2e-01-detail.txt" "${DESKTOP_REASON}"
  skip_case "E2E-02" "desktop" "Desktop search + selection" "e2e-02-desktop-skill.png,e2e-02-detail.txt" "${DESKTOP_REASON}"
  skip_case "E2E-03" "desktop" "Desktop comments/read path" "e2e-03-comments.png,e2e-03-comments.txt,e2e-03-detail.txt" "${DESKTOP_REASON}"
  skip_case "E2E-04" "desktop" "Desktop trollbox compose" "e2e-04-trollbox-compose.png,e2e-04-access-member.txt,e2e-04-trollbox-feed.txt" "${DESKTOP_REASON}"
  skip_case "E2E-05" "desktop" "Desktop dark-mode render" "e2e-05-dark.png" "${DESKTOP_REASON}"
fi

if [[ ${IOS_ENABLED} -eq 1 ]]; then
  run_case "E2E-06" "ios" "iOS Safari baseline" "e2e-06-ios-landing.png,e2e-06-ios-detail.txt" case_e2e_06
  run_case "E2E-07" "ios" "iOS search + node detail" "e2e-07-ios-meta.png,e2e-07-ios-detail.txt" case_e2e_07
  run_case "E2E-08" "ios" "iOS trollbox" "e2e-08-ios-trollbox.png,e2e-08-access-member.txt,e2e-08-ios-feed.txt" case_e2e_08
else
  skip_case "E2E-06" "ios" "iOS Safari baseline" "e2e-06-ios-landing.png,e2e-06-ios-detail.txt" "${IOS_REASON}"
  skip_case "E2E-07" "ios" "iOS search + node detail" "e2e-07-ios-meta.png,e2e-07-ios-detail.txt" "${IOS_REASON}"
  skip_case "E2E-08" "ios" "iOS trollbox" "e2e-08-ios-trollbox.png,e2e-08-access-member.txt,e2e-08-ios-feed.txt" "${IOS_REASON}"
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
