#!/usr/bin/env python3
"""Content validation build step (engineering standards §3.7, §6).

Every file under content/ must be:

1. laid out as content/<kind>/<id>.json (one directory level, .json only);
2. of a kind with a registered schema at tools/content_schemas/<kind>.json;
3. well-formed JSON whose top level is an object carrying an integer schema_version.

Structural validation against the registered schema starts with the first content
kind (M1); registering the schema file is what turns that kind on. Until then, any
content file fails here with a message saying which schema is missing.

Exit status 0 when clean; 1 with one line per problem otherwise. Standard library only.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ID_RE = re.compile(r"^[a-z0-9][a-z0-9_]*$")
IGNORED_NAMES = {"README.md", ".gitkeep"}


def registered_kinds(root: Path) -> set[str]:
    schemas = root / "tools" / "content_schemas"
    if not schemas.is_dir():
        return set()
    return {p.stem for p in schemas.glob("*.json")}


def check_file(path: Path, rel: str, kinds: set[str]) -> list[str]:
    parts = Path(rel).parts  # ("content", kind, file)
    if len(parts) != 3:
        return [f"{rel}: content files live exactly one level deep: content/<kind>/<id>.json"]
    kind, filename = parts[1], parts[2]
    if path.suffix != ".json":
        return [f"{rel}: content files must be .json"]
    if not ID_RE.match(path.stem):
        return [f"{rel}: id must match {ID_RE.pattern}"]
    if kind not in kinds:
        return [f"{rel}: no schema registered for kind '{kind}' (expected tools/content_schemas/{kind}.json)"]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        return [f"{rel}: not valid JSON: {exc}"]
    if not isinstance(data, dict):
        return [f"{rel}: top level must be an object"]
    version = data.get("schema_version")
    if isinstance(version, bool) or not isinstance(version, int) or version < 1:
        return [f"{rel}: schema_version must be a positive integer"]
    return []


def run(root: Path) -> list[str]:
    base = root / "content"
    if not base.is_dir():
        return [f"{base.relative_to(root).as_posix()}/: directory missing"]
    kinds = registered_kinds(root)
    problems: list[str] = []
    for path in sorted(p for p in base.rglob("*") if p.is_file()):
        if path.name in IGNORED_NAMES:
            continue
        problems.extend(check_file(path, path.relative_to(root).as_posix(), kinds))
    return problems


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent
    problems = run(root)
    for problem in problems:
        print(problem)
    if problems:
        print(f"validate_content: {len(problems)} problem(s)")
        return 1
    print("validate_content: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
