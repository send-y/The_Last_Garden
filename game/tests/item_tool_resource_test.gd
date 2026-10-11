extends SceneTree
const Fixture := preload("res://tests/fixtures/item_tool_fixture.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var sim := Fixture.world()
	sim.try_pickup_item("test:axe_variant", 1)
	var first := sim.get_inventory_instance_id("test:axe_variant", 0)
	sim.select_inventory_item("test:axe_variant", first)
	var target := "core:wood_north"
	sim.set_player_position(sim.content.get_interactable(target).position)
	var work := sim.execute_resource_work("core:player", target)
	check(work.success, "Variant axe performs actual wood work")
	check(sim.has_method("actor_tool_supports"), "Actual actor capability query")
	if not sim.has_method("actor_tool_supports"):
		finish()
		return
	check(sim.call("get_resource_required_tool_action", target) == "chop", "Target advertises action")
	sim.try_pickup_item("test:axe_variant", 1)
	var second := sim.get_inventory_instance_id("test:axe_variant", 1)
	sim.select_inventory_item("test:axe_variant", second)
	work = sim.execute_resource_work("core:player", target)
	check(work.reason_id == "core:resource_work_tool_changed" and not sim.is_collected(target) and sim.get_resource_work_progress(target) == 0, "Changing physical copy resets progress")
	check(sim.execute_resource_work("core:player", target).success, "New copy starts next work")
	sim.select_inventory_item("", "")
	check(not sim.execute_resource_work("core:player", target).success, "Backpack ownership is insufficient")
	var before := sim.export_state()
	check(not sim.execute_resource_work("core:player", target).success and sim.export_state() == before, "Idle refusal has no side effects")
	sim.select_inventory_item("test:axe_variant", first)
	sim._set_instance_location(first, "npc", "core:first_neighbor")
	check(not sim.call("actor_tool_supports", "core:player", "chop"), "Foreign tool cannot be selected")
	sim._set_instance_location(first, "inventory")
	sim.select_inventory_item("test:axe_variant", first)
	var bush: Dictionary = sim.get_surface_berry_bushes()[0]
	sim.set_player_position(bush.position)
	check(sim.edit_world("clear_bush", Vector2i.ZERO, String(bush.id)).success, "Variant clears real bush")
	sim = Fixture.world()
	var stone := "core:stone_south"
	sim.try_pickup_item("test:pickaxe_variant", 1)
	sim.select_inventory_item("test:pickaxe_variant", sim.get_inventory_instance_id("test:pickaxe_variant", 0))
	sim.set_player_position(sim.content.get_interactable(stone).position)
	check(sim.execute_resource_work("core:player", stone).success, "Variant pickaxe mines")
	sim = Fixture.world()
	sim.try_pickup_item("test:axe_variant", 1)
	var variant_id := sim.get_inventory_instance_id("test:axe_variant", 0)
	sim.try_pickup_item("core:axe", 1)
	var base_id := sim.get_inventory_instance_id("core:axe", 0)
	sim.select_inventory_item("test:axe_variant", variant_id)
	sim.set_player_position(sim.content.get_interactable(target).position)
	check(sim.execute_resource_work("core:player", target).success, "Variant starts before switching model")
	sim.select_inventory_item("core:axe", base_id)
	check(sim.execute_resource_work("core:player", target).reason_id == "core:resource_work_tool_changed", "Different compatible model also resets physical progress")
	sim.select_inventory_item("test:axe_variant", variant_id)
	for step: int in range(sim.get_resource_work_required(target)):
		sim.execute_resource_work("core:player", target)
	check(sim.is_collected(target), "Variant completes actual resource")
	sim.select_inventory_item("", "")
	var wood_drops := 0
	for drop: Dictionary in sim.state.world_drops.duplicate(true):
		if String(drop.item_id) == "core:wood":
			wood_drops += 1
			sim.set_player_position(Vector2(float(drop.position[0]), float(drop.position[1])))
			check(sim.try_pickup_world_drop(String(drop.drop_id)).success, "Resource drop pickup needs no held tool")
	check(wood_drops > 0, "Actual wood was dropped")
	finish()
func finish() -> void:
	print("ITEM_TOOL_RESOURCE: %d failures" % failures)
	quit(0 if failures == 0 else 1)
