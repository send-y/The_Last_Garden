extends Node
const Main := preload("res://src/main/main.tscn")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Connections := preload("res://src/construction/wall_connections.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames() -> void:
	for i: int in range(4): await get_tree().process_frame
func shift_click(world: Node2D, at: Vector2) -> void:
	var point := world.get_global_transform_with_canvas()*at
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_RIGHT
		event.shift_pressed = true
		event.pressed = pressed
		get_viewport().push_input(event,true)
func sprite_at(layer, cell: Vector2i) -> Sprite2D:
	for sprite: Sprite2D in layer._structure_sprites:
		if sprite.get_meta("cell") == cell: return sprite
	return null
func _ready() -> void:
	get_tree().create_timer(35).timeout.connect(func(): get_tree().quit(1))
	Session.set_mechanics_lab_active(true)
	var state: Dictionary = Fixture.create().export_state()
	for structure: Dictionary in state.structures:
		if structure.building_id == "core:wood_door": structure.open = false
	Session.apply_debug_state(state,"world editing",true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var world = main.get_node("World")
	var layer = main.get_node("World/StructureLayer")
	var sim = Session.simulation
	var door := Vector2i(39,32)
	var p := Content.cell_center(38,32)
	sim.set_player_position(p)
	main.get_node("Player").apply_loaded_position()
	var count: int = layer._collision_bodies.size()
	await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters2D.create(Content.cell_center(38,32),Content.cell_center(40,32),2)
	check(not world.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(),"Closed doorway really blocks physics ray")
	world.select_at_world_position(Content.cell_center(door.x,door.y))
	world.interact_with_selection()
	await frames()
	check(sim._find_structure([39,32]).open,"Actual world interaction opens door")
	check(not sprite_at(layer,door).visible,"Open door leaf must disappear instead of leaving a thin plank")
	check(layer._collision_bodies.size() == count-1,"Open door removes actual physics collision")
	await get_tree().physics_frame
	check(world.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(),"Open doorway is physically traversable")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("D:/The_Last_Garden/artifacts/world-editing-2026-10-09/door-open.png")
	world.interact_with_selection()
	await frames()
	check(not sim._find_structure([39,32]).open and layer._collision_bodies.size() == count,"Closing restores physics collision")
	check(sprite_at(layer,door).visible,"Closed door leaf becomes visible again")
	check(sim.housing.room_valid(sim,Fixture.ROOM),"Closed and open doors preserve room enclosure")
	check(is_equal_approx(sprite_at(layer,Vector2i(39,31)).rotation,PI/2),"Side wall follows vertical connection including door")
	check(is_zero_approx(sprite_at(layer,Vector2i(41,29)).rotation),"Top wall follows horizontal connections")
	check(int(sprite_at(layer,Vector2i(39,29)).get_meta("connections")) == 3,"Corner has both connected arms")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("D:/The_Last_Garden/artifacts/world-editing-2026-10-09/door-closed.png")
	# Removing the wall over a floor must preserve the floor and update neighbours.
	var at := Vector2i(43,36)
	sim.state.structures.append({"building_id":"core:wood_floor","cell":[43,36]})
	sim.state.structures.append({"building_id":"core:wood_wall","cell":[43,36]})
	sim.state.structures.append({"building_id":"core:wood_wall","cell":[43,37]})
	Session.state_changed.emit()
	await frames()
	check(is_equal_approx(sprite_at(layer,at).rotation,PI/2),"New neighbour turns a wall vertically")
	sim.set_player_position(Content.cell_center(44,36))
	main.get_node("Player").apply_loaded_position()
	await frames()
	var cursor = main.get_node("ConstructionCursor")
	cursor.set_build_mode_active(true)
	shift_click(world,Content.cell_center(at.x,at.y))
	await frames()
	cursor.set_build_mode_active(false)
	check(sim._find_structure([43,36]).building_id == "core:wood_floor","Removal chooses wall before its underlying floor")
	check(is_zero_approx(sprite_at(layer,Vector2i(43,37)).rotation),"Neighbour returns to default orientation after connection removed")
	var bush: Dictionary = sim.get_surface_berry_bushes()[0]
	sim._add_item("core:axe",1)
	sim.select_inventory_item("core:axe",sim.get_inventory_instance_id("core:axe",0))
	sim.set_player_position(bush.position)
	main.get_node("Player").apply_loaded_position()
	await frames()
	shift_click(world,bush.position)
	await frames()
	for view in world._interactables:
		if view.object_id == bush.id: check(not view.visible,"Uprooting hides actual bush view")
	if failures == 0: print("PASS: Door interaction, collision, wall connections, removal and bush visuals")
	get_tree().quit(1 if failures else 0)
