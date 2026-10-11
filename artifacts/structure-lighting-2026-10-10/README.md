# Structure lighting presentation, 10 October 2026

Scope: preserve existing shader/mask and world behavior; light-state changes
update existing torch textures without rebuilding the structure scene or its
physics. Geometry edits, door changes and simulation/index replacement retain
the full refresh. The new door revision is derived runtime data, not saved.

`red.log` records seven failing assertions before implementation. The new scene
regression checks object identity on light changes, actual mask/shader binding,
no-op/coalesced updates, mixed door/geometry edits and reload. The torch map only
stores sprites; it does not retain or mutate authoritative structure records.

`checks.json` records the same functional set as the preceding increment plus
the new structure-lighting scene. Run it before graphical probes. A separate
focused repeat checks the final simplified map and shader-mask assertions.

Graphical probes run sequentially with no functional tests at the same time.
Compare to `artifacts/npc-work-queries-2026-10-10/final`, especially actual 30
torch activations in `evening-lights-30`. Minute calculation timings exclude
deferred visual frames; natural windows include both. `ordinary-2` actually
has three active residents. No production save changes and no threading.

All 36 functional sets passed. The final four focused tests passed again;
`furniture-ui-native.json`/`.log` confirm the actual rendered brightness change.
All four primary graphical cases and one evening repeat passed without errors.
`comparison.json` records the primary before/after windows. The light-triggered
visual frame fell from 185.314 to 36.801 ms; repeat: 38.880 ms. Both windows had
zero full structure rebuilds/draws and one local light update. The main natural
stress window remains 101.946 ms max / 74.84 FPS, ordinary three-resident control
24.293 ms max / 479.70 FPS. General minute smoothness has not improved here.

The first evening run also recorded a 93.529 ms paused spike with no structure
rebuild. Repeat paused maximum was 15.602 ms; cause of the first spike is unknown.
Keep this observation in reports, rather than claiming stable 100 FPS.

```powershell
python -B artifacts/structure-lighting-2026-10-10/run_checks.py --godot <console-exe>
python -B artifacts/structure-lighting-2026-10-10/run_diagnostics.py --godot <GUI-exe> --output-root <new-directory> evening-lights-30 work-30 natural-30 ordinary-2
```
