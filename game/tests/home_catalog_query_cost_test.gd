extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Catalog := preload("res://src/characters/npc_catalog.gd")
const Projects := preload("res://src/npc_work/npc_home_projects.gd")
class ObservedCatalog extends Catalog:
	var definition_copies := 0
	var roster_copies := 0
	func get_definitions() -> Array[Dictionary]:
		roster_copies += 1
		return super.get_definitions()
	func get_definition(id: String) -> Dictionary:
		definition_copies += 1
		return super.get_definition(id)
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var sim = Fixture.create(true)
	var catalog := ObservedCatalog.new()
	for definition: Dictionary in sim.npc_catalog.get_definitions():
		catalog._definitions_by_id[String(definition.id)] = definition
	catalog._definition_order = sim.npc_catalog._definition_order.duplicate()
	sim.npc_catalog = catalog
	var npc: Dictionary = sim.state.npcs[Fixture.NPC]
	var goal := Projects.choose(sim,npc)
	check(not goal.is_empty(),"The resident chooses a useful home goal in a real shared room")
	check(catalog.definition_copies == 0,"Checking whether another resident exists does not clone their entire definition")
	var other := ""
	for id: String in sim.state.npcs:
		if id != Fixture.NPC: other = id
	sim.state.npcs[other].home_goal = goal.duplicate(true)
	var second_goal := Projects.choose(sim,npc)
	check(second_goal.is_empty() or Projects.key(second_goal) != Projects.key(goal),"Membership check still protects another resident's reserved goal")
	var definition := catalog.get_definition(Fixture.NPC)
	catalog.definition_copies = 0
	npc.known = true
	check(catalog.get_label_key(sim.state.npcs,Fixture.NPC,"fallback") == String(definition.get("name_key","fallback")),"Known names read the current catalog label")
	npc.known = false
	check(catalog.get_label_key(sim.state.npcs,Fixture.NPC,"fallback") == String(definition.get("unknown_label_key","fallback")),"Learning state still selects an unknown label immediately")
	check(catalog.get_label_key(sim.state.npcs,"missing","fallback") == "fallback","Missing residents retain the caller label fallback")
	check(catalog.definition_copies == 0,"Reading a label does not copy the whole resident definition")
	var ids := catalog.definition_ids()
	check(ids.size() == catalog.definition_count(),"Count and ids include the current ordered authored/generated catalog")
	ids.clear()
	check(catalog.definition_count() > 0 and not catalog.definition_ids().is_empty(),"Returned identity arrays do not share live catalog order")
	catalog.roster_copies = 0
	sim.housing.contexts(sim)
	sim.NpcPracticalWork.prepare(sim)
	check(catalog.roster_copies == 0,"Identity-only housing and work loops do not clone the complete roster")
	print("HOME_CATALOG_QUERY_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
