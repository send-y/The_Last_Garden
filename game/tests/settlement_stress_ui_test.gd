extends Node

const Lab := preload("res://src/dev/settlement_stress.tscn")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	Session.set_process(false)
	var lab = Lab.instantiate()
	add_child(lab)
	for _index: int in range(3): await get_tree().process_frame
	check(lab._active_scenario_id == &"settlement_stress", "F6 opens the thirty-resident scenario by default")
	check(lab._stress_participants.size() == 30, "Laboratory holds all thirty participants")
	var world = lab.get_node("Game/World")
	var views := 0
	for interactable in world._interactables:
		if interactable.kind == "npc" and interactable.visible: views += 1
	check(views == 30, "All thirty residents have visible live world views")
	var camera: Camera2D = lab.get_node("Game/Player/Camera2D")
	lab._request_help_button.pressed.emit()
	check(camera.top_level and camera.zoom.x < 0.5, "Overview button shows the whole settlement")
	lab._request_help_button.pressed.emit()
	check(not camera.top_level and camera.zoom == Vector2.ONE, "Overview returns to the player camera")
	check(not Session.save_game(false), "Laboratory cannot overwrite the ordinary player save")
	var tool_count := 0
	for stored: Dictionary in Session.simulation.state.storage_items:
		if stored.has("instance_id"): tool_count += 1
	check(tool_count == 120, "Scene reload keeps the real shared tool pool")
	# Reload signals must not run old stress rules on the incoming ordinary world.
	var incoming: Dictionary = {}
	var capture := func(): incoming["state"] = Session.simulation.export_state()
	Session.state_reloaded.connect(capture)
	lab._set_stress_overview(true)
	select_scenario(lab,&"resident_homes")
	check(Session.simulation.export_state() == incoming.state, "Leaving stress preserves the incoming ordinary population and finite stock")
	check(not camera.top_level and camera.zoom == Vector2.ONE, "Leaving stress restores the ordinary player camera")
	check(lab._stress_participants.is_empty(), "Ordinary houses disable the stress population controller")
	var planks := 0
	var residents := 0
	for stored: Dictionary in Session.simulation.state.storage_items:
		if String(stored.item_id) == "core:plank": planks += int(stored.amount)
	for npc: Dictionary in Session.simulation.state.npcs.values():
		if bool(npc.active): residents += 1
	check(planks == 70 and residents == 3, "Ordinary houses retain seventy planks and three active residents")
	var before_tick: Dictionary = Session.simulation.export_state()
	Session.time_changed.emit()
	check(Session.simulation.export_state() == before_tick, "Ordinary time notification does not refill its warehouse")
	if failures > 0:
		print("SETTLEMENT_STRESS_UI: %d failures" % failures)
		get_tree().quit(1)
		return
	select_scenario(lab,&"settlement_stress")
	check(Session.simulation.export_state() == incoming.state, "Entering stress preserves its incoming prepared world")
	var depleted: Dictionary = {}
	for stored: Dictionary in Session.simulation.state.storage_items:
		if String(stored.item_id) == "core:plank":
			depleted = stored
			break
	check(not depleted.is_empty(), "Returning to stress has real replenish-able materials")
	if not depleted.is_empty():
		depleted.amount = 1
		Session.time_changed.emit()
		check(int(depleted.amount) > 1, "Returning to stress re-enables replenishment on subsequent time notifications")
	lab._reset_scenario()
	check(Session.simulation.export_state() == incoming.state, "Resetting stress does not apply the old controller during reload")
	select_scenario(lab,&"fresh_start")
	check(Session.simulation.export_state() == incoming.state, "Leaving stress for a fresh world preserves its starter supplies and NPC state")
	Session.state_reloaded.disconnect(capture)
	print("SETTLEMENT_STRESS_UI: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func select_scenario(lab, scenario_id: StringName) -> void:
	for index: int in range(lab._scenario_select.item_count):
		if StringName(lab._scenario_select.get_item_metadata(index)) == scenario_id:
			lab._scenario_select.select(index)
			lab._scenario_select.item_selected.emit(index)
			return
	check(false,"Requested laboratory scenario is available")
