class_name MechanicsLabScenarios
extends RefCounted

const Simulation := preload("res://src/simulation/first_night_simulation.gd")

const FRESH_START: StringName = &"fresh_start"
const PREPARED_EVENING: StringName = &"prepared_evening"
const MORNING_WITH_MIRA: StringName = &"morning_with_mira"
const MIRA_RESTING: StringName = &"mira_resting"
const PREPARED_MINUTE: int = 17 * 60 + 50


static func definitions() -> Array[Dictionary]:
	return [
		{
			"id": FRESH_START,
			"label": "Начало первого дня",
			"description": "День 1, 11:00. Чистое начало среза.",
		},
		{
			"id": PREPARED_EVENING,
			"label": "Готово к вечеру",
			"description": "День 1, 17:50. Все приготовления завершены.",
		},
		{
			"id": MORNING_WITH_MIRA,
			"label": "Первое утро",
			"description": "День 2, 07:00. Мира появилась, но ещё неизвестна.",
		},
		{
			"id": MIRA_RESTING,
			"label": "Поздний вечер Миры",
			"description": "День 2, 22:00. Мира прожила день и отдыхает.",
		},
	]


static func get_definition(scenario_id: StringName) -> Dictionary:
	for definition: Dictionary in definitions():
		if StringName(definition.get("id", &"")) == scenario_id:
			return definition.duplicate(true)
	return {}


static func build(scenario_id: StringName) -> Dictionary:
	var definition: Dictionary = get_definition(scenario_id)
	if definition.is_empty():
		return {
			"success": false,
			"scenario_id": scenario_id,
			"message": "Неизвестный сценарий лаборатории: %s" % scenario_id,
			"steps": [],
		}

	var simulation: FirstNightSimulation = Simulation.new()
	var steps: Array[Dictionary] = []
	if (
		scenario_id == PREPARED_EVENING
		or scenario_id == MORNING_WITH_MIRA
		or scenario_id == MIRA_RESTING
	):
		if not _prepare_evening(simulation, steps):
			return _failed_build(scenario_id, simulation, steps)
	if scenario_id == MORNING_WITH_MIRA or scenario_id == MIRA_RESTING:
		if not _advance_to(simulation, simulation.EVENING_MINUTE, steps):
			return _failed_build(scenario_id, simulation, steps)
		if not _interact(simulation, "core:bed_site", steps):
			return _failed_build(scenario_id, simulation, steps)
	if scenario_id == MIRA_RESTING:
		if not _advance_to(simulation, 22 * 60, steps):
			return _failed_build(scenario_id, simulation, steps)

	return {
		"success": true,
		"scenario_id": scenario_id,
		"definition": definition,
		"simulation": simulation,
		"state": simulation.export_state(),
		"steps": steps,
	}


static func _prepare_evening(
	simulation: FirstNightSimulation,
	steps: Array[Dictionary]
) -> bool:
	var targets: Array[String] = [
		"core:common_house",
		"core:old_tools",
		"core:wood_north",
		"core:wood_west",
		"core:wood_east",
		"core:stone_south",
		"core:stone_east",
		"core:berry_bush",
		"core:shore_water",
		"core:repair_room",
		"core:repair_room",
		"core:repair_room",
		"core:campfire_site",
		"core:campfire_site",
		"core:campfire_site",
		"core:bed_site",
	]
	for target_id: String in targets:
		if not _interact(simulation, target_id, steps):
			return false
	return _advance_to(simulation, PREPARED_MINUTE, steps)


static func _interact(
	simulation: FirstNightSimulation,
	target_id: String,
	steps: Array[Dictionary]
) -> bool:
	var missing_position := Vector2(-999999.0, -999999.0)
	var target_position: Vector2 = simulation.get_interaction_target_position(
		target_id,
		missing_position
	)
	if target_position.is_equal_approx(missing_position):
		steps.append({
			"kind": "interaction",
			"target_id": target_id,
			"success": false,
			"message": "Цель сценария отсутствует.",
		})
		return false

	simulation.set_player_position(target_position)
	var result: Dictionary = simulation.execute_command(
		simulation.PLAYER_ACTOR_ID,
		target_id,
		simulation.ACTION_INTERACT
	)
	steps.append({
		"kind": "interaction",
		"target_id": target_id,
		"success": bool(result.get("success", false)),
		"message_key": String(result.get("message_key", "")),
		"message_args": (result.get("message_args", {}) as Dictionary).duplicate(true),
	})
	return bool(result.get("success", false))


static func _advance_to(
	simulation: FirstNightSimulation,
	target_minute: int,
	steps: Array[Dictionary]
) -> bool:
	var amount: int = target_minute - simulation.get_minute_of_day()
	var success: bool = amount == 0 or simulation.advance_minutes(amount)
	steps.append({
		"kind": "advance_time",
		"target_minute": target_minute,
		"success": success,
	})
	return success and simulation.get_minute_of_day() == target_minute


static func _failed_build(
	scenario_id: StringName,
	simulation: FirstNightSimulation,
	steps: Array[Dictionary]
) -> Dictionary:
	return {
		"success": false,
		"scenario_id": scenario_id,
		"message": "Не удалось воспроизвести достижимое состояние сценария.",
		"simulation": simulation,
		"state": simulation.export_state(),
		"steps": steps,
	}
