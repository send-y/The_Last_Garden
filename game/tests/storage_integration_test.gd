extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Localized := preload("res://src/localization/localized_text.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(true)
	var state: Dictionary = Simulation.create_new_state(2441)
	(state["inventory"] as Dictionary)["core:wood"] = 5
	Session.apply_debug_state(state, "storage integration", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	var world := main.get_node("World") as FirstNightWorld
	var player := main.get_node("Player") as PlayerController
	var target_cell := Vector2i(10, 10)
	var target_position := Content.cell_center(target_cell.x, target_cell.y)
	player.global_position = target_position
	Session.simulation.set_player_position(target_position)
	var created := Session.create_storage_zone(target_cell, target_cell)
	if not bool(created.get("success", false)):
		_fail("could not create the storage test zone")
		return
	world.select_at_world_position(target_position)
	world.interact_with_selection()
	await get_tree().process_frame
	if not hud.is_modal_open() or not Session.is_paused():
		_fail("interacting with a nearby storage cell must open a pausing modal")
		return
	var panel := hud.get_node("StoragePanel") as StoragePanel
	var rows := panel.get_node("Margin/Column/Scroll/Rows") as VBoxContainer
	var wood_row := _row_for_item(rows, "core:wood")
	if wood_row == null:
		_fail("storage panel is missing the wood row")
		return
	(wood_row.get_child(1) as Button).pressed.emit()
	await get_tree().process_frame
	if Session.get_inventory().get("core:wood", 0) != 0 or Session.get_storage_contents(target_cell).get("core:wood", 0) != 5:
		_fail("store button must transfer carried wood into the physical zone")
		return
	var close_button := panel.get_node("Margin/Column/Header/Close") as Button
	close_button.pressed.emit()
	await get_tree().process_frame
	if hud.is_modal_open() or Session.is_paused():
		_fail("closing storage must restore the previous unpaused state")
		return
	world.interact_with_selection()
	await get_tree().process_frame
	wood_row = _row_for_item(rows, "core:wood")
	(wood_row.get_child(2) as Button).pressed.emit()
	await get_tree().process_frame
	if Session.get_inventory().get("core:wood", 0) != 5 or not Session.get_storage_contents(target_cell).is_empty():
		_fail("take button must move contents back into the backpack")
		return
	print("PASS: storage selection, pause, and item transfers integrate with the HUD")
	get_tree().quit(0)


func _row_for_item(rows: VBoxContainer, item_id: String) -> HBoxContainer:
	var label_text := Localized.resolve(Content.new().item_label_key(item_id))
	for row_node: Node in rows.get_children():
		var row := row_node as HBoxContainer
		if row != null and String((row.get_child(0) as Label).text).begins_with(label_text):
			return row
	return null


func _fail(message: String) -> void:
	push_error("FAIL: %s" % message)
	get_tree().quit(1)
