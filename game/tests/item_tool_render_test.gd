extends Node
const Visual := preload("res://src/characters/character_visual.gd")
const Fixture := preload("res://tests/fixtures/item_tool_fixture.gd")
const OUT := "res://../artifacts/item-tools-2026-10-11/render"
var failures := 0
func _ready() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)
func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	var content := Fixture.catalog()
	var base := SubViewport.new()
	var variants := SubViewport.new()
	var actors: Array[CharacterVisual] = []
	for viewport: SubViewport in [base, variants]:
		viewport.size = Vector2i(384,384)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for row: int in range(4):
			for column: int in range(4):
				var kind: String = ["axe", "pickaxe", "hoe", "bucket"][row]
				var id := "core:" + kind if viewport == base else "test:" + kind + "_variant"
				var visual := Visual.new()
				visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				visual.position = Vector2(48 + column*96,48 + row*96)
				visual.scale = Vector2.ONE*2
				viewport.add_child(visual)
				visual.set_pose([Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2.UP][column],1,true)
				var texture: Texture2D = load(content.item_icon_path(id, {"charges": content.item_tool_capacity(id)}))
				if visual.get("_held_grip") == null:
					visual.set_held_item(id, texture)
				else:
					visual.call("set_held_item", id, texture, content.item_tool_grip(id))
				actors.append(visual)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var base_image := base.get_texture().get_image()
	var variant_image := variants.get_texture().get_image()
	check(base_image.get_data() == variant_image.get_data(), "Same assets and grips render equal in all four directions")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	base_image.save_png(OUT + "/base-four-directions.png")
	variant_image.save_png(OUT + "/variants-four-directions.png")
	if actors[0].get("_held_grip") != null:
		var texture: Texture2D = actors[0].get("_held_texture")
		actors[0].call("set_held_item", "core:axe", texture, "carry")
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		check(base.get_texture().get_image().get_data() != base_image.get_data(), "Grip change alone triggers redraw")
	for actor: CharacterVisual in actors: actor.set_held_item("", null)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(base.get_texture().get_image().get_data() == variants.get_texture().get_image().get_data(), "Clearing hand removes both model visuals")
	check(base.get_texture().get_image().get_data() != base_image.get_data(), "Actual tool pixels were drawn")
	print("ITEM_TOOL_RENDER: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
