extends RefCounted

# Derived runtime index. Only this module mutates live structure records.
# Queries copy local records; primitive membership checks allocate no records.
var revision := 0
var geometry_revision := 0
var lighting_revision := 0
var door_revision := 0
var _catalog: BuildingCatalog
var _structures: Array
var _records: Dictionary = {}
var _by_cell: Dictionary = {}
var _by_type: Dictionary = {}
var _order: Dictionary = {}
var _next_order := 0
var _expected: Dictionary = {}
var _floor_cells: Dictionary = {}
var _floor_records: Dictionary = {}

func _init(structures: Array, catalog: BuildingCatalog) -> void:
	_structures = structures
	_catalog = catalog
	for value: Dictionary in structures:
		_register(value)

func _key(record: Dictionary) -> String:
	var cell: Array = record.get("cell",[])
	if cell.size() != 2: return ""
	return "%s@%d,%d" % [_catalog.get_layer_id(String(record.get("building_id",""))),int(cell[0]),int(cell[1])]

func _register(record: Dictionary) -> void:
	var key := _key(record)
	_records[key] = record
	_expected[key] = record.duplicate(true)
	_order[key] = _next_order
	_next_order += 1
	var id := String(record.building_id)
	var floor_record := _catalog.is_floor(id)
	if floor_record: _floor_records[key] = true
	if not _by_type.has(id): _by_type[id] = []
	_by_type[id].append(key)
	for cell: Vector2i in _catalog.get_footprint_cells(id,Vector2i(int(record.cell[0]),int(record.cell[1]))):
		if not _by_cell.has(cell): _by_cell[cell] = []
		_by_cell[cell].append(key)
		if floor_record: _floor_cells[cell] = int(_floor_cells.get(cell,0))+1

func _bump(geometry: bool, lighting: bool) -> void:
	revision += 1
	if geometry: geometry_revision += 1
	if geometry or lighting: lighting_revision += 1

func add(record: Dictionary) -> bool:
	var key := _key(record)
	if key.is_empty() or _records.has(key) or _catalog.get_definition(String(record.get("building_id",""))).is_empty(): return false
	var stored := record.duplicate(true)
	_structures.append(stored)
	_register(stored)
	_bump(true,false)
	return true

func remove(record: Dictionary) -> bool:
	var key := _key(record)
	if not _records.has(key): return false
	var stored: Dictionary = _records[key]
	if String(record.get("building_id","")) != String(stored.building_id): return false
	var id := String(stored.building_id)
	for cell: Vector2i in _catalog.get_footprint_cells(id,Vector2i(int(stored.cell[0]),int(stored.cell[1]))):
		_by_cell[cell].erase(key)
		if _by_cell[cell].is_empty(): _by_cell.erase(cell)
		if _floor_records.has(key):
			_floor_cells[cell] -= 1
			if _floor_cells[cell] <= 0: _floor_cells.erase(cell)
	_by_type[id].erase(key)
	if _by_type[id].is_empty(): _by_type.erase(id)
	_structures.erase(stored)
	_records.erase(key)
	_order.erase(key)
	_expected.erase(key)
	_floor_records.erase(key)
	_bump(true,false)
	return true

func set_state(record: Dictionary, field: String, value: bool) -> bool:
	var key := _key(record)
	if not _records.has(key): return false
	var stored: Dictionary = _records[key]
	var id := String(stored.building_id)
	if String(record.get("building_id","")) != id: return false
	if not ((field == "lit" and id == "core:torch") or (field == "open" and id == "core:wood_door")): return false
	if bool(stored.get(field,true)) == value: return false
	stored[field] = value
	_expected[key] = stored.duplicate(true)
	if field == "open": door_revision += 1
	_bump(false,field == "lit")
	return true

func replace(records: Array) -> void:
	# Explicit bulk replacement for normalized/bootstrap state, never a query.
	var copy := records.duplicate(true)
	_structures.clear()
	_records.clear()
	_by_cell.clear()
	_by_type.clear()
	_order.clear()
	_expected.clear()
	_floor_cells.clear()
	_floor_records.clear()
	_next_order = 0
	for record: Dictionary in copy:
		_structures.append(record)
		_register(record)
	_bump(true,false)

func has_floor(cell: Vector2i) -> bool:
	return _floor_cells.has(cell)

func at(cell: Vector2i) -> Array[Dictionary]:
	return _copies(_by_cell.get(cell,[]))

func of_type(id: String) -> Array[Dictionary]:
	return _copies(_by_type.get(id,[]))

func _copies(keys: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in keys:
		result.append(_records[key].duplicate(true))
	return result

func in_cells(cells: Array[Vector2i], include_floors: bool = true) -> Array[Dictionary]:
	var found: Dictionary = {}
	for cell: Vector2i in cells:
		for key: String in _by_cell.get(cell,[]):
			if include_floors or not _floor_records.has(key): found[key] = true
	var keys: Array = found.keys()
	keys.sort_custom(func(a: String,b: String) -> bool: return int(_order[a]) < int(_order[b]))
	return _copies(keys)

func validate(actual: Array) -> Array[String]:
	# Slow, independent check; explicitly invoked only by tests/opt-in Lab.
	var errors: Array[String] = []
	var expected_cells: Dictionary = {}
	var expected_types: Dictionary = {}
	var expected_floors: Dictionary = {}
	var expected_floor_records: Dictionary = {}
	var seen: Dictionary = {}
	var previous_order := -1
	for record: Dictionary in actual:
		var key := _key(record)
		if seen.has(key) or not _expected.has(key) or _expected.get(key,{}) != record:
			errors.append("Structure changed outside mutation API: "+key)
		seen[key] = true
		var order := int(_order.get(key,-1))
		if order <= previous_order: errors.append("Structure order mismatch: "+key)
		previous_order = order
		var id := String(record.building_id)
		if _catalog.is_floor(id): expected_floor_records[key] = true
		if not expected_types.has(id): expected_types[id] = []
		expected_types[id].append(key)
		for cell: Vector2i in _catalog.get_footprint_cells(id,Vector2i(int(record.cell[0]),int(record.cell[1]))):
			if not expected_cells.has(cell): expected_cells[cell] = []
			expected_cells[cell].append(key)
			if _catalog.is_floor(id): expected_floors[cell] = int(expected_floors.get(cell,0))+1
	if seen.size() != _records.size(): errors.append("Structure count mismatch")
	if expected_cells != _by_cell: errors.append("Structure cell index mismatch")
	if expected_types != _by_type: errors.append("Structure type index mismatch")
	if expected_floors != _floor_cells: errors.append("Structure floor index mismatch")
	if expected_floor_records != _floor_records: errors.append("Structure floor record index mismatch")
	return errors
