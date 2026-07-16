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
		return _failure("Не удалось открыть временный файл сохранения.")

	file.store_string(JSON.stringify(snapshot, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_exists(_temp_path)
		return _failure("Не удалось полностью записать временное сохранение.")

	var verification: Dictionary = _read_path(_temp_path)
	if not bool(verification.get("success", false)):
		_remove_if_exists(_temp_path)
		return _failure("Временное сохранение не прошло проверку JSON.")

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
		backup["primary_error"] = String(primary.get("message", "Основное сохранение недоступно."))
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
			return _failure("Не удалось подготовить резервную копию сохранения.")

		var backup_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(_save_path),
			ProjectSettings.globalize_path(_backup_path)
		)
		if backup_error != OK:
			return _failure("Не удалось создать резервную копию сохранения.")

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
	return _failure("Не удалось заменить основной файл сохранения.")


func _read_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("Файл сохранения ещё не создан.", true)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось прочитать файл сохранения.")
	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return _failure(
			"Сохранение повреждено: ошибка JSON в строке %d." % json.get_error_line()
		)
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("Сохранение повреждено: ожидался объект JSON.")
	return {
		"success": true,
		"state": (parsed as Dictionary).duplicate(true),
		"path": path,
	}


func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _failure(message: String, missing: bool = false) -> Dictionary:
	return {
		"success": false,
		"message": message,
		"missing": missing,
	}
