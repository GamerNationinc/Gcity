#!/usr/bin/env python3
"""Runs the unit or replay stage of tools/test.sh across several engine processes.

The suite is CPU-bound GDScript run one file after another in one process; on a machine
with spare cores most of the wall-clock time is waiting. This splits the work without
changing what a test means:

  unit    every tests/**/test_*.gd file runs in its own engine process through
          tests/run_tests.gd (the one definition of how a test runs), up to --jobs at
          once, longest first by the previous run's times. A file whose header has a
          line starting `## Runs alone:` asserts wall-clock time and runs by itself
          after the rest. Each process gets its own user:// folder (XDG_DATA_HOME, in
          a temporary directory outside the project, removed afterwards), so no two
          tests share saves or logs and nothing in the project tree sees them. The per-file logs are joined in path order
          into tests/out/unit.log, ending in the same summary line run_tests.gd prints,
          so tools/check_test_log.py reads it unchanged.
  replay  every fixture is replayed twice by tools/replay_hash.gd and the hashes
          compared, as stage_replay does, several fixtures at once.

usage: parallel_tests.py unit   --godot PATH --jobs N
       parallel_tests.py replay --godot PATH --jobs N [fixture ...]
Exit 0 only if everything ran and passed. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "out"
ALONE = re.compile(r"^## Runs alone:", re.MULTILINE)
# run_tests.gd's exit code when the files it was given hold no test_* method. In one
# process that file simply adds nothing (tests/harness/test_case.gd, the base class, is
# named like a test file); alone, it is the same nothing, not a failure.
NO_TESTS_EXIT = 2
SUMMARY = re.compile(r"^(?P<tests>\d+) tests, (?P<assertions>\d+) assertions, (?P<failed>\d+) failed$", re.MULTILINE)


@dataclass
class FileRun:
    path: str  # res://tests/...
    log: str
    code: int
    seconds: float


def discover(root: Path = ROOT) -> list[str]:
    """Test files as run_tests.gd finds them: tests/**/test_*.gd, sorted, as res:// paths."""
    tests = root / "tests"
    found = [p for p in tests.rglob("test_*.gd") if OUT not in p.parents and not any(part.startswith(".") for part in p.relative_to(root).parts)]
    return sorted("res://" + p.relative_to(root).as_posix() for p in found)


def runs_alone(text: str) -> bool:
    return ALONE.search(text) is not None


def schedule(paths: list[str], durations: dict[str, float], sizes: dict[str, int]) -> list[str]:
    """Longest first: by the last recorded time, files never timed first of all (by size)."""
    def key(p: str) -> tuple[int, float, int, str]:
        if p in durations:
            return (1, -durations[p], 0, p)
        return (0, 0.0, -sizes.get(p, 0), p)
    return sorted(paths, key=key)


def summarise(runs: list[FileRun]) -> tuple[int, int, int, list[str]]:
    """Totals over every file's summary line. A run without one (a crash, a parse error
    that stopped the engine) counts as one failed test, named."""
    tests = assertions = failed = 0
    problems: list[str] = []
    for run in sorted(runs, key=lambda r: r.path):
        m = None
        for m in SUMMARY.finditer(run.log):
            pass
        if m is None:
            tests += 1
            failed += 1
            problems.append(f"FAIL {run.path}: the run ended without a summary (exit {run.code})")
            continue
        tests += int(m["tests"])
        assertions += int(m["assertions"])
        failed += int(m["failed"])
        if int(m["tests"]) == 0 and run.code == NO_TESTS_EXIT:
            continue
        if int(m["failed"]) == 0 and run.code != 0:
            failed += 1
            problems.append(f"FAIL {run.path}: every test passed but the engine exited {run.code}")
    return tests, assertions, failed, problems


def joined_log(runs: list[FileRun]) -> str:
    """Every file's output in path order, its own summary line dropped (the totals go last)."""
    parts = []
    for run in sorted(runs, key=lambda r: r.path):
        parts.append(SUMMARY.sub("", run.log).rstrip("\n"))
    return "\n".join(parts) + "\n"


#: Where each run's user:// folders go; set by `_with_user_root`. Outside the project on
#: purpose: a folder there named after a test file (`...test_x.gd`) is a "script" to the
#: analyzer and a resource to the importer.
_user_root: Path | None = None


def _user_dir(name: str) -> dict[str, str]:
    assert _user_root is not None, "user dirs are made inside _with_user_root"
    folder = _user_root / re.sub(r"[^A-Za-z0-9_-]", "_", name)
    folder.mkdir(parents=True)
    return {**os.environ, "XDG_DATA_HOME": str(folder)}


def _with_user_root(stage) -> int:
    global _user_root
    _user_root = Path(tempfile.mkdtemp(prefix="gcity-user-"))
    try:
        return stage()
    finally:
        shutil.rmtree(_user_root, ignore_errors=True)
        _user_root = None


def _run_file(godot: str, path: str) -> FileRun:
    start = time.monotonic()
    proc = subprocess.run([godot, "--headless", "--path", str(ROOT), "-s", "tests/run_tests.gd", "--", path],
                          cwd=ROOT, env=_user_dir(path), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, encoding="utf-8", errors="replace")
    return FileRun(path, proc.stdout, proc.returncode, time.monotonic() - start)


def unit(godot: str, jobs: int) -> int:
    paths = discover()
    if not paths:
        print("no tests found under tests/")
        return 2
    texts = {p: (ROOT / p.removeprefix("res://")).read_text(encoding="utf-8") for p in paths}
    alone = [p for p in paths if runs_alone(texts[p])]
    together = [p for p in paths if p not in alone]
    times_file = OUT / "durations.json"
    try:
        durations = {str(k): float(v) for k, v in json.loads(times_file.read_text(encoding="utf-8")).items()}
    except (OSError, ValueError, AttributeError):
        durations = {}
    sizes = {p: len(texts[p]) for p in paths}
    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        runs = list(pool.map(lambda p: _run_file(godot, p), schedule(together, durations, sizes)))
    for p in alone:
        runs.append(_run_file(godot, p))
    wall = time.monotonic() - start
    tests, assertions, failed, problems = summarise(runs)
    OUT.mkdir(parents=True, exist_ok=True)
    log = joined_log(runs)
    if problems:
        log += "\n".join(problems) + "\n"
    log += f"\n{tests} tests, {assertions} assertions, {failed} failed\n"
    log += f"({len(runs)} files, {jobs} at once, {len(alone)} alone after: {', '.join(alone) or 'none'}; {wall:.0f} s)\n"
    (OUT / "unit.log").write_text(log, encoding="utf-8")
    times_file.write_text(json.dumps({r.path: round(r.seconds, 1) for r in runs}, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    return 0 if failed == 0 and tests > 0 else 1


def _replay_one(godot: str, fixture: str) -> str:
    hashes = []
    for run in (1, 2):
        proc = subprocess.run([godot, "--headless", "--path", str(ROOT), "-s", "tools/replay_hash.gd", "--", fixture],
                              cwd=ROOT, env=_user_dir(f"replay-{fixture}-{run}"), stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace")
        lines = proc.stdout.strip().splitlines()
        hashes.append(lines[-1] if lines else "")
    first, second = hashes
    if not first or first != second:
        return f"FAIL {fixture}: run 1 = '{first}', run 2 = '{second}'"
    return f"ok   {fixture} {first}"


def replay(godot: str, jobs: int, fixtures: list[str]) -> int:
    if not fixtures:
        fixtures = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "tests" / "replay").rglob("*.json"))
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        lines = list(pool.map(lambda f: _replay_one(godot, f), fixtures))
    for line in lines:
        print(line)
    return 1 if any(line.startswith("FAIL") for line in lines) else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage", choices=["unit", "replay"])
    parser.add_argument("fixtures", nargs="*")
    parser.add_argument("--godot", required=True)
    parser.add_argument("--jobs", type=int, required=True)
    args = parser.parse_args(argv[1:])
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    if args.stage == "unit":
        if args.fixtures:
            parser.error("unit takes no fixtures")
        return _with_user_root(lambda: unit(args.godot, args.jobs))
    return _with_user_root(lambda: replay(args.godot, args.jobs, args.fixtures))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
