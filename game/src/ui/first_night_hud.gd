class_name FirstNightHud
extends Control

const Content := preload("res://src/content/first_night_content.gd")
const Localized := preload("res://src/localization/localized_text.gd")

var _time_label: Label
var _inventory_label: Label
var _objective_label: Label
var _selection_label: Label
var _message_label: Label
var _controls_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	Session.state_changed.connect(refresh)
	Session.state_reloaded.connect(refresh)
	Session.time_changed.connect(refresh)
	Session.pause_changed.connect(_on_pause_changed)
	Session.message_emitted.connect(_on_message)
	refresh()


func set_selection(selection: Dictionary) -> void:
	var kind: String = String(selection.get("kind", "none"))
	if kind == "cell":
		_selection_label.text = Localized.resolve("ui.hud.selection.cell", {
			"x": int(selection.get("x", -1)),
			"y": int(selection.get("y", -1)),
		})
		return
	if kind == "interactable":
		var status: String = String(selection.get("status", ""))
		var in_range: bool = bool(selection.get("in_range", false))
		var selection_key: String
		if in_range:
			selection_key = (
				"ui.hud.selection.in_range_with_status"
				if not status.is_empty()
				else "ui.hud.selection.in_range"
			)
		else:
			selection_key = (
				"ui.hud.selection.out_of_range_with_status"
				if not status.is_empty()
				else "ui.hud.selection.out_of_range"
			)
		_selection_label.text = Localized.resolve(selection_key, {
			"label": String(selection.get("label", "")),
			"status": status,
		})
		return
	_selection_label.text = Localized.resolve("ui.hud.selection.none")


func refresh() -> void:
	var time_key: String = "ui.hud.day_time_paused" if Session.is_paused() else "ui.hud.day_time"
	_time_label.text = Localized.resolve(time_key, {
		"day": Session.get_day(),
		"time": Session.get_time_text(),
	})
	_inventory_label.text = _format_inventory()
	_objective_label.text = Localized.resolve("ui.hud.objective", {
		"objective": Session.get_current_objective(),
	})


func _build_ui() -> void:
	var top_panel := ColorRect.new()
	top_panel.position = Vector2(8.0, 8.0)
	top_panel.size = Vector2(252.0, 86.0)
	top_panel.color = Color(0.07, 0.08, 0.07, 0.82)
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_panel)

	_time_label = _make_label(top_panel, Vector2(8.0, 6.0), Vector2(236.0, 20.0), 14)
	_inventory_label = _make_label(top_panel, Vector2(8.0, 26.0), Vector2(236.0, 50.0), 11)
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var objective_panel := ColorRect.new()
	objective_panel.position = Vector2(270.0, 8.0)
	objective_panel.size = Vector2(362.0, 54.0)
	objective_panel.color = Color(0.07, 0.08, 0.07, 0.82)
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(objective_panel)
	_objective_label = _make_label(objective_panel, Vector2(8.0, 6.0), Vector2(346.0, 42.0), 12)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var bottom_panel := ColorRect.new()
	bottom_panel.position = Vector2(8.0, 300.0)
	bottom_panel.size = Vector2(624.0, 52.0)
	bottom_panel.color = Color(0.07, 0.08, 0.07, 0.86)
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_panel)
	_selection_label = _make_label(bottom_panel, Vector2(8.0, 3.0), Vector2(608.0, 17.0), 11)
	_selection_label.text = Localized.resolve("ui.hud.selection.none")
	_message_label = _make_label(bottom_panel, Vector2(8.0, 20.0), Vector2(608.0, 26.0), 11)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.text = Localized.resolve("ui.hud.intro")

	_controls_label = _make_label(self, Vector2(376.0, 68.0), Vector2(256.0, 42.0), 10)
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_controls_label.text = Localized.resolve("ui.hud.controls")


func _make_label(parent: Node, at: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = label_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eee7d5"))
	parent.add_child(label)
	return label


func _format_inventory() -> String:
	var inventory: Dictionary = Session.get_inventory()
	var inventory_key: String = (
		"ui.hud.inventory_with_tools"
		if bool(Session.get_flags().get("tools_found", false))
		else "ui.hud.inventory"
	)
	return Localized.resolve(inventory_key, {
		"weight": String.num(Session.get_inventory_weight(), 1),
		"max_weight": String.num(Session.get_max_carry_weight(), 0),
		"wood": int(inventory.get(FirstNightContent.WOOD_ID, 0)),
		"stone": int(inventory.get(FirstNightContent.STONE_ID, 0)),
		"raw_water": int(inventory.get(FirstNightContent.RAW_WATER_ID, 0)),
		"boiled_water": int(inventory.get(FirstNightContent.BOILED_WATER_ID, 0)),
		"food": int(inventory.get(FirstNightContent.FOOD_ID, 0)),
	})


func _on_pause_changed(_paused: bool) -> void:
	refresh()


func _on_message(message: String, success: bool) -> void:
	_message_label.text = message
	_message_label.add_theme_color_override("font_color", Color("d7e8bd") if success else Color("f0c2a7"))
	refresh()
