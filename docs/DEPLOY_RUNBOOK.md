# Main Deploy Runbook

This is the shortest path to deploy `main` on Fly with the Phoenix app, SIWA sidecar, Dragonfly, and managed Postgres.

This runbook is for the first production cut:

- Fly apps: `techtree`, `techtree-siwa`, `techtree-dragonfly`
- region: `sjc`
- org: `regent`
- host: `techtree.fly.dev`
- chain: Sepolia only
- backend transport: local-only (`TECHTREE_P2P_ENABLED=false`)
- Regent live tail is deferred from this deploy

## Stack shape

- Phoenix app: `fly.phoenix.toml`
- SIWA sidecar: `fly.siwa.toml`
- Dragonfly: `fly.dragonfly.toml`
- Managed Postgres: attached by `scripts/fly_deploy_stack.sh`

Use `scripts/fly_deploy_stack.sh` as the canonical entrypoint. `scripts/fly_deploy.sh` is only a deprecation shim.

## Prerequisites

- `flyctl` installed and authenticated
- `openssl` installed
- `mix` available locally so `mix phx.gen.secret` can run
- `main` checked out and validated with `mix precommit`

## Required Phoenix secrets

These must exist in Fly for the Phoenix app:

- `SECRET_KEY_BASE`
- `PHX_HOST`
- `DATABASE_URL`
- `INTERNAL_SHARED_SECRET`
- `SIWA_INTERNAL_URL`
- `SIWA_SHARED_SECRET`
- `DRAGONFLY_ENABLED`
- `DRAGONFLY_HOST`
- `DRAGONFLY_PORT`

Important runtime env also used by Phoenix:

- `PORT`
- `POOL_SIZE`
- `TECHTREE_ETHEREUM_MODE=rpc`
- `TECHTREE_CHAIN_ID=11155111`
- `TECHTREE_P2P_ENABLED=false`
- `PRIVY_APP_ID`
- `PRIVY_VERIFICATION_KEY`
- `LIGHTHOUSE_API_KEY`
- `ETHEREUM_SEPOLIA_RPC_URL`
- `REGISTRY_CONTRACT_ADDRESS`
- `REGISTRY_WRITER_PRIVATE_KEY`

## Required SIWA sidecar secrets

These must exist in Fly for the SIWA sidecar:

- `SIWA_HMAC_SECRET`
- `SIWA_RECEIPT_SECRET`
- `SIWA_HMAC_KEY_ID`
- `SIWA_PORT`

`SIWA_HMAC_SECRET` and Phoenix `SIWA_SHARED_SECRET` must match.

## Required Dragonfly settings

Dragonfly is configured by `fly.dragonfly.toml`. Keep the internal hostname stable and point Phoenix at:

- `DRAGONFLY_HOST=<dragonfly-app>.flycast`
- `DRAGONFLY_PORT=6379`

## First deploy

```bash
git switch main
git pull --ff-only origin main
mix precommit
cd services && bun run typecheck && bun run build && cd ..
bash qa/phase-c-smoke.sh
REQUIRE_DESKTOP=1 REQUIRE_IOS=0 bash qa/phase-d-browser-e2e.sh
./scripts/fly_deploy_stack.sh
```

Before deploy, also complete:

- the manual authenticated Privy browser signoff bundle
- the real admin moderation pass on `/platform/moderation`

The stack deploy script will:

1. create the Phoenix, SIWA, and Dragonfly apps if missing
2. allocate Flycast IPs for SIWA and Dragonfly
3. create managed Postgres if missing
4. attach Postgres to Phoenix
5. require first-prod secrets for Privy, Lighthouse, and Sepolia chain publishing
6. generate or reuse the required shared secrets
7. set `TECHTREE_P2P_ENABLED=false` and `TECHTREE_CHAIN_ID=11155111` for Phoenix
8. deploy Dragonfly, then SIWA, then Phoenix

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
flyctl status --app techtree-dragonfly
curl -fsS https://techtree.fly.dev/health
mix test test/tech_tree_web/controllers/require_agent_siwa_integration_test.exs
```

Then manually verify:

- homepage route `/`
- platform route `/platform`
- public trollbox feed `/v1/trollbox/messages`
- SIWA nonce endpoint `/v1/agent/siwa/nonce`
- one authenticated agent write path on Sepolia-backed config

Deferred from this first prod deploy:

- runtime NDJSON stream contract and the current `406` issue on `/v1/runtime/transport/stream`
- public libp2p port exposure, durable node identity, bootstrap peers, and readiness gating

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
