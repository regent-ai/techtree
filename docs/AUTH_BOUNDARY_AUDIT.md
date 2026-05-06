# Auth Boundary Audit

Audit date: 2026-04-28

Scope:

- `TechTreeWeb.Plugs.RequireAgentSiwa`
- `TechTreeWeb.Plugs.RequirePrivyJWT`
- `TechTreeWeb.Plugs.RequireInternalSharedSecret`
- `TechTreeWeb.PlatformAuthController`
- shared `siwa-server` integration

## Fixed in this pass

1. Runtime write endpoints now stay behind agent-authenticated routes

- public runtime HTTP routes are read-only
- runtime publish, validation, and challenge writes live under `/v1/agent/runtime/*`
- removed unused runtime controller actions that accepted a local workspace `path` in the request body
- added checks that the OpenAPI contract and Phoenix router keep this split

2. Public request bodies no longer expose local runtime workspace paths

- confirmed network-facing compile, pin, and prepare publish routes are absent from the OpenAPI contract
- confirmed the router does not expose public runtime write routes that accept local filesystem paths

## Remaining path-shaped fields

These fields remain in the contract because they describe files inside published BBH source manifests or response metadata, not public unauthenticated upload instructions:

- `BbhRunSource.paths` and `BbhRunPaths.*`: agent-authenticated BBH run source metadata for files inside a submitted workspace bundle
- `BbhArtifactManifestEntry.path`: path inside a submitted artifact manifest, paired with a hash
- `BbhReviewSource.paths.*`: agent-authenticated validation/review metadata for reproduced outputs
- `ScienceTask* export_target_path`, `protocol_path`, and `rubric_path`: persisted task metadata and response fields

The public runtime write surface should continue to use submitted manifests, CIDs, run IDs, and node IDs rather than raw local filesystem paths.

3. Techtree-owned SIWA service removed

- Techtree now calls the shared `siwa-server` directly
- Techtree no longer owns SIWA HMAC or receipt-signing secrets

4. Internal shared-secret plug now fails closed outside tests

- previous behavior allowed internal routes through when the shared secret was unset
- current behavior only permits the empty-secret bypass in `:test`

## Re-checked and acceptable

1. `RequireAgentSiwa`

- requires the shared SIWA verification path before write handlers run
- rejects missing or malformed Techtree agent headers before protected writes run
- leaves SIWA receipt parsing, receipt binding, nonce/replay, and HTTP-signature verification to shared `siwa-server`
- still checks agent status after shared SIWA confirms the envelope

2. `RequirePrivyJWT`

- still validates issuer, audience, expiration, `nbf`, and `iat`
- still rejects malformed bearer headers

3. `PlatformAuthController`

- only persists `display_name`, `wallet_address`, and the current XMTP inbox id for that wallet
- does not trust client-supplied roles
- requires a valid Privy bearer token before it writes the browser session
- writes the browser session only after Privy JWT verification succeeds
- requires a connected wallet address before it opens the browser session
- creates or reopens the stored XMTP inbox id during session setup and uses a second wallet-sign step when the inbox is not ready yet
- clears only the Privy session key on logout instead of dropping the full browser session

## Residual launch checks

- ensure `INTERNAL_SHARED_SECRET` is set before any internal-only HTTP route is re-enabled
- ensure `SIWA_INTERNAL_URL` points at the shared `siwa-server`
- verify production Privy keys before the first live deploy
