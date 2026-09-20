import tempfile
import unittest
from pathlib import Path

from tools import check_dependencies as cd


class Repo:
    """A throwaway repository layout for one test."""

    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def write(self, rel: str, text: str) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def cleanup(self) -> None:
        self._tmp.cleanup()


class CheckDependenciesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Repo()
        self.addCleanup(self.repo.cleanup)

    def test_clean_repo_has_no_violations(self) -> None:
        self.repo.write("sim/core/a.gd", 'class_name A extends RefCounted\nvar b: int = preload("res://sim/core/b.gd").X\n')
        self.repo.write("sim/core/b.gd", "class_name B extends RefCounted\nconst X: int = 1\n")
        self.repo.write("client/main.gd", 'extends Control\nvar a: A = A.new()\nvar t: float = Time.get_unix_time_from_system()\n')
        self.repo.write("content/README.md", "data only\n")
        self.assertEqual(cd.run(self.repo.root), [])

    def test_sim_path_reference_to_client_is_a_violation(self) -> None:
        self.repo.write("sim/x.gd", 'extends RefCounted\nvar s: Variant = load("res://client/main.tscn")\n')
        problems = cd.run(self.repo.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("sim/x.gd:2", problems[0])
        self.assertIn("res://client/main.tscn", problems[0])

    def test_sim_scene_ext_resource_to_client_is_a_violation(self) -> None:
        self.repo.write("sim/x.tscn", '[ext_resource type="Script" path="res://client/hud/thing.gd" id="1"]\n')
        problems = cd.run(self.repo.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("sim/x.tscn:1", problems[0])

    def test_sim_reference_to_tools_or_tests_is_a_violation(self) -> None:
        self.repo.write("sim/x.gd", 'extends "res://tools/helper.gd"\n')
        self.assertEqual(len(cd.run(self.repo.root)), 1)

    def test_sim_use_of_client_class_name_is_a_violation(self) -> None:
        self.repo.write("client/local_host.gd", "class_name LocalHost extends Node\n")
        self.repo.write("sim/x.gd", "extends RefCounted\nvar host: LocalHost\n")
        problems = cd.run(self.repo.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("LocalHost", problems[0])
        self.assertIn("client/local_host.gd", problems[0])

    def test_client_class_name_match_is_whole_word(self) -> None:
        self.repo.write("client/local_host.gd", "class_name LocalHost extends Node\n")
        self.repo.write("sim/x.gd", "extends RefCounted\nvar local_hosts: int = 0\nvar LocalHostile: int = 0\n")
        self.assertEqual(cd.run(self.repo.root), [])

    def test_denylist_catches_input_time_and_global_rng(self) -> None:
        self.repo.write(
            "sim/x.gd",
            "extends RefCounted\n"
            "func f() -> void:\n"
            "\tif Input.is_action_pressed(&\"jump\"):\n"
            "\t\tpass\n"
            "\tvar t: int = Time.get_ticks_msec()\n"
            "\tvar r: int = randi()\n"
            "\tvar a: Array = [1]\n"
            "\ta.shuffle()\n",
        )
        problems = cd.run(self.repo.root)
        self.assertEqual(len(problems), 4, problems)
        self.assertTrue(any(":3:" in p and "Input" in p for p in problems))
        self.assertTrue(any(":5:" in p and "Time." in p for p in problems))
        self.assertTrue(any(":6:" in p and "randi" in p for p in problems))
        self.assertTrue(any(":8:" in p and "shuffle" in p for p in problems))

    def test_denylist_ignores_comments_and_substrings(self) -> None:
        self.repo.write(
            "sim/x.gd",
            "extends RefCounted\n"
            "# Input and Time and randi() are mentioned here only in a comment\n"
            "## Doc comment: never use OS.get_name()\n"
            "var input_count: int = 0\n"
            "var timeline: int = 0\n"
            "var brandish: int = 0\n"
            "func rng() -> RandomNumberGenerator:\n"
            "\treturn RandomNumberGenerator.new()\n"
            "func g() -> int:\n"
            "\treturn rng().randi()\n",
        )
        self.assertEqual(cd.run(self.repo.root), [])

    def test_content_may_not_hold_code(self) -> None:
        self.repo.write("content/weapons/pistol.gd", "extends RefCounted\n")
        self.repo.write("content/weapons/pistol.json", "{}\n")
        problems = cd.run(self.repo.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("content/weapons/pistol.gd", problems[0])

    def test_real_repository_is_clean(self) -> None:
        root = Path(__file__).resolve().parent.parent.parent
        self.assertEqual(cd.run(root), [])


if __name__ == "__main__":
    unittest.main()
