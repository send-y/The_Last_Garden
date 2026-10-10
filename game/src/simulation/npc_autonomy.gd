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
const ACTIVITY_SLEEPING: String = "core:sleeping"
const ACTIVITY_CHAIR_RESTING := "core:chair_resting"
const ACTIVITY_TABLE_EATING := "core:table_eating"
const ACTIVITY_COLLECTING_MEAL := "core:collecting_meal"
const ACTIVITY_BLOCKED: String = "core:blocked"
const ACTIVITY_GOING_TO_BUILD: String = "core:going_to_build"
const ACTIVITY_BUILDING: String = "core:building"

const HUNGRY_THRESHOLD: float = 55.0
const CRITICAL_ENERGY_THRESHOLD: float = 18.0
const RESTED_THRESHOLD: float = 72.0
const EVENING_START: int = 17 * 60
const REST_START: int = 21 * 60
const CONSTRUCTION_REQUEST_MIN_HUNGER: float = 35.0
const CONSTRUCTION_REQUEST_MIN_ENERGY: float = 30.0
const CONSTRUCTION_WORK_MINUTES: int = 12
const INVALID_CELL: Vector2i = Vector2i(-1, -1)

const ACTIVITY_KEYS: Dictionary = {
	"core:work_craft_take": "npc.activity.work_craft_take",
	"core:work_craft": "npc.activity.work_craft",
	"core:work_travel": "npc.activity.work_travel",
	"core:work_borrow": "npc.activity.work_borrow",
	"core:work_refill": "npc.activity.work_refill",
	"core:work_work": "npc.activity.work_work",
	"core:work_collect": "npc.activity.work_collect",
	"core:work_take_materials": "npc.activity.work_take_materials",
	"core:work_deliver": "npc.activity.work_deliver",
	"core:work_build": "npc.activity.work_build",
	"core:work_switch_on": "npc.activity.work_switch_on",
	"core:work_return": "npc.activity.work_return",
	"core:work_watering": "npc.activity.work_watering",
	"core:work_chopping": "npc.activity.work_chopping",
	"core:work_mining": "npc.activity.work_mining",
	ACTIVITY_ARRIVING: "npc.activity.arriving",
	ACTIVITY_MORNING: "npc.activity.morning",
	ACTIVITY_OUTDOORS: "npc.activity.outdoors",
	ACTIVITY_EVENING: "npc.activity.evening",
	ACTIVITY_GOING_TO_MEAL: "npc.activity.going_to_meal",
	ACTIVITY_EATING: "npc.activity.eating",
	ACTIVITY_WAITING_FOR_FOOD: "npc.activity.waiting_for_food",
	ACTIVITY_GOING_TO_REST: "npc.activity.going_to_rest",
	ACTIVITY_RESTING: "npc.activity.resting",
	ACTIVITY_SLEEPING: "npc.activity.sleeping",
	ACTIVITY_CHAIR_RESTING: "npc.activity.chair_resting",
	ACTIVITY_TABLE_EATING: "npc.activity.table_eating",
	ACTIVITY_COLLECTING_MEAL: "npc.activity.collecting_meal",
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


func can_reach(from: Vector2i, target: Vector2i, _blocker: Vector2i = Vector2i(-1, -1)) -> bool:
	# Keep call compatibility: actor positions no longer obstruct travel.
	return _pathfinder.is_walkable(target) and (from == target or _pathfinder.next_cell(from, target) != from)


func find_temporary_rest_cell(preferred: Vector2i, from: Vector2i, _blocker: Vector2i) -> Vector2i:
	# Keep temporary rest physically reachable when furniture blocks the old spot.
	for radius: int in range(9):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius:
					continue
				var candidate := preferred + Vector2i(x, y)
				if can_reach(from, candidate):
					return candidate
	return from


func find_construction_work_cell(
	target_cell: Vector2i,
	npc_cell: Vector2i,
	_player_cell: Vector2i
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
		if not _pathfinder.is_walkable(candidate):
			continue
		var reachable: bool = (
			candidate == npc_cell
			or _pathfinder.next_cell(npc_cell, candidate) != npc_cell
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
	blueprint_cells: Array[Vector2i] = [],
	meals: Dictionary = {},
	practical_work: Dictionary = {},
	homes: Dictionary = {},
	furniture: Dictionary = {}
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
				effects,
				meals.get(npc_id, {}),
				practical_work.get(npc_id, {}),
				homes.get(npc_id, {}),
				furniture.get(npc_id,{})
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
	effects: Array[Dictionary],
	meal: Dictionary = {},
	practical: Dictionary = {},
	home: Dictionary = {},
	furniture: Dictionary = {}
) -> void:
	var needs: Dictionary = npc.get("needs", {}) as Dictionary
	var activity_id: String = String(npc.get("activity_id", ACTIVITY_ARRIVING))

	var autonomy: Dictionary = definition.get("autonomy", {}) as Dictionary
	var target_cell: Vector2i
	var travel_activity: String
	var arrival_activity: String
	var hunger: float = float(needs["hunger"])
	var energy: float = float(needs["energy"])
	var food_count: int = 0 if meal.is_empty() else 1
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
		activity_id in [ACTIVITY_RESTING, ACTIVITY_SLEEPING,ACTIVITY_CHAIR_RESTING]
		and minute < REST_START
		and energy < RESTED_THRESHOLD
	)
	var urgent_meal := hunger <= 35 and food_count > 0
	if String(furniture.get("kind","")) == "meal":
		target_cell = Vector2i(int(furniture.target_cell[0]),int(furniture.target_cell[1]))
		travel_activity = ACTIVITY_GOING_TO_MEAL
		arrival_activity = ACTIVITY_TABLE_EATING
	elif (minute >= REST_START or minute < 7 * 60 or energy <= CRITICAL_ENERGY_THRESHOLD or should_keep_resting) and not urgent_meal:
		target_cell = _cell_from_value(home.get("target_cell", autonomy.get("rest_cell")), Vector2i(25, 23))
		if home.is_empty():
			target_cell = find_temporary_rest_cell(target_cell, _pathfinder.world_to_cell(_position_from_state(npc)), _pathfinder.world_to_cell(player_position))
		travel_activity = ACTIVITY_GOING_TO_REST
		arrival_activity = ACTIVITY_SLEEPING if not home.is_empty() and (minute >= REST_START or minute < 7 * 60) else ACTIVITY_RESTING
		if minute >= 7 * 60 and minute < REST_START and String(furniture.get("kind","")) == "rest":
			target_cell = Vector2i(int(furniture.target_cell[0]),int(furniture.target_cell[1]))
			arrival_activity = ACTIVITY_CHAIR_RESTING
	elif hunger <= HUNGRY_THRESHOLD or not npc.get("meal_trip",{}).is_empty():
		target_cell = _cell_from_value(meal.get("target_cell", autonomy.get("meal_cell")), Vector2i(20, 28))
		# The food system validates the seat; its owner may already occupy its solid cell.
		if not meal.get("seat",{}).is_empty():
			target_cell = Vector2i(int(meal.target_cell[0]),int(meal.target_cell[1]))
		travel_activity = ACTIVITY_GOING_TO_MEAL
		arrival_activity = (ACTIVITY_COLLECTING_MEAL if bool(meal.get("carry",false)) else ACTIVITY_EATING) if food_count > 0 else ACTIVITY_WAITING_FOR_FOOD
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
	elif not practical.is_empty():
		target_cell = _cell_from_value(practical.target_cell, INVALID_CELL)
		travel_activity = String(practical.travel_activity)
		arrival_activity = String(practical.arrival_activity)
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
		var next_cell: Vector2i = _pathfinder.next_cell(from_cell, target_cell)
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
	if arrival_activity in [ACTIVITY_EATING,ACTIVITY_COLLECTING_MEAL] and food_count > 0:
		effects.append({"type": "consume_meal", "npc_id": String(npc.id), "meal": meal.duplicate(true)})
	elif arrival_activity == ACTIVITY_CHAIR_RESTING and npc.get("furniture_use",{}).is_empty():
		effects.append({"type":"sit_for_rest","npc_id":String(npc.id),"seat":furniture})
	elif not practical.is_empty() and arrival_activity == String(practical.arrival_activity):
		effects.append({"type": "advance_initiative", "npc_id": String(npc.id), "context": practical})
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
