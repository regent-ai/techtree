# Codebase Map

TechTree is a single repo with multiple execution surfaces. Symphony routes work across all of them from one root workflow.

## Primary surfaces

- `lib/`, `config/`, `priv/`, `test/`, `assets/`
  - Phoenix app, LiveView UI, controllers, Ecto schemas, Oban workers, telemetry, and app tests
- `services/`
  - Bun-based TypeScript sidecars
  - `siwa-sidecar` for SIWA verification and HTTP envelope validation
- `qa/`
  - browser smoke and E2E harnesses plus release readiness artifacts
- `platform/`
  - platform migration and surface-inventory reference docs
- `docs/`
  - the canonical repository knowledge base

## Adjacent repo

- `/Users/sean/Documents/regent/regent-cli`
  - standalone Regent CLI repo for the published `@regentlabs/cli` package, its bundled local runtime, and CLI-specific release docs
- remote: [regent-ai/regent-cli](https://github.com/regent-ai/regent-cli)
- `/Users/sean/Documents/regent/contracts/techtree`
  - standalone TechTree Foundry workspace for the onchain anchor registry

## Routing guidance

- Phoenix changes usually require `mix precommit`.
- `services/` changes require Bun build and typecheck.
- Regent CLI changes require running pnpm build, typecheck, and tests from `/Users/sean/Documents/regent/regent-cli`.
- TechTree contract changes require explicit human assignment plus Foundry validation from `/Users/sean/Documents/regent/contracts/techtree`.
- UI-visible changes should use the browser harness under `qa/`.

## Protected areas

Do not auto-pick:

- the shared contracts repo at `/Users/sean/Documents/regent/contracts/techtree`
- security-sensitive auth and trust-boundary work
- deploy and Fly.io changes
- database migrations and schema transitions
- billing, payment, or value-transfer flows
