## `--sandbox` (M7.6 spec claim 1): the game's content and the sandbox's, built by
## `SandboxAssembly`. The world view loads this script by path, never by name, so a
## release export that leaves `client/sandbox/` and `sim/sandbox/` out still runs, and
## `--sandbox` there says so instead of failing to parse (decision 1).
extends RefCounted

const CONTENT_ROOT: String = "res://sandbox_content"


## The game's content with the sandbox's added, or null (after an error).
static func content() -> ContentDb:
	var db := ContentDb.new()
	if ContentLoader.load_all(db) != OK:
		return null
	if DirAccess.dir_exists_absolute(CONTENT_ROOT) and ContentLoader.load_all(db, CONTENT_ROOT) != OK:
		return null
	return db


## Hands the host the sandbox's assembly and content. False when the content did not load.
static func install(host: LocalHost) -> bool:
	var db: ContentDb = content()
	if db == null:
		return false
	host.use_assembly(SandboxAssembly.build, db)
	return true
