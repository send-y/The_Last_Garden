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
var _messages: Dictionary = {}
var _failure_messages: Dictionary = {}
var _stage_labels: Dictionary = {}
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


func item_weight(item_id: String) -> float:
	var normalized_id: String = normalize_item_id(item_id)
	var definition: Dictionary = _item_defs.get(normalized_id, {}) as Dictionary
	return float(definition.get("weight", 0.0))


func item_label(item_id: String) -> String:
	var normalized_id: String = normalize_item_id(item_id)
	var definition: Dictionary = _item_defs.get(normalized_id, {}) as Dictionary
	return String(definition.get("label", normalized_id))


func create_empty_inventory() -> Dictionary:
	var inventory: Dictionary = {}
	for item_id: String in _item_order:
		inventory[item_id] = 0
	return inventory


func normalize_inventory(raw_inventory: Dictionary) -> Dictionary:
	var inventory: Dictionary = create_empty_inventory()
	for item_variant: Variant in raw_inventory.keys():
		var item_id: String = normalize_item_id(String(item_variant))
		var amount: int = int(raw_inventory[item_variant])
		inventory[item_id] = int(inventory.get(item_id, 0)) + amount
	return inventory


func normalize_collected(raw_collected: Dictionary) -> Dictionary:
	var collected: Dictionary = {}
	for object_variant: Variant in raw_collected.keys():
		var object_id: String = normalize_object_id(String(object_variant))
		collected[object_id] = bool(raw_collected[object_variant])
	return collected


func interactables() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object_id: String in _object_order:
		var definition: Dictionary = _object_defs[object_id] as Dictionary
		var cell: Array = definition.get("cell", [0, 0]) as Array
		var size: Array = definition.get("size", [24.0, 20.0]) as Array
		result.append({
			"id": object_id,
			"kind": String(definition.get("kind", "")),
			"label": String(definition.get("label", object_id)),
			"position": cell_center(int(cell[0]), int(cell[1])),
			"color": Color(String(definition.get("color", "ffffff"))),
			"size": Vector2(float(size[0]), float(size[1])),
		})
	return result


func has_collect_rule(kind: String) -> bool:
	return _collect_rules.has(kind)


func get_collect_rule(kind: String) -> Dictionary:
	return (_collect_rules.get(kind, {}) as Dictionary).duplicate(true)


func is_collect_rule_repeatable(kind: String) -> bool:
	var rule: Dictionary = _collect_rules.get(kind, {}) as Dictionary
	return bool(rule.get("repeatable", false))


func get_message(message_id: String, fallback: String = "") -> String:
	return String(_messages.get(message_id, fallback))


func get_failure_message(message_id: String, fallback: String = "") -> String:
	return String(_failure_messages.get(message_id, fallback))


func get_stage_label(kind: String, stage: int, fallback: String) -> String:
	var labels: Array = _stage_labels.get(kind, []) as Array
	if labels.is_empty():
		return fallback
	var safe_stage: int = clampi(stage, 0, labels.size() - 1)
	return String(labels[safe_stage])


func get_cost(cost_id: String) -> Dictionary:
	return (_costs.get(cost_id, {}) as Dictionary).duplicate(true)


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
	_messages = (data.get("messages", {}) as Dictionary).duplicate(true)
	_failure_messages = (data.get("failure_messages", {}) as Dictionary).duplicate(true)
	_stage_labels = (data.get("stage_labels", {}) as Dictionary).duplicate(true)

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


func _validate() -> void:
	for item_id: String in _item_order:
		if not item_id.contains(":"):
			push_error("Item id should be namespaced: %s." % item_id)

	for object_id: String in _object_order:
		if not object_id.contains(":"):
			push_error("Object id should be namespaced: %s." % object_id)
		var definition: Dictionary = _object_defs[object_id] as Dictionary
		if String(definition.get("kind", "")).is_empty():
			push_error("Object %s has no interaction kind." % object_id)

	for kind_variant: Variant in _collect_rules.keys():
		var rule: Dictionary = _collect_rules[kind_variant] as Dictionary
		var item_id: String = String(rule.get("item_id", ""))
		if not _item_defs.has(item_id):
			push_error("Collect rule %s references unknown item %s." % [kind_variant, item_id])

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
