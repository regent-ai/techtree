# Codebase Map

TechTree is a single repo with multiple execution surfaces. The root workflow routes work across all of them.

## Primary surfaces

- `lib/`, `config/`, `priv/`, `test/`, `assets/`
  - Phoenix app, LiveView UI, controllers, Ecto schemas, Oban workers, telemetry, and app tests
- `lib/tech_tree/platform*`, `lib/tech_tree_web/live/platform*`, and `platform_*` tables
  - Techtree operator read model for Platform-adjacent records shown inside this app. Platform remains the owner for human identity, billing, formation, and shared Regent records; any source-data change starts in the Platform-owned contract or import path.
- `services/`
  - Bun-based TypeScript sidecars
  - `siwa-sidecar` for SIWA verification and HTTP envelope validation
- `qa/`
  - browser smoke and E2E harnesses plus release readiness artifacts
- `contracts/`
  - Foundry workspace for the Techtree contracts, scripts, and tests
- `platform/`
  - platform migration and surface-inventory reference docs
- `docs/`
  - the canonical repository knowledge base

## Adjacent repo

- `/Users/sean/Documents/regent/regents-cli`
  - standalone Regents CLI repo for the published `@regentslabs/cli` package, its bundled local runtime, and CLI-specific release docs
- remote: [regents-ai/regents-cli](https://github.com/regents-ai/regents-cli)

## Routing guidance

- Phoenix changes usually require `mix precommit`.
- `services/` changes require Bun build and typecheck.
- Regents CLI changes require running pnpm build, typecheck, and tests from `/Users/sean/Documents/regent/regents-cli`.
- TechTree contract changes require explicit human assignment plus Foundry validation from `/Users/sean/Documents/regent/techtree/contracts`.
- UI-visible changes should use the browser harness under `qa/`.

## Protected areas

Do not auto-pick:

- the local Techtree contract workspace at `/Users/sean/Documents/regent/techtree/contracts`
- security-sensitive auth and trust-boundary work
- deploy and Fly.io changes
- database migrations and schema transitions
- billing, payment, or value-transfer flows
