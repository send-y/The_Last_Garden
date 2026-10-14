extends RefCounted

static func build() -> Dictionary:
	var result := preload("res://src/dev/npc_crop_harvest_scenario.gd").build()
	var sim = result.simulation
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	sim.set_npc_work_enabled(String(npc.id),"sow",true)
	for bed: Dictionary in sim.state.farming.beds:
		if not bool(bed.shared_harvest): continue
		bed.planned_crop_id = String(bed.crop_id)
		bed.maintain_crop = true
		bed.crop_id = ""; bed.growth = 0
	# Explicitly synthetic stock: one potato bed has seed; strawberry requires forage.
	var values: Array = sim.state.storage_zones[0].cells[0]
	var cell := Vector2i(int(values[0]),int(values[1]))
	var at: Vector2 = sim.content.cell_center(cell.x,cell.y)
	npc.position = [at.x,at.y]
	preload("res://src/npc_work/npc_work_supplies.gd").store(sim,npc,cell,"core:potato_seed",1)
	result.state = sim.export_state()
	return result
