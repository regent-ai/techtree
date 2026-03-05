#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

if [[ -z "${LOCAL_DATABASE_URL:-}" ]]; then
  LOCAL_DATABASE_URL="ecto://${USER:-postgres}:@localhost/tech_tree_dev"
fi

export LOCAL_DATABASE_URL
export PHX_SERVER=false
export PORT="${PORT:-4010}"

echo "Using LOCAL_DATABASE_URL=$LOCAL_DATABASE_URL"

mix setup

echo "\nLocal setup complete. Start the app with:"
echo "  mix phx.server"
