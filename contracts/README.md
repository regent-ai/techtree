# TechTree Foundry Contracts

Foundry workspace for the v0.0.1 `TechTreeRegistry` anchor contract.

## Scope

- Externally supplied node IDs (`nodeId`) are canonical.
- Anchors `manifestUri` + `manifestHash` onchain.
- Enforces parent existence for non-root nodes.
- Writer allowlist (`WRITER_ROLE`) for node creation.
- Admin-controlled pause/unpause.
- Canonical `NodeKind` order:
  - `Hypothesis`
  - `Data`
  - `Result`
  - `NullResult`
  - `Review`
  - `Synthesis`
  - `Meta`
  - `Skill`

## Layout

- `src/TechTreeRegistry.sol`: main registry contract.
- `src/utils/AccessControlLite.sol`: local minimal role primitive.
- `src/utils/PausableLite.sol`: local minimal pause primitive.
- `script/DeployTechTreeRegistry.s.sol`: deploy script for Anvil/Ethereum Sepolia/Ethereum mainnet targets.
- `test/TechTreeRegistry.t.sol`: forge tests (success + failure paths).

## Why local primitives (no OpenZeppelin import)

This workspace is intentionally network-independent. If OpenZeppelin is unavailable locally, the contract still compiles and tests run because role/pause primitives are implemented in-project.

## Build and test

```bash
cd /Users/sean/Documents/regent/techtree/contracts
forge fmt
forge test
```

## Deploy

Use `forge script` with `DEPLOY_TARGET` to pick key env vars:

- `DEPLOY_TARGET=anvil` uses `ANVIL_PRIVATE_KEY`
- `DEPLOY_TARGET=sepolia` uses `ETHEREUM_SEPOLIA_PRIVATE_KEY`
- `DEPLOY_TARGET=mainnet` uses `ETHEREUM_MAINNET_PRIVATE_KEY`

Optional:

- `REGISTRY_ADMIN` (defaults to deployer)
- `REGISTRY_INITIAL_WRITER` (defaults to deployer)

Anvil example:

```bash
export DEPLOY_TARGET=anvil
export ANVIL_RPC_URL=http://127.0.0.1:8545
export ANVIL_PRIVATE_KEY=<anvil_private_key>
forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$ANVIL_RPC_URL" \
  --broadcast
```

Ethereum Sepolia example:

```bash
export DEPLOY_TARGET=sepolia
export ETHEREUM_SEPOLIA_RPC_URL=<ethereum_sepolia_rpc_url>
export ETHEREUM_SEPOLIA_PRIVATE_KEY=<ethereum_sepolia_private_key>
forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$ETHEREUM_SEPOLIA_RPC_URL" \
  --broadcast
```

Ethereum mainnet example:

```bash
export DEPLOY_TARGET=mainnet
export ETHEREUM_MAINNET_RPC_URL=<ethereum_mainnet_rpc_url>
export ETHEREUM_MAINNET_PRIVATE_KEY=<ethereum_mainnet_private_key>
forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$ETHEREUM_MAINNET_RPC_URL" \
  --broadcast
```
