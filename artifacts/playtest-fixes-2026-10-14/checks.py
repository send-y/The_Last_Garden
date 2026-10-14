import concurrent.futures, hashlib, json, pathlib, subprocess, sys, time
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent
GODOT = 'D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe'
SAVE = pathlib.Path.home() / 'AppData/Roaming/Godot/app_userdata/The Last Garden/first_night_save.json'
def digest():
    return hashlib.sha256(SAVE.read_bytes()).hexdigest() if SAVE.exists() else 'absent'
def run(name):
    graphic = name.startswith('graphic:')
    name = name.removeprefix('graphic:')
    args = [GODOT, '--path', str(ROOT / 'game')]
    args += ['--rendering-method', 'gl_compatibility'] if graphic else ['--headless']
    args += ['--script', 'res://tests/' + name] if name.endswith('.gd') else ['res://tests/' + name]
    path = OUT / (sys.argv[1] + "-" + pathlib.Path(name).stem + ('-graphic' if graphic else '') + '.log')
    with path.open('wb') as stream:
        process = subprocess.Popen(args, stdout=stream, stderr=stream)
        started = time.monotonic()
        while process.poll() is None:
            time.sleep(0.25)
            current = path.read_bytes().decode('utf-8', errors='replace')
            if 'SCRIPT ERROR:' in current or time.monotonic() - started > 420:
                process.kill()
                break
        code = process.wait()
    log = path.read_text(encoding='utf-8', errors='replace')
    passed = code == 0 and 'SCRIPT ERROR:' not in log and 'ERROR:' not in log and ('PASS' in log or '0 failures' in log)
    print(f'{name}: {"PASS" if passed else "FAIL"} exit={code}', flush=True)
    if not passed: print(log[-2500:], flush=True)
    return {'name': name, 'graphic': graphic, 'exit': code, 'passed': passed}
if __name__ == '__main__':
    before = digest()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(run, sys.argv[2:]))
    after = digest()
    (OUT / (sys.argv[1] + '.json')).write_text(json.dumps({'checks': results, 'save_before': before, 'save_after': after}, indent=2), encoding='utf-8')
    assert before == after, 'Default game save changed'
    sys.exit(0 if all(row['passed'] for row in results) else 1)
