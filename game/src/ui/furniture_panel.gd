extends PanelContainer

signal close_requested
const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
var cell := Vector2i(-1,-1)
var _title: Label
var _status: Label
var _foods: OptionButton
var _food_ids: Array[String] = []
var _eat: Button
var _rest: Button
var _feedback: Label

func _ready() -> void:
	name = "FurniturePanel"
	custom_minimum_size = Vector2(300,0)
	add_theme_stylebox_override("panel",UiSkin.panel_style())
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side,12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation",7)
	margin.add_child(column)
	_title = _label(column,14)
	_status = _label(column,11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_foods = OptionButton.new()
	_foods.name = "Foods"
	_foods.fit_to_longest_item = false
	_foods.add_theme_font_size_override("font_size",11)
	column.add_child(_foods)
	_eat = _button(column,"EatButton","furniture.eat")
	_eat.pressed.connect(func() -> void:
		if _foods.selected >= 0 and _foods.selected < _food_ids.size():
			_act("eat",_food_ids[_foods.selected])
	)
	_rest = _button(column,"RestButton","furniture.rest")
	_rest.pressed.connect(func() -> void: _act("rest"))
	_feedback = _label(column,10)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(column,"CloseButton","housing.close").pressed.connect(func() -> void: close_requested.emit())
	hide()

func present(at: Vector2i) -> void:
	cell = at
	_feedback.text = ""
	refresh()
	show()

func refresh() -> void:
	var data: Dictionary = Session.get_furniture_options(cell)
	if not ["core:chair","core:table"].has(String(data.building_id)):
		close_requested.emit()
		return
	_title.text = Localized.resolve(String(Session.simulation.building_catalog.get_definition(String(data.building_id)).label_key))
	_status.text = Localized.resolve("furniture.seat.available" if not data.rest.is_empty() else "furniture.failure.seat")
	_status.text += "\n" + Localized.resolve("furniture.light.day" if Session.get_minute_of_day() >= 7 * 60 and Session.get_minute_of_day() < 18 * 60 else ("furniture.light.seat" if bool(data.lit) else "furniture.light.dark"))
	var selected := "" if _foods.selected < 0 or _foods.selected >= _food_ids.size() else _food_ids[_foods.selected]
	_foods.clear()
	_food_ids.clear()
	for item: String in data.foods:
		_food_ids.append(item)
		_foods.add_item("%s ×%d" % [Localized.resolve(Session.simulation.content.item_label_key(item)),Session.simulation.get_item_count(item)])
		if item == selected:
			_foods.select(_food_ids.size()-1)
	_eat.disabled = data.meal.is_empty() or _food_ids.is_empty()
	_rest.disabled = data.rest.is_empty()
	_eat.tooltip_text = Localized.resolve("furniture.failure.seat" if data.meal.is_empty() else "furniture.meal.hint")
	_rest.tooltip_text = Localized.resolve("furniture.rest.hint")

func _act(action: String, item: String = "") -> void:
	var result: Dictionary = Session.execute_furniture_command(cell,action,item)
	refresh()
	_feedback.text = Localized.resolve(String(result.message_key),result.get("message_args",{}))

func _label(parent: Node, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",UiSkin.TEXT_PRIMARY)
	parent.add_child(label)
	return label

func _button(parent: Node, id: String, key: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = Localized.resolve(key)
	button.add_theme_font_size_override("font_size",11)
	UiSkin.apply_card_button(button)
	parent.add_child(button)
	return button
