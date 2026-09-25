class_name CraftingPanel
extends PanelContainer

signal close_requested
signal recipe_requested(recipe_id: String)

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")

var _content_data: FirstNightContent

@onready var _title_label: Label = $Margin/Column/Header/Title as Label
@onready var _close_button: Button = $Margin/Column/Header/Close as Button
@onready var _hint_label: Label = $Margin/Column/Hint as Label
@onready var _recipes: VBoxContainer = $Margin/Column/Recipes as VBoxContainer
@onready var _footer_label: Label = $Margin/Column/Footer as Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiSkin.panel_style())
	_title_label.add_theme_color_override("font_color", UiSkin.TEXT_PRIMARY)
	_hint_label.add_theme_color_override("font_color", UiSkin.TEXT_MUTED)
	_footer_label.add_theme_color_override("font_color", UiSkin.TEXT_ACCENT)
	UiSkin.apply_close_button(_close_button)
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	_title_label.text = Localized.resolve("ui.crafting.title")
	_hint_label.text = Localized.resolve("ui.crafting.hint.short")
	_footer_label.text = Localized.resolve("ui.crafting.footer")


func present(
	recipes: Array[Dictionary],
	content_data: FirstNightContent
) -> void:
	_content_data = content_data
	for child: Node in _recipes.get_children():
		child.queue_free()
	for recipe: Dictionary in recipes:
		var recipe_id := String(recipe.get("id", ""))
		var button := Button.new()
		button.custom_minimum_size = Vector2(320.0, 48.0)
		button.text = _format_recipe(recipe)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 11)
		UiSkin.apply_card_button(button)
		button.pressed.connect(_emit_recipe.bind(recipe_id))
		_recipes.add_child(button)


func choose_recipe(recipe_id: String) -> void:
	_emit_recipe(recipe_id)


func _emit_recipe(recipe_id: String) -> void:
	recipe_requested.emit(recipe_id)


func _format_recipe(recipe: Dictionary) -> String:
	var input_text := _format_items(recipe.get("inputs", {}) as Dictionary)
	var output_text := _format_items(recipe.get("outputs", {}) as Dictionary)
	return "%s\n%s  →  %s   ·   %d мин" % [
		Localized.resolve(String(recipe.get("label_key", recipe.get("id", "")))),
		input_text,
		output_text,
		int(recipe.get("work_minutes", 0)),
	]


func _format_items(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_variant: Variant in items.keys():
		var item_id := String(item_variant)
		parts.append("%d %s" % [
			int(items[item_variant]),
			Localized.resolve(_content_data.item_label_key(item_id)),
		])
	return ", ".join(parts)
