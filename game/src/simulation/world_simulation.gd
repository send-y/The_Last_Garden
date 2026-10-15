class_name WorldSimulation
extends "res://src/simulation/world_rules.gd"

signal event_emitted(event: Dictionary)
const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")

# Stable command/query facade. State and dependencies live only here.
const ConstructionCommandsSystem := preload("res://src/simulation/systems/construction_commands.gd")
const ConstructionProjectsSystem := preload("res://src/simulation/systems/construction_projects.gd")
const ConstructionStateSystem := preload("res://src/simulation/systems/construction_state.gd")
const CraftingSystem := preload("res://src/simulation/systems/crafting_system.gd")
const EquipmentSystem := preload("res://src/simulation/systems/equipment_system.gd")
const InventorySystem := preload("res://src/simulation/systems/inventory_system.gd")
const ItemInstancesSystem := preload("res://src/simulation/systems/item_instances.gd")
const MapMarkersSystem := preload("res://src/simulation/systems/map_markers.gd")
const OpeningScenarioSystem := preload("res://src/simulation/systems/opening_scenario.gd")
const ResourceSystem := preload("res://src/simulation/systems/resource_system.gd")
const RoomSystem := preload("res://src/simulation/systems/room_system.gd")
const SaveMigrationsSystem := preload("res://src/simulation/systems/save_migrations.gd")
const SettlementNpcsSystem := preload("res://src/simulation/systems/settlement_npcs.gd")
const StorageStateSystem := preload("res://src/simulation/systems/storage_state.gd")
const StorageSystem := preload("res://src/simulation/systems/storage_system.gd")
const StorageTransfersSystem := preload("res://src/simulation/systems/storage_transfers.gd")
const WorldCalendarSystem := preload("res://src/simulation/systems/world_calendar.gd")
const WorldDropsSystem := preload("res://src/simulation/systems/world_drops.gd")

const NpcPracticalWork := preload("res://src/npc_work/npc_practical_work.gd")
const NpcWorkQueries := preload("res://src/npc_work/npc_work_queries.gd")
var work_queries := NpcWorkQueries.new()
var work_metrics := preload("res://src/dev/npc_work_metrics.gd").new()
const NpcHomeProjects := preload("res://src/npc_work/npc_home_projects.gd")

const Housing := preload("res://src/housing/housing_system.gd")
const HomePolicy := preload("res://src/housing/home_policy.gd")
const StockReserves := preload("res://src/npc_work/stock_reserves.gd")
var housing := Housing.new()
const Furniture := preload("res://src/furniture/furniture_system.gd")
var furniture := Furniture.new()

var state: Dictionary
var content: FirstNightContent
var npc_catalog
var _npc_conversation_pending: Dictionary = {}
const CharacterNeedsScript := preload("res://src/needs/character_needs.gd")
const NpcFoodSupply := preload("res://src/needs/npc_food_supply.gd")
const HouseholdFeedback := preload("res://src/needs/household_feedback.gd")
var needs := CharacterNeedsScript.new()
var npc_autonomy
var building_catalog: BuildingCatalog
const StructureIndex := preload("res://src/construction/structure_index.gd")
var structure_index
var room_revision := 0
var housing_revision := 0
var _home_policy_revision := -1
var _home_policy_rooms: Array[Dictionary] = []
var _home_policy_room_by_character: Dictionary = {}
var _home_policy_inputs: Dictionary = {}
var crafting_catalog: CraftingCatalog
var _minute_accumulator: float = 0.0
var _berry_bush_nodes: Array[Dictionary] = []
var _food_object_ids: Dictionary = {}
var farming: FarmingSystem
var item_load_diagnostics: Array[Dictionary] = []
var builtin_pinecone_enabled := true
var _inventory_layout_content: FirstNightContent
var _inventory_layout_counts: Dictionary = {}
var _inventory_layout_snapshot: Array = []
var _inventory_layout_synced := false


func _init(initial_state: Dictionary = {}, item_content: FirstNightContent = null, recipes_path: String = CraftingCatalogScript.RECIPES_PATH) -> void:
	building_catalog = BuildingCatalogScript.new()
	content = item_content if item_content != null else Content.new()
	crafting_catalog = CraftingCatalogScript.new(content, recipes_path)
	farming = FarmingScript.new(content)
	npc_catalog = Npcs.new()
	npc_autonomy = NpcAutonomyScript.new(npc_catalog)
	if initial_state.is_empty():
		state = create_new_state(DEFAULT_SEED, ResourceNodeCatalogScript.CURRENT_LAYOUT_VERSION, content)
	else:
		var header_result: Dictionary = validate_save_header(initial_state)
		if bool(header_result.get("success", false)):
			state = initial_state.duplicate(true)
		else:
			push_error("Save state rejected: %s." % String(header_result.get("code", "unknown")))
			state = create_new_state(DEFAULT_SEED, ResourceNodeCatalogScript.CURRENT_LAYOUT_VERSION, content)
	var drop_errors := content.validate_item_references([{ "source_path": "res://src/simulation/systems/resource_system.gd", "owner_id": "pinecone_drop", "field": "item_id", "item_id": ResourceSystem.PINECONE_DROP_ITEM_ID }])
	content.report_reference_errors(drop_errors)
	builtin_pinecone_enabled = drop_errors.is_empty()
	var legacy_farm_missing := not state.has("farming")
	for roster_error: String in npc_catalog.restore(state.get("npc_profiles", {})):
		push_warning(roster_error)
	_normalize_state()
	structure_index = StructureIndex.new(state.structures,building_catalog)
	farming.normalize(self)
	if legacy_farm_missing:
		for object_id: String in state.collected:
			if bool(state.collected[object_id]) and String(_resolve_interaction_target(object_id).get("kind", "")) == "food":
				state.farming.berry_ready_at[object_id] = get_elapsed_game_minutes() + int(farming.catalog.settings.berry_regrow_minutes)
	_sync_structure_navigation()
	housing.normalize(self)
	HomePolicy.normalize(self)
	StockReserves.normalize(self)
	furniture.normalize(self)


func get_item_load_diagnostics() -> Array[Dictionary]:
	return item_load_diagnostics.duplicate(true)

func tick(real_delta: float) -> bool:
	return WorldCalendarSystem.tick(self, real_delta)


func notify_housing_changed(geometry: bool = false) -> void:
	housing_revision += 1
	if geometry: room_revision += 1


func set_npc_active(npc_id: String, active: bool) -> bool:
	var npc: Dictionary = state.npcs.get(npc_id,{})
	if npc.is_empty() or bool(npc.get("active",false)) == active: return false
	npc.active = active
	notify_housing_changed()
	return true


func add_structure(record: Dictionary) -> bool:
	if not structure_index.add(record): return false
	notify_housing_changed()
	return true


func remove_structure(record: Dictionary) -> bool:
	if not structure_index.remove(record): return false
	notify_housing_changed()
	return true


func set_structure_state(record: Dictionary, field: String, value: bool) -> bool:
	return structure_index.set_state(record,field,value)


func replace_structures(records: Array) -> void:
	structure_index.replace(records)
	notify_housing_changed()


func debug_validate_structures() -> Array[String]:
	var errors: Array[String] = structure_index.validate(state.structures)
	errors.append_array(HomePolicy.debug_validate(self))
	return errors


func create_generated_npc(seed_value: int, arrival_cell: Vector2i) -> Dictionary:
	return preload("res://src/characters/npc_creation.gd").create(self, seed_value, arrival_cell)

func arrive_npc(npc_id: String, cell: Vector2i) -> Dictionary:
	return preload("res://src/characters/npc_arrivals.gd").arrive(self, npc_id, cell)

func set_npc_resident(npc_id: String, resident: bool) -> Dictionary:
	return preload("res://src/characters/npc_arrivals.gd").set_resident(self, npc_id, resident)

func get_npc_profile_summary(npc_id: String) -> Dictionary:
	var npc: Dictionary = state.npcs.get(npc_id,{})
	return preload("res://src/characters/npc_introduction.gd").describe(npc_catalog.get_profile(npc_id),npc.get("known_facts",{}))

func get_npc_conversation_topics(npc_id: String) -> Array[Dictionary]:
	return preload("res://src/characters/npc_conversation.gd").get_topics(self,npc_id)

func choose_npc_conversation(npc_id: String, topic_id: String) -> Dictionary:
	return preload("res://src/characters/npc_conversation.gd").choose(self,npc_id,topic_id)

func acknowledge_npc_utterance(npc_id: String, utterance_id: String, page_index: int) -> Dictionary:
	return preload("res://src/characters/npc_conversation.gd").acknowledge(self,npc_id,utterance_id,page_index)

func close_npc_conversation() -> void:
	_npc_conversation_pending = {"serial":int(_npc_conversation_pending.get("serial",0))}


func advance_minutes(amount: int) -> bool:
	return WorldCalendarSystem.advance_minutes(self, amount)


func _advance_clock(amount: int) -> bool:
	return WorldCalendarSystem._advance_clock(self, amount)


func _on_world_morning(notify: bool) -> bool:
	return OpeningScenarioSystem._on_world_morning(self, notify)


func edit_world(action: String, cell: Vector2i, target_id: String = "", actor_id: String = "core:player") -> Dictionary:
	return preload("res://src/construction/world_editing.gd").execute(self,action,cell,target_id,actor_id)


func execute_interaction(target_id: String) -> Dictionary:
	return OpeningScenarioSystem.execute_interaction(self, target_id)


func execute_command(actor_id: String, target_id: String, action_id: String) -> Dictionary:
	return OpeningScenarioSystem.execute_command(self, actor_id, target_id, action_id)


func execute_resource_work(
	actor_id: String,
	target_id: String
) -> Dictionary:
	return ResourceSystem.execute_resource_work(self, actor_id, target_id)


func _maybe_drop_pinecone(
	tree_id: String,
	work_step: int,
	origin: Vector2
) -> Array[String]:
	return ResourceSystem._maybe_drop_pinecone(self, tree_id, work_step, origin)


func _create_resource_drops(
	source_id: String,
	item_id: String,
	amount: int,
	origin: Vector2
) -> Array[String]:
	return ResourceSystem._create_resource_drops(self, source_id, item_id, amount, origin)


func _get_resource_actor_position(
	actor_id: String
) -> Dictionary:
	return ResourceSystem._get_resource_actor_position(self, actor_id)


func execute_construction_command(command: Dictionary) -> Dictionary:
	return ConstructionCommandsSystem.execute_construction_command(self, command)


func execute_crafting_command(command: Dictionary) -> Dictionary:
	return CraftingSystem.execute_crafting_command(self, command)


func _start_crafting_project(
	cell_data: Array,
	station_type: String,
	recipe_id: String
) -> Dictionary:
	return CraftingSystem._start_crafting_project(self, cell_data, station_type, recipe_id)


func _advance_crafting_project(cell_data: Array, target_position: Vector2) -> Dictionary:
	return CraftingSystem._advance_crafting_project(self, cell_data, target_position)


func _get_crafting_drop_origin(station_position: Vector2) -> Vector2:
	return CraftingSystem._get_crafting_drop_origin(self, station_position)


func execute_npc_work_request(command: Dictionary) -> Dictionary:
	return SettlementNpcsSystem.execute_npc_work_request(self, command)


func _execute_cancel_blueprint(command: Dictionary) -> Dictionary:
	return ConstructionCommandsSystem._execute_cancel_blueprint(self, command)


func _execute_deliver_blueprint_materials(command: Dictionary) -> Dictionary:
	return ConstructionCommandsSystem._execute_deliver_blueprint_materials(self, command)


func _execute_work_blueprint(command: Dictionary) -> Dictionary:
	return ConstructionCommandsSystem._execute_work_blueprint(self, command)


func _sync_structure_navigation() -> void:
	ConstructionProjectsSystem._sync_structure_navigation(self)


func _get_blueprint_cells() -> Array[Vector2i]:
	return ConstructionProjectsSystem._get_blueprint_cells(self)


func _apply_autonomy_effects(effects: Array) -> bool:
	return SettlementNpcsSystem._apply_autonomy_effects(self, effects)


func _record_first_shared_wall_memory(
	npc: Dictionary,
	cell_data: Array,
	event_minute: int
) -> bool:
	return SettlementNpcsSystem._record_first_shared_wall_memory(self, npc, cell_data, event_minute)


func _is_actor_in_cell(cell_data: Array) -> bool:
	return ConstructionProjectsSystem._is_actor_in_cell(self, cell_data)


func _is_actor_in_blueprint(blueprint: Dictionary) -> bool:
	return ConstructionProjectsSystem._is_actor_in_blueprint(self, blueprint)


func _entity_occupies_cell(entity: Dictionary, cell_data: Array) -> bool:
	return ConstructionProjectsSystem._entity_occupies_cell(self, entity, cell_data)


func _building_footprints_overlap(
	first_building_id: String,
	first_cell: Array,
	second_building_id: String,
	second_cell: Array
) -> bool:
	return ConstructionProjectsSystem._building_footprints_overlap(self, first_building_id, first_cell, second_building_id, second_cell)


func _blueprint_has_all_materials(blueprint: Dictionary) -> bool:
	return ConstructionProjectsSystem._blueprint_has_all_materials(self, blueprint)


func _calculate_material_transfer(
	blueprint: Dictionary,
	source_inventory: Dictionary
) -> Dictionary:
	return ConstructionProjectsSystem._calculate_material_transfer(self, blueprint, source_inventory)


func _transfer_completes_blueprint(
	blueprint: Dictionary,
	transfer: Dictionary
) -> bool:
	return ConstructionProjectsSystem._transfer_completes_blueprint(self, blueprint, transfer)


func _apply_material_transfer(
	blueprint: Dictionary,
	source_inventory: Dictionary,
	transfer: Dictionary
) -> void:
	ConstructionProjectsSystem._apply_material_transfer(self, blueprint, source_inventory, transfer)


func _add_items_to_inventory(items: Dictionary, target_inventory: Dictionary) -> void:
	ConstructionProjectsSystem._add_items_to_inventory(self, items, target_inventory)


func _return_cancelled_materials(
	materials: Dictionary,
	blueprint_cell: Vector2i
) -> Dictionary:
	return ConstructionProjectsSystem._return_cancelled_materials(self, materials, blueprint_cell)


func _advance_blueprint_work(cell_data: Array, actor_id: String = PLAYER_ACTOR_ID) -> Dictionary:
	return ConstructionProjectsSystem._advance_blueprint_work(self, cell_data,actor_id)


func _execute_complete_blueprint(command: Dictionary) -> Dictionary:
	return ConstructionProjectsSystem._execute_complete_blueprint(self, command)


func _complete_blueprint_at_cell(cell_data: Array) -> Dictionary:
	return ConstructionProjectsSystem._complete_blueprint_at_cell(self, cell_data)


func _find_blueprint(cell_data: Array) -> Dictionary:
	return ConstructionProjectsSystem._find_blueprint(self, cell_data)


func _emit_work_request_result(
	success: bool,
	reason_id: String,
	message_key: String,
	changed: bool = false
) -> Dictionary:
	return SettlementNpcsSystem._emit_work_request_result(self, success, reason_id, message_key, changed)


func _execute_resolved_interaction(target_id: String, kind: String) -> Dictionary:
	return OpeningScenarioSystem._execute_resolved_interaction(self, target_id, kind)


func get_interaction_target_position(target_id: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	return OpeningScenarioSystem.get_interaction_target_position(self, target_id, fallback)


func export_state() -> Dictionary:
	return state.duplicate(true)


func try_pickup_item(item_id: String, amount: int) -> Dictionary:
	return WorldDropsSystem.try_pickup_item(self, item_id, amount)


func get_world_drops() -> Array:
	return WorldDropsSystem.get_world_drops(self)


func get_elapsed_game_minutes() -> int:
	return WorldDropsSystem.get_elapsed_game_minutes(self)


func drop_inventory_stack(item_id: String, stack_index: int) -> Dictionary:
	return WorldDropsSystem.drop_inventory_stack(self, item_id, stack_index)


func get_storage_zones() -> Array[Dictionary]:
	return StorageSystem.get_storage_zones(self)


func get_room_assignments() -> Array[Dictionary]:
	return RoomSystem.get_room_assignments(self)


func assign_room_type(room_type_id: String, target: Vector2i) -> Dictionary:
	return RoomSystem.assign_room_type(self, room_type_id, target)


func remove_room_at(cell: Vector2i) -> Dictionary:
	return RoomSystem.remove_room_at(self, cell)


func get_storage_items() -> Array[Dictionary]:
	return StorageSystem.get_storage_items(self)


func get_storage_contents(cell: Vector2i) -> Dictionary:
	return StorageSystem.get_storage_contents(self, cell)


func get_storage_layout(cell: Vector2i) -> Array[Dictionary]:
	return StorageSystem.get_storage_layout(self, cell)


func get_storage_grid_size(cell: Vector2i) -> Vector2i:
	return StorageSystem.get_storage_grid_size(self, cell)


func set_storage_layout(cell: Vector2i, layout: Array[Dictionary]) -> Dictionary:
	return StorageSystem.set_storage_layout(self, cell, layout)


func transfer_inventory_stack_to_storage(
	cell: Vector2i,
	item_id: String,
	stack_index: int,
	destination_origin: Vector2i = Vector2i(-1, -1),
	destination_rotation: int = -1
) -> Dictionary:
	return StorageTransfersSystem.transfer_inventory_stack_to_storage(self, cell, item_id, stack_index, destination_origin, destination_rotation)


func transfer_storage_stack_to_inventory(
	cell: Vector2i,
	placement_id: String,
	destination_origin: Vector2i = Vector2i(-1, -1),
	destination_rotation: int = -1
) -> Dictionary:
	return StorageTransfersSystem.transfer_storage_stack_to_inventory(self, cell, placement_id, destination_origin, destination_rotation)


func _pack_inventory_storage_return(
	candidate_inventory: Dictionary,
	item_id: String,
	previous_amount: int,
	destination_origin: Vector2i,
	destination_rotation: int
) -> Dictionary:
	return StorageTransfersSystem._pack_inventory_storage_return(self, candidate_inventory, item_id, previous_amount, destination_origin, destination_rotation)


func create_storage_zone(from_cell: Vector2i, to_cell: Vector2i) -> Dictionary:
	return StorageSystem.create_storage_zone(self, from_cell, to_cell)


func remove_storage_zone_at(cell: Vector2i) -> Dictionary:
	return StorageTransfersSystem.remove_storage_zone_at(self, cell)


func store_item_in_storage(cell: Vector2i, item_id: String) -> Dictionary:
	return StorageTransfersSystem.store_item_in_storage(self, cell, item_id)


func take_item_from_storage(cell: Vector2i, item_id: String) -> Dictionary:
	return StorageTransfersSystem.take_item_from_storage(self, cell, item_id)


func get_surface_boulders() -> Array[Dictionary]:
	return ResourceSystem.get_surface_boulders(self)


func get_surface_trees() -> Array[Dictionary]:
	return ResourceSystem.get_surface_trees(self)


func get_surface_berry_bushes() -> Array[Dictionary]:
	return ResourceSystem.get_surface_berry_bushes(self)


func try_pickup_world_drop(drop_id: String) -> Dictionary:
	return WorldDropsSystem.try_pickup_world_drop(self, drop_id)


func get_resource_work_progress(object_id: String) -> int:
	return ResourceSystem.get_resource_work_progress(self, object_id)


func actor_tool_supports(actor_id: String, action_id: String) -> bool:
	var tool := get_actor_tool(actor_id)
	return not String(tool.get("instance_id", "")).is_empty() and content.item_tool_supports(String(tool.get("item_id", "")), action_id)

func get_resource_required_tool_action(target_id: String) -> String:
	return ResourceSystem.get_resource_required_tool_action(self, target_id)

func get_resource_required_tool_item_id(target_id: String) -> String:
	return ResourceSystem.get_resource_required_tool_item_id(self, target_id)


func get_resource_work_required(object_id: String) -> int:
	return ResourceSystem.get_resource_work_required(self, object_id)


func get_inventory() -> Dictionary:
	return InventorySystem.get_inventory(self)


func get_inventory_placements() -> Array[Dictionary]:
	return InventorySystem.get_inventory_placements(self)


func get_inventory_layout() -> Array[Dictionary]:
	return InventorySystem.get_inventory_layout(self)


func get_hotbar_slots() -> Array[String]:
	return EquipmentSystem.get_hotbar_slots(self)


func get_active_hotbar_slot() -> int:
	return EquipmentSystem.get_active_hotbar_slot(self)


func get_active_item_instance() -> Dictionary:
	return EquipmentSystem.get_active_item_instance(self)


func get_held_item() -> Dictionary:
	return EquipmentSystem.get_held_item(self)


func select_inventory_item(item_id: String, instance_id: String = "") -> Dictionary:
	return EquipmentSystem.select_inventory_item(self, item_id, instance_id)


func assign_hotbar_slot(slot_index: int, instance_id: String) -> Dictionary:
	return EquipmentSystem.assign_hotbar_slot(self, slot_index, instance_id)


func select_hotbar_slot(slot_index: int) -> Dictionary:
	return EquipmentSystem.select_hotbar_slot(self, slot_index)


func fill_active_bucket(water_cell: Vector2i) -> Dictionary:
	return EquipmentSystem.fill_active_bucket(self, water_cell)


func _has_water_line_of_sight(target_cell: Vector2i) -> bool:
	return EquipmentSystem._has_water_line_of_sight(self, target_cell)


func _cell_blocks_water_line_of_sight(
	cell: Vector2i,
	structures: Array[Dictionary]
) -> bool:
	return EquipmentSystem._cell_blocks_water_line_of_sight(self, cell, structures)


func get_item_instance(instance_id: String) -> Dictionary:
	return ItemInstancesSystem.get_item_instance(self, instance_id)


func get_inventory_instance_id(item_id: String, stack_index: int) -> String:
	return ItemInstancesSystem.get_inventory_instance_id(self, item_id, stack_index)


func get_blueprints() -> Array:
	return ConstructionProjectsSystem.get_blueprints(self)


func get_structures() -> Array:
	return ConstructionProjectsSystem.get_structures(self)


func get_crafting_projects() -> Array:
	return CraftingSystem.get_crafting_projects(self)


func get_crafting_recipes(station_type: String) -> Array[Dictionary]:
	return CraftingSystem.get_crafting_recipes(self, station_type)

func is_recipe_unlocked(recipe_id: String) -> bool:
	return preload("res://src/crafting/recipe_learning.gd").unlocked(self, crafting_catalog.get_definition(recipe_id))


func is_navigation_cell_walkable(cell: Vector2i) -> bool:
	return ConstructionProjectsSystem.is_navigation_cell_walkable(self, cell)


func get_flags() -> Dictionary:
	return _flags_mutable().duplicate(true)


func get_npcs() -> Dictionary:
	return SettlementNpcsSystem.get_npcs(self)


func get_item_count(item_id: String) -> int:
	return InventorySystem.get_item_count(self, item_id)


func get_player_energy() -> float:
	return WorldCalendarSystem.get_player_energy(self)


func get_player_needs() -> Dictionary:
	var physical := CharacterNeedsScript.normalize(state.get("player_needs", {}))
	physical.energy = get_player_energy()
	return physical


func get_npc_psychology(npc_id: String) -> Dictionary:
	var npc: Dictionary = state.npcs.get(npc_id, {})
	if npc.is_empty() or not npc.has("psychology"):
		return {}
	var result: Dictionary = npc.psychology.duplicate(true)
	var home: Dictionary = housing.home(self, npc_id)
	result["reasons"] = needs.reasons(npc, bool(home.covered), get_elapsed_game_minutes(), home, furniture.comfort(self,npc_id))
	return result

func get_npc_household_status(npc_id: String) -> Dictionary:
	return HouseholdFeedback.describe(self,npc_id)


func rest_player(in_bed: bool = false) -> Dictionary:
	if in_bed:
		var home: Dictionary = housing.home(self, "core:player")
		if not bool(home.valid):
			return _emit_result(false, String(home.reason_key))
		var cell: Array = home.cell
		if not housing.contains_player(self, home) or get_player_position().distance_to(Content.cell_center(int(cell[0]), int(cell[1]))) > Content.INTERACTION_RANGE:
			return _emit_result(false, "interaction.failure.too_far")
	var activity := "resting_in_bed" if in_bed else ("resting_on_chair" if not furniture.comfort(self,"core:player").is_empty() else "resting")
	WorldCalendarSystem._advance_clock(self, 15, true, activity)
	return _emit_result(true, "needs.rested", true, true)


func get_player_energy_max() -> float:
	return WorldCalendarSystem.get_player_energy_max(self)


func get_player_work_speed_multiplier() -> float:
	return WorldCalendarSystem.get_player_work_speed_multiplier(self)


func execute_farming_command(command: Dictionary) -> Dictionary:
	return farming.execute(self, command)


func get_farm_beds() -> Array:
	return (state.farming.beds as Array).duplicate(true)


func get_farm_bed(cell: Vector2i) -> Dictionary:
	return farming.bed_at(self, cell).duplicate(true)


func is_roof_covered() -> bool:
	return WorldCalendarSystem.is_roof_covered(self)


func get_sleep_energy_preview(place_id: String = "") -> float:
	return WorldCalendarSystem.get_sleep_energy_preview(self, place_id)


func _spend_player_work_energy(multiplier: float = 1.0) -> void:
	WorldCalendarSystem._spend_player_work_energy(self, multiplier)


func get_day() -> int:
	return WorldCalendarSystem.get_day(self)


func get_minute_of_day() -> int:
	return WorldCalendarSystem.get_minute_of_day(self)


func get_time_text() -> String:
	return WorldCalendarSystem.get_time_text(self)


func get_player_position() -> Vector2:
	var stored: Array = state.get("player_position", [784.0, 944.0]) as Array
	if stored.size() < 2:
		return Vector2(784.0, 944.0)
	return Vector2(float(stored[0]), float(stored[1]))


func get_markers() -> Array[Dictionary]:
	return MapMarkersSystem.get_markers(self)


func create_marker(marker_name: String, color: Color) -> Dictionary:
	return MapMarkersSystem.create_marker(self, marker_name, color)


func rename_marker(marker_id: String, marker_name: String) -> Dictionary:
	return MapMarkersSystem.rename_marker(self, marker_id, marker_name)


func set_marker_enabled(marker_id: String, enabled: bool) -> Dictionary:
	return MapMarkersSystem.set_marker_enabled(self, marker_id, enabled)


func remove_marker(marker_id: String) -> Dictionary:
	return MapMarkersSystem.remove_marker(self, marker_id)


func eat_food(item_id: String = FirstNightContent.FOOD_ID) -> Dictionary:
	return InventorySystem.eat_food(self, item_id)


func set_inventory_layout(layout: Array[Dictionary]) -> Dictionary:
	return InventorySystem.set_inventory_layout(self, layout)


func set_player_position(value: Vector2) -> void:
	var use: Dictionary = state.get("player_furniture_use",{})
	if not use.is_empty() and value.distance_to(Content.cell_center(int(use.chair_cell[0]),int(use.chair_cell[1]))) > 1.0:
		state.player_furniture_use = {}
	state["player_position"] = [value.x, value.y]


func is_collected(object_id: String) -> bool:
	return OpeningScenarioSystem.is_collected(self, object_id)


func get_object_stage(kind: String) -> int:
	return OpeningScenarioSystem.get_object_stage(self, kind)


func get_object_label_key(kind: String, fallback_key: String, object_id: String = "") -> String:
	return OpeningScenarioSystem.get_object_label_key(self, kind, fallback_key, object_id)


func should_hide_interactable(object_id: String, kind: String) -> bool:
	return OpeningScenarioSystem.should_hide_interactable(self, object_id, kind)


func is_npc_visible(npc_id: String) -> bool:
	return SettlementNpcsSystem.is_npc_visible(self, npc_id)


func get_npc_position(npc_id: String, fallback: Vector2) -> Vector2:
	return SettlementNpcsSystem.get_npc_position(self, npc_id, fallback)


func get_npc_appearance(npc_id: String) -> Dictionary:
	return SettlementNpcsSystem.get_npc_appearance(self, npc_id)


func get_npc_activity_id(npc_id: String) -> String:
	return SettlementNpcsSystem.get_npc_activity_id(self, npc_id)


func get_npc_activity_key(npc_id: String) -> String:
	return SettlementNpcsSystem.get_npc_activity_key(self, npc_id)


func get_npc_needs(npc_id: String) -> Dictionary:
	return SettlementNpcsSystem.get_npc_needs(self, npc_id)


func get_npc_personal_food(npc_id: String) -> int:
	return SettlementNpcsSystem.get_npc_personal_food(self, npc_id)


func get_npc_work_commitment(npc_id: String) -> Dictionary:
	return SettlementNpcsSystem.get_npc_work_commitment(self, npc_id)


func get_npc_memories(npc_id: String) -> Array:
	return SettlementNpcsSystem.get_npc_memories(self, npc_id)


func get_npc_relationship_to_player(npc_id: String) -> Dictionary:
	return SettlementNpcsSystem.get_npc_relationship_to_player(self, npc_id)


func get_npc_target_cell(npc_id: String) -> Vector2i:
	return SettlementNpcsSystem.get_npc_target_cell(self, npc_id)


func get_npc_facing(npc_id: String) -> Vector2:
	return SettlementNpcsSystem.get_npc_facing(self, npc_id)


func is_npc_moving(npc_id: String) -> bool:
	return SettlementNpcsSystem.is_npc_moving(self, npc_id)

func get_presentation_game_time() -> float:
	return WorldCalendarSystem.get_presentation_game_time(self)

func get_next_npc_update_game_time(npc_id: String) -> float:
	return WorldCalendarSystem.get_next_npc_update_game_time(self,npc_id)


func _resolve_interaction_target(target_id: String) -> Dictionary:
	return OpeningScenarioSystem._resolve_interaction_target(self, target_id)


func get_current_objective_key() -> String:
	return OpeningScenarioSystem.get_current_objective_key(self)


func _has_starting_workbench() -> bool:
	return OpeningScenarioSystem._has_starting_workbench(self)


func _get_starting_workbench_blueprint() -> Dictionary:
	return OpeningScenarioSystem._get_starting_workbench_blueprint(self)


func _has_saw_plank_project() -> bool:
	return OpeningScenarioSystem._has_saw_plank_project(self)


func _get_dropped_item_count(item_id: String) -> int:
	return OpeningScenarioSystem._get_dropped_item_count(self, item_id)


func _get_roof_wood_required() -> int:
	return OpeningScenarioSystem._get_roof_wood_required(self)


func get_resource_search_hint() -> Dictionary:
	return OpeningScenarioSystem.get_resource_search_hint(self)


func _inspect_house() -> Dictionary:
	return OpeningScenarioSystem._inspect_house(self)


func _find_tools() -> Dictionary:
	return OpeningScenarioSystem._find_tools(self)


func _collect_resource(object_id: String, kind: String) -> Dictionary:
	return OpeningScenarioSystem._collect_resource(self, object_id, kind)


func _advance_repair() -> Dictionary:
	return OpeningScenarioSystem._advance_repair(self)


func _advance_campfire() -> Dictionary:
	return OpeningScenarioSystem._advance_campfire(self)


func _advance_bed() -> Dictionary:
	return OpeningScenarioSystem._advance_bed(self)


func _talk_to_npc(npc_id: String) -> Dictionary:
	return SettlementNpcsSystem._talk_to_npc(self, npc_id)


func _sleep_until_morning() -> Dictionary:
	return WorldCalendarSystem._sleep_until_morning(self)


func _can_add_item(item_id: String, amount: int) -> bool:
	return InventorySystem._can_add_item(self, item_id, amount)


func _add_item(item_id: String, amount: int) -> void:
	InventorySystem._add_item(self, item_id, amount)


func _consume_items(costs: Dictionary) -> bool:
	return InventorySystem._consume_items(self, costs)


func _create_item_instances(
	item_id: String,
	amount: int,
	location_kind: String,
	location_id: String = "",
	initial_state: Dictionary = {}
) -> Array[String]:
	return ItemInstancesSystem._create_item_instances(self, item_id, amount, location_kind, location_id, initial_state)


func _set_instance_location(
	instance_id: String,
	location_kind: String,
	location_id: String = ""
) -> bool:
	return ItemInstancesSystem._set_instance_location(self, instance_id, location_kind, location_id)


func _update_instance_state(instance_id: String, item_state: Dictionary) -> bool:
	return ItemInstancesSystem._update_instance_state(self, instance_id, item_state)


func _remove_item_instance(instance_id: String) -> bool:
	return ItemInstancesSystem._remove_item_instance(self, instance_id)


func _clear_hotbar_instance(instance_id: String, keep_binding: bool = false) -> void:
	ItemInstancesSystem._clear_hotbar_instance(self, instance_id, keep_binding)


func _inventory_counts_without_instances(inventory: Dictionary) -> Dictionary:
	return ItemInstancesSystem._inventory_counts_without_instances(self, inventory)


func _get_outcome_label_keys(outcome_ids: Array[String]) -> Array[String]:
	return WorldCalendarSystem._get_outcome_label_keys(self, outcome_ids)


func _emit_result(
	success: bool,
	message_key: String,
	changed: bool = false,
	auto_save: bool = false,
	message_args: Dictionary = {},
	inventory_changed: bool = true
) -> Dictionary:
	var span := Diagnostic.begin("simulation.command_result") if Diagnostic.enabled else 0
	if changed:
		if not (state.get("selected_inventory_item", {}) as Dictionary).is_empty() and get_held_item().is_empty():
			state["selected_inventory_item"] = {}
		# Pure household notices change goals, not player item locations/counts.
		if inventory_changed: _sync_inventory_layout()
	var event: Dictionary = {
		"type": "command_result",
		"success": success,
		"message_key": message_key,
		"message_args": message_args.duplicate(true),
		"changed": changed,
		"auto_save": auto_save,
	}
	event_emitted.emit(event)
	Diagnostic.end(span)
	return event


func _sync_inventory_layout() -> void:
	var inventory := get_inventory()
	var layout: Array = state.get("inventory_layout", [])
	# NPC goals and home events do not change the backpack. Compare small,
	# isolated inputs before invoking its full placement algorithm again.
	if _inventory_layout_synced and _inventory_layout_content == content and _inventory_layout_counts == inventory and _inventory_layout_snapshot == layout:
		return
	var span := Diagnostic.begin("inventory.layout_sync") if Diagnostic.enabled else 0
	state.inventory_layout = InventoryPackerScript.pack_with_layout(inventory,content,layout,4,4).get("layout", [])
	_inventory_layout_content = content
	_inventory_layout_counts = inventory.duplicate(true)
	_inventory_layout_snapshot = state.inventory_layout.duplicate(true)
	_inventory_layout_synced = true
	Diagnostic.end(span)


func _normalize_state() -> void:
	SaveMigrationsSystem._normalize_state(self)


func _normalize_item_instances(value: Variant, legacy_inventory: Dictionary) -> Array[Dictionary]:
	return ItemInstancesSystem._normalize_item_instances(self, value, legacy_inventory)


func _new_item_instance_id(known_ids: Dictionary = {}) -> String:
	return ItemInstancesSystem._new_item_instance_id(self, known_ids)


func _normalize_next_item_instance_serial(value: Variant, instances: Array) -> int:
	return ItemInstancesSystem._normalize_next_item_instance_serial(self, value, instances)


func _ensure_item_instance_for_owner(
	item_id: String,
	instance_id: String,
	location_kind: String,
	location_id: String
) -> String:
	return ItemInstancesSystem._ensure_item_instance_for_owner(self, item_id, instance_id, location_kind, location_id)


func _reconcile_item_instance_locations() -> void:
	ItemInstancesSystem._reconcile_item_instance_locations(self)


func _normalize_hotbar_state() -> void:
	ItemInstancesSystem._normalize_hotbar_state(self)


func _normalize_markers(value: Variant) -> Array[Dictionary]:
	return MapMarkersSystem._normalize_markers(self, value)


func _normalize_storage_zones(value: Variant) -> Array[Dictionary]:
	return StorageStateSystem._normalize_storage_zones(self, value)


func _normalize_room_assignments(value: Variant) -> Array[Dictionary]:
	return RoomSystem._normalize_room_assignments(self, value)


func _normalize_next_room_serial(value: Variant, rooms: Array) -> int:
	return RoomSystem._normalize_next_room_serial(self, value, rooms)


func _room_validation_failure(validation: Dictionary) -> Dictionary:
	return RoomSystem._room_validation_failure(self, validation)


func _room_cells_set(values: Variant) -> Dictionary:
	return RoomSystem._room_cells_set(self, values)


func _building_allowed_in_assigned_rooms(building_id: String, raw_origin: Array) -> bool:
	return RoomSystem._building_allowed_in_assigned_rooms(self, building_id, raw_origin)


func _room_storage_cell_has_forbidden_structure(cell: Vector2i) -> bool:
	return RoomSystem._room_storage_cell_has_forbidden_structure(self, cell)


func _normalize_storage_items(value: Variant, zones: Array) -> Array[Dictionary]:
	return StorageStateSystem._normalize_storage_items(self, value, zones)


func _recover_orphaned_storage_items(
	raw_value: Variant,
	normalized_items: Array
) -> void:
	StorageStateSystem._recover_orphaned_storage_items(self, raw_value, normalized_items)


func _normalize_next_storage_zone_serial(value: Variant, zones: Array) -> int:
	return StorageStateSystem._normalize_next_storage_zone_serial(self, value, zones)


func _validate_storage_access(cell: Vector2i) -> Dictionary:
	return StorageSystem._validate_storage_access(self, cell)


func _storage_zone_index_at_cell(cell: Vector2i) -> int:
	return StorageSystem._storage_zone_index_at_cell(self, cell)


func _storage_zone_cell_keys(zone: Dictionary) -> Dictionary:
	return StorageSystem._storage_zone_cell_keys(self, zone)


func _storage_placement_key(placement: Dictionary) -> String:
	return StorageSystem._storage_placement_key(self, placement)


func _storage_item_at_key(items: Array, cell_key: String) -> Dictionary:
	return StorageSystem._storage_item_at_key(self, items, cell_key)


func _storage_cell_key(value: Variant) -> String:
	return StorageSystem._storage_cell_key(self, value)


func _storage_cell_array(cell_key: String) -> Array:
	return StorageSystem._storage_cell_array(self, cell_key)


func _storage_cell_has_blocking_structure(cell: Vector2i) -> bool:
	return StorageSystem._storage_cell_has_blocking_structure(self, cell)


func _world_cell_blocks_storage(cell: Vector2i, for_farming: bool = false) -> bool:
	return StorageSystem._world_cell_blocks_storage(self, cell, for_farming)


func _storage_cell_has_floor(cell: Vector2i) -> bool:
	return StorageSystem._storage_cell_has_floor(self, cell)


func _normalize_next_marker_serial(value: Variant, markers: Array) -> int:
	return MapMarkersSystem._normalize_next_marker_serial(self, value, markers)


func _normalize_resource_work(
	value: Variant
) -> Dictionary:
	return ResourceSystem._normalize_resource_work(self, value)


func _normalize_resource_work_tool_instances(
	value: Variant,
	resource_work: Dictionary
) -> Dictionary:
	return ResourceSystem._normalize_resource_work_tool_instances(self, value, resource_work)


func _normalize_resource_nodes(
	value: Variant,
	world_seed: int
) -> Array[Dictionary]:
	return ResourceSystem._normalize_resource_nodes(self, value, world_seed)


func _normalize_tree_nodes(
	value: Variant,
	world_seed: int,
	boulders: Array
) -> Array[Dictionary]:
	return ResourceSystem._normalize_tree_nodes(self, value, world_seed, boulders)


func _get_tree_node(node_id: String) -> Dictionary:
	return ResourceSystem._get_tree_node(self, node_id)


func _update_tree_stage(node_id: String, stage_id: String) -> void:
	ResourceSystem._update_tree_stage(self, node_id, stage_id)


func _normalize_world_drops(value: Variant) -> Array[Dictionary]:
	return WorldDropsSystem._normalize_world_drops(self, value)


func _expire_world_drops() -> bool:
	return WorldDropsSystem._expire_world_drops(self)


func _normalize_blueprints(
	value: Variant,
	allow_multiple_layers: bool = false,
	migrate_legacy_wall_material: bool = false
) -> Array[Dictionary]:
	return ConstructionStateSystem._normalize_blueprints(self, value, allow_multiple_layers, migrate_legacy_wall_material)


func _normalize_structures(value: Variant) -> Array[Dictionary]:
	return ConstructionStateSystem._normalize_structures(self, value)


func _normalize_crafting_projects(
	value: Variant,
	structures: Array[Dictionary]
) -> Array[Dictionary]:
	return CraftingSystem._normalize_crafting_projects(self, value, structures)


func _find_structure(cell_data: Array) -> Dictionary:
	return ConstructionProjectsSystem._find_structure(self, cell_data)


func _find_crafting_project(cell_data: Array) -> Dictionary:
	return CraftingSystem._find_crafting_project(self, cell_data)


func _without_structure_cells(
	blueprints: Array[Dictionary],
	structures: Array[Dictionary]
) -> Array[Dictionary]:
	return ConstructionStateSystem._without_structure_cells(self, blueprints, structures)


func _inventory_mutable() -> Dictionary:
	return state["inventory"] as Dictionary


func _flags_mutable() -> Dictionary:
	return state["flags"] as Dictionary


func _npcs_mutable() -> Dictionary:
	return state["npcs"] as Dictionary


func set_npc_work_enabled(npc_id: String, kind: String, enabled: bool) -> Dictionary:
	return NpcPracticalWork.set_enabled(self, npc_id, kind, enabled)


func get_npc_work_status(npc_id: String) -> Dictionary:
	return NpcPracticalWork.status(self, npc_id)


func get_npc_personal_goal(npc_id: String) -> Dictionary:
	return NpcHomeProjects.status(self,npc_id)


func defer_npc_personal_goal(npc_id: String, resume: bool = false) -> Dictionary:
	return NpcHomeProjects.defer(self,npc_id,resume)


func get_actor_tool(actor_id: String) -> Dictionary:
	if actor_id == PLAYER_ACTOR_ID:
		return get_active_item_instance()
	var npc: Dictionary = state.npcs.get(actor_id, {})
	if npc.is_empty() or not bool(npc.get("active", false)):
		return {}
	return NpcPracticalWork.Supply.tool(self, npc)


func assign_sleep_place(character_id: String, place_id: String) -> Dictionary:
	return housing.assign(self, character_id, place_id)


func get_housing_rooms() -> Array[Dictionary]:
	return HomePolicy.rooms(self)


func get_home_policy(character_id: String) -> Dictionary:
	return HomePolicy.for_character(self, character_id)


func set_home_mode(room_id: String, mode: String) -> Dictionary:
	return HomePolicy.set_mode(self, room_id, mode)


func get_stock_reserve_report() -> Array[Dictionary]:
	return StockReserves.report(self)


func set_stock_reserve(item_id: String, amount: Variant) -> Dictionary:
	return StockReserves.set_reserve(self, item_id, amount)


func get_character_home(character_id: String) -> Dictionary:
	return housing.home(self, character_id)


func get_sleep_places() -> Array[Dictionary]:
	return housing.places(self)


func sleep_at_place(place_id: String) -> Dictionary:
	return housing.sleep_at(self, place_id)

func execute_furniture_command(cell: Vector2i, action: String, item_id: String = "") -> Dictionary:
	return furniture.execute(self,cell,action,item_id)

func get_furniture_options(cell: Vector2i) -> Dictionary:
	return furniture.options(self,cell)

func is_cell_lit(cell: Vector2i) -> bool:
	return furniture.lighting.is_lit(self,cell)

func leave_player_seat() -> bool:
	return furniture.leave_player(self)

func prepare_player_work() -> bool:
	if state.get("player_furniture_use",{}).is_empty():
		return true
	if not furniture.leave_player(self):
		return false
	event_emitted.emit({"type":"state_changed"})
	return true
