# Cutover Follow-up Slices

Use these as the maintainability split after the large cutover landed.

## Slice 1: Frontpage shell and graph/grid interaction

Scope:

- `lib/tech_tree_web/live/frontpage_demo_live.ex`
- `assets/js/hooks/home-grid.ts`
- `assets/js/hooks/home-windows.ts`
- `assets/css/app.css`
- `test/tech_tree_web/live/frontpage_demo_live_test.exs`

Goal:

- keep homepage presentation, grid math, and top-level interaction isolated from platform and CLI work

## Slice 2: Platform data model and importer

Scope:

- `lib/tech_tree/platform.ex`
- `lib/tech_tree/platform/**`
- `lib/mix/tasks/tech_tree.platform.import.ex`
- `priv/repo/migrations/20260311100000_create_platform_surface.exs`
- `priv/repo/migrations/20260311103000_expand_node_search_document_sources.exs`
- `test/tech_tree/platform/**`
- `test/support/platform_fixtures.ex`

Goal:

- keep canonical platform read-model work independent from web-shell changes

## Slice 3: Platform LiveView surfaces

Scope:

- `lib/tech_tree_web/components/platform_components.ex`
- `lib/tech_tree_web/live/platform/**`
- `lib/tech_tree_web/controllers/platform_api/**`
- `lib/tech_tree_web/controllers/platform_auth_controller.ex`
- `test/tech_tree_web/live/platform_live_test.exs`
- `test/tech_tree_web/controllers/platform_api_controller_test.exs`
- `test/tech_tree_web/controllers/platform_auth_controller_test.exs`

Goal:

- keep Phoenix route and UX work separate from importer and auth internals

## Slice 4: Chatbox canonicalization

Scope:

- `lib/tech_tree/chatbox.ex`
- `lib/tech_tree/chatbox/**`
- `lib/tech_tree_web/channels/chatbox_channel.ex`
- `lib/tech_tree_web/controllers/chatbox_controller.ex`
- `lib/tech_tree_web/controllers/agent_chatbox_controller.ex`
- `priv/repo/migrations/20260312110000_create_chatbox_messages.exs`
- `test/tech_tree_web/controllers/chatbox_controller_test.exs`
- `test/tech_tree_web/controllers/agent_chatbox_controller_test.exs`

Goal:

- keep chat storage, relay, and moderation flow reviewable on its own

## Slice 5: Auth and internal service boundary hardening

Scope:

- `lib/tech_tree/privy.ex`
- `lib/tech_tree_web/plugs/require_agent_siwa.ex`
- `lib/tech_tree_web/plugs/require_privy_jwt.ex`
- `lib/tech_tree_web/plugs/require_internal_shared_secret.ex`
- `lib/tech_tree_web/controllers/agent_siwa_controller.ex`
- `services/siwa-sidecar/**`
- `test/tech_tree_web/controllers/require_agent_siwa_integration_test.exs`
- `test/tech_tree_web/plugs/**`

Goal:

- keep trust-boundary review small, explicit, and easy to audit

## Slice 6: Regents CLI and runtime

Scope:

- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/**`
- `/Users/sean/Documents/regent/regents-cli/test-support/**`
- `/Users/sean/Documents/regent/regents-cli/docs/**`

Goal:

- keep standalone CLI/runtime contract changes out of Phoenix review noise
