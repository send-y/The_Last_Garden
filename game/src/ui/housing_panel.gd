extends PanelContainer

signal close_requested
const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
var character_id := "core:player"
var _title: Label
var _status: Label
var _choices: OptionButton
var _assign: Button
var _release: Button
var _feedback: Label
var _ids: Array[String] = []
var _places: Array[Dictionary] = []
var _mode: OptionButton
var _set_mode: Button
var _members: Label
var _room_hint: Label
var _room_id := ""
var _scroll: ScrollContainer
const MODES: Array[String] = ["settlement", "personal", "shared"]

func _ready() -> void:
	name = "HousingPanel"
	custom_minimum_size = Vector2(330, 0)
	add_theme_stylebox_override("panel", UiSkin.panel_style())
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 13)
	add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_title = _label(column, 14)
	_scroll = ScrollContainer.new()
	_scroll.name = "HousingDetails"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	_scroll.add_child(body)
	_status = _label(body, 11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choices = OptionButton.new()
	_choices.name = "SleepPlaces"
	_choices.fit_to_longest_item = false
	_choices.add_theme_font_size_override("font_size", 10)
	_choices.item_selected.connect(func(_index: int) -> void:
		_update_assign()
		_update_room()
	)
	body.add_child(_choices)
	_members = _label(body, 11)
	_members.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode = OptionButton.new()
	_mode.name = "HomeMode"
	_mode.fit_to_longest_item = false
	_mode.add_theme_font_size_override("font_size", 11)
	for mode: String in MODES:
		_mode.add_item(Localized.resolve("home.mode." + mode))
	body.add_child(_mode)
	_set_mode = _button(body, "SetHomeMode", "home.mode.apply")
	_set_mode.pressed.connect(func() -> void:
		if _room_id.is_empty() or _mode.selected < 0: return
		var result: Dictionary = Session.set_home_mode(_room_id, MODES[_mode.selected])
		refresh()
		_feedback.text = Localized.resolve(String(result.message_key), result.get("message_args", {}))
	)
	_room_hint = _label(body, 10)
	_room_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assign = _button(body, "AssignButton", "housing.assign")
	_assign.pressed.connect(func() -> void:
		if _choices.selected >= 0 and _choices.selected < _ids.size():
			var result: Dictionary = Session.assign_sleep_place(character_id, _ids[_choices.selected])
			refresh()
			_feedback.text = Localized.resolve(String(result.message_key), result.get("message_args", {}))
	)
	_release = _button(body, "ReleaseButton", "housing.release")
	_release.pressed.connect(func() -> void:
		var result: Dictionary = Session.assign_sleep_place(character_id, "")
		refresh()
		_feedback.text = Localized.resolve(String(result.message_key), result.get("message_args", {}))
	)
	var actions := HBoxContainer.new()
	actions.name = "AssignmentActions"
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	_assign.reparent(actions)
	_release.reparent(actions)
	_assign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_release.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback = _label(body, 10)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := _label(body, 10)
	hint.text = Localized.resolve("housing.hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(column, "CloseButton", "housing.close").pressed.connect(func() -> void: close_requested.emit())
	hide()

func present(id: String) -> void:
	character_id = id
	_feedback.text = ""
	refresh()
	show()

func refresh() -> void:
	var home: Dictionary = Session.get_character_home(character_id)
	_title.text = Localized.resolve("housing.title") + ": " + _character_name(character_id)
	var current := String(home.place_id)
	var home_label := Localized.resolve("housing.no_place")
	if not current.is_empty():
		home_label = _place_name(home) if not String(home.building_id).is_empty() else Localized.resolve("housing.missing")
	_status.text = Localized.resolve("housing.current", {"place": home_label})
	if not bool(home.valid):
		_status.text += "\n" + Localized.resolve(String(home.reason_key))
	else:
		_status.text += "\n" + Localized.resolve("needs.roof.full" if bool(home.covered) else "needs.roof.poor")
	_choices.clear()
	_ids.clear()
	_places.clear()
	var first_free := -1
	var selected := -1
	for place: Dictionary in Session.get_sleep_places():
		var index := _ids.size()
		var owner := String(place.owner_id)
		var available := bool(place.valid) and (owner.is_empty() or owner == character_id)
		var label := _place_name(place)
		if not owner.is_empty():
			label += " · " + _character_name(owner)
		elif not bool(place.valid):
			label += " · " + Localized.resolve("housing.unavailable")
		_choices.add_item(label)
		_choices.set_item_disabled(index, not available)
		_choices.set_item_tooltip(index, Localized.resolve(String(place.reason_key)))
		_ids.append(String(place.place_id))
		_places.append(place)
		if available and first_free < 0:
			first_free = index
		if String(place.place_id) == current and available:
			selected = index
	_choices.select(selected if selected >= 0 else first_free)
	_release.disabled = current.is_empty()
	_update_assign()
	_update_room()
	fit_to_viewport(get_parent_control().size if get_parent_control() != null else get_viewport_rect().size)

func _update_room() -> void:
	_room_id = ""
	if _choices.selected >= 0 and _choices.selected < _places.size():
		_room_id = String(_places[_choices.selected].get("room_id", ""))
	var report: Dictionary = {}
	for room: Dictionary in Session.get_housing_rooms():
		if String(room.room_id) == _room_id:
			report = room
			break
	var mode := String(report.get("mode", "settlement"))
	_mode.select(maxi(MODES.find(mode), 0))
	var fixed := _room_id == "core:base_house"
	_mode.disabled = fixed or report.is_empty() or not bool(report.get("valid", false))
	_set_mode.disabled = _mode.disabled
	var names: Array[String] = []
	for id: String in report.get("members", []): names.append(_character_name(id))
	_members.text = Localized.resolve("home.members", {"names": ", ".join(names) if not names.is_empty() else Localized.resolve("home.members.none")})
	_room_hint.text = Localized.resolve("home.mode.fixed" if fixed else "home.mode.hint")

func fit_to_viewport(available: Vector2) -> void:
	if _scroll == null: return
	available = available.min(get_viewport_rect().size)
	var width := minf(380, maxf(280, available.x - 16))
	custom_minimum_size.x = minf(330, width)
	_scroll.custom_minimum_size.y = 0
	var overhead := get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = minf(300, maxf(48, available.y - 16 - overhead))
	scale = Vector2.ONE
	size = Vector2(width, 0)
	size.y = get_combined_minimum_size().y
	position = (available - size) * 0.5

func _update_assign() -> void:
	_assign.disabled = _choices.selected < 0 or _choices.is_item_disabled(_choices.selected)

func _character_name(id: String) -> String:
	if id == "core:player":
		return Localized.resolve("housing.player")
	return Localized.resolve(Session.simulation.npc_catalog.get_label_key(Session.simulation.get_npcs(), id, "npc.generic.traveler.name"))

func _place_name(place: Dictionary) -> String:
	var label := Localized.resolve(String(Session.simulation.building_catalog.get_definition(String(place.building_id)).label_key))
	var cell: Array = place.cell
	return "%s (%d, %d)" % [label, cell[0], cell[1]]

func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
	parent.add_child(label)
	return label

func _button(parent: Node, id: String, key: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = Localized.resolve(key)
	button.add_theme_font_size_override("font_size", 11)
	UiSkin.apply_card_button(button)
	parent.add_child(button)
	return button
