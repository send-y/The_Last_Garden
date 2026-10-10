extends Node

const Probe := preload("res://tests/fixtures/hoe_icon_probe.gd")
const Content := preload("res://src/content/first_night_content.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Session.set_process(false)
	var content := Content.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600, 180)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var probes: Array[InventoryGrid] = []
	for turns: int in range(4):
		var probe := Probe.new()
		probe.position = Vector2(10 + turns * 146, 10)
		viewport.add_child(probe)
		probe.present([{"item_id": "core:hoe", "stack_index": 0, "origin": Vector2i.ZERO, "rotation": turns,
			"footprint": content.item_footprint("core:hoe", turns), "icon_path": content.item_icon_path("core:hoe")}])
		probes.append(probe)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if not _fits_cells(image, probes, content):
		get_tree().quit(1)
		return
	for turns: int in range(4):
		var probe := probes[turns]
		probe._dragged_placement_index = 0
		probe._drag_rotation = turns
		probe._drag_mouse_position = Vector2.ZERO
		probe._cursor_pointer_global = probe.global_position
		probe.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not _fits_cells(viewport.get_texture().get_image(), probes, content):
		get_tree().quit(1)
		return
	print("PASS: actual hoe sprite fits its occupied cells in all four rotations, including transfer preview")
	get_tree().quit(0)

func _fits_cells(image: Image, probes: Array[InventoryGrid], content: FirstNightContent) -> bool:
	for turns: int in range(4):
		var footprint := content.item_footprint("core:hoe", turns)
		var probe := probes[turns]
		var bounds := probe._footprint_bounds(footprint)
		var outside_pixels := 0
		for y: int in range(bounds.size.y * 42):
			for x: int in range(bounds.size.x * 42):
				if footprint.has(Vector2i(x / 42, y / 42)):
					continue
				var point := Vector2i(probe.position) + Vector2i(x, y)
				if image.get_pixelv(point).a > 0.5:
					outside_pixels += 1
		if outside_pixels > 12:
			push_error("Actual hoe sprite extends outside occupied cells in rotation %d: %d pixels" % [turns, outside_pixels])
			return false
	return true
