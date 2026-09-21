#!/usr/bin/env python3
"""Fails a headless test run that logged errors no test asserted on.

The runner (tests/run_tests.gd) can only see assertions. A test can pass while the
engine logged "SCRIPT ERROR: Trying to assign ..." or a bad-index error underneath it,
which is exactly the silent failure the standards forbid (§10, "never"). This filter
reads the run's combined output and reports:

  * every `SCRIPT ERROR:` line (GDScript runtime errors are always bugs), and
  * every `ERROR:`/`USER ERROR:` line whose `at:` line is not `push_error` — the sim's
    deliberate loud rejections go through push_error and are exercised by tests on
    purpose; anything else (engine-internal errors, failed loads) is a bug.

usage: check_test_log.py <log file>     exit 0 when clean, 1 with the offending lines.
Standard library only.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SCRIPT_ERROR = re.compile(r"^\s*SCRIPT ERROR:")
ENGINE_ERROR = re.compile(r"^\s*(USER )?ERROR:")
AT_LINE = re.compile(r"^\s*at: (?P<where>.+)$")
PUSH_ERROR_AT = re.compile(r"^push_error \(")


def offending_lines(text: str) -> list[str]:
    lines = text.splitlines()
    found: list[str] = []
    for i, line in enumerate(lines):
        if SCRIPT_ERROR.match(line):
            found.append(f"{i + 1}: {line.strip()}")
            continue
        if ENGINE_ERROR.match(line):
            where = ""
            for follow in lines[i + 1 : i + 4]:
                m = AT_LINE.match(follow)
                if m:
                    where = m.group("where")
                    break
            if not PUSH_ERROR_AT.match(where):
                found.append(f"{i + 1}: {line.strip()}  [at: {where or 'unknown'}]")
    return found


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    found = offending_lines(Path(argv[1]).read_text(encoding="utf-8", errors="replace"))
    if found:
        print(f"check_test_log: {len(found)} error line(s) not produced by push_error:")
        for line in found:
            print(f"  {line}")
        return 1
    print("check_test_log: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
