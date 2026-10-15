extends RefCounted
const Rules := preload("res://src/inventory/inventory_placement_rules.gd")
const Packer := preload("res://src/inventory/inventory_auto_packer.gd")

static func at(placements: Array, cell: Vector2i, content) -> Dictionary:
	for record: Dictionary in placements:
		var raw: Variant = record.get("origin",Vector2i.ZERO)
		var origin: Vector2i = raw if raw is Vector2i else Vector2i(int(raw[0]),int(raw[1]))
		if content.item_footprint(String(record.item_id),int(record.rotation)).has(cell-origin): return record
	return {}

# Both placements and ownership changes are planned before any mutation.
static func exchange(sim, cell: Vector2i, bag: Dictionary, stock: Dictionary,
	bag_origin: Vector2i, bag_rotation: int, stock_origin: Vector2i, stock_rotation: int,
	from_storage: bool) -> Dictionary:
	var bag_id := String(bag.item_id)
	var stock_id := String(stock.item_id)
	var bag_shape: Array[Vector2i] = sim.content.item_footprint(bag_id,bag_rotation)
	var stock_shape: Array[Vector2i] = sim.content.item_footprint(stock_id,stock_rotation)
	if bag_shape.size() != stock_shape.size(): return {"success":false}
	for offset: Vector2i in bag_shape:
		if not stock_shape.has(offset): return {"success":false}
	var bag_instance := String(bag.get("instance_id",""))
	var stock_instance := String(stock.get("instance_id",""))
	if sim.content.item_is_instance_based(bag_id) and sim.get_item_instance(bag_instance).get("location",{}).get("kind","") != "inventory": return {"success":false}
	if sim.content.item_is_instance_based(stock_id) and sim.get_item_instance(stock_instance).get("location",{}).get("kind","") != "storage": return {"success":false}
	if not bag_instance.is_empty() and String(sim.get_item_instance(bag_instance).get("item_id","")) != bag_id: return {"success":false}
	if not stock_instance.is_empty() and (String(sim.get_item_instance(stock_instance).get("item_id","")) != stock_id or String(sim.get_item_instance(stock_instance).location.get("id","")) != String(stock.placement_id)): return {"success":false}
	var placements: Array = sim.get_inventory_placements()
	var layout: Array[Dictionary] = []
	var used := {}
	var next_bag_index := 0
	var future_indices := {}
	var counts := {}
	for instance: Dictionary in sim.state.item_instances:
		var id := String(instance.instance_id)
		if id == bag_instance: continue
		if id != stock_instance and String(instance.location.kind) != "inventory": continue
		var item := String(instance.item_id)
		future_indices[id] = int(counts.get(item,0))
		counts[item] = int(counts.get(item,0))+1
	for placement: Dictionary in placements:
		if placement.item_id == bag_id and int(placement.stack_index) == int(bag.stack_index): continue
		var origin: Vector2i = placement.origin
		var index := int(placement.stack_index)
		if placement.item_id == bag_id and index > int(bag.stack_index): index -= 1
		if placement.has("instance_id"): index = int(future_indices[String(placement.instance_id)])
		layout.append({"item_id":String(placement.item_id),"stack_index":index,"amount":int(placement.amount),"origin":[origin.x,origin.y],"rotation":int(placement.rotation)})
		Rules.occupy(placement.footprint,origin,used,String(placement.placement_id))
		if placement.item_id == stock_id: next_bag_index = maxi(next_bag_index,index+1)
	if not stock_instance.is_empty(): next_bag_index = int(future_indices[stock_instance])
	if not Rules.can_place(stock_shape,bag_origin,used,4,4): return {"success":false}
	layout.append({"item_id":stock_id,"stack_index":next_bag_index,"amount":int(stock.amount),"origin":[bag_origin.x,bag_origin.y],"rotation":stock_rotation})
	var candidate: Dictionary = sim.get_inventory()
	candidate[bag_id] = int(candidate.get(bag_id,0))-int(bag.amount)
	candidate[stock_id] = int(candidate.get(stock_id,0))+int(stock.amount)
	var packed := Packer.pack_with_layout(candidate,sim.content,layout,4,4)
	if not packed.requested_layout_valid or not packed.overflow.is_empty() or packed.placements.size() != layout.size(): return {"success":false}
	var storage_items: Array = sim.state.storage_items.duplicate(true)
	var storage_used := {}
	var next_stock_index := 0
	var found := -1
	for index: int in range(storage_items.size()):
		var record: Dictionary = storage_items[index]
		if record.cell != [cell.x,cell.y]: continue
		if String(record.placement_id) == String(stock.placement_id): found = index; continue
		var origin := Vector2i(int(record.origin[0]),int(record.origin[1]))
		Rules.occupy(sim.content.item_footprint(String(record.item_id),int(record.rotation)),origin,storage_used,String(record.placement_id))
		if record.item_id == bag_id: next_stock_index = maxi(next_stock_index,int(record.stack_index)+1)
	var size: Vector2i = sim.get_storage_grid_size(cell)
	if found < 0 or not Rules.can_place(bag_shape,stock_origin,storage_used,size.x,size.y): return {"success":false}
	var new_key := "%s:%d" % [bag_id,next_stock_index]
	var replacement := {"cell":[cell.x,cell.y],"item_id":bag_id,"amount":int(bag.amount),"origin":[stock_origin.x,stock_origin.y],"rotation":bag_rotation,"stack_index":next_stock_index,"placement_id":new_key}
	if not bag_instance.is_empty(): replacement.instance_id = bag_instance
	storage_items[found] = replacement
	sim.state.storage_items = storage_items
	if not bag_instance.is_empty():
		sim._set_instance_location(bag_instance,"storage",new_key)
		sim._clear_hotbar_instance(bag_instance,true)
	if not stock_instance.is_empty(): sim._set_instance_location(stock_instance,"inventory")
	sim.state.inventory = sim._inventory_counts_without_instances(candidate)
	sim.state.inventory_layout = packed.layout
	var result: Dictionary = sim._emit_result(true,"ui.inventory.move.success",true,true)
	result.exchanged = true
	result.held_item_id = bag_id if from_storage else stock_id
	result.held_instance_id = bag_instance if from_storage else stock_instance
	result.held_stack_index = next_stock_index if from_storage else next_bag_index
	return result
