class_name FarmingSystem
extends RefCounted

const Catalog := preload("res://src/farming/crop_catalog.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Navigation := preload("res://src/simulation/first_night_navigation.gd")
const Packer := preload("res://src/inventory/inventory_auto_packer.gd")
const Localized := preload("res://src/localization/localized_text.gd")
var catalog := Catalog.new()


static func empty_state() -> Dictionary:
	return {"beds": [], "berry_ready_at": {}, "roll_index": 0, "harvest_count": 0, "extraction_count": 0, "crop_extraction_count": 0}


func normalize(sim) -> void:
	var raw: Variant = sim.state.get("farming", {})
	var farm: Dictionary = raw if raw is Dictionary else {}
	var normalized := empty_state()
	var now: int = sim.get_elapsed_game_minutes()
	for key: String in ["roll_index", "harvest_count", "extraction_count", "crop_extraction_count"]:
		normalized[key] = clampi(_number(farm.get(key), 0), 0, 100000000)
	var used: Dictionary = {}
	var beds: Variant = farm.get("beds", [])
	if beds is Array:
		for value: Variant in beds:
			if not value is Dictionary:
				continue
			var cell_value: Variant = value.get("cell")
			if not _valid_cell(cell_value):
				continue
			var cell := Vector2i(int(cell_value[0]), int(cell_value[1]))
			if used.has(_key(cell)) or not _soil_allowed(sim, cell):
				continue
			used[_key(cell)] = true
			var crop := catalog.find(String(value.get("crop_id", "")))
			var bed: Dictionary = {"cell": [cell.x, cell.y], "crop_id": String(crop.get("id", "")),
				"growth": 0, "wet_until": 0, "last_update": now, "harvests": 0}
			bed["harvests"] = clampi(_number(value.get("harvests"), 0), 0, 100000000)
			bed["wet_until"] = clampi(_number(value.get("wet_until"), 0), 0, now + int(catalog.settings.water_duration_minutes))
			bed["last_update"] = clampi(_number(value.get("last_update"), now), 0, now)
			if not crop.is_empty():
				bed["growth"] = clampi(_number(value.get("growth"), 0), 0, _required_growth(bed, crop))
			(normalized.beds as Array).append(bed)
	var timers: Variant = farm.get("berry_ready_at", {})
	if timers is Dictionary:
		for id: Variant in timers.keys():
			var target: Dictionary = sim._resolve_interaction_target(String(id))
			if String(target.get("kind", "")) == "food":
				normalized.berry_ready_at[String(id)] = clampi(_number(timers[id], 0), 0, now + int(catalog.settings.berry_regrow_minutes))
	sim.state["farming"] = normalized


func advance(sim) -> bool:
	var now: int = sim.get_elapsed_game_minutes()
	var changed := false
	for bed: Dictionary in sim.state.farming.beds:
		var previous: int = int(bed.last_update)
		bed.last_update = now
		var crop := catalog.find(String(bed.crop_id))
		if crop.is_empty():
			continue
		var wet_minutes := maxi(0, mini(now, int(bed.wet_until)) - previous)
		var growth := mini(_required_growth(bed, crop), int(bed.growth) + wet_minutes)
		changed = changed or growth != int(bed.growth) or (previous < int(bed.wet_until) and now >= int(bed.wet_until))
		bed.growth = growth
	# Waking bushes changes their selection prompt even without a crop bed.
	for ready: Variant in sim.state.farming.berry_ready_at.values():
		changed = changed or int(ready) == now
	return changed


func bed_at(sim, cell: Vector2i) -> Dictionary:
	var raw_farm: Variant = sim.state.get("farming", {})
	if not raw_farm is Dictionary or not raw_farm.get("beds", []) is Array:
		return {}
	for value: Variant in raw_farm.get("beds", []):
		if not value is Dictionary:
			continue
		var bed: Dictionary = value
		if bed.get("cell", []) == [cell.x, cell.y]:
			return bed
	return {}


func extraction_unlocked(sim) -> bool:
	for structure: Dictionary in sim.get_structures():
		if String(structure.get("building_id", "")) == "core:study_table":
			return true
	return false


func berry_ready(sim, id: String) -> bool:
	var raw: Variant = sim.state.get("farming", {})
	if not raw is Dictionary or not raw.get("berry_ready_at", {}) is Dictionary:
		return true
	return sim.get_elapsed_game_minutes() >= _number(raw.get("berry_ready_at", {}).get(id, 0), 0)


func execute(sim, command: Dictionary) -> Dictionary:
	if String(command.get("actor_id", "")) != "core:player":
		return _result(sim, false, "farming.failure.actor")
	var action := String(command.get("action_id", ""))
	if action == "extract":
		return _extract(sim, String(command.get("item_id", "")))
	if action == "eat":
		return _eat(sim, String(command.get("item_id", "")))
	var cell_value: Variant = command.get("cell")
	if not _valid_cell(cell_value):
		return _result(sim, false, "farming.failure.soil")
	var cell := Vector2i(int(cell_value[0]), int(cell_value[1]))
	if sim.get_player_position().distance_to(Content.cell_center(cell.x, cell.y)) > Content.INTERACTION_RANGE:
		return _result(sim, false, "interaction.failure.too_far")
	if action in ["till","plant","water","harvest","remove"]:
		if not sim.prepare_player_work():
			return _result(sim,false,"furniture.failure.approach")
		if sim.get_player_position().distance_to(Content.cell_center(cell.x,cell.y)) > Content.INTERACTION_RANGE:
			return _result(sim,false,"interaction.failure.too_far")
	var bed := bed_at(sim, cell)
	match action:
		"till":
			if String(sim.get_active_item_instance().get("item_id", "")) != "core:hoe":
				return _result(sim, false, "farming.failure.hoe")
			if not bed.is_empty() or not _soil_allowed(sim, cell):
				return _result(sim, false, "farming.failure.soil")
			sim.state.farming.beds.append({"cell": [cell.x, cell.y], "crop_id": "", "growth": 0,
				"wet_until": 0, "last_update": sim.get_elapsed_game_minutes(), "harvests": 0})
			sim._spend_player_work_energy()
			return _result(sim, true, "farming.tilled")
		"plant":
			var seed_id := String(command.get("item_id", ""))
			var crop := catalog.find(seed_id)
			if bed.is_empty() or not String(bed.crop_id).is_empty() or crop.is_empty() or seed_id != String(crop.seed_id):
				return _result(sim, false, "farming.failure.plant")
			if not sim._consume_items({seed_id: 1}):
				return _result(sim, false, "farming.failure.seeds")
			bed.crop_id = crop.id
			bed.growth = 0
			bed.harvests = 0
			bed.last_update = sim.get_elapsed_game_minutes()
			return _result(sim, true, "farming.planted")
		"water":
			return water_for_actor(sim, "core:player", cell)
		"harvest":
			var crop := catalog.find(String(bed.get("crop_id", "")))
			if crop.is_empty() or int(bed.growth) < _required_growth(bed, crop):
				return _result(sim, false, "farming.failure.unripe")
			sim._create_resource_drops("farming:%s" % crop.id, String(crop.product_id), int(crop.yield), Content.cell_center(cell.x, cell.y))
			bed.harvests = int(bed.harvests) + 1
			bed.growth = 0
			bed.last_update = sim.get_elapsed_game_minutes()
			if String(crop.harvest_mode) != "perennial":
				bed.crop_id = ""
			sim.state.farming.harvest_count = int(sim.state.farming.harvest_count) + 1
			return _result(sim, true, "farming.harvested", {"amount": int(crop.yield)})
		"remove":
			if bed.is_empty():
				return _result(sim, false, "farming.failure.plant")
			sim.state.farming.beds.erase(bed)
			return _result(sim, true, "farming.removed")
	return _result(sim, false, "farming.failure.action")


func _extract(sim, item_id: String) -> Dictionary:
	var special := item_id == Content.FOOD_ID
	var crop := catalog.find(item_id)
	if not special and (crop.is_empty() or item_id != String(crop.product_id)):
		return _result(sim, false, "farming.failure.product")
	if not special and not extraction_unlocked(sim):
		return _result(sim, false, "farming.failure.study")
	if sim.get_item_count(item_id) < 1:
		return _result(sim, false, "farming.failure.product")
	var rng := RandomNumberGenerator.new()
	var serial: int = int(sim.state.farming.roll_index)
	# The stream advances only when the entire inventory transaction commits.
	# Save/load and failed capacity checks retain the same next result.
	rng.seed = int(sim.state.seed) ^ (serial * 104729 + 57391)
	if special:
		crop = catalog.crops[rng.randi_range(0, catalog.crops.size() - 1)]
	var amount := rng.randi_range(2, 4) if special else rng.randi_range(1, 5)
	var inventory: Dictionary = sim.get_inventory()
	inventory[item_id] = int(inventory.get(item_id, 0)) - 1
	var seed_id := String(crop.seed_id)
	inventory[seed_id] = int(inventory.get(seed_id, 0)) + amount
	var packed := Packer.pack_with_layout(inventory, sim.content, sim.state.inventory_layout, 4, 4)
	if not (packed.get("overflow", {}) as Dictionary).is_empty():
		return _result(sim, false, "first_night.inventory.no_space")
	sim._consume_items({item_id: 1})
	sim._add_item(seed_id, amount)
	sim.state.inventory_layout = packed.layout
	sim.state.farming.roll_index = serial + 1
	sim.state.farming.extraction_count = int(sim.state.farming.extraction_count) + 1
	if not special:
		sim.state.farming.crop_extraction_count = int(sim.state.farming.crop_extraction_count) + 1
	return _result(sim, true, "farming.extracted", {"amount": amount, "crop": Localized.text_reference(String(crop.name_key))})


func _eat(sim, item_id: String) -> Dictionary:
	var crop := catalog.find(item_id)
	var energy := int(catalog.settings.special_berry_energy) if item_id == Content.FOOD_ID else int(crop.get("energy", 0))
	if energy <= 0 or (item_id != Content.FOOD_ID and item_id != String(crop.get("product_id", ""))):
		return _result(sim, false, "farming.failure.product")
	if not sim._consume_items({item_id: 1}):
		return _result(sim, false, "ui.inventory.food.none")
	var profile: Dictionary = sim.needs.food_profile(item_id, catalog)
	var physical: Dictionary = sim.get_player_needs()
	sim.needs.feed(physical, profile)
	sim.state.player_energy = physical.energy
	sim.state.player_needs.hunger = physical.hunger
	return _result(sim, true, "farming.eaten", {"energy": energy, "satiety": profile.satiety})


func _soil_allowed(sim, cell: Vector2i) -> bool:
	if not Rect2i(Vector2i.ZERO, Content.MAP_SIZE).has_point(cell) or Navigation.blocked_cells().has(cell):
		return false
	# The static Common House has a floor, so it is not arable ground.
	if Rect2i(19, 17, 10, 9).has_point(cell) or sim._world_cell_blocks_storage(cell, true):
		return false
	if sim._storage_zone_index_at_cell(cell) >= 0:
		return false
	# Protect the whole visible boulder and the tree's ground-level trunk,
	# rather than only the resource's center cell.
	var ground := Rect2(Vector2(cell) * Content.CELL_SIZE, Vector2.ONE * Content.CELL_SIZE)
	for rock: Dictionary in sim.get_surface_boulders():
		if ground.intersects(Rect2((rock.position as Vector2) - Vector2(32, 32), Vector2(64, 64))):
			return false
	for tree: Dictionary in sim.get_surface_trees():
		if String(tree.presentation_id) == "surface_tree" and ground.intersects(Rect2((tree.position as Vector2) + Vector2(-8, 11), Vector2(16, 18))):
			return false
	for key: String in ["structures", "blueprints"]:
		for entity: Dictionary in sim.state[key]:
			if sim._entity_occupies_cell(entity, [cell.x, cell.y]):
				return false
	return true


func _required_growth(bed: Dictionary, crop: Dictionary) -> int:
	return int(crop.regrow_minutes) if String(crop.harvest_mode) == "perennial" and int(bed.harvests) > 0 else int(crop.growth_minutes)


func objective(sim) -> String:
	var farm: Dictionary = sim.state.farming
	if int(farm.harvest_count) >= 2 and int(farm.crop_extraction_count) > 0:
		return "farming.objective.complete"
	var planted := false
	for bed: Dictionary in farm.beds:
		var crop := catalog.find(String(bed.crop_id))
		if crop.is_empty():
			continue
		planted = true
		if int(bed.growth) >= _required_growth(bed, crop):
			return "farming.objective.harvest"
		if int(bed.wet_until) <= sim.get_elapsed_game_minutes():
			return "farming.objective.water"
	if not extraction_unlocked(sim):
		return "farming.objective.study"
	if int(farm.harvest_count) > 0:
		if int(farm.crop_extraction_count) <= 0:
			return "farming.objective.extract"
	if planted:
		return "farming.objective.grow"
	for crop: Dictionary in catalog.crops:
		if sim.get_item_count(String(crop.seed_id)) > 0:
			return "farming.objective.bed" if (farm.beds as Array).is_empty() else "farming.objective.plant"
	return "farming.objective.seeds"


func status(sim, cell: Vector2i) -> String:
	var bed := bed_at(sim, cell)
	if bed.is_empty():
		return ""
	var crop := catalog.find(String(bed.crop_id))
	var wet: bool = int(bed.wet_until) > sim.get_elapsed_game_minutes()
	if crop.is_empty():
		return Localized.resolve("farming.bed.empty")
	var required := _required_growth(bed, crop)
	return Localized.resolve("farming.bed.status", {"crop": Localized.text_reference(String(crop.name_key)),
		"percent": mini(100, int(bed.growth) * 100 / required),
		"state": Localized.text_reference("farming.ready" if int(bed.growth) >= required else "farming.wet" if wet else "farming.dry")})


func _valid_cell(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for coordinate: Variant in value:
		if _number(coordinate, -1) < 0 or _number(coordinate, -1) >= Content.MAP_SIZE.x:
			return false
	return true


func _number(value: Variant, fallback: int) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var number := float(value)
	return int(number) if is_finite(number) and number == floor(number) and absf(number) < 1000000000.0 else fallback


func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _result(sim, success: bool, key: String, args: Dictionary = {}) -> Dictionary:
	return sim._emit_result(success, key, success, success, args)


func water_for_actor(sim, actor_id: String, cell: Vector2i) -> Dictionary:
	var actor: Dictionary = sim._get_resource_actor_position(actor_id)
	if not bool(actor.get("found", false)) or (actor.position as Vector2).distance_to(Content.cell_center(cell.x, cell.y)) > Content.INTERACTION_RANGE:
		return _result(sim, false, "farming.failure.actor")
	var bed: Dictionary = sim.get_farm_bed(cell)
	var bucket: Dictionary = sim.get_actor_tool(actor_id)
	if bed.is_empty() or String(bucket.get("item_id", "")) != "core:bucket":
		return _result(sim, false, "farming.failure.water")
	var bucket_state: Dictionary = bucket.get("state", {})
	if int(bucket_state.get("charges", 0)) <= 0:
		return _result(sim, false, "farming.failure.water")
	if int(bed.wet_until) > sim.get_elapsed_game_minutes():
		return _result(sim, false, "farming.failure.wet")
	bucket_state.charges = int(bucket_state.get("charges", 0)) - 1
	sim._update_instance_state(String(bucket.instance_id), bucket_state)
	for stored_bed: Dictionary in sim.state.farming.beds:
		if stored_bed.cell == [cell.x, cell.y]:
			stored_bed.wet_until = sim.get_elapsed_game_minutes() + int(catalog.settings.water_duration_minutes)
			break
	return _result(sim, true, "farming.watered")
