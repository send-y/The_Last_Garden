extends VBoxContainer

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
var _intent: Label
var _status: Label
var _details: Label
var _defer: Button
var _resume: Button
var _housing: Label
var npc_id := ""

func _ready() -> void:
	name = "NpcGoalCard"
	add_theme_constant_override("separation",6)
	_housing = _label(self,10)
	_housing.name = "HomePolicy"
	_intent = _label(self,11)
	_status = _label(self,10)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0,170)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_details = _label(scroll,10)
	_defer = _button("DeferGoal","npc.goal.defer")
	_defer.pressed.connect(func() -> void: Session.defer_npc_personal_goal(npc_id))
	_resume = _button("ResumeGoals","npc.goal.resume")
	_resume.pressed.connect(func() -> void: Session.defer_npc_personal_goal(npc_id,true))

func refresh(id: String) -> void:
	npc_id = id
	var report: Dictionary = Session.get_npc_personal_goal(id)
	var goal: Dictionary = report.get("goal",{})
	var state := String(report.get("status","idle"))
	var home: Dictionary = report.get("housing", {})
	_housing.visible = not home.is_empty() and state not in ["unknown", "inactive"]
	var mode := String(home.get("mode", ""))
	_housing.text = Localized.resolve("npc.goal.housing", {"mode": Localized.text_reference("home.mode." + mode)}) if _housing.visible and not mode.is_empty() else Localized.resolve("household.home.unassigned")
	var expansion: Dictionary = report.get("expansion", {})
	var wanted := String(goal.get("building_id", expansion.get("building_id", "")))
	_intent.text = Localized.resolve("npc.goal.intent." + wanted.trim_prefix("core:")) if not wanted.is_empty() else Localized.resolve("npc.goal.none")
	_status.text = Localized.resolve("npc.goal.status." + state)
	_status.add_theme_color_override("font_color",Color("a8c689") if state == "done" else Color("ebcf73"))
	var lines: Array[String] = []
	var production: Dictionary = report.get("production",{})
	if not production.is_empty():
		lines.append(Localized.resolve("npc.production." + String(production.reason), {"amount":int(production.get("amount",0)),"current":int(production.get("current",0)),"total":int(production.get("total",0))}))
	if not expansion.is_empty() and state not in ["unknown", "inactive"]:
		lines.append(Localized.resolve("npc.goal.expansion", {"item": Localized.text_reference(Session.simulation.building_catalog.get_definition(String(expansion.building_id)).label_key)}))
		lines.append(Localized.resolve(String(expansion.reason_key)))
	for item: String in report.get("protected", {}):
		lines.append(Localized.resolve("npc.goal.protected", {"item": Localized.text_reference(Session.simulation.content.item_label_key(item)), "amount": int(report.protected[item])}))
	var preferences := preload("res://src/characters/npc_preferences.gd")
	var profile: Dictionary = Session.simulation.state.get("npc_profiles",{}).get(id,{})
	var motive := preferences.explain(profile,{"kind":"build"})
	if not String(motive.fact_id).is_empty() and Session.simulation.state.npcs.get(id,{}).get("known_facts",{}).has(motive.fact_id):
		lines.append(Localized.resolve(motive.reason_key,motive.args))
	if not goal.is_empty():
		lines.append(Localized.resolve(String(goal.reason_key)))
		lines.append(Localized.resolve("npc.goal.location",{"x":int(goal.cell[0]),"y":int(goal.cell[1])}))
		for item: String in report.get("missing",{}):
			lines.append(Localized.resolve("npc.goal.missing",{"item":Localized.text_reference(Session.simulation.content.item_label_key(item)),"amount":int(report.missing[item])}))
		var blueprint: Dictionary = Session.simulation._find_blueprint(goal.cell)
		if not blueprint.is_empty():
			lines.append(Localized.resolve("npc.goal.progress",{"current":int(blueprint.work_progress_minutes),"total":int(blueprint.required_work_minutes)}))
	lines.append(Localized.resolve("npc.goal.scope"))
	var completed: Array = report.get("completed",[])
	if not completed.is_empty():
		lines.append("\n" + Localized.resolve("npc.goal.results"))
		for result: Dictionary in completed:
			lines.append(Localized.resolve("npc.goal.result",{"item":Localized.text_reference(Session.simulation.building_catalog.get_definition(String(result.building_id)).label_key),"x":int(result.cell[0]),"y":int(result.cell[1])}))
	_details.text = "\n".join(lines)
	_defer.visible = not goal.is_empty() and String(goal.status) == "pending" and state not in ["unknown","inactive"]
	_resume.visible = not report.get("declined",[]).is_empty() and state not in ["unknown","inactive"]

func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",UiSkin.TEXT_PRIMARY)
	parent.add_child(label)
	return label

func _button(id: String, text_key: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = Localized.resolve(text_key)
	button.add_theme_font_size_override("font_size",11)
	UiSkin.apply_card_button(button)
	add_child(button)
	return button
