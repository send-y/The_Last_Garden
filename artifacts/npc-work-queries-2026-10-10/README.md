# NPC work query optimization, 10 October 2026

`approach-only/` is an intermediate graphical probe after retaining approach
queries and adding finer timing. It showed that ongoing contexts were small;
new choices dominated. Do not present it as the final implementation or an
improvement: its natural maximum frame was 168.220 ms against the prior
161.179 ms single probe.

The final increment also filters home-project stock queries to outstanding
materials, reads one assigned sleeping place, and uses the shared structure
index for blueprint placement overlap. Actual stock and permission checks
remain live. Navigation results are simulation-owned runtime data.

`checks.json` and individual logs contain functional results. `authority-after.json`
is compared exactly with the original index baseline; the paired cache-enabled/
disabled test additionally compares 240 minutes with interruptions.

Use the graphical Godot executable directly for `run_diagnostics.py`. Run
benchmarks sequentially and after all headless functional tests have ended.
`ordinary-2` uses the `resident_homes` scenario, which actually has three active
residents (two generated and Mira); see the recorded `active_residents` field.
No benchmark changes the production save file. The save schema is unchanged.

All 35 functional sets and six final graphical runs passed. `comparison.json`
compares the preceding minute-frame-time increment to `final/`: work-30 minute
calculations 144.572/89.479 -> 63.199/52.762 ms; natural-30 maximum complete frame
161.179 -> 92.360 ms. The evening visual frame remains 185.314 ms and ordinary
three-resident maximum is 23.446 ms. These are single short probes, not a
guarantee of 100 FPS or a multi-day playtest.

```powershell
python -B artifacts/npc-work-queries-2026-10-10/run_checks.py --godot <console-exe>
python -B artifacts/npc-work-queries-2026-10-10/run_diagnostics.py --godot <GUI-exe> --output-root <new-directory> work-30 sleep-30 evening-lights-30 work-3 natural-30 ordinary-2
python -B artifacts/npc-work-queries-2026-10-10/compare.py
```
