# TechTree Foundry Contracts

Foundry workspace for the TechTree contracts inside the main Techtree repo at `/Users/sean/Documents/regent/techtree/contracts`.

## Chain language

Use this wording consistently when talking about the product around this repo:

- `autolaunch` is purely on Base mainnet, with Base Sepolia for testing
- the current Techtree launch target is Base Sepolia for registry-backed publishing
- Techtree agent identity login uses Base Sepolia for this launch
- `Techtree` contract scope here is the registry, TECH token, staking, emissions, and paid-node settlement surfaces

## Scope

This workspace contains three contract surfaces.

Current launch scope:

- the v1 registry contracts used for anchored node publication
- the TECH token, staking vote, and emission controller flow
- the Base-first content settlement rail for paid Techtree node unlocks

## Layout

- `src/ITechTreeRegistry.sol`
- `src/TechTreeRegistry.sol`
- `src/TechToken.sol`
- `src/TechStakingVote.sol`
- `src/TechEmissionController.sol`
- `src/TechTreeContentSettlement.sol`
- `script/DeployTechTreeRegistry.s.sol`
- `script/DeployTechTreeContentSettlement.s.sol`
- `script/DeployLocalTestUSDC.s.sol`
- `test/TechTreeRegistry.t.sol`
- `test/TechTreeContentSettlement.t.sol`
- `test/token/TechToken.t.sol`
- `test/staking/TechStakingVote.unit.t.sol`
- `test/staking/TechStakingVote.fuzz.t.sol`
- `test/staking/TechStakingVote.invariant.t.sol`
- `test/emissions/TechEmissionController.t.sol`

## Build and test

```bash
cd /Users/sean/Documents/regent/techtree/contracts
forge fmt
forge test --offline
```

The TECH staking and emissions tests include unit, fuzz, and invariant coverage.

## Deploy

This repo's current registry and settlement deploy helpers are Base-targeted. For the current v0.1 launch path, both the registry deploy and the paid-node settlement deploy are in scope. Use `forge script` with `DEPLOY_TARGET` to pick key env vars:

- `DEPLOY_TARGET=anvil` uses `ANVIL_PRIVATE_KEY`
- `DEPLOY_TARGET=base-sepolia` uses `BASE_SEPOLIA_PRIVATE_KEY`
- `DEPLOY_TARGET=base-mainnet` uses `BASE_MAINNET_PRIVATE_KEY`

`DeployTechTreeContentSettlement.s.sol` is the settlement deploy helper for paid node unlocks on Base-targeted environments.
`DeployLocalTestUSDC.s.sol` is only for local Anvil rehearsals.

Base Sepolia registry deploy:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=base-sepolia
export BASE_SEPOLIA_RPC_URL=...
export BASE_SEPOLIA_PRIVATE_KEY=...

forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --broadcast
```

Base Sepolia content settlement deploy:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=base-sepolia
export BASE_SEPOLIA_RPC_URL=...
export BASE_SEPOLIA_PRIVATE_KEY=...
export AUTOSKILL_BASE_SEPOLIA_USDC_TOKEN=0x...
export AUTOSKILL_BASE_SEPOLIA_TREASURY_ADDRESS=0x...

forge script script/DeployTechTreeContentSettlement.s.sol:DeployTechTreeContentSettlement \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --broadcast
```

After deployment, check both addresses:

```bash
cast code "$REGISTRY_CONTRACT_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL"
cast code "$AUTOSKILL_BASE_SEPOLIA_SETTLEMENT_CONTRACT" --rpc-url "$BASE_SEPOLIA_RPC_URL"
cast code "$AUTOSKILL_BASE_SEPOLIA_USDC_TOKEN" --rpc-url "$BASE_SEPOLIA_RPC_URL"
```

Each call should return bytecode. The full app, CLI, and Fly run sheet lives at [../docs/REGENT_CLI_LOCAL_AND_FLY_TESTING.md](../docs/REGENT_CLI_LOCAL_AND_FLY_TESTING.md).

Local Anvil rehearsal:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export ANVIL_RPC_URL=http://127.0.0.1:8545
export ANVIL_PRIVATE_KEY=0x...
export DEPLOY_TARGET=anvil

forge script script/DeployLocalTestUSDC.s.sol:DeployLocalTestUSDC \
  --rpc-url "$ANVIL_RPC_URL" \
  --broadcast

export AUTOSKILL_ANVIL_USDC_TOKEN=0xLOCAL_TEST_USDC
export AUTOSKILL_ANVIL_TREASURY_ADDRESS="$(cast wallet address --private-key "$ANVIL_PRIVATE_KEY")"

forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$ANVIL_RPC_URL" \
  --broadcast

forge script script/DeployTechTreeContentSettlement.s.sol:DeployTechTreeContentSettlement \
  --rpc-url "$ANVIL_RPC_URL" \
  --broadcast
```
