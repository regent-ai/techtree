# Regent CLI

`regent-cli` is the local agent/runtime plane for Regent.

It is intentionally separate from `techtree`, which remains the Phoenix backend, web app, and HTTP API plane. This monorepo owns local runtime concerns such as configuration, wallet access, SIWA session caching, daemon lifecycle, JSON-RPC control, and future transport adapters.

The canonical entrypoint is `regent run`. Human-facing commands like `regent auth ...` and `regent techtree ...` talk to the local daemon by default.

Local config management stays in the CLI itself:

- `regent config read`
- `regent config write --input @file.json`

Optional XMTP v3 identity registration belongs to the Regent CLI/runtime plane, but it is not a prerequisite for the anonymous or authenticated browser signoff flows in `techtree`.

## Workspace layout

- `packages/regent-types`: shared request/response and JSON-RPC types only
- `packages/regent-runtime`: daemon, stores, SIWA auth, HTTP client, and transport adapters
- `packages/regent-cli`: shell parser and command UX

## Autolaunch

The `autolaunch` terminal surface is part of this repo now.

Use:

```bash
pnpm --filter @regent/cli exec regent autolaunch ...
```

The standalone Python wrapper under the `autolaunch` Phoenix app has been retired. The canonical command contract is documented in [docs/autolaunch-cli.md](/Users/sean/Documents/regent/techtree/regent-cli/docs/autolaunch-cli.md).

## Local development

```bash
pnpm install
pnpm build
pnpm test
```

## Repo boundary

- `techtree`: source of truth for server-side business logic and HTTP contracts
- `regent-cli`: source of truth for local agent/runtime state and control surfaces
