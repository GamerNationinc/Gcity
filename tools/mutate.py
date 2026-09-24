#!/usr/bin/env python3
"""Mutation testing for `sim/` (engineering standards §3.6; M6 spec claim 12).

A test suite that passes tells you the code does what the tests say. It does not tell
you the tests would notice if the code stopped doing it. Mutation testing asks the
second question: change the code in a small, plausible way and see whether anything
fails. A mutant nothing catches is a hole in the tests, not a bug in the code.

    tools/mutate.py                 every sim file, the default sample per file
    tools/mutate.py --per-file 4    a smaller sample, for a quick read
    tools/mutate.py sim/quests      only under a path
    tools/mutate.py --json out.json the full report, for the gate package

Each mutant runs only the test files that cover the file it mutates, because the whole
suite takes twenty minutes on a Deck and a mutation run needs hundreds of executions.
The mapping is `tests/<area>/test_<name>.gd` for `sim/<area>/<name>.gd`, plus the
assembly test, which every system is registered in.
"""

from __future__ import annotations

import argparse
import atexit
import json
import random
import re
import signal
import subprocess
import sys
import time
import types
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
#: The file currently holding a mutant, and what it should say again. A mutation run
#: rewrites a source file, tests it, and puts it back; killed between those two and it
#: would leave the mutant in the working tree. That happened, on a Deck that ran out of
#: memory mid-run, and the inverted type check it left behind was only spotted because
#: the tree was checked. Everything that can end the process restores it first.
_IN_FLIGHT: tuple[Path, str] | None = None


def _hold(path: Path, original: str) -> None:
    global _IN_FLIGHT
    _IN_FLIGHT = (path, original)


def restore_in_flight() -> bool:
    """Puts the file being mutated back. True if there was one. Safe to call twice."""
    global _IN_FLIGHT
    if _IN_FLIGHT is None:
        return False
    path, original = _IN_FLIGHT
    _IN_FLIGHT = None
    try:
        path.write_text(original, encoding="utf-8")
    except OSError as exc:  # the disk is the last thing that can save us
        print(f"could not restore {path}: {exc}", file=sys.stderr)
        return False
    return True


def _on_signal(signum: int, _frame: types.FrameType | None) -> None:
    if restore_in_flight():
        print(f"\nsignal {signum}: restored the file being mutated", file=sys.stderr)
    raise SystemExit(128 + signum)
#: Always run: every system registers here, so a mutant that breaks assembly dies fast.
#: Always run. The assembly test registers every system; the corpus test is a hostile
#: payload for every command kind, so it covers the argument checking in every handler
#: — which is why it is worth its own file and worth running against every mutant.
ALWAYS = [
    "res://tests/sim/test_sim_assembly.gd",
    "res://tests/fuzz/test_command_corpus.gd",
]
#: Files whose tests live somewhere the naming rule does not find.
EXTRA_TESTS = {
    "sim/core/sim_root.gd": ["res://tests/sim/test_sim_root.gd", "res://tests/sim/test_pause.gd"],
    "sim/core/state_hash.gd": ["res://tests/sim/test_state_hash.gd"],
    "sim/core/save_file.gd": ["res://tests/sim/test_save_file.gd"],
    "sim/core/replay.gd": ["res://tests/sim/test_replay.gd"],
    "sim/core/content_db.gd": ["res://tests/sim/test_content_db.gd"],
    "sim/core/entity_ids.gd": ["res://tests/sim/test_entity_ids.gd"],
    "sim/core/event_bus.gd": ["res://tests/sim/test_event_bus.gd"],
    "sim/core/command_registry.gd": ["res://tests/sim/test_command_registry.gd"],
    "sim/core/json_numbers.gd": ["res://tests/sim/test_json_numbers.gd"],
    "sim/progression/stat_resolver.gd": ["res://tests/progression/test_stat_resolver.gd"],
    "sim/progression/progression_system.gd": ["res://tests/progression/test_progression_system.gd"],
    "sim/agents/corpse_system.gd": ["res://tests/agents/test_corpse.gd", "res://tests/agents/test_actor_system.gd"],
    "sim/agents/movement_system.gd": [
        "res://tests/agents/test_movement_system.gd",
        "res://tests/agents/test_vertical_movement.gd",
        # M7 claim 12: every agents system drops a removed actor's rows, and the one
        # test that removes an agent in the middle of everything is the actor test
        "res://tests/agents/test_actor_system.gd",
    ],
    "sim/agents/squad_system.gd": ["res://tests/agents/test_squad.gd", "res://tests/agents/test_actor_system.gd"],
    "sim/quests/run_score_system.gd": ["res://tests/quests/test_run_score.gd"],
    "sim/nav/portal_graph.gd": ["res://tests/nav/test_portal_graph.gd"],
    "sim/world/site_system.gd": ["res://tests/world/test_site_system.gd"],
    "sim/threat/standing_system.gd": ["res://tests/threat/test_standing.gd"],
    "sim/agents/aim_system.gd": ["res://tests/agents/test_aim_and_stress.gd", "res://tests/agents/test_actor_system.gd"],
    "sim/agents/stress_system.gd": ["res://tests/agents/test_aim_and_stress.gd", "res://tests/agents/test_actor_system.gd"],
    "sim/agents/pathing_system.gd": ["res://tests/agents/test_agent_pathing.gd", "res://tests/agents/test_actor_system.gd"],
    "sim/agents/stance_system.gd": ["res://tests/agents/test_stance_scoring.gd", "res://tests/agents/test_actor_system.gd"],
    "sim/agents/perception_system.gd": ["res://tests/agents/test_perception_system.gd", "res://tests/agents/test_actor_system.gd"],
    "sim/core/replay_fixture.gd": ["res://tests/sim/test_replay_fixture.gd"],
    "sim/core/sim_command.gd": ["res://tests/sim/test_sim_root.gd"],
    "sim/assembly.gd": ["res://tests/sim/test_sim_assembly.gd"],
}
#: Files with no tests of their own and nothing to mutate worth scoring.
NO_TESTS_NEEDED = {"sim/core/sim_system.gd"}
#: Lines that are not worth mutating: a mutant here is noise, not a hole in the tests.
SKIP_LINE = re.compile(r"^\s*(#|##|@|class_name|extends|assert\()")


@dataclass
class Mutant:
    """One changed line: what it was, what it became, and what happened to it."""

    path: str
    line: int
    operator: str
    before: str
    after: str
    outcome: str = "failed"
    by: str = ""
    seconds: float = 0.0

    @property
    def killed(self) -> bool:
        return self.outcome == "failed"

    @property
    def counts(self) -> bool:
        """Invalid mutants are not evidence either way, so they are left out."""
        return self.outcome in ("failed", "passed")


@dataclass
class Report:
    mutants: list[Mutant] = field(default_factory=list)

    @property
    def scored(self) -> list[Mutant]:
        return [m for m in self.mutants if m.counts]

    @property
    def invalid(self) -> list[Mutant]:
        return [m for m in self.mutants if not m.counts]

    @property
    def killed(self) -> int:
        return sum(1 for m in self.scored if m.killed)

    @property
    def score(self) -> float:
        scored = self.scored
        if not scored:
            return 0.0
        return 100.0 * self.killed / len(scored)


def mutations(line: str) -> list[tuple[str, str]]:
    """Every (operator, rewritten line) this line admits, in a fixed order.

    The operators are the four the standards name: integer constants, comparison
    operators, boolean returns, and a deleted statement.
    """
    out: list[tuple[str, str]] = []
    stripped = line.strip()
    if SKIP_LINE.match(line) or not stripped:
        return out
    # comparison operators: <= before < so the longer match wins
    for op, other in (("<=", "<"), (">=", ">"), ("==", "!="), ("!=", "=="), ("<", "<="), (">", ">=")):
        idx = _operator_at(line, op)
        if idx >= 0:
            out.append((f"{op} -> {other}", line[:idx] + other + line[idx + len(op):]))
            break
    # boolean returns
    if re.search(r"\breturn true\b", line):
        out.append(("return true -> false", re.sub(r"\breturn true\b", "return false", line, count=1)))
    elif re.search(r"\breturn false\b", line):
        out.append(("return false -> true", re.sub(r"\breturn false\b", "return true", line, count=1)))
    # integer constants, skipping array indices and the 0 in a plain `!= 0`
    number = re.search(r"(?<![\w.\[])(\d+)(?![\w.\]])", line)
    if number and "\"" not in line and "'" not in line:
        value = int(number.group(1))
        out.append((f"{value} -> {value + 1}", line[:number.start(1)] + str(value + 1) + line[number.end(1):]))
    # a deleted statement, where deleting cannot break the parse
    if not stripped.endswith(":") and not stripped.startswith(("return", "pass", "else", "elif", "var ")):
        indent = line[: len(line) - len(line.lstrip())]
        out.append(("statement deleted", indent + "pass"))
    return out


def _operator_at(line: str, op: str) -> int:
    """Where `op` appears outside a string and not as part of a longer operator."""
    in_string = False
    quote = ""
    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            if ch == quote:
                in_string = False
        elif ch in "\"'":
            in_string = True
            quote = ch
        elif ch == "#":
            return -1
        elif line.startswith(op, i):
            nxt = line[i + len(op): i + len(op) + 1]
            prev = line[i - 1: i] if i else ""
            if op in ("<", ">") and (nxt == "=" or prev in "<>"):
                i += 1
                continue
            # `->` is a return type, not a comparison: mutating it is a parse error
            if op == ">" and prev == "-":
                i += 1
                continue
            if op in ("<", ">") and (prev == "[" or nxt == "["):
                i += 1
                continue
            return i
        i += 1
    return -1


def tests_for(rel: str) -> list[str]:
    """The test files that cover a sim file, or just ALWAYS if nothing does.

    A file that falls through to ALWAYS is not covered: the assembly test would not
    notice most changes, so every mutant in it survives and the score reports the
    tests as weaker than they are. `unmapped()` is what keeps that from being silent.
    """
    if rel in EXTRA_TESTS:
        return EXTRA_TESTS[rel] + ALWAYS
    parts = Path(rel).parts
    if len(parts) >= 3:
        area, name = parts[1], Path(parts[-1]).stem
        for candidate in (f"res://tests/{area}/test_{name}.gd", f"res://tests/{area}/test_{name.replace('_system', '')}.gd"):
            if (ROOT / candidate.removeprefix("res://")).exists():
                return [candidate] + ALWAYS
    return list(ALWAYS)


def unmapped() -> list[str]:
    """Sim files nothing but the assembly test covers.

    A silent fallback here is worse than a missing number: it reports real tests as
    absent and sends whoever reads the score hunting for holes that are not there.
    The first full pass called four systems untested because their test files are
    named for what they test rather than for the file.
    """
    out: list[str] = []
    for path in sorted((ROOT / "sim").rglob("*.gd")):
        rel = path.relative_to(ROOT).as_posix()
        if rel in NO_TESTS_NEEDED:
            continue
        if tests_for(rel) == ALWAYS:
            out.append(rel)
    return out


def sim_files(under: list[str]) -> list[Path]:
    """The files to mutate. An argument may be a directory or a single file: after
    adding a test you want to mutate the one file it covers, not the whole tree."""
    roots = [ROOT / u for u in under] if under else [ROOT / "sim"]
    found: list[Path] = []
    for root in roots:
        if root.is_file():
            found.append(root)
        else:
            found.extend(sorted(p for p in root.rglob("*.gd")))
    seen: dict[Path, None] = {}
    for path in found:
        seen.setdefault(path, None)
    return list(seen)


def diagnostics(output: str) -> tuple[str, ...]:
    """The engine errors a test run printed, as a comparable multiset.

    Deleting a `push_error` is a mutant nothing in GDScript can assert against: there
    is no hook to say "this call should have complained". But the run's own output
    changes, and this project's standards say errors are handled or loudly fatal — so
    the loud part going missing *is* a behavioural change, and one that is visible from
    out here even though it is not visible from inside a test.
    """
    lines = [line.strip() for line in output.splitlines() if line.strip().startswith("ERROR:")]
    return tuple(sorted(lines))


def run(tests: list[str], godot: str, timeout: int) -> tuple[str, str, tuple[str, ...]]:
    """Runs the given test files. Returns (outcome, why, the errors it printed).

    The outcome is `passed`, `failed`, or `invalid`. A mutant that will not compile is
    invalid, not killed: nothing about the tests caught it, and counting it as a kill
    flatters the score. The engine says so on stderr rather than by exit code, which is
    why this reads both.
    """
    try:
        result = subprocess.run(
            [godot, "--headless", "--path", str(ROOT), "-s", "tools/run_test_file.gd", "--", *tests],
            capture_output=True, text=True, timeout=timeout, cwd=ROOT,
        )
    except subprocess.TimeoutExpired:
        return "failed", "timed out", ()
    output = result.stdout + result.stderr
    if "Parse Error" in output or "did not compile" in output or "Could not parse" in output:
        return "invalid", "did not compile", ()
    if result.returncode == 0:
        return "passed", "", diagnostics(output)
    for line in result.stdout.splitlines():
        if line.startswith("FAIL"):
            return "failed", line.strip(), diagnostics(output)
    return "failed", "non-zero exit", diagnostics(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("under", nargs="*", help="paths under the repo to mutate (default: sim)")
    parser.add_argument("--per-file", type=int, default=6, help="mutants sampled per file (default 6)")
    parser.add_argument("--seed", type=int, default=20261230, help="sampling seed")
    parser.add_argument("--timeout", type=int, default=600, help="seconds allowed per mutant")
    parser.add_argument("--json", help="write the full report here")
    parser.add_argument("--godot", default="", help="engine binary (default: tools/godot.sh)")
    args = parser.parse_args()

    godot = args.godot or subprocess.run([str(ROOT / "tools/godot.sh")], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    if not godot:
        print("could not find the engine; is tools/godot.sh working?", file=sys.stderr)
        return 2

    atexit.register(restore_in_flight)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _on_signal)

    missing = unmapped()
    if missing:
        print("no tests are mapped to these, so every mutant in them would survive:", file=sys.stderr)
        for rel in missing:
            print(f"  {rel}", file=sys.stderr)
        print("add them to EXTRA_TESTS in tools/mutate.py", file=sys.stderr)
        return 2

    rng = random.Random(args.seed)
    report = Report()
    for path in sim_files(args.under):
        rel = path.relative_to(ROOT).as_posix()
        if rel in NO_TESTS_NEEDED:
            continue
        original = path.read_text(encoding="utf-8")
        lines = original.splitlines(keepends=True)
        candidates: list[Mutant] = []
        for i, line in enumerate(lines):
            for operator, rewritten in mutations(line.rstrip("\n")):
                candidates.append(Mutant(rel, i + 1, operator, line.rstrip("\n"), rewritten))
        if not candidates:
            continue
        rng.shuffle(candidates)
        chosen = candidates[: args.per_file]
        tests = tests_for(rel)
        # what the tests say with the file untouched, so a mutant that silences a
        # diagnostic can be told from one that changes nothing at all
        _, _, baseline = run(tests, godot, args.timeout)
        for mutant in chosen:
            lines[mutant.line - 1] = mutant.after + "\n"
            _hold(path, original)
            path.write_text("".join(lines), encoding="utf-8")
            started = time.monotonic()
            outcome, why, printed = run(tests, godot, args.timeout)
            mutant.seconds = time.monotonic() - started
            if outcome == "passed" and printed != baseline:
                outcome = "failed"
                why = "the run stopped complaining about something"
            mutant.outcome = outcome
            mutant.by = why
            lines[mutant.line - 1] = mutant.before + "\n"
            restore_in_flight()
            report.mutants.append(mutant)
            mark = {"failed": "killed  ", "passed": "SURVIVED", "invalid": "invalid "}[outcome]
            print(f"{mark} {rel}:{mutant.line} {mutant.operator}  ({mutant.seconds:.1f}s)", flush=True)

    print()
    print(f"{len(report.scored)} mutants, {report.killed} killed, score {report.score:.1f}%"
          f"  ({len(report.invalid)} did not compile and are not counted)")
    survivors = [m for m in report.scored if not m.killed]
    if survivors:
        print("\nsurvived:")
        for m in survivors:
            print(f"  {m.path}:{m.line}  {m.operator}")
            print(f"      {m.before.strip()}")
    if args.json:
        Path(args.json).write_text(json.dumps({
            "score": report.score,
            "mutants": len(report.scored),
            "killed": report.killed,
            "invalid": len(report.invalid),
            "per_file": args.per_file,
            "seed": args.seed,
            "detail": [vars(m) for m in report.mutants],
        }, indent="\t") + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
