class_name NpcCatalog
extends RefCounted

const Appearance := preload("res://src/characters/character_appearance.gd")
const FirstNightContentScript := preload("res://src/content/first_night_content.gd")
const Localized := preload("res://src/localization/localized_text.gd")

const NPCS_PATH: String = "res://content/core/npcs.json"

var _appearance_catalog := Appearance.new()
var _definitions_by_id: Dictionary = {}
var _definition_order: Array[String] = []


func _init() -> void:
	_load()
	_validate_content()


func get_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for npc_id: String in _definition_order:
		result.append((_definitions_by_id[npc_id] as Dictionary).duplicate(true))
	return result


func get_definition(npc_id: String) -> Dictionary:
	return (_definitions_by_id.get(npc_id, {}) as Dictionary).duplicate(true)


func create_initial_states(world_seed: int) -> Dictionary:
	var npcs: Dictionary = {}
	for npc_id: String in _definition_order:
		var definition: Dictionary = _definitions_by_id[npc_id] as Dictionary
		var seed_offset: int = int(definition.get("appearance_seed_offset", 0))
		var cell: Array = definition.get("position_cell", [24, 29]) as Array
		var autonomy: Dictionary = definition.get("autonomy", {}) as Dictionary
		npcs[npc_id] = {
			"id": npc_id,
			"active": false,
			"known": false,
			"talk_count": 0,
			"position": _cell_center_array(int(cell[0]), int(cell[1])),
			"appearance_seed": world_seed + seed_offset,
			"appearance": _appearance_catalog.generate_npc_appearance(world_seed + seed_offset),
			"needs": {
				"hunger": clampf(float(autonomy.get("initial_hunger", 72.0)), 0.0, 100.0),
				"energy": clampf(float(autonomy.get("initial_energy", 82.0)), 0.0, 100.0),
			},
			"activity_id": "core:arriving",
			"activity_started_minute": 7 * 60,
			"target_cell": [int(cell[0]), int(cell[1])],
			"personal_inventory": {
				"core:food": maxi(0, int(autonomy.get("personal_food", 0))),
			},
			"facing": [0.0, -1.0],
			"moving": false,
		}
	return npcs


func normalize_states(raw_npcs: Dictionary, world_seed: int) -> Dictionary:
	var defaults: Dictionary = create_initial_states(world_seed)
	var normalized: Dictionary = {}
	for raw_id_variant: Variant in raw_npcs.keys():
		var raw_id: String = String(raw_id_variant)
		if _definitions_by_id.has(raw_id):
			continue
		var unknown_state: Variant = raw_npcs[raw_id_variant]
		if typeof(unknown_state) == TYPE_DICTIONARY:
			normalized[raw_id] = (unknown_state as Dictionary).duplicate(true)

	for npc_id: String in _definition_order:
		var default_state: Dictionary = defaults[npc_id] as Dictionary
		var raw_value: Variant = raw_npcs.get(npc_id, {})
		var raw_state: Dictionary = {}
		if typeof(raw_value) == TYPE_DICTIONARY:
			raw_state = raw_value as Dictionary
		var npc_state: Dictionary = default_state.duplicate(true)

		for key_variant: Variant in raw_state.keys():
			var key: String = String(key_variant)
			npc_state[key] = raw_state[key_variant]

		npc_state["id"] = npc_id
		npc_state["active"] = _safe_bool(npc_state.get("active"), bool(default_state["active"]))
		npc_state["known"] = _safe_bool(npc_state.get("known"), bool(default_state["known"]))
		npc_state["talk_count"] = maxi(0, _safe_int(npc_state.get("talk_count"), int(default_state["talk_count"])))
		npc_state["appearance_seed"] = _safe_int(
			npc_state.get("appearance_seed"),
			int(default_state["appearance_seed"])
		)

		var position_value: Variant = npc_state.get("position", default_state["position"])
		if not _is_valid_position(position_value):
			npc_state["position"] = default_state["position"]
		else:
			var position: Array = position_value as Array
			npc_state["position"] = [float(position[0]), float(position[1])]

		var appearance_value: Variant = npc_state.get("appearance", {})
		var appearance: Dictionary = {}
		if typeof(appearance_value) == TYPE_DICTIONARY:
			appearance = appearance_value as Dictionary
		if not _appearance_catalog.validate_appearance(appearance).is_empty():
			npc_state["appearance"] = _appearance_catalog.generate_npc_appearance(int(npc_state["appearance_seed"]))
		else:
			npc_state["appearance"] = appearance.duplicate(true)

		var default_needs: Dictionary = default_state["needs"] as Dictionary
		var needs_value: Variant = npc_state.get("needs", {})
		var needs: Dictionary = {}
		if typeof(needs_value) == TYPE_DICTIONARY:
			needs = needs_value as Dictionary
		npc_state["needs"] = {
			"hunger": clampf(
				_safe_float(needs.get("hunger"), float(default_needs["hunger"])),
				0.0,
				100.0
			),
			"energy": clampf(
				_safe_float(needs.get("energy"), float(default_needs["energy"])),
				0.0,
				100.0
			),
		}

		var default_activity: String = String(default_state["activity_id"])
		var activity_id: String = String(npc_state.get("activity_id", default_activity))
		npc_state["activity_id"] = activity_id if activity_id.contains(":") else default_activity
		npc_state["activity_started_minute"] = clampi(
			_safe_int(
				npc_state.get("activity_started_minute"),
				int(default_state["activity_started_minute"])
			),
			0,
			24 * 60 - 1
		)
		npc_state["target_cell"] = _normalize_cell(
			npc_state.get("target_cell"),
			default_state["target_cell"] as Array
		)

		var inventory_value: Variant = npc_state.get("personal_inventory", {})
		var inventory: Dictionary = {}
		if typeof(inventory_value) == TYPE_DICTIONARY:
			for item_variant: Variant in (inventory_value as Dictionary).keys():
				var item_id: String = String(item_variant)
				if not item_id.contains(":"):
					continue
				var amount: int = _safe_int(
					(inventory_value as Dictionary)[item_variant],
					0
				)
				if amount >= 0:
					inventory[item_id] = amount
		var default_inventory: Dictionary = default_state["personal_inventory"] as Dictionary
		if not inventory.has("core:food"):
			inventory["core:food"] = int(default_inventory.get("core:food", 0))
		npc_state["personal_inventory"] = inventory

		npc_state["facing"] = _normalize_facing(
			npc_state.get("facing"),
			default_state["facing"] as Array
		)
		npc_state["moving"] = _safe_bool(
			npc_state.get("moving"),
			bool(default_state["moving"])
		)

		normalized[npc_id] = npc_state
	return normalized


func get_interactables() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for npc_id: String in _definition_order:
		var definition: Dictionary = _definitions_by_id[npc_id] as Dictionary
		var cell: Array = definition.get("position_cell", [24, 29]) as Array
		result.append({
			"id": npc_id,
			"kind": "npc",
			"label_key": String(
				definition.get(
					"unknown_label_key",
					definition.get("name_key", "npc.generic.traveler.name")
				)
			),
			"position": FirstNightContentScript.cell_center(int(cell[0]), int(cell[1])),
			"color": Color("eee7d5"),
			"size": Vector2(24.0, 32.0),
		})
	return result


func activate_after_first_night(npcs: Dictionary) -> bool:
	var changed: bool = false
	for npc_id: String in _definition_order:
		var definition: Dictionary = _definitions_by_id[npc_id] as Dictionary
		if String(definition.get("spawn", "")) != "after_first_night":
			continue
		var npc_state: Dictionary = npcs[npc_id] as Dictionary
		if not bool(npc_state.get("active", false)):
			npc_state["active"] = true
			changed = true
	return changed


func is_visible(npcs: Dictionary, npc_id: String) -> bool:
	if not npcs.has(npc_id):
		return false
	var npc_state: Dictionary = npcs[npc_id] as Dictionary
	return bool(npc_state.get("active", false))


func get_label_key(npcs: Dictionary, npc_id: String, fallback_key: String) -> String:
	var definition: Dictionary = get_definition(npc_id)
	if definition.is_empty() or not npcs.has(npc_id):
		return fallback_key
	var npc_state: Dictionary = npcs[npc_id] as Dictionary
	if bool(npc_state.get("known", false)):
		return String(definition.get("name_key", fallback_key))
	return String(definition.get("unknown_label_key", fallback_key))


func get_position(npcs: Dictionary, npc_id: String, fallback: Vector2) -> Vector2:
	if not npcs.has(npc_id):
		return fallback
	var npc_state: Dictionary = npcs[npc_id] as Dictionary
	var position: Array = npc_state.get("position", [fallback.x, fallback.y]) as Array
	if position.size() < 2:
		return fallback
	return Vector2(float(position[0]), float(position[1]))


func get_appearance(npcs: Dictionary, npc_id: String) -> Dictionary:
	if not npcs.has(npc_id):
		return {}
	var npc_state: Dictionary = npcs[npc_id] as Dictionary
	return (npc_state.get("appearance", {}) as Dictionary).duplicate(true)


func talk(npcs: Dictionary, npc_id: String) -> Dictionary:
	if not npcs.has(npc_id):
		return {
			"success": false,
			"message_key": "interaction.failure.no_npc",
			"message_args": {},
			"changed": false,
		}

	var npc_state: Dictionary = npcs[npc_id] as Dictionary
	if not bool(npc_state.get("active", false)):
		return {
			"success": false,
			"message_key": "interaction.failure.no_npc",
			"message_args": {},
			"changed": false,
		}

	var definition: Dictionary = get_definition(npc_id)
	var talk_count: int = int(npc_state.get("talk_count", 0))
	var line_key: String = String(definition.get("greeting_key", ""))
	if talk_count > 0:
		line_key = String(definition.get("repeat_line_key", line_key))

	npc_state["known"] = true
	npc_state["talk_count"] = talk_count + 1
	return {
		"success": true,
		"message_key": "ui.dialogue.speaker_line",
		"message_args": {
			"speaker": Localized.text_reference(
				String(definition.get("name_key", "npc.generic.traveler.name"))
			),
			"line": Localized.text_reference(line_key),
		},
		"changed": true,
	}


func _cell_center_array(x: int, y: int) -> Array[float]:
	var position: Vector2 = FirstNightContentScript.cell_center(x, y)
	return [position.x, position.y]


func _safe_bool(value: Variant, fallback: bool) -> bool:
	if typeof(value) != TYPE_BOOL:
		return fallback
	return value


func _safe_int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) != TYPE_FLOAT:
		return fallback
	var number: float = float(value)
	if not is_finite(number) or number != floor(number):
		return fallback
	return int(number)


func _safe_float(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var number: float = float(value)
	return number if is_finite(number) else fallback


func _is_valid_position(value: Variant) -> bool:
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


func _normalize_cell(value: Variant, fallback: Array) -> Array[int]:
	if typeof(value) != TYPE_ARRAY:
		return [int(fallback[0]), int(fallback[1])]
	var cell: Array = value as Array
	if cell.size() < 2:
		return [int(fallback[0]), int(fallback[1])]
	var x: int = _safe_int(cell[0], int(fallback[0]))
	var y: int = _safe_int(cell[1], int(fallback[1]))
	return [
		clampi(x, 0, FirstNightContentScript.MAP_SIZE.x - 1),
		clampi(y, 0, FirstNightContentScript.MAP_SIZE.y - 1),
	]


func _normalize_facing(value: Variant, fallback: Array) -> Array[float]:
	if typeof(value) != TYPE_ARRAY:
		return [float(fallback[0]), float(fallback[1])]
	var facing: Array = value as Array
	if facing.size() < 2:
		return [float(fallback[0]), float(fallback[1])]
	var direction := Vector2(
		_safe_float(facing[0], float(fallback[0])),
		_safe_float(facing[1], float(fallback[1]))
	)
	if direction == Vector2.ZERO:
		return [float(fallback[0]), float(fallback[1])]
	if absf(direction.x) > absf(direction.y):
		return [1.0 if direction.x > 0.0 else -1.0, 0.0]
	return [0.0, 1.0 if direction.y > 0.0 else -1.0]


func _load() -> void:
	var data: Dictionary = _read_json(NPCS_PATH)
	var npcs: Array = data.get("npcs", []) as Array
	for npc_variant: Variant in npcs:
		var definition: Dictionary = (npc_variant as Dictionary).duplicate(true)
		var npc_id: String = String(definition.get("id", ""))
		if npc_id.is_empty():
			push_error("NPC definition without id in %s." % NPCS_PATH)
			continue
		_definitions_by_id[npc_id] = definition
		_definition_order.append(npc_id)


func _validate_content() -> void:
	for npc_id: String in _definition_order:
		if not npc_id.contains(":"):
			push_error("NPC id should be namespaced: %s." % npc_id)
		var definition: Dictionary = _definitions_by_id[npc_id] as Dictionary
		if String(definition.get("name_key", "")).is_empty():
			push_error("NPC %s has no name_key." % npc_id)
		if String(definition.get("unknown_label_key", "")).is_empty():
			push_error("NPC %s has no unknown_label_key." % npc_id)
		if String(definition.get("greeting_key", "")).is_empty():
			push_error("NPC %s has no greeting_key." % npc_id)
		if String(definition.get("repeat_line_key", "")).is_empty():
			push_error("NPC %s has no repeat_line_key." % npc_id)
		var cell: Array = definition.get("position_cell", []) as Array
		if cell.size() < 2:
			push_error("NPC %s has invalid position_cell." % npc_id)
		var autonomy: Dictionary = definition.get("autonomy", {}) as Dictionary
		for cell_key: String in [
			"meal_cell",
			"rest_cell",
			"morning_cell",
			"day_cell",
			"evening_cell",
		]:
			var autonomy_cell: Array = autonomy.get(cell_key, []) as Array
			if autonomy_cell.size() < 2:
				push_error("NPC %s has invalid autonomy.%s." % [npc_id, cell_key])


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing NPC content file: %s." % path)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open NPC content file: %s." % path)
		return {}

	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("NPC content is not a JSON object: %s." % path)
		return {}
	return parsed as Dictionary
