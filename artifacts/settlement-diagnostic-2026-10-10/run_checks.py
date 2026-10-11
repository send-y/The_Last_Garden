"""Functional verification after CPU probes; do not run alongside benchmarks."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
args = parser.parse_args()
output = Path(__file__).resolve().parent
root = output.parents[1]
tests = [
    ('trace-contract', ['--script', 'res://tests/diagnostic_trace_test.gd']),
    ('core', ['--script', 'res://tests/run_tests.gd']),
    ('stress-ui', ['res://tests/settlement_stress_ui_test.tscn']),
    ('storage-ui', ['res://tests/storage_integration_test.tscn']),
    ('furniture-ui', ['res://tests/furniture_ui_test.tscn']),
    ('editing-ui', ['res://tests/world_editing_ui_test.tscn']),
    ('housing-ui', ['res://tests/housing_ui_test.tscn']),
    ('fps-ui', ['res://tests/frame_rate_hud_test.tscn']),
]

def run(test):
    name, options = test
    process = subprocess.run([args.godot, '--headless', '--path', str(root / 'game'), *options],
                             capture_output=True, timeout=600)
    text = (process.stdout + process.stderr).decode('utf-8', errors='replace')
    (output / (name + '.log')).write_text(text, encoding='utf-8')
    errors = [line for line in text.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    result = {'name': name, 'exit': process.returncode, 'errors': errors,
              'passed': process.returncode == 0 and not errors,
              'summary': [line for line in text.splitlines() if line.startswith('PASS:') or 'failures' in line]}
    print(json.dumps(result), flush=True)
    return result

with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, tests))
(output / 'checks.json').write_text(json.dumps(results, indent=2))
raise SystemExit(0 if all(result['passed'] for result in results) else 1)
