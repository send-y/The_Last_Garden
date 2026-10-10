extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_window().size = Vector2i(1270, 640)
	await get_tree().process_frame
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	var palette := hud.get_node("ConstructionPalette") as ConstructionPalette
	var menu := palette.get_node("BuildMenu") as Control
	var hotbar: Control
	for child: Node in hud.get_children():
		if child is Control and is_equal_approx(child.size.x, 238.0) and is_equal_approx(child.size.y, 56.0):
			hotbar = child as Control
			break
	if hotbar == null:
		_fail("could not locate bottom-centered hotbar")
		return

	menu.show()
	await get_tree().process_frame
	var tasks := hud.get_children().filter(
		func(child: Node) -> bool:
			return child is TextureRect and (child as TextureRect).anchor_left == 1.0
	)
	if tasks.is_empty():
		_fail("right-anchored task panel was not created")
		return
	var task_panel := tasks[0] as Control
	if not _no_overlap(menu, hotbar):
		_fail("construction menu overlaps the hotbar at a wide aspect ratio")
		return
	if not _no_overlap(menu, task_panel):
		_fail("construction menu overlaps the task panel")
		return
	if _overlaps_bottom_feedback_labels(hud, menu):
		_fail("construction menu overlaps bottom feedback text")
		return
	if hud.size.x < 700.0 or hud.size.y < 350.0:
		_fail("wide-window viewport did not expand as expected: %s" % hud.size)
		return
	var button := palette.get_node("BuildButton") as Control
	if button.get_global_rect().end.x > hud.size.x or button.get_global_rect().end.y > hud.size.y:
		_fail("construction toggle moved outside the viewport")
		return
	var objective_label: Control
	for child: Node in hud.get_children():
		if child is Label and child.anchor_left == 1.0 and child.anchor_top == 0.0:
			objective_label = child as Control
			break
	if objective_label == null or objective_label.get_global_rect().end.x > hud.size.x:
		_fail("objective panel content moved outside the viewport")
		return
	print("PASS: responsive HUD layout (%s viewport)" % hud.size)
	get_tree().quit(0)


func _overlaps_bottom_feedback_labels(hud: Control, menu: Control) -> bool:
	for child: Node in hud.get_children():
		if child is Label and (child as Label).anchor_top == 1.0:
			if menu.get_global_rect().intersects((child as Control).get_global_rect()):
				return true
	return false


func _no_overlap(first: Control, second: Control) -> bool:
	return not first.get_global_rect().intersects(second.get_global_rect())


func _fail(message: String) -> void:
	push_error("FAIL: %s" % message)
	get_tree().quit(1)
