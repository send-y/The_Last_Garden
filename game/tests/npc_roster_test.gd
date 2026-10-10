extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _run() -> void:
	var sim := World.new()
	if not sim.has_method("create_generated_npc"):
		push_error("Missing dynamic roster facade")
		quit(1)
		return
	var mira: Dictionary = sim.state.npcs["core:first_neighbor"].duplicate(true)
	var a: Dictionary = sim.create_generated_npc(94, Vector2i(24, 29))
	var b: Dictionary = sim.create_generated_npc(95, Vector2i(25, 29))
	check(a.ok and b.ok and a.npc_id != b.npc_id, "Stable unique NPC IDs")
	check(sim.state.npcs["core:first_neighbor"] == mira, "Mira state preserved")
	var id: String = a.npc_id
	sim.state.npcs[id].known_facts = {"name":{"source":"conversation", "minute":42}}
	sim.state.npcs[id].personal_inventory["core:food"] = 4
	var saved := sim.export_state()
	var restored := World.new(JSON.parse_string(JSON.stringify(saved)))
	check(JSON.parse_string(JSON.stringify(restored.export_state())) == JSON.parse_string(JSON.stringify(saved)), "Complete serialized state round-trip")
	check(restored.npc_catalog.get_definitions().size() == 3, "All saved definitions restored")
	check(not restored.npc_catalog.add(saved.npc_profiles[id], {}).ok, "Duplicate rejected")
	var profile: Dictionary = restored.npc_catalog.get_profile(id)
	profile.name = "mutated query"
	check(restored.npc_catalog.get_profile(id).name != "mutated query", "Queries return copies")
	var future := saved.duplicate(true)
	future.npc_profiles[id].experience_id = "future:removed_component"
	var changed := World.new(future)
	check(changed.npc_catalog.get_profile(id).experience_id == "future:removed_component", "Saved profile is never regenerated")
	var old := World.create_new_state()
	old.version = 32
	old.npcs["core:first_neighbor"].talk_count = 8
	old.npcs["core:first_neighbor"].known = true
	var migrated := World.new(old)
	check(migrated.state.npcs["core:first_neighbor"].talk_count == 8, "Legacy Mira progress")
	check(migrated.state.npc_profiles.is_empty(), "Migration does not invent residents")
	var c: Dictionary = restored.create_generated_npc(96, Vector2i(26, 29))
	check(c.ok and c.npc_id != a.npc_id and c.npc_id != b.npc_id, "Counter survives loading")
	var ordinary := World.new()
	ordinary.advance_minutes(1440 + 1200)
	check(ordinary.get_day() == 3 and ordinary.state.npc_profiles.size() == 1,"Ordinary world morning triggers first procedural visitor")
	var visitor_id: String = ordinary.state.npc_profiles.keys()[0]
	check(ordinary.is_npc_visible(visitor_id),"Scheduled visitor is visible")
	ordinary.advance_minutes(3*1440)
	check(ordinary.state.npc_profiles.size() == 1,"Pending visitor prevents arrival flood")
	if failures == 0: print("PASS: persistent NPC roster, migration, identity, copies and counter")
	quit(0 if failures == 0 else 1)
