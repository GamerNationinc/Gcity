"""Unit tests for tools/mutate.py (M6 spec claim 23)."""
from __future__ import annotations

import unittest

from tools import mutate


class OperatorTests(unittest.TestCase):
    def ops(self, line: str) -> list[tuple[str, str]]:
        return [(m.op, m.after) for m in mutate.mutants_of_line("sim/items/x.gd", 1, line)]

    def test_comparisons_flip_and_arrows_and_shifts_are_left_alone(self) -> None:
        got = self.ops("\tif a < b and c >= 2:\n")
        self.assertIn(("cmp", "\tif a >= b and c >= 2:"), got)
        self.assertIn(("cmp", "\tif a < b and c < 2:"), got)
        self.assertIn(("andor", "\tif a < b or c >= 2:"), got)
        self.assertIn(("int", "\tif a < b and c >= 3:"), got)
        self.assertIn(("int", "\tif a < b and c >= 1:"), got)
        self.assertEqual([op for op, _ in self.ops("\tvar x: int = 1 << 20\n") if op == "cmp"], [])
        self.assertEqual(self.ops("func f(a: int) -> bool:\n"), [])

    def test_booleans_and_not(self) -> None:
        got = self.ops("\treturn not done and true\n")
        self.assertIn(("bool", "\treturn done and true"), got)
        self.assertIn(("bool", "\treturn not done and false"), got)

    def test_strings_comments_constants_and_floats_are_not_mutated(self) -> None:
        self.assertEqual(self.ops('\tpush_error("a < b == 3")\n'), [])
        self.assertEqual(self.ops("\t# x == 1\n"), [])
        self.assertEqual(self.ops("const LIMIT: int = 40\n"), [])
        self.assertEqual([a for op, a in self.ops("\tvar f: float = 1.5\n") if op == "int"], [])
        got = self.ops("\tvar n: int = 3  # was 2 < 3\n")
        self.assertEqual(sorted(a for _, a in got), ["\tvar n: int = 2  # was 2 < 3", "\tvar n: int = 4  # was 2 < 3"])

    def test_early_returns_use_the_return_types_zero(self) -> None:
        lines = ["func a() -> bool:\n", "\tvar x: int = 1\n", "\n", "static func b(v: int) -> Array[int]:\n", "\t# c\n", "\treturn [v]\n",
                 "func c() -> Vector3i:\n", "\treturn Vector3i.ZERO\n", "func d() -> void:\n", "\tpass\n"]
        got = {m.line: m.after for m in mutate.return_mutants("sim/x.gd", lines)}
        self.assertEqual(got[2], "\treturn false\n\tvar x: int = 1")
        self.assertEqual(got[6], "\treturn Array[int]()\n\treturn [v]")
        self.assertEqual(got[10], "\treturn\n\tpass")
        self.assertNotIn(8, got, "no zero for Vector3i: skipped")


class SamplingTests(unittest.TestCase):
    def test_sampling_is_fixed_by_the_seed_and_covers_every_module(self) -> None:
        pool = [mutate.Mutant(f"sim/{mod}/f.gd", i, "int", "a", "b") for mod in ("items", "land", "core") for i in range(1, 60)]
        pool += [mutate.Mutant("sim/assembly.gd", i, "int", "a", "b") for i in range(1, 5)]
        one = mutate.sample(pool, 100, 30, 7)
        two = mutate.sample(pool, 100, 30, 7)
        self.assertEqual(one, two)
        self.assertEqual(len(one), 100)
        for mod in ("items", "land", "core"):
            self.assertGreaterEqual(sum(1 for m in one if m.module == mod), 30)
        self.assertEqual(sum(1 for m in one if m.module == ""), 4, "a module with fewer than 30 gives all it has")
        self.assertNotEqual(mutate.sample(pool, 100, 30, 8), one)

    def test_the_real_tree_offers_enough_mutants(self) -> None:
        mutants = mutate.all_mutants()
        modules = {m.module for m in mutants}
        self.assertTrue({"agents", "items", "land", "nav", "quests", "threat", "core"} <= modules)
        self.assertGreaterEqual(len(mutants), 400)


class IntervalTests(unittest.TestCase):
    def test_wilson_interval(self) -> None:
        low, high = mutate.wilson(70, 100)
        self.assertAlmostEqual(low, 0.604, places=3)
        self.assertAlmostEqual(high, 0.781, places=3)
        self.assertEqual(mutate.wilson(0, 0), (0.0, 1.0))
        low, high = mutate.wilson(400, 400)
        self.assertEqual(high, 1.0)
        self.assertGreater(low, 0.99)


if __name__ == "__main__":
    unittest.main()


class ShardTests(unittest.TestCase):
    def test_shards_partition_the_sample_and_combine_to_one_score(self) -> None:
        import json
        import tempfile
        from pathlib import Path
        results = [{"file": f"sim/items/f.gd", "line": i, "op": "int", "before": "a", "after": "b", "module": "items",
                    "outcome": "killed" if i % 4 else "survived"} for i in range(1, 41)]
        with tempfile.TemporaryDirectory() as tmp:
            paths = []
            for k in range(4):
                part = mutate.summarise(results[k::4], 9)
                p = Path(tmp) / f"s{k}.json"
                p.write_text(json.dumps(part))
                paths.append(str(p))
            out = Path(tmp) / "all.json"
            self.assertEqual(mutate.main(["--combine", *paths, "--report", str(out)]), 0)
            combined = json.loads(out.read_text())
        self.assertEqual(combined["mutants"], 40)
        self.assertEqual(combined["killed"], 30)
        self.assertEqual(len(combined["survivors"]), 10)
