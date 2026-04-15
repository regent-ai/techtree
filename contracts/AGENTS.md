This file governs the TechTree contract workspace at `/Users/sean/Documents/regent/techtree/contracts`.

## Core Rules

- Hard cutover only. Do not add backwards compatibility shims, migration glue, or dual paths unless explicitly requested.
- Use Foundry for contract development and testing.
- For API <-> backend functionality around Techtree, the source of truth lives in the Regent CLI contract surface, not in these Solidity files. Start from `/Users/sean/Documents/regent/regent-cli/docs/api-contract-workflow.md`, `/Users/sean/Documents/regent/techtree/docs/api-contract.openapiv3.yaml`, and `/Users/sean/Documents/regent/regent-cli/packages/regent-cli/src/contracts/api-ownership.ts`.
- Contract file meanings:
  - `api-contract.openapiv3.yaml` is the source of truth for a product's HTTP backend contract, including routes, auth, request bodies, response shapes, and stable error envelopes.
  - `regent-services-contract.openapiv3.yaml` is the source of truth for shared HTTP backend contracts that are not owned by one product, such as `regent-staking`.
  - `cli-contract.yaml` is the source of truth for a product's shipped CLI surface, including command names, flags/args, auth mode, whether a command is HTTP-backed or local/runtime-backed, and which backend contract operation it is allowed to use.
- If work changes code in `/Users/sean/Documents/regent/techtree` or `/Users/sean/Documents/regent/regent-cli`, it is not done until validation has been run in the app, the CLI repo, and this contract workspace. Run `mix precommit` in `techtree`, `pnpm build`, `pnpm typecheck`, `pnpm test`, and `pnpm test:pack-smoke` in `regent-cli`, and `forge test --offline` from `/Users/sean/Documents/regent/techtree/contracts`.
- Prefer repository-local, versioned docs over off-repo context.

## Protected Work

- This contract workspace must never be auto-picked by autonomous agents unless a human explicitly assigns it.
- Treat auth, deploy, migration, and payment-related work as protected and hand it back unless a human explicitly assigns it.

## Validation

```bash
cd /Users/sean/Documents/regent/techtree/contracts
forge test --offline
```
