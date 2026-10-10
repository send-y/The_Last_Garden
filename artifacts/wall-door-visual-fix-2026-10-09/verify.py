from pathlib import Path
import subprocess,json,sys,re
from concurrent.futures import ThreadPoolExecutor,as_completed
root=Path('D:/The_Last_Garden')
out=root/'artifacts/wall-door-visual-fix-2026-10-09'
engine='D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe'
cases={
 'wall-pixels':([],['res://tests/wall_cell_visual_test.tscn']),
 'door-and-input':([],['res://tests/world_editing_ui_test.tscn','--','--capture']),
 'minute-refresh':(['--headless'],['res://tests/minute_structure_refresh_test.tscn']),
 'rules':(['--headless'],['--script','res://tests/world_editing_test.gd'])}
selected=sys.argv[1:] or list(cases)
def run(name):
 flags,args=cases[name]
 p=subprocess.run([engine,*flags,'--path',str(root/'game'),*args],capture_output=True,timeout=60)
 data=(p.stdout+p.stderr).decode('utf-8',errors='replace')
 (out/(name+'.log')).write_text(data,encoding='utf-8')
 return {'name':name,'exit':p.returncode,'passed':p.returncode==0 and not re.search(r'(^|\n)(SCRIPT ERROR:|ERROR:)',data)}
results=[]
with ThreadPoolExecutor(max_workers=2) as pool:
 for f in as_completed([pool.submit(run,name) for name in selected]):
  result=f.result()
  print(json.dumps(result),flush=True)
  results.append(result)
(out/'verification.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
