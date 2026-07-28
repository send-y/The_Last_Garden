extends Node

signal state_changed
signal state_reloaded
signal time_changed
signal message_emitted(message: String, success: bool)
signal pause_changed(is_paused: bool)

const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const SAVE_PATH: String = "user://first_night_save.json"

var simulation: FirstNightSimulation
var _is_paused: bool = false
var _mechanics_lab_active: bool = false
var _save_store := SaveStore.new(SAVE_PATH)


func _ready() -> void:
	_register_input_actions()
	_start_new_simulation()


func _process(delta: float) -> void:
	if _is_paused:
		return
	simulation.tick(delta)


func execute_interaction(target_id: String) -> Dictionary:
	return simulation.execute_interaction(target_id)


func execute_command(actor_id: String, target_id: String, action_id: String) -> Dictionary:
	return simulation.execute_command(actor_id, target_id, action_id)


func execute_construction_command(command: Dictionary) -> Dictionary:
	return simulation.execute_construction_command(command)


func get_state() -> Dictionary:
	return simulation.export_state()


func get_inventory() -> Dictionary:
	return simulation.get_inventory().duplicate(true)


func get_inventory_weight() -> float:
	return simulation.get_inventory_weight()


func get_max_carry_weight() -> float:
	return simulation.MAX_CARRY_WEIGHT


func get_flags() -> Dictionary:
	return simulation.get_flags().duplicate(true)


func get_day() -> int:
	return simulation.get_day()


func get_minute_of_day() -> int:
	return simulation.get_minute_of_day()


func get_time_text() -> String:
	return simulation.get_time_text()


func get_current_objective() -> String:
	return Localized.resolve(simulation.get_current_objective_key())


func get_player_position() -> Vector2:
	return simulation.get_player_position()


func set_player_position(value: Vector2) -> void:
	simulation.set_player_position(value)


func is_collected(object_id: String) -> bool:
	return simulation.is_collected(object_id)


func get_object_stage(kind: String) -> int:
	return simulation.get_object_stage(kind)


func get_object_label(kind: String, fallback_key: String, object_id: String = "") -> String:
	return Localized.resolve(simulation.get_object_label_key(kind, fallback_key, object_id))


func should_hide_interactable(object_id: String, kind: String) -> bool:
	return simulation.should_hide_interactable(object_id, kind)


func is_npc_visible(npc_id: String) -> bool:
	return simulation.is_npc_visible(npc_id)


func get_npc_position(npc_id: String, fallback: Vector2) -> Vector2:
	return simulation.get_npc_position(npc_id, fallback)


func get_npc_appearance(npc_id: String) -> Dictionary:
	return simulation.get_npc_appearance(npc_id)


func get_npc_activity(npc_id: String) -> String:
	return Localized.resolve(simulation.get_npc_activity_key(npc_id))


func get_npc_activity_id(npc_id: String) -> String:
	return simulation.get_npc_activity_id(npc_id)


func get_npc_needs(npc_id: String) -> Dictionary:
	return simulation.get_npc_needs(npc_id)


func get_npc_personal_food(npc_id: String) -> int:
	return simulation.get_npc_personal_food(npc_id)


func get_npc_target_cell(npc_id: String) -> Vector2i:
	return simulation.get_npc_target_cell(npc_id)


func get_npc_facing(npc_id: String) -> Vector2:
	return simulation.get_npc_facing(npc_id)


func is_npc_moving(npc_id: String) -> bool:
	return simulation.is_npc_moving(npc_id)


func set_mechanics_lab_active(active: bool) -> bool:
	if active and not OS.is_debug_build():
		push_warning("The mechanics lab is unavailable in release builds.")
		return false
	_mechanics_lab_active = active
	return true


func is_mechanics_lab_active() -> bool:
	return _mechanics_lab_active


func get_blueprints() -> Array:
	return simulation.get_blueprints()


func apply_debug_state(
	initial_state: Dictionary,
	scenario_label: String = "",
	start_paused: bool = true
) -> bool:
	if not OS.is_debug_build() or not _mechanics_lab_active:
		push_warning("Debug state replacement is unavailable in release builds.")
		return false
	var header_result: Dictionary = Simulation.validate_save_header(initial_state)
	if not bool(header_result.get("success", false)):
		_emit_player_message_key(
			String(header_result.get("message_key", "system.load.incompatible")),
			header_result.get("message_args", {}) as Dictionary,
			false
		)
		return false

	_replace_simulation(initial_state)
	_publish_reloaded_state(start_paused)
	var label_suffix: String = " «%s»" % scenario_label if not scenario_label.is_empty() else ""
	message_emitted.emit("Загружен сценарий лаборатории%s." % label_suffix, true)
	return true


func advance_debug_minutes(amount: int) -> bool:
	if not OS.is_debug_build() or not _mechanics_lab_active:
		push_warning("Debug time controls are unavailable in release builds.")
		return false
	if amount <= 0:
		return false
	return simulation.advance_minutes(amount)


func is_paused() -> bool:
	return _is_paused


func toggle_pause() -> void:
	_is_paused = not _is_paused
	pause_changed.emit(_is_paused)
	_emit_player_message_key(
		"system.pause.enabled" if _is_paused else "system.pause.disabled",
		{},
		true
	)


func notify_player(message: String, success: bool = false) -> void:
	message_emitted.emit(message, success)


func notify_player_key(
	message_key: String,
	message_args: Dictionary = {},
	success: bool = false
) -> void:
	_emit_player_message_key(message_key, message_args, success)


func save_game(show_message: bool = true) -> bool:
	if _mechanics_lab_active:
		if show_message:
			message_emitted.emit("Лаборатория не записывает обычные сохранения.", false)
		return false
	var result: Dictionary = _save_store.write_state(simulation.export_state())
	if not bool(result.get("success", false)):
		_emit_player_message_key(
			String(result.get("message_key", "system.save.failed")),
			result.get("message_args", {}) as Dictionary,
			false
		)
		return false
	if show_message:
		_emit_player_message_key("system.save.success", {}, true)
	return true


func load_game() -> bool:
	if _mechanics_lab_active:
		message_emitted.emit("Обычная загрузка отключена внутри лаборатории.", false)
		return false
	var read_result: Dictionary = _save_store.read_state()
	if not bool(read_result.get("success", false)):
		_emit_player_message_key(
			String(read_result.get("message_key", "system.load.failed")),
			read_result.get("message_args", {}) as Dictionary,
			false
		)
		return false

	var loaded_state: Dictionary = read_result.get("state", {}) as Dictionary
	var header_result: Dictionary = Simulation.validate_save_header(loaded_state)
	if (
		not bool(header_result.get("success", false))
		and String(header_result.get("code", "")) != "future_version"
		and not bool(read_result.get("recovered_from_backup", false))
	):
		var backup_result: Dictionary = _save_store.read_backup_state()
		if bool(backup_result.get("success", false)):
			var backup_state: Dictionary = backup_result.get("state", {}) as Dictionary
			var backup_header: Dictionary = Simulation.validate_save_header(backup_state)
			if bool(backup_header.get("success", false)):
				read_result = backup_result
				loaded_state = backup_state
				header_result = backup_header
	if not bool(header_result.get("success", false)):
		_emit_player_message_key(
			String(header_result.get("message_key", "system.load.incompatible")),
			header_result.get("message_args", {}) as Dictionary,
			false
		)
		return false

	_replace_simulation(loaded_state)
	_publish_reloaded_state()
	if bool(read_result.get("recovered_from_backup", false)):
		_emit_player_message_key("system.load.recovered_backup", {}, true)
	else:
		_emit_player_message_key("system.load.success", {}, true)
	return true


func _start_new_simulation() -> void:
	_replace_simulation(Simulation.create_new_state())


func _replace_simulation(initial_state: Dictionary) -> void:
	simulation = Simulation.new(initial_state)
	simulation.event_emitted.connect(_on_simulation_event)


func _publish_reloaded_state(start_paused: bool = false) -> void:
	_is_paused = start_paused
	state_reloaded.emit()
	state_changed.emit()
	time_changed.emit()
	pause_changed.emit(_is_paused)


func _on_simulation_event(event: Dictionary) -> void:
	var event_type: String = String(event.get("type", ""))
	if event_type == "time_changed":
		time_changed.emit()
		return

	if event_type == "state_changed":
		state_changed.emit()
		return

	if event_type == "command_result":
		_emit_player_message_key(
			String(event.get("message_key", "")),
			event.get("message_args", {}) as Dictionary,
			bool(event.get("success", false))
		)
		if bool(event.get("changed", false)):
			state_changed.emit()
		if bool(event.get("auto_save", false)) and not _mechanics_lab_active:
			save_game(false)


func _emit_player_message_key(
	message_key: String,
	message_args: Dictionary,
	success: bool
) -> void:
	message_emitted.emit(Localized.resolve(message_key, message_args), success)


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
