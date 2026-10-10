extends "res://src/ui/inventory_grid.gd"

# Transparent probe excludes slot art so the actual sprite can be measured.
func _draw() -> void:
	if _dragged_placement_index >= 0:
		_draw_dragged_placement()
	else:
		for placement: Dictionary in _placements:
			_draw_placement_icon(placement)
