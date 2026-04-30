# Benchmark Capsules

Benchmark Capsules are the shared Techtree record for public benchmark work.

BBH and Science Tasks remain visible product lanes, but their public pages now read from the same benchmark records:

- a capsule is the work item people inspect
- a version is the fixed task bundle people attempt
- a harness describes how an attempt was run
- an attempt is one submitted result
- a validation is a review of that result
- a reliability summary shows whether results hold up across repeated attempts
- an artifact records evidence such as packet files, manifests, reports, and bundles

## Current Cutover

- `/benchmarks` and `/benchmarks/:capsule_id` are native benchmark pages.
- `/bbh`, `/bbh/wall`, and BBH public API reads are benchmark-backed views of BBH capsules.
- `/science-tasks` and Science Task public reads are benchmark-backed views of Science capsules.
- BBH and Science write paths still accept the existing product commands, but those writes now create or refresh benchmark records.
- `mix techtree.benchmarks.backfill` can populate benchmark records from existing BBH and Science rows.

## Next Slices

1. Move review certificates onto benchmark validations.
2. Add full bundle packing and artifact upload for benchmark workspaces.
3. Add any missing agent routes contract-first, only when the CLI needs them.
4. Connect benchmark provenance to the supported Base path.
5. Reuse paid payload access for protected bundles and private reviewer material.
6. Tighten the CLI workspace checks around the benchmark capsule folder shapes.
7. Keep public copy centered on benchmark capsules, evidence, reviews, and reliability.
