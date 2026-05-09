extends GutTest
## SaveSystem unit tests — ADR-0004 validation.
## Covers: load/flush/delete, .tmp recovery, schema migration, edge cases.

var _save_system: SaveSystem


func before_each() -> void:
	_save_system = SaveSystem.new()
	add_child(_save_system)
	# Clean up any leftover test files
	for i in range(SaveSystem.MAX_SAVE_PROFILES):
		_save_system.delete_profile(i)


func after_each() -> void:
	# Clean up test files
	for i in range(SaveSystem.MAX_SAVE_PROFILES):
		_save_system.delete_profile(i)
		var tmp_path: String = _save_system.get_tmp_path(i)
		if FileAccess.file_exists(tmp_path):
			var dir: DirAccess = DirAccess.open("user://")
			if dir:
				dir.remove(tmp_path)
	_save_system.queue_free()


# ── Basic Operations ──

func test_flush_and_load_basic() -> void:
	var data: Dictionary = {"player_name": "test_child", "times_played": 3}
	var flushed: bool = _save_system.flush_profile(0, data)
	assert_true(flushed, "flush_profile should return true")

	var loaded: Dictionary = _save_system.load_profile(0)
	assert_eq(loaded["player_name"], "test_child", "player_name should match")
	assert_eq(loaded["times_played"], 3, "times_played should match")
	assert_eq(loaded["schema_version"], SaveSystem.CURRENT_SCHEMA_VERSION, "schema_version should be current")


func test_flush_stamps_timestamp() -> void:
	var data: Dictionary = {"test": true}
	_save_system.flush_profile(0, data)

	var loaded: Dictionary = _save_system.load_profile(0)
	assert_true(loaded.has("last_saved_timestamp"), "should have timestamp")
	assert_true(loaded["last_saved_timestamp"].ends_with("Z"), "timestamp should end with Z")


func test_flush_deep_copies_data() -> void:
	var nested: Dictionary = {"inner": {"value": 42}}
	_save_system.flush_profile(0, nested)

	# Modify original — should not affect saved data
	nested["inner"]["value"] = 99

	var loaded: Dictionary = _save_system.load_profile(0)
	assert_eq(loaded["inner"]["value"], 42, "saved data should be independent of original")


func test_profile_exists() -> void:
	assert_false(_save_system.profile_exists(0), "profile should not exist initially")

	_save_system.flush_profile(0, {"test": true})
	assert_true(_save_system.profile_exists(0), "profile should exist after flush")


func test_delete_profile() -> void:
	_save_system.flush_profile(0, {"test": true})
	assert_true(_save_system.profile_exists(0), "profile should exist")

	var deleted: bool = _save_system.delete_profile(0)
	assert_true(deleted, "delete should return true")
	assert_false(_save_system.profile_exists(0), "profile should not exist after delete")


func test_delete_idempotent() -> void:
	# Deleting non-existent profile should succeed
	var deleted: bool = _save_system.delete_profile(0)
	assert_true(deleted, "delete of non-existent profile should return true")


func test_get_save_path() -> void:
	assert_eq(_save_system.get_save_path(0), "user://save_profile_0.json")
	assert_eq(_save_system.get_save_path(2), "user://save_profile_2.json")


# ── Multiple Profiles ──

func test_multiple_profiles_independent() -> void:
	_save_system.flush_profile(0, {"name": "child_A"})
	_save_system.flush_profile(1, {"name": "child_B"})

	var loaded_0: Dictionary = _save_system.load_profile(0)
	var loaded_1: Dictionary = _save_system.load_profile(1)

	assert_eq(loaded_0["name"], "child_A", "profile 0 data should be independent")
	assert_eq(loaded_1["name"], "child_B", "profile 1 data should be independent")


# ── Edge Cases ──

func test_load_invalid_index_negative() -> void:
	var loaded: Dictionary = _save_system.load_profile(-1)
	assert_true(loaded.is_empty(), "invalid index should return empty dict")
	assert_eq(_save_system.get_last_load_error(), SaveSystem.LoadError.INVALID_INDEX)


func test_load_invalid_index_out_of_range() -> void:
	var loaded: Dictionary = _save_system.load_profile(99)
	assert_true(loaded.is_empty(), "out of range index should return empty dict")
	assert_eq(_save_system.get_last_load_error(), SaveSystem.LoadError.INVALID_INDEX)


func test_load_nonexistent_profile() -> void:
	var loaded: Dictionary = _save_system.load_profile(0)
	assert_true(loaded.is_empty(), "non-existent profile should return empty dict")
	assert_eq(_save_system.get_last_load_error(), SaveSystem.LoadError.FILE_NOT_FOUND)


func test_flush_invalid_index() -> void:
	var flushed: bool = _save_system.flush_profile(-1, {"test": true})
	assert_false(flushed, "flush with invalid index should return false")


# ── Schema Migration ──

func test_migration_v1_to_v2_adds_fields() -> void:
	# Simulate a v1 save file (write raw JSON bypassing flush)
	var raw_v1: Dictionary = {
		"schema_version": 1,
		"player_name": "legacy_child",
		"recording_path": "user://recordings/child_001.wav"
	}
	_write_raw_json(0, raw_v1)

	var loaded: Dictionary = _save_system.load_profile(0)
	assert_eq(loaded["schema_version"], SaveSystem.CURRENT_SCHEMA_VERSION, "should be migrated to v2")
	assert_eq(loaded["player_name"], "legacy_child", "existing data preserved")
	assert_true(loaded.has("first_star_at"), "v2 field first_star_at added")
	assert_true(loaded.has("recording_paths"), "v2 field recording_paths added")
	assert_true(loaded.has("parent_map_hint_dismissed"), "v2 field parent_map_hint_dismissed added")


func test_migration_converts_singular_recording_path() -> void:
	var raw_v1: Dictionary = {
		"schema_version": 1,
		"recording_path": "user://recordings/test.wav"
	}
	_write_raw_json(0, raw_v1)

	var loaded: Dictionary = _save_system.load_profile(0)
	assert_eq(loaded["recording_paths"], ["user://recordings/test.wav"], "singular path should be wrapped in array")


func test_migration_empty_recording_path() -> void:
	var raw_v1: Dictionary = {
		"schema_version": 1,
		"recording_path": ""
	}
	_write_raw_json(0, raw_v1)

	var loaded: Dictionary = _save_system.load_profile(0)
	assert_eq(loaded["recording_paths"], [], "empty singular path should become empty array")


func test_migration_idempotent() -> void:
	var raw_v1: Dictionary = {
		"schema_version": 1,
		"player_name": "test",
		"recording_path": "test.wav"
	}
	_write_raw_json(0, raw_v1)

	# Load twice
	var first_load: Dictionary = _save_system.load_profile(0)
	var second_load: Dictionary = _save_system.load_profile(0)

	assert_eq(first_load.hash(), second_load.hash(), "two consecutive loads should produce identical output")


func test_downgrade_protection() -> void:
	var future_data: Dictionary = {
		"schema_version": 99,
		"data": "from_future"
	}
	_write_raw_json(0, future_data)

	var loaded: Dictionary = _save_system.load_profile(0)
	assert_true(loaded.is_empty(), "future schema version should return empty dict")
	assert_eq(_save_system.get_last_load_error(), SaveSystem.LoadError.SCHEMA_VERSION_UNSUPPORTED)


# ── .tmp Recovery ──

func test_tmp_recovery_tmp_only() -> void:
	# Simulate: .tmp exists, .json does not
	var tmp_path: String = _save_system.get_tmp_path(0)
	var data: Dictionary = {"schema_version": 2, "recovered": true}
	var json_text: String = JSON.stringify(data)
	var fh: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	fh.store_string(json_text)
	fh.close()

	assert_true(FileAccess.file_exists(tmp_path), ".tmp should exist")
	assert_false(FileAccess.file_exists(_save_system.get_save_path(0)), ".json should not exist")

	# Trigger recovery
	_save_system._recover_tmp_files()

	assert_true(FileAccess.file_exists(_save_system.get_save_path(0)), ".json should exist after recovery")
	assert_false(FileAccess.file_exists(tmp_path), ".tmp should be removed after recovery")


func test_tmp_recovery_both_exist() -> void:
	# Simulate: both .tmp and .json exist (stale .tmp)
	_save_system.flush_profile(0, {"valid": true})

	var tmp_path: String = _save_system.get_tmp_path(0)
	var stale_data: Dictionary = {"stale": true}
	var fh: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(stale_data))
	fh.close()

	assert_true(FileAccess.file_exists(tmp_path), ".tmp should exist")

	# Trigger recovery
	_save_system._recover_tmp_files()

	# .json should be unchanged, .tmp should be deleted
	var loaded: Dictionary = _save_system.load_profile(0)
	assert_true(loaded["valid"], ".json should contain original valid data")
	assert_false(FileAccess.file_exists(tmp_path), "stale .tmp should be removed")


# ── Helpers ──

func _write_raw_json(index: int, data: Dictionary) -> void:
	## Write raw JSON directly (bypassing flush's schema stamping) for migration tests.
	var path: String = _save_system.get_save_path(index)
	var fh: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(data))
	fh.close()
