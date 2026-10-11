extends SceneTree

const Sim := preload("res://src/simulation/first_night_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const Construction := preload("res://src/construction/construction_command.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_extraction_and_capacity()
	_test_berry_cooldown()
	_test_growth_water_and_harvest_modes()
	_test_sleep_and_disk_round_trip()
	_test_invalid_commands_and_state()
	if _failures == 0:
		print("PASS: farming seed transactions, 72-hour bushes, physical tools/water, three harvest modes, dry growth, sleep, and save migration")
	quit(0 if _failures == 0 else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("FAIL: farming rules: " + message)


func _command(sim: FirstNightSimulation, action: String, cell := Vector2i(-1, -1), item_id := "") -> Dictionary:
	return sim.execute_farming_command({"actor_id": "core:player", "action_id": action, "cell": [cell.x, cell.y], "item_id": item_id})


func _equip(sim: FirstNightSimulation, item_id: String, charges: int = 0) -> String:
	_check(bool(sim.try_pickup_item(item_id, 1).success), "tool fixture must fit")
	var id := sim.get_inventory_instance_id(item_id, 0)
	if item_id == "core:bucket":
		sim._update_instance_state(id, {"charges": charges})
	_check(bool(sim.assign_hotbar_slot(0, id).success), "physical tool must be assigned")
	sim.select_hotbar_slot(0)
	return id


func _soil(sim: FirstNightSimulation) -> Vector2i:
	for y: int in range(27, 45):
		for x: int in range(20, 45):
			var cell := Vector2i(x, y)
			if sim.farming._soil_allowed(sim, cell) and sim.get_farm_bed(cell).is_empty():
				return cell
	_check(false, "map must contain arable soil")
	return Vector2i(-1, -1)


func _advance_fixture(sim: FirstNightSimulation, minutes: int) -> void:
	# Exact elapsed-time boundaries are isolated here. The sleep test below
	# proves real clock integration and disk persistence without this fixture.
	sim.state.elapsed_game_minutes = sim.get_elapsed_game_minutes() + minutes
	sim.farming.advance(sim)


func _test_extraction_and_capacity() -> void:
	var sim := Sim.new()
	sim.try_pickup_item("core:food", 2)
	var before := sim.export_state()
	var clone := Sim.new(JSON.parse_string(JSON.stringify(before)))
	var a := _command(sim, "extract", Vector2i(-1, -1), "core:food")
	var b := _command(clone, "extract", Vector2i(-1, -1), "core:food")
	_check(bool(a.success) and bool(b.success), "special berries need no study table")
	_check(sim.get_inventory() == clone.get_inventory(), "save/reload must retain the next draw")
	_check(int(a.message_args.amount) >= 2 and int(a.message_args.amount) <= 4, "special berry yields 2-4 seeds")
	_check(sim.get_item_count("core:food") == 1 and int(sim.state.farming.roll_index) == 1, "one berry and one committed draw")
	var seen: Dictionary = {}
	for _index: int in range(100):
		for crop: Dictionary in sim.farming.catalog.crops:
			sim.state.inventory[String(crop.seed_id)] = 0
		sim.state.inventory["core:food"] = 1
		var result := _command(sim, "extract", Vector2i(-1, -1), "core:food")
		_check(bool(result.success), "empty bag extraction succeeds")
		var types := 0
		for crop: Dictionary in sim.farming.catalog.crops:
			var count := sim.get_item_count(String(crop.seed_id))
			if count > 0:
				types += 1
				seen[String(crop.id)] = true
				_check(count >= 2 and count <= 4, "all random batches respect 2-4")
		_check(types == 1, "one berry produces exactly one crop type")
	_check(seen.size() == 4, "seeded stream exercises the full starting pool")
	var full_state := Sim.create_new_state()
	full_state.inventory["core:stone"] = 45
	full_state.inventory["core:food"] = 2
	var full := Sim.new(full_state)
	var unchanged := full.export_state()
	_check(not bool(_command(full, "extract", Vector2i(-1, -1), "core:food").success), "capacity rejection must be atomic")
	_check(full.export_state() == unchanged, "rejection consumes neither berry nor random serial")
	full.state.inventory["core:stone"] = 42
	_check(bool(_command(full, "extract", Vector2i(-1, -1), "core:food").success), "freeing one slot allows the same pending draw")
	var product := Sim.new()
	product.try_pickup_item("core:carrot", 1)
	_check(not bool(_command(product, "extract", Vector2i(-1, -1), "core:carrot").success), "ordinary product is gated by a built table")
	product.add_structure({"building_id": "core:study_table", "cell": [22, 20], "stage_id": "core:complete"})
	var result := _command(product, "extract", Vector2i(-1, -1), "core:carrot")
	_check(bool(result.success) and product.get_item_count("core:carrot") == 0, "ordinary extraction consumes one product")
	_check(product.get_item_count("core:carrot_seed") >= 1 and product.get_item_count("core:carrot_seed") <= 5, "ordinary crop returns its own 1-5 seeds")
	_check(product.get_item_count("core:potato_seed") == 0, "ordinary crop never produces another species")


func _test_berry_cooldown() -> void:
	var sim := Sim.new()
	var bush: Dictionary = sim.get_surface_berry_bushes()[0]
	sim.set_player_position(bush.position)
	_check(bool(sim.execute_interaction(String(bush.id)).success), "actual generated bush can be gathered")
	var ready := int(sim.state.farming.berry_ready_at[String(bush.id)])
	_check(ready - sim.get_elapsed_game_minutes() == 4320, "bush regrows 72 hours after collection")
	_check(not bool(sim.execute_interaction(String(bush.id)).success), "same bush cannot be spammed")
	var loaded := Sim.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	loaded.state.elapsed_game_minutes = ready - 1
	_check(not bool(loaded.execute_interaction(String(bush.id)).success), "cooldown survives JSON load to its last minute")
	_advance_fixture(loaded, 1)
	_check(bool(loaded.execute_interaction(String(bush.id)).success), "exact 72-hour boundary allows collection")


func _test_growth_water_and_harvest_modes() -> void:
	for definition: Dictionary in Sim.new().farming.catalog.crops:
		var sim := Sim.new()
		var hoe := _equip(sim, "core:hoe")
		var cell := _soil(sim)
		sim.set_player_position(Content.cell_center(cell.x, cell.y))
		_check(bool(_command(sim, "till", cell).success), "equipped physical hoe tills real soil")
		var seed_id := String(definition.seed_id)
		sim.try_pickup_item(seed_id, 1)
		_check(bool(_command(sim, "plant", cell, seed_id).success), "one seed plants one slot")
		_check(sim.get_item_count(seed_id) == 0, "planting consumes exactly one seed")
		var bucket := _equip(sim, "core:bucket", 2)
		_check(bool(_command(sim, "water", cell).success), "selected charged bucket waters")
		_check(int(sim.get_item_instance(bucket).state.charges) == 1, "only selected instance loses one charge")
		_check(not bool(_command(sim, "water", cell).success), "wet bed rejects wasteful repeated watering")
		_advance_fixture(sim, 1440)
		_check(int(sim.get_farm_bed(cell).growth) == mini(1440, int(definition.growth_minutes)), "24 hours of moisture grants corresponding growth")
		var dry_growth := int(sim.get_farm_bed(cell).growth)
		_advance_fixture(sim, 1440)
		_check(int(sim.get_farm_bed(cell).growth) == dry_growth, "dryness pauses rather than advances growth")
		while int(sim.get_farm_bed(cell).growth) < int(definition.growth_minutes):
			sim._update_instance_state(bucket, {"charges": 2})
			_check(bool(_command(sim, "water", cell).success), "dry crop can resume")
			_advance_fixture(sim, 1440)
		var drops_before := sim.get_world_drops().size()
		_check(bool(_command(sim, "harvest", cell).success), "ripe crop harvest succeeds")
		_check(sim.get_world_drops().size() - drops_before == int(definition["yield"]), "harvest creates the correct physical product count")
		_check(sim.get_item_count(seed_id) == 0, "no legacy automatic 67-percent seed return remains")
		_check(not bool(_command(sim, "harvest", cell).success), "harvest cannot be repeated instantly")
		if String(definition.harvest_mode) == "perennial":
			_check(String(sim.get_farm_bed(cell).crop_id) == String(definition.id), "perennial plant remains")
			sim._update_instance_state(bucket, {"charges": 2})
			if int(sim.get_farm_bed(cell).wet_until) <= sim.get_elapsed_game_minutes():
				_command(sim, "water", cell)
			_advance_fixture(sim, int(definition.regrow_minutes))
			_check(bool(_command(sim, "harvest", cell).success), "perennial gives a second crop after its interval")
		else:
			_check(String(sim.get_farm_bed(cell).crop_id).is_empty(), "single and multiple harvests free the slot")
		var loaded := Sim.new(JSON.parse_string(JSON.stringify(sim.export_state())))
		_check(loaded.get_farm_bed(cell) == sim.get_farm_bed(cell), "harvest mode state survives JSON reload")
		_check(bool(_command(loaded, "remove", cell).success) and loaded.get_farm_bed(cell).is_empty(), "player can clear any bed")
		_check(not hoe.is_empty(), "tool fixture uses a stable physical identity")


func _test_sleep_and_disk_round_trip() -> void:
	var sim := Sim.new()
	_equip(sim, "core:hoe")
	var cell := _soil(sim)
	sim.set_player_position(Content.cell_center(cell.x, cell.y))
	_command(sim, "till", cell)
	sim.try_pickup_item("core:carrot_seed", 1)
	_command(sim, "plant", cell, "core:carrot_seed")
	_equip(sim, "core:bucket", 2)
	_command(sim, "water", cell)
	var start := sim.get_elapsed_game_minutes()
	sim.advance_minutes(18 * 60 - sim.get_minute_of_day())
	sim.set_player_position(sim.content.get_interactable("core:bed_site").position)
	_check(bool(sim.execute_interaction("core:bed_site").success), "real sleep advances crop clock")
	_check(int(sim.get_farm_bed(cell).growth) == sim.get_elapsed_game_minutes() - start, "sleep growth matches actual elapsed minutes")
	var store := SaveStore.new("user://farming_rules_test.json")
	_check(bool(store.write_state(sim.export_state()).success), "farming state saves to disk")
	var read: Dictionary = store.read_state()
	_check(bool(read.success), "farming state reloads from disk")
	var loaded := Sim.new(read.state)
	_check(loaded.get_farm_bed(cell) == sim.get_farm_bed(cell), "load does not replay sleep or reset crop progress")
	var old := sim.export_state()
	old.version = 24
	old.erase("farming")
	var old_bush_id := String(sim.get_surface_berry_bushes()[0].id)
	old.collected[old_bush_id] = true
	var migrated := Sim.new(old)
	_check(migrated.get_farm_beds().is_empty() and migrated.get_day() == sim.get_day(), "v24 adds empty farm without resetting day")
	_check(migrated.get_inventory() == sim.get_inventory() and migrated.get_player_energy() == sim.get_player_energy(), "migration retains inventory and energy")
	_check(not migrated.farming.berry_ready(migrated, old_bush_id) and int(migrated.state.farming.berry_ready_at[old_bush_id]) == migrated.get_elapsed_game_minutes() + 4320, "old consumed bush starts a single cooldown on migration")
	var migrated_reload := Sim.new(JSON.parse_string(JSON.stringify(migrated.export_state())))
	_check(migrated_reload.state.farming.berry_ready_at == migrated.state.farming.berry_ready_at, "loading migrated cooldown does not restart it")
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path("user://farming_rules_test.json" + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_invalid_commands_and_state() -> void:
	var sim := Sim.new()
	var cell := _soil(sim)
	sim.set_player_position(Content.cell_center(cell.x, cell.y))
	_check(not bool(_command(sim, "till", cell).success), "owning no equipped hoe rejects preparation")
	_equip(sim, "core:hoe")
	_check(not bool(_command(sim, "till", Vector2i(127, 127)).success), "remote preparation is rejected")
	_check(not bool(_command(sim, "till", Vector2i(22, 20)).success), "house floor is not arable")
	var rock: Dictionary = sim.get_surface_boulders()[0]
	var neighbor := Vector2i(floori(rock.position.x / Content.CELL_SIZE) + 1, floori(rock.position.y / Content.CELL_SIZE))
	_check(not sim.farming._soil_allowed(sim, neighbor), "boulder edge protects adjacent ground beyond its center cell")
	_check(bool(_command(sim, "till", cell).success), "valid preparation succeeds")
	_check(not bool(sim.execute_construction_command(Construction.place_blueprint(cell, "core:wood_floor")).success), "construction cannot overwrite bed")
	_check(not bool(sim.create_storage_zone(cell, cell).success), "storage cannot overwrite bed")
	var bad := sim.export_state()
	bad.farming = {"beds": [{"cell": [cell.x, cell.y], "crop_id": "carrot", "growth": "bad"}, {"cell": [cell.x, cell.y]}], "roll_index": -8}
	var loaded := Sim.new(bad)
	_check(loaded.get_farm_beds().size() == 1 and int(loaded.state.farming.roll_index) == 0, "invalid values and duplicate plots normalize")
	sim.try_pickup_item("core:carrot", 1)
	sim.state.player_energy = 0.0
	_check(sim.get_player_work_speed_multiplier() > 0.0 and sim.get_player_work_speed_multiplier() < 1.0, "fatigue slows but permits work")
	_check(bool(sim.eat_food("core:carrot").success) and sim.get_player_energy() > 0.0, "raw crop restores actual energy")
