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

	for item_id: String in content_data.item_ids():
		var remaining: int = maxi(
			0,
			int(inventory.get(item_id, 0))
		)

		while remaining > 0:
			var stack_index := int(stack_indices.get(item_id, 0))
			stack_indices[item_id] = stack_index + 1
			var stack_amount: int = mini(
				remaining,
				content_data.item_max_stack(item_id)
			)
			var base_footprint: Array[Vector2i] = (
				content_data.item_footprint(item_id)
			)
			var fit: Dictionary = {}
			for preference_variant: Variant in preferred_layout:
				if typeof(preference_variant) != TYPE_DICTIONARY:
					continue
				var preference: Dictionary = preference_variant as Dictionary
				if (
					String(preference.get("item_id", "")) != item_id
					or int(preference.get("stack_index", -1)) != stack_index
				):
					continue
				var raw_origin: Variant = preference.get("origin", [])
				if typeof(raw_origin) == TYPE_ARRAY and (raw_origin as Array).size() == 2:
					var preferred_origin := Vector2i(
						int((raw_origin as Array)[0]),
						int((raw_origin as Array)[1])
					)
					var preferred_rotation := posmod(int(preference.get("rotation", 0)), 4)
					var preferred_footprint := content_data.item_footprint(item_id, preferred_rotation)
					if PlacementRules.can_place(
						preferred_footprint, preferred_origin,
						occupied_cells, columns, rows
					):
						fit = {"origin": preferred_origin, "rotation": preferred_rotation}
						break
				requested_layout_valid = false
				break
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
		})
	return layout
