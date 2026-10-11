extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Stress := preload("res://src/dev/settlement_stress_scenario.gd")
class ObservedWorld extends World:
	var cell_sets := 0
	func _room_cells_set(values: Variant) -> Dictionary:
		cell_sets += 1
		return super._room_cells_set(values)
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var scenario := Stress.build(1)
	check(bool(scenario.success),"The thirty-house fixture is generated successfully")
	var sim := ObservedWorld.new(scenario.state)
	var before := sim.housing.places(sim)
	sim.add_structure({"building_id":"core:wood_floor","cell":[124,124]})
	sim.cell_sets = 0
	var after := sim.housing.places(sim)
	check(before == after and after.size() >= 31,"Distant construction preserves all thirty actual bed places")
	check(sim.cell_sets <= 100,"Housing rebuild gathers each room cell set once, instead of once per bed-room pair")
	var wall := {"building_id":"core:wood_wall","cell":[15,47]}
	check(sim.remove_structure(wall),"A boundary wall is removed through the structure authority")
	check(not bool(sim.housing.place(sim,"core:bedroll@15,48").valid),"Opening one room immediately invalidates its sleeping place")
	check(bool(sim.housing.place(sim,"core:bedroll@31,48").valid),"Opening one room does not invalidate the adjacent house")
	check(sim.add_structure(wall),"A boundary wall can be restored")
	check(bool(sim.housing.place(sim,"core:bedroll@15,48").valid),"Restoring the boundary restores valid housing")
	print("HOUSING_ROOM_SETS_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
