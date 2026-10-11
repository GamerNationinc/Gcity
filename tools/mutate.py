#!/usr/bin/env python3
"""Mutation testing for sim/ (M6 spec claim 23; standards §3.6). Standard library only.

A mutant is one small change to one line of a sim/ script. Operators:
  cmp     a comparison flipped (== !=, < >=, > <=, <= >, >= <)
  int     an integer literal moved by +1 or -1
  bool    true and false swapped, or a `not ` removed
  andor   `and` and `or` swapped
  return  an early return at the top of a function body (with the return type's
          zero value: false, 0, "", &"", [], {}, OK, or nothing for void)

The runner samples at least --mutants mutants with a fixed --seed, at least
--per-module from every sim module (or all of a module's, if it has fewer), applies
each to a scratch copy of the repository, and runs the tests mapped to the module
(tests/<module>; sim/core, sim/world and the root scripts map to tests/sim). A mutant
is killed when that run fails or times out, and survives when it passes. The report
gives the score with a 95 % Wilson interval, per-module scores and every survivor.

usage:
  tools/mutate.py [--mutants N] [--per-module N] [--seed S] [--timeout SECONDS]
                  [--shard K/N] [--report PATH] [--list]
  tools/mutate.py --combine SHARD.json... [--report PATH]
--list prints the sampled mutants without running anything. --shard K/N runs every
N-th sampled mutant from the K-th (1-based), so a scheduled CI job can split the run
across jobs; --combine merges the shards' reports into one score.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SIM = ROOT / "sim"

CMP_FLIP = {"==": "!=", "!=": "==", "<": ">=", ">=": "<", ">": "<=", "<=": ">"}
# a comparison operator standing alone (not part of <<, >>, ->, <=, >= when matching < or >)
CMP_RE = re.compile(r"(?<![<>=!\-])(==|!=|<=|>=|<|>)(?![<>=])")
INT_RE = re.compile(r"(?<![\w.])(\d+)(?![\w.])")
BOOL_RE = re.compile(r"\b(true|false)\b")
NOT_RE = re.compile(r"\bnot\s+")
ANDOR_RE = re.compile(r"\b(and|or)\b")
FUNC_RE = re.compile(r"^(static\s+)?func\s+\w+\(.*\)\s*(->\s*(?P<ret>[\w\[\], ]+))?\s*:\s*$")
ZERO = {"bool": "false", "int": "0", "String": '""', "StringName": '&""', "Error": "OK",
        "Dictionary": "{}", "void": ""}

MODULE_TESTS = {"agents": "agents", "items": "items", "land": "land", "nav": "nav",
                "progression": "progression", "quests": "quests", "threat": "threat",
                "core": "sim", "world": "sim", "": "sim"}


@dataclass
class Mutant:
    file: str      # repository-relative path
    line: int      # 1-based
    op: str
    before: str
    after: str     # the whole replacement line (or two lines for `return`)

    @property
    def module(self) -> str:
        parts = Path(self.file).parts
        return parts[1] if len(parts) > 2 else ""


def code_part(line: str) -> tuple[str, str]:
    """The line split at its comment, ignoring # inside strings."""
    in_str = ""
    for i, c in enumerate(line):
        if in_str:
            if c == in_str and line[i - 1] != "\\":
                in_str = ""
        elif c in "\"'":
            in_str = c
        elif c == "#":
            return line[:i], line[i:]
    return line, ""


def _outside_strings(code: str, start: int) -> bool:
    quotes = 0
    for c in code[:start]:
        if c == '"':
            quotes += 1
    return quotes % 2 == 0


def mutants_of_line(path: str, number: int, line: str) -> list[Mutant]:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or stripped.startswith("##"):
        return []
    if stripped.startswith(("const ", "class_name ", "extends ")):
        return []  # declarations: a constant's value is content-like and its mutants noise
    code, comment = code_part(line.rstrip("\n"))
    out: list[Mutant] = []

    def add(op: str, start: int, end: int, replacement: str) -> None:
        if not _outside_strings(code, start):
            return
        new = code[:start] + replacement + code[end:] + comment
        out.append(Mutant(path, number, op, line.rstrip("\n"), new))

    if "->" not in code and "func " not in code:
        for m in CMP_RE.finditer(code):
            add("cmp", m.start(), m.end(), CMP_FLIP[m.group(1)])
    if "func " not in code:
        for m in INT_RE.finditer(code):
            value = int(m.group(1))
            add("int", m.start(), m.end(), str(value + 1))
            if value > 0:
                add("int", m.start(), m.end(), str(value - 1))
    for m in BOOL_RE.finditer(code):
        add("bool", m.start(), m.end(), "false" if m.group(1) == "true" else "true")
    for m in NOT_RE.finditer(code):
        add("bool", m.start(), m.end(), "")
    for m in ANDOR_RE.finditer(code):
        add("andor", m.start(), m.end(), "or" if m.group(1) == "and" else "and")
    return out


def return_mutants(path: str, lines: list[str]) -> list[Mutant]:
    out: list[Mutant] = []
    for i, line in enumerate(lines):
        m = FUNC_RE.match(line.strip())
        if not m:
            continue
        ret = (m.group("ret") or "void").strip()
        if ret.startswith("Array"):
            zero = "[]" if ret == "Array" else f"{ret}()"
        elif ret in ZERO:
            zero = ZERO[ret]
        else:
            continue  # no obvious zero value (Vector3i, a class): skip
        # the body's first statement line and its indentation
        for j in range(i + 1, len(lines)):
            body = lines[j]
            if body.strip() and not body.strip().startswith("#"):
                indent = body[: len(body) - len(body.lstrip())]
                inserted = f"{indent}return {zero}".rstrip()
                out.append(Mutant(path, j + 1, "return", body.rstrip("\n"), inserted + "\n" + body.rstrip("\n")))
                break
    return out


def all_mutants(root: Path = ROOT) -> list[Mutant]:
    out: list[Mutant] = []
    for f in sorted((root / "sim").rglob("*.gd")):
        rel = f.relative_to(root).as_posix()
        lines = f.read_text().splitlines(keepends=True)
        for n, line in enumerate(lines, start=1):
            out.extend(mutants_of_line(rel, n, line))
        out.extend(return_mutants(rel, lines))
    return out


def sample(mutants: list[Mutant], total: int, per_module: int, seed: int) -> list[Mutant]:
    rng = random.Random(seed)
    by_module: dict[str, list[Mutant]] = {}
    for m in mutants:
        by_module.setdefault(m.module, []).append(m)
    chosen: list[Mutant] = []
    for module in sorted(by_module):
        pool = by_module[module]
        chosen.extend(rng.sample(pool, min(per_module, len(pool))))
    rest = [m for m in mutants if m not in chosen]
    if len(chosen) < total and rest:
        chosen.extend(rng.sample(rest, min(total - len(chosen), len(rest))))
    return chosen


def wilson(killed: int, n: int, z: float = 1.96) -> tuple[float, float]:
    if n == 0:
        return (0.0, 1.0)
    p = killed / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def apply(copy_root: Path, m: Mutant) -> str:
    """Writes the mutant into the copy; returns the file's original text."""
    f = copy_root / m.file
    original = f.read_text()
    lines = original.splitlines(keepends=True)
    lines[m.line - 1] = m.after + "\n"
    f.write_text("".join(lines))
    return original


def run_tests(copy_root: Path, godot: str, module: str, timeout: int) -> str:
    tests = MODULE_TESTS.get(module, "sim")
    cmd = [godot, "--headless", "--path", str(copy_root), "-s", "tests/run_tests.gd", "--",
           f"--only=res://tests/{tests}", "--fail-fast"]
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "killed (timeout)"
    text = done.stdout + done.stderr
    if done.returncode != 0 or "SCRIPT ERROR" in text:
        return "killed"
    return "survived"


def _skip(directory: str, names: list[str]) -> list[str]:
    """What the scratch copy leaves out: git data, the engine cache, test output."""
    here = Path(directory)
    return [n for n in names if n in (".git", ".cache") or (here == ROOT / "tests" and n == "out")]


def summarise(results: list[dict], seed: int) -> dict:
    killed = sum(1 for r in results if r["outcome"].startswith("killed"))
    low, high = wilson(killed, len(results))
    modules: dict[str, list[int]] = {}
    for r in results:
        k = modules.setdefault(r["module"] or "(root)", [0, 0])
        k[1] += 1
        if r["outcome"].startswith("killed"):
            k[0] += 1
    return {"seed": seed, "mutants": len(results), "killed": killed,
            "score": killed / len(results) if results else 0.0, "interval95": [low, high],
            "modules": {k: {"killed": v[0], "mutants": v[1]} for k, v in sorted(modules.items())},
            "survivors": [r for r in results if r["outcome"] == "survived"],
            "results": results}


def report(summary: dict, path: str) -> None:
    low, high = summary["interval95"]
    print(f"score {summary['killed']}/{summary['mutants']} = {summary['score']:.1%} (95 % interval {low:.1%} to {high:.1%})")
    for name, v in summary["modules"].items():
        print(f"  {name:12} {v['killed']}/{v['mutants']}")
    for r in summary["survivors"]:
        print(f"  survived: {r['file']}:{r['line']} {r['op']}: {r['before'].strip()}  =>  {r['after'].strip()}")
    if path:
        Path(path).write_text(json.dumps(summary, indent=2) + "\n")


def main(argv: list[str]) -> int:
    if argv and argv[0] == "--combine":
        files = [a for a in argv[1:] if not a.startswith("--report")]
        out = ""
        if "--report" in argv:
            out = argv[argv.index("--report") + 1]
            files = [f for f in files if f != out]
        results: list[dict] = []
        seeds: set[int] = set()
        for f in files:
            part = json.loads(Path(f).read_text())
            seeds.add(part["seed"])
            results.extend(part["results"])
        if len(seeds) > 1:
            print(f"shards were sampled with different seeds: {sorted(seeds)}", file=sys.stderr)
            return 2
        report(summarise(results, seeds.pop() if seeds else 0), out)
        return 0
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--mutants", type=int, default=400)
    ap.add_argument("--per-module", type=int, default=30)
    ap.add_argument("--seed", type=int, default=20261199)
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--report", default="")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--shard", default="1/1")
    args = ap.parse_args(argv)
    chosen = sample(all_mutants(), args.mutants, args.per_module, args.seed)
    k, n = (int(x) for x in args.shard.split("/"))
    chosen = chosen[k - 1 :: n]
    if args.list:
        for m in chosen:
            print(f"{m.file}:{m.line} {m.op}: {m.before.strip()}  =>  {m.after.strip()}")
        print(f"{len(chosen)} mutants")
        return 0
    godot = os.environ.get("GODOT") or subprocess.run([str(ROOT / "tools/godot.sh")], capture_output=True, text=True, check=True).stdout.strip()
    results: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="gcity-mutate-") as tmp:
        copy_root = Path(tmp) / "repo"
        shutil.copytree(ROOT, copy_root, ignore=_skip)
        subprocess.run([godot, "--headless", "--path", str(copy_root), "--import"], capture_output=True)
        for i, m in enumerate(chosen, start=1):
            original = apply(copy_root, m)
            try:
                outcome = run_tests(copy_root, godot, m.module, args.timeout)
            finally:
                (copy_root / m.file).write_text(original)
            results.append({**asdict(m), "module": m.module, "outcome": outcome})
            print(f"[{i}/{len(chosen)}] {outcome:16} {m.file}:{m.line} {m.op}", flush=True)
    report(summarise(results, args.seed), args.report)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
