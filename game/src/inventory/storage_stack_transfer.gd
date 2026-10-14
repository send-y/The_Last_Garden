extends RefCounted

const Rules := preload("res://src/inventory/inventory_placement_rules.gd")
const Packer := preload("res://src/inventory/inventory_auto_packer.gd")
const Changes := preload("res://src/inventory/inventory_layout_changes.gd")

# Plan against copies; commit only once some resource can actually be stored.
static func store_stack(sim, cell: Vector2i, selected: Dictionary, current_layout: Array,
	origin: Vector2i, rotation: int) -> Dictionary:
	var item_id := String(selected.item_id)
	var remaining := int(selected.amount)
	var items: Array = sim.state.storage_items.duplicate(true)
	var used := {}
	var grid: Vector2i = sim.get_storage_grid_size(cell)
	var next_index := 0
	var targets: Array[Dictionary] = []
	var pointed: Dictionary = {}
	for record: Dictionary in items:
		if record.cell != [cell.x, cell.y]: continue
		var id := String(record.item_id)
		var at := Vector2i(int(record.origin[0]),int(record.origin[1]))
		var shape: Array[Vector2i] = sim.content.item_footprint(id,int(record.rotation))
		Rules.occupy(shape,at,used,String(record.placement_id))
		if id == item_id:
			next_index = maxi(next_index,int(record.stack_index)+1)
			if int(record.amount) < sim.content.item_max_stack(id): targets.append(record)
		if shape.has(origin-at): pointed = record
	var exact := origin.x >= 0 and origin.y >= 0
	if exact and not pointed.is_empty():
		if String(pointed.item_id) != item_id or int(pointed.amount) >= sim.content.item_max_stack(item_id):
			return sim._emit_result(false,"ui.storage.failure.no_capacity")
		targets = [pointed]
	elif exact:
		targets.clear()
	for target: Dictionary in targets:
		var added := mini(remaining,sim.content.item_max_stack(item_id)-int(target.amount))
		target.amount = int(target.amount)+added
		remaining -= added
		if remaining == 0: break
	# Exact drops onto a stack leave excess in the source, never move it elsewhere.
	if remaining > 0 and (not exact or pointed.is_empty()):
		var fit: Dictionary
		if exact:
			var turns := posmod(rotation,4)
			if Rules.can_place(sim.content.item_footprint(item_id,turns),origin,used,grid.x,grid.y): fit = {"origin":origin,"rotation":turns}
			else: fit = {}
		else: fit = Rules.find_first_fit(sim.content.item_footprint(item_id),used,grid.x,grid.y)
		var at: Vector2i = fit.get("origin",Rules.INVALID_ORIGIN)
		if at != Rules.INVALID_ORIGIN:
			items.append({"cell":[cell.x,cell.y],"item_id":item_id,"amount":remaining,"origin":[at.x,at.y],"rotation":int(fit.rotation),"stack_index":next_index,"placement_id":"%s:%d" % [item_id,next_index]})
			remaining = 0
	var moved := int(selected.amount)-remaining
	if moved == 0: return sim._emit_result(false,"ui.storage.failure.no_capacity")
	var candidate: Dictionary = sim.get_inventory()
	candidate[item_id] = int(candidate[item_id])-moved
	var layout: Array = current_layout
	if remaining == 0: layout = Changes.without_stack(layout,item_id,int(selected.stack_index))
	else:
		layout = layout.duplicate(true)
		for entry: Dictionary in layout:
			if String(entry.item_id) == item_id and int(entry.stack_index) == int(selected.stack_index): entry.amount = remaining
	var packed := Packer.pack_with_layout(candidate,sim.content,layout,4,4)
	if not packed.overflow.is_empty(): return sim._emit_result(false,"ui.inventory.move.invalid")
	sim.state.storage_items = items
	sim.state.inventory = sim._inventory_counts_without_instances(candidate)
	sim.state.inventory_layout = packed.layout
	var result: Dictionary = sim._emit_result(true,"ui.storage.transfer.stored",true,true,{"amount":moved,"item":LocalizedText.resolve(sim.content.item_label_key(item_id))})
	result.remaining_source = remaining
	result.amount = moved
	return result
