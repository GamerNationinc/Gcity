extends GcityTest


func test_ids_start_at_one_and_never_repeat() -> void:
	var ids := EntityIds.new()
	assert_eq(ids.allocate(), 1, "first id")
	assert_eq(ids.allocate(), 2, "second id")
	assert_eq(ids.peek_next(), 3, "peek")
	assert_eq(ids.snapshot(), {"next": 3}, "snapshot")
	assert_eq(EntityIds.NONE, 0, "zero means none")


func test_restore_validates() -> void:
	var ids := EntityIds.new()
	assert_eq(ids.restore({"next": 0}), ERR_INVALID_DATA, "next below 1")
	assert_eq(ids.restore({"next": 1.0}), ERR_INVALID_DATA, "float")
	assert_eq(ids.restore({"next": 5, "extra": 1}), ERR_INVALID_DATA, "extra key")
	assert_eq(ids.restore({}), ERR_INVALID_DATA, "empty")
	assert_eq(ids.peek_next(), 1, "untouched by rejected restores")
	assert_eq(ids.restore({"next": 40}), OK, "valid")
	assert_eq(ids.allocate(), 40, "continues from the restored value")


## Mutation testing (M6 claim 12) found the lower bound untested from below: `next < 1`
## rejects nothing that `next < 2` or `next <= 1` would not also reject, unless
## something asserts that one is a legal place to restore from.
func test_one_is_a_legal_next_id() -> void:
	var ids := EntityIds.new()
	assert_eq(ids.restore({"next": 1}), OK, "a fresh allocator's own state restores")
	assert_eq(ids.peek_next(), 1, "and it is still fresh")
	assert_eq(ids.allocate(), 1, "the first id is one")
	assert_eq(ids.allocate(), 2, "then two")
	assert_eq(ids.restore({"next": 0}), ERR_INVALID_DATA, "zero is not an id")
	assert_eq(ids.restore({"next": -1}), ERR_INVALID_DATA, "nor is anything below it")
	assert_eq(ids.peek_next(), 3, "and neither rejection moved the allocator")
