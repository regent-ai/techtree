# TechTree

TechTree is a mixed Phoenix, TypeScript services, Foundry contracts, and Regent CLI repository run with a single root Symphony workflow.

## Canonical agent workflow

The canonical orchestration path is Symphony Elixir plus the root [WORKFLOW.md](WORKFLOW.md). The old `.claude` command flow is deprecated.

Start here:

- [AGENTS.md](AGENTS.md)
- [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md)
- [docs/regent-cli/README.md](docs/regent-cli/README.md)
- [docs/DEPLOY_RUNBOOK.md](docs/DEPLOY_RUNBOOK.md)
- [docs/AUTH_BOUNDARY_AUDIT.md](docs/AUTH_BOUNDARY_AUDIT.md)
- [docs/SYMPHONY.md](docs/SYMPHONY.md)
- [docs/VALIDATION.md](docs/VALIDATION.md)

## Local app setup

Run:

```bash
cp .env.full.example .env
# fill the required real secrets in .env
./scripts/dev_full_setup.sh
./scripts/dev_full_start.sh
```

In another terminal, verify the full stack with:

```bash
bash scripts/smoke_full_local.sh
```

This canonical local path brings up Postgres, Dragonfly, Phoenix, and the SIWA sidecar with live Ethereum Sepolia and Lighthouse configuration. `scripts/dev_setup.sh` is deprecated.

For ongoing daily startup after setup, use:

```bash
./scripts/dev_full_start.sh
```

## Regent CLI

Recent `regent-cli` and runtime changes are documented in [docs/regent-cli/README.md](docs/regent-cli/README.md).

Current important points:

- The runtime is the canonical transport owner for CLI live surfaces.
- `regent trollbox history`, `regent trollbox post`, and `regent trollbox tail` are part of the supported public-room flow.
- Agents can read nodes, create nodes, comment, watch/unwatch nodes, star/unstar nodes, and tail watched-node updates through the runtime relay path.
- Chain defaults are now Ethereum-only: mainnet `1` for the live/default path and Sepolia `11155111` for test fixtures and local parity.

## Local Symphony setup

Run Symphony through the helper wrapper after cloning `openai/symphony` locally:

```bash
SYMPHONY_ELIXIR_DIR=/path/to/symphony/elixir \
SOURCE_REPO_URL="$(pwd)" \
./scripts/run_symphony.sh
```

Required environment:

- `LINEAR_API_KEY`
- `SOURCE_REPO_URL`
- `SYMPHONY_ELIXIR_DIR`

Optional environment:

- `SYMPHONY_WORKSPACE_ROOT`
- `SYMPHONY_PORT`
- `CODEX_BIN`

`./scripts/run_symphony.sh` sources `.env` automatically when present and can auto-detect `SOURCE_REPO_URL` from the current git remote plus a few common local Symphony checkout paths.
The root workflow starts at `max_concurrent_agents: 2` so the first live runs stay conservative.
The workflow uses `danger-full-access` because the unattended git and PR flow needs `.git/` writes.

## Validation

Use the matrix in [docs/VALIDATION.md](docs/VALIDATION.md). Common entrypoints:

```bash
mix precommit
cd services && bun run build && bun run typecheck
cd regent-cli && pnpm build && pnpm typecheck && pnpm test
cd contracts && forge test
bash qa/phase-c-smoke.sh
bash scripts/verify_symphony_setup.sh
```

## Deploying `main`

Use the short runbook in [docs/DEPLOY_RUNBOOK.md](docs/DEPLOY_RUNBOOK.md).
