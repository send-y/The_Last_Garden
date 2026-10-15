extends Node
const ErrorBuffer := preload("res://addons/garden_bridge/error_buffer.gd")
const METHODS := ["get_state","inspect_tree","get_errors","capture_frame"]
var enabled := false
var session_id := ""
var folder := ""
var _errors
var _poll := 0.0
var _heartbeat := 0.0
var _busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.is_editor_hint() or not OS.is_debug_build(): set_process(false); return
	var root_path := ProjectSettings.globalize_path("res://../.garden_bridge")
	var testing := false; var explicit := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-save-path="): testing = true
		if arg=="--garden-bridge-off": set_process(false); return
		if arg.begins_with("--garden-bridge-dir="):
			root_path = arg.trim_prefix("--garden-bridge-dir="); explicit = true
	if testing and not explicit: set_process(false); return
	if not root_path.is_absolute_path(): set_process(false); return
	session_id = "%d-%s" % [OS.get_process_id(),Crypto.new().generate_random_bytes(8).hex_encode()]
	folder = root_path.path_join(session_id)
	for child: String in ["requests","responses","captures"]:
		if DirAccess.make_dir_recursive_absolute(folder.path_join(child))!=OK: set_process(false); return
	_errors = ErrorBuffer.new(); OS.add_logger(_errors)
	enabled = true; _manifest()

func _exit_tree() -> void:
	if enabled:
		OS.remove_logger(_errors)
		DirAccess.remove_absolute(folder.path_join("manifest.json"))

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(value)); file.close()
	return DirAccess.rename_absolute(path+".tmp",path)==OK

func _manifest() -> void:
	_write_json(folder.path_join("manifest.json"),{"session_id":session_id,"pid":OS.get_process_id(),"heartbeat":Time.get_unix_time_from_system(),"project_path":ProjectSettings.globalize_path("res://"),"scene":get_tree().current_scene.scene_file_path if get_tree().current_scene!=null else "","version":"0.1.0"})

func _process(delta: float) -> void:
	if not enabled: return
	_heartbeat += delta; _poll += delta
	if _heartbeat>=1.0: _heartbeat = 0; _manifest()
	if _poll<0.05 or _busy: return
	_poll = 0
	for filename: String in DirAccess.get_files_at(folder.path_join("requests")):
		if not filename.ends_with(".json"): continue
		var id := filename.trim_suffix(".json")
		if id.length()!=32 or not id.is_valid_hex_number(false): continue
		var path := folder.path_join("requests").path_join(filename)
		if FileAccess.get_file_as_bytes(path).size()>8192: DirAccess.remove_absolute(path); continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		DirAccess.remove_absolute(path)
		_busy = true; _handle(id,raw); break

func _handle(id: String, raw: Variant) -> void:
	var response := {"id":id}
	if not raw is Dictionary or raw.get("id","")!=id or not METHODS.has(String(raw.get("method",""))) or not raw.get("params",{}) is Dictionary:
		response.error = "Invalid or unsupported bridge request"
	else:
		var params: Dictionary = raw.get("params",{})
		match String(raw.method):
			"get_state": response.result = state_snapshot()
			"inspect_tree": response.result = tree_snapshot(params)
			"get_errors": response.result = {"errors":_errors.snapshot(int(params.get("limit",50)))}
			"capture_frame":
				if DisplayServer.get_name()=="headless": response.error = "Screenshot unavailable in headless mode"
				else:
					await RenderingServer.frame_post_draw
					var image_path := folder.path_join("captures").path_join(id+".png")
					var snapshot_path := folder.path_join("captures").path_join(id+".json")
					var hud := get_tree().root.find_child("Hud",true,false)
					var tree_params := {"root":String(hud.get_path()),"max_nodes":600,"max_depth":12} if hud!=null else {}
					var snapshot := {"frame_id":Engine.get_process_frames(),"state":state_snapshot(),"tree":tree_snapshot(tree_params),"errors":_errors.snapshot()}
					if get_viewport().get_texture().get_image().save_png(image_path)!=OK or not _write_json(snapshot_path,snapshot): response.error = "Could not write capture"
					else: response.result = {"frame_id":snapshot.frame_id,"image_path":image_path,"snapshot_path":snapshot_path,"session_id":session_id}
	_write_json(folder.path_join("responses").path_join(id+".json"),response)
	_busy = false

func state_snapshot() -> Dictionary:
	var sim = Session.simulation
	var npcs: Dictionary = {}
	for id: String in sim.state.npcs:
		var npc: Dictionary = sim.state.npcs[id]
		if not bool(npc.get("active",false)): continue
		npcs[id] = {}
		for key: String in ["known","position","activity_id","needs","personal_inventory","work_options","initiative_job","work_cargo","crop_food_trip"]: npcs[id][key] = npc.get(key)
	var hotbar: Array = []
	for id: String in sim.get_hotbar_slots(): hotbar.append(sim.get_item_instance(id))
	return {"session_id":session_id,"frame_id":Engine.get_process_frames(),"day":sim.get_day(),"minute_of_day":sim.get_minute_of_day(),"elapsed_minutes":sim.get_elapsed_game_minutes(),"paused":Session.is_paused(),"player":{"position":sim.state.get("player_position"),"needs":sim.get_player_needs(),"held_item":sim.get_held_item()},"hotbar":{"active_slot":sim.get_active_hotbar_slot(),"slots":hotbar},"inventory":sim.get_inventory(),"inventory_layout":sim.get_inventory_layout(),"farming":sim.state.farming.duplicate(true),"storage":{"zones":sim.state.storage_zones.duplicate(true),"items":sim.state.storage_items.duplicate(true)},"npcs":npcs}

func tree_snapshot(params: Dictionary) -> Dictionary:
	var path := String(params.get("root","/root"))
	if not (path=="/root" or path.begins_with("/root/")): return {"error":"Tree root must be under /root"}
	var target := get_node_or_null(NodePath(path))
	if target==null: return {"error":"Node not found: "+path}
	var nodes: Array = []
	var limit := clampi(int(params.get("max_nodes",300)),1,600)
	var depth_limit := clampi(int(params.get("max_depth",8)),1,12)
	var queue: Array = [{"node":target,"depth":0}]
	var skipped_depth := false
	while not queue.is_empty() and nodes.size()<limit:
		var entry: Dictionary = queue.pop_front()
		var node: Node = entry.node
		var row := {"path":String(node.get_path()),"class":node.get_class(),"child_count":node.get_child_count()}
		if node.get_script()!=null: row.script = node.get_script().resource_path
		if node is CanvasItem: row.visible = node.is_visible_in_tree()
		if node is Control:
			var rect: Rect2 = node.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,node.size)
			var clip := Rect2(Vector2.ZERO,node.get_viewport_rect().size)
			var parent := node.get_parent()
			while parent!=null:
				if parent is Control and parent.clip_contents: clip = clip.intersection(parent.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,parent.size))
				parent = parent.get_parent()
			row.rect = _rect(rect); row.clip_rect = _rect(clip)
			row.clipped = not clip.encloses(rect); row.mouse_filter = node.mouse_filter
		nodes.append(row)
		if int(entry.depth)>=depth_limit:
			skipped_depth = skipped_depth or node.get_child_count()>0; continue
		for child: Node in node.get_children(): queue.append({"node":child,"depth":int(entry.depth)+1})
	return {"frame_id":Engine.get_process_frames(),"nodes":nodes,"truncated":not queue.is_empty() or skipped_depth}

func _rect(value: Rect2) -> Dictionary:
	return {"position":[value.position.x,value.position.y],"size":[value.size.x,value.size.y]}
