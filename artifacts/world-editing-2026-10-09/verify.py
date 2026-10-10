from pathlib import Path
import subprocess,json,time,re,sys
from concurrent.futures import ThreadPoolExecutor,as_completed
root=Path('D:/The_Last_Garden')
out=root/'artifacts/world-editing-2026-10-09'
engine='D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe'
cases=[('rules',['--script','res://tests/world_editing_test.gd']),
 ('editing-ui',['res://tests/world_editing_ui_test.tscn']),
 ('editing-graphical',['res://tests/world_editing_ui_test.tscn','--','--capture']),
 ('storage-ui',['res://tests/storage_integration_test.tscn']),
 ('structure-refresh',['res://tests/minute_structure_refresh_test.tscn']),
 ('full',['--script','res://tests/run_tests.gd']),
 ('farming',['--script','res://tests/farming_rules_test.gd']),
 ('housing',['--script','res://tests/housing_sleep_test.gd']),
 ('home-projects',['--script','res://tests/resident_home_projects_test.gd']),
 ('geometry-cache',['--script','res://tests/minute_geometry_cache_test.gd']),
 ('furniture',['--script','res://tests/furniture_rules_test.gd']),
 ('persistent-world',['--script','res://tests/persistent_world_test.gd'])]
if len(sys.argv)>1: cases=[case for case in cases if case[0] in sys.argv[1:]]
selected={case[0] for case in cases}
results=[r for r in json.loads((out/'verification.json').read_text(encoding='utf-8')) if r['name'] not in selected] if (out/'verification.json').exists() else []
def run(case):
 name,args=case
 start=time.perf_counter()
 try:
  flags=[] if name=='editing-graphical' else ['--headless']
  p=subprocess.run([engine,*flags,'--path',str(root/'game'),*args],capture_output=True,timeout=180)
  data=(p.stdout+p.stderr).decode('utf-8',errors='replace')
  errors=bool(re.search(r'(^|\n)(SCRIPT ERROR:|ERROR:)',data))
  result={'name':name,'exit_code':p.returncode,'errors':errors,'passed':p.returncode==0 and not errors}
 except subprocess.TimeoutExpired as e:
  data=((e.stdout or b'')+(e.stderr or b'')).decode('utf-8',errors='replace')
  result={'name':name,'passed':False,'timeout':True}
 (out/(name+'.log')).write_text(data,encoding='utf-8')
 result['seconds']=round(time.perf_counter()-start,2)
 return result
with ThreadPoolExecutor(max_workers=3) as pool:
 for future in as_completed([pool.submit(run,case) for case in cases]):
  result=future.result()
  results.append(result)
  print(json.dumps(result),flush=True)
  (out/'verification.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
