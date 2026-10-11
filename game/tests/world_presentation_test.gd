extends Node
const Main := preload("res://src/main/main.tscn")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
const Catalog := preload("res://src/characters/npc_catalog.gd")
class ObservedCatalog extends Catalog:
	var roster_copies := 0
	func get_definitions() -> Array[Dictionary]:
		roster_copies += 1
		return super.get_definitions()
const SaveStore := preload("res://src/save/first_night_save_store.gd")
var failures := 0
func _ready() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func frames() -> void:
	for _frame: int in range(5): await get_tree().process_frame
func calls(label: String) -> int:
	return int(Trace.snapshot().spans.get(label,{}).get("calls",0))
func run() -> void:
	Session._save_store = SaveStore.new("user://world_presentation_test.json")
	Session.set_paused(true,false)
	var fixture = Fixture.create()
	var soil := Vector2i(-1,-1)
	for y: int in range(27,45):
		for x: int in range(20,45):
			if fixture.farming._soil_allowed(fixture,Vector2i(x,y)):
				soil = Vector2i(x,y)
				break
		if soil.x >= 0: break
	check(soil.x >= 0,"Fixture has arable ground outside structures and resources")
	var state: Dictionary = fixture.export_state()
	state.farming.beds = [{"cell":[soil.x,soil.y],"crop_id":"","growth":0,"wet_until":int(state.elapsed_game_minutes)+1,"last_update":state.elapsed_game_minutes,"harvests":0}]
	Session._replace_simulation(state)
	Session._publish_reloaded_state(true)
	check(Session.get_farm_beds().size() == 1,"Fixture contains one actual valid wet soil bed")
	var observed := ObservedCatalog.new()
	observed._definitions_by_id = Session.simulation.npc_catalog._definitions_by_id.duplicate(true)
	observed._definition_order = Session.simulation.npc_catalog._definition_order.duplicate()
	Session.simulation.npc_catalog = observed
	var game := Main.instantiate()
	add_child(game)
	await frames()
	var world = game.get_node("World")
	observed.roster_copies = 0
	Trace.reset()
	Trace.enabled = true
	Session.simulation.state.npcs[Fixture.NPC].needs.energy -= 1.0
	Session.state_changed.emit()
	await frames()
	check(observed.roster_copies == 0,"Refreshing an unchanged NPC population does not clone the complete catalog to count its members")
	check(calls("scene.world_draw") == 0,"NPC needs never rebuild static terrain")
	check(calls("scene.world_storage_draw") == 0,"NPC needs never redraw stored items")
	check(calls("scene.structure_refresh") == 0,"NPC needs never copy/rebuild structure presentation")
	Trace.reset()
	for i: int in range(3):
		Session.simulation.state.npcs[Fixture.NPC].needs.energy -= 1.0
		Session.state_changed.emit()
		Session.message_emitted.emit("Событие %d" % i,true)
	Session.simulation.state.minute_of_day += 1
	Session.time_changed.emit()
	await frames()
	check(calls("scene.world_state_refresh") == 1,"Multiple changes before a frame refresh the world presentation once")
	check(calls("scene.hud_refresh") == 1,"Multiple state/time/message events refresh HUD once")
	var hud = game.get_node("Hud/HudRoot")
	check(hud._time_label.text.contains(Session.get_time_text()),"Combined refresh displays the final current time")
	check(hud._message_label.text == "Событие 2","Combined refresh preserves the latest player message")
	var layers: Variant = world.get("_presentation_layers")
	check(layers is Dictionary,"Independent world presentation layers exist")
	if layers is Dictionary:
		Trace.reset()
		world.select_at_world_position(Content.cell_center(41,31))
		await frames()
		check(calls("scene.world_selection_draw") == 1 and calls("scene.world_draw") == 0,"Selecting a cell refreshes selection without redrawing terrain")
		Trace.reset()
		Fixture.stock(Session.simulation,5)
		await frames()
		check(calls("scene.world_storage_draw") == 1 and calls("scene.world_draw") == 0,"Actual inventory transfer refreshes stored items only")
		check(not world._storage_layouts.is_empty(),"Stored goods have actual indexed visual placements")
		for cell: Vector2i in world._storage_layouts:
			check(world._storage_layouts[cell] == Session.get_storage_layout(cell),"Indexed visual placements equal the authoritative storage report")
		Trace.reset()
		layers.storage.queue_redraw()
		await frames()
		check(calls("scene.world_storage_draw") == 1,"A requested storage redraw still displays the existing goods")
		check(calls("scene.storage_icon_load") == 0,"Redrawing existing goods reuses retained icon textures without resource loading")
		Trace.reset()
		Session.simulation.advance_minutes(1)
		await frames()
		check(calls("scene.world_farm_draw") == 1 and calls("scene.world_draw") == 0,"Wet soil expiry refreshes farms without redrawing terrain")
		var fresh: Dictionary = Session.get_state()
		fresh.storage_items = []
		Trace.reset()
		Session._replace_simulation(fresh)
		Session._publish_reloaded_state(true)
		await frames()
		check(world._storage_layouts.is_empty(),"Reload cannot retain goods from the previous world")
		check(calls("scene.world_draw") == 1,"Reload explicitly refreshes the static world")
	Trace.enabled = false
	print("WORLD_PRESENTATION: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
