extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
class ObservedWorld extends World:
	var inventory_reads := 0
	func get_inventory() -> Dictionary:
		inventory_reads += 1
		return super.get_inventory()
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var fixture = Fixture.create()
	var sim := ObservedWorld.new(fixture.export_state())
	var npc: Dictionary = sim.state.npcs[Fixture.NPC]
	sim.set_npc_work_enabled(Fixture.NPC,"build",true)
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	var layout: Array = sim.state.inventory_layout.duplicate(true)
	sim.inventory_reads = 0
	sim.NpcHomeProjects.prepare(sim,npc)
	check(not npc.home_goal.is_empty(),"The fixture produces a genuine personal goal")
	check(sim.inventory_reads == 0,"Choosing a household goal does not scan the unchanged player backpack")
	check(sim.state.inventory_layout == layout,"An informational home notice preserves the actual inventory layout")
	check(events.any(func(event: Dictionary): return String(event.get("message_key","")) == "npc.goal.chosen" and bool(event.get("changed",false))),"The same chosen-goal message and state notification are delivered")
	var goal: Dictionary = npc.home_goal
	sim.add_structure({"building_id":goal.building_id,"cell":goal.cell,"lit":true})
	sim.inventory_reads = 0
	sim.NpcHomeProjects.observe(sim,npc)
	check(String(npc.home_goal.status) == "done" and sim.inventory_reads == 0,"Completing a project delivers its notice without scanning the backpack")
	sim.inventory_reads = 0
	sim.NpcHomeProjects.request_expansion(sim,npc,Fixture.ROOM,"core:table")
	check(not npc.home_expansion.is_empty() and sim.inventory_reads == 0,"Expansion requests are informational and preserve the backpack")
	sim.state.inventory["core:plank"] = 3
	sim._emit_result(true,"ui.inventory.move.success",true)
	check(sim.inventory_reads > 0,"Ordinary commands still read changed physical/count inventory")
	check(sim.state.inventory_layout != layout,"An ordinary actual inventory change still rebuilds its layout")
	var ids := sim._create_item_instances("core:axe",1,"inventory")
	sim._emit_result(true,"ui.inventory.move.success",true)
	sim.select_inventory_item("core:axe",ids[0])
	sim._set_instance_location(ids[0],"storage","core:test")
	sim.NpcHomeProjects.request_expansion(sim,npc,Fixture.ROOM,"core:chair")
	check(sim.state.selected_inventory_item.is_empty(),"Home notices still validate that the selected physical tool is present")
	print("HOUSEHOLD_NOTICE_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
