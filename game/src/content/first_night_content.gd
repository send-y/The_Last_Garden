class_name FirstNightContent
extends RefCounted

const CELL_SIZE: int = 32
const MAP_SIZE: Vector2i = Vector2i(48, 48)
const INTERACTION_RANGE: float = 68.0

const WOOD_ID: String = "core:wood"
const STONE_ID: String = "core:stone"
const RAW_WATER_ID: String = "core:raw_water"
const BOILED_WATER_ID: String = "core:boiled_water"
const FOOD_ID: String = "core:food"

const ITEMS_PATH: String = "res://content/core/items.json"
const OBJECTS_PATH: String = "res://content/core/first_night_objects.json"
const PROGRESSION_PATH: String = "res://content/core/first_night_progression.json"

const LEGACY_ITEM_IDS: Dictionary = {
	"wood": WOOD_ID,
	"stone": STONE_ID,
	"raw_water": RAW_WATER_ID,
	"boiled_water": BOILED_WATER_ID,
	"food": FOOD_ID,
}

const InventoryShapeRules := preload(
	"res://src/inventory/inventory_shape.gd"
)

const LEGACY_OBJECT_IDS: Dictionary = {
	"common_house": "core:common_house",
	"old_tools": "core:old_tools",
	"repair_room": "core:repair_room",
	"campfire_site": "core:campfire_site",
	"bed_site": "core:bed_site",
	"wood_north": "core:wood_north",
	"wood_west": "core:wood_west",
	"wood_east": "core:wood_east",
	"stone_south": "core:stone_south",
	"stone_east": "core:stone_east",
	"shore_water": "core:shore_water",
	"berry_bush": "core:berry_bush",
}

var _item_defs: Dictionary = {}
var _item_order: Array[String] = []
var _object_defs: Dictionary = {}
var _object_order: Array[String] = []
var _collect_rules: Dictionary = {}
var _message_keys: Dictionary = {}
var _failure_message_keys: Dictionary = {}
var _stage_label_keys: Dictionary = {}
var _costs: Dictionary = {}


func _init() -> void:
	_load_items()
	_load_objects()
	_load_progression()
	_validate()


static func cell_center(x: int, y: int) -> Vector2:
	return Vector2(float(x * CELL_SIZE + CELL_SIZE / 2), float(y * CELL_SIZE + CELL_SIZE / 2))


func normalize_item_id(item_id: String) -> String:
	return String(LEGACY_ITEM_IDS.get(item_id, item_id))


func normalize_object_id(object_id: String) -> String:
	return String(LEGACY_OBJECT_IDS.get(object_id, object_id))


func has_item(item_id: String) -> bool:
	return _item_defs.has(normalize_item_id(item_id))

func item_ids() -> Array[String]:
	var result: Array[String] = []
	result.append_array(_item_order)
	return result

func item_weight(item_id: String) -> float:
	var normalized_id: String = normalize_item_id(item_id)
	var definition: Dictionary = _item_defs.get(normalized_id, {}) as Dictionary
	return float(definition.get("weight", 0.0))


func item_label_key(item_id: String) -> String:
	var normalized_id: String = normalize_item_id(item_id)
	var definition: Dictionary = _item_defs.get(normalized_id, {}) as Dictionary
	return String(definition.get("label_key", normalized_id))


func item_icon_path(item_id: String) -> String:
	var normalized_id: String = normalize_item_id(item_id)
	var definition: Dictionary = (
		_item_defs.get(normalized_id, {}) as Dictionary
	)
	return String(definition.get("icon_path", ""))


func item_max_stack(item_id: String) -> int:
	var normalized_id: String = normalize_item_id(item_id)
	var definition: Dictionary = (
		_item_defs.get(normalized_id, {}) as Dictionary
	)
	return maxi(1, int(definition.get("max_stack", 1)))


func item_footprint(
	item_id: String,
	quarter_turns: int = 0
) -> Array[Vector2i]:
	var normalized_id: String = normalize_item_id(item_id)
	var definition: Dictionary = (
		_item_defs.get(normalized_id, {}) as Dictionary
	)
	var raw_footprint := (
		definition.get("footprint", []) as Array
	)
	var footprint: Array[Vector2i] = (
		InventoryShapeRules.from_raw(raw_footprint)
	)

	if footprint.is_empty():
		footprint.append(Vector2i.ZERO)

	return InventoryShapeRules.rotated(
		footprint,
		quarter_turns
	)

func create_empty_inventory() -> Dictionary:
	var inventory: Dictionary = {}
	for item_id: String in _item_order:
		inventory[item_id] = 0
	return inventory


func normalize_inventory(raw_inventory: Dictionary) -> Dictionary:
	var inventory: Dictionary = create_empty_inventory()
	for item_variant: Variant in raw_inventory.keys():
		var item_id: String = normalize_item_id(String(item_variant))
		if not item_id.contains(":"):
			continue
		var raw_amount: Variant = raw_inventory[item_variant]
		if not _is_finite_integer(raw_amount):
			continue
		var amount: int = maxi(0, int(raw_amount))
		inventory[item_id] = int(inventory.get(item_id, 0)) + amount
	return inventory


func normalize_collected(raw_collected: Dictionary) -> Dictionary:
	var collected: Dictionary = {}
	for object_variant: Variant in raw_collected.keys():
		var object_id: String = normalize_object_id(String(object_variant))
		if not object_id.contains(":") or typeof(raw_collected[object_variant]) != TYPE_BOOL:
			continue
		collected[object_id] = raw_collected[object_variant]
	return collected


func get_interactable(object_id: String) -> Dictionary:
	var normalized_id: String = normalize_object_id(object_id)
	if not _object_defs.has(normalized_id):
		return {}
	return _build_interactable(normalized_id, _object_defs[normalized_id] as Dictionary)


func interactables() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object_id: String in _object_order:
		result.append(_build_interactable(object_id, _object_defs[object_id] as Dictionary))
	return result


func has_collect_rule(kind: String) -> bool:
	return _collect_rules.has(kind)


func get_collect_rule(kind: String) -> Dictionary:
	return (_collect_rules.get(kind, {}) as Dictionary).duplicate(true)


func is_collect_rule_repeatable(kind: String) -> bool:
	var rule: Dictionary = _collect_rules.get(kind, {}) as Dictionary
	return bool(rule.get("repeatable", false))


func get_message_key(message_id: String, fallback_key: String = "") -> String:
	return String(_message_keys.get(message_id, fallback_key))


func get_failure_message_key(message_id: String, fallback_key: String = "") -> String:
	return String(_failure_message_keys.get(message_id, fallback_key))


func get_stage_label_key(kind: String, stage: int, fallback_key: String) -> String:
	var label_keys: Array = _stage_label_keys.get(kind, []) as Array
	if label_keys.is_empty():
		return fallback_key
	var safe_stage: int = clampi(stage, 0, label_keys.size() - 1)
	return String(label_keys[safe_stage])


func get_cost(cost_id: String) -> Dictionary:
	return (_costs.get(cost_id, {}) as Dictionary).duplicate(true)


func _build_interactable(object_id: String, definition: Dictionary) -> Dictionary:
	var cell: Array = definition.get("cell", [0, 0]) as Array
	var size: Array = definition.get("size", [24.0, 20.0]) as Array
	return {
		"id": object_id,
		"kind": String(definition.get("kind", "")),
		"label_key": String(definition.get("label_key", object_id)),
		"position": cell_center(int(cell[0]), int(cell[1])),
		"color": Color(String(definition.get("color", "ffffff"))),
		"size": Vector2(float(size[0]), float(size[1])),
	}


func _load_items() -> void:
	var data: Dictionary = _read_json(ITEMS_PATH)
	var items: Array = data.get("items", []) as Array
	for item_variant: Variant in items:
		var item: Dictionary = item_variant as Dictionary
		var item_id: String = String(item.get("id", ""))
		if item_id.is_empty():
			push_error("Item content entry without id in %s." % ITEMS_PATH)
			continue
		_item_defs[item_id] = item.duplicate(true)
		_item_order.append(item_id)


func _load_objects() -> void:
	var data: Dictionary = _read_json(OBJECTS_PATH)
	var objects: Array = data.get("objects", []) as Array
	for object_variant: Variant in objects:
		var object_def: Dictionary = object_variant as Dictionary
		var object_id: String = String(object_def.get("id", ""))
		if object_id.is_empty():
			push_error("Object content entry without id in %s." % OBJECTS_PATH)
			continue
		_object_defs[object_id] = object_def.duplicate(true)
		_object_order.append(object_id)

	var rules: Dictionary = data.get("collect_rules", {}) as Dictionary
	for kind_variant: Variant in rules.keys():
		var kind: String = String(kind_variant)
		var rule: Dictionary = (rules[kind_variant] as Dictionary).duplicate(true)
		rule["item_id"] = normalize_item_id(String(rule.get("item_id", "")))
		_collect_rules[kind] = rule

	var map: Dictionary = data.get("map", {}) as Dictionary
	if int(map.get("cell_size", CELL_SIZE)) != CELL_SIZE:
		push_error("First-night content cell size does not match runtime constant.")
	var map_size: Array = map.get("map_size", [MAP_SIZE.x, MAP_SIZE.y]) as Array
	if Vector2i(int(map_size[0]), int(map_size[1])) != MAP_SIZE:
		push_error("First-night content map size does not match runtime constant.")
	if not is_equal_approx(float(map.get("interaction_range", INTERACTION_RANGE)), INTERACTION_RANGE):
		push_error("First-night content interaction range does not match runtime constant.")


func _load_progression() -> void:
	var data: Dictionary = _read_json(PROGRESSION_PATH)
	_message_keys = (data.get("message_keys", {}) as Dictionary).duplicate(true)
	_failure_message_keys = (data.get("failure_message_keys", {}) as Dictionary).duplicate(true)
	_stage_label_keys = (data.get("stage_label_keys", {}) as Dictionary).duplicate(true)

	var costs: Dictionary = data.get("costs", {}) as Dictionary
	for cost_variant: Variant in costs.keys():
		var cost_id: String = String(cost_variant)
		_costs[cost_id] = _normalize_cost(costs[cost_variant] as Dictionary)


func _normalize_cost(raw_cost: Dictionary) -> Dictionary:
	var cost: Dictionary = {}
	for item_variant: Variant in raw_cost.keys():
		var item_id: String = normalize_item_id(String(item_variant))
		cost[item_id] = int(raw_cost[item_variant])
	return cost


func _is_finite_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number)


func _validate() -> void:
	for item_id: String in _item_order:
		if not item_id.contains(":"):
			push_error("Item id should be namespaced: %s." % item_id)
		var item_definition: Dictionary = _item_defs[item_id] as Dictionary
		if String(item_definition.get("label_key", "")).is_empty():
			push_error("Item %s has no label_key." % item_id)
		var icon_path := String(
			item_definition.get("icon_path", ""))
		if (
			not icon_path.is_empty()
			and not ResourceLoader.exists(icon_path)
		):
			push_error(
				"Item %s references missing icon %s."
				% [item_id, icon_path]
			)
		if int(item_definition.get("max_stack", 0)) <= 0:
			push_error(
				"Item %s has invalid max_stack." % item_id
			)

		var raw_footprint := (
			item_definition.get("footprint", []) as Array
		)
		if InventoryShapeRules.from_raw(raw_footprint).is_empty():
			push_error(
				"Item %s has no valid footprint." % item_id
			)
	for object_id: String in _object_order:
		if not object_id.contains(":"):
			push_error("Object id should be namespaced: %s." % object_id)
		var definition: Dictionary = _object_defs[object_id] as Dictionary
		if String(definition.get("kind", "")).is_empty():
			push_error("Object %s has no interaction kind." % object_id)
		if String(definition.get("label_key", "")).is_empty():
			push_error("Object %s has no label_key." % object_id)

	for kind_variant: Variant in _collect_rules.keys():
		var rule: Dictionary = _collect_rules[kind_variant] as Dictionary
		var item_id: String = String(rule.get("item_id", ""))
		if not _item_defs.has(item_id):
			push_error("Collect rule %s references unknown item %s." % [kind_variant, item_id])
		if String(rule.get("message_key", "")).is_empty():
			push_error("Collect rule %s has no message_key." % kind_variant)
		if String(rule.get("full_message_key", "")).is_empty():
			push_error("Collect rule %s has no full_message_key." % kind_variant)

	for message_id_variant: Variant in _message_keys.keys():
		if String(_message_keys[message_id_variant]).is_empty():
			push_error("Progression message %s has no localization key." % message_id_variant)
	for failure_id_variant: Variant in _failure_message_keys.keys():
		if String(_failure_message_keys[failure_id_variant]).is_empty():
			push_error("Progression failure %s has no localization key." % failure_id_variant)

	for cost_variant: Variant in _costs.keys():
		var cost: Dictionary = _costs[cost_variant] as Dictionary
		for item_variant: Variant in cost.keys():
			var item_id: String = String(item_variant)
			if not _item_defs.has(item_id):
				push_error("Cost %s references unknown item %s." % [cost_variant, item_id])


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing content file: %s." % path)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open content file: %s." % path)
		return {}

	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Content file is not a JSON object: %s." % path)
		return {}
	return parsed as Dictionary
