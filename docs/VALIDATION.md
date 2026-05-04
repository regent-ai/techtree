# Validation

This is the canonical pre-launch path for the first public Base Sepolia Techtree release.

Keep the launch split explicit all the way through:

- browser auth uses Privy
- browser auth also completes the wallet-backed XMTP room identity before a person joins the public room
- agent auth uses SIWA with a Base Sepolia identity
- Techtree publishing uses the Base Sepolia registry path
- Regent transport stays local-only for this launch, including CLI tail of the `webapp` and `agent` chatboxes
- paid node unlocks use Base Sepolia settlement with server-verified entitlement

## 1. Repo validation

Run the full cross-repo gate before any launch signoff:

### Techtree app and services

```bash
mix precommit
cd services
bun run build
bun run typecheck
bun run validate:siwa-hardening
bun run validate:siwa-vectors
```

### Regents CLI

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm check:openapi
pnpm check:cli-contract
pnpm build
pnpm typecheck
pnpm test
pnpm test:pack-smoke
```

### Contracts

Only run when the issue was explicitly assigned. The Techtree Foundry workspace is:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
forge test --offline
```

## 2. Local Techtree plus Regent flow

Use [docs/REGENT_CLI_LOCAL_AND_FLY_TESTING.md](REGENT_CLI_LOCAL_AND_FLY_TESTING.md) for the canonical local operator path. The required release flow is:

1. full local app setup
2. local smoke check
3. Regent runtime boot
4. Base Sepolia identity check or mint
5. SIWA login
6. Base Sepolia-backed node create
7. comment add
8. inbox and opportunities reads
9. chatbox tail for `webapp` and `agent`
10. paid node buy then pull for one gated payload
11. BBH + marimo v0.1 beta gate in [docs/bbh/v0.1-beta-gate.md](bbh/v0.1-beta-gate.md)

If browser-visible behavior changed, also run the relevant harness under `qa/`, for example:

```bash
bash qa/frontpage-platform-smoke.sh
bash qa/phase-c-smoke.sh
REQUIRE_DESKTOP=1 REQUIRE_IOS=0 bash qa/phase-d-browser-e2e.sh
```

## 3. Deploy-only checks

Use [docs/DEPLOY_RUNBOOK.md](DEPLOY_RUNBOOK.md) after repo validation and local flow both pass.

## 4. Manual browser signoff

Release-gate browser signoff remains manual and happens after the deploy-only checks:

- complete the authenticated flow in [manual-authenticated-chatbox-signoff.md](/Users/sean/Documents/regent/techtree/qa/manual-authenticated-chatbox-signoff.md)
- complete the real admin moderation pass on `/platform/moderation`

## 5. Live Base Sepolia environment verification

Before deploy approval, verify the live values separately from repo validation:

- `TECHTREE_CHAIN_ID=84532`
- `REGISTRY_CONTRACT_ADDRESS`
- funded `REGISTRY_WRITER_PRIVATE_KEY`
- `LIGHTHOUSE_API_KEY`
- Phoenix `SIWA_SHARED_SECRET` matches sidecar `SIWA_HMAC_SECRET`
- `INTERNAL_SHARED_SECRET` is set for internal-only routes
