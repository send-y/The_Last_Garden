extends RefCounted

const Introduction := preload("res://src/characters/npc_introduction.gd")
const Knowledge := preload("res://src/characters/npc_knowledge.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const PATH := "res://content/core/npc_conversations.json"
const Meeting := preload("res://src/characters/npc_first_meeting.gd")

static func definitions() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return data.get("topics",[]) if data is Dictionary else []

static func available(sim, npc: Dictionary, topic: Dictionary) -> bool:
	if String(topic.id) == "greeting":
		return not Meeting.complete(npc)
	if not Meeting.complete(npc): return false
	if String(topic.id) == "overview": return true
	if String(topic.id) in ["take_supplies","decline_supplies"]: return Meeting.gift_available(npc)
	if String(topic.id) in ["chat","home","past","values","heritage"] and not bool(npc.get("first_meeting_closed",true)): return false
	if not bool(npc.get("known",false)): return false
	if String(topic.id) == "stay" and String(npc.get("residency","resident")) != "visitor": return false
	if sim.npc_catalog.get_profile(String(npc.id)).is_empty(): return String(topic.id) in ["home","chat"]
	return int(npc.get("talk_count",0)) >= int(topic.get("min_talks",0)) and sim.get_elapsed_game_minutes()-int(npc.get("arrival_minute",0)) >= int(topic.get("wait_minutes",0))

static func in_range(sim, npc_id: String) -> bool:
	return sim.is_npc_visible(npc_id) and sim.get_player_position().distance_to(sim.get_npc_position(npc_id,Vector2.ZERO)) <= 68.0

static func get_topics(sim, npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var npc: Dictionary = sim.state.npcs.get(npc_id,{})
	if npc.is_empty() or not in_range(sim,npc_id): return result
	for topic: Dictionary in definitions():
		if not bool(topic.get("hidden",false)) and available(sim,npc,topic): result.append({"topic_id":String(topic.id),"label_key":String(topic.label_key)})
	return result

static func choose(sim, npc_id: String, topic_id: String) -> Dictionary:
	var npc: Dictionary = sim.state.npcs.get(npc_id,{})
	if npc.is_empty() or not in_range(sim,npc_id): return {"ok":false,"reason_key":"interaction.failure.too_far"}
	var chosen: Dictionary = {}
	for topic: Dictionary in definitions():
		if String(topic.id) == topic_id: chosen = topic
	if chosen.is_empty() or not available(sim,npc,chosen): return {"ok":false,"reason_key":"conversation.refuse.context"}
	if topic_id not in ["greeting","overview","take_supplies","decline_supplies"] and (float(npc.needs.hunger) < 25 or float(npc.needs.energy) < 18):
		return {"ok":false,"reason_key":"conversation.refuse.needs"}
	var profile: Dictionary = sim.npc_catalog.get_profile(npc_id)
	var pages: Array[Dictionary] = []
	var discussed_memory := ""
	if topic_id == "greeting":
		pages = Meeting.pages(sim,npc)
	elif topic_id == "overview":
		pages.append({"text_key":"meeting.overview", "text_args":{}, "facts":[]})
	elif topic_id in ["take_supplies","decline_supplies"]:
		pages.append(Meeting.receive(sim,npc,topic_id == "decline_supplies"))
	elif profile.is_empty():
		var definition: Dictionary = sim.npc_catalog.get_definition(npc_id)
		pages.append({"text_key":String(definition.get("greeting_key","conversation.home")) if topic_id == "greeting" else "conversation.home",
			"text_args":{},"facts":["name"] if topic_id == "greeting" else []})
		if topic_id == "chat":
			pages[0].text_key = String(definition.get("repeat_line_key","npc.generated.repeat"))
			for memory: Dictionary in npc.get("memories",[]):
				var line := String(definition.get("context_lines",{}).get(String(memory.get("event_id","")),""))
				if not bool(memory.get("acknowledged",false)) and not line.is_empty():
					pages[0].text_key = line
					discussed_memory = String(memory.get("memory_id",""))
					break
	else:
		for template: Dictionary in chosen.pages:
			var args: Dictionary = {}
			for argument: String in template.get("args",{}): args[argument] = Introduction.field_reference(profile,String(template.args[argument]))
			pages.append({"text_key":String(template.text_key),"text_args":args,"facts":template.get("facts",[]).duplicate()})
	if topic_id == "home":
		var home: Dictionary = sim.housing.home(sim,npc_id)
		pages[0].text_key = "conversation.home.assigned" if bool(home.get("valid",false)) else "conversation.home.missing"
		var project: Dictionary = sim.get_npc_personal_goal(npc_id)
		var expansion: Dictionary = project.get("expansion",{})
		if not expansion.is_empty():
			pages[0].text_key = "conversation.home.expansion"
			pages[0].text_args = {"item":Localized.text_reference(sim.building_catalog.get_definition(String(expansion.building_id)).label_key)}
		elif String(project.get("status","")) == "reserve":
			pages[0].text_key = "conversation.home.reserve"
	var serial: int = int(sim._npc_conversation_pending.get("serial",0))+1
	var utterance_id := "%s:%d" % [npc_id,serial]
	sim._npc_conversation_pending = {"serial":serial,"npc_id":npc_id,"utterance_id":utterance_id,"topic_id":topic_id,
		"pages":pages.duplicate(true),"acknowledged":[],"complete":false,"memory_id":discussed_memory}
	return {"ok":true,"npc_id":npc_id,"utterance_id":utterance_id,"pages":public_pages(pages),"name_key":sim.npc_catalog.get_label_key(sim.state.npcs,npc_id,"npc.generic.traveler.name")}

static func public_pages(pages: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for page: Dictionary in pages: result.append({"text_key":page.text_key,"text_args":page.text_args.duplicate(true)})
	return result

static func acknowledge(sim, npc_id: String, utterance_id: String, page_index: int) -> Dictionary:
	var pending: Dictionary = sim._npc_conversation_pending
	if String(pending.get("npc_id","")) != npc_id or String(pending.get("utterance_id","")) != utterance_id or not in_range(sim,npc_id):
		return {"ok":false}
	if page_index < 0 or page_index >= pending.pages.size(): return {"ok":false}
	if pending.acknowledged.has(page_index): return {"ok":true,"changed":false}
	if page_index != pending.acknowledged.size(): return {"ok":false}
	var npc: Dictionary = sim.state.npcs[npc_id]
	var changed := false
	for fact: String in pending.pages[page_index].facts:
		var source := {"source":"conversation","speaker_id":npc_id,"minute":sim.get_elapsed_game_minutes(),"utterance_id":utterance_id,
			"account_kind":"family_account" if fact == "heritage_ids" else "self_report"}
		changed = Knowledge.remember(npc,fact,source) or changed
	pending.acknowledged.append(page_index)
	var history: Array = npc.get("conversation_history",[])
	if not pending.has("history_index"):
		history.append({"topic_id":String(pending.topic_id),"minute":sim.get_elapsed_game_minutes(),"pages":[],"complete":false})
		history = history.slice(maxi(0,history.size()-24))
		pending["history_index"] = history.size()-1
	var page: Dictionary = pending.pages[page_index]
	history[int(pending.history_index)].pages.append({"text_key":String(page.text_key),"text_args":page.text_args.duplicate(true)})
	npc["conversation_history"] = history
	changed = true
	if pending.acknowledged.size() == pending.pages.size() and not pending.complete:
		pending.complete = true
		if String(pending.topic_id) == "greeting":
			npc.first_meeting_complete = true
			npc.first_meeting_closed = false
		npc.talk_count = int(npc.get("talk_count",0))+1
		sim.needs.add_effect(npc,"conversation",sim.get_elapsed_game_minutes())
		if String(pending.topic_id) == "stay": sim.set_npc_resident(npc_id,true)
		if not String(pending.get("memory_id","")).is_empty():
			for memory: Dictionary in npc.get("memories",[]):
				if String(memory.get("memory_id","")) == String(pending.memory_id): memory.acknowledged = true
		history[int(pending.history_index)].complete = true
		changed = true
	if changed: sim.event_emitted.emit({"type":"state_changed"})
	return {"ok":true,"changed":changed}
