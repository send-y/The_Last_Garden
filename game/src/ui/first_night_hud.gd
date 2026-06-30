class_name FirstNightHud
extends Control

const Content := preload("res://src/content/first_night_content.gd")

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


func set_selection(label: String, in_range: bool) -> void:
	if label.is_empty() or label.begins_with("Клетка -1"):
		_selection_label.text = "Выбор: —"
		return
	if label.begins_with("Клетка"):
		_selection_label.text = "Выбор: %s" % label
		return
	var suffix: String = "  [E / ПКМ]" if in_range else "  [подойдите ближе]"
	_selection_label.text = "Выбор: %s%s" % [label, suffix]


func refresh() -> void:
	_time_label.text = "День %d  %s%s" % [Session.get_day(), Session.get_time_text(), "  ПАУЗА" if Session.is_paused() else ""]
	_inventory_label.text = _format_inventory()
	_objective_label.text = "Цель: %s" % Session.get_current_objective()


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
	_selection_label.text = "Выбор: —"
	_message_label = _make_label(bottom_panel, Vector2(8.0, 20.0), Vector2(608.0, 26.0), 11)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.text = "Осмотрите Общий дом. ЛКМ выбирает объект, ПКМ взаимодействует."

	_controls_label = _make_label(self, Vector2(376.0, 68.0), Vector2(256.0, 42.0), 10)
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_controls_label.text = "WASD/стрелки — движение   Space — пауза\nF5 — сохранить   F9 — загрузить"


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
	return "Вес %.1f/%.0f кг\nДерево %d  Камень %d  Вода %d/%d  Еда %d%s" % [
		Session.get_inventory_weight(),
		Session.get_max_carry_weight(),
		int(inventory.get(FirstNightContent.WOOD_ID, 0)),
		int(inventory.get(FirstNightContent.STONE_ID, 0)),
		int(inventory.get(FirstNightContent.RAW_WATER_ID, 0)),
		int(inventory.get(FirstNightContent.BOILED_WATER_ID, 0)),
		int(inventory.get(FirstNightContent.FOOD_ID, 0)),
		"  Инструменты ✓" if bool(Session.get_flags().get("tools_found", false)) else "",
	]


func _on_pause_changed(_paused: bool) -> void:
	refresh()


func _on_message(message: String, success: bool) -> void:
	_message_label.text = message
	_message_label.add_theme_color_override("font_color", Color("d7e8bd") if success else Color("f0c2a7"))
	refresh()
