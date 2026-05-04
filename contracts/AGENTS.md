This file governs the TechTree contract workspace at `/Users/sean/Documents/regent/techtree/contracts`.

## Regent Dependency Skills

The Regent dependency skills are installed in `/Users/sean/Documents/regent/.agents/skills` and `/Users/sean/.codex/skills`. Foundry remains the primary contracts workflow. Also open:

- `safe-viem-wallet-actions` when contract changes affect prepared transactions, viem ABI calls, wallet action envelopes, or confirmation paths.
- `contract-first-cli-api` when contract changes require app, API, CLI, generated binding, or operator-documentation changes.
- `techtree-research-runtime` when contract behavior affects publishing, paid payloads, BBH, Science Tasks, or evidence artifacts.

## Core Rules

- Hard cutover only. Do not add backwards compatibility shims, migration glue, or dual paths unless explicitly requested.
- Use Foundry for contract development and testing.
- For API <-> backend functionality around Techtree, the source of truth lives in the Regents CLI contract surface, not in these Solidity files. Start from `/Users/sean/Documents/regent/regents-cli/docs/api-contract-workflow.md`, `/Users/sean/Documents/regent/techtree/docs/api-contract.openapiv3.yaml`, and `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/contracts/api-ownership.ts`.
- Contract file meanings:
  - `api-contract.openapiv3.yaml` is the source of truth for a product's HTTP backend contract, including routes, auth, request bodies, response shapes, and stable error envelopes.
  - `regent-services-contract.openapiv3.yaml` is the source of truth for shared HTTP backend contracts that are not owned by one product, such as `regent-staking`.
  - `cli-contract.yaml` is the source of truth for a product's shipped CLI surface, including command names, flags/args, auth mode, whether a command is HTTP-backed or local/runtime-backed, and which backend contract operation it is allowed to use.
- If work changes code in `/Users/sean/Documents/regent/techtree` or `/Users/sean/Documents/regent/regents-cli`, it is not done until validation has been run in the app, the CLI repo, and this contract workspace. Run `mix precommit` in `techtree`, `pnpm build`, `pnpm typecheck`, `pnpm test`, and `pnpm test:pack-smoke` in `regents-cli`, and `forge test --offline` from `/Users/sean/Documents/regent/techtree/contracts`.
- Prefer repository-local, versioned docs over off-repo context.

## Protected Work

- This contract workspace must never be auto-picked by autonomous agents unless a human explicitly assigns it.
- Treat auth, deploy, migration, and payment-related work as protected and hand it back unless a human explicitly assigns it.

## Validation

```bash
cd /Users/sean/Documents/regent/techtree/contracts
forge test --offline
```
