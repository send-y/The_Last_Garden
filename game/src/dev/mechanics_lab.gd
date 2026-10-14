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
@onready var _hud: FirstNightHud = $Game/Hud/HudRoot as FirstNightHud

var _build_mode_button: Button
var _request_help_button: Button
var _scenario_select: OptionButton
var _description_label: Label
var _status_label: Label
var _lab_panel: Control
var _lab_toggle_button: Button
var _active_scenario_id: StringName = Scenarios.FRESH_START
var _last_message: String = ""
var _selected_cell: Vector2i = Vector2i(-1, -1)
var _stress_participants: Array[String] = []
var _stress_overview := false
var _stress_advancing := false
var _loading_scenario := false
var _verify_structure_index := false
var _structure_verify_elapsed := 0.0

func _process(delta: float) -> void:
	# DevUi is above all game UI. Its launcher must not cover modal controls;
	# F2 remains available for explicitly opening/closing the lab.
	_lab_toggle_button.visible = not _hud.is_modal_open()
	if not _verify_structure_index: return
	_structure_verify_elapsed += delta
	if _structure_verify_elapsed < 1.0: return
	_structure_verify_elapsed = 0.0
	for error: String in Session.simulation.debug_validate_structures(): push_error(error)


func _ready() -> void:
	if not OS.is_debug_build():
		push_error("The mechanics lab can only run in debug builds.")
		get_tree().quit(1)
		return
	if not Session.set_mechanics_lab_active(true):
		get_tree().quit(1)
		return

	_verify_structure_index = "--verify-structure-index" in OS.get_cmdline_user_args()
	_build_ui()
	Session.state_changed.connect(_refresh_status)
	Session.state_reloaded.connect(_refresh_status)
	Session.time_changed.connect(_on_lab_time_changed)
	Session.pause_changed.connect(_on_pause_changed)
	Session.message_emitted.connect(_on_session_message)
	_world.selection_changed.connect(_on_world_selection_changed)
	var hud: FirstNightHud = $Game/Hud/HudRoot as FirstNightHud
	hud.npc_conversation_opened.connect(_on_npc_conversation_opened)
	get_viewport().size_changed.connect(_layout_lab_ui)
	_load_scenario(_scenario_from_command_line())


func _exit_tree() -> void:
	if OS.is_debug_build():
		Session.set_mechanics_lab_active(false)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "MechanicsLabUi"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dev_ui.add_child(root)

	var panel := ColorRect.new()
	panel.name = "MechanicsPanel"
	panel.size = Vector2(238.0, 288.0)
	panel.color = Color(0.055, 0.065, 0.06, 0.94)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	_lab_panel = panel
	panel.hide()
	_lab_toggle_button = _make_button(
		root, "Механики [F2]", Vector2.ZERO, Vector2(104.0, 24.0)
	)
	_lab_toggle_button.name = "MechanicsToggle"
	_lab_toggle_button.toggle_mode = true
	_lab_toggle_button.toggled.connect(_set_lab_panel_open)
	_layout_lab_ui()

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

	var status_scroll := ScrollContainer.new()
	status_scroll.position = Vector2(8,193)
	status_scroll.size = Vector2(222,90)
	status_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(status_scroll)
	_status_label = _make_label(status_scroll,Vector2.ZERO,Vector2(210,90),9)
	_status_label.custom_minimum_size.x = 210
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _layout_lab_ui() -> void:
	var dimensions := get_viewport().get_visible_rect().size
	_lab_toggle_button.position = Vector2(
		maxf(8.0, (dimensions.x - _lab_toggle_button.size.x) * 0.5), 8.0
	)
	_lab_panel.position = Vector2(
		maxf(8.0, dimensions.x - _lab_panel.size.x - 8.0),
		maxf(8.0, minf(40.0, dimensions.y - _lab_panel.size.y - 8.0))
	)


func _set_lab_panel_open(open: bool) -> void:
	_lab_panel.visible = open
	_lab_toggle_button.set_pressed_no_signal(open)
	_lab_toggle_button.text = "Закрыть [F2]" if open else "Механики [F2]"
	if open: _refresh_status()


func _on_npc_conversation_opened(_npc_id: String) -> void:
	_set_lab_panel_open(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_set_lab_panel_open(not _lab_panel.visible)
		get_viewport().set_input_as_handled()


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
	if not _stress_participants.is_empty():
		_set_stress_overview(not _stress_overview)
		return
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
	var stress_count := 30
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--stress-residents="):
			stress_count = argument.trim_prefix("--stress-residents=").to_int()
	var result: Dictionary = Scenarios.build(scenario_id, stress_count)
	if not bool(result.get("success", false)):
		Session.notify_player(String(result.get("message", "Сценарий не загружен.")))
		return

	var definition: Dictionary = result.get("definition", {}) as Dictionary
	var label: String = String(definition.get("label", scenario_id))
	var state: Dictionary = result.get("state", {}) as Dictionary
	# Reload emits time_changed before this lab adopts the incoming scenario.
	# Do not apply the previous population/warehouse rules to the new world.
	_loading_scenario = true
	var loaded := Session.apply_debug_state(state, label, true)
	_loading_scenario = false
	if not loaded:
		return
	Session.simulation.work_metrics.enabled = true
	_active_scenario_id = scenario_id
	_stress_participants.assign(result.get("participants", []))
	_set_stress_overview(false)
	_request_help_button.text = "Обзор поселения / игрок" if not _stress_participants.is_empty() else "Попросить Миру строить"
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


func _on_lab_time_changed() -> void:
	if _loading_scenario: return
	if not _stress_participants.is_empty():
		var changed := false
		# Keep the debug population fixed even when the normal visitor system fires.
		for npc: Dictionary in Session.simulation.state.npcs.values():
			if bool(npc.active) and not _stress_participants.has(String(npc.id)):
				Session.simulation.set_npc_active(String(npc.id),false)
				changed = true
		var mode := "production" if _active_scenario_id == Scenarios.STRESS_PRODUCTION else ("gather" if _active_scenario_id == Scenarios.STRESS_GATHER else "full")
		if Scenarios.SettlementStress.replenish(Session.simulation, mode) or changed:
			Session.state_changed.emit()
	_refresh_status()


func _set_stress_overview(enabled: bool) -> void:
	_stress_overview = enabled
	var camera: Camera2D = $Game/Player/Camera2D
	camera.top_level = enabled
	camera.position = Scenarios.FirstNightContent.cell_center(61, 74) if enabled else Vector2.ZERO
	var factor := minf(get_viewport().get_visible_rect().size.x / 3300.0, (get_viewport().get_visible_rect().size.y - 80.0) / 2800.0)
	camera.zoom = Vector2.ONE * maxf(0.07, factor) if enabled else Vector2.ONE
	camera.reset_smoothing()


func _advance_time(amount: int) -> void:
	if not _stress_participants.is_empty():
		if _stress_advancing:
			return
		_stress_advancing = true
		var advancing_simulation = Session.simulation
		var was_paused := Session.is_paused()
		Session.set_paused(true, false)
		for _minute: int in range(amount):
			if Session.simulation != advancing_simulation:
				break
			# Emit the ordinary minute signal each step, so the warehouse
			# replenishes during debug fast-forward as well as natural time.
			if not Session.advance_debug_minutes(1):
				break
			await get_tree().process_frame
		if Session.simulation == advancing_simulation:
			Session.set_paused(was_paused, false)
		_stress_advancing = false
		return
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
	if _status_label == null or _lab_panel == null or not _lab_panel.visible:
		return
	# The debug label only reads this resident; exporting the complete world
	# on every command/time event dominates the minute when many NPCs act.
	var mira: Dictionary = Session.simulation.state.npcs.get(FIRST_NEIGHBOR_ID, {})
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
	var work: Dictionary = Session.simulation.work_metrics.summary(Session.get_day())
	_status_label.text += "\nРабота/житель %.1f · простой %.0f%%\nСмен/час %.1f · наблюдений %d мин" % [float(work.work_per_resident),float(work.idle_percent),float(work.changes_per_hour),int(work.sample_minutes)]


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
