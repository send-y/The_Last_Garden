# Mechanics Lab scenario-switch regression

Reported `warehouse_cell()` index 4 failure reproduced when switching from
`settlement_stress` to `resident_homes` through the scenario selector.
`Session.apply_debug_state()` replaces the world and synchronously emits
`time_changed` before the lab adopts the new scenario ID and participants.
The previous stress handler therefore modified the incoming ordinary warehouse.

`red.log` records the pre-fix failure and the assertion that the incoming
world's population and finite supplies must remain unchanged during reload.
The lab now suppresses its time handler only while applying the incoming state;
normal subsequent stress replenishment remains enabled. Failed application
also clears the loading guard. No simulation, save schema or lighting changes.

The scene regression checks stress -> ordinary houses -> stress -> stress reset
-> fresh start, restoring the player camera, retaining seventy ordinary planks
and three active residents, and replenishing a depleted stack after return.
It captures the world at `state_reloaded` and verifies reload callbacks do not
change it. These are headless scene checks, not a graphical FPS benchmark.

Run the same 35 functional sets used for the preceding optimization:

```powershell
python -B artifacts/lab-scenario-switch-2026-10-10/run_checks.py --godot D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe
```

Individual logs and `checks.json` contain the fresh post-fix outcomes.
All 35 sets passed with exit code 0 and no `ERROR`/`SCRIPT ERROR`. The expanded
scenario-switch scene regression passed; the pre-fix run exited 1 with the
reported index error and the incoming-world preservation assertion failure.
