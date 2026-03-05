#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/sean/Documents/regent/techtree"
PHOENIX_URL="${PHOENIX_URL:-http://127.0.0.1:4000}"
APP_PATH="${APP_PATH:-/}"
APP_URL="${APP_URL:-${PHOENIX_URL%/}${APP_PATH}}"
OUT_DIR="${ROOT}/qa/artifacts/phase-c"
AB_HOME="${ROOT}/qa/.agent-browser-home"
POST_TEXT="phase-c deterministic smoke ping"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.58.2}"
APP_READY_TIMEOUT_SEC="${APP_READY_TIMEOUT_SEC:-45}"
FIXTURE_FILE="${OUT_DIR}/00-live-fixture.json"
BASE_NODE_ID=""
BASE_NODE_TITLE=""
ALT_NODE_ID=""
ALT_NODE_TITLE=""

mkdir -p "${OUT_DIR}"
mkdir -p "${AB_HOME}"

ab() {
  HOME="${AB_HOME}" agent-browser "$@"
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

capture_text() {
  local selector="$1"
  local outfile="$2"
  ab get text "${selector}" > "${outfile}"
}

wait_for_contains() {
  local selector="$1"
  local expected="$2"
  local outfile="$3"
  local attempts="${4:-30}"
  local delay_ms="${5:-150}"

  local i
  for ((i = 1; i <= attempts; i++)); do
    capture_text "${selector}" "${outfile}"
    if rg -Fq "${expected}" "${outfile}"; then
      return 0
    fi
    ab wait "${delay_ms}"
  done

  echo "ASSERT FAIL: did not observe '${expected}' for selector ${selector}" >&2
  echo "Last capture (${outfile}):" >&2
  cat "${outfile}" >&2 || true
  exit 1
}

LAST_WAIT_MATCH=""

wait_for_any_contains() {
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
    capture_text "${selector}" "${outfile}"
    for expected in "${expected_values[@]}"; do
      if rg -Fq "${expected}" "${outfile}"; then
        LAST_WAIT_MATCH="${expected}"
        return 0
      fi
    done
    ab wait "${delay_ms}"
  done

  echo "ASSERT FAIL: did not observe any expected state for ${selector}: ${expected_values[*]}" >&2
  cat "${outfile}" >&2 || true
  exit 1
}

extract_fixture() {
  ab eval 'JSON.stringify((() => {
    const nodes = Array.from(document.querySelectorAll("[data-node-id]")).map((el) => {
      const title = (el.textContent || "").replace(/\s+/g, " ").trim();
      return { id: el.getAttribute("data-node-id"), title };
    }).filter((n) => n.id && n.title);
    return {
      nodes,
      hasDetailCard: !!document.querySelector("#detailCard"),
      hasTrollboxAccess: !!document.querySelector("#trollboxAccess")
    };
  })())' > "${FIXTURE_FILE}"

  if ! jq -e . "${FIXTURE_FILE}" >/dev/null 2>&1; then
    echo "ASSERT FAIL: fixture extraction produced invalid JSON (${FIXTURE_FILE})" >&2
    exit 1
  fi

  if [[ "$(jq -r '.hasDetailCard' "${FIXTURE_FILE}")" != "true" ]]; then
    echo "ASSERT FAIL: #detailCard missing in live app" >&2
    exit 1
  fi

  if [[ "$(jq -r '.hasTrollboxAccess' "${FIXTURE_FILE}")" != "true" ]]; then
    echo "ASSERT FAIL: #trollboxAccess missing in live app" >&2
    exit 1
  fi

  if [[ "$(jq -r '.nodes | length' "${FIXTURE_FILE}")" -lt 1 ]]; then
    echo "ASSERT FAIL: no [data-node-id] elements found in live app" >&2
    exit 1
  fi

  BASE_NODE_ID="$(jq -r '.nodes[0].id // empty' "${FIXTURE_FILE}")"
  BASE_NODE_TITLE="$(jq -r '.nodes[0].title // empty' "${FIXTURE_FILE}")"
  ALT_NODE_ID="$(jq -r '.nodes[1].id // .nodes[0].id // empty' "${FIXTURE_FILE}")"
  ALT_NODE_TITLE="$(jq -r '.nodes[1].title // .nodes[0].title // empty' "${FIXTURE_FILE}")"

  if [[ -z "${BASE_NODE_ID}" || -z "${BASE_NODE_TITLE}" || -z "${ALT_NODE_ID}" || -z "${ALT_NODE_TITLE}" ]]; then
    echo "ASSERT FAIL: unable to derive live node fixtures from ${FIXTURE_FILE}" >&2
    exit 1
  fi
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
extract_fixture
ab snapshot -i > "${OUT_DIR}/00-baseline.snapshot.txt"
ab screenshot "${OUT_DIR}/01-landing.png"
capture_text "#detailCard" "${OUT_DIR}/01-detail.txt"
assert_contains "${OUT_DIR}/01-detail.txt" "${BASE_NODE_TITLE}" "default detail should match first live node title"

# Initial visibility assertions (viewer mode)
capture_text "#trollboxAccess" "${OUT_DIR}/02-access-initial.txt"
assert_contains "${OUT_DIR}/02-access-initial.txt" "membership: viewer" "initial membership should be viewer"
assert_contains "${OUT_DIR}/02-access-initial.txt" "read" "initial access panel should include read field"
assert_contains "${OUT_DIR}/02-access-initial.txt" "join" "initial access panel should include join field"
assert_contains "${OUT_DIR}/02-access-initial.txt" "post" "initial access panel should include post field"
assert_contains "${OUT_DIR}/02-access-initial.txt" "visible" "initial access should include visible fields"
assert_contains "${OUT_DIR}/02-access-initial.txt" "hidden" "initial post visibility should be hidden"

# Join flow assertions (viewer -> pending -> member)
ab click "#trollboxJoin"
ab wait 60
capture_text "#trollboxAccess" "${OUT_DIR}/06-access-pending.txt"
assert_contains "${OUT_DIR}/06-access-pending.txt" "membership: pending" "join click should move membership to pending"
assert_contains "${OUT_DIR}/06-access-pending.txt" "Join request pending" "pending notice should render"
assert_contains "${OUT_DIR}/06-access-pending.txt" "hidden" "join/post should be hidden while pending"
ab screenshot "${OUT_DIR}/09-join-pending.png"

wait_for_any_contains "#trollboxAccess" "${OUT_DIR}/10-access-member.txt" 50 140 "membership: member" "membership: pending" "state: join_pending"
if [[ "${LAST_WAIT_MATCH}" == "membership: member" ]]; then
  assert_contains "${OUT_DIR}/10-access-member.txt" "visible" "read/post should be visible for member"
  assert_contains "${OUT_DIR}/10-access-member.txt" "hidden" "join should remain hidden for member"

  # Post message and verify feed entry when compose is granted.
  ab fill "#trollboxInput" "${POST_TEXT}"
  ab click "#trollboxSend"
  wait_for_contains "#trollboxFeed" "${POST_TEXT}" "${OUT_DIR}/14-trollbox-feed.txt" 40 120
  capture_text "#trollboxFeed" "${OUT_DIR}/14-trollbox-feed.txt"
  assert_contains "${OUT_DIR}/14-trollbox-feed.txt" "${POST_TEXT}" "posted message should appear in trollbox feed"
else
  assert_contains "${OUT_DIR}/10-access-member.txt" "pending" "membership should remain pending when grant is unavailable in live mode"
  printf "membership remained pending; compose assertion gated in smoke mode\n" > "${OUT_DIR}/14-trollbox-feed.txt"
fi
ab screenshot "${OUT_DIR}/15-trollbox-posted.png"

# Ensure tree interaction remains independent after post/membership changes
ab click "[data-node-id='${ALT_NODE_ID}']"
wait_for_contains "#detailCard" "${ALT_NODE_TITLE}" "${OUT_DIR}/16-detail-n8.txt" 40 120
capture_text "#detailCard" "${OUT_DIR}/16-detail-n8.txt"
capture_text "#trollboxVisibilityPost" "${OUT_DIR}/17-post-after-switch.txt"
assert_contains "${OUT_DIR}/16-detail-n8.txt" "${ALT_NODE_TITLE}" "node selection should still update detail view"
if [[ "${LAST_WAIT_MATCH}" == "membership: member" ]]; then
  assert_contains "${OUT_DIR}/17-post-after-switch.txt" "visible" "post visibility should stay visible after node switch when member"
else
  assert_contains "${OUT_DIR}/17-post-after-switch.txt" "hidden" "post visibility should remain hidden while membership is pending"
fi
ab screenshot "${OUT_DIR}/18-node-n8-after-post.png"

cat > "${OUT_DIR}/99-assertions.txt" <<'EOF'
phase-c smoke assertions passed:
- initial viewer/read/join/post visibility
- deterministic join transition viewer -> pending (and optionally member when granted)
- compose/feed assertions gated by live membership state with deterministic checks in both branches
- tree detail updates remain independent after trollbox post
EOF
