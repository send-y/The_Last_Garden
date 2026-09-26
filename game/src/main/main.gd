extends Node2D
const ConstructionCommand := preload(
	"res://src/construction/construction_command.gd"
)
const CraftingCommand := preload(
	"res://src/crafting/crafting_command.gd"
)
const Content := preload("res://src/content/first_night_content.gd")
const SimulationRules := preload("res://src/simulation/first_night_simulation.gd")
const PLAYER_WORK_MINUTES_PER_SECOND: float = (
	SimulationRules.GAME_MINUTES_PER_SECOND
)
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const PLAYER_ACTOR_ID: String = "core:player"

var _active_resource_id: String = ""
var _active_build_cell: Vector2i = INVALID_CELL
var _active_crafting_cell: Vector2i = INVALID_CELL
var _selected_building_id: String = ConstructionCommand.WOOD_WALL_ID
var _work_minute_accumulator: float = 0.0
var _work_command_in_flight: bool = false

@onready var _player: PlayerController = $Player as PlayerController
@onready var _world: FirstNightWorld = $World as FirstNightWorld
@onready var _hud: FirstNightHud = $Hud/HudRoot as FirstNightHud
@onready var _dusk_overlay: ColorRect = $DuskOverlay/ColorRect as ColorRect
@onready var _construction_cursor: ConstructionCursor = (
	$ConstructionCursor as ConstructionCursor
)


func _ready() -> void:
	_world.selection_changed.connect(_on_world_selection_changed)
	_world.blueprint_interaction_requested.connect(_on_blueprint_interaction_requested)
	_world.resource_interaction_requested.connect(_on_resource_interaction_requested)
	_world.structure_interaction_requested.connect(_on_structure_interaction_requested)
	_world.storage_interaction_requested.connect(_on_storage_interaction_requested)
	_hud.build_mode_toggled.connect(_on_build_mode_toggled)
	_hud.building_selected.connect(_on_building_selected)
	_hud.crafting_recipe_requested.connect(_on_crafting_recipe_requested)
	_construction_cursor.cell_selected.connect(
		_on_construction_cell_selected
	)
	_construction_cursor.cell_cancel_requested.connect(
		_on_construction_cell_cancel_requested
	)
	_construction_cursor.storage_area_selected.connect(_on_storage_area_selected)
	_construction_cursor.storage_zone_cancel_requested.connect(_on_storage_zone_cancel_requested)
	Session.state_reloaded.connect(_player.apply_loaded_position)
	Session.state_reloaded.connect(_on_session_state_reloaded)
	Session.time_changed.connect(_update_dusk_overlay)
	_update_dusk_overlay()


func _process(delta: float) -> void:
	if not _active_resource_id.is_empty():
		_process_player_resource_work(delta)
		return
	if _active_crafting_cell != INVALID_CELL:
		_process_player_crafting(delta)
		return
	if _active_build_cell == INVALID_CELL:
		return
	if not Input.is_action_pressed(&"interact"):
		_stop_player_construction(true)
		return
	if Session.is_paused():
		return
	var movement: Vector2 = Input.get_vector(
		&"move_left",
		&"move_right",
		&"move_up",
		&"move_down"
	)
	if movement != Vector2.ZERO:
		_stop_player_construction(true)
		return
	var target_position := Content.cell_center(
		_active_build_cell.x,
		_active_build_cell.y
	)
	if _player.global_position.distance_to(target_position) > Content.INTERACTION_RANGE:
		_stop_player_construction(false)
		Session.notify_player_key("construction.feedback.too_far")
		return

	_work_minute_accumulator += delta * PLAYER_WORK_MINUTES_PER_SECOND
	while _work_minute_accumulator >= 1.0:
		_work_minute_accumulator -= 1.0
		_work_command_in_flight = true
		var result: Dictionary = Session.execute_construction_command(
			ConstructionCommand.work_blueprint(_active_build_cell)
		)
		_work_command_in_flight = false
		_show_construction_result(result)
		if (
			not bool(result.get("success", false))
			or String(result.get("reason_id", "")) == "core:structure_completed"
		):
			_clear_player_construction()
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_inventory"):
		_hud.toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).physical_keycode == KEY_L
		and (event as InputEventKey).shift_pressed
		and _hud.is_marker_list_open()
	):
		_hud.toggle_marker_list()
		get_viewport().set_input_as_handled()
		return

	if _hud.is_modal_open():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (
			key_event.pressed
			and not key_event.echo
			and key_event.physical_keycode == KEY_L
		):
			if key_event.shift_pressed:
				_hud.toggle_marker_list()
			else:
				_hud.request_marker_creation()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed(&"pause_time"):
		Session.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_save"):
		Session.quick_save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_load"):
		Session.quick_load()
		get_viewport().set_input_as_handled()


func _on_construction_cell_selected(cell: Vector2i) -> void:
	var command: Dictionary = ConstructionCommand.place_blueprint(cell, _selected_building_id)
	var result: Dictionary = Session.execute_construction_command(command)
	_show_construction_result(result)

func _on_construction_cell_cancel_requested(cell: Vector2i) -> void:
	var command: Dictionary = ConstructionCommand.cancel_blueprint(cell)
	var result: Dictionary = Session.execute_construction_command(command)
	_show_construction_result(result)


func _on_storage_area_selected(from_cell: Vector2i, to_cell: Vector2i) -> void:
	_show_storage_result(Session.create_storage_zone(from_cell, to_cell))


func _on_storage_zone_cancel_requested(cell: Vector2i) -> void:
	_show_storage_result(Session.remove_storage_zone_at(cell))


func _on_blueprint_interaction_requested(
	cell: Vector2i,
	continuous_work: bool
) -> void:
	var command: Dictionary = ConstructionCommand.deliver_blueprint_materials(cell)
	var result: Dictionary = Session.execute_construction_command(command)
	if String(result.get("reason_id", "")) == "core:materials_already_delivered":
		if continuous_work:
			_start_player_construction(cell)
		else:
			Session.notify_player_key("construction.feedback.hold_to_build")
		return
	_show_construction_result(result)


func _start_player_construction(cell: Vector2i) -> void:
	_clear_player_resource_work()
	_clear_player_crafting()
	if _active_build_cell == cell:
		return
	_active_build_cell = cell
	_work_minute_accumulator = 0.0
	Session.notify_player_key("construction.feedback.work_started", {}, true)


func _stop_player_construction(show_message: bool) -> void:
	if _active_build_cell == INVALID_CELL:
		return
	_clear_player_construction()
	if show_message:
		Session.notify_player_key("construction.feedback.work_interrupted")


func _clear_player_construction() -> void:
	_active_build_cell = INVALID_CELL
	_work_minute_accumulator = 0.0


func _on_world_selection_changed(selection: Dictionary) -> void:
	_hud.set_selection(selection)
	if (
		not _active_resource_id.is_empty()
		and not _work_command_in_flight
		and String(selection.get("object_id", ""))
		!= _active_resource_id
	):
		_stop_player_resource_work(true)
	if _active_build_cell == INVALID_CELL or _work_command_in_flight:
		if _active_crafting_cell == INVALID_CELL or _work_command_in_flight:
			return
		var crafting_cell := Vector2i(
			int(selection.get("x", -1)),
			int(selection.get("y", -1))
		)
		if String(selection.get("kind", "")) != "structure" or crafting_cell != _active_crafting_cell:
			_stop_player_crafting(true)
		return
	var selected_cell := Vector2i(
		int(selection.get("x", -1)),
		int(selection.get("y", -1))
	)
	if String(selection.get("kind", "")) != "blueprint" or selected_cell != _active_build_cell:
		_stop_player_construction(true)


func _on_build_mode_toggled(active: bool) -> void:
	_construction_cursor.set_build_mode_active(active)
	_construction_cursor.set_storage_mode_active(
		active and _selected_building_id == "core:storage_zone"
	)
	if active:
		_stop_player_resource_work(true)
		_stop_player_construction(true)
		_stop_player_crafting(true)


func _on_building_selected(building_id: String) -> void:
	_selected_building_id = building_id
	_construction_cursor.set_storage_mode_active(
		_hud.is_build_mode_active() and building_id == "core:storage_zone"
	)


func _on_storage_interaction_requested(cell: Vector2i) -> void:
	_hud.open_storage(cell)


func _on_session_state_reloaded() -> void:
	_clear_player_resource_work()
	_clear_player_construction()
	_clear_player_crafting()

func _on_resource_interaction_requested(
	target_id: String,
	continuous_work: bool
) -> void:
	if not continuous_work:
		Session.notify_player_key(
			"resource.feedback.hold_to_work"
		)
		return

	_start_player_resource_work(target_id)


func _start_player_resource_work(
	target_id: String
) -> void:
	if _active_resource_id == target_id:
		return

	_clear_player_construction()
	_clear_player_crafting()
	_active_resource_id = target_id
	_work_minute_accumulator = 0.0


func _process_player_resource_work(delta: float) -> void:
	if not Input.is_action_pressed(&"interact"):
		_stop_player_resource_work(true)
		return

	if Session.is_paused():
		return

	var movement: Vector2 = Input.get_vector(
		&"move_left",
		&"move_right",
		&"move_up",
		&"move_down"
	)

	if movement != Vector2.ZERO:
		_stop_player_resource_work(true)
		return

	_work_minute_accumulator += (
		delta * PLAYER_WORK_MINUTES_PER_SECOND
	)

	while _work_minute_accumulator >= 1.0:
		_work_minute_accumulator -= 1.0
		_work_command_in_flight = true

		var result: Dictionary = (
			Session.execute_resource_work(
				PLAYER_ACTOR_ID,
				_active_resource_id
			)
		)

		_work_command_in_flight = false
		_show_resource_work_result(result)

		var completed: bool = (
			bool(result.get("success", false))
			and String(result.get("reason_id", ""))
			== "core:resource_depleted"
		)

		if completed:
			_clear_player_resource_work()
			return

		if not bool(result.get("success", false)):
			_clear_player_resource_work()
			return

func _stop_player_resource_work(
	show_message: bool
) -> void:
	if _active_resource_id.is_empty():
		return

	_clear_player_resource_work()

	if show_message:
		Session.notify_player_key(
			"resource.feedback.interrupted"
		)


func _clear_player_resource_work() -> void:
	_active_resource_id = ""
	_work_minute_accumulator = 0.0


func _on_structure_interaction_requested(
	cell: Vector2i,
	continuous_work: bool
) -> void:
	var project: Dictionary = _crafting_project_at(cell)
	if project.is_empty():
		_hud.open_crafting(cell, Session.get_crafting_recipes("core:workbench"))
		return
	if not continuous_work:
		Session.notify_player_key("crafting.feedback.hold_to_work")
		return
	_clear_player_resource_work()
	_clear_player_construction()
	_active_crafting_cell = cell
	_work_minute_accumulator = 0.0
	Session.notify_player_key("crafting.feedback.work_started", {}, true)


func _on_crafting_recipe_requested(cell: Vector2i, recipe_id: String) -> void:
	var result: Dictionary = Session.execute_crafting_command(
		CraftingCommand.start_project(cell, recipe_id)
	)
	_show_crafting_result(result)


func _process_player_crafting(delta: float) -> void:
	if not Input.is_action_pressed(&"interact"):
		_stop_player_crafting(true)
		return
	if Session.is_paused():
		return
	if Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down") != Vector2.ZERO:
		_stop_player_crafting(true)
		return
	var target_position := Content.cell_center(_active_crafting_cell.x, _active_crafting_cell.y)
	if _player.global_position.distance_to(target_position) > Content.INTERACTION_RANGE:
		_stop_player_crafting(false)
		Session.notify_player_key("crafting.feedback.too_far")
		return
	_work_minute_accumulator += delta * PLAYER_WORK_MINUTES_PER_SECOND
	while _work_minute_accumulator >= 1.0:
		_work_minute_accumulator -= 1.0
		_work_command_in_flight = true
		var result: Dictionary = Session.execute_crafting_command(
			CraftingCommand.work_project(_active_crafting_cell)
		)
		_work_command_in_flight = false
		_show_crafting_result(result)
		if not bool(result.get("success", false)) or String(result.get("reason_id", "")) == "core:crafting_completed":
			_clear_player_crafting()
			return


func _stop_player_crafting(show_message: bool) -> void:
	if _active_crafting_cell == INVALID_CELL:
		return
	_clear_player_crafting()
	if show_message:
		Session.notify_player_key("crafting.feedback.interrupted")


func _clear_player_crafting() -> void:
	_active_crafting_cell = INVALID_CELL
	_work_minute_accumulator = 0.0


func _crafting_project_at(cell: Vector2i) -> Dictionary:
	for project_value: Variant in Session.get_crafting_projects():
		if typeof(project_value) == TYPE_DICTIONARY:
			var project := project_value as Dictionary
			if project.get("cell", []) == [cell.x, cell.y]:
				return project
	return {}


func _show_crafting_result(result: Dictionary) -> void:
	var reason_id := String(result.get("reason_id", ""))
	var message_key := "crafting.feedback.invalid"
	match reason_id:
		"core:crafting_project_started":
			message_key = "crafting.feedback.project_started"
		"core:crafting_work_progressed":
			message_key = "crafting.feedback.work_progressed"
		"core:crafting_completed":
			message_key = "crafting.feedback.completed"
		"core:required_materials_missing":
			message_key = "crafting.feedback.materials_missing"
		"core:station_busy":
			message_key = "crafting.feedback.station_busy"
		"core:too_far":
			message_key = "crafting.feedback.too_far"
	Session.notify_player_key(message_key, {
		"progress": int(result.get("work_progress_minutes", 0)),
		"required": int(result.get("required_work_minutes", 0)),
	}, bool(result.get("success", false)))


func _show_resource_work_result(
	result: Dictionary
) -> void:
	var reason_id: String = String(
		result.get("reason_id", "")
	)
	var message_key: String = "resource.feedback.invalid"

	match reason_id:
		"core:resource_work_progressed":
			message_key = (
				"resource.feedback.work_progressed"
			)
		"core:resource_depleted":
			message_key = (
				"resource.feedback.completed"
				if bool(result.get("success", false))
				else "first_night.collect.empty"
			)
		"core:too_far":
			message_key = "interaction.failure.too_far"

	Session.notify_player_key(
		message_key,
		{
			"progress": int(
				result.get("work_progress_minutes", 0)
			),
			"required": int(
				result.get("required_work_minutes", 0)
			),
		},
		bool(result.get("success", false))
	)


func _show_construction_result(result: Dictionary) -> void:
	var reason_id: String = String(result.get("reason_id", ""))
	var message_key: String = "construction.feedback.invalid"

	match reason_id:
		"core:blueprint_placed":
			message_key = "construction.feedback.blueprint_placed"
		"core:blueprint_cancelled":
			message_key = "construction.feedback.blueprint_cancelled"
		"core:materials_delivered":
			message_key = (
				"construction.feedback.materials_delivered_ready"
				if bool(result.get("materials_ready", false))
				else "construction.feedback.materials_delivered"
			)
		"core:materials_already_delivered":
			message_key = "construction.feedback.materials_already_delivered"
		"core:required_materials_missing":
			message_key = "construction.feedback.required_materials_missing"
		"core:construction_work_progressed":
			message_key = "construction.feedback.work_progressed"
		"core:structure_completed":
			message_key = "construction.feedback.structure_completed"
		"core:occupied_by_actor":
			message_key = "construction.feedback.occupied_by_actor"
		"core:too_far":
			message_key = "construction.feedback.too_far"
		"core:blocked_cell":
			message_key = "construction.feedback.blocked_cell"
		"core:occupied_cell":
			message_key = "construction.feedback.occupied_cell"
		"core:missing_blueprint":
			message_key = "construction.feedback.missing_blueprint"
		"core:out_of_bounds":
			message_key = "construction.feedback.out_of_bounds"

	Session.notify_player_key(
		message_key,
		{
			"amount": int(result.get("transferred_total", 0)),
			"progress": int(result.get("work_progress_minutes", 0)),
			"required": int(result.get("required_work_minutes", 0)),
		},
		bool(result.get("success", false))
	)


func _show_storage_result(result: Dictionary) -> void:
	var message_key := String(result.get("message_key", "ui.storage.failure.invalid"))
	var message_args := result.get("message_args", {}) as Dictionary
	Session.notify_player_key(message_key, message_args, bool(result.get("success", false)))


func _update_dusk_overlay() -> void:
	var minute: int = Session.get_minute_of_day()
	var alpha: float = 0.0
	if minute >= 17 * 60:
		alpha = remap(clampf(float(minute), 17.0 * 60.0, 22.0 * 60.0), 17.0 * 60.0, 22.0 * 60.0, 0.0, 0.42)
	_dusk_overlay.color = Color(0.10, 0.13, 0.28, alpha)
