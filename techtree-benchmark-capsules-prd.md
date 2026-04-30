# Techtree Benchmark Capsules PRD + Implementation Spec

**Target repo:** `techtree`  
**Repo snapshot inspected:** `/mnt/data/techtree-src/techtree-main`  
**Audience:** coding agent implementing the feature inside Techtree and the Regents CLI  
**Status:** implementation handoff, hard-cutover style  
**Primary product direction:** make Techtree the place where humans and personal agents create, solve, validate, review, publish, and improve verifiable benchmark capsules.

---

## 1. Product thesis

Techtree already has the ingredients for an agent-native benchmark product: BBH capsules, local run folders, marimo notebooks, Hypotest-style replay, Science Tasks, Autoskill, IPFS pinning, paid payloads, Base Sepolia registry anchoring, and agent-authenticated API routes. The next implementation pass should consolidate those ingredients into one first-class product primitive:

> A **benchmark capsule** is a versioned, content-addressed, reviewable research task bundle with a controlled ground truth policy, reproducible input bundle, validation notebook, allowed-tool policy, agent harness policy, solver attempts, validations, reliability metrics, and provenance trail.

The capsule is not just a benchmark row. It is the unit of work that personal agents can learn to create, test, solve, review, and improve. OpenClaw, Regents, Hermes, Codex, Claude, and future agent runtimes should all be able to participate through the same local workspace contract and the same Techtree/Regents CLI contract.

The final product should make it possible to answer:

1. What exactly was the task?
2. What data and tool policy were allowed?
3. Was the ground truth objective, hidden, public, or reviewer-controlled?
4. Which agent/harness/skill stack attempted it?
5. Did the solver succeed once, or succeed reliably across repeated attempts?
6. Can another agent or reviewer replay, validate, or challenge the result?
7. Which artifacts, notebooks, CIDs, reviews, and Base receipts prove the work happened?
8. Which skills or harness improvements emerged from failures?

---

## 2. Current Techtree analysis

### 2.1 Existing strengths to preserve

The repo already points strongly toward this product:

- `README.md` defines the loop: define work with Science Tasks or BBH capsules, run with Hermes/OpenClaw/SkyDiscover, capture marimo notebooks/verdicts/logs/reviews, check with Hypotest or Harbor review, and publish through Regents CLI, Techtree, and Base contract paths.
- `AGENTS.md` correctly says Techtree API/CLI changes must start in `docs/api-contract.openapiv3.yaml` and `docs/cli-contract.yaml`, then flow into Techtree and `/Users/sean/Documents/regent/regents-cli`.
- `docs/MARIMO_WORKSPACES.md` already defines the local trust boundary: marimo notebooks are local workspaces, not a remote control plane; BBH uses `analysis.py`; Autoskill uses `session.marimo.py`; ACP-capable agents attach locally.
- `docs/BBH_LOCAL_AGENT_RUNBOOK.md` already documents a local run-folder loop and strict writable-file policy for Hermes, OpenClaw, and SkyDiscover.
- `docs/api-contract.openapiv3.yaml` now exists and already includes BBH, Science Tasks, Autoskill, runtime, tree, paid payload, and chatbox routes.
- `docs/cli-contract.yaml` already includes command groups for `tree`, `autoskill`, `science-tasks`, `chatbox`, `bbh-review`, and `runtime-workspace`.
- `lib/tech_tree/bbh/*` already has capsules, assignments, genomes, runs, validations, drafts, reviewer profiles, review requests, and review submissions.
- `lib/tech_tree/science_tasks.ex` already has a strong authoring/checklist/evidence/review packet model.
- `lib/tech_tree/autoskill/*` already supports skill/eval bundles, results, reviews, listings, and paid pull surfaces.
- `lib/tech_tree/ipfs/lighthouse_client.ex` already supports content uploads, CID validation, mock uploads, gateway URLs, and telemetry.
- `lib/tech_tree/nodes/publishing.ex` and workers already provide queue-backed IPFS pinning and Base anchoring for published nodes.
- `lib/tech_tree/node_access/*` and `contracts/src/TechTreeContentSettlement.sol` already support paid payload metadata, verified purchase entitlements, and 1% treasury / 99% seller USDC split.

### 2.2 Existing tables that become the foundation

Keep these, but move them under a cleaner `Benchmarks` concept:

- `bbh_capsules`: task-level benchmark capsule data.
- `bbh_genomes`: solver/harness/model/prompt/skill/tool profile bundle.
- `bbh_runs`: attempt/run record with final answer, verdict, logs, score, run source.
- `bbh_validations`: replay/manual/community/official validation record.
- `bbh_draft_proposals`: draft capsule proposal and workspace patch record.
- `bbh_review_requests` and `bbh_review_submissions`: reviewer packet flow.
- `science_tasks`: strong task authoring and review-evidence model.
- `node_bundles`, `autoskill_results`, `autoskill_reviews`, `autoskill_listings`: reusable skills and evals.
- `node_paid_payloads`, `node_purchase_entitlements`: paid capsule data/report/skill access.
- `node_publish_attempts`, `node_chain_receipts`, `node_cross_chain_links`: publish and chain provenance.

### 2.3 Major gaps

Current BBH is useful, but too narrow for the new product:

1. **BBH-specific naming leaks everywhere.** `bbh_capsules`, `bbh_runs`, and `bbh_genomes` should become domain adapters under a generic benchmark layer, not the product center.
2. **No capsule version object.** A benchmark capsule needs immutable versions because data bundles, validation notebooks, scoring policies, and allowed-tool policies can change.
3. **No first-class reliability model.** Anthropic-style repeated attempts need `attempt_count`, `solve_count`, `solve_rate`, `answer_variance`, and brittle-vs-reliable solve metrics.
4. **No generic hidden ground truth policy.** Bioinformatics and science capsules need public, hidden-server, reviewer-only, deterministic-oracle, and external-oracle modes.
5. **`data_files` is too small/simple.** Large benchmarks need content-addressed manifests, not inline arrays.
6. **`genome` is confusing outside BBH.** For generic benchmark capsules, call this a `harness` or `solver_profile`. Keep BBH `genome` as a legacy adapter if necessary.
7. **Review certificates are partly fake/stubbed.** `TechTree.BBH.Reviews` creates a synthetic-looking review node id. Capsule certification should use real review artifacts, real node publish attempts, or explicit unanchored review state.
8. **Science Tasks and BBH are separate product islands.** Science Tasks should become one capsule domain or authoring packet type inside Benchmark Capsules.
9. **No importer/batch primitive.** CompBioBench/BioMysteryBench-like bundles need import batches, dataset manifests, and large-data references.
10. **Onchain node type mapping appears inconsistent.** `AnchorNodeWorker` maps node kinds to `0..7`, while `TechTreeRegistry.sol` only accepts `1..3`. Any new capsule provenance anchor must fix or avoid that mismatch.

---

## 3. Design principles

### 3.1 Hard cutover, not compatibility sprawl

Do not create long-lived parallel product shapes. The new canonical product is `Benchmarks`. BBH remains as a domain/landing page/filter, not as the only backend abstraction.

Recommended cutover:

- Add `TechTree.Benchmarks` as the canonical context.
- Keep old `/v1/bbh/*` routes temporarily as thin wrappers around `TechTree.Benchmarks` only where necessary for an existing public BBH wall.
- New CLI help, README copy, and agent workflows should say `benchmark capsules` first and `BBH` as a domain/lane.
- Do not add `benchmark_capsules` plus keep growing `science_tasks` and `bbh_capsules` separately forever.

### 3.2 Workspace is the trust boundary

The web server must not become a general remote agent execution sandbox. Agents solve locally through Regents CLI and local workspaces. Phoenix accepts signed submissions, validates bundle hashes, stores workflow state, pins content-addressed artifacts, and anchors provenance.

### 3.3 Marimo is the notebook/evidence surface, not the remote orchestrator

Use marimo notebooks because they are Python, scriptable, reproducible, and agent-friendly. Do not integrate `molab.marimo.io` as a dependency in v1. Cloud marimo can be a future optional hosting path.

### 3.4 IPFS stores content-addressed evidence; Base stores provenance

- IPFS/Lighthouse stores public input bundles, run bundles, validation notebooks, reports, review packets, and optionally encrypted/private hidden materials.
- Techtree DB stores workflow state, indexes, summaries, review state, and access policy.
- Base anchors manifest CIDs/hashes and author/provenance receipts.
- Hidden answers and sensitive biological metadata must not be published onchain.

### 3.5 Agents are first-class contributors

Agents must be able to enter the product in several roles:

- **Route-setter / author:** creates the capsule and validation notebook.
- **Solver:** attempts the task using a harness and skill stack.
- **Validator:** replays or independently checks a run.
- **Skill crafter:** proposes reusable skills based on repeated failures or wins.
- **Reviewer:** checks capsule quality, anti-cheat policy, reproducibility, and evidence.
- **Importer:** packages third-party benchmarks into Techtree capsule format.

---

## 4. Product requirements

### 4.1 Capsule authoring

An authenticated agent or human-assisted agent can create a benchmark capsule draft.

Required author inputs:

- Title.
- Domain and field.
- Question/instructions in Markdown.
- Input data bundle or external data manifest.
- Answer schema.
- Ground truth policy.
- Validation notebook reference.
- Allowed-tool policy.
- External-resource policy.
- Scoring policy.
- Reproducibility notes.
- Anti-cheat notes.
- License and attribution.
- Human baseline status if known.
- Difficulty label if known.

The authoring flow must distinguish between:

- **Verification notebook:** proves the signal exists or the answer can be checked.
- **Solver notebook:** open workspace for an agent to attempt the problem.
- **Ground truth bundle:** hidden, reviewer-only, deterministic, or public depending on policy.

### 4.2 Capsule solving

A solver agent can materialize a workspace for a specific capsule version and harness.

The solver can edit only allowed files. The solver submits:

- final answer
- solver notebook source
- verdict or local evaluation output
- run log
- tool-call log
- artifact list
- environment/harness metadata
- optional generated skill proposal

A run must be accepted only if input bundle hashes and capsule version hashes match the published capsule version.

### 4.3 Repeated attempts and reliability

The platform must support `N` attempts by the same solver/harness/capsule version.

Reliability metrics must be first-class:

- `attempt_count`
- `solve_count`
- `solve_rate`
- `reliable_solve_rate`, where reliability threshold defaults to `>= 4/5` successful attempts
- `brittle_solve_count`, where success occurs in only `1/5` or `2/5` attempts
- `answer_variance`
- `median_runtime_seconds`
- `p90_runtime_seconds`
- `median_cost_usd`, optional
- `tool_install_events_count`
- `external_resource_call_count`
- `invalid_output_count`
- `validation_confirmed_count`

This is the main product difference from a simple leaderboard. The UI should reward reliable methods, not just one lucky win.

### 4.4 Validation and review

A validator can replay or manually validate an attempt. Validation types:

- `official_replay`
- `community_replay`
- `manual_review`
- `independent_replication`
- `oracle_check`
- `hidden_truth_check`

Reviewers can inspect capsule authoring quality before publication:

- Does the signal exist?
- Is the answer objective enough?
- Is the hidden truth protected?
- Are allowed tools clear?
- Are external resources allowed or disallowed clearly?
- Is the data licensing acceptable?
- Are scorer and answer schema deterministic?
- Is there a leakage/shortcut risk?
- Is the validation notebook separate from the solver path?

### 4.5 Skill and harness improvement loop

A failure or brittle win can generate a skill-improvement proposal.

Example flow:

1. Solver fails on 4/5 repeated attempts.
2. Another agent inspects logs and creates an Autoskill draft.
3. Skill gets evaluated across a capsule family.
4. Skill bundle is published with review evidence.
5. New repeated attempts show improved solve rate.
6. Techtree links the skill bundle to the capsule/harness leaderboard.

This should connect `Benchmarks` to the existing Autoskill tables rather than inventing a separate skill marketplace.

### 4.6 Public capsule pages

Each capsule page should show:

- capsule title, domain, field, summary
- question/instructions
- input bundle manifest
- answer schema
- scoring policy summary
- ground truth policy label, without revealing hidden truth
- allowed tools and external-resource policy
- validation notebook/public proof reference
- lineage: parent capsule, imported benchmark, source node, related skill bundles
- top reliable solver profiles
- top raw-score attempts
- repeatability chart/table
- validation history
- artifact trail: CIDs, node receipts, reviews, run bundles
- paid payload availability where relevant

BBH can keep a `/bbh` wall, but it should read from the same capsule tables filtered by `domain = "bbh"` or `family = "bbh"`.

---

## 5. Canonical data model

### 5.1 Recommendation: add generic benchmark tables

Do **not** keep adding fields only to `bbh_capsules`. Add a generic layer and backfill BBH into it.

Create a new migration:

`priv/repo/migrations/YYYYMMDDHHMMSS_create_benchmark_capsules.exs`

Use hard-cutover `up/down`; for `down`, raising is acceptable for irreversible enum/table reshapes.

### 5.2 `benchmark_capsules`

Purpose: mutable workflow record for a benchmark task across versions.

Suggested columns:

```elixir
create table(:benchmark_capsules, primary_key: false) do
  add :capsule_id, :text, primary_key: true
  add :legacy_bbh_capsule_id, :text
  add :source_node_id, references(:nodes, on_delete: :nilify_all)
  add :owner_agent_id, references(:agent_identities, on_delete: :nilify_all)
  add :owner_wallet_address, :text

  add :domain, :text, null: false
  add :field, :text
  add :family_ref, :text
  add :provider, :text
  add :provider_ref, :text
  add :import_batch_id, :text

  add :title, :text, null: false
  add :summary_md, :text
  add :question_md, :text, null: false
  add :difficulty_label, :text
  add :human_baseline_status, :text, null: false, default: "unknown"

  add :ground_truth_policy, :text, null: false
  add :answer_format, :map, null: false, default: %{}
  add :allowed_tools_policy, :map, null: false, default: %{}
  add :external_resource_policy, :map, null: false, default: %{}
  add :scoring_policy, :map, null: false, default: %{}
  add :anti_cheat_policy, :map, null: false, default: %{}

  add :workflow_state, :text, null: false, default: "authoring"
  add :visibility, :text, null: false, default: "draft"
  add :current_version_id, :text
  add :published_at, :utc_datetime_usec
  add :retired_at, :utc_datetime_usec

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:benchmark_capsules, [:legacy_bbh_capsule_id], where: "legacy_bbh_capsule_id is not null")
create index(:benchmark_capsules, [:domain, :field])
create index(:benchmark_capsules, [:workflow_state])
create index(:benchmark_capsules, [:visibility])
create index(:benchmark_capsules, [:provider, :provider_ref])
```

Allowed values:

- `domain`: `bbh`, `bioinformatics`, `computational_biology`, `science_task`, `code`, `math`, `agent_skill`, `other`.
- `human_baseline_status`: `unknown`, `human_solvable`, `human_difficult`, `expert_only`, `unsolved`, `not_applicable`.
- `ground_truth_policy`: `public`, `hidden_server`, `reviewer_only`, `deterministic_oracle`, `external_oracle`, `metadata_scrambled`, `synthetic`.
- `workflow_state`: `authoring`, `review_ready`, `in_review`, `approved`, `published`, `rejected`, `retired`.
- `visibility`: `draft`, `private_review`, `public`, `paid_access`.

### 5.3 `benchmark_capsule_versions`

Purpose: immutable versioned content bundle. Every attempt targets exactly one version.

Suggested columns:

```elixir
create table(:benchmark_capsule_versions, primary_key: false) do
  add :version_id, :text, primary_key: true
  add :capsule_id, references(:benchmark_capsules, column: :capsule_id, type: :text, on_delete: :delete_all), null: false
  add :version_label, :text, null: false
  add :version_status, :text, null: false, default: "draft"

  add :manifest_cid, :text
  add :manifest_sha256, :text
  add :manifest_uri, :text
  add :input_bundle_cid, :text
  add :input_bundle_sha256, :text
  add :validation_notebook_cid, :text
  add :validation_notebook_sha256, :text
  add :redacted_validation_notebook_cid, :text
  add :ground_truth_manifest_hash, :text
  add :ground_truth_storage_policy, :map, null: false, default: %{}
  add :environment_lock_ref, :map, null: false, default: %{}
  add :data_manifest, :map, null: false, default: %{}
  add :capsule_source, :map, null: false, default: %{}

  add :publication_node_id, references(:nodes, on_delete: :nilify_all)
  add :chain_tx_hash, :text
  add :chain_id, :integer
  add :anchored_at, :utc_datetime_usec

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:benchmark_capsule_versions, [:capsule_id, :version_label])
create index(:benchmark_capsule_versions, [:version_status])
create index(:benchmark_capsule_versions, [:manifest_cid])
```

Allowed version statuses:

- `draft`
- `review_ready`
- `approved`
- `published`
- `superseded`
- `retired`

### 5.4 `benchmark_harnesses`

Purpose: generic replacement for `bbh_genomes`. Keep `bbh_genomes` as a domain adapter or backfill to harnesses.

Suggested columns:

```elixir
create table(:benchmark_harnesses, primary_key: false) do
  add :harness_id, :text, primary_key: true
  add :owner_agent_id, references(:agent_identities, on_delete: :nilify_all)
  add :name, :text, null: false
  add :description_md, :text
  add :domain, :text
  add :runner_kind, :text, null: false
  add :model_id, :text
  add :agent_runtime, :text
  add :harness_version, :text, null: false
  add :prompt_pack_ref, :map, null: false, default: %{}
  add :skill_pack_refs, {:array, :map}, null: false, default: []
  add :tool_profile, :map, null: false, default: %{}
  add :runtime_image, :text
  add :dependency_lock_ref, :map, null: false, default: %{}
  add :workspace_policy, :map, null: false, default: %{}
  add :normalized_bundle_hash, :text, null: false
  add :source, :map, null: false, default: %{}

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:benchmark_harnesses, [:normalized_bundle_hash])
create index(:benchmark_harnesses, [:runner_kind])
create index(:benchmark_harnesses, [:model_id])
```

Allowed `runner_kind` values:

- `hermes`
- `openclaw`
- `regents`
- `codex`
- `claude`
- `skydiscover`
- `gemini`
- `opencode`
- `manual_human`
- `custom_local`

### 5.5 `benchmark_attempts`

Purpose: generic solver attempt record. It replaces the conceptual role of `bbh_runs`.

Suggested columns:

```elixir
create table(:benchmark_attempts, primary_key: false) do
  add :attempt_id, :text, primary_key: true
  add :capsule_id, references(:benchmark_capsules, column: :capsule_id, type: :text, on_delete: :restrict), null: false
  add :version_id, references(:benchmark_capsule_versions, column: :version_id, type: :text, on_delete: :restrict), null: false
  add :harness_id, references(:benchmark_harnesses, column: :harness_id, type: :text, on_delete: :restrict), null: false
  add :solver_agent_id, references(:agent_identities, on_delete: :nilify_all)
  add :solver_wallet_address, :text

  add :repeat_group_id, :text
  add :attempt_ordinal, :integer, null: false, default: 1
  add :status, :text, null: false, default: "submitted"
  add :score_status, :text, null: false, default: "unscored"
  add :raw_score, :float
  add :normalized_score, :float
  add :score_source, :text
  add :solved, :boolean

  add :answer_text, :text
  add :answer_json, :map
  add :answer_hash, :text
  add :verdict_json, :map, null: false, default: %{}

  add :run_bundle_cid, :text
  add :run_bundle_sha256, :text
  add :solver_notebook_cid, :text
  add :report_cid, :text
  add :tool_calls_cid, :text
  add :log_cid, :text
  add :artifact_manifest, :map, null: false, default: %{}

  add :runtime_seconds, :integer
  add :cost_usd_micros, :bigint
  add :tokens_input, :bigint
  add :tokens_output, :bigint
  add :tool_install_events_count, :integer, null: false, default: 0
  add :external_resource_call_count, :integer, null: false, default: 0

  add :run_source, :map, null: false, default: %{}
  add :workspace_source, :map, null: false, default: %{}

  add :submitted_at, :utc_datetime_usec
  add :validated_at, :utc_datetime_usec

  timestamps(type: :utc_datetime_usec)
end

create index(:benchmark_attempts, [:capsule_id, :version_id])
create index(:benchmark_attempts, [:harness_id])
create index(:benchmark_attempts, [:repeat_group_id])
create index(:benchmark_attempts, [:normalized_score])
create index(:benchmark_attempts, [:solved])
```

Allowed statuses:

- `created`
- `running`
- `submitted`
- `scored`
- `validation_pending`
- `validated`
- `rejected`
- `failed`

### 5.6 `benchmark_validations`

Purpose: generic validation/replay/review record.

```elixir
create table(:benchmark_validations, primary_key: false) do
  add :validation_id, :text, primary_key: true
  add :attempt_id, references(:benchmark_attempts, column: :attempt_id, type: :text, on_delete: :delete_all), null: false
  add :capsule_id, references(:benchmark_capsules, column: :capsule_id, type: :text, on_delete: :delete_all), null: false
  add :validator_agent_id, references(:agent_identities, on_delete: :nilify_all)
  add :validator_wallet_address, :text
  add :role, :text, null: false
  add :method, :text, null: false
  add :result, :text, null: false
  add :reproduced_raw_score, :float
  add :reproduced_normalized_score, :float
  add :tolerance_raw_abs, :float, null: false, default: 0.01
  add :summary_md, :text, null: false
  add :validation_notebook_cid, :text
  add :verdict_json, :map, null: false, default: %{}
  add :review_source, :map, null: false, default: %{}
  add :review_node_id, references(:nodes, on_delete: :nilify_all)
  add :chain_tx_hash, :text
  add :chain_id, :integer

  timestamps(type: :utc_datetime_usec)
end

create index(:benchmark_validations, [:attempt_id])
create index(:benchmark_validations, [:capsule_id])
create index(:benchmark_validations, [:role, :result])
```

Allowed roles:

- `official`
- `community`
- `reviewer`
- `author`
- `oracle`

Allowed methods:

- `replay`
- `manual`
- `replication`
- `oracle`
- `hidden_truth_check`

Allowed results:

- `confirmed`
- `rejected`
- `mixed`
- `needs_revision`
- `inconclusive`

### 5.7 `benchmark_reliability_summaries`

Purpose: fast read model for scoreboards and capsule pages.

```elixir
create table(:benchmark_reliability_summaries, primary_key: false) do
  add :summary_id, :text, primary_key: true
  add :capsule_id, references(:benchmark_capsules, column: :capsule_id, type: :text, on_delete: :delete_all), null: false
  add :version_id, references(:benchmark_capsule_versions, column: :version_id, type: :text, on_delete: :delete_all), null: false
  add :harness_id, references(:benchmark_harnesses, column: :harness_id, type: :text, on_delete: :delete_all), null: false
  add :repeat_group_id, :text

  add :attempt_count, :integer, null: false, default: 0
  add :solve_count, :integer, null: false, default: 0
  add :solve_rate, :float, null: false, default: 0.0
  add :reliable, :boolean, null: false, default: false
  add :brittle, :boolean, null: false, default: false
  add :answer_variance, :map, null: false, default: %{}
  add :median_runtime_seconds, :float
  add :p90_runtime_seconds, :float
  add :median_cost_usd_micros, :bigint
  add :validation_confirmed_count, :integer, null: false, default: 0
  add :last_attempt_at, :utc_datetime_usec

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:benchmark_reliability_summaries, [:capsule_id, :version_id, :harness_id, :repeat_group_id])
create index(:benchmark_reliability_summaries, [:solve_rate])
create index(:benchmark_reliability_summaries, [:reliable])
```

### 5.8 `benchmark_artifacts`

Purpose: normalized artifact records to avoid stuffing everything into maps.

```elixir
create table(:benchmark_artifacts, primary_key: false) do
  add :artifact_id, :text, primary_key: true
  add :capsule_id, references(:benchmark_capsules, column: :capsule_id, type: :text, on_delete: :nilify_all)
  add :version_id, references(:benchmark_capsule_versions, column: :version_id, type: :text, on_delete: :nilify_all)
  add :attempt_id, references(:benchmark_attempts, column: :attempt_id, type: :text, on_delete: :nilify_all)
  add :validation_id, references(:benchmark_validations, column: :validation_id, type: :text, on_delete: :nilify_all)

  add :kind, :text, null: false
  add :name, :text
  add :cid, :text
  add :uri, :text
  add :sha256, :text
  add :byte_size, :bigint
  add :content_type, :text
  add :storage_provider, :text, null: false, default: "lighthouse"
  add :visibility, :text, null: false, default: "public"
  add :encryption_meta, :map, null: false, default: %{}
  add :license, :text

  timestamps(type: :utc_datetime_usec)
end

create index(:benchmark_artifacts, [:kind])
create index(:benchmark_artifacts, [:cid])
create index(:benchmark_artifacts, [:capsule_id])
```

Artifact kinds:

- `input_bundle`
- `data_manifest`
- `validation_notebook`
- `redacted_validation_notebook`
- `ground_truth_manifest`
- `run_bundle`
- `solver_notebook`
- `tool_calls_log`
- `run_log`
- `report`
- `review_packet`
- `skill_bundle`
- `harness_bundle`

---

## 6. Backend architecture

### 6.1 New context modules

Add:

```text
lib/tech_tree/benchmarks.ex
lib/tech_tree/benchmarks/capsule.ex
lib/tech_tree/benchmarks/capsule_version.ex
lib/tech_tree/benchmarks/harness.ex
lib/tech_tree/benchmarks/attempt.ex
lib/tech_tree/benchmarks/validation.ex
lib/tech_tree/benchmarks/reliability_summary.ex
lib/tech_tree/benchmarks/artifact.ex
lib/tech_tree/benchmarks/authoring.ex
lib/tech_tree/benchmarks/bundles.ex
lib/tech_tree/benchmarks/attempts.ex
lib/tech_tree/benchmarks/validations.ex
lib/tech_tree/benchmarks/reliability.ex
lib/tech_tree/benchmarks/imports.ex
lib/tech_tree/benchmarks/presentation.ex
```

`TechTree.Benchmarks` should expose stable public functions:

```elixir
list_capsules(params \\ %{})
get_capsule(capsule_id)
get_capsule_version(version_id)
create_capsule(agent, attrs)
create_capsule_version(agent, capsule_id, attrs)
mark_capsule_review_ready(agent, capsule_id, attrs)
publish_capsule(agent, capsule_id, attrs)
create_harness(agent, attrs)
create_attempt(agent, attrs)
create_validation(agent, attrs)
recompute_reliability(capsule_id, version_id \\ nil)
scoreboard(capsule_id, params \\ %{})
```

### 6.2 Domain adapters

Add adapters instead of keeping domain logic interleaved:

```text
lib/tech_tree/benchmarks/domains/bbh.ex
lib/tech_tree/benchmarks/domains/science_task.ex
lib/tech_tree/benchmarks/domains/bioinformatics.ex
```

Responsibilities:

- Convert legacy BBH fields into generic capsule fields.
- Convert Science Task packet files/checklist/evidence into capsule authoring packet.
- Provide domain-specific default answer schemas and scoring policies.
- Provide UI labels and route filters.

### 6.3 One-time backfill path

Implement a hard-cut migration or Mix task:

```bash
mix techtree.benchmarks.backfill_bbh
mix techtree.benchmarks.backfill_science_tasks
```

Rules:

- Do not duplicate future writes after cutover.
- Backfill existing `bbh_capsules` to `benchmark_capsules` with `domain = "bbh"`.
- Backfill `bbh_runs` to `benchmark_attempts` where possible.
- Backfill `bbh_genomes` to `benchmark_harnesses`.
- Backfill `bbh_validations` to `benchmark_validations`.
- Backfill `science_tasks` to `benchmark_capsules` with `domain = "science_task"` and create one version using packet hash/files.

After backfill, writes should go through `TechTree.Benchmarks`. Old BBH functions should call the benchmark context or be removed in the same pass where CLI and docs are cut over.

### 6.4 Workers

Add Oban workers:

```text
lib/tech_tree/workers/pin_benchmark_bundle_worker.ex
lib/tech_tree/workers/anchor_benchmark_artifact_worker.ex
lib/tech_tree/workers/recompute_benchmark_reliability_worker.ex
lib/tech_tree/workers/import_benchmark_batch_worker.ex
```

Reuse `TechTree.IPFS.LighthouseClient`, but do not force benchmark bundles through `NodeBundleBuilder`, which is node/notebook-specific.

### 6.5 Bundle builder

Add:

```text
lib/tech_tree/benchmarks/bundle_manifest.ex
lib/tech_tree/benchmarks/bundle_builder.ex
```

Manifest schema v1:

```json
{
  "schema_version": "techtree.benchmark.bundle.v1",
  "bundle_kind": "capsule_version | attempt | validation | harness | skill",
  "capsule_id": "bench_...",
  "version_id": "benchv_...",
  "created_at": "2026-04-30T...Z",
  "created_by": {
    "agent_id": 123,
    "wallet_address": "0x...",
    "chain_id": 84532
  },
  "files": [
    {
      "path": "question.md",
      "sha256": "...",
      "bytes": 1234,
      "content_type": "text/markdown"
    }
  ],
  "policies": {
    "ground_truth_policy": "hidden_server",
    "allowed_tools_policy_hash": "...",
    "external_resource_policy_hash": "...",
    "scoring_policy_hash": "..."
  },
  "artifacts": {
    "input_bundle_cid": "...",
    "validation_notebook_cid": "...",
    "ground_truth_manifest_hash": "..."
  }
}
```

---

## 7. API contract changes

All changes must start in `docs/api-contract.openapiv3.yaml`.

### 7.1 New tag

Add tag:

```yaml
- name: benchmarks
  description: Benchmark capsule authoring, solving, validation, reliability, and harness surfaces.
```

### 7.2 Public read routes

Add:

```text
GET /v1/benchmarks/capsules
GET /v1/benchmarks/capsules/{id}
GET /v1/benchmarks/capsules/{id}/versions
GET /v1/benchmarks/capsules/{id}/scoreboard
GET /v1/benchmarks/capsules/{id}/reliability
GET /v1/benchmarks/attempts/{id}
GET /v1/benchmarks/attempts/{id}/validations
GET /v1/benchmarks/harnesses/{id}
GET /v1/benchmarks/imports/{id}
```

### 7.3 Agent write routes

Protected by `:api_agent`:

```text
POST /v1/agent/benchmarks/capsules
POST /v1/agent/benchmarks/capsules/{id}/versions
POST /v1/agent/benchmarks/capsules/{id}/review-ready
POST /v1/agent/benchmarks/capsules/{id}/publish
POST /v1/agent/benchmarks/harnesses
POST /v1/agent/benchmarks/attempts
POST /v1/agent/benchmarks/attempts/repeat-group
POST /v1/agent/benchmarks/attempts/{id}/validate
POST /v1/agent/benchmarks/validations
POST /v1/agent/benchmarks/imports
POST /v1/agent/benchmarks/capsules/{id}/reliability/recompute
```

### 7.4 Reviewer routes

Either reuse `/v1/agent/reviews/*` with generic target types or add:

```text
GET /v1/agent/benchmark-reviews/open
POST /v1/agent/benchmark-reviews/{request_id}/claim
GET /v1/agent/benchmark-reviews/{request_id}/packet
POST /v1/agent/benchmark-reviews/{request_id}/submit
```

Recommendation: reuse existing reviewer identity and review request infrastructure, but store target type `benchmark_capsule` and target id instead of BBH-only fields.

### 7.5 Example response envelope

Public capsule summary:

```json
{
  "ok": true,
  "capsule": {
    "capsule_id": "bench_bio_0001",
    "domain": "bioinformatics",
    "field": "single_cell_rna_seq",
    "title": "Identify the tissue source of an anonymized scRNA-seq sample",
    "summary_md": "...",
    "difficulty_label": "human_difficult",
    "human_baseline_status": "human_difficult",
    "ground_truth_policy": "hidden_server",
    "workflow_state": "published",
    "visibility": "public",
    "current_version_id": "benchv_...",
    "input_bundle": {
      "cid": "bafy...",
      "sha256": "...",
      "bytes": 123456789
    },
    "validation_notebook": {
      "cid": "bafy...",
      "redacted": true
    },
    "reliability": {
      "best_reliable_solve_rate": 0.8,
      "attempt_count": 25,
      "validated_attempt_count": 8
    }
  }
}
```

Attempt create request:

```json
{
  "attempt_id": "attempt_...",
  "capsule_id": "bench_bio_0001",
  "version_id": "benchv_...",
  "harness_source": {
    "harness_id": "harness_...",
    "runner_kind": "claude",
    "model_id": "claude-opus-...",
    "harness_version": "1.0.0",
    "tool_profile": {"network": "allowed", "conda": true, "pip": true},
    "runtime_image": "ghcr.io/regents/bench-harness:py311"
  },
  "repeat_group_id": "repeat_...",
  "attempt_ordinal": 3,
  "workspace_source": {
    "workspace_manifest_hash": "...",
    "input_bundle_sha256": "..."
  },
  "answer_json": {"answer": "..."},
  "verdict_json": {"metrics": {"raw_score": 1.0, "normalized_score": 1.0}},
  "artifacts": {
    "run_bundle_cid": "bafy...",
    "solver_notebook_cid": "bafy...",
    "log_cid": "bafy..."
  }
}
```

---

## 8. CLI contract changes

All changes must start in `docs/cli-contract.yaml`, then update Regents CLI.

### 8.1 New command group

Add `benchmarks` group:

```yaml
- name: benchmarks
  interface: mixed
  auth_mode: mixed
  output_envelope: benchmark-capsule-envelopes
  commands:
    - techtree benchmarks list
    - techtree benchmarks get <capsule_id>
    - techtree benchmarks scoreboard <capsule_id>
    - techtree benchmarks reliability <capsule_id>
    - techtree benchmarks capsule init
    - techtree benchmarks capsule pack
    - techtree benchmarks capsule upload
    - techtree benchmarks capsule submit
    - techtree benchmarks capsule publish
    - techtree benchmarks capsule import
    - techtree benchmarks notebook pair
    - techtree benchmarks harness init
    - techtree benchmarks harness publish
    - techtree benchmarks run materialize
    - techtree benchmarks run solve
    - techtree benchmarks run repeat
    - techtree benchmarks run submit
    - techtree benchmarks validate
    - techtree benchmarks skill propose
  rpc_methods:
    - techtree.benchmarks.notebook.pair
    - techtree.benchmarks.run.solve
    - techtree.benchmarks.run.repeat
    - techtree.benchmarks.capsule.pack
  path_templates:
    - /v1/benchmarks/capsules
    - /v1/benchmarks/capsules/{id}
    - /v1/benchmarks/capsules/{id}/versions
    - /v1/benchmarks/capsules/{id}/scoreboard
    - /v1/benchmarks/capsules/{id}/reliability
    - /v1/benchmarks/attempts/{id}
    - /v1/benchmarks/harnesses/{id}
    - /v1/agent/benchmarks/capsules
    - /v1/agent/benchmarks/capsules/{id}/versions
    - /v1/agent/benchmarks/capsules/{id}/review-ready
    - /v1/agent/benchmarks/capsules/{id}/publish
    - /v1/agent/benchmarks/harnesses
    - /v1/agent/benchmarks/attempts
    - /v1/agent/benchmarks/attempts/repeat-group
    - /v1/agent/benchmarks/validations
```

### 8.2 Command behavior

#### `techtree benchmarks capsule init`

Creates a local authoring workspace:

```bash
regents techtree benchmarks capsule init ./capsule-work \
  --domain bioinformatics \
  --field single-cell-rna-seq \
  --title "Identify tissue source from anonymized scRNA-seq" \
  --ground-truth-policy hidden-server
```

Creates:

```text
capsule.yaml
question.md
data/README.md
notebooks/author.marimo.py
notebooks/validate.marimo.py
answer_schema.json
scoring_policy.json
allowed_tools_policy.json
external_resource_policy.json
README.md
```

#### `techtree benchmarks capsule pack`

Validates and writes `dist/capsule.bundle.json` and `dist/manifest.json`.

Hard checks:

- required files exist
- answer schema valid JSON schema
- scoring policy valid
- hidden truth not included in public input bundle
- data manifest hashes match files
- notebook files are valid Python files
- bundle manifest hash stable

#### `techtree benchmarks run materialize`

Creates a solver workspace from a capsule version:

```bash
regents techtree benchmarks run materialize ./run-work \
  --capsule bench_bio_0001 \
  --version latest \
  --harness claude-opus-local
```

#### `techtree benchmarks run solve`

Runs local solver against workspace.

Supported solver values:

- `hermes`
- `openclaw`
- `regents`
- `codex`
- `claude`
- `skydiscover`
- `manual`

The command should not submit automatically.

#### `techtree benchmarks run repeat`

Runs N attempts and produces a repeat group:

```bash
regents techtree benchmarks run repeat ./run-work \
  --n 5 \
  --solver claude \
  --harness claude-opus-local \
  --submit
```

The CLI must create one `repeat_group_id`, one attempt folder per run, and a local summary:

```text
dist/repeat-summary.json
attempts/001/final_answer.json
attempts/001/outputs/verdict.json
attempts/002/...
```

---

## 9. Local workspace contract

### 9.1 Capsule author workspace

```text
capsule-work/
  capsule.yaml
  question.md
  answer_schema.json
  scoring_policy.json
  allowed_tools_policy.json
  external_resource_policy.json
  anti_cheat_policy.md
  license.md
  data/
    README.md
    ...
  truth/
    README.md
    ground_truth.json          # never included in public bundle unless policy=public
  notebooks/
    author.marimo.py
    validate.marimo.py
  dist/
    capsule.bundle.json
    manifest.json
    public-input-bundle.tar.zst
    private-truth-manifest.json
```

Authoring agents may edit everything except generated `dist/**` unless explicitly repacking.

### 9.2 Solver workspace

```text
run-work/
  capsule.yaml                 # read-only
  version.yaml                 # read-only
  question.md                  # read-only
  answer_schema.json           # read-only
  scoring_policy.json          # read-only/public or redacted
  allowed_tools_policy.json    # read-only
  external_resource_policy.json# read-only
  data/**                      # read-only
  notebooks/
    solver.marimo.py           # writable
  final_answer.json            # writable
  final_answer.md              # writable alternative
  outputs/
    verdict.json               # writable
    run.log                    # writable
    report.html                # writable
    tool_calls.jsonl           # writable
    artifacts/**               # writable
  dist/
    run.bundle.json            # generated
```

Solver agents must not edit:

- `capsule.yaml`
- `version.yaml`
- `question.md`
- `answer_schema.json`
- `scoring_policy.json`
- `allowed_tools_policy.json`
- `external_resource_policy.json`
- anything under `data/**`
- anything outside the workspace

### 9.3 Validation workspace

```text
validation-work/
  capsule.yaml
  version.yaml
  attempt.source.yaml
  notebooks/
    validate.marimo.py
    replay.marimo.py
  outputs/
    validation_verdict.json
    validation_report.html
    validation.log
  dist/
    validation.bundle.json
```

Validators can access hidden truth only if the capsule policy allows it and the agent has reviewer/official authorization.

---

## 10. Marimo requirements

### 10.1 Notebook roles

- `author.marimo.py`: explains capsule construction and demonstrates signal exists.
- `validate.marimo.py`: deterministic validation/scoring path, public if it does not reveal hidden truth; otherwise redacted public version plus private/reviewer version.
- `solver.marimo.py`: solver reasoning/code/work product.
- `replay.marimo.py`: validation/reproduction notebook.

### 10.2 File conventions

All benchmark marimo notebooks should include:

```toml
[tool.marimo.runtime]
watcher_on_save = "autorun"
```

The CLI should support:

```bash
regents techtree benchmarks notebook pair ./capsule-work
regents techtree benchmarks notebook pair ./run-work
```

Pairing command responsibilities:

- detect workspace type
- validate required files
- check `marimo-pair` skill availability
- open correct notebook with `uvx marimo edit`
- print solver-specific prompt text for Hermes/OpenClaw/Codex/Claude/etc.
- print allowed edit paths
- refuse to run if workspace shape is invalid

### 10.3 ACP-capable agents

Do not build vendor-specific logic into Phoenix. The local CLI should know how to print/start instructions for:

- Codex
- Claude Code
- Gemini
- OpenCode
- Hermes
- OpenClaw
- Regents

The server only records the declared `runner_kind`, `model_id`, `harness_source`, and artifact hashes.

---

## 11. IPFS/Lighthouse requirements

### 11.1 Public bundles

Use the existing `TechTree.IPFS.LighthouseClient` but add benchmark-specific bundle builders.

Public bundles:

- `capsule_version_manifest`
- `public_input_bundle`
- `redacted_validation_notebook`
- `solver_run_bundle`
- `validation_bundle`
- `review_packet`
- `harness_bundle`
- `skill_bundle`

Each stored artifact must record:

- `cid`
- `gateway_url`
- `sha256`
- `byte_size`
- `content_type`
- `storage_provider`
- `visibility`

### 11.2 Hidden/private bundles

Hidden truth must not be published as a public IPFS bundle. Allowed patterns:

1. Store only a `ground_truth_manifest_hash` publicly.
2. Store encrypted hidden truth with an access-control/encryption policy and record only encrypted CID + metadata.
3. Keep hidden truth server-side/reviewer-side and publish no CID at all.

The capsule page must show the policy, not the hidden answer.

### 11.3 Large datasets

For large datasets, support external manifest entries:

```json
{
  "path": "data/sample_001.fastq.gz",
  "storage": "external",
  "uri": "s3://... or https://...",
  "sha256": "...",
  "bytes": 12345678900,
  "license": "...",
  "access": "public | gated | reviewer_only"
}
```

Techtree should not require loading a 12GB bundle into Phoenix memory. Uploads/imports should be CLI/local-first or worker-backed.

---

## 12. Base provenance requirements

### 12.1 What should be anchored

Anchor these as Techtree nodes or benchmark-specific registry records:

- published capsule version manifest CID/hash
- official attempt bundle CID/hash
- official validation bundle CID/hash
- review/certificate bundle CID/hash
- paid payload listing references

Do not anchor:

- hidden ground truth
- private reviewer notes unless intentionally published
- raw secrets, API keys, local paths, or sensitive dataset metadata

### 12.2 Registry node type issue

The current app maps node kinds to `0..7` in `AnchorNodeWorker`, while `TechTreeRegistry.sol` accepts only node types `1..3`. This must be resolved before benchmark capsule anchoring is considered reliable.

Recommended hard-cut fix:

- Update the registry contract and tests to accept a stable enum for Techtree node types, or
- Normalize the app mapping so all currently anchored content uses only valid `1..3` types and puts specific type in the manifest.

For benchmark capsules, prefer explicit contract enum values:

```solidity
uint8 constant NODE_TYPE_CAPSULE = 1;
uint8 constant NODE_TYPE_ATTEMPT = 2;
uint8 constant NODE_TYPE_VALIDATION = 3;
uint8 constant NODE_TYPE_REVIEW = 4;
uint8 constant NODE_TYPE_SKILL = 5;
```

If the contract is not changed in this implementation slice, then the benchmark code must set `node_type = 1` for capsule manifests, `2` for attempts, and `3` for validations, and put the richer kind in the manifest.

### 12.3 Chain/network policy

Use the existing Techtree launch story:

- Base Sepolia for current Techtree publishing and paid settlement paths.
- Base mainnet for production `$TECH`/emission story, not benchmark capsule v1 provenance unless explicitly cut over.

---

## 13. Paid payload requirements

Benchmark capsules should support paid/gated access, using existing paid node payloads where possible.

Paid payload examples:

- large data bundle
- expert validation notebook
- full solver report
- replay report
- curated skill bundle
- reviewer packet
- private challenge set access

Rules:

- Public capsule metadata remains public.
- Public scoreboard remains public unless a private challenge lane is explicitly configured.
- Hidden ground truth must not become purchasable unless the benchmark is retired or the payload is explicitly marked as training/review material.
- Entitlement checks should reuse `NodeAccess` and `TechTreeContentSettlement` rather than a separate payment rail.

---

## 14. UI requirements

### 14.1 New public benchmark hub

Add route:

```text
/benchmarks
```

Features:

- filter by domain, field, status, human baseline status, difficulty
- cards showing reliability, attempt count, validation count, latest activity
- tabs: All, BBH, Science, Bioinformatics, Agent Skills

### 14.2 Capsule detail page

Route:

```text
/benchmarks/:capsule_id
```

Sections:

1. Header: title, domain, status, author, version.
2. Task: question, answer format, data manifest summary.
3. Policies: ground truth, allowed tools, external resources, anti-cheat.
4. Validation: validation notebook, signal proof, reviewer status.
5. Scoreboard: best reliable harnesses, best raw attempts, latest validated attempts.
6. Reliability: repeated-attempt table and solve consistency chart.
7. Artifacts: CIDs, manifests, review packets, run bundles.
8. Provenance: node id, Base chain id, tx hash, anchored status.
9. Skills: linked Autoskill bundles and improvement history.

### 14.3 Preserve `/bbh`

Keep `/bbh` and `/bbh/wall` as domain-specific views, but read benchmark capsules where `domain = "bbh"`.

### 14.4 Science Tasks UI simplification

Do not build a second full science task product surface in parallel. Either:

- redirect `/science-tasks` to `/benchmarks?domain=science_task`, or
- keep `/science-tasks` as a filtered benchmark page that uses the same `BenchmarkCapsule` read model.

---

## 15. Simplification plan

### 15.1 Collapse BBH, Science Tasks, and future bio benchmarks into `Benchmarks`

Current state:

- BBH has capsules/runs/validations.
- Science Tasks has task packets/checklists/evidence/review loop.
- Autoskill has skills/evals/results/listings.

New state:

- `Benchmarks` owns task/capsule/attempt/validation/reliability.
- `Autoskill` remains the reusable skill/eval marketplace.
- `Science Tasks` becomes a domain adapter and/or filtered UI, not a separate backend product island.
- `BBH` becomes a domain adapter and public wall, not the only capsule abstraction.

### 15.2 Rename “genome” to “harness” in new surfaces

Do not force all future users to learn BBH-specific `genome` terminology. New APIs should say `harness`. Backfill `bbh_genomes` into `benchmark_harnesses`. Keep `genome` only as a compatibility/domain term inside BBH docs if absolutely necessary.

### 15.3 Remove fake certificate node creation

Certification must become either:

- a real review node published through `Nodes.Publishing`, or
- an explicit DB-only review/certificate state marked `unanchored`.

Do not create synthetic node ids that look like chain records.

### 15.4 Replace inline data arrays with artifact/bundle refs

For large real-world benchmarks, `data_files` arrays are insufficient. Store data manifests and bundle refs.

### 15.5 Keep remote execution out of Phoenix

Do not expand `/v1/runtime` into public filesystem/agent execution routes. The local CLI and workspace own solving. Phoenix owns records, auth, content addressing, review state, and publish/anchor workers.

### 15.6 Make all routes contract-first

Every benchmark route and CLI command must be in YAML before implementation.

---

## 16. Implementation phases

### Phase 0: Contract and repo alignment

Files to change first:

- `docs/api-contract.openapiv3.yaml`
- `docs/cli-contract.yaml`
- `README.md`
- `AGENTS.md`
- `docs/MARIMO_WORKSPACES.md`
- `docs/BBH_LOCAL_AGENT_RUNBOOK.md`
- `/Users/sean/Documents/regent/regents-cli` generated bindings and command help

Acceptance:

- Contract checker passes.
- Router/contract test includes new benchmark routes.
- CLI contract check includes new command group.
- README and AGENTS agree on the new product center.

### Phase 1: DB and context foundation

Implement benchmark schemas, migrations, context modules, and presentations.

Acceptance:

- Can create a capsule draft.
- Can create a version.
- Can create a harness.
- Can create an attempt.
- Can create a validation.
- Can compute a reliability summary.
- Unit tests cover state transitions and constraints.

### Phase 2: Backfill and domain adapters

Backfill BBH and Science Tasks.

Acceptance:

- Existing BBH capsules appear in `/v1/benchmarks/capsules?domain=bbh`.
- Existing BBH run detail can be read through new attempt detail.
- Existing Science Tasks appear in `/v1/benchmarks/capsules?domain=science_task`.
- Old BBH public pages still render using benchmark read model.

### Phase 3: Bundle builder and IPFS artifacts

Implement benchmark bundle builders and artifact records.

Acceptance:

- Capsule version can be packed and pinned.
- Attempt bundle can be pinned.
- Validation bundle can be pinned.
- CIDs, sha256, byte sizes, and gateway URLs persist.
- Mock upload tests pass without network.

### Phase 4: CLI/workspace/harness

Implement Regents CLI command group and local workspace contracts.

Acceptance:

- `benchmarks capsule init/pack/upload/submit` works locally.
- `benchmarks run materialize/solve/repeat/submit` works locally.
- Solver cannot mutate read-only inputs without CLI detecting hash mismatch.
- `repeat --n 5` produces a repeat group and reliability summary.

### Phase 5: Validation/review/reliability

Implement validator workflows and public reliability scoreboard.

Acceptance:

- Official validation can confirm/reject attempt.
- Community validation can be listed but not auto-official unless policy allows.
- Reliability summary updates after attempts/validations.
- UI/API exposes reliable vs brittle solves.

### Phase 6: Base provenance and paid payloads

Implement capsule/attempt/validation anchoring and paid payload support.

Acceptance:

- Capsule version manifest can anchor to Base Sepolia through existing publish worker or a dedicated benchmark anchor worker.
- Chain receipt is stored and visible.
- Paid payload listing can gate a large data/report/skill artifact.
- Hidden truth is never anchored or paid-unlocked accidentally.

### Phase 7: Importers

Implement generic import batch, with first target shaped around CompBioBench-style bundles.

Acceptance:

- Import batch records source, manifest, imported capsule count, errors.
- Imported capsules have data manifests and ground truth policies.
- Import does not require loading large tarballs into Phoenix memory.

---

## 17. Test plan

### 17.1 Contract tests

- Every `/v1/benchmarks/*` route is in OpenAPI.
- Every OpenAPI benchmark path is mounted in router.
- Every CLI benchmark command references an allowed route or RPC method.
- New response schemas include stable error envelopes.

### 17.2 Schema tests

- Invalid ground truth policy rejected.
- Invalid workflow transition rejected.
- Attempt cannot target missing capsule version.
- Attempt cannot target retired capsule version unless explicit override.
- Harness normalized hash uniqueness enforced.
- Reliability unique key enforced.

### 17.3 Workspace tests

- `capsule pack` refuses missing required files.
- `capsule pack` refuses hidden truth inside public bundle.
- `run submit` refuses changed input files.
- `run submit` accepts valid run bundle.
- `repeat --n 5` creates one repeat group and five attempt directories.

### 17.4 IPFS tests

- Mock Lighthouse upload returns deterministic CID.
- Real upload client decodes `Hash`, `Name`, and `Size`.
- Invalid CID rejected.
- Artifact record persists sha256 and CID.

### 17.5 Reliability tests

Cases:

- 0/5 solved -> solve rate 0.0, not reliable, not brittle.
- 1/5 solved -> brittle.
- 2/5 solved -> brittle.
- 3/5 solved -> neither reliable nor brittle by default.
- 4/5 solved -> reliable.
- 5/5 solved -> reliable.
- Different final answers among solved attempts populate answer variance.

### 17.6 Review tests

- Reviewer can claim open review.
- Non-reviewer cannot access reviewer-only hidden truth.
- Official validation updates attempt status.
- Community validation does not override official rejected status unless configured.
- Certificate/review nodes are real or explicitly unanchored; no synthetic fake chain ids.

### 17.7 Chain tests

- Node type mapping works with registry contract.
- Capsule version manifest anchors successfully in mock/fork test.
- Hidden truth CID/hash is never included in onchain payload.
- Paid payload settlement grants entitlement only after verified purchase event.

---

## 18. Security and trust boundaries

### 18.1 Hidden truth

Hidden truth is the most sensitive benchmark material. Rules:

- Never include hidden truth in public bundle.
- Never include hidden truth in solver workspace.
- Never put hidden truth onchain.
- Store only hash or encrypted CID metadata publicly.
- Reviewer access must be logged.

### 18.2 Local execution

Agents run locally. The server must not execute arbitrary user-submitted notebooks or shell commands in v1.

### 18.3 External resources

A capsule may permit external databases or internet use, but the policy must be explicit:

```json
{
  "network": "allowed",
  "allowed_domains": ["ncbi.nlm.nih.gov", "ensembl.org"],
  "package_install": {"pip": true, "conda": true},
  "max_runtime_seconds": 7200
}
```

### 18.4 Agent identity

Use shared SIWA for agent-authenticated writes. Store agent ids and lowercase wallet addresses. Product DB remains source of truth for benchmark workflow state; onchain state remains source of truth for chain receipts and paid settlement.

---

## 19. Coding-agent implementation checklist

A coding agent should execute in this order:

1. Read `AGENTS.md`, `README.md`, `docs/CODEBASE_MAP.md`, `docs/MARIMO_WORKSPACES.md`, `docs/BBH_LOCAL_AGENT_RUNBOOK.md`.
2. Update `docs/api-contract.openapiv3.yaml` with benchmark routes and schemas.
3. Update `docs/cli-contract.yaml` with benchmark command group.
4. Add migration for generic benchmark tables.
5. Add `TechTree.Benchmarks` schemas and context.
6. Add benchmark controllers and router routes.
7. Add contract/router tests.
8. Add reliability computation module and tests.
9. Add bundle builder and artifact persistence.
10. Add IPFS pin worker for benchmark bundles.
11. Add domain adapters/backfill tasks for BBH and Science Tasks.
12. Cut BBH public reads to benchmark read model.
13. Update Regents CLI generated types and command group.
14. Add local workspace commands and validators in Regents CLI.
15. Add marimo notebook pair behavior for benchmark workspaces.
16. Add UI pages for `/benchmarks` and `/benchmarks/:capsule_id`.
17. Add Base anchoring path or fix node type mapping first.
18. Add paid payload support for capsule artifacts.
19. Update README, AGENTS, and local runbooks.
20. Run validation.

---

## 20. Validation commands

Minimum local checks after implementation:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix techtree.contracts.check
mix test
mix precommit
```

When CLI touched:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm check:openapi
pnpm check:cli-contract
pnpm build
pnpm typecheck
pnpm test
pnpm test:pack-smoke
```

When contracts touched:

```bash
cd /Users/sean/Documents/regent/techtree/contracts
forge fmt --check
forge build
forge test --offline
```

When UI touched:

```bash
cd /Users/sean/Documents/regent/techtree
npm --prefix assets test
npm --prefix assets run build
```

Use the repo’s actual available asset commands if different.

---

## 21. Suggested first vertical slice

Build the smallest complete product path:

1. Add `BenchmarkCapsule`, `BenchmarkCapsuleVersion`, `BenchmarkHarness`, `BenchmarkAttempt`, `BenchmarkValidation`, `BenchmarkReliabilitySummary`.
2. Add public `GET /v1/benchmarks/capsules` and `GET /v1/benchmarks/capsules/{id}`.
3. Add agent `POST /v1/agent/benchmarks/capsules`, `POST /versions`, `POST /attempts`, `POST /validations`.
4. Add CLI `benchmarks capsule init`, `pack`, `submit`, `run materialize`, `run submit`, `reliability`.
5. Backfill one BBH capsule manually in test fixture.
6. Run five synthetic attempts against it and show reliability summary.
7. Add `/benchmarks/:id` page with capsule detail + reliability table.

This proves the core idea without requiring importers, paid payloads, or full Base anchoring in the first slice.

---

## 22. Open decisions

1. Should `bbh_capsules` be physically migrated into `benchmark_capsules`, or kept as a legacy backing table for one release? Recommendation: migrate and keep thin read wrappers only.
2. Should Base registry contract be updated now to support richer node types? Recommendation: yes if anchoring is part of this release; otherwise explicitly defer anchoring for benchmark capsules.
3. Should hidden truth be server-stored, encrypted-IPFS-stored, or reviewer-local for v1? Recommendation: support policy metadata now; implement public hash + reviewer-local/server-private first.
4. Should `/science-tasks` redirect to `/benchmarks?domain=science_task` immediately? Recommendation: backend cutover first, UI redirect/filter second.
5. Should importers support huge tarballs now? Recommendation: import manifest references first; do not move multi-GB uploads through Phoenix.

---

## 23. Implementation prompt for the coding agent

Use this prompt for the implementing agent:

> You are implementing Techtree Benchmark Capsules. Read `AGENTS.md`, `README.md`, `docs/CODEBASE_MAP.md`, `docs/MARIMO_WORKSPACES.md`, and `docs/BBH_LOCAL_AGENT_RUNBOOK.md` first. This is a hard-cutover task. Start with `docs/api-contract.openapiv3.yaml` and `docs/cli-contract.yaml`; do not implement routes or CLI commands before the contracts. Add a generic `TechTree.Benchmarks` context with capsule, version, harness, attempt, validation, reliability, artifact, and bundle modules. BBH and Science Tasks become domain adapters. Agents must solve locally through Regents CLI workspaces; Phoenix must not execute arbitrary notebooks. Use marimo notebooks as evidence artifacts, Lighthouse/IPFS for content-addressed bundles, and Base Sepolia only for provenance manifests when node type mapping is safe. Hidden ground truth must never leak into public bundles or onchain payloads. Reliability from repeated attempts is a first-class feature. Update Regents CLI in the same pass for all HTTP-backed commands. Run contract, compile, test, and CLI validation before claiming completion.

---

## 24. Success definition

The feature is successful when a human or agent can:

1. Create a benchmark capsule draft.
2. Attach a marimo validation notebook and data manifest.
3. Publish a content-addressed capsule version.
4. Materialize a solver workspace locally.
5. Let Claude, Codex, Hermes, OpenClaw, Regents, or another local agent attempt it.
6. Submit five repeated attempts.
7. Validate at least one attempt.
8. See reliable-vs-brittle solve metrics on a public Techtree page.
9. Link a skill/harness improvement to the capsule.
10. Inspect the artifact and provenance trail without trusting a static PDF or opaque leaderboard.
