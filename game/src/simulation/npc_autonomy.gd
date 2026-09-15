class_name NpcAutonomy
extends RefCounted

const Pathfinder := preload("res://src/simulation/local_grid_pathfinder.gd")
const NavigationData := preload("res://src/simulation/first_night_navigation.gd")

const ACTIVITY_ARRIVING: String = "core:arriving"
const ACTIVITY_MORNING: String = "core:morning"
const ACTIVITY_OUTDOORS: String = "core:outdoors"
const ACTIVITY_EVENING: String = "core:evening"
const ACTIVITY_GOING_TO_MEAL: String = "core:going_to_meal"
const ACTIVITY_EATING: String = "core:eating"
const ACTIVITY_WAITING_FOR_FOOD: String = "core:waiting_for_food"
const ACTIVITY_GOING_TO_REST: String = "core:going_to_rest"
const ACTIVITY_RESTING: String = "core:resting"
const ACTIVITY_BLOCKED: String = "core:blocked"
const ACTIVITY_GOING_TO_BUILD: String = "core:going_to_build"
const ACTIVITY_BUILDING: String = "core:building"

const HUNGER_DECAY_PER_MINUTE: float = 0.12
const SLEEP_HUNGER_DECAY_PER_MINUTE: float = 0.06
const ENERGY_DECAY_PER_MINUTE: float = 0.07
const REST_ENERGY_PER_MINUTE: float = 0.25
const HUNGRY_THRESHOLD: float = 45.0
const CRITICAL_ENERGY_THRESHOLD: float = 18.0
const RESTED_THRESHOLD: float = 72.0
const MEAL_RESTORE: float = 58.0
const EVENING_START: int = 17 * 60
const REST_START: int = 21 * 60
const CONSTRUCTION_REQUEST_MIN_HUNGER: float = 35.0
const CONSTRUCTION_REQUEST_MIN_ENERGY: float = 30.0
const CONSTRUCTION_WORK_MINUTES: int = 12
const INVALID_CELL: Vector2i = Vector2i(-1, -1)

const ACTIVITY_KEYS: Dictionary = {
	ACTIVITY_ARRIVING: "npc.activity.arriving",
	ACTIVITY_MORNING: "npc.activity.morning",
	ACTIVITY_OUTDOORS: "npc.activity.outdoors",
	ACTIVITY_EVENING: "npc.activity.evening",
	ACTIVITY_GOING_TO_MEAL: "npc.activity.going_to_meal",
	ACTIVITY_EATING: "npc.activity.eating",
	ACTIVITY_WAITING_FOR_FOOD: "npc.activity.waiting_for_food",
	ACTIVITY_GOING_TO_REST: "npc.activity.going_to_rest",
	ACTIVITY_RESTING: "npc.activity.resting",
	ACTIVITY_BLOCKED: "npc.activity.blocked",
	ACTIVITY_GOING_TO_BUILD: "npc.activity.going_to_build",
	ACTIVITY_BUILDING: "npc.activity.building",
}

var _catalog
var _pathfinder := Pathfinder.new(
	NavigationData.MAP_SIZE,
	NavigationData.CELL_SIZE,
	NavigationData.blocked_cells()
)


func _init(catalog) -> void:
	_catalog = catalog


func set_structure_cells(structure_cells: Array[Vector2i]) -> void:
	var blocked_cells: Array[Vector2i] = NavigationData.blocked_cells()

	for cell: Vector2i in structure_cells:
		if not blocked_cells.has(cell):
			blocked_cells.append(cell)

	_pathfinder = Pathfinder.new(
		NavigationData.MAP_SIZE,
		NavigationData.CELL_SIZE,
		blocked_cells
	)


func is_cell_walkable(cell: Vector2i) -> bool:
	return _pathfinder.is_walkable(cell)


func find_construction_work_cell(
	target_cell: Vector2i,
	npc_cell: Vector2i,
	player_cell: Vector2i
) -> Vector2i:
	var candidates: Array[Vector2i] = [
		target_cell + Vector2i.DOWN,
		target_cell + Vector2i.RIGHT,
		target_cell + Vector2i.UP,
		target_cell + Vector2i.LEFT,
	]
	var best_cell: Vector2i = INVALID_CELL
	var best_distance: int = 1_000_000

	for candidate: Vector2i in candidates:
		if not _pathfinder.is_walkable(candidate) or candidate == player_cell:
			continue
		var reachable: bool = (
			candidate == npc_cell
			or _pathfinder.next_cell(npc_cell, candidate, player_cell) != npc_cell
		)
		if not reachable:
			continue
		var distance: int = absi(candidate.x - npc_cell.x) + absi(candidate.y - npc_cell.y)
		if distance < best_distance:
			best_cell = candidate
			best_distance = distance

	return best_cell


func advance_minutes(
	npcs: Dictionary,
	previous_minute: int,
	next_minute: int,
	player_position: Vector2,
	blueprint_cells: Array[Vector2i] = []
) -> Dictionary:
	if next_minute <= previous_minute:
		return {
			"changed": false,
			"effects": [],
		}
	var changed: bool = false
	var effects: Array[Dictionary] = []
	for minute: int in range(previous_minute + 1, next_minute + 1):
		for definition: Dictionary in _catalog.get_definitions():
			var npc_id: String = String(definition.get("id", ""))
			if not npcs.has(npc_id):
				continue
			var npc: Dictionary = npcs[npc_id] as Dictionary
			if not bool(npc.get("active", false)):
				continue
			_advance_npc_minute(
				npc,
				definition,
				minute,
				player_position,
				blueprint_cells,
				effects
			)
			changed = true
	return {
		"changed": changed,
		"effects": effects,
	}


func start_morning(npcs: Dictionary, minute: int, first_arrival: bool) -> bool:
	var changed: bool = false
	for definition: Dictionary in _catalog.get_definitions():
		var npc_id: String = String(definition.get("id", ""))
		if not npcs.has(npc_id):
			continue
		var npc: Dictionary = npcs[npc_id] as Dictionary
		if not bool(npc.get("active", false)):
			continue
		var needs: Dictionary = npc.get("needs", {}) as Dictionary
		if not first_arrival:
			needs["hunger"] = maxf(0.0, float(needs.get("hunger", 72.0)) - 10.0)
			needs["energy"] = 92.0
		npc["needs"] = needs
		var autonomy: Dictionary = definition.get("autonomy", {}) as Dictionary
		var target_cell: Vector2i = _cell_from_value(
			autonomy.get("morning_cell", definition.get("position_cell", [24, 29])),
			Vector2i(24, 29)
		)
		_set_activity(npc, ACTIVITY_ARRIVING if first_arrival else ACTIVITY_MORNING, minute)
		npc["target_cell"] = [target_cell.x, target_cell.y]
		npc["moving"] = false
		changed = true
	return changed


func get_activity_key(activity_id: String) -> String:
	return String(ACTIVITY_KEYS.get(activity_id, "npc.activity.unknown"))


func _advance_npc_minute(
	npc: Dictionary,
	definition: Dictionary,
	minute: int,
	player_position: Vector2,
	blueprint_cells: Array[Vector2i],
	effects: Array[Dictionary]
) -> void:
	var needs: Dictionary = npc.get("needs", {}) as Dictionary
	var activity_id: String = String(npc.get("activity_id", ACTIVITY_ARRIVING))
	var resting: bool = activity_id == ACTIVITY_RESTING
	needs["hunger"] = clampf(
		float(needs.get("hunger", 72.0))
		- (SLEEP_HUNGER_DECAY_PER_MINUTE if resting else HUNGER_DECAY_PER_MINUTE),
		0.0,
		100.0
	)
	needs["energy"] = clampf(
		float(needs.get("energy", 82.0))
		+ (REST_ENERGY_PER_MINUTE if resting else -ENERGY_DECAY_PER_MINUTE),
		0.0,
		100.0
	)
	npc["needs"] = needs

	var autonomy: Dictionary = definition.get("autonomy", {}) as Dictionary
	var target_cell: Vector2i
	var travel_activity: String
	var arrival_activity: String
	var hunger: float = float(needs["hunger"])
	var energy: float = float(needs["energy"])
	var personal_inventory: Dictionary = npc.get("personal_inventory", {}) as Dictionary
	var food_count: int = int(personal_inventory.get("core:food", 0))
	var commitment: Dictionary = npc.get("work_commitment", {}) as Dictionary
	if not commitment.is_empty():
		var committed_target: Vector2i = _cell_from_value(
			commitment.get("target_cell"),
			INVALID_CELL
		)
		if not blueprint_cells.has(committed_target):
			var resume_activity: String = String(
				commitment.get("resume_activity_id", ACTIVITY_MORNING)
			)
			npc["work_commitment"] = {}
			_set_activity(npc, resume_activity, minute)
			commitment = {}

	var should_keep_resting: bool = (
		activity_id == ACTIVITY_RESTING
		and minute < REST_START
		and energy < RESTED_THRESHOLD
	)
	if minute >= REST_START or energy <= CRITICAL_ENERGY_THRESHOLD or should_keep_resting:
		target_cell = _cell_from_value(autonomy.get("rest_cell"), Vector2i(25, 23))
		travel_activity = ACTIVITY_GOING_TO_REST
		arrival_activity = ACTIVITY_RESTING
	elif hunger <= HUNGRY_THRESHOLD:
		target_cell = _cell_from_value(autonomy.get("meal_cell"), Vector2i(20, 28))
		travel_activity = ACTIVITY_GOING_TO_MEAL
		arrival_activity = ACTIVITY_EATING if food_count > 0 else ACTIVITY_WAITING_FOR_FOOD
	elif not commitment.is_empty():
		var current_cell: Vector2i = _pathfinder.world_to_cell(_position_from_state(npc))
		var committed_target: Vector2i = _cell_from_value(
			commitment.get("target_cell"),
			INVALID_CELL
		)
		var stored_work_cell: Vector2i = _cell_from_value(
			commitment.get("work_cell"),
			INVALID_CELL
		)
		if stored_work_cell == INVALID_CELL:
			var player_cell: Vector2i = _pathfinder.world_to_cell(player_position)
			stored_work_cell = find_construction_work_cell(
				committed_target,
				current_cell,
				player_cell
			)
			if stored_work_cell != INVALID_CELL:
				commitment["work_cell"] = [
					stored_work_cell.x,
					stored_work_cell.y,
				]
				npc["work_commitment"] = commitment
		if stored_work_cell == INVALID_CELL:
			target_cell = current_cell
			travel_activity = ACTIVITY_BLOCKED
			arrival_activity = ACTIVITY_BLOCKED
		else:
			target_cell = stored_work_cell
			travel_activity = ACTIVITY_GOING_TO_BUILD
			arrival_activity = ACTIVITY_BUILDING
	elif minute < 9 * 60:
		target_cell = _cell_from_value(autonomy.get("morning_cell"), Vector2i(24, 29))
		travel_activity = ACTIVITY_MORNING
		arrival_activity = ACTIVITY_MORNING
	elif minute < EVENING_START:
		target_cell = _cell_from_value(autonomy.get("day_cell"), Vector2i(16, 30))
		travel_activity = ACTIVITY_OUTDOORS
		arrival_activity = ACTIVITY_OUTDOORS
	else:
		target_cell = _cell_from_value(autonomy.get("evening_cell"), Vector2i(21, 28))
		travel_activity = ACTIVITY_EVENING
		arrival_activity = ACTIVITY_EVENING

	npc["target_cell"] = [target_cell.x, target_cell.y]
	var position: Vector2 = _position_from_state(npc)
	var from_cell: Vector2i = _pathfinder.world_to_cell(position)
	if from_cell != target_cell:
		var player_cell: Vector2i = _pathfinder.world_to_cell(player_position)
		if player_cell == target_cell:
			npc["moving"] = false
			_set_activity(npc, ACTIVITY_BLOCKED, minute)
			return
		var next_cell: Vector2i = _pathfinder.next_cell(from_cell, target_cell, player_cell)
		if next_cell == from_cell:
			npc["moving"] = false
			_set_activity(npc, ACTIVITY_BLOCKED, minute)
			return
		var direction: Vector2i = next_cell - from_cell
		npc["position"] = _position_array(_pathfinder.cell_to_world(next_cell))
		npc["facing"] = [float(direction.x), float(direction.y)]
		npc["moving"] = true
		_set_activity(npc, travel_activity, minute)
		return

	npc["moving"] = false
	_set_activity(npc, arrival_activity, minute)
	if arrival_activity == ACTIVITY_EATING and food_count > 0:
		personal_inventory["core:food"] = food_count - 1
		npc["personal_inventory"] = personal_inventory
		needs["hunger"] = minf(100.0, float(needs["hunger"]) + MEAL_RESTORE)
		npc["needs"] = needs
	elif arrival_activity == ACTIVITY_BUILDING and not commitment.is_empty():
		effects.append({
			"type": "advance_construction_work",
			"npc_id": String(npc.get("id", "")),
			"minute": minute,
			"target_cell": (
				commitment.get("target_cell", []) as Array
			).duplicate(),
		})


func _set_activity(npc: Dictionary, activity_id: String, minute: int) -> void:
	if String(npc.get("activity_id", "")) == activity_id:
		return
	npc["activity_id"] = activity_id
	npc["activity_started_minute"] = minute


func _position_from_state(npc: Dictionary) -> Vector2:
	var position: Array = npc.get("position", [0.0, 0.0]) as Array
	if position.size() < 2:
		return Vector2.ZERO
	return Vector2(float(position[0]), float(position[1]))


func _position_array(position: Vector2) -> Array[float]:
	return [position.x, position.y]


func _cell_from_value(value: Variant, fallback: Vector2i) -> Vector2i:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var cell: Array = value as Array
	if cell.size() < 2:
		return fallback
	if (
		(typeof(cell[0]) != TYPE_INT and typeof(cell[0]) != TYPE_FLOAT)
		or (typeof(cell[1]) != TYPE_INT and typeof(cell[1]) != TYPE_FLOAT)
	):
		return fallback
	var result := Vector2i(int(cell[0]), int(cell[1]))
	if not _pathfinder.is_walkable(result):
		return fallback
	return result
