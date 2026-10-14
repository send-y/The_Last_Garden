class_name MechanicsLabScenarios
extends RefCounted

const Simulation := preload("res://src/simulation/world_simulation.gd")
const ConstructionCommand := preload(
	"res://src/construction/construction_command.gd"
)
const NpcWorkRequest := preload("res://src/simulation/npc_work_request.gd")
const FirstNightContent := preload("res://src/content/first_night_content.gd")
const ResidentHomes := preload("res://src/dev/resident_homes_scenario.gd")
const PackageD := preload("res://src/dev/package_d_scenarios.gd")
const SettlementStress := preload("res://src/dev/settlement_stress_scenario.gd")
const SETTLEMENT_STRESS: StringName = &"settlement_stress"
const STRESS_PRODUCTION: StringName = &"stress_production"
const STRESS_GATHER: StringName = &"stress_gather"

const FRESH_START: StringName = &"fresh_start"
const PLAYER_CHECKPOINT: StringName = &"player_checkpoint"
const RESIDENT_HOMES: StringName = &"resident_homes"
const HOME_PRODUCTION: StringName = &"home_production"
const GENERATED_RESIDENTS: StringName = &"generated_residents"
const PREPARED_EVENING: StringName = &"prepared_evening"
const MORNING_WITH_MIRA: StringName = &"morning_with_mira"
const MIRA_RESTING: StringName = &"mira_resting"
const MIRA_AFTER_SHARED_WALL: StringName = &"mira_after_shared_wall"
const WORKBENCH_CRAFTING: StringName = &"workbench_crafting"
const SURFACE_BOULDERS: StringName = &"surface_boulders"
const BUCKET_HOTBAR: StringName = &"bucket_hotbar"
const PREPARED_MINUTE: int = 17 * 60 + 50


static func definitions(include_historical: bool = false) -> Array[Dictionary]:
	var all: Array[Dictionary] = [
		{"id":&"day_three","label":"День 3: готовый склад 3×3","description":"Искусственный старт, не копия сейва.\nСклад, верстак и два жителя."},
		{"id":&"first_meeting_hungry","label":"Первая встреча: оба голодны","description":"Незнакомая Мира с припасами.\nПроверь разговор и передачу еды."},
		{"id":&"communal_production","label":"Доски для общей стены","description":"Есть древесина и верстак.\nМира делает доски и строит стену."},
		{"id":&"missing_workbench","label":"Просьба о верстаке","description":"Общая стена без досок и верстака.\nМира подходит с просьбой."},
		{"id": PLAYER_CHECKPOINT, "label": "Архив плейтеста: день 5", "description": "Реальная копия мира 14 октября.\nПауза; обычный сейв защищён."},
		{"id": SETTLEMENT_STRESS, "label": "30 жителей: стресс поселения", "description": "30 домов · 60 грядок · все работы.\nСклад пополняется. Пробел — пауза."},
		{"id": STRESS_PRODUCTION, "label": "30 жителей: нужны доски", "description": "30 домов · нужны доски для мебели.\nСырьё и еда пополняются."},
		{"id": STRESS_GATHER, "label": "30 жителей: добыча и полив", "description": "30 домов уже обустроены.\nДобыча сырья и полив; еда пополняется."},
		{"id": HOME_PRODUCTION, "label":"Житель делает доски для дома", "description":"Личные дома и верстак. На общем складе 25 древесины; 5 защищены. Досок нет: житель должен изготовить их для своей мебели."},
		{"id": RESIDENT_HOMES, "label":"Дома жителей и защищённый запас", "description":"Два знакомых жителя: отдельные дома, самостоятельная мебель, теснота и склад с защищённым запасом в 35 досок."},
		{"id": GENERATED_RESIDENTS, "label":"Три случайных жителя", "description":"Три незнакомых человека рядом с домом: разговор, ночлег и работа."},
		{
			"id": FRESH_START,
			"label": "Обычная новая игра",
			"description": "День 1, 11:00. Действующий старт игры.",
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
			"description": "День 2, 07:35. Мира завершила стену и готова вспомнить об этом.",
		},
		{
			"id": WORKBENCH_CRAFTING,
			"label": "Верстак и первые рецепты",
			"description": "Готовый верстак рядом с игроком и пять брёвен в рюкзаке.",
		},
		{
			"id": SURFACE_BOULDERS,
			"label": "Крупные валуны",
			"description": "Сгенерированные валуны рядом с игроком для проверки добычи.",
		},
		{
			"id": BUCKET_HOTBAR,
			"label": "Ведро и хотбар",
			"description": "Два ведра с разным наполнением у доступного берега.",
		},
	]
	if include_historical: return all
	var obsolete := [PREPARED_EVENING,MORNING_WITH_MIRA,MIRA_RESTING,MIRA_AFTER_SHARED_WALL,SETTLEMENT_STRESS,STRESS_PRODUCTION,STRESS_GATHER]
	return all.filter(func(entry: Dictionary) -> bool: return not obsolete.has(StringName(entry.id)))


static func get_definition(scenario_id: StringName) -> Dictionary:
	for definition: Dictionary in definitions(true):
		if StringName(definition.get("id", &"")) == scenario_id:
			return definition.duplicate(true)
	return {}


static func build(scenario_id: StringName, stress_count: int = 30) -> Dictionary:
	var definition: Dictionary = get_definition(scenario_id)
	if definition.is_empty():
		return {
			"success": false,
			"scenario_id": scenario_id,
			"message": "Неизвестный сценарий лаборатории: %s" % scenario_id,
			"steps": [],
		}

	if scenario_id in [SETTLEMENT_STRESS, STRESS_PRODUCTION, STRESS_GATHER]:
		var mode := "production" if scenario_id == STRESS_PRODUCTION else ("gather" if scenario_id == STRESS_GATHER else "full")
		var stress: Dictionary = SettlementStress.build(stress_count, mode)
		stress.scenario_id = scenario_id
		stress.definition = definition
		stress.steps = []
		return stress
	if scenario_id in [&"day_three",&"first_meeting_hungry",&"communal_production",&"missing_workbench"]:
		var current := PackageD.build(scenario_id)
		current.scenario_id = scenario_id
		current.definition = definition
		return current
	if scenario_id == PLAYER_CHECKPOINT:
		var base := "res://tests/fixtures/package_d/"
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "manifest.json"))
		if not manifest is Dictionary: return {"success": false}
		var path := base + String(manifest.file)
		if FileAccess.get_sha256(path) != String(manifest.sha256): return {"success": false, "message": "Контрольная сумма архива не совпала."}
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not saved is Dictionary or not bool(Simulation.validate_save_header(saved).get("success", false)): return {"success": false}
		var checkpoint := Simulation.new(saved)
		return {"success": true, "scenario_id": scenario_id, "definition": definition, "simulation": checkpoint, "state": checkpoint.export_state(), "steps": []}
	var initial_state: Dictionary = Simulation.create_new_state()
	if scenario_id == FRESH_START: initial_state = Simulation.create_new_game_state()
	if scenario_id in [RESIDENT_HOMES,HOME_PRODUCTION]: initial_state = ResidentHomes.initial_state()
	if scenario_id == HOME_PRODUCTION:
		initial_state.structures.append({"building_id":"core:workbench","cell":[36,34],"stage_id":"core:complete"})
	if scenario_id == GENERATED_RESIDENTS: initial_state = Simulation.create_new_game_state()
	if scenario_id == BUCKET_HOTBAR:
		initial_state["item_instances"] = [
			{
				"instance_id": "core:item_instance_000001",
				"item_id": "core:bucket",
				"state": {"charges": 0},
				"location": {"kind": "inventory", "id": ""},
			},
			{
				"instance_id": "core:item_instance_000002",
				"item_id": "core:bucket",
				"state": {"charges": 1},
				"location": {"kind": "inventory", "id": ""},
			},
		]
		initial_state["next_item_instance_serial"] = 3
		var shore_position := FirstNightContent.cell_center(7, 27)
		initial_state["player_position"] = [shore_position.x, shore_position.y]
	if scenario_id == MIRA_AFTER_SHARED_WALL:
		(initial_state["inventory"] as Dictionary)["core:plank"] = 30
	var simulation: Simulation = Simulation.new(initial_state)
	if scenario_id == GENERATED_RESIDENTS:
		for index: int in range(3):
			var generated: Dictionary = simulation.create_generated_npc(94+index,Vector2i(24+index,29))
			if not generated.ok or not simulation.arrive_npc(generated.npc_id,Vector2i(24+index,29)).ok:
				return _failed_build(scenario_id,simulation,[])
	var steps: Array[Dictionary] = []
	if scenario_id in [RESIDENT_HOMES,HOME_PRODUCTION] and not ResidentHomes.prepare(simulation, steps):
		return _failed_build(scenario_id, simulation, steps)
	if scenario_id == HOME_PRODUCTION:
		simulation.state.storage_items = simulation.state.storage_items.filter(func(record: Dictionary) -> bool: return String(record.item_id) != "core:plank")
		simulation.set_stock_reserve("core:plank",0)
		simulation.set_stock_reserve("core:wood",5)
		for i: int in range(5):
			simulation.state.inventory["core:wood"] = 5
			var stored := false
			for cell: Vector2i in ResidentHomes.WAREHOUSE:
				if stored: break
				simulation.set_player_position(FirstNightContent.cell_center(cell.x,cell.y+1))
				stored = bool(simulation.transfer_inventory_stack_to_storage(cell,"core:wood",0).success)
			if not stored: return _failed_build(scenario_id,simulation,steps)
		simulation.set_player_position(FirstNightContent.cell_center(38,33))
		steps = [{"kind":"home_production","wood":25,"protected":5,"success":true}]
	if scenario_id == WORKBENCH_CRAFTING:
		var crafting_state: Dictionary = Simulation.create_new_state()
		(crafting_state["inventory"] as Dictionary)["core:wood"] = 5
		(crafting_state["structures"] as Array).append({
			"building_id": "core:workbench",
			"cell": [22, 29],
			"stage_id": "core:complete",
		})
		simulation = Simulation.new(crafting_state)
	if scenario_id == SURFACE_BOULDERS:
		var boulders: Array[Dictionary] = simulation.get_surface_boulders()
		if boulders.is_empty():
			return _failed_build(scenario_id, simulation, steps)
		var first_boulder: Dictionary = boulders[0]
		var boulder_position: Vector2 = first_boulder.get(
			"position",
			Vector2.ZERO
		) as Vector2
		simulation.set_player_position(
			boulder_position + Vector2(56.0, 0.0)
		)
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
	simulation: Simulation,
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

	# This isolated wall-memory scenario explicitly equips its worker.
	# Ordinary residents must borrow a player-supplied tool from a real warehouse.
	if not simulation.actor_tool_supports("core:first_neighbor", "build"):
		var worker: Dictionary = simulation.state.npcs["core:first_neighbor"]
		simulation.NpcPracticalWork.Supply.drop_remaining(simulation, worker)
		worker.carried_instance_id = simulation._create_item_instances("core:mallet", 1, "npc", "core:first_neighbor")[0]
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

	if not _advance_to(simulation, 7 * 60 + 35, steps):
		return false
	if simulation.get_npc_memories("core:first_neighbor").size() != 1:
		return false
	simulation.set_player_position(
		simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	)
	return true


static func _prepare_evening(
	simulation: Simulation,
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
	]
	for target_id: String in targets:
		if not _interact(simulation, target_id, steps):
			return false
	# Evening/NPC scenarios are explicit fixtures. The ordinary starter route
	# separately proves workbench construction, board crafting, and physical pickup.
	var roof_stock := simulation.try_pickup_item(
		"core:plank",
		int(simulation.content.get_cost("repair_stage_1").get("core:plank", 0))
	)
	steps.append({
		"kind": "fixture_roof_stock",
		"success": bool(roof_stock.get("success", false)),
	})
	if not bool(roof_stock.get("success", false)):
		return false
	var preparations: Array[String] = [
		"core:repair_room",
		"core:repair_room",
		"core:repair_room",
		"core:campfire_site",
		"core:campfire_site",
		"core:campfire_site",
		"core:bed_site",
	]
	for target_id: String in preparations:
		if not _interact(simulation, target_id, steps):
			return false
	return _advance_to(simulation, PREPARED_MINUTE, steps)


static func _interact(
	simulation: Simulation,
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
	var scenario_tool_instance_id := ""
	var required_tool_item_id := simulation.get_resource_required_tool_item_id(
		target_id
	)
	if not required_tool_item_id.is_empty():
		var scenario_tool_ids: Array[String] = simulation._create_item_instances(
			required_tool_item_id,
			1,
			"inventory"
		)
		if scenario_tool_ids.is_empty():
			return false
		scenario_tool_instance_id = scenario_tool_ids[0]
		if not bool(simulation.assign_hotbar_slot(4, scenario_tool_instance_id).get("success", false)):
			return false
		simulation.select_hotbar_slot(4)
	if required_work > 0:
		for _minute: int in range(required_work):
			result = simulation.execute_resource_work(
				simulation.PLAYER_ACTOR_ID,
				target_id
			)
			if not bool(result.get("success", false)):
				break
	if not scenario_tool_instance_id.is_empty():
		simulation._clear_hotbar_instance(scenario_tool_instance_id)
		simulation._remove_item_instance(scenario_tool_instance_id)
		if bool(result.get("success", false)):
			var created_drop_ids: Array = (
				result.get("created_drop_ids", []) as Array
			)
			for drop_id_variant: Variant in created_drop_ids:
				result = simulation.try_pickup_world_drop(
					String(drop_id_variant)
				)
				if not bool(result.get("success", false)):
					break
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
	simulation: Simulation,
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
	simulation: Simulation,
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
