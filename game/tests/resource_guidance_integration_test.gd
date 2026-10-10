extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const Localized := preload("res://src/localization/localized_text.gd")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const TEST_SAVE_PATH := "user://resource_guidance_test.json"

var _world: FirstNightWorld
var _hud: FirstNightHud
var _player: PlayerController
var _last_selection: Dictionary = {}
var _tool_homes: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(false)
	Session._save_store = SaveStore.new(TEST_SAVE_PATH)
	_cleanup_test_saves()
	Session._start_new_simulation()
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	Session.set_paused(true, false)
	_world = main.get_node("World") as FirstNightWorld
	_hud = main.get_node("Hud/HudRoot") as FirstNightHud
	_player = main.get_node("Player") as PlayerController
	_world.selection_changed.connect(_record_selection)

	if not _check(
		Session.simulation.get_resource_search_hint().is_empty(),
		"new game must not reveal a resource direction before retrieving a tool"
	):
		return
	if not _take_tool("core:axe", 0):
		return
	var hint: Dictionary = Session.simulation.get_resource_search_hint()
	if not _check(
		String(hint.get("kind", "")) == "wood",
		"retrieving the physical axe must enable guidance for missing repair wood"
	):
		return
	var tree := _find_view(String(hint.get("target_id", "")))
	if not _check(
		tree != null and tree.presentation_id == "surface_tree",
		"the search hint must address a real generated tree view"
	):
		return
	_hud.refresh()
	var objective_text: String = _hud._objective_label.text
	var direction: String = Localized.resolve(String(hint.get("direction_key", "")))
	if not _check(
		objective_text.contains("Дерево")
		and objective_text.contains(direction)
		and objective_text.contains(str(int(hint.get("distance_cells", -1))))
		and objective_text.contains("\n")
		and not objective_text.contains("\\n")
		and not objective_text.contains("{")
		and not objective_text.contains("resource.direction."),
		"ordinary HUD objective must display translated direction/distance and a real newline"
	):
		return

	# Position fixtures isolate selection and presentation; they do not test walking.
	var far_position: Vector2 = _player.global_position
	if not _select_and_check(tree, "core:axe", false):
		return
	if not await _check_layouts(tree, far_position):
		return

	_move_player(tree.global_position + Vector2(0.0, 48.0))
	if not _select_and_check(tree, "core:axe", true):
		return
	var tree_required: int = Session.get_resource_work_required(tree.object_id)
	if not _perform_one_step(tree, "core:axe"):
		return
	if not _check(
		Session.get_resource_work_required(tree.object_id) == tree_required,
		"partial tree work must preserve its required work"
	):
		return
	for _step: int in range(1, tree_required):
		var result: Dictionary = Session.execute_resource_work("core:player", tree.object_id)
		if not _check(bool(result.get("success", false)), "ordinary axe work must finish the tree"):
			return
	if not _check(
		tree.presentation_id == "surface_stump"
		and Session.get_resource_work_required(tree.object_id) == 4
		and Session.get_resource_work_progress(tree.object_id) == 0,
		"finishing the tree must expose the stump's own four-step work"
	):
		return
	if not _select_and_check(tree, "core:axe", true):
		return
	if not _perform_one_step(tree, "core:axe"):
		return
	if not _return_tool("core:axe"):
		return
	if not _take_tool("core:pickaxe", 1):
		return

	var stone_nodes: Array[Dictionary] = Session.get_surface_boulders()
	if not _check(not stone_nodes.is_empty(), "ordinary new game must have a generated boulder"):
		return
	var stone := _find_view(String(stone_nodes[0].get("id", "")))
	if not _check(stone != null, "the generated boulder must exist in the ordinary world"):
		return
	_move_player(stone.global_position + Vector2(0.0, 48.0))
	if not _select_and_check(stone, "core:pickaxe", true):
		return
	if not _perform_one_step(stone, "core:pickaxe"):
		return

	_cleanup_test_saves()
	print("PASS: ordinary pantry tools, resource direction, world-to-HUD selection, live tree/stump/boulder work, and guidance layout")
	get_tree().quit(0)


func _take_tool(item_id: String, slot_index: int) -> bool:
	for zone: Dictionary in Session.get_storage_zones():
		for cell_value: Variant in zone.get("cells", []) as Array:
			var coordinates: Array = cell_value as Array
			var cell := Vector2i(int(coordinates[0]), int(coordinates[1]))
			for placement: Dictionary in Session.get_storage_layout(cell):
				if String(placement.get("item_id", "")) != item_id:
					continue
				var instance_id: String = String(placement.get("instance_id", ""))
				_move_player(Vector2(cell * 32) + Vector2(16.0, 16.0))
				var result: Dictionary = Session.transfer_storage_stack_to_inventory(
					cell, String(placement.get("placement_id", ""))
				)
				if not _check(
					bool(result.get("success", false)) and not instance_id.is_empty(),
					"could not transfer the real %s instance from the pantry: %s" % [item_id, result]
				):
					return false
				_tool_homes[item_id] = cell
				result = Session.assign_hotbar_slot(slot_index, instance_id)
				if not _check(bool(result.get("success", false)), "could not assign the physical tool"):
					return false
				_hud.handle_hotbar_key(slot_index)
				return _check(
					String(Session.get_active_item_instance().get("instance_id", "")) == instance_id,
					"HUD hotbar selection must use the same physical pantry instance"
				)
	return _check(false, "the ordinary pantry is missing %s" % item_id)


func _return_tool(item_id: String) -> bool:
	var cell: Vector2i = _tool_homes[item_id]
	_move_player(Vector2(cell * 32) + Vector2(16.0, 16.0))
	for placement: Dictionary in Session.get_inventory_layout():
		if String(placement.get("item_id", "")) != item_id:
			continue
		var result: Dictionary = Session.transfer_inventory_stack_to_storage(
			cell, item_id, int(placement.get("stack_index", -1))
		)
		return _check(
			bool(result.get("success", false)),
			"could not return the real axe before retrieving the pickaxe: %s" % result
		)
	return _check(false, "the axe disappeared from the ordinary inventory")


func _select_and_check(target: InteractableView, tool_id: String, in_range: bool) -> bool:
	_last_selection = {}
	_world.select_at_world_position(target.global_position)
	if not _check(
		String(_last_selection.get("object_id", "")) == target.object_id
		and String(_last_selection.get("required_tool_item_id", "")) == tool_id
		and bool(_last_selection.get("in_range", false)) == in_range,
		"real world selection must emit the selected resource, required tool, and actual range"
	):
		return false
	var expected_progress: String = "%d/%d" % [
		Session.get_resource_work_progress(target.object_id),
		Session.get_resource_work_required(target.object_id),
	]
	var text: String = _hud._selection_label.text
	var tool_name: String = "топор" if tool_id == "core:axe" else "кирка"
	if not _check(
		text.to_lower().contains(tool_name)
		and text.to_lower().contains("удерживайте e")
		and text.contains(expected_progress)
		and String(_last_selection.get("status", "")).contains(expected_progress)
		and text.contains("\n")
		and not text.contains("\\n")
		and not text.contains("{")
		and not text.contains("[E / ПКМ]"),
		"world-to-HUD resource selection must retain live progress and show the translated tool/hold action"
	):
		return false
	return _check(
		text.to_lower().contains("подойдите ближе") == (not in_range),
		"the resource selection must explain when the player is outside interaction range"
	)


func _perform_one_step(target: InteractableView, tool_id: String) -> bool:
	var before: int = Session.get_resource_work_progress(target.object_id)
	var result: Dictionary = Session.execute_resource_work("core:player", target.object_id)
	if not _check(
		bool(result.get("success", false))
		and Session.get_resource_work_progress(target.object_id) == before + 1,
		"selected physical tool must advance resource work by one step"
	):
		return false
	# The Session state signal must update the existing world selection and HUD.
	var progress: String = "%d/%d" % [
		before + 1, Session.get_resource_work_required(target.object_id),
	]
	return _check(
		String(_last_selection.get("required_tool_item_id", "")) == tool_id
		and String(_last_selection.get("status", "")).contains(progress)
		and _hud._selection_label.text.contains(progress),
		"resource work must refresh the selected progress through the real state signal"
	)


func _check_layouts(target: InteractableView, far_position: Vector2) -> bool:
	var sizes: Array[Vector2i] = [Vector2i(640, 360), Vector2i(1270, 640)]
	for index: int in range(sizes.size()):
		get_window().size = sizes[index]
		await get_tree().process_frame
		await get_tree().process_frame
		_move_player(far_position)
		_hud.refresh()
		if not _select_and_check(target, "core:axe", false):
			return false
		await get_tree().process_frame
		if not _check(
			(index != 0 or _hud.size.is_equal_approx(Vector2(640.0, 360.0)))
			and (index != 1 or _hud.size.x > 640.0),
			"guidance layout must be exercised at the 640x360 base viewport and a wider viewport"
		):
			return false
		var viewport_bounds := Rect2(_hud.global_position, _hud.size)
		if not _check_label_bounds(_hud._objective_label, viewport_bounds, 48.0, "objective"):
			return false
		if not _check_label_bounds(_hud._selection_label, viewport_bounds, 39.0, "selection"):
			return false
		if not _check(
			not _hud._selection_label.get_global_rect().intersects(_hud._message_label.get_global_rect())
			and not _hud._objective_label.get_global_rect().intersects(_hud._selection_label.get_global_rect())
			and not _hud._objective_label.get_global_rect().intersects(_hud._message_label.get_global_rect()),
			"wrapped resource guidance must not overlap selection or message feedback"
		):
			return false
		var screenshot_argument: String = (
			"--screenshot-path=" if index == 0 else "--wide-screenshot-path="
		)
		if not await _save_screenshot_argument(screenshot_argument):
			return false
	return true


func _check_label_bounds(label: Label, viewport_bounds: Rect2, maximum_height: float, name: String) -> bool:
	return _check(
		viewport_bounds.encloses(label.get_global_rect())
		and label.size.y <= maximum_height + 0.5
		and label.get_minimum_size().y <= maximum_height + 0.5
		and label.get_visible_line_count() == label.get_line_count(),
		"%s guidance text must fit its actual viewport and allocated height; rect=%s minimum=%s lines=%s/%s" % [
			name, label.get_global_rect(), label.get_minimum_size(),
			label.get_visible_line_count(), label.get_line_count(),
		]
	)


func _save_screenshot_argument(prefix: String) -> bool:
	var path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			path = argument.trim_prefix(prefix)
	if path.is_empty():
		return true
	if DisplayServer.get_name() == "headless":
		push_warning("Guidance screenshot skipped: run without --headless to render %s" % path)
		return true
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	return _check(
		not screenshot.is_empty() and screenshot.save_png(path) == OK,
		"could not save the optional rendered guidance screenshot: %s" % path
	)


func _record_selection(selection: Dictionary) -> void:
	_last_selection = selection.duplicate(true)


func _move_player(position: Vector2) -> void:
	_player.global_position = position
	Session.set_player_position(position)


func _find_view(object_id: String) -> InteractableView:
	for child: Node in _world.get_children():
		if child is InteractableView and (child as InteractableView).object_id == object_id:
			return child as InteractableView
	return null


func _cleanup_test_saves() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH + suffix)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("FAIL: resource guidance integration: %s" % message)
	_cleanup_test_saves()
	get_tree().quit(1)
	return false
