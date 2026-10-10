extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const TEST_SAVE_PATH := "user://quick_save_input_test.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(false)
	Session._save_store = SaveStore.new(TEST_SAVE_PATH)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var starting_minute := Session.simulation.get_minute_of_day()
	Session.simulation.advance_minutes(5)
	var save_event := InputEventAction.new()
	save_event.action = &"quick_save"
	save_event.pressed = true
	main._unhandled_input(save_event)
	if not FileAccess.file_exists(TEST_SAVE_PATH):
		_fail("F5 action did not write a save through MainScene")
		return
	Session.simulation.advance_minutes(10)
	var load_event := InputEventAction.new()
	load_event.action = &"quick_load"
	load_event.pressed = true
	main._unhandled_input(load_event)
	await get_tree().process_frame
	if Session.simulation.get_minute_of_day() != starting_minute + 5:
		_fail("F9 action did not restore the state saved through MainScene")
		return
	_cleanup_test_saves()
	print("PASS: F5 and F9 quick-save actions integrate with MainScene")
	get_tree().quit(0)


func _cleanup_test_saves() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH + suffix)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)


func _fail(message: String) -> void:
	push_error("FAIL: %s" % message)
	_cleanup_test_saves()
	get_tree().quit(1)
