class_name FirstNightSimulation
extends RefCounted

signal event_emitted(event: Dictionary)

const Content := preload("res://src/content/first_night_content.gd")
const Npcs := preload("res://src/characters/npc_catalog.gd")
const NpcAutonomyScript := preload("res://src/simulation/npc_autonomy.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const ConstructionCommandScript := preload(
	"res://src/construction/construction_command.gd"
)
const ConstructionValidatorScript := preload(
	"res://src/construction/construction_validator.gd"
)
const BuildingCatalogScript := preload(
	"res://src/construction/building_catalog.gd"
)
const NpcWorkRequestScript := preload(
	"res://src/simulation/npc_work_request.gd"
)
const NpcWorkRequestValidatorScript := preload(
	"res://src/simulation/npc_work_request_validator.gd"
)
const NpcMemoryScript := preload("res://src/simulation/npc_memory.gd")

const SAVE_VERSION: int = 10
const DEFAULT_SEED: int = 247061
const START_MINUTE: int = 11 * 60
const EVENING_MINUTE: int = 18 * 60
const LATEST_MINUTE: int = 23 * 60 + 50
const GAME_MINUTES_PER_SECOND: float = 0.75
const MAX_CARRY_WEIGHT: float = 24.0
const PLAYER_ACTOR_ID: String = "core:player"
const ACTION_INTERACT: String = "core:interact"
const OUTCOME_DRY_ROOM_ID: String = "core:dry_room"
const OUTCOME_COLD_DRAFT_ID: String = "core:cold_draft"
const OUTCOME_RESIDUAL_WARMTH_ID: String = "core:residual_warmth"
const OUTCOME_SAFE_WATER_ID: String = "core:safe_water"
const OUTCOME_LIGHT_SUPPER_ID: String = "core:light_supper"
const OUTCOME_HUNGRY_SLEEP_ID: String = "core:hungry_sleep"
const BLUEPRINT_STAGE_ID: String = "core:blueprint"
const COMPLETE_STAGE_ID: String = "core:complete"

const OUTCOME_LABEL_KEYS: Dictionary = {
	OUTCOME_DRY_ROOM_ID: "first_night.outcome.dry_room",
	OUTCOME_COLD_DRAFT_ID: "first_night.outcome.cold_draft",
	OUTCOME_RESIDUAL_WARMTH_ID: "first_night.outcome.residual_warmth",
	OUTCOME_SAFE_WATER_ID: "first_night.outcome.safe_water",
	OUTCOME_LIGHT_SUPPER_ID: "first_night.outcome.light_supper",
	OUTCOME_HUNGRY_SLEEP_ID: "first_night.outcome.hungry_sleep",
}

# These Russian values are fingerprints of save versions 1-3, not display copy.
const LEGACY_V3_OUTCOME_IDS: Dictionary = {
	"сухая комната": OUTCOME_DRY_ROOM_ID,
	"холодный сквозняк": OUTCOME_COLD_DRAFT_ID,
	"остаточное тепло": OUTCOME_RESIDUAL_WARMTH_ID,
	"безопасная вода": OUTCOME_SAFE_WATER_ID,
	"лёгкий ужин": OUTCOME_LIGHT_SUPPER_ID,
	"голодный сон": OUTCOME_HUNGRY_SLEEP_ID,
}

var state: Dictionary
var content: FirstNightContent
var npc_catalog
var npc_autonomy
var building_catalog: BuildingCatalog
var _minute_accumulator: float = 0.0


func _init(initial_state: Dictionary = {}) -> void:
	building_catalog = BuildingCatalogScript.new()
	content = Content.new()
	npc_catalog = Npcs.new()
	npc_autonomy = NpcAutonomyScript.new(npc_catalog)
	if initial_state.is_empty():
		state = create_new_state()
	else:
		var header_result: Dictionary = validate_save_header(initial_state)
		if bool(header_result.get("success", false)):
			state = initial_state.duplicate(true)
		else:
			push_error("Save state rejected: %s." % String(header_result.get("code", "unknown")))
			state = create_new_state()
	_normalize_state()
	_sync_structure_navigation()


static func create_new_state(seed_value: int = DEFAULT_SEED) -> Dictionary:
	var content_data: FirstNightContent = Content.new()
	var npc_data := Npcs.new()
	return {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"day": 1,
		"minute_of_day": START_MINUTE,
		"player_position": [784.0, 944.0],
		"inventory": content_data.create_empty_inventory(),
		"collected": {},
		"npcs": npc_data.create_initial_states(seed_value),
		"flags": {
			"house_inspected": false,
			"tools_found": false,
			"repair_stage": 0,
			"campfire_stage": 0,
			"bed_ready": false,
			"water_boiled": false,
			"dusk_warned": false,
			"late_warned": false,
			"first_night_complete": false,
		},
		"outcomes": [],
		"blueprints": [],
		"structures": [],
	}


static func validate_save_header(raw_state: Dictionary) -> Dictionary:
	if not raw_state.has("version"):
		return {
			"success": false,
			"code": "missing_version",
			"message_key": "save.error.missing_version",
			"message_args": {},
		}

	var raw_version: Variant = raw_state["version"]
	if typeof(raw_version) != TYPE_INT and typeof(raw_version) != TYPE_FLOAT:
		return {
			"success": false,
			"code": "invalid_version",
			"message_key": "save.error.version_type",
			"message_args": {},
		}

	var numeric_version: float = float(raw_version)
	if not is_finite(numeric_version) or numeric_version != floor(numeric_version):
		return {
			"success": false,
			"code": "invalid_version",
			"message_key": "save.error.version_integer",
			"message_args": {},
		}

	var version: int = int(numeric_version)
	if version < 1:
		return {
			"success": false,
			"code": "invalid_version",
			"message_key": "save.error.version_range",
			"message_args": {},
		}
	if version > SAVE_VERSION:
		return {
			"success": false,
			"code": "future_version",
			"message_key": "save.error.future_version",
			"message_args": {},
		}
	return {
		"success": true,
		"code": "ok",
		"version": version,
	}


func tick(real_delta: float) -> bool:
	_minute_accumulator += real_delta * GAME_MINUTES_PER_SECOND
	var whole_minutes: int = int(floor(_minute_accumulator))
	if whole_minutes <= 0:
		return false

	_minute_accumulator -= float(whole_minutes)
	return _advance_clock(whole_minutes)


func advance_minutes(amount: int) -> bool:
	if amount <= 0:
		return false
	return _advance_clock(amount)


func _advance_clock(amount: int) -> bool:
	var previous_minute: int = get_minute_of_day()
	var next_minute: int = mini(previous_minute + amount, LATEST_MINUTE)
	if next_minute == previous_minute:
		return false
	state["minute_of_day"] = next_minute
	var autonomy_result: Dictionary = npc_autonomy.advance_minutes(
		_npcs_mutable(),
		previous_minute,
		next_minute,
		get_player_position(),
		_get_blueprint_cells()
	)
	var npcs_changed: bool = bool(autonomy_result.get("changed", false))
	var construction_changed: bool = _apply_autonomy_effects(
		autonomy_result.get("effects", []) as Array
	)

	var flags: Dictionary = _flags_mutable()
	if previous_minute < 17 * 60 and next_minute >= 17 * 60 and not bool(flags["dusk_warned"]):
		flags["dusk_warned"] = true
		_emit_result(true, "first_night.message.dusk", true)
	if next_minute >= LATEST_MINUTE and not bool(flags["late_warned"]):
		flags["late_warned"] = true
		_emit_result(true, "first_night.message.exhausted", true)

	if npcs_changed or construction_changed:
		event_emitted.emit({"type": "state_changed"})
	event_emitted.emit({"type": "time_changed", "minute": next_minute})
	return true


func execute_interaction(target_id: String) -> Dictionary:
	return execute_command(PLAYER_ACTOR_ID, target_id, ACTION_INTERACT)


func execute_command(actor_id: String, target_id: String, action_id: String) -> Dictionary:
	if actor_id != PLAYER_ACTOR_ID:
		return _emit_result(false, "interaction.failure.unknown_actor")
	if action_id != ACTION_INTERACT:
		return _emit_result(false, "interaction.failure.unsupported_action")

	var target: Dictionary = _resolve_interaction_target(target_id)
	if target.is_empty():
		return _emit_result(false, "interaction.failure.missing_target")

	var resolved_target_id: String = String(target.get("id", ""))
	var kind: String = String(target.get("kind", ""))
	if should_hide_interactable(resolved_target_id, kind):
		return _emit_result(false, "interaction.failure.target_unavailable")

	var target_position: Vector2 = target.get("position", Vector2.ZERO) as Vector2
	if get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return _emit_result(false, "interaction.failure.too_far")

	return _execute_resolved_interaction(resolved_target_id, kind)


func execute_construction_command(command: Dictionary) -> Dictionary:
	var action_id: String = String(command.get("action_id", ""))
	if action_id == ConstructionCommandScript.ACTION_CANCEL_BLUEPRINT:
		return _execute_cancel_blueprint(command)

	if action_id == ConstructionCommandScript.ACTION_DELIVER_MATERIALS:
		return _execute_deliver_blueprint_materials(command)

	if action_id == ConstructionCommandScript.ACTION_COMPLETE_BLUEPRINT:
		return _execute_complete_blueprint(command)

	var validation: Dictionary = (
		ConstructionValidatorScript.validate_place_blueprint(command)
	)

	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	for blueprint_value: Variant in (state["blueprints"] as Array):
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue

		var existing: Dictionary = blueprint_value as Dictionary
		if existing.get("cell", []) == cell_data:
			return {
				"success": false,
				"changed": false,
				"reason_id": "core:occupied_cell",
			}

	for structure_value: Variant in (state["structures"] as Array):
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue

		var existing_structure: Dictionary = structure_value as Dictionary
		if existing_structure.get("cell", []) == cell_data:
			return {
				"success": false,
				"changed": false,
				"reason_id": "core:occupied_cell",
			}
	var building_id: String = String(validation.get("building_id", ""))
	var material_cost: Dictionary = building_catalog.get_material_cost(building_id)
	var required_work_minutes: int = building_catalog.get_work_minutes(building_id)

	if material_cost.is_empty() or required_work_minutes <= 0:
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:invalid_building",
		}

	var delivered_materials: Dictionary = {}
	for item_variant: Variant in material_cost.keys():
		delivered_materials[String(item_variant)] = 0

	var blueprint: Dictionary = {
		"building_id": building_id,
		"cell": cell_data.duplicate(),
		"stage_id": BLUEPRINT_STAGE_ID,
		"required_materials": material_cost.duplicate(true),
		"delivered_materials": delivered_materials,
		"required_work_minutes": required_work_minutes,
		"work_progress_minutes": 0,
	}
	(state["blueprints"] as Array).append(blueprint)
	event_emitted.emit({"type": "state_changed"})

	return {
		"success": true,
		"changed": true,
		"reason_id": "core:blueprint_placed",
		"blueprint": blueprint.duplicate(true),
	}


func execute_npc_work_request(command: Dictionary) -> Dictionary:
	var validation: Dictionary = (
		NpcWorkRequestValidatorScript.validate_construction_help(command)
	)
	if not bool(validation.get("success", false)):
		return _emit_work_request_result(
			false,
			String(validation.get("reason_id", "core:invalid_request")),
			"npc.work_request.failure.invalid"
		)

	var npc_id: String = String(validation.get("npc_id", ""))
	var npcs: Dictionary = _npcs_mutable()
	if not npcs.has(npc_id):
		return _emit_work_request_result(
			false,
			"core:missing_npc",
			"npc.work_request.failure.missing_npc"
		)

	var npc: Dictionary = npcs[npc_id] as Dictionary
	if not bool(npc.get("active", false)):
		return _emit_work_request_result(
			false,
			"core:missing_npc",
			"npc.work_request.failure.missing_npc"
		)
	if not bool(npc.get("known", false)):
		return _emit_work_request_result(
			false,
			"core:not_acquainted",
			"npc.work_request.failure.not_acquainted"
		)
	if (
		get_player_position().distance_to(get_npc_position(npc_id, Vector2.ZERO))
		> FirstNightContent.INTERACTION_RANGE
	):
		return _emit_work_request_result(
			false,
			"core:too_far",
			"npc.work_request.failure.too_far"
		)
	if not (npc.get("work_commitment", {}) as Dictionary).is_empty():
		return _emit_work_request_result(
			false,
			"core:npc_busy",
			"npc.work_request.failure.busy"
		)

	var target_cell_data: Array = validation.get("target_cell", []) as Array
	var blueprint: Dictionary = _find_blueprint(target_cell_data)
	if blueprint.is_empty():
		return _emit_work_request_result(
			false,
			"core:missing_blueprint",
			"npc.work_request.failure.missing_blueprint"
		)

	var needs: Dictionary = npc.get("needs", {}) as Dictionary
	if (
		float(needs.get("hunger", 0.0))
		< npc_autonomy.CONSTRUCTION_REQUEST_MIN_HUNGER
	):
		return _emit_work_request_result(
			false,
			"core:npc_hungry",
			"npc.work_request.failure.hungry"
		)
	if (
		float(needs.get("energy", 0.0))
		< npc_autonomy.CONSTRUCTION_REQUEST_MIN_ENERGY
	):
		return _emit_work_request_result(
			false,
			"core:npc_tired",
			"npc.work_request.failure.tired"
		)

	var target_cell := Vector2i(
		int(target_cell_data[0]),
		int(target_cell_data[1])
	)
	var npc_cell: Vector2i = _world_position_to_cell(
		get_npc_position(npc_id, Vector2.ZERO)
	)
	var player_cell: Vector2i = _world_position_to_cell(get_player_position())
	var work_cell: Vector2i = npc_autonomy.find_construction_work_cell(
		target_cell,
		npc_cell,
		player_cell
	)
	if work_cell == npc_autonomy.INVALID_CELL:
		return _emit_work_request_result(
			false,
			"core:unreachable_work",
			"npc.work_request.failure.unreachable"
		)

	if not _blueprint_has_all_materials(blueprint):
		var npc_inventory: Dictionary = npc.get("personal_inventory", {}) as Dictionary
		var transfer: Dictionary = _calculate_material_transfer(
			blueprint,
			npc_inventory
		)
		if not _transfer_completes_blueprint(blueprint, transfer):
			return _emit_work_request_result(
				false,
				"core:required_materials_missing",
				"npc.work_request.failure.materials_missing"
			)
		_apply_material_transfer(blueprint, npc_inventory, transfer)
		npc["personal_inventory"] = npc_inventory

	npc["work_commitment"] = {
		"commitment_id": NpcWorkRequestScript.HELP_BUILD_COMMITMENT_ID,
		"requester_id": NpcWorkRequestScript.PLAYER_ACTOR_ID,
		"target_cell": target_cell_data.duplicate(),
		"work_cell": [work_cell.x, work_cell.y],
		"building_id": String(blueprint.get("building_id", "")),
		"accepted_minute": get_minute_of_day(),
		"progress_minutes": 0,
		"required_minutes": npc_autonomy.CONSTRUCTION_WORK_MINUTES,
		"resume_activity_id": String(
			npc.get("activity_id", npc_autonomy.ACTIVITY_MORNING)
		),
	}
	npc["target_cell"] = [work_cell.x, work_cell.y]

	return _emit_work_request_result(
		true,
		"core:request_accepted",
		"npc.work_request.accepted",
		true
	)


func _execute_cancel_blueprint(command: Dictionary) -> Dictionary:
	var validation: Dictionary = (
		ConstructionValidatorScript.validate_cancel_blueprint(command)
	)

	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	var blueprints: Array = state["blueprints"] as Array

	for index: int in range(blueprints.size()):
		var blueprint_value: Variant = blueprints[index]
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue

		var blueprint: Dictionary = blueprint_value as Dictionary
		if blueprint.get("cell", []) != cell_data:
			continue

		var returned_materials: Dictionary = (
			blueprint.get("delivered_materials", {}) as Dictionary
		).duplicate(true)
		_add_items_to_inventory(returned_materials, _inventory_mutable())
		blueprints.remove_at(index)
		event_emitted.emit({"type": "state_changed"})

		return {
			"success": true,
			"changed": true,
			"reason_id": "core:blueprint_cancelled",
			"cell": cell_data.duplicate(),
			"returned_materials": returned_materials,
		}

	return {
		"success": false,
		"changed": false,
		"reason_id": "core:missing_blueprint",
	}


func _execute_deliver_blueprint_materials(command: Dictionary) -> Dictionary:
	var validation: Dictionary = (
		ConstructionValidatorScript.validate_deliver_materials(command)
	)
	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	var blueprint: Dictionary = _find_blueprint(cell_data)
	if blueprint.is_empty():
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:missing_blueprint",
		}

	var target_position := FirstNightContent.cell_center(
		int(cell_data[0]),
		int(cell_data[1])
	)
	if get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:too_far",
		}

	if _blueprint_has_all_materials(blueprint):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:materials_already_delivered",
		}

	var inventory: Dictionary = _inventory_mutable()
	var transfer: Dictionary = _calculate_material_transfer(blueprint, inventory)
	if transfer.is_empty():
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:required_materials_missing",
		}

	_apply_material_transfer(blueprint, inventory, transfer)
	var transferred_total: int = 0
	for amount_value: Variant in transfer.values():
		transferred_total += int(amount_value)
	event_emitted.emit({"type": "state_changed"})
	return {
		"success": true,
		"changed": true,
		"reason_id": "core:materials_delivered",
		"cell": cell_data.duplicate(),
		"transferred_materials": transfer.duplicate(true),
		"transferred_total": transferred_total,
		"blueprint": blueprint.duplicate(true),
	}


func _sync_structure_navigation() -> void:
	var structure_cells: Array[Vector2i] = []

	for structure_value: Variant in (state["structures"] as Array):
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue

		var structure: Dictionary = structure_value as Dictionary
		var cell_data: Array = structure.get("cell", []) as Array
		if cell_data.size() != 2:
			continue

		structure_cells.append(Vector2i(
			int(cell_data[0]),
			int(cell_data[1])
		))

	npc_autonomy.set_structure_cells(structure_cells)


func _get_blueprint_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for blueprint_value: Variant in (state["blueprints"] as Array):
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue
		var cell_data: Array = (blueprint_value as Dictionary).get("cell", []) as Array
		if cell_data.size() != 2:
			continue
		result.append(Vector2i(int(cell_data[0]), int(cell_data[1])))
	return result


func _apply_autonomy_effects(effects: Array) -> bool:
	var changed: bool = false
	for effect_value: Variant in effects:
		if typeof(effect_value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_value as Dictionary
		if String(effect.get("type", "")) != "complete_construction":
			continue
		var cell_data: Array = effect.get("target_cell", []) as Array
		if cell_data.size() != 2 or _is_actor_in_cell(cell_data):
			continue
		var completion: Dictionary = _complete_blueprint_at_cell(cell_data)
		if not bool(completion.get("success", false)):
			continue

		var npc_id: String = String(effect.get("npc_id", ""))
		var npcs: Dictionary = _npcs_mutable()
		if npcs.has(npc_id):
			var npc: Dictionary = npcs[npc_id] as Dictionary
			var commitment: Dictionary = npc.get("work_commitment", {}) as Dictionary
			_record_first_shared_wall_memory(
				npc,
				cell_data,
				int(effect.get("minute", get_minute_of_day()))
			)
			npc["work_commitment"] = {}
			npc["activity_id"] = String(
				commitment.get("resume_activity_id", npc_autonomy.ACTIVITY_MORNING)
			)
			npc["activity_started_minute"] = get_minute_of_day()
			npc["moving"] = false
		changed = true
	return changed


func _record_first_shared_wall_memory(
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
		get_day(),
		event_minute,
		target_cell
	))
	npc["memories"] = memories
	return true


func _is_actor_in_cell(cell_data: Array) -> bool:
	var target_cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
	if _world_position_to_cell(get_player_position()) == target_cell:
		return true

	for npc_value: Variant in _npcs_mutable().values():
		if typeof(npc_value) != TYPE_DICTIONARY:
			continue

		var npc: Dictionary = npc_value as Dictionary
		if not bool(npc.get("active", false)):
			continue

		var position_data: Array = npc.get("position", []) as Array
		if position_data.size() < 2:
			continue
		var npc_position := Vector2(
			float(position_data[0]),
			float(position_data[1])
		)
		if _world_position_to_cell(npc_position) == target_cell:
			return true

	return false


func _blueprint_has_all_materials(blueprint: Dictionary) -> bool:
	var required: Dictionary = blueprint.get("required_materials", {}) as Dictionary
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	for item_variant: Variant in required.keys():
		var item_id: String = String(item_variant)
		if int(delivered.get(item_id, 0)) < int(required[item_variant]):
			return false
	return not required.is_empty()


func _calculate_material_transfer(
	blueprint: Dictionary,
	source_inventory: Dictionary
) -> Dictionary:
	var required: Dictionary = blueprint.get("required_materials", {}) as Dictionary
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	var transfer: Dictionary = {}
	var item_ids: Array[String] = []
	for item_variant: Variant in required.keys():
		item_ids.append(String(item_variant))
	item_ids.sort()
	for item_id: String in item_ids:
		var missing: int = maxi(
			0,
			int(required.get(item_id, 0)) - int(delivered.get(item_id, 0))
		)
		var amount: int = mini(missing, maxi(0, int(source_inventory.get(item_id, 0))))
		if amount > 0:
			transfer[item_id] = amount
	return transfer


func _transfer_completes_blueprint(
	blueprint: Dictionary,
	transfer: Dictionary
) -> bool:
	var required: Dictionary = blueprint.get("required_materials", {}) as Dictionary
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	for item_variant: Variant in required.keys():
		var item_id: String = String(item_variant)
		if (
			int(delivered.get(item_id, 0)) + int(transfer.get(item_id, 0))
			< int(required[item_variant])
		):
			return false
	return not required.is_empty()


func _apply_material_transfer(
	blueprint: Dictionary,
	source_inventory: Dictionary,
	transfer: Dictionary
) -> void:
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	for item_variant: Variant in transfer.keys():
		var item_id: String = String(item_variant)
		var amount: int = int(transfer[item_variant])
		source_inventory[item_id] = maxi(
			0,
			int(source_inventory.get(item_id, 0)) - amount
		)
		delivered[item_id] = int(delivered.get(item_id, 0)) + amount
	blueprint["delivered_materials"] = delivered


func _add_items_to_inventory(items: Dictionary, target_inventory: Dictionary) -> void:
	for item_variant: Variant in items.keys():
		var item_id: String = String(item_variant)
		var amount: int = maxi(0, int(items[item_variant]))
		target_inventory[item_id] = int(target_inventory.get(item_id, 0)) + amount


static func _world_position_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(FirstNightContent.CELL_SIZE)),
		floori(world_position.y / float(FirstNightContent.CELL_SIZE))
	)


func _execute_complete_blueprint(command: Dictionary) -> Dictionary:
	var validation: Dictionary = (
		ConstructionValidatorScript.validate_complete_blueprint(command)
	)

	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	if _is_actor_in_cell(cell_data):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:occupied_by_actor",
		}

	var result: Dictionary = _complete_blueprint_at_cell(cell_data)
	if bool(result.get("changed", false)):
		event_emitted.emit({"type": "state_changed"})
	return result


func _complete_blueprint_at_cell(cell_data: Array) -> Dictionary:
	var structures: Array = state["structures"] as Array

	for structure_value: Variant in structures:
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue

		var existing_structure: Dictionary = structure_value as Dictionary
		if existing_structure.get("cell", []) == cell_data:
			return {
				"success": false,
				"changed": false,
				"reason_id": "core:occupied_cell",
			}

	var blueprints: Array = state["blueprints"] as Array
	for index: int in range(blueprints.size()):
		var blueprint_value: Variant = blueprints[index]
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue

		var blueprint: Dictionary = blueprint_value as Dictionary
		if blueprint.get("cell", []) != cell_data:
			continue
		if not _blueprint_has_all_materials(blueprint):
			return {
				"success": false,
				"changed": false,
				"reason_id": "core:required_materials_missing",
			}

		var structure: Dictionary = {
			"building_id": String(blueprint.get("building_id", "")),
			"cell": cell_data.duplicate(),
			"stage_id": COMPLETE_STAGE_ID,
		}

		blueprints.remove_at(index)
		structures.append(structure)
		_sync_structure_navigation()

		return {
			"success": true,
			"changed": true,
			"reason_id": "core:structure_completed",
			"structure": structure.duplicate(true),
		}

	return {
		"success": false,
		"changed": false,
		"reason_id": "core:missing_blueprint",
	}


func _find_blueprint(cell_data: Array) -> Dictionary:
	for blueprint_value: Variant in (state["blueprints"] as Array):
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue
		var blueprint: Dictionary = blueprint_value as Dictionary
		if blueprint.get("cell", []) == cell_data:
			return blueprint
	return {}


func _emit_work_request_result(
	success: bool,
	reason_id: String,
	message_key: String,
	changed: bool = false
) -> Dictionary:
	var result: Dictionary = _emit_result(success, message_key, changed)
	result["reason_id"] = reason_id
	return result


func _execute_resolved_interaction(target_id: String, kind: String) -> Dictionary:
	match kind:
		"house":
			return _inspect_house()
		"tools":
			return _find_tools()
		"repair":
			return _advance_repair()
		"campfire":
			return _advance_campfire()
		"bed":
			return _advance_bed()
		"npc":
			return _talk_to_npc(target_id)

	if content.has_collect_rule(kind):
		return _collect_resource(target_id, kind)
	return _emit_result(false, "interaction.failure.unsupported_target")


func get_interaction_target_position(target_id: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var target: Dictionary = _resolve_interaction_target(target_id)
	if target.is_empty():
		return fallback
	return target.get("position", fallback) as Vector2


func export_state() -> Dictionary:
	return state.duplicate(true)


func get_inventory() -> Dictionary:
	return _inventory_mutable().duplicate(true)


func get_blueprints() -> Array:
	return (state.get("blueprints", []) as Array).duplicate(true)


func get_structures() -> Array:
	return (state.get("structures", []) as Array).duplicate(true)


func is_navigation_cell_walkable(cell: Vector2i) -> bool:
	return npc_autonomy.is_cell_walkable(cell)


func get_flags() -> Dictionary:
	return _flags_mutable().duplicate(true)


func get_npcs() -> Dictionary:
	return _npcs_mutable().duplicate(true)


func get_item_count(item_id: String) -> int:
	return int(get_inventory().get(content.normalize_item_id(item_id), 0))


func get_inventory_weight() -> float:
	var total: float = 0.0
	var inventory: Dictionary = get_inventory()
	for item_variant: Variant in inventory.keys():
		var item_id: String = String(item_variant)
		total += float(inventory[item_id]) * content.item_weight(item_id)
	return total


func get_day() -> int:
	return int(state.get("day", 1))


func get_minute_of_day() -> int:
	return int(state.get("minute_of_day", START_MINUTE))


func get_time_text() -> String:
	var minute: int = get_minute_of_day()
	return "%02d:%02d" % [minute / 60, minute % 60]


func get_player_position() -> Vector2:
	var stored: Array = state.get("player_position", [784.0, 944.0]) as Array
	if stored.size() < 2:
		return Vector2(784.0, 944.0)
	return Vector2(float(stored[0]), float(stored[1]))


func set_player_position(value: Vector2) -> void:
	state["player_position"] = [value.x, value.y]


func is_collected(object_id: String) -> bool:
	var collected: Dictionary = state["collected"] as Dictionary
	return bool(collected.get(content.normalize_object_id(object_id), false))


func get_object_stage(kind: String) -> int:
	var flags: Dictionary = get_flags()
	match kind:
		"repair":
			return int(flags["repair_stage"])
		"campfire":
			return int(flags["campfire_stage"])
		"bed":
			return 1 if bool(flags["bed_ready"]) else 0
		_:
			return 0


func get_object_label_key(kind: String, fallback_key: String, object_id: String = "") -> String:
	var flags: Dictionary = get_flags()
	match kind:
		"npc":
			return npc_catalog.get_label_key(get_npcs(), object_id, fallback_key)
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


func should_hide_interactable(object_id: String, kind: String) -> bool:
	if kind == "npc":
		return not npc_catalog.is_visible(get_npcs(), object_id)
	if kind == "tools":
		return bool(get_flags().get("tools_found", false))
	if content.has_collect_rule(kind) and not content.is_collect_rule_repeatable(kind):
		return is_collected(object_id)
	return false


func is_npc_visible(npc_id: String) -> bool:
	return npc_catalog.is_visible(get_npcs(), npc_id)


func get_npc_position(npc_id: String, fallback: Vector2) -> Vector2:
	return npc_catalog.get_position(get_npcs(), npc_id, fallback)


func get_npc_appearance(npc_id: String) -> Dictionary:
	return npc_catalog.get_appearance(get_npcs(), npc_id)


func get_npc_activity_id(npc_id: String) -> String:
	var npc: Dictionary = get_npcs().get(npc_id, {}) as Dictionary
	return String(npc.get("activity_id", NpcAutonomyScript.ACTIVITY_ARRIVING))


func get_npc_activity_key(npc_id: String) -> String:
	return npc_autonomy.get_activity_key(get_npc_activity_id(npc_id))


func get_npc_needs(npc_id: String) -> Dictionary:
	var npc: Dictionary = get_npcs().get(npc_id, {}) as Dictionary
	return (npc.get("needs", {}) as Dictionary).duplicate(true)


func get_npc_personal_food(npc_id: String) -> int:
	var npc: Dictionary = get_npcs().get(npc_id, {}) as Dictionary
	var inventory: Dictionary = npc.get("personal_inventory", {}) as Dictionary
	return int(inventory.get(FirstNightContent.FOOD_ID, 0))


func get_npc_work_commitment(npc_id: String) -> Dictionary:
	var npc: Dictionary = get_npcs().get(npc_id, {}) as Dictionary
	return (npc.get("work_commitment", {}) as Dictionary).duplicate(true)


func get_npc_memories(npc_id: String) -> Array:
	var npc: Dictionary = get_npcs().get(npc_id, {}) as Dictionary
	return (npc.get("memories", []) as Array).duplicate(true)


func get_npc_relationship_to_player(npc_id: String) -> Dictionary:
	return NpcMemoryScript.relationship_from_memories(
		get_npc_memories(npc_id)
	)


func get_npc_target_cell(npc_id: String) -> Vector2i:
	var npc: Dictionary = get_npcs().get(npc_id, {}) as Dictionary
	var cell: Array = npc.get("target_cell", [-1, -1]) as Array
	if cell.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(cell[0]), int(cell[1]))


func get_npc_facing(npc_id: String) -> Vector2:
	var npc: Dictionary = get_npcs().get(npc_id, {}) as Dictionary
	var facing: Array = npc.get("facing", [0.0, -1.0]) as Array
	if facing.size() < 2:
		return Vector2.UP
	return Vector2(float(facing[0]), float(facing[1]))


func is_npc_moving(npc_id: String) -> bool:
	var npc: Dictionary = get_npcs().get(npc_id, {}) as Dictionary
	return bool(npc.get("moving", false))


func _resolve_interaction_target(target_id: String) -> Dictionary:
	var object_target: Dictionary = content.get_interactable(target_id)
	if not object_target.is_empty():
		return object_target

	if npc_catalog.get_definition(target_id).is_empty() or not get_npcs().has(target_id):
		return {}
	return {
		"id": target_id,
		"kind": "npc",
		"position": npc_catalog.get_position(get_npcs(), target_id, Vector2.ZERO),
	}


func get_current_objective_key() -> String:
	var flags: Dictionary = get_flags()
	if bool(flags["first_night_complete"]):
		var first_neighbor: Dictionary = get_npcs().get("core:first_neighbor", {}) as Dictionary
		if bool(first_neighbor.get("active", false)) and int(first_neighbor.get("talk_count", 0)) <= 0:
			return "first_night.objective.meet_neighbor"
		return "first_night.objective.complete"
	if not bool(flags["tools_found"]):
		return "first_night.objective.find_tools"
	if int(flags["repair_stage"]) < 3:
		return "first_night.objective.repair_room"
	if int(flags["campfire_stage"]) < 2:
		return "first_night.objective.light_campfire"
	if not bool(flags["water_boiled"]):
		return "first_night.objective.boil_water"
	if not bool(flags["bed_ready"]):
		return "first_night.objective.prepare_bed"
	if get_minute_of_day() < EVENING_MINUTE:
		return "first_night.objective.wait_for_evening"
	return "first_night.objective.sleep"


func _inspect_house() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if bool(flags["house_inspected"]):
		return _emit_result(
			true,
			content.get_message_key("house_repeat", "first_night.message.house.repeat")
		)
	flags["house_inspected"] = true
	return _emit_result(
		true,
		content.get_message_key("house_first", "first_night.message.house.first"),
		true
	)


func _find_tools() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if bool(flags["tools_found"]):
		return _emit_result(
			true,
			content.get_message_key("tools_repeat", "first_night.message.tools.repeat")
		)
	flags["tools_found"] = true
	return _emit_result(
		true,
		content.get_message_key("tools_first", "first_night.message.tools.first"),
		true
	)


func _collect_resource(object_id: String, kind: String) -> Dictionary:
	var rule: Dictionary = content.get_collect_rule(kind)
	var item_id: String = String(rule.get("item_id", ""))
	var amount: int = int(rule.get("amount", 0))
	var repeatable: bool = bool(rule.get("repeatable", false))

	if not repeatable and is_collected(object_id):
		return _emit_result(
			false,
			String(rule.get("empty_message_key", "first_night.collect.empty"))
		)
	if not _can_add_item(item_id, amount):
		return _emit_result(
			false,
			String(rule.get("full_message_key", "first_night.inventory.too_heavy"))
		)

	if not repeatable:
		var collected: Dictionary = state["collected"] as Dictionary
		collected[content.normalize_object_id(object_id)] = true
	_add_item(item_id, amount)
	return _emit_result(
		true,
		String(rule.get("message_key", "first_night.collect.generic.success")),
		true,
		false,
		{"amount": amount}
	)


func _advance_repair() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if not bool(flags["tools_found"]):
		return _emit_result(
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
			return _emit_result(
				true,
				content.get_message_key(
					"repair_stage_0",
					"first_night.message.repair.cleared"
				),
				true
			)
		1:
			if not _consume_items(content.get_cost("repair_stage_1")):
				return _emit_result(
					false,
					content.get_failure_message_key(
						"repair_stage_1_cost",
						"first_night.failure.repair.roof_resources"
					)
				)
			flags["repair_stage"] = 2
			return _emit_result(
				true,
				content.get_message_key(
					"repair_stage_1",
					"first_night.message.repair.roof_strengthened"
				),
				true
			)
		2:
			if not _consume_items(content.get_cost("repair_stage_2")):
				return _emit_result(
					false,
					content.get_failure_message_key(
						"repair_stage_2_cost",
						"first_night.failure.repair.finish_resources"
					)
				)
			flags["repair_stage"] = 3
			return _emit_result(
				true,
				content.get_message_key(
					"repair_stage_2",
					"first_night.message.repair.finished"
				),
				true
			)
		_:
			return _emit_result(
				true,
				content.get_message_key(
					"repair_done",
					"first_night.message.repair.already_done"
				)
			)


func _advance_campfire() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	var stage: int = int(flags["campfire_stage"])
	match stage:
		0:
			if not _consume_items(content.get_cost("campfire_stage_0")):
				return _emit_result(
					false,
					content.get_failure_message_key(
						"campfire_stage_0_cost",
						"first_night.failure.campfire.resources"
					)
				)
			flags["campfire_stage"] = 1
			return _emit_result(
				true,
				content.get_message_key(
					"campfire_stage_0",
					"first_night.message.campfire.built"
				),
				true
			)
		1:
			if not bool(flags["tools_found"]):
				return _emit_result(
					false,
					content.get_failure_message_key(
						"campfire_tools_required",
						"first_night.failure.campfire.tools_required"
					)
				)
			flags["campfire_stage"] = 2
			return _emit_result(
				true,
				content.get_message_key(
					"campfire_stage_1",
					"first_night.message.campfire.lit"
				),
				true
			)
		_:
			if get_item_count(FirstNightContent.RAW_WATER_ID) <= 0:
				return _emit_result(
					false,
					content.get_failure_message_key(
						"water_required",
						"first_night.failure.water.raw_required"
					)
				)
			_consume_items(content.get_cost("boil_water"))
			_add_item(FirstNightContent.BOILED_WATER_ID, 1)
			flags["water_boiled"] = true
			return _emit_result(
				true,
				content.get_message_key(
					"water_boiled",
					"first_night.message.water.boiled"
				),
				true
			)


func _advance_bed() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if int(flags["repair_stage"]) < 3:
		return _emit_result(
			false,
			content.get_failure_message_key(
				"bed_repair_required",
				"first_night.failure.bed.room_required"
			)
		)
	if not bool(flags["bed_ready"]):
		if not _consume_items(content.get_cost("bed")):
			return _emit_result(
				false,
				content.get_failure_message_key(
					"bed_cost",
					"first_night.failure.bed.resources"
				)
			)
		flags["bed_ready"] = true
		return _emit_result(
			true,
			content.get_message_key("bed_ready", "first_night.message.bed.ready"),
			true
		)
	if get_minute_of_day() < EVENING_MINUTE:
		return _emit_result(
			false,
			content.get_failure_message_key(
				"bed_too_early",
				"first_night.failure.bed.too_early"
			)
		)
	return _sleep_until_morning()


func _talk_to_npc(npc_id: String) -> Dictionary:
	var result: Dictionary = npc_catalog.talk(_npcs_mutable(), npc_id)
	return _emit_result(
		bool(result.get("success", false)),
		String(result.get("message_key", "interaction.failure.no_npc")),
		bool(result.get("changed", false)),
		false,
		(result.get("message_args", {}) as Dictionary).duplicate(true)
	)


func _sleep_until_morning() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	var outcomes: Array[String] = []
	if int(flags["repair_stage"]) >= 3:
		outcomes.append(OUTCOME_DRY_ROOM_ID)
	else:
		outcomes.append(OUTCOME_COLD_DRAFT_ID)
	if int(flags["campfire_stage"]) >= 2:
		outcomes.append(OUTCOME_RESIDUAL_WARMTH_ID)
	if get_item_count(FirstNightContent.BOILED_WATER_ID) > 0:
		outcomes.append(OUTCOME_SAFE_WATER_ID)
	if get_item_count(FirstNightContent.FOOD_ID) > 0:
		_consume_items(content.get_cost("sleep_food"))
		outcomes.append(OUTCOME_LIGHT_SUPPER_ID)
	else:
		outcomes.append(OUTCOME_HUNGRY_SLEEP_ID)

	state["outcomes"] = outcomes
	state["day"] = get_day() + 1
	state["minute_of_day"] = 7 * 60
	flags["first_night_complete"] = true
	var npc_arrived: bool = npc_catalog.activate_after_first_night(_npcs_mutable())
	npc_autonomy.start_morning(_npcs_mutable(), get_minute_of_day(), npc_arrived)
	var result: Dictionary = _emit_result(
		true,
		(
			"first_night.message.morning.summary_with_neighbor"
			if npc_arrived
			else "first_night.message.morning.summary"
		),
		true,
		true,
		{
			"outcomes": Localized.text_reference_list(_get_outcome_label_keys(outcomes)),
		}
	)
	event_emitted.emit({"type": "time_changed", "minute": get_minute_of_day()})
	return result


func _can_add_item(item_id: String, amount: int) -> bool:
	var added_weight: float = content.item_weight(item_id) * float(amount)
	return get_inventory_weight() + added_weight <= MAX_CARRY_WEIGHT + 0.001


func _add_item(item_id: String, amount: int) -> void:
	var inventory: Dictionary = _inventory_mutable()
	var normalized_id: String = content.normalize_item_id(item_id)
	inventory[normalized_id] = int(inventory.get(normalized_id, 0)) + amount


func _consume_items(costs: Dictionary) -> bool:
	var inventory: Dictionary = _inventory_mutable()
	for item_variant: Variant in costs.keys():
		var item_id: String = content.normalize_item_id(String(item_variant))
		var required_amount: int = int(costs[item_variant])
		if int(inventory.get(item_id, 0)) < required_amount:
			return false
	for item_variant: Variant in costs.keys():
		var item_id: String = content.normalize_item_id(String(item_variant))
		var required_amount: int = int(costs[item_variant])
		inventory[item_id] = int(inventory.get(item_id, 0)) - required_amount
	return true


func _get_outcome_label_keys(outcome_ids: Array[String]) -> Array[String]:
	var label_keys: Array[String] = []
	for outcome_id: String in outcome_ids:
		var label_key: String = String(OUTCOME_LABEL_KEYS.get(outcome_id, ""))
		if not label_key.is_empty():
			label_keys.append(label_key)
	return label_keys


func _emit_result(
	success: bool,
	message_key: String,
	changed: bool = false,
	auto_save: bool = false,
	message_args: Dictionary = {}
) -> Dictionary:
	var event: Dictionary = {
		"type": "command_result",
		"success": success,
		"message_key": message_key,
		"message_args": message_args.duplicate(true),
		"changed": changed,
		"auto_save": auto_save,
	}
	event_emitted.emit(event)
	return event


func _normalize_state() -> void:
	var seed_value: int = _safe_int(state.get("seed"), DEFAULT_SEED)
	var defaults: Dictionary = create_new_state(seed_value)
	for key_variant: Variant in defaults.keys():
		var key: String = String(key_variant)
		if not state.has(key):
			state[key] = defaults[key]

	var loaded_version: int = _safe_int(state.get("version"), SAVE_VERSION)
	state["version"] = SAVE_VERSION
	state["seed"] = seed_value
	state["day"] = maxi(1, _safe_int(state.get("day"), 1))
	state["minute_of_day"] = clampi(
		_safe_int(state.get("minute_of_day"), START_MINUTE),
		0,
		LATEST_MINUTE
	)

	state["inventory"] = content.normalize_inventory(_as_dictionary(state.get("inventory")))
	state["collected"] = content.normalize_collected(_as_dictionary(state.get("collected")))
	state["npcs"] = npc_catalog.normalize_states(_as_dictionary(state.get("npcs")), seed_value)

	var normalized_structures: Array[Dictionary] = (
		_normalize_structures(state.get("structures", []))
	)
	var normalized_blueprints: Array[Dictionary] = (
		_normalize_blueprints(state.get("blueprints", []))
	)
	state["structures"] = normalized_structures
	state["blueprints"] = _without_structure_cells(
		normalized_blueprints,
		normalized_structures
	)

	var flags: Dictionary = _as_dictionary(state.get("flags"))
	var default_flags: Dictionary = defaults["flags"] as Dictionary
	for flag_variant: Variant in default_flags.keys():
		var flag_id: String = String(flag_variant)
		var default_value: Variant = default_flags[flag_id]
		if typeof(default_value) == TYPE_BOOL:
			flags[flag_id] = _safe_bool(flags.get(flag_id), bool(default_value))
		else:
			flags[flag_id] = _safe_int(flags.get(flag_id), int(default_value))
	flags["repair_stage"] = clampi(_safe_int(flags.get("repair_stage"), 0), 0, 3)
	flags["campfire_stage"] = clampi(_safe_int(flags.get("campfire_stage"), 0), 0, 2)
	state["flags"] = flags
	if bool(flags["first_night_complete"]):
		npc_catalog.activate_after_first_night(_npcs_mutable())

	var stored_position_value: Variant = state.get("player_position", defaults["player_position"])
	if not _is_valid_position(stored_position_value):
		state["player_position"] = (defaults["player_position"] as Array).duplicate(true)
	else:
		var stored_position: Array = stored_position_value as Array
		state["player_position"] = [float(stored_position[0]), float(stored_position[1])]
	state["outcomes"] = _normalize_outcomes(state.get("outcomes"), loaded_version)

	if loaded_version != SAVE_VERSION:
		push_warning("Save version %s migrated into prototype version %s." % [loaded_version, SAVE_VERSION])


static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


func _normalize_blueprints(value: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return normalized

	var occupied_cells: Dictionary = {}
	for blueprint_value: Variant in (value as Array):
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue

		var blueprint: Dictionary = blueprint_value as Dictionary
		var cell_value: Variant = blueprint.get("cell", [])
		if typeof(cell_value) != TYPE_ARRAY:
			continue

		var cell_data: Array = cell_value as Array
		if cell_data.size() != 2:
			continue
		if not _is_whole_number(cell_data[0]) or not _is_whole_number(cell_data[1]):
			continue

		var normalized_command: Dictionary = {
			"actor_id": ConstructionCommandScript.PLAYER_ACTOR_ID,
			"action_id": ConstructionCommandScript.ACTION_PLACE_BLUEPRINT,
			"building_id": String(blueprint.get("building_id", "")),
			"cell": [int(cell_data[0]), int(cell_data[1])],
		}
		var validation: Dictionary = (
			ConstructionValidatorScript.validate_place_blueprint(normalized_command)
		)
		if not bool(validation.get("success", false)):
			continue

		var normalized_cell: Array = validation.get("cell", []) as Array
		var cell_key: String = "%d:%d" % [int(normalized_cell[0]), int(normalized_cell[1])]
		if occupied_cells.has(cell_key):
			continue
		occupied_cells[cell_key] = true
		var building_id: String = String(
			validation.get("building_id", "")
		)
		var required_materials: Dictionary = (
			building_catalog.get_material_cost(building_id)
		)
		var required_work_minutes: int = (
			building_catalog.get_work_minutes(building_id)
		)

		if required_materials.is_empty() or required_work_minutes <= 0:
			continue

		var raw_delivered: Dictionary = {}
		var delivered_value: Variant = blueprint.get(
			"delivered_materials",
			{}
		)
		if typeof(delivered_value) == TYPE_DICTIONARY:
			raw_delivered = delivered_value as Dictionary

		var delivered_materials: Dictionary = {}
		for item_variant: Variant in required_materials.keys():
			var item_id: String = String(item_variant)
			var required_amount: int = int(required_materials[item_variant])
			delivered_materials[item_id] = clampi(
				_safe_int(raw_delivered.get(item_id), 0),
				0,
				required_amount
			)

		var work_progress_minutes: int = clampi(
			_safe_int(blueprint.get("work_progress_minutes"), 0),
			0,
			required_work_minutes
		)
		normalized.append({
			"building_id": building_id,
			"cell": normalized_cell.duplicate(),
			"stage_id": BLUEPRINT_STAGE_ID,
			"required_materials": required_materials,
			"delivered_materials": delivered_materials,
			"required_work_minutes": required_work_minutes,
			"work_progress_minutes": work_progress_minutes,
		})

	return normalized


func _normalize_structures(value: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = _normalize_blueprints(value)

	for structure: Dictionary in normalized:
		structure["stage_id"] = COMPLETE_STAGE_ID
		structure.erase("required_materials")
		structure.erase("delivered_materials")
		structure.erase("required_work_minutes")
		structure.erase("work_progress_minutes")

	return normalized


static func _without_structure_cells(
	blueprints: Array[Dictionary],
	structures: Array[Dictionary]
) -> Array[Dictionary]:
	var structure_cells: Dictionary = {}
	for structure: Dictionary in structures:
		var cell_data: Array = structure.get("cell", []) as Array
		structure_cells[_construction_cell_key(cell_data)] = true

	var filtered: Array[Dictionary] = []
	for blueprint: Dictionary in blueprints:
		var cell_data: Array = blueprint.get("cell", []) as Array
		if structure_cells.has(_construction_cell_key(cell_data)):
			continue
		filtered.append(blueprint.duplicate(true))
	return filtered


static func _construction_cell_key(cell_data: Array) -> String:
	return "%d:%d" % [int(cell_data[0]), int(cell_data[1])]


static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and is_equal_approx(number, round(number))


func _inventory_mutable() -> Dictionary:
	return state["inventory"] as Dictionary


func _flags_mutable() -> Dictionary:
	return state["flags"] as Dictionary


func _npcs_mutable() -> Dictionary:
	return state["npcs"] as Dictionary


static func _safe_bool(value: Variant, fallback: bool) -> bool:
	if typeof(value) != TYPE_BOOL:
		return fallback
	return value


static func _safe_int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) != TYPE_FLOAT:
		return fallback
	var number: float = float(value)
	if not is_finite(number) or number != floor(number):
		return fallback
	return int(number)


static func _is_valid_position(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var position: Array = value as Array
	if position.size() < 2:
		return false
	for index: int in range(2):
		var coordinate: Variant = position[index]
		if typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT:
			return false
		if not is_finite(float(coordinate)):
			return false
	return true


static func _normalize_outcomes(value: Variant, loaded_version: int) -> Array[String]:
	var outcomes: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return outcomes
	var raw_outcomes: Array = value as Array
	for entry: Variant in raw_outcomes:
		if typeof(entry) == TYPE_STRING or typeof(entry) == TYPE_STRING_NAME:
			var outcome_id: String = String(entry)
			if loaded_version <= 3:
				outcome_id = String(LEGACY_V3_OUTCOME_IDS.get(outcome_id, outcome_id))
			if not outcome_id.is_empty() and outcome_id.contains(":"):
				outcomes.append(outcome_id)
	return outcomes
