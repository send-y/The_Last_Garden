extends VBoxContainer

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const COLORS := {"good":Color("a8c689"),"problem":Color("e6a184"),"improvement":Color("ebcf73")}
var _current: Label
var _rows: Dictionary = {}

func _ready() -> void:
	name = "HouseholdStatus"
	add_theme_constant_override("separation",6)
	_current = _label(self,10)
	var scroll := ScrollContainer.new()
	scroll.name = "Provisions"
	scroll.custom_minimum_size = Vector2(0,174)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",8)
	scroll.add_child(column)
	for id: String in ["sleep","food","dining","light"]:
		var card := VBoxContainer.new()
		card.name = id.capitalize()
		column.add_child(card)
		var title := _label(card,11)
		title.text = Localized.resolve("household.title." + id)
		var text := _label(card,10)
		var hint := _label(card,9)
		hint.add_theme_color_override("font_color",UiSkin.TEXT_MUTED)
		_rows[id] = {"title":title,"text":text,"hint":hint}
	var footer := _label(self,9)
	footer.text = Localized.resolve("household.scope")
	footer.add_theme_color_override("font_color",UiSkin.TEXT_MUTED)

func refresh(report: Dictionary, npc_id: String) -> void:
	var physical: Dictionary = Session.get_npc_needs(npc_id)
	var current: Array[String] = []
	if float(physical.get("hunger",100)) <= Session.simulation.npc_autonomy.HUNGRY_THRESHOLD:
		current.append(Localized.resolve("household.current.hungry"))
	if float(physical.get("restedness",100)) < 55:
		current.append(Localized.resolve("household.current.sleepy"))
	if float(physical.get("energy",100)) <= Session.simulation.npc_autonomy.CRITICAL_ENERGY_THRESHOLD:
		current.append(Localized.resolve("household.current.tired"))
	_current.text = Localized.resolve("household.current.stable") if current.is_empty() else Localized.resolve("household.current",{"needs":", ".join(current)})
	for row: Dictionary in report.get("rows",[]):
		var controls: Dictionary = _rows[row.id]
		var severity := String(row.severity)
		controls.title.text = Localized.resolve("household.row_heading",{"topic":Localized.resolve("household.title." + String(row.id)),"status":Localized.resolve("household.severity." + severity)})
		controls.title.add_theme_color_override("font_color",COLORS.get(severity,UiSkin.TEXT_PRIMARY))
		controls.text.text = Localized.resolve(String(row.text_key))
		controls.hint.visible = not String(row.hint_key).is_empty()
		controls.hint.text = "" if not controls.hint.visible else Localized.resolve(String(row.hint_key),row.get("hint_args",{}))
		controls.title.tooltip_text = Localized.resolve("household.severity." + severity)

static func home_text(home: Dictionary) -> String:
	if String(home.get("place_id","")).is_empty():
		return Localized.resolve("household.home.unassigned")
	if String(home.get("building_id","")).is_empty():
		return Localized.resolve("household.home.missing")
	var bid := String(home.building_id)
	var label := Localized.resolve(String(Session.simulation.building_catalog.get_definition(bid).label_key))
	var location := Localized.resolve("household.home.base" if String(home.room_id) == "core:base_house" else ("household.home.room" if not String(home.room_id).is_empty() else "household.home.invalid"))
	return Localized.resolve("household.home.location",{"place":label,"location":location,"x":int(home.cell[0]),"y":int(home.cell[1])})

func _label(parent: Node, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",UiSkin.TEXT_PRIMARY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
