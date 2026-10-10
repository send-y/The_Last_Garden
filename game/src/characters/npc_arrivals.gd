extends RefCounted

const INVALID := Vector2i(-1,-1)

static func free_cell(sim, preferred: Vector2i) -> Vector2i:
	var occupied: Array[Vector2i] = [sim._world_position_to_cell(sim.get_player_position())]
	for npc: Dictionary in sim.state.npcs.values():
		if bool(npc.get("active",false)):
			occupied.append(sim._world_position_to_cell(Vector2(float(npc.position[0]),float(npc.position[1]))))
	for radius: int in range(12):
		for y: int in range(-radius,radius+1):
			for x: int in range(-radius,radius+1):
				if absi(x)+absi(y) != radius: continue
				var cell := preferred + Vector2i(x,y)
				if not occupied.has(cell) and sim.npc_autonomy.is_cell_walkable(cell): return cell
	return INVALID

static func arrive(sim, npc_id: String, cell: Vector2i) -> Dictionary:
	var npc: Dictionary = sim.state.npcs.get(npc_id,{})
	if npc.is_empty() or sim.npc_catalog.get_definition(npc_id).is_empty(): return {"ok":false,"reason_id":"core:no_npc"}
	if bool(npc.get("active",false)): return {"ok":false,"reason_id":"core:already_arrived"}
	var actual := free_cell(sim,cell)
	if actual == INVALID: return {"ok":false,"reason_id":"core:no_arrival_space"}
	var position: Vector2 = sim.content.cell_center(actual.x,actual.y)
	npc.position = [position.x,position.y]
	npc.target_cell = [actual.x,actual.y]
	npc.active = true
	npc["residency"] = "visitor"
	npc["arrival_minute"] = sim.get_elapsed_game_minutes()
	sim.event_emitted.emit({"type":"state_changed"})
	return {"ok":true,"npc_id":npc_id,"cell":[actual.x,actual.y]}

static func set_resident(sim, npc_id: String, resident: bool) -> Dictionary:
	var npc: Dictionary = sim.state.npcs.get(npc_id,{})
	if npc.is_empty() or not bool(npc.get("active",false)) or not bool(npc.get("known",false)):
		return {"ok":false,"reason_id":"core:unknown_npc"}
	npc.residency = "resident" if resident else "visitor"
	sim.event_emitted.emit({"type":"state_changed"})
	return {"ok":true,"npc_id":npc_id}

static func on_morning(sim) -> bool:
	# Provisional cadence from content, not settled game balance. One pending visitor at a time.
	var settings: Dictionary = preload("res://src/characters/npc_generation_catalog.gd").new().data.get("settings",{})
	var interval := maxi(1,int(settings.get("visit_interval_days",3)))
	if sim.get_day() < 3 or sim.get_day() % interval != 0: return false
	for npc: Dictionary in sim.state.npcs.values():
		if bool(npc.get("active",false)) and String(npc.get("residency","resident")) == "visitor": return false
	var cell := free_cell(sim,Vector2i(24,29))
	if cell == INVALID: return false
	var created: Dictionary = sim.create_generated_npc(int(sim.state.seed)+sim.get_day()*7919,cell)
	if not created.ok: return false
	return bool(arrive(sim,created.npc_id,cell).ok)
