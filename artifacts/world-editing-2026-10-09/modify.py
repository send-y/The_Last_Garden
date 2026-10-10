from pathlib import Path
root=Path('D:/The_Last_Garden')
def edit(name,old,new):
 p=root/name
 s=p.read_text(encoding='utf-8-sig')
 assert old in s,name+' missing replacement: '+old[:80]
 p.write_text(s.replace(old,new,1),encoding='utf-8')
edit('game/src/simulation/world_simulation.gd','func execute_interaction(target_id: String) -> Dictionary:', '''func edit_world(action: String, cell: Vector2i, target_id: String = "", actor_id: String = "core:player") -> Dictionary:
	return preload("res://src/construction/world_editing.gd").execute(self,action,cell,target_id,actor_id)


func execute_interaction(target_id: String) -> Dictionary:''')
edit('game/src/simulation/world_rules.gd','const SAVE_VERSION: int = 34','const SAVE_VERSION: int = 35')
edit('game/src/simulation/world_rules.gd','"collected": {},','"collected": {},\n\t\t"removed_bushes": {},')
edit('game/src/simulation/systems/save_migrations.gd','state["collected"] = content.normalize_collected', '''var removed: Dictionary = {}
	var raw_removed: Variant = state.get("removed_bushes",{})
	if raw_removed is Dictionary:
		for id: String in sim._food_object_ids:
			if raw_removed.get(id,false) is bool and raw_removed.get(id,false): removed[id] = true
	state["removed_bushes"] = removed
	state["collected"] = content.normalize_collected''')
edit('game/src/simulation/systems/opening_scenario.gd','if kind == "food":\n\t\treturn false','if kind == "food":\n\t\treturn bool(sim.state.removed_bushes.get(content.normalize_object_id(object_id),false))')
edit('game/src/simulation/systems/construction_projects.gd','blueprints.remove_at(index)\n\t\tstructures.append(structure)','if building_id == "core:wood_door": structure["open"] = false\n\t\tblueprints.remove_at(index)\n\t\tstructures.append(structure)')
edit('game/src/simulation/systems/construction_state.gd','structure["stage_id"] = COMPLETE_STAGE_ID', '''if String(structure.building_id) == "core:wood_door":
			# Missing state is a legacy always-passable door.
			structure.open = true
			for raw: Variant in value:
				if raw is Dictionary and raw.get("cell",[]) == structure.cell and String(raw.get("building_id","")) == "core:wood_door" and raw.get("open") is bool:
					structure.open = raw.open
					break
		structure["stage_id"] = COMPLETE_STAGE_ID''')
edit('game/src/simulation/systems/world_calendar.gd','var autonomy_result: Dictionary = npc_autonomy.advance_minutes(', 'var doors_changed: bool = preload("res://src/construction/world_editing.gd").open_for_npcs(sim)\n\t\tvar autonomy_result: Dictionary = npc_autonomy.advance_minutes(')
edit('game/src/simulation/systems/world_calendar.gd','var construction_changed: bool = sim._apply_autonomy_effects(', 'doors_changed = preload("res://src/construction/world_editing.gd").open_for_npcs(sim) or doors_changed\n\t\tvar construction_changed: bool = sim._apply_autonomy_effects(')
edit('game/src/simulation/systems/world_calendar.gd','npc_or_world_changed = npc_or_world_changed or construction_changed','npc_or_world_changed = npc_or_world_changed or construction_changed or doors_changed')
edit('game/src/simulation/systems/construction_projects.gd','if not String(definition.get("station_type", "")).is_empty():\n\t\t\t\treturn structure','if not String(definition.get("station_type", "")).is_empty():\n\t\t\t\treturn structure\n\t\t\tif not building_catalog.is_floor(String(structure.get("building_id", ""))):\n\t\t\t\tfallback = structure')
edit('game/src/world/first_night_world.gd','interact_with_selection(false)\n\t\t\tget_viewport()', 'if mouse_event.shift_pressed:\n\t\t\t\tremove_selection()\n\t\t\telse:\n\t\t\t\tinteract_with_selection(false)\n\t\t\tget_viewport()')
edit('game/src/world/first_night_world.gd','func interact_with_selection(continuous_work: bool = false) -> void:', '''func remove_selection() -> void:
	var result: Dictionary
	if _selected != null and is_instance_valid(_selected) and _selected.kind == "food":
		result = Session.simulation.edit_world("clear_bush",Vector2i.ZERO,_selected.object_id)
	else:
		result = Session.simulation.edit_world("dismantle",_selected_cell)
	Session.notify_player_key(String(result.message_key),{},bool(result.success))


func interact_with_selection(continuous_work: bool = false) -> void:''')
edit('game/src/world/first_night_world.gd','or building_id in ["core:bed", "core:bedroll","core:chair","core:table","core:torch"]','or building_id in ["core:bed", "core:bedroll","core:chair","core:table","core:torch","core:wood_door"]')
edit('game/src/world/first_night_world.gd','if not status.is_empty():\n\t\tresult["status"] = status','if interactable.kind == "food":\n\t\tstatus += "\\n" + Localized.resolve("world_edit.bush.hint")\n\tif not status.is_empty():\n\t\tresult["status"] = status')
edit('game/src/world/first_night_world.gd','if sleep_place:\n\t\tvar place_id', 'if String(structure.get("building_id","")) == "core:wood_door":\n\t\tstatus = Localized.resolve("world_edit.door.open_hint" if bool(structure.get("open",true)) else "world_edit.door.closed_hint")\n\tstatus += "\\n" + Localized.resolve("world_edit.dismantle.hint")\n\tif sleep_place:\n\t\tvar place_id')
edit('game/src/main/main.gd','for structure: Dictionary in Session.get_structures():\n\t\tif structure.get("cell",[])', '''var clicked: Dictionary = Session.simulation._find_structure([cell.x,cell.y])
	if String(clicked.get("building_id","")) == "core:wood_door":
		# Holding E starts one action; repeated work never toggles a door.
		var result: Dictionary = Session.simulation.edit_world("toggle_door",cell)
		Session.notify_player_key(String(result.message_key),{},bool(result.success))
		return
	for structure: Dictionary in Session.get_structures():
		if structure.get("cell",[])''')
edit('game/src/construction/construction_cursor.gd','var mouse_event := event as InputEventMouseButton\n\tif _storage_mode_active:', '''var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed and mouse_event.shift_pressed:
		var world := get_node_or_null("../World") as FirstNightWorld
		if world != null:
			world.select_at_world_position(get_global_mouse_position())
			world.remove_selection()
		get_viewport().set_input_as_handled()
		return
	if _storage_mode_active:''')
edit('game/src/construction/structure_layer.gd','var _collision_bodies: Array[StaticBody2D]', '''const Connections := preload("res://src/construction/wall_connections.gd")
const WallVisual := preload("res://src/construction/connected_wall_visual.gd")

var _collision_bodies: Array[StaticBody2D]''')
edit('game/src/construction/structure_layer.gd','for structure_value: Variant in structures:', 'var boundaries := Connections.index(structures,_building_catalog)\n\tfor structure_value: Variant in structures:')
edit('game/src/construction/structure_layer.gd','var sprite := Sprite2D.new()\n\t\t\tsprite.texture = texture', '''var wall := String(_building_catalog.get_definition(building_id).get("category_id","")) == "core:wall"
			var sprite: Sprite2D = WallVisual.new() if wall else Sprite2D.new()
			sprite.texture = null if wall else texture''')
edit('game/src/construction/structure_layer.gd','sprite.position = Vector2(origin * CELL_SIZE)\n\t\t\tsprite.z_as_relative', '''sprite.position = Vector2(origin * CELL_SIZE)
			var connections := Connections.mask(origin,boundaries)
			if wall:
				sprite.source_texture = texture
				sprite.connection_mask = connections if connections else 5
				sprite.position += Vector2(16,16)
				if Connections.vertical(connections):
					sprite.rotation = PI/2
					sprite.connection_mask = ((connections >> 1) | ((connections & 1) << 3)) & 15
			elif building_id == "core:wood_door":
				sprite.centered = true
				sprite.position += Vector2(16,16)
				if Connections.vertical(connections): sprite.rotation = PI/2
				if bool(structure.get("open",true)):
					sprite.rotation += PI/2
					sprite.scale = Vector2(0.25,1)
			sprite.set_meta("cell",origin)
			sprite.set_meta("connections",connections)
			sprite.z_as_relative''')
edit('game/src/construction/structure_layer.gd','if not bool(definition.get("blocks_movement", false)):\n\t\t\tcontinue', 'var blocks := bool(definition.get("blocks_movement",false)) or (building_id == "core:wood_door" and not bool(structure.get("open",true)))\n\t\tif not blocks:\n\t\t\tcontinue')
localization={
 'world_edit.failure.actor':'Разбор доступен только игроку.',
 'world_edit.failure.target':'Здесь нечего разбирать или убирать.',
 'world_edit.failure.occupied':'Сначала освободите клетку от персонажей.',
 'world_edit.failure.busy':'Сначала завершите работу на этом верстаке.',
 'world_edit.failure.axe':'Выберите топор в руку чтобы выкорчевать куст.',
 'world_edit.door.opened':'Дверь открыта.', 'world_edit.door.closed':'Дверь закрыта.',
 'world_edit.dismantled':'Постройка разобрана. Возвращена половина материалов; лишнее лежит рядом.',
 'world_edit.bush.cleared':'Куст выкорчеван. На этом месте он больше не вырастет.',
 'world_edit.bush.hint':'Shift + ПКМ с топором: выкорчевать куст.',
 'world_edit.dismantle.hint':'Shift + ПКМ рядом: разобрать (возврат 50% материалов).',
 'world_edit.door.open_hint':'Дверь открыта. ПКМ / E: закрыть.',
 'world_edit.door.closed_hint':'Дверь закрыта. ПКМ / E: открыть.'
}
with (root/'game/localization/core.csv').open('a',encoding='utf-8',newline='') as f:
 import csv
 w=csv.writer(f)
 for key,value in localization.items(): w.writerow([key,value])
