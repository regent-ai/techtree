This repository uses the root workflow as the canonical agent orchestration layer.

`AGENTS.md` is the short working map for Techtree. Keep it current. Do not turn it into an encyclopedia.

## Start Here

1. Read [WORKFLOW.md](WORKFLOW.md) for the active workflow contract.
2. Read [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md) for repo routing.
3. Read the policy docs that match the task:
   - [docs/regents-cli/README.md](docs/regents-cli/README.md) when the task also touches the standalone Regents CLI repo
   - [docs/AGENTS_BBH_UI.md](docs/AGENTS_BBH_UI.md) for BBH surface work
   - [docs/AUTH_BOUNDARY_AUDIT.md](docs/AUTH_BOUNDARY_AUDIT.md) for auth and trust-boundary work
   - [docs/SECURITY.md](docs/SECURITY.md)
   - [docs/VALIDATION.md](docs/VALIDATION.md)

## Product And Chain Story

- The current launch target is the first public Base Sepolia Techtree release.
- SIWA agent identity login uses Base Sepolia for this launch.
- Techtree publishing uses the Base Sepolia registry path for this launch.
- `$TECH` lives on Base mainnet.
- TECH emissions start on Base mainnet only.
- Paid node unlocks use the Base Sepolia content settlement rail for this launch.
- Regent live tail is in scope for this launch through the daemon-owned `webapp` and `agent` chatbox rooms.
- Do not flatten these into one vague “testnet” or “mainnet” story. Base Sepolia publishing, Base Sepolia identity, and Base mainnet TECH emissions are related but not interchangeable.
- Keep Techtree chain language separate from Autolaunch chain language. Both products now use the Base family for contract-linked work, but they still have different operator stories.

## Core Rules

- Hard cutover only. Do not add backwards compatibility shims, migration glue, or dual paths unless explicitly requested.
- The root workflow is single-source-of-truth for agent execution. Do not revive the old `.claude` command flow.
- For API <-> backend functionality, treat the Regents CLI contract surface as the source of truth. Start from the contract files and ownership map in `/Users/sean/Documents/regent/regents-cli`, then update Techtree backend code to match.
- When a concept or process changes, keep these surfaces aligned in the same pass: `README.md`, `AGENTS.md`, homepage/app copy, and the adjacent Regents CLI help and operator docs.
- For most agent work, use Regents CLI as the normal entry path into Techtree:
  1. run `regent techtree identities list --chain base-sepolia` or mint if needed
  2. run `regent auth siwa login --registry-address ... --token-id ...`
  3. run `regent doctor techtree`
  4. only then use protected Techtree commands such as `node create`, `comment add`, `inbox`, `opportunities`, `autoskill buy`, and `autoskill pull`
- If an agent bypasses Regents CLI and calls the SIWA HTTP routes directly, it must send the current request shape only: snake_case fields with an explicit `chain_id`. Do not rely on the backend to invent a chain value.
- Agent registry and wallet addresses are stored in lowercase. Treat case variants as the same identity.
- Contract file meanings:
  - `api-contract.openapiv3.yaml` is the source of truth for a product's HTTP backend contract, including routes, auth, request bodies, response shapes, and stable error envelopes.
  - `regent-services-contract.openapiv3.yaml` is the source of truth for shared HTTP backend contracts that are not owned by one product, such as `regent-staking`.
  - `cli-contract.yaml` is the source of truth for a product's shipped CLI surface, including command names, flags/args, auth mode, whether a command is HTTP-backed or local/runtime-backed, and which backend contract operation it is allowed to use.
- The first files to check for API-contract work are:
  - `/Users/sean/Documents/regent/regents-cli/docs/api-contract-workflow.md`
  - `/Users/sean/Documents/regent/techtree/docs/api-contract.openapiv3.yaml`
  - `/Users/sean/Documents/regent/techtree/docs/cli-contract.yaml`
  - `/Users/sean/Documents/regent/regents-cli/docs/regent-services-contract.openapiv3.yaml`
  - `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/contracts/api-ownership.ts`
  - `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/generated/techtree-openapi.ts`
- If work changes code in `/Users/sean/Documents/regent/techtree` or `/Users/sean/Documents/regent/regents-cli`, it is not done until validation has been run in the app, the CLI repo, and the local Techtree Foundry workspace. Run `mix precommit` in `techtree`, `pnpm build`, `pnpm typecheck`, `pnpm test`, and `pnpm test:pack-smoke` in `regents-cli`, and `forge test --offline` from `/Users/sean/Documents/regent/techtree/contracts`.
- Use `mix precommit` for Phoenix validation when touching app code.
- Use `Req` for Elixir HTTP calls. Do not introduce `:httpoison`, `:tesla`, or `:httpc`.
- Use Foundry for contract development and testing.
- Regents CLI live transport flows are daemon-owned. Do not add direct CLI-to-Phoenix socket paths.
- Prefer repository-local, versioned docs over off-repo context.
- Regents CLI terminal UI work should use the shared CLI palette unless a human explicitly asks for a different one:
  - `#315569` Charcoal Blue
  - `#034568` Yale Blue
  - `#FBF4DE` Ivory Mist
  - `#D4A756` Sunlit Clay
  - `#848078` Grey Olive

## Canonical Story

Keep these names and meanings consistent across docs, website copy, and CLI help:

- Guided start: `regent techtree start` is the first step. It prepares local config, checks the runtime, helps bind identity, and confirms readiness.
- Run folder: the local folder for one active run. After the guided start, people usually open the next Techtree task or start the BBH loop.
- Live tree: the public map of seeds, nodes, and branches.
- BBH branch: the Big-Bench Hard research branch. It gives people a notebook flow, optional SkyDiscover search, and Hypotest replay validation.
- Platform workspace: the operator surface for review, moderation, and adjacent platform work.
- Public rooms: the human room and the agent room. They stay nearby for context, but they are not the first step.

For human-facing copy, keep the main loop readable in this order:

1. Install Regent.
2. Create or reuse local state, then run `regent techtree start`.
3. Move into the next Techtree task or the BBH branch you need.
4. Use the live tree, BBH branch, platform workspace, or public rooms without repeating setup work.

## BBH Process

- BBH means the Big-Bench Hard branch in TechTree.
- The canonical local BBH package lives under `environments/techtree-bbh-py`. That package owns the run-folder shape, seeded files, scoring handoff, and replay validation bundle.
- The local loop is:
  1. `regent techtree bbh run exec` materializes the run folder.
  2. `regent techtree bbh notebook pair` opens the notebook and prints the operator prompt.
  3. `regent techtree bbh run solve --solver hermes|openclaw|skydiscover` produces the answer.
  4. `regent techtree bbh submit` stores the run.
  5. `regent techtree bbh validate` replays the run.
- SkyDiscover is the search runner. It writes `search.config.yaml`, `dist/search-summary.json`, and `outputs/search.log`.
- Hypotest is the scorer and replay checker. The verdict Techtree stores must match that same replay story.
- When you touch BBH run flow, keep these files aligned:
  - `docs/api-contract.openapiv3.yaml`
  - `core/src/techtree_core/bbh_models.py`
  - `core/schemas/techtree.bbh.*`
  - `environments/techtree-bbh-py/**`
  - `lib/tech_tree/bbh/**`
  - `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/internal-runtime/workloads/bbh*.ts`
- The public site should describe BBH in plain language. Name SkyDiscover and Hypotest, explain what each one does, and keep the run loop readable from the homepage, the BBH guide, and the wall.

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
- API drift is now a workflow failure. Do not change Techtree HTTP behavior first and plan to “fix the CLI later.” Change the CLI-owned contract surface first, then make the backend match it.

### 3. Techtree Contracts

Hand work here when the task is mainly onchain semantics, TECH token logic, staking, emissions, registry behavior, deploy scripts, Foundry tests, or app/CLI wording that must stay aligned with contract reality.

Open these files first:
- `/Users/sean/Documents/regent/techtree/contracts/README.md`
- `/Users/sean/Documents/regent/techtree/contracts/AGENTS.md`
- `/Users/sean/Documents/regent/techtree/contracts/src/TechTreeRegistry.sol`
- `/Users/sean/Documents/regent/techtree/contracts/src/TechToken.sol`
- `/Users/sean/Documents/regent/techtree/contracts/src/TechStakingVote.sol`
- `/Users/sean/Documents/regent/techtree/contracts/src/TechEmissionController.sol`
- `/Users/sean/Documents/regent/techtree/contracts/script/DeployTechTreeRegistry.s.sol`
- `/Users/sean/Documents/regent/techtree/contracts/test/utils/TechContractsBase.sol`

Main risks:
- Terminology drift between app, CLI, and contracts.
- Chain-language mistakes around Base versus Ethereum.
- Staking and emission math changes that look small but break invariants.

### 4. Regents CLI Local Setup + Packaging + CI/CD

Hand work here when the task is mainly local setup, runtime bootstrapping, npm packaging, release flow, operator docs, CLI test coverage, or Techtree/Autolaunch command behavior in the CLI.

Open these files first:
- `/Users/sean/Documents/regent/regents-cli/README.md`
- `/Users/sean/Documents/regent/regents-cli/package.json`
- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/package.json`
- `/Users/sean/Documents/regent/regents-cli/docs/api-contract-workflow.md`
- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/contracts/api-ownership.ts`
- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/generated/techtree-openapi.ts`
- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/generated/autolaunch-openapi.ts`
- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/generated/regent-services-openapi.ts`
- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/index.ts`
- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/commands/techtree-start.ts`
- `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/internal-runtime/runtime.ts`
- `/Users/sean/Documents/regent/regents-cli/docs/autolaunch-cli.md`
- `/Users/sean/Documents/regent/regents-cli/docs/techtree-api-contract.md`
- `/Users/sean/Documents/regent/regents-cli/scripts/release-cli.sh`
- `/Users/sean/Documents/regent/regents-cli/scripts/packed-install-smoke.sh`

Main risks:
- The shipped package is nested under `packages/regents-cli`, so repo-root changes can be misleading.
- The CLI contract files are the source of truth for API <-> backend functionality, so backend work that skips them will drift immediately.
- Release and CI wiring are easy to miss because some validation lives from the Techtree side.

## Protected Work

The following work must never be auto-picked by autonomous agents unless a human explicitly assigns it:

- the local Techtree contract workspace at `/Users/sean/Documents/regent/techtree/contracts`
- security-sensitive auth or trust-boundary changes
- deploy and Fly.io changes
- database migrations and schema transitions
- billing, payment, or value-transfer flows

See [docs/SECURITY.md](docs/SECURITY.md) for the full policy.
