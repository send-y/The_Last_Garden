class_name FirstNightWorld
extends Node2D

signal selection_changed(label: String, in_range: bool)

const Catalog := preload("res://src/world/first_night_catalog.gd")
const Interactable := preload("res://src/world/interactable_view.gd")

var _interactables: Array[InteractableView] = []
var _selected: InteractableView
var _selected_cell: Vector2i = Vector2i(-1, -1)

@onready var _player: CharacterBody2D = get_node("../Player") as CharacterBody2D


func _ready() -> void:
	_build_static_collision()
	_spawn_interactables()
	Session.state_changed.connect(_on_state_changed)
	Session.state_reloaded.connect(_on_state_reloaded)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			select_at_world_position(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			select_at_world_position(get_global_mouse_position())
			interact_with_selection()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		interact_with_selection()
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


func interact_with_selection() -> void:
	if _selected == null or not is_instance_valid(_selected) or not _selected.visible:
		Session.notify_player("Сначала выберите объект левой кнопкой мыши.")
		return

	Session.execute_interaction(_selected.object_id)
	_refresh_interactables()
	if not _selected.visible:
		_set_selected(null)
	else:
		var in_range: bool = (
			_player.global_position.distance_to(_selected.global_position)
			<= Catalog.INTERACTION_RANGE
		)
		selection_changed.emit(_selected.get_display_label(), in_range)


func _set_selected(value: InteractableView) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = value
	if _selected == null:
		selection_changed.emit("Клетка %d, %d" % [_selected_cell.x, _selected_cell.y], false)
		return
	_selected.set_selected(true)
	var in_range: bool = _player.global_position.distance_to(_selected.global_position) <= Catalog.INTERACTION_RANGE
	selection_changed.emit(_selected.get_display_label(), in_range)


func _spawn_interactables() -> void:
	for definition: Dictionary in Catalog.interactables():
		var interactable: InteractableView = Interactable.new()
		add_child(interactable)
		interactable.configure(definition)
		_interactables.append(interactable)


func _refresh_interactables() -> void:
	for interactable: InteractableView in _interactables:
		interactable.refresh_from_state()
	queue_redraw()


func _on_state_changed() -> void:
	_refresh_interactables()
	if _selected == null or not is_instance_valid(_selected):
		return
	if not _selected.visible:
		_selected_cell = Vector2i(-1, -1)
		_set_selected(null)
		return
	var in_range: bool = _player.global_position.distance_to(_selected.global_position) <= Catalog.INTERACTION_RANGE
	selection_changed.emit(_selected.get_display_label(), in_range)


func _on_state_reloaded() -> void:
	_refresh_interactables()
	_selected_cell = Vector2i(-1, -1)
	_set_selected(null)


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
