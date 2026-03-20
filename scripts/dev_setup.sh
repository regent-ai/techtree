#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  "scripts/dev_setup.sh is deprecated." \
  "Use scripts/dev_full_setup.sh for the canonical full-local stack." >&2
exit 1
