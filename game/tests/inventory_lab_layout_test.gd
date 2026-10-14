extends Node

const Lab := preload("res://src/dev/mechanics_lab.tscn")
const OUT := "res://../artifacts/inventory-lab-fix-2026-10-12"
var failures := 0

class FrameProbe extends Node2D:
	var style: StyleBox
	var bounds: Rect2
	func _draw() -> void:
		draw_style_box(style, bounds)

func _ready() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)

func settle() -> void:
	for _frame: int in range(5): await get_tree().process_frame

func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	get_window().size = Vector2i(640,360)
	get_window().content_scale_size = Vector2i(640,360)
	var lab := Lab.instantiate() as MechanicsLab
	add_child(lab)
	await settle()
	var state := Session.get_state().duplicate(true)
	state.inventory = {}
	state.item_instances = [
		{"instance_id":"core:item_instance_000001", "item_id":"core:bucket", "state":{"charges":0}, "location":{"kind":"inventory", "id":""}},
		{"instance_id":"core:item_instance_000002", "item_id":"core:bucket", "state":{"charges":2}, "location":{"kind":"inventory", "id":""}},
	]
	state.inventory_layout = []
	state.hotbar_slots = ["core:item_instance_000001", "core:item_instance_000002", "", "", ""]
	state.next_item_instance_serial = 3
	Session.apply_debug_state(state, "lab layout screenshot regression", false)
	var hud := lab.get_node("Game/Hud/HudRoot") as FirstNightHud
	var panel := hud._inventory_panel
	hud.toggle_inventory()
	await settle()
	var original := Session.get_inventory_layout()
	for resolution: Vector2i in [Vector2i(640,360),Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1270,640)]:
		get_window().size = resolution
		await settle()
		check(not lab._lab_toggle_button.is_visible_in_tree() or not lab._lab_toggle_button.get_global_rect().intersects(panel.get_global_rect()), "Lab toggle does not cover backpack controls at %s" % resolution)
		check(Rect2(Vector2.ZERO,hud.size).encloses(panel.get_global_rect()), "Entire backpack fits at %s" % resolution)
		# A 4x4 backpack plus controls scales to fit the 360px logical viewport;
		# the previous unscaled 64px assertion also failed on the starting revision.
		check(panel._inventory_grid.get_global_transform_with_canvas().basis_xform(Vector2(64,0)).length() >= 48, "Cells remain readable while the whole panel fits at %s" % resolution)
		check(Session.get_inventory_layout() == original, "Layout unchanged at %s" % resolution)
		if resolution == Vector2i(1920,1080) and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
			get_viewport().get_texture().get_image().save_png(OUT + "/lab-backpack.png")
	if DisplayServer.get_name() != "headless": await check_frame(panel)
	hud.toggle_inventory()
	await settle()
	check(lab._lab_toggle_button.is_visible_in_tree(), "Closing backpack restores lab button")
	var key := InputEventKey.new()
	key.keycode = KEY_F2
	key.physical_keycode = KEY_F2
	key.pressed = true
	get_viewport().push_input(key,true)
	await settle()
	check(lab._lab_panel.visible, "F2 still opens the laboratory")
	print("INVENTORY_LAB_LAYOUT: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func check_frame(panel: InventoryPanel) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400,400)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var probe := FrameProbe.new()
	probe.style = panel.get_theme_stylebox("panel")
	probe.bounds = Rect2(Vector2(24,24),panel.size)
	viewport.add_child(probe)
	await settle()
	await RenderingServer.frame_post_draw
	var used := viewport.get_texture().get_image().get_used_rect()
	check(Rect2(used).encloses(probe.bounds.grow(-1)), "Painted frame encloses panel contents instead of leaving transparent gutters: %s vs %s" % [used,probe.bounds])
	viewport.queue_free()
