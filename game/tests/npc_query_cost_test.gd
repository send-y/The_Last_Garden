extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const NPC := "core:first_neighbor"

class ObservedWorld extends World:
	var roster_copies := 0
	func get_npcs() -> Dictionary:
		roster_copies += 1
		return super.get_npcs()

var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var sim := ObservedWorld.new()
	var npc: Dictionary = sim.state.npcs[NPC]
	npc.active = true
	npc.position = [123.0,456.0]
	npc.needs = {"hunger":77.0,"energy":82.0,"restedness":43.0}
	npc.personal_inventory = {Content.FOOD_ID:3}
	npc.work_commitment = {"target_cell":[42,31],"required_minutes":3}
	npc.memories = []
	npc.target_cell = [42,33]
	npc.facing = [1.0,0.0]
	npc.moving = true
	npc.activity_id = "core:work_travel"
	sim.roster_copies = 0
	check(sim.is_npc_visible(NPC),"Existing active resident is visible")
	check(sim.get_npc_position(NPC,Vector2.ZERO) == Vector2(123,456),"Position reads the requested resident")
	check(sim.get_npc_position("core:missing",Vector2(5,6)) == Vector2(5,6),"Missing resident retains fallback")
	var appearance := sim.get_npc_appearance(NPC)
	check(not appearance.is_empty(),"Resident appearance is returned")
	appearance.clear()
	check(not sim.get_npc_appearance(NPC).is_empty(),"Appearance result cannot mutate the authoritative resident")
	var needs := sim.get_npc_needs(NPC)
	check(needs.hunger == 77.0,"Physical needs return current value")
	needs.hunger = 0.0
	check(npc.needs.hunger == 77.0,"Needs result is isolated")
	check(sim.get_npc_personal_food(NPC) == 3,"Food is read from this resident only")
	var commitment := sim.get_npc_work_commitment(NPC)
	commitment.target_cell[0] = 99
	check(npc.work_commitment.target_cell == [42,31],"Nested commitment result is isolated")
	var memories := sim.get_npc_memories(NPC)
	memories.append({"test":true})
	check(npc.memories.is_empty(),"Memory result is isolated")
	sim.get_npc_relationship_to_player(NPC)
	check(sim.get_npc_target_cell(NPC) == Vector2i(42,33),"Current target cell is returned")
	check(sim.get_npc_facing(NPC) == Vector2.RIGHT and sim.is_npc_moving(NPC),"Current movement and direction are returned")
	check(sim.get_npc_activity_id(NPC) == "core:work_travel","Current activity is returned")
	sim.get_npc_activity_key(NPC)
	check(sim.get_npc_needs("core:missing").is_empty() and not sim.is_npc_visible("core:missing"),"Unknown resident queries keep empty defaults")
	check(sim.roster_copies == 0,"Single-resident queries must never duplicate the whole population")
	var roster := sim.get_npcs()
	roster[NPC].needs.hunger = 0.0
	check(npc.needs.hunger == 77.0,"Full roster public export remains isolated")
	print("NPC_QUERY_COST: %d failures; full roster reads %d" % [failures,sim.roster_copies])
	quit(0 if failures == 0 else 1)
