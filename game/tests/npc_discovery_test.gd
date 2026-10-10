extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(value: bool,message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _run() -> void:
	var sim := World.new()
	if not sim.has_method("choose_npc_conversation"):
		push_error("Missing conversation and controlled disclosure")
		quit(1)
		return
	var created: Dictionary = sim.create_generated_npc(94,Vector2i(24,29))
	var id: String = created.npc_id
	sim.arrive_npc(id,Vector2i(24,29))
	sim.set_player_position(sim.get_npc_position(id,Vector2.ZERO)+Vector2(32,0))
	sim.execute_interaction(id)
	check(not sim.state.npcs[id].known and sim.state.npcs[id].known_facts.is_empty(),"Legacy talk cannot bypass page disclosure")
	var before := sim.export_state()
	var topics: Array = sim.get_npc_conversation_topics(id)
	check(not topics.is_empty() and topics[0].topic_id == "greeting", "Unknown greeting")
	check(sim.export_state() == before, "Topics read-only")
	check(sim.get_npc_profile_summary(id).facts.is_empty(), "No hidden facts exposed")
	var greeting: Dictionary = sim.choose_npc_conversation(id,"greeting")
	check(greeting.ok and not sim.state.npcs[id].known, "Choosing does not disclose")
	check(not sim.acknowledge_npc_utterance(id,"forged",0).ok, "Forged utterance rejected")
	check(not sim.acknowledge_npc_utterance(id,greeting.utterance_id,1).ok, "Skipping page rejected")
	check(sim.acknowledge_npc_utterance(id,greeting.utterance_id,0).ok, "Displayed name learned")
	check(sim.state.npcs[id].known and not sim.state.npcs[id].known_facts.has("experience_id"), "Only displayed page facts")
	check(sim.state.npcs[id].conversation_history.size() == 1 and sim.state.npcs[id].conversation_history[0].pages.size() == 1,"History records heard page without the unseen next page")
	sim.close_npc_conversation()
	var resumed: Array = sim.get_npc_conversation_topics(id)
	check(not resumed.is_empty(),"Interrupted introduction remains available")
	greeting = sim.choose_npc_conversation(id,"greeting")
	check(greeting.ok,"Partly introduced NPC can continue talking")
	if not greeting.get("ok",false):
		quit(1)
		return
	sim.acknowledge_npc_utterance(id,greeting.utterance_id,0)
	check(sim.acknowledge_npc_utterance(id,greeting.utterance_id,1).ok, "Displayed experience learned")
	var count: int = sim.state.npcs[id].talk_count
	sim.acknowledge_npc_utterance(id,greeting.utterance_id,1)
	check(sim.state.npcs[id].talk_count == count, "Acknowledgement idempotent")
	var work: Dictionary = sim.choose_npc_conversation(id,"work")
	check(work.ok, "Work topic available")
	sim.acknowledge_npc_utterance(id,work.utterance_id,0)
	check(sim.state.npcs[id].known_facts.has("aspiration_id"), "Aspiration only after utterance")
	check(not sim.choose_npc_conversation(id,"past").ok, "Past not forced before context")
	sim.state.npcs[id].needs.hunger = 5
	var hungry: Dictionary = sim.choose_npc_conversation(id,"values")
	check(not hungry.ok and not sim.state.npcs[id].known_facts.has("value_ids"), "Refusal conceals values")
	var reloaded := World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(reloaded.get_npc_profile_summary(id).facts.size() == 2 and reloaded.state.npcs[id].known_facts.size() == 3, "Learned facts persisted, name separate from biography")
	check(not reloaded.acknowledge_npc_utterance(id,work.utterance_id,0).ok, "Pending conversation is not replayable after reload")
	var summary: Dictionary = sim.get_npc_profile_summary(id)
	summary.facts.clear()
	check(sim.get_npc_profile_summary(id).facts.size() == 2, "Summary query copy")
	sim.set_player_position(Vector2.ZERO)
	check(not sim.choose_npc_conversation(id,"work").ok, "Remote dialogue rejected")
	sim.state.npcs[id].needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
	sim.advance_minutes(360)
	sim.state.npcs[id].talk_count = 4
	sim.set_player_position(sim.get_npc_position(id,Vector2.ZERO)+Vector2(32,0))
	var family: Dictionary = sim.choose_npc_conversation(id,"heritage")
	check(family.get("ok",false),"Suitable conversation context can reveal a family account")
	if family.get("ok",false):
		sim.acknowledge_npc_utterance(id,family.utterance_id,0)
		var family_reload := World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
		check(family_reload.state.npcs[id].known_facts.heritage_ids.account_kind == "family_account" and family_reload.state.npcs[id].known_facts.heritage_ids.speaker_id == id,"Heard family account keeps its provenance after loading")
	var authored := World.new()
	var mira: Dictionary = authored.state.npcs["core:first_neighbor"]
	mira.active = true
	mira.known = true
	mira.memories.append(preload("res://src/simulation/npc_memory.gd").create_first_shared_wall(2,500,Vector2i(22,29)))
	authored.set_player_position(authored.get_npc_position("core:first_neighbor",Vector2.ZERO)+Vector2(32,0))
	var remembered: Dictionary = authored.choose_npc_conversation("core:first_neighbor","chat")
	check(remembered.get("ok",false),"Mira can discuss her existing authored memories")
	if remembered.get("ok",false):
		check(remembered.pages[0].text_key == "dialogue.core.first_neighbor.shared_wall" and not mira.memories[0].acknowledged,"Memory line prepared without acknowledging unseen text")
		authored.acknowledge_npc_utterance("core:first_neighbor",remembered.utterance_id,0)
		check(mira.memories[0].acknowledged,"Memory acknowledged only after display")
	if failures == 0: print("PASS: gradual NPC discovery, contextual refusal, page acknowledgements and persistence")
	quit(0 if failures == 0 else 1)
