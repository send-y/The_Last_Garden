extends RefCounted

const Localized := preload("res://src/localization/localized_text.gd")

static func normalize(sim) -> void:
	var raw: Variant = sim.state.get("stock_reserves", {})
	var normalized: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in raw:
			if not key is String or not _valid_item(sim,String(key)) or not _valid_amount(raw[key]): continue
			var amount := int(raw[key])
			if amount > 0: normalized[String(key)] = amount
	sim.state.stock_reserves = normalized

static func total(sim, item_id: String) -> int:
	var count := 0
	for record: Dictionary in sim.state.storage_items:
		if String(record.get("item_id","")) == item_id: count += maxi(0,int(record.get("amount",0)))
	return count

static func available(sim, item_id: String) -> int:
	return maxi(0,total(sim,item_id) - int(sim.state.stock_reserves.get(item_id,0)))

static func report(sim) -> Array[Dictionary]:
	var included: Dictionary = {}
	for record: Dictionary in sim.state.storage_items: included[String(record.get("item_id",""))] = true
	for id: String in sim.state.stock_reserves: included[id] = true
	for building_id: String in ["core:table", "core:chair", "core:torch"]:
		for item_id: String in sim.building_catalog.get_material_cost(building_id): included[item_id] = true
	var result: Array[Dictionary] = []
	for item_id: String in sim.content.item_ids():
		if included.has(item_id) and _valid_item(sim,item_id):
			var count := total(sim,item_id)
			var reserved := int(sim.state.stock_reserves.get(item_id,0))
			result.append({"item_id":item_id,"label_key":sim.content.item_label_key(item_id),"stock":count,"reserved":reserved,"available":maxi(0,count-reserved)})
	return result

static func set_reserve(sim, item_id: String, amount: Variant) -> Dictionary:
	if not _valid_item(sim,item_id): return sim._emit_result(false,"stock.reserve.failure.item")
	if not _valid_amount(amount): return sim._emit_result(false,"stock.reserve.failure.amount")
	if int(amount) == 0: sim.state.stock_reserves.erase(item_id)
	else: sim.state.stock_reserves[item_id] = int(amount)
	return sim._emit_result(true,"stock.reserve.changed",true,false,{"item":Localized.text_reference(sim.content.item_label_key(item_id)),"amount":int(amount)})

static func _valid_item(sim, item_id: String) -> bool:
	return sim.content.has_item(item_id) and sim.content.item_ids().has(item_id) and not sim.content.item_is_instance_based(item_id)

static func _valid_amount(amount: Variant) -> bool:
	if not (amount is int or amount is float): return false
	var value := float(amount)
	return is_finite(value) and value >= 0.0 and value < 9223372036854775807.0 and value == floor(value)
