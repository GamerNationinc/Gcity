#!/usr/bin/env python3
"""The button audit of a Deck run (CEOGG, 2026-10-05: every button works or says why).

Reads a run log (`~/.local/share/godot/app_userdata/Gcity/logs/runs/run-*.log`) and, for
every press, looks for its result before the next press: a command sent, a creator or
device line (every press logs what it changed since bd1cb8e's follow-up), a note, or a
world-state line. Prints a table per button and every press that shows nothing.

    tools/check_buttons.py [run.log]      (default: the newest run log)

Exit 1 when any press was silent or arrived unbound.
"""
import pathlib
import re
import sys

RUNS = pathlib.Path.home() / ".local/share/godot/app_userdata/Gcity/logs/runs"
PRESS = re.compile(r"^\s*([\d.]+)\s+(t-?\d+)\s+input\s+(\S+) pressed")
RESULT = re.compile(r"^\s*[\d.]+\s+t-?\d+\s+(command|create|device|note|world|rejected)\s")


def audit(lines: list[str]) -> tuple[dict[str, list[int]], list[str]]:
    table: dict[str, list[int]] = {}
    silent: list[str] = []
    presses = []
    for i, l in enumerate(lines):
        m = PRESS.match(l)
        # logs before 2026-10-05 16:30 name one press twice outside the creator (A as
        # world_build_place and device_select, on the same line pair): one press, the first name
        if m and presses and lines[i - 1].strip() and PRESS.match(lines[i - 1]) and PRESS.match(lines[i - 1]).group(2) == m.group(2):
            continue
        if m:
            presses.append((i, m))
    for n, (i, m) in enumerate(presses):
        action = m.group(3)
        end = presses[n + 1][0] if n + 1 < len(presses) else len(lines)
        shown = any(RESULT.match(l) for l in lines[i + 1:end])
        row = table.setdefault(action, [0, 0])
        row[0] += 1
        row[1] += shown
        if not shown or action == "unbound":
            silent.append(lines[i].strip())
    return table, silent


def main() -> int:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else max(RUNS.glob("run-*.log"), key=lambda p: p.stat().st_mtime)
    table, silent = audit(path.read_text(encoding="utf-8").splitlines())
    print(f"{path.name}: {sum(r[0] for r in table.values())} presses, {len(silent)} silent")
    for action, (pressed, shown) in sorted(table.items()):
        print(f"  {action:20} {pressed:4} pressed  {shown:4} with a result{'' if pressed == shown else '   <-- check'}")
    for line in silent:
        print("  silent:", line)
    return 1 if silent else 0


if __name__ == "__main__":
    sys.exit(main())
