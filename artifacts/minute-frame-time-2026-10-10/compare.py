"""Summarize measured minutes and complete natural frame windows, without equating them."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
repo = root.parents[1]
def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

before = repo / 'artifacts/settlement-index-consumers-2026-10-10/final'
result = {'minutes': [], 'natural_windows': [], 'checks': read(root/'checks.json')}
result['authority_equal'] = read(repo/'artifacts/settlement-index-2026-10-10/authority-before.json') == read(root/'authority-after.json')
for case in ['work-30', 'sleep-30', 'evening-lights-30', 'work-3', 'natural-30', 'ordinary-2']:
    path = root/'final'/case/'stages.json'
    if not path.exists():
        continue
    stages = read(path)
    old = {row['label']:row for row in read(before/case/'stages.json')} if (before/case/'stages.json').exists() else {}
    print(case)
    for row in stages:
        frames = row['frames']
        spans = row['trace']['spans']
        if row['label'].startswith('minute_'):
            entry = {'case':case, 'label':row['label'], 'before_ms':old.get(row['label'],{}).get('wall_ms'), 'after_ms':row['wall_ms']}
            if 'lit_before' in row:
                entry.update({key:row[key] for key in ['lit_before','lit_after','lighting_revision_delta']})
            result['minutes'].append(entry)
            print(entry)
            print('  spans',sorted([(key,value['calls'],round(value['inclusive_us']/1000,3),round(value['self_us']/1000,3)) for key,value in spans.items()],key=lambda x:-x[2])[:12])
        if frames:
            entry = {'case':case,'label':row['label'],'fps':frames['frames']*1000/row['wall_ms'],'max_frame_ms':frames['max_frame_ms'],'frames':frames['frames'],'elapsed_game_minutes':row['elapsed_game_minutes'],'minute_calls':spans.get('clock.total',{}).get('calls',0),'world_refreshes':spans.get('scene.world_state_refresh',{}).get('calls',0),'hud_refreshes':spans.get('scene.hud_refresh',{}).get('calls',0),'active_residents':row['active_residents']}
            result['natural_windows'].append(entry)
            print(entry)
            if entry['minute_calls']:
                print('  spans',sorted([(key,value['calls'],round(value['inclusive_us']/1000,3),round(value['maximum_us']/1000,3)) for key,value in spans.items()],key=lambda x:-x[2])[:15])
(root/'comparison.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
print('authority_equal',result['authority_equal'],'checks',sum(row['passed'] for row in result['checks']),len(result['checks']))
