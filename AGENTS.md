This repository uses the root workflow as the canonical agent orchestration layer.

`AGENTS.md` is the short working map for Techtree. Keep it current. Do not turn it into an encyclopedia.

## Regent Dependency Skills

The Regent dependency skills are installed in `/Users/sean/Documents/regent/.agents/skills` and `/Users/sean/.codex/skills`. Open the matching skill before touching these areas:

- `contract-first-cli-api`: Techtree API routes, CLI command surfaces, OpenAPI files, CLI YAML, generated clients, and CLI/backend alignment.
- `shared-siwa`: SIWA sidecar behavior, receipts, signed request envelopes, nonce/replay rules, and protected agent routes.
- `xmtp-rooms`: public rooms, agent rooms, XMTP group mirrors, membership, presence, moderation, and room sync shared with Autolaunch.
- `oban-workers`: background jobs, queues, retries, idempotency, job args, and DB-backed lifecycle work.
- `cachex-regent-cache`: cache keys, TTLs, invalidation, hot reads, and any cached public or paid payload view.
- `privy-auth-boundary`: human auth, Privy token verification, session bootstrap, and human-vs-agent route boundaries.
- `safe-viem-wallet-actions`: viem, prepared transactions, wallet actions, contract ABI calls, and transaction confirmation.
- `techtree-research-runtime`: BBH, Science Tasks, marimo notebooks, Pydantic/PyYAML/PyCryptodome, deck.gl, libp2p, and evidence artifacts.
- `observability-promex-sentry`: PromEx, Sentry, Telemetry, structured logs, health checks, and private-data redaction.

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
- Keep Techtree chain language separate from Autolaunch chain language. Both products now use the Base chain for contract-linked work, but they still have different operator stories.
- Treat the mirrored XMTP room model as shared with Autolaunch. If you change room identity, membership command leasing, shard allocation, or internal sync semantics here, check the matching Autolaunch flow in the same pass.

## Core Rules

- Hard cutover only. Do not add backwards compatibility shims, migration glue, or dual paths unless explicitly requested.
- The root workflow is single-source-of-truth for agent execution. Do not revive the old `.claude` command flow.
- For Techtree API or CLI work, start from the Techtree-owned contract files: `docs/api-contract.openapiv3.yaml` for HTTP behavior and `docs/cli-contract.yaml` for shipped command behavior. Then update Techtree and `/Users/sean/Documents/regent/regents-cli` to match.
- When a concept or process changes, keep these surfaces aligned in the same pass: `README.md`, `AGENTS.md`, homepage/app copy, and the adjacent Regents CLI help and operator docs.
- For supported Techtree workflows, agents should use Regents CLI as the normal entry path into Techtree backend records and Base contract-backed publishing:
  1. run `regents techtree identities list --chain base-sepolia` or mint if needed
  2. run `regents identity ensure`
  3. run `regents doctor techtree`
  4. only then use protected Techtree commands such as `node create`, `comment add`, `inbox`, `opportunities`, `autoskill buy`, and `autoskill pull`
- Do not bypass Regents CLI for supported Techtree workflows unless the task is explicitly backend development or contract development.
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

- Techtree: the public research record for agent science. The public story is: define the task, run the agent, capture the notebook, check the result, and publish what held up.
- Regents CLI: the agent interface for Techtree. It prepares local research folders, runs benchmark and review loops, syncs evidence to Techtree, and publishes verified records through supported Base contract paths.
- Guided start: `regents techtree start` is the first step. It prepares local config, checks the runtime, helps bind identity, and confirms readiness.
- Run folder: the local folder for one active run. After the guided start, people usually open the next Techtree task or start the BBH loop.
- Live tree: the public map of seeds, nodes, branches, and layer-0 subject areas. BBH is the first layer-0 branch today, not the last. Science Tasks now sits under `Evals` as the branch for Harbor-ready science benchmark tasks.
- BBH branch: the Big-Bench Hard research branch. It gives people a notebook flow, optional SkyDiscover search, Hypotest replay validation, and the clearest public publish-and-review loop in Techtree today.
- Science Tasks branch: the `Evals` branch for packaging scientific workflows into real task packets with blocking checklist lines, evidence, and review-loop tracking for Harbor review.
- marimo notebooks: the readable research record agents create, pair with workspaces, publish, and surface in the Notebook Gallery.
- Autoskill: the reuse layer for skills, evals, notebook sessions, results, reviews, and listings.
- Harbor review loop: the supported Science Tasks review path. Do not claim that Techtree trains models today.
- Public rooms: the homepage human room and agent room help people notice movement, hand work forward, and jump into the next branch. Treat them as an important public coordination surface, not decorative chrome.
- Leaf-node access: paid payload unlocks and autoskill buying belong on specific leaf nodes after someone already knows what they want. Do not turn them into the front-door story.
- Trusted agent identity: Regent identity plus SIWA-backed provenance is an important trust layer, but not the main public pitch.
- Platform workspace: the operator surface for review, moderation, and adjacent platform work. Keep it out of the public front-door story unless a task is explicitly about operator tools.

For human-facing copy, keep the main loop readable in this order:

1. Define the work with Science Tasks or BBH capsules.
2. Run the work with Hermes, OpenClaw, or SkyDiscover through Regents CLI.
3. Capture the evidence in marimo notebooks, verdicts, logs, and review files.
4. Check the result with Hypotest replay for BBH or Harbor review for Science Tasks.
5. Publish what held up through Regents CLI, Techtree, and the supported Base contract paths.

## BBH Process

- BBH means the Big-Bench Hard branch in TechTree.
- The canonical local BBH package lives under `environments/techtree-bbh-py`. That package owns the run-folder shape, seeded files, scoring handoff, and replay validation bundle.
- The local loop is:
  1. `regents techtree bbh run exec` materializes the run folder.
  2. `regents techtree bbh notebook pair` opens the notebook and prints the operator prompt.
  3. `regents techtree bbh run solve --solver hermes|openclaw|skydiscover` produces the answer.
  4. `regents techtree bbh submit` stores the run.
  5. `regents techtree bbh validate` replays the run.
- SkyDiscover is the search runner. It writes `search.config.yaml`, `dist/search-summary.json`, and `outputs/search.log`.
- Hypotest is the scorer and replay checker. The verdict Techtree stores must match that same replay story.
- BBH genome commands compare model, harness, prompt, skill, tool, runtime, and data choices across capsules. Keep that story tied to evidence, not to an unsupported training claim.
- When you touch BBH run flow, keep these files aligned:
  - `docs/api-contract.openapiv3.yaml`
  - `core/src/techtree_core/bbh_models.py`
  - `core/schemas/techtree.bbh.*`
  - `environments/techtree-bbh-py/**`
  - `lib/tech_tree/bbh/**`
  - `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/internal-runtime/workloads/bbh*.ts`
- The public site should describe BBH in plain language. Name SkyDiscover and Hypotest, explain what each one does, and keep the run loop readable from the homepage, the BBH guide, and the wall.

## Science Tasks Process

- Science Tasks means the Evals branch for Harbor-ready science benchmark tasks.
- The workspace should look like a Harbor task, including `instruction.md`, `task.toml`, `environment/Dockerfile`, `tests/test.sh`, tests, solution notes, helper notes, and `science-task.json`.
- The canonical local review loop is:
  1. `regents techtree science-tasks init --workspace-path ...` creates the task workspace and links it to Techtree.
  2. `regents techtree science-tasks review-loop --workspace-path ... --pr-url ...` runs Hermes with the `harbor-task-review-loop` skill.
  3. Hermes writes `dist/harbor-review-loop.json`.
  4. Regent validates that file, updates `science-task.json`, then syncs checklist, evidence, Harbor PR, and review state to Techtree.
  5. `regents techtree science-tasks export --workspace-path ...` writes the submission folder.
- Do not add a new Techtree HTTP route for review-loop work unless the stored Science Tasks record is missing a required field. The intended design uses the existing checklist, evidence, submit, and review-update endpoints.
- When Science Tasks command behavior changes, start with `/Users/sean/Documents/regent/techtree/docs/cli-contract.yaml`, then update `/Users/sean/Documents/regent/regents-cli`.
- When you touch Science Tasks flow, keep these files aligned:
  - `docs/cli-contract.yaml`
  - `lib/tech_tree/science_tasks.ex`
  - `lib/tech_tree_web/controllers/science_task_controller.ex`
  - `lib/tech_tree_web/live/public/science_task_live.ex`
  - `lib/tech_tree_web/live/public/science_tasks_live.ex`
  - `/Users/sean/Documents/regent/regents-cli/packages/regents-cli/src/internal-runtime/workloads/science-tasks.ts`
  - `/Users/sean/Documents/regent/regents-cli/docs/techtree-api-contract.md`
- Public copy should say what a researcher can do: prepare the task, run review, capture evidence, answer reviewer concerns, and export the submission. Avoid explaining internal storage or transport details in public copy.
- Public copy should call this a Harbor review path. Do not describe it as model training.

## Notebook And Autoskill Process

- marimo notebooks are the readable research record. BBH workspaces use `analysis.py`; Autoskill workspaces use `session.marimo.py`.
- Agents pair notebooks through Regents CLI before publishing notebook-backed work:
  1. `regents techtree bbh notebook pair ...`
  2. `regents techtree autoskill notebook pair ...`
- Autoskill packages reusable skills, evals, notebook sessions, results, reviews, and listings. It is the current name. Do not rename it.
- When public copy mentions reusable agent skills, connect them to evidence: the useful path is run work, capture proof, publish the skill or eval, then let other agents pull it through Regents CLI.

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
