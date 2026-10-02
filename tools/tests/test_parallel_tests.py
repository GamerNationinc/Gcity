"""Unit tests for tools/parallel_tests.py: discovery, the run-alone marker, scheduling,
and how per-file runs add up (a crash or a bad exit must never read as a pass)."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools import parallel_tests as pt


def run(path: str, log: str, code: int = 0) -> pt.FileRun:
    return pt.FileRun(path, log, code, 1.0)


class DiscoverTest(unittest.TestCase):
    def test_finds_test_files_sorted_and_skips_output_and_hidden(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel in ["tests/b/test_two.gd", "tests/a/test_one.gd", "tests/a/helper.gd",
                        "tests/out/test_scratch.gd", "tests/.hidden/test_hidden.gd", "tests/a/test_one.gd.uid"]:
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                (root / rel).write_text("", encoding="utf-8")
            old_out = pt.OUT
            pt.OUT = root / "tests" / "out"
            try:
                found = pt.discover(root)
            finally:
                pt.OUT = old_out
            self.assertEqual(found, ["res://tests/a/test_one.gd", "res://tests/b/test_two.gd"])

    def test_the_real_suite_is_found(self) -> None:
        found = pt.discover()
        self.assertIn("res://tests/client/test_terrain_streamer.gd", found)
        self.assertEqual(found, sorted(found))


class AloneTest(unittest.TestCase):
    def test_the_marker_is_a_header_line(self) -> None:
        self.assertTrue(pt.runs_alone("extends GcityTest\n\n## Runs alone: it times the mesher.\n"))
        self.assertFalse(pt.runs_alone("extends GcityTest\n## it runs alone sometimes\n"))
        self.assertFalse(pt.runs_alone('var s = "## Runs alone:"\n'))

    def test_the_two_wall_clock_files_carry_it(self) -> None:
        for rel in ["tests/client/test_surface_nets.gd", "tests/client/test_terrain_streamer.gd"]:
            self.assertTrue(pt.runs_alone((pt.ROOT / rel).read_text(encoding="utf-8")), rel)


class ScheduleTest(unittest.TestCase):
    def test_untimed_first_by_size_then_longest_recorded(self) -> None:
        order = pt.schedule(["a", "b", "c", "d"], {"a": 5.0, "b": 50.0}, {"c": 10, "d": 900, "a": 1, "b": 1})
        self.assertEqual(order, ["d", "c", "b", "a"])

    def test_ties_break_on_the_path(self) -> None:
        self.assertEqual(pt.schedule(["y", "x"], {"x": 1.0, "y": 1.0}, {}), ["x", "y"])


class SummariseTest(unittest.TestCase):
    def test_totals_add_up_over_files(self) -> None:
        runs = [run("b", "ok   b::t\n\n3 tests, 40 assertions, 0 failed\n"),
                run("a", "FAIL a::t\n\n2 tests, 7 assertions, 1 failed\n", 1)]
        self.assertEqual(pt.summarise(runs), (5, 47, 1, []))

    def test_a_run_without_a_summary_is_a_failure(self) -> None:
        tests, _, failed, problems = pt.summarise([run("a", "ok   a::t\nSegmentation fault\n", 139)])
        self.assertEqual((tests, failed), (1, 1))
        self.assertIn("without a summary (exit 139)", problems[0])

    def test_a_bad_exit_after_passing_tests_is_a_failure(self) -> None:
        _, _, failed, problems = pt.summarise([run("a", "1 tests, 1 assertions, 0 failed\n", 1)])
        self.assertEqual(failed, 1)
        self.assertIn("exited 1", problems[0])

    def test_a_file_with_no_tests_adds_nothing(self) -> None:
        # the base class tests/harness/test_case.gd is named like a test file
        log = "\n0 tests, 0 assertions, 0 failed\nno tests found under res://tests\n"
        self.assertEqual(pt.summarise([run("res://tests/harness/test_case.gd", log, 2)]), (0, 0, 0, []))

    def test_no_tests_with_another_exit_is_a_failure(self) -> None:
        _, _, failed, problems = pt.summarise([run("a", "\n0 tests, 0 assertions, 0 failed\n", 1)])
        self.assertEqual(failed, 1)
        self.assertIn("exited 1", problems[0])

    def test_no_tests_found_is_no_summary(self) -> None:
        _, _, failed, _ = pt.summarise([run("a", "no tests found under res://tests\n", 2)])
        self.assertEqual(failed, 1)


class UserDirTest(unittest.TestCase):
    def test_user_dirs_live_outside_the_project_and_are_removed(self) -> None:
        seen: list[Path] = []

        def stage() -> int:
            env = pt._user_dir("res://tests/agents/test_body.gd")
            seen.append(Path(env["XDG_DATA_HOME"]))
            return 0

        self.assertEqual(pt._with_user_root(stage), 0)
        folder = seen[0]
        self.assertNotIn(pt.ROOT, folder.parents)
        self.assertFalse(folder.name.endswith(".gd"), folder.name)
        self.assertFalse(folder.exists())


class JoinTest(unittest.TestCase):
    def test_logs_join_in_path_order_without_their_summaries(self) -> None:
        log = pt.joined_log([run("b", "ok   b\n\n1 tests, 1 assertions, 0 failed\n"),
                             run("a", "ERROR: x\n   at: push_error (y)\nok   a\n\n1 tests, 2 assertions, 0 failed\n")])
        self.assertEqual(log, "ERROR: x\n   at: push_error (y)\nok   a\nok   b\n")
        self.assertNotIn("assertions", log)


if __name__ == "__main__":
    unittest.main()
