"""Compare minute CPU steps separately from deferred and natural visual frames."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
before = root.parents[1] / 'artifacts/npc-work-queries-2026-10-10/final'
cases = ['evening-lights-30', 'work-30', 'natural-30', 'ordinary-2']
def read(path):
    return json.loads(path.read_text(encoding='utf-8'))
result = {'checks':read(root/'checks.json'), 'runs':read(root/'final/runs.json'), 'stages':[]}
assert len(result['checks']) == 36 and all(row['passed'] for row in result['checks'])
assert len(result['runs']) == 4 and all(row['passed'] for row in result['runs'])
for case in cases:
    old = {row['label']:row for row in read(before/case/'stages.json')}
    for row in read(root/'final'/case/'stages.json'):
        prior = old[row['label']]
        spans = row['trace']['spans']
        entry = {'case':case, 'label':row['label'],
                 'minute_before_ms':prior['wall_ms'] if row['label'].startswith('minute_') else None,
                 'minute_after_ms':row['wall_ms'] if row['label'].startswith('minute_') else None,
                 'frame_before_ms':prior['frames'].get('max_frame_ms'),
                 'frame_after_ms':row['frames'].get('max_frame_ms'),
                 'fps_after':row['frames']['frames']*1000/row['wall_ms'] if row['frames'] else None,
                 'active_residents':row['active_residents'],
                 'minute_calls':spans.get('clock.total',{}).get('calls',0),
                 'structure_rebuilds':spans.get('scene.structure_refresh',{}).get('calls',0),
                 'structure_draws':spans.get('scene.structure_draw',{}).get('calls',0),
                 'local_light_updates':spans.get('scene.structure_lights',{}).get('calls',0)}
        for key in ['lit_before','lit_after','lighting_revision_delta']:
            if key in row: entry[key] = row[key]
        result['stages'].append(entry)
        if row['label'].startswith('minute_') or row['label'] in ['natural_minutes','render_after_2']:
            print(entry)
(root/'comparison.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
