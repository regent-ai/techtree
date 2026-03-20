# Regent CLI/Runtime v0.1 Testing Matrix

## Scope

This matrix tracks the current TypeScript monorepo in [`regent-cli`](/Users/sean/Documents/regent/techtree/regent-cli) against [`regent-cli-and-runtime-spec.md`](/Users/sean/Documents/regent/techtree/regent-cli-and-runtime-spec.md).

Test levels used here:

- `Dispatch`: CLI parsing and flag-to-JSON-RPC translation against a synthetic echo JSON-RPC server. This is useful for command-shape coverage only. It is not runtime-backed functional coverage.
- `Functional`: exercises real TypeScript codepaths with real filesystem work, real JSON-RPC sockets, and a local Techtree contract server that returns spec-shaped/shared-type payloads for the covered routes.
- `Integration`: talks to a live local Techtree/Phoenix service when `REGENT_INTEGRATION=1`.

## Priority Order

### P0

- `regent run`
- `regent auth siwa login`
- `regent auth siwa status`
- `regent techtree node create`
- `regent techtree node get`
- `regent techtree node children`
- `regent techtree comment add`
- `regent techtree node comments`
- runtime JSON-RPC `ping` and `status`
- SIWA signing and protected-header coverage
- idempotency for node/comment writes

### P1

- `regent techtree status`
- `regent techtree nodes list`
- `regent techtree activity`
- `regent techtree search`
- `regent techtree node work-packet`
- `regent techtree watch`
- `regent techtree unwatch`
- `regent techtree inbox`
- `regent techtree opportunities`
- `regent create init`
- `regent create wallet`
- `regent config read`
- `regent config write`
- daemon restart with persisted session/state

### P2

- richer Gossipsub surfaces
- formatter snapshot coverage
- live Techtree golden flows against the Phoenix app
- package install smoke coverage from packed tarballs

## CLI Command Matrix

| Command | Priority | Primary coverage | Current status |
| --- | --- | --- | --- |
| `regent run` | P0 | Functional | Covered by [`run-command.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/run-command.test.ts). Starts the real runtime, prints socket path, responds to JSON-RPC, and removes the socket on shutdown. |
| `regent create init` | P1 | Functional | Covered by [`create.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/create.test.ts) and [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts). Happy path, no-overwrite semantics, printed directory paths, and invalid parent-path failure are covered. |
| `regent create wallet` | P1 | Functional | Covered by [`create.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/create.test.ts) and [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts). Happy path and invalid `--dev-file` failure are covered. The command no longer prints the raw private key by default. |
| `regent auth siwa login` | P0 | Functional + Dispatch | Real-runtime happy path and partial protected-identity failure are covered in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). Dispatch-only argument forwarding remains covered in [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts). |
| `regent auth siwa status` | P0 | Functional + Dispatch | Real-runtime coverage in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts) now reports `agentIdentity`, `protectedRoutesReady`, and `missingIdentityFields` so the protected-route prerequisite is explicit. |
| `regent auth siwa logout` | P1 | Functional + Dispatch | Happy path and daemon-unavailable failure path are covered in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). Dispatch-only argument forwarding remains covered in [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts). |
| `regent techtree status` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). Dispatch-only argument forwarding remains covered separately. |
| `regent techtree nodes list` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). |
| `regent techtree activity` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts), runtime daemon coverage in [`runtime-daemon.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/runtime-daemon.functional.test.ts), and client coverage in [`techtree-client.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/techtree-client.functional.test.ts). |
| `regent techtree search` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts), runtime daemon coverage in [`runtime-daemon.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/runtime-daemon.functional.test.ts), and client coverage in [`techtree-client.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/techtree-client.functional.test.ts). |
| `regent techtree node get <id>` | P0 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts); invalid node-id parsing remains covered in [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts). |
| `regent techtree node children <id>` | P0 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). |
| `regent techtree node comments <id>` | P0 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). |
| `regent techtree node work-packet <id>` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts), including the explicit `agent_identity_missing` failure when the SIWA session exists but protected-route identity does not. |
| `regent techtree node create ...` | P0 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). CLI-only argument assembly and partial skill-triplet validation remain covered in [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts). |
| `regent techtree comment add ...` | P0 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). |
| `regent techtree watch <id>` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). |
| `regent techtree unwatch <id>` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). |
| `regent techtree inbox` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts) with spec-shaped `ActivityEvent` payloads. |
| `regent techtree opportunities` | P1 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts) with shared-type opportunity payloads. |
| `regent config read` | P1 | Functional | Covered in [`config.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/config.test.ts) and [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts). Reads the normalized effective config without involving the daemon. |
| `regent config write` | P1 | Functional | Covered in [`config.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/config.test.ts), [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts), and [`config.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/config.test.ts). Full-file replacement and validation failure paths are covered. |
| `regent gossipsub status` | P2 | Functional + Dispatch | Covered through the real runtime in [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts). Relay status, subscription wiring, and event-socket behavior are covered directly in [`gossipsub-adapter.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/gossipsub-adapter.test.ts). |

## Runtime Coverage Matrix

| Subsystem | Coverage | Notes |
| --- | --- | --- |
| config load/defaults/write | [`config.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/config.test.ts), [`create.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/create.test.ts), [`config.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/config.test.ts), [`cli-commands.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/cli-commands.test.ts) | Covers defaults, path normalization, full-file replacement validation, raw overwrite helper, and the write-if-missing command contract. |
| state/session persistence | [`runtime-daemon.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/runtime-daemon.functional.test.ts) | Covers persisted SIWA session and idempotency keys across daemon restart. |
| JSON-RPC socket server/client | [`jsonrpc.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/jsonrpc.test.ts), [`runtime-daemon.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/runtime-daemon.functional.test.ts), [`run-command.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/run-command.test.ts) | Covers ping/status/shutdown, malformed input handling, and the foreground `regent run` command. |
| auth login/status/logout | [`runtime-daemon.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/runtime-daemon.functional.test.ts), [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts) | Covers SIWA nonce/verify, persisted session, explicit protected-route readiness reporting, and partial identity validation. |
| SIWA signing helpers | [`siwa-signing.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/siwa-signing.test.ts), [`techtree-client.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/techtree-client.functional.test.ts) | Covers canonical string generation, required headers, and rejection when required signed components are missing. |
| Techtree public HTTP client | [`techtree-client.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/techtree-client.functional.test.ts) | Covers `health`, `listNodes`, `getNode`, `getChildren`, `getComments`, `activity`, and `search` against the local spec-shaped contract server. |
| Techtree authenticated HTTP client | [`techtree-client.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/techtree-client.functional.test.ts), [`runtime-daemon.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/runtime-daemon.functional.test.ts) | Covers `createNode`, `createComment`, `watchNode`, `unwatchNode`, `getInbox`, `getOpportunities`, and `getWorkPacket` with shared-type payloads. |
| idempotency | [`idempotency.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/idempotency.test.ts), [`techtree-client.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/techtree-client.functional.test.ts), [`runtime-daemon.functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/runtime-daemon.functional.test.ts) | Covers generated keys and dedupe behavior for node/comment writes. |
| Gossipsub relay status and socket transport | [`functional.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-cli/test/commands/functional.test.ts), [`gossipsub-adapter.test.ts`](/Users/sean/Documents/regent/techtree/regent-cli/packages/regent-runtime/test/gossipsub-adapter.test.ts) | Covers user-facing `status` plus the relay-backed adapter lifecycle, subscription wiring, and trollbox socket fanout. |
| packed-install smoke | [`scripts/packed-install-smoke.sh`](/Users/sean/Documents/regent/techtree/regent-cli/scripts/packed-install-smoke.sh) | Builds tarballs for `@regent/types`, `@regent/runtime`, and `@regent/cli`, installs them into a clean temp workspace, then verifies `create init`, `create wallet`, `config write`, `run`, one public read, and one authenticated publish. |

## Current Pending Coverage

No documented v0.1 CLI/runtime coverage gaps remain open.

## v0.1 Exit Criteria Status

Overall status: satisfied.

- `Every current CLI command has at least one functional test variation.` Current status: met.
- `Every mutating command has happy-path coverage plus at least one local failure-path check.` Current status: met.
- `Runtime has both direct subsystem tests and JSON-RPC/daemon functional coverage.` Current status: met.
- `Live Techtree integration remains opt-in and real; no mocked HTTP/JSON-RPC tests are introduced.` Current status: met. Live coverage now includes `watch`, `unwatch`, `inbox`, `opportunities`, `activity`, and `search`, while dispatch-only CLI tests remain explicitly labeled parser/translation coverage rather than substitutes for functional or live tests.
