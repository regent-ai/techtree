This repository uses the root workflow as the canonical agent orchestration layer.

`AGENTS.md` is the short working map for Techtree. Keep it current. Do not turn it into an encyclopedia.

## Start Here

1. Read [WORKFLOW.md](WORKFLOW.md) for the active workflow contract.
2. Read [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md) for repo routing.
3. Read the policy docs that match the task:
   - [docs/regent-cli/README.md](docs/regent-cli/README.md) when the task also touches the standalone Regent CLI repo
   - [docs/AGENTS_BBH_UI.md](docs/AGENTS_BBH_UI.md) for BBH surface work
   - [docs/AUTH_BOUNDARY_AUDIT.md](docs/AUTH_BOUNDARY_AUDIT.md) for auth and trust-boundary work
   - [docs/SECURITY.md](docs/SECURITY.md)
   - [docs/VALIDATION.md](docs/VALIDATION.md)

## Product And Chain Story

- Techtree starts on Base mainnet as the first live testbed.
- Techtree will also deploy on Ethereum mainnet shortly after.
- `$TECH` lives on Ethereum mainnet.
- TECH emissions start on Ethereum mainnet only.
- Do not flatten these into one vague “mainnet” story. Base testbed work, Ethereum mainnet identity, and TECH emissions are related but not interchangeable.
- Keep Techtree chain language separate from Autolaunch chain language. Autolaunch is Ethereum-mainnet-first. Techtree spans Base and Ethereum concerns.

## Core Rules

- Hard cutover only. Do not add backwards compatibility shims, migration glue, or dual paths unless explicitly requested.
- The root workflow is single-source-of-truth for agent execution. Do not revive the old `.claude` command flow.
- If work changes code in `/Users/sean/Documents/regent/techtree`, `/Users/sean/Documents/regent/regent-cli`, or `/Users/sean/Documents/regent/contracts`, it is not done until validation has been run in all three repos. Run `mix precommit` in `techtree`, `pnpm build`, `pnpm typecheck`, and `pnpm test` in `regent-cli`, and `forge test --offline` from `/Users/sean/Documents/regent/contracts/techtree` for the Techtree contracts workspace.
- Use `mix precommit` for Phoenix validation when touching app code.
- Use `Req` for Elixir HTTP calls. Do not introduce `:httpoison`, `:tesla`, or `:httpc`.
- Use Foundry for contract development and testing.
- Regent CLI live transport flows are daemon-owned. Do not add direct CLI-to-Phoenix socket paths.
- Prefer repository-local, versioned docs over off-repo context.
- Regent CLI terminal UI work should use the shared CLI palette unless a human explicitly asks for a different one:
  - `#315569` Charcoal Blue
  - `#034568` Yale Blue
  - `#FBF4DE` Ivory Mist
  - `#D4A756` Sunlit Clay
  - `#848078` Grey Olive

## Permanent Owner Map

Use these ownership lines when delegating work or deciding who should review a task first.

### 1. Techtree Frontend

Hand work here when the task is mainly browser UI, LiveView rendering, TypeScript hooks, frontend copy, page structure, interaction polish, or browser-facing flows.

Open these files first:
- `lib/tech_tree_web/router.ex`
- `lib/tech_tree_web/live/home_live.ex`
- `lib/tech_tree_web/controllers/page_controller.ex`
- `lib/tech_tree_web/controllers/page_html/home.html.heex`
- `lib/tech_tree_web/components/home_components.ex`
- `lib/tech_tree_web/components/platform_components.ex`
- `assets/js/app.ts`
- `assets/js/hooks/index.ts`

Main risk:
- LiveView templates and browser-side hooks are tightly coupled. UI changes often require matching hook updates.

### 2. Techtree Backend + DB + SIWA Sidecar

Hand work here when the task is mainly Phoenix routes, controllers, contexts, database shape, auth/session handling, protected routes, internal APIs, or the SIWA sidecar trust boundary.

Open these files first:
- `lib/tech_tree/application.ex`
- `lib/tech_tree_web/router.ex`
- `lib/tech_tree_web/controllers/agent_siwa_controller.ex`
- `lib/tech_tree_web/controllers/platform_auth_controller.ex`
- `lib/tech_tree_web/plugs/require_agent_siwa.ex`
- `lib/tech_tree_web/plugs/load_current_human.ex`
- `lib/tech_tree/accounts.ex`
- `lib/tech_tree/agents.ex`
- `priv/repo/migrations/20260304020000_create_techtree_schema.exs`
- `services/siwa-sidecar/src/server.ts`

Main risks:
- Privy browser auth and SIWA agent auth are different paths with different failure modes.
- DB migrations and trust-boundary changes are high-risk by default.

### 3. Techtree Contracts

Hand work here when the task is mainly onchain semantics, TECH token logic, staking, emissions, registry behavior, deploy scripts, Foundry tests, or app/CLI wording that must stay aligned with contract reality.

Open these files first:
- `/Users/sean/Documents/regent/contracts/techtree/README.md`
- `/Users/sean/Documents/regent/contracts/techtree/AGENTS.md`
- `/Users/sean/Documents/regent/contracts/techtree/src/TechTreeRegistry.sol`
- `/Users/sean/Documents/regent/contracts/techtree/src/TechToken.sol`
- `/Users/sean/Documents/regent/contracts/techtree/src/TechStakingVote.sol`
- `/Users/sean/Documents/regent/contracts/techtree/src/TechEmissionController.sol`
- `/Users/sean/Documents/regent/contracts/techtree/script/DeployTechTreeRegistry.s.sol`
- `/Users/sean/Documents/regent/contracts/techtree/test/utils/TechContractsBase.sol`

Main risks:
- Terminology drift between app, CLI, and contracts.
- Chain-language mistakes around Base versus Ethereum.
- Staking and emission math changes that look small but break invariants.

### 4. Regent CLI Local Setup + Packaging + CI/CD

Hand work here when the task is mainly local setup, runtime bootstrapping, npm packaging, release flow, operator docs, CLI test coverage, or Techtree/Autolaunch command behavior in the CLI.

Open these files first:
- `/Users/sean/Documents/regent/regent-cli/README.md`
- `/Users/sean/Documents/regent/regent-cli/package.json`
- `/Users/sean/Documents/regent/regent-cli/packages/regent-cli/package.json`
- `/Users/sean/Documents/regent/regent-cli/packages/regent-cli/src/index.ts`
- `/Users/sean/Documents/regent/regent-cli/packages/regent-cli/src/commands/techtree-start.ts`
- `/Users/sean/Documents/regent/regent-cli/packages/regent-cli/src/internal-runtime/runtime.ts`
- `/Users/sean/Documents/regent/regent-cli/docs/autolaunch-cli.md`
- `/Users/sean/Documents/regent/regent-cli/docs/techtree-api-contract.md`
- `/Users/sean/Documents/regent/regent-cli/scripts/release-cli.sh`
- `/Users/sean/Documents/regent/regent-cli/scripts/packed-install-smoke.sh`

Main risks:
- The shipped package is nested under `packages/regent-cli`, so repo-root changes can be misleading.
- CLI changes often need matching Techtree API or auth-contract updates.
- Release and CI wiring are easy to miss because some validation lives from the Techtree side.

## Protected Work

The following work must never be auto-picked by autonomous agents unless a human explicitly assigns it:

- the shared contracts repo at `/Users/sean/Documents/regent/contracts`, including `/Users/sean/Documents/regent/contracts/techtree` and `/Users/sean/Documents/regent/contracts/autolaunch`
- security-sensitive auth or trust-boundary changes
- deploy and Fly.io changes
- database migrations and schema transitions
- billing, payment, or value-transfer flows

See [docs/SECURITY.md](docs/SECURITY.md) for the full policy.
