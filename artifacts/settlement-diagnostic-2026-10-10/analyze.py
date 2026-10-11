"""Summarize measured native CPU windows and nested diagnostic spans."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parent
summary = []
for case in ['work-30', 'sleep-30', 'work-3', 'work-30-no-trace', 'frames-30', 'frames-30-settled', 'storage-redraw-30']:
    directory = root / case
    if not (directory / 'stages.json').exists(): continue
    native = json.loads((directory / 'cpu.json').read_text())
    cpu = {row['label']: row for row in native['measurements']}
    for stage in json.loads((directory / 'stages.json').read_text()):
        if stage['label'] not in cpu: continue
        row = cpu[stage['label']]
        spans = stage['trace']['spans']
        summary.append({'case': case, 'label': stage['label'], 'wall_ms': stage['wall_ms'],
                        'native_window_ms': row['native_window_ms'], 'main_cpu_ms': row['main_cpu_ms'],
                        'process_cpu_ms': row['process_cpu_ms'],
                        'main_thread_cpu_wall_percent': row['main_one_core_percent'],
                        'process_percent_normalized_12_cpus': row['process_machine_percent'],
                        'geometry_calls': spans.get('housing.geometry_compare', {}).get('calls', 0),
                        'geometry_ms': spans.get('housing.geometry_compare', {}).get('inclusive_us', 0) / 1000,
                        'astar_ms': spans.get('navigation.astar', {}).get('inclusive_us', 0) / 1000,
                        'astar_calls': stage['trace']['counters'].get('astar_calls', 0),
                        'frames': stage['frames'].get('frames'),
                        'maximum_frame_ms': stage['frames'].get('max_frame_ms'),
                        'interval_rate': stage['frames']['frames'] / (stage['wall_ms'] / 1000) if stage['frames'].get('frames') else None,
                        'top_spans': sorted([{'name': name, 'calls': value['calls'],
                                             'inclusive_ms': value['inclusive_us'] / 1000,
                                             'self_ms': value['self_us'] / 1000}
                                            for name, value in spans.items()], key=lambda r: -r['inclusive_ms'])[:12]})
(root / 'summary.json').write_text(json.dumps(summary, indent=2))

fig, axes = plt.subplots(2, 1, figsize=(11, 8), constrained_layout=True)
minutes = [row for row in summary if row['label'].startswith('minute') and row['case'] != 'work-30-no-trace']
positions = range(len(minutes))
geometry = [row['geometry_ms'] / 1000 for row in minutes]
other = [(row['wall_ms'] - row['geometry_ms']) / 1000 for row in minutes]
axes[0].barh(positions, geometry, color='#c16c48', label='Repeated housing geometry comparisons')
axes[0].barh(positions, other, left=geometry, color='#627f8c', label='Remaining step time')
axes[0].set_yticks(list(positions), [row['case'] + ' / ' + row['label'] for row in minutes])
axes[0].set_xlabel('Elapsed seconds for one game minute')
axes[0].legend(fontsize=8)
axes[0].set_title('Measured time attribution; simulation behavior unchanged')

samples = json.loads((root / 'work-30' / 'samples.json').read_text())
first = json.loads((root / 'work-30' / 'cpu.json').read_text())['measurements']
axes[1].plot([r['seconds'] for r in samples], [r['main_one_core_percent'] for r in samples],
             color='#c16c48', label='Native primary thread: CPU time / wall time')
axes[1].plot([r['seconds'] for r in samples], [r['process_machine_percent'] for r in samples],
             color='#427b8a', label='Godot process: CPU / wall / 12 logical CPUs')
axes[1].set_xlabel('Seconds since launch (includes setup and boundary handshakes)')
axes[1].set_ylabel('Percent (CPU-time accounting)')
axes[1].set_ylim(0, 115)
axes[1].legend(fontsize=8)
fig.suptitle('The Last Garden: CPU diagnostic, i5-12400F / RTX 4060\nLow aggregate CPU load while the primary thread is occupied')
fig.savefig(root / 'diagnostic-comparison.png', dpi=160)
print(json.dumps([{k: row[k] for k in ['case', 'label', 'wall_ms', 'main_thread_cpu_wall_percent', 'geometry_calls', 'geometry_ms', 'interval_rate']} for row in summary]))
