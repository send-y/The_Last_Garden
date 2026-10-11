"""Compare retained baseline to steps 1-2; run after all probes finish."""
import json
from pathlib import Path

output = Path(__file__).resolve().parent
baseline = output.parent / 'settlement-diagnostic-2026-10-10'
before = json.loads((output / 'authority-before.json').read_text(encoding='utf-8'))
after = json.loads((output / 'authority-after.json').read_text(encoding='utf-8'))
authority = {key: before[key] == after[key] for key in before}
(output / 'authority-comparison.json').write_text(json.dumps(authority, indent=2))
assert all(authority.values()), authority
checks = json.loads((output / 'checks.json').read_text(encoding='utf-8'))
assert len(checks) == 25 and all(row['passed'] for row in checks)
runs = json.loads((output / 'runs.json').read_text(encoding='utf-8'))
assert len(runs) >= 2 and all(row['passed'] for row in runs)
comparison = []
for case in ['work-30', 'sleep-30']:
    previous = {row['label']: row for row in json.loads((baseline / case / 'stages.json').read_text(encoding='utf-8'))}
    current = json.loads((output / case / 'stages.json').read_text(encoding='utf-8'))
    for row in current:
        label = row['label']
        old = previous[label]
        spans = row['trace']['spans']
        entry = {
            'case': case, 'label': label,
            'before_wall_ms': old['wall_ms'], 'after_wall_ms': row['wall_ms'],
            'ratio': old['wall_ms'] / row['wall_ms'],
            'geometry_compare_calls_before': old['trace']['spans'].get('housing.geometry_compare', {}).get('calls', 0),
            'geometry_compare_calls_after': spans.get('housing.geometry_compare', {}).get('calls', 0),
            'policy_rebuild_calls': spans.get('housing.policy_rebuild', {}).get('calls', 0),
            'housing_rebuild_calls': spans.get('housing.rebuild', {}).get('calls', 0),
            'structure_validation_enabled': row['structure_validation_enabled'],
            'frames': row['frames'],
            'spans': {key: value for key, value in spans.items() if key.startswith(('housing.', 'world.draw', 'storage.', 'lighting.'))},
        }
        comparison.append(entry)
        print(json.dumps({key: value for key, value in entry.items() if key != 'spans'}))
        assert entry['geometry_compare_calls_after'] == 0
        assert not row['structure_validation_enabled']
summary = {'authority_equal': authority, 'checks_passed': len(checks), 'comparison': comparison}
(output / 'comparison.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
