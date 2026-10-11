"""Functional checks only; never run alongside CPU probes."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('names', nargs='*')
args = parser.parse_args()
output = Path(__file__).resolve().parent
root = output.parents[1]
scripts = ['furniture_approach_context_cost_test', 'household_notice_cost_test', 'housing_approach_query_cost_test', 'furniture_seat_query_cost_test', 'building_catalog_query_cost_test', 'home_catalog_query_cost_test', 'inventory_count_cost_test', 'inventory_layout_sync_cost_test', 'housing_room_sets_cost_test', 'npc_work_query_cache_test', 'npc_work_material_query_test', 'construction_query_cost_test', 'npc_query_cost_test', 'local_home_layout_cost_test', 'housing_refresh_cost_test', 'indexed_consumers_test', 'structure_index_test', 'minute_geometry_cache_test', 'diagnostic_trace_test',
           'run_tests', 'housing_sleep_test', 'resident_home_policy_test',
           'resident_home_projects_test', 'npc_home_projects_test', 'npc_home_production_test',
           'npc_practical_work_test', 'household_feedback_test', 'world_editing_test',
           'furniture_rules_test', 'farming_rules_test',
           'settlement_stress_test']
scenes = ['structure_lighting_ui_test', 'lab_status_cost_test', 'mechanics_lab_dialogue_ui_test', 'world_presentation_test', 'generated_npcs_integration_test', 'housing_ui_test', 'resident_homes_ui_test', 'npc_home_projects_ui_test',
          'npc_home_production_ui_test', 'world_editing_ui_test', 'furniture_ui_test',
          'storage_integration_test', 'settlement_stress_ui_test', 'frame_rate_hud_test']
tests = [(name, ['--script',f'res://tests/{name}.gd']) for name in scripts]
tests += [(name, [f'res://tests/{name}.tscn']) for name in scenes]
if args.names:
    tests = [test for test in tests if test[0] in args.names]
previous = json.loads((output/'checks.json').read_text()) if (output/'checks.json').exists() else []
previous = [entry for entry in previous if entry['name'] not in {test[0] for test in tests}]

def run(test):
    name, options = test
    try:
        process = subprocess.run([args.godot,'--headless','--path',str(root/'game'),*options], capture_output=True, timeout=600)
        text = (process.stdout+process.stderr).decode('utf-8',errors='replace')
        code = process.returncode
    except subprocess.TimeoutExpired as error:
        text = str(error)
        code = -1
    (output/(name+'.log')).write_text(text,encoding='utf-8')
    errors = [line for line in text.splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:'))]
    result = {'name':name,'exit':code,'errors':errors,'passed':code==0 and not errors,
              'summary':[line for line in text.splitlines() if line.startswith('PASS:') or 'failures' in line]}
    print(json.dumps(result),flush=True)
    return result

with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run,tests))
(output/'checks.json').write_text(json.dumps(previous+results,indent=2),encoding='utf-8')
raise SystemExit(0 if all(entry['passed'] for entry in results) else 1)
