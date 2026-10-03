"""M7.5 spec claim 16: tools/import_site.py brings a creator-tool site into content/site,
checked by the validator CI runs, and refuses anything else with a message."""
import json
import random
import shutil
import tempfile
import unittest
from pathlib import Path

from tools import import_site as imp
from tools import validate_content as vc

REPO = Path(__file__).resolve().parent.parent.parent
CORPUS = REPO / "tests" / "fuzz" / "import_site"
GOOD = REPO / "content" / "site" / "m4_test_building.json"
FUZZ_CASES = 500


class ImportSiteTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name) / "repo"
        shutil.copytree(REPO / "content", self.root / "content")
        shutil.copytree(REPO / "tools" / "content_schemas", self.root / "tools" / "content_schemas")
        self.inbox = Path(self._tmp.name) / "inbox"
        self.inbox.mkdir()

    def file(self, name: str, text: str) -> Path:
        path = self.inbox / name
        path.write_text(text, encoding="utf-8")
        return path

    def site_files(self) -> set[str]:
        return {p.name for p in (self.root / "content" / "site").glob("*.json")}

    def test_a_good_site_is_imported_under_its_new_id_and_the_content_stays_clean(self) -> None:
        self.assertEqual(imp.import_site(GOOD, "corner_shop", "Corner shop", self.root), [])
        written = json.loads((self.root / "content" / "site" / "corner_shop.json").read_text(encoding="utf-8"))
        original = json.loads(GOOD.read_text(encoding="utf-8"))
        self.assertEqual(written["title"], "Corner shop")
        original["title"] = "Corner shop"
        self.assertEqual(written, original, "nothing else about it changed")
        self.assertEqual(vc.run(self.root), [], "and the content validator CI runs is still clean")

    def test_without_a_title_it_keeps_its_own(self) -> None:
        self.assertEqual(imp.import_site(GOOD, "kept", None, self.root), [])
        written = json.loads((self.root / "content" / "site" / "kept.json").read_text(encoding="utf-8"))
        self.assertEqual(written["title"], json.loads(GOOD.read_text(encoding="utf-8"))["title"])

    def test_every_corpus_file_is_refused_with_a_reason_and_nothing_written(self) -> None:
        files = sorted(CORPUS.glob("*.json"))
        self.assertGreaterEqual(len(files), 20, "the corpus is there")
        for path in files:
            with self.subTest(path.name):
                problems = imp.import_site(path, "fuzzed_" + path.stem, None, self.root)
                self.assertTrue(problems, f"{path.name} is refused")
                self.assertTrue(all(isinstance(p, str) and p for p in problems), "each with a message")
                self.assertFalse((self.root / "content" / "site" / f"fuzzed_{path.stem}.json").exists(), "and nothing is written")

    def test_an_oversized_file_is_refused_before_it_is_read(self) -> None:
        big = self.file("big.json", " " * (imp.MAX_BYTES + 1))
        problems = imp.import_site(big, "big", None, self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("more than a site can be", problems[0])

    def test_a_bad_id_a_taken_id_a_bad_title_and_a_missing_file(self) -> None:
        self.assertIn("must match", imp.import_site(GOOD, "Corner Shop", None, self.root)[0])
        self.assertIn("exists", imp.import_site(GOOD, "cold_storage", None, self.root)[0])
        self.assertTrue(imp.import_site(GOOD, "long", "x" * 61, self.root), "a title past the schema's length")
        self.assertIn("cannot read", imp.import_site(self.inbox / "nope.json", "nope", None, self.root)[0])
        self.assertEqual(self.site_files(), {p.name for p in (REPO / "content" / "site").glob("*.json")})

    def test_a_face_is_one_slot_from_either_side(self) -> None:
        self.assertEqual(imp.slot([1, 1, 0], "nx"), imp.slot([0, 1, 0], "px"))
        self.assertEqual(imp.slot([0, 2, 0], "ny"), imp.slot([0, 1, 0], "py"))
        self.assertNotEqual(imp.slot([0, 1, 0], ""), imp.slot([0, 1, 0], "px"), "a cell is not its face")

    def test_main_reports_and_exits_by_outcome(self) -> None:
        self.assertEqual(imp.main(["import_site.py"]), 2, "usage")

    def test_fuzz_mutated_sites_never_crash_and_what_is_accepted_is_valid(self) -> None:
        rng = random.Random(20261416)
        good = json.loads(GOOD.read_text(encoding="utf-8"))
        text = GOOD.read_text(encoding="utf-8")
        accepted = 0
        for case in range(FUZZ_CASES):
            if case % 2 == 0:
                raw = bytearray(text.encode("utf-8"))
                for _ in range(rng.randint(1, 4)):
                    raw[rng.randrange(len(raw))] = rng.randrange(256)
                path = self.inbox / f"bytes_{case}.json"
                path.write_bytes(bytes(raw))
            else:
                data = json.loads(json.dumps(good))
                _mutate(rng, data)
                path = self.file(f"value_{case}.json", json.dumps(data))
            site_id = f"fuzz_{case}"
            problems = imp.import_site(path, site_id, None, self.root)
            target = self.root / "content" / "site" / f"{site_id}.json"
            if problems:
                self.assertFalse(target.exists(), f"case {case}: refused and written")
                continue
            accepted += 1
            self.assertEqual(vc.run(self.root), [], f"case {case}: accepted, so the content is still valid")
            target.unlink()
        self.assertGreater(accepted, 0, "some mutations are harmless")
        self.assertLess(accepted, FUZZ_CASES, "and most are not")


def _mutate(rng: random.Random, data: dict) -> None:
    """One plausible edit by hand: a number, a name, a key or a list changed."""
    piece = rng.choice(data["pieces"])
    choice = rng.randrange(8)
    if choice == 0:
        piece["rel"][rng.randrange(3)] = rng.choice([-100001, 100001, 0, 1, 2.5, "1", None])
    elif choice == 1:
        piece["piece"] = rng.choice(["wall_panel", "nope", "", 7])
    elif choice == 2:
        piece["facing"] = rng.choice(["px", "nz", "", "up", None])
    elif choice == 3:
        data[rng.choice(["base", "title", "parcels", "spawns", "terminals", "schema_version"])] = rng.choice([[], {}, "x", -1, None, [0, 0, 0]])
    elif choice == 4:
        data.pop(rng.choice(list(data)))
    elif choice == 5:
        data["pieces"].append(dict(rng.choice(data["pieces"])))
    elif choice == 6:
        data["spawns"] = [{"profile": "guard_sim", "rel": [0, 1, 0], "facing": rng.randint(-5, 400), "squad": rng.randint(-1, 70), "route": ""}]
    else:
        piece[rng.choice(["extra", "hp"])] = 1


if __name__ == "__main__":
    unittest.main()
