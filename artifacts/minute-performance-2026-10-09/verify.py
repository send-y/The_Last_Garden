from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
GODOT = 'D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe'
TESTS = [
    'minute_geometry_cache_test.gd', 'minute_structure_refresh_test.tscn',
    'resident_home_policy_test.gd', 'resident_home_projects_test.gd',
    'npc_home_projects_test.gd', 'resident_homes_ui_test.tscn',
    'housing_sleep_test.gd', 'housing_ui_test.tscn',
    'furniture_rules_test.gd', 'furniture_ui_test.tscn',
    'household_feedback_test.gd', 'household_feedback_ui_test.tscn',
    'npc_practical_work_test.gd', 'generated_npcs_integration_test.tscn',
    'room_designation_integration_test.tscn', 'pickup_refresh_integration_test.tscn',
    'mechanics_lab_dialogue_ui_test.tscn', 'persistent_world_test.gd', 'run_tests.gd',
]

def run(test, graphical=False):
    args = [GODOT] + ([] if graphical else ['--headless']) + ['--path',str(ROOT/'game')]
    args += ['--script','res://tests/'+test] if test.endswith('.gd') else ['res://tests/'+test]
    name = Path(test).stem + ('-graphical' if graphical else '')
    try:
        proc = subprocess.run(args,cwd=ROOT,capture_output=True,timeout=180)
        output = (proc.stdout+proc.stderr).decode('utf-8',errors='replace')
        code = proc.returncode
    except subprocess.TimeoutExpired as error:
        output = ((error.stdout or b'')+(error.stderr or b'')).decode('utf-8',errors='replace')+'\nTIMEOUT'
        code = -1
    (OUT/('check-'+name+'.log')).write_text(output,encoding='utf-8')
    passed = code == 0 and 'PASS:' in output and not re.search(r'(?m)^(SCRIPT ERROR:|ERROR:|FAIL:)',output)
    print(('PASS ' if passed else 'FAIL ')+name+' exit='+str(code),flush=True)
    return {'test':test,'graphical':graphical,'exit':code,'passed':passed}

with ThreadPoolExecutor(max_workers=3) as pool:
    results = [future.result() for future in as_completed([pool.submit(run,test) for test in TESTS])]
results.append(run('minute_structure_refresh_test.tscn',True))
(OUT/'verification.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('VERIFIED '+str(sum(r['passed'] for r in results))+'/'+str(len(results)),flush=True)
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
