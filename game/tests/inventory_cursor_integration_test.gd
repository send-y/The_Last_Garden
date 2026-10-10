extends Node

const Main := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	get_window().size = Vector2i(640, 360)
	get_window().content_scale_size = Vector2i(640, 360)
	var state := Simulation.create_new_state()
	state.inventory["core:wood"] = 3
	Session.apply_debug_state(state, "cursor test", false)
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	hud.toggle_inventory()
	await get_tree().process_frame
	var grid := hud._inventory_panel._inventory_grid
	var before := Session.get_inventory_layout()
	var placement: Dictionary = grid._placements[0]
	var point: Vector2 = grid.get_global_transform_with_canvas() * (Vector2(placement.origin) * 42 + Vector2(18, 18))
	_click(point)
	await get_tree().process_frame
	if not grid.is_holding_item():
		_fail("A single click must attach the item to the cursor after releasing LMB")
		return
	if Session.get_inventory_layout() != before:
		_fail("Cursor pickup changed the saved layout before placement")
		return
	var cursor := grid.get("_cursor_visual") as Control
	var origin := cursor.position
	_motion(point + Vector2(13, 7))
	await get_tree().process_frame
	if not cursor.position.is_equal_approx(origin + Vector2(13, 7)):
		_fail("The held image snaps instead of following each pixel of cursor movement")
		return
	_motion(Vector2(35, 32))
	await get_tree().process_frame
	if not cursor.visible or cursor.get_global_rect().get_center().distance_to(Vector2(35, 32)) > 35:
		_fail("The held image did not follow the pointer outside its source panel")
		return
	await _capture("cursor-outside-backpack.png")
	var target: Vector2 = grid.get_global_transform_with_canvas() * Vector2(147, 147)
	_click(target)
	await get_tree().process_frame
	if grid.is_holding_item() or Session.get_inventory_layout()[0].origin != [3, 3]:
		_fail("Second click did not place the stack in the target cell")
		return
	_click(target)
	_click(Vector2(35, 32), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	if grid.is_holding_item() or Session.get_inventory_layout()[0].origin != [3, 3]:
		_fail("Right click did not cancel cursor transfer while preserving the original layout")
		return
	hud.toggle_inventory()
	var storage := hud._storage_panel
	storage.present(Vector2i(10, 10), Content.new())
	storage.show()
	await get_tree().process_frame
	await get_tree().process_frame
	if not Rect2(Vector2(3, 3), Vector2(634, 354)).encloses(storage.get_global_rect()):
		_fail("The storage menu extends outside the 640x360 screen: %s" % storage.get_global_rect())
		return
	await _capture("compact-storage.png")
	storage.hide()
	var content := Content.new()
	hud._crafting_panel.present(Session.get_crafting_recipes("core:workbench"), content)
	hud._marker_panel.call("show_creation")
	hud._marker_panel.hide()
	for window_size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1270, 640)]:
		get_window().size = window_size
		await get_tree().process_frame
		await get_tree().process_frame
		for panel: Control in [hud._inventory_panel, hud._crafting_panel, storage, hud._farming_panel, hud._marker_panel]:
			panel.show()
			await get_tree().process_frame
			await get_tree().process_frame
			if not Rect2(Vector2.ZERO, hud.size).encloses(panel.get_global_rect()):
				_fail("%s exceeds the screen at %s: %s" % [panel.name, window_size, panel.get_global_rect()])
				return
			panel.hide()
	print("PASS: one-click cursor, smooth movement outside panel, placement/cancellation, all five compact menus fit small/default/wide screens")
	get_tree().quit(0)

func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var output := "res://../artifacts/cursor-menus-2026-10-08"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_viewport().get_texture().get_image().save_png(output + "/" + file_name)

func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_motion(point)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = point
		event.global_position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)

func _motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
