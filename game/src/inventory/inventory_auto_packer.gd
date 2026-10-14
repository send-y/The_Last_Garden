class_name InventoryAutoPacker
extends RefCounted

const PlacementRules := preload(
	"res://src/inventory/inventory_placement_rules.gd"
)


static func pack(
	inventory: Dictionary,
	content_data: FirstNightContent,
	columns: int = 4,
	rows: int = 4
) -> Dictionary:
	return pack_with_layout(inventory, content_data, [], columns, rows)


static func pack_with_layout(
	inventory: Dictionary,
	content_data: FirstNightContent,
	preferred_layout: Array,
	columns: int = 4,
	rows: int = 4
) -> Dictionary:
	var placements: Array[Dictionary] = []
	var occupied_cells: Dictionary = {}
	var overflow: Dictionary = {}
	var stack_indices: Dictionary = {}
	var requested_layout_valid := true
	var reserved_fits: Dictionary = {}
	var amounts_by_item := {}
	for item_id: String in content_data.item_ids():
		amounts_by_item[item_id] = preload("res://src/inventory/inventory_stack_amounts.gd").partitions(item_id,maxi(0,int(inventory.get(item_id,0))),content_data.item_max_stack(item_id),preferred_layout,content_data.item_is_instance_based(item_id))
	# Reserve every surviving manual placement before fitting any new stack.
	for preference_variant: Variant in preferred_layout:
		if typeof(preference_variant) != TYPE_DICTIONARY:
			continue
		var preference := preference_variant as Dictionary
		var item_id := String(preference.get("item_id", ""))
		if not content_data.has_item(item_id):
			continue
		var stack_index := int(preference.get("stack_index", -1))
		var stack_count: int = amounts_by_item[item_id].size()
		if stack_index < 0 or stack_index >= stack_count:
			continue
		var key := "%s:%d" % [item_id, stack_index]
		var raw_origin: Variant = preference.get("origin", [])
		if reserved_fits.has(key) or typeof(raw_origin) != TYPE_ARRAY or (raw_origin as Array).size() != 2:
			requested_layout_valid = false
			continue
		var origin := Vector2i(int(raw_origin[0]), int(raw_origin[1]))
		var rotation := posmod(int(preference.get("rotation", 0)), 4)
		var footprint := content_data.item_footprint(item_id, rotation)
		if not PlacementRules.can_place(footprint, origin, occupied_cells, columns, rows):
			requested_layout_valid = false
			continue
		reserved_fits[key] = {"origin": origin, "rotation": rotation}
		PlacementRules.occupy(footprint, origin, occupied_cells, key)

	for item_id: String in content_data.item_ids():
		var remaining: int = maxi(
			0,
			int(inventory.get(item_id, 0))
		)

		while remaining > 0:
			var stack_index := int(stack_indices.get(item_id, 0))
			stack_indices[item_id] = stack_index + 1
			var stack_amount: int = amounts_by_item[item_id][stack_index]
			var base_footprint: Array[Vector2i] = (
				content_data.item_footprint(item_id)
			)
			var fit: Dictionary = reserved_fits.get("%s:%d" % [item_id, stack_index], {})
			if fit.is_empty():
				fit = PlacementRules.find_first_fit(
					base_footprint,
					occupied_cells,
					columns,
					rows
				)
			var origin: Vector2i = fit.get(
				"origin",
				PlacementRules.INVALID_ORIGIN
			)

			if origin == PlacementRules.INVALID_ORIGIN:
				overflow[item_id] = remaining
				break

			var rotation: int = int(
				fit.get("rotation", 0)
			)
			var footprint: Array[Vector2i] = (
				content_data.item_footprint(
					item_id,
					rotation
				)
			)
			var placement_id := "%s:%d" % [
				item_id,
				stack_index,
			]

			placements.append({
				"placement_id": placement_id,
				"item_id": item_id,
				"amount": stack_amount,
				"origin": origin,
				"rotation": rotation,
				"footprint": footprint,
				"stack_index": stack_index,
			})

			PlacementRules.occupy(
				footprint,
				origin,
				occupied_cells,
				placement_id
			)

			remaining -= stack_amount

	return {
		"placements": placements,
		"occupied_cells": occupied_cells,
		"overflow": overflow,
		"layout": _layout_from_placements(placements),
		"requested_layout_valid": requested_layout_valid,
	}


static func _layout_from_placements(placements: Array[Dictionary]) -> Array[Dictionary]:
	var layout: Array[Dictionary] = []
	for placement: Dictionary in placements:
		var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
		layout.append({
			"item_id": String(placement.get("item_id", "")),
			"stack_index": int(placement.get("stack_index", 0)),
			"origin": [origin.x, origin.y],
			"rotation": int(placement.get("rotation", 0)),
			"amount": int(placement.amount),
		})
	return layout
