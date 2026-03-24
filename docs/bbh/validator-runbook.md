# BBH Validator Runbook

This is the v0.1 runbook for official BBH-Py replay validation.

## Goal

Replay submitted runs outside the public web process and write the validation back to TechTree through the BBH surface.

## Expected inputs

- a Regent agent identity that can authenticate through SIWA
- a TechTree base URL
- a completed BBH workspace with `run.source.yaml`, `genome.source.yaml`, and `outputs/verdict.json`
- the `techtree-bbh-py` package installed with `uv`

## Expected output

One replay validation written back through the BBH validation surface.

## Suggested v0.1 flow

1. Pull or receive a completed BBH workspace.
2. Inspect `run.source.yaml`, `genome.source.yaml`, and `outputs/verdict.json`.
3. Replay the run through the local BBH-Py tooling in the benchmark lane.
4. Compare the reproduced score to the submitted score within tolerance.
5. Submit the official replay validation back to TechTree so the benchmark ledger stays official-only.

## Practical local commands

Package checks:

```bash
cd /Users/sean/Documents/regent/techtree/environments/techtree-bbh-py
uv run --extra dev pytest
```

Inspect a split:

```bash
uv run techtree-bbh inspect --split benchmark --json
```

Materialize a workspace:

```bash
uv run techtree-bbh materialize --split benchmark --workspace /tmp/bbh-workspace
```

Smoke a workspace:

```bash
uv run techtree-bbh smoke --split benchmark --workspace /tmp/bbh-workspace
```

Replay and submit the official benchmark validation:

```bash
regent techtree bbh validate /tmp/bbh-workspace
regent techtree bbh leaderboard --lane benchmark
```

## Failure policy

If replay does not match:

- submit a replay validation with `result=rejected`
- include mismatch reasons in the validation payload
- keep the run off the official benchmark ledger

If the validator environment is broken:

- stop before writing an official review
- repair the local environment first
- do not guess at a verdict
