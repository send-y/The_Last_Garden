extends Node
const World := preload("res://src/simulation/world_simulation.gd")
const View := preload("res://src/world/interactable_view.gd")
var failures := 0
func _ready() -> void: call_deferred("run")
func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	Session._is_paused = false
	var state := World.create_new_game_state()
	var npc: Dictionary = state.npcs["core:first_neighbor"]
	npc.active = true
	npc.known = true
	npc.position = [560.0,976.0]
	Session._replace_simulation(state)
	var view := View.new()
	view.configure({"id":"core:first_neighbor","kind":"npc","label_key":"npc.first_neighbor.name","position":Vector2(560,976),"color":Color.WHITE})
	add_child(view)
	view.set_physics_process(false)
	var idle_frames := 0
	for step: int in range(4):
		view._target_position = Vector2(560+32*(step+1),976)
		for frame: int in range(80):
			var before := view.position
			view._physics_process(1.0/60.0)
			if before.is_equal_approx(view.position): idle_frames += 1
	if idle_frames > 4:
		failures += 1
		print("FAIL: Continuous walk waits between logical minutes: ",idle_frames," idle frames")
	print("NPC_MOTION_SAMPLE: idle_seconds=",float(idle_frames)/60.0," total_seconds=",320.0/60.0)
	print("PLAYTEST_NPC_MOTION: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
