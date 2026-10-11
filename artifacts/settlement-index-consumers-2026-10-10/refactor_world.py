"""One-time mechanical extraction preserving the existing drawing order."""
from pathlib import Path
import re

path = Path(__file__).resolve().parents[2] / 'game/src/world/first_night_world.gd'
source = path.read_text(encoding='utf-8')
prefix, farm = source.split('func _draw_farm_beds() -> void:', 1)
farm, draw = farm.split('func _draw() -> void:', 1)
background, rooms = draw.split('\tfor room: Dictionary in Session.get_room_assignments():', 1)
rooms, house = rooms.split('\tdraw_texture_rect(\n\t\tDIRT_TILE,', 1)
house, zones = house.split('\tfor zone: Dictionary in Session.get_storage_zones():', 1)
zones, items = zones.split('\tvar storage_span := Diagnostic.begin("scene.world_storage_draw") if Diagnostic.enabled else 0', 1)
items, rest = items.split('\tDiagnostic.end(storage_span)', 1)
grid, selection = rest.split('\tif _selected_cell.x >= 0', 1)
grid = grid.replace('\t_draw_farm_beds()\n', '')
selection = '\tif _selected_cell.x >= 0' + selection
selection = selection.replace('\tDiagnostic.end(span)\n', '')
background += '\tDiagnostic.end(span)\n'

def convert(body):
    body = re.sub(r'(?<![\w.])draw_(rect|line|circle|texture_rect|string|colored_polygon)\(', r'canvas.draw_\1(', body)
    return body.replace('IconPresentation.draw_icon(self,', 'IconPresentation.draw_icon(canvas,')

methods = []
for name, body in [
    ('rooms', '\tfor room: Dictionary in Session.get_room_assignments():' + rooms),
    ('house', '\tdraw_texture_rect(\n\t\tDIRT_TILE,' + house),
    ('storage_zones', '\tfor zone: Dictionary in Session.get_storage_zones():' + zones),
    ('storage_items', items.replace('var placements := Session.get_storage_layout(cell)', 'var placements: Array = _storage_layouts.get(cell,[])')),
    ('farm_beds', farm), ('grid', grid), ('selection', selection),
]:
    methods.append(f'func _draw_{name}(canvas: Node2D) -> void:\n\tvar tile := float(Catalog.CELL_SIZE)\n\tvar map_pixels := Vector2(Catalog.MAP_SIZE * Catalog.CELL_SIZE)\n' + convert(body).lstrip('\n'))

prefix = prefix.replace('const Diagnostic :=', 'const PresentationLayer := preload("res://src/world/world_presentation_layer.gd")\nconst StoragePresentation := preload("res://src/simulation/systems/storage_system.gd")\n\nconst Diagnostic :=', 1)
prefix = prefix.replace('var _interactables:', 'var _presentation_layers: Dictionary = {}\nvar _storage_layouts: Dictionary = {}\n\nvar _interactables:', 1)
prefix = prefix.replace('\t_build_static_collision()\n', '\t_build_static_collision()\n\t_build_presentation_layers()\n', 1)
prefix = prefix.replace('\tSession.state_reloaded.connect(_on_state_reloaded)\n\tqueue_redraw()', '\tSession.state_reloaded.connect(_on_state_reloaded)\n\tSession.time_changed.connect(_refresh_farm_presentation)\n\t_refresh_presentation(true)\n\tqueue_redraw()', 1)
# Keep the one initial terrain redraw; other state/selection updates target layers.
marker = prefix.index('func select_at_world_position')
prefix = prefix[:marker] + prefix[marker:].replace('queue_redraw()', '_refresh_presentation()')
prefix = prefix.replace('\t_refresh_interactables()\n\t_sync_dropped_items()\n\t_refresh_presentation()\n', '\t_refresh_interactables()\n\t_sync_dropped_items()\n', 1)
prefix = prefix.replace('\t_refresh_interactables(true)\n\t_sync_dropped_items()\n', '\t_refresh_interactables(true)\n\t_sync_dropped_items()\n\t_refresh_presentation(true)\n\tqueue_redraw()\n', 1)
path.write_text(prefix + 'func _draw() -> void:' + background + '\n\n' + '\n\n'.join(methods), encoding='utf-8')
