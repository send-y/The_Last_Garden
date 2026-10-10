"""Verify indexed game files without the developer's Godot import cache."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
args = parser.parse_args()
out = Path(__file__).resolve().parent
root = out.parents[1]
checkout = out / 'clean-checkout' / uuid.uuid4().hex
checkout.mkdir(parents=True)
paths = subprocess.run(['git', 'ls-files', '-z', 'game'], cwd=root,
                       capture_output=True, check=True).stdout
subprocess.run(['git', 'checkout-index', '--prefix=' + checkout.as_posix() + '/',
                '--stdin', '-z'], input=paths, cwd=root, check=True)
results = []
for name, flags in [
    ('bootstrap-import', ['--editor', '--import']),
    ('import', ['--editor', '--import']),
    ('full', ['--script', 'res://tests/run_tests.gd']),
    ('npc-home-production-ui', ['res://tests/npc_home_production_ui_test.tscn']),
    ('main-startup', ['--quit-after', '5']),
]:
    process = subprocess.run([args.godot, '--headless', '--path', str(checkout / 'game'), *flags],
                             capture_output=True, timeout=240)
    data = (process.stdout + process.stderr).decode('utf-8', errors='replace')
    (out / ('clean-' + name + '.log')).write_text(data, encoding='utf-8')
    errors = re.findall(r'^(?:SCRIPT ERROR:|ERROR:).*$', data, re.M)
    # Godot reads configured translations before the first CSV import. Keep the
    # bootstrap diagnostics visible; only these exact missing generated files
    # may be accepted, followed by a second import with no errors permitted.
    expected = []
    if name == 'bootstrap-import':
        allowed = {"ERROR: Cannot open file 'res://localization/core.ru.translation'.",
                   'ERROR: Failed loading resource: res://localization/core.ru.translation.'}
        expected = [line for line in errors if line.strip() in allowed]
        errors = [line for line in errors if line.strip() not in allowed]
    result = {'name': name, 'exit': process.returncode,
              'passed': process.returncode == 0 and not errors, 'errors': errors,
              'expected_bootstrap_diagnostics': expected}
    results.append(result)
    print(json.dumps(result), flush=True)
    (out / 'clean-verification.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    if not result['passed']:
        break
sys.exit(0 if len(results) == 5 and all(r['passed'] for r in results) else 1)
