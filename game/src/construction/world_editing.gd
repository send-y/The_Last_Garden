extends RefCounted
const Content := preload("res://src/content/first_night_content.gd")
const DOOR := "core:wood_door"

static func execute(sim, action: String, cell: Vector2i, target_id: String, actor_id: String) -> Dictionary:
	if actor_id != "core:player": return _result(false,"world_edit.failure.actor")
	if action == "clear_bush": return _clear_bush(sim,target_id)
	if action not in ["dismantle","toggle_door"]: return _result(false,"world_edit.failure.target")
	if sim.get_player_position().distance_to(Content.cell_center(cell.x,cell.y)) > Content.INTERACTION_RANGE:
		return _result(false,"interaction.failure.too_far")
	var structure: Dictionary = sim._find_structure([cell.x,cell.y])
	if structure.is_empty(): return _result(false,"world_edit.failure.target")
	if action == "toggle_door":
		if String(structure.building_id) != DOOR: return _result(false,"world_edit.failure.target")
		var opening := not bool(structure.get("open",true))
		if not opening and sim._is_actor_in_cell(structure.cell): return _result(false,"world_edit.failure.occupied")
		structure.open = opening
		sim.event_emitted.emit({"type":"state_changed"})
		return _result(true,"world_edit.door.opened" if opening else "world_edit.door.closed")
	# Reserved recipe inputs must not be silently lost with their workbench.
	if not sim._find_crafting_project(structure.cell).is_empty(): return _result(false,"world_edit.failure.busy")
	var origin := Vector2i(int(structure.cell[0]),int(structure.cell[1]))
	if sim.building_catalog.is_floor(String(structure.building_id)) and not sim.get_storage_contents(origin).is_empty():
		return _result(false,"world_edit.failure.storage")
	if sim._is_actor_in_blueprint(structure): return _result(false,"world_edit.failure.occupied")
	if not sim.prepare_player_work(): return _result(false,"furniture.failure.approach")
	if sim.get_player_position().distance_to(Content.cell_center(cell.x,cell.y)) > Content.INTERACTION_RANGE:
		return _result(false,"interaction.failure.too_far")
	var refund: Dictionary = {}
	var materials: Dictionary = sim.building_catalog.get_material_cost(String(structure.building_id))
	for item: String in materials:
		var amount := floori(float(materials[item])*0.5)
		if amount > 0: refund[item] = amount
	var place_id := "%s@%d,%d" % [structure.building_id,origin.x,origin.y]
	for id: String in sim.state.sleep_assignments:
		if sim.state.sleep_assignments[id] == place_id: sim.state.sleep_assignments[id] = ""
	sim.state.structures.erase(structure)
	sim._sync_structure_navigation()
	sim.housing.normalize(sim)
	sim.furniture.normalize(sim)
	sim._spend_player_work_energy()
	var overflow: Dictionary = sim._return_cancelled_materials(refund,origin)
	sim.event_emitted.emit({"type":"state_changed"})
	var result := _result(true,"world_edit.dismantled")
	result.refund = refund
	result.dropped = overflow
	return result

static func _clear_bush(sim, target_id: String) -> Dictionary:
	var id: String = sim.content.normalize_object_id(target_id)
	var target: Dictionary = sim._resolve_interaction_target(id)
	if String(target.get("kind","")) != "food" or not sim._food_object_ids.has(id) or bool(sim.state.removed_bushes.get(id,false)):
		return _result(false,"world_edit.failure.target")
	if sim.get_player_position().distance_to(target.position) > Content.INTERACTION_RANGE:
		return _result(false,"interaction.failure.too_far")
	var tool: Dictionary = sim.get_actor_tool("core:player")
	if String(tool.get("item_id","")) != "core:axe" or String(tool.get("instance_id","")).is_empty():
		return _result(false,"world_edit.failure.axe")
	if not sim.prepare_player_work(): return _result(false,"furniture.failure.approach")
	if sim.get_player_position().distance_to(target.position) > Content.INTERACTION_RANGE:
		return _result(false,"interaction.failure.too_far")
	sim.state.removed_bushes[id] = true
	sim.state.farming.berry_ready_at.erase(id)
	sim._spend_player_work_energy()
	sim.event_emitted.emit({"type":"state_changed"})
	return _result(true,"world_edit.bush.cleared")

static func open_for_npcs(sim) -> bool:
	# Doors are traversable by pathfinding: a resident opens the leaf before passing.
	var changed := false
	for structure: Dictionary in sim.state.structures:
		if String(structure.building_id) != DOOR or bool(structure.get("open",true)): continue
		var center := Content.cell_center(int(structure.cell[0]),int(structure.cell[1]))
		for id: String in sim.state.npcs:
			if not bool(sim.state.npcs[id].get("active",false)): continue
			if sim.get_npc_position(id,Vector2.ZERO).distance_to(center) <= 33.0:
				structure.open = true
				changed = true
				break
	return changed

static func _result(success: bool, key: String) -> Dictionary:
	return {"success":success,"changed":success,"message_key":key,"message_args":{}}
