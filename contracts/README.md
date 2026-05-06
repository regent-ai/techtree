# TechTree Foundry Contracts

Foundry workspace for the TechTree contracts inside the main Techtree repo at `/Users/sean/Documents/regent/techtree/contracts`.

For a high-level map of registry publishing, paid settlement, TECH rewards, and emissions, see [../docs/ONCHAIN_SYSTEM.md](../docs/ONCHAIN_SYSTEM.md).

## Chain language

Use this wording consistently when talking about the product around this repo:

- `autolaunch` is purely on Base mainnet; use staging chains only for rehearsal
- the current Techtree public beta target is Base mainnet for registry-backed publishing
- Techtree agent identity login uses Base mainnet for this launch
- `Techtree` contract scope here is the registry, TECH rewards, emissions, exit-fee swap, and paid-node settlement surfaces

## Scope

This workspace contains three contract surfaces.

Current launch scope:

- the v1 registry contracts used for anchored node publication
- the TECH v0.2 token, locked agent reward vault, reward router, leaderboard registry, emission controller, and exit-fee swap
- the Base-first content settlement rail for paid Techtree node unlocks

## Layout

- `src/ITechTreeRegistry.sol`
- `src/TechTreeRegistry.sol`
- `src/TechToken.sol`
- `src/TechAgentRewardVault.sol`
- `src/TechRewardRouter.sol`
- `src/TechEmissionControllerV2.sol`
- `src/TechLeaderboardRegistry.sol`
- `src/TechExitFeeLotSwap.sol`
- `src/TechTreeContentSettlement.sol`
- `script/DeployTechTreeRegistry.s.sol`
- `script/DeployTechTreeContentSettlement.s.sol`
- `script/DeployTechStack.s.sol`
- `script/VerifyTechStack.s.sol`
- `script/DeployLocalTestUSDC.s.sol`
- `test/TechTreeRegistry.t.sol`
- `test/TechTreeContentSettlement.t.sol`
- `test/token/TechToken.t.sol`
- `test/TechRewardStack.t.sol`
- `test/TechLeaderboardRegistry.t.sol`
- `test/DeployTechStack.t.sol`

## Build and test

```bash
cd /Users/sean/Documents/regent/techtree/contracts
forge fmt
forge test --offline
```

The TECH v0.2 tests cover the token cap, reward roots, locked vault balances,
agent ownership checks, withdrawals, the exit-fee path, and deploy wiring.

## Deploy

This repo's registry, settlement, and TECH v0.2 deploy helpers are Base-targeted.
Use `forge script` with `DEPLOY_TARGET` to pick key env vars:

- `DEPLOY_TARGET=anvil` uses `ANVIL_PRIVATE_KEY`
- `DEPLOY_TARGET=base-mainnet` uses `BASE_MAINNET_PRIVATE_KEY`

`DeployTechTreeContentSettlement.s.sol` is the settlement deploy helper for paid node unlocks on Base-targeted environments.
`DeployLocalTestUSDC.s.sol` is only for local Anvil rehearsals.
`DeployTechStack.s.sol` deploys the TECH v0.2 stack and prints one
`TECH_STACK_RESULT_JSON:{...}` line.
`VerifyTechStack.s.sol` checks post-deploy wiring and role cleanup.

Base mainnet registry deploy:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=base-mainnet
export BASE_MAINNET_RPC_URL=...
export BASE_MAINNET_PRIVATE_KEY=...

forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --broadcast
```

Base mainnet content settlement deploy:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=base-mainnet
export BASE_MAINNET_RPC_URL=...
export BASE_MAINNET_PRIVATE_KEY=...
export AUTOSKILL_BASE_MAINNET_USDC_TOKEN=0x...
export AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS=0x...

forge script script/DeployTechTreeContentSettlement.s.sol:DeployTechTreeContentSettlement \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --broadcast
```

Base mainnet TECH v0.2 deploy:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=base-mainnet
export BASE_MAINNET_RPC_URL=...
export BASE_MAINNET_PRIVATE_KEY=...
export TECH_ADMIN_ADDRESS=...
export TECH_OWNER_ADDRESS=...
export TECH_ROOT_MANAGER_ADDRESS=...
export TECH_LEADERBOARD_MANAGER_ADDRESS=...
export TECH_PAUSER_ADDRESS=...
export TECH_AGENT_REGISTRY_ADDRESS=...
export TECH_WETH_TOKEN=...
export TECH_REGENT_TOKEN=...
export TECH_UNISWAP_V4_POOL_MANAGER=...
export TECH_UNIVERSAL_ROUTER=...
export TECH_PERMIT2=...
export TECH_ETH_USD_FEED=...
export TECH_BASE_SEQUENCER_UPTIME_FEED=...
export TECH_MAX_SUPPLY=...
export TECH_EPOCH_DURATION_SECONDS=...
export TECH_MAX_EPOCHS=...
export TECH_INITIAL_EPOCH_EMISSION=...
export TECH_MAX_EMISSION_SUPPLY=...
export TECH_DECAY_NUMERATOR=...
export TECH_DECAY_DENOMINATOR=...
export TECH_WETH_POOL_FEE=...
export TECH_WETH_POOL_TICK_SPACING=...
export WETH_REGENT_POOL_FEE=...
export WETH_REGENT_POOL_TICK_SPACING=...
export TECH_WETH_MIN_LIQUIDITY=...
export WETH_REGENT_MIN_LIQUIDITY=...
export TECH_ETH_USD_MAX_STALENESS_SECONDS=...
export TECH_SEQUENCER_GRACE_PERIOD_SECONDS=...

forge script script/DeployTechStack.s.sol:DeployTechStack \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --broadcast
```

After deployment, check both addresses:

```bash
cast code "$REGISTRY_CONTRACT_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_USDC_TOKEN" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$TECH_TOKEN_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$TECH_AGENT_REWARD_VAULT_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$TECH_REWARD_ROUTER_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$TECH_EMISSION_CONTROLLER_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$TECH_LEADERBOARD_REGISTRY_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$TECH_EXIT_SWAP_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
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
