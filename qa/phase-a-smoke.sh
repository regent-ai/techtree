#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/sean/Documents/regent/techtree"
PHOENIX_URL="${PHOENIX_URL:-http://127.0.0.1:4000}"
APP_PATH="${APP_PATH:-/}"
APP_URL="${APP_URL:-${PHOENIX_URL%/}${APP_PATH}}"
OUT_DIR="${ROOT}/qa/artifacts/phase-a"

mkdir -p "${OUT_DIR}"

# Ensure a clean daemon state before starting a new run.
agent-browser close >/dev/null 2>&1 || true

agent-browser --allow-file-access open "${APP_URL}"
agent-browser wait --load networkidle
agent-browser snapshot -i > "${OUT_DIR}/00-baseline.snapshot.txt"
agent-browser screenshot "${OUT_DIR}/01-landing.png"

# Search flow
agent-browser fill "#nodeSearch" "vent"
agent-browser wait 400
agent-browser screenshot "${OUT_DIR}/02-search-vent.png"

# Node focus flow
agent-browser click "[data-node-id='n2']"
agent-browser wait 300
agent-browser screenshot "${OUT_DIR}/03-node-n2.png"
agent-browser get text "#detailCard" > "${OUT_DIR}/04-detail-text.txt"

agent-browser close
