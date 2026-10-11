import argparse
import json
from pathlib import Path

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--directory', default='verified')
parser.add_argument('--before-directory', default='final')
args = parser.parse_args()
current = root / args.directory
previous = root / args.before_directory
result = {}
for run in json.loads((current / 'runs.json').read_text()):
    name = run['case']
    assert run['passed'], run
    stages = json.loads((current / name / 'stages.json').read_text())
    before_path = previous / name / 'stages.json'
    before = {x['label']: x for x in json.loads(before_path.read_text())} if before_path.exists() else {}
    rows = []
    for stage in stages:
        label = stage['label']
        old = before.get(label)
        row = {'stage': label, 'wall_ms': stage['wall_ms'], 'frames': stage['frames'],
               'active_residents': stage['active_residents'],
               'elapsed_game_minutes': stage['elapsed_game_minutes']}
        if old:
            row['before_wall_ms'] = old['wall_ms']
            row['before_frames'] = old['frames']
        if stage['frames']:
            row['average_fps'] = stage['frames']['frames'] / (stage['wall_ms'] / 1000)
        if 'lit_before' in stage:
            row.update({key: stage[key] for key in ['lit_before', 'lit_after', 'lighting_revision_delta']})
        row['top_spans'] = sorted(
            ({'span': key, 'calls': value['calls'], 'total_ms': value['inclusive_us']/1000,
              'max_ms': value['maximum_us']/1000} for key, value in stage['trace']['spans'].items()),
            key=lambda x: -x['total_ms'])[:12]
        rows.append(row)
    result[name] = rows
(current / 'comparison.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
for name, rows in result.items():
    print(name)
    for row in rows:
        if row['stage'].startswith('minute') or row['stage'] == 'natural_minutes':
            print(row['stage'], round(row['wall_ms'],3),row['frames'],row.get('average_fps'))
