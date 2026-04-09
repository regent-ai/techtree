# BBH Local Agent Runbook

This is the operator path for solving a BBH workspace locally with an agent.

The loop is:

1. materialize a BBH workspace
2. run the notebook pairing helper
3. run one local agent against that workspace only
4. inspect the outputs
5. submit and validate through the existing BBH flow

## Preconditions

- Techtree is running locally.
- The Regent runtime is running locally.
- You already have a working SIWA session for protected BBH submit and validate steps.
- The local BBH workspace came from `regent techtree bbh run exec`.
- Install the shared marimo pairing skill once for Hermes or OpenClaw:

```bash
npx skills add marimo-team/marimo-pair
```

Upgrade later with:

```bash
npx skills upgrade marimo-team/marimo-pair
```

If you do not have `npx` but you do have `uv`:

```bash
uvx deno -A npm:skills add marimo-team/marimo-pair
```

- Recommended default: use the Techtree CLI skill with an OpenAI plan on GPT-5.4 high effort, and treat Hermes or OpenClaw as the local workspace runners.

## Required workspace inputs

The solve step expects these files to already exist:

- `genome.source.yaml`
- `run.source.yaml`
- `task.json`
- `protocol.md`
- `rubric.json`
- `analysis.py`
- `final_answer.md`
- `outputs/verdict.json`

The solve step only allows the agent to change:

- `analysis.py`
- `final_answer.md`
- `outputs/**`

It must not change:

- `genome.source.yaml`
- `run.source.yaml`
- `task.json`
- `protocol.md`
- `rubric.json`
- `artifact.source.yaml` when present
- anything under `data/`
- anything outside the target workspace

## Fast path

Create the workspace:

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm --filter @regentlabs/cli exec regent techtree bbh run exec ./bbh-run --lane climb
```

Use the notebook pairing helper:

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm --filter @regentlabs/cli exec regent techtree bbh notebook pair ./bbh-run
```

That command does four things for you:

- checks that `marimo-pair` is installed
- checks that the BBH workspace shape is valid
- opens `analysis.py` in marimo
- prints the exact Techtree skill and the exact Hermes or OpenClaw prompt text to use next

If you only want the instructions without opening marimo:

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm --filter @regentlabs/cli exec regent techtree bbh notebook pair ./bbh-run --no-open
```

Solve with a supported local agent:

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm --filter @regentlabs/cli exec regent techtree bbh run solve ./bbh-run --agent hermes
```

Or:

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm --filter @regentlabs/cli exec regent techtree bbh run solve ./bbh-run --agent openclaw
```

The solve step returns a summary with:

- the workspace path
- the selected agent
- the produced files
- the verdict decision
- raw and normalized score fields from `outputs/verdict.json`

## What success looks like

After a successful solve, the workspace should contain:

- a non-empty `final_answer.md`
- a valid `outputs/verdict.json`
- optional `outputs/report.html`
- optional `outputs/run.log`

The solve step does not submit anything to Techtree for you.

## Submit and validate

Once you are satisfied with the workspace outputs:

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm --filter @regentlabs/cli exec regent techtree bbh submit ./bbh-run
pnpm --filter @regentlabs/cli exec regent techtree bbh validate ./bbh-run
```

## Genome improvement flow

The genome improver uses the same workspace loop. A typical sequence is:

```bash
pnpm --filter @regentlabs/cli exec regent techtree bbh genome init ./bbh-draft
pnpm --filter @regentlabs/cli exec regent techtree bbh genome improve ./bbh-draft
pnpm --filter @regentlabs/cli exec regent techtree bbh genome score ./bbh-draft
pnpm --filter @regentlabs/cli exec regent techtree bbh genome propose <capsule_id> ./bbh-draft
```

The solve step stays local and operator-controlled. It never auto-submits and it never edits Techtree or Regent CLI source code.
