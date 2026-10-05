"""tools/check_sandbox_run.py: every step of G7.6 §3's demo script is read off the run
log, and a step the run skipped is reported missing."""
import unittest

from tools import check_sandbox_run as cs

LOG = """\
    0.002  t-1     launch   user args ["--sandbox"]
    0.002  t-1     machine  Steam Deck env: SteamDeck=1, SteamAppId=1, SteamGameId=2
    0.002  t-1     build    executable /home/deck/Gcity/build/linux-dev/gcity-dev.x86_64
    5.000  t200    command  build.place {"actor":1,"piece":"foundation_block"}
    6.000  t240    command  build.place {"actor":1,"piece":"wall_panel"}
    6.500  t260    beat     90 fps, worst frame 11.1 ms, 90 frames
    7.000  t280    device   device_next_app -> Spawn: agents page: foot_patrol, unarmed
    8.000  t320    command  sandbox.spawn_agent {"actor":1,"kit":{"frame":"g19"},"profile":"foot_patrol"}
    9.000  t360    command  sandbox.spawn_agent {"actor":1,"kit":{"frame":"g19"},"profile":"foot_patrol"}
   10.000  t400    note     god mode on
   11.000  t440    note     every overlay on
   11.500  t460    beat     60 fps, worst frame 22.0 ms, 60 frames
   12.000  t480    world    device: lowered
   13.000  t520    sandbox  fly up
   14.000  t560    note     every guard frozen
   15.000  t600    note     every guard no longer frozen
   16.000  t640    note     time held
   17.000  t640    note     stepped to tick 641
   18.000  t641    note     time x1/4
   19.000  t650    note     time x1
   20.000  t690    note     saved user://fixtures/sandbox-20261005-150000.json: 690 ticks, 9 commands
""".splitlines()


class CheckSandboxRunTest(unittest.TestCase):
    def test_a_full_run_has_every_step(self) -> None:
        steps, numbers = cs.check(LOG)
        self.assertEqual([s for s, done, _ in steps if not done], [])
        self.assertIn("overlays off", numbers)
        self.assertIn("60 fps", numbers["overlays on"])

    def test_a_skipped_step_is_missing(self) -> None:
        steps, _ = cs.check([line for line in LOG if "frozen" not in line and "kit" not in line])
        missing = [s for s, done, _ in steps if not done]
        self.assertEqual(missing, ["4. two armed guards", "7. ai freeze / thaw"])

    def test_a_desktop_or_demo_launch_is_not_the_deck_run(self) -> None:
        steps, _ = cs.check([LOG[0].replace('"]', '", "--demo"]')] + LOG[1:])
        self.assertFalse(steps[0][1])
        steps, _ = cs.check([LOG[0], LOG[1].replace("SteamGameId=2", "SteamGameId=")] + LOG[2:])
        self.assertFalse(steps[0][1])


if __name__ == "__main__":
    unittest.main()
