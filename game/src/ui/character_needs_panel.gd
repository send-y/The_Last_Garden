extends PanelContainer

signal close_requested
signal rest_requested
signal housing_requested(character_id: String)
signal conversation_requested(npc_id: String)
const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const Status := preload("res://src/ui/need_status_hud.gd")
const HouseholdCard := preload("res://src/ui/household_status_card.gd")
const GoalCard := preload("res://src/ui/npc_goal_card.gd")
const CompactLayout := preload("res://src/ui/compact_panel_layout.gd")
var npc_id := ""
var _title: Label
var _activity: Label
var _rows: Dictionary = {}
var _reasons: Label
var _rest: Button
var _work_controls: HBoxContainer
var _work_buttons: Dictionary = {}
var _work_hint: Label
var _housing: Button
var _home_summary: Label
var _tabs: HBoxContainer
var _tab_buttons: Dictionary = {}
var _stats_content: VBoxContainer
var _psychology_column: VBoxContainer
var _household
var _goal_card
var _profile: ScrollContainer
var _profile_text: Label
var _talk: Button
var _body_scroll: ScrollContainer
var _goal_actions: VBoxContainer

func _ready() -> void:
	name = "CharacterNeedsPanel"
	custom_minimum_size = Vector2(380, 0)
	add_theme_stylebox_override("panel", UiSkin.panel_style())
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 13)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = _label(header, 14)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "×"
	close.add_theme_font_size_override("font_size", 14)
	UiSkin.apply_card_button(close)
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)
	_activity = _label(column, 10)
	_home_summary = _label(column,10)
	_home_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tabs = HBoxContainer.new()
	column.add_child(_tabs)
	for id: String in ["state","household","plans","profile"]:
		var tab := Button.new()
		tab.name = id.capitalize() + "Tab"
		tab.text = Localized.resolve("conversation.profile.tab" if id == "profile" else "household.tab." + id)
		tab.add_theme_font_size_override("font_size",11)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		UiSkin.apply_tab_button(tab)
		tab.pressed.connect(func() -> void: _select_tab(id))
		_tabs.add_child(tab)
		_tab_buttons[id] = tab
	_stats_content = VBoxContainer.new()
	column.add_child(_stats_content)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation",12)
	_stats_content.add_child(stats)
	var physical_column := VBoxContainer.new()
	physical_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(physical_column)
	_psychology_column = VBoxContainer.new()
	_psychology_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(_psychology_column)
	for key: String in ["hunger", "energy", "restedness", "mood", "wellbeing"]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		(physical_column if Status.KEYS.has(key) else _psychology_column).add_child(row)
		var text := _label(row, 11)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 5)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var background := StyleBoxFlat.new()
		background.bg_color = Color("30272e")
		bar.add_theme_stylebox_override("background", background)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Status.COLORS.get(key, Color("b18baa"))
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		row.tooltip_text = Localized.resolve("needs.hint." + key)
		_rows[key] = {"row": row, "text": text, "bar": bar}
	_work_controls = HBoxContainer.new()
	_work_controls.name = "WorkPermissions"
	_stats_content.add_child(_work_controls)
	for kind: String in ["water", "gather", "build"]:
		var button := CheckButton.new()
		button.name = kind.capitalize() + "Permission"
		button.text = Localized.resolve("npc.work." + kind)
		button.tooltip_text = Localized.resolve("npc.work.permissions_hint")
		button.add_theme_font_size_override("font_size", 10)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggled.connect(func(enabled: bool) -> void: Session.set_npc_work_enabled(npc_id, kind, enabled))
		_work_controls.add_child(button)
		_work_buttons[kind] = button
	_work_hint = _label(_stats_content, 9)
	_work_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.name = "Explanations"
	scroll.custom_minimum_size = Vector2(0, 84)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stats_content.add_child(scroll)
	_reasons = _label(scroll, 10)
	_reasons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reasons.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rest = Button.new()
	_rest.name = "RestButton"
	_rest.text = Localized.resolve("needs.rest_button")
	_rest.add_theme_font_size_override("font_size", 11)
	UiSkin.apply_card_button(_rest)
	_rest.pressed.connect(func() -> void: rest_requested.emit())
	_stats_content.add_child(_rest)
	_household = HouseholdCard.new()
	column.add_child(_household)
	_goal_card = GoalCard.new()
	column.add_child(_goal_card)
	_housing = Button.new()
	_housing.name = "HousingButton"
	_housing.text = Localized.resolve("housing.manage")
	_housing.add_theme_font_size_override("font_size", 11)
	UiSkin.apply_card_button(_housing)
	_housing.pressed.connect(func() -> void: housing_requested.emit("core:player" if npc_id.is_empty() else npc_id))
	column.add_child(_housing)
	_profile = ScrollContainer.new()
	_profile.name = "KnownProfile"
	_profile.custom_minimum_size = Vector2(0,160)
	_profile.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_profile)
	_profile_text = _label(_profile,11)
	_profile_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_talk = Button.new()
	_talk.name = "TalkButton"
	_talk.text = Localized.resolve("conversation.open")
	_talk.add_theme_font_size_override("font_size",11)
	UiSkin.apply_card_button(_talk)
	_talk.pressed.connect(func() -> void: conversation_requested.emit(npc_id))
	column.add_child(_talk)
	_body_scroll = ScrollContainer.new()
	_body_scroll.name = "CharacterDetails"
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body_scroll)
	column.move_child(_body_scroll, _tabs.get_index() + 1)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	_body_scroll.add_child(body)
	for content: Control in [_activity, _home_summary, _stats_content, _household, _goal_card, _profile]:
		content.reparent(body)
	_goal_actions = VBoxContainer.new()
	_goal_actions.name = "GoalActions"
	_goal_actions.add_theme_constant_override("separation", 5)
	column.add_child(_goal_actions)
	column.move_child(_goal_actions, _housing.get_index())
	_goal_card._defer.reparent(_goal_actions)
	_goal_card._resume.reparent(_goal_actions)
	_rest.reparent(column)
	column.move_child(_rest, _housing.get_index())
	_select_tab("state")
	hide()

func present(character_id: String = "") -> void:
	npc_id = character_id
	_select_tab("state")
	refresh()
	show()

func refresh() -> void:
	var is_player := npc_id.is_empty()
	_tabs.visible = not is_player
	_home_summary.visible = not is_player
	_psychology_column.visible = not is_player
	_talk.visible = not is_player
	var physical: Dictionary = Session.get_player_needs() if is_player else Session.get_npc_needs(npc_id)
	if physical.is_empty() or (not is_player and not Session.is_npc_visible(npc_id)):
		close_requested.emit()
		return
	var name_key: String = "needs.player_title" if is_player else Session.simulation.npc_catalog.get_label_key(Session.simulation.get_npcs(), npc_id, "npc.generic.traveler.name")
	_title.text = Localized.resolve(name_key)
	_activity.text = Localized.resolve("needs.player_activity") if is_player else Localized.resolve(Session.get_npc_activity_key(npc_id))
	var psychology: Dictionary = {} if is_player else Session.get_npc_psychology(npc_id)
	for key: String in _rows:
		var row: Dictionary = _rows[key]
		var visible_row := physical.has(key) or psychology.has(key)
		row.row.visible = visible_row
		if visible_row:
			var current := float(physical.get(key, psychology.get(key, 0)))
			row.text.text = "%s  %d/100" % [Localized.resolve("needs." + key), roundi(current)]
			row.bar.value = current
	_rest.visible = is_player
	_work_controls.visible = not is_player
	_work_hint.visible = not is_player
	_housing.disabled = not is_player and not bool(Session.simulation.state.npcs[npc_id].get("known", false))
	if not is_player:
		var summary := Session.get_npc_profile_summary(npc_id)
		var facts: Array[String] = []
		for fact: Dictionary in summary.get("facts",[]):
			facts.append(Localized.resolve(String(fact.label_key)) + ": " + Localized.resolve("{value}",{"value":fact.value}))
		_profile_text.text = "\n\n".join(facts) if not facts.is_empty() else Localized.resolve("conversation.profile.empty")
		var household: Dictionary = Session.get_npc_household_status(npc_id)
		_home_summary.text = HouseholdCard.home_text(household.get("home",{}))
		_household.refresh(household,npc_id)
		_goal_card.refresh(npc_id)
		var work: Dictionary = Session.get_npc_work_status(npc_id)
		var known: bool = bool(Session.simulation.state.npcs[npc_id].get("known", false))
		for kind: String in _work_buttons:
			_work_buttons[kind].disabled = not known
			_work_buttons[kind].set_pressed_no_signal(bool(work.get("options", {}).get(kind, false)))
		_work_hint.text = Localized.resolve("npc.work.permissions_hint" if known else "npc.work.meet_first")
	var lines: Array[String] = []
	if is_player:
		for key: String in Status.KEYS:
			lines.append(Localized.resolve("needs.hint." + key))
		lines.append(Localized.resolve("needs.roof.full" if Session.is_roof_covered() else "needs.roof.poor"))
	else:
		lines.append(Localized.resolve("needs.reasons_title"))
		for reason: Dictionary in psychology.get("reasons", []):
			lines.append("%+d  %s" % [int(reason.amount), Localized.resolve(String(reason.key))])
		lines.append(Localized.resolve("needs.hint.wellbeing"))
	_reasons.text = "\n".join(lines)
	call_deferred("_fit_to_viewport")

func _select_tab(id: String) -> void:
	_stats_content.visible = id == "state"
	_household.visible = id == "household" and not npc_id.is_empty()
	_goal_card.visible = id == "plans" and not npc_id.is_empty()
	_profile.visible = id == "profile" and not npc_id.is_empty()
	_goal_actions.visible = id == "plans" and not npc_id.is_empty()
	_body_scroll.scroll_vertical = 0
	for tab: String in _tab_buttons:
		_tab_buttons[tab].set_pressed_no_signal(tab == id)
	call_deferred("_fit_to_viewport")

func _fit_to_viewport() -> void:
	if visible and get_parent_control() != null:
		CompactLayout.fit_centered(self,get_parent_control().size)

func fit_to_viewport(available: Vector2) -> void:
	if _body_scroll == null: return
	available = available.min(get_viewport_rect().size)
	custom_minimum_size.x = minf(380, available.x - 16)
	_body_scroll.custom_minimum_size.y = 0
	var overhead := get_combined_minimum_size().y
	_body_scroll.custom_minimum_size.y = minf(320, maxf(48, available.y - 16 - overhead))
	scale = Vector2.ONE
	size = Vector2(minf(520, available.x - 16), 0)
	size.y = get_combined_minimum_size().y
	position = (available - size) * 0.5

func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
	parent.add_child(label)
	return label
