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
	var placements: Array[Dictionary] = []
	var occupied_cells: Dictionary = {}
	var overflow: Dictionary = {}
	var placement_index: int = 0

	for item_id: String in content_data.item_ids():
		var remaining: int = maxi(
			0,
			int(inventory.get(item_id, 0))
		)

		while remaining > 0:
			var stack_amount: int = mini(
				remaining,
				content_data.item_max_stack(item_id)
			)
			var base_footprint: Array[Vector2i] = (
				content_data.item_footprint(item_id)
			)
			var fit: Dictionary = PlacementRules.find_first_fit(
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
				placement_index,
			]

			placements.append({
				"placement_id": placement_id,
				"item_id": item_id,
				"amount": stack_amount,
				"origin": origin,
				"rotation": rotation,
				"footprint": footprint,
			})

			PlacementRules.occupy(
				footprint,
				origin,
				occupied_cells,
				placement_id
			)

			remaining -= stack_amount
			placement_index += 1

	return {
		"placements": placements,
		"occupied_cells": occupied_cells,
		"overflow": overflow,
	}
