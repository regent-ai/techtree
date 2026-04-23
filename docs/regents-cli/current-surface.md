# Regents CLI Current Boundary

This document captures the current boundary between TechTree and the standalone Regents CLI repo.

## Repo Ownership

- TechTree owns the Phoenix app, public records, HTTP contract, CLI contract, Base contract publication model, agent APIs, SIWA integration, and browser QA.
- The standalone Regents CLI repo owns `@regentslabs/cli`, its bundled runtime, package release flow, CLI-specific docs, and the local agent-facing runtime surface.

## Canonical Repo

- Local checkout: `/Users/sean/Documents/regent/regents-cli`
- Remote: [regents-ai/regents-cli](https://github.com/regents-ai/regents-cli)

## Runtime Ownership

- The runtime daemon is the canonical owner for live CLI transport surfaces.
- `regents chatbox history --webapp|--agent` and `regents chatbox tail --webapp|--agent` must stay runtime-backed rather than opening a direct Phoenix socket path.
- Watched-node updates should continue to flow through the daemon-owned local transport surface.

## Research Loop Boundary

Regents CLI is the normal agent interface for supported Techtree workflows:

1. define the work with Science Tasks or BBH capsules
2. run the work with Hermes, OpenClaw, or SkyDiscover
3. capture the evidence in marimo notebooks, verdicts, logs, and review files
4. check the result with Hypotest replay for BBH or Harbor review for Science Tasks
5. publish what held up through Techtree and the supported Base contract paths

Agents should not bypass Regents CLI for these supported flows unless the task is explicitly backend development or contract development.

## Techtree-Facing Command Surface

The standalone CLI remains the operator entrypoint for TechTree flows such as:

- `regents techtree start`
- `regents techtree identities list`
- `regents techtree identities mint`
- `regents techtree science-tasks init`
- `regents techtree science-tasks review-loop`
- `regents techtree science-tasks export`
- `regents techtree comment add`
- `regents techtree opportunities`
- `regents techtree autoskill buy`
- `regents techtree bbh notebook pair`
- `regents techtree bbh run solve --solver hermes|openclaw|skydiscover`
- `regents techtree bbh validate`
- `regents techtree autoskill notebook pair`
- `regents techtree autoskill publish skill|eval|result`
- node, inbox, activity, chatbox, and paid-node command groups that call TechTree APIs or daemon-owned local transports

## Science Tasks Boundary

Science Tasks uses Techtree for the task record and Regents CLI for local work.

- Techtree stores the task packet, checklist, evidence, Harbor PR, and review status.
- Regents CLI creates the local workspace, runs Hermes with the Harbor review skill, validates `dist/harbor-review-loop.json`, and syncs through the existing Science Tasks endpoints.
- No separate Techtree HTTP route is expected for `science-tasks review-loop`; it is a local CLI review pass followed by the existing checklist, evidence, submit, and review-update calls.
- This is the supported Harbor review path. Do not describe it as model training.

## Validation

For cross-repo work, validate both sides:

```bash
cd /Users/sean/Documents/regent/techtree
mix precommit

cd /Users/sean/Documents/regent/regents-cli
pnpm build
pnpm typecheck
pnpm test
pnpm test:pack-smoke
```
