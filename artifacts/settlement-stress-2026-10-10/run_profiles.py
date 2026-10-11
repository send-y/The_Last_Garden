"""Run graphical settlement probes sequentially; never benchmark in parallel."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('cases', nargs='*')
args = parser.parse_args()
out = Path(__file__).resolve().parent
root = out.parents[1]
cases = {
    'baseline-3': (3, 'settlement_stress', 'work', 'player', 30),
    'full-30': (30, 'settlement_stress', 'work', 'player', 60),
    'night-30': (30, 'settlement_stress', 'night', 'player', 45),
    'production-30': (30, 'stress_production', 'work', 'player', 10),
    'gather-30': (30, 'stress_gather', 'work', 'player', 10),
    'overview-30': (30, 'settlement_stress', 'work', 'overview', 30),
    'quiet-30': (30, 'settlement_stress', 'paused', 'player', 20),
    'original-3': (3, 'generated_residents', 'work', 'player', 20),
    'sleep-30': (30, 'settlement_stress', 'sleep', 'player', 10),
    'quiet-no-light-refresh-30': (30, 'settlement_stress', 'paused', 'player', 20),
}
selected = args.cases or list(cases)
results = json.loads((out / 'runs.json').read_text()) if (out / 'runs.json').exists() else []
results = [r for r in results if r['name'] not in selected]
for name in selected:
    count, scenario, phase, view, seconds = cases[name]
    print(json.dumps({'starting': name, 'seconds': seconds}), flush=True)
    command = [args.godot, '--path', str(root / 'game'),
               'res://src/dev/settlement_stress_profile.tscn', '--',
               f'--stress-residents={count}', f'--lab-scenario={scenario}',
               f'--profile-phase={phase}', f'--profile-view={view}',
               f'--profile-seconds={seconds}', f'--profile-tag={name}']
    if name == 'quiet-no-light-refresh-30':
        command.append('--profile-disable-light-refresh')
    start = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        stdout, stderr = process.communicate(timeout=360)
        code = process.returncode
    except subprocess.TimeoutExpired:
        # Kill only the process tree launched by this probe, including Godot's
        # Windows console launcher child. User editor processes are untouched.
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
        stdout, stderr = process.communicate()
        code = -1
    text = (stdout + stderr).decode('utf-8', errors='replace')
    (out / (name + '.log')).write_text(text, encoding='utf-8')
    result = {'name': name, 'exit': code, 'seconds_total': round(time.monotonic() - start, 2),
              'errors': re.findall(r'^(?:SCRIPT ERROR:|ERROR:).*$', text, re.M)}
    result['passed'] = code == 0 and not result['errors'] and (out / (name + '.json')).exists()
    if result['passed']:
        profile = json.loads((out / (name + '.json')).read_text())
        result['fps'] = profile['average_fps']
        result['maximum_frame_ms'] = profile['frame_ms']['max']
        result['maximum_minute_ms'] = profile['minute_cpu_ms'].get('max')
    results.append(result)
    (out / 'runs.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(json.dumps(result), flush=True)
    if not result['passed']:
        break
sys.exit(0 if all(r['passed'] for r in results) and len(results) >= len(selected) else 1)
