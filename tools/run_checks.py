"""Run selected Godot checks with isolated Session storage and immutable logs."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SAVE = pathlib.Path.home() / "AppData/Roaming/Godot/app_userdata/The Last Garden/first_night_save.json"

def hashes():
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None
            for p in (SAVE, pathlib.Path(str(SAVE) + ".bak"))}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run_id")
    parser.add_argument("checks", nargs="+")
    parser.add_argument("--godot", default="D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe")
    args = parser.parse_args()
    if pathlib.Path(args.run_id).name != args.run_id:
        parser.error("run_id must be a directory name")
    out = ROOT / "artifacts/package-d-2026-10-14" / args.run_id
    out.mkdir(parents=True, exist_ok=False)
    before = hashes()
    results = []
    with tempfile.TemporaryDirectory(prefix="garden-checks-") as isolated:
        for entry in args.checks:
            graphic = entry.startswith("graphic:")
            name = entry.removeprefix("graphic:")
            cmd = [args.godot, "--path", str(ROOT / "game")]
            cmd += ["--rendering-method", "gl_compatibility"] if graphic else ["--headless"]
            cmd += ["--script", "res://tests/" + name] if name.endswith(".gd") else ["res://tests/" + name]
            cmd += ["--", "--test-save-path=" + str(pathlib.Path(isolated) / "session.json"), "--test-artifact-dir=" + str(out)]
            log_path = out / (pathlib.Path(name).stem + ("-graphic" if graphic else "") + ".log")
            with log_path.open("wb") as log:
                process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
                try:
                    code = process.wait(timeout=420)
                except subprocess.TimeoutExpired:
                    process.kill()
                    code = process.wait()
            text = log_path.read_text(encoding="utf-8", errors="replace")
            passed = code == 0 and "ERROR:" not in text and ("PASS" in text or "0 failures" in text)
            results.append({"check": entry, "exit": code, "passed": passed})
            print(f"{entry}: {'PASS' if passed else 'FAIL'} exit={code}", flush=True)
            if not passed:
                print(text[-3500:], flush=True)
            if hashes() != before:
                break
    after = hashes()
    (out / "result.json").write_text(json.dumps({"checks": results, "save_before": before, "save_after": after}, indent=2), encoding="utf-8")
    assert after == before, "Ordinary player save or backup changed"
    return 0 if len(results) == len(args.checks) and all(r["passed"] for r in results) else 1

if __name__ == "__main__":
    raise SystemExit(main())
