from __future__ import annotations

import argparse
import json
from pathlib import Path

from .env import load_environment


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="techtree-bbh")
    parser.add_argument("--split", default="climb")
    parser.add_argument("--task-id", action="append", dest="task_ids")
    parser.add_argument("--public-dataset")
    parser.add_argument("--problem-jsonl")
    parser.add_argument("--workspace-root")
    parser.add_argument("--official-mode", action="store_true")
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("--json", action="store_true")

    materialize_parser = subparsers.add_parser("materialize")
    materialize_parser.add_argument("--workspace", required=True)
    materialize_parser.add_argument("--capsule-id")

    score_parser = subparsers.add_parser("score")
    score_parser.add_argument("--workspace", required=True)

    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--workspace", required=True)
    validate_parser.add_argument("--run-id")

    smoke_parser = subparsers.add_parser("smoke")
    smoke_parser.add_argument("--workspace", required=True)
    smoke_parser.add_argument("--capsule-id")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    environment = load_environment(
        split=args.split,
        task_ids=args.task_ids,
        public_dataset=args.public_dataset,
        problem_jsonl=args.problem_jsonl,
        workspace_root=args.workspace_root,
        official_mode=args.official_mode,
    )

    if args.command == "inspect":
        payload = {
            "split": environment.split,
            "capsules": [
                {
                    "capsule_id": capsule.capsule_id,
                    "split": capsule.split,
                    "title": capsule.title,
                    "provider": capsule.provider,
                    "assignment_policy": capsule.assignment_policy,
                    "mode": capsule.mode,
                }
                for capsule in environment.capsules
            ],
        }
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            print(f"split: {payload['split']}")
            for capsule in payload["capsules"]:
                print(
                    f"- {capsule['capsule_id']}: {capsule['title']} "
                    f"[{capsule['mode']}, {capsule['assignment_policy']}]"
                )
        return 0

    if args.command == "materialize":
        workspace = environment.materialize(
            args.capsule_id,
            workspace_dir=Path(args.workspace),
        )
        print(
            json.dumps(
                {
                    "capsule_id": workspace.capsule.capsule_id,
                    "workspace_dir": str(workspace.workspace_dir),
                    "analysis_py": str(workspace.analysis_py_path),
                    "verdict_json": str(workspace.verdict_json_path),
                    "run_source": str(workspace.run_source_path),
                    "search_config": str(workspace.search_config_path) if workspace.search_config_path else None,
                    "search_summary_json": (
                        str(workspace.search_summary_json_path)
                        if workspace.search_summary_json_path
                        else None
                    ),
                    "search_log": str(workspace.search_log_path) if workspace.search_log_path else None,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    if args.command == "score":
        result = environment.score(Path(args.workspace))
        print(
            json.dumps(
                {
                    "decision": result.decision,
                    "raw_score": result.raw_score,
                    "normalized_score": result.normalized_score,
                    "status": result.status,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    if args.command == "validate":
        result = environment.validate(Path(args.workspace), run_id=args.run_id)
        print(
            json.dumps(
                {
                    "result": result.result,
                    "matches": result.matches,
                    "reproduced_raw_score": result.reproduced_raw_score,
                    "reproduced_normalized_score": result.reproduced_normalized_score,
                    "review_source": str(result.review_source_path),
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    if args.command == "smoke":
        print(
            json.dumps(
                environment.smoke(
                    capsule_id=args.capsule_id,
                    workspace_dir=Path(args.workspace),
                ),
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    parser.error(f"unsupported command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
