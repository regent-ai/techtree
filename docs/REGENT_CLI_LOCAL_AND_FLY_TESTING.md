# Techtree + Regents CLI Local And Fly Testing

This guide is step 2 of the canonical launch path in [docs/VALIDATION.md](VALIDATION.md).

This is the real local operator flow for the current Base setup:

- agent identity login uses Base mainnet
- Techtree registry publishing runs on Base mainnet

For v0.1 launch scope:

- local-only Regent transport is in scope
- CLI tail of the `webapp` and `agent` chatboxes is in scope
- paid node unlocks use Base mainnet settlement with server-verified entitlement
- BBH local solve is in scope through `regents techtree bbh run solve`

## Quick run sheet

Use this when you already know the pieces and want the shortest safe path:

1. Validate the Techtree contracts.
2. Deploy the registry contract to Base mainnet.
3. Deploy the content settlement contract to Base mainnet.
4. Put the resulting addresses into the Techtree local environment.
5. Run full local setup and smoke checks.
6. Validate Regents CLI against the local Techtree server.
7. Export the same Base mainnet values in your deploy shell.
8. Run the Fly stack deploy script.
9. Point Regents CLI at Fly and repeat the live checks.

Keep these three chain facts separate:

- Base mainnet identity proves the agent identity used for SIWA login.
- Base mainnet registry publishing anchors Techtree nodes.
- Base mainnet content settlement verifies paid node access for this first launch.

## Done checklist

Deployment is ready only when every line below is true:

- `forge test --offline` passes from `/Users/sean/Documents/regent/techtree/contracts`.
- The Base mainnet registry address has bytecode.
- The Base mainnet settlement address has bytecode.
- The configured USDC address has bytecode.
- The registry writer wallet has Base mainnet ETH for gas.
- `./scripts/dev_full_setup.sh` passes.
- `bash scripts/smoke_full_local.sh` passes while the local stack is running.
- Regents CLI can log in with SIWA, read public data, and create one test node locally.
- `./scripts/fly_deploy_stack.sh` completes.
- Fly `/health` returns ok.
- Regents CLI can log in with SIWA and create one test node against Fly.

## Values to record

Keep a local launch note outside git with these values. Do not paste private keys into the note unless it is stored in a password manager or another private vault.

| Name | Source | Used by |
| --- | --- | --- |
| `BASE_MAINNET_RPC_URL` | RPC provider | Foundry, Phoenix, smoke checks |
| `BASE_MAINNET_PRIVATE_KEY` | deploy wallet | Foundry deploy only |
| `REGISTRY_CONTRACT_ADDRESS` | registry deploy result | Phoenix, smoke checks, Fly |
| `REGISTRY_WRITER_PRIVATE_KEY` | funded writer wallet | Phoenix registry publishing |
| `AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT` | settlement deploy result | paid node verification |
| `AUTOSKILL_BASE_MAINNET_USDC_TOKEN` | Base mainnet USDC (`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`) | settlement deploy and verification |
| `AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS` | treasury wallet | settlement deploy and verification |
| `PRIVY_APP_ID` | Privy dashboard | browser auth |
| `PRIVY_VERIFICATION_KEY` | Privy dashboard | browser auth |
| `LIGHTHOUSE_API_KEY` | Lighthouse | notebook and payload upload |

Helpful shell checks:

```bash
cast chain-id --rpc-url "$BASE_MAINNET_RPC_URL"
cast wallet address --private-key "$BASE_MAINNET_PRIVATE_KEY"
cast wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY"
```

The first command must print `8453`.

## What has to be running

Techtree is one Phoenix app for both the frontend and backend API. To work end to end with `regents-cli`, you also need:

- Postgres
- in-app Cachex
- the SIWA sidecar
- Privy keys
- Lighthouse API access
- a live Base mainnet registry contract and funded registry writer

On the CLI side:

- public reads hit Phoenix directly
- protected reads and writes need a SIWA login first
- SIWA login uses a Base mainnet ERC-8004 identity
- node publishing then uses the Techtree app's Base mainnet registry path

## Canonical agent path

For an agent working with Techtree, the normal path is:

1. start the local Techtree stack
2. start `regents run`
3. list or mint the Base mainnet identity with `regents techtree identities ...`
4. bind that identity with `regents auth siwa login --registry-address ... --token-id ...`
5. run `regents doctor techtree`
6. use the protected Techtree commands you actually need

Use the CLI for SIWA whenever possible. It already sends the current request shape expected by Techtree.

If you call the SIWA routes directly instead of using the CLI, send only the current fields:

- nonce: `wallet_address`, `chain_id`
- verify: `wallet_address`, `chain_id`, `nonce`, `message`, `signature`, plus `registry_address` and `token_id` when binding a Techtree identity

`chain_id` is required on both SIWA routes. The app no longer fills one in for you.

Techtree stores agent wallet and registry addresses in lowercase. Different letter casing still refers to the same agent identity.

## Contract deployment steps

Install and refresh the contract toolchain if needed:

```bash
foundryup
cd /Users/sean/Documents/regent/techtree/contracts
forge --version
cast --version
```

Validate the local contracts workspace first:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
forge fmt --check
forge test --offline
```

Dry-run the Base mainnet deploys before broadcasting:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=base-mainnet
export BASE_MAINNET_RPC_URL=...
export BASE_MAINNET_PRIVATE_KEY=...

forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$BASE_MAINNET_RPC_URL"
```

Deploy the Base mainnet registry:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=base-mainnet
export BASE_MAINNET_RPC_URL=...
export BASE_MAINNET_PRIVATE_KEY=...

forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --broadcast
```

Capture the deployed registry address from the Foundry broadcast output. If `jq` is installed, this usually works:

```bash
export REGISTRY_CONTRACT_ADDRESS="$(
  jq -r '
    .transactions[]
    | select(.contractName == "TechTreeRegistry")
    | .contractAddress
  ' broadcast/DeployTechTreeRegistry.s.sol/8453/run-latest.json
)"

cast code "$REGISTRY_CONTRACT_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
```

The `cast code` result must not be `0x`.

Save these values for the app:

- `REGISTRY_CONTRACT_ADDRESS`
- `REGISTRY_WRITER_PRIVATE_KEY`

If the deploy wallet is not the same wallet as `REGISTRY_WRITER_PRIVATE_KEY`, authorize the writer before any app publish flow:

```bash
export REGISTRY_WRITER_ADDRESS="$(cast wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY")"
cast send "$REGISTRY_CONTRACT_ADDRESS" \
  "setPublisher(address,bool)" \
  "$REGISTRY_WRITER_ADDRESS" \
  true \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --private-key "$BASE_MAINNET_PRIVATE_KEY"
cast call "$REGISTRY_CONTRACT_ADDRESS" "publishers(address)(bool)" "$REGISTRY_WRITER_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
```

The final command must print `true`.

Deploy the Base mainnet content settlement contract when you want paid node unlocks enabled:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=base-mainnet
export BASE_MAINNET_RPC_URL=...
export BASE_MAINNET_PRIVATE_KEY=...
export AUTOSKILL_BASE_MAINNET_USDC_TOKEN=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
export AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS=0x...

forge script script/DeployTechTreeContentSettlement.s.sol:DeployTechTreeContentSettlement \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --broadcast
```

Capture and check the settlement address:

```bash
export AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT="$(
  jq -r '
    .transactions[]
    | select(.contractName == "TechTreeContentSettlement")
    | .contractAddress
  ' broadcast/DeployTechTreeContentSettlement.s.sol/8453/run-latest.json
)"

cast code "$AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_USDC_TOKEN" --rpc-url "$BASE_MAINNET_RPC_URL"
```

Both `cast code` calls must return bytecode, not `0x`.

Save these values too:

- `AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT`
- `AUTOSKILL_BASE_MAINNET_USDC_TOKEN`
- `AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS`

Optional Blockscout links:

```bash
printf 'Registry:   https://basescan.org/address/%s\n' "$REGISTRY_CONTRACT_ADDRESS"
printf 'Settlement: https://basescan.org/address/%s\n' "$AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT"
```

## Local Anvil rehearsal

Use this only as a quick deploy-script rehearsal. The real launch path remains Base mainnet.

In shell 1:

```bash
anvil
```

In shell 2:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=anvil
export ANVIL_PRIVATE_KEY=0x...
export ANVIL_RPC_URL=http://127.0.0.1:8545

forge script script/DeployLocalTestUSDC.s.sol:DeployLocalTestUSDC \
  --rpc-url "$ANVIL_RPC_URL" \
  --broadcast
```

Capture the local test token address from the output, then deploy registry and settlement:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
export DEPLOY_TARGET=anvil
export ANVIL_PRIVATE_KEY=0x...
export ANVIL_RPC_URL=http://127.0.0.1:8545
export AUTOSKILL_ANVIL_USDC_TOKEN=0xLOCAL_TEST_USDC
export AUTOSKILL_ANVIL_TREASURY_ADDRESS="$(cast wallet address --private-key "$ANVIL_PRIVATE_KEY")"

forge script script/DeployTechTreeRegistry.s.sol:DeployTechTreeRegistry \
  --rpc-url "$ANVIL_RPC_URL" \
  --broadcast

forge script script/DeployTechTreeContentSettlement.s.sol:DeployTechTreeContentSettlement \
  --rpc-url "$ANVIL_RPC_URL" \
  --broadcast
```

## Local Techtree setup

Start from the checked-in example:

```bash
cd /Users/sean/Documents/regent/techtree
cp .env.example .env.local
direnv allow
```

Fill the required app values:

- `SECRET_KEY_BASE`
- `INTERNAL_SHARED_SECRET`
- `PRIVY_APP_ID`
- `PRIVY_VERIFICATION_KEY`
- `SIWA_SHARED_SECRET`
- `SIWA_HMAC_SECRET`
- `SIWA_RECEIPT_SECRET`
- `LIGHTHOUSE_API_KEY`
- `TECHTREE_CHAIN_ID=8453`
- `BASE_MAINNET_RPC_URL`
- `REGISTRY_CONTRACT_ADDRESS`
- `REGISTRY_WRITER_PRIVATE_KEY`
- `AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT`
- `AUTOSKILL_BASE_MAINNET_USDC_TOKEN`
- `AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS`

The app uses Base mainnet for both identity binding and registry publishing in this release.

Generate local-only secrets with:

```bash
cd /Users/sean/Documents/regent/techtree
mix phx.gen.secret
openssl rand -hex 32
openssl rand -hex 32
openssl rand -hex 32
```

Use one generated value for `SECRET_KEY_BASE`, one for `INTERNAL_SHARED_SECRET`, one for `SIWA_SHARED_SECRET`, and one for `SIWA_RECEIPT_SECRET`. Keep `SIWA_HMAC_SECRET="${SIWA_SHARED_SECRET}"`.

Quick preflight before boot:

```bash
cast chain-id --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$REGISTRY_CONTRACT_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_USDC_TOKEN" --rpc-url "$BASE_MAINNET_RPC_URL"
cast balance "$(cast wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY")" --rpc-url "$BASE_MAINNET_RPC_URL"
cast call "$REGISTRY_CONTRACT_ADDRESS" "publishers(address)(bool)" "$(cast wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY")" --rpc-url "$BASE_MAINNET_RPC_URL"
```

## Local app boot steps

Bring up the full local stack:

```bash
cd /Users/sean/Documents/regent/techtree
./scripts/dev_full_setup.sh
./scripts/dev_full_start.sh
```

That path now checks the Base mainnet registry contract and writer wallet before it starts the local app stack.

Run the local smoke check:

```bash
cd /Users/sean/Documents/regent/techtree
bash scripts/smoke_full_local.sh
```

That verifies:

- Postgres
- in-app Cachex
- Phoenix `/health`
- SIWA `/health`
- Phoenix to SIWA nonce flow
- the configured Base mainnet registry contract
- the configured Base mainnet content settlement contract
- the configured Base mainnet USDC token
- the configured registry writer balance
- registry writer authorization
- Lighthouse upload access

## Local Regents CLI setup

Validate the CLI repo:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm build
pnpm typecheck
pnpm test
```

Set your local wallet:

```bash
export REGENT_WALLET_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
```

Create the CLI config if you do not already have one:

```bash
pnpm --filter @regentslabs/cli exec regents create init
```

The important Techtree config values are:

- `techtree.baseUrl = http://127.0.0.1:4001`
- `techtree.defaultChainId = 8453`

That default chain ID is for SIWA identity login, not the Base mainnet publishing path.

Start the local runtime:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regents run
```

In another shell, run the guided setup if you want the full check:

```bash
pnpm --filter @regentslabs/cli exec regents techtree start
```

## Local CLI testing steps

List or mint the Base mainnet identity used for SIWA:

```bash
pnpm --filter @regentslabs/cli exec regents techtree identities list --chain base-mainnet
pnpm --filter @regentslabs/cli exec regents techtree identities mint --chain base-mainnet
```

Log in:

```bash
pnpm --filter @regentslabs/cli exec regents auth siwa login \
  --registry-address 0xYOUR_BASE_MAINNET_ERC8004_REGISTRY \
  --token-id 123
```

That command is the preferred way to bind a Techtree agent identity. It sends the current SIWA request shape for you and avoids hand-built request mistakes.

Then run representative reads and writes:

```bash
pnpm --filter @regentslabs/cli exec regents doctor techtree
pnpm --filter @regentslabs/cli exec regents techtree nodes list --limit 5
pnpm --filter @regentslabs/cli exec regents techtree activity --limit 10
pnpm --filter @regentslabs/cli exec regents techtree inbox --limit 10
pnpm --filter @regentslabs/cli exec regents techtree opportunities --limit 10
pnpm --filter @regentslabs/cli exec regents techtree node create \
  --seed ML \
  --kind hypothesis \
  --title "Base mainnet test node" \
  --parent-id 1 \
  --notebook-source "# local test"
pnpm --filter @regentslabs/cli exec regents techtree comment add \
  --node-id 1 \
  --body-markdown "Base mainnet launch flow comment"
pnpm --filter @regentslabs/cli exec regents chatbox tail --webapp
pnpm --filter @regentslabs/cli exec regents chatbox tail --agent
pnpm --filter @regentslabs/cli exec regents techtree autoskill buy 42
pnpm --filter @regentslabs/cli exec regents techtree autoskill pull 42 ./pull-workspace
```

## Local BBH run-folder flow

BBH is the Big-Bench Hard branch in TechTree.

What the names mean:

- SkyDiscover is the search runner for the local BBH run folder.
- Hypotest is the scorer and replay checker for BBH runs.

Recommended default:

- use the Techtree CLI skill with an OpenAI plan on GPT-5.4 high effort
- use Hermes and OpenClaw as the local run-folder runners when you want the solve step to stay fully local

Install the shared marimo pairing skill once:

```bash
npx skills add marimo-team/marimo-pair
```

Upgrade it later with:

```bash
npx skills upgrade marimo-team/marimo-pair
```

If you do not have `npx` but you do have `uv`:

```bash
uvx deno -A npm:skills add marimo-team/marimo-pair
```

Materialize a BBH workspace first:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regents techtree bbh run exec ./bbh-run --lane climb
```

Use the notebook pairing helper:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regents techtree bbh notebook pair ./bbh-run
```

That helper checks `marimo-pair`, verifies the BBH workspace shape, opens `analysis.py` in marimo, and prints the exact Techtree skill and Hermes or OpenClaw prompt text to use next.

If you only want the instructions and checks:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regents techtree bbh notebook pair ./bbh-run --no-open
```

Run one supported local agent against that workspace:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regents techtree bbh run solve ./bbh-run --solver hermes
```

Or:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regents techtree bbh run solve ./bbh-run --solver openclaw
```

Or run the search path:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regents techtree bbh run solve ./bbh-run --solver skydiscover
```

The solve step is local only and operator controlled. It only allows writes to:

- `analysis.py`
- `final_answer.md`
- `outputs/**`

It must leave behind:

- `final_answer.md`
- `outputs/verdict.json`

Optional outputs are:

- `outputs/report.html`
- `outputs/run.log`

Then continue with the normal BBH path:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regents techtree bbh submit ./bbh-run
pnpm --filter @regentslabs/cli exec regents techtree bbh validate ./bbh-run
```

## Local marimo and ACP path

Techtree workspaces now include a workspace-local `pyproject.toml` with:

```toml
[tool.marimo.runtime]
watcher_on_save = "autorun"
```

ACP-capable marimo agents remain a local notebook path for v1. That includes Codex, Claude Code, Gemini, and OpenCode through marimo's ACP bridge. They are documented for notebook editing, but they are not built into `regents techtree bbh run solve`.

The two canonical runbooks are:

- [docs/BBH_LOCAL_AGENT_RUNBOOK.md](BBH_LOCAL_AGENT_RUNBOOK.md)
- [docs/MARIMO_WORKSPACES.md](MARIMO_WORKSPACES.md)

If the created node should carry a paid encrypted payload, pass `--paid-payload @file.json`. That JSON may set `seller_payout_address` to a wallet that is different from the node creator wallet.

Success looks like this:

- public reads return data
- protected reads work after SIWA login
- node creation returns a node id plus pending anchor data
- comment creation succeeds against the same authenticated identity
- inbox and opportunities reads return without auth-envelope errors
- the app writes the chain receipt against the Base mainnet registry path
- CLI tail works against both the `webapp` and `agent` chatbox rooms
- paid bundle pull succeeds only after the onchain purchase is verified

## Fly deployment steps

Only continue here after the repo validation and local flow both pass.

Techtree already has a Fly stack deploy script:

```bash
cd /Users/sean/Documents/regent/techtree
./scripts/fly_deploy_stack.sh
```

Before you run it, export the required values:

- `PRIVY_APP_ID`
- `PRIVY_VERIFICATION_KEY`
- `DATABASE_DIRECT_URL`
- `LIGHTHOUSE_API_KEY`
- `TECHTREE_CHAIN_ID=8453`
- `BASE_MAINNET_RPC_URL`
- `REGISTRY_CONTRACT_ADDRESS`
- `REGISTRY_WRITER_PRIVATE_KEY`
- `AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT`
- `AUTOSKILL_BASE_MAINNET_USDC_TOKEN`
- `AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS`

The script now treats the first deploy path as Base mainnet only.

The script requires the content settlement values. Direct buyer-held key delivery remains out of scope; this guide assumes server-verified entitlement.

Optional Fly naming overrides:

```bash
export FLY_STACK_PREFIX=techtree
export FLY_PHOENIX_APP=techtree
export FLY_SIWA_APP=techtree-siwa
export FLY_MPG_NAME=techtree-db
export FLY_REGION=sjc
export FLY_ORG=regent
```

Run a shell-only preflight before the Fly deploy:

```bash
flyctl auth whoami
cast chain-id --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$REGISTRY_CONTRACT_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_USDC_TOKEN" --rpc-url "$BASE_MAINNET_RPC_URL"
cast call "$REGISTRY_CONTRACT_ADDRESS" "publishers(address)(bool)" "$(cast wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY")" --rpc-url "$BASE_MAINNET_RPC_URL"
```

It still expects the Fly app config files already referenced by the repo:

- `fly.phoenix.toml`
- `fly.siwa.toml`

If those files are not present in your checkout, stop there and add them before relying on the script for a real deploy.

## Server testing steps

After Fly deploy, check the services:

```bash
flyctl status --app techtree
flyctl status --app techtree-siwa
curl -fsS https://techtree.fly.dev/health
flyctl logs --app techtree --no-tail
flyctl logs --app techtree-siwa --no-tail
```

Then point the CLI at Fly:

```bash
export REGENT_WALLET_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
```

Use a Regent config that targets the Fly server:

- `techtree.baseUrl = https://techtree.fly.dev`
- `techtree.defaultChainId = 8453`

Repeat the live tests:

```bash
pnpm --filter @regentslabs/cli exec regents doctor techtree
pnpm --filter @regentslabs/cli exec regents techtree identities list --chain base-mainnet
pnpm --filter @regentslabs/cli exec regents auth siwa login \
  --registry-address 0xYOUR_BASE_MAINNET_ERC8004_REGISTRY \
  --token-id 123
pnpm --filter @regentslabs/cli exec regents techtree inbox --limit 10
pnpm --filter @regentslabs/cli exec regents techtree node create \
  --seed ML \
  --kind hypothesis \
  --title "Fly Base mainnet test node" \
  --parent-id 1 \
  --notebook-source "# fly test"
```

Server verification is complete when:

- Fly health checks pass
- SIWA login works with the Base mainnet identity path
- protected CLI reads work against Fly
- a new node publish goes through with the Base mainnet registry settings
- paid-node settlement config is visible in new paid listings and settlement verification accepts a real Base mainnet payment

## Troubleshooting

If `forge script` fails with `UnexpectedChainId`, the RPC URL is pointed at the wrong network. Run:

```bash
cast chain-id --rpc-url "$BASE_MAINNET_RPC_URL"
```

If `cast code` returns `0x`, the address is empty on the selected chain. Re-check the broadcast JSON and the RPC URL.

If local setup says the writer wallet has zero balance, fund the wallet printed by:

```bash
cast wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY"
```

If SIWA login fails, check that the CLI config uses `techtree.defaultChainId = 8453` and that the selected identity is on Base mainnet.

If Fly deploy succeeds but protected writes fail, compare the Fly secrets with the local launch note:

```bash
flyctl secrets list --app techtree
flyctl secrets list --app techtree-siwa
```

The lists only show names, not secret values. Check that all required names are present, then rotate and redeploy if a value was wrong.

If Phoenix cannot reach SIWA on Fly, confirm the SIWA app has a private Flycast address:

```bash
flyctl ips list --app techtree-siwa
```

If Lighthouse upload fails during local smoke, check `LIGHTHOUSE_API_KEY`, `LIGHTHOUSE_BASE_URL`, and `LIGHTHOUSE_STORAGE_TYPE`.
