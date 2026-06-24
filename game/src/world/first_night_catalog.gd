class_name FirstNightCatalog
extends RefCounted

const CELL_SIZE: int = 32
const MAP_SIZE: Vector2i = Vector2i(48, 48)
const INTERACTION_RANGE: float = 68.0


static func cell_center(x: int, y: int) -> Vector2:
	return Vector2(float(x * CELL_SIZE + CELL_SIZE / 2), float(y * CELL_SIZE + CELL_SIZE / 2))


static func interactables() -> Array[Dictionary]:
	return [
		{
			"id": "common_house",
			"kind": "house",
			"label": "Общий дом",
			"position": cell_center(24, 27),
			"color": Color("8f7357"),
			"size": Vector2(44.0, 24.0),
		},
		{
			"id": "old_tools",
			"kind": "tools",
			"label": "Старый ящик",
			"position": cell_center(22, 22),
			"color": Color("b68b4c"),
			"size": Vector2(24.0, 18.0),
		},
		{
			"id": "repair_room",
			"kind": "repair",
			"label": "Заваленная комната",
			"position": cell_center(25, 20),
			"color": Color("9a6a58"),
			"size": Vector2(30.0, 24.0),
		},
		{
			"id": "campfire_site",
			"kind": "campfire",
			"label": "Место для костра",
			"position": cell_center(19, 28),
			"color": Color("cf7041"),
			"size": Vector2(24.0, 20.0),
		},
		{
			"id": "bed_site",
			"kind": "bed",
			"label": "Место для постели",
			"position": cell_center(26, 23),
			"color": Color("8b789e"),
			"size": Vector2(30.0, 18.0),
		},
		{
			"id": "wood_north",
			"kind": "wood",
			"label": "Упавшие ветви",
			"position": cell_center(15, 17),
			"color": Color("8a5a3b"),
			"size": Vector2(26.0, 18.0),
		},
		{
			"id": "wood_west",
			"kind": "wood",
			"label": "Сухое дерево",
			"position": cell_center(13, 24),
			"color": Color("8a5a3b"),
			"size": Vector2(26.0, 18.0),
		},
		{
			"id": "wood_east",
			"kind": "wood",
			"label": "Обломки досок",
			"position": cell_center(33, 24),
			"color": Color("8a5a3b"),
			"size": Vector2(26.0, 18.0),
		},
		{
			"id": "stone_south",
			"kind": "stone",
			"label": "Камни у дороги",
			"position": cell_center(17, 33),
			"color": Color("777c82"),
			"size": Vector2(24.0, 18.0),
		},
		{
			"id": "stone_east",
			"kind": "stone",
			"label": "Каменная осыпь",
			"position": cell_center(34, 18),
			"color": Color("777c82"),
			"size": Vector2(24.0, 18.0),
		},
		{
			"id": "shore_water",
			"kind": "water",
			"label": "Берег ручья",
			"position": cell_center(7, 27),
			"color": Color("4f8e9e"),
			"size": Vector2(28.0, 22.0),
		},
		{
			"id": "berry_bush",
			"kind": "food",
			"label": "Куст с ягодами",
			"position": cell_center(12, 31),
			"color": Color("5d7d45"),
			"size": Vector2(24.0, 22.0),
		},
	]
