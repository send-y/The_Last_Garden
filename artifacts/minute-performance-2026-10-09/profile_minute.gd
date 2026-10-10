extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for scenario: StringName in [Scenarios.FRESH_START,Scenarios.GENERATED_RESIDENTS,Scenarios.RESIDENT_HOMES]:
		var built: Dictionary = Scenarios.build(scenario)
		var sim := World.new(built.state)
		var samples: Array[int] = []
		for index: int in range(15):
			var started := Time.get_ticks_usec()
			sim.advance_minutes(1)
			samples.append(Time.get_ticks_usec()-started)
		print("MINUTE ",scenario," us=",samples," structures=",sim.state.structures.size()," npcs=",sim.state.npcs.size())
		var operations := {
			"housing":func(): return sim.housing.contexts(sim),
			"policy":func(): return sim.HomePolicy.rooms(sim),
			"work":func(): return sim.NpcPracticalWork.prepare(sim),
			"furniture":func(): return sim.furniture.npc_contexts(sim),
		}
		for op: String in operations:
			var started := Time.get_ticks_usec()
			operations[op].call()
			print("COMPONENT ",scenario," ",op," us=",Time.get_ticks_usec()-started)
	quit(0)
