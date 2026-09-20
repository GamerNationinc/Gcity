# Replay fixtures

`save = seed + input stream`, replayed headless, asserted by state hash
(engineering standards §3.1). Every milestone from M1 on adds at least one; CI replays
all of them on every commit.

Format: see `sim/core/replay_fixture.gd` (schema version 1). To record a new fixture,
write it with `"expected_hash": ""`, run

```
tools/test.sh replay tests/replay/<name>.json
```

and paste the printed hash in. A fixture whose hash changes is either a deliberate sim
change (update the hash in the same commit, and say why) or a nondeterminism bug.
