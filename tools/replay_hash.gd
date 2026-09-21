## Replays one fixture against the game's assembled sim and prints its state hash.
## Usage: godot --headless --path . -s tools/replay_hash.gd -- <fixture path>
## Exit 0 with the hash on stdout; exit 1 with a message on failure. CI runs this twice
## per fixture and diffs the output (standards §11, G0: bit-identical twice).
##
## The sim is built through SimAssembly over the shipped content, so a fixture replays
## against exactly the system set the player runs, and a content change moves every
## fixture hash visibly (M1 spec claim 16).
extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: -s tools/replay_hash.gd -- <fixture.json>")
		quit(1)
		return
	var path: String = args[0]
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	var fixture: ReplayFixture = ReplayFixture.parse(file.get_as_text())
	if not fixture.is_valid():
		printerr("invalid fixture %s: %s" % [path, fixture.error])
		quit(1)
		return
	var content := ContentDb.new()
	var load_err: Error = ContentLoader.load_all(content)
	if load_err != OK:
		printerr("content failed to load: %s" % error_string(load_err))
		quit(1)
		return
	var sim: SimRoot = SimAssembly.build(fixture.seed, content)
	if sim == null:
		printerr("sim assembly failed")
		quit(1)
		return
	var hash: String = Replay.run(fixture, sim)
	if hash.is_empty():
		printerr("replay of %s failed" % path)
		quit(1)
		return
	print(hash)
	quit(0)
