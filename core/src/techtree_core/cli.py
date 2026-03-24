from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .compiler import compile_workspace, export_schema_files, verify_workspace, write_compilation
from .models import ZERO_ADDRESS


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="techtree-core")
    parser.add_argument("--author", default=ZERO_ADDRESS, help="Hex address to use in derived headers")
    subparsers = parser.add_subparsers(dest="command", required=True)

    compile_parser = subparsers.add_parser("compile", help="Compile a TechTree workspace")
    compile_parser.add_argument("path", help="Workspace directory or source manifest path")
    compile_parser.add_argument("--output-dir", help="Override dist directory")

    verify_parser = subparsers.add_parser("verify", help="Verify a TechTree workspace")
    verify_parser.add_argument("path", help="Workspace directory or source manifest path")

    schema_parser = subparsers.add_parser("schema-export", help="Export JSON schemas")
    schema_parser.add_argument("path", help="Output directory for schema files")

    return parser


def _run_compile(path: str, author: str, output_dir: str | None) -> dict[str, object]:
    result = compile_workspace(Path(path), author=author)
    files = write_compilation(result, output_dir=output_dir)
    return {
        "node_type": result.node_type,
        "node_id": result.node_id,
        "dist_dir": str(Path(output_dir) if output_dir else Path(result.dist_dir)),
        "written": {name: str(path) for name, path in files.items()},
    }


def _run_verify(path: str, author: str) -> dict[str, object]:
    result = verify_workspace(Path(path), author=author)
    return result.model_dump(exclude_none=True)


def _run_schema_export(path: str) -> dict[str, str]:
    written = export_schema_files(Path(path))
    return {name: str(path) for name, path in written.items()}


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.command == "compile":
        print(json.dumps(_run_compile(args.path, args.author, args.output_dir), indent=2, sort_keys=True))
        return 0

    if args.command == "verify":
        result = _run_verify(args.path, args.author)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0 if result.get("ok") else 1

    if args.command == "schema-export":
        print(json.dumps(_run_schema_export(args.path), indent=2, sort_keys=True))
        return 0

    parser.error(f"Unknown command: {args.command}")
    return 2


def compile_entrypoint() -> int:
    parser = argparse.ArgumentParser(prog="techtree-core-compile")
    parser.add_argument("path", help="Workspace directory or source manifest path")
    parser.add_argument("--author", default=ZERO_ADDRESS, help="Hex address to use in derived headers")
    parser.add_argument("--output-dir", help="Override dist directory")
    args = parser.parse_args()
    print(json.dumps(_run_compile(args.path, args.author, args.output_dir), indent=2, sort_keys=True))
    return 0


def verify_entrypoint() -> int:
    parser = argparse.ArgumentParser(prog="techtree-core-verify")
    parser.add_argument("path", help="Workspace directory or source manifest path")
    parser.add_argument("--author", default=ZERO_ADDRESS, help="Hex address to use in derived headers")
    args = parser.parse_args()
    result = _run_verify(args.path, args.author)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("ok") else 1


def schema_export_entrypoint() -> int:
    parser = argparse.ArgumentParser(prog="techtree-core-schema-export")
    parser.add_argument("path", help="Output directory for schema files")
    args = parser.parse_args()
    print(json.dumps(_run_schema_export(args.path), indent=2, sort_keys=True))
    return 0
