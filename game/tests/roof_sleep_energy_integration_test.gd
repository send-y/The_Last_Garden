extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const TEST_SAVE_PATH := "user://roof_sleep_energy_integration_test.json"
const STAGE_OBJECTIVE_KEYS: Array[String] = [
	"first_night.objective.clear_room",
	"first_night.objective.build_workbench",
	"first_night.objective.finish_workbench",
	"first_night.objective.saw_planks",
	"first_night.objective.finish_saw_planks",
	"first_night.objective.pick_up_planks",
	"first_night.objective.cover_roof",
]
const WOOD_HINT_OBJECTIVE_KEYS: Array[String] = [
	"first_night.objective.clear_room",
	"first_night.objective.build_workbench",
	"first_night.objective.finish_workbench",
	"first_night.objective.saw_planks",
]

var _world: FirstNightWorld
var _hud: FirstNightHud
var _player: PlayerController
var _last_selection: Dictionary = {}
var _full_fill_width: float = 0.0
var _layout_wood_hint: String = ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(false)
	Session._save_store = SaveStore.new(TEST_SAVE_PATH)
	_cleanup_test_saves()
	Session.set_paused(true, false)
	Session._start_new_simulation()
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_world = main.get_node("World") as FirstNightWorld
	_hud = main.get_node("Hud/HudRoot") as FirstNightHud
	_player = main.get_node("Player") as PlayerController
	_player.set_physics_process(false)
	_world.selection_changed.connect(_record_selection)
	_full_fill_width = _hud._energy_fill.size.x
	if not _check(
		is_equal_approx(Session.get_player_energy(), Session.get_player_energy_max())
		and _full_fill_width > 0.0
		and _hud._needs_hud.labels.size() == 3,
		"ordinary new game must show three real physical stats"
	):
		return
	if not _check_hud("ordinary new game"):
		return

	# These fixtures isolate commands, Session signals, and presentation. The
	# core ordinary-route test proves resource collection and actual plank craft.
	var unprepared: Dictionary = Session.get_state()
	unprepared["player_energy"] = 0.0
	unprepared["minute_of_day"] = 18 * 60
	Session._replace_simulation(unprepared)
	Session._publish_reloaded_state(true)
	await get_tree().process_frame
	if not _check_hud("exhausted unprepared evening reload"):
		return
	if not _check(
		not Session.is_roof_covered()
		and not bool(Session.get_flags().get("tools_found", false))
		and bool(Session.get_flags().get("bed_ready", false))
		and not bool(Session.get_flags().get("water_boiled", false))
		and Session.get_inventory_placements().is_empty(),
		"poor-night fixture retains starter bedroll, open roof and missing tools, food and water"
	):
		return
	var poor_preview: float = Session.get_sleep_energy_preview()
	if not _check(
		poor_preview > 0.0 and poor_preview < Session.get_player_energy_max()
		and is_zero_approx(Session.get_player_energy()),
		"an uncovered roof must preview partial recovery without changing current energy"
	):
		return
	if not _select_target("core:bed_site", false):
		return
	var before_day: int = Session.get_day()
	var poor_sleep: Dictionary = Session.execute_interaction("core:bed_site")
	if not _check(
		bool(poor_sleep.get("success", false))
		and Session.get_day() == before_day + 1
		and Session.get_minute_of_day() == 7 * 60
		and is_equal_approx(Session.get_player_energy(), poor_preview)
		and bool(Session.get_flags().get("first_night_complete", false))
		and not bool(Session.get_flags().get("comfortable_sleep_completed", false)),
		"ordinary bed command at zero energy must allow an unprepared partial night"
	):
		return
	if not _check_hud("poor sleep state signal"):
		return
	if not _reload_saved_morning(poor_preview, false):
		return
	await get_tree().process_frame
	if not _check_hud("poor morning save/load"):
		return

	var repair_fixture: Dictionary = Session.get_state()
	repair_fixture["minute_of_day"] = 18 * 60
	(repair_fixture["flags"] as Dictionary)["tools_found"] = true
	(repair_fixture["flags"] as Dictionary)["repair_stage"] = 1
	Session._replace_simulation(repair_fixture)
	Session._publish_reloaded_state(true)
	var wood_hint: Dictionary = Session.simulation.get_resource_search_hint()
	if not _check(String(wood_hint.get("kind", "")) == "wood", "uncovered roof fixture must provide a real Session wood-search hint"):
		return
	# Use the live hint distance and the southwest direction for these
	# presentation bounds. This does not reproduce resource-price calculations.
	_layout_wood_hint = Localized.resolve("resource.objective.search_wood", {
		"direction": Localized.text_reference("resource.direction.southwest"),
		"distance_cells": int(wood_hint.get("distance_cells", 0)),
	})
	var roof_cost: Dictionary = Session.simulation.content.get_cost("repair_stage_1")
	repair_fixture["inventory"] = roof_cost.duplicate(true)
	repair_fixture["inventory_layout"] = []
	Session._replace_simulation(repair_fixture)
	Session._publish_reloaded_state(true)
	await get_tree().process_frame
	if not _select_target("core:repair_room", false):
		return
	var energy_before_repair: float = Session.get_player_energy()
	var planks_before: int = Session.simulation.get_item_count("core:plank")
	if not _check(planks_before > 0, "roof UI fixture must provide authored plank materials"):
		return
	var repaired: Dictionary = Session.execute_interaction("core:repair_room")
	if not _check(
		bool(repaired.get("success", false))
		and int(Session.get_flags().get("repair_stage", 0)) == 2
		and Session.is_roof_covered()
		and Session.simulation.get_item_count("core:plank") == 0
		and is_equal_approx(Session.get_player_energy(), energy_before_repair)
		and not bool(Session.get_flags().get("comfortable_sleep_completed", false)),
		"the plank roof command must cover the roof without instantly restoring energy or completing sleep"
	):
		return
	if not _check_hud("roof repair state signal") or not _check_selected_preview(true):
		return
	if not _select_target("core:bed_site", true):
		return
	var full_preview: float = Session.get_sleep_energy_preview()
	before_day = Session.get_day()
	var comfortable_sleep: Dictionary = Session.execute_interaction("core:bed_site")
	if not _check(
		bool(comfortable_sleep.get("success", false))
		and Session.get_day() == before_day + 1
		and Session.get_minute_of_day() == 7 * 60
		and is_equal_approx(full_preview, Session.get_player_energy_max())
		and is_equal_approx(Session.get_player_energy(), full_preview)
		and bool(Session.get_flags().get("comfortable_sleep_completed", false))
		and int(Session.get_flags().get("repair_stage", 0)) == 2,
		"a covered roof must restore full energy through sleep without requiring optional room finish"
	):
		return
	if not _check_hud("comfortable sleep state signal"):
		return
	if not _check(
		_hud._message_label.text.begins_with("Утро: энергия ")
		and _hud._message_label.text.contains("%d/%d" % [
			roundi(Session.get_player_energy()), roundi(Session.get_player_energy_max()),
		])
		and not _hud._message_label.text.contains("{"),
		"comfortable sleep must publish its current/max energy in the resolved morning message"
	):
		return
	if not await _check_layouts():
		return
	if not _reload_saved_morning(full_preview, true):
		return
	await get_tree().process_frame
	if not _check_hud("comfortable morning save/load"):
		return
	_cleanup_test_saves()
	print("PASS: ordinary MainScene energy HUD, unprepared sleep, plank roof preview, comfortable sleep, and isolated save/load")
	get_tree().quit(0)


func _select_target(object_id: String, covered: bool) -> bool:
	var target := _find_view(object_id)
	if not _check(target != null, "ordinary world is missing %s" % object_id):
		return false
	# Position fixtures isolate interaction distance; this test does not prove walking.
	_player.global_position = target.global_position + Vector2(0.0, 32.0)
	Session.set_player_position(_player.global_position)
	_world.select_at_world_position(target.global_position)
	if not _check(
		String(_last_selection.get("object_id", "")) == object_id
		and bool(_last_selection.get("in_range", false)),
		"real world selection must publish the selected roof/bed and actual interaction range"
	):
		return false
	return _check_selected_preview(covered)


func _check_selected_preview(covered: bool) -> bool:
	var expected: String = Localized.resolve(
		"sleep.preview.full" if covered else "sleep.preview.partial",
		{
			"energy": roundi(Session.get_sleep_energy_preview()),
			"energy_max": roundi(Session.get_player_energy_max()),
		}
	)
	if String(_last_selection.get("object_id", "")) == "core:bed_site" and Session.get_minute_of_day() >= 7 * 60 and Session.get_minute_of_day() < 18 * 60:
		expected = Localized.resolve("housing.day_rest")
	return _check(
		String(_last_selection.get("status", "")) == expected
		and _hud._selection_label.text.contains(expected)
		and not _hud._selection_label.text.contains("{")
		and not _hud._selection_label.text.contains("sleep.preview."),
		"roof/bed selection must show the translated live sleep-energy preview through the real world signal"
	)


func _check_hud(context: String) -> bool:
	if not _check_status_label_bounds(context):
		return false
	var current: float = Session.get_player_energy()
	var maximum: float = Session.get_player_energy_max()
	var expected_text: String = "%d/%d" % [roundi(current), roundi(maximum)]
	var expected_width: float = _full_fill_width * clampf(current / maximum, 0.0, 1.0)
	return _check(
		_hud._energy_label.text == expected_text
		and is_equal_approx(_hud._energy_fill.size.x, expected_width)
		and _hud._energy_fill.visible == (current > 0.0)
		and not Session.get_state().has("player_health"),
		"%s must update real energy text/fill while health remains unknown; text=%s width=%s" % [
			context, _hud._energy_label.text, _hud._energy_fill.size.x,
		]
	)


func _check_status_label_bounds(context: String) -> bool:
	for key: String in _hud._needs_hud.labels:
		var label: Label = _hud._needs_hud.labels[key]
		var button: Button = _hud._needs_hud.buttons[key]
		if not _check(button.get_global_rect().encloses(label.get_global_rect()), context + " status value must fit its row: " + str(button.get_global_rect()) + " / " + str(label.get_global_rect())):
			return false
	return true


func _reload_saved_morning(expected_energy: float, comfortable: bool) -> bool:
	if not _check(FileAccess.file_exists(TEST_SAVE_PATH), "sleep must autosave into the isolated test path"):
		return false
	var saved_day: int = Session.get_day()
	# Deliberately differ from the persisted value: a load must restore the saved
	# energy, and a poor morning must not be upgraded into full energy on load.
	Session.simulation.state["player_energy"] = 0.0
	if not _check(Session.load_game(), "ordinary Session load must read the isolated sleep autosave"):
		return false
	Session.set_paused(true, false)
	return _check(
		Session.get_day() == saved_day
		and Session.get_minute_of_day() == 7 * 60
		and is_equal_approx(Session.get_player_energy(), expected_energy)
		and bool(Session.get_flags().get("comfortable_sleep_completed", false)) == comfortable,
		"save/load must preserve morning, energy, and comfortable-sleep history without replaying sleep"
	)


func _check_layouts() -> bool:
	var sizes: Array[Vector2i] = [Vector2i(640, 360), Vector2i(1270, 640)]
	for index: int in range(sizes.size()):
		get_window().size = sizes[index]
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds := Rect2(_hud.global_position, _hud.size)
		if not _check(
			bounds.encloses(_hud._energy_label.get_global_rect())
			and bounds.encloses(_hud._energy_fill.get_global_rect())
			and _hud._energy_label.get_visible_line_count() == _hud._energy_label.get_line_count(),
			"energy text/fill must fit the actual base and wider HUD viewports"
		):
			return false
		if not _check_hud("resized HUD") or not _check_selected_preview(true):
			return false
		if not await _check_stage_goal_layouts(bounds):
			return false
		var prefix: String = "--screenshot-path=" if index == 0 else "--wide-screenshot-path="
		if not await _save_screenshot_argument(prefix):
			return false
	return true


func _check_stage_goal_layouts(viewport_bounds: Rect2) -> bool:
	for objective_key: String in STAGE_OBJECTIVE_KEYS:
		var objective: String = Localized.resolve(objective_key)
		if WOOD_HINT_OBJECTIVE_KEYS.has(objective_key):
			objective += "\n" + _layout_wood_hint
		_hud._objective_label.text = Localized.resolve("ui.hud.objective", {"objective": objective})
		await get_tree().process_frame
		var minimum: Vector2 = _hud._objective_label.get_minimum_size()
		if not _check(
			viewport_bounds.encloses(_hud._objective_label.get_global_rect())
			and _hud._objective_label.size.x <= 158.5
			and _hud._objective_label.size.y <= 48.5
			and minimum.x <= 158.5 and minimum.y <= 48.5
			and _hud._objective_label.get_visible_line_count() == _hud._objective_label.get_line_count(),
			"%s must fit its real 158x48 objective label with its applicable southwest wood hint; viewport=%s minimum=%s lines=%s/%s" % [
				objective_key, _hud.size, minimum,
				_hud._objective_label.get_visible_line_count(), _hud._objective_label.get_line_count(),
			]
		):
			return false
	# Return the presentation fixture to the actual Session goal through the
	# same state signal used after commands; no simulation progress is changed.
	Session.state_changed.emit()
	await get_tree().process_frame
	return _check(
		_hud._objective_label.text == Localized.resolve("ui.hud.objective", {
			"objective": Session.get_current_objective(),
		}),
		"the state signal must restore the current Session objective after presentation bounds checks"
	)


func _save_screenshot_argument(prefix: String) -> bool:
	var path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			path = argument.trim_prefix(prefix)
	if path.is_empty():
		return true
	if DisplayServer.get_name() == "headless":
		push_warning("Roof/energy screenshot skipped: run without --headless to render %s" % path)
		return true
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	return _check(
		not screenshot.is_empty() and screenshot.save_png(path) == OK,
		"could not save the optional rendered roof/energy screenshot: %s" % path
	)


func _record_selection(selection: Dictionary) -> void:
	_last_selection = selection.duplicate(true)


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
	push_error("FAIL: roof/sleep energy integration: %s" % message)
	_cleanup_test_saves()
	get_tree().quit(1)
	return false
