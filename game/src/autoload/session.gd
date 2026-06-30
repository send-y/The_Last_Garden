extends Node

signal state_changed
signal state_reloaded
signal time_changed
signal message_emitted(message: String, success: bool)
signal pause_changed(is_paused: bool)

const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const SAVE_PATH: String = "user://first_night_save.json"

var simulation: FirstNightSimulation
var _is_paused: bool = false


func _ready() -> void:
	_register_input_actions()
	_start_new_simulation()


func _process(delta: float) -> void:
	if _is_paused:
		return
	simulation.tick(delta)


func execute_interaction(object_id: String, kind: String) -> Dictionary:
	return simulation.execute_interaction(object_id, kind)


func get_state() -> Dictionary:
	return simulation.state


func get_inventory() -> Dictionary:
	return simulation.get_inventory()


func get_inventory_weight() -> float:
	return simulation.get_inventory_weight()


func get_max_carry_weight() -> float:
	return simulation.MAX_CARRY_WEIGHT


func get_flags() -> Dictionary:
	return simulation.get_flags()


func get_day() -> int:
	return simulation.get_day()


func get_minute_of_day() -> int:
	return simulation.get_minute_of_day()


func get_time_text() -> String:
	return simulation.get_time_text()


func get_current_objective() -> String:
	return simulation.get_current_objective()


func get_player_position() -> Vector2:
	return simulation.get_player_position()


func set_player_position(value: Vector2) -> void:
	simulation.set_player_position(value)


func is_collected(object_id: String) -> bool:
	return simulation.is_collected(object_id)


func get_object_stage(kind: String) -> int:
	return simulation.get_object_stage(kind)


func get_object_label(kind: String, fallback: String) -> String:
	return simulation.get_object_label(kind, fallback)


func should_hide_interactable(object_id: String, kind: String) -> bool:
	return simulation.should_hide_interactable(object_id, kind)


func is_paused() -> bool:
	return _is_paused


func toggle_pause() -> void:
	_is_paused = not _is_paused
	pause_changed.emit(_is_paused)
	message_emitted.emit("Время остановлено." if _is_paused else "Время снова идёт.", true)


func notify_player(message: String, success: bool = false) -> void:
	message_emitted.emit(message, success)


func save_game(show_message: bool = true) -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		message_emitted.emit("Не удалось открыть файл сохранения.", false)
		return false
	file.store_string(JSON.stringify(simulation.state, "\t"))
	file.close()
	if show_message:
		message_emitted.emit("Состояние сохранено.", true)
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		message_emitted.emit("Сохранение ещё не создано.", false)
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		message_emitted.emit("Не удалось прочитать сохранение.", false)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		message_emitted.emit("Сохранение повреждено: ожидался объект JSON.", false)
		return false

	_replace_simulation(parsed as Dictionary)
	_is_paused = false
	state_reloaded.emit()
	state_changed.emit()
	time_changed.emit()
	pause_changed.emit(false)
	message_emitted.emit("Состояние загружено.", true)
	return true


func _start_new_simulation() -> void:
	_replace_simulation(Simulation.create_new_state())


func _replace_simulation(initial_state: Dictionary) -> void:
	simulation = Simulation.new(initial_state)
	simulation.event_emitted.connect(_on_simulation_event)


func _on_simulation_event(event: Dictionary) -> void:
	var event_type: String = String(event.get("type", ""))
	if event_type == "time_changed":
		time_changed.emit()
		return

	if event_type == "command_result":
		message_emitted.emit(String(event.get("message", "")), bool(event.get("success", false)))
		if bool(event.get("changed", false)):
			state_changed.emit()
		if bool(event.get("auto_save", false)):
			save_game(false)


func _register_input_actions() -> void:
	_bind_keys(&"move_left", [KEY_A, KEY_LEFT])
	_bind_keys(&"move_right", [KEY_D, KEY_RIGHT])
	_bind_keys(&"move_up", [KEY_W, KEY_UP])
	_bind_keys(&"move_down", [KEY_S, KEY_DOWN])
	_bind_keys(&"interact", [KEY_E])
	_bind_keys(&"pause_time", [KEY_SPACE])
	_bind_keys(&"quick_save", [KEY_F5])
	_bind_keys(&"quick_load", [KEY_F9])


func _bind_keys(action: StringName, physical_keys: Array[int]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key_code: int in physical_keys:
		var input_event := InputEventKey.new()
		input_event.keycode = key_code as Key
		input_event.physical_keycode = key_code as Key
		InputMap.action_add_event(action, input_event)
