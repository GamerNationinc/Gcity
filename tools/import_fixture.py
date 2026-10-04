#!/usr/bin/env python3
"""Brings a session saved in the sandbox into the replay suite (M7.6 spec claim 9).

    tools/import_fixture.py <file> [name]

Reads a fixture the sandbox saved (`user://fixtures/<name>.json`), checks it against the
replay fixture schema `sim/core/replay_fixture.gd` enforces, and writes
`tests/replay/<name>.json`, where `tools/test.sh replay` replays it twice like any
other fixture and compares the hash it recorded.

The file is untrusted (engineering standards §5.1): anything that is not a fixture is
refused with one line per problem and nothing is written. An existing fixture is never
overwritten.

Exit status 0 when imported, 1 when refused, 2 on a usage error. Standard library only.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MAX_BYTES = 64 * 1024 * 1024
#: The limits sim/core/replay_fixture.gd holds a fixture to.
SCHEMA_VERSION = 1
MAX_TICKS = 10_000_000
MAX_COMMANDS = 1_000_000
MAX_NAME_LENGTH = 128
MAX_EXACT_INT = 1 << 53
REQUIRED = {"schema_version", "name", "seed", "ticks", "commands", "expected_hash"}
OPTIONAL = {"assembly"}
ASSEMBLIES = {"game", "sandbox"}
NAME = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
HASH = re.compile(r"^[0-9a-f]{64}$")


def _whole(value: object) -> bool:
    """An int, or a float JSON made of one, within the exactly representable range."""
    if isinstance(value, bool):
        return False
    if isinstance(value, float):
        return value.is_integer() and abs(value) <= MAX_EXACT_INT
    return isinstance(value, int) and abs(value) <= MAX_EXACT_INT


def problems(fixture: object, name: str) -> list[str]:
    """Every reason the fixture would not replay, or none."""
    if not isinstance(fixture, dict):
        return ["the top level must be an object"]
    out: list[str] = []
    missing = REQUIRED - fixture.keys()
    unknown = fixture.keys() - REQUIRED - OPTIONAL
    out += ["missing key '%s'" % k for k in sorted(missing)]
    out += ["unknown key '%s'" % k for k in sorted(unknown)]
    if missing:
        return out
    if fixture["schema_version"] != SCHEMA_VERSION:
        out.append("schema_version must be %d" % SCHEMA_VERSION)
    if not NAME.match(name) or len(name) > MAX_NAME_LENGTH:
        out.append("name '%s' must be lower case letters, digits, '-' and '_', at most %d" % (name, MAX_NAME_LENGTH))
    if not _whole(fixture["seed"]):
        out.append("seed must be a whole number")
    ticks = fixture["ticks"]
    if not _whole(ticks) or not 1 <= ticks <= MAX_TICKS:
        out.append("ticks must be a whole number from 1 to %d" % MAX_TICKS)
        ticks = 0
    if not isinstance(fixture["expected_hash"], str) or not HASH.match(fixture["expected_hash"]):
        out.append("expected_hash must be 64 lowercase hex characters (a recorded run)")
    if fixture.get("assembly", "game") not in ASSEMBLIES:
        out.append("assembly must be one of %s" % sorted(ASSEMBLIES))
    commands = fixture["commands"]
    if not isinstance(commands, list) or len(commands) > MAX_COMMANDS:
        out.append("commands must be a list of at most %d" % MAX_COMMANDS)
        return out
    for i, c in enumerate(commands):
        if not isinstance(c, dict) or set(c.keys()) != {"tick", "kind", "payload"}:
            out.append("commands[%d] must be exactly {tick, kind, payload}" % i)
            continue
        if not _whole(c["tick"]) or not 1 <= c["tick"] <= max(ticks, 1):
            out.append("commands[%d]: tick must be from 1 to the fixture's ticks" % i)
        if not isinstance(c["kind"], str) or not c["kind"]:
            out.append("commands[%d]: kind must be a non-empty string" % i)
        if not isinstance(c["payload"], dict):
            out.append("commands[%d]: payload must be an object" % i)
    return out


def import_fixture(source: Path, name: str | None, root: Path = REPO) -> list[str]:
    """Writes `tests/replay/<name>.json` under `root`; the problems if it does not."""
    try:
        if source.stat().st_size > MAX_BYTES:
            return ["%s is larger than %d bytes" % (source, MAX_BYTES)]
        fixture = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as err:
        return ["%s: %s" % (source, err)]
    if isinstance(fixture, dict) and name is not None:
        fixture["name"] = name
    final = name if name is not None else (fixture.get("name", "") if isinstance(fixture, dict) else "")
    found = problems(fixture, final if isinstance(final, str) else "")
    if found:
        return found
    target = root / "tests" / "replay" / ("%s.json" % final)
    if target.exists():
        return ["%s already exists; a fixture is never overwritten" % target.relative_to(root)]
    target.write_text(json.dumps(fixture, indent="\t") + "\n", encoding="utf-8")
    return []


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    found = import_fixture(Path(argv[1]), argv[2] if len(argv) == 3 else None)
    for p in found:
        print("import_fixture: %s" % p, file=sys.stderr)
    if found:
        return 1
    print("imported into tests/replay/; tools/test.sh replay checks it")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
