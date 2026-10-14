extends RefCounted

# One authority for regrowth and yields, shared by player collection and NPC meals.
static func harvest(sim, actor_id: String, object_id: String) -> Dictionary:
	var target: Dictionary = sim._resolve_interaction_target(object_id)
	if target.is_empty() or String(target.get("kind","")) != "food" or sim.should_hide_interactable(object_id,"food") or not sim.farming.berry_ready(sim,object_id):
		return {"success":false,"reason":"unavailable"}
	var actor: Dictionary = sim._get_resource_actor_position(actor_id)
	if not bool(actor.get("found",false)) or Vector2(actor.position).distance_to(Vector2(target.position)) > sim.content.INTERACTION_RANGE:
		return {"success":false,"reason":"too_far"}
	var rule: Dictionary = sim.content.get_collect_rule("food")
	var item_id := String(rule.get("item_id",""))
	var amount := int(rule.get("amount",0))
	if amount <= 0 or not sim.content.has_item(item_id): return {"success":false,"reason":"invalid_source"}
	if actor_id == "core:player":
		if not sim._can_add_item(item_id,amount): return {"success":false,"reason":"inventory_full"}
		sim._add_item(item_id,amount)
	else:
		var npc: Dictionary = sim.state.npcs.get(actor_id,{})
		if npc.is_empty() or not bool(npc.active): return {"success":false,"reason":"unknown_actor"}
		npc.personal_inventory[item_id] = int(npc.personal_inventory.get(item_id,0))+amount
	sim.state.farming.berry_ready_at[object_id] = sim.get_elapsed_game_minutes()+int(sim.farming.catalog.settings.berry_regrow_minutes)
	return {"success":true,"item_id":item_id,"amount":amount}
