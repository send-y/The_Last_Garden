extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
func _initialize() -> void:
	var sim = World.new()
	var objects: Array = sim.content.interactables()
	objects.append_array(sim.get_surface_trees())
	objects.append_array(sim.get_surface_boulders())
	objects.append_array(sim.get_surface_berry_bushes())
	for object: Dictionary in objects:
		var p: Vector2 = object.get("position",Vector2(-999,-999))
		var cell := Vector2i(floori(p.x/32),floori(p.y/32))
		if cell == Vector2i(26,2) or cell == Vector2i(26,20) or cell == Vector2i(26,23):
			print("CELL_OBJECT ",cell," ",object)
		var bounds := Rect2(p-Vector2(16,16),Vector2(32,32))
		if String(object.get("presentation_id","")) == "surface_tree": bounds = Rect2(p+Vector2(-36,-60),Vector2(72,80))
		elif String(object.get("presentation_id","")) == "surface_boulder": bounds = Rect2(p-Vector2(32,32),Vector2(64,64))
		if bounds.intersects(Rect2(Vector2(26,2)*32,Vector2(32,32))): print("CELL_RENDER_OVERLAP (26,2) ",object)
	print("Inspection finished; no output for a coordinate means no starting object at that exact cell.")
	quit()
