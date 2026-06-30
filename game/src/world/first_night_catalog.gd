class_name FirstNightCatalog
extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")

const CELL_SIZE: int = 32
const MAP_SIZE: Vector2i = Vector2i(48, 48)
const INTERACTION_RANGE: float = 68.0


static func cell_center(x: int, y: int) -> Vector2:
	return FirstNightContent.cell_center(x, y)


static func interactables() -> Array[Dictionary]:
	var content: FirstNightContent = Content.new()
	return content.interactables()
