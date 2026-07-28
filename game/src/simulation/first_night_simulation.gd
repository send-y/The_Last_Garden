class_name FirstNightSimulation
extends RefCounted

signal event_emitted(event: Dictionary)

const Content := preload("res://src/content/first_night_content.gd")
const Npcs := preload("res://src/characters/npc_catalog.gd")
const Localized := preload("res://src/localization/localized_text.gd")

const SAVE_VERSION: int = 4
const DEFAULT_SEED: int = 247061
const START_MINUTE: int = 11 * 60
const EVENING_MINUTE: int = 18 * 60
const LATEST_MINUTE: int = 23 * 60 + 50
const GAME_MINUTES_PER_SECOND: float = 0.75
const MAX_CARRY_WEIGHT: float = 24.0
const PLAYER_ACTOR_ID: String = "core:player"
const ACTION_INTERACT: String = "core:interact"
const OUTCOME_DRY_ROOM_ID: String = "core:dry_room"
const OUTCOME_COLD_DRAFT_ID: String = "core:cold_draft"
const OUTCOME_RESIDUAL_WARMTH_ID: String = "core:residual_warmth"
const OUTCOME_SAFE_WATER_ID: String = "core:safe_water"
const OUTCOME_LIGHT_SUPPER_ID: String = "core:light_supper"
const OUTCOME_HUNGRY_SLEEP_ID: String = "core:hungry_sleep"

const OUTCOME_LABEL_KEYS: Dictionary = {
	OUTCOME_DRY_ROOM_ID: "first_night.outcome.dry_room",
	OUTCOME_COLD_DRAFT_ID: "first_night.outcome.cold_draft",
	OUTCOME_RESIDUAL_WARMTH_ID: "first_night.outcome.residual_warmth",
	OUTCOME_SAFE_WATER_ID: "first_night.outcome.safe_water",
	OUTCOME_LIGHT_SUPPER_ID: "first_night.outcome.light_supper",
	OUTCOME_HUNGRY_SLEEP_ID: "first_night.outcome.hungry_sleep",
}

# These Russian values are fingerprints of save versions 1-3, not display copy.
const LEGACY_V3_OUTCOME_IDS: Dictionary = {
	"сухая комната": OUTCOME_DRY_ROOM_ID,
	"холодный сквозняк": OUTCOME_COLD_DRAFT_ID,
	"остаточное тепло": OUTCOME_RESIDUAL_WARMTH_ID,
	"безопасная вода": OUTCOME_SAFE_WATER_ID,
	"лёгкий ужин": OUTCOME_LIGHT_SUPPER_ID,
	"голодный сон": OUTCOME_HUNGRY_SLEEP_ID,
}

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
			push_error("Save state rejected: %s." % String(header_result.get("code", "unknown")))
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
			"message_key": "save.error.missing_version",
			"message_args": {},
		}

	var raw_version: Variant = raw_state["version"]
	if typeof(raw_version) != TYPE_INT and typeof(raw_version) != TYPE_FLOAT:
		return {
			"success": false,
			"code": "invalid_version",
			"message_key": "save.error.version_type",
			"message_args": {},
		}

	var numeric_version: float = float(raw_version)
	if not is_finite(numeric_version) or numeric_version != floor(numeric_version):
		return {
			"success": false,
			"code": "invalid_version",
			"message_key": "save.error.version_integer",
			"message_args": {},
		}

	var version: int = int(numeric_version)
	if version < 1:
		return {
			"success": false,
			"code": "invalid_version",
			"message_key": "save.error.version_range",
			"message_args": {},
		}
	if version > SAVE_VERSION:
		return {
			"success": false,
			"code": "future_version",
			"message_key": "save.error.future_version",
			"message_args": {},
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
	return _advance_clock(whole_minutes)


func advance_minutes(amount: int) -> bool:
	if amount <= 0:
		return false
	return _advance_clock(amount)


func _advance_clock(amount: int) -> bool:
	var previous_minute: int = get_minute_of_day()
	var next_minute: int = mini(previous_minute + amount, LATEST_MINUTE)
	state["minute_of_day"] = next_minute

	var flags: Dictionary = _flags_mutable()
	if previous_minute < 17 * 60 and next_minute >= 17 * 60 and not bool(flags["dusk_warned"]):
		flags["dusk_warned"] = true
		_emit_result(true, "first_night.message.dusk", true)
	if next_minute >= LATEST_MINUTE and not bool(flags["late_warned"]):
		flags["late_warned"] = true
		_emit_result(true, "first_night.message.exhausted", true)

	event_emitted.emit({"type": "time_changed", "minute": next_minute})
	return next_minute != previous_minute


func execute_interaction(target_id: String) -> Dictionary:
	return execute_command(PLAYER_ACTOR_ID, target_id, ACTION_INTERACT)


func execute_command(actor_id: String, target_id: String, action_id: String) -> Dictionary:
	if actor_id != PLAYER_ACTOR_ID:
		return _emit_result(false, "interaction.failure.unknown_actor")
	if action_id != ACTION_INTERACT:
		return _emit_result(false, "interaction.failure.unsupported_action")

	var target: Dictionary = _resolve_interaction_target(target_id)
	if target.is_empty():
		return _emit_result(false, "interaction.failure.missing_target")

	var resolved_target_id: String = String(target.get("id", ""))
	var kind: String = String(target.get("kind", ""))
	if should_hide_interactable(resolved_target_id, kind):
		return _emit_result(false, "interaction.failure.target_unavailable")

	var target_position: Vector2 = target.get("position", Vector2.ZERO) as Vector2
	if get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return _emit_result(false, "interaction.failure.too_far")

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
	return _emit_result(false, "interaction.failure.unsupported_target")


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


func get_object_label_key(kind: String, fallback_key: String, object_id: String = "") -> String:
	var flags: Dictionary = get_flags()
	match kind:
		"npc":
			return npc_catalog.get_label_key(get_npcs(), object_id, fallback_key)
		"tools":
			return content.get_stage_label_key(kind, 0, fallback_key)
		"repair":
			var stage: int = int(flags["repair_stage"])
			return content.get_stage_label_key(kind, stage, fallback_key)
		"campfire":
			var fire_stage: int = int(flags["campfire_stage"])
			return content.get_stage_label_key(kind, fire_stage, fallback_key)
		"bed":
			var bed_stage: int = 1 if bool(flags["bed_ready"]) else 0
			return content.get_stage_label_key(kind, bed_stage, fallback_key)
		_:
			return fallback_key


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


func get_current_objective_key() -> String:
	var flags: Dictionary = get_flags()
	if bool(flags["first_night_complete"]):
		var first_neighbor: Dictionary = get_npcs().get("core:first_neighbor", {}) as Dictionary
		if bool(first_neighbor.get("active", false)) and int(first_neighbor.get("talk_count", 0)) <= 0:
			return "first_night.objective.meet_neighbor"
		return "first_night.objective.complete"
	if not bool(flags["tools_found"]):
		return "first_night.objective.find_tools"
	if int(flags["repair_stage"]) < 3:
		return "first_night.objective.repair_room"
	if int(flags["campfire_stage"]) < 2:
		return "first_night.objective.light_campfire"
	if not bool(flags["water_boiled"]):
		return "first_night.objective.boil_water"
	if not bool(flags["bed_ready"]):
		return "first_night.objective.prepare_bed"
	if get_minute_of_day() < EVENING_MINUTE:
		return "first_night.objective.wait_for_evening"
	return "first_night.objective.sleep"


func _inspect_house() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if bool(flags["house_inspected"]):
		return _emit_result(
			true,
			content.get_message_key("house_repeat", "first_night.message.house.repeat")
		)
	flags["house_inspected"] = true
	return _emit_result(
		true,
		content.get_message_key("house_first", "first_night.message.house.first"),
		true
	)


func _find_tools() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if bool(flags["tools_found"]):
		return _emit_result(
			true,
			content.get_message_key("tools_repeat", "first_night.message.tools.repeat")
		)
	flags["tools_found"] = true
	return _emit_result(
		true,
		content.get_message_key("tools_first", "first_night.message.tools.first"),
		true
	)


func _collect_resource(object_id: String, kind: String) -> Dictionary:
	var rule: Dictionary = content.get_collect_rule(kind)
	var item_id: String = String(rule.get("item_id", ""))
	var amount: int = int(rule.get("amount", 0))
	var repeatable: bool = bool(rule.get("repeatable", false))

	if not repeatable and is_collected(object_id):
		return _emit_result(
			false,
			String(rule.get("empty_message_key", "first_night.collect.empty"))
		)
	if not _can_add_item(item_id, amount):
		return _emit_result(
			false,
			String(rule.get("full_message_key", "first_night.inventory.too_heavy"))
		)

	if not repeatable:
		var collected: Dictionary = state["collected"] as Dictionary
		collected[content.normalize_object_id(object_id)] = true
	_add_item(item_id, amount)
	return _emit_result(
		true,
		String(rule.get("message_key", "first_night.collect.generic.success")),
		true,
		false,
		{"amount": amount}
	)


func _advance_repair() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if not bool(flags["tools_found"]):
		return _emit_result(
			false,
			content.get_failure_message_key(
				"repair_tools_required",
				"first_night.failure.repair.tools_required"
			)
		)

	var stage: int = int(flags["repair_stage"])
	match stage:
		0:
			flags["repair_stage"] = 1
			return _emit_result(
				true,
				content.get_message_key(
					"repair_stage_0",
					"first_night.message.repair.cleared"
				),
				true
			)
		1:
			if not _consume_items(content.get_cost("repair_stage_1")):
				return _emit_result(
					false,
					content.get_failure_message_key(
						"repair_stage_1_cost",
						"first_night.failure.repair.roof_resources"
					)
				)
			flags["repair_stage"] = 2
			return _emit_result(
				true,
				content.get_message_key(
					"repair_stage_1",
					"first_night.message.repair.roof_strengthened"
				),
				true
			)
		2:
			if not _consume_items(content.get_cost("repair_stage_2")):
				return _emit_result(
					false,
					content.get_failure_message_key(
						"repair_stage_2_cost",
						"first_night.failure.repair.finish_resources"
					)
				)
			flags["repair_stage"] = 3
			return _emit_result(
				true,
				content.get_message_key(
					"repair_stage_2",
					"first_night.message.repair.finished"
				),
				true
			)
		_:
			return _emit_result(
				true,
				content.get_message_key(
					"repair_done",
					"first_night.message.repair.already_done"
				)
			)


func _advance_campfire() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	var stage: int = int(flags["campfire_stage"])
	match stage:
		0:
			if not _consume_items(content.get_cost("campfire_stage_0")):
				return _emit_result(
					false,
					content.get_failure_message_key(
						"campfire_stage_0_cost",
						"first_night.failure.campfire.resources"
					)
				)
			flags["campfire_stage"] = 1
			return _emit_result(
				true,
				content.get_message_key(
					"campfire_stage_0",
					"first_night.message.campfire.built"
				),
				true
			)
		1:
			if not bool(flags["tools_found"]):
				return _emit_result(
					false,
					content.get_failure_message_key(
						"campfire_tools_required",
						"first_night.failure.campfire.tools_required"
					)
				)
			flags["campfire_stage"] = 2
			return _emit_result(
				true,
				content.get_message_key(
					"campfire_stage_1",
					"first_night.message.campfire.lit"
				),
				true
			)
		_:
			if get_item_count(FirstNightContent.RAW_WATER_ID) <= 0:
				return _emit_result(
					false,
					content.get_failure_message_key(
						"water_required",
						"first_night.failure.water.raw_required"
					)
				)
			_consume_items(content.get_cost("boil_water"))
			_add_item(FirstNightContent.BOILED_WATER_ID, 1)
			flags["water_boiled"] = true
			return _emit_result(
				true,
				content.get_message_key(
					"water_boiled",
					"first_night.message.water.boiled"
				),
				true
			)


func _advance_bed() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	if int(flags["repair_stage"]) < 3:
		return _emit_result(
			false,
			content.get_failure_message_key(
				"bed_repair_required",
				"first_night.failure.bed.room_required"
			)
		)
	if not bool(flags["bed_ready"]):
		if not _consume_items(content.get_cost("bed")):
			return _emit_result(
				false,
				content.get_failure_message_key(
					"bed_cost",
					"first_night.failure.bed.resources"
				)
			)
		flags["bed_ready"] = true
		return _emit_result(
			true,
			content.get_message_key("bed_ready", "first_night.message.bed.ready"),
			true
		)
	if get_minute_of_day() < EVENING_MINUTE:
		return _emit_result(
			false,
			content.get_failure_message_key(
				"bed_too_early",
				"first_night.failure.bed.too_early"
			)
		)
	return _sleep_until_morning()


func _talk_to_npc(npc_id: String) -> Dictionary:
	var result: Dictionary = npc_catalog.talk(_npcs_mutable(), npc_id)
	return _emit_result(
		bool(result.get("success", false)),
		String(result.get("message_key", "interaction.failure.no_npc")),
		bool(result.get("changed", false)),
		false,
		(result.get("message_args", {}) as Dictionary).duplicate(true)
	)


func _sleep_until_morning() -> Dictionary:
	var flags: Dictionary = _flags_mutable()
	var outcomes: Array[String] = []
	if int(flags["repair_stage"]) >= 3:
		outcomes.append(OUTCOME_DRY_ROOM_ID)
	else:
		outcomes.append(OUTCOME_COLD_DRAFT_ID)
	if int(flags["campfire_stage"]) >= 2:
		outcomes.append(OUTCOME_RESIDUAL_WARMTH_ID)
	if get_item_count(FirstNightContent.BOILED_WATER_ID) > 0:
		outcomes.append(OUTCOME_SAFE_WATER_ID)
	if get_item_count(FirstNightContent.FOOD_ID) > 0:
		_consume_items(content.get_cost("sleep_food"))
		outcomes.append(OUTCOME_LIGHT_SUPPER_ID)
	else:
		outcomes.append(OUTCOME_HUNGRY_SLEEP_ID)

	state["outcomes"] = outcomes
	state["day"] = get_day() + 1
	state["minute_of_day"] = 7 * 60
	flags["first_night_complete"] = true
	var npc_arrived: bool = npc_catalog.activate_after_first_night(_npcs_mutable())
	var result: Dictionary = _emit_result(
		true,
		(
			"first_night.message.morning.summary_with_neighbor"
			if npc_arrived
			else "first_night.message.morning.summary"
		),
		true,
		true,
		{
			"outcomes": Localized.text_reference_list(_get_outcome_label_keys(outcomes)),
		}
	)
	event_emitted.emit({"type": "time_changed", "minute": get_minute_of_day()})
	return result


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


func _get_outcome_label_keys(outcome_ids: Array[String]) -> Array[String]:
	var label_keys: Array[String] = []
	for outcome_id: String in outcome_ids:
		var label_key: String = String(OUTCOME_LABEL_KEYS.get(outcome_id, ""))
		if not label_key.is_empty():
			label_keys.append(label_key)
	return label_keys


func _emit_result(
	success: bool,
	message_key: String,
	changed: bool = false,
	auto_save: bool = false,
	message_args: Dictionary = {}
) -> Dictionary:
	var event: Dictionary = {
		"type": "command_result",
		"success": success,
		"message_key": message_key,
		"message_args": message_args.duplicate(true),
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
	state["outcomes"] = _normalize_outcomes(state.get("outcomes"), loaded_version)

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


static func _normalize_outcomes(value: Variant, loaded_version: int) -> Array[String]:
	var outcomes: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return outcomes
	var raw_outcomes: Array = value as Array
	for entry: Variant in raw_outcomes:
		if typeof(entry) == TYPE_STRING or typeof(entry) == TYPE_STRING_NAME:
			var outcome_id: String = String(entry)
			if loaded_version <= 3:
				outcome_id = String(LEGACY_V3_OUTCOME_IDS.get(outcome_id, outcome_id))
			if not outcome_id.is_empty() and outcome_id.contains(":"):
				outcomes.append(outcome_id)
	return outcomes
