## Reads content/<kind>/<id>.json into a [ContentDb]. Lives in client/ because the sim
## may not touch files (CLAUDE.md dependency rule); tools and tests use it too. The
## build-time validator has already checked structure; this loader only parses and
## hands dictionaries across the sim boundary, where ContentDb re-checks shape.
class_name ContentLoader extends RefCounted

const CONTENT_ROOT: String = "res://content"


## Loads every kind directory under `root`. Returns the first error; a partial load is
## an error, never a usable database.
static func load_all(db: ContentDb, root: String = CONTENT_ROOT) -> Error:
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		push_error("ContentLoader: cannot open %s: %s" % [root, error_string(DirAccess.get_open_error())])
		return ERR_FILE_CANT_OPEN
	var kinds: PackedStringArray = dir.get_directories()
	kinds.sort()
	for kind: String in kinds:
		var err: Error = _load_kind(db, root.path_join(kind), kind)
		if err != OK:
			return err
	return OK


static func _load_kind(db: ContentDb, dir_path: String, kind: String) -> Error:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("ContentLoader: cannot open %s" % dir_path)
		return ERR_FILE_CANT_OPEN
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file: String in files:
		if not file.ends_with(".json"):
			continue
		var path: String = dir_path.path_join(file)
		var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
		if handle == null:
			push_error("ContentLoader: cannot read %s: %s" % [path, error_string(FileAccess.get_open_error())])
			return ERR_FILE_CANT_READ
		var json: JSON = JSON.new()
		var parse_err: Error = json.parse(handle.get_as_text())
		if parse_err != OK:
			push_error("ContentLoader: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
			return ERR_PARSE_ERROR
		var data: Variant = json.data
		if typeof(data) != TYPE_DICTIONARY:
			push_error("ContentLoader: %s: top level must be an object" % path)
			return ERR_INVALID_DATA
		var dict: Dictionary = data
		JsonNumbers.normalise(dict)
		var add_err: Error = db.add(StringName(kind), StringName(file.get_basename()), dict)
		if add_err != OK:
			return add_err
	return OK
