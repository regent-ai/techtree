# TechTree BBH-Py

This package provides the standalone BBH-Py workload package for the TechTree BBH v0.1 loop.

It can:

- load Python-only capsule rows from local split fixtures or JSONL input
- materialize the v0.1 BBH workspace contract
- score a completed run through `outputs/verdict.json`
- replay-validate a prior run locally
- expose a small CLI for inspection, workspace generation, scoring, validation, and smoke runs

## Quick start

```bash
uv run techtree-bbh inspect --split climb --json
uv run techtree-bbh materialize --split challenge --workspace /tmp/bbh-workspace
uv run techtree-bbh smoke --split benchmark --workspace /tmp/bbh-benchmark
```

## Workspace contract

Each materialized workspace contains:

- `artifact.source.yaml`
- `genome.source.yaml`
- `run.source.yaml`
- `task.json`
- `protocol.md`
- `rubric.json`
- `analysis.py`
- `final_answer.md`
- `outputs/verdict.json`
- `outputs/run.log`
- `dist/`
