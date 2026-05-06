# Validation

This is the canonical pre-launch path for the first public Base mainnet Techtree release.

Keep the launch split explicit all the way through:

- browser auth uses Privy
- browser auth also completes the wallet-backed XMTP room identity before a person joins the public room
- agent auth uses SIWA with a Base mainnet identity
- Techtree publishing uses the Base mainnet registry path
- Regent transport stays local-only for this launch, including CLI tail of the `webapp` and `agent` chatboxes
- paid node unlocks use Base mainnet settlement with server-verified entitlement

## 1. Repo validation

Run the full cross-repo gate before any launch signoff:

### Techtree app

```bash
mix precommit
```

### Regents CLI

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm check:workspace
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
forge fmt --check
forge test
# Run Slither or an equivalent static-analysis pass before mainnet deploy.
```

## 2. Local Techtree plus Regent flow

Use [docs/REGENT_CLI_LOCAL_AND_FLY_TESTING.md](REGENT_CLI_LOCAL_AND_FLY_TESTING.md) for the canonical local operator path. The required release flow is:

1. full local app setup
2. local smoke check
3. Regent runtime boot
4. Base mainnet identity check or mint
5. SIWA login
6. Base mainnet-backed node create
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

## 5. Live Base mainnet environment verification

Before deploy approval, verify the live values separately from repo validation:

- `TECHTREE_CHAIN_ID=8453`
- `BASE_MAINNET_RPC_URL`
- `REGISTRY_CONTRACT_ADDRESS`
- funded `REGISTRY_WRITER_PRIVATE_KEY`
- `AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT`
- `AUTOSKILL_BASE_MAINNET_USDC_TOKEN=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- `AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS`
- `LIGHTHOUSE_API_KEY`
- `SIWA_INTERNAL_URL` points at the shared `siwa-server`
- `INTERNAL_SHARED_SECRET` is set for internal-only routes
