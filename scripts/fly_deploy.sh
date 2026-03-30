#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "scripts/fly_deploy.sh is deprecated; forwarding to scripts/fly_deploy_stack.sh"
exec "${ROOT_DIR}/scripts/fly_deploy_stack.sh"
