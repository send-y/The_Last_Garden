extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const NPC := "core:first_neighbor"
const Meeting := preload("res://src/characters/npc_first_meeting.gd")
const Localized := preload("res://src/localization/localized_text.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func fixture():
	var sim = World.new(World.create_new_game_state())
	var npc: Dictionary = sim.state.npcs[NPC]
	npc.active = true
	sim.set_player_position(sim.get_npc_position(NPC,Vector2.ZERO)+Vector2(32,0))
	return sim
func finish(sim, view: Dictionary) -> void:
	if not bool(view.get("ok",false)): return
	for i: int in range(view.pages.size()):
		check(bool(sim.acknowledge_npc_utterance(String(view.npc_id),String(view.utterance_id),i).ok),"Actual page acknowledged")
func has_topic(sim, id: String) -> bool:
	for topic: Dictionary in sim.get_npc_conversation_topics(NPC):
		if String(topic.topic_id) == id: return true
	return false
func run() -> void:
	TranslationServer.set_locale("ru")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Meeting.PATH))
	check(Meeting.validate_data(data).is_empty(),"First-meeting catalog validates")
	data.typo = true
	check(not Meeting.validate_data(data).is_empty(),"Unsupported first-meeting fields are diagnosed")
	var sim = fixture()
	check(int(sim.state.npcs[NPC].personal_inventory.get("core:food",0)) == 18,"Mira actually brings eighteen portions")
	for hungers: Array in [[1,72],[90,1],[1,1]]:
		sim = fixture()
		sim.state.player_needs.hunger = hungers[0]
		sim.state.npcs[NPC].needs.hunger = hungers[1]
		var view: Dictionary = sim.choose_npc_conversation(NPC,"greeting")
		check(bool(view.ok),"Short first meeting works with hungry participants")
		if not bool(view.ok): continue
		for page: Dictionary in view.pages:
			check(Localized.resolve(String(page.text_key),page.text_args) != String(page.text_key),"Meeting line is present in Russian localization")
		sim.acknowledge_npc_utterance(NPC,String(view.utterance_id),0)
		check(not has_topic(sim,"chat"),"Hearing name alone does not expose ordinary small talk")
		finish(sim,view)
		check(has_topic(sim,"take_supplies"),"First meeting offers a concrete food action")
		var gift: Dictionary = sim.choose_npc_conversation(NPC,"take_supplies")
		check(bool(gift.ok),"Hungry NPC can share its welcome gift")
		finish(sim,gift)
		check(sim.get_item_count("core:food") == 10 and int(sim.state.npcs[NPC].personal_inventory["core:food"]) == 8,"Gift transfers ten real portions and preserves eight for Mira")
		check(not has_topic(sim,"chat") and not has_topic(sim,"home"),"Small talk remains absent during first meeting and gift exchange")
		var loaded = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
		loaded.choose_npc_conversation(NPC,"take_supplies")
		check(loaded.get_item_count("core:food") == 10 and int(loaded.state.npcs[NPC].personal_inventory["core:food"]) == 8,"Reload and repeated response never duplicate supplies")
		check(not bool(loaded.choose_npc_conversation(NPC,"past").ok),"Ordinary long conversation retains its needs/context restrictions")
	sim = fixture()
	finish(sim,sim.choose_npc_conversation(NPC,"greeting"))
	# Fill all sixteen cells through real inventory packing.
	check(bool(sim.try_pickup_item("core:wood",80).success),"Full backpack fixture uses real packing")
	var before: int = sim.state.npcs[NPC].personal_inventory["core:food"]
	finish(sim,sim.choose_npc_conversation(NPC,"take_supplies"))
	check(sim.get_item_count("core:food") == 0 and int(sim.state.npcs[NPC].personal_inventory["core:food"]) == before,"Failed full-inventory transfer preserves all food")
	check(has_topic(sim,"take_supplies"),"Unreceived gift remains available")
	sim.drop_inventory_stack("core:wood",0)
	finish(sim,sim.choose_npc_conversation(NPC,"take_supplies"))
	check(sim.get_item_count("core:food") == 5 and int(sim.state.npcs[NPC].personal_inventory["core:food"]) == 13,"One free cell receives only fitting five portions")
	var loaded = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	loaded.drop_inventory_stack("core:wood",0)
	finish(loaded,loaded.choose_npc_conversation(NPC,"take_supplies"))
	check(loaded.get_item_count("core:food") == 10 and int(loaded.state.npcs[NPC].personal_inventory["core:food"]) == 8,"Partial gift resumes after reload without reissuing earlier portions")
	sim = fixture()
	finish(sim,sim.choose_npc_conversation(NPC,"greeting"))
	finish(sim,sim.choose_npc_conversation(NPC,"decline_supplies"))
	check(sim.get_item_count("core:food") == 0 and int(sim.state.npcs[NPC].personal_inventory["core:food"]) == 18,"Refusal never destroys Mira's food")
	check(not has_topic(sim,"take_supplies"),"Declined gift is not repeatedly offered")
	# Facts of the world and existing character habits choose semantic pages.
	sim = fixture()
	var plain: Dictionary = sim.choose_npc_conversation(NPC,"greeting")
	sim.state.flags.repair_stage = 2
	var covered: Dictionary = sim.choose_npc_conversation(NPC,"greeting")
	check(plain.get("pages",[]) != covered.get("pages",[]),"Opening responds to actual roof state")
	var created: Dictionary = sim.create_generated_npc(94,Vector2i(24,29))
	var id := String(created.npc_id)
	sim.arrive_npc(id,Vector2i(24,29))
	sim.set_player_position(sim.get_npc_position(id,Vector2.ZERO)+Vector2(32,0))
	sim.npc_catalog._profiles[id].habit_ids = ["core:habit_prepare"]
	var careful: Dictionary = sim.choose_npc_conversation(id,"greeting")
	sim.npc_catalog._profiles[id].habit_ids = ["core:habit_try"]
	var direct: Dictionary = sim.choose_npc_conversation(id,"greeting")
	check(careful.get("pages",[]) != direct.get("pages",[]),"Existing different habits produce different introductions")
	# Legacy familiarity and heard facts must survive the additive gift migration.
	var raw: Dictionary = fixture().export_state()
	raw.npcs[NPC].known = true
	raw.npcs[NPC].known_facts = {"name":{"source":"conversation"}}
	raw.npcs[NPC].talk_count = 5
	raw.npcs[NPC].erase("welcome_gift")
	raw.npcs[NPC].erase("first_meeting_complete")
	loaded = World.new(raw)
	check(loaded.state.npcs[NPC].known_facts == raw.npcs[NPC].known_facts and loaded.state.npcs[NPC].talk_count == 5,"Legacy acquaintance is never reset")
	check(has_topic(loaded,"take_supplies"),"Legacy familiar Mira has one additive welcome gift")
	sim = fixture()
	finish(sim,sim.choose_npc_conversation(NPC,"greeting"))
	check(not has_topic(sim,"chat"),"Small talk waits until first encounter has closed")
	sim.close_npc_conversation()
	check(has_topic(sim,"chat"),"Later conversation remains available without arbitrary time delay")
	print("PACKAGE_D_MEETING: %d failures" % failures)
	quit(0 if failures == 0 else 1)
