extends Node

const Grid := preload("res://src/ui/inventory_grid.gd")
const Content := preload("res://src/content/first_night_content.gd")
const OUTPUT_DIR := "res://../artifacts/inventory-scale-2026-10-12/rotations"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	var stride := Grid.CELL_SIZE * 4 + 8
	var screen_size := Vector2i(Vector2.ONE * (stride * 4 + 24))
	get_window().size = screen_size
	get_window().content_scale_size = screen_size
	var colors: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]
	var marker := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in range(16):
		for x: int in range(16):
			marker.set_pixel(x, y, colors[(1 if x >= 8 else 0) + (2 if y >= 8 else 0)])
	var content := Content.new()
	var grids: Array[InventoryGrid] = []
	var tools: Array[String] = ["core:axe", "core:pickaxe", "core:hoe", "core:bucket"]
	for tool_index: int in range(tools.size()):
		for turns: int in range(4):
			var grid := Grid.new()
			grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			grid.position = Vector2(12 + turns * stride, 12 + tool_index * stride)
			grid._icon_cache["test:orientation"] = ImageTexture.create_from_image(marker)
			add_child(grid)
			grid.present([{
				"item_id": tools[tool_index], "stack_index": 0, "amount": 1,
				"origin": Vector2i.ZERO, "rotation": turns,
				"footprint": content.item_footprint(tools[tool_index], turns),
				"icon_path": "test:orientation",
			}])
			grids.append(grid)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rendered := get_viewport().get_texture().get_image()
	for index: int in range(grids.size()):
		var grid := grids[index]
		var turns := index % 4
		var bounds := grid._footprint_bounds(content.item_footprint(tools[index / 4], turns))
		var extent := Vector2(bounds.size) * Grid.CELL_SIZE - Vector2(10.0, 10.0)
		var source_extent := Vector2(extent.y, extent.x) if turns % 2 else extent
		# The square marker keeps its source proportions in every footprint.
		source_extent = Vector2.ONE * minf(source_extent.x, source_extent.y)
		var center := grid.global_position + Vector2(bounds.size) * Grid.CELL_SIZE * 0.5
		for quadrant: int in range(4):
			var offset := Vector2(-0.25 if quadrant % 2 == 0 else 0.25, -0.25 if quadrant < 2 else 0.25) * source_extent
			var sample := center + offset.rotated(turns * PI / 2.0)
			var pixel := rendered.get_pixel(int(sample.x), int(sample.y))
			var expected := colors[quadrant]
			if maxf(absf(pixel.r - expected.r), maxf(absf(pixel.g - expected.g), absf(pixel.b - expected.b))) > 0.04:
				_fail("%s turn %d quadrant %d does not follow its footprint: %s" % [tools[index / 4], turns, quadrant, pixel])
				return
	# Preview uses the same rotation while an item is held.
	var preview := grids[1]
	preview._dragged_placement_index = 0
	preview._drag_rotation = 1
	preview._drag_mouse_position = Vector2.ZERO
	preview._cursor_pointer_global = preview.global_position
	preview.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var preview_image := get_viewport().get_texture().get_image()
	var preview_size := Vector2(preview._footprint_bounds(content.item_footprint("core:axe", 1)).size) * Grid.CELL_SIZE
	var preview_center := preview.global_position + preview_size * 0.5
	var preview_sample := preview_center + (Vector2(-0.25, -0.25) * (minf(preview_size.x, preview_size.y) - 10)).rotated(PI / 2.0)
	var preview_pixel := preview_image.get_pixel(int(preview_sample.x), int(preview_sample.y))
	if preview_pixel.r < 0.6 or preview_pixel.g > 0.45 or preview_pixel.b > 0.45:
		_fail("held axe preview does not rotate its icon")
		return
	for index: int in range(grids.size()):
		var turns := index % 4
		var item_id := tools[index / 4]
		grids[index].present([{
			"item_id": item_id, "stack_index": 0, "amount": 1,
			"origin": Vector2i.ZERO, "rotation": turns,
			"footprint": content.item_footprint(item_id, turns),
			"icon_path": content.item_icon_path(item_id, {}),
		}])
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	get_viewport().get_texture().get_image().save_png(OUTPUT_DIR + "/tool-rotations.png")
	print("PASS: actual grid rendering rotates four tool icons in all orientations and in held preview")
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
