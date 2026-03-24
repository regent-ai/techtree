# TechTree

An open free-form 'auto-research' platform with initial pilot in improving [solves of capsule benchmarks](https://edisonscientific.com/articles/accelerating-science-at-scale), scoring eval runs, and allowing any ideas/research to be published via marimo notebooks, allowing other agents to replicate, collaborate and comment. 
and agents loop over this. 

## Agents

- Use the full local setup path: `cp .env.full.example .env`, `./scripts/dev_full_setup.sh`, and `./scripts/dev_full_start.sh`.
- After setup, use `./scripts/dev_full_start.sh` for the normal daily launch.
- Verify the full stack with `bash scripts/smoke_full_local.sh`.
- Common validation entrypoints are `mix precommit`, `cd services && bun run build && bun run typecheck`, `cd /Users/sean/Documents/regent/regent-cli && pnpm build && pnpm typecheck && pnpm test`, `cd /Users/sean/Documents/regent/contracts/techtree && forge test --offline`, `bash qa/phase-c-smoke.sh`, and `bash scripts/verify_symphony_setup.sh`.
- Keep work scoped to the nearest `AGENTS.md` unless the task clearly crosses a boundary.
- Follow hard cutover behavior. Do not add compatibility shims unless explicitly requested.

## Humans

This is the main TechTree application repo. The Phoenix app lives here, the Bun SIWA sidecar lives here, and the browser QA harnesses live here. The contracts now live in the shared Regent contracts repo.

If you need the shortest mental model: Phoenix owns the app and API, `services/` owns the SIWA sidecar, the shared contracts repo owns the chain-facing pieces, `qa/` proves the cutover path still works, and the standalone Regent CLI repo owns the local operator surface.

## Quick Start

Use the full environment path for day-to-day work:

```bash
cp .env.full.example .env
./scripts/dev_full_setup.sh
./scripts/dev_full_start.sh
```

Then verify the stack:

```bash
bash scripts/smoke_full_local.sh
```

`scripts/dev_setup.sh` is deprecated.

## Repo Map

- `lib/`, `config/`, `priv/`, `test/`, `assets/`: Phoenix app, LiveView UI, workers, schemas, and tests
- `services/`: Bun-based sidecars, including the SIWA service
- `qa/`: browser smoke tests, E2E runs, and release evidence
- `docs/`: canonical repo documentation and operator notes

The standalone CLI repo lives at [regent-ai/regent-cli](https://github.com/regent-ai/regent-cli) and is expected locally at `/Users/sean/Documents/regent/regent-cli`.

The TechTree contract workspace now lives at `/Users/sean/Documents/regent/contracts/techtree`.

TODO: add more information about the release process and ownership boundaries between these surfaces.

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

Use the repo matrix in [docs/VALIDATION.md](docs/VALIDATION.md). Common entrypoints are:

```bash
mix precommit
cd services && bun run build && bun run typecheck
cd /Users/sean/Documents/regent/regent-cli && pnpm build && pnpm typecheck && pnpm test
cd /Users/sean/Documents/regent/contracts/techtree && forge test --offline
bash qa/phase-c-smoke.sh
bash scripts/verify_symphony_setup.sh
```

## Launch Points

- The Phoenix app and API live under `lib/`, `config/`, `priv/`, `test/`, and `assets/`.
- The SIWA sidecar lives under `services/`.
- The CLI runtime surface lives in the standalone Regent CLI repo and is summarized under `docs/regent-cli/`.
- Deployment guidance lives in [docs/DEPLOY_RUNBOOK.md](docs/DEPLOY_RUNBOOK.md).
- Security and trust-boundary guidance lives in [docs/AUTH_BOUNDARY_AUDIT.md](docs/AUTH_BOUNDARY_AUDIT.md).

TODO: add more information about the primary product flows, with a short map of which folder owns each one.
