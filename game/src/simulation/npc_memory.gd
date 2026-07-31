extends RefCounted

const Navigation := preload("res://src/simulation/first_night_navigation.gd")

const MEMORY_FIRST_SHARED_WALL_ID: String = "core:first_shared_wall"
const EVENT_SHARED_WALL_COMPLETED_ID: String = "core:shared_wall_completed"
const SUBJECT_PLAYER_ID: String = "core:player"
const KIND_SHARED_EXPERIENCE_ID: String = "core:shared_experience"
const SOURCE_PERSONAL_EXPERIENCE_ID: String = "core:personal_experience"
const VALENCE_POSITIVE_ID: String = "core:positive"

const AXIS_TRUST: String = "trust"
const AXIS_WARMTH: String = "warmth"
const AXIS_RESPECT: String = "respect"
const RELATIONSHIP_MIN: float = -100.0
const RELATIONSHIP_MAX: float = 100.0


static func create_first_shared_wall(
	day: int,
	minute: int,
	target_cell: Vector2i
) -> Dictionary:
	return {
		"memory_id": MEMORY_FIRST_SHARED_WALL_ID,
		"event_id": EVENT_SHARED_WALL_COMPLETED_ID,
		"subject_id": SUBJECT_PLAYER_ID,
		"kind_id": KIND_SHARED_EXPERIENCE_ID,
		"source_id": SOURCE_PERSONAL_EXPERIENCE_ID,
		"valence_id": VALENCE_POSITIVE_ID,
		"day": maxi(1, day),
		"minute": clampi(minute, 0, 24 * 60 - 1),
		"salience": 1.0,
		"relationship_effects": {
			AXIS_TRUST: 1.0,
			AXIS_WARMTH: 2.0,
			AXIS_RESPECT: 1.0,
		},
		"acknowledged": false,
		"target_cell": [target_cell.x, target_cell.y],
	}


static func normalize_memories(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	var seen_ids: Dictionary = {}
	for memory_value: Variant in value as Array:
		var memory: Dictionary = _normalize_memory(memory_value)
		if memory.is_empty():
			continue
		var memory_id: String = String(memory.get("memory_id", ""))
		if seen_ids.has(memory_id):
			continue
		seen_ids[memory_id] = true
		result.append(memory)
	return result


static func has_memory(memories: Array, memory_id: String) -> bool:
	for memory_value: Variant in memories:
		if typeof(memory_value) != TYPE_DICTIONARY:
			continue
		if String((memory_value as Dictionary).get("memory_id", "")) == memory_id:
			return true
	return false


static func relationship_from_memories(memories: Array) -> Dictionary:
	var result: Dictionary = {
		AXIS_TRUST: 0.0,
		AXIS_WARMTH: 0.0,
		AXIS_RESPECT: 0.0,
	}
	for memory_value: Variant in memories:
		if typeof(memory_value) != TYPE_DICTIONARY:
			continue
		var memory: Dictionary = memory_value as Dictionary
		var salience: float = clampf(float(memory.get("salience", 0.0)), 0.0, 1.0)
		var effects: Dictionary = memory.get("relationship_effects", {}) as Dictionary
		for axis: String in [AXIS_TRUST, AXIS_WARMTH, AXIS_RESPECT]:
			result[axis] = clampf(
				float(result[axis]) + float(effects.get(axis, 0.0)) * salience,
				RELATIONSHIP_MIN,
				RELATIONSHIP_MAX
			)
	return result


static func _normalize_memory(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var memory: Dictionary = value as Dictionary
	for id_field: String in [
		"memory_id",
		"event_id",
		"subject_id",
		"kind_id",
		"source_id",
		"valence_id",
	]:
		if not String(memory.get(id_field, "")).contains(":"):
			return {}
	if not _is_valid_cell(memory.get("target_cell")):
		return {}

	var day: int = _safe_int(memory.get("day"), 0)
	var minute: int = _safe_int(memory.get("minute"), -1)
	var salience: float = _safe_float(memory.get("salience"), -1.0)
	if day < 1 or minute < 0 or minute >= 24 * 60 or salience < 0.0:
		return {}

	var effects_value: Variant = memory.get("relationship_effects", {})
	if typeof(effects_value) != TYPE_DICTIONARY:
		return {}
	var effects: Dictionary = effects_value as Dictionary
	var normalized_effects: Dictionary = {}
	for axis: String in [AXIS_TRUST, AXIS_WARMTH, AXIS_RESPECT]:
		var effect: float = _safe_float(effects.get(axis), 0.0)
		normalized_effects[axis] = clampf(
			effect,
			RELATIONSHIP_MIN,
			RELATIONSHIP_MAX
		)

	var target_cell: Array = memory.get("target_cell") as Array
	return {
		"memory_id": String(memory.get("memory_id", "")),
		"event_id": String(memory.get("event_id", "")),
		"subject_id": String(memory.get("subject_id", "")),
		"kind_id": String(memory.get("kind_id", "")),
		"source_id": String(memory.get("source_id", "")),
		"valence_id": String(memory.get("valence_id", "")),
		"day": day,
		"minute": minute,
		"salience": clampf(salience, 0.0, 1.0),
		"relationship_effects": normalized_effects,
		"acknowledged": _safe_bool(memory.get("acknowledged"), false),
		"target_cell": [int(target_cell[0]), int(target_cell[1])],
	}


static func _is_valid_cell(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var cell: Array = value as Array
	if cell.size() != 2:
		return false
	var x: int = _safe_int(cell[0], -1)
	var y: int = _safe_int(cell[1], -1)
	if x < 0 or y < 0:
		return false
	return Rect2i(Vector2i.ZERO, Navigation.MAP_SIZE).has_point(Vector2i(x, y))


static func _safe_bool(value: Variant, fallback: bool) -> bool:
	return bool(value) if typeof(value) == TYPE_BOOL else fallback


static func _safe_int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) != TYPE_FLOAT:
		return fallback
	var number: float = float(value)
	if not is_finite(number) or number != floor(number):
		return fallback
	return int(number)


static func _safe_float(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var number: float = float(value)
	return number if is_finite(number) else fallback
