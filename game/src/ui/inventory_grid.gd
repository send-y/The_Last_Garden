class_name InventoryGrid
extends Control

signal selection_changed(placement: Dictionary)

const GRID_COLUMNS: int = 4
const GRID_ROWS: int = 4
const CELL_SIZE: float = 42.0
const CELL_GAP: float = 2.0

const GRID_PIXEL_SIZE := Vector2(
	GRID_COLUMNS * CELL_SIZE + (GRID_COLUMNS - 1) * CELL_GAP,
	GRID_ROWS * CELL_SIZE + (GRID_ROWS - 1) * CELL_GAP
)

const AMOUNT_BADGE_COLOR := Color8(35, 27, 31, 235)
const AMOUNT_TEXT_COLOR := Color8(239, 226, 207)

const SLOT_TEXTURES: Dictionary = {
	"regular": {
		0: preload("res://assets/sprites/ui/inv_slot_regular_0side.png"),
		1: preload("res://assets/sprites/ui/inv_slot_regular_1side.png"),
		2: preload("res://assets/sprites/ui/inv_slot_regular_2side.png"),
		"2_parallel": preload("res://assets/sprites/ui/inv_slot_regular_2side_parallel.png"),
		3: preload("res://assets/sprites/ui/inv_slot_regular_3side.png"),
		4: preload("res://assets/sprites/ui/inv_slot_regular.png"),
	},
	"hover": {
		0: preload("res://assets/sprites/ui/inv_slot_hover_0side.png"),
		1: preload("res://assets/sprites/ui/inv_slot_hover_1side.png"),
		2: preload("res://assets/sprites/ui/inv_slot_hover_2side.png"),
		"2_parallel": preload("res://assets/sprites/ui/inv_slot_hover_2side_parallel.png"),
		3: preload("res://assets/sprites/ui/inv_slot_hover_3side.png"),
		4: preload("res://assets/sprites/ui/inv_slot_hover.png"),
	},
	"selected": {
		0: preload("res://assets/sprites/ui/inv_slot_selected_0side.png"),
		1: preload("res://assets/sprites/ui/inv_slot_selected_1side.png"),
		2: preload("res://assets/sprites/ui/inv_slot_selected_2side.png"),
		"2_parallel": preload("res://assets/sprites/ui/inv_slot_selected_2side_parallel.png"),
		3: preload("res://assets/sprites/ui/inv_slot_selected_3side.png"),
		4: preload("res://assets/sprites/ui/inv_slot_selected.png"),
	},
}

var _placements: Array[Dictionary] = []
var _cell_to_placement: Dictionary = {}
var _icon_cache: Dictionary = {}
var _hover_cell := Vector2i(-1, -1)
var _selected_placement_index: int = -1
var _selected_key: String = ""


func _ready() -> void:
	custom_minimum_size = GRID_PIXEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func present(placements: Array[Dictionary]) -> void:
	_placements.clear()
	_cell_to_placement.clear()
	_selected_placement_index = -1

	for placement: Dictionary in placements:
		var placement_copy := placement.duplicate(true)
		var placement_index := _placements.size()
		_placements.append(placement_copy)
		_cache_placement_icon(placement_copy)
		_index_placement_cells(placement_copy, placement_index)

		if _placement_key(placement_copy) == _selected_key:
			_selected_placement_index = placement_index

	if _selected_placement_index < 0:
		_selected_key = ""

	selection_changed.emit(get_selected_placement())
	queue_redraw()


func get_selected_placement() -> Dictionary:
	if _selected_placement_index < 0:
		return {}
	if _selected_placement_index >= _placements.size():
		return {}
	return _placements[_selected_placement_index].duplicate(true)


func _draw() -> void:
	for row: int in range(GRID_ROWS):
		for column: int in range(GRID_COLUMNS):
			var cell := Vector2i(column, row)
			var placement_index := int(
				_cell_to_placement.get(cell, -1)
			)
			if placement_index < 0:
				var empty_state := (
					"hover" if cell == _hover_cell else "regular"
				)
				_draw_slot(cell, empty_state, [cell])
				continue

			var state := _placement_state(placement_index)
			var occupied_cells := _placement_cells(
				_placements[placement_index]
			)
			_draw_slot(cell, state, occupied_cells)

	for placement: Dictionary in _placements:
		_draw_placement_icon(placement)
		_draw_placement_amount(placement)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_set_hover_cell(_cell_at_position(motion.position))
		return

	if event is not InputEventMouseButton:
		return

	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not mouse_button.pressed:
		return

	var cell := _cell_at_position(mouse_button.position)
	var placement_index := int(_cell_to_placement.get(cell, -1))
	_select_placement(placement_index)
	accept_event()


func _draw_slot(
	cell: Vector2i,
	state: String,
	occupied_cells: Array[Vector2i]
) -> void:
	var exposed := {
		"left": not occupied_cells.has(cell + Vector2i.LEFT),
		"top": not occupied_cells.has(cell + Vector2i.UP),
		"right": not occupied_cells.has(cell + Vector2i.RIGHT),
		"bottom": not occupied_cells.has(cell + Vector2i.DOWN),
	}
	var exposed_count: int = 0
	for value: bool in exposed.values():
		if value:
			exposed_count += 1

	var texture_key: Variant = exposed_count
	var rotation := 0.0
	if exposed_count == 1:
		rotation = _single_side_rotation(exposed)
	elif exposed_count == 2:
		if bool(exposed.left) and bool(exposed.right):
			texture_key = "2_parallel"
		elif bool(exposed.top) and bool(exposed.bottom):
			texture_key = "2_parallel"
			rotation = PI / 2.0
		else:
			rotation = _adjacent_sides_rotation(exposed)
	elif exposed_count == 3:
		rotation = _three_sides_rotation(exposed)

	var state_textures := SLOT_TEXTURES.get(
		state,
		SLOT_TEXTURES["regular"]
	) as Dictionary
	var texture := state_textures.get(texture_key) as Texture2D
	if texture == null:
		return

	var cell_rect := _cell_rect(cell)
	var center := cell_rect.get_center()
	draw_set_transform(center, rotation, Vector2.ONE)
	draw_texture_rect(
		texture,
		Rect2(-cell_rect.size / 2.0, cell_rect.size),
		false
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _placement_state(placement_index: int) -> String:
	if placement_index == _selected_placement_index:
		return "selected"
	var hovered_index := int(
		_cell_to_placement.get(_hover_cell, -1)
	)
	if placement_index == hovered_index:
		return "hover"
	return "regular"


func _draw_placement_amount(placement: Dictionary) -> void:
	var amount := int(placement.get("amount", 1))
	if amount <= 1:
		return

	var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
	var origin_rect := _cell_rect(origin)
	var badge_rect := Rect2(
		origin_rect.end - Vector2(20.0, 16.0),
		Vector2(18.0, 14.0)
	)
	draw_rect(badge_rect, AMOUNT_BADGE_COLOR, true)
	draw_string(
		ThemeDB.fallback_font,
		badge_rect.position + Vector2(3.0, 11.0),
		str(amount),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		AMOUNT_TEXT_COLOR
	)


func _draw_placement_icon(placement: Dictionary) -> void:
	var icon_path := String(placement.get("icon_path", ""))
	if icon_path.is_empty() or not _icon_cache.has(icon_path):
		return

	var texture := _icon_cache[icon_path] as Texture2D
	if texture == null:
		return

	var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
	var icon_rect := Rect2(
		_cell_rect(origin).position + Vector2(5.0, 5.0),
		Vector2(CELL_SIZE - 10.0, CELL_SIZE - 10.0)
	)
	draw_texture_rect(texture, icon_rect, false)


func _cache_placement_icon(placement: Dictionary) -> void:
	var icon_path := String(placement.get("icon_path", ""))
	if icon_path.is_empty() or _icon_cache.has(icon_path):
		return
	if not ResourceLoader.exists(icon_path):
		return

	var texture := load(icon_path) as Texture2D
	if texture != null:
		_icon_cache[icon_path] = texture


func _index_placement_cells(
	placement: Dictionary,
	placement_index: int
) -> void:
	for cell: Vector2i in _placement_cells(placement):
		_cell_to_placement[cell] = placement_index


func _placement_cells(placement: Dictionary) -> Array[Vector2i]:
	var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
	var footprint := placement.get("footprint", []) as Array
	var cells: Array[Vector2i] = []
	for local_cell_variant: Variant in footprint:
		var local_cell: Vector2i = local_cell_variant
		cells.append(origin + local_cell)
	return cells


func _select_placement(placement_index: int) -> void:
	_selected_placement_index = placement_index
	if placement_index < 0:
		_selected_key = ""
	else:
		_selected_key = _placement_key(_placements[placement_index])
	selection_changed.emit(get_selected_placement())
	queue_redraw()


func _placement_key(placement: Dictionary) -> String:
	var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
	return "%s:%d:%d" % [
		String(placement.get("item_id", "")),
		origin.x,
		origin.y,
	]


func _set_hover_cell(cell: Vector2i) -> void:
	if _hover_cell == cell:
		return
	_hover_cell = cell
	queue_redraw()


func _on_mouse_exited() -> void:
	_set_hover_cell(Vector2i(-1, -1))


func _cell_at_position(local_position: Vector2) -> Vector2i:
	if local_position.x < 0.0 or local_position.y < 0.0:
		return Vector2i(-1, -1)
	var stride := CELL_SIZE + CELL_GAP
	var cell := Vector2i(
		int(floor(local_position.x / stride)),
		int(floor(local_position.y / stride))
	)
	if cell.x < 0 or cell.x >= GRID_COLUMNS:
		return Vector2i(-1, -1)
	if cell.y < 0 or cell.y >= GRID_ROWS:
		return Vector2i(-1, -1)
	var within_cell := local_position - Vector2(cell) * stride
	if within_cell.x > CELL_SIZE or within_cell.y > CELL_SIZE:
		return Vector2i(-1, -1)
	return cell


func _cell_rect(cell: Vector2i) -> Rect2:
	var position := Vector2(cell) * (CELL_SIZE + CELL_GAP)
	return Rect2(position, Vector2(CELL_SIZE, CELL_SIZE))


func _single_side_rotation(exposed: Dictionary) -> float:
	if bool(exposed.top):
		return PI / 2.0
	if bool(exposed.right):
		return PI
	if bool(exposed.bottom):
		return -PI / 2.0
	return 0.0


func _adjacent_sides_rotation(exposed: Dictionary) -> float:
	if bool(exposed.top) and bool(exposed.right):
		return PI / 2.0
	if bool(exposed.right) and bool(exposed.bottom):
		return PI
	if bool(exposed.bottom) and bool(exposed.left):
		return -PI / 2.0
	return 0.0


func _three_sides_rotation(exposed: Dictionary) -> float:
	if not bool(exposed.left):
		return PI / 2.0
	if not bool(exposed.top):
		return PI
	if not bool(exposed.right):
		return -PI / 2.0
	return 0.0
