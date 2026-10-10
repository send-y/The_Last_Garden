extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(true)
	var state: Dictionary = Simulation.create_new_state(3991)
	var structures: Array = []
	for y: int in range(10, 14):
		for x: int in range(10, 14):
			if x != 10 and x != 13 and y != 10 and y != 13:
				continue
			var door := x == 11 and y == 10
			structures.append({
				"building_id": "core:wood_door" if door else "core:wood_wall",
				"cell": [x, y],
			})
	state["structures"] = structures
	if not Session.apply_debug_state(state, "room designation UI", true):
		_fail("could not install the enclosed-room fixture")
		return
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var palette := main.get_node("Hud/HudRoot/ConstructionPalette") as ConstructionPalette
	var cursor := main.get_node("ConstructionCursor") as ConstructionCursor
	palette._select_category("other")
	await get_tree().process_frame
	var storage_button: Button
	for child: Node in palette.get_node("BuildMenu/Margin/Column/Scroll/Choices").get_children():
		if child is Button and (child as Button).text == "Назначить склад":
			storage_button = child as Button
			break
	if storage_button == null:
		_fail("construction palette does not expose the warehouse room plan")
		return
	storage_button.pressed.emit()
	palette._on_mode_toggled(true)
	cursor.cell_selected.emit(Vector2i(11, 11))
	if Session.get_room_assignments().size() != 1:
		_fail("clicking inside an eligible room did not apply its warehouse plan")
		return
	if Session.get_storage_zones().size() != 1:
		_fail("warehouse designation did not activate storage on its interior cells")
		return
	cursor.cell_cancel_requested.emit(Vector2i(11, 11))
	if not Session.get_room_assignments().is_empty() or not Session.get_storage_zones().is_empty():
		_fail("right-click did not clear an empty room designation")
		return
	print("PASS: room plan menu, click designation, and right-click removal")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("FAIL: %s" % message)
	get_tree().quit(1)
