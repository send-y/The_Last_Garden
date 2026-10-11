extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Housing := preload("res://src/housing/housing_system.gd")
const Layout := preload("res://src/npc_work/home_furnishing_layout.gd")
const Stock := preload("res://src/npc_work/home_project_stock.gd")

class ObservedWorld extends World:
	var position_reads := 0
	func get_npc_position(id: String, fallback: Vector2) -> Vector2:
		position_reads += 1
		return super.get_npc_position(id,fallback)

class ObservedHousing extends Housing:
	var full_place_lists := 0
	func places(sim) -> Array[Dictionary]:
		full_place_lists += 1
		return super.places(sim)

var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var original = Fixture.create()
	Fixture.stock(original,30)
	var sim := ObservedWorld.new(original.export_state())
	sim.housing = ObservedHousing.new()
	var npc: Dictionary = sim.state.npcs[Fixture.NPC]
	var room := Layout.territory(sim,npc)
	check(room.id == Fixture.ROOM and room.home.place_id == "core:bedroll@40,30","Work territory identifies the actual assigned home")
	check(sim.housing.full_place_lists == 0,"One resident's territory must not enumerate every sleeping place and owner")
	var goal := {"action":"build","building_id":"core:table","cell":[42,33]}
	sim.position_reads = 0
	var report := Stock.report(sim,npc,goal)
	check(report.missing.is_empty() and report.protected.is_empty(),"Thirty reachable planks fully supply the planned table")
	check(sim.position_reads == 1,"Project materials must only check cells with required items, not the tool warehouse")
	sim.StockReserves.set_reserve(sim,"core:plank",3)
	report = Stock.report(sim,npc,goal)
	check(report.missing == {"core:plank":3} and report.protected == {"core:plank":3},"An updated protected reserve immediately affects an existing goal")
	npc.work_cargo = {"core:plank":30}
	sim.position_reads = 0
	report = Stock.report(sim,npc,goal)
	check(report.missing.is_empty() and report.protected.is_empty(),"Carried materials satisfy the goal without another withdrawal")
	check(sim.position_reads == 0,"A fully supplied goal does not search warehouse approaches")
	print("NPC_WORK_MATERIAL_QUERY: %d failures" % failures)
	quit(0 if failures == 0 else 1)
