extends RefCounted

# Preserve real partial stacks; aggregate inventory remains the quantity authority.
static func partitions(item_id: String, total: int, maximum: int, layout: Array, instance_based: bool) -> Array[int]:
	var amounts: Array[int] = []
	var preferred := {}
	if not instance_based:
		for value: Variant in layout:
			if not value is Dictionary: continue
			var entry: Dictionary = value
			if String(entry.get("item_id","")) != item_id: continue
			var index := int(entry.get("stack_index",-1))
			var raw: Variant = entry.get("amount",0)
			if index < 0 or index >= 16 or not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) != floorf(float(raw)) or int(raw) <= 0 or int(raw) > maximum: continue
			preferred[index] = int(raw)
		for index: int in range(preferred.size()):
			if not preferred.has(index):
				amounts.clear(); break
			amounts.append(int(preferred[index]))
	var sum := 0
	for amount: int in amounts: sum += amount
	while sum > total and not amounts.is_empty():
		var removed := mini(sum-total,amounts.back())
		amounts[-1] -= removed
		sum -= removed
		if amounts.back() == 0: amounts.pop_back()
	var remaining := total-sum
	for index: int in range(amounts.size()):
		var added := mini(remaining,maximum-amounts[index])
		amounts[index] += added
		remaining -= added
	while remaining > 0:
		var added := mini(remaining,maximum)
		amounts.append(added)
		remaining -= added
	return amounts
