# Fuzz corpus: replay fixture loader

Each file is a hostile or malformed fixture that `ReplayFixture.parse()` must reject
with a message and without crashing (engineering standards §3.5, §5.1). The test
`tests/sim/test_replay_fixture.gd` loads every `*.json` here on each run.

When a fuzzing session or a bug report finds a new input that misbehaves, commit it
here permanently as a regression case.
