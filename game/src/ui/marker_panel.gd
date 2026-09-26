extends PanelContainer

signal close_requested
signal create_requested(marker_name: String, color: Color)
signal rename_requested(marker_id: String, marker_name: String)
signal delete_requested(marker_id: String)

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const MARKER_COLORS: Array[Color] = [
	Color("f26f5b"), Color("e5b94f"), Color("64c98b"),
	Color("5ebbd0"), Color("7797ef"), Color("c77ad9"),
]

var _mode: String = ""
var _editing_marker_id: String = ""
var _title: Label
var _feedback: Label
var _name_input: LineEdit
var _name_row: HBoxContainer
var _marker_list: VBoxContainer


func _ready() -> void:
	name = "MarkerPanel"
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -190.0
	offset_right = 190.0
	offset_top = -150.0
	offset_bottom = 150.0
	add_theme_stylebox_override("panel", UiSkin.panel_style())
	_build_contents()
	hide()


func show_creation() -> void:
	_mode = "create"
	_editing_marker_id = ""
	_title.text = Localized.resolve("ui.marker.create_title")
	_name_input.text = ""
	_feedback.hide()
	_name_row.show()
	show()
	_name_input.grab_focus()


func show_list(markers: Array[Dictionary]) -> void:
	_mode = "list"
	_title.text = Localized.resolve("ui.marker.list_title")
	_name_row.hide()
	_feedback.hide()
	_refresh_marker_list(markers)
	show()


func is_list_open() -> bool:
	return visible and _mode == "list"


func set_feedback(message: String) -> void:
	_feedback.text = message
	_feedback.show()


func _build_contents() -> void:
	var margin := MarginContainer.new()
	margin.name = "MarkerContentMargin"
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	add_child(margin)
	var column := VBoxContainer.new()
	column.name = "MarkerColumn"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.name = "MarkerHeaderRow"
	column.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = Localized.resolve("ui.marker.close")
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)
	_name_row = HBoxContainer.new()
	_name_row.name = "MarkerNameRow"
	column.add_child(_name_row)
	_name_input = LineEdit.new()
	_name_input.name = "MarkerNameInput"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.max_length = 32
	_name_input.placeholder_text = Localized.resolve("ui.marker.name_placeholder")
	_name_input.text_submitted.connect(func(_text: String) -> void: _submit_name())
	_name_row.add_child(_name_input)
	var save_button := Button.new()
	save_button.name = "MarkerSaveButton"
	save_button.text = Localized.resolve("ui.marker.save")
	save_button.pressed.connect(_submit_name)
	_name_row.add_child(save_button)
	_feedback = Label.new()
	_feedback.name = "MarkerFeedback"
	_feedback.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.hide()
	column.add_child(_feedback)
	var scroll := ScrollContainer.new()
	scroll.name = "MarkerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_marker_list = VBoxContainer.new()
	_marker_list.name = "MarkerList"
	_marker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_marker_list)


func _submit_name() -> void:
	if _mode == "rename":
		rename_requested.emit(_editing_marker_id, _name_input.text)
	else:
		var color := MARKER_COLORS[randi_range(0, MARKER_COLORS.size() - 1)]
		create_requested.emit(_name_input.text, color)


func _refresh_marker_list(markers: Array[Dictionary]) -> void:
	for child: Node in _marker_list.get_children():
		child.queue_free()
	if markers.is_empty():
		var empty_label := Label.new()
		empty_label.text = Localized.resolve("ui.marker.empty")
		_marker_list.add_child(empty_label)
		return
	for marker: Dictionary in markers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_marker_list.add_child(row)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.color = Color.from_string(String(marker.get("color", "ffffff")), Color.WHITE)
		row.add_child(swatch)
		var name_label := Label.new()
		name_label.text = String(marker.get("name", ""))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var marker_id := String(marker.get("id", ""))
		var marker_name := String(marker.get("name", ""))
		var rename_button := Button.new()
		rename_button.text = Localized.resolve("ui.marker.rename")
		rename_button.pressed.connect(
			func() -> void: _begin_rename(marker_id, marker_name)
		)
		row.add_child(rename_button)
		var delete_button := Button.new()
		delete_button.text = Localized.resolve("ui.marker.delete")
		delete_button.pressed.connect(
			func() -> void: delete_requested.emit(marker_id)
		)
		row.add_child(delete_button)


func _begin_rename(marker_id: String, marker_name: String) -> void:
	_mode = "rename"
	_editing_marker_id = marker_id
	_title.text = Localized.resolve("ui.marker.rename_title")
	_name_input.text = marker_name
	_feedback.hide()
	_name_row.show()
	_name_input.grab_focus()
