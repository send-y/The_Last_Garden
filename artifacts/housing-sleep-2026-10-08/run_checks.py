from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess, json, sys

ROOT = Path('D:/The_Last_Garden')
OUTPUT = ROOT / 'artifacts/housing-sleep-2026-10-08'
GODOT = 'C:/Users/Bohdan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64_console.exe'
TESTS = [
    ('housing-ui', ['res://tests/housing_ui_test.tscn']),
    ('housing-rules', ['--script', 'res://tests/housing_sleep_test.gd']),
    ("npc-work", ["--script", "res://tests/npc_practical_work_test.gd"]),
    ("npc-work-ui", ["res://tests/npc_practical_work_ui_test.tscn"]),
    ('needs-rules', ['--script', 'res://tests/character_needs_test.gd']),
    ('core', ['--script', 'res://tests/run_tests.gd']),
    ('persistent-world', ['--script', 'res://tests/persistent_world_test.gd']),
    ('farming-rules', ['--script', 'res://tests/farming_rules_test.gd']),
    ('needs-ui', ['res://tests/character_needs_ui_test.tscn']),
    ('roof-energy', ['res://tests/roof_sleep_energy_integration_test.tscn']),
    ('inventory-context', ['res://tests/inventory_context_integration_test.tscn']),
    ('inventory-cursor', ['res://tests/inventory_cursor_integration_test.tscn']),
    ('pickup-refresh', ['res://tests/pickup_refresh_integration_test.tscn']),
    ('farming-ui', ['res://tests/farming_integration_test.tscn']),
    ('storage', ['res://tests/storage_integration_test.tscn']),
    ('persistent-world-ui', ['res://tests/persistent_world_integration_test.tscn']),
    ('hud-layout', ['res://tests/responsive_hud_layout_integration_test.tscn']),
]

def run(test):
    name, args = test
    p = subprocess.run([GODOT, '--headless', '--path', str(ROOT / 'game'), *args],
                       capture_output=True, text=True, encoding='utf-8', timeout=120)
    output = p.stdout + p.stderr
    (OUTPUT / f'{name}.log').write_text(output, encoding='utf-8')
    errors = [s for s in output.splitlines() if s.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    result = {'name': name, 'exit': p.returncode, 'errors': errors,
              'passes': [s for s in output.splitlines() if s.startswith('PASS:')]}
    summary = dict(result, errors=errors[:8], error_count=len(errors))
    print(json.dumps(summary, ensure_ascii=True), flush=True)
    return result

selected = TESTS if len(sys.argv) == 1 else [t for t in TESTS if t[0] in sys.argv[1:]]
with ThreadPoolExecutor(max_workers=3) as pool:
    fresh = list(pool.map(run, selected))
previous_path = OUTPUT / 'checks.json'
previous = json.loads(previous_path.read_text(encoding='utf-8')) if previous_path.exists() else []
by_name = {r['name']: r for r in previous + fresh}
results = [by_name[name] for name, _ in TESTS if name in by_name]
(OUTPUT / 'checks.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
raise SystemExit(0 if all(r['exit'] == 0 and not r['errors'] for r in results) else 1)
