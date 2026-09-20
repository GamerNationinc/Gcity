import unittest

from tools import check_test_log as ctl


class CheckTestLogTest(unittest.TestCase):
    def test_push_error_is_allowed(self) -> None:
        log = (
            "ok   res://tests/x.gd::test_a\n"
            "ERROR: SimRoot: cannot register 'b' after tick 0\n"
            "   at: push_error (core/variant/variant_utility.cpp:1024)\n"
            "   GDScript backtrace (most recent call first):\n"
            "       [0] register_system (res://sim/core/sim_root.gd:67)\n"
            "ok   res://tests/x.gd::test_b\n"
        )
        self.assertEqual(ctl.offending_lines(log), [])

    def test_script_error_is_reported(self) -> None:
        log = (
            'SCRIPT ERROR: Trying to assign an array of type "Array" to a variable of type "Array[StringName]".\n'
            "          at: test_property (res://tests/progression/test_stat_resolver.gd:195)\n"
            "ok   res://tests/progression/test_stat_resolver.gd::test_property\n"
        )
        found = ctl.offending_lines(log)
        self.assertEqual(len(found), 1)
        self.assertIn("Trying to assign", found[0])

    def test_engine_error_not_from_push_error_is_reported(self) -> None:
        log = (
            'ERROR: Failed to load script "res://main.gd" with error "Parse error".\n'
            "   at: load (modules/gdscript/gdscript.cpp:2907)\n"
            "ERROR: Index p_index = 3 is out of bounds (size() = 3).\n"
            "   at: get (core/variant/array.cpp:210)\n"
            "USER ERROR: something via printerr-like path\n"
            "   at: _something (res://x.gd:1)\n"
        )
        found = ctl.offending_lines(log)
        self.assertEqual(len(found), 3, found)

    def test_error_without_at_line_is_reported(self) -> None:
        self.assertEqual(len(ctl.offending_lines("ERROR: orphan\n")), 1)

    def test_clean_log(self) -> None:
        self.assertEqual(ctl.offending_lines("ok   a\nok   b\n29 tests, 188 assertions, 0 failed\n"), [])
