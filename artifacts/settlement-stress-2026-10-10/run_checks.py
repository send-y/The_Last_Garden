"""Contract checks; never run concurrently with graphical performance probes."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
args = parser.parse_args()
output_dir = Path(__file__).resolve().parent
root = output_dir.parents[1]
tests = [
    ('rules', ['--script', 'res://tests/settlement_stress_test.gd']),
    ('stress-ui', ['res://tests/settlement_stress_ui_test.tscn']),
    ('core', ['--script', 'res://tests/run_tests.gd']),
    ('lab-dialogue', ['res://tests/mechanics_lab_dialogue_ui_test.tscn']),
    ('home-production', ['res://tests/npc_home_production_ui_test.tscn']),
]

def run(test):
    name, options = test
    start = time.perf_counter()
    command = [args.godot, '--headless', '--path', str(root / 'game'), *options]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        stdout, _ = process.communicate(timeout=600)
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
        stdout, _ = process.communicate()
    text = stdout.decode('utf-8', errors='replace')
    (output_dir / (name + '.log')).write_text(text, encoding='utf-8')
    errors = [line for line in text.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    result = {'name': name, 'exit': process.returncode, 'seconds': round(time.perf_counter() - start, 2),
              'errors': errors, 'passed': process.returncode == 0 and not errors,
              'summary': [line for line in text.splitlines() if 'failures' in line or line.startswith(('PASS:', 'RESULT:', 'TESTS:'))]}
    print(json.dumps(result), flush=True)
    return result

# These are functional headless checks, not performance measurements.
with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, tests))
(output_dir / 'checks.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
raise SystemExit(0 if all(result['passed'] for result in results) else 1)
