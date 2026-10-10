extends RefCounted

# Shared constants, factories and pure save-value helpers.

const Content := preload("res://src/content/first_night_content.gd")
const Npcs := preload("res://src/characters/npc_roster.gd")
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
const CraftingCatalogScript := preload(
	"res://src/crafting/crafting_catalog.gd"
)
const CraftingCommandScript := preload(
	"res://src/crafting/crafting_command.gd"
)
const NpcWorkRequestScript := preload(
	"res://src/simulation/npc_work_request.gd"
)
const NpcWorkRequestValidatorScript := preload(
	"res://src/simulation/npc_work_request_validator.gd"
)
const NpcMemoryScript := preload("res://src/simulation/npc_memory.gd")
const InventoryPackerScript := preload(
	"res://src/inventory/inventory_auto_packer.gd"
)
const InventoryPlacementRulesScript := preload(
	"res://src/inventory/inventory_placement_rules.gd"
)
const ItemInstanceRegistryScript := preload(
	"res://src/inventory/item_instance_registry.gd"
)
const ResourceNodeCatalogScript := preload(
	"res://src/content/resource_node_catalog.gd"
)
const RoomTopologyScript := preload(
	"res://src/construction/room_topology.gd"
)
const WaterMapScript := preload("res://src/world/water_map.gd")
const FarmingScript := preload("res://src/farming/farming_system.gd")

const SAVE_VERSION: int = 36
const LEGACY_WALL_MATERIAL_MIGRATION_CUTOFF: int = 22
const PLAYER_ENERGY_SAVE_VERSION: int = 24
const PLAYER_ENERGY_MAX: float = 100.0
const PLAYER_WORK_ENERGY_COST: float = 1.0
const PLAYER_POOR_SLEEP_ENERGY: float = 60.0
const STORAGE_COLUMNS: int = 3
const STORAGE_ROWS: int = 2
const FLOORED_STORAGE_COLUMNS: int = 3
const FLOORED_STORAGE_ROWS: int = 3
const STARTER_PANTRY_ZONE_ID: String = "core:storage_zone_0001"
const STARTER_PANTRY_CELLS: Array[Vector2i] = [
	Vector2i(22, 22), Vector2i(23, 22),
	Vector2i(22, 23), Vector2i(23, 23),
]
const WORLD_DROP_LIFETIME_MINUTES: int = 30 * 60
const DEFAULT_SEED: int = 247061
const START_MINUTE: int = 11 * 60
const EVENING_MINUTE: int = 18 * 60
const LATEST_MINUTE: int = 23 * 60 + 50
const MINUTES_PER_DAY: int = 24 * 60
const LAST_MINUTE_OF_DAY: int = MINUTES_PER_DAY - 1
const MORNING_MINUTE: int = 7 * 60
const GAME_MINUTES_PER_SECOND: float = 0.75
const PLAYER_ACTOR_ID: String = "core:player"
const MAX_STORAGE_ZONE_CELLS: int = 256
const MAX_STORAGE_ZONES: int = 256
const ACTION_INTERACT: String = "core:interact"
const OUTCOME_DRY_ROOM_ID: String = "core:dry_room"
const OUTCOME_COLD_DRAFT_ID: String = "core:cold_draft"
const OUTCOME_RESIDUAL_WARMTH_ID: String = "core:residual_warmth"
const OUTCOME_SAFE_WATER_ID: String = "core:safe_water"
const OUTCOME_LIGHT_SUPPER_ID: String = "core:light_supper"
const OUTCOME_HUNGRY_SLEEP_ID: String = "core:hungry_sleep"
const BLUEPRINT_STAGE_ID: String = "core:blueprint"
const COMPLETE_STAGE_ID: String = "core:complete"
const DROP_OFFSETS: Array[Vector2] = [
	Vector2(-11.0, -5.0),
	Vector2(9.0, -8.0),
	Vector2(4.0, 11.0),
	Vector2(-9.0, 10.0),
]

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

static func create_new_state(
	seed_value: int = DEFAULT_SEED,
	resource_generation_version: int = ResourceNodeCatalogScript.CURRENT_LAYOUT_VERSION
) -> Dictionary:
	var content_data: FirstNightContent = Content.new()
	var npc_data := Npcs.new()
	var boulders: Array[Dictionary] = (
		ResourceNodeCatalogScript.generate_surface_boulders(seed_value, resource_generation_version)
	)
	return {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"resource_generation_version": resource_generation_version,
		"day": 1,
		"minute_of_day": START_MINUTE,
		"elapsed_game_minutes": START_MINUTE,
		"player_position": [784.0, 944.0],
		"player_energy": PLAYER_ENERGY_MAX,
		"player_needs": {"hunger": 90.0, "restedness": 100.0},
		"farming": FarmingScript.empty_state(),
		"inventory": content_data.create_empty_inventory(),
		"inventory_layout": [],
		"item_instances": [],
		"next_item_instance_serial": 1,
		"hotbar_slots": ["", "", "", "", ""],
		"active_hotbar_slot": -1,
		"selected_inventory_item": {},
		"markers": [],
		"next_marker_serial": 1,
		"resource_nodes": boulders,
		"tree_nodes": ResourceNodeCatalogScript.generate_surface_trees(
			seed_value,
			boulders,
			resource_generation_version
		),
		"collected": {},
		"removed_bushes": {},
		"resource_work": {},
		"resource_work_tool_instances": {},
		"world_drops": [],
		"next_drop_serial": 1,
		"storage_zones": [],
		"storage_items": [],
		"next_storage_zone_serial": 1,
		"room_assignments": [],
		"home_policies": {},
		"stock_reserves": {},
		"next_room_serial": 1,
		"npcs": npc_data.create_initial_states(seed_value),
		"npc_profiles": {},
		"next_npc_serial": 1,
		"flags": {
			"house_inspected": false,
			"tools_found": false,
			"repair_stage": 0,
			"campfire_stage": 0,
			"bed_ready": true,
			"water_boiled": false,
			"dusk_warned": false,
			"late_warned": false,
			"first_night_complete": false,
			"comfortable_sleep_completed": false,
		},
		"outcomes": [],
		"blueprints": [],
		"structures": [],
		"crafting_projects": [],
	}

static func create_new_game_state(seed_value: int = DEFAULT_SEED) -> Dictionary:
	var new_state := create_new_state(seed_value)
	var floors: Array[Dictionary] = []
	var storage_cells: Array = []
	for cell: Vector2i in STARTER_PANTRY_CELLS:
		floors.append({
			"building_id": "core:wood_floor",
			"cell": [cell.x, cell.y],
			"stage_id": COMPLETE_STAGE_ID,
		})
		storage_cells.append([cell.x, cell.y])
	new_state["structures"] = floors
	new_state["storage_zones"] = [{
		"id": STARTER_PANTRY_ZONE_ID,
		"cells": storage_cells,
	}]
	new_state["next_storage_zone_serial"] = 2
	new_state["collected"] = {"core:old_tools": true}
	new_state["item_instances"] = [
		{
			"instance_id": "core:item_instance_000001",
			"item_id": "core:bucket",
			"state": {"charges": 0},
			"location": {"kind": "storage", "id": "core:bucket:0"},
		},
		{
			"instance_id": "core:item_instance_000002",
			"item_id": "core:axe",
			"state": {},
			"location": {"kind": "storage", "id": "core:axe:0"},
		},
		{
			"instance_id": "core:item_instance_000003",
			"item_id": "core:pickaxe",
			"state": {},
			"location": {"kind": "storage", "id": "core:pickaxe:0"},
		},
		{
			"instance_id": "core:item_instance_000004",
			"item_id": "core:hoe",
			"state": {},
			"location": {"kind": "storage", "id": "core:hoe:0"},
		},
	]
	new_state["next_item_instance_serial"] = 5
	new_state["storage_items"] = [
		{
			"cell": [22, 22], "item_id": "core:axe", "amount": 1,
			"origin": [0, 0], "rotation": 0, "stack_index": 0,
			"placement_id": "core:axe:0", "instance_id": "core:item_instance_000002",
		},
		{
			"cell": [22, 22], "item_id": "core:bucket", "amount": 1,
			"origin": [2, 0], "rotation": 0, "stack_index": 0,
			"placement_id": "core:bucket:0", "instance_id": "core:item_instance_000001",
		},
		{
			"cell": [23, 22], "item_id": "core:pickaxe", "amount": 1,
			"origin": [0, 0], "rotation": 0, "stack_index": 0,
			"placement_id": "core:pickaxe:0", "instance_id": "core:item_instance_000003",
		},
		{
			"cell": [22, 23], "item_id": "core:hoe", "amount": 1,
			"origin": [0, 0], "rotation": 0, "stack_index": 0,
			"placement_id": "core:hoe:0", "instance_id": "core:item_instance_000004",
		},
	]
	return new_state

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

static func _crafting_failure(reason_id: String) -> Dictionary:
	return {"success": false, "changed": false, "reason_id": reason_id}

static func _world_position_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(FirstNightContent.CELL_SIZE)),
		floori(world_position.y / float(FirstNightContent.CELL_SIZE))
	)

static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)

static func _is_valid_hex_color(value: String) -> bool:
	if value.length() != 6 and value.length() != 8:
		return false
	for character: int in value.to_lower().to_ascii_buffer():
		if not (character >= 48 and character <= 57) and not (character >= 97 and character <= 102):
			return false
	return true

static func _normalize_next_drop_serial(
	value: Variant,
	drops: Array
) -> int:
	var next_serial: int = maxi(1, _safe_int(value, 1))
	for drop_value: Variant in drops:
		if typeof(drop_value) != TYPE_DICTIONARY:
			continue
		var drop_id: String = String(
			(drop_value as Dictionary).get("drop_id", "")
		)
		if not drop_id.begins_with("core:drop_"):
			continue
		var serial_text: String = drop_id.trim_prefix("core:drop_")
		if not serial_text.is_valid_int():
			continue
		next_serial = maxi(next_serial, int(serial_text) + 1)
	return next_serial

static func _construction_cell_key(cell_data: Array) -> String:
	return "%d:%d" % [int(cell_data[0]), int(cell_data[1])]

static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and is_equal_approx(number, round(number))

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
