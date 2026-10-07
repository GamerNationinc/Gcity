#!/usr/bin/env python3
"""Reads CEOGG's sandbox Deck run (G7.6 §3, claim 13) off its run log, so the run is
the only thing CEOGG does: every step of the demo script is checked, the gate's numbers
are measured, the button audit runs and the saved session is imported and replayed.

    tools/check_sandbox_run.py [run.log] [--replay]

With no log, the newest run launched with `--sandbox`. `--replay` also imports the
fixture the run saved (`tools/import_fixture.py`) and replays it (`tools/test.sh replay`).
Prints one line per step (ok / MISSING) and the gate's numbers. Exit 1 when a step is
missing, the button audit finds a silent press or the replay fails.
"""
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))
from tools import check_buttons  # noqa: E402

USER = pathlib.Path.home() / ".local/share/godot/app_userdata/Gcity"
RUNS = USER / "logs/runs"
LINE = re.compile(r"^\s*([\d.]+)\s+t(-?\d+)\s+(\S+)\s+(.*)$")
BEAT = re.compile(r"^(\d+) fps, worst frame ([\d.]+) ms")
SAVED = re.compile(r"saved (user://fixtures/(\S+\.json))")


def parse(lines: list[str]) -> list[tuple[float, int, str, str]]:
    out = []
    for line in lines:
        m = LINE.match(line)
        if m:
            out.append((float(m.group(1)), int(m.group(2)), m.group(3), m.group(4)))
    return out


def check(lines: list[str]) -> tuple[list[tuple[str, bool, str]], dict[str, str]]:
    """The demo script's steps, each (step, done, evidence), and the gate's numbers."""
    rows = parse(lines)
    kind = lambda k: [r for r in rows if r[2] == k]  # noqa: E731
    notes = [r[3] for r in kind("note")]
    commands = [r[3] for r in kind("command")]
    launch = next((r[3] for r in kind("launch")), "")
    env = " ".join(r[3] for r in kind("machine"))
    build = " ".join(r[3] for r in kind("build"))
    places = [c for c in commands if c.startswith("build.place ")]
    armed = []
    for c in commands:
        if c.startswith("sandbox.spawn_agent "):
            kit = json.loads(c.split(" ", 1)[1]).get("kit", {})
            if kit:
                armed.append(c)
    spawn_app = any("-> Spawn:" in r[3] for r in kind("device"))
    has = lambda text: any(text in n for n in notes)  # noqa: E731
    sight = has("every overlay on") or has("sight lines, eyes and centres on")
    saved = [m for n in notes if (m := SAVED.search(n))]
    lowered_after = any(r[3] == "device: lowered" for r in kind("world"))
    flew = any(r[3].startswith("fly ") for r in kind("sandbox"))
    # item 30: a clear, then a site raised after it
    cleared = next((i for i, n in enumerate(notes) if n.startswith("clearing the lot")), None)
    raised_after = cleared is not None and any(n.startswith("raising ") for n in notes[cleared + 1:])
    steps = [
        ("1. sandbox build in Game Mode", '"--sandbox"' in launch and "linux-dev" in build and "--demo" not in launch
         and "SteamGameId=" in env and not re.search(r"SteamGameId=(\s|$)", env),
         f"{launch}; {'Steam-launched' if re.search(r'SteamGameId=\S', env) else 'not launched from Steam'}"),
        ("2. a foundation and a wall", len(places) >= 2, f"{len(places)} pieces placed"),
        ("3. the Spawn app", spawn_app, "opened" if spawn_app else "never opened"),
        ("4. two armed guards", len(armed) >= 2, f"{len(armed)} spawned with a kit"),
        ("5. god mode, sight lines", has("god mode on") and sight,
         f"god {'on' if has('god mode on') else 'never on'}, sight lines {'on' if sight else 'never on'}"),
        ("6. device down, fly", lowered_after and flew, f"{'flew' if flew else 'never flew'}"),
        ("7. ai freeze / thaw", has("every guard frozen") and has("every guard no longer frozen"), ""),
        ("7. time hold, step, x1/4, x1", has("time held") and has("stepped to tick") and has("time x1/4")
         and any(n == "time x1" for n in notes), ""),
        ("7b. remove, clear, raise again", has("removing ") and cleared is not None and raised_after,
         "" if cleared is not None else "no clear"),
        ("8. session saved", bool(saved), saved[-1].group(1) if saved else "no fixture saved"),
    ]
    # the gate's numbers: how long steps 2-8 took, fps with the overlays off and on
    numbers: dict[str, str] = {}
    first = next((r[0] for r in rows if r[2] == "command" and r[3].startswith("build.place ")), None)
    last = next((r[0] for r in reversed(rows) if r[2] == "note" and SAVED.search(r[3])), None)
    if first is not None and last is not None:
        numbers["steps 2-8"] = f"{(last - first) / 60:.1f} min"
    overlays = 0
    names_on: set[str] = set()
    fps: dict[bool, list[int]] = {False: [], True: []}
    worst: dict[bool, float] = {False: 0.0, True: 0.0}
    # timed from the first piece to the save: the load before it is not play, and neither
    # is the first ground streaming (a piece can be placed on the first ticks: the demo's)
    loaded = next((r[0] for r in rows if r[2] == "beat" and "(streaming)" not in r[3]), 0.0)
    start = max(first if first is not None else 0.0, loaded)
    end = last if last is not None else float("inf")
    for at, _, k, text in rows:
        if k == "note":
            if text == "every overlay on":
                names_on = {"all"}
            elif text == "every overlay off":
                names_on = set()
            elif text.endswith(" on") and "," in text and "god" not in text:
                names_on.add(text[:-3])
            elif text.endswith(" off") and text[:-4] in names_on:
                names_on.discard(text[:-4])
            overlays = len(names_on)
        elif k == "beat" and start <= at <= end and (m := BEAT.match(text)):
            fps[overlays > 0].append(int(m.group(1)))
            worst[overlays > 0] = max(worst[overlays > 0], float(m.group(2)))
    for on in (False, True):
        if fps[on]:
            ordered = sorted(fps[on])
            low = ordered[max(0, len(ordered) // 100 - 1)] if len(ordered) >= 100 else ordered[0]
            numbers[f"overlays {'on' if on else 'off'}"] = (
                f"{sum(ordered) / len(ordered):.0f} fps mean, {low} fps 1 % low (per second), worst frame {worst[on]:.1f} ms")
    return steps, numbers


def newest_sandbox_run() -> pathlib.Path | None:
    runs = sorted(RUNS.glob("run-*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    for path in runs:
        head = path.read_text(encoding="utf-8", errors="replace").splitlines()[:8]
        if any('"--sandbox"' in line and "launch" in line and "--demo" not in line for line in head):
            return path
    return None


def main(argv: list[str]) -> int:
    replay = "--replay" in argv
    args = [a for a in argv if a != "--replay"]
    path = pathlib.Path(args[0]) if args else newest_sandbox_run()
    if path is None:
        print("no sandbox run yet: play it from the Gcity Sandbox shortcut (G7.6 §3)")
        return 1
    lines = path.read_text(encoding="utf-8").splitlines()
    steps, numbers = check(lines)
    print(f"{path.name}: the sandbox demo script (G7.6 §3)")
    for step, done, evidence in steps:
        print(f"  {'ok     ' if done else 'MISSING'} {step}{'  (' + evidence + ')' if evidence else ''}")
    for name, value in numbers.items():
        print(f"  {name}: {value}")
    table, silent = check_buttons.audit(lines)
    print(f"  buttons: {sum(r[0] for r in table.values())} presses, {len(silent)} silent")
    for line in silent:
        print("    silent:", line)
    failed = not all(done for _, done, _ in steps) or bool(silent)
    saved = next((m for n in reversed(lines) if (m := SAVED.search(n))), None)
    if replay and saved:
        fixture = USER / "fixtures" / saved.group(2)
        name = fixture.stem.replace("-", "_")
        target = REPO / "tests/replay" / f"{name}.json"
        if not target.exists():
            r = subprocess.run([sys.executable, str(REPO / "tools/import_fixture.py"), str(fixture), name], cwd=REPO)
            if r.returncode != 0:
                return 1
        r = subprocess.run(["bash", "-l", "-c", f"tools/test.sh replay tests/replay/{target.name}"], cwd=REPO)
        print(f"  replay of {target.name}: {'ok, twice to its hash' if r.returncode == 0 else 'FAILED'}")
        failed = failed or r.returncode != 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
