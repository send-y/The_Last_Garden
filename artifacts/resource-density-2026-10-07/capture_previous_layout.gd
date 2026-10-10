extends SceneTree

const Catalog := preload("res://src/content/resource_node_catalog.gd")

func _initialize() -> void:
	var seed_value := 247061
	var boulders := Catalog.generate_surface_boulders(seed_value, 2)
	var trees := Catalog.generate_surface_trees(seed_value, boulders, 2)
	var berries := Catalog.generate_berry_bushes(seed_value, boulders, trees, 2)
	var output := FileAccess.open("res://tests/fixtures/resources_layout_2_seed_247061.json", FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify({"seed": seed_value, "resource_nodes": boulders, "tree_nodes": trees, "berry_bushes": berries}, "\t") + "\n")
	output.close()
	print("Captured pre-change layout 2: %d trees, %d boulders, %d bushes" % [trees.size(), boulders.size(), berries.size()])
	quit(0)
