#!/usr/bin/env python3
"""Brings a site made with the creator tool into the game (M7.5 spec claim 16).

    tools/import_site.py <file> <id> [title]

Reads a site file the creator saved (`user://sites/<id>.json`), checks it against the
`site` schema with the same validator CI runs (tools/validate_content.py), gives it its
content id and, if given, a title, and writes `content/site/<id>.json`. From there it
is raised or bound like Cold Storage.

The file is untrusted (engineering standards §5.1): anything that is not a site this
content can build is refused with one line per problem and nothing is written. Beyond
the schema it checks what the game would otherwise only find at assembly: no two
pieces in one slot. An existing site is never overwritten.

Exit status 0 when imported, 1 when refused, 2 on a usage error. Standard library only.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from tools import validate_content as vc
except ImportError:  # run as tools/import_site.py: its own directory is on the path, not the repo
    import validate_content as vc  # type: ignore[no-redef]

#: Larger than any site the schema allows (2 048 pieces at about 80 bytes each), with room.
MAX_BYTES = 1024 * 1024
KIND = "site"
#: A face named from the negative side is the face of the cell before it on that axis.
_AXES = {"x": 0, "y": 1, "z": 2}


def slot(rel: list[int], facing: str) -> str:
    """The slot a piece takes, as BuildSystem keys it: its cell, or its face's lower cell and axis."""
    if not facing:
        return "%d,%d,%d" % tuple(rel)
    cell = list(rel)
    if facing.startswith("n"):
        cell[_AXES[facing[1]]] -= 1
    return "%d,%d,%d|%s" % (cell[0], cell[1], cell[2], facing[1])


def check(data: object, where: str, root: Path) -> list[str]:
    """Every problem with `data` as a site of this content, or [] if it is one."""
    if not isinstance(data, dict):
        return [f"{where}: top level must be an object"]
    version = data.get("schema_version")
    if isinstance(version, bool) or not isinstance(version, int) or version < 1:
        return [f"{where}: schema_version must be a positive integer"]
    schemas, problems = vc.load_schemas(root, vc.registered_kinds(root))
    if problems:
        return problems
    if KIND not in schemas:
        return [f"tools/content_schemas/{KIND}.json: missing"]
    ids: dict[str, set[str]] = {}
    for path in sorted((root / "content").glob("*/*.json")):
        ids.setdefault(path.parent.name, set()).add(path.stem)
    problems = vc.check_object(data, schemas[KIND], where, ids)
    if problems:
        return problems
    seen: dict[str, int] = {}
    for i, piece in enumerate(data["pieces"]):
        key = slot(piece["rel"], piece["facing"])
        if key in seen:
            problems.append(f"{where}: pieces {seen[key]} and {i} are both at {key}")
        seen.setdefault(key, i)
    return problems


def import_site(source: Path, site_id: str, title: str | None, root: Path) -> list[str]:
    """Writes content/site/<site_id>.json from `source`; the problems if it would not."""
    if not vc.ID_RE.match(site_id):
        return [f"id '{site_id}' must match {vc.ID_RE.pattern}"]
    target = root / "content" / KIND / f"{site_id}.json"
    if target.exists():
        return [f"{target.relative_to(root).as_posix()} exists: choose another id"]
    try:
        size = source.stat().st_size
    except OSError as exc:
        return [f"{source}: cannot read: {exc.strerror}"]
    if size > MAX_BYTES:
        return [f"{source}: {size} bytes is more than a site can be ({MAX_BYTES})"]
    try:
        data = json.loads(source.read_bytes().decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
        return [f"{source}: not valid JSON: {exc}"]
    if title is not None and isinstance(data, dict):
        data["title"] = title
    problems = check(data, source.name, root)
    if problems:
        return problems
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, indent="\t", sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    return []


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print("usage: tools/import_site.py <file> <id> [title]")
        return 2
    root = Path(__file__).resolve().parent.parent
    problems = import_site(Path(argv[1]), argv[2], argv[3] if len(argv) == 4 else None, root)
    for problem in problems:
        print(problem)
    if problems:
        print(f"import_site: refused, {len(problems)} problem(s); nothing written")
        return 1
    print(f"import_site: content/{KIND}/{argv[2]}.json written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
