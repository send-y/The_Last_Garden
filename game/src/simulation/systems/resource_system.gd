extends "res://src/simulation/world_rules.gd"

const PINECONE_DROP_ITEM_ID := "core:pinecone"
const WorkProgress := preload("res://src/items/tool_work_progress.gd")

# Operates on the authoritative WorldSimulation state; owns no copy.

static func execute_resource_work(sim,
	actor_id: String,
	target_id: String
) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var actor_result: Dictionary = sim._get_resource_actor_position(actor_id
	)

	if not bool(actor_result.get("found", false)):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:unknown_actor",
		}

	var normalized_id: String = content.normalize_object_id(
		target_id
	)
	var target: Dictionary = sim._resolve_interaction_target(
		normalized_id
	)

	if target.is_empty():
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:missing_resource",
		}

	var kind: String = String(target.get("kind", ""))
	var rule: Dictionary = content.get_collect_rule(kind)
	if rule.is_empty():
		return {"success": false, "changed": false, "reason_id": "core:not_workable_resource"}
	var presentation_id := String(target.get("presentation_id", ""))
	var required_work: int = maxi(
		0,
		int(rule.get("work_minutes", 0))
	)
	if presentation_id == "surface_tree":
		required_work = 8
	elif presentation_id == "surface_stump":
		required_work = 4

	if required_work <= 0:
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:not_workable_resource",
		}

	if sim.is_collected(normalized_id):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:resource_depleted",
		}

	var target_position := (
		target.get("position", Vector2.ZERO) as Vector2
	)
	var actor_position := (
		actor_result.get("position", Vector2.ZERO) as Vector2
	)

	if (
		actor_position.distance_to(target_position)
		> FirstNightContent.INTERACTION_RANGE
	):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:too_far",
		}

	var required_tool_item_id: String = sim.get_resource_required_tool_item_id(normalized_id
	)
	var active_tool: Dictionary = sim.get_actor_tool(actor_id)
	var required_action: String = sim.get_resource_required_tool_action(normalized_id)
	var active_tool_instance_id := String(active_tool.get("instance_id", ""))
	var resource_work := (
		state["resource_work"] as Dictionary
	)
	var work_tool_instances := (
		state["resource_work_tool_instances"] as Dictionary
	)
	var current_work: float = WorkProgress.normalize(resource_work.get(normalized_id, 0), required_work)
	if (
		not required_action.is_empty()
		and not sim.actor_tool_supports(actor_id, required_action)
	):
		if current_work > 0 and work_tool_instances.has(normalized_id):
			resource_work.erase(normalized_id)
			work_tool_instances.erase(normalized_id)
			sim.event_emitted.emit({"type": "state_changed"})
			return {
				"success": false,
				"changed": true,
				"reason_id": "core:resource_work_tool_changed",
				"required_tool_item_id": required_tool_item_id,
			"required_tool_action": required_action,
			}
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:resource_tool_not_selected",
			"required_tool_item_id": required_tool_item_id,
			"required_tool_action": required_action,
		}

	if not required_action.is_empty():
		var work_tool_instance_id := String(
			work_tool_instances.get(normalized_id, "")
		)
		if (
			not work_tool_instance_id.is_empty()
			and work_tool_instance_id != active_tool_instance_id
		):
			resource_work.erase(normalized_id)
			work_tool_instances.erase(normalized_id)
			sim.event_emitted.emit({"type": "state_changed"})
			return {
				"success": false,
				"changed": true,
				"reason_id": "core:resource_work_tool_changed",
				"required_tool_item_id": required_tool_item_id,
			"required_tool_action": required_action,
			}
		work_tool_instances[normalized_id] = active_tool_instance_id

	if actor_id == PLAYER_ACTOR_ID:
		if not sim.prepare_player_work() or sim.get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
			return {"success":false,"changed":false,"reason_id":"core:too_far"}
		sim._spend_player_work_energy()
	else:
		sim.needs.spend_work(sim.state.npcs[actor_id].needs)
	var next_work: float = minf(current_work + content.item_tool_work_rate(String(active_tool.get("item_id", ""))), float(required_work))

	if next_work < required_work:
		resource_work[normalized_id] = WorkProgress.stored(next_work)
		var pinecone_drop_ids: Array[String] = []
		if presentation_id == "surface_tree":
			pinecone_drop_ids = sim._maybe_drop_pinecone(normalized_id,
				int(next_work),
				target_position
			)
		sim.event_emitted.emit({"type": "state_changed"})

		return {
			"success": true,
			"changed": true,
			"reason_id": "core:resource_work_progressed",
			"target_id": normalized_id,
			"work_progress_minutes": next_work,
			"required_work_minutes": required_work,
			"created_drop_ids": pinecone_drop_ids,
		}

	resource_work.erase(normalized_id)
	work_tool_instances.erase(normalized_id)

	var collected: Dictionary = state["collected"] as Dictionary
	var tree_node: Dictionary = sim._get_tree_node(normalized_id)
	if presentation_id == "surface_tree":
		sim._update_tree_stage(normalized_id, "stump")
	elif not tree_node.is_empty():
		collected[normalized_id] = true
	else:
		collected[normalized_id] = true
	var drop_item_id: String = String(rule.get("item_id", ""))
	var drop_amount: int = maxi(0, int(rule.get("amount", 0)))
	if not tree_node.is_empty():
		drop_amount = int(tree_node.get("yield_amount", drop_amount))
	if presentation_id == "surface_stump":
		drop_amount = 0
	if presentation_id == "surface_boulder":
		drop_amount = int(target.get("yield_amount", drop_amount))
	var drop_origin: Vector2 = target_position
	if String(target.get("presentation_id", "")) == "surface_boulder":
		drop_origin += Vector2(0.0, 40.0)
	var created_drop_ids: Array[String] = sim._create_resource_drops(normalized_id,
		drop_item_id,
		drop_amount,
		drop_origin
	)
	if presentation_id == "surface_tree":
		created_drop_ids.append_array(sim._maybe_drop_pinecone(normalized_id,
			int(next_work),
			drop_origin
		))
	if presentation_id in ["surface_tree", "surface_stump", "surface_boulder"]:
		sim._sync_structure_navigation()

	sim.event_emitted.emit({"type": "state_changed"})

	return {
		"success": true,
		"changed": true,
		"reason_id": "core:resource_depleted",
		"target_id": normalized_id,
		"work_progress_minutes": required_work,
		"required_work_minutes": required_work,
		"drop_item_id": drop_item_id,
		"drop_amount": drop_amount,
		"drop_origin": drop_origin,
		"created_drop_ids": created_drop_ids,
	}


static func _maybe_drop_pinecone(sim,
	tree_id: String,
	work_step: int,
	origin: Vector2
) -> Array[String]:
	if not sim.builtin_pinecone_enabled: return []
	var state: Dictionary = sim.state
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(state.get("seed", DEFAULT_SEED))
		^ int(tree_id.hash())
		^ (work_step * 0x45D9F3B)
	)
	if rng.randf() >= 0.15:
		return []
	return sim._create_resource_drops(tree_id,
		PINECONE_DROP_ITEM_ID,
		1,
		origin
	)


static func _create_resource_drops(sim,
	source_id: String,
	item_id: String,
	amount: int,
	origin: Vector2
) -> Array[String]:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var created_ids: Array[String] = []
	var normalized_item_id: String = content.normalize_item_id(item_id)
	if amount <= 0 or not content.has_item(normalized_item_id):
		return created_ids

	var drops: Array = state["world_drops"] as Array
	for index: int in range(amount):
		var serial: int = maxi(
			1,
			int(state.get("next_drop_serial", 1))
		)
		state["next_drop_serial"] = serial + 1
		var drop_id := "core:drop_%06d" % serial
		var offset: Vector2 = DROP_OFFSETS[
			index % DROP_OFFSETS.size()
		]
		drops.append({
			"drop_id": drop_id,
			"item_id": normalized_item_id,
			"amount": 1,
			"position": [
				origin.x + offset.x,
				origin.y + offset.y,
			],
			"source_id": source_id,
			"expires_at_game_minute": sim.get_elapsed_game_minutes() + WORLD_DROP_LIFETIME_MINUTES,
		})
		if content.item_is_instance_based(normalized_item_id):
			var instances: Array[String] = sim._create_item_instances(normalized_item_id, 1, "world_drop", drop_id)
			drops.back()["instance_id"] = instances[0]
		created_ids.append(drop_id)

	return created_ids


static func _get_resource_actor_position(sim,
	actor_id: String
) -> Dictionary:
	if actor_id == PLAYER_ACTOR_ID:
		return {
			"found": true,
			"position": sim.get_player_position(),
		}

	var npcs: Dictionary = sim.get_npcs()

	if npcs.has(actor_id) and bool(npcs[actor_id].get("active", false)):
		return {
			"found": true,
			"position": sim.get_npc_position(
				actor_id,
				Vector2.ZERO
			),
		}

	return {"found": false}


static func get_surface_boulders(sim) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var result: Array[Dictionary] = []
	for node_value: Variant in state.get("resource_nodes", []) as Array:
		if typeof(node_value) != TYPE_DICTIONARY:
			continue
		var interactable: Dictionary = ResourceNodeCatalogScript.to_interactable(
			node_value as Dictionary
		)
		if not interactable.is_empty():
			result.append(interactable)
	return result


static func get_surface_trees(sim) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var result: Array[Dictionary] = []
	for node_value: Variant in state.get("tree_nodes", []) as Array:
		if typeof(node_value) != TYPE_DICTIONARY:
			continue
		var interactable := ResourceNodeCatalogScript.to_interactable(
			node_value as Dictionary
		)
		if not interactable.is_empty():
			result.append(interactable)
	return result


static func get_surface_berry_bushes(sim) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for bush: Dictionary in sim._berry_bush_nodes:
		result.append(ResourceNodeCatalogScript.to_interactable(bush))
	return result


static func get_resource_work_progress(sim, object_id: String) -> int:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var progress: Dictionary = (
		state.get("resource_work", {}) as Dictionary
	)
	var normalized_id: String = content.normalize_object_id(
		object_id
	)
	return int(progress.get(normalized_id, 0))


static func get_resource_required_tool_action(sim, target_id: String) -> String:
	var target: Dictionary = sim._resolve_interaction_target(sim.content.normalize_object_id(target_id))
	match String(target.get("kind", "")):
		"wood": return "chop"
		"stone": return "mine"
	return ""

static func get_resource_required_tool_item_id(sim, target_id: String) -> String:
	var content: FirstNightContent = sim.content
	var target: Dictionary = sim._resolve_interaction_target(
		content.normalize_object_id(target_id)
	)
	match String(target.get("kind", "")):
		"wood":
			return "core:axe"
		"stone":
			return "core:pickaxe"
	return ""


static func get_resource_work_required(sim, object_id: String) -> int:
	var content: FirstNightContent = sim.content
	var target: Dictionary = sim._resolve_interaction_target(
		object_id
	)

	if target.is_empty():
		return 0

	var kind: String = String(target.get("kind", ""))
	var presentation_id := String(target.get("presentation_id", ""))
	if presentation_id == "surface_tree":
		return 8
	if presentation_id == "surface_stump":
		return 4
	var rule: Dictionary = content.get_collect_rule(kind)
	return maxi(0, int(rule.get("work_minutes", 0)))


static func _normalize_resource_work(sim,
	value: Variant
) -> Dictionary:
	var content: FirstNightContent = sim.content
	var normalized: Dictionary = {}

	if typeof(value) != TYPE_DICTIONARY:
		return normalized

	var raw_progress := value as Dictionary

	for object_variant: Variant in raw_progress.keys():
		var object_id: String = content.normalize_object_id(
			String(object_variant)
		)
		var target: Dictionary = sim._resolve_interaction_target(object_id)

		if target.is_empty() or sim.is_collected(object_id):
			continue

		var kind: String = String(target.get("kind", ""))
		var rule: Dictionary = content.get_collect_rule(kind)
		var presentation_id := String(target.get("presentation_id", ""))
		var required: int = maxi(
			0,
			int(rule.get("work_minutes", 0))
		)
		if presentation_id == "surface_tree":
			required = 8
		elif presentation_id == "surface_stump":
			required = 4

		if required <= 0:
			continue

		var progress: float = WorkProgress.normalize(raw_progress.get(object_variant), required)

		if progress > 0:
			normalized[object_id] = WorkProgress.stored(progress)

	return normalized


static func _normalize_resource_work_tool_instances(sim,
	value: Variant,
	resource_work: Dictionary
) -> Dictionary:
	var content: FirstNightContent = sim.content
	var normalized: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return normalized
	for object_variant: Variant in resource_work.keys():
		var object_id := content.normalize_object_id(String(object_variant))
		var instance_id := String((value as Dictionary).get(object_variant, ""))
		if not instance_id.is_empty():
			normalized[object_id] = instance_id
	return normalized


static func _normalize_resource_nodes(sim,
	value: Variant,
	world_seed: int
) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var generated: Array[Dictionary] = (
		ResourceNodeCatalogScript.generate_surface_boulders(
			world_seed, int(state["resource_generation_version"])
		)
	)
	if typeof(value) != TYPE_ARRAY:
		return generated
	var raw_nodes := value as Array
	var count_range := ResourceNodeCatalogScript.boulder_count_range(int(state["resource_generation_version"]))
	if (
		raw_nodes.size() < count_range.x
		or raw_nodes.size() > count_range.y
	):
		return generated

	var normalized: Array[Dictionary] = []
	var seen_cells: Dictionary = {}
	for index: int in range(raw_nodes.size()):
		if typeof(raw_nodes[index]) != TYPE_DICTIONARY:
			return generated
		var node := raw_nodes[index] as Dictionary
		var expected_id := "core:surface_boulder_%02d" % (index + 1)
		var cell_value: Variant = node.get("cell", [])
		if (
			String(node.get("id", "")) != expected_id
			or typeof(cell_value) != TYPE_ARRAY
			or (cell_value as Array).size() != 2
		):
			return generated
		var cell := cell_value as Array
		if not _is_whole_number(cell[0]) or not _is_whole_number(cell[1]):
			return generated
		var cell_position := Vector2i(int(cell[0]), int(cell[1]))
		if (
		not ResourceNodeCatalogScript.position_in_bounds(cell_position)
			or ResourceNodeCatalogScript.is_reserved_cell(cell_position)
		):
			return generated
		var cell_key := "%d,%d" % [cell_position.x, cell_position.y]
		if seen_cells.has(cell_key):
			return generated
		seen_cells[cell_key] = true
		normalized.append(
			ResourceNodeCatalogScript.make_surface_boulder(
				index + 1,
				cell_position,
				clampi(_safe_int(node.get("yield_amount"), 9), 9, 12)
			)
		)
	return normalized


static func _normalize_tree_nodes(sim,
	value: Variant,
	world_seed: int,
	boulders: Array
) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var generated := ResourceNodeCatalogScript.generate_surface_trees(
		world_seed,
		boulders,
		int(state["resource_generation_version"])
	)
	if typeof(value) != TYPE_ARRAY:
		return generated
	var raw_nodes := value as Array
	var count_range := ResourceNodeCatalogScript.tree_count_range(int(state["resource_generation_version"]))
	if (
		raw_nodes.size() < count_range.x
		or raw_nodes.size() > count_range.y
	):
		return generated
	var normalized: Array[Dictionary] = []
	var seen_cells: Dictionary = {}
	for index: int in range(raw_nodes.size()):
		if typeof(raw_nodes[index]) != TYPE_DICTIONARY:
			return generated
		var node := raw_nodes[index] as Dictionary
		var expected_id := "core:surface_tree_%02d" % (index + 1)
		var cell_value: Variant = node.get("cell", [])
		if (
			String(node.get("id", "")) != expected_id
			or typeof(cell_value) != TYPE_ARRAY
			or (cell_value as Array).size() != 2
		):
			return generated
		var cell := cell_value as Array
		if not _is_whole_number(cell[0]) or not _is_whole_number(cell[1]):
			return generated
		var cell_position := Vector2i(int(cell[0]), int(cell[1]))
		if (
			not ResourceNodeCatalogScript.position_in_bounds(cell_position)
			or ResourceNodeCatalogScript.is_reserved_cell(cell_position)
		):
			return generated
		var cell_key := "%d,%d" % [cell_position.x, cell_position.y]
		if seen_cells.has(cell_key):
			return generated
		seen_cells[cell_key] = true
		var stage_id := String(node.get("stage_id", "tree"))
		if stage_id != "tree" and stage_id != "stump":
			return generated
		normalized.append(ResourceNodeCatalogScript.make_surface_tree(
			index + 1,
			cell_position,
			clampi(_safe_int(node.get("yield_amount"), 12), 12, 13),
			stage_id
		))
	return normalized


static func _get_tree_node(sim, node_id: String) -> Dictionary:
	var state: Dictionary = sim.state
	for node_value: Variant in state.get("tree_nodes", []) as Array:
		if typeof(node_value) != TYPE_DICTIONARY:
			continue
		var node := node_value as Dictionary
		if String(node.get("id", "")) == node_id:
			return node
	return {}


static func _update_tree_stage(sim, node_id: String, stage_id: String) -> void:
	var state: Dictionary = sim.state
	var nodes: Array = state.get("tree_nodes", []) as Array
	for index: int in range(nodes.size()):
		if typeof(nodes[index]) != TYPE_DICTIONARY:
			continue
		var node := (nodes[index] as Dictionary).duplicate(true)
		if String(node.get("id", "")) != node_id:
			continue
		node["stage_id"] = stage_id
		nodes[index] = node
		return
