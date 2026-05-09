class_name SaveSystem
extends Node
## Sole persistence I/O layer for all game state.
## Implements ADR-0004: Atomic write protocol (.tmp + DirAccess.rename()).
##
## Usage:
##   SaveSystem.flush_profile(0, data)  # atomic write
##   var data = SaveSystem.load_profile(0)  # load + auto-migrate

const CURRENT_SCHEMA_VERSION: int = 2
const MAX_SAVE_PROFILES: int = 3
const SAVE_INDENT: String = ""

enum LoadError {
	NONE = 0,
	FILE_NOT_FOUND = 1,
	FILE_READ_ERROR = 2,
	JSON_PARSE_ERROR = 3,
	SCHEMA_VERSION_UNSUPPORTED = 4,
	INVALID_INDEX = 5
}

var _last_load_error: LoadError = LoadError.NONE


func _ready() -> void:
	_recover_tmp_files()


func get_save_path(index: int) -> String:
	return "user://save_profile_%d.json" % index


func get_tmp_path(index: int) -> String:
	return "user://save_profile_%d.tmp" % index


func profile_exists(index: int) -> bool:
	if not _is_valid_index(index):
		return false
	return FileAccess.file_exists(get_save_path(index))


func get_last_load_error() -> LoadError:
	return _last_load_error


func load_profile(index: int) -> Dictionary:
	_last_load_error = LoadError.NONE

	if not _is_valid_index(index):
		_last_load_error = LoadError.INVALID_INDEX
		return {}

	var path: String = get_save_path(index)
	if not FileAccess.file_exists(path):
		_last_load_error = LoadError.FILE_NOT_FOUND
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_load_error = LoadError.FILE_READ_ERROR
		return {}

	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(json_text)
	if error != OK:
		_last_load_error = LoadError.JSON_PARSE_ERROR
		return {}

	var data: Dictionary = json.data
	if not data is Dictionary:
		_last_load_error = LoadError.JSON_PARSE_ERROR
		return {}

	var schema_version: int = data.get("schema_version", 0)
	if schema_version > CURRENT_SCHEMA_VERSION:
		_last_load_error = LoadError.SCHEMA_VERSION_UNSUPPORTED
		return {}

	if schema_version < CURRENT_SCHEMA_VERSION:
		var migrated: Dictionary = _migrate_to_v2(data)
		flush_profile(index, migrated)  # persist migrated (failure = push_error only)
		return migrated

	return data


func flush_profile(index: int, data: Dictionary) -> bool:
	if not _is_valid_index(index):
		push_error("SaveSystem: invalid profile index %d" % index)
		return false

	var tmp_path: String = get_tmp_path(index)
	var final_path: String = get_save_path(index)

	# ① deep copy
	var save_data: Dictionary = data.duplicate(true)

	# ② stamp schema version
	save_data["schema_version"] = CURRENT_SCHEMA_VERSION

	# ③ stamp UTC timestamp
	save_data["last_saved_timestamp"] = Time.get_datetime_string_from_system(true) + "Z"

	# ④ serialize to JSON
	var json_text: String = JSON.stringify(save_data, SAVE_INDENT)

	# ⑤ write to .tmp
	var fh: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if fh == null:
		_cleanup_tmp(tmp_path)
		push_error("SaveSystem: failed to open %s for writing" % tmp_path)
		return false

	var ok: bool = fh.store_string(json_text)  # returns bool (Godot 4.4+)
	fh.close()
	if not ok:
		_cleanup_tmp(tmp_path)
		push_error("SaveSystem: store_string failed for %s" % tmp_path)
		return false

	# ⑥ rename .tmp → .json (atomic)
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		_cleanup_tmp(tmp_path)
		push_error("SaveSystem: failed to open user:// directory")
		return false

	var err: Error = dir.rename(tmp_path, final_path)  # Error.OK = 0 is falsy
	if err != OK:
		_cleanup_tmp(tmp_path)
		push_error("SaveSystem: rename failed (%s → %s): %s" % [tmp_path, final_path, error_string(err)])
		return false

	return true


func delete_profile(index: int) -> bool:
	if not _is_valid_index(index):
		push_error("SaveSystem: invalid profile index %d" % index)
		return false

	var path: String = get_save_path(index)
	var tmp_path: String = get_tmp_path(index)

	# Delete .json if exists
	if FileAccess.file_exists(path):
		var dir: DirAccess = DirAccess.open("user://")
		if dir == null:
			push_error("SaveSystem: failed to open user:// for delete")
			return false
		var err: Error = dir.remove(path)
		if err != OK:
			push_error("SaveSystem: failed to delete %s: %s" % [path, error_string(err)])
			return false

	# Delete .tmp if exists (idempotent)
	_cleanup_tmp(tmp_path)

	return true


func _recover_tmp_files() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("SaveSystem: cannot open user:// for .tmp recovery")
		return

	for index in range(MAX_SAVE_PROFILES):
		var tmp_path: String = get_tmp_path(index)
		var json_path: String = get_save_path(index)

		if not FileAccess.file_exists(tmp_path):
			continue

		if not FileAccess.file_exists(json_path):
			# .tmp is the only copy — recover it
			var err: Error = dir.rename(tmp_path, json_path)
			if err != OK:
				push_error("SaveSystem: .tmp recovery failed for index %d: %s" % [index, error_string(err)])
			else:
				print("SaveSystem: recovered .tmp for profile %d" % index)
		else:
			# Both exist — .tmp is stale from successful prior rename
			_cleanup_tmp(tmp_path)


func _cleanup_tmp(tmp_path: String) -> void:
	if not FileAccess.file_exists(tmp_path):
		return
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		dir.remove(tmp_path)


func _is_valid_index(index: int) -> bool:
	return index >= 0 and index < MAX_SAVE_PROFILES


func _migrate_to_v2(old_data: Dictionary) -> Dictionary:
	## Additive-only migration: never delete existing fields.
	## Idempotent: running twice produces identical output.
	var migrated: Dictionary = old_data.duplicate(true)

	# Ensure v2 fields exist with defaults
	if not migrated.has("first_star_at"):
		migrated["first_star_at"] = null

	if not migrated.has("recording_paths"):
		# Check for v1 singular field
		if migrated.has("recording_path"):
			var singular: String = migrated["recording_path"]
			migrated["recording_paths"] = [singular] if singular != "" else []
			migrated.erase("recording_path")
		else:
			migrated["recording_paths"] = []

	if not migrated.has("parent_map_hint_dismissed"):
		migrated["parent_map_hint_dismissed"] = false

	migrated["schema_version"] = CURRENT_SCHEMA_VERSION
	return migrated
