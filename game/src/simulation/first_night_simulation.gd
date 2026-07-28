class_name FirstNightSimulation
extends RefCounted

signal event_emitted(event: Dictionary)

const Content := preload("res://src/content/first_night_content.gd")
const Npcs := preload("res://src/characters/npc_catalog.gd")

const SAVE_VERSION: int = 3
const DEFAULT_SEED: int = 247061
const START_MINUTE: int = 11 * 60
const EVENING_MINUTE: int = 18 * 60
const LATEST_MINUTE: int = 23 * 60 + 50
const GAME_MINUTES_PER_SECOND: float = 0.75
const MAX_CARRY_WEIGHT: float = 24.0
const PLAYER_ACTOR_ID: String = "core:player"
const ACTION_INTERACT: String = "core:interact"

var state: Dictionary
var content: FirstNightContent
var npc_catalog
var _minute_accumulator: float = 0.0


func _init(initial_state: Dictionary = {}) -> void:
	content = Content.new()
	npc_catalog = Npcs.new()
	if initial_state.is_empty():
		state = create_new_state()
	else:
		var header_result: Dictionary = validate_save_header(initial_state)
		if bool(header_result.get("success", false)):
			state = initial_state.duplicate(true)
		else:
			push_error(String(header_result.get("message", "Сохранение несовместимо.")))
			state = create_new_state()
	_normalize_state()


static func create_new_state(seed_value: int = DEFAULT_SEED) -> Dictionary:
	var content_data: FirstNightContent = Content.new()
	var npc_data := Npcs.new()
	return {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"day": 1,
		"minute_of_day": START_MINUTE,
		"player_position": [784.0, 944.0],
		"inventory": content_data.create_empty_inventory(),
		"collected": {},
		"npcs": npc_data.create_initial_states(seed_value),
		"flags": {
			"house_inspected": false,
			"tools_found": false,
			"repair_stage": 0,
			"campfire_stage": 0,
			"bed_ready": false,
			"water_boiled": false,
			"dusk_warned": false,
			"late_warned": false,
			"first_night_complete": false,
		},
		"outcomes": [],
	}


static func validate_save_header(raw_state: Dictionary) -> Dictionary:
	if not raw_state.has("version"):
		return {
			"success": false,
			"code": "missing_version",
			"message": "Сохранение повреждено: отсутствует версия формата.",
		}

	var raw_version: Variant = raw_state["version"]
	if typeof(raw_version) != TYPE_INT and typeof(raw_version) != TYPE_FLOAT:
		return {
			"success": false,
			"code": "invalid_version",
			"message": "Сохранение повреждено: версия формата имеет неверный тип.",
		}

	var numeric_version: float = float(raw_version)
	if not is_finite(numeric_version) or numeric_version != floor(numeric_version):
		return {
			"success": false,
			"code": "invalid_version",
			"message": "Сохранение повреждено: версия формата должна быть целым числом.",
		}

	var version: int = int(numeric_version)
	if version < 1:
		return {
			"success": false,
			"code": "invalid_version",
			"message": "Сохранение повреждено: версия формата вне допустимого диапазона.",
		}
	if version > SAVE_VERSION:
		return {
			"success": false,
			"code": "future_version",
			"message": "Сохранение создано более новой версией игры.",
		}
	return {
		"success": true,
		"code": "ok",
		"version": version,
	}


func tick(real_delta: float) -> bool:
	if bool(get_flags().get("first_night_complete", false)):
		return false

	_minute_accumulator += real_delta * GAME_MINUTES_PER_SECOND
	var whole_minutes: int = int(floor(_minute_accumulator))
	if whole_minutes <= 0:
		return false

	_minute_accumulator -= float(whole_minutes)
	var previous_minute: int = get_minute_of_day()
	var next_minute: int = mini(previous_minute + whole_minutes, LATEST_MINUTE)
	state["minute_of_day"] = next_minute

	var flags: Dictionary = _flags_mutable()
	if previous_minute < 17 * 60 and next_minute >= 17 * 60 and not bool(flags["dusk_warned"]):
		flags["dusk_warned"] = true
		_emit_result(true, "Солнце садится. Пора заканчивать подготовку к ночи.", true)
	if next_minute >= LATEST_MINUTE and not bool(flags["late_warned"]):
		flags["late_warned"] = true
		_emit_result(true, "Вы слишком устали. Подготовьте постель и завершите день.", true)

	event_emitted.emit({"type": "time_changed", "minute": next_minute})
	return true


func advance_minutes(amount: int) -> void:
	state["minute_of_day"] = clampi(get_minute_of_day() + amount, 0, LATEST_MINUTE)
	event_emitted.emit({"type": "time_changed", "minute": get_minute_of_day()})


func execute_interaction(target_id: String) -> Dictionary:
	return execute_command(PLAYER_ACTOR_ID, target_id, ACTION_INTERACT)


func execute_command(actor_id: String, target_id: String, action_id: String) -> Dictionary:
	if actor_id != PLAYER_ACTOR_ID:
		return _emit_result(false, "Неизвестный участник действия.")
	if action_id != ACTION_INTERACT:
		return _emit_result(false, "Это действие пока недоступно.")

	var target: Dictionary = _resolve_interaction_target(target_id)
	if target.is_empty():
		return _emit_result(false, "Такой цели здесь нет.")

	var resolved_target_id: String = String(target.get("id", ""))
	var kind: String = String(target.get("kind", ""))
	if should_hide_interactable(resolved_target_id, kind):
		return _emit_result(false, "Сейчас с этим нельзя взаимодействовать.")

	var target_position: Vector2 = target.get("position", Vector2.ZERO) as Vector2
	if get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return _emit_result(false, "Слишком далеко: подойдите ближе к выбранному объекту.")

	return _execute_resolved_interaction(resolved_target_id, kind)


func _execute_resolved_interaction(target_id: String, kind: String) -> Dictionary:
	match kind:
		"house":
			return _inspect_house()
		"tools":
			return _find_tools()
		"repair":
			return _advance_repair()
		"campfire":
			return _advance_campfire()
		"bed":
			return _advance_bed()
		"npc":
			return _talk_to_npc(target_id)

	if content.has_collect_rule(kind):
		return _collect_resource(target_id, kind)
	return _emit_result(false, "С этим пока нельзя взаимодействовать.")


func get_interaction_target_position(target_id: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var target: Dictionary = _resolve_interaction_target(target_id)
	if target.is_empty():
		return fallback
	return target.get("position", fallback) as Vector2


func export_state() -> Dictionary:
	return state.duplicate(true)


func get_inventory() -> Dictionary:
	return _inventory_mutable().duplicate(true)


func get_flags() -> Dictionary:
	return _flags_mutable().duplicate(true)


func get_npcs() -> Dictionary:
	return _npcs_mutable().duplicate(true)


func get_item_count(item_id: String) -> int:
	return int(get_inventory().get(content.normalize_item_id(item_id), 0))


func get_inventory_weight() -> float:
	var total: float = 0.0
	var inventory: Dictionary = get_inventory()
	for item_variant: Variant in inventory.keys():
		var item_id: String = String(item_variant)
		total += float(inventory[item_id]) * content.item_weight(item_id)
	return total


func get_day() -> int:
	return int(state.get("day", 1))


func get_minute_of_day() -> int:
	return int(state.get("minute_of_day", START_MINUTE))


func get_time_text() -> String:
	var minute: int = get_minute_of_day()
	return "%02d:%02d" % [minute / 60, minute % 60]


func get_player_position() -> Vector2:
	var stored: Array = state.get("player_position", [784.0, 944.0]) as Array
	if stored.size() < 2:
		return Vector2(784.0, 944.0)
	return Vector2(float(stored[0]), float(stored[1]))


func set_player_position(value: Vector2) -> void:
	state["player_position"] = [value.x, value.y]


func is_collected(object_id: String) -> bool:
	var collected: Dictionary = state["collected"] as Dictionary
	return bool(collected.get(content.normalize_object_id(object_id), false))


func get_object_stage(kind: String) -> int:
	var flags: Dictionary = get_flags()
	match kind:
		"repair":
			return int(flags["repair_stage"])
		"campfire":
			return int(flags["campfire_stage"])
		"bed":
			return 1 if bool(flags["bed_ready"]) else 0
		_:
			return 0


func get_object_label(kind: String, fallback: String, object_id: String = "") -> String:
	var flags: Dictionary = get_flags()
	match kind:
		"npc":
			return npc_catalog.get_label(get_npcs(), object_id, fallback)
		"tools":
			return content.get_stage_label(kind, 0, fallback)
		"repair":
			var stage: int = int(flags["repair_stage"])
			return content.get_stage_label(kind, stage, fallback)
		"campfire":
			var fire_stage: int = int(flags["campfire_stage"])
			return content.get_stage_label(kind, fire_stage, fallback)
		"bed":
			var bed_stage: int = 1 if bool(flags["bed_ready"]) else 0
			return content.get_stage_label(kind, bed_stage, fallback)
		_:
			return fallback


func should_hide_interactable(object_id: String, kind: String) -> bool:
	if kind == "npc":
		return not npc_catalog.is_visible(get_npcs(), object_id)
	if kind == "tools":
		return bool(get_flags().get("tools_found", false))
	if content.has_collect_rule(kind) and not content.is_collect_rule_repeatable(kind):
		return is_collected(object_id)
	return false


func is_npc_visible(npc_id: String) -> bool:
	return npc_catalog.is_visible(get_npcs(), npc_id)


func get_npc_position(npc_id: String, fallback: Vector2) -> Vector2:
	return npc_catalog.get_position(get_npcs(), npc_id, fallback)


func get_npc_appearance(npc_id: String) -> Dictionary:
	return npc_catalog.get_appearance(get_npcs(), npc_id)


func _resolve_interaction_target(target_id: String) -> Dictionary:
	var object_target: Dictionary = content.get_interactable(target_id)
	if not object_target.is_empty():
		return object_target

	if npc_catalog.get_definition(target_id).is_empty() or not get_npcs().has(target_id):
		return {}
	return {
		"id": target_id,
		"kind": "npc",
		"position": npc_catalog.get_position(get_npcs(), target_id, Vector2.ZERO),
	}


func get_current_objective() -> String:
	var flags: Dictionary = get_flags()
	if bool(flags["first_night_complete"]):
		var first_neighbor: Dictionary = get_npcs().get("core:first_neighbor", {}) as Dictionary
		if bool(first_neighbor.get("active", false)) and int(first_neighbor.get("talk_count", 0)) <= 0:
			return "Утром у Общего дома появился путник. Поговорите с ним."
		return "Первое утро наступило. Срез пройден."
	if not bool(flags["tools_found"]):
		return "Осмотрите Общий дом и найдите инструменты."
	if int(flags["repair_stage"]) < 3:
		return "Соберите древесину и камень, затем отремонтируйте комнату."
	if int(flags["campfire_stage"]) < 2:
		return "Соберите костёр из древесины и камня, затем разожгите его."
	if not bool(flags["water_boiled"]):
		return "Наберите воду у берега и вскипятите её на костре."
	if not bool(flags["bed_ready"]):
		return "Подготовьте временную постель в отремонтированной комнате."
	if get_minute_of_day() < EVENING_MINUTE:
		return "Подготовка закончена. Дождитесь 18:00 или исследуйте карту."
	return "Вернитесь к постели и завершите первую ночь."


func _inspect_house() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if bool(flags["house_inspected"]):
		return _emit_result(true, content.get_message("house_repeat", "Общий дом сильно повреждён, но одну комнату ещё можно спасти."))
	flags["house_inspected"] = true
	return _emit_result(true, content.get_message("house_first", "Внутри Общего дома видны старые инструменты и комната с повреждённой крышей."), true)


func _find_tools() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if bool(flags["tools_found"]):
		return _emit_result(true, content.get_message("tools_repeat", "Инструменты уже у вас."))
	flags["tools_found"] = true
	return _emit_result(true, content.get_message("tools_first", "Найдены изношенные топорик, молоток, пила, нож и котелок."), true)


func _collect_resource(object_id: String, kind: String) -> Dictionary:
	var rule: Dictionary = content.get_collect_rule(kind)
	var item_id: String = String(rule.get("item_id", ""))
	var amount: int = int(rule.get("amount", 0))
	var repeatable: bool = bool(rule.get("repeatable", false))

	if not repeatable and is_collected(object_id):
		return _emit_result(false, String(rule.get("empty_message", "Здесь больше ничего нет.")))
	if not _can_add_item(item_id, amount):
		return _emit_result(false, String(rule.get("full_message", "Слишком тяжело. Сначала потратьте или оставьте часть ресурсов.")))

	if not repeatable:
		var collected: Dictionary = state["collected"] as Dictionary
		collected[content.normalize_object_id(object_id)] = true
	_add_item(item_id, amount)
	return _emit_result(true, String(rule.get("message", "Ресурс собран.")), true)


func _advance_repair() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if not bool(flags["tools_found"]):
		return _emit_result(false, content.get_failure_message("repair_tools_required", "Для ремонта нужен найденный набор инструментов."))

	var stage: int = int(flags["repair_stage"])
	match stage:
		0:
			flags["repair_stage"] = 1
			return _emit_result(true, content.get_message("repair_stage_0", "Вы расчистили завал и добрались до повреждённой крыши."), true)
		1:
			if not _consume_items(content.get_cost("repair_stage_1")):
				return _emit_result(false, content.get_failure_message("repair_stage_1_cost", "Для ремонта крыши нужно 3 древесины и 2 камня."))
			flags["repair_stage"] = 2
			return _emit_result(true, content.get_message("repair_stage_1", "Крыша укреплена. Осталось закрыть щели в комнате."), true)
		2:
			if not _consume_items(content.get_cost("repair_stage_2")):
				return _emit_result(false, content.get_failure_message("repair_stage_2_cost", "Для завершения комнаты нужно ещё 2 древесины."))
			flags["repair_stage"] = 3
			return _emit_result(true, content.get_message("repair_stage_2", "Комната укрыта от ветра и готова к первой ночи."), true)
		_:
			return _emit_result(true, content.get_message("repair_done", "Отремонтированная комната выдержит эту ночь."))


func _advance_campfire() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	var stage: int = int(flags["campfire_stage"])
	match stage:
		0:
			if not _consume_items(content.get_cost("campfire_stage_0")):
				return _emit_result(false, content.get_failure_message("campfire_stage_0_cost", "Для костра нужно 2 древесины и 2 камня."))
			flags["campfire_stage"] = 1
			return _emit_result(true, content.get_message("campfire_stage_0", "Кострище сложено. Взаимодействуйте снова, чтобы разжечь огонь."), true)
		1:
			if not bool(flags["tools_found"]):
				return _emit_result(false, content.get_failure_message("campfire_tools_required", "Без инструментов и старого огнива разжечь костёр не получится."))
			flags["campfire_stage"] = 2
			return _emit_result(true, content.get_message("campfire_stage_1", "Огонь разгорелся и начал прогревать двор."), true)
		_:
			if get_item_count(FirstNightContent.RAW_WATER_ID) <= 0:
				return _emit_result(false, content.get_failure_message("water_required", "Принесите котелок сырой воды, чтобы вскипятить её."))
			_consume_items(content.get_cost("boil_water"))
			_add_item(FirstNightContent.BOILED_WATER_ID, 1)
			flags["water_boiled"] = true
			return _emit_result(true, content.get_message("water_boiled", "Вода прокипела и теперь безопасна."), true)


func _advance_bed() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if int(flags["repair_stage"]) < 3:
		return _emit_result(false, content.get_failure_message("bed_repair_required", "Сначала нужно закончить ремонт комнаты."))
	if not bool(flags["bed_ready"]):
		if not _consume_items(content.get_cost("bed")):
			return _emit_result(false, content.get_failure_message("bed_cost", "Для основания временной постели нужна 1 древесина."))
		flags["bed_ready"] = true
		return _emit_result(true, content.get_message("bed_ready", "Временная постель готова. После 18:00 здесь можно завершить день."), true)
	if get_minute_of_day() < EVENING_MINUTE:
		return _emit_result(false, content.get_failure_message("bed_too_early", "Ещё слишком рано спать. Используйте оставшееся дневное время."))
	return _sleep_until_morning()


func _talk_to_npc(npc_id: String) -> Dictionary:
	var result: Dictionary = npc_catalog.talk(_npcs_mutable(), npc_id)
	return _emit_result(bool(result.get("success", false)), String(result.get("message", "")), bool(result.get("changed", false)))


func _sleep_until_morning() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	var outcomes: Array = []
	if int(flags["repair_stage"]) >= 3:
		outcomes.append("сухая комната")
	else:
		outcomes.append("холодный сквозняк")
	if int(flags["campfire_stage"]) >= 2:
		outcomes.append("остаточное тепло")
	if get_item_count(FirstNightContent.BOILED_WATER_ID) > 0:
		outcomes.append("безопасная вода")
	if get_item_count(FirstNightContent.FOOD_ID) > 0:
		_consume_items(content.get_cost("sleep_food"))
		outcomes.append("лёгкий ужин")
	else:
		outcomes.append("голодный сон")

	state["outcomes"] = outcomes
	state["day"] = get_day() + 1
	state["minute_of_day"] = 7 * 60
	flags["first_night_complete"] = true
	var npc_arrived: bool = npc_catalog.activate_after_first_night(_npcs_mutable())
	var morning_note: String = " На рассвете у Общего дома появился путник." if npc_arrived else ""
	return _emit_result(true, "Наступило новое утро. Итог: %s.%s" % [", ".join(outcomes), morning_note], true, true)


func _can_add_item(item_id: String, amount: int) -> bool:
	var added_weight: float = content.item_weight(item_id) * float(amount)
	return get_inventory_weight() + added_weight <= MAX_CARRY_WEIGHT + 0.001


func _add_item(item_id: String, amount: int) -> void:
	var inventory: Dictionary = _inventory_mutable()
	var normalized_id: String = content.normalize_item_id(item_id)
	inventory[normalized_id] = int(inventory.get(normalized_id, 0)) + amount


func _consume_items(costs: Dictionary) -> bool:
	var inventory: Dictionary = _inventory_mutable()
	for item_variant: Variant in costs.keys():
		var item_id: String = content.normalize_item_id(String(item_variant))
		var required_amount: int = int(costs[item_variant])
		if int(inventory.get(item_id, 0)) < required_amount:
			return false
	for item_variant: Variant in costs.keys():
		var item_id: String = content.normalize_item_id(String(item_variant))
		var required_amount: int = int(costs[item_variant])
		inventory[item_id] = int(inventory.get(item_id, 0)) - required_amount
	return true


func _emit_result(success: bool, message: String, changed: bool = false, auto_save: bool = false) -> Dictionary:
	var event: Dictionary = {
		"type": "command_result",
		"success": success,
		"message": message,
		"changed": changed,
		"auto_save": auto_save,
	}
	event_emitted.emit(event)
	return event


func _normalize_state() -> void:
	var seed_value: int = _safe_int(state.get("seed"), DEFAULT_SEED)
	var defaults: Dictionary = create_new_state(seed_value)
	for key_variant: Variant in defaults.keys():
		var key: String = String(key_variant)
		if not state.has(key):
			state[key] = defaults[key]

	var loaded_version: int = _safe_int(state.get("version"), SAVE_VERSION)
	state["version"] = SAVE_VERSION
	state["seed"] = seed_value
	state["day"] = maxi(1, _safe_int(state.get("day"), 1))
	state["minute_of_day"] = clampi(
		_safe_int(state.get("minute_of_day"), START_MINUTE),
		0,
		LATEST_MINUTE
	)

	state["inventory"] = content.normalize_inventory(_as_dictionary(state.get("inventory")))
	state["collected"] = content.normalize_collected(_as_dictionary(state.get("collected")))
	state["npcs"] = npc_catalog.normalize_states(_as_dictionary(state.get("npcs")), seed_value)

	var flags: Dictionary = _as_dictionary(state.get("flags"))
	var default_flags: Dictionary = defaults["flags"] as Dictionary
	for flag_variant: Variant in default_flags.keys():
		var flag_id: String = String(flag_variant)
		var default_value: Variant = default_flags[flag_id]
		if typeof(default_value) == TYPE_BOOL:
			flags[flag_id] = _safe_bool(flags.get(flag_id), bool(default_value))
		else:
			flags[flag_id] = _safe_int(flags.get(flag_id), int(default_value))
	flags["repair_stage"] = clampi(_safe_int(flags.get("repair_stage"), 0), 0, 3)
	flags["campfire_stage"] = clampi(_safe_int(flags.get("campfire_stage"), 0), 0, 2)
	state["flags"] = flags
	if bool(flags["first_night_complete"]):
		npc_catalog.activate_after_first_night(_npcs_mutable())

	var stored_position_value: Variant = state.get("player_position", defaults["player_position"])
	if not _is_valid_position(stored_position_value):
		state["player_position"] = (defaults["player_position"] as Array).duplicate(true)
	else:
		var stored_position: Array = stored_position_value as Array
		state["player_position"] = [float(stored_position[0]), float(stored_position[1])]
	state["outcomes"] = _normalize_outcomes(state.get("outcomes"))

	if loaded_version != SAVE_VERSION:
		push_warning("Save version %s migrated into prototype version %s." % [loaded_version, SAVE_VERSION])


static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


func _inventory_mutable() -> Dictionary:
	return state["inventory"] as Dictionary


func _flags_mutable() -> Dictionary:
	return state["flags"] as Dictionary


func _npcs_mutable() -> Dictionary:
	return state["npcs"] as Dictionary


static func _safe_bool(value: Variant, fallback: bool) -> bool:
	if typeof(value) != TYPE_BOOL:
		return fallback
	return value


static func _safe_int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) != TYPE_FLOAT:
		return fallback
	var number: float = float(value)
	if not is_finite(number) or number != floor(number):
		return fallback
	return int(number)


static func _is_valid_position(value: Variant) -> bool:
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


static func _normalize_outcomes(value: Variant) -> Array[String]:
	var outcomes: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return outcomes
	var raw_outcomes: Array = value as Array
	for entry: Variant in raw_outcomes:
		if typeof(entry) == TYPE_STRING or typeof(entry) == TYPE_STRING_NAME:
			outcomes.append(String(entry))
	return outcomes
