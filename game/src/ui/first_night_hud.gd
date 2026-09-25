class_name FirstNightHud
extends Control
signal build_mode_toggled(active: bool)
signal building_selected(building_id: String)
signal crafting_recipe_requested(cell: Vector2i, recipe_id: String)

const Content := preload("res://src/content/first_night_content.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const InventoryPacker := preload(
	"res://src/inventory/inventory_auto_packer.gd"
)
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const CraftingPanelScene: PackedScene = preload(
	"res://src/ui/crafting_panel.tscn"
)
const ConstructionPaletteScene: PackedScene = preload(
	"res://src/ui/construction_palette.tscn"
)

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
var _construction_palette: ConstructionPalette
var _crafting_cell: Vector2i = Vector2i(-1, -1)
var _inventory_was_paused: bool = false

@onready var _inventory_panel: InventoryPanel = (
	$InventoryPanel as InventoryPanel
)
@onready var _inventory_backdrop: ColorRect = (
	$InventoryBackdrop as ColorRect
)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_inventory_panel.close_requested.connect(
		_on_inventory_close_requested
	)
	_inventory_panel.hide()
	_inventory_backdrop.hide()
	Session.state_changed.connect(refresh)
	Session.state_reloaded.connect(refresh)
	Session.time_changed.connect(refresh)
	Session.pause_changed.connect(_on_pause_changed)
	Session.message_emitted.connect(_on_message)
	refresh()


func set_selection(selection: Dictionary) -> void:
	var kind: String = String(selection.get("kind", "none"))
	if kind == "cell":
		_selection_label.text = Localized.resolve("ui.hud.selection.cell", {
			"x": int(selection.get("x", -1)),
			"y": int(selection.get("y", -1)),
		})
		return
	if kind == "interactable" or kind == "blueprint" or kind == "structure":
		var status: String = String(selection.get("status", ""))
		var in_range: bool = bool(selection.get("in_range", false))
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


func refresh() -> void:
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

func _refresh_inventory_panel() -> void:
	var packed: Dictionary = InventoryPacker.pack(
		Session.get_inventory(),
		_content_data
	)
	var packed_placements := (
		packed.get("placements", []) as Array
	)
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

		placement["icon_path"] = (
			_content_data.item_icon_path(item_id)
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
	_add_ui_texture("date_weather.png", Vector2(10, 10), Vector2(188, 48))
	_add_ui_texture("time.png", Vector2(69, 58), Vector2(70, 20))
	_time_label = _make_label(self, Vector2(20, 20), Vector2(168, 24), 12)
	_time_label.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	_inventory_label = _make_label(self, Vector2(20, 40), Vector2(165, 15), 8)
	_inventory_label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)

	_tasks_background = _add_ui_texture(
		"tasks_panel_full.png", Vector2(420, 10), Vector2(210, 88)
	)
	_tasks_toggle = Button.new()
	_tasks_toggle.position = Vector2(597, 13)
	_tasks_toggle.size = Vector2(24, 20)
	_tasks_toggle.flat = true
	_tasks_toggle.focus_mode = Control.FOCUS_NONE
	_tasks_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_tasks_toggle.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	_tasks_toggle.add_theme_font_size_override("font_size", 12)
	_tasks_toggle.text = Localized.resolve("ui.hud.tasks.collapse")
	_tasks_toggle.pressed.connect(_toggle_tasks_panel)
	add_child(_tasks_toggle)
	_objective_label = _make_label(self, Vector2(434, 38), Vector2(158, 48), 9)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var feedback_panel := _make_pixel_panel(
		Vector2(210.0, 258.0), Vector2(220.0, 28.0)
	)
	_selection_label = _make_label(
		feedback_panel, Vector2(5.0, 2.0), Vector2(210.0, 15.0), 8
	)
	_selection_label.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	_selection_label.text = Localized.resolve("ui.hud.selection.none")
	_message_label = _make_label(
		feedback_panel, Vector2(5.0, 15.0), Vector2(210.0, 12.0), 8
	)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.text = Localized.resolve("ui.hud.intro")

	_add_ui_texture("status_heart.png", Vector2(10, 299), Vector2(18, 18))
	_add_ui_texture("status_energy.png", Vector2(10, 324), Vector2(18, 18))
	# Player health and stamina are not yet part of the simulation. Keep the
	# authored frames visible, but do not imply invented values with fake fills.
	_add_ui_texture("status_bar_frame.png", Vector2(32, 301), Vector2(138, 14))
	_add_ui_texture("status_bar_frame.png", Vector2(32, 326), Vector2(138, 14))
	var health_unknown := _make_label(self, Vector2(32, 301), Vector2(138, 14), 9)
	health_unknown.text = "—"
	health_unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_unknown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var stamina_unknown := _make_label(self, Vector2(32, 326), Vector2(138, 14), 9)
	stamina_unknown.text = "—"
	stamina_unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamina_unknown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_add_ui_texture("hotbar.png", Vector2(201, 294), Vector2(238, 56))
	for slot_index in range(5):
		_add_ui_texture(
			"hotbar_slot_normal.png",
			Vector2(208 + slot_index * 44, 301),
			Vector2(42, 42)
		)

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


func _add_ui_texture(file_name: String, at: Vector2, texture_size: Vector2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.texture = load("res://assets/sprites/ui/%s" % file_name) as Texture2D
	texture_rect.position = at
	texture_rect.size = texture_size
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture_rect)
	return texture_rect


func _toggle_tasks_panel() -> void:
	_tasks_expanded = not _tasks_expanded
	_tasks_background.texture = load(
		"res://assets/sprites/ui/tasks_panel_full.png"
		if _tasks_expanded
		else "res://assets/sprites/ui/tasks_panel_small.png"
	) as Texture2D
	_tasks_background.size = Vector2(210, 88 if _tasks_expanded else 26)
	_objective_label.visible = _tasks_expanded
	_tasks_toggle.text = Localized.resolve(
		"ui.hud.tasks.collapse" if _tasks_expanded else "ui.hud.tasks.expand"
	)


func _make_pixel_panel(at: Vector2, panel_size: Vector2) -> Control:
	var panel := PanelContainer.new()
	panel.position = at
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiSkin.panel_style())
	add_child(panel)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	return content


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
	if _crafting_panel.visible:
		_set_crafting_open(false)
	_set_inventory_open(not _inventory_panel.visible)


func is_inventory_open() -> bool:
	return _inventory_panel.visible


func is_modal_open() -> bool:
	return _inventory_panel.visible or _crafting_panel.visible


func open_crafting(cell: Vector2i, recipes: Array[Dictionary]) -> void:
	_set_inventory_open(false)
	_crafting_cell = cell
	_crafting_panel.present(recipes, _content_data)
	_set_crafting_open(true)


func _set_inventory_open(should_open: bool) -> void:
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
	_inventory_backdrop.hide()
	_construction_palette.show()

	if not _inventory_was_paused:
		Session.set_paused(false, false)


func _on_inventory_close_requested() -> void:
	_set_inventory_open(false)


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
