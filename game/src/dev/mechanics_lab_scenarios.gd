class_name MechanicsLabScenarios
extends RefCounted

const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const ConstructionCommand := preload(
	"res://src/construction/construction_command.gd"
)
const NpcWorkRequest := preload("res://src/simulation/npc_work_request.gd")
const FirstNightContent := preload("res://src/content/first_night_content.gd")

const FRESH_START: StringName = &"fresh_start"
const PREPARED_EVENING: StringName = &"prepared_evening"
const MORNING_WITH_MIRA: StringName = &"morning_with_mira"
const MIRA_RESTING: StringName = &"mira_resting"
const MIRA_AFTER_SHARED_WALL: StringName = &"mira_after_shared_wall"
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
		{
			"id": MIRA_AFTER_SHARED_WALL,
			"label": "После совместной стены",
			"description": "День 2, 07:20. Мира завершила стену и готова вспомнить об этом.",
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
		or scenario_id == MIRA_AFTER_SHARED_WALL
	):
		if not _prepare_evening(simulation, steps):
			return _failed_build(scenario_id, simulation, steps)
	if (
		scenario_id == MORNING_WITH_MIRA
		or scenario_id == MIRA_RESTING
		or scenario_id == MIRA_AFTER_SHARED_WALL
	):
		if not _advance_to(simulation, simulation.EVENING_MINUTE, steps):
			return _failed_build(scenario_id, simulation, steps)
		if not _interact(simulation, "core:bed_site", steps):
			return _failed_build(scenario_id, simulation, steps)
	if scenario_id == MIRA_RESTING:
		if not _advance_to(simulation, 22 * 60, steps):
			return _failed_build(scenario_id, simulation, steps)
	if scenario_id == MIRA_AFTER_SHARED_WALL:
		if not _prepare_shared_wall_memory(simulation, steps):
			return _failed_build(scenario_id, simulation, steps)

	return {
		"success": true,
		"scenario_id": scenario_id,
		"definition": definition,
		"simulation": simulation,
		"state": simulation.export_state(),
		"steps": steps,
	}


static func _prepare_shared_wall_memory(
	simulation: FirstNightSimulation,
	steps: Array[Dictionary]
) -> bool:
	if not _interact(simulation, "core:first_neighbor", steps):
		return false
	var target_cell := Vector2i(22, 29)
	var build_result: Dictionary = simulation.execute_construction_command(
		ConstructionCommand.place_wall_blueprint(target_cell)
	)
	steps.append({
		"kind": "construction_command",
		"success": bool(build_result.get("success", false)),
		"reason_id": String(build_result.get("reason_id", "")),
	})
	if not bool(build_result.get("success", false)):
		return false
	simulation.set_player_position(FirstNightContent.cell_center(
		target_cell.x,
		target_cell.y
	))
	var delivery_result: Dictionary = simulation.execute_construction_command(
		ConstructionCommand.deliver_blueprint_materials(target_cell)
	)
	steps.append({
		"kind": "construction_delivery",
		"success": bool(delivery_result.get("success", false)),
		"reason_id": String(delivery_result.get("reason_id", "")),
	})
	if not bool(delivery_result.get("success", false)):
		return false
	simulation.set_player_position(
		simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	)

	var request_result: Dictionary = simulation.execute_npc_work_request(
		NpcWorkRequest.request_construction_help(
			"core:first_neighbor",
			target_cell
		)
	)
	steps.append({
		"kind": "work_request",
		"success": bool(request_result.get("success", false)),
		"reason_id": String(request_result.get("reason_id", "")),
	})
	if not bool(request_result.get("success", false)):
		return false

	if not _advance_to(simulation, 7 * 60 + 20, steps):
		return false
	if simulation.get_npc_memories("core:first_neighbor").size() != 1:
		return false
	simulation.set_player_position(
		simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	)
	return true


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
	var result: Dictionary
	var required_work: int = simulation.get_resource_work_required(
		target_id
	)
	if required_work > 0:
		for _minute: int in range(required_work):
			result = simulation.execute_resource_work(
				simulation.PLAYER_ACTOR_ID,
				target_id
			)
			if not bool(result.get("success", false)):
				break
		if bool(result.get("success", false)):
			result = simulation.try_pickup_item(
				String(result.get("drop_item_id", "")),
				int(result.get("drop_amount", 0))
			)
	else:
		result = simulation.execute_command(
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
