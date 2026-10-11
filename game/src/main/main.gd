extends Node2D
const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")
const ConstructionCommand := preload(
	"res://src/construction/construction_command.gd"
)
const CraftingCommand := preload(
	"res://src/crafting/crafting_command.gd"
)
const BuildingCatalogScript := preload(
	"res://src/construction/building_catalog.gd"
)
const Content := preload("res://src/content/first_night_content.gd")
const SimulationRules := preload("res://src/simulation/world_simulation.gd")
const PLAYER_WORK_MINUTES_PER_SECOND: float = (
	SimulationRules.GAME_MINUTES_PER_SECOND
)
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const PLAYER_ACTOR_ID: String = "core:player"

var _active_resource_id: String = ""
var _active_resource_tool_instance_id: String = ""
var _active_build_cell: Vector2i = INVALID_CELL
var _active_crafting_cell: Vector2i = INVALID_CELL
var _selected_building_id: String = ConstructionCommand.WOOD_WALL_ID
var _work_minute_accumulator: float = 0.0
var _work_command_in_flight: bool = false
var _building_catalog := BuildingCatalogScript.new()
var _lighting_material: ShaderMaterial

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
	_world.water_interaction_requested.connect(_on_water_interaction_requested)
	_world.farming_interaction_requested.connect(_on_farming_interaction_requested)
	_world.npc_conversation_requested.connect(_hud.open_npc_conversation)
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
	_lighting_material = ShaderMaterial.new()
	_lighting_material.shader = preload("res://src/furniture/night_lighting.gdshader")
	_dusk_overlay.material = _lighting_material
	_update_dusk_overlay()


func _process(delta: float) -> void:
	_update_light_field()
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

	_work_minute_accumulator += delta * PLAYER_WORK_MINUTES_PER_SECOND * Session.get_player_work_speed_multiplier()
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
	if event is InputEventKey:
		var number_key := event as InputEventKey
		if number_key.pressed and not number_key.echo and number_key.physical_keycode >= KEY_1 and number_key.physical_keycode <= KEY_5:
			_hud.handle_hotbar_key(number_key.physical_keycode - KEY_1)
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
		Session.save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_load"):
		Session.load_game()
		get_viewport().set_input_as_handled()


func _on_construction_cell_selected(cell: Vector2i) -> void:
	if _selected_building_id == "core:storage_room" or _selected_building_id == "core:living_room":
		_show_room_result(Session.assign_room_type(_selected_building_id, cell))
		return
	var command: Dictionary = ConstructionCommand.place_blueprint(cell, _selected_building_id)
	var result: Dictionary = Session.execute_construction_command(command)
	_show_construction_result(result)

func _on_construction_cell_cancel_requested(cell: Vector2i) -> void:
	if _selected_building_id == "core:storage_room" or _selected_building_id == "core:living_room":
		_show_room_result(Session.remove_room_at(cell))
		return
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
	if not _stand_for_work():
		return
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
	if active:
		_stop_player_resource_work(true)
		_stop_player_construction(true)
		_stop_player_crafting(true)


func _on_building_selected(building_id: String) -> void:
	_selected_building_id = building_id
	_construction_cursor.set_building_id(building_id)


func _on_storage_interaction_requested(cell: Vector2i) -> void:
	_hud.open_storage(cell)


func _on_water_interaction_requested(cell: Vector2i) -> void:
	var result := Session.fill_active_bucket(cell)
	Session.notify_player_key(
		String(result.get("message_key", "ui.bucket.failure.not_water")),
		result.get("message_args", {}) as Dictionary,
		bool(result.get("success", false))
	)


func _on_session_state_reloaded() -> void:
	_clear_player_resource_work()
	_clear_player_construction()
	_clear_player_crafting()


func _on_farming_interaction_requested(cell: Vector2i) -> void:
	_clear_player_resource_work()
	_clear_player_construction()
	_clear_player_crafting()
	if Session.get_farm_bed(cell).is_empty():
		Session.execute_farming_command({"actor_id": PLAYER_ACTOR_ID, "action_id": "till", "cell": [cell.x, cell.y]})
	else:
		_hud.open_farming(cell)

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
	var required_action := Session.get_resource_required_tool_action(target_id)
	var active_tool := Session.get_active_item_instance()
	if (
		not required_action.is_empty()
		and not Session.simulation.actor_tool_supports(PLAYER_ACTOR_ID, required_action)
	):
		Session.notify_player_key(
			_resource_tool_requirement_message(required_action)
		)
		return

	if not _stand_for_work():
		return
	_clear_player_construction()
	_clear_player_crafting()
	_active_resource_id = target_id
	_active_resource_tool_instance_id = String(
		active_tool.get("instance_id", "")
	)
	_work_minute_accumulator = 0.0


func _process_player_resource_work(delta: float) -> void:
	var required_action := Session.get_resource_required_tool_action(_active_resource_id)
	if not required_action.is_empty():
		var active_tool := Session.get_active_item_instance()
		if (
			_active_resource_tool_instance_id.is_empty()
			or String(active_tool.get("instance_id", ""))
			!= _active_resource_tool_instance_id
		):
			var interrupted_result: Dictionary = Session.execute_resource_work(
				PLAYER_ACTOR_ID,
				_active_resource_id
			)
			_show_resource_work_result(interrupted_result)
			_clear_player_resource_work()
			return

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
		delta * PLAYER_WORK_MINUTES_PER_SECOND * Session.get_player_work_speed_multiplier()
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
	_active_resource_tool_instance_id = ""
	_work_minute_accumulator = 0.0


func _on_structure_interaction_requested(
	cell: Vector2i,
	continuous_work: bool
) -> void:
	var clicked: Dictionary = Session.simulation._find_structure([cell.x,cell.y])
	if String(clicked.get("building_id","")) == "core:wood_door":
		# Holding E starts one action; repeated work never toggles a door.
		var result: Dictionary = Session.simulation.edit_world("toggle_door",cell)
		Session.notify_player_key(String(result.message_key),{},bool(result.success))
		return
	for structure: Dictionary in Session.get_structures():
		if structure.get("cell",[]) == [cell.x,cell.y] and String(structure.get("building_id","")) in ["core:chair","core:table","core:torch"]:
			_clear_player_resource_work()
			_clear_player_construction()
			_clear_player_crafting()
			if String(structure.building_id) == "core:torch":
				Session.execute_furniture_command(cell,"toggle_light")
			else:
				_hud.open_furniture(cell)
			return
		if structure.get("cell", []) == [cell.x, cell.y] and String(structure.get("building_id", "")) in ["core:bed", "core:bedroll"]:
			Session.sleep_at_place("%s@%d,%d" % [structure.building_id, cell.x, cell.y])
			return
		if structure.get("cell", []) == [cell.x, cell.y] and String(structure.get("building_id", "")) == "core:study_table":
			Session.notify_player_key("farming.study_ready", {}, true)
			return
	var project: Dictionary = _crafting_project_at(cell)
	if project.is_empty():
		_hud.open_crafting(cell, Session.get_crafting_recipes("core:workbench"))
		return
	if not continuous_work:
		Session.notify_player_key("crafting.feedback.hold_to_work")
		return
	_clear_player_resource_work()
	_clear_player_construction()
	if not _stand_for_work():
		return
	_active_crafting_cell = cell
	_work_minute_accumulator = 0.0
	Session.notify_player_key("crafting.feedback.work_started", {}, true)


func _on_crafting_recipe_requested(cell: Vector2i, recipe_id: String) -> void:
	var result: Dictionary = Session.execute_crafting_command(
		CraftingCommand.start_project(cell, recipe_id)
	)
	_show_crafting_result(result)

func _stand_for_work() -> bool:
	if Session.simulation.prepare_player_work():
		return true
	Session.notify_player_key("furniture.failure.approach")
	return false


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
	_work_minute_accumulator += delta * PLAYER_WORK_MINUTES_PER_SECOND * Session.get_player_work_speed_multiplier()
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
			var origin_data: Array = project.get("cell", []) as Array
			if origin_data.size() != 2:
				continue
			var origin := Vector2i(int(origin_data[0]), int(origin_data[1]))
			if origin == cell:
				return project
			for structure_value: Variant in Session.get_structures():
				if typeof(structure_value) != TYPE_DICTIONARY:
					continue
				var structure := structure_value as Dictionary
				if structure.get("cell", []) != [origin.x, origin.y]:
					continue
				var building_id := String(structure.get("building_id", ""))
				if String(_building_catalog.get_definition(building_id).get("station_type", "")).is_empty():
					continue
				if _building_catalog.get_footprint_cells(building_id, origin).has(cell):
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
		"core:resource_tool_not_selected":
			message_key = _resource_tool_requirement_message(
				String(result.get("required_tool_action", ""))
			)
		"core:resource_work_tool_changed":
			message_key = "resource.feedback.tool_changed"
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


func _resource_tool_requirement_message(action_id: String) -> String:
	match action_id:
		"chop":
			return "resource.feedback.axe_required"
		"mine":
			return "resource.feedback.pickaxe_required"
	return "resource.feedback.invalid"


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


func _show_room_result(result: Dictionary) -> void:
	var message_key := String(result.get("message_key", "ui.room.failure.invalid"))
	var message_args := result.get("message_args", {}) as Dictionary
	Session.notify_player_key(message_key, message_args, bool(result.get("success", false)))


func _update_dusk_overlay() -> void:
	var minute: int = Session.get_minute_of_day()
	var alpha: float = 0.0
	if minute >= 17 * 60:
		alpha = remap(clampf(float(minute), 17.0 * 60.0, 22.0 * 60.0), 17.0 * 60.0, 22.0 * 60.0, 0.0, 0.42)
	elif minute < 5 * 60:
		alpha = 0.42
	elif minute < 7 * 60:
		alpha = remap(float(minute),5.0 * 60,7.0 * 60,0.42,0.0)
	_dusk_overlay.color = Color(0.10, 0.13, 0.28, alpha)
	if _lighting_material != null:
		_lighting_material.set_shader_parameter("night_alpha",alpha)

func _update_light_field() -> void:
	if _lighting_material == null:
		return
	var span := Diagnostic.begin("scene.update_light_field") if Diagnostic.enabled else 0
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	var origin := inverse * Vector2.ZERO
	_lighting_material.set_shader_parameter("world_origin",origin)
	_lighting_material.set_shader_parameter("world_extent",inverse * get_viewport_rect().size - origin)
	_lighting_material.set_shader_parameter("light_mask",Session.simulation.furniture.lighting.texture(Session.simulation))
	Diagnostic.end(span)
