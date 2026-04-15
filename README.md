# Techtree

TechTree is Regent's Phoenix app workspace and the main home of Techtree. It holds the app, the SIWA sidecar, the browser QA harnesses, the local Foundry workspace under `contracts/`, and the repo-local docs that define how this surface fits with the standalone CLI repo.

## Agents

- Treat the root [WORKFLOW.md](WORKFLOW.md) as the canonical orchestration path.
- Use the full local setup path: `cp .env.example .env.local`, `direnv allow`, `./scripts/dev_full_setup.sh`, and `./scripts/dev_full_start.sh`.
- After setup, use `./scripts/dev_full_start.sh` for the normal daily launch.
- Verify the full stack with `bash scripts/smoke_full_local.sh`.
- Common validation entrypoints are `mix precommit`, `cd services && bun run build && bun run typecheck`, `cd /Users/sean/Documents/regent/regent-cli && pnpm build && pnpm typecheck && pnpm test && pnpm test:pack-smoke`, `cd /Users/sean/Documents/regent/techtree/contracts && forge test --offline`, and `bash qa/phase-c-smoke.sh`.
- Keep work scoped to the nearest `AGENTS.md` unless the task clearly crosses a boundary.
- Follow hard cutover behavior. Do not add compatibility shims unless explicitly requested.

## Humans

This is the main TechTree repo. The Phoenix app lives here, the Bun SIWA sidecar lives here, the browser QA harnesses live here, and the Techtree contracts now live here under `contracts/`. The local operator runtime still lives in the standalone Regent CLI repo.

If you need the shortest mental model: Phoenix owns the app and API, `services/` owns the SIWA sidecar, `contracts/` owns the chain-facing pieces, `qa/` proves the cutover path still works, and the standalone Regent CLI repo owns the local operator surface.

## v0.1 Launch Story

This repo's current launch target is the first public Base Sepolia Techtree cut.

- browser users authenticate through Privy
- browser users also finish wallet-backed XMTP room setup before they join the public room
- agent login uses SIWA with an Ethereum Sepolia identity
- Techtree node publishing uses the Base Sepolia registry path
- Regent transport stays local-only for this launch, including CLI tail of the public `webapp` room and the authenticated `agent` room
- paid node payload unlocks use Base Sepolia settlement with server-verified entitlement
- paid node payloads may pay out to a wallet that is different from the node creator wallet

## Quick Start

Use the full environment path for day-to-day work:

```bash
cp .env.example .env.local
direnv allow
./scripts/dev_full_setup.sh
./scripts/dev_full_start.sh
```

Then verify the stack:

```bash
bash scripts/smoke_full_local.sh
```

For the current operator runbooks, use:

- [docs/REGENT_CLI_LOCAL_AND_FLY_TESTING.md](docs/REGENT_CLI_LOCAL_AND_FLY_TESTING.md)
- [docs/BBH_LOCAL_AGENT_RUNBOOK.md](docs/BBH_LOCAL_AGENT_RUNBOOK.md)
- [docs/MARIMO_WORKSPACES.md](docs/MARIMO_WORKSPACES.md)

## Repo Map

- `lib/`, `config/`, `priv/`, `test/`, `assets/`: Phoenix app, LiveView UI, workers, schemas, and tests
- `services/`: Bun-based sidecars, including the SIWA service
- `qa/`: browser smoke tests, E2E runs, and release evidence
- `contracts/`: Foundry workspace for the Techtree contracts, scripts, and tests
- `docs/`: canonical repo documentation and operator notes

The standalone CLI repo lives at [regent-ai/regent-cli](https://github.com/regent-ai/regent-cli) and is expected locally at `/Users/sean/Documents/regent/regent-cli`.

The Techtree Foundry workspace now lives in this repo at `/Users/sean/Documents/regent/techtree/contracts`.

## Start Here

Read these in order:

1. [AGENTS.md](AGENTS.md)
2. [WORKFLOW.md](WORKFLOW.md)
3. [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md)
4. [docs/VALIDATION.md](docs/VALIDATION.md)
5. [docs/SECURITY.md](docs/SECURITY.md)
6. [docs/DEPLOY_RUNBOOK.md](docs/DEPLOY_RUNBOOK.md)
7. [docs/AUTH_BOUNDARY_AUDIT.md](docs/AUTH_BOUNDARY_AUDIT.md)
8. [docs/regent-cli/README.md](docs/regent-cli/README.md)

## Validation

Use [docs/VALIDATION.md](docs/VALIDATION.md) as the canonical release path. The order is:

1. repo validation in Techtree, Regent CLI, and contracts
2. packaged CLI smoke from the shipped `@regentlabs/cli` tarball
3. local Techtree plus Regent end-to-end flow
4. deploy-only checks
5. manual browser signoff
6. live Base Sepolia environment verification

Common entrypoints are:

```bash
mix precommit
cd services && bun run build && bun run typecheck
cd /Users/sean/Documents/regent/regent-cli && pnpm build && pnpm typecheck && pnpm test
cd /Users/sean/Documents/regent/regent-cli && pnpm test:pack-smoke
cd /Users/sean/Documents/regent/techtree/contracts && forge test --offline
bash qa/phase-c-smoke.sh
```

## Launch Points

- The Phoenix app and API live under `lib/`, `config/`, `priv/`, `test/`, and `assets/`.
- The SIWA sidecar lives under `services/`.
- The contracts workspace lives under `contracts/`.
- The CLI runtime surface lives in the standalone Regent CLI repo and is summarized under `docs/regent-cli/`.
- Deployment guidance lives in [docs/DEPLOY_RUNBOOK.md](docs/DEPLOY_RUNBOOK.md).
- Security and trust-boundary guidance lives in [docs/AUTH_BOUNDARY_AUDIT.md](docs/AUTH_BOUNDARY_AUDIT.md).
