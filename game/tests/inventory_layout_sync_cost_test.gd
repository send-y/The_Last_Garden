extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Packer := preload("res://src/inventory/inventory_auto_packer.gd")
class ObservedContent extends Content:
	var footprints := 0
	func item_footprint(item_id: String, rotation: int = 0) -> Array[Vector2i]:
		footprints += 1
		return super.item_footprint(item_id,rotation)
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func check_layout(sim, message: String) -> void:
	var expected := Packer.pack_with_layout(sim.get_inventory(),sim.content,sim.state.inventory_layout,4,4)
	check(sim.state.inventory_layout == expected.layout,message)
func run() -> void:
	var sim := World.new()
	var content := ObservedContent.new()
	sim.content = content
	sim.state.inventory = {"core:plank":5}
	var ids := sim._create_item_instances("core:axe",1,"inventory")
	sim._emit_result(true,"npc.goal.chosen",true)
	check_layout(sim,"Initial synchronization creates a valid layout for resources and a physical tool")
	var before := sim.export_state()
	content.footprints = 0
	for _event: int in range(30): sim._emit_result(true,"npc.goal.chosen",true)
	check(content.footprints == 0,"Unrelated resident events must not repack an unchanged player inventory")
	check(sim.export_state() == before,"Skipping duplicate synchronization preserves authoritative state")
	sim.state.inventory["core:plank"] = 8
	sim._emit_result(true,"npc.goal.chosen",true)
	check(content.footprints > 0,"A changed stack invalidates synchronization immediately")
	check_layout(sim,"Changed inventory remains canonically packed")
	sim.select_inventory_item("core:axe",ids[0])
	sim._set_instance_location(ids[0],"storage","core:test")
	sim._emit_result(true,"npc.goal.chosen",true)
	check(sim.state.selected_inventory_item.is_empty(),"A removed physical tool cannot remain selected")
	check_layout(sim,"Moving a physical instance out of inventory updates layout")
	sim._set_instance_location(ids[0],"inventory","")
	sim._emit_result(true,"npc.goal.chosen",true)
	check_layout(sim,"Returning a physical instance updates layout")
	sim.state.inventory_layout[0].origin = [3,3]
	sim._emit_result(true,"npc.goal.chosen",true)
	check_layout(sim,"An in-place manual layout change is validated instead of hidden by a shared cache alias")
	content.footprints = 0
	sim.content = ObservedContent.new()
	sim._emit_result(true,"npc.goal.chosen",true)
	check(sim.content.footprints > 0,"Replacing content invalidates runtime synchronization")
	var loaded := World.new(sim.export_state())
	var loaded_before := loaded.export_state()
	loaded._emit_result(true,"npc.goal.chosen",true)
	check(loaded.export_state() == loaded_before,"A loaded world validates its own inventory without changing an already valid save")
	print("INVENTORY_LAYOUT_SYNC_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
