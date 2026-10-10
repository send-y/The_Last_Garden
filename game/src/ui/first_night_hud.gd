class_name FirstNightHud
extends Control
signal build_mode_toggled(active: bool)
signal building_selected(building_id: String)
signal crafting_recipe_requested(cell: Vector2i, recipe_id: String)
signal npc_conversation_opened(npc_id: String)

const Content := preload("res://src/content/first_night_content.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const CraftingPanelScene: PackedScene = preload(
	"res://src/ui/crafting_panel.tscn"
)
const StoragePanelScene: PackedScene = preload("res://src/ui/storage_panel.tscn")
const ConstructionPaletteScene: PackedScene = preload(
	"res://src/ui/construction_palette.tscn"
)
const MarkerPanelScene: PackedScene = preload("res://src/ui/marker_panel.tscn")
const MarkerOverlayScript := preload("res://src/ui/marker_overlay.gd")
const PlaceholderIcon := preload("res://src/items/item_placeholder_icon.gd")
const CompactLayout := preload("res://src/ui/compact_panel_layout.gd")

var _content_data: FirstNightContent = Content.new()
var _time_label: Label
var _inventory_label: Label
var _objective_label: Label
var _selection_label: Label
var _message_label: Label
var _tasks_background: TextureRect
var _tasks_toggle: Button
var _tasks_expanded: bool = true
var _crafting_panel: CraftingPanel
var _storage_panel: StoragePanel
var _construction_palette: ConstructionPalette
var _crafting_cell: Vector2i = Vector2i(-1, -1)
var _storage_cell: Vector2i = Vector2i(-1, -1)
var _inventory_was_paused: bool = false
var _marker_panel: PanelContainer
var _marker_overlay: Control
var _marker_was_paused: bool = false
var _hotbar_buttons: Array[Button] = []
var _hotbar_icons: Array[TextureRect] = []
var _hotbar_charges: Array[Label] = []
var _needs_hud: Control
var _needs_panel: PanelContainer
var _housing_panel: PanelContainer
var _furniture_panel: PanelContainer
var _needs_was_paused := false
var _selected_npc := ""
var _npc_needs_button: Button
var _energy_fill: ColorRect
var _energy_label: Label
var _farming_panel: FarmingPanel
var _conversation_panel: PanelContainer
var _conversation_was_paused := false

@onready var _inventory_panel: InventoryPanel = (
	$InventoryPanel as InventoryPanel
)
@onready var _inventory_backdrop: ColorRect = (
	$InventoryBackdrop as ColorRect
)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# This fullscreen dimmer is visual only. Let modal panels receive GUI input.
	_inventory_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_needs_panel = preload("res://src/ui/character_needs_panel.gd").new()
	_needs_panel.z_index = 24
	add_child(_needs_panel)
	_housing_panel = preload("res://src/ui/housing_panel.gd").new()
	_housing_panel.z_index = 24
	add_child(_housing_panel)
	_furniture_panel = preload("res://src/ui/furniture_panel.gd").new()
	_furniture_panel.z_index = 24
	add_child(_furniture_panel)
	_furniture_panel.close_requested.connect(func() -> void: _set_needs_open(false))
	_housing_panel.close_requested.connect(func() -> void: _set_needs_open(false))
	_needs_panel.housing_requested.connect(func(character_id: String) -> void:
		_needs_panel.hide()
		_housing_panel.present(character_id)
		CompactLayout.fit_centered(_housing_panel, size)
	)
	_needs_panel.close_requested.connect(func() -> void: _set_needs_open(false))
	_needs_panel.conversation_requested.connect(open_npc_conversation)
	_needs_panel.rest_requested.connect(func() -> void:
		_set_needs_open(false)
		Session.rest_player()
	)
	Session.state_reloaded.connect(func() -> void: _set_needs_open(false))
	_conversation_panel = preload("res://src/ui/npc_conversation_panel.tscn").instantiate()
	_conversation_panel.z_index = 30
	add_child(_conversation_panel)
	_conversation_panel.close_requested.connect(_close_npc_conversation)
	_conversation_panel.topic_requested.connect(_choose_conversation_topic)
	_conversation_panel.page_presented.connect(func(utterance_id: String,page_index: int) -> void:
		Session.acknowledge_npc_utterance(_conversation_panel.npc_id,utterance_id,page_index)
	)
	_conversation_panel.utterance_completed.connect(func() -> void:
		_conversation_panel.show_topics(Session.get_npc_conversation_topics(_conversation_panel.npc_id))
	)
	Session.state_reloaded.connect(func() -> void: _close_npc_conversation(false))
	resized.connect(func() -> void:
		if _conversation_panel.visible: _conversation_panel.fit_to_viewport(size)
	)
	_farming_panel = preload("res://src/ui/farming_panel.gd").new()
	_farming_panel.z_index = 23
	add_child(_farming_panel)
	_farming_panel.close_requested.connect(func() -> void: _set_farming_open(false))
	_build_marker_ui()
	_inventory_panel.close_requested.connect(
		_on_inventory_close_requested
	)
	_inventory_panel.eat_food_requested.connect(_on_eat_food_requested)
	_inventory_panel.extract_seeds_requested.connect(_on_extract_seeds_requested)
	_inventory_panel.inventory_layout_changed.connect(
		_on_inventory_layout_changed
	)
	_inventory_panel.drop_requested.connect(_on_inventory_drop_requested)
	_inventory_panel.hotbar_drop_requested.connect(_on_inventory_hotbar_drop_requested)
	_inventory_panel.equip_requested.connect(_on_inventory_equip_requested)
	_inventory_panel.set_external_hotbar_target(get_node("Hotbar") as Control)
	_inventory_panel.hide()
	_inventory_backdrop.hide()
	Session.state_changed.connect(refresh)
	Session.state_reloaded.connect(refresh)
	Session.time_changed.connect(refresh)
	Session.pause_changed.connect(_on_pause_changed)
	Session.message_emitted.connect(_on_message)
	refresh()


func _process(_delta: float) -> void:
	for panel: Control in [_crafting_panel, _storage_panel, _farming_panel, _marker_panel, _needs_panel, _housing_panel, _furniture_panel]:
		if is_instance_valid(panel) and panel.visible:
			CompactLayout.fit_centered(panel, size)


func set_selection(selection: Dictionary) -> void:
	_selected_npc = String(selection.get("object_id", ""))
	_npc_needs_button.visible = Session.is_npc_visible(_selected_npc)
	var kind: String = String(selection.get("kind", "none"))
	if kind == "cell":
		_selection_label.text = Localized.resolve("ui.hud.selection.cell", {
			"x": int(selection.get("x", -1)),
			"y": int(selection.get("y", -1)),
		})
		return
	if kind == "interactable" or kind == "blueprint" or kind == "structure" or kind == "storage":
		var status: String = String(selection.get("status", ""))
		var in_range: bool = bool(selection.get("in_range", false))
		if bool(selection.get("sleep_preview", false)):
			_selection_label.text = Localized.resolve(
				"sleep.selection.in_range" if in_range else "sleep.selection.out_of_range",
				{
					"label": String(selection.get("label", "")),
					"status": status,
				}
			)
			return
		var action_hint_key: String = String(selection.get("action_hint_key", ""))
		if not action_hint_key.is_empty():
			var required_tool_item_id: String = String(
				selection.get("required_tool_item_id", "")
			)
			var resource_selection_key: String = (
				"resource.selection.in_range"
				if in_range
				else "resource.selection.out_of_range"
			)
			_selection_label.text = Localized.resolve(resource_selection_key, {
				"label": String(selection.get("label", "")),
				"status": " — " + status if not status.is_empty() else "",
				"action": Localized.text_reference(action_hint_key, {
					"tool": Localized.text_reference(
						_content_data.item_label_key(required_tool_item_id)
					),
				}),
			})
			return
		var selection_key: String
		if in_range:
			selection_key = (
				"ui.hud.selection.in_range_with_status"
				if not status.is_empty()
				else "ui.hud.selection.in_range"
			)
		else:
			selection_key = (
				"ui.hud.selection.out_of_range_with_status"
				if not status.is_empty()
				else "ui.hud.selection.out_of_range"
			)
		_selection_label.text = Localized.resolve(selection_key, {
			"label": String(selection.get("label", "")),
			"status": status,
		})
		return
	_selection_label.text = Localized.resolve("ui.hud.selection.none")


func request_marker_creation() -> void:
	_show_marker_panel()
	_marker_panel.call("show_creation")


func toggle_marker_list() -> void:
	if _marker_panel.visible:
		_close_marker_panel()
		return
	_show_marker_panel()
	_marker_panel.call("show_list", Session.get_markers())


func is_marker_list_open() -> bool:
	return bool(_marker_panel.call("is_list_open"))


func _build_marker_ui() -> void:
	_marker_overlay = MarkerOverlayScript.new() as Control
	add_child(_marker_overlay)
	move_child(_marker_overlay, 0)
	_marker_panel = MarkerPanelScene.instantiate() as PanelContainer
	_marker_panel.connect("close_requested", _close_marker_panel)
	_marker_panel.connect("create_requested", _on_marker_create_requested)
	_marker_panel.connect("rename_requested", _on_marker_rename_requested)
	_marker_panel.connect("enabled_changed", _on_marker_enabled_changed)
	_marker_panel.connect("delete_requested", _on_marker_delete_requested)
	add_child(_marker_panel)


func _show_marker_panel() -> void:
	_set_needs_open(false)
	_set_farming_open(false)
	if _marker_panel.visible:
		return
	_marker_was_paused = Session.is_paused()
	Session.set_paused(true, false)
	_inventory_backdrop.show()


func _close_marker_panel() -> void:
	if not _marker_panel.visible:
		return
	_marker_panel.hide()
	_inventory_backdrop.hide()
	if not _marker_was_paused:
		Session.set_paused(false, false)


func _on_marker_create_requested(marker_name: String, color: Color) -> void:
	var result := Session.create_marker(marker_name, color)
	if bool(result.get("success", false)):
		_close_marker_panel()
		return
	_marker_panel.call("set_feedback", Localized.resolve(String(result.get("message_key", ""))))


func _on_marker_rename_requested(marker_id: String, marker_name: String) -> void:
	var result := Session.rename_marker(marker_id, marker_name)
	if bool(result.get("success", false)):
		_close_marker_panel()
		return
	_marker_panel.call("set_feedback", Localized.resolve(String(result.get("message_key", ""))))


func _on_marker_enabled_changed(marker_id: String, enabled: bool) -> void:
	Session.set_marker_enabled(marker_id, enabled)
	_marker_panel.call("show_list", Session.get_markers())


func _on_marker_delete_requested(marker_id: String) -> void:
	Session.remove_marker(marker_id)
	_marker_panel.call("show_list", Session.get_markers())


func refresh() -> void:
	if _farming_panel != null and _farming_panel.visible:
		_farming_panel.refresh()
	var time_key: String = "ui.hud.day_time_paused" if Session.is_paused() else "ui.hud.day_time"
	_time_label.text = Localized.resolve(time_key, {
		"day": Session.get_day(),
		"time": Session.get_time_text(),
	})
	_inventory_label.text = _format_inventory()
	_objective_label.text = Localized.resolve("ui.hud.objective", {
		"objective": Session.get_current_objective(),
	})
	_refresh_inventory_panel()
	_refresh_hotbar()
	_refresh_player_energy()

func _refresh_inventory_panel() -> void:
	var packed_placements := Session.get_inventory_placements()
	var placements: Array[Dictionary] = []

	for placement_variant: Variant in packed_placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			continue

		var placement := (
			placement_variant as Dictionary
		).duplicate(true)
		var item_id := String(
			placement.get("item_id", "")
		)

		placement["icon_path"] = _content_data.item_icon_path(
			item_id, placement.get("instance_state", {}) as Dictionary
		)
		placement["label"] = Localized.resolve(
			_content_data.item_label_key(item_id)
		)
		placements.append(placement)

	_inventory_panel.present(
		Localized.resolve("ui.inventory.title"),
		placements
	)


func _build_ui() -> void:
	var frame_rate := preload("res://src/ui/frame_rate_label.gd").new()
	frame_rate.name = "FrameRate"
	frame_rate.anchor_left = 0.5
	frame_rate.anchor_right = 0.5
	frame_rate.offset_left = -98
	frame_rate.offset_right = 98
	frame_rate.offset_top = 10
	frame_rate.offset_bottom = 27
	add_child(frame_rate)
	_add_ui_texture("date_weather.png", Vector2(10, 10), Vector2(188, 48))
	_add_ui_texture("time.png", Vector2(69, 58), Vector2(70, 20))
	_time_label = _make_label(self, Vector2(20, 20), Vector2(168, 24), 12)
	_time_label.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	_inventory_label = _make_label(self, Vector2(20, 40), Vector2(165, 15), 8)
	_inventory_label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)

	_tasks_background = _add_ui_texture(
		"tasks_panel_full.png", Vector2(420, 10), Vector2(210, 88)
	)
	_tasks_background.anchor_left = 1.0
	_tasks_background.anchor_right = 1.0
	_tasks_background.offset_left = -220.0
	_tasks_background.offset_right = -10.0
	_tasks_background.offset_top = 10.0
	_tasks_background.offset_bottom = 98.0
	_tasks_toggle = Button.new()
	_tasks_toggle.anchor_left = 1.0
	_tasks_toggle.anchor_right = 1.0
	_tasks_toggle.offset_left = -43.0
	_tasks_toggle.offset_right = -19.0
	_tasks_toggle.offset_top = 13.0
	_tasks_toggle.offset_bottom = 33.0
	_tasks_toggle.flat = true
	_tasks_toggle.focus_mode = Control.FOCUS_NONE
	_tasks_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_tasks_toggle.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	_tasks_toggle.add_theme_font_size_override("font_size", 12)
	_tasks_toggle.text = Localized.resolve("ui.hud.tasks.collapse")
	_tasks_toggle.pressed.connect(_toggle_tasks_panel)
	add_child(_tasks_toggle)
	_objective_label = _make_label(self, Vector2(434, 38), Vector2(158, 48), 9)
	_objective_label.anchor_left = 1.0
	_objective_label.anchor_right = 1.0
	_objective_label.offset_left = -196.0
	_objective_label.offset_right = -38.0
	_objective_label.offset_top = 38.0
	_objective_label.offset_bottom = 86.0
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Keep feedback in a dedicated, background-free area above the hotbar. The
	# previous 9-patch panel was compressed vertically into a purple strip.
	_selection_label = _make_bottom_feedback_label(-126.0, -87.0, 10)
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_label.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	_selection_label.text = Localized.resolve("ui.hud.selection.none")
	_message_label = _make_bottom_feedback_label(-87.0, -68.0, 9)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message_label.text = Localized.resolve("ui.hud.intro")

	_needs_hud = preload("res://src/ui/need_status_hud.gd").new()
	_needs_hud.anchor_top = 1.0
	_needs_hud.anchor_bottom = 1.0
	_needs_hud.offset_left = 10
	_needs_hud.offset_right = 184
	_needs_hud.offset_top = -70
	_needs_hud.offset_bottom = -10
	add_child(_needs_hud)
	_needs_hud.details_requested.connect(func() -> void: open_character_needs())
	_energy_fill = _needs_hud.fills.energy
	_energy_label = _needs_hud.labels.energy
	_npc_needs_button = Button.new()
	_npc_needs_button.name = "NpcNeedsButton"
	_npc_needs_button.position = Vector2(20, 80)
	_npc_needs_button.text = Localized.resolve("needs.npc_button")
	_npc_needs_button.add_theme_font_size_override("font_size", 10)
	UiSkin.apply_card_button(_npc_needs_button)
	_npc_needs_button.pressed.connect(func() -> void: open_character_needs(_selected_npc))
	add_child(_npc_needs_button)
	_npc_needs_button.hide()
	var hotbar := Control.new()
	hotbar.name = "Hotbar"
	hotbar.anchor_left = 0.5
	hotbar.anchor_right = 0.5
	hotbar.anchor_top = 1.0
	hotbar.anchor_bottom = 1.0
	hotbar.offset_left = -119.0
	hotbar.offset_right = 119.0
	hotbar.offset_top = -66.0
	hotbar.offset_bottom = -10.0
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hotbar)
	_add_ui_texture_to(hotbar, "hotbar.png", Vector2.ZERO, Vector2(238, 56))
	for slot_index in range(5):
		var slot := Button.new()
		slot.position = Vector2(10 + slot_index * 44, 7)
		slot.name = "Slot%d" % (slot_index + 1)
		slot.size = Vector2(42, 42)
		slot.flat = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		slot.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		slot.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		slot.pressed.connect(_on_hotbar_button_pressed.bind(slot_index))
		hotbar.add_child(slot)
		_hotbar_buttons.append(slot)
		var key_label := Label.new()
		key_label.position = Vector2(3, 1)
		key_label.size = Vector2(12, 12)
		key_label.text = str(slot_index + 1)
		key_label.add_theme_font_size_override("font_size", 7)
		key_label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(key_label)
		var icon := TextureRect.new()
		icon.position = Vector2(4, 4)
		icon.size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		_hotbar_icons.append(icon)
		var charge := Label.new()
		charge.position = Vector2(18, 19)
		charge.size = Vector2(22, 19)
		charge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		charge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		charge.add_theme_font_size_override("font_size", 9)
		charge.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
		charge.add_theme_color_override("font_shadow_color", Color("241a20"))
		charge.add_theme_constant_override("shadow_offset_x", 1)
		charge.add_theme_constant_override("shadow_offset_y", 1)
		charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(charge)
		_hotbar_charges.append(charge)

	_construction_palette = (
		ConstructionPaletteScene.instantiate() as ConstructionPalette
	)
	_construction_palette.position = Vector2.ZERO
	_construction_palette.build_mode_toggled.connect(
		_on_build_mode_toggled
	)
	_construction_palette.building_selected.connect(
		_on_building_selected
	)
	add_child(_construction_palette)

	_crafting_panel = CraftingPanelScene.instantiate() as CraftingPanel
	_crafting_panel.z_index = 22
	_crafting_panel.set_anchors_preset(Control.PRESET_CENTER)
	_crafting_panel.position = Vector2(-190.0, -135.0)
	_crafting_panel.close_requested.connect(
		_on_crafting_close_requested
	)
	_crafting_panel.recipe_requested.connect(_on_recipe_pressed)
	add_child(_crafting_panel)
	_crafting_panel.hide()
	_storage_panel = StoragePanelScene.instantiate() as StoragePanel
	_storage_panel.z_index = 23
	_storage_panel.set_anchors_preset(Control.PRESET_CENTER)
	_storage_panel.position = Vector2(-310.0, -205.0)
	_storage_panel.close_requested.connect(_on_storage_close_requested)
	_storage_panel.transfer_requested.connect(_on_storage_transfer_requested)
	_storage_panel.storage_layout_changed.connect(_on_storage_layout_changed)
	_storage_panel.inventory_layout_changed.connect(_on_storage_inventory_layout_changed)
	_storage_panel.drop_requested.connect(_on_inventory_drop_requested)
	add_child(_storage_panel)
	_storage_panel.hide()


func _add_ui_texture(file_name: String, at: Vector2, texture_size: Vector2) -> TextureRect:
	return _add_ui_texture_to(self, file_name, at, texture_size)


func _add_ui_texture_to(
	parent: Control,
	file_name: String,
	at: Vector2,
	texture_size: Vector2
) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.texture = load("res://assets/sprites/ui/%s" % file_name) as Texture2D
	texture_rect.position = at
	texture_rect.size = texture_size
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(texture_rect)
	return texture_rect


func _make_bottom_feedback_label(
	top_offset: float,
	bottom_offset: float,
	font_size: int
) -> Label:
	var label := Label.new()
	# Keep feedback to the right of the construction popup, not under it.
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = -300.0
	label.offset_right = -10.0
	label.offset_top = top_offset
	label.offset_bottom = bottom_offset
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
	add_child(label)
	return label


func _toggle_tasks_panel() -> void:
	_tasks_expanded = not _tasks_expanded
	_tasks_background.texture = load(
		"res://assets/sprites/ui/tasks_panel_full.png"
		if _tasks_expanded
		else "res://assets/sprites/ui/tasks_panel_small.png"
	) as Texture2D
	_tasks_background.offset_bottom = 10.0 + (88.0 if _tasks_expanded else 26.0)
	_objective_label.visible = _tasks_expanded
	_tasks_toggle.text = Localized.resolve(
		"ui.hud.tasks.collapse" if _tasks_expanded else "ui.hud.tasks.expand"
	)


func _make_label(parent: Node, at: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = label_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
	parent.add_child(label)
	return label


func _format_inventory() -> String:
	var inventory: Dictionary = Session.get_inventory()
	return Localized.resolve("ui.hud.inventory_brief", {
		"wood": int(inventory.get(FirstNightContent.WOOD_ID, 0)),
		"stone": int(inventory.get(FirstNightContent.STONE_ID, 0)),
	})


func _refresh_player_energy() -> void:
	_needs_hud.refresh(Session.get_player_needs())
	if _needs_panel != null and _needs_panel.visible:
		_needs_panel.refresh()
	if _housing_panel != null and _housing_panel.visible:
		_housing_panel.refresh()
	if _furniture_panel != null and _furniture_panel.visible:
		_furniture_panel.refresh()


func _refresh_hotbar() -> void:
	var slots := Session.get_hotbar_slots()
	var active := Session.get_active_hotbar_slot()
	for index: int in range(_hotbar_buttons.size()):
		var instance_id := slots[index]
		var instance: Dictionary = Session.get_item_instance(instance_id) if not instance_id.is_empty() else {}
		var item_id := String(instance.get("item_id", ""))
		var instance_state: Dictionary = instance.get("state", {}) as Dictionary
		var icon_path := _content_data.item_icon_path(item_id, instance_state)
		var icon_texture: Texture2D
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			icon_texture = load(icon_path) as Texture2D
		_hotbar_icons[index].texture = (
			icon_texture if icon_texture != null
			else PlaceholderIcon.texture_for(item_id) if not item_id.is_empty()
			else null
		)
		var charges := int(instance_state.get("charges", 0))
		_hotbar_charges[index].text = "%d/2" % charges if item_id == "core:bucket" else ""
		_hotbar_buttons[index].tooltip_text = Localized.resolve(_content_data.item_label_key(item_id)) if not item_id.is_empty() else "%d" % (index + 1)
		_hotbar_buttons[index].modulate = Color("ffe59c") if index == active else Color.WHITE


func handle_hotbar_key(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= 5:
		return
	if _inventory_panel.visible:
		var placement := _inventory_panel.get_selected_placement()
		var instance_id := String(placement.get("instance_id", ""))
		if not instance_id.is_empty():
			Session.assign_hotbar_slot(slot_index, instance_id)
			refresh()
		return
	if is_modal_open():
		return
	Session.select_hotbar_slot(slot_index)
	refresh()


func _on_hotbar_button_pressed(slot_index: int) -> void:
	if is_modal_open() and not _inventory_panel.visible:
		return
	Session.select_hotbar_slot(slot_index)
	refresh()


func _on_inventory_equip_requested(placement: Dictionary) -> void:
	Session.select_inventory_item(String(placement.get("item_id", "")), String(placement.get("instance_id", "")))


func _on_inventory_hotbar_drop_requested(
	placement: Dictionary,
	slot_index: int
) -> void:
	var instance_id := String(placement.get("instance_id", ""))
	if instance_id.is_empty():
		return
	Session.assign_hotbar_slot(slot_index, instance_id)
	refresh()


func _on_pause_changed(_paused: bool) -> void:
	refresh()


func _on_message(message: String, success: bool) -> void:
	_message_label.text = message
	_message_label.add_theme_color_override("font_color", Color("d7e8bd") if success else Color("f0c2a7"))
	refresh()


func _on_build_mode_toggled(active: bool) -> void:
	build_mode_toggled.emit(active)


func _on_building_selected(building_id: String) -> void:
	building_selected.emit(building_id)

func toggle_inventory() -> void:
	if _needs_panel.visible or _housing_panel.visible or _furniture_panel.visible:
		_set_needs_open(false)
		return
	if _farming_panel.visible:
		_set_farming_open(false)
	if _marker_panel.visible:
		_close_marker_panel()
		return
	if _crafting_panel.visible:
		_set_crafting_open(false)
	if _storage_panel.visible:
		_set_storage_open(false)
	_set_inventory_open(not _inventory_panel.visible)


func is_inventory_open() -> bool:
	return _inventory_panel.visible


func is_modal_open() -> bool:
	return (_conversation_panel != null and _conversation_panel.visible) or (_needs_panel != null and _needs_panel.visible) or (_housing_panel != null and _housing_panel.visible) or (_furniture_panel != null and _furniture_panel.visible) or _inventory_panel.visible or _crafting_panel.visible or _storage_panel.visible or _marker_panel.visible or _farming_panel.visible


func open_farming(cell: Vector2i) -> void:
	_set_needs_open(false)
	if Session.get_farm_bed(cell).is_empty():
		return
	_set_farming_open(false)
	_set_inventory_open(false)
	_set_crafting_open(false)
	_set_storage_open(false)
	if _marker_panel.visible:
		_close_marker_panel()
	_farming_panel.present(cell)
	_set_farming_open(true)


func _set_farming_open(open: bool) -> void:
	if open:
		_inventory_was_paused = Session.is_paused()
		Session.set_paused(true, false)
		_construction_palette.hide()
		_inventory_backdrop.show()
		_farming_panel.show()
	elif _farming_panel.visible:
		_farming_panel.hide()
		_inventory_backdrop.hide()
		_construction_palette.show()
		if not _inventory_was_paused:
			Session.set_paused(false, false)


func is_build_mode_active() -> bool:
	return _construction_palette.is_build_mode_active()


func open_crafting(cell: Vector2i, recipes: Array[Dictionary]) -> void:
	_set_needs_open(false)
	_set_farming_open(false)
	_set_inventory_open(false)
	_set_storage_open(false)
	if _marker_panel.visible:
		_close_marker_panel()
	_crafting_cell = cell
	_crafting_panel.present(recipes, _content_data)
	_set_crafting_open(true)


func open_storage(cell: Vector2i) -> void:
	_set_needs_open(false)
	_set_farming_open(false)
	_set_inventory_open(false)
	_set_crafting_open(false)
	if _marker_panel.visible:
		_close_marker_panel()
	_storage_cell = cell
	_storage_panel.present(cell, _content_data)
	_set_storage_open(true)


func _set_inventory_open(should_open: bool) -> void:
	if should_open: _close_npc_conversation()
	if _inventory_panel.visible == should_open:
		return

	if should_open:
		_inventory_was_paused = Session.is_paused()
		Session.set_paused(true, false)
		_construction_palette.hide()
		_inventory_backdrop.show()
		_inventory_panel.show()
		_refresh_inventory_panel()
		return

	_inventory_panel.hide()
	_inventory_panel.cancel_held_item()
	_inventory_backdrop.hide()
	_construction_palette.show()

	if not _inventory_was_paused:
		Session.set_paused(false, false)


func _on_inventory_close_requested() -> void:
	_set_inventory_open(false)


func _on_eat_food_requested(item_id: String) -> void:
	Session.eat_food(item_id)
	_refresh_inventory_panel()


func _on_extract_seeds_requested(item_id: String) -> void:
	Session.execute_farming_command({"actor_id": "core:player", "action_id": "extract", "item_id": item_id})
	_refresh_inventory_panel()


func _on_inventory_layout_changed(layout: Array[Dictionary]) -> void:
	var result: Dictionary = Session.set_inventory_layout(layout)
	if not bool(result.get("success", false)):
		return
	_refresh_inventory_panel()
	_inventory_panel.cancel_held_item()


func _on_inventory_drop_requested(placement: Dictionary) -> void:
	var result := Session.drop_inventory_stack(
		String(placement.get("item_id", "")),
		int(placement.get("stack_index", -1))
	)
	if not bool(result.get("success", false)):
		return
	if _storage_panel.visible:
		_storage_panel.return_held_items()
		_storage_panel.refresh(_storage_cell)
		return
	_inventory_panel.cancel_held_item()
	_refresh_inventory_panel()


func _set_crafting_open(should_open: bool) -> void:
	if _crafting_panel.visible == should_open:
		return
	if should_open:
		_inventory_was_paused = Session.is_paused()
		Session.set_paused(true, false)
		_construction_palette.hide()
		_inventory_backdrop.show()
		_crafting_panel.show()
		return
	_crafting_panel.hide()
	_inventory_backdrop.hide()
	_construction_palette.show()
	if not _inventory_was_paused:
		Session.set_paused(false, false)


func _on_recipe_pressed(recipe_id: String) -> void:
	var cell := _crafting_cell
	_set_crafting_open(false)
	crafting_recipe_requested.emit(cell, recipe_id)


func _on_crafting_close_requested() -> void:
	_set_crafting_open(false)


func _set_storage_open(should_open: bool) -> void:
	if _storage_panel.visible == should_open:
		return
	if should_open:
		_inventory_was_paused = Session.is_paused()
		Session.set_paused(true, false)
		_construction_palette.hide()
		_inventory_backdrop.show()
		_storage_panel.show()
		_storage_panel.refresh(_storage_cell)
		return
	_storage_panel.return_held_items()
	_storage_panel.hide()
	_inventory_backdrop.hide()
	_construction_palette.show()
	if not _inventory_was_paused:
		Session.set_paused(false, false)


func _on_storage_close_requested() -> void:
	_set_storage_open(false)


func _on_storage_transfer_requested(
	placement: Dictionary,
	from_storage: bool,
	target_cell: Vector2i,
	quick: bool
) -> void:
	var result: Dictionary
	if from_storage:
		result = Session.transfer_storage_stack_to_inventory(
			_storage_cell,
			String(placement.get("placement_id", "")),
			target_cell if not quick else Vector2i(-1, -1),
			int(placement.get("rotation", 0))
		)
	else:
		result = Session.transfer_inventory_stack_to_storage(
			_storage_cell,
			String(placement.get("item_id", "")),
			int(placement.get("stack_index", -1)),
			target_cell if not quick else Vector2i(-1, -1),
			int(placement.get("rotation", 0))
		)
	if bool(result.get("success", false)):
		_storage_panel.refresh(_storage_cell)


func _on_storage_layout_changed(layout: Array[Dictionary]) -> void:
	Session.set_storage_layout(_storage_cell, layout)
	_storage_panel.refresh(_storage_cell)


func _on_storage_inventory_layout_changed(layout: Array[Dictionary]) -> void:
	var result := Session.set_inventory_layout(layout)
	if bool(result.get("success", false)):
		_storage_panel.refresh(_storage_cell)


func open_character_needs(npc_id: String = "") -> void:
	_close_npc_conversation()
	if not npc_id.is_empty() and not Session.is_npc_visible(npc_id):
		return
	_set_needs_open(false)
	_set_farming_open(false)
	_set_inventory_open(false)
	_set_crafting_open(false)
	_set_storage_open(false)
	_close_marker_panel()
	_needs_was_paused = Session.is_paused()
	_needs_panel.present(npc_id)
	_inventory_backdrop.show()
	_construction_palette.hide()
	Session.set_paused(true, false)
	CompactLayout.fit_centered(_needs_panel, size)


func _set_needs_open(open: bool) -> void:
	if open or _needs_panel == null or (not _needs_panel.visible and not _housing_panel.visible and not _furniture_panel.visible):
		return
	_needs_panel.hide()
	_housing_panel.hide()
	_furniture_panel.hide()
	_inventory_backdrop.hide()
	_construction_palette.show()
	if not _needs_was_paused:
		Session.set_paused(false, false)


func _input(event: InputEvent) -> void:
	if _needs_panel != null and (_needs_panel.visible or _housing_panel.visible or _furniture_panel.visible) and event.is_action_pressed("ui_cancel"):
		_set_needs_open(false)
		get_viewport().set_input_as_handled()

func open_npc_conversation(npc_id: String) -> void:
	var topics := Session.get_npc_conversation_topics(npc_id)
	if topics.is_empty():
		Session.notify_player_key("interaction.failure.too_far")
		return
	_set_needs_open(false)
	_set_farming_open(false)
	_set_inventory_open(false)
	_set_crafting_open(false)
	_set_storage_open(false)
	_close_marker_panel()
	_close_npc_conversation()
	_conversation_was_paused = Session.is_paused()
	Session.set_paused(true,false)
	_choose_conversation_topic(String(topics[0].topic_id),npc_id)
	if _conversation_panel.visible:
		npc_conversation_opened.emit(npc_id)

func _choose_conversation_topic(topic_id: String,npc_id: String = "") -> void:
	var id := npc_id if not npc_id.is_empty() else String(_conversation_panel.npc_id)
	var result := Session.choose_npc_conversation(id,topic_id)
	if not bool(result.get("ok",false)):
		Session.notify_player_key(String(result.get("reason_key","conversation.refuse.context")))
		if not _conversation_panel.visible:
			Session.simulation.close_npc_conversation()
			Session.set_paused(_conversation_was_paused,false)
		return
	result["appearance"] = Session.get_npc_appearance(id)
	_conversation_panel.show_topics([])
	_conversation_panel.present(result)
	_inventory_backdrop.show()
	_construction_palette.hide()

func _close_npc_conversation(restore_pause: bool = true) -> void:
	if _conversation_panel == null: return
	var was_open := _conversation_panel.visible
	_conversation_panel.hide()
	Session.simulation.close_npc_conversation()
	if was_open:
		_inventory_backdrop.hide()
		_construction_palette.show()
		if restore_pause: Session.set_paused(_conversation_was_paused,false)

func open_furniture(cell: Vector2i) -> void:
	_set_needs_open(false)
	_set_farming_open(false)
	_set_inventory_open(false)
	_set_crafting_open(false)
	_set_storage_open(false)
	_close_marker_panel()
	_needs_was_paused = Session.is_paused()
	_furniture_panel.present(cell)
	_inventory_backdrop.show()
	_construction_palette.hide()
	Session.set_paused(true,false)
	CompactLayout.fit_centered(_furniture_panel,size)
