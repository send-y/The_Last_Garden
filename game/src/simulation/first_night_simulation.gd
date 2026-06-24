class_name FirstNightSimulation
extends RefCounted

signal event_emitted(event: Dictionary)

const SAVE_VERSION: int = 1
const DEFAULT_SEED: int = 247061
const START_MINUTE: int = 11 * 60
const EVENING_MINUTE: int = 18 * 60
const LATEST_MINUTE: int = 23 * 60 + 50
const GAME_MINUTES_PER_SECOND: float = 0.75
const MAX_CARRY_WEIGHT: float = 24.0

const ITEM_WEIGHTS: Dictionary = {
	"wood": 1.0,
	"stone": 1.5,
	"raw_water": 1.0,
	"boiled_water": 1.0,
	"food": 0.5,
}

var state: Dictionary
var _minute_accumulator: float = 0.0


func _init(initial_state: Dictionary = {}) -> void:
	if initial_state.is_empty():
		state = create_new_state()
	else:
		state = initial_state.duplicate(true)
	_normalize_state()


static func create_new_state(seed_value: int = DEFAULT_SEED) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"day": 1,
		"minute_of_day": START_MINUTE,
		"player_position": [784.0, 944.0],
		"inventory": {
			"wood": 0,
			"stone": 0,
			"raw_water": 0,
			"boiled_water": 0,
			"food": 0,
		},
		"collected": {},
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

	var flags: Dictionary = get_flags()
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


func execute_interaction(object_id: String, kind: String) -> Dictionary:
	match kind:
		"house":
			return _inspect_house()
		"tools":
			return _find_tools()
		"wood":
			return _collect_once(object_id, "wood", 3, "Собрана древесина: 3 ед.")
		"stone":
			return _collect_once(object_id, "stone", 3, "Собран камень: 3 ед.")
		"water":
			return _collect_water()
		"food":
			return _collect_once(object_id, "food", 2, "Найдены съедобные ягоды: 2 порции.")
		"repair":
			return _advance_repair()
		"campfire":
			return _advance_campfire()
		"bed":
			return _advance_bed()
		_:
			return _emit_result(false, "С этим пока нельзя взаимодействовать.")


func get_inventory() -> Dictionary:
	return state["inventory"] as Dictionary


func get_flags() -> Dictionary:
	return state["flags"] as Dictionary


func get_item_count(item_id: String) -> int:
	return int(get_inventory().get(item_id, 0))


func get_inventory_weight() -> float:
	var total: float = 0.0
	var inventory: Dictionary = get_inventory()
	for item_variant: Variant in inventory.keys():
		var item_id: String = String(item_variant)
		total += float(inventory[item_id]) * float(ITEM_WEIGHTS.get(item_id, 0.0))
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
	return bool(collected.get(object_id, false))


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


func get_object_label(kind: String, fallback: String) -> String:
	var flags: Dictionary = get_flags()
	match kind:
		"tools":
			return "Набор инструментов"
		"repair":
			var stage: int = int(flags["repair_stage"])
			return ["Заваленная комната", "Расчищенная комната", "Повреждённая крыша", "Укрытая комната"][stage]
		"campfire":
			var fire_stage: int = int(flags["campfire_stage"])
			return ["Место для костра", "Сложенный костёр", "Горящий костёр"][fire_stage]
		"bed":
			return "Временная постель" if bool(flags["bed_ready"]) else "Место для постели"
		_:
			return fallback


func get_current_objective() -> String:
	var flags: Dictionary = get_flags()
	if bool(flags["first_night_complete"]):
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
	var flags: Dictionary = get_flags()
	if bool(flags["house_inspected"]):
		return _emit_result(true, "Общий дом сильно повреждён, но одну комнату ещё можно спасти.")
	flags["house_inspected"] = true
	return _emit_result(true, "Внутри Общего дома видны старые инструменты и комната с повреждённой крышей.", true)


func _find_tools() -> Dictionary:
	var flags: Dictionary = get_flags()
	if bool(flags["tools_found"]):
		return _emit_result(true, "Инструменты уже у вас.")
	flags["tools_found"] = true
	return _emit_result(true, "Найдены изношенные топорик, молоток, пила, нож и котелок.", true)


func _collect_once(object_id: String, item_id: String, amount: int, message: String) -> Dictionary:
	if is_collected(object_id):
		return _emit_result(false, "Здесь больше ничего нет.")
	if not _can_add_item(item_id, amount):
		return _emit_result(false, "Слишком тяжело. Сначала потратьте или оставьте часть ресурсов.")

	var collected: Dictionary = state["collected"] as Dictionary
	collected[object_id] = true
	_add_item(item_id, amount)
	return _emit_result(true, message, true)


func _collect_water() -> Dictionary:
	if not _can_add_item("raw_water", 1):
		return _emit_result(false, "Котелок полон или груз уже слишком тяжёлый.")
	_add_item("raw_water", 1)
	return _emit_result(true, "Котелок наполнен небезопасной водой.", true)


func _advance_repair() -> Dictionary:
	var flags: Dictionary = get_flags()
	if not bool(flags["tools_found"]):
		return _emit_result(false, "Для ремонта нужен найденный набор инструментов.")

	var stage: int = int(flags["repair_stage"])
	match stage:
		0:
			flags["repair_stage"] = 1
			return _emit_result(true, "Вы расчистили завал и добрались до повреждённой крыши.", true)
		1:
			if not _consume_items({"wood": 3, "stone": 2}):
				return _emit_result(false, "Для ремонта крыши нужно 3 древесины и 2 камня.")
			flags["repair_stage"] = 2
			return _emit_result(true, "Крыша укреплена. Осталось закрыть щели в комнате.", true)
		2:
			if not _consume_items({"wood": 2}):
				return _emit_result(false, "Для завершения комнаты нужно ещё 2 древесины.")
			flags["repair_stage"] = 3
			return _emit_result(true, "Комната укрыта от ветра и готова к первой ночи.", true)
		_:
			return _emit_result(true, "Отремонтированная комната выдержит эту ночь.")


func _advance_campfire() -> Dictionary:
	var flags: Dictionary = get_flags()
	var stage: int = int(flags["campfire_stage"])
	match stage:
		0:
			if not _consume_items({"wood": 2, "stone": 2}):
				return _emit_result(false, "Для костра нужно 2 древесины и 2 камня.")
			flags["campfire_stage"] = 1
			return _emit_result(true, "Кострище сложено. Взаимодействуйте снова, чтобы разжечь огонь.", true)
		1:
			if not bool(flags["tools_found"]):
				return _emit_result(false, "Без инструментов и старого огнива разжечь костёр не получится.")
			flags["campfire_stage"] = 2
			return _emit_result(true, "Огонь разгорелся и начал прогревать двор.", true)
		_:
			if get_item_count("raw_water") <= 0:
				return _emit_result(false, "Принесите котелок сырой воды, чтобы вскипятить её.")
			_consume_items({"raw_water": 1})
			_add_item("boiled_water", 1)
			flags["water_boiled"] = true
			return _emit_result(true, "Вода прокипела и теперь безопасна.", true)


func _advance_bed() -> Dictionary:
	var flags: Dictionary = get_flags()
	if int(flags["repair_stage"]) < 3:
		return _emit_result(false, "Сначала нужно закончить ремонт комнаты.")
	if not bool(flags["bed_ready"]):
		if not _consume_items({"wood": 1}):
			return _emit_result(false, "Для основания временной постели нужна 1 древесина.")
		flags["bed_ready"] = true
		return _emit_result(true, "Временная постель готова. После 18:00 здесь можно завершить день.", true)
	if get_minute_of_day() < EVENING_MINUTE:
		return _emit_result(false, "Ещё слишком рано спать. Используйте оставшееся дневное время.")
	return _sleep_until_morning()


func _sleep_until_morning() -> Dictionary:
	var flags: Dictionary = get_flags()
	var outcomes: Array = []
	if int(flags["repair_stage"]) >= 3:
		outcomes.append("сухая комната")
	else:
		outcomes.append("холодный сквозняк")
	if int(flags["campfire_stage"]) >= 2:
		outcomes.append("остаточное тепло")
	if get_item_count("boiled_water") > 0:
		outcomes.append("безопасная вода")
	if get_item_count("food") > 0:
		_consume_items({"food": 1})
		outcomes.append("лёгкий ужин")
	else:
		outcomes.append("голодный сон")

	state["outcomes"] = outcomes
	state["day"] = get_day() + 1
	state["minute_of_day"] = 7 * 60
	flags["first_night_complete"] = true
	return _emit_result(true, "Наступило новое утро. Итог: %s." % ", ".join(outcomes), true, true)


func _can_add_item(item_id: String, amount: int) -> bool:
	var added_weight: float = float(ITEM_WEIGHTS.get(item_id, 0.0)) * float(amount)
	return get_inventory_weight() + added_weight <= MAX_CARRY_WEIGHT + 0.001


func _add_item(item_id: String, amount: int) -> void:
	var inventory: Dictionary = get_inventory()
	inventory[item_id] = int(inventory.get(item_id, 0)) + amount


func _consume_items(costs: Dictionary) -> bool:
	var inventory: Dictionary = get_inventory()
	for item_variant: Variant in costs.keys():
		var item_id: String = String(item_variant)
		if int(inventory.get(item_id, 0)) < int(costs[item_id]):
			return false
	for item_variant: Variant in costs.keys():
		var item_id: String = String(item_variant)
		inventory[item_id] = int(inventory.get(item_id, 0)) - int(costs[item_id])
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
	var defaults: Dictionary = create_new_state(int(state.get("seed", DEFAULT_SEED)))
	for key_variant: Variant in defaults.keys():
		var key: String = String(key_variant)
		if not state.has(key):
			state[key] = defaults[key]

	state["version"] = int(state.get("version", SAVE_VERSION))
	state["seed"] = int(state.get("seed", DEFAULT_SEED))
	state["day"] = int(state.get("day", 1))
	state["minute_of_day"] = int(state.get("minute_of_day", START_MINUTE))

	var inventory: Dictionary = state["inventory"] as Dictionary
	var default_inventory: Dictionary = defaults["inventory"] as Dictionary
	for item_variant: Variant in default_inventory.keys():
		var item_id: String = String(item_variant)
		inventory[item_id] = int(inventory.get(item_id, 0))

	var flags: Dictionary = state["flags"] as Dictionary
	var default_flags: Dictionary = defaults["flags"] as Dictionary
	for flag_variant: Variant in default_flags.keys():
		var flag_id: String = String(flag_variant)
		if not flags.has(flag_id):
			flags[flag_id] = default_flags[flag_id]
	flags["repair_stage"] = clampi(int(flags["repair_stage"]), 0, 3)
	flags["campfire_stage"] = clampi(int(flags["campfire_stage"]), 0, 2)

	var stored_position: Array = state.get("player_position", defaults["player_position"]) as Array
	if stored_position.size() < 2:
		state["player_position"] = defaults["player_position"]
	else:
		state["player_position"] = [float(stored_position[0]), float(stored_position[1])]

	if int(state["version"]) != SAVE_VERSION:
		push_warning("Save version %s loaded into prototype version %s." % [state["version"], SAVE_VERSION])
