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

    def test_device_scripts_hold_no_sim_state_between_frames(self) -> None:
        self.repo.write("client/device/apps/ok_app.gd", "extends Control\nvar _cursor: int = 0\nvar _label: RichTextLabel\nvar _submit: Callable = Callable()\n")
        self.assertEqual(cd.run(self.repo.root), [])
        self.repo.write("client/device/apps/bad_app.gd", "extends Control\nvar _items: Array[int] = []\nvar _wielded: int = 0\nvar _cache: Dictionary = {}\nvar untyped = 3\n")
        problems = cd.run(self.repo.root)
        self.assertEqual(len(problems), 4)
        for name in ["_items", "_wielded", "_cache", "untyped"]:
            self.assertTrue(any(f"`var {name}`" in p and "rule 4" in p for p in problems), name)
        self.repo.write("client/hud/anything.gd", "extends Control\nvar _items: Array[int] = []\n")
        self.assertEqual(len(cd.run(self.repo.root)), 4, "the rule covers client/device only")

    def test_client_calls_no_sim_setter(self) -> None:
        # M6 spec claim 3: every public set_* method declared under sim/ is a sim setter
        self.repo.write("sim/agents/actors.gd", "class_name Actors extends RefCounted\nfunc set_position(a: int, p: Vector3i) -> Error:\n\treturn OK\nfunc _set_hidden() -> void:\n\tpass\n")
        self.repo.write("client/view.gd", "extends Node3D\nfunc f(actors: Actors, glyphs: Object) -> void:\n\tglyphs.set_deck(true)\n\tactors.set_position(1, Vector3i.ZERO)\n")
        problems = cd.run(self.repo.root)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("client/view.gd:4", problems[0])
        self.assertIn("set_position", problems[0])
        # a client method of the same shape that the sim does not declare is fine
        self.repo.write("client/view.gd", "extends Node3D\nfunc f(glyphs: Object) -> void:\n\tglyphs.set_deck(true)\n\tglyphs.set_hidden(true)\n")
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


class M1RulesTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        for d in ("sim/core", "sim/items", "sim/progression", "client", "content"):
            (self.root / d).mkdir(parents=True)

    def write(self, rel: str, text: str) -> None:
        (self.root / rel).write_text(text, encoding="utf-8")

    def test_only_the_resolver_reads_bases_and_modifiers(self) -> None:
        self.write("sim/progression/stat_resolver.gd", "var _bases: Dictionary = {}\nfunc get_base(e: int, s: StringName) -> int:\n\treturn 0\n")
        self.write("sim/items/item_system.gd", "func f(r: StatResolver) -> int:\n\treturn r.get_base(1, &\"damage\")\n")
        self.write("sim/core/x.gd", "var _modifiers: Dictionary = {}\n")
        problems = cd.run(self.root)
        self.assertEqual(len(problems), 2, problems)
        self.assertTrue(any("item_system.gd:2" in p and "get_base" in p for p in problems), problems)
        self.assertTrue(any("x.gd:1" in p and "_modifiers" in p for p in problems), problems)

    def test_client_views_only_submit(self) -> None:
        self.write("client/local_host.gd", "func _physics_process(_d: float) -> void:\n\t_sim.step()\n\t_sim = SimAssembly.build(1, _content)\n")
        self.write("client/content_loader.gd", "func load_all(db: ContentDb) -> Error:\n\treturn db.add(&\"a\", &\"b\", {})\n")
        self.write("client/main.gd", "func _p() -> void:\n\tsim.submit(SimCommand.new(1, &\"x\", {}))\n\tvar v: int = stats.resolve(1, &\"damage\")\n\titems.spawn(&\"ammo\", &\"x\", &\"world\", 1)\n\tsim.step()\n\tstats.set_base(1, &\"damage\", 5)\n")
        problems = cd.run(self.root)
        self.assertEqual(len(problems), 3, problems)
        self.assertTrue(all("client/main.gd" in p for p in problems), problems)

    def test_real_repository_is_clean_under_the_new_rules(self) -> None:
        repo = Path(__file__).resolve().parent.parent.parent
        self.assertEqual(cd.run(repo), [])
