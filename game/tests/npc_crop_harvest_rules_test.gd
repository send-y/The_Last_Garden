extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const ID := "core:first_neighbor"
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL: ", label)

func fixture():
	var state := World.create_new_game_state(1337)
	state.npcs[ID].active = true
	state.npcs[ID].known = true
	return World.new(state)

func soil(sim) -> Vector2i:
	for y: int in range(27, 44):
		for x: int in range(20, 44):
			var cell := Vector2i(x,y)
			if sim.farming._soil_allowed(sim,cell): return cell
	return Vector2i(-1,-1)

func run() -> void:
	var sim = fixture()
	var cell := soil(sim)
	var point := Content.cell_center(cell.x,cell.y)
	sim.state.farming.beds.append({"cell":[cell.x,cell.y],"crop_id":"carrot","growth":1440,"wet_until":0,"last_update":0,"harvests":0})
	var restored = World.new(sim.export_state())
	check(not bool(restored.get_farm_bed(cell).get("shared_harvest",true)),"Legacy bed defaults to personal")
	check(int(restored.get_farm_bed(cell).growth)==1440,"Migration retains ripe crop growth")
	if not sim.farming.has_method("harvest_for_actor"):
		check(false,"Missing authoritative actor crop harvest")
		quit(1); return
	var npc: Dictionary = sim.state.npcs[ID]
	npc.position = [point.x,point.y]
	npc.work_options.harvest = true
	var before := JSON.stringify(sim.export_state())
	check(not bool(sim.farming.harvest_for_actor(sim,ID,cell).success),"NPC cannot harvest personal bed")
	check(JSON.stringify(sim.export_state())==before,"Refusal preserves complete state")
	sim.set_player_position(point)
	check(bool(sim.execute_farming_command({"actor_id":"core:player","action_id":"set_shared_harvest","cell":[cell.x,cell.y],"enabled":true}).success),"Player shares nearby bed")
	check(bool(sim.get_farm_bed(cell).shared_harvest),"Sharing is authoritative")
	npc.position = [0.0,0.0]
	check(not bool(sim.farming.harvest_for_actor(sim,ID,cell).success),"Distant actor cannot harvest")
	npc.position = [point.x,point.y]
	check(not bool(sim.farming.harvest_for_actor(sim,"missing",cell).success),"Unknown actor cannot harvest")
	npc.work_options.harvest = false
	check(not bool(sim.farming.harvest_for_actor(sim,ID,cell).success),"Actor work permission required")
	npc.work_options.harvest = true
	var energy := float(npc.needs.energy)
	var result: Dictionary = sim.farming.harvest_for_actor(sim,ID,cell)
	check(bool(result.success) and result.item_id=="core:carrot" and int(result.amount)==1 and result.created_drop_ids.size()==1,"One physical carrot created")
	check(is_equal_approx(float(npc.needs.energy),energy-float(sim.needs.config.work_energy_cost)),"One successful NPC harvest pays ordinary work energy")
	before = JSON.stringify(sim.export_state())
	check(not bool(sim.farming.harvest_for_actor(sim,ID,cell).success),"Repeated harvest fails")
	check(JSON.stringify(sim.export_state())==before,"Repeat neither yields nor spends energy")
	check(bool(World.new(sim.export_state()).get_farm_bed(cell).shared_harvest),"Sharing survives reload after harvest")
	for crop: Dictionary in sim.farming.catalog.crops:
		var bed: Dictionary = sim.farming.bed_at(sim,cell)
		bed.crop_id = crop.id; bed.growth = int(crop.growth_minutes); bed.harvests = 0
		result = sim.farming.harvest_for_actor(sim,"core:player",cell)
		check(bool(result.success) and int(result.amount)==int(crop.yield),"Catalog yield "+String(crop.id))
		check(String(bed.crop_id)==(String(crop.id) if crop.harvest_mode=="perennial" else ""),"Catalog harvest mode "+String(crop.id))
		check(int(bed.growth)==0 and int(bed.harvests)==1,"Harvest resets growth once")
	print("PASS: crop permissions, atomic actor harvest, modes and migration" if failures==0 else "FAIL: crop harvest rules")
	quit(0 if failures==0 else 1)
