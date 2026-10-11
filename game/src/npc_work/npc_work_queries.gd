extends RefCounted

# Derived queries owned by one simulation. Never stored in NPC/save data.
const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")
var enabled := true
var _navigation: RefCounted
var _navigation_revision := -1
var _actors: Dictionary = {}

func work_cell(sim, npc: Dictionary, target: Vector2i) -> Vector2i:
	var from: Vector2i = sim._world_position_to_cell(sim.get_npc_position(String(npc.id),Vector2.ZERO))
	if not enabled:
		return sim.npc_autonomy.find_construction_work_cell(target,from,sim._world_position_to_cell(sim.get_player_position()))
	if _navigation != sim.npc_autonomy or _navigation_revision != sim.npc_autonomy.navigation_revision:
		_navigation = sim.npc_autonomy
		_navigation_revision = sim.npc_autonomy.navigation_revision
		_actors.clear()
	var id := String(npc.id)
	if not _actors.has(id) or _actors[id].from != from:
		# Keep queries only for each resident's current cell, not their travel history.
		_actors[id] = {"from":from,"targets":{}}
	var targets: Dictionary = _actors[id].targets
	if targets.has(target):
		if Diagnostic.enabled: Diagnostic.counters["work_approach_cache_hits"] = int(Diagnostic.counters.get("work_approach_cache_hits",0))+1
		return targets[target]
	if Diagnostic.enabled: Diagnostic.counters["work_approach_cache_misses"] = int(Diagnostic.counters.get("work_approach_cache_misses",0))+1
	var result: Vector2i = sim.npc_autonomy.find_construction_work_cell(target,from,sim._world_position_to_cell(sim.get_player_position()))
	targets[target] = result
	return result

func prune_inactive(sim) -> void:
	for id: String in _actors.keys():
		if not bool(sim.state.npcs.get(id,{}).get("active",false)): _actors.erase(id)
