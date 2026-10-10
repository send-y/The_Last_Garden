"""Compile WorldSimulation consumers with its global registration missing.

Run: python game/tests/check_world_class_registry.py --godot <Godot executable>
The real project's class cache and user saves are never modified.
"""

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[1]
    output = game.parent / "artifacts" / "world-class-loading-2026-10-08"
    output.mkdir(parents=True, exist_ok=True)
    cache_source = game / ".godot" / "global_script_class_cache.cfg"
    if not cache_source.exists():
        parser.error("Import the project in Godot before running this regression.")
    temporary = Path(tempfile.mkdtemp(prefix="registry-check-", dir=output)).resolve()
    assert temporary.is_relative_to(output.resolve())
    results = []
    try:
        fixture = temporary / "game"
        shutil.copytree(game, fixture, ignore=shutil.ignore_patterns(".godot"))
        cache = fixture / ".godot"
        cache.mkdir()
        shutil.copytree(game / ".godot" / "imported", cache / "imported")
        uid_cache = game / ".godot" / "uid_cache.bin"
        if uid_cache.exists():
            shutil.copy2(uid_cache, cache / uid_cache.name)
        # Godot's cache is a list of dictionaries. Remove exactly this entry.
        raw = cache_source.read_text(encoding="utf-8")
        pattern = r', \{\n"base": &"RefCounted",\n"class": &"WorldSimulation",.*?\n\}'
        stale, removed = re.subn(pattern, "", raw, flags=re.S)
        if removed != 1:
            raise RuntimeError("Expected one WorldSimulation cache entry.")
        (cache / cache_source.name).write_text(stale, encoding="utf-8")
        for name, command in [
            ("core", ["--check-only", "--script", "res://tests/run_tests.gd"]),
            ("session", ["--check-only", "--script", "res://src/autoload/session.gd"]),
            ("lab", ["--check-only", "--script", "res://src/dev/mechanics_lab_scenarios.gd"]),
            ("persistent-world", ["--check-only", "--script", "res://tests/persistent_world_test.gd"]),
            # Scene startup supplies autoloads; checking a Node as a CLI script does not.
            ("persistent-world-ui", ["res://tests/persistent_world_integration_test.tscn"]),
        ]:
            run = subprocess.run(
                [args.godot, "--headless", "--path", str(fixture), *command],
                capture_output=True, text=True, encoding="utf-8", timeout=60,
            )
            log = run.stdout + run.stderr
            (output / f"registry-{name}.log").write_text(log, encoding="utf-8")
            errors = [line for line in log.splitlines()
                      if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
            result = {"name": name, "exit": run.returncode, "errors": errors}
            results.append(result)
            print(json.dumps(result), flush=True)
        (output / "registry-checks.json").write_text(
            json.dumps(results, indent=2), encoding="utf-8")
        return 0 if all(r["exit"] == 0 and not r["errors"] for r in results) else 1
    finally:
        assert temporary.is_relative_to(output.resolve())
        shutil.rmtree(temporary)


if __name__ == "__main__":
    raise SystemExit(main())
