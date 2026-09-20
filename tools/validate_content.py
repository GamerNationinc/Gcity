#!/usr/bin/env python3
"""Content validation build step (engineering standards §3.7, §6).

Every file under content/ must be:

1. laid out as content/<kind>/<id>.json (one directory level, .json only);
2. of a kind with a registered schema at tools/content_schemas/<kind>.json;
3. well-formed JSON whose top level is an object carrying an integer schema_version;
4. structurally valid against that schema, including cross-references to other kinds.

Schema dialect (tools/content_schemas/README.md): a schema is an object with optional
"properties" (name -> rule), "required" (names) and "additional_properties" (bool,
default true). A rule has "type" (int | number | string | bool | array | object), and
by type: "min"/"max" (int, number), "min_length"/"max_length"/"pattern" (string),
"min_length"/"max_length"/"items" (array), nested "properties"/"required"/
"additional_properties" (object), and "ref": "<kind>" (string must be the id of an
existing content file of that kind). An empty schema {} accepts any object.

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


def load_schemas(root: Path, kinds: set[str]) -> tuple[dict[str, dict], list[str]]:
    schemas: dict[str, dict] = {}
    problems: list[str] = []
    for kind in sorted(kinds):
        path = root / "tools" / "content_schemas" / f"{kind}.json"
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            problems.append(f"tools/content_schemas/{kind}.json: not valid JSON: {exc}")
            continue
        if not isinstance(data, dict):
            problems.append(f"tools/content_schemas/{kind}.json: schema must be an object")
            continue
        schemas[kind] = data
    return schemas, problems


TYPES = {
    "int": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "string": lambda v: isinstance(v, str),
    "bool": lambda v: isinstance(v, bool),
    "array": lambda v: isinstance(v, list),
    "object": lambda v: isinstance(v, dict),
}


def check_value(value, rule: dict, where: str, ids: dict[str, set[str]]) -> list[str]:
    """Checks one value against one rule. `where` names the field for messages."""
    problems: list[str] = []
    kind = rule.get("type")
    if kind is not None:
        if kind not in TYPES:
            return [f"{where}: schema rule has unknown type '{kind}'"]
        if not TYPES[kind](value):
            return [f"{where}: must be {kind}"]
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "min" in rule and value < rule["min"]:
            problems.append(f"{where}: must be >= {rule['min']}")
        if "max" in rule and value > rule["max"]:
            problems.append(f"{where}: must be <= {rule['max']}")
    if isinstance(value, (str, list)):
        if "min_length" in rule and len(value) < rule["min_length"]:
            problems.append(f"{where}: length must be >= {rule['min_length']}")
        if "max_length" in rule and len(value) > rule["max_length"]:
            problems.append(f"{where}: length must be <= {rule['max_length']}")
    if isinstance(value, str):
        if "pattern" in rule and not re.fullmatch(rule["pattern"], value):
            problems.append(f"{where}: must match {rule['pattern']}")
        if "ref" in rule and value not in ids.get(rule["ref"], set()):
            problems.append(f"{where}: '{value}' is not an id under content/{rule['ref']}/")
    if isinstance(value, list) and "items" in rule:
        for i, item in enumerate(value):
            problems.extend(check_value(item, rule["items"], f"{where}[{i}]", ids))
    if isinstance(value, dict) and any(k in rule for k in ("properties", "required", "additional_properties")):
        problems.extend(check_object(value, rule, where, ids, top=False))
    return problems


def check_object(data: dict, schema: dict, where: str, ids: dict[str, set[str]], top: bool = True) -> list[str]:
    """`where` is the file for a top-level object ("file: field"), else the field path ("a.b")."""
    problems: list[str] = []
    props: dict = schema.get("properties", {})
    for name in schema.get("required", []):
        if name not in data:
            problems.append(f"{where}: missing required '{name}'")
    if schema.get("additional_properties", True) is False:
        for name in sorted(data):
            if name not in props:
                problems.append(f"{where}: unexpected '{name}'")
    for name in sorted(data):
        if name in props:
            label = f"{where}: {name}" if top else f"{where}.{name}"
            problems.extend(check_value(data[name], props[name], label, ids))
    return problems


def check_file(path: Path, rel: str, kinds: set[str]) -> list[str]:
    """Layout, kind registration, JSON shape and schema_version (rules 1-3)."""
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
    schemas, problems = load_schemas(root, kinds)
    files = sorted(p for p in base.rglob("*") if p.is_file() and p.name not in IGNORED_NAMES)
    ids: dict[str, set[str]] = {}
    for path in files:
        parts = path.relative_to(root).parts
        if len(parts) == 3 and path.suffix == ".json":
            ids.setdefault(parts[1], set()).add(path.stem)
    for path in files:
        rel = path.relative_to(root).as_posix()
        shape = check_file(path, rel, kinds)
        if shape:
            problems.extend(shape)
            continue
        kind = path.relative_to(root).parts[1]
        if kind in schemas:
            data = json.loads(path.read_text(encoding="utf-8"))
            problems.extend(check_object(data, schemas[kind], rel, ids))
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
