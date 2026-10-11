extends RefCounted

static func warning_text(row: Dictionary) -> String:
	return "Item load: id=%s count=%d reason=%s" % [String(row.id), int(row.count), String(row.reason)]
