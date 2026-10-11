extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Stress := preload("res://src/dev/settlement_stress_scenario.gd")
class ReferenceWorld extends World:
	func _emit_result(success: bool, message_key: String, changed: bool = false, auto_save: bool = false, message_args: Dictionary = {}, _inventory_changed: bool = true) -> Dictionary:
		return super._emit_result(success,message_key,changed,auto_save,message_args,true)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var old_furniture: GDScript = load(args[0])
	if old_furniture == null:
		quit(1)
		return
	var scenario := Stress.build(30)
	var current := World.new(scenario.state)
	var reference := ReferenceWorld.new(scenario.state)
	reference.furniture = old_furniture.new()
	reference.furniture.normalize(reference)
	reference.housing.approach_cache_enabled = false
	var equal := current.export_state() == reference.export_state()
	var checked := 0
	var meals := 0
	for minute: int in range(66):
		for sim in [current,reference]:
			sim.advance_minutes(1)
			Stress.replenish(sim)
		checked += 1
		for npc: Dictionary in current.state.npcs.values():
			if not npc.get("meal_trip",{}).is_empty() or not npc.get("furniture_use",{}).is_empty(): meals += 1
		if current.export_state() != reference.export_state():
			equal = false
			FileAccess.open(args[1]+"-current.json",FileAccess.WRITE).store_string(JSON.stringify(current.export_state()))
			FileAccess.open(args[1]+"-reference.json",FileAccess.WRITE).store_string(JSON.stringify(reference.export_state()))
			push_error("Seat-range authority differs at minute %d" % (minute+1))
			break
	var report := {"equal":equal,"minutes":checked,"participants":30,"meal_or_furniture_user_minutes":meals}
	FileAccess.open(args[1]+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print("MEAL_AUTHORITY_PROBE: ",JSON.stringify(report))
	quit(0 if equal else 1)
