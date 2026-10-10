"""Run existing standalone and scene checks for the NPC milestone checkpoint."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
from pathlib import Path
import re
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('--only', nargs='*', help='Rerun named checks only')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
game = root / 'game'
output = Path(__file__).resolve().parent
cases = [('full', ['--script', 'res://tests/run_tests.gd'])]
for script in sorted((game / 'tests').glob('*test.gd')):
    if re.search(r'^extends SceneTree\s*$', script.read_text(encoding='utf-8-sig'), re.M):
        cases.append((script.stem, ['--script', 'res://tests/' + script.name]))
for scene in sorted((game / 'tests').glob('*test.tscn')):
    cases.append((scene.stem, ['res://tests/' + scene.name]))
cases.append(('main-startup', ['--quit-after', '5']))
graphical = {'held_item_render_integration_test', 'hoe_alignment_integration_test',
             'inventory_rotation_integration_test', 'wall_cell_visual_test'}
if args.only:
    cases = [case for case in cases if case[0] in args.only]
    if len(cases) != len(set(args.only)):
        parser.error('Unknown or duplicate check name')

def run(case):
    name, flags = case
    start = time.monotonic()
    try:
        result = subprocess.run(
            [args.godot, *([] if name in graphical else ['--headless']), '--path', str(game), *flags],
            capture_output=True, timeout=240,
        )
        data = (result.stdout + result.stderr).decode('utf-8', errors='replace')
        code = result.returncode
    except subprocess.TimeoutExpired as exc:
        data = ((exc.stdout or b'') + (exc.stderr or b'')).decode('utf-8', errors='replace')
        data += '\nCHECKPOINT TIMEOUT\n'
        code = -1
    (output / (name + '.log')).write_text(data, encoding='utf-8')
    errors = re.findall(r'^(?:SCRIPT ERROR:|ERROR:).*$', data, re.M)
    return {'name': name, 'exit': code, 'passed': code == 0 and not errors,
            'seconds': round(time.monotonic() - start, 2), 'errors': errors}

results = []
if args.only and (output / 'verification.json').exists():
    results = [item for item in json.loads((output / 'verification.json').read_text())
               if item['name'] not in args.only]
print(json.dumps({'checks': len(cases)}), flush=True)
with ThreadPoolExecutor(max_workers=3) as pool:
    for future in as_completed([pool.submit(run, case) for case in cases]):
        result = future.result()
        results.append(result)
        print(json.dumps(result, ensure_ascii=True), flush=True)
        (output / 'verification.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
sys.exit(0 if all(result['passed'] for result in results) else 1)
