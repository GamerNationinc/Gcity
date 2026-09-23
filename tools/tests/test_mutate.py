import unittest

from tools import mutate


class Operators(unittest.TestCase):
    """The four operators the standards name, and the lines they must leave alone."""

    def ops(self, line: str) -> list[str]:
        return [op for op, _ in mutate.mutations(line)]

    def rewrite(self, line: str, operator: str) -> str:
        for op, out in mutate.mutations(line):
            if op == operator:
                return out
        raise AssertionError(f"{operator} not offered for {line!r}")

    def test_comparisons_flip_one_at_a_time(self) -> None:
        self.assertEqual(self.rewrite("\tif n < 0:", "< -> <="), "\tif n <= 0:")
        self.assertEqual(self.rewrite("\tif n >= cap:", ">= -> >"), "\tif n > cap:")
        self.assertEqual(self.rewrite("\tif a == b:", "== -> !="), "\tif a != b:")
        self.assertEqual(self.rewrite("\tif a != b:", "!= -> =="), "\tif a == b:")

    def test_a_comparison_inside_a_string_is_not_one(self) -> None:
        self.assertEqual(self.ops('\tvar s: String = "a < b"'), [])

    def test_a_comment_is_not_code(self) -> None:
        self.assertEqual(self.ops("\t# if n < 0:"), [])
        self.assertEqual(self.ops("## docs mentioning == equality"), [])

    def test_an_annotation_or_declaration_is_left_alone(self) -> None:
        self.assertEqual(self.ops("class_name Foo extends Bar"), [])
        self.assertEqual(self.ops("@abstract"), [])
        self.assertEqual(self.ops("extends SceneTree"), [])

    def test_an_assert_is_not_a_mutant(self) -> None:
        # asserts state what the code believes; mutating them tests the belief, not the
        # tests, and they are compiled out of a release build anyway
        self.assertEqual(self.ops('\tassert(n > 0, "positive")'), [])

    def test_boolean_returns_flip(self) -> None:
        self.assertEqual(self.rewrite("\treturn true", "return true -> false"), "\treturn false")
        self.assertEqual(self.rewrite("\t\treturn false", "return false -> true"), "\t\treturn true")

    def test_integer_constants_step(self) -> None:
        self.assertEqual(self.rewrite("\tvar x: int = 40", "40 -> 41"), "\tvar x: int = 41")
        self.assertIn("0 -> 1", self.ops("\tif n < 0:"))

    def test_a_statement_can_be_deleted_but_not_a_block_opener(self) -> None:
        self.assertEqual(self.rewrite("\t_events.emit(E, {})", "statement deleted"), "\tpass")
        self.assertNotIn("statement deleted", self.ops("\tif n < 0:"))
        self.assertNotIn("statement deleted", self.ops("\treturn true"))
        self.assertNotIn("statement deleted", self.ops("\tvar x: int = 1"))

    def test_every_rewrite_actually_changes_the_line(self) -> None:
        lines = [
            "\tif n < 0:", "\treturn true", "\tvar x: int = 40",
            "\t_events.emit(E, {})", "\tif a == b and c != d:",
        ]
        for line in lines:
            for operator, out in mutate.mutations(line):
                self.assertNotEqual(out, line, f"{operator} on {line!r} changed nothing")


class TestMapping(unittest.TestCase):
    """A mutant is killed by the tests that cover it, not by the whole suite."""

    def test_a_system_maps_to_its_own_test_and_the_assembly(self) -> None:
        tests = mutate.tests_for("sim/quests/run_score_system.gd")
        self.assertIn("res://tests/quests/test_run_score.gd", tests)
        self.assertIn("res://tests/sim/test_sim_assembly.gd", tests)

    def test_an_unmapped_file_still_runs_the_assembly(self) -> None:
        tests = mutate.tests_for("sim/nowhere/imaginary.gd")
        self.assertEqual(tests, mutate.ALWAYS)

    def test_every_named_test_file_exists(self) -> None:
        named = set(mutate.ALWAYS)
        for paths in mutate.EXTRA_TESTS.values():
            named.update(paths)
        for path in sorted(named):
            rel = path.removeprefix("res://")
            self.assertTrue((mutate.ROOT / rel).exists(), f"{path} does not exist")

    def test_every_mapped_sim_file_exists(self) -> None:
        for rel in sorted(mutate.EXTRA_TESTS):
            self.assertTrue((mutate.ROOT / rel).exists(), f"{rel} does not exist")


if __name__ == "__main__":
    unittest.main()


class InvalidMutants(unittest.TestCase):
    """A mutant that will not compile is not a mutant the tests caught."""

    def test_a_return_arrow_is_not_a_comparison(self) -> None:
        # `-> void:` became `->= void:`, which is a parse error, and the run that
        # failed to compile was being counted as a kill
        line = "func _on_event(payload: Dictionary, event: StringName) -> void:"
        self.assertEqual(mutate.mutations(line), [])
        self.assertEqual(mutate.mutations("func f(a: int) -> int:"), [])

    def test_an_invalid_mutant_is_left_out_of_the_score(self) -> None:
        report = mutate.Report()
        killed = mutate.Mutant("a.gd", 1, "op", "x", "y", outcome="failed")
        survived = mutate.Mutant("a.gd", 2, "op", "x", "y", outcome="passed")
        broken = mutate.Mutant("a.gd", 3, "op", "x", "y", outcome="invalid")
        report.mutants = [killed, survived, broken]
        self.assertEqual(len(report.scored), 2)
        self.assertEqual(len(report.invalid), 1)
        self.assertEqual(report.killed, 1)
        self.assertAlmostEqual(report.score, 50.0)

    def test_a_score_with_nothing_to_score_is_zero_not_a_crash(self) -> None:
        self.assertEqual(mutate.Report().score, 0.0)
