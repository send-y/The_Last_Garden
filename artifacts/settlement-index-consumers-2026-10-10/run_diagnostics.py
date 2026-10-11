"""Windows CPU-time sampling with exact native primary thread ID from CreateProcess.

Launch the graphical Godot executable directly (not its console launcher).
Never run alongside tests or another game benchmark.
"""
import _winapi
import argparse
import json
from pathlib import Path
import subprocess
import threading
import time
import psutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('--output-root')
parser.add_argument('cases', nargs='*')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = Path(args.output_root).resolve() if args.output_root else Path(__file__).resolve().parent
output.mkdir(parents=True, exist_ok=True)
cases = {'work-30': (30, 'work', 2, True), 'sleep-30': (30, 'sleep', 1, True),
         'evening-lights-30': (30, 'evening', 2, True),
         'work-3': (3, 'work', 1, True), 'work-30-no-trace': (30, 'work', 1, False),
         'frames-30': (30, 'frames', 1, True), 'frames-30-settled': (30, 'frames', 1, True),
         'storage-redraw-30': (30, 'redraw', 1, True)}
selected = args.cases or list(cases)
results = json.loads((output / 'runs.json').read_text()) if (output / 'runs.json').exists() else []
results = [result for result in results if result['case'] not in selected]

def snapshot(process):
    clock = time.perf_counter()
    cpu = process.cpu_times()
    threads = {item.id: item.user_time + item.system_time for item in process.threads()}
    io = process.io_counters()
    return {'clock': clock, 'process_cpu': cpu.user + cpu.system,
            'threads': threads, 'rss': process.memory_info().rss,
            'read_bytes': io.read_bytes, 'write_bytes': io.write_bytes}

for name in selected:
    count, phase, steps, tracing = cases[name]
    directory = output / name
    directory.mkdir(parents=True, exist_ok=True)
    # Remove only this runner's previous handshake files, within its own case dir.
    for file in [directory / 'boundary.json', *directory.glob('ack-*')]:
        if file.exists(): file.unlink()
    command = [args.godot, '--path', str(root / 'game'),
               'res://src/dev/settlement_cpu_diagnostic.tscn', '--',
               '--lab-scenario=settlement_stress', f'--stress-residents={count}',
               f'--diag-phase={phase}', f'--diag-minutes={steps}', f'--diag-output={directory}']
    if not tracing: command.append('--diag-no-trace')
    native = {}
    original_create = _winapi.CreateProcess
    def create(*parameters, **options):
        handles = original_create(*parameters, **options)
        native['pid'], native['main_tid'] = handles[2], handles[3]
        return handles
    _winapi.CreateProcess = create
    try:
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    finally:
        _winapi.CreateProcess = original_create
    print(json.dumps({'starting': name, **native}), flush=True)
    process = psutil.Process(child.pid)
    captured = bytearray()
    def read_output():
        while True:
            chunk = child.stdout.read(4096)
            if not chunk: break
            captured.extend(chunk)
    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    starts, measurements, samples = {}, [], []
    seen = 0
    started = time.perf_counter()
    last_sample = 0.0
    previous = snapshot(process)
    psutil.cpu_percent()
    sampler_error = None
    while child.poll() is None:
        if time.perf_counter() - started > 360:
            subprocess.run(['taskkill', '/PID', str(child.pid), '/T', '/F'], capture_output=True)
            sampler_error = 'timeout'
            break
        marker = directory / 'boundary.json'
        try:
            boundary = json.loads(marker.read_text()) if marker.exists() else {}
        except (json.JSONDecodeError, PermissionError):
            boundary = {}
        if boundary and boundary['sequence'] != seen:
            seen = boundary['sequence']
            if boundary['pid'] != child.pid:
                sampler_error = 'Godot PID differs from launched executable; use the GUI binary directly'
                subprocess.run(['taskkill', '/PID', str(child.pid), '/T', '/F'], capture_output=True)
                break
            current = snapshot(process)
            label = boundary['label']
            if boundary['edge'] == 'before':
                starts[label] = current
            else:
                initial = starts[label]
                elapsed = current['clock'] - initial['clock']
                threads = [{'tid': tid, 'cpu_ms': 1000 * max(0, cpu - initial['threads'].get(tid, 0))}
                           for tid, cpu in current['threads'].items()]
                threads.sort(key=lambda item: item['cpu_ms'], reverse=True)
                main_cpu = next((item['cpu_ms'] for item in threads if item['tid'] == native['main_tid']), 0)
                cpu = 1000 * (current['process_cpu'] - initial['process_cpu'])
                row = {'label': label, 'native_window_ms': elapsed * 1000,
                       'process_cpu_ms': cpu, 'main_cpu_ms': main_cpu,
                       'main_one_core_percent': main_cpu / (elapsed * 10),
                       'process_machine_percent': cpu / (elapsed * 10 * psutil.cpu_count()),
                       'other_threads_cpu_ms': max(0, cpu - main_cpu), 'threads': threads[:12],
                       'rss_end_bytes': current['rss'],
                       'read_bytes_delta': current['read_bytes'] - initial['read_bytes'],
                       'write_bytes_delta': current['write_bytes'] - initial['write_bytes']}
                measurements.append(row)
                (directory / 'cpu.json').write_text(json.dumps({'native': native, 'logical_cpus': psutil.cpu_count(), 'measurements': measurements}, indent=2))
                print(json.dumps({'case': name, **{key: row[key] for key in ['label', 'native_window_ms', 'process_cpu_ms', 'main_cpu_ms', 'main_one_core_percent', 'process_machine_percent']}}), flush=True)
            (directory / ('ack-%d' % seen)).write_text('ack')
        if time.perf_counter() - last_sample >= 0.25:
            try:
                current = snapshot(process)
            except psutil.NoSuchProcess:
                break  # Normal exit may race the final periodic sample.
            elapsed = current['clock'] - previous['clock']
            main_delta = current['threads'].get(native['main_tid'], 0) - previous['threads'].get(native['main_tid'], 0)
            samples.append({'seconds': current['clock'] - started,
                            'label': boundary.get('label', 'setup'), 'edge': boundary.get('edge', ''),
                            'main_one_core_percent': main_delta / elapsed * 100,
                            'process_machine_percent': (current['process_cpu'] - previous['process_cpu']) / elapsed * 100 / psutil.cpu_count(),
                            'machine_cpu_percent': psutil.cpu_percent(), 'rss_bytes': current['rss']})
            previous = current
            last_sample = time.perf_counter()
        time.sleep(0.01)
    child.wait()
    reader.join(timeout=5)
    text = captured.decode('utf-8', errors='replace')
    (directory / 'godot.log').write_text(text, encoding='utf-8')
    (directory / 'samples.json').write_text(json.dumps(samples, indent=2))
    errors = [line for line in text.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    result = {'case': name, 'exit': child.returncode, 'errors': errors, 'sampler_error': sampler_error,
              'passed': child.returncode == 0 and not errors and sampler_error is None and len(measurements) == (2 if phase == 'redraw' else (7 if phase == 'frames' else 2 * steps + 2))}
    results.append(result)
    (output / 'runs.json').write_text(json.dumps(results, indent=2))
    print(json.dumps(result), flush=True)
    if not result['passed']: break
raise SystemExit(0 if all(result['passed'] for result in results) else 1)
