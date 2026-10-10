from pathlib import Path
import subprocess, json

root = Path('D:/The_Last_Garden')
output = root / 'artifacts/housing-sleep-2026-10-08'
godot = 'D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64.exe'
p = subprocess.run([godot, '--path', str(root/'game'), '--rendering-method', 'gl_compatibility',
    'res://tests/housing_ui_test.tscn', '--', '--screenshots='+str(output)],
    capture_output=True, text=True, encoding='utf-8', timeout=90)
log = p.stdout + p.stderr
(output/'housing-ui-graphic.log').write_text(log, encoding='utf-8')
errors = [line for line in log.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
print(json.dumps({'exit':p.returncode, 'errors':errors[:8], 'error_count':len(errors),
    'passes':[line for line in log.splitlines() if line.startswith('PASS:')]}))
raise SystemExit(0 if p.returncode == 0 and not errors and 'PASS:' in log else 1)
