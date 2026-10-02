extends GcityTest

## The run log (CEOGG, Deck run 2026-10-01): one file per launch, flushed as it goes,
## the newest thirty kept.


## No folder yet is no runs yet: on a machine the client has never run on, the first
## test opens the first log.
func _runs() -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(RunLog.DIR):
		return PackedStringArray()
	return DirAccess.get_files_at(RunLog.DIR)


func test_a_run_writes_its_header_its_lines_and_its_end_to_one_new_file() -> void:
	var before: int = _runs().size()
	var log: RunLog = RunLog.open(PackedStringArray(["--wilds"]))
	assert_true(log != null, "the log opens")
	var path: String = log.path()
	log.line(7, "note", "walked into the gate")
	log.flush()
	var mid: String = FileAccess.get_file_as_string(path)
	assert_true(mid.contains("walked into the gate"), "a flushed line is on disk before the run ends")
	assert_true(mid.contains("user args [\"--wilds\"]"), "the header records the launch")
	assert_true(mid.contains("controller") , "the header records the controllers")
	log.close(9, "quit")
	var text: String = FileAccess.get_file_as_string(path)
	assert_true(text.contains("t9      end      quit"), "the end is recorded with its tick")
	assert_true(_runs().size() <= maxi(before + 1, RunLog.KEEP), "one file more, within the limit")
	DirAccess.remove_absolute(path)


func test_only_the_newest_runs_are_kept() -> void:
	DirAccess.make_dir_recursive_absolute(RunLog.DIR)
	var made: Array[String] = []
	for i: int in RunLog.KEEP + 3:
		var name: String = "%s/run-0000-00-00_00-00-%02d.log" % [RunLog.DIR, i]
		FileAccess.open(name, FileAccess.WRITE).store_line("old")
		made.append(name)
	var log: RunLog = RunLog.open(PackedStringArray())
	var path: String = log.path()
	log.close(-1, "quit")
	assert_true(_runs().size() <= RunLog.KEEP, "at most %d runs kept (%d)" % [RunLog.KEEP, _runs().size()])
	assert_false(FileAccess.file_exists(made[0]), "the oldest went first")
	assert_true(FileAccess.file_exists(path), "the new one stayed")
	for name: String in made:
		DirAccess.remove_absolute(name)
	DirAccess.remove_absolute(path)
