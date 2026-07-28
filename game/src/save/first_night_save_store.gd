class_name FirstNightSaveStore
extends RefCounted

var _save_path: String
var _temp_path: String
var _backup_path: String


func _init(save_path: String) -> void:
	_save_path = save_path
	_temp_path = save_path + ".tmp"
	_backup_path = save_path + ".bak"


func write_state(snapshot: Dictionary) -> Dictionary:
	var file: FileAccess = FileAccess.open(_temp_path, FileAccess.WRITE)
	if file == null:
		return _failure("save.error.temp_open")

	file.store_string(JSON.stringify(snapshot, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_exists(_temp_path)
		return _failure("save.error.temp_write")

	var verification: Dictionary = _read_path(_temp_path)
	if not bool(verification.get("success", false)):
		_remove_if_exists(_temp_path)
		return _failure("save.error.temp_verify_json")

	var replace_result: Dictionary = _replace_main_file()
	if not bool(replace_result.get("success", false)):
		_remove_if_exists(_temp_path)
		return replace_result
	return {
		"success": true,
		"path": _save_path,
	}


func read_state() -> Dictionary:
	var primary: Dictionary = _read_path(_save_path)
	if bool(primary.get("success", false)):
		primary["recovered_from_backup"] = false
		return primary

	var backup: Dictionary = read_backup_state()
	if bool(backup.get("success", false)):
		backup["primary_error_key"] = String(
			primary.get("message_key", "save.error.primary_unavailable")
		)
		backup["primary_error_args"] = (
			primary.get("message_args", {}) as Dictionary
		).duplicate(true)
		return backup
	return primary


func read_backup_state() -> Dictionary:
	var backup: Dictionary = _read_path(_backup_path)
	if bool(backup.get("success", false)):
		backup["recovered_from_backup"] = true
	return backup


func _replace_main_file() -> Dictionary:
	var save_exists: bool = FileAccess.file_exists(_save_path)
	if save_exists:
		var remove_backup_error: Error = _remove_if_exists(_backup_path)
		if remove_backup_error != OK:
			return _failure("save.error.backup_prepare")

		var backup_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(_save_path),
			ProjectSettings.globalize_path(_backup_path)
		)
		if backup_error != OK:
			return _failure("save.error.backup_create")

	var replace_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(_temp_path),
		ProjectSettings.globalize_path(_save_path)
	)
	if replace_error == OK:
		return {"success": true}

	if save_exists:
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(_backup_path),
			ProjectSettings.globalize_path(_save_path)
		)
	return _failure("save.error.replace_primary")


func _read_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("save.error.not_found", {}, true)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("save.error.read_failed")
	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return _failure(
			"save.error.json_line",
			{"line": json.get_error_line()}
		)
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("save.error.expected_object")
	return {
		"success": true,
		"state": (parsed as Dictionary).duplicate(true),
		"path": path,
	}


func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _failure(
	message_key: String,
	message_args: Dictionary = {},
	missing: bool = false
) -> Dictionary:
	return {
		"success": false,
		"message_key": message_key,
		"message_args": message_args.duplicate(true),
		"missing": missing,
	}
