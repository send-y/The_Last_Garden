extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func run() -> void:
	var sim = World.new(World.create_new_game_state())
	if not "work_metrics" in sim:
		check(false,"World provides optional per-resident work metrics")
		finish(); return
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.active = true
	npc.known = true
	var before := JSON.stringify(sim.export_state())
	sim.work_metrics.enabled = true
	sim.work_metrics.observe_minute(sim)
	check(JSON.stringify(sim.export_state()) == before,"Metrics never modify saved simulation state")
	var axes: Array[String] = sim._create_item_instances("core:axe_stone",1,"npc",String(npc.id))
	npc.carried_instance_id = axes[0]
	var target := "core:wood_north"
	var at: Vector2 = sim.content.get_interactable(target).position
	npc.position = [at.x,at.y]
	check(sim.execute_resource_work(String(npc.id),target).success,"Real measured NPC work succeeds")
	var rows: Dictionary = sim.work_metrics.snapshot(sim.get_day())
	check(is_equal_approx(float(rows[String(npc.id)].work_units),1.5),"Metrics count actual stone-tool contribution rather than attempted work")
	check(int(rows[String(npc.id)].idle_minutes) == 1,"Idle minute is counted separately from useful work")
	finish()
func finish() -> void:
	print("PLAYTEST_WORK_METRICS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
