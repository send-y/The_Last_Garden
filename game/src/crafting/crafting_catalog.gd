class_name CraftingCatalog
extends RefCounted

const RECIPES_PATH: String = "res://content/core/recipes.json"
const SCHEMA_VERSION: int = 1

var _definitions: Dictionary = {}
var _order: Array[String] = []


func _init() -> void:
	_load_definitions()


func get_definition(recipe_id: String) -> Dictionary:
	if not _definitions.has(recipe_id):
		return {}
	return (_definitions[recipe_id] as Dictionary).duplicate(true)


func recipes_for_station(station_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id: String in _order:
		var definition: Dictionary = _definitions[recipe_id] as Dictionary
		if String(definition.get("station_type", "")) == station_type:
			result.append(definition.duplicate(true))
	return result


func get_inputs(recipe_id: String) -> Dictionary:
	return _positive_item_amounts(get_definition(recipe_id).get("inputs", {}))


func get_outputs(recipe_id: String) -> Dictionary:
	return _positive_item_amounts(get_definition(recipe_id).get("outputs", {}))


func get_work_minutes(recipe_id: String) -> int:
	var value: Variant = get_definition(recipe_id).get("work_minutes", 0)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	var number := float(value)
	if not is_finite(number) or number != floor(number) or number <= 0.0:
		return 0
	return int(number)


func _load_definitions() -> void:
	var file := FileAccess.open(RECIPES_PATH, FileAccess.READ)
	if file == null:
		push_error("Crafting catalog could not open %s." % RECIPES_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Crafting catalog root must be a dictionary.")
		return
	var data := parsed as Dictionary
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		push_error("Crafting catalog has an unsupported schema version.")
		return
	var recipes_value: Variant = data.get("recipes", [])
	if typeof(recipes_value) != TYPE_ARRAY:
		push_error("Crafting catalog has no recipes array.")
		return
	for definition_value: Variant in recipes_value as Array:
		if typeof(definition_value) != TYPE_DICTIONARY:
			continue
		var definition := definition_value as Dictionary
		var recipe_id := String(definition.get("id", ""))
		if recipe_id.is_empty() or not recipe_id.contains(":") or _definitions.has(recipe_id):
			push_error("Crafting catalog contains invalid or duplicate id %s." % recipe_id)
			continue
		_definitions[recipe_id] = definition.duplicate(true)
		_order.append(recipe_id)


static func _positive_item_amounts(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for item_variant: Variant in (value as Dictionary).keys():
		var item_id := String(item_variant)
		var amount_value: Variant = (value as Dictionary)[item_variant]
		if item_id.is_empty() or not item_id.contains(":"):
			continue
		if typeof(amount_value) != TYPE_INT and typeof(amount_value) != TYPE_FLOAT:
			continue
		var amount_number := float(amount_value)
		if is_finite(amount_number) and amount_number == floor(amount_number) and amount_number > 0.0:
			result[item_id] = int(amount_number)
	return result
