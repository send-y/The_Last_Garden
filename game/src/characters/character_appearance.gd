class_name CharacterAppearance
extends RefCounted

const PARTS_PATH: String = "res://content/core/character_parts.json"
const DEFAULT_PLAYER_OUTFIT_ID: String = "core:player_placeholder"

var _frame_size: Vector2i = Vector2i(32, 32)
var _directions: Array[String] = []
var _frames_per_direction: int = 4
var _slot_order: Array[String] = []
var _required_slots: Dictionary = {}
var _parts_by_id: Dictionary = {}
var _parts_by_slot: Dictionary = {}
var _outfits: Dictionary = {}


func _init() -> void:
	_load()
	_validate_content()


func get_frame_size() -> Vector2i:
	return _frame_size


func get_directions() -> Array[String]:
	return _directions.duplicate()


func get_frames_per_direction() -> int:
	return _frames_per_direction


func get_slot_order() -> Array[String]:
	return _slot_order.duplicate()


func get_default_player_appearance() -> Dictionary:
	return get_outfit(DEFAULT_PLAYER_OUTFIT_ID)


func get_outfit(outfit_id: String) -> Dictionary:
	var outfit: Dictionary = _outfits.get(outfit_id, {}) as Dictionary
	var result: Dictionary = {}
	for slot_id: String in _slot_order:
		if outfit.has(slot_id):
			result[slot_id] = String(outfit[slot_id])
	return result


func generate_npc_appearance(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var result: Dictionary = {}
	for slot_id: String in _slot_order:
		result[slot_id] = _choose_weighted_part(slot_id, rng)
	return result


func validate_appearance(appearance: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for slot_id: String in _slot_order:
		var part_id: String = String(appearance.get(slot_id, ""))
		if part_id.is_empty():
			if bool(_required_slots.get(slot_id, false)):
				errors.append("Missing required appearance slot: %s." % slot_id)
			continue

		if not _parts_by_id.has(part_id):
			errors.append("Unknown appearance part id: %s." % part_id)
			continue

		var part: Dictionary = _parts_by_id[part_id] as Dictionary
		var part_slot: String = String(part.get("slot", ""))
		if part_slot != slot_id:
			errors.append("Part %s belongs to slot %s, not %s." % [part_id, part_slot, slot_id])
	return errors


func get_part(part_id: String) -> Dictionary:
	return (_parts_by_id.get(part_id, {}) as Dictionary).duplicate(true)


func get_part_for_slot(appearance: Dictionary, slot_id: String) -> Dictionary:
	var part_id: String = String(appearance.get(slot_id, ""))
	if part_id.is_empty():
		return {}
	return get_part(part_id)


func get_layered_parts(appearance: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for slot_id: String in _slot_order:
		var part: Dictionary = get_part_for_slot(appearance, slot_id)
		if part.is_empty() or bool(part.get("empty", false)):
			continue
		parts.append(part)
	parts.sort_custom(_sort_parts_by_layer)
	return parts


func _choose_weighted_part(slot_id: String, rng: RandomNumberGenerator) -> String:
	var parts: Array = _parts_by_slot.get(slot_id, []) as Array
	if parts.is_empty():
		return ""

	var total_weight: float = 0.0
	for part_variant: Variant in parts:
		var part: Dictionary = part_variant as Dictionary
		total_weight += maxf(float(part.get("weight", 1.0)), 0.0)

	if total_weight <= 0.0:
		return String((parts[0] as Dictionary).get("id", ""))

	var roll: float = rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for part_variant: Variant in parts:
		var part: Dictionary = part_variant as Dictionary
		cursor += maxf(float(part.get("weight", 1.0)), 0.0)
		if roll <= cursor:
			return String(part.get("id", ""))
	return String((parts[parts.size() - 1] as Dictionary).get("id", ""))


func _sort_parts_by_layer(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("layer", 0)) < int(b.get("layer", 0))


func _load() -> void:
	var data: Dictionary = _read_json(PARTS_PATH)
	var frame: Dictionary = data.get("frame", {}) as Dictionary
	var size: Array = frame.get("size", [32, 32]) as Array
	_frame_size = Vector2i(int(size[0]), int(size[1]))
	_frames_per_direction = int(frame.get("frames_per_direction", 4))

	_directions.clear()
	var directions: Array = frame.get("directions", ["down", "left", "right", "up"]) as Array
	for direction_variant: Variant in directions:
		_directions.append(String(direction_variant))

	var slots: Array = data.get("slots", []) as Array
	for slot_variant: Variant in slots:
		var slot: Dictionary = slot_variant as Dictionary
		var slot_id: String = String(slot.get("id", ""))
		if slot_id.is_empty():
			push_error("Character appearance slot without id in %s." % PARTS_PATH)
			continue
		_slot_order.append(slot_id)
		_required_slots[slot_id] = bool(slot.get("required", false))
		_parts_by_slot[slot_id] = []

	var parts: Array = data.get("parts", []) as Array
	for part_variant: Variant in parts:
		var part: Dictionary = (part_variant as Dictionary).duplicate(true)
		var part_id: String = String(part.get("id", ""))
		var slot_id: String = String(part.get("slot", ""))
		if part_id.is_empty() or slot_id.is_empty():
			push_error("Character appearance part must have id and slot in %s." % PARTS_PATH)
			continue
		_parts_by_id[part_id] = part
		if not _parts_by_slot.has(slot_id):
			_parts_by_slot[slot_id] = []
		(_parts_by_slot[slot_id] as Array).append(part)

	_outfits = (data.get("outfits", {}) as Dictionary).duplicate(true)


func _validate_content() -> void:
	if _frame_size != Vector2i(32, 32):
		push_error("Character appearance prototype expects 32x32 frames.")
	if _frames_per_direction != 4:
		push_error("Character appearance prototype expects four frames per direction.")

	for slot_id: String in _slot_order:
		if (_parts_by_slot.get(slot_id, []) as Array).is_empty():
			push_error("Character appearance slot has no parts: %s." % slot_id)

	for part_id_variant: Variant in _parts_by_id.keys():
		var part_id: String = String(part_id_variant)
		if not part_id.contains(":"):
			push_error("Character appearance part id should be namespaced: %s." % part_id)
		var part: Dictionary = _parts_by_id[part_id] as Dictionary
		var slot_id: String = String(part.get("slot", ""))
		if not _required_slots.has(slot_id):
			push_error("Character appearance part %s references unknown slot %s." % [part_id, slot_id])

	for outfit_id_variant: Variant in _outfits.keys():
		var outfit_id: String = String(outfit_id_variant)
		var errors: Array[String] = validate_appearance(_outfits[outfit_id] as Dictionary)
		for error: String in errors:
			push_error("Outfit %s is invalid: %s" % [outfit_id, error])


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing character appearance content file: %s." % path)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open character appearance content file: %s." % path)
		return {}

	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Character appearance content is not a JSON object: %s." % path)
		return {}
	return parsed as Dictionary
