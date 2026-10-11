extends Node

const Lab := preload("res://src/dev/mechanics_lab.tscn")
const World := preload("res://src/simulation/world_simulation.gd")
const SaveStore := preload("res://src/save/first_night_save_store.gd")

class ObservedWorld extends World:
	var exports := 0
	func export_state() -> Dictionary:
		exports += 1
		return super.export_state()

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	Session._save_store = SaveStore.new("user://lab_status_cost_test.json")
	Session.set_process(false)
	var lab := Lab.instantiate()
	add_child(lab)
	var observed := ObservedWorld.new(Session.get_state())
	Session.simulation = observed
	observed.event_emitted.connect(Session._on_simulation_event)
	observed.state.minute_of_day = 12 * 60 + 34
	for i: int in range(4):
		Session.state_changed.emit()
		Session.time_changed.emit()
		Session.message_emitted.emit("Событие %d" % i, true)
	check(observed.exports == 0, "Collapsed laboratory must not export the world for every notification")
	lab._set_lab_panel_open(true)
	check(lab._status_label.text.contains("12:34"), "Opening laboratory immediately shows the current clock")
	check(lab._status_label.text.contains("Событие 3"), "Opening laboratory shows the latest event from while collapsed")
	observed.state.minute_of_day += 1
	Session.time_changed.emit()
	check(lab._status_label.text.contains("12:35"), "Visible laboratory still updates its clock")
	check(observed.exports == 0, "Visible status uses bounded queries instead of a full export")
	print("LAB_STATUS_COST: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
