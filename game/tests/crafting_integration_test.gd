extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const LabScenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var scenario: Dictionary = LabScenarios.build(LabScenarios.WORKBENCH_CRAFTING)
	Session.set_mechanics_lab_active(true)
	if not Session.apply_debug_state(scenario.get("state", {}) as Dictionary, "crafting", false):
		_fail("could not install crafting lab state")
		return
	await get_tree().process_frame
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	var palette := hud.get_node("ConstructionPalette") as ConstructionPalette
	var mode_button := palette.get_node("Margin/Column/ModeButton") as Button
	mode_button.button_pressed = true
	await get_tree().process_frame
	_save_screenshot_argument("--hud-screenshot-path=")
	var cell := Vector2i(22, 29)
	hud.open_crafting(cell, Session.get_crafting_recipes("core:workbench"))
	await get_tree().process_frame
	_save_screenshot_argument("--screenshot-path=")
	if not hud.is_modal_open() or not Session.is_paused() or palette.visible:
		_fail("crafting menu must be modal and pause the simulation")
		return
	hud._on_recipe_pressed("core:saw_planks")
	await get_tree().process_frame
	if hud.is_modal_open() or Session.is_paused() or not palette.visible:
		_fail("choosing a recipe must close the menu and restore time")
		return
	var projects: Array = Session.get_crafting_projects()
	if projects.size() != 1:
		_fail("recipe button must create one deterministic crafting project")
		return
	print("PASS: crafting UI integration")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("FAIL: %s" % message)
	get_tree().quit(1)


func _save_screenshot_argument(prefix: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with(prefix):
			continue
		var path := argument.trim_prefix(prefix)
		get_viewport().get_texture().get_image().save_png(path)
