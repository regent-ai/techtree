# TechTree BBH-Py

This package provides the standalone BBH-Py workload package for the TechTree BBH v0.1 loop.

It can:

- load Python-only capsule rows from local split fixtures or JSONL input
- materialize the v0.1 BBH workspace contract
- score a completed run through `outputs/verdict.json`
- normalize Hypotest-style output into the canonical verdict file
- replay-validate a prior run locally with the same evaluator context
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
- `search.config.yaml`
- `eval/hypotest_skydiscover.py`
- `solver/initial_program.py`
- `task.json`
- `protocol.md`
- `rubric.json`
- `analysis.py`
- `final_answer.md`
- `outputs/verdict.json`
- `outputs/run.log`
- `outputs/skydiscover/search.log`
- `outputs/skydiscover/search_summary.json`
- `outputs/skydiscover/best_program.py`
- `outputs/skydiscover/evaluator_artifacts.json`
- `outputs/skydiscover/latest_checkpoint.txt`
- `outputs/skydiscover/best_solution.patch`
- `dist/`
