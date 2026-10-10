extends Node

const World := preload("res://src/simulation/world_simulation.gd")
const Main := preload("res://src/main/main.tscn")
const Store := preload("res://src/save/first_night_save_store.gd")
const TEST_SAVE := "user://persistent_world_integration_test.json"
var _failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	var state := World.create_new_game_state()
	state.minute_of_day = 23 * 60 + 49
	state.elapsed_game_minutes = state.minute_of_day
	Session.apply_debug_state(state, "persistent world", true)
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	_check(Session.simulation is World, "normal Session must use WorldSimulation")
	var pantry := Session.get_storage_items()
	var time_events := [0]
	Session.time_changed.connect(func() -> void: time_events[0] += 1)
	Session.advance_debug_minutes(20)
	await get_tree().process_frame
	_check(Session.get_day() == 2 and Session.get_time_text() == "00:09", "Session must pass midnight")
	_check(time_events[0] == 1 and hud._time_label.text.contains("00:09"), "Session signal must refresh HUD after midnight")
	_check(Session.get_storage_items() == pantry, "rendered world must keep pantry contents")
	var store := Store.new(TEST_SAVE)
	_check(bool(store.write_state(Session.get_state()).success), "world after midnight must save to disk")
	var read := store.read_state()
	_check(bool(read.success), "saved persistent world must load")
	if bool(read.success):
		Session.apply_debug_state(read.state as Dictionary, "restored world", true)
		await get_tree().process_frame
		_check(hud._time_label.text.contains("00:09"), "reload must publish restored time to HUD")
		Session.advance_debug_minutes(411)
		await get_tree().process_frame
		_check(Session.is_npc_visible("core:first_neighbor"), "neighbor must arrive through normal Session events without sleep")
		_check(hud._time_label.text.contains("07:00"), "HUD must show the first independent morning")
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(TEST_SAVE + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if not _failed:
		print("PASS: persistent world through Session, main scene, HUD, storage and disk reload")
	get_tree().quit(1 if _failed else 0)


func _check(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error("FAIL: persistent world integration: " + message)
