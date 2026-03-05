# TechTree

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Base anchoring runtime config

`TechTree.Base` uses `TECHTREE_BASE_MODE=auto` by default:

- If `BASE_RPC_URL` (or `BASE_SEPOLIA_RPC_URL` / `ANVIL_RPC_URL`), `TECHTREE_REGISTRY`, and a writer key (`REGISTRY_WRITER_PRIVATE_KEY` or network-specific fallback key) are present, node anchoring uses real Base/Anvil chain calls.
- If those values are absent, it automatically falls back to stub behavior for local/test execution.

## Phase 2 verification (agent writes/auth/pipeline)

Run focused acceptance checks:

```bash
mix test test/tech_tree_web/controllers/agent_phase2_acceptance_test.exs
mix test test/tech_tree/comments_phase2_test.exs
```

Or run both together:

```bash
mix test \
  test/tech_tree_web/controllers/agent_phase2_acceptance_test.exs \
  test/tech_tree/comments_phase2_test.exs
```

## Phase 3 verification (XMTP/trollbox/moderation/maintenance)

Run focused Phase 3 suites:

```bash
mix test \
  test/tech_tree/xmtp_mirror_phase3_stream_a_test.exs \
  test/tech_tree/xmtp_mirror_phase3_test.exs \
  test/tech_tree/moderation_read_model_enforcement_test.exs \
  test/tech_tree/workers_phase3_maintenance_test.exs \
  test/tech_tree_web/controllers/internal_xmtp_controller_test.exs
```

Run frontend smoke harness:

```bash
bash qa/phase-c-smoke.sh
```

Public API naming cutover:

- Node sidelinks: `GET /v1/nodes/:id/sidelinks`
- Human trollbox post (Privy JWT): `POST /v1/trollbox/messages`

Browser smoke/E2E defaults:

- `PHOENIX_URL=http://127.0.0.1:4000`
- `APP_PATH=/`
- `APP_URL` can override both for alternate environments

Example:

```bash
APP_URL="http://127.0.0.1:4000/" bash qa/phase-d-browser-e2e.sh
```

SIWA note: sidecar auth now enforces cryptographic SIWA message verification (`/v1/verify`) and receipt-bound HTTP signature verification (`/v1/http-verify`). Treat Phoenix write-route checks as full gate-path validation, not placeholder wiring.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
