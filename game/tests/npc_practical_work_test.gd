extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func fixture():
	var state := preload("res://tests/fixtures/stocked_tool_state.gd").prepare(World.create_new_game_state())
	state.day = 2
	state.minute_of_day = 9 * 60
	state.elapsed_game_minutes = 1980
	state.flags.first_night_complete = true
	state.flags.repair_stage = 2
	state.npcs["core:first_neighbor"].known = true
	state.npcs["core:first_neighbor"].needs.hunger = 100.0
	return World.new(state)

func _run() -> void:
	var sim = fixture()
	check(sim.has_method("set_npc_work_enabled"), "NPC practical work API must exist")
	if not sim.has_method("set_npc_work_enabled"):
		quit(1)
		return
	_test_water()
	_test_gather()
	_test_build()
	_test_needs_and_reload()
	_test_cancellation_and_recovery()
	_test_tools_and_material_limits()
	_test_distant_storage()
	_test_blocked_water()
	_test_work_phase_reloads()
	_test_stock_targets()
	_test_old_resource_position()
	if failures == 0:
		print("PASS: NPC practical watering, physical resource work, hauling, blueprint construction, needs and persistence")
	quit(0 if failures == 0 else 1)

func _test_water() -> void:
	var sim = fixture()
	var cell := Vector2i(18, 29)
	sim.state.farming.beds.append({"cell": [18,29], "crop_id": "carrot", "growth": 0, "wet_until": 0, "last_update": 1980, "harvests": 0})
	sim.advance_minutes(20)
	check(int(sim.get_farm_bed(cell).wet_until) == 0, "Residents do not work before permission is enabled")
	check(sim.set_npc_work_enabled("core:first_neighbor", "water", true).success, "Watering can be enabled separately")
	var energy_before: float = sim.get_player_energy()
	sim.advance_minutes(160)
	check(int(sim.get_farm_bed(cell).wet_until) > sim.get_elapsed_game_minutes(), "Resident collects water and waters a real planted bed")
	check(sim.get_player_energy() == energy_before, "NPC work never spends player energy")
	var bucket: Dictionary = sim.get_item_instance("core:item_instance_000001")
	check(String(bucket.location.kind) == "storage" and int(bucket.state.charges) == 1, "The same physical bucket returns with one remaining charge")
	var dry = fixture()
	dry.state.farming.beds = sim.state.farming.beds.duplicate(true)
	dry.state.farming.beds[0].wet_until = 0
	for record: Dictionary in dry.state.storage_items.duplicate():
		if String(record.item_id) == "core:bucket":
			dry.state.storage_items.erase(record)
			dry._set_instance_location(String(record.instance_id), "inventory")
	dry.set_npc_work_enabled("core:first_neighbor", "water", true)
	dry.advance_minutes(60)
	check(int(dry.state.farming.beds[0].wet_until) == 0, "A player-owned bucket cannot be borrowed remotely")

func _test_gather() -> void:
	var sim = fixture()
	sim.set_npc_work_enabled("core:first_neighbor", "gather", true)
	var before: Array = sim.state.tree_nodes.duplicate(true)
	sim.advance_minutes(240)
	var stored := 0
	for record: Dictionary in sim.get_storage_items():
		if ["core:wood", "core:stone"].has(String(record.item_id)):
			stored += int(record.amount)
	check(stored > 0, "Resident obtains real resource output and delivers it to warehouse")
	check(sim.state.tree_nodes.duplicate(true) != before or not sim.state.collected.is_empty(), "Resource gathering changes actual world resources")
	check(sim.get_player_energy() == 100, "NPC gathering leaves player energy alone")
	var seen: Dictionary = {}
	for instance: Dictionary in sim.state.item_instances:
		check(not seen.has(String(instance.instance_id)), "Tool instances remain unique")
		seen[String(instance.instance_id)] = true

func _test_build() -> void:
	var sim = fixture()
	var target := Vector2i(17, 29)
	var definition: Dictionary = sim.building_catalog.get_definition("core:wood_wall")
	sim.state.blueprints.append({"building_id": "core:wood_wall", "cell": [17,29],
		"stage_id": "core:blueprint", "required_materials": definition.get("material_cost", {}),
		"delivered_materials": {}, "work_progress_minutes": 0, "required_work_minutes": 12})
	# Normalize the blueprint using the production schema before testing work.
	sim = World.new(sim.export_state())
	var blueprint: Dictionary = sim._find_blueprint([17,29])
	check(not blueprint.is_empty(), "Construction fixture uses a real normalized blueprint")
	for item_id: String in blueprint.get("required_materials", {}):
		sim.state.inventory[item_id] = int(blueprint.required_materials[item_id])
		sim.set_player_position(Content.cell_center(23, 24))
		while int(sim.get_inventory().get(item_id, 0)) > 0:
			var stored: Dictionary = sim.transfer_inventory_stack_to_storage(Vector2i(23,23), item_id, 0)
			check(stored.success, "Actual building materials enter storage")
			if not stored.success:
				break
	sim.set_npc_work_enabled("core:first_neighbor", "build", true)
	sim.advance_minutes(120)
	check(sim._find_blueprint([17,29]).is_empty() and not sim._find_structure([target.x, target.y]).is_empty(), "Resident hauls warehouse materials and completes an existing blueprint")
	check(sim.get_player_energy() == 100, "NPC construction spends its own energy")

func _test_needs_and_reload() -> void:
	var sim = fixture()
	sim.set_npc_work_enabled("core:first_neighbor", "gather", true)
	sim.advance_minutes(6)
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(restored.get_npc_work_status("core:first_neighbor") == sim.get_npc_work_status("core:first_neighbor"), "Work phase and permission survive a mid-task reload")
	sim.advance_minutes(140)
	restored.advance_minutes(140)
	check(JSON.stringify(restored.export_state()) == JSON.stringify(sim.export_state()), "Resumed work keeps deterministic choices, real tools and cargo")
	var tired = fixture()
	tired.state.npcs["core:first_neighbor"].needs.energy = 0.0
	tired.set_npc_work_enabled("core:first_neighbor", "gather", true)
	tired.advance_minutes(5)
	check(tired.get_npc_work_status("core:first_neighbor").job.is_empty(), "Exhausted resident chooses recovery instead of a new task")

func _test_cancellation_and_recovery() -> void:
	var sim = fixture()
	sim.set_npc_work_enabled("core:first_neighbor", "gather", true)
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	for minute: int in range(80):
		sim.advance_minutes(1)
		if not String(npc.carried_instance_id).is_empty():
			break
	var tool_id := String(npc.carried_instance_id)
	check(not tool_id.is_empty(), "Cancellation fixture borrowed a physical tool")
	npc.position = [Content.cell_center(16, 30).x, Content.cell_center(16, 30).y]
	npc.needs.hunger = 50.0
	npc.personal_inventory = {}
	npc.work_cargo = {"core:wood": 2}
	sim.set_npc_work_enabled("core:first_neighbor", "gather", false)
	sim.advance_minutes(1)
	check(String(npc.carried_instance_id) == tool_id and int(npc.work_cargo.get("core:wood",0)) == 2, "Hungry cancellation retains physical tool and paid cargo")
	check(String(sim.get_item_instance(tool_id).location.kind) == "npc", "Interrupted tool is still owned by the resident")
	sim = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(String(sim.state.npcs["core:first_neighbor"].carried_instance_id) == tool_id, "Suspended tool survives disk reload")
	sim.advance_minutes(160)
	check(String(sim.get_item_instance(tool_id).location.kind) == "storage", "After eating the resident returns the exact borrowed tool")
	var stored_wood := 0
	for record: Dictionary in sim.state.storage_items:
		if String(record.item_id) == "core:wood": stored_wood += int(record.amount)
	check(stored_wood == 2, "Interrupted cargo is deposited without loss")
	for drop: Dictionary in sim.state.world_drops:
		check(String(drop.get("instance_id","")) != tool_id, "Normal return does not discard the tool on ground")

func _test_tools_and_material_limits() -> void:
	var sim = fixture()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	var target: Dictionary = sim.get_surface_trees()[0]
	npc.position = [target.position.x, target.position.y + 32]
	var result: Dictionary = sim.execute_resource_work(String(npc.id), String(target.id))
	check(not result.success, "NPC cannot use the player's selected tool or mere ownership")
	var pantry_position := Content.cell_center(23,24)
	npc.position = [pantry_position.x, pantry_position.y]
	var source: Dictionary = sim.NpcPracticalWork.Supply.find_stock(sim, npc, "core:axe")
	var cell: Array = source.record.cell
	npc.position = [Content.cell_center(int(cell[0]), int(cell[1]) + 1).x, Content.cell_center(int(cell[0]), int(cell[1]) + 1).y]
	check(sim.NpcPracticalWork.Supply.borrow(sim, npc, source), "Tool borrowing removes actual warehouse record")
	check(not sim.NpcPracticalWork.Supply.borrow(sim, npc, source), "The same tool cannot be borrowed twice")
	sim.set_npc_active(String(npc.id),false)
	check(not sim.execute_resource_work(String(npc.id), String(target.id)).success, "Inactive residents cannot perform physical resource work")
	var orphan := World.new(sim.export_state())
	check(String(orphan.get_item_instance(String(npc.carried_instance_id)).location.kind) == "inventory", "Inactive owner recovery preserves the original tool")
	var empty = fixture()
	empty.state.blueprints.append({"building_id": "core:wood_wall", "cell": [17,29], "stage_id": "core:blueprint", "required_materials": {}, "delivered_materials": {}, "work_progress_minutes": 0, "required_work_minutes": 25})
	empty = World.new(empty.export_state())
	empty.set_npc_work_enabled("core:first_neighbor", "build", true)
	empty.advance_minutes(100)
	check(int(empty._find_blueprint([17,29]).work_progress_minutes) == 0, "NPC does not invent absent building materials")
	var corrupt: Dictionary = fixture().export_state()
	corrupt.npcs["core:first_neighbor"].carried_instance_id = "core:item_instance_000001"
	var checked = World.new(corrupt)
	check(String(checked.get_item_instance("core:item_instance_000001").location.kind) == "storage", "Bad carried reference cannot steal a warehouse-owned instance")

func _test_distant_storage() -> void:
	var sim = fixture()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	var source: Dictionary = sim.NpcPracticalWork.Supply.find_stock(sim, npc, "core:axe")
	var cell: Array = source.record.cell
	var position := Content.cell_center(int(cell[0]), int(cell[1]) + 1)
	npc.position = [position.x, position.y]
	check(sim.NpcPracticalWork.Supply.borrow(sim, npc, source), "Distant warehouse fixture borrows tool")
	var held := String(npc.carried_instance_id)
	# Two valid warehouse cells: the first full, the distant second free.
	sim.state.storage_zones = [{"id": "core:storage_zone_0001", "cells": [[22,22], [16,30]]}]
	sim.state.storage_items = []
	var grid: Vector2i = sim.get_storage_grid_size(Vector2i(22,22))
	for y: int in range(grid.y):
		for x: int in range(grid.x):
			var index := y * grid.x + x
			sim.state.storage_items.append({"cell": [22,22], "item_id": "core:food", "amount": 5, "origin": [x,y], "rotation": 0, "stack_index": index, "placement_id": "core:food:%d" % index})
	npc.initiative_job = {"kind": "gather", "phase": "return", "cell": [0,0], "drops": []}
	sim.advance_minutes(30)
	check(String(sim.get_item_instance(held).location.kind) == "storage", "A full nearby warehouse sends the resident to an available distant cell")
	var returned := false
	for record: Dictionary in sim.state.storage_items:
		if String(record.get("instance_id", "")) == held:
			returned = record.cell == [16,30]
	check(returned, "The real borrowed tool reaches distant warehouse space")

func _test_blocked_water() -> void:
	var sim = fixture()
	var walls: Array[Vector2i] = []
	for x: int in range(14, 36):
		walls.append(Vector2i(x, 14))
		walls.append(Vector2i(x, 36))
	for y: int in range(15, 36):
		walls.append(Vector2i(14, y))
		walls.append(Vector2i(35, y))
	sim.npc_autonomy.set_structure_cells(walls)
	sim.state.farming.beds.append({"cell": [18,29], "crop_id": "carrot", "growth": 0, "wet_until": 0, "last_update": 1980, "harvests": 0})
	sim.set_npc_work_enabled("core:first_neighbor", "water", true)
	sim.advance_minutes(90)
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	check(int(npc.initiative_choice_index) == 0 and npc.initiative_job.is_empty(), "An enclosed garden with an empty bucket causes no impossible repeated watering jobs")
	check(String(sim.get_item_instance("core:item_instance_000001").location.kind) == "storage", "Impossible watering leaves the communal bucket available")

func _test_work_phase_reloads() -> void:
	for kind: String in ["water", "gather", "build"]:
		var sim = fixture()
		if kind == "water":
			sim.state.farming.beds.append({"cell": [18,29], "crop_id": "carrot", "growth": 0, "wet_until": 0, "last_update": 1980, "harvests": 0})
		if kind == "build":
			sim.state.blueprints.append({"building_id": "core:wood_wall", "cell": [17,29], "stage_id": "core:blueprint", "required_materials": {}, "delivered_materials": {}, "work_progress_minutes": 0, "required_work_minutes": 25})
			sim = World.new(sim.export_state())
			store_fixture(sim, "core:plank", 30)
		sim.set_npc_work_enabled("core:first_neighbor", kind, true)
		var seen: Dictionary = {}
		for minute: int in range(90):
			sim.advance_minutes(1)
			var status: Dictionary = sim.get_npc_work_status("core:first_neighbor")
			var phase := String(status.job.get("phase", "idle"))
			if seen.has(phase):
				continue
			seen[phase] = true
			var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
			check(restored.get_npc_work_status("core:first_neighbor") == status, "Reload preserves " + kind + " phase " + phase)
			restored.advance_minutes(4)
			var comparison = World.new(sim.export_state())
			comparison.advance_minutes(4)
			check(JSON.stringify(restored.export_state()) == JSON.stringify(comparison.export_state()), "Future replay matches during " + kind + " phase " + phase)

func store_fixture(sim, item_id: String, amount: int) -> void:
	sim.state.inventory[item_id] = amount
	sim.set_player_position(Content.cell_center(23,24))
	while int(sim.get_inventory().get(item_id, 0)) > 0:
		var result: Dictionary = sim.transfer_inventory_stack_to_storage(Vector2i(23,23), item_id, 0)
		check(result.success, "Fixture stores actual " + item_id)
		if not result.success:
			break

func _test_stock_targets() -> void:
	var sim = fixture()
	store_fixture(sim, "core:wood", 20)
	store_fixture(sim, "core:stone", 15)
	var before: Array = sim.state.tree_nodes.duplicate(true)
	sim.set_npc_work_enabled("core:first_neighbor", "gather", true)
	sim.advance_minutes(90)
	check(sim.state.tree_nodes == before and int(sim.state.npcs["core:first_neighbor"].initiative_choice_index) == 0, "Sufficient common stock prevents endless gathering and deforestation")

func _test_old_resource_position() -> void:
	var sim = fixture()
	var tree: Dictionary = sim.get_surface_trees()[0]
	var occupied: Vector2i = sim._world_position_to_cell(tree.position) + Vector2i.DOWN
	var position := Content.cell_center(occupied.x, occupied.y)
	var state: Dictionary = sim.export_state()
	state.version = 28
	state.npcs["core:first_neighbor"].position = [position.x, position.y]
	sim = World.new(state)
	check(not sim.npc_autonomy.is_cell_walkable(occupied), "Legacy fixture begins in a newly solid resource cell")
	sim.advance_minutes(20)
	var current: Vector2i = sim._world_position_to_cell(sim.get_npc_position("core:first_neighbor", Vector2.ZERO))
	check(current != occupied and sim.npc_autonomy.is_cell_walkable(current), "Resident escapes a newly blocked starting cell after old-save migration")
	check(not sim.npc_autonomy.is_cell_walkable(occupied), "Escaping does not make the resource cell permanently walkable")
