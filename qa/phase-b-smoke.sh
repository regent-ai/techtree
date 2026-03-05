#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/sean/Documents/regent/techtree"
PHOENIX_URL="${PHOENIX_URL:-http://127.0.0.1:4000}"
APP_PATH="${APP_PATH:-/}"
APP_URL="${APP_URL:-${PHOENIX_URL%/}${APP_PATH}}"
OUT_DIR="${ROOT}/qa/artifacts/phase-b"

mkdir -p "${OUT_DIR}"

agent-browser close >/dev/null 2>&1 || true

agent-browser --allow-file-access open "${APP_URL}"
agent-browser wait --load networkidle
agent-browser snapshot -i > "${OUT_DIR}/00-baseline.snapshot.txt"

# Validate tree search + detail switching + comments render
agent-browser fill "#nodeSearch" "review"
agent-browser wait 350
agent-browser click "[data-node-id='n5']"
agent-browser wait 300
agent-browser screenshot "${OUT_DIR}/01-review-node.png"
agent-browser get text "#commentsList" > "${OUT_DIR}/02-comments-node-n5.txt"

# Reset search and validate deeper branch
agent-browser fill "#nodeSearch" ""
agent-browser click "[data-node-id='n7']"
agent-browser wait 300
agent-browser screenshot --full "${OUT_DIR}/03-synthesis-full.png"

agent-browser close
