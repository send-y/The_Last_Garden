class_name StoragePanel
extends PanelContainer

signal close_requested
signal transfer_requested(item_id: String, store: bool)

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")

var _content: FirstNightContent
var _cell := Vector2i(-1, -1)

@onready var _title: Label = $Margin/Column/Header/Title as Label
@onready var _close: Button = $Margin/Column/Header/Close as Button
@onready var _rows: VBoxContainer = $Margin/Column/Scroll/Rows as VBoxContainer
@onready var _hint: Label = $Margin/Column/Hint as Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiSkin.panel_style())
	_title.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
	_hint.add_theme_color_override("font_color", UiSkin.TEXT_MUTED)
	UiSkin.apply_close_button(_close)
	_close.pressed.connect(func() -> void: close_requested.emit())
	_title.text = Localized.resolve("ui.storage.panel.title")
	_hint.text = Localized.resolve("ui.storage.panel.hint")


func present(cell: Vector2i, content: FirstNightContent) -> void:
	_cell = cell
	_content = content
	refresh(cell)


func refresh(cell: Vector2i) -> void:
	_cell = cell
	if _content == null or not is_node_ready():
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	var inventory := Session.get_inventory()
	var stored := Session.get_storage_contents(_cell)
	for item_id: String in _content.item_ids():
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, 34.0)
		row.add_theme_constant_override("separation", 5)
		var item_label := Label.new()
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_label.text = "%s   %d / %d" % [
			Localized.resolve(_content.item_label_key(item_id)),
			int(inventory.get(item_id, 0)),
			int(stored.get(item_id, 0)),
		]
		item_label.add_theme_font_size_override("font_size", 10)
		row.add_child(item_label)
		var store_button := _make_transfer_button("→", item_id, true)
		store_button.disabled = int(inventory.get(item_id, 0)) <= 0
		row.add_child(store_button)
		var take_button := _make_transfer_button("←", item_id, false)
		take_button.disabled = int(stored.get(item_id, 0)) <= 0
		row.add_child(take_button)
		_rows.add_child(row)


func _make_transfer_button(caption: String, item_id: String, store: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(36.0, 28.0)
	button.text = caption
	button.tooltip_text = Localized.resolve(
		"ui.storage.transfer.store" if store else "ui.storage.transfer.take"
	)
	button.add_theme_font_size_override("font_size", 12)
	UiSkin.apply_card_button(button)
	button.pressed.connect(func() -> void: transfer_requested.emit(item_id, store))
	return button
