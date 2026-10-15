extends Node

func _ready() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	var state := preload("res://src/dev/package_d_scenarios.gd").day_three_state()
	Session.apply_debug_state(state,"Garden Bridge isolated host",true)
	var game := preload("res://src/main/main.tscn").instantiate()
	game.name = "Game"; add_child(game)
	game.get_node("Player").set_physics_process(false)
	var cell: Array = Session.simulation.state.storage_zones[0].cells[0]
	Session.simulation.set_player_position(Session.simulation.content.cell_center(int(cell[0]),int(cell[1])))
	game.get_node("Hud/HudRoot").open_storage(Vector2i(int(cell[0]),int(cell[1])))
	for i: int in range(8): await get_tree().process_frame
	push_warning("GARDEN_BRIDGE_TEST_MARKER")
	if OS.get_cmdline_user_args().has("--bridge-test-no-render"): RenderingServer.render_loop_enabled = false
	var before := JSON.stringify(Session.simulation.export_state())
	print("BRIDGE_HOST_READY")
	get_tree().create_timer(12).timeout.connect(func() -> void:
		var unchanged := before==JSON.stringify(Session.simulation.export_state())
		print("BRIDGE_READ_ONLY_PASS" if unchanged else "FAIL: diagnostics changed full simulation state")
		get_tree().quit(0 if unchanged else 1)
	)
