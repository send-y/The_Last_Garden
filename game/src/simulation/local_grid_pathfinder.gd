class_name LocalGridPathfinder
extends RefCounted

var _grid := AStarGrid2D.new()
var _map_size: Vector2i
var _cell_size: int


func _init(map_size: Vector2i, cell_size: int, blocked_cells: Array[Vector2i]) -> void:
	_map_size = map_size
	_cell_size = cell_size
	_grid.region = Rect2i(Vector2i.ZERO, map_size)
	_grid.cell_size = Vector2(cell_size, cell_size)
	_grid.offset = Vector2(cell_size, cell_size) * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_grid.update()
	for cell: Vector2i in blocked_cells:
		if _grid.is_in_boundsv(cell):
			_grid.set_point_solid(cell)


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		clampi(floori(world_position.x / float(_cell_size)), 0, _map_size.x - 1),
		clampi(floori(world_position.y / float(_cell_size)), 0, _map_size.y - 1)
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * _cell_size) + Vector2(_cell_size, _cell_size) * 0.5


func next_cell(
	from_cell: Vector2i,
	to_cell: Vector2i,
	temporary_blocker: Vector2i = Vector2i(-1, -1)
) -> Vector2i:
	if not _grid.is_in_boundsv(from_cell) or not _grid.is_in_boundsv(to_cell):
		return from_cell
	if _grid.is_point_solid(from_cell) or _grid.is_point_solid(to_cell):
		return from_cell

	var blocker_applied: bool = (
		_grid.is_in_boundsv(temporary_blocker)
		and temporary_blocker != from_cell
		and temporary_blocker != to_cell
		and not _grid.is_point_solid(temporary_blocker)
	)
	if blocker_applied:
		_grid.set_point_solid(temporary_blocker)

	var path: Array[Vector2i] = _grid.get_id_path(from_cell, to_cell)
	if blocker_applied:
		_grid.set_point_solid(temporary_blocker, false)
	if path.size() < 2:
		return from_cell
	return path[1]


func is_walkable(cell: Vector2i) -> bool:
	return _grid.is_in_boundsv(cell) and not _grid.is_point_solid(cell)
