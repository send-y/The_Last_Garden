extends Control


func _ready() -> void:
	name = "MarkerOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if not Session.get_markers().is_empty():
		queue_redraw()


func _draw() -> void:
	if get_viewport().get_camera_2d() == null:
		return
	var viewport_size := get_viewport_rect().size
	var screen_center := viewport_size * 0.5
	var half_bounds := viewport_size * 0.5 - Vector2(24.0, 24.0)
	for marker: Dictionary in Session.get_markers():
		var raw_position := marker.get("position", []) as Array
		if raw_position.size() < 2:
			continue
		var world_position := Vector2(float(raw_position[0]), float(raw_position[1]))
		var screen_position: Vector2 = get_viewport().get_canvas_transform() * world_position
		var color := Color.from_string(String(marker.get("color", "ffffff")), Color.WHITE)
		if Rect2(Vector2.ZERO, viewport_size).grow(-24.0).has_point(screen_position):
			draw_circle(screen_position, 7.0, color)
			draw_circle(screen_position, 3.0, Color("fff2d5"))
			continue
		var direction: Vector2 = screen_position - screen_center
		if direction.length_squared() < 0.01:
			continue
		var distance_to_edge := minf(
			half_bounds.x / maxf(absf(direction.x), 0.001),
			half_bounds.y / maxf(absf(direction.y), 0.001)
		)
		var edge_position: Vector2 = screen_center + direction * distance_to_edge
		draw_set_transform(edge_position, direction.angle(), Vector2.ONE)
		draw_colored_polygon(
			PackedVector2Array([Vector2(10, 0), Vector2(-7, -6), Vector2(-7, 6)]),
			color
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(
			ThemeDB.fallback_font,
			edge_position + Vector2(10.0, 4.0),
			String(marker.get("name", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			180.0,
			10,
			color
		)
