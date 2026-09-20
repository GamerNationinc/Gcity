import tempfile
import unittest
from pathlib import Path

from tools import validate_content as vc


class ValidateContentTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        (self.root / "content").mkdir()

    def write(self, rel: str, text: str) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def register(self, kind: str) -> None:
        self.write(f"tools/content_schemas/{kind}.json", "{}\n")

    def test_empty_content_is_clean(self) -> None:
        self.write("content/README.md", "x\n")
        self.assertEqual(vc.run(self.root), [])

    def test_missing_content_directory_is_a_problem(self) -> None:
        (self.root / "content").rmdir()
        self.assertEqual(len(vc.run(self.root)), 1)

    def test_unregistered_kind_fails_with_schema_path(self) -> None:
        self.write("content/weapons/pistol.json", '{"schema_version": 1}\n')
        problems = vc.run(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("tools/content_schemas/weapons.json", problems[0])

    def test_registered_kind_with_valid_file_is_clean(self) -> None:
        self.register("weapons")
        self.write("content/weapons/pistol_g19.json", '{"schema_version": 1, "id": "pistol_g19"}\n')
        self.assertEqual(vc.run(self.root), [])

    def test_layout_rules(self) -> None:
        self.register("weapons")
        self.write("content/loose.json", '{"schema_version": 1}\n')
        self.write("content/weapons/deep/x.json", '{"schema_version": 1}\n')
        self.write("content/weapons/notes.txt", "x\n")
        self.write("content/weapons/Bad-Id.json", '{"schema_version": 1}\n')
        problems = vc.run(self.root)
        self.assertEqual(len(problems), 4, problems)

    def test_malformed_json_and_versions(self) -> None:
        self.register("weapons")
        self.write("content/weapons/a.json", "{\n")
        self.write("content/weapons/b.json", "[]\n")
        self.write("content/weapons/c.json", '{"schema_version": "1"}\n')
        self.write("content/weapons/d.json", '{"schema_version": 0}\n')
        self.write("content/weapons/e.json", '{"schema_version": true}\n')
        self.write("content/weapons/f.json", '{"id": "f"}\n')
        problems = vc.run(self.root)
        self.assertEqual(len(problems), 6, problems)

    def test_real_repository_is_clean(self) -> None:
        root = Path(__file__).resolve().parent.parent.parent
        self.assertEqual(vc.run(root), [])


if __name__ == "__main__":
    unittest.main()


class SchemaDialectTest(ValidateContentTest):
    STAT = ('{"schema_version": 1, "properties": {'
            '"schema_version": {"type": "int", "min": 1, "max": 1}, '
            '"default_base": {"type": "int", "min": -10, "max": 10}, '
            '"description": {"type": "string", "min_length": 1, "max_length": 20, "pattern": "[A-Za-z .]+"}, '
            '"tags": {"type": "array", "max_length": 2, "items": {"type": "string", "pattern": "[a-z_.]+"}}, '
            '"nested": {"type": "object", "properties": {"n": {"type": "number"}}, "required": ["n"], "additional_properties": false}, '
            '"uses": {"type": "string", "ref": "stat"}, '
            '"flag": {"type": "bool"}}, '
            '"required": ["schema_version", "default_base", "description"], "additional_properties": false}\n')

    def setUp(self) -> None:
        super().setUp()
        self.write("tools/content_schemas/stat.json", self.STAT)

    def test_valid_file_is_clean(self) -> None:
        self.write("content/stat/damage.json", '{"schema_version": 1, "default_base": 3, "description": "Damage dealt.", '
                   '"tags": ["a.b"], "nested": {"n": 1.5}, "uses": "damage", "flag": true}\n')
        self.assertEqual(vc.run(self.root), [])

    def test_each_rule_fails_with_the_field_named(self) -> None:
        cases = {
            "a": ('{"schema_version": 1, "default_base": 3}', "missing required 'description'"),
            "b": ('{"schema_version": 1, "default_base": 3, "description": "x", "extra": 1}', "unexpected 'extra'"),
            "c": ('{"schema_version": 1, "default_base": 3.0, "description": "x"}', "default_base: must be int"),
            "d": ('{"schema_version": 1, "default_base": true, "description": "x"}', "default_base: must be int"),
            "e": ('{"schema_version": 1, "default_base": 11, "description": "x"}', "default_base: must be <= 10"),
            "f": ('{"schema_version": 1, "default_base": -11, "description": "x"}', "default_base: must be >= -10"),
            "g": ('{"schema_version": 1, "default_base": 1, "description": ""}', "description: length must be >= 1"),
            "h": ('{"schema_version": 1, "default_base": 1, "description": "way too long a description"}', "length must be <= 20"),
            "i": ('{"schema_version": 1, "default_base": 1, "description": "x1"}', "description: must match"),
            "j": ('{"schema_version": 1, "default_base": 1, "description": "x", "tags": ["a", "b", "c"]}', "tags: length must be <= 2"),
            "k": ('{"schema_version": 1, "default_base": 1, "description": "x", "tags": ["A"]}', "tags[0]: must match"),
            "l": ('{"schema_version": 1, "default_base": 1, "description": "x", "nested": {"m": 1}}', "nested: missing required 'n'"),
            "m": ('{"schema_version": 1, "default_base": 1, "description": "x", "nested": {"n": "s"}}', "nested.n: must be number"),
            "n": ('{"schema_version": 1, "default_base": 1, "description": "x", "uses": "nope"}', "not an id under content/stat/"),
            "o": ('{"schema_version": 1, "default_base": 1, "description": "x", "flag": 1}', "flag: must be bool"),
            "p": ('{"schema_version": 1, "default_base": 1, "description": "x", "tags": "a"}', "tags: must be array"),
        }
        for name, (text, _) in cases.items():
            self.write(f"content/stat/{name}.json", text + "\n")
        problems = vc.run(self.root)
        for name, (_, expected) in cases.items():
            matching = [p for p in problems if p.startswith(f"content/stat/{name}.json") and expected in p]
            self.assertTrue(matching, f"{name}: expected a problem containing {expected!r}, got {problems}")
        files_with_problems = {p.split(":")[0] for p in problems}
        self.assertEqual(len(files_with_problems), len(cases), problems)

    def test_ref_sees_ids_of_other_kinds(self) -> None:
        self.write("tools/content_schemas/perk.json", '{"properties": {"stat": {"type": "string", "ref": "stat"}}}\n')
        self.write("content/stat/damage.json", '{"schema_version": 1, "default_base": 0, "description": "d"}\n')
        self.write("content/perk/focus.json", '{"schema_version": 1, "stat": "damage"}\n')
        self.write("content/perk/broken.json", '{"schema_version": 1, "stat": "armour"}\n')
        problems = vc.run(self.root)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("content/perk/broken.json", problems[0])

    def test_unparseable_schema_is_reported_once(self) -> None:
        self.write("tools/content_schemas/perk.json", "{\n")
        self.write("content/perk/x.json", '{"schema_version": 1}\n')
        problems = vc.run(self.root)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("tools/content_schemas/perk.json", problems[0])

    def test_real_repository_content_is_clean(self) -> None:
        repo = Path(__file__).resolve().parent.parent.parent
        self.assertEqual(vc.run(repo), [])
