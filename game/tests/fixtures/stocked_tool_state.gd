extends RefCounted

# Explicit equipment for pre-existing subsystem tests, separate from the ordinary start.
static func prepare(state: Dictionary) -> Dictionary:
	var tools := [
		["core:bucket", 1, [22,22], [2,0]],
		["core:pickaxe", 3, [23,22], [0,0]],
		["core:hoe", 4, [22,23], [0,0]],
		["core:mallet", 5, [24,23], [0,0]],
	]
	for entry: Array in tools:
		var exists := false
		for instance: Dictionary in state.item_instances:
			if String(instance.item_id) == String(entry[0]): exists = true
		if exists: continue
		var id := "core:item_instance_%06d" % int(entry[1])
		var placement := String(entry[0]) + ":0"
		state.item_instances.append({"instance_id":id,"item_id":entry[0],"state":{"charges":0} if entry[0] == "core:bucket" else {},"location":{"kind":"storage","id":placement}})
		state.storage_items.append({"cell":entry[2].duplicate(),"item_id":entry[0],"amount":1,"origin":entry[3].duplicate(),"rotation":0,"stack_index":0,"placement_id":placement,"instance_id":id})
	state.next_item_instance_serial = maxi(int(state.next_item_instance_serial), 6)
	state.structures.append({"building_id":"core:wood_floor","cell":[24,23]})
	state.storage_zones[0].cells.append([24,23])
	return state
