# Main Deploy Runbook

This is the shortest path to deploy `main` on Fly with the Phoenix app, SIWA sidecar, in-app Cachex, and managed Postgres.

This runbook is for the first production cut:

- Fly apps: `techtree`, `techtree-siwa`
- region: `sjc`
- org: `regent`
- host: `techtree.fly.dev`
- chain: Base mainnet (`TECHTREE_CHAIN_ID=8453`)
- backend transport: local-only (`TECHTREE_P2P_ENABLED=false`)
- Regent live tail stays daemon-owned and local-only in this deploy
- paid node unlocks use Base mainnet settlement with server-verified entitlement

## Stack shape

- Phoenix app: `fly.phoenix.toml`
- SIWA sidecar: `fly.siwa.toml`
- in-app Cachex: runs inside the Phoenix app
- Managed Postgres: attached by `scripts/fly_deploy_stack.sh`

Use `scripts/fly_deploy_stack.sh` as the deploy entrypoint.

The Phoenix Dockerfile expects `../elixir-utils` and `../design-system` to be staged under `.fly-build/`. A direct Docker build is not the release path; run `scripts/fly_deploy_stack.sh` so those folders are staged before Fly builds Phoenix.

## Prerequisites

- `flyctl` installed and authenticated
- `openssl` installed
- `rsync` installed
- `mix` available locally so `mix phx.gen.secret` can run
- Foundry installed locally so `cast` can check the Base mainnet contracts before deploy
- `main` checked out and validated through steps 1 to 3 in [docs/VALIDATION.md](VALIDATION.md)
- sibling checkouts at `../elixir-utils` and `../design-system`; the deploy script stages them into `.fly-build/`
- Base mainnet registry and content settlement contracts already deployed

## Auth model for this deploy

Keep the launch auth paths separate:

- browser users authenticate through Privy
- agent API access uses SIWA with a Base mainnet identity
- internal service-to-service routes use `INTERNAL_SHARED_SECRET`

The residual live checks for those paths stay in [docs/AUTH_BOUNDARY_AUDIT.md](AUTH_BOUNDARY_AUDIT.md) and [docs/VALIDATION.md](VALIDATION.md).

## Required Phoenix secrets

These must exist in Fly for the Phoenix app:

- `SECRET_KEY_BASE`
- `PHX_HOST`
- `DATABASE_URL`
- `DATABASE_DIRECT_URL`
- `INTERNAL_SHARED_SECRET`
- `SIWA_INTERNAL_URL`
- `SIWA_SHARED_SECRET`

Important runtime env also used by Phoenix:

- `PORT`
- `ECTO_POOL_SIZE`
- `TECHTREE_ETHEREUM_MODE=rpc`
- `TECHTREE_CHAIN_ID=8453`
- `TECHTREE_P2P_ENABLED=false`
- `TECHTREE_HOME_UNICORN_HERO_ENABLED=false`
- `PRIVY_APP_ID`
- `PRIVY_VERIFICATION_KEY`
- `LIGHTHOUSE_API_KEY`
- `BASE_MAINNET_RPC_URL`
- `REGISTRY_CONTRACT_ADDRESS`
- `REGISTRY_WRITER_PRIVATE_KEY`
- `AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT`
- `AUTOSKILL_BASE_MAINNET_USDC_TOKEN` (`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` for Circle USDC on Base)
- `AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS`

Before deploy, check the Base mainnet values from the deploy shell:

```bash
cast chain-id --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$REGISTRY_CONTRACT_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT" --rpc-url "$BASE_MAINNET_RPC_URL"
cast code "$AUTOSKILL_BASE_MAINNET_USDC_TOKEN" --rpc-url "$BASE_MAINNET_RPC_URL"
REGISTRY_WRITER_ADDRESS="$(cast wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY")"
cast balance "$REGISTRY_WRITER_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
cast call "$REGISTRY_CONTRACT_ADDRESS" "publishers(address)(bool)" "$REGISTRY_WRITER_ADDRESS" --rpc-url "$BASE_MAINNET_RPC_URL"
```

The chain ID must be `8453`, each `cast code` call must return bytecode, the writer must have Base ETH, and the final publisher check must return `true`.

If the registry deployer and app writer are different wallets, authorize the app writer before deploying Phoenix:

```bash
REGISTRY_WRITER_ADDRESS="$(cast wallet address --private-key "$REGISTRY_WRITER_PRIVATE_KEY")"
cast send "$REGISTRY_CONTRACT_ADDRESS" \
  "setPublisher(address,bool)" \
  "$REGISTRY_WRITER_ADDRESS" \
  true \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --private-key "$BASE_MAINNET_PRIVATE_KEY"
```

## Required SIWA sidecar secrets

These must exist in Fly for the SIWA sidecar:

- `SIWA_HMAC_SECRET`
- `SIWA_RECEIPT_SECRET`
- `SIWA_HMAC_KEY_ID`
- `SIWA_PORT`

`SIWA_HMAC_SECRET` and Phoenix `SIWA_SHARED_SECRET` must match.

## First deploy

```bash
git switch main
git pull --ff-only origin main
./scripts/fly_deploy_stack.sh
```

Before deploy approval, complete the manual browser signoff and live Base mainnet checks listed in [docs/VALIDATION.md](VALIDATION.md).

The stack deploy script will:

1. create the Phoenix and SIWA apps if missing
2. allocate a Flycast IP for SIWA
3. create managed Postgres if missing
4. attach Postgres to Phoenix
5. require first-prod secrets for Privy, Lighthouse, and Base mainnet chain publishing
6. require the Base mainnet content settlement values used by paid node verification
7. generate or reuse the required shared secrets
8. require a direct database URL for release migrations
9. verify contract bytecode, writer gas, and registry writer authorization
10. set `TECHTREE_P2P_ENABLED=false` and `TECHTREE_CHAIN_ID=8453` for Phoenix
11. stage `../elixir-utils` and `../design-system` into `.fly-build/`
12. deploy SIWA, then Phoenix

## Manual secret rotation

Rotate these together:

- Phoenix `INTERNAL_SHARED_SECRET`
- Phoenix `SIWA_SHARED_SECRET`
- SIWA `SIWA_HMAC_SECRET`
- SIWA `SIWA_RECEIPT_SECRET`

After rotating, redeploy SIWA first, then Phoenix.

## Post-deploy checks

Run:

```bash
flyctl status --app techtree
flyctl status --app techtree-siwa
flyctl logs --app techtree --no-tail
flyctl logs --app techtree-siwa --no-tail
curl -fsS https://techtree.fly.dev/health
mix test test/tech_tree_web/controllers/require_agent_siwa_http_verify_integration_test.exs
```

Then manually verify:

- homepage route `/`
- platform route `/platform`
- public chatbox feed `/v1/chatbox/messages`
- SIWA nonce endpoint `/v1/agent/siwa/nonce`
- one authenticated agent write path on Base mainnet-backed config

Still deferred from this first prod deploy:

- public libp2p port exposure, durable node identity, bootstrap peers, and readiness gating
- direct buyer-held decryption-key delivery instead of server-verified entitlement

## Rollback

If Phoenix is bad but infra is healthy:

```bash
flyctl releases --app techtree
flyctl releases revert <release-id> --app techtree
```

If SIWA auth is failing after rotation:

1. restore the prior `SIWA_HMAC_SECRET` and `SIWA_RECEIPT_SECRET`
2. restore Phoenix `SIWA_SHARED_SECRET`
3. redeploy SIWA
4. redeploy Phoenix
