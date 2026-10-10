"""One-time, reproducible extraction from the preserved pre-refactor source.

Only relocates function bodies and adds explicit simulation context. Not a game
dependency. Do not rerun after editing the extracted systems.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).with_name('first_night_simulation.before.gd').read_text(encoding='utf-8-sig')
DEST = ROOT / 'game/src/simulation'
SYSTEMS = DEST / 'systems'
SYSTEMS.mkdir(exist_ok=True)
matches = list(re.finditer(r'^(static )?func (\w+)\(', SOURCE, re.M))
functions = {}
for index, match in enumerate(matches):
    end = matches[index + 1].start() if index + 1 < len(matches) else len(SOURCE)
    text = SOURCE[match.start():end].rstrip()
    header_end = re.search(r'\)\s*->\s*([^:]+):', text).end()
    header, body = text[:header_end], text[header_end:]
    functions[match[2]] = dict(name=match[2], static=bool(match[1]), header=header,
                              body=body, line=SOURCE[:match.start()].count('\n') + 1,
                              result=re.search(r'->\s*([^:]+):', header)[1].strip())

# Explicit ownership, reviewed against the original method index.
ranges = [
    (329, 382, 'world_calendar'), (383, 408, 'opening_scenario'),
    (409, 698, 'resource_system'), (699, 821, 'construction_commands'),
    (822, 964, 'crafting_system'), (965, 1100, 'settlement_npcs'),
    (1101, 1240, 'construction_commands'), (1241, 1279, 'construction_projects'),
    (1280, 1337, 'settlement_npcs'), (1338, 1696, 'construction_projects'),
    (1697, 1706, 'construction_projects'), (1707, 1717, 'settlement_npcs'),
    (1718, 1750, 'opening_scenario'), (1755, 1854, 'world_drops'),
    (1855, 1862, 'storage_system'), (1863, 1952, 'room_system'),
    (1953, 2076, 'storage_system'), (2077, 2341, 'storage_transfers'),
    (2342, 2371, 'storage_system'), (2372, 2495, 'storage_transfers'),
    (2496, 2528, 'resource_system'), (2529, 2592, 'world_drops'),
    (2593, 2632, 'resource_system'), (2633, 2688, 'inventory_system'),
    (2689, 2839, 'equipment_system'), (2840, 2852, 'item_instances'),
    (2853, 2860, 'construction_projects'), (2861, 2868, 'crafting_system'),
    (2869, 2869, 'construction_projects'), (2877, 2880, 'settlement_npcs'),
    (2881, 2884, 'inventory_system'), (2885, 2899, 'world_calendar'),
    (2912, 2936, 'world_calendar'), (2944, 3010, 'map_markers'),
    (3011, 3054, 'inventory_system'), (3059, 3100, 'opening_scenario'),
    (3100, 3111, 'opening_scenario'), (3112, 3180, 'settlement_npcs'),
    (3181, 3534, 'opening_scenario'), (3535, 3562, 'opening_scenario'),
    (3563, 3573, 'settlement_npcs'), (3574, 3620, 'world_calendar'),
    (3621, 3671, 'inventory_system'), (3672, 3757, 'item_instances'),
    (3758, 3766, 'world_calendar'), (3792, 3971, 'save_migrations'),
    (3972, 4124, 'item_instances'), (4131, 4171, 'map_markers'),
    (4172, 4225, 'storage_state'), (4226, 4366, 'room_system'),
    (4367, 4536, 'storage_state'), (4537, 4662, 'storage_system'),
    (4663, 4677, 'map_markers'), (4687, 4884, 'resource_system'),
    (4885, 4971, 'world_drops'), (4992, 5122, 'construction_state'),
    (5123, 5204, 'crafting_system'), (5205, 5221, 'construction_projects'),
    (5222, 5230, 'crafting_system'), (5231, 5264, 'construction_state'),
]
kept = {'_init', 'export_state', 'get_flags', 'execute_farming_command', 'get_farm_beds',
        'get_farm_bed', 'get_player_position', 'set_player_position', '_emit_result',
        '_inventory_mutable', '_flags_mutable', '_npcs_mutable'}
for f in functions.values():
    if f['static'] or f['name'] in kept:
        f['module'] = None
    else:
        f['module'] = next((m for a, b, m in ranges if a <= f['line'] <= b), None)
        assert f['module'], f['name']

# Lexer protects strings/comments and member accesses from identifier rewriting.
TOKENS = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|#[^\n]*|\b[A-Za-z_]\w*\b')
FIELDS = {'state': 'Dictionary', 'content': 'FirstNightContent', 'npc_catalog': 'NpcCatalog',
          'npc_autonomy': 'NpcAutonomy', 'building_catalog': 'BuildingCatalog',
          'crafting_catalog': 'CraftingCatalog', 'farming': 'FarmingSystem'}
PROPERTIES = {'_minute_accumulator', '_berry_bush_nodes', '_food_object_ids', 'event_emitted'}

def rewrite(body, module):
    used = set()
    def token(match):
        word = match[0]
        if not re.fullmatch(r'[A-Za-z_]\w*', word):
            return word
        prefix = body[:match.start()].rsplit('\n', 1)[-1].rstrip()
        if prefix.endswith('.'):
            return word
        if word == 'self':
            return 'sim'
        if word in FIELDS:
            used.add(word)
            return word
        if word in PROPERTIES:
            return 'sim.' + word
        if word in functions and not functions[word]['static'] and re.match(r'\s*\(', body[match.end():]):
            if functions[word]['module'] == module:
                return word  # context inserted in a second, protected token pass
            return 'sim.' + word
        return word
    result = TOKENS.sub(token, body)
    # Insert context in local calls, including multiline and empty arguments.
    local = {n for n, f in functions.items() if f['module'] == module}
    edits = []
    for match in TOKENS.finditer(result):
        if match[0] not in local or result[:match.start()].rsplit('\n', 1)[-1].rstrip().endswith('.'):
            continue
        suffix = re.match(r'\s*\(', result[match.end():])
        if suffix:
            point = match.end() + suffix.end()
            edits.append((point, 'sim' if result[point:].lstrip().startswith(')') else 'sim, '))
    for point, replacement in reversed(edits):
        result = result[:point] + replacement + result[point:]
    # Calls through an untyped context need explicit return types for := locals.
    pattern = r'(var\s+\w+)\s*:=\s*sim\.(\w+)\('
    def declaration(match):
        f = functions.get(match[2])
        assert f, match[0]
        return f'{match[1]}: {f["result"]} = sim.{match[2]}('
    result = re.sub(pattern, declaration, result)
    aliases = ''.join(f'\tvar {field}: {typ} = sim.{field}\n' for field, typ in FIELDS.items() if field in used)
    return '\n' + aliases + result.lstrip('\n')

constants_start = SOURCE.index('const Content')
variables_start = SOURCE.index('var state:')
rules = 'extends RefCounted\n\n# Shared constants, factories and pure save-value helpers.\n\n' + SOURCE[constants_start:variables_start]
rules += '\n\n'.join(f['header'] + f['body'] for f in functions.values() if f['static']) + '\n'
(DEST / 'world_rules.gd').write_text(rules, encoding='utf-8')

modules = sorted({f['module'] for f in functions.values() if f['module']})
for module in modules:
    output = 'extends "res://src/simulation/world_rules.gd"\n\n# Operates on the authoritative WorldSimulation state; owns no copy.\n\n'
    for f in functions.values():
        if f['module'] != module:
            continue
        header = f['header'].replace('func ' + f['name'] + '(', 'static func ' + f['name'] + '(sim' + (', ' if not re.search(r'\(\s*\)', f['header']) else ''), 1)
        output += header + rewrite(f['body'], module) + '\n\n\n'
    (SYSTEMS / (module + '.gd')).write_text(output.rstrip() + '\n', encoding='utf-8')

def symbol(module):
    return ''.join(part.title() for part in module.split('_')) + 'System'

facade = 'class_name WorldSimulation\nextends "res://src/simulation/world_rules.gd"\n\nsignal event_emitted(event: Dictionary)\n\n'
facade += '# Stable command/query facade. State and dependencies live only here.\n'
facade += ''.join(f'const {symbol(m)} := preload("res://src/simulation/systems/{m}.gd")\n' for m in modules)
facade += '\n' + SOURCE[variables_start:matches[0].start()]
for f in functions.values():
    if f['static']:
        continue
    if not f['module']:
        facade += f['header'] + f['body'] + '\n\n\n'
        continue
    params = re.search(r'\((.*?)\)\s*->', f['header'], re.S)[1]
    args = re.findall(r'(?:^|,)\s*(\w+)\s*:', params)
    assert len(args) == params.count(':') or not params.strip(), (f['name'], params, args)
    dispatch = f'{symbol(f["module"])}.{f["name"]}(self' + ''.join(', ' + a for a in args) + ')'
    facade += f['header'] + '\n\t' + ('' if f['result'] == 'void' else 'return ') + dispatch + '\n\n\n'
(DEST / 'world_simulation.gd').write_text(facade.rstrip() + '\n', encoding='utf-8')
(DEST / 'first_night_simulation.gd').write_text('class_name FirstNightSimulation\nextends "res://src/simulation/world_simulation.gd"\n\n# Compatibility name for existing saves, integrations and opening scenarios.\n', encoding='utf-8')
print(f'Extracted {len(functions)} methods into {len(modules)} systems; facade {len(facade.splitlines())} lines')
for module in modules:
    path = SYSTEMS / (module + '.gd')
    print(f'{module}: {len(path.read_text(encoding="utf-8").splitlines())}')
