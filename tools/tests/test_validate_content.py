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
