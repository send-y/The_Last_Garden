class_name FirstNightCatalog
extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")
const Npcs := preload("res://src/characters/npc_catalog.gd")

const CELL_SIZE: int = 32
const MAP_SIZE: Vector2i = Vector2i(48, 48)
const INTERACTION_RANGE: float = 68.0


static func cell_center(x: int, y: int) -> Vector2:
	return FirstNightContent.cell_center(x, y)


static func interactables() -> Array[Dictionary]:
	var content: FirstNightContent = Content.new()
	var npc_catalog := Npcs.new()
	var result: Array[Dictionary] = content.interactables()
	result.append_array(npc_catalog.get_interactables())
	return result
