"""Summarize captured stages and compare exported authoritative JSON values."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

result = {'cases': {}, 'checks_passed': sum(row['passed'] for row in read(HERE / 'checks.json'))}
for directory in sorted((HERE / 'final').iterdir()):
    if not directory.is_dir() or not (directory / 'stages.json').exists():
        continue
    rows = []
    for stage in read(directory / 'stages.json'):
        frames = stage['frames']
        spans = stage['trace']['spans']
        row = {key: stage[key] for key in ('label', 'wall_ms', 'structure_validation_enabled')}
        if frames:
            row['fps'] = frames['frames'] * 1000 / stage['wall_ms']
            row['max_frame_ms'] = frames['max_frame_ms']
        row['serialize_or_deep_compare_calls'] = sum(value['calls'] for key, value in spans.items()
            if 'serialize_structures' in key or key == 'housing.geometry_compare')
        row['counters'] = stage['trace']['counters']
        row['spans'] = spans
        for key in ('lit_before', 'lit_after', 'lighting_revision_delta', 'participants'):
            if key in stage:
                row[key] = stage[key]
        rows.append(row)
    result['cases'][directory.name] = rows

before_path = ROOT / 'artifacts/settlement-index-2026-10-10/authority-before.json'
after_path = HERE / 'authority-after.json'
if after_path.exists():
    before, after = read(before_path), read(after_path)
    result['authority_equal'] = {key: before[key] == after[key] for key in before}
    if not all(result['authority_equal'].values()):
        raise SystemExit('Authoritative state differs from baseline')
(HERE / 'comparison.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
summary = {name: [{key: row[key] for key in row if key not in ('spans', 'counters')}
    for row in rows] for name, rows in result['cases'].items()}
print(json.dumps({'checks_passed':result['checks_passed'], 'authority_equal':result.get('authority_equal'),
    'cases':summary}, ensure_ascii=False, indent=2))
