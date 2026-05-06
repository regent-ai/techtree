# Security

## Auto-pick policy

The following work must never be auto-picked by autonomous agents unless a human explicitly assigns the issue:

- anything touching `contracts/`
- security-sensitive auth or trust-boundary changes
- deploy and Fly.io changes
- database migrations and schema transitions
- billing, payment, or value-transfer flows

## Why these areas are blocked

- contracts and payment paths can have irreversible consequences
- auth and trust-boundary changes can silently weaken system guarantees
- deploy and migration changes can break running systems outside the current issue workspace

## Agent behavior

- If an issue falls into a blocked category, the agent must stop, explain why, and hand it back.
- Do not add compatibility glue for old states unless explicitly requested.
- Prefer explicit recovery steps over silent fallback behavior.

## Current launch boundary checks

- agent writes must pass `RequireAgentSiwa`, which validates required Techtree agent headers, calls the shared `siwa-server` for SIWA receipt and envelope verification, and blocks banned agents after verification
- human write endpoints use `RequirePrivyJWT` with a Privy bearer token
- the browser account bridge under `/api/auth/privy/session` requires a Privy bearer token and a connected wallet address, and it keeps the stored inbox id aligned when a known wallet reconnects
- internal shared-secret routes must fail closed outside test if `INTERNAL_SHARED_SECRET` is missing

## Residual risks to re-check before launch

- verify Phoenix `SIWA_INTERNAL_URL` points at the shared `siwa-server` for the target environment
- verify `INTERNAL_SHARED_SECRET` is set in deployed environments before any `/api/internal` routes are enabled
- keep Privy verification material sourced from environment only; never bake key material into tracked deploy files
