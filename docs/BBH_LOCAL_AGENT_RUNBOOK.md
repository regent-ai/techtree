# BBH Local Agent Runbook

This is the operator path for solving a BBH run folder locally with an agent.

BBH is the Big-Bench Hard branch in TechTree.

What the names mean:

- SkyDiscover is the search runner. It explores multiple candidate attempts inside the run folder and writes the search files that travel with the run.
- Hypotest is the scorer and replay check. It turns the run output into the verdict file and is the same scoring path used again during replay validation.

The loop is:

1. materialize a BBH run folder
2. run the notebook pairing helper
3. run one local agent against that run folder only
4. inspect the outputs
5. submit and validate through the existing BBH flow

## Preconditions

- Techtree is running locally.
- The Regent runtime is running locally.
- You already have a working SIWA session for protected BBH submit and validate steps.
- The local BBH run folder came from `regent techtree bbh run exec`.
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

- Recommended default: use the Techtree CLI skill with an OpenAI plan on GPT-5.4 high effort, and treat Hermes or OpenClaw as the local run-folder runners.

## Required run-folder inputs

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
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regent techtree bbh run exec ./bbh-run --lane climb
```

Use the notebook pairing helper:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regent techtree bbh notebook pair ./bbh-run
```

That command does four things for you:

- checks that `marimo-pair` is installed
- checks that the BBH workspace shape is valid
- opens `analysis.py` in marimo
- prints the exact Techtree skill and the exact Hermes or OpenClaw prompt text to use next

If you only want the instructions without opening marimo:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regent techtree bbh notebook pair ./bbh-run --no-open
```

Solve with a supported local agent:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regent techtree bbh run solve ./bbh-run --solver hermes
```

Or:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regent techtree bbh run solve ./bbh-run --solver openclaw
```

Or run the search path:

```bash
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regent techtree bbh run solve ./bbh-run --solver skydiscover
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
cd /Users/sean/Documents/regent/regents-cli
pnpm --filter @regentslabs/cli exec regent techtree bbh submit ./bbh-run
pnpm --filter @regentslabs/cli exec regent techtree bbh validate ./bbh-run
```

## Genome improvement flow

The genome improver uses the same workspace loop. A typical sequence is:

```bash
pnpm --filter @regentslabs/cli exec regent techtree bbh genome init ./bbh-draft
pnpm --filter @regentslabs/cli exec regent techtree bbh genome improve ./bbh-draft
pnpm --filter @regentslabs/cli exec regent techtree bbh genome score ./bbh-draft
pnpm --filter @regentslabs/cli exec regent techtree bbh genome propose <capsule_id> ./bbh-draft
```

The solve step stays local and operator-controlled. It never auto-submits and it never edits Techtree or Regents CLI source code.
