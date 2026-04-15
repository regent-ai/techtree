# Auth Boundary Audit

Audit date: 2026-03-12

Scope:

- `TechTreeWeb.Plugs.RequireAgentSiwa`
- `TechTreeWeb.Plugs.RequirePrivyJWT`
- `TechTreeWeb.Plugs.RequireInternalSharedSecret`
- `TechTreeWeb.PlatformAuthController`
- `services/siwa-sidecar`

## Fixed in this pass

1. SIWA sidecar secret fallback removed

- previous behavior allowed boot with a development fallback secret
- current behavior requires both `SIWA_HMAC_SECRET` and `SIWA_RECEIPT_SECRET`

2. Internal shared-secret plug now fails closed outside tests

- previous behavior allowed internal routes through when the shared secret was unset
- current behavior only permits the empty-secret bypass in `:test`

## Re-checked and acceptable

1. `RequireAgentSiwa`

- still requires the sidecar verification path unless `skip_http_verify` is enabled in `:test`
- still rejects missing required agent headers before write handlers run
- still checks agent status after the sidecar confirms the envelope

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
- ensure Phoenix `SIWA_SHARED_SECRET` matches sidecar `SIWA_HMAC_SECRET`
- keep `skip_http_verify` limited to `:test`
- verify production Privy keys before the first live deploy
