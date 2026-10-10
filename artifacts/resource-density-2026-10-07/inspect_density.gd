extends SceneTree

const Catalog := preload("res://src/content/resource_node_catalog.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Water := preload("res://src/world/water_map.gd")

func _initialize() -> void:
	var seeds: Array[int] = [247061, 4127]
	for seed_value: int in range(100, 200):
		seeds.append(seed_value)
	for seed_value: int in seeds:
		var boulders := Catalog.generate_surface_boulders(seed_value)
		var trees := Catalog.generate_surface_trees(seed_value, boulders)
		if boulders.size() < 90 or boulders.size() > 110 or trees.size() < 180 or trees.size() > 220:
			fail("count bounds for seed %d" % seed_value)
			return
		for index: int in range(Catalog.STARTER_BOULDER_COUNT):
			if not Catalog.STARTER_BOULDER_REGION.has_point(cell_of(boulders[index])):
				fail("missing starter stone for seed %d" % seed_value)
				return
		for index: int in range(Catalog.STARTER_TREE_COUNT):
			if not Catalog.STARTER_TREE_REGION.has_point(cell_of(trees[index])):
				fail("missing starter tree for seed %d" % seed_value)
				return
		var occupied: Dictionary = {}
		for nodes: Array in [boulders, trees]:
			for node: Dictionary in nodes:
				var cell := cell_of(node)
				if Water.contains_cell(cell) or Catalog.is_reserved_cell(cell) or occupied.has(cell):
					fail("blocked or overlapping resource for seed %d" % seed_value)
					return
				occupied[cell] = true
		if seed_value == 247061:
			var spawn := Vector2(784.0, 944.0)
			var nearby: Array[int] = [0, 0]
			var sets: Array = [trees, boulders]
			for kind_index: int in range(sets.size()):
				for node: Dictionary in sets[kind_index]:
					var cell := cell_of(node)
					if spawn.distance_to(Content.cell_center(cell.x, cell.y)) < 20.0 * Content.CELL_SIZE:
						nearby[kind_index] += 1
			print("Default seed: %d trees, %d boulders; within 20 cells: %d trees, %d boulders" % [trees.size(), boulders.size(), nearby[0], nearby[1]])
	print("PASS: %d seeds have expanded totals, complete starter regions, dry unreserved resource cells, and no shared tree/stone cells" % seeds.size())
	quit(0)

func cell_of(node: Dictionary) -> Vector2i:
	var cell := node["cell"] as Array
	return Vector2i(int(cell[0]), int(cell[1]))

func fail(message: String) -> void:
	push_error(message)
	quit(1)
