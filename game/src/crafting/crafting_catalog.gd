class_name CraftingCatalog
extends RefCounted

const RECIPES_PATH: String = "res://content/core/recipes.json"
const SCHEMA_VERSION: int = 2

var _definitions: Dictionary = {}
var _inactive_inputs: Dictionary = {}
var _order: Array[String] = []
var _unlocks: Dictionary = {}

func has_unlock(id: String) -> bool:
	return _unlocks.has(id)


var content: FirstNightContent
var reference_errors: Array[String] = []
var _recipes_path: String = RECIPES_PATH

func _init(item_content: FirstNightContent = null, recipes_path: String = RECIPES_PATH) -> void:
	content = item_content if item_content != null else FirstNightContent.new()
	_recipes_path = recipes_path
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


func get_inactive_inputs(recipe_id: String) -> Dictionary:
	return (_inactive_inputs.get(recipe_id, {}) as Dictionary).duplicate(true)


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
	var file := FileAccess.open(_recipes_path, FileAccess.READ)
	if file == null:
		push_error("Crafting catalog could not open %s." % _recipes_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Crafting catalog root must be a dictionary.")
		return
	var data := parsed as Dictionary
	if int(data.get("schema_version", 0)) not in [1, SCHEMA_VERSION]:
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
		var definition_errors := validate_definition(definition)
		if not definition_errors.is_empty():
			for error: String in definition_errors: push_error(error)
			continue
		var recipe_id := String(definition.get("id", ""))
		if recipe_id.is_empty() or not recipe_id.contains(":") or _definitions.has(recipe_id):
			push_error("Crafting catalog contains invalid or duplicate id %s." % recipe_id)
			continue
		var refs: Array[Dictionary] = []
		if definition.has("requires_discovery"):
			refs.append({"source_path":RECIPES_PATH,"owner_id":recipe_id,"field":"requires_discovery","item_id":String(definition.requires_discovery)})
		for field: String in ["inputs", "outputs"]:
			for id: String in definition.get(field, {}):
				refs.append({"source_path": RECIPES_PATH, "owner_id": recipe_id, "field": field, "item_id": id})
		var errors := content.validate_item_references(refs)
		reference_errors.append_array(errors)
		content.report_reference_errors(errors)
		if not errors.is_empty():
			_inactive_inputs[recipe_id] = _positive_item_amounts(definition.get("inputs", {}))
			continue
		_definitions[recipe_id] = definition.duplicate(true)
		_order.append(recipe_id)
		for unlock: String in definition.get("unlocks", []): _unlocks[unlock] = true
	for id: String in _order.duplicate():
		var required := String(_definitions[id].get("requires_unlock", ""))
		if not required.is_empty() and not _unlocks.has(required):
			push_error("Recipe %s requires unknown unlock %s" % [id, required])
			_definitions.erase(id)
			_order.erase(id)

static func validate_definition(recipe: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var prefix := "Recipe %s " % str(recipe.get("id", "<missing>"))
	for key: Variant in recipe:
		if key not in ["id", "label_key", "station_type", "inputs", "outputs", "work_minutes", "requires_discovery", "requires_unlock", "unlocks"]: errors.append(prefix + str(key) + ": unknown field")
	for field: String in ["id", "label_key", "station_type"]:
		if not recipe.get(field) is String or String(recipe.get(field, "")).is_empty(): errors.append(prefix + field + ": nonempty string required")
	var work: Variant = recipe.get("work_minutes")
	if not (typeof(work) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(work)) or float(work) <= 0 or float(work) > 1440 or float(work) != floor(float(work)): errors.append(prefix + "work_minutes: integer in 1..1440 required")
	for field: String in ["inputs", "outputs"]:
		var amounts: Variant = recipe.get(field)
		if not amounts is Dictionary:
			errors.append(prefix + field + ": object required")
			continue
		for id: Variant in amounts:
			var amount: Variant = amounts[id]
			if not id is String or not String(id).contains(":") or not (typeof(amount) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(amount)) or float(amount) < 1 or float(amount) > 10000 or float(amount) != floor(float(amount)): errors.append(prefix + field + ": positive integer amounts required")
	for field: String in ["requires_discovery", "requires_unlock"]:
		if recipe.has(field) and (not recipe[field] is String or not String(recipe[field]).contains(":")): errors.append(prefix + field + ": namespaced id required")
	var grants: Variant = recipe.get("unlocks", [])
	if not grants is Array:
		errors.append(prefix + "unlocks: array required")
	else:
		var seen := {}
		for id: Variant in grants:
			if not id is String or not String(id).contains(":") or seen.has(id): errors.append(prefix + "unlocks: unique namespaced ids required")
			seen[id] = true
	var inputs: Variant = recipe.get("inputs")
	var outputs: Variant = recipe.get("outputs")
	if inputs is Dictionary and outputs is Dictionary and (inputs.is_empty() or (outputs.is_empty() and (not grants is Array or grants.is_empty()))): errors.append(prefix + "inputs/outputs: work must consume input and produce an item or unlock")
	return errors


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
