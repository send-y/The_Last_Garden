extends Node
const Main := preload("res://src/main/main.tscn")
const World := preload("res://src/simulation/world_simulation.gd")
const Save := preload("res://src/save/first_night_save_store.gd")
const Content := preload("res://src/content/first_night_content.gd")
const SAVE_PATH := "user://starting_pantry_integration_test.json"
var failures := 0
func _ready() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
func run() -> void:
	Session.set_mechanics_lab_active(false)
	Session.set_process(false)
	Session._save_store = Save.new(SAVE_PATH)
	Session._start_new_simulation()
	var sim = Session.simulation
	check(sim.state.item_instances.size() == 1 and sim.state.item_instances[0].item_id == "core:axe", "Ordinary world has exactly one wooden axe")
	check(sim.get_storage_zones().size() == 1 and sim.get_storage_zones()[0].cells.size() == 4, "Ordinary pantry still has four useful floor cells")
	for cell: Vector2i in World.STARTER_PANTRY_CELLS: check(sim.get_storage_grid_size(cell) == Vector2i(3,3), "Pantry floor has its real 3x3 storage")
	check(sim.should_hide_interactable("core:old_tools","tools"), "Legacy source cannot duplicate starter tools")
	sim.set_player_position(Content.cell_center(22,22))
	var main := Main.instantiate()
	add_child(main)
	await settle()
	var hud: FirstNightHud = main.get_node("Hud/HudRoot")
	hud.open_storage(Vector2i(22,22))
	await settle()
	check(hud._storage_panel.visible and hud._storage_panel._storage_grid._placements.size() == 1, "Warehouse UI shows only the actual starter axe")
	var axe: Dictionary = sim.state.storage_items[0]
	check(String(hud._storage_panel._storage_grid._placements[0].icon_path).ends_with("axe_wood.png"), "Starter icon matches primitive tier")
	hud._set_storage_open(false)
	check(Session.transfer_storage_stack_to_inventory(Vector2i(22,22),String(axe.placement_id)).success, "Starter axe enters the backpack physically")
	check(Session.assign_hotbar_slot(0,String(axe.instance_id)).success, "Starter axe can occupy a hotbar slot")
	hud.handle_hotbar_key(0)
	check(Session.get_active_item_instance().instance_id == axe.instance_id, "Hotbar selects the same physical axe")
	check(sim.try_pickup_item("core:wood",2).success, "Handcraft UI fixture discovers wood")
	hud.toggle_inventory()
	await settle()
	var button: Button = hud._inventory_panel.get_node("ContentMargin/ContentColumn/HandcraftButton")
	check(button.visible, "Backpack exposes handcraft entry")
	check(button.text == "Изготовить в руках", "Handcraft entry has its Russian translation")
	check(String(TranslationServer.translate("item.core.mallet.name")) == "Деревянная киянка", "New tool name has its Russian translation")
	button.pressed.emit()
	await settle()
	check(hud._crafting_panel.visible and not hud._inventory_panel.visible, "Handcraft opens its modal panel")
	var panel_rect := hud._crafting_panel.get_global_rect()
	check(get_viewport().get_visible_rect().encloses(panel_rect), "Handcraft panel fits the visible viewport")
	hud._crafting_panel.choose_recipe("core:make_mallet")
	await settle()
	check(not hud._crafting_panel.visible, "Choosing hand recipe closes the panel")
	for drop: Dictionary in sim.get_world_drops():
		if String(drop.item_id) == "core:mallet":
			sim.set_player_position(Vector2(float(drop.position[0]),float(drop.position[1])))
			check(sim.try_pickup_world_drop(String(drop.drop_id)).success, "Handmade mallet is recoverable through real pickup")
	check(not sim.get_inventory_instance_id("core:mallet",0).is_empty(), "Handcraft UI produces a real tool instance")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(restored.state.item_instances.size() == 2 and restored.get_item_instance(String(axe.instance_id)).item_id == "core:axe", "Reload preserves original axe and crafted mallet without duplication")
	if DisplayServer.get_name() != "headless":
		hud.toggle_inventory()
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/tool-gameplay-2026-10-13/starter-handcraft-ui.png"))
	for suffix: String in ["", ".bak", ".tmp"]:
		var file := ProjectSettings.globalize_path(SAVE_PATH+suffix)
		if FileAccess.file_exists(file): DirAccess.remove_absolute(file)
	print("STARTING_PANTRY: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
