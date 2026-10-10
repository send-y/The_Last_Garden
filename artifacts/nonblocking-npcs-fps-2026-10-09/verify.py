from pathlib import Path
import subprocess, json, re, sys
from concurrent.futures import ThreadPoolExecutor, as_completed

root = Path('D:/The_Last_Garden')
out = root / 'artifacts/nonblocking-npcs-fps-2026-10-09'
engine = 'D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe'
cases = {
    'full': ['--script', 'res://tests/run_tests.gd'],
    'collision': ['res://tests/npc_collision_integration_test.tscn'],
    'navigation': ['--script', 'res://tests/npc_nonblocking_navigation_test.gd'],
    'fps': ['res://tests/frame_rate_hud_test.tscn'],
    'generated': ['res://tests/generated_npcs_integration_test.tscn'],
    'doors': ['res://tests/world_editing_ui_test.tscn'],
    'drops': ['res://tests/world_drop_scene_test.tscn'],
}
selected = sys.argv[1:] or list(cases)
previous = json.loads((out / 'verification.json').read_text()) if (out / 'verification.json').exists() else []
results = [r for r in previous if r['name'] not in selected]
def run(name):
    p = subprocess.run([engine, '--headless', '--path', str(root / 'game'), *cases[name]], capture_output=True, timeout=240)
    data = (p.stdout + p.stderr).decode('utf-8', errors='replace')
    (out / (name + '-green.log')).write_text(data, encoding='utf-8')
    return {'name': name, 'exit': p.returncode, 'passed': p.returncode == 0 and not re.search(r'(^|\n)(SCRIPT ERROR:|ERROR:)', data)}
with ThreadPoolExecutor(max_workers=3) as pool:
    for future in as_completed([pool.submit(run, name) for name in selected]):
        result = future.result()
        results.append(result)
        print(json.dumps(result), flush=True)
        (out / 'verification.json').write_text(json.dumps(results, indent=2))
