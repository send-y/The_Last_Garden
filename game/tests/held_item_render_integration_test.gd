extends Node

const Visual := preload("res://src/characters/character_visual.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Placeholder := preload("res://src/items/item_placeholder_icon.gd")
const OUTPUT_DIR := "res://../artifacts/item-tools-2026-10-11/held-items-baseline"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Session.set_process(false)
	get_window().size = Vector2i(720, 700)
	get_window().content_scale_size = Vector2i(720, 700)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 700)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var content := Content.new()
	var ids: Array[String] = ["core:axe", "core:pickaxe", "core:hoe", "core:bucket", "core:wood", ""]
	var poses: Array[Vector2] = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	var visuals: Array[CharacterVisual] = []
	for row: int in range(ids.size()):
		for column: int in range(4):
			var visual := Visual.new()
			visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			visual.scale = Vector2.ONE * 3
			visual.position = Vector2(90 + column * 180, 63 + row * 110)
			viewport.add_child(visual)
			visual.set_pose(poses[column], 1, true)
			var path := content.item_icon_path(ids[row], {"charges": 2}) if not ids[row].is_empty() else ""
			var texture: Texture2D = load(path) if not path.is_empty() else (Placeholder.texture_for(ids[row]) if not ids[row].is_empty() else null)
			visual.set_held_item(ids[row], texture, content.item_tool_grip(ids[row]))
			visuals.append(visual)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var with_items := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	with_items.save_png(OUTPUT_DIR + "/held-items-four-directions.png")
	for visual: CharacterVisual in visuals:
		visual.set_held_item("", null)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var empty_hands := viewport.get_texture().get_image()
	for row: int in range(ids.size()):
		for column: int in range(4):
			var changed_pixels := 0
			for y: int in range(row * 110, row * 110 + 106):
				for x: int in range(column * 180, column * 180 + 178):
					if with_items.get_pixel(x, y) != empty_hands.get_pixel(x, y):
						changed_pixels += 1
			if (row < 5 and changed_pixels < 20) or (row == 5 and changed_pixels != 0):
				push_error("Held item rendering is missing or stale for %s direction %d (%d pixels)" % [ids[row], column, changed_pixels])
				get_tree().quit(1)
				return
	print("PASS: five actual held item textures are visible in all four walking directions; empty hand removes them")
	get_tree().quit(0)
