extends GcityTest

## M7.5 claim 13: a scripted demo plays the world its run was proven in. The client
## picks a random world otherwise, and the stealth run is only clean in some of them.


func test_the_command_line_chooses_the_world() -> void:
	assert_eq(LocalHost.seed_from_args(PackedStringArray(["--seed=42"]), 0), 42, "--seed sets it")
	assert_eq(LocalHost.seed_from_args(PackedStringArray(["--demo", "--seed=-7"]), 0), -7, "and beats the demo's")
	assert_eq(LocalHost.seed_from_args(PackedStringArray(["--mission", "--demo"]), 0), LocalHost.DEMO_SEED, "a demo plays the fixtures' world")
	assert_eq(LocalHost.seed_from_args(PackedStringArray(["--wilds"]), 9), 9, "anything else leaves it alone")
	assert_eq(LocalHost.seed_from_args(PackedStringArray([]), 0), 0, "random when nothing asks")


func test_the_demo_world_is_the_one_the_stealth_fixture_proves() -> void:
	var fixture: ReplayFixture = ReplayFixture.parse(FileAccess.get_file_as_string("res://tests/replay/m6-stealth.json"))
	assert_true(fixture.is_valid(), "the fixture parses")
	assert_eq(fixture.seed, LocalHost.DEMO_SEED, "the demo's world is m6-stealth's")
