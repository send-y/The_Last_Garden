extends Node

const MainScene := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")
var samples: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	var state := Simulation.create_new_game_state()
	Session.apply_debug_state(state, "pickup profiling", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var connections := Session.state_changed.get_connections()
	for connection: Dictionary in connections:
		var original := connection["callable"] as Callable
		var target := original.get_object() as Node
		var label := "%s.%s" % [target.name, original.get_method()]
		Session.state_changed.disconnect(original)
		Session.state_changed.connect(func() -> void:
			var start := Time.get_ticks_usec()
			original.call()
			var records: Array = samples.get(label, [])
			records.append(Time.get_ticks_usec() - start)
			samples[label] = records
		)
	var ids := Session.simulation._create_resource_drops("profile", "core:wood", 12, Vector2(2000.0, 2000.0))
	var total_start := Time.get_ticks_usec()
	var totals: Array[int] = []
	for id: String in ids:
		var start := Time.get_ticks_usec()
		var result := Session.try_pickup_world_drop(id)
		totals.append(Time.get_ticks_usec() - start)
		if not bool(result.get("success", false)):
			push_error("profiling pickup rejected")
			get_tree().quit(1)
			return
	print("PICKUP synchronous usec: %s; batch usec: %d" % [totals, Time.get_ticks_usec() - total_start])
	for label: String in samples:
		print("CALLBACK %s usec: %s" % [label, samples[label]])
	var world := main.get_node("World") as FirstNightWorld
	var refresh_start := Time.get_ticks_usec()
	world._refresh_interactables()
	print("WORLD refresh interactables usec: %d" % (Time.get_ticks_usec() - refresh_start))
	var drops_start := Time.get_ticks_usec()
	world._sync_dropped_items()
	print("WORLD sync drops usec: %d" % (Time.get_ticks_usec() - drops_start))
	var frame_start := Time.get_ticks_usec()
	await get_tree().process_frame
	print("DEFERRED next process usec: %d" % (Time.get_ticks_usec() - frame_start))
	print("PROFILE complete; %d wood, %d trees, %d boulders" % [Session.simulation.get_item_count("core:wood"), Session.get_surface_trees().size(), Session.get_surface_boulders().size()])
	get_tree().quit(0)
