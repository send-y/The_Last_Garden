extends Node
const Main := preload("res://src/main/main.tscn")
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
func _ready() -> void:
	Session.set_mechanics_lab_active(true)
	Session.apply_debug_state(Scenarios.build(Scenarios.RESIDENT_HOMES).state,"minute profile",true)
	var main := Main.instantiate()
	add_child(main)
	for _frame: int in range(3): await get_tree().process_frame
	var samples: Array[int] = []
	for _minute: int in range(15):
		var start := Time.get_ticks_usec()
		Session.advance_debug_minutes(1)
		samples.append(Time.get_ticks_usec()-start)
		await get_tree().process_frame
	print("SCENE_MINUTE us=",samples)
	var hud: Control = main.get_node("Hud/HudRoot")
	var start := Time.get_ticks_usec()
	hud.refresh()
	print("HUD_REFRESH us=",Time.get_ticks_usec()-start)
	start = Time.get_ticks_usec()
	main.get_node("World")._on_state_changed()
	print("WORLD_REFRESH us=",Time.get_ticks_usec()-start)
	get_tree().quit(0)
