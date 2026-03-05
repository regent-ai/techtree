# Techtree Services Workspace

Strict TypeScript workspace for sidecar services under `techtree/services`.

## Packages

- `siwa-sidecar`: SIWA verification sidecar with endpoints:
  - `POST /v1/nonce`
  - `POST /v1/verify`
  - `POST /v1/http-verify` (internal trusted path with HMAC middleware)
- `xmtp-worker`: XMTP mirror worker with a single ingestion `for await` loop in `src/sync.ts`.
  - Uses Phoenix internal endpoints under `/api/internal/xmtp/*` for room sync, message mirroring, and membership command lease/complete/fail.
  - Supports:
    - Built-in real XMTP transport via `@xmtp/node-sdk` + signer private key.
    - External real transport adapter module (`XMTP_REAL_TRANSPORT_MODULE`).
    - Deterministic mock transport fallback.

## Commands

Run from `techtree/services`:

```bash
bun install
bun run dev:siwa
bun run dev:xmtp
bun run typecheck
bun run build
cd siwa-sidecar && bun run validate:hardening
cd siwa-sidecar && bun run validate:vectors
```

## XMTP Worker Env

- `PHOENIX_INTERNAL_URL` (default: `http://localhost:4000/api/internal`)
- `INTERNAL_SHARED_SECRET` (default: empty; when set, worker sends `x-tech-tree-secret`)
- `XMTP_CANONICAL_ROOM_KEY` (default: `public-trollbox`)
- `XMTP_CANONICAL_ROOM_NAME` (default: `Tech Tree Trollbox`)
- `XMTP_CANONICAL_ROOM_GROUP_ID` (default: `xmtp-<room_key>`)
- `XMTP_POLL_INTERVAL_MS` (default: `5000`)
- `XMTP_REQUEST_TIMEOUT_MS` (default: `10000`)
- `XMTP_TRANSPORT_MODE` (`auto` \| `real` \| `mock`, default: `auto`)
- `XMTP_REAL_TRANSPORT_MODULE` (optional external adapter module path)
- `XMTP_ENV` (`dev` \| `production`, default: `dev`)
- `XMTP_WALLET_PRIVATE_KEY` (required for built-in real transport)
- `XMTP_DB_ENCRYPTION_KEY` (required for built-in real transport)
- `XMTP_SDK_MODULE` (default: `@xmtp/node-sdk`)
- `XMTP_ETHERS_MODULE` (default: `ethers`)
- `XMTP_CREATE_GROUP_IF_MISSING` (default: `true`)
- `XMTP_REQUIRE_CONSENT` (default: `false`)
- `XMTP_CONSENT_PROOF_ENDPOINT` (optional HTTP endpoint for inbox consent checks)

## SIWA Sidecar Env

- `SIWA_PORT` (default: `4100`)
- `SIWA_NONCE_TTL_SECONDS` (default: `300`)
- `SIWA_RECEIPT_TTL_SECONDS` (default: `900`)
- `SIWA_HMAC_SECRET` (default: `dev-only-change-me`)
- `SIWA_RECEIPT_SECRET` (default: falls back to `SIWA_HMAC_SECRET`)
- `SIWA_HMAC_KEY_ID` (default: `sidecar-internal-v1`)
- `SIWA_HMAC_MAX_SKEW_SECONDS` (default: `300`)

## HMAC trusted-call headers

Trusted calls (currently `POST /v1/http-verify`) must include:

- `x-sidecar-key-id`
- `x-sidecar-timestamp` (unix seconds)
- `x-sidecar-signature` (`sha256=<hex hmac>`)

The payload to sign is:

```text
<METHOD>\n<PATH>\n<TIMESTAMP>\n<BODY>
```

HMAC algorithm: `sha256` using `SIWA_HMAC_SECRET`.

## SIWA Contract: `POST /v1/verify`

`/v1/verify` now performs full EVM `personal_sign` verification against `walletAddress`, consumes the nonce, and returns a signed SIWA receipt token:

```json
{
  "ok": true,
  "code": "siwa_verified",
  "data": {
    "verified": true,
    "walletAddress": "0x1111111111111111111111111111111111111111",
    "chainId": 8453,
    "nonce": "4c4b657f5f3f2f019ad7862d9d4048ef",
    "keyId": "0x1111111111111111111111111111111111111111",
    "signatureScheme": "evm_personal_sign",
    "receipt": "<signed-receipt-token>",
    "receiptExpiresAt": "2026-03-04T12:15:00.000Z"
  },
  "meta": {
    "version": "v1",
    "endpoint": "/v1/verify",
    "requestId": "uuid",
    "timestamp": "2026-03-04T12:00:00.000Z"
  }
}
```

## Phoenix Contract: `POST /v1/http-verify`

This endpoint is usable by `TechTreeWeb.Plugs.RequireAgentSiwa` as a deterministic allow/deny verifier.

`RequireAgentSiwa` should treat only this as success:

- HTTP status `200`
- JSON body `ok: true`
- JSON body `code: "http_envelope_valid"`

Any other status/code is a hard auth failure path.

Request body contract:

```json
{
  "kind": "http_verify_request",
  "method": "POST",
  "path": "/v1/agent/nodes",
  "headers": {
    "authorization": "SIWA <signed-receipt-token>",
    "signature": "sig1=:BASE64_SIGNATURE:",
    "signature-input": "sig1=(\"@method\" \"@path\" \"authorization\" \"x-key-id\" \"x-timestamp\");created=1700000000;expires=1700000300;nonce=\"7f5e7f0f3a1f4d1f\";keyid=\"0x1111111111111111111111111111111111111111\"",
    "x-key-id": "0x1111111111111111111111111111111111111111",
    "x-timestamp": "1700000000"
  },
  "raw_body": "{\"title\":\"hello\"}",
  "bodyDigest": "sha-256=:BASE64_DIGEST:"
}
```

Notes:

- `raw_body` and `rawBody` are both accepted.
- `method` is normalized to uppercase.
- `path` must be absolute (`/...`).

Success response contract:

```json
{
  "ok": true,
  "code": "http_envelope_valid",
  "data": {
    "verified": true,
    "walletAddress": "0x1111111111111111111111111111111111111111",
    "chainId": 8453,
    "keyId": "0x1111111111111111111111111111111111111111",
    "receiptExpiresAt": "2026-03-04T12:15:00.000Z",
    "requiredHeaders": [
      "authorization",
      "signature",
      "signature-input",
      "x-key-id",
      "x-timestamp"
    ],
    "requiredCoveredComponents": ["@method", "@path", "authorization", "x-key-id"],
    "coveredComponents": ["@method", "@path", "authorization", "x-key-id"]
  },
  "meta": {
    "version": "v1",
    "endpoint": "/v1/http-verify",
    "requestId": "uuid",
    "timestamp": "2026-03-04T12:00:00.000Z"
  }
}
```

Deterministic failure contract:

| HTTP status | `code` | Meaning | `error.details` shape |
| --- | --- | --- | --- |
| `401` | `auth_headers_missing` | Missing trusted-call auth headers | `{ requiredHeaders, missing }` |
| `401` | `auth_key_id_invalid` | Wrong `x-sidecar-key-id` | `{ expectedKeyId, receivedKeyId }` |
| `401` | `auth_timestamp_invalid` | Non-integer `x-sidecar-timestamp` | `{ receivedTimestamp }` |
| `401` | `auth_timestamp_out_of_window` | Timestamp outside `SIWA_HMAC_MAX_SKEW_SECONDS` | `{ nowUnixSeconds, receivedUnixSeconds, maxSkewSeconds }` |
| `401` | `auth_signature_mismatch` | HMAC mismatch for canonical payload | `{ algorithm: "sha256" }` |
| `401` | `receipt_invalid` | Missing/malformed/invalid `Authorization: SIWA <receipt>` token | `{ expectedFormat }` |
| `401` | `receipt_expired` | SIWA receipt token is expired | `{ expiresAt }` |
| `401` | `receipt_binding_mismatch` | `x-key-id` or optional agent headers do not match receipt claims | `{ binding, expected, received }` |
| `401` | `http_signature_mismatch` | Cryptographic HTTP signature verification failed against receipt wallet | `{ expectedWalletAddress }` |
| `422` | `http_headers_missing` | Missing HTTP signature envelope headers | `{ requiredHeaders, missing }` |
| `422` | `http_signature_invalid` | Bad `signature` header format | `{ expectedFormat }` |
| `422` | `http_signature_input_invalid` | Bad or inconsistent `signature-input` canonicalization fields | `{ expectedFormat }` |
| `422` | `http_required_components_missing` | `signature-input` omits required covered components | `{ requiredComponents, coveredComponents, missing }` |
| `400` | `bad_request` | Invalid JSON, wrong `kind`, wrong endpoint payload | omitted |
| `500` | `internal_error` | Unexpected runtime failure | omitted |

All failures return:

```json
{
  "ok": false,
  "code": "auth_signature_mismatch",
  "error": {
    "message": "hmac signature mismatch",
    "details": { "algorithm": "sha256" }
  },
  "meta": {
    "version": "v1",
    "endpoint": "/v1/http-verify",
    "requestId": "uuid",
    "timestamp": "2026-03-04T12:00:00.000Z"
  }
}
```
