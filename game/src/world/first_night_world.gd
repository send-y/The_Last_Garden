class_name FirstNightWorld
extends Node2D

signal selection_changed(selection: Dictionary)
signal blueprint_interaction_requested(cell: Vector2i, continuous_work: bool)
signal resource_interaction_requested(target_id: String, continuous_work: bool)
signal structure_interaction_requested(cell: Vector2i, continuous_work: bool)

const Catalog := preload("res://src/world/first_night_catalog.gd")
const Interactable := preload("res://src/world/interactable_view.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const BuildingCatalogScript := preload(
	"res://src/construction/building_catalog.gd"
)
const CraftingCatalogScript := preload(
	"res://src/crafting/crafting_catalog.gd"
)
const DroppedItemScene: PackedScene = preload(
	"res://src/items/dropped_item.tscn"
)

var _interactables: Array[InteractableView] = []
var _drop_views: Dictionary = {}
var _selected: InteractableView
var _selected_cell: Vector2i = Vector2i(-1, -1)
var _content := Content.new()
var _building_catalog := BuildingCatalogScript.new()
var _crafting_catalog := CraftingCatalogScript.new()

@onready var _player: CharacterBody2D = get_node("../Player") as CharacterBody2D

@onready var _dropped_items: Node2D = (
	$DroppedItems as Node2D
)

func _ready() -> void:
	_build_static_collision()
	_spawn_interactables()
	_sync_dropped_items()
	Session.state_changed.connect(_on_state_changed)
	Session.state_reloaded.connect(_on_state_reloaded)
	queue_redraw()


func _sync_dropped_items() -> void:
	var active_ids: Dictionary = {}
	for drop_value: Variant in Session.get_world_drops():
		if typeof(drop_value) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = drop_value as Dictionary
		var drop_id: String = String(definition.get("drop_id", ""))
		if drop_id.is_empty():
			continue
		active_ids[drop_id] = true
		var drop: DroppedItem = _drop_views.get(drop_id) as DroppedItem
		if drop == null or not is_instance_valid(drop):
			drop = _create_dropped_item_view(definition)
			if drop == null:
				continue
			_drop_views[drop_id] = drop
		_update_dropped_item_view(drop, definition)

	for drop_id_variant: Variant in _drop_views.keys():
		var drop_id: String = String(drop_id_variant)
		if active_ids.has(drop_id):
			continue
		var stale_drop: DroppedItem = (
			_drop_views.get(drop_id) as DroppedItem
		)
		if stale_drop != null and is_instance_valid(stale_drop):
			stale_drop.queue_free()
		_drop_views.erase(drop_id)


func _create_dropped_item_view(
	definition: Dictionary
) -> DroppedItem:
	var drop := DroppedItemScene.instantiate() as DroppedItem
	if drop == null:
		push_error("Failed to create dropped item view.")
		return null
	_dropped_items.add_child(drop)
	drop.pickup_requested.connect(
		_on_dropped_item_pickup_requested
	)
	return drop


func _update_dropped_item_view(
	drop: DroppedItem,
	definition: Dictionary
) -> void:
	var item_id: String = String(definition.get("item_id", ""))
	var icon_path: String = _content.item_icon_path(item_id)
	var icon_texture: Texture2D
	if not icon_path.is_empty():
		icon_texture = load(icon_path) as Texture2D

	drop.configure(
		String(definition.get("drop_id", "")),
		item_id,
		int(definition.get("amount", 1)),
		icon_texture
	)
	var position_data: Array = definition.get("position", []) as Array
	if position_data.size() == 2:
		drop.global_position = Vector2(
			float(position_data[0]),
			float(position_data[1])
		)


func _on_dropped_item_pickup_requested(
	drop: DroppedItem
) -> void:
	if not is_instance_valid(drop):
		return

	Session.try_pickup_world_drop(drop.drop_id)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			select_at_world_position(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			select_at_world_position(get_global_mouse_position())
			interact_with_selection(false)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		interact_with_selection(true)
		get_viewport().set_input_as_handled()


func select_at_world_position(world_position: Vector2) -> void:
	var nearest: InteractableView
	var nearest_distance: float = INF
	for candidate: InteractableView in _interactables:
		if not candidate.contains_world_point(world_position):
			continue
		var candidate_distance: float = candidate.global_position.distance_to(world_position)
		if candidate_distance < nearest_distance:
			nearest = candidate
			nearest_distance = candidate_distance

	if nearest == null:
		_selected_cell = Vector2i(floori(world_position.x / Catalog.CELL_SIZE), floori(world_position.y / Catalog.CELL_SIZE))
	else:
		_selected_cell = Vector2i(-1, -1)
	_set_selected(nearest)
	queue_redraw()


func interact_with_selection(continuous_work: bool = false) -> void:
	var blueprint: Dictionary = _get_selected_blueprint()
	if not blueprint.is_empty():
		var target_position := Content.cell_center(_selected_cell.x, _selected_cell.y)
		if _player.global_position.distance_to(target_position) > Catalog.INTERACTION_RANGE:
			Session.notify_player_key("interaction.failure.too_far")
			return
		blueprint_interaction_requested.emit(_selected_cell, continuous_work)
		return
	var structure: Dictionary = _get_selected_structure()
	if not structure.is_empty():
		var building: Dictionary = _building_catalog.get_definition(
			String(structure.get("building_id", ""))
		)
		if String(building.get("station_type", "")).is_empty():
			Session.notify_player_key("interaction.failure.unsupported_target")
			return
		var target_position := Content.cell_center(_selected_cell.x, _selected_cell.y)
		if _player.global_position.distance_to(target_position) > Catalog.INTERACTION_RANGE:
			Session.notify_player_key("interaction.failure.too_far")
			return
		structure_interaction_requested.emit(_selected_cell, continuous_work)
		return

	if _selected == null or not is_instance_valid(_selected) or not _selected.visible:
		Session.notify_player_key("interaction.prompt.select_object")
		return
	var required_work: int = (
		Session.get_resource_work_required(
			_selected.object_id
		)
	)

	if required_work > 0:
		var distance: float = (
			_player.global_position.distance_to(
				_selected.global_position
			)
		)

		if distance > Catalog.INTERACTION_RANGE:
			Session.notify_player_key(
				"interaction.failure.too_far"
			)
			return

		resource_interaction_requested.emit(
			_selected.object_id,
			continuous_work
		)
		return

	Session.execute_interaction(_selected.object_id)
	_refresh_interactables()
	if _selected == null or not is_instance_valid(_selected):
		return
	if not _selected.visible:
		_set_selected(null)
	else:
		var in_range: bool = (
			_player.global_position.distance_to(_selected.global_position)
			<= Catalog.INTERACTION_RANGE
		)
		selection_changed.emit(_selection_payload(_selected, in_range))


func _set_selected(value: InteractableView) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = value
	if _selected == null:
		if _selected_cell.x < 0 or _selected_cell.y < 0:
			selection_changed.emit({"kind": "none"})
		elif not _get_selected_blueprint().is_empty():
			selection_changed.emit(_blueprint_selection_payload())
		elif not _get_selected_structure().is_empty():
			selection_changed.emit(_structure_selection_payload())
		else:
			selection_changed.emit({
				"kind": "cell",
				"x": _selected_cell.x,
				"y": _selected_cell.y,
			})
		return
	_selected.set_selected(true)
	var in_range: bool = _player.global_position.distance_to(_selected.global_position) <= Catalog.INTERACTION_RANGE
	selection_changed.emit(_selection_payload(_selected, in_range))


func _spawn_interactables() -> void:
	var definitions: Array[Dictionary] = Catalog.interactables()
	definitions.append_array(Session.get_surface_boulders())
	var existing_by_id: Dictionary = {}
	for interactable: InteractableView in _interactables:
		if is_instance_valid(interactable):
			existing_by_id[interactable.object_id] = interactable
	var next_interactables: Array[InteractableView] = []
	var retained_ids: Dictionary = {}
	for definition: Dictionary in definitions:
		var object_id := String(definition.get("id", ""))
		var interactable: InteractableView
		if existing_by_id.has(object_id):
			interactable = existing_by_id[object_id] as InteractableView
		else:
			interactable = Interactable.new()
			add_child(interactable)
		interactable.configure(definition)
		next_interactables.append(interactable)
		retained_ids[object_id] = true
	for old_interactable: InteractableView in _interactables:
		if (
			is_instance_valid(old_interactable)
			and not retained_ids.has(old_interactable.object_id)
		):
			old_interactable.queue_free()
	_interactables = next_interactables


func _refresh_interactables(snap: bool = false) -> void:
	for interactable: InteractableView in _interactables:
		interactable.refresh_from_state(snap)
	queue_redraw()


func _on_state_changed() -> void:
	_refresh_interactables()
	_sync_dropped_items()
	if _selected == null or not is_instance_valid(_selected):
		if _selected_cell.x >= 0 and _selected_cell.y >= 0:
			_set_selected(null)
		return
	if not _selected.visible:
		_selected_cell = Vector2i(-1, -1)
		_set_selected(null)
		return
	var in_range: bool = _player.global_position.distance_to(_selected.global_position) <= Catalog.INTERACTION_RANGE
	selection_changed.emit(_selection_payload(_selected, in_range))


func _on_state_reloaded() -> void:
	_selected_cell = Vector2i(-1, -1)
	_set_selected(null)
	_spawn_interactables()
	_refresh_interactables(true)
	_sync_dropped_items()


func _selection_payload(interactable: InteractableView, in_range: bool) -> Dictionary:
	var result: Dictionary = {
		"kind": "interactable",
		"label": interactable.get_display_label(),
		"in_range": in_range,
		"object_id": interactable.object_id,
	}
	var status: String = interactable.get_status_text()
	if not status.is_empty():
		result["status"] = status
	return result


func _get_selected_blueprint() -> Dictionary:
	if _selected_cell.x < 0 or _selected_cell.y < 0:
		return {}
	for blueprint_value: Variant in Session.get_blueprints():
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue
		var blueprint: Dictionary = blueprint_value as Dictionary
		if blueprint.get("cell", []) == [_selected_cell.x, _selected_cell.y]:
			return blueprint
	return {}


func _get_selected_structure() -> Dictionary:
	if _selected_cell.x < 0 or _selected_cell.y < 0:
		return {}
	for structure_value: Variant in Session.get_structures():
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue
		var structure := structure_value as Dictionary
		if structure.get("cell", []) == [_selected_cell.x, _selected_cell.y]:
			return structure
	return {}


func _structure_selection_payload() -> Dictionary:
	var structure: Dictionary = _get_selected_structure()
	var building: Dictionary = _building_catalog.get_definition(
		String(structure.get("building_id", ""))
	)
	var status := ""
	for project_value: Variant in Session.get_crafting_projects():
		if typeof(project_value) != TYPE_DICTIONARY:
			continue
		var project := project_value as Dictionary
		if project.get("cell", []) != [_selected_cell.x, _selected_cell.y]:
			continue
		var recipe := _crafting_catalog.get_definition(String(project.get("recipe_id", "")))
		status = Localized.resolve("crafting.project.status", {
			"recipe": Localized.resolve(String(recipe.get("label_key", ""))),
			"progress": int(project.get("work_progress_minutes", 0)),
			"required": int(project.get("required_work_minutes", 0)),
		})
		break
	var target_position := Content.cell_center(_selected_cell.x, _selected_cell.y)
	return {
		"kind": "structure",
		"x": _selected_cell.x,
		"y": _selected_cell.y,
		"building_id": String(structure.get("building_id", "")),
		"label": Localized.resolve(String(building.get("label_key", ""))),
		"status": status,
		"in_range": _player.global_position.distance_to(target_position) <= Catalog.INTERACTION_RANGE,
	}


func _blueprint_selection_payload() -> Dictionary:
	var blueprint: Dictionary = _get_selected_blueprint()
	if blueprint.is_empty():
		return {
			"kind": "cell",
			"x": _selected_cell.x,
			"y": _selected_cell.y,
		}
	var building: Dictionary = _building_catalog.get_definition(
		String(blueprint.get("building_id", ""))
	)
	var label: String = Localized.resolve(
		String(building.get("label_key", "building.core.wood_wall.name"))
	)
	var progress_parts: PackedStringArray = []
	var required: Dictionary = blueprint.get("required_materials", {}) as Dictionary
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	var item_ids: Array[String] = []
	for item_variant: Variant in required.keys():
		item_ids.append(String(item_variant))
	item_ids.sort()
	for item_id: String in item_ids:
		progress_parts.append(Localized.resolve(
			"construction.blueprint.material_progress",
			{
				"item": Localized.resolve(_content.item_label_key(item_id)),
				"delivered": int(delivered.get(item_id, 0)),
				"required": int(required.get(item_id, 0)),
			}
		))
	progress_parts.append(Localized.resolve(
		"construction.blueprint.work_progress",
		{
			"progress": int(blueprint.get("work_progress_minutes", 0)),
			"required": int(blueprint.get("required_work_minutes", 0)),
		}
	))
	var target_position := Content.cell_center(_selected_cell.x, _selected_cell.y)
	return {
		"kind": "blueprint",
		"x": _selected_cell.x,
		"y": _selected_cell.y,
		"label": label,
		"status": ", ".join(progress_parts),
		"in_range": (
			_player.global_position.distance_to(target_position)
			<= Catalog.INTERACTION_RANGE
		),
	}


func _build_static_collision() -> void:
	var map_pixels := Vector2(Catalog.MAP_SIZE * Catalog.CELL_SIZE)
	_add_static_rect(Rect2(-32.0, -32.0, map_pixels.x + 64.0, 32.0))
	_add_static_rect(Rect2(-32.0, map_pixels.y, map_pixels.x + 64.0, 32.0))
	_add_static_rect(Rect2(-32.0, 0.0, 32.0, map_pixels.y))
	_add_static_rect(Rect2(map_pixels.x, 0.0, 32.0, map_pixels.y))

	var tile: float = float(Catalog.CELL_SIZE)
	_add_static_rect(Rect2(19.0 * tile, 17.0 * tile, 10.0 * tile, 16.0))
	_add_static_rect(Rect2(19.0 * tile, 17.0 * tile, 16.0, 9.0 * tile))
	_add_static_rect(Rect2(29.0 * tile - 16.0, 17.0 * tile, 16.0, 9.0 * tile))
	_add_static_rect(Rect2(19.0 * tile, 26.0 * tile - 16.0, 5.0 * tile, 16.0))
	_add_static_rect(Rect2(25.0 * tile, 26.0 * tile - 16.0, 4.0 * tile, 16.0))


func _add_static_rect(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _draw() -> void:
	var tile: float = float(Catalog.CELL_SIZE)
	var map_pixels := Vector2(Catalog.MAP_SIZE * Catalog.CELL_SIZE)
	draw_rect(Rect2(Vector2.ZERO, map_pixels), Color("566f46"))

	for y: int in range(Catalog.MAP_SIZE.y):
		for x: int in range(Catalog.MAP_SIZE.x):
			if (x * 7 + y * 11) % 9 == 0:
				draw_rect(Rect2(x * tile + 4.0, y * tile + 5.0, 4.0, 3.0), Color(0.30, 0.42, 0.25, 0.55))

	var water_rect := Rect2(0.0, 20.0 * tile, 7.5 * tile, 15.0 * tile)
	draw_rect(water_rect, Color("356c79"))
	for y_line: int in range(21, 35, 2):
		draw_line(Vector2(12.0, y_line * tile), Vector2(7.0 * tile, y_line * tile), Color(0.45, 0.72, 0.73, 0.45), 2.0)

	draw_colored_polygon(PackedVector2Array([
		Vector2(7.0 * tile, 20.0 * tile),
		Vector2(9.0 * tile, 21.0 * tile),
		Vector2(8.0 * tile, 35.0 * tile),
		Vector2(7.0 * tile, 35.0 * tile),
	]), Color("b39a69"))

	draw_rect(Rect2(19.0 * tile, 17.0 * tile, 10.0 * tile, 9.0 * tile), Color("746b58"))
	draw_rect(Rect2(19.0 * tile, 17.0 * tile, 10.0 * tile, 16.0), Color("3d3933"))
	draw_rect(Rect2(19.0 * tile, 17.0 * tile, 16.0, 9.0 * tile), Color("3d3933"))
	draw_rect(Rect2(29.0 * tile - 16.0, 17.0 * tile, 16.0, 9.0 * tile), Color("3d3933"))
	draw_rect(Rect2(19.0 * tile, 26.0 * tile - 16.0, 5.0 * tile, 16.0), Color("3d3933"))
	draw_rect(Rect2(25.0 * tile, 26.0 * tile - 16.0, 4.0 * tile, 16.0), Color("3d3933"))
	draw_rect(Rect2(24.0 * tile, 26.0 * tile - 8.0, tile, 8.0), Color("b99b68"))

	var road_color := Color(0.55, 0.46, 0.33, 0.55)
	draw_rect(Rect2(23.2 * tile, 26.0 * tile, 2.6 * tile, 12.0 * tile), road_color)
	draw_rect(Rect2(8.0 * tile, 30.0 * tile, 16.0 * tile, 2.0 * tile), road_color)

	var grid_color := Color(0.12, 0.16, 0.11, 0.10)
	for x_line: int in range(Catalog.MAP_SIZE.x + 1):
		draw_line(Vector2(x_line * tile, 0.0), Vector2(x_line * tile, map_pixels.y), grid_color, 1.0)
	for y_line: int in range(Catalog.MAP_SIZE.y + 1):
		draw_line(Vector2(0.0, y_line * tile), Vector2(map_pixels.x, y_line * tile), grid_color, 1.0)

	if _selected_cell.x >= 0 and _selected_cell.y >= 0 and _selected_cell.x < Catalog.MAP_SIZE.x and _selected_cell.y < Catalog.MAP_SIZE.y:
		var selected_rect := Rect2(Vector2(_selected_cell) * tile, Vector2(tile, tile))
		draw_rect(selected_rect.grow(-1.0), Color("f1d66b"), false, 2.0)
