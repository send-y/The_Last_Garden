class_name InventoryPanel
extends PanelContainer

signal close_requested
signal eat_food_requested(item_id: String)
signal extract_seeds_requested(item_id: String)
signal inventory_layout_changed(layout: Array[Dictionary])
signal drop_requested(placement: Dictionary)
signal hotbar_drop_requested(placement: Dictionary, slot_index: int)
signal equip_requested(placement: Dictionary)

const Localized := preload(
	"res://src/localization/localized_text.gd"
)
var _extract_button: Button
var _eat_button: Button
var _drop_button: Button
var _details_label: Label
var _context_menu: PanelContainer
var _context_placement: Dictionary = {}
const PANEL_TEXTURE := preload(
	"res://assets/sprites/ui/panel_9patch.png"
)
const TAB_REGULAR_TEXTURE := preload(
	"res://assets/sprites/ui/tab_regular.png"
)
const TAB_HOVER_TEXTURE := preload(
	"res://assets/sprites/ui/tab_hover.png"
)
const TAB_ACTIVE_TEXTURE := preload(
	"res://assets/sprites/ui/tab_active.png"
)
const CLOSE_REGULAR_TEXTURE := preload(
	"res://assets/sprites/ui/x_mark_regular.png"
)
const CLOSE_HOVER_TEXTURE := preload(
	"res://assets/sprites/ui/x_mark_hover.png"
)

@onready var _title_label: Label = (
	$ContentMargin/ContentColumn/HeaderRow/TitleLabel as Label
)
@onready var _close_button: Button = (
	$ContentMargin/ContentColumn/HeaderRow/CloseButton as Button
)
@onready var _inventory_grid: InventoryGrid = (
	$ContentMargin/ContentColumn/GridCenter/InventoryGrid
	as InventoryGrid
)
@onready var _tab_buttons: Array[Button] = [
	$ContentMargin/ContentColumn/HeaderRow/TabCenter/TabRow/Tab1 as Button,
	$ContentMargin/ContentColumn/HeaderRow/TabCenter/TabRow/Tab2 as Button,
	$ContentMargin/ContentColumn/HeaderRow/TabCenter/TabRow/Tab3 as Button,
	$ContentMargin/ContentColumn/HeaderRow/TabCenter/TabRow/Tab4 as Button,
]


func _ready() -> void:
	_apply_panel_style()
	_apply_close_button_style()
	_apply_tab_styles()
	_create_context_menu()
	visibility_changed.connect(_close_context_menu)
	_close_button.pressed.connect(_on_close_button_pressed)
	_inventory_grid.context_requested.connect(_open_context_menu)
	_inventory_grid.equip_requested.connect(func(placement: Dictionary) -> void: equip_requested.emit(placement))
	_inventory_grid.tooltip_text = Localized.resolve("ui.inventory.controls_hint")
	_inventory_grid.selection_changed.connect(
		_on_inventory_selection_changed
	)
	_inventory_grid.layout_changed.connect(_on_inventory_layout_changed)
	_inventory_grid.drop_requested.connect(_on_drop_requested)
	_inventory_grid.external_drop_boundary = self
	_inventory_grid.hotbar_drop_requested.connect(_on_hotbar_drop_requested)
	_details_label.text = Localized.resolve(
		"ui.inventory.details.empty"
	)


func _create_context_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ContextLayer"
	layer.layer = 30
	add_child(layer)
	_context_menu = PanelContainer.new()
	_context_menu.name = "ItemContextMenu"
	_context_menu.custom_minimum_size.x = 160.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(57, 40, 39)
	style.border_color = Color8(151, 109, 78)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_context_menu.add_theme_stylebox_override("panel", style)
	layer.add_child(_context_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_context_menu.add_child(column)
	_details_label = Label.new()
	_details_label.custom_minimum_size.x = 144.0
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_label.add_theme_font_size_override("font_size", 12)
	_details_label.add_theme_color_override("font_color", Color8(239, 226, 207))
	column.add_child(_details_label)
	_eat_button = _context_button(column, "EatButton", "ui.inventory.eat")
	_extract_button = _context_button(column, "ExtractButton", "ui.inventory.extract_seeds")
	_drop_button = _context_button(column, "DropButton", "ui.inventory.drop_stack")
	_eat_button.pressed.connect(func() -> void:
		var item_id := String(_context_placement.get("item_id", ""))
		_close_context_menu()
		if not item_id.is_empty():
			eat_food_requested.emit(item_id)
	)
	_extract_button.pressed.connect(func() -> void:
		var item_id := String(_context_placement.get("item_id", ""))
		var allowed := not _extract_button.disabled
		_close_context_menu()
		if allowed and not item_id.is_empty():
			extract_seeds_requested.emit(item_id)
	)
	_drop_button.pressed.connect(func() -> void:
		var placement := _context_placement.duplicate(true)
		_close_context_menu()
		if not placement.is_empty():
			drop_requested.emit(placement)
	)
	_context_menu.hide()


func _context_button(column: VBoxContainer, button_name: String, text_key: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = Localized.resolve(text_key)
	button.custom_minimum_size.y = 24.0
	button.add_theme_font_size_override("font_size", 12)
	column.add_child(button)
	return button


func _open_context_menu(placement: Dictionary, pointer: Vector2) -> void:
	_close_context_menu()
	if placement.is_empty() or not is_visible_in_tree():
		return
	_on_inventory_selection_changed(placement)
	_context_placement = placement.duplicate(true)
	_context_menu.size = Vector2(160, 0)
	_context_menu.position = pointer + Vector2(6, 6)
	_context_menu.show()
	_clamp_context_menu()


func _close_context_menu() -> void:
	_context_placement.clear()
	if is_instance_valid(_context_menu):
		_context_menu.hide()


func _clamp_context_menu() -> void:
	var bounds := get_viewport_rect()
	_context_menu.scale = Vector2.ONE * minf(0.9, minf((bounds.size.x - 6) / _context_menu.size.x, (bounds.size.y - 6) / _context_menu.size.y))
	_context_menu.position = _context_menu.position.clamp(bounds.position + Vector2.ONE * 3, bounds.end - _context_menu.size * _context_menu.scale - Vector2.ONE * 3)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_context_menu) or not _context_menu.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_context_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not _context_menu.get_global_rect().has_point(event.global_position):
		_close_context_menu()
		# A right click on another item can immediately open its own menu.
		if event.button_index != MOUSE_BUTTON_RIGHT or not _inventory_grid.get_global_rect().has_point(event.global_position):
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		_fit_to_viewport()
	if _context_menu.visible:
		_clamp_context_menu()


func _fit_to_viewport() -> void:
	# Use native-size cells whenever the viewport can fit them. The hotbar sits
	# against the bottom edge while this panel is open, leaving room for all rows.
	var available := (get_parent() as Control).size
	var height := maxf(custom_minimum_size.y, get_combined_minimum_size().y)
	var width := maxf(custom_minimum_size.x, get_combined_minimum_size().x)
	var bottom_gap := minf(56.0, available.y * 0.16)
	var factor := minf(1.0, minf((available.x - 16) / width, (available.y - bottom_gap - 8) / height))
	scale = Vector2.ONE * maxf(0.1, factor)
	size = Vector2(width, height)
	position = Vector2((available.x - width * scale.x) * 0.5, available.y - bottom_gap - height * scale.y)


func present(
	title_text: String,
	placements: Array[Dictionary],
	item_content: FirstNightContent = null
) -> void:
	_title_label.text = title_text
	_close_context_menu()
	_inventory_grid.present(placements, item_content)


func set_external_hotbar_target(target: Control) -> void:
	_inventory_grid.external_hotbar_target = target


func _on_inventory_layout_changed(layout: Array[Dictionary]) -> void:
	inventory_layout_changed.emit(layout)


func _on_drop_requested(placement: Dictionary) -> void:
	drop_requested.emit(placement)


func _on_hotbar_drop_requested(placement: Dictionary, slot_index: int) -> void:
	hotbar_drop_requested.emit(placement, slot_index)


func get_details_text() -> String:
	return _details_label.text


func get_selected_placement() -> Dictionary:
	return _inventory_grid.get_selected_placement()


func cancel_held_item() -> void:
	_inventory_grid.return_held_item()


func _apply_panel_style() -> void:
	var panel_style := StyleBoxTexture.new()
	panel_style.texture = PANEL_TEXTURE
	panel_style.texture_margin_left = 20.0
	panel_style.texture_margin_top = 20.0
	panel_style.texture_margin_right = 20.0
	panel_style.texture_margin_bottom = 20.0
	# Padding belongs to ContentMargin; nine-patch edges must not add it again.
	panel_style.content_margin_left = 0.0
	panel_style.content_margin_top = 0.0
	panel_style.content_margin_right = 0.0
	panel_style.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", panel_style)


func _apply_close_button_style() -> void:
	var regular_style := _texture_style(CLOSE_REGULAR_TEXTURE)
	var hover_style := _texture_style(CLOSE_HOVER_TEXTURE)
	_close_button.add_theme_stylebox_override("normal", regular_style)
	_close_button.add_theme_stylebox_override("hover", hover_style)
	_close_button.add_theme_stylebox_override("pressed", hover_style)
	_close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _apply_tab_styles() -> void:
	var regular_style := _texture_style(TAB_REGULAR_TEXTURE)
	var hover_style := _texture_style(TAB_HOVER_TEXTURE)
	var active_style := _texture_style(TAB_ACTIVE_TEXTURE)

	for index: int in range(_tab_buttons.size()):
		var button := _tab_buttons[index]
		button.add_theme_stylebox_override("normal", regular_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", active_style)
		button.add_theme_stylebox_override("disabled", regular_style)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.tooltip_text = Localized.resolve(
			"ui.inventory.tab.items"
			if index == 0
			else "ui.inventory.tab.future"
		)

	_tab_buttons[0].button_pressed = true
	for index: int in range(1, _tab_buttons.size()):
		_tab_buttons[index].disabled = true


func _texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	return style


func _on_inventory_selection_changed(
	placement: Dictionary
) -> void:
	_close_context_menu()
	if placement.is_empty():
		_details_label.text = Localized.resolve(
			"ui.inventory.details.empty"
		)
		_eat_button.hide()
		_extract_button.hide()
		return

	_details_label.text = Localized.resolve(
		"ui.inventory.details.item",
		{
			"item": String(placement.get("label", "")),
			"amount": int(placement.get("amount", 1)),
		}
	)
	if Session.simulation.content.item_tool_supports(String(placement.get("item_id", "")), "water"):
		var item_state: Dictionary = placement.get("instance_state", {}) as Dictionary
		_details_label.text += "  %d/%d" % [int(item_state.get("charges", 0)), Session.simulation.content.item_tool_capacity(String(placement.item_id))]
	var item_id := String(placement.get("item_id", ""))
	var profile: Dictionary = Session.simulation.content.item_food_profile(item_id)
	_eat_button.visible = not profile.is_empty()
	_extract_button.visible = Session.simulation.farming.can_extract_seeds(item_id)
	_extract_button.disabled = item_id != "core:food" and not Session.simulation.farming.extraction_unlocked(Session.simulation)
	_extract_button.tooltip_text = Localized.resolve("farming.failure.study") if _extract_button.disabled else Localized.resolve("farming.extract_hint")
	if _eat_button.visible:
		var energy := int(profile.energy)
		var satiety := int(profile.satiety)
		_details_label.text += Localized.resolve("farming.energy_hint", {"energy": energy, "satiety": satiety})
		_eat_button.tooltip_text = Localized.resolve("farming.energy_hint", {"energy": energy, "satiety": satiety})


func _on_close_button_pressed() -> void:
	close_requested.emit()
