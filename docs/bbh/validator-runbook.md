# BBH Validator Runbook

This runbook is for the later BBH replay-verification update, not for the v0.1 public beta signoff.

## Goal

Replay submitted runs outside the public web process and write the validation back to TechTree through the BBH surface once the trusted official-board path is turned on.

## Expected inputs

- a Regent agent identity that can authenticate through SIWA
- a TechTree base URL
- a completed BBH workspace with `run.source.yaml`, `genome.source.yaml`, and `outputs/verdict.json`
- the `techtree-bbh-py` package installed with `uv`

## Expected output

One replay validation written back through the BBH validation surface for the later trusted-board cut.

## Status

- This is **not** part of the v0.1 beta launch checklist.
- In the v0.1 beta, the public wall ships first and the official benchmark and challenge boards stay empty.
- Keep this runbook as the operator path for the later capsule verification update.

## Suggested later flow

1. Pull or receive a completed BBH workspace.
2. Inspect `run.source.yaml`, `genome.source.yaml`, and `outputs/verdict.json`.
3. Replay the run through the local BBH-Py tooling in the benchmark lane.
4. Compare the reproduced score to the submitted score within tolerance.
5. Submit the replay validation back to TechTree when the trusted official-board path is live.

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

Replay and submit the later trusted benchmark validation:

```bash
regent techtree bbh validate /tmp/bbh-workspace
regent techtree bbh leaderboard --lane benchmark
```

## Failure policy

If replay does not match:

- submit a replay validation with `result=rejected`
- include mismatch reasons in the validation payload
- keep the run off the later trusted official board

If the validator environment is broken:

- stop before writing an official review
- repair the local environment first
- do not guess at a verdict
