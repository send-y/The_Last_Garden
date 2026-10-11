class_name BuildingCatalog
extends RefCounted

const BUILDINGS_PATH: String = "res://content/core/buildings.json"
const SCHEMA_VERSION: int = 1

var _definitions: Dictionary = {}


func _init() -> void:
	_load_definitions()


func get_definition(building_id: String) -> Dictionary:
	if not _definitions.has(building_id):
		return {}

	return (_definitions[building_id] as Dictionary).duplicate(true)


func all_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for building_id: String in _definitions.keys():
		result.append((_definitions[building_id] as Dictionary).duplicate(true))
	return result


func get_layer_id(building_id: String) -> String:
	return String((_definitions.get(building_id,{}) as Dictionary).get("layer_id", "structure"))


func is_floor(building_id: String) -> bool:
	return get_layer_id(building_id) == "floor"


func get_footprint_size(building_id: String) -> Vector2i:
	var raw_size: Variant = (_definitions.get(building_id,{}) as Dictionary).get("footprint", {})
	if typeof(raw_size) != TYPE_DICTIONARY:
		return Vector2i.ONE
	var footprint: Dictionary = raw_size as Dictionary
	return Vector2i(
		maxi(1, int(footprint.get("width", 1))),
		maxi(1, int(footprint.get("height", 1)))
	)


func get_footprint_cells(building_id: String, origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var footprint_size := get_footprint_size(building_id)
	for y: int in range(footprint_size.y):
		for x: int in range(footprint_size.x):
			result.append(origin + Vector2i(x, y))
	return result


func get_texture_path(building_id: String) -> String:
	return String((_definitions.get(building_id,{}) as Dictionary).get("texture_path", ""))


func get_material_cost(building_id: String) -> Dictionary:
	var definition: Dictionary = _definitions.get(building_id,{})
	var cost_value: Variant = definition.get("material_cost", {})

	if typeof(cost_value) != TYPE_DICTIONARY:
		return {}

	var result: Dictionary = {}

	for item_variant: Variant in (cost_value as Dictionary).keys():
		var item_id: String = String(item_variant)
		var amount_value: Variant = (cost_value as Dictionary)[item_variant]

		if item_id.is_empty() or not item_id.contains(":"):
			continue

		if typeof(amount_value) != TYPE_INT and typeof(amount_value) != TYPE_FLOAT:
			continue

		var amount_number: float = float(amount_value)
		if (
			not is_finite(amount_number)
			or amount_number != floor(amount_number)
			or amount_number <= 0.0
		):
			continue

		result[item_id] = int(amount_number)

	return result


func get_work_minutes(building_id: String) -> int:
	var definition: Dictionary = _definitions.get(building_id,{})
	var value: Variant = definition.get("work_minutes", 0)

	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0

	var number: float = float(value)
	if not is_finite(number) or number != floor(number) or number <= 0.0:
		return 0

	return int(number)


func _load_definitions() -> void:
	var file := FileAccess.open(BUILDINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("Building catalog could not open %s." % BUILDINGS_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Building catalog root must be a dictionary.")
		return

	var data: Dictionary = parsed as Dictionary
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		push_error("Building catalog has an unsupported schema version.")
		return

	var buildings_value: Variant = data.get("buildings", [])
	if typeof(buildings_value) != TYPE_ARRAY:
		push_error("Building catalog has no buildings array.")
		return

	for definition_value: Variant in buildings_value as Array:
		if typeof(definition_value) != TYPE_DICTIONARY:
			continue

		var definition: Dictionary = definition_value as Dictionary
		var building_id: String = String(definition.get("id", ""))

		if building_id.is_empty() or not building_id.contains(":"):
			push_error("Building catalog contains an invalid id.")
			continue

		if _definitions.has(building_id):
			push_error("Building catalog contains duplicate id %s." % building_id)
			continue

		_definitions[building_id] = definition.duplicate(true)
