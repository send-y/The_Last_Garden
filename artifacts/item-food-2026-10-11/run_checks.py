"""Correctness checks for food properties; no FPS/stress measurements."""
import json
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
GODOT = "D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe"
SCRIPTS = ["item_food_properties_test", "character_needs_test", "farming_rules_test",
           "furniture_rules_test", "household_feedback_test", "inventory_layout_sync_cost_test",
           "inventory_count_cost_test", "run_tests"]
SCENES = ["item_food_actions_test", "farming_integration_test", "inventory_context_integration_test",
          "character_needs_ui_test", "furniture_ui_test", "household_feedback_ui_test"]

def saves():
    folder = Path(os.environ['APPDATA']) / 'Godot/app_userdata'
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.glob('*/first_night_save.json') if p.is_file()}

def run(test):
    name, args = test
    process = subprocess.run([GODOT, '--headless', '--path', str(ROOT/'game'), *args],
                             capture_output=True, timeout=360)
    log = (process.stdout+process.stderr).decode('utf-8', errors='replace')
    (OUT/(name+'.log')).write_text(log, encoding='utf-8')
    errors = [s for s in log.splitlines() if s.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    row = {'name': name, 'exit': process.returncode, 'errors': errors,
           'passed': process.returncode == 0 and not errors,
           'summary': [s for s in log.splitlines() if s.startswith('PASS:') or 'failures' in s]}
    print(json.dumps(row), flush=True)
    return row

before = saves()
tests = [(s, ['--script', f'res://tests/{s}.gd']) for s in SCRIPTS]
tests += [(s, [f'res://tests/{s}.tscn']) for s in SCENES]
with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, tests))
after = saves()
(OUT/'checks.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
(OUT/'save-check.json').write_text(json.dumps({'before':before,'after':after,'unchanged':before==after},indent=2),encoding='utf-8')
print('Game saves unchanged:', before == after, flush=True)
raise SystemExit(0 if all(r['passed'] for r in results) and before == after else 1)
