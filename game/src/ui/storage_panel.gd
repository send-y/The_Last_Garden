class_name StoragePanel
extends PanelContainer

signal close_requested
signal transfer_requested(placement: Dictionary, from_storage: bool, target_cell: Vector2i, quick: bool)
signal storage_layout_changed(layout: Array[Dictionary])
signal inventory_layout_changed(layout: Array[Dictionary])
signal drop_requested(placement: Dictionary)

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")

var _content: FirstNightContent
var _cell := Vector2i(-1, -1)
var _reserve_editor
var _reserve_tab: Button
var _items_tab: Button
var _reserve_scroll: ScrollContainer
var _items_scroll: ScrollContainer
var _reserves_open := false

@onready var _title: Label = $Margin/Column/Header/Title as Label
@onready var _close: Button = $Margin/Column/Header/Close as Button
@onready var _hint: Label = $Margin/Column/Hint as Label
@onready var _inventory_title: Label = $Margin/Column/Grids/InventoryColumn/InventoryTitle as Label
@onready var _storage_title: Label = $Margin/Column/Grids/StorageColumn/StorageTitle as Label
@onready var _inventory_grid: InventoryGrid = $Margin/Column/Grids/InventoryColumn/InventoryGrid as InventoryGrid
@onready var _storage_grid: InventoryGrid = $Margin/Column/Grids/StorageColumn/StorageGrid as InventoryGrid
@onready var _grids: HBoxContainer = $Margin/Column/Grids as HBoxContainer


func _ready() -> void:
	_inventory_grid.configure_grid(4, 4)
	_inventory_grid.equip_requested.connect(func(placement: Dictionary) -> void:
		Session.select_inventory_item(String(placement.get("item_id", "")), String(placement.get("instance_id", "")))
	)
	_storage_grid.configure_grid(3, 2)
	_inventory_grid.external_drop_boundary = self
	_storage_grid.external_drop_boundary = self
	add_theme_stylebox_override("panel", UiSkin.panel_style())
	_title.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
	_hint.add_theme_color_override("font_color", UiSkin.TEXT_MUTED)
	UiSkin.apply_close_button(_close)
	_close.pressed.connect(func() -> void: close_requested.emit())
	_inventory_grid.drop_requested.connect(func(placement: Dictionary) -> void: drop_requested.emit(placement))
	_inventory_grid.external_transfer_target = _storage_grid
	_inventory_grid.cross_grid_drop_requested.connect(_on_inventory_drop_to_storage)
	_inventory_grid.layout_changed.connect(func(layout: Array[Dictionary]) -> void: inventory_layout_changed.emit(layout))
	_inventory_grid.quick_transfer_requested.connect(func(placement: Dictionary) -> void: transfer_requested.emit(placement, false, Vector2i(-1, -1), true))
	_storage_grid.layout_changed.connect(func(layout: Array[Dictionary]) -> void: storage_layout_changed.emit(layout))
	_storage_grid.external_transfer_target = _inventory_grid
	_storage_grid.cross_grid_drop_requested.connect(_on_storage_drop_to_inventory)
	_storage_grid.quick_transfer_requested.connect(func(placement: Dictionary) -> void: transfer_requested.emit(placement, true, Vector2i(-1, -1), true))
	_title.text = Localized.resolve("ui.storage.panel.title")
	_hint.text = Localized.resolve("ui.storage.panel.hint")
	_inventory_title.text = Localized.resolve("ui.storage.panel.backpack")
	_storage_title.text = Localized.resolve("ui.storage.panel.cell", {
		"columns": 3,
		"rows": 2,
	})
	var column := $Margin/Column
	var tabs := HBoxContainer.new()
	tabs.name = "StorageTabs"
	column.add_child(tabs)
	column.move_child(tabs, $Margin/Column/Hint.get_index())
	for id: String in ["items", "reserves"]:
		var button := Button.new()
		button.name = "ReserveTab" if id == "reserves" else "ItemsTab"
		button.text = Localized.resolve("stock.reserve.tab" if id == "reserves" else "stock.items.tab")
		button.add_theme_font_size_override("font_size", 11)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		UiSkin.apply_tab_button(button)
		button.pressed.connect(func() -> void: _select_tab(id == "reserves"))
		tabs.add_child(button)
		if id == "reserves": _reserve_tab = button
		else: _items_tab = button
	_items_scroll = ScrollContainer.new()
	_items_scroll.name = "ItemsScroll"
	_items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_items_scroll)
	_grids.reparent(_items_scroll)
	_grids.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reserve_scroll = ScrollContainer.new()
	_reserve_scroll.name = "ReserveScroll"
	_reserve_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_reserve_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_reserve_scroll)
	_reserve_editor = preload("res://src/ui/storage_reserve_editor.gd").new()
	_reserve_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reserve_scroll.add_child(_reserve_editor)
	_select_tab(false)


func present(cell: Vector2i, content: FirstNightContent) -> void:
	_cell = cell
	_content = content
	_configure_storage_grid(cell)
	_select_tab(false)
	refresh(cell)


func refresh(cell: Vector2i) -> void:
	_cell = cell
	if _content == null or not is_node_ready():
		return
	_content = Session.simulation.content
	_configure_storage_grid(cell)
	var storage_size := Session.get_storage_grid_size(cell)
	_storage_title.text = Localized.resolve("ui.storage.panel.cell", {
		"columns": storage_size.x,
		"rows": storage_size.y,
	})
	var backpack_placements: Array[Dictionary] = []
	for placement_value: Variant in Session.get_inventory_placements():
		if typeof(placement_value) != TYPE_DICTIONARY:
			continue
		var placement := (placement_value as Dictionary).duplicate(true)
		var item_id := String(placement.get("item_id", ""))
		placement["icon_path"] = _content.item_icon_path(
			item_id, placement.get("instance_state", {}) as Dictionary
		)
		placement["label"] = Localized.resolve(_content.item_label_key(item_id))
		backpack_placements.append(placement)
	_inventory_grid.present(backpack_placements, _content)
	_storage_grid.present(Session.get_storage_layout(_cell), _content)
	if _reserves_open: _reserve_editor.refresh()

func _select_tab(reserves: bool) -> void:
	return_held_items()
	_reserves_open = reserves
	_grids.visible = not reserves
	_items_scroll.visible = not reserves
	_hint.visible = not reserves
	_reserve_scroll.visible = reserves
	_reserve_editor.visible = reserves
	_items_tab.set_pressed_no_signal(not reserves)
	_reserve_tab.set_pressed_no_signal(reserves)
	if reserves: _reserve_editor.refresh()
	fit_to_viewport(get_parent_control().size if get_parent_control() != null else get_viewport_rect().size)

func fit_to_viewport(available: Vector2) -> void:
	if not is_node_ready(): return
	available = available.min(get_viewport_rect().size)
	custom_minimum_size = Vector2(minf(400, available.x - 16), 0)
	_reserve_scroll.custom_minimum_size.y = 0
	_items_scroll.custom_minimum_size.y = 0
	var overhead := get_combined_minimum_size().y
	_reserve_scroll.custom_minimum_size.y = minf(215, maxf(48, available.y - 16 - overhead)) if _reserves_open else 0
	_items_scroll.custom_minimum_size.y = minf(215, maxf(48, available.y - 16 - overhead)) if not _reserves_open else 0
	scale = Vector2.ONE
	size = Vector2(custom_minimum_size.x, 0)
	size.y = get_combined_minimum_size().y
	position = (available - size) * 0.5


func _configure_storage_grid(cell: Vector2i) -> void:
	var grid_size := Session.get_storage_grid_size(cell)
	_storage_grid.configure_grid(grid_size.x, grid_size.y)
func return_held_items() -> void:
	_inventory_grid.return_held_item()
	_storage_grid.return_held_item()


func _on_inventory_drop_to_storage(placement: Dictionary, target_cell: Vector2i) -> void:
	transfer_requested.emit(placement, false, target_cell, false)


func _on_storage_drop_to_inventory(placement: Dictionary, target_cell: Vector2i) -> void:
	transfer_requested.emit(placement, true, target_cell, false)
