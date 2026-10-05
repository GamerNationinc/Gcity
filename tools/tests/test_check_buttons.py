"""tools/check_buttons.py: a press with a result before the next press passes; one with
none, or one that arrived unbound, is reported (CEOGG, 2026-10-05)."""
import unittest

from tools import check_buttons as cb

LOG = """\
    0.001  t-1     launch   user args ["--create"]
    2.902  t118    input    create_left pressed (Joypad Button 13 (D-pad Left))
    2.902  t118    create   create_left -> cursor (41, 0, 46)
    3.146  t128    input    create_left released (Joypad Button 13 (D-pad Left))
    4.000  t150    input    device_secondary pressed (Joypad Button 3 (Top Action))
    4.100  t152    beat     90 fps
    4.200  t155    input    device_secondary released (Joypad Button 3 (Top Action))
    5.000  t160    input    unbound pressed (Joypad Button 7)
    5.000  t160    note     unbound button
    6.000  t170    input    world_device pressed (Joypad Button 4 (Back))
    6.200  t175    input    world_device released (Joypad Button 4 (Back))
    6.200  t175    command  sim.pause {"actor":1}
""".splitlines()


class CheckButtonsTest(unittest.TestCase):
    def test_silent_and_unbound_presses_are_reported(self) -> None:
        table, silent = cb.audit(LOG)
        self.assertEqual(table["create_left"], [1, 1])
        self.assertEqual(table["device_secondary"], [1, 0], "a beat is not a result")
        self.assertEqual(table["world_device"], [1, 1], "a result on release counts")
        self.assertEqual(len(silent), 2)
        self.assertIn("device_secondary", silent[0])
        self.assertIn("unbound", silent[1])

    def test_a_clean_run_has_nothing_silent(self) -> None:
        _, silent = cb.audit(LOG[:4] + LOG[9:])
        self.assertEqual(silent, [])


if __name__ == "__main__":
    unittest.main()
