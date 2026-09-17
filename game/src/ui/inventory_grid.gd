class_name InventoryGrid
extends Control

const GRID_COLUMNS: int = 4
const GRID_ROWS: int = 4
const CELL_SIZE: float = 40.0
const CELL_GAP: float = 2.0

const GRID_PIXEL_SIZE := Vector2(
	GRID_COLUMNS * CELL_SIZE + (GRID_COLUMNS - 1) * CELL_GAP,
	GRID_ROWS * CELL_SIZE + (GRID_ROWS - 1) * CELL_GAP
)

const SLOT_COLOR := Color8(37, 41, 37)
const SLOT_BORDER_COLOR := Color8(89, 96, 89)
const ITEM_CELL_COLOR := Color8(69, 97, 58)
const ITEM_BORDER_COLOR := Color8(169, 184, 106)

const AMOUNT_BADGE_COLOR := Color8(23, 26, 24, 230)
const AMOUNT_TEXT_COLOR := Color8(216, 210, 184)

var _placements: Array[Dictionary] = []
var _icon_cache: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = GRID_PIXEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func present(placements: Array[Dictionary]) -> void:
	_placements.clear()

	for placement: Dictionary in placements:
		var placement_copy := placement.duplicate(true)
		_placements.append(placement_copy)
		_cache_placement_icon(placement_copy)

	queue_redraw()


func _draw() -> void:
	_draw_empty_slots()

	for placement: Dictionary in _placements:
		_draw_placement(placement)


func _draw_empty_slots() -> void:
	for row: int in range(GRID_ROWS):
		for column: int in range(GRID_COLUMNS):
			var cell := Vector2i(column, row)
			var cell_rect := _cell_rect(cell)

			draw_rect(cell_rect, SLOT_COLOR, true)
			draw_rect(
				cell_rect,
				SLOT_BORDER_COLOR,
				false,
				1.0
			)


func _draw_placement(placement: Dictionary) -> void:
	var origin: Vector2i = placement.get(
		"origin",
		Vector2i.ZERO
	)
	var footprint := (
		placement.get("footprint", []) as Array
	)

	for cell_variant: Variant in footprint:
		var local_cell: Vector2i = cell_variant
		var absolute_cell := origin + local_cell
		var item_rect := _cell_rect(
			absolute_cell
		).grow(-2.0)

		draw_rect(item_rect, ITEM_CELL_COLOR, true)
		draw_rect(
			item_rect,
			ITEM_BORDER_COLOR,
			false,
			1.0
		)

	_draw_placement_icon(placement, origin)
	_draw_placement_amount(placement, origin)


func _draw_placement_amount(
	placement: Dictionary,
	origin: Vector2i
) -> void:
	var amount := int(placement.get("amount", 1))
	if amount <= 1:
		return

	var origin_rect := _cell_rect(origin)
	var badge_rect := Rect2(
		origin_rect.end - Vector2(20.0, 16.0),
		Vector2(18.0, 14.0)
	)

	draw_rect(
		badge_rect,
		AMOUNT_BADGE_COLOR,
		true
	)
	draw_string(
		ThemeDB.fallback_font,
		badge_rect.position + Vector2(3.0, 11.0),
		str(amount),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		AMOUNT_TEXT_COLOR
	)


func _draw_placement_icon(
	placement: Dictionary,
	origin: Vector2i
) -> void:
	var icon_path := String(
		placement.get("icon_path", "")
	)
	if icon_path.is_empty():
		return
	if not _icon_cache.has(icon_path):
		return

	var texture := _icon_cache[icon_path] as Texture2D
	if texture == null:
		return

	var icon_rect := Rect2(
		_cell_rect(origin).position + Vector2(4.0, 4.0),
		Vector2(32.0, 32.0)
	)
	draw_texture_rect(texture, icon_rect, false)


func _cache_placement_icon(
	placement: Dictionary
) -> void:
	var icon_path := String(
		placement.get("icon_path", "")
	)
	if icon_path.is_empty():
		return
	if _icon_cache.has(icon_path):
		return
	if not ResourceLoader.exists(icon_path):
		return

	var texture := load(icon_path) as Texture2D
	if texture != null:
		_icon_cache[icon_path] = texture


func _cell_rect(cell: Vector2i) -> Rect2:
	var position := Vector2(cell) * (
		CELL_SIZE + CELL_GAP
	)
	return Rect2(
		position,
		Vector2(CELL_SIZE, CELL_SIZE)
	)
