# Codebase Map

TechTree is a single repo with multiple execution surfaces. Symphony routes work across all of them from one root workflow.

## Primary surfaces

- `lib/`, `config/`, `priv/`, `test/`, `assets/`
  - Phoenix app, LiveView UI, controllers, Ecto schemas, Oban workers, telemetry, and app tests
- `services/`
  - Bun-based TypeScript sidecars
  - `siwa-sidecar` for SIWA verification and HTTP envelope validation
- `regent-cli/`
  - pnpm workspace for the Regent CLI, runtime, and shared TS contracts
- `contracts/`
  - Foundry workspace for the onchain anchor registry
- `qa/`
  - browser smoke and E2E harnesses plus release readiness artifacts
- `platform/`
  - platform migration and surface-inventory reference docs
- `docs/`
  - the canonical repository knowledge base

## Routing guidance

- Phoenix changes usually require `mix precommit`.
- `services/` changes require Bun build and typecheck.
- `regent-cli/` changes require pnpm build, typecheck, and tests.
- `contracts/` changes require explicit human assignment plus Foundry validation.
- UI-visible changes should use the browser harness under `qa/`.

## Protected areas

Do not auto-pick:

- `contracts/`
- security-sensitive auth and trust-boundary work
- deploy and Fly.io changes
- database migrations and schema transitions
- billing, payment, or value-transfer flows
