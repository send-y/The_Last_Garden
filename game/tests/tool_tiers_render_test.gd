extends Node
const Content := preload("res://src/content/first_night_content.gd")
const Grid := preload("res://src/ui/inventory_grid.gd")
const Visual := preload("res://src/characters/character_visual.gd")
var failures := 0

func _ready() -> void: call_deferred("run")
func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	var content := Content.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 1024)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for row: int in range(4):
		for column: int in range(4):
			var kind: String = ["axe", "pickaxe", "hoe", "mallet"][column]
			var suffix: String = ["", "_stone", "_copper", "_steel"][row]
			var id := "core:" + kind + suffix
			var grid := Grid.new()
			grid.configure_grid(4, 3)
			grid.position = Vector2(column * 256, row * 256)
			viewport.add_child(grid)
			var placements: Array[Dictionary] = [{"item_id":id,"amount":1,"origin":Vector2i.ZERO,"rotation":0,"footprint":content.item_footprint(id),"icon_path":content.item_icon_path(id)}]
			grid.present(placements, content)
			var label := Label.new()
			label.position = grid.position + Vector2(4,194)
			label.text = id
			label.add_theme_font_size_override("font_size", 12)
			viewport.add_child(label)
			for facing: int in range(4):
				var visual := Visual.new()
				visual.position = grid.position + Vector2(32 + facing * 56, 232)
				visual.scale = Vector2.ONE * 1.6
				visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				viewport.add_child(visual)
				visual.set_pose([Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP][facing], 1, true)
				visual.set_held_item(id, load(content.item_icon_path(id)), content.item_tool_grip(id))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://../artifacts/tool-gameplay-2026-10-13/tool-tiers-inventory-and-hands.png")
	if rendered.save_png(out) != OK: failures += 1
	print("TOOL_TIERS_RENDER: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
