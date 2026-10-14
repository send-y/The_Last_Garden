extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Food := preload("res://src/needs/npc_food_supply.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func run() -> void:
	var sim = World.new(World.create_new_game_state())
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.active = true
	npc.known = true
	npc.personal_inventory = {}
	npc.needs.hunger = 40.0
	var bush: Dictionary = sim.get_surface_berry_bushes()[0]
	var position: Vector2 = bush.position+Vector2(32,0)
	npc.position = [position.x,position.y]
	var meal: Dictionary = Food.find_meal(sim,npc)
	check(meal.get("source","") == "wild","Hungry NPC finds ready wild food without warehouse food")
	if meal.get("source","") == "wild":
		var destination: Array = meal.target_cell
		var point: Vector2 = sim.content.cell_center(int(destination[0]),int(destination[1]))
		npc.position = [point.x,point.y]
		check(Food.fulfil(sim,{"npc_id":String(npc.id),"meal":meal}),"NPC harvests actual reachable wild source")
		check(int(npc.personal_inventory.get("core:food",0)) == 2,"Harvest creates the real existing two portions")
		check(not sim.farming.berry_ready(sim,String(meal.object_id)),"Shared bush enters normal regrowth cooldown")
		var before := JSON.stringify(sim.export_state())
		check(not Food.fulfil(sim,{"npc_id":String(npc.id),"meal":meal}) and JSON.stringify(sim.export_state()) == before,"Second harvest cannot duplicate food")
		var personal: Dictionary = Food.find_meal(sim,npc)
		var at: Vector2 = sim.content.cell_center(int(personal.target_cell[0]),int(personal.target_cell[1]))
		npc.position = [at.x,at.y]
		check(Food.fulfil(sim,{"npc_id":String(npc.id),"meal":personal}) and float(npc.needs.hunger) > 40,"Harvested portion actually feeds NPC")
	print("PLAYTEST_NPC_FOOD: %d failures" % failures)
	quit(0 if failures == 0 else 1)
