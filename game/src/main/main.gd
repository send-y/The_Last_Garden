extends Node2D
const ConstructionCommand := preload(
	"res://src/construction/construction_command.gd"
)

@onready var _player: PlayerController = $Player as PlayerController
@onready var _world: FirstNightWorld = $World as FirstNightWorld
@onready var _hud: FirstNightHud = $Hud/HudRoot as FirstNightHud
@onready var _dusk_overlay: ColorRect = $DuskOverlay/ColorRect as ColorRect
@onready var _construction_cursor: ConstructionCursor = (
	$ConstructionCursor as ConstructionCursor
)


func _ready() -> void:
	_world.selection_changed.connect(_hud.set_selection)
	_hud.build_mode_toggled.connect(
	_construction_cursor.set_build_mode_active
	)
	_construction_cursor.cell_selected.connect(
		_on_construction_cell_selected
	)
	_construction_cursor.cell_cancel_requested.connect(
		_on_construction_cell_cancel_requested
	)
	Session.state_reloaded.connect(_player.apply_loaded_position)
	Session.time_changed.connect(_update_dusk_overlay)
	_update_dusk_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_time"):
		Session.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_save"):
		Session.save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_load"):
		Session.load_game()
		get_viewport().set_input_as_handled()


func _on_construction_cell_selected(cell: Vector2i) -> void:
	var command: Dictionary = ConstructionCommand.place_wall_blueprint(cell)
	var result: Dictionary = Session.execute_construction_command(command)
	_show_construction_result(result)

func _on_construction_cell_cancel_requested(cell: Vector2i) -> void:
	var command: Dictionary = ConstructionCommand.cancel_blueprint(cell)
	var result: Dictionary = Session.execute_construction_command(command)
	_show_construction_result(result)


func _show_construction_result(result: Dictionary) -> void:
	var reason_id: String = String(result.get("reason_id", ""))
	var message_key: String = "construction.feedback.invalid"

	match reason_id:
		"core:blueprint_placed":
			message_key = "construction.feedback.blueprint_placed"
		"core:blueprint_cancelled":
			message_key = "construction.feedback.blueprint_cancelled"
		"core:blocked_cell":
			message_key = "construction.feedback.blocked_cell"
		"core:occupied_cell":
			message_key = "construction.feedback.occupied_cell"
		"core:missing_blueprint":
			message_key = "construction.feedback.missing_blueprint"
		"core:out_of_bounds":
			message_key = "construction.feedback.out_of_bounds"

	Session.notify_player_key(
		message_key,
		{},
		bool(result.get("success", false))
	)


func _update_dusk_overlay() -> void:
	var minute: int = Session.get_minute_of_day()
	var alpha: float = 0.0
	if minute >= 17 * 60:
		alpha = remap(clampf(float(minute), 17.0 * 60.0, 22.0 * 60.0), 17.0 * 60.0, 22.0 * 60.0, 0.0, 0.42)
	_dusk_overlay.color = Color(0.10, 0.13, 0.28, alpha)
