extends PanelContainer

signal close_requested
signal topic_requested(topic_id: String)
signal page_presented(utterance_id: String, page_index: int)
signal utterance_completed
const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const Visual := preload("res://src/characters/character_visual.gd")
@export_range(12,18,1) var text_font_size := 12
const WRAP_FLAGS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
var npc_id := ""
var _view: Dictionary = {}
var _page := 0
var _chunk := 0
var _chunks: Array[String] = []
var _page_complete := false
var _display_generation := 0
var _history_open := false
var _title: Label
var _body: Label
var _portrait
var _topics: ScrollContainer
var _choices: VBoxContainer
var _next_button: Button
var _history: ScrollContainer
var _history_text: Label
var _free_input: LineEdit
var _layout_dimensions := Vector2.ZERO

func _ready() -> void:
	name = "NpcConversationPanel"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel",UiSkin.card_style(UiSkin.CARD_NORMAL,UiSkin.BORDER_HOVER))
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,4)
	add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation",4)
	margin.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	column.add_child(row)
	var portrait_frame := Control.new()
	portrait_frame.name = "Portrait"
	portrait_frame.custom_minimum_size = Vector2(68,76)
	portrait_frame.clip_contents = true
	row.add_child(portrait_frame)
	_portrait = Visual.new()
	_portrait.position = Vector2(34,60)
	_portrait.scale = Vector2(2,2)
	portrait_frame.add_child(_portrait)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation",2)
	row.add_child(text_column)
	_title = label(text_column,13)
	_title.add_theme_color_override("font_color",UiSkin.TEXT_ACCENT)
	_body = label(text_column,text_font_size)
	_body.name = "Reply"
	_body.custom_minimum_size = Vector2(0,52)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_topics = ScrollContainer.new()
	_topics.name = "Topics"
	_topics.custom_minimum_size = Vector2(0,72)
	_topics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_topics.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_topics)
	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices.add_theme_constant_override("separation",2)
	_topics.add_child(_choices)
	_history = ScrollContainer.new()
	_history.name = "History"
	_history.custom_minimum_size = Vector2(0,72)
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_history)
	_history_text = label(_history,12)
	_history_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history.hide()
	var free_input_row := HBoxContainer.new()
	free_input_row.name = "FreeInputRow"
	column.add_child(free_input_row)
	_free_input = LineEdit.new()
	_free_input.name = "FreeInput"
	_free_input.editable = false
	_free_input.focus_mode = Control.FOCUS_NONE
	_free_input.placeholder_text = Localized.resolve("conversation.free_input.placeholder")
	_free_input.add_theme_font_size_override("font_size",11)
	_free_input.add_theme_color_override("font_uneditable_color",UiSkin.TEXT_MUTED)
	_free_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	free_input_row.add_child(_free_input)
	var send := button(free_input_row,"SendButton","conversation.free_input.send")
	send.disabled = true
	send.focus_mode = Control.FOCUS_NONE
	var caption := label(column,10)
	caption.name = "FreeInputCaption"
	caption.text = Localized.resolve("conversation.free_input.caption")
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_color_override("font_color",UiSkin.TEXT_MUTED)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	var history_button := button(footer,"HistoryButton","conversation.history")
	history_button.pressed.connect(_toggle_history)
	_next_button = button(footer,"NextButton","conversation.next")
	_next_button.pressed.connect(_next)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var close := button(footer,"CloseButton","conversation.goodbye")
	close.pressed.connect(func() -> void: close_requested.emit())
	hide()

func fit_to_viewport(dimensions: Vector2) -> void:
	_layout_dimensions = dimensions
	# Reflow at native font size; topics scroll instead of expanding outside the window.
	scale = Vector2.ONE
	custom_minimum_size = Vector2.ZERO
	var previous_size := size
	var height := 244.0 if _topics.visible or _history.visible else 184.0
	size = Vector2(minf(560,maxf(280,dimensions.x-16)),minf(height,dimensions.y-16))
	position = Vector2(maxf(8,(dimensions.x-size.x)*0.5),maxf(8,dimensions.y-size.y-8))
	if visible and not _view.is_empty() and previous_size != size:
		_chunk = 0 # Resizing cannot skip unread portions of the current semantic page.
		call_deferred("_render_page")

func present(view_model: Dictionary) -> void:
	_view = view_model.duplicate(true)
	npc_id = String(_view.get("npc_id",""))
	_page = 0
	_chunk = 0
	_history_open = false
	_history.hide()
	_topics.visible = _choices.get_child_count() > 0
	_title.text = Localized.resolve(String(_view.get("name_key","npc.generic.traveler.name")))
	_portrait.set_appearance(_view.get("appearance",Session.get_npc_appearance(npc_id)))
	_portrait.set_pose(Vector2.DOWN,0,false)
	show()
	fit_to_viewport(get_parent_control().size if get_parent_control() != null else get_viewport_rect().size)
	_render_page()

func _render_page() -> void:
	_display_generation += 1
	var generation := _display_generation
	_page_complete = false
	_next_button.disabled = true
	if _view.get("pages",[]).is_empty(): return
	await get_tree().process_frame
	if not visible or generation != _display_generation: return
	var page: Dictionary = _view.pages[_page]
	var text := String(page.get("text","")) if page.has("text") else Localized.resolve(String(page.get("text_key","")),page.get("text_args",{}))
	_chunks = _split_text(text,maxf(80,_body.size.x),52)
	_chunk = clampi(_chunk,0,_chunks.size()-1)
	_show_chunk()

func _split_text(text: String,width: float,height: float) -> Array[String]:
	var font: Font = _body.get_theme_font("font")
	var result: Array[String] = []
	var chunk := ""
	for word: String in text.split(" ",false):
		if font.get_multiline_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,width,text_font_size,-1,WRAP_FLAGS).y > height:
			if not chunk.is_empty():
				result.append(chunk)
				chunk = ""
			for character: String in word:
				if not chunk.is_empty() and font.get_multiline_string_size(chunk+character,HORIZONTAL_ALIGNMENT_LEFT,width,text_font_size,-1,WRAP_FLAGS).y > height:
					result.append(chunk)
					chunk = ""
				chunk += character
			continue
		var candidate := word if chunk.is_empty() else chunk+" "+word
		if not chunk.is_empty() and font.get_multiline_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,width,text_font_size,-1,WRAP_FLAGS).y > height:
			result.append(chunk)
			chunk = word
		else: chunk = candidate
	if not chunk.is_empty(): result.append(chunk)
	if result.is_empty(): result.append("")
	return result

func _show_chunk() -> void:
	_body.text = _chunks[_chunk]
	_next_button.show()
	_next_button.disabled = false
	_page_complete = false
	if _chunk == _chunks.size()-1:
		var generation := _display_generation
		await get_tree().process_frame
		if not visible or generation != _display_generation or _history_open: return
		_page_complete = true
		page_presented.emit(String(_view.get("utterance_id","")),_page)
		_title.text = Localized.resolve(Session.simulation.npc_catalog.get_label_key(Session.simulation.state.npcs,npc_id,"npc.generic.traveler.name"))
		if _page == _view.pages.size()-1:
			_next_button.hide()
			utterance_completed.emit()

func _next() -> void:
	if _history_open or _chunks.is_empty(): return
	if _chunk < _chunks.size()-1:
		_chunk += 1
		_show_chunk()
	elif _page_complete and _page < _view.pages.size()-1:
		_page += 1
		_chunk = 0
		_render_page()

func show_topics(topics: Array) -> void:
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	for topic: Dictionary in topics:
		var choice := button(_choices,"Topic_"+String(topic.topic_id),String(topic.label_key))
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choice.add_theme_font_size_override("font_size",text_font_size)
		for style_name: String in ["normal","hover","pressed"]:
			var style: StyleBox = choice.get_theme_stylebox(style_name).duplicate()
			style.content_margin_top = 2
			style.content_margin_bottom = 2
			choice.add_theme_stylebox_override(style_name,style)
		choice.pressed.connect(func() -> void: topic_requested.emit(String(topic.topic_id)))
	if _choices.get_child_count() > 0: (_choices.get_child(0) as Button).grab_focus()
	_topics.visible = not topics.is_empty() and not _history_open
	fit_to_viewport(_layout_dimensions if _layout_dimensions != Vector2.ZERO else get_viewport_rect().size)

func set_text_font_size(value: int) -> void:
	text_font_size = clampi(value,12,18)
	_body.add_theme_font_size_override("font_size",text_font_size)
	_chunk = 0
	if visible: _render_page()

func _toggle_history() -> void:
	_history_open = not _history_open
	_history.visible = _history_open
	_topics.visible = not _history_open and _choices.get_child_count()>0
	if _history_open:
		var lines: Array[String] = []
		for entry: Dictionary in Session.simulation.state.npcs.get(npc_id,{}).get("conversation_history",[]):
			for page: Dictionary in entry.pages: lines.append(Localized.resolve(page.text_key,page.text_args))
		_history_text.text = "\n\n".join(lines) if not lines.is_empty() else Localized.resolve("conversation.history.empty")
	elif not _page_complete: _show_chunk()
	fit_to_viewport(_layout_dimensions if _layout_dimensions != Vector2.ZERO else get_viewport_rect().size)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()

func label(parent: Node,font_size: int) -> Label:
	var control := Label.new()
	control.add_theme_font_size_override("font_size",font_size)
	control.add_theme_color_override("font_color",UiSkin.TEXT_PRIMARY)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(control)
	return control

func button(parent: Node,id: String,key: String) -> Button:
	var control := Button.new()
	control.name = id
	control.text = Localized.resolve(key)
	control.add_theme_font_size_override("font_size",12)
	UiSkin.apply_card_button(control)
	parent.add_child(control)
	return control
