# SDD ledger ? plan: docs/superpowers/plans/2026-10-11-item-tool-variants.md
Pre-flight: Tasks 1 -> 2/3/4/5 share prepared capability API and injected content; consistent. Task 3 -> 5 shares capacity/state. Task 4 -> 5 shares actual carried instance.
Ruling: work on existing codex/storage-zones checkout, preserve food package; local commits at Tasks 5 and 6 only, no push/FPS.
Task 1 Ruling: source rejections are validation errors stored in arrays and logged with push_warning; invalid entries are disabled. Negative-hook tests can prove errors without fatal Godot log failures. No relaxation of acceptance.
Task 1: complete (base 4310641, changes uncommitted per plan; tests: checks.py task1 ? all 5 passed, including run_tests; save hash unchanged). Ruling: already-run final checks recorded directly instead of task-done rerun; avoid duplicate long checks.
Task 2/3: core GREEN ? water-fix.json: resource+water passed; tasks2-3.json: farming_rules, food_actions, run_tests passed after selected Dictionary type fix. world_editing passed before water changes; dependency rerun before package commit. Task 2 Session/main facade completed; UI verification next.
Task 4: complete ? task4-fixed.json NPC integration+practical work passed; task4.json query/material cache regressions passed. Safe storage validation uses existing floor/zone/blocking queries.
Task 5 Ruling: include inventory_grid/storage_panel so variant drag footprints use injected content; preserve held item over unchanged refresh. Old held-item integration and new test both RED on cursor reset. Otherwise variant rotation/selection remains broken.
Task 2: complete - precommit.json resource+world editing+run_tests and real Main hold/UI tests passed.
Task 3: complete - precommit.json water+farming+food+run_tests passed.
Task 5: all 16 precommit checks PASS; graphic pixels inspected. Source factory checks moved to actual public new-game constructor (bare create_new_state deliberately has no pantry). Local game commit follows.
Task 5: complete (commit 8932d48568bf95b2c78fd81d2b1f49e11baf9bd7; precommit.json 16/16, save unchanged).
Task 6 Ruling: two older UI assertions sampled before a deferred world refresh already present in 4310641; tests now wait for frames and check real depletion/physics and actual borrowed grip. Preserve frame batching; pre-fix failures in final-cross logs. If diagnosis wrong, real-authority assertions still fail.
Task 6: complete (commit 725464b53036dd25d9bc05d75eceac60c63ece92; final-results.json 23/23, assets/JSON/links checked, save unchanged, no FPS/push).

Final: reviewer gpt-6-astra/high read-only 4310641..725464b: no Critical, two Important, no Minor. Important source execution and historical load loss reproduced (review-red-confirmed:12 failures); fixes GREEN. Boundary extension:4 failures -> GREEN.
Final: Ruling: keep retired crop definitions for load/render, freeze inactive beds and block new output - preserve saved identity without forbidden issuance - cost: bed inactive until source restored.
Final: Ruling: cancel inactive crafting projects and refund committed known items once - avoid losing paid inputs - cost: crafting progress resets.
Final: Ruling: FPS/stress excluded - honor paused measurements - cost: performance remains unmeasured.
Final: Ruling: new jobs/preferences/durability/quality/content excluded - finish supported variants only - cost: separate contracts needed.
Final: Ruling: art quality/gameplay feel excluded - pixel tests prove rendering only - cost: human playtest still needed.
Final: Ruling: existing crafting-label catalog unchanged - no concrete held/capacity defect found - cost: future injected content labels can diverge.
Final: fixed both Important findings in one pass; full review-final-complete.json 25/25 including graphical, save hash unchanged. No deferred Minor findings. No second review or FPS/push.
Final: code and evidence committed c140844c5f9fbd7ed8cc0c66b785f5de49ae6d0c; existing branch kept per user local-only authorization.
Final: Ruling: automatic approval review rejected scratch-directory cleanup; leave ignored plan workspace intact, archive ledger instead - cost: temporary files remain.
