extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func execute_npc_work_request(sim, command: Dictionary) -> Dictionary:
	var npc_autonomy: NpcAutonomy = sim.npc_autonomy
	var validation: Dictionary = (
		NpcWorkRequestValidatorScript.validate_construction_help(command)
	)
	if not bool(validation.get("success", false)):
		return sim._emit_work_request_result(false,
			String(validation.get("reason_id", "core:invalid_request")),
			"npc.work_request.failure.invalid"
		)

	var npc_id: String = String(validation.get("npc_id", ""))
	var npcs: Dictionary = sim._npcs_mutable()
	if not npcs.has(npc_id):
		return sim._emit_work_request_result(false,
			"core:missing_npc",
			"npc.work_request.failure.missing_npc"
		)

	var npc: Dictionary = npcs[npc_id] as Dictionary
	if not bool(npc.get("active", false)):
		return sim._emit_work_request_result(false,
			"core:missing_npc",
			"npc.work_request.failure.missing_npc"
		)
	if not bool(npc.get("known", false)):
		return sim._emit_work_request_result(false,
			"core:not_acquainted",
			"npc.work_request.failure.not_acquainted"
		)
	if (
		sim.get_player_position().distance_to(sim.get_npc_position(npc_id, Vector2.ZERO))
		> FirstNightContent.INTERACTION_RANGE
	):
		return sim._emit_work_request_result(false,
			"core:too_far",
			"npc.work_request.failure.too_far"
		)
	if not (npc.get("work_commitment", {}) as Dictionary).is_empty():
		return sim._emit_work_request_result(false,
			"core:npc_busy",
			"npc.work_request.failure.busy"
		)

	var target_cell_data: Array = validation.get("target_cell", []) as Array
	var blueprint: Dictionary = sim._find_blueprint(target_cell_data)
	if blueprint.is_empty():
		return sim._emit_work_request_result(false,
			"core:missing_blueprint",
			"npc.work_request.failure.missing_blueprint"
		)

	var needs: Dictionary = npc.get("needs", {}) as Dictionary
	if (
		float(needs.get("hunger", 0.0))
		< npc_autonomy.CONSTRUCTION_REQUEST_MIN_HUNGER
	):
		return sim._emit_work_request_result(false,
			"core:npc_hungry",
			"npc.work_request.failure.hungry"
		)
	if (
		float(needs.get("energy", 0.0))
		< npc_autonomy.CONSTRUCTION_REQUEST_MIN_ENERGY
	):
		return sim._emit_work_request_result(false,
			"core:npc_tired",
			"npc.work_request.failure.tired"
		)

	if float(needs.get("restedness", 100)) < 25:
		return sim._emit_work_request_result(false, "core:npc_sleepy", "needs.refusal.sleepy")
	var psychology: Dictionary = npc.get("psychology", {})
	if float(psychology.get("mood", 60)) < 25 or float(psychology.get("wellbeing", 60)) < 30:
		return sim._emit_work_request_result(false, "core:npc_unwell", "needs.refusal.unwell")

	var target_cell := Vector2i(
		int(target_cell_data[0]),
		int(target_cell_data[1])
	)
	var npc_cell: Vector2i = _world_position_to_cell(
		sim.get_npc_position(npc_id, Vector2.ZERO)
	)
	var player_cell: Vector2i = _world_position_to_cell(sim.get_player_position())
	var work_cell: Vector2i = npc_autonomy.find_construction_work_cell(
		target_cell,
		npc_cell,
		player_cell
	)
	if work_cell == npc_autonomy.INVALID_CELL:
		return sim._emit_work_request_result(false,
			"core:unreachable_work",
			"npc.work_request.failure.unreachable"
		)

	if not sim._blueprint_has_all_materials(blueprint):
		var npc_inventory: Dictionary = npc.get("personal_inventory", {}) as Dictionary
		var transfer: Dictionary = sim._calculate_material_transfer(
			blueprint,
			npc_inventory
		)
		if not sim._transfer_completes_blueprint(blueprint, transfer):
			return sim._emit_work_request_result(false,
				"core:required_materials_missing",
				"npc.work_request.failure.materials_missing"
			)
		sim._apply_material_transfer(blueprint, npc_inventory, transfer)
		npc["personal_inventory"] = npc_inventory

	npc["work_commitment"] = {
		"commitment_id": NpcWorkRequestScript.HELP_BUILD_COMMITMENT_ID,
		"requester_id": NpcWorkRequestScript.PLAYER_ACTOR_ID,
		"target_cell": target_cell_data.duplicate(),
		"work_cell": [work_cell.x, work_cell.y],
		"building_id": String(blueprint.get("building_id", "")),
		"accepted_minute": sim.get_minute_of_day(),
		"progress_minutes": 0,
		"required_minutes": int(blueprint.get("required_work_minutes", 1)),
		"resume_activity_id": String(
			npc.get("activity_id", npc_autonomy.ACTIVITY_MORNING)
		),
	}
	npc["target_cell"] = [work_cell.x, work_cell.y]

	return sim._emit_work_request_result(true,
		"core:request_accepted",
		"npc.work_request.accepted",
		true
	)


static func _apply_autonomy_effects(sim, effects: Array) -> bool:
	var npc_autonomy: NpcAutonomy = sim.npc_autonomy
	var changed: bool = false
	for effect_value: Variant in effects:
		if typeof(effect_value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_value as Dictionary
		if String(effect.get("type","")) == "sit_for_rest":
			var worker: Dictionary = sim.state.npcs.get(String(effect.get("npc_id","")),{})
			if not worker.is_empty():
				changed = sim.furniture.sit_npc(sim,worker,effect.seat,"rest") or changed
			continue
		if String(effect.get("type", "")) == "advance_initiative":
			changed = sim.NpcPracticalWork.fulfil(sim, effect) or changed
			continue
		if String(effect.get("type", "")) == "consume_meal":
			changed = sim.NpcFoodSupply.fulfil(sim, effect) or changed
			continue
		if String(effect.get("type", "")) != "advance_construction_work":
			continue
		var cell_data: Array = effect.get("target_cell", []) as Array
		if cell_data.size() != 2:
			continue
		var work_result: Dictionary = sim._advance_blueprint_work(cell_data,String(effect.get("npc_id","")))
		if bool(work_result.get("changed", false)):
			changed = true
			var worker: Dictionary = sim.state.npcs.get(String(effect.get("npc_id", "")), {})
			if not worker.is_empty():
				sim.needs.spend_work(worker.needs)
		if String(work_result.get("reason_id", "")) != "core:structure_completed":
			continue

		var npc_id: String = String(effect.get("npc_id", ""))
		var npcs: Dictionary = sim._npcs_mutable()
		if npcs.has(npc_id):
			var npc: Dictionary = npcs[npc_id] as Dictionary
			var commitment: Dictionary = npc.get("work_commitment", {}) as Dictionary
			if String(work_result.get("building_id", "")) == "core:wood_wall":
				sim._record_first_shared_wall_memory(npc,
					cell_data,
					int(effect.get("minute", sim.get_minute_of_day()))
				)
			npc["work_commitment"] = {}
			npc["activity_id"] = String(
				commitment.get("resume_activity_id", npc_autonomy.ACTIVITY_MORNING)
			)
			npc["activity_started_minute"] = sim.get_minute_of_day()
			npc["moving"] = false
	return changed


static func _record_first_shared_wall_memory(sim,
	npc: Dictionary,
	cell_data: Array,
	event_minute: int
) -> bool:
	var memories: Array = npc.get("memories", []) as Array
	if NpcMemoryScript.has_memory(
		memories,
		NpcMemoryScript.MEMORY_FIRST_SHARED_WALL_ID
	):
		return false
	var target_cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
	memories.append(NpcMemoryScript.create_first_shared_wall(
		sim.get_day(),
		event_minute,
		target_cell
	))
	npc["memories"] = memories
	sim.needs.add_effect(npc, "shared_wall", sim.get_elapsed_game_minutes())
	return true


static func _emit_work_request_result(sim,
	success: bool,
	reason_id: String,
	message_key: String,
	changed: bool = false
) -> Dictionary:
	var result: Dictionary = sim._emit_result(success, message_key, changed)
	result["reason_id"] = reason_id
	return result


static func get_npcs(sim) -> Dictionary:
	return sim._npcs_mutable().duplicate(true)


static func is_npc_visible(sim, npc_id: String) -> bool:
	var npc_catalog: NpcCatalog = sim.npc_catalog
	return npc_catalog.is_visible(sim.get_npcs(), npc_id)


static func get_npc_position(sim, npc_id: String, fallback: Vector2) -> Vector2:
	var npc_catalog: NpcCatalog = sim.npc_catalog
	return npc_catalog.get_position(sim.get_npcs(), npc_id, fallback)


static func get_npc_appearance(sim, npc_id: String) -> Dictionary:
	var npc_catalog: NpcCatalog = sim.npc_catalog
	return npc_catalog.get_appearance(sim.get_npcs(), npc_id)


static func get_npc_activity_id(sim, npc_id: String) -> String:
	var npc: Dictionary = sim.get_npcs().get(npc_id, {}) as Dictionary
	return String(npc.get("activity_id", NpcAutonomyScript.ACTIVITY_ARRIVING))


static func get_npc_activity_key(sim, npc_id: String) -> String:
	var npc_autonomy: NpcAutonomy = sim.npc_autonomy
	return npc_autonomy.get_activity_key(sim.get_npc_activity_id(npc_id))


static func get_npc_needs(sim, npc_id: String) -> Dictionary:
	var npc: Dictionary = sim.get_npcs().get(npc_id, {}) as Dictionary
	return (npc.get("needs", {}) as Dictionary).duplicate(true)


static func get_npc_personal_food(sim, npc_id: String) -> int:
	var npc: Dictionary = sim.get_npcs().get(npc_id, {}) as Dictionary
	var inventory: Dictionary = npc.get("personal_inventory", {}) as Dictionary
	return int(inventory.get(FirstNightContent.FOOD_ID, 0))


static func get_npc_work_commitment(sim, npc_id: String) -> Dictionary:
	var npc: Dictionary = sim.get_npcs().get(npc_id, {}) as Dictionary
	return (npc.get("work_commitment", {}) as Dictionary).duplicate(true)


static func get_npc_memories(sim, npc_id: String) -> Array:
	var npc: Dictionary = sim.get_npcs().get(npc_id, {}) as Dictionary
	return (npc.get("memories", []) as Array).duplicate(true)


static func get_npc_relationship_to_player(sim, npc_id: String) -> Dictionary:
	return NpcMemoryScript.relationship_from_memories(
		sim.get_npc_memories(npc_id)
	)


static func get_npc_target_cell(sim, npc_id: String) -> Vector2i:
	var npc: Dictionary = sim.get_npcs().get(npc_id, {}) as Dictionary
	var cell: Array = npc.get("target_cell", [-1, -1]) as Array
	if cell.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(cell[0]), int(cell[1]))


static func get_npc_facing(sim, npc_id: String) -> Vector2:
	var npc: Dictionary = sim.get_npcs().get(npc_id, {}) as Dictionary
	var facing: Array = npc.get("facing", [0.0, -1.0]) as Array
	if facing.size() < 2:
		return Vector2.UP
	return Vector2(float(facing[0]), float(facing[1]))


static func is_npc_moving(sim, npc_id: String) -> bool:
	var npc: Dictionary = sim.get_npcs().get(npc_id, {}) as Dictionary
	return bool(npc.get("moving", false))


static func _talk_to_npc(sim, npc_id: String) -> Dictionary:
	var npc_catalog: NpcCatalog = sim.npc_catalog
	var result: Dictionary = npc_catalog.talk(sim._npcs_mutable(), npc_id)
	if bool(result.get("success", false)):
		sim.needs.add_effect(sim.state.npcs[npc_id], "conversation", sim.get_elapsed_game_minutes())
	return sim._emit_result(
		bool(result.get("success", false)),
		String(result.get("message_key", "interaction.failure.no_npc")),
		bool(result.get("changed", false)),
		false,
		(result.get("message_args", {}) as Dictionary).duplicate(true)
	)
