# Validation

Choose validation by touched surface.

## Phoenix app

```bash
mix precommit
```

## Services

```bash
cd services
bun run build
bun run typecheck
```

## Full local parity stack

```bash
bash scripts/smoke_full_local.sh
```

## Regent CLI

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm build
pnpm typecheck
pnpm test
```

## Contracts

Only run when the issue was explicitly assigned. The contracts Git repo is `/Users/sean/Documents/regent/contracts`, and the Techtree Foundry workspace inside it is:

```bash
cd /Users/sean/Documents/regent/contracts/techtree
forge test --offline
```

## Browser-visible changes

Run the relevant harness under `qa/`, for example:

```bash
bash qa/frontpage-platform-smoke.sh
bash qa/phase-c-smoke.sh
REQUIRE_DESKTOP=1 REQUIRE_IOS=0 bash qa/phase-d-browser-e2e.sh
```

For release-gate browser signoff, also complete the manual authenticated flow in [manual-authenticated-trollbox-signoff.md](/Users/sean/Documents/regent/techtree/qa/manual-authenticated-trollbox-signoff.md).

## Deploys

Before deploying `main`, walk the checklist in [docs/DEPLOY_RUNBOOK.md](DEPLOY_RUNBOOK.md).

## Docs and workflow integrity

```bash
bash scripts/check_docs.sh
```
