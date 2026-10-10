extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Knowledge := preload("res://src/characters/npc_knowledge.gd")
const NPC := "core:first_neighbor"
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_first_authored_greeting(World.new())
	for malformed: Variant in [null, [], "invalid"]:
		var sim := World.new()
		var state := sim.export_state()
		if malformed == null: state.npcs[NPC].erase("known_facts")
		else: state.npcs[NPC].known_facts = malformed
		_test_first_authored_greeting(World.new(JSON.parse_string(JSON.stringify(state))))
	var incomplete := {"known":false}
	check(Knowledge.remember(incomplete,"name",{"source":"conversation"}), "Remember safely initializes an absent knowledge map")
	check(bool(incomplete.known) and incomplete.get("known_facts",{}).has("name"), "Remember retains the actually heard name")
	check(not Knowledge.remember(incomplete,"name",{"source":"duplicate"}), "Repeated name does not overwrite its first source")
	if failures == 0: print("PASS: first Mira greeting, missing/malformed legacy knowledge, heard facts and save continuity")
	quit(0 if failures == 0 else 1)

func _test_first_authored_greeting(sim) -> void:
	var npc: Dictionary = sim.state.npcs[NPC]
	npc.active = true
	npc.known = false
	check(npc.get("known_facts") is Dictionary, "Authored and loaded NPC always have a knowledge map")
	if npc.has("known_facts") and not npc.known_facts is Dictionary: return
	sim.set_player_position(sim.get_npc_position(NPC,Vector2.ZERO)+Vector2(32,0))
	var utterance: Dictionary = sim.choose_npc_conversation(NPC,"greeting")
	check(bool(utterance.get("ok",false)), "Nearby unknown Mira offers her first greeting")
	if not bool(utterance.get("ok",false)): return
	check(not npc.known and not npc.get("known_facts",{}).has("name"), "Preparing a greeting does not disclose its unheard name")
	var acknowledged: Dictionary = sim.acknowledge_npc_utterance(NPC,String(utterance.utterance_id),0)
	check(bool(acknowledged.get("ok",false)) and npc.known and npc.get("known_facts",{}).has("name"), "Displaying Mira's greeting learns her name without script errors")
	var count := int(npc.talk_count)
	sim.acknowledge_npc_utterance(NPC,String(utterance.utterance_id),0)
	check(int(npc.talk_count) == count, "Repeated page acknowledgement stays idempotent")
	var saved := World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(saved.state.npcs[NPC].known and saved.state.npcs[NPC].get("known_facts",{}).has("name"), "Heard Mira identity survives JSON save/load")
