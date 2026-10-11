# Item food properties, 11 October 2026

Baseline local commit: `431064131498a7a5eb4c7df45bfd2a13f06d6931`.
This directory records correctness checks only; no FPS/stress probes were run.
The new feature remains uncommitted above the baseline; no push was performed.

`properties-red.log`: three missing APIs before implementation (test setup
constructor error corrected first). `properties-green.log`: 0 failures.
`actions-red.log`: 15 missing-feature assertions before consumer changes,
after test scene/API/host setup errors were fixed. `actions-green.log`: 0 failures.

`run_checks.py` runs 14 targeted suites, two workers, Godot 4.7 Mono headless.
`checks.json` contains exits, errors and summaries; `save-check.json` hashes
existing default game save files before and after. Tests use in-memory JSON
roundtrips or explicitly named test saves; temporary food catalogs use the
process ID and are removed after loading.

The initial suite passed 13/14 and preserved game saves. The existing farming
UI test inspected a hidden context popup after resize. The same failure is
recorded on baseline 4310641 (`baseline-farming-ui.log`) in an independently
archived project. `farming-viewport-diagnostic.log` confirms `visible=false`;
`farming-viewport-fixed.log` passes after reopening the same selected item before
checking visibility/bounds. The diagnostic and baseline logs retain the failure;
the per-suite logs are replaced by the latest complete run.

Final review found duplicate item IDs could retain the first food profile.
`duplicate-id-red.log` records two regression failures before the fix;
`duplicate-id-green.log` records zero afterward. Duplicate IDs now reject the
catalog before caches are populated. `independent-seeds-green.log` also proves
that a crop product without food remains extractable but cannot be eaten.

Final run after the review fix: 14/14 passed, no ERROR/SCRIPT ERROR, default
game save unchanged. Legacy migration tests emit their expected warnings.
Review findings and execution decisions: [review-resolution.md](review-resolution.md).

Reproduce correctness checks (no measurements):

```powershell
python -B artifacts/item-food-2026-10-11/run_checks.py
```

The proof-only `test:ration` 17/0 lives in
`game/tests/fixtures/item_food_additions.json`; the production item catalog never
contains that ID. Existing nutrition is checked against literal values in the
test, not copied from another catalog. Author guide:
[`items.md`](../../docs/content-authoring/items.md).
