from pathlib import Path
import subprocess, json, re, sys
from concurrent.futures import ThreadPoolExecutor, as_completed
root = Path('D:/The_Last_Garden')
out = root / 'artifacts/npc-home-production-2026-10-09'
engine = 'D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe'
cases = {
    'production': ['--script', 'res://tests/npc_home_production_test.gd'],
    'production-ui': ['res://tests/npc_home_production_ui_test.tscn'],
    'production-graphical': ['res://tests/npc_home_production_ui_test.tscn', '--', '--capture'],
    'home-projects': ['--script', 'res://tests/npc_home_projects_test.gd'],
    'resident-projects': ['--script', 'res://tests/resident_home_projects_test.gd'],
    'home-ui': ['res://tests/npc_home_projects_ui_test.tscn'],
    'crafting-ui': ['res://tests/crafting_integration_test.tscn'],
    'full': ['--script', 'res://tests/run_tests.gd'],
    'minute-refresh': ['res://tests/minute_structure_refresh_test.tscn'],
    'editing': ['--script', 'res://tests/world_editing_test.gd'],
}
selected = sys.argv[1:] or list(cases)
results = json.loads((out / 'verification.json').read_text()) if (out / 'verification.json').exists() else []
results = [r for r in results if r['name'] not in selected]
def run(name):
    flags = [] if name == 'production-graphical' else ['--headless']
    p = subprocess.run([engine, *flags, '--path', str(root / 'game'), *cases[name]], capture_output=True, timeout=240)
    data = (p.stdout + p.stderr).decode('utf-8', errors='replace')
    (out / (name + '.log')).write_text(data, encoding='utf-8')
    return {'name': name, 'exit': p.returncode, 'passed': p.returncode == 0 and not re.search(r'(^|\n)(SCRIPT ERROR:|ERROR:)', data)}
with ThreadPoolExecutor(max_workers=3) as pool:
    for future in as_completed([pool.submit(run, name) for name in selected]):
        result = future.result()
        results.append(result)
        print(json.dumps(result), flush=True)
        (out / 'verification.json').write_text(json.dumps(results, indent=2))
