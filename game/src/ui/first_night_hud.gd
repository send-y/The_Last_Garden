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

var _content_data: FirstNightContent = Content.new()
var _time_label: Label
var _inventory_label: Label
var _objective_label: Label
var _selection_label: Label
var _message_label: Label
var _controls_label: Label
var _build_mode_button: Button
var _building_picker: OptionButton
var _crafting_panel: PanelContainer
var _crafting_recipes_box: VBoxContainer
var _crafting_cell: Vector2i = Vector2i(-1, -1)
var _selected_building_id: String = "core:wood_wall"
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
	_build_crafting_panel()
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
		placement["total_weight"] = (
			_content_data.item_weight(item_id)
			* int(placement.get("amount", 1))
		)
		placements.append(placement)

	_inventory_panel.present(
		Localized.resolve("ui.inventory.title"),
		Localized.resolve(
			"ui.inventory.weight",
			{
				"weight": String.num(
					Session.get_inventory_weight(),
					1
				),
				"max_weight": String.num(
					Session.get_max_carry_weight(),
					0
				),
			}
		),
		placements
	)


func _build_ui() -> void:
	var top_panel := ColorRect.new()
	top_panel.position = Vector2(8.0, 8.0)
	top_panel.size = Vector2(252.0, 86.0)
	top_panel.color = Color(0.07, 0.08, 0.07, 0.82)
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_panel)

	_time_label = _make_label(top_panel, Vector2(8.0, 6.0), Vector2(236.0, 20.0), 14)
	_inventory_label = _make_label(top_panel, Vector2(8.0, 26.0), Vector2(236.0, 50.0), 11)
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var objective_panel := ColorRect.new()
	objective_panel.position = Vector2(270.0, 8.0)
	objective_panel.size = Vector2(362.0, 54.0)
	objective_panel.color = Color(0.07, 0.08, 0.07, 0.82)
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(objective_panel)
	_objective_label = _make_label(objective_panel, Vector2(8.0, 6.0), Vector2(346.0, 42.0), 12)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_mode_button = Button.new()
	_build_mode_button.position = Vector2(8.0, 266.0)
	_build_mode_button.size = Vector2(160.0, 28.0)
	_build_mode_button.toggle_mode = true
	_build_mode_button.text = Localized.resolve("ui.construction.mode.off")
	_build_mode_button.toggled.connect(_on_build_mode_toggled)
	add_child(_build_mode_button)

	_building_picker = OptionButton.new()
	_building_picker.position = Vector2(174.0, 266.0)
	_building_picker.size = Vector2(150.0, 28.0)
	_building_picker.add_item(Localized.resolve("building.core.wood_wall.name"))
	_building_picker.set_item_metadata(0, "core:wood_wall")
	_building_picker.add_item(Localized.resolve("building.core.workbench.name"))
	_building_picker.set_item_metadata(1, "core:workbench")
	_building_picker.item_selected.connect(_on_building_selected)
	add_child(_building_picker)

	var bottom_panel := ColorRect.new()
	bottom_panel.position = Vector2(8.0, 300.0)
	bottom_panel.size = Vector2(624.0, 52.0)
	bottom_panel.color = Color(0.07, 0.08, 0.07, 0.86)
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_panel)
	_selection_label = _make_label(bottom_panel, Vector2(8.0, 3.0), Vector2(608.0, 17.0), 11)
	_selection_label.text = Localized.resolve("ui.hud.selection.none")
	_message_label = _make_label(bottom_panel, Vector2(8.0, 20.0), Vector2(608.0, 26.0), 11)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.text = Localized.resolve("ui.hud.intro")

	_controls_label = _make_label(self, Vector2(376.0, 68.0), Vector2(256.0, 42.0), 10)
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_controls_label.text = Localized.resolve("ui.hud.controls")


func _make_label(parent: Node, at: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = label_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eee7d5"))
	parent.add_child(label)
	return label


func _format_inventory() -> String:
	var inventory: Dictionary = Session.get_inventory()
	var inventory_key: String = (
		"ui.hud.inventory_with_tools"
		if bool(Session.get_flags().get("tools_found", false))
		else "ui.hud.inventory"
	)
	return Localized.resolve(inventory_key, {
		"weight": String.num(Session.get_inventory_weight(), 1),
		"max_weight": String.num(Session.get_max_carry_weight(), 0),
		"wood": int(inventory.get(FirstNightContent.WOOD_ID, 0)),
		"stone": int(inventory.get(FirstNightContent.STONE_ID, 0)),
		"raw_water": int(inventory.get(FirstNightContent.RAW_WATER_ID, 0)),
		"boiled_water": int(inventory.get(FirstNightContent.BOILED_WATER_ID, 0)),
		"food": int(inventory.get(FirstNightContent.FOOD_ID, 0)),
	})


func _on_pause_changed(_paused: bool) -> void:
	refresh()


func _on_message(message: String, success: bool) -> void:
	_message_label.text = message
	_message_label.add_theme_color_override("font_color", Color("d7e8bd") if success else Color("f0c2a7"))
	refresh()


func _on_build_mode_toggled(active: bool) -> void:
	var text_key: String = (
		"ui.construction.mode.on"
		if active
		else "ui.construction.mode.off"
	)
	_build_mode_button.text = Localized.resolve(text_key)
	build_mode_toggled.emit(active)


func _on_building_selected(index: int) -> void:
	_selected_building_id = String(_building_picker.get_item_metadata(index))
	building_selected.emit(_selected_building_id)

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
	for child: Node in _crafting_recipes_box.get_children():
		child.queue_free()
	for recipe: Dictionary in recipes:
		var recipe_id := String(recipe.get("id", ""))
		var button := Button.new()
		button.text = _format_recipe_button(recipe)
		button.custom_minimum_size = Vector2(300.0, 34.0)
		button.pressed.connect(_on_recipe_pressed.bind(recipe_id))
		_crafting_recipes_box.add_child(button)
	_set_crafting_open(true)


func _format_recipe_button(recipe: Dictionary) -> String:
	var input_parts: PackedStringArray = []
	var output_parts: PackedStringArray = []
	var inputs: Dictionary = recipe.get("inputs", {}) as Dictionary
	var outputs: Dictionary = recipe.get("outputs", {}) as Dictionary
	for item_variant: Variant in inputs.keys():
		var item_id := String(item_variant)
		input_parts.append("%d %s" % [
			int(inputs[item_variant]),
			Localized.resolve(_content_data.item_label_key(item_id)),
		])
	for item_variant: Variant in outputs.keys():
		var item_id := String(item_variant)
		output_parts.append("%d %s" % [
			int(outputs[item_variant]),
			Localized.resolve(_content_data.item_label_key(item_id)),
		])
	return "%s  ·  %s → %s" % [
		Localized.resolve(String(recipe.get("label_key", recipe.get("id", "")))),
		", ".join(input_parts),
		", ".join(output_parts),
	]


func _set_inventory_open(should_open: bool) -> void:
	if _inventory_panel.visible == should_open:
		return

	if should_open:
		_inventory_was_paused = Session.is_paused()
		Session.set_paused(true, false)
		_inventory_backdrop.show()
		_inventory_panel.show()
		_refresh_inventory_panel()
		return

	_inventory_panel.hide()
	_inventory_backdrop.hide()

	if not _inventory_was_paused:
		Session.set_paused(false, false)


func _on_inventory_close_requested() -> void:
	_set_inventory_open(false)


func _build_crafting_panel() -> void:
	_crafting_panel = PanelContainer.new()
	_crafting_panel.z_index = 22
	_crafting_panel.custom_minimum_size = Vector2(380.0, 260.0)
	_crafting_panel.set_anchors_preset(Control.PRESET_CENTER)
	_crafting_panel.position = Vector2(-190.0, -130.0)
	add_child(_crafting_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_crafting_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var title := Label.new()
	title.text = Localized.resolve("ui.crafting.title")
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	var hint := Label.new()
	hint.text = Localized.resolve("ui.crafting.hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)
	_crafting_recipes_box = VBoxContainer.new()
	root.add_child(_crafting_recipes_box)
	var close_button := Button.new()
	close_button.text = Localized.resolve("ui.crafting.close")
	close_button.pressed.connect(_on_crafting_close_requested)
	root.add_child(close_button)
	_crafting_panel.hide()


func _set_crafting_open(should_open: bool) -> void:
	if _crafting_panel.visible == should_open:
		return
	if should_open:
		_inventory_was_paused = Session.is_paused()
		Session.set_paused(true, false)
		_inventory_backdrop.show()
		_crafting_panel.show()
		return
	_crafting_panel.hide()
	_inventory_backdrop.hide()
	if not _inventory_was_paused:
		Session.set_paused(false, false)


func _on_recipe_pressed(recipe_id: String) -> void:
	var cell := _crafting_cell
	_set_crafting_open(false)
	crafting_recipe_requested.emit(cell, recipe_id)


func _on_crafting_close_requested() -> void:
	_set_crafting_open(false)
