extends Node

const MainScene := preload("res://src/main/main.tscn")
const LabScenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")


func _ready() -> void:
	Session.set_mechanics_lab_active(true)
	var fresh_result: Dictionary = LabScenarios.build(
		LabScenarios.FRESH_START
	)
	Session.apply_debug_state(
		fresh_result["state"] as Dictionary,
		"inventory close test",
		false
	)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	var panel := hud.get_node("InventoryPanel") as InventoryPanel
	var close_button := panel.get_node(
		"ContentMargin/ContentColumn/HeaderRow/CloseButton"
	) as Button
	hud.toggle_inventory()
	await get_tree().process_frame

	var click_position: Vector2 = (
		close_button.get_global_rect().get_center()
	)
	_send_mouse_motion(click_position)
	await get_tree().process_frame
	_send_mouse_button(click_position, true)
	await get_tree().process_frame
	_send_mouse_button(click_position, false)
	await get_tree().process_frame

	if panel.visible:
		push_error(
			"Inventory close button did not close the modal. "
			+ "button_rect=%s" % close_button.get_global_rect()
		)
		get_tree().quit(1)
		return

	if Session.is_paused():
		push_error("Closing the inventory did not restore time.")
		get_tree().quit(1)
		return

	Session.set_paused(true, false)
	hud.toggle_inventory()
	await get_tree().process_frame
	click_position = close_button.get_global_rect().get_center()
	_send_mouse_motion(click_position)
	await get_tree().process_frame
	_send_mouse_button(click_position, true)
	await get_tree().process_frame
	_send_mouse_button(click_position, false)
	await get_tree().process_frame
	if panel.visible or not Session.is_paused():
		push_error(
			"Closing the inventory did not preserve an existing pause."
		)
		get_tree().quit(1)
		return

	print(
		"PASS: inventory close button closes the modal "
		+ "and preserves an existing pause"
	)
	get_tree().quit(0)


func _send_mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	get_viewport().push_input(event, true)


func _send_mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	get_viewport().push_input(event, true)
