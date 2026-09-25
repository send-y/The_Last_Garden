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
	var inventory_grid := panel.get_node(
		"ContentMargin/ContentColumn/GridCenter/InventoryGrid"
	) as InventoryGrid
	hud.toggle_inventory()
	await get_tree().process_frame
	panel.present(
		"Рюкзак",
		"Вес 2.0/24 кг",
		[
			{
				"item_id": "test:wood",
				"label": "Древесина",
				"amount": 2,
				"total_weight": 2.0,
				"origin": Vector2i.ZERO,
				"footprint": [Vector2i.ZERO],
				"icon_path": "",
			},
		]
	)
	await get_tree().process_frame

	var item_position := (
		inventory_grid.get_global_rect().position
		+ Vector2(10.0, 10.0)
	)
	_send_mouse_motion(item_position)
	await get_tree().process_frame
	_send_mouse_button(item_position, true)
	await get_tree().process_frame
	_send_mouse_button(item_position, false)
	await get_tree().process_frame
	if not panel.get_details_text().contains("Древесина"):
		push_error(
			"Inventory item selection did not update details. "
			+ "grid_rect=%s item_position=%s hovered=%s details=%s" % [
				inventory_grid.get_global_rect(),
				item_position,
				get_viewport().gui_get_hovered_control(),
				panel.get_details_text(),
			]
		)
		get_tree().quit(1)
		return

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
		"PASS: inventory selection and close button work, "
		+ "including pause-state preservation"
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
