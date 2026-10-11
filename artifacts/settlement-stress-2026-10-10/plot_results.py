"""Plot measured frame distributions and individual gameplay minute costs."""
import csv
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parent
cases = ['original-3', 'baseline-3', 'quiet-30', 'full-30', 'night-30',
         'production-30', 'gather-30', 'sleep-30', 'quiet-no-light-refresh-30']
profiles = [(name, json.loads((root / (name + '.json')).read_text()))
            for name in cases if (root / (name + '.json')).exists()]
labels = {'original-3': '3 NPC, original map', 'baseline-3': '3 NPC, 30 houses',
          'quiet-30': '30 NPC, simulation paused', 'full-30': '30 NPC, full warehouse',
          'night-30': '30 NPC, return to beds', 'production-30': '30 NPC, no supplied planks',
          'gather-30': '30 NPC, gathering pressure', 'sleep-30': '30 NPC, already sleeping',
          'quiet-no-light-refresh-30': 'Diagnostic: paused, Main light update off'}
fig, axes = plt.subplots(2, 1, figsize=(12, 9), constrained_layout=True)
positions = range(len(profiles))
axes[0].bar(positions, [p['average_fps'] for _, p in profiles], color=['#458c5b' if p['average_fps'] >= 100 else '#c86548' for _, p in profiles])
axes[0].set_yscale('log')
axes[0].axhline(100, color='#222222', linestyle='--', label='Target: 100 FPS')
axes[0].set_ylabel('Average FPS (log scale)')
axes[0].set_xticks(list(positions), [labels[name] for name, _ in profiles], rotation=30, ha='right', fontsize=8)
for i, (_, p) in enumerate(profiles):
    axes[0].text(i, p['average_fps'] * 1.12, f"{p['average_fps']:.2f}", ha='center', fontsize=8)
axes[0].legend(loc='upper right')
for name in ['original-3', 'baseline-3', 'quiet-30', 'full-30']:
    path = root / (name + '-frames.csv')
    if not path.exists(): continue
    with path.open() as file:
        rows = list(csv.DictReader(file))
    axes[1].plot([float(r['elapsed_ms']) / 1000 for r in rows],
                 [float(r['frame_ms']) for r in rows], label=labels[name], alpha=0.8, linewidth=1)
axes[1].set_yscale('log')
axes[1].axhline(10, color='#222222', linestyle='--', label='100 FPS frame budget: 10 ms')
axes[1].set_xlabel('Probe time, seconds (slow ticks may exceed requested duration)')
axes[1].set_ylabel('Frame time, ms (log scale)')
axes[1].legend(fontsize=8)
fig.suptitle('The Last Garden: 30-resident settlement stress test\ni5-12400F / RTX 4060 / 1280x720 / VSync off / sequential probes')
fig.savefig(root / 'performance-comparison.png', dpi=160)
summary = []
for name, p in profiles:
    summary.append({'case': name, 'fps': p['average_fps'], 'frames': p['frames'],
                    'seconds': p['seconds'], 'game_minutes': p['game_minutes'],
                    'max_frame_ms': p['frame_ms']['max'],
                    'max_minute_ms': p['minute_cpu_ms'].get('max'),
                    'final_activities': p['activities'],
                    'diagnostic': p.get('diagnostic_light_refresh_disabled', False)})
(root / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps(summary))
