extends RefCounted

const Catalog := preload("res://src/characters/npc_generation_catalog.gd")
const Generator := preload("res://src/characters/npc_profile_generator.gd")

static func create(sim, seed_value: int, arrival_cell: Vector2i) -> Dictionary:
	var serial := maxi(1, int(sim.state.get("next_npc_serial", 1)))
	var npc_id := "core:resident_%d" % serial
	while not sim.npc_catalog.get_definition(npc_id).is_empty() or sim.state.npcs.has(npc_id):
		serial += 1
		npc_id = "core:resident_%d" % serial
	var result := Generator.new().generate(seed_value, npc_id, Catalog.new().data)
	if not result.ok: return result
	var position: Vector2 = sim.content.cell_center(arrival_cell.x, arrival_cell.y)
	var registered: Dictionary = sim.npc_catalog.add(result.profile, {
		"position":[position.x,position.y],"target_cell":[arrival_cell.x,arrival_cell.y]})
	if not registered.ok: return registered
	sim.state.npcs[npc_id] = registered.state
	sim.state.npcs = sim.npc_catalog.normalize_states(sim.state.npcs, int(sim.state.seed))
	sim.housing.normalize(sim)
	sim.furniture.normalize(sim)
	sim.state.npc_profiles = sim.npc_catalog.to_save()
	sim.state.next_npc_serial = serial + 1
	return {"ok":true,"npc_id":npc_id,"profile":result.profile.duplicate(true)}
