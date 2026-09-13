class_name MechanicsLab
extends Node

const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const NpcWorkRequest := preload("res://src/simulation/npc_work_request.gd")
const FIRST_NEIGHBOR_ID: String = "core:first_neighbor"

@onready var _dev_ui: CanvasLayer = $DevUi as CanvasLayer
@onready var _construction_cursor: ConstructionCursor = (
	$ConstructionCursor as ConstructionCursor
)
@onready var _world: FirstNightWorld = $Game/World as FirstNightWorld

var _build_mode_button: Button
var _request_help_button: Button
var _scenario_select: OptionButton
var _description_label: Label
var _status_label: Label
var _active_scenario_id: StringName = Scenarios.FRESH_START
var _last_message: String = ""
var _selected_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	if not OS.is_debug_build():
		push_error("The mechanics lab can only run in debug builds.")
		get_tree().quit(1)
		return
	if not Session.set_mechanics_lab_active(true):
		get_tree().quit(1)
		return

	_build_ui()
	Session.state_changed.connect(_refresh_status)
	Session.state_reloaded.connect(_refresh_status)
	Session.time_changed.connect(_refresh_status)
	Session.pause_changed.connect(_on_pause_changed)
	Session.message_emitted.connect(_on_session_message)
	_world.selection_changed.connect(_on_world_selection_changed)
	_load_scenario(_scenario_from_command_line())


func _exit_tree() -> void:
	if OS.is_debug_build():
		Session.set_mechanics_lab_active(false)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dev_ui.add_child(root)

	var panel := ColorRect.new()
	panel.position = Vector2(394.0, 68.0)
	panel.size = Vector2(238.0, 288.0)
	panel.color = Color(0.055, 0.065, 0.06, 0.94)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)

	var title := _make_label(panel, Vector2(8.0, 4.0), Vector2(222.0, 18.0), 13)
	title.text = "ЛАБОРАТОРИЯ МЕХАНИК"

	_scenario_select = OptionButton.new()
	_scenario_select.position = Vector2(8.0, 24.0)
	_scenario_select.size = Vector2(222.0, 25.0)
	_scenario_select.add_theme_font_size_override("font_size", 11)
	panel.add_child(_scenario_select)
	for definition: Dictionary in Scenarios.definitions():
		_scenario_select.add_item(String(definition.get("label", "Сценарий")))
		var index: int = _scenario_select.item_count - 1
		_scenario_select.set_item_metadata(index, String(definition.get("id", "")))
	_scenario_select.item_selected.connect(_on_scenario_selected)

	_description_label = _make_label(
		panel,
		Vector2(8.0, 51.0),
		Vector2(222.0, 28.0),
		9
	)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var add_ten := _make_button(panel, "+10 мин", Vector2(8.0, 82.0), Vector2(62.0, 24.0))
	add_ten.pressed.connect(_advance_time.bind(10))
	var add_hour := _make_button(panel, "+1 час", Vector2(74.0, 82.0), Vector2(62.0, 24.0))
	add_hour.pressed.connect(_advance_time.bind(60))
	var to_evening := _make_button(panel, "До 18:00", Vector2(140.0, 82.0), Vector2(90.0, 24.0))
	to_evening.pressed.connect(_advance_to_evening)

	var reset := _make_button(panel, "Сбросить сценарий", Vector2(8.0, 110.0), Vector2(222.0, 24.0))
	reset.pressed.connect(_reset_scenario)

	_build_mode_button = _make_button(
		panel,
		"Строительство: ВЫКЛ",
		Vector2(8.0, 137.0),
		Vector2(222.0, 24.0)
	)
	_build_mode_button.toggle_mode = true
	_build_mode_button.toggled.connect(_on_build_mode_toggled)

	_request_help_button = _make_button(
		panel,
		"Попросить Миру строить",
		Vector2(8.0, 165.0),
		Vector2(222.0, 24.0)
	)
	_request_help_button.pressed.connect(_request_mira_construction_help)

	_status_label = _make_label(
		panel,
		Vector2(8.0, 193.0),
		Vector2(222.0, 90.0),
		9
	)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _on_build_mode_toggled(active: bool) -> void:
	_construction_cursor.set_build_mode_active(active)
	_build_mode_button.text = (
		"Строительство: ВКЛ"
		if active
		else "Строительство: ВЫКЛ"
	)


func _on_world_selection_changed(selection: Dictionary) -> void:
	if String(selection.get("kind", "")) == "cell":
		_selected_cell = Vector2i(
			int(selection.get("x", -1)),
			int(selection.get("y", -1))
		)
	else:
		_selected_cell = Vector2i(-1, -1)
	_refresh_status()


func _request_mira_construction_help() -> void:
	if _selected_cell.x < 0 or _selected_cell.y < 0:
		Session.notify_player_key("npc.work_request.prompt.select_blueprint")
		return
	var command: Dictionary = NpcWorkRequest.request_construction_help(
		FIRST_NEIGHBOR_ID,
		_selected_cell
	)
	var result: Dictionary = Session.execute_npc_work_request(command)
	print("WORK REQUEST RESULT: ", JSON.stringify(result))
	print(
		"MIRA COMMITMENT: ",
		JSON.stringify(Session.get_npc_work_commitment(FIRST_NEIGHBOR_ID))
	)


func _load_scenario(scenario_id: StringName) -> void:
	var result: Dictionary = Scenarios.build(scenario_id)
	if not bool(result.get("success", false)):
		Session.notify_player(String(result.get("message", "Сценарий не загружен.")))
		return

	var definition: Dictionary = result.get("definition", {}) as Dictionary
	var label: String = String(definition.get("label", scenario_id))
	var state: Dictionary = result.get("state", {}) as Dictionary
	if not Session.apply_debug_state(state, label, true):
		return
	_active_scenario_id = scenario_id
	_description_label.text = String(definition.get("description", ""))
	_select_scenario(scenario_id)
	_refresh_status()
	print(
		"LAB_READY scenario=%s day=%d time=%s" % [
			scenario_id,
			Session.get_day(),
			Session.get_time_text(),
		]
	)


func _scenario_from_command_line() -> StringName:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--lab-scenario="):
			var requested := StringName(argument.trim_prefix("--lab-scenario="))
			if not Scenarios.get_definition(requested).is_empty():
				return requested
			push_warning("Unknown mechanics lab scenario: %s" % requested)
	return Scenarios.FRESH_START


func _select_scenario(scenario_id: StringName) -> void:
	for index: int in range(_scenario_select.item_count):
		if StringName(_scenario_select.get_item_metadata(index)) == scenario_id:
			_scenario_select.select(index)
			return


func _on_scenario_selected(index: int) -> void:
	_load_scenario(StringName(_scenario_select.get_item_metadata(index)))


func _reset_scenario() -> void:
	_load_scenario(_active_scenario_id)


func _advance_time(amount: int) -> void:
	if not Session.advance_debug_minutes(amount):
		Session.notify_player("Время уже достигло предела текущего среза.")


func _advance_to_evening() -> void:
	var target_minute: int = 18 * 60
	var amount: int = target_minute - Session.get_minute_of_day()
	if amount <= 0:
		Session.notify_player("В этом дне уже наступило 18:00.", true)
		return
	_advance_time(amount)


func _on_pause_changed(_is_paused: bool) -> void:
	_refresh_status()


func _on_session_message(message: String, _success: bool) -> void:
	_last_message = message
	_refresh_status()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var state: Dictionary = Session.get_state()
	var npcs: Dictionary = state.get("npcs", {}) as Dictionary
	var mira: Dictionary = npcs.get(FIRST_NEIGHBOR_ID, {}) as Dictionary
	var mira_status: String = "скрыта"
	if bool(mira.get("active", false)):
		mira_status = "знакома" if bool(mira.get("known", false)) else "неизвестна"
	var player: Vector2 = Session.get_player_position()
	var mira_position: Vector2 = Session.get_npc_position(FIRST_NEIGHBOR_ID, Vector2.ZERO)
	var mira_target: Vector2i = Session.get_npc_target_cell(FIRST_NEIGHBOR_ID)
	var mira_needs: Dictionary = Session.get_npc_needs(FIRST_NEIGHBOR_ID)
	var mira_activity: String = Session.get_npc_activity_id(FIRST_NEIGHBOR_ID).trim_prefix("core:")
	var commitment: Dictionary = Session.get_npc_work_commitment(FIRST_NEIGHBOR_ID)
	var memories: Array = Session.get_npc_memories(FIRST_NEIGHBOR_ID)
	var relationship: Dictionary = Session.get_npc_relationship_to_player(
		FIRST_NEIGHBOR_ID
	)
	var commitment_text: String = "нет"
	if not commitment.is_empty():
		var target_cell: Array = commitment.get("target_cell", []) as Array
		commitment_text = "0/%d" % int(commitment.get("required_minutes", 0))
		for blueprint_value: Variant in Session.get_blueprints():
			if typeof(blueprint_value) != TYPE_DICTIONARY:
				continue
			var blueprint: Dictionary = blueprint_value as Dictionary
			if blueprint.get("cell", []) != target_cell:
				continue
			commitment_text = "%d/%d" % [
				int(blueprint.get("work_progress_minutes", 0)),
				int(blueprint.get("required_work_minutes", 0)),
			]
			break
	var selected_text: String = (
		"%d,%d" % [_selected_cell.x, _selected_cell.y]
		if _selected_cell.x >= 0 and _selected_cell.y >= 0
		else "—"
	)
	var event_text: String = _last_message if not _last_message.is_empty() else "Событие: —"
	if event_text.length() > 54:
		event_text = event_text.left(51) + "..."
	_status_label.text = (
		"День %d · %s · %s\n"
		+ "Игрок %.0f, %.0f · Мира %s\n"
		+ "%s · голод %.0f · силы %.0f · еда %d\n"
		+ "Мира %.0f, %.0f → %d, %d\n"
		+ "Клетка %s · стройка %s\n"
		+ "Память %d · Д %.0f · Т %.0f · У %.0f\n%s"
	) % [
		Session.get_day(),
		Session.get_time_text(),
		"ПАУЗА" if Session.is_paused() else "ИДЁТ",
		player.x,
		player.y,
		mira_status,
		mira_activity,
		float(mira_needs.get("hunger", 0.0)),
		float(mira_needs.get("energy", 0.0)),
		Session.get_npc_personal_food(FIRST_NEIGHBOR_ID),
		mira_position.x,
		mira_position.y,
		mira_target.x,
		mira_target.y,
		selected_text,
		commitment_text,
		memories.size(),
		float(relationship.get("trust", 0.0)),
		float(relationship.get("warmth", 0.0)),
		float(relationship.get("respect", 0.0)),
		event_text,
	]


func _make_label(
	parent: Node,
	position: Vector2,
	size: Vector2,
	font_size: int
) -> Label:
	var label := Label.new()
	label.position = position
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eee7d5"))
	parent.add_child(label)
	return label


func _make_button(
	parent: Node,
	text: String,
	position: Vector2,
	size: Vector2
) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position
	button.size = size
	button.add_theme_font_size_override("font_size", 10)
	parent.add_child(button)
	return button


func _on_construction_cursor_cell_selected(cell: Vector2i) -> void:
	var command: Dictionary = ConstructionCommand.place_wall_blueprint(cell)
	var result: Dictionary = Session.execute_construction_command(command)

	print("BUILD RESULT: ", JSON.stringify(result))
	print("BLUEPRINTS IN STATE: ", Session.get_blueprints().size())


func _on_construction_cursor_cell_cancel_requested(cell: Vector2i) -> void:
	var command: Dictionary = ConstructionCommand.cancel_blueprint(cell)
	var result: Dictionary = Session.execute_construction_command(command)

	print("CANCEL RESULT: ", JSON.stringify(result))
	print("BLUEPRINTS IN STATE: ", Session.get_blueprints().size())


func _on_construction_cursor_cell_completion_requested(cell: Vector2i) -> void:
	var command: Dictionary = ConstructionCommand.complete_blueprint(cell)
	var result: Dictionary = Session.execute_construction_command(command)

	print("COMPLETE RESULT: ", JSON.stringify(result))
	print("BLUEPRINTS IN STATE: ", Session.get_blueprints().size())
	print("STRUCTURES IN STATE: ", Session.get_structures().size())
