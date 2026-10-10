extends VBoxContainer

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
var _items: OptionButton
var _amount: SpinBox
var _stock: Label
var _feedback: Label
var _save: Button
var _report: Array[Dictionary] = []

func _ready() -> void:
	name = "StockReserveEditor"
	add_theme_constant_override("separation", 8)
	var hint := _label("stock.reserve.hint")
	hint.add_theme_color_override("font_color", UiSkin.TEXT_MUTED)
	_items = OptionButton.new()
	_items.name = "ReserveResource"
	_items.fit_to_longest_item = false
	_items.add_theme_font_size_override("font_size", 11)
	_items.item_selected.connect(func(_index: int) -> void: _update_selected())
	add_child(_items)
	_stock = _label("")
	var row := HBoxContainer.new()
	add_child(row)
	var label := _label("stock.reserve.amount")
	remove_child(label)
	row.add_child(label)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount = SpinBox.new()
	_amount.name = "ReserveAmount"
	_amount.min_value = 0
	_amount.max_value = 1000000
	_amount.allow_greater = true
	_amount.step = 1
	_amount.custom_minimum_size.x = 100
	_amount.add_theme_font_size_override("font_size", 11)
	row.add_child(_amount)
	_save = Button.new()
	_save.name = "SetStockReserve"
	_save.text = Localized.resolve("stock.reserve.apply")
	_save.add_theme_font_size_override("font_size", 11)
	UiSkin.apply_card_button(_save)
	_save.pressed.connect(_apply)
	add_child(_save)
	_feedback = _label("")

func refresh() -> void:
	if not is_node_ready(): return
	var item_id := _selected_item()
	_report = Session.get_stock_reserve_report()
	_items.clear()
	var selected := 0
	for row: Dictionary in _report:
		var index := _items.item_count
		_items.add_item(Localized.resolve(String(row.label_key)))
		_items.set_item_metadata(index, String(row.item_id))
		if String(row.item_id) == item_id: selected = index
	if _items.item_count > 0: _items.select(selected)
	_save.disabled = _items.item_count == 0
	_update_selected()

func _selected_item() -> String:
	return String(_items.get_item_metadata(_items.selected)) if _items != null and _items.selected >= 0 else ""

func _update_selected() -> void:
	var index := _items.selected
	if index < 0 or index >= _report.size():
		_stock.text = Localized.resolve("stock.reserve.empty")
		return
	var row: Dictionary = _report[index]
	_stock.text = Localized.resolve("stock.reserve.summary", {"stock": int(row.stock), "reserved": int(row.reserved), "available": int(row.available)})
	_amount.set_value_no_signal(int(row.reserved))

func _apply() -> void:
	_amount.apply()
	var result: Dictionary = Session.set_stock_reserve(_selected_item(), int(_amount.value))
	refresh()
	_feedback.text = Localized.resolve(String(result.message_key), result.get("message_args", {}))

func _label(key: String) -> Label:
	var label := Label.new()
	label.text = Localized.resolve(key)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
	add_child(label)
	return label
