# Marimo Workspaces In Techtree

Techtree uses marimo notebooks as local workspaces, not as a remote control plane.

For v1:

- BBH workspaces open on `analysis.py`
- autoskill workspaces open on `session.marimo.py`
- ACP-capable agents can be attached locally through marimo
- `molab.marimo.io` is not integrated into Techtree yet

The shared notebook helper for local agent pairing is `marimo-pair`.

Install it once for Agent Skills-compatible runners:

```bash
npx skills add marimo-team/marimo-pair
```

Upgrade it with:

```bash
npx skills upgrade marimo-team/marimo-pair
```

If you do not have `npx` but you do have `uv`:

```bash
uvx deno -A npm:skills add marimo-team/marimo-pair
```

The workspace is the trust boundary. The repo is not.

## BBH workspace contract

Readable inputs:

- `task.json`
- `protocol.md`
- `rubric.json`
- `analysis.py`
- `data/**`
- `genome.source.yaml`
- `run.source.yaml`

Required outputs:

- `final_answer.md`
- `outputs/verdict.json`

Optional outputs:

- `outputs/report.html`
- `outputs/run.log`

## Autoskill skill workspace contract

Editable files:

- `session.marimo.py`
- `SKILL.md`
- `prompts/**`
- `examples/**`
- `manifest.yaml`

## Autoskill eval workspace contract

Editable files:

- `session.marimo.py`
- `README.md`
- `tasks/**`
- `graders/**`
- `fixtures/**`
- `scenario.yaml`
- `result.json`
- `artifacts.json`
- `repro-manifest.json`

## Local launch path

BBH notebook helper:

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm --filter @regentlabs/cli exec regent techtree bbh notebook pair /path/to/bbh-workspace
```

Autoskill notebook helper:

```bash
cd /Users/sean/Documents/regent/regent-cli
pnpm --filter @regentlabs/cli exec regent techtree autoskill notebook pair /path/to/autoskill-workspace
```

Those helper commands:

- check that `marimo-pair` is installed
- check the workspace shape
- open the correct notebook in marimo
- print the exact Techtree skill plus Hermes and OpenClaw prompt text to use next

If you only want the instructions and checks, add `--no-open`.

New Regent workspaces now include:

```toml
[tool.marimo.runtime]
watcher_on_save = "autorun"
```

That gives you immediate reruns on notebook save when marimo is open locally.

## ACP-capable local agents

Techtree documents the local marimo ACP path for:

- Codex
- Claude Code
- Gemini
- OpenCode

Those agents are local notebook helpers in v1. They are not built into `regent techtree bbh run solve`.

Typical local flow:

1. scaffold the workspace with Regent CLI
2. open the notebook with `uvx marimo edit ...`
3. start the ACP bridge for your chosen agent
4. let the agent edit only the allowed workspace files
5. inspect the result
6. continue with the normal Techtree submit, validate, publish, or review flow

## Editing rules

- never edit Techtree or Regent CLI source files from a workspace agent session
- never change secrets or local config
- never claim success without checking the required output files
- always report which files changed
- fail fast if the workspace shape is wrong
