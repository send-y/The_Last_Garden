extends RefCounted
const Packer := preload("res://src/inventory/inventory_auto_packer.gd")
const Rules := preload("res://src/inventory/inventory_placement_rules.gd")
const Exchange := preload("res://src/inventory/inventory_storage_exchange.gd")

static func take(sim, item: Dictionary, storage_index: int, origin: Vector2i, rotation: int) -> Dictionary:
	var id := String(item.item_id)
	var original_amount := int(item.amount)
	var remaining := original_amount
	var current := Packer.pack_with_layout(sim.get_inventory(),sim.content,sim.state.inventory_layout,4,4)
	var layout: Array = current.layout.duplicate(true)
	var pointed := Exchange.at(current.placements,origin,sim.content)
	var exact := origin.x >= 0 and origin.y >= 0
	var occupied := {}
	var next_index := 0
	for placement: Dictionary in current.placements:
		Rules.occupy(placement.footprint,placement.origin,occupied,String(placement.placement_id))
		if placement.item_id == id: next_index = maxi(next_index,int(placement.stack_index)+1)
	for entry: Dictionary in layout:
		if entry.item_id != id: continue
		if exact and (pointed.is_empty() or int(entry.stack_index) != int(pointed.stack_index)): continue
		var moved := mini(remaining,sim.content.item_max_stack(id)-int(entry.amount))
		entry.amount = int(entry.amount)+moved
		remaining -= moved
		if remaining == 0: break
	if remaining > 0 and (not exact or pointed.is_empty()):
		var fit: Dictionary = {}
		if exact:
			var turns := posmod(rotation,4) if rotation >= 0 else 0
			if Rules.can_place(sim.content.item_footprint(id,turns),origin,occupied,4,4): fit = {"origin":origin,"rotation":turns}
		else: fit = Rules.find_first_fit(sim.content.item_footprint(id),occupied,4,4)
		if not fit.is_empty() and fit.origin != Rules.INVALID_ORIGIN:
			layout.append({"item_id":id,"stack_index":next_index,"amount":remaining,"origin":[fit.origin.x,fit.origin.y],"rotation":int(fit.rotation)})
			remaining = 0
	var moved := original_amount-remaining
	if moved <= 0: return sim._emit_result(false,"ui.storage.failure.inventory_full")
	var candidate: Dictionary = sim.get_inventory()
	candidate[id] = int(candidate.get(id,0))+moved
	var packed := Packer.pack_with_layout(candidate,sim.content,layout,4,4)
	if not packed.requested_layout_valid or not packed.overflow.is_empty(): return sim._emit_result(false,"ui.storage.failure.inventory_full")
	sim.state.inventory = sim._inventory_counts_without_instances(candidate)
	sim.state.inventory_layout = packed.layout
	if remaining == 0: sim.state.storage_items.remove_at(storage_index)
	else: item.amount = remaining
	preload("res://src/crafting/recipe_learning.gd").discover(sim,id)
	var result: Dictionary = sim._emit_result(true,"ui.storage.transfer.taken",true,true,{"amount":moved,"item":LocalizedText.resolve(sim.content.item_label_key(id))})
	result.amount = moved
	result.remaining_source = remaining
	return result
