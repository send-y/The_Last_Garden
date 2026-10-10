extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func execute_interaction(sim, target_id: String) -> Dictionary:
	return sim.execute_command(PLAYER_ACTOR_ID, target_id, ACTION_INTERACT)


static func execute_command(sim, actor_id: String, target_id: String, action_id: String) -> Dictionary:
	if actor_id != PLAYER_ACTOR_ID:
		return sim._emit_result(false, "interaction.failure.unknown_actor")
	if action_id != ACTION_INTERACT:
		return sim._emit_result(false, "interaction.failure.unsupported_action")

	var target: Dictionary = sim._resolve_interaction_target(target_id)
	if target.is_empty():
		return sim._emit_result(false, "interaction.failure.missing_target")

	var resolved_target_id: String = String(target.get("id", ""))
	var kind: String = String(target.get("kind", ""))
	if sim.should_hide_interactable(resolved_target_id, kind):
		return sim._emit_result(false, "interaction.failure.target_unavailable")

	var target_position: Vector2 = target.get("position", Vector2.ZERO) as Vector2
	if sim.get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return sim._emit_result(false, "interaction.failure.too_far")

	return sim._execute_resolved_interaction(resolved_target_id, kind)


static func _execute_resolved_interaction(sim, target_id: String, kind: String) -> Dictionary:
	var content: FirstNightContent = sim.content
	match kind:
		"house":
			return sim._inspect_house()
		"tools":
			return sim._find_tools()
		"repair":
			return sim._advance_repair()
		"campfire":
			return sim._advance_campfire()
		"bed":
			return sim._advance_bed()
		"npc":
			return sim._talk_to_npc(target_id)

	if content.has_collect_rule(kind):
		var rule: Dictionary = content.get_collect_rule(kind)
		if int(rule.get("work_minutes", 0)) > 0:
			return sim._emit_result(
				false,
				"resource.feedback.hold_to_work"
			)
		return sim._collect_resource(target_id, kind)
	return sim._emit_result(false, "interaction.failure.unsupported_target")


static func get_interaction_target_position(sim, target_id: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var target: Dictionary = sim._resolve_interaction_target(target_id)
	if target.is_empty():
		return fallback
	return target.get("position", fallback) as Vector2


static func is_collected(sim, object_id: String) -> bool:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var farming: FarmingSystem = sim.farming
	var normalized_id := content.normalize_object_id(object_id)
	if sim._food_object_ids.has(normalized_id):
		return not farming.berry_ready(sim, normalized_id)
	var collected: Dictionary = state["collected"] as Dictionary
	return bool(collected.get(normalized_id, false))


static func get_object_stage(sim, kind: String) -> int:
	var flags: Dictionary = sim.get_flags()
	match kind:
		"repair":
			return int(flags["repair_stage"])
		"campfire":
			return int(flags["campfire_stage"])
		"bed":
			return 1 if bool(flags["bed_ready"]) else 0
		_:
			return 0


static func get_object_label_key(sim, kind: String, fallback_key: String, object_id: String = "") -> String:
	var content: FirstNightContent = sim.content
	var npc_catalog: NpcCatalog = sim.npc_catalog
	var flags: Dictionary = sim.get_flags()
	match kind:
		"npc":
			return npc_catalog.get_label_key(sim.get_npcs(), object_id, fallback_key)
		"tools":
			return content.get_stage_label_key(kind, 0, fallback_key)
		"repair":
			var stage: int = int(flags["repair_stage"])
			return content.get_stage_label_key(kind, stage, fallback_key)
		"campfire":
			var fire_stage: int = int(flags["campfire_stage"])
			return content.get_stage_label_key(kind, fire_stage, fallback_key)
		"bed":
			var bed_stage: int = 1 if bool(flags["bed_ready"]) else 0
			return content.get_stage_label_key(kind, bed_stage, fallback_key)
		_:
			return fallback_key


static func should_hide_interactable(sim, object_id: String, kind: String) -> bool:
	var content: FirstNightContent = sim.content
	var npc_catalog: NpcCatalog = sim.npc_catalog
	if kind == "npc":
		return not npc_catalog.is_visible(sim.get_npcs(), object_id)
	if kind == "tools":
		return bool(sim.get_flags().get("tools_found", false)) or sim.is_collected(object_id)
	if kind == "food":
		return bool(sim.state.removed_bushes.get(content.normalize_object_id(object_id),false))
	if content.has_collect_rule(kind) and not content.is_collect_rule_repeatable(kind):
		return sim.is_collected(object_id)
	return false


static func _resolve_interaction_target(sim, target_id: String) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var npc_catalog: NpcCatalog = sim.npc_catalog
	var object_target: Dictionary = content.get_interactable(target_id)
	if not object_target.is_empty():
		return object_target
	for node_value: Variant in state.get("resource_nodes", []) as Array:
		if typeof(node_value) != TYPE_DICTIONARY:
			continue
		var node := node_value as Dictionary
		if String(node.get("id", "")) == target_id:
			return ResourceNodeCatalogScript.to_interactable(node)
	for node_value: Variant in state.get("tree_nodes", []) as Array:
		if typeof(node_value) != TYPE_DICTIONARY:
			continue
		var node := node_value as Dictionary
		if String(node.get("id", "")) == target_id:
			return ResourceNodeCatalogScript.to_interactable(node)
	for node: Dictionary in sim._berry_bush_nodes:
		if String(node.get("id", "")) == target_id:
			return ResourceNodeCatalogScript.to_interactable(node)

	if npc_catalog.get_definition(target_id).is_empty() or not sim.get_npcs().has(target_id):
		return {}
	return {
		"id": target_id,
		"kind": "npc",
		"position": npc_catalog.get_position(sim.get_npcs(), target_id, Vector2.ZERO),
	}


static func get_current_objective_key(sim) -> String:
	var content: FirstNightContent = sim.content
	var farming: FarmingSystem = sim.farming
	var flags: Dictionary = sim.get_flags()
	if bool(flags["comfortable_sleep_completed"]):
		var first_neighbor: Dictionary = sim.get_npcs().get("core:first_neighbor", {}) as Dictionary
		if bool(first_neighbor.get("active", false)) and int(first_neighbor.get("talk_count", 0)) <= 0:
			return "first_night.objective.meet_neighbor"
		return farming.objective(sim)
	if not bool(flags["tools_found"]):
		return "first_night.objective.find_tools"
	if int(flags["repair_stage"]) == 0:
		return "first_night.objective.clear_room"
	if not sim.is_roof_covered():
		var roof_planks := int(content.get_cost("repair_stage_1").get("core:plank", 0))
		if sim.get_item_count("core:plank") >= roof_planks:
			return "first_night.objective.cover_roof"
		if sim.get_item_count("core:plank") + sim._get_dropped_item_count("core:plank") >= roof_planks:
			return "first_night.objective.pick_up_planks"
		if sim._has_saw_plank_project():
			return "first_night.objective.finish_saw_planks"
		if sim._has_starting_workbench():
			return "first_night.objective.saw_planks"
		if not sim._get_starting_workbench_blueprint().is_empty():
			return "first_night.objective.finish_workbench"
		return "first_night.objective.build_workbench"
	if sim.get_minute_of_day() < EVENING_MINUTE:
		return "first_night.objective.wait_for_evening"
	return "first_night.objective.sleep"


static func _has_starting_workbench(sim) -> bool:
	var building_catalog: BuildingCatalog = sim.building_catalog
	for structure: Dictionary in sim.get_structures():
		var definition := building_catalog.get_definition(String(structure.get("building_id", "")))
		if String(definition.get("station_type", "")) == "core:workbench":
			return true
	return false


static func _get_starting_workbench_blueprint(sim) -> Dictionary:
	for blueprint: Dictionary in sim.get_blueprints():
		if String(blueprint.get("building_id", "")) == "core:workbench":
			return blueprint
	return {}


static func _has_saw_plank_project(sim) -> bool:
	for project: Dictionary in sim.get_crafting_projects():
		if String(project.get("recipe_id", "")) == "core:saw_planks":
			return true
	return false


static func _get_dropped_item_count(sim, item_id: String) -> int:
	var total := 0
	for drop: Dictionary in sim.get_world_drops():
		if String(drop.get("item_id", "")) == item_id:
			total += int(drop.get("amount", 0))
	return total


static func _get_roof_wood_required(sim) -> int:
	var content: FirstNightContent = sim.content
	var building_catalog: BuildingCatalog = sim.building_catalog
	var crafting_catalog: CraftingCatalog = sim.crafting_catalog
	var roof_planks := int(content.get_cost("repair_stage_1").get("core:plank", 0))
	var missing_planks := maxi(
		0, roof_planks - sim.get_item_count("core:plank") - sim._get_dropped_item_count("core:plank")
	)
	if missing_planks == 0 or sim._has_saw_plank_project():
		return 0
	var batch_output := maxi(1, int(crafting_catalog.get_outputs("core:saw_planks").get("core:plank", 0)))
	var batches := ceili(float(missing_planks) / float(batch_output))
	var wood_required := batches * int(crafting_catalog.get_inputs("core:saw_planks").get("core:wood", 0))
	if not sim._has_starting_workbench():
		var blueprint: Dictionary = sim._get_starting_workbench_blueprint()
		var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
		wood_required += maxi(
			0, int(building_catalog.get_material_cost("core:workbench").get("core:wood", 0))
			- int(delivered.get("core:wood", 0))
		)
	return wood_required


static func get_resource_search_hint(sim) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var flags: Dictionary = sim.get_flags()
	if not bool(flags["tools_found"]) or sim.is_roof_covered():
		return {}
	var cost: Dictionary = {"core:wood": sim._get_roof_wood_required()}
	var resource_kind := ""
	for kind: String in ["wood", "stone"]:
		var item_id := content.normalize_item_id(kind)
		if sim.get_item_count(item_id) < int(cost.get(item_id, 0)):
			resource_kind = kind
			break
	if resource_kind.is_empty():
		return {}
	var nodes: Array[Dictionary] = sim.get_surface_trees() if resource_kind == "wood" else sim.get_surface_boulders()
	var collected: Dictionary = state.get("collected", {}) as Dictionary
	var player_position: Vector2 = sim.get_player_position()
	var closest: Dictionary = {}
	var closest_distance := INF
	for node: Dictionary in nodes:
		var target_id := String(node.get("id", ""))
		if (
			bool(collected.get(target_id, false))
			or String(node.get("presentation_id", "")) == "surface_stump"
		):
			continue
		var position: Vector2 = node.get("position", Vector2.ZERO)
		var distance := player_position.distance_to(position)
		if distance < closest_distance:
			closest = node
			closest_distance = distance
	if closest.is_empty():
		return {}
	var offset: Vector2 = (closest["position"] as Vector2) - player_position
	var directions: Array[String] = [
		"resource.direction.east", "resource.direction.southeast",
		"resource.direction.south", "resource.direction.southwest",
		"resource.direction.west", "resource.direction.northwest",
		"resource.direction.north", "resource.direction.northeast",
	]
	var direction_key := "resource.direction.nearby"
	if closest_distance > FirstNightContent.INTERACTION_RANGE:
		var sector := posmod(roundi(offset.angle() / (PI / 4.0)), directions.size())
		direction_key = directions[sector]
	return {
		"kind": resource_kind,
		"target_id": String(closest["id"]),
		"direction_key": direction_key,
		"distance_cells": ceili(closest_distance / float(FirstNightContent.CELL_SIZE)),
	}


static func _inspect_house(sim) -> Dictionary:
	var content: FirstNightContent = sim.content
	var flags: Dictionary = sim._flags_mutable()
	if bool(flags["house_inspected"]):
		return sim._emit_result(
			true,
			content.get_message_key("house_repeat", "first_night.message.house.repeat")
		)
	flags["house_inspected"] = true
	return sim._emit_result(
		true,
		content.get_message_key("house_first", "first_night.message.house.first"),
		true
	)


static func _find_tools(sim) -> Dictionary:
	var content: FirstNightContent = sim.content
	var flags: Dictionary = sim._flags_mutable()
	if bool(flags["tools_found"]):
		return sim._emit_result(
			true,
			content.get_message_key("tools_repeat", "first_night.message.tools.repeat")
		)
	flags["tools_found"] = true
	return sim._emit_result(
		true,
		content.get_message_key("tools_first", "first_night.message.tools.first"),
		true
	)


static func _collect_resource(sim, object_id: String, kind: String) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var farming: FarmingSystem = sim.farming
	if kind == "food" and not farming.berry_ready(sim, object_id):
		return sim._emit_result(false, "farming.berry.wait")
	var rule: Dictionary = content.get_collect_rule(kind)
	var item_id: String = String(rule.get("item_id", ""))
	var amount: int = int(rule.get("amount", 0))
	var repeatable: bool = kind == "food" or bool(rule.get("repeatable", false))

	if not repeatable and sim.is_collected(object_id):
		return sim._emit_result(
			false,
			String(rule.get("empty_message_key", "first_night.collect.empty"))
		)
	if not sim._can_add_item(item_id, amount):
		return sim._emit_result(
			false,
			String(rule.get("full_message_key", "first_night.inventory.no_space"))
		)

	if not repeatable:
		var collected: Dictionary = state["collected"] as Dictionary
		collected[content.normalize_object_id(object_id)] = true
	sim._add_item(item_id, amount)
	if kind == "food":
		state.farming.berry_ready_at[object_id] = sim.get_elapsed_game_minutes() + int(farming.catalog.settings.berry_regrow_minutes)
	return sim._emit_result(
		true,
		String(rule.get("message_key", "first_night.collect.generic.success")),
		true,
		false,
		{"amount": amount}
	)


static func _advance_repair(sim) -> Dictionary:
	var content: FirstNightContent = sim.content
	var flags: Dictionary = sim._flags_mutable()
	if not bool(flags["tools_found"]):
		return sim._emit_result(
			false,
			content.get_failure_message_key(
				"repair_tools_required",
				"first_night.failure.repair.tools_required"
			)
		)

	var stage: int = int(flags["repair_stage"])
	match stage:
		0:
			flags["repair_stage"] = 1
			return sim._emit_result(
				true,
				content.get_message_key(
					"repair_stage_0",
					"first_night.message.repair.cleared"
				),
				true
			)
		1:
			if not sim._consume_items(content.get_cost("repair_stage_1")):
				return sim._emit_result(
					false,
					content.get_failure_message_key(
						"repair_stage_1_cost",
						"first_night.failure.repair.roof_resources"
					)
				)
			flags["repair_stage"] = 2
			return sim._emit_result(
				true,
				content.get_message_key(
					"repair_stage_1",
					"first_night.message.repair.roof_strengthened"
				),
				true
			)
		2:
			if not sim._consume_items(content.get_cost("repair_stage_2")):
				return sim._emit_result(
					false,
					content.get_failure_message_key(
						"repair_stage_2_cost",
						"first_night.failure.repair.finish_resources"
					)
				)
			flags["repair_stage"] = 3
			return sim._emit_result(
				true,
				content.get_message_key(
					"repair_stage_2",
					"first_night.message.repair.finished"
				),
				true
			)
		_:
			return sim._emit_result(
				true,
				content.get_message_key(
					"repair_done",
					"first_night.message.repair.already_done"
				)
			)


static func _advance_campfire(sim) -> Dictionary:
	var content: FirstNightContent = sim.content
	var flags: Dictionary = sim._flags_mutable()
	var stage: int = int(flags["campfire_stage"])
	match stage:
		0:
			if not sim._consume_items(content.get_cost("campfire_stage_0")):
				return sim._emit_result(
					false,
					content.get_failure_message_key(
						"campfire_stage_0_cost",
						"first_night.failure.campfire.resources"
					)
				)
			flags["campfire_stage"] = 1
			return sim._emit_result(
				true,
				content.get_message_key(
					"campfire_stage_0",
					"first_night.message.campfire.built"
				),
				true
			)
		1:
			if not bool(flags["tools_found"]):
				return sim._emit_result(
					false,
					content.get_failure_message_key(
						"campfire_tools_required",
						"first_night.failure.campfire.tools_required"
					)
				)
			flags["campfire_stage"] = 2
			return sim._emit_result(
				true,
				content.get_message_key(
					"campfire_stage_1",
					"first_night.message.campfire.lit"
				),
				true
			)
		_:
			if sim.get_item_count(FirstNightContent.RAW_WATER_ID) <= 0:
				return sim._emit_result(
					false,
					content.get_failure_message_key(
						"water_required",
						"first_night.failure.water.raw_required"
					)
				)
			sim._consume_items(content.get_cost("boil_water"))
			sim._add_item(FirstNightContent.BOILED_WATER_ID, 1)
			flags["water_boiled"] = true
			return sim._emit_result(
				true,
				content.get_message_key(
					"water_boiled",
					"first_night.message.water.boiled"
				),
				true
			)


static func _advance_bed(sim) -> Dictionary:
	var result: Dictionary = sim.housing.sleep_at(sim, sim.housing.STARTER)
	if bool(result.success):
		sim._flags_mutable()["bed_ready"] = true
	return result


static func _on_world_morning(sim, notify: bool) -> bool:
	var flags: Dictionary = sim._flags_mutable()
	var changed := not bool(flags["first_night_complete"])
	flags["first_night_complete"] = true
	var arrived: bool = sim.npc_catalog.activate_after_first_night(sim._npcs_mutable())
	if arrived:
		sim.npc_autonomy.start_morning(sim._npcs_mutable(), MORNING_MINUTE, true)
		if notify:
			sim._emit_result(true, "world.message.neighbor_arrived", true, true)
	return changed or arrived
