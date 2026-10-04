"""M7.6 spec claim 9: tools/import_fixture.py brings a sandbox session into tests/replay,
checked against the fixture schema, and refuses anything else with a message."""
import json
import tempfile
import unittest
from pathlib import Path

from tools import import_fixture as imp

GOOD = {
    "schema_version": 1, "name": "sandbox-20261004-120000", "seed": 7, "ticks": 3,
    "commands": [{"tick": 1, "kind": "sandbox.trainer", "payload": {"actor": 1, "effect": "god", "on": True}}],
    "expected_hash": "a" * 64, "assembly": "sandbox",
}


class ImportFixtureTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        (self.root / "tests" / "replay").mkdir(parents=True)

    def file(self, data: object) -> Path:
        path = self.root / "in.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def test_a_session_is_imported_under_its_name_once(self) -> None:
        self.assertEqual(imp.import_fixture(self.file(GOOD), None, self.root), [])
        written = json.loads((self.root / "tests" / "replay" / "sandbox-20261004-120000.json").read_text())
        self.assertEqual(written, GOOD)
        again = imp.import_fixture(self.file(GOOD), None, self.root)
        self.assertTrue(again and "never overwritten" in again[0])

    def test_a_new_name_is_given(self) -> None:
        self.assertEqual(imp.import_fixture(self.file(GOOD), "two-guards", self.root), [])
        written = json.loads((self.root / "tests" / "replay" / "two-guards.json").read_text())
        self.assertEqual(written["name"], "two-guards")

    def test_anything_else_is_refused_with_a_reason(self) -> None:
        cases = {
            "missing key 'ticks'": {k: v for k, v in GOOD.items() if k != "ticks"},
            "unknown key 'extra'": dict(GOOD, extra=1),
            "expected_hash": dict(GOOD, expected_hash=""),
            "assembly must be": dict(GOOD, assembly="mods"),
            "ticks must be": dict(GOOD, ticks=0),
            "tick must be from 1": dict(GOOD, commands=[dict(GOOD["commands"][0], tick=9)]),
            "exactly {tick, kind, payload}": dict(GOOD, commands=[{"tick": 1}]),
            "name '../x'": dict(GOOD, name="../x"),
            "seed must be": dict(GOOD, seed=1.5),
            "top level": [1, 2],
        }
        for expected, data in cases.items():
            found = imp.import_fixture(self.file(data), None, self.root)
            self.assertTrue(any(expected in p for p in found), "%s not in %s" % (expected, found))
        self.assertEqual(list((self.root / "tests" / "replay").iterdir()), [], "nothing written")


if __name__ == "__main__":
    unittest.main()
