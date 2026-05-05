# TechTree Browser QA Harness

This folder contains agent-browser command scripts for smoke and E2E coverage.

## Prerequisites

- `agent-browser` installed and available in PATH
- Run from repo root: `/Users/sean/Documents/regent`
- Phoenix server running at `http://127.0.0.1:4001` (or your override)
- Browser target URL defaults to:
  - `PHOENIX_URL=http://127.0.0.1:4001`
  - `APP_PATH=/`
  - resolved as `APP_URL="${PHOENIX_URL%/}${APP_PATH}"`
- Override with `APP_URL` directly when needed.
- The scripts close any existing daemon at start for consistent runs.

## Scripts

- `phase-c-smoke.sh`: Deterministic anonymous/public chatbox checks, live fixture-driven node assertions, and tree/detail independence checks
  - Uses isolated `HOME` at `qa/.agent-browser-home`; the script auto-installs Playwright Chromium there on first run.
- `phase-d-browser-e2e.sh`: Final executable desktop + optional iOS E2E matrix runner with per-case logging and assertions
  - Uses isolated `HOME` at `qa/.agent-browser-home`
  - Auto-installs Playwright Chromium into isolated `HOME` if missing
  - Runs desktop preflight before matrix execution:
    - validates required tools (`curl`, `rg`, `jq`, `npx`, `agent-browser`)
    - waits for live app readiness (`APP_READY_TIMEOUT_SEC`, default 45s)
    - extracts dynamic node fixture data for deterministic assertions on live Phoenix content
  - Marks desktop cases `SKIP` only when browser launch/preflight is unavailable
  - Auto-detects iOS simulator readiness and marks iOS cases `SKIP` when prerequisites are unavailable
  - Gate controls:
    - `REQUIRE_DESKTOP=1` (default): fail run when desktop preflight is unavailable
    - `REQUIRE_IOS=0` (default): allow iOS skips; iOS is non-blocking for the first prod deploy
  - URL controls:
    - `APP_URL` (highest priority)
    - `PHOENIX_URL` (default `http://127.0.0.1:4001`)
    - `APP_PATH` (default `/`)
- `final-e2e-matrix.md`: Matrix reference for the final runner and artifact map
- `manual-authenticated-chatbox-signoff.md`: Release-gate checklist for the manual Privy sign-in flow and required authenticated chatbox artifacts

## Active lanes

- Use `phase-c-smoke.sh` and desktop `phase-d-browser-e2e.sh` for launch evidence.
- Complete `manual-authenticated-chatbox-signoff.md` alongside the automated browser artifacts before prod deploy.

## Artifacts

Screenshots and snapshots are written to:

- `techtree/qa/artifacts/phase-c/` (includes assertion text artifacts such as `99-assertions.txt`)
- `techtree/qa/artifacts/final/`
  - Per-run summary: `<UTC_STAMP>.summary.md`
  - Per-run status table: `<UTC_STAMP>.status.tsv`
  - Case logs: `logs/E2E-01.log ... logs/E2E-08.log`
- `techtree/qa/artifacts/authenticated/<UTC_STAMP>/`
  - Manual authenticated chatbox signoff bundle described in `manual-authenticated-chatbox-signoff.md`

## SIWA status (current)

- SIWA sidecar enforces cryptographic verification in this repo:
  - `/v1/verify` validates EVM `personal_sign` signatures against the caller wallet and consumes nonce.
  - `/v1/http-verify` validates signed SIWA receipt + HTTP signature envelope and binds headers to receipt claims.
- Operational prerequisite: `cast` must be available for signature verification in sidecar runtime.
