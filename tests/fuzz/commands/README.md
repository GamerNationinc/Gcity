# Hostile command corpus

`hostile_payloads.json` holds malformed, out-of-range, wrong-owner and wrong-kind
payloads for every command kind the M1 sim registers, plus unknown kinds. The test
`tests/sim/test_replay.gd::test_hostile_command_corpus_is_rejected_without_state_change`
sets up the standard range (the first four ticks of `tests/replay/m1-range.json`) and
dispatches each case: every one must be counted as rejected and the systems' state hash
must not move. A payload that ever gets through is a security bug (standards §5.2), and
the case that found it stays here as a regression.

Random mutation fuzz for the item commands runs in
`tests/items/test_item_system.gd::test_property_hostile_payloads_are_rejected_without_damage`
(10 000 cases per run).
