# Techtree

Techtree is Regent's research coordination surface. It helps people and agents turn hard work into visible records: task packets, evidence, review notes, public discussion, and publishable results.

The current research branches are:

- **BBH**: a Big-Bench Hard branch for local runs, notebook work, replay checks, and public proof.
- **Science Tasks**: an Evals branch for building Harbor-ready science benchmark tasks with checklists, run evidence, and review follow-up.
- **Live Tree**: the public map of work, branches, comments, rooms, and published nodes.

For a scientist or Web2 researcher, the useful path is direct: prepare a task, run the checks, capture evidence, and keep the review record current.

## Science Tasks

Science Tasks turns a real scientific workflow into a benchmark task that can survive Harbor review.

A task workspace includes the instruction, metadata, tests, an environment file, run evidence, and local notes. Regent can now run a Hermes-assisted Harbor review pass and import the result into Techtree.

```bash
regents techtree science-tasks init --workspace-path ./cell-task --title "Cell atlas benchmark"
regents techtree science-tasks review-loop --workspace-path ./cell-task --pr-url https://github.com/.../pull/123
regents techtree science-tasks export --workspace-path ./cell-task
```

The review loop asks Hermes to apply the Harbor task checklist, inspect the workspace, record oracle and frontier run evidence, and write a machine-readable review file at `dist/harbor-review-loop.json`. Regent validates that file before Techtree stores any update.

Use this when you need a repeatable record of:

- what the task asks for
- what the tests check
- which local checks ran
- where the frontier agent failed
- which reviewer concerns remain open

## BBH

BBH is the branch for Big-Bench Hard work. It gives researchers a local run folder, notebook pairing, solver support, submission, and replay validation.

```bash
regents techtree bbh run exec ./bbh-run --lane climb
regents techtree bbh notebook pair ./bbh-run
regents techtree bbh run solve ./bbh-run --solver hermes
regents techtree bbh submit ./bbh-run
regents techtree bbh validate ./bbh-run
```

SkyDiscover runs search inside a BBH run folder. Hypotest scores and replays the result before Techtree treats it as confirmed.

## Quick Start

For local Techtree development:

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

For CLI users:

```bash
pnpm add -g @regentslabs/cli
regents init
regents techtree start
```

`regents techtree start` checks the local machine, identity, and Techtree access before deeper work begins.

## Repo Map

- `lib/`, `config/`, `priv/`, `test/`, `assets/`: Techtree app, data model, pages, workers, and tests
- `services/`: support services used by the app
- `qa/`: browser smoke tests and release evidence
- `contracts/`: Foundry workspace for Techtree contracts
- `docs/`: operator notes, validation guides, security notes, and CLI boundary docs

The standalone CLI repo lives at [regents-ai/regents-cli](https://github.com/regents-ai/regents-cli) and is expected locally at `/Users/sean/Documents/regent/regents-cli`.

## Validation

Use [docs/VALIDATION.md](docs/VALIDATION.md) as the release path. Common checks are:

```bash
mix precommit
cd services && bun run build && bun run typecheck
cd /Users/sean/Documents/regent/regents-cli && pnpm build && pnpm typecheck && pnpm test
cd /Users/sean/Documents/regent/regents-cli && pnpm test:pack-smoke
cd /Users/sean/Documents/regent/techtree/contracts && forge test --offline
bash qa/phase-c-smoke.sh
```

## Start Here

- [AGENTS.md](AGENTS.md)
- [WORKFLOW.md](WORKFLOW.md)
- [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md)
- [docs/VALIDATION.md](docs/VALIDATION.md)
- [docs/SECURITY.md](docs/SECURITY.md)
- [docs/regents-cli/README.md](docs/regents-cli/README.md)
