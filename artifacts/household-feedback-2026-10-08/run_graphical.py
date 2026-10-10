from pathlib import Path
import subprocess, json

root = Path('D:/The_Last_Garden')
out = root / 'artifacts/household-feedback-2026-10-08'
godot = 'D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64.exe'
p = subprocess.run([godot, '--path', str(root / 'game'), '--rendering-method',
                    'gl_compatibility', 'res://tests/household_feedback_ui_test.tscn', '--',
                    '--screenshots=' + str(out)], capture_output=True,
                   encoding='utf-8', timeout=90)
output = p.stdout + p.stderr
(out / 'graphical.log').write_text(output, encoding='utf-8')
errors = [line for line in output.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
result = {'exit':p.returncode, 'errors':errors,
          'passes':[line for line in output.splitlines() if line.startswith('PASS:')]}
(out / 'graphical.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result))
raise SystemExit(0 if p.returncode == 0 and not errors else 1)
