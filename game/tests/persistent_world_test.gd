extends SceneTree

const Sim := preload("res://src/simulation/first_night_simulation.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_midnight_and_reload()
	_test_multi_day_determinism()
	_test_sleep_nearest_morning()
	_test_intro_is_optional()
	_test_elapsed_deadlines()
	_test_crop_across_days()
	_test_compatibility_facade()
	if _failures == 0:
		print("PASS: persistent world midnight, multiple days, sleep, optional introduction, deadlines, reload and compatibility")
	quit(0 if _failures == 0 else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("FAIL: persistent world: " + message)


func _fixture(day: int, minute: int) -> Dictionary:
	var state := Sim.create_new_game_state()
	state.day = day
	state.minute_of_day = minute
	state.elapsed_game_minutes = (day - 1) * 1440 + minute
	return state


func _test_midnight_and_reload() -> void:
	var sim := World.new(_fixture(1, 23 * 60 + 49))
	var before := sim.export_state()
	_check(sim.advance_minutes(20), "clock must keep advancing after the old cutoff")
	_check(sim.get_day() == 2 and sim.get_minute_of_day() == 9, "23:49 + 20 minutes must become day 2, 00:09")
	_check(sim.get_elapsed_game_minutes() == 1449, "elapsed time must remain continuous")
	for key: String in ["structures", "tree_nodes", "resource_nodes", "storage_items", "item_instances", "storage_zones"]:
		_check(sim.state[key] == before[key], "midnight must preserve " + key)
	var restored := World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	_check(restored.export_state() == sim.export_state(), "JSON reload must preserve world state after midnight")
	_check(restored.advance_minutes(1431) and restored.get_day() == 3 and restored.get_minute_of_day() == 0, "a full-day boundary must still report time changed")
	var late := World.new(_fixture(3, 23 * 60 + 59))
	_check(late.get_minute_of_day() == 1439, "23:59 must survive normalization")
	late.tick(2.0)
	_check(late.get_day() == 4 and late.get_minute_of_day() == 0, "real-time ticking must cross midnight")


func _test_multi_day_determinism() -> void:
	var batch := World.new(_fixture(1, 11 * 60))
	var steps := World.new(batch.export_state())
	_check(batch.advance_minutes(3 * 1440), "multi-day advance must succeed")
	for minute: int in range(3 * 1440):
		steps.advance_minutes(1)
	_check(batch.get_day() == 4 and batch.get_minute_of_day() == 660, "three days must preserve the time of day")
	_check(batch.export_state() == steps.export_state(), "one batch and minute steps must produce the same authoritative state")
	_check(not batch.advance_minutes(0) and not batch.advance_minutes(-1), "invalid durations must not change time")


func _test_sleep_nearest_morning() -> void:
	for minute: int in [30, 20 * 60]:
		var state := _fixture(2, minute)
		state.flags.repair_stage = 2
		state.flags.bed_ready = true
		state.player_energy = 10.0
		var sim := World.new(state)
		sim.set_player_position(sim.get_interaction_target_position("core:bed_site"))
		var elapsed := sim.get_elapsed_game_minutes()
		var result := sim.execute_interaction("core:bed_site")
		_check(bool(result.get("success", false)), "bed must allow sleep in the evening and after midnight")
		_check(sim.get_day() == (2 if minute < 420 else 3) and sim.get_minute_of_day() == 420, "sleep must select the nearest future 07:00")
		var duration := 420 - minute if minute < 420 else 1440 - minute + 420
		_check(sim.get_elapsed_game_minutes() == elapsed + duration, "sleep must advance exact elapsed minutes")
		_check(sim.get_player_energy() == sim.PLAYER_ENERGY_MAX, "covered roof must still restore full energy")
	var draft := World.new(_fixture(1, 20 * 60))
	draft._sleep_until_morning()
	_check(draft.get_player_energy() == draft.PLAYER_POOR_SLEEP_ENERGY, "uncovered roof must retain soft poor-sleep penalty")


func _test_intro_is_optional() -> void:
	var sim := World.new(_fixture(1, 23 * 60 + 49))
	sim.advance_minutes(431)
	_check(sim.get_day() == 2 and sim.get_minute_of_day() == 420, "first morning must be reachable without sleeping")
	_check(sim.is_npc_visible("core:first_neighbor"), "neighbor must arrive without the mandatory first-night interaction")
	_check(not bool(sim.get_flags().comfortable_sleep_completed), "arrival must not grant unearned comfortable-sleep progression")
	_check(sim.get_player_energy() == sim.PLAYER_ENERGY_MAX, "staying awake must not grant or remove energy outside existing work rules")
	var npc_before := sim.get_npcs()
	sim.advance_minutes(5)
	_check(sim.get_npcs() != npc_before, "NPC must keep advancing after arrival")
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(event: Dictionary) -> void: events.append(event))
	sim.advance_minutes(2 * 1440)
	var dusk_count := 0
	for event: Dictionary in events:
		if String(event.get("message_key", "")) == "first_night.message.dusk":
			dusk_count += 1
	_check(dusk_count == 2, "daily dusk reminders must reset after each midnight")


func _test_elapsed_deadlines() -> void:
	var sim := World.new(_fixture(1, 23 * 60 + 49))
	var berry: Dictionary = sim.get_surface_berry_bushes()[0]
	var berry_id := String(berry.id)
	sim.set_player_position(berry.position as Vector2)
	_check(bool(sim.execute_interaction(berry_id).get("success", false)), "berry fixture must be collectible")
	sim.try_pickup_item(Content.WOOD_ID, 1)
	_check(bool(sim.drop_inventory_stack(Content.WOOD_ID, 0).get("success", false)), "drop fixture must be created")
	sim.advance_minutes(30 * 60 - 1)
	_check(sim.get_world_drops().size() == 1, "drop must live until its exact deadline across days")
	sim.advance_minutes(1)
	_check(sim.get_world_drops().is_empty(), "drop must expire at the deadline")
	_check(sim.is_collected(berry_id), "berry must still be depleted before 72 hours")
	sim.advance_minutes(72 * 60 - 30 * 60)
	_check(not sim.is_collected(berry_id), "berry must regenerate after three continuous days")


func _test_compatibility_facade() -> void:
	var old_name := Sim.new(Sim.create_new_game_state())
	var new_name := World.new(World.create_new_game_state())
	_check(old_name is World, "legacy name must instantiate the new authority")
	_check(old_name.export_state() == new_name.export_state(), "old and new facade names must create identical state")
	_check(Sim.validate_save_header(old_name.export_state()) == World.validate_save_header(new_name.export_state()), "static save API must remain compatible")
	var legacy := _fixture(1, 1430)
	legacy.version = 26
	var migrated := World.new(legacy)
	_check(migrated.state.version == World.SAVE_VERSION and migrated.get_minute_of_day() == 1430, "v26 migration must preserve the saved clock")
	_check(migrated.get_storage_items() == old_name.get_storage_items(), "v26 migration must preserve physical storage placements")
	migrated.advance_minutes(20)
	_check(migrated.get_day() == 2 and migrated.get_minute_of_day() == 10, "migrated first-night save must continue into the persistent world")


func _test_crop_across_days() -> void:
	var sim := World.new(_fixture(1, 23 * 60 + 49))
	var cell := Vector2i(-1, -1)
	for y: int in range(27, 45):
		for x: int in range(20, 45):
			var candidate := Vector2i(x, y)
			if sim.farming._soil_allowed(sim, candidate):
				cell = candidate
				break
		if cell.x >= 0:
			break
	_check(cell.x >= 0, "existing map must contain arable soil")
	if cell.x < 0:
		return
	sim.set_player_position(Content.cell_center(cell.x, cell.y))
	sim.try_pickup_item("core:hoe", 1)
	var hoe := sim.get_inventory_instance_id("core:hoe", 0)
	sim.assign_hotbar_slot(0, hoe)
	sim.select_hotbar_slot(0)
	_check(bool(_farm(sim, "till", cell).success), "physical hoe must prepare a real bed")
	sim.try_pickup_item("core:carrot_seed", 1)
	_check(bool(_farm(sim, "plant", cell, "core:carrot_seed").success), "seed must plant on the existing map")
	sim.try_pickup_item("core:bucket", 1)
	var bucket := sim.get_inventory_instance_id("core:bucket", 0)
	sim._update_instance_state(bucket, {"charges": 2})
	sim.assign_hotbar_slot(1, bucket)
	sim.select_hotbar_slot(1)
	_check(bool(_farm(sim, "water", cell).success), "charged physical bucket must water")
	var now := sim.get_elapsed_game_minutes()
	sim.advance_minutes(1440)
	_check(sim.get_elapsed_game_minutes() == now + 1440, "crop clock must advance a whole day without sleep")
	var expected := mini(1440, int(sim.farming.catalog.find("carrot").growth_minutes))
	_check(int(sim.get_farm_bed(cell).growth) == expected, "continuous watering grants exactly 24 hours of growth")
	_check(int(sim.get_farm_bed(cell).wet_until) == sim.get_elapsed_game_minutes(), "water expires at its 24-hour boundary across midnight")
	var restored := World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	_check(restored.get_farm_bed(cell) == sim.get_farm_bed(cell), "crop, growth and water deadline must survive reload")
	restored.advance_minutes(1440)
	_check(int(restored.get_farm_bed(cell).growth) == expected, "a second dry day must pause crop growth")


func _farm(sim: World, action: String, cell: Vector2i, item_id: String = "") -> Dictionary:
	return sim.execute_farming_command({"actor_id": "core:player", "action_id": action, "cell": [cell.x, cell.y], "item_id": item_id})
