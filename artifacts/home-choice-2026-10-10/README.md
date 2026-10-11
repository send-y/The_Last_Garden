# Home/work query and inventory costs, 10 October 2026

Paused at the user's request on 11 October. No new tests or measurements were
started when documenting the checkpoint. See
[`frame-stalls-checkpoint-2026-10-11.md`](../../docs/implementation/frame-stalls-checkpoint-2026-10-11.md).
The current `complete` version is not a completed performance objective:
its 90-second natural window has one frame >=100 ms (114.741 ms maximum),
and its completed 180-second window has 29 (255.418 ms maximum), including
three full structure refreshes. Evening natural time has none (90.976 ms),
with all 30 torches actually enabled. The subsequent ordinary case has only
an initial idle stage, no reported engine errors and exit 0, but insufficient
stages: its `passed: false` is retained. The cause is unknown. The runner did
not execute the subsequent evening-lights case. Do not analyze this series
as though every requested case completed.

This increment targets maximum minute frames without changing NPC decisions,
minute cadence, authority, saved schema or introducing threads.

Changes:
- One synchronous placement-search context per furniture choice, rather than
  rebuilding room/furniture/blueprint footprints for every rejected candidate.
- Matching completed home structures uses the existing cell index.
- Effective player inventory counts visit physical instances once.
- Unchanged counts/layout/content skip repeated backpack packing on NPC events.
- Each housing rebuild derives room cell sets once; room furniture validation
  and furniture search omit floors before copying local structure records.
- Catalog membership, labels/count/ordered IDs and small building queries avoid
  copying complete definitions. Identity-only housing/work/observe loops use IDs.
- A synchronous seat search reads other NPC positions once for every candidate.
  Every following query reads current positions again; no cross-query occupancy
  cache is used. NPC seat candidates outside the useful radius skip pathfinding; the
  original approach-distance limit and preference score are unchanged.
- Storage icon textures are retained by resource path between redraws.
- Pure goal-choice/completion/expansion notices preserve equipment validation but
  skip scanning player inventory. All ordinary commands keep synchronization.
- Sleep approaches retain one current query per character. Navigator/catalog
  identity, navigation/room revision, actor cell, player blocker and exact
  place/footprint inputs invalidate it. Housing validity/needs/ownership stay live.

Baseline source snapshots are kept here for reviewing exactly this increment
inside the larger uncommitted worktree. `authority_probe.gd` checks 240 seeded
placement choices plus RNG state (five rooms/obstruction/preference variants)
and 240 complete authoritative minute states with hunger and permissions/reserves
changing. All after snapshots, including the latest `authority-final.json`, match
`authority-before.json`. This is a deterministic contract, not a gameplay test.
`meal-authority-final.json` additionally checks 66 minutes with 30 residents,
replenishing stock as the Lab does, against both the original seat query and
uncached housing approaches and the original inventory-sync-on-every-notice
behavior. Complete authority matched, including 17 observed
meal/furniture user-minutes.

Cost regressions were observed failing before each corresponding fix. The new
tests cover repeated packing, actual owner/location counts, room sets and NPC
catalog copying; existing layout/housing/index tests gained floor-query checks.
`structure-index-test-invalid-array.log` records a mistake in the added test:
an untyped array passed to a dynamically called typed method. Its test process
was stopped, argument fixed, and the test rerun successfully. `checks.json`
records 42 functional sets passing before the final housing-approach cache,
plus two new approach/notice cost tests. Six rule sets were rerun after the
approach cache; 16 affected inventory, housing, NPC and UI sets were rerun after
the notice change. After the last seat-context/catalog changes, 15 affected sets were rerun.
The accumulated checks file has 45 passing sets; it does not
mean all 45 were rerun after every individual edit. Static structure-write protection
and its negative regression also passed.

Graphical diagnostics run sequentially, after all Godot functional test
processes have exited. The existing editor is left alone. Godot 4.7 Mono,
1280x720, Compatibility/OpenGL, VSync off and uncapped FPS; diagnostic spans
enabled, expensive structure-index verification disabled. Native CPU sampling
uses the exact primary thread ID. Sampler handshake time is outside Godot's
reported calculation time; native CPU boundary wall time is not frame time.

`layout-probe` isolates the first placement/matching-structure changes;
`room-inventory-probe` adds room sets and packing synchronization, before the
one-pass counting and floor filtering. `final` is the intermediate version that
first exposed 23 frames >=100 ms (maximum 320.789 ms) in the longer window.
`verified` adds the building queries, seat filter and retained storage textures:
its long window still had 13 such frames (129.758 ms). `housing-approach` is the
penultimate source version (one frame >=100 ms in both long/evening windows).
`final-verified` adds the pure-notice optimization: its 90-second window still
had two frames >=100 ms (112.618 ms). Its extended run was explicitly stopped
once the prior completed measurement proved another fix was needed; that
incomplete run is not evidence of performance or an engine failure.
`complete` adds occupancy contexts and primitive catalog queries (including
identity-only minute loops), and is the
source version at this pause, with separate 90/180-second natural stress windows. Directories are preserved so improved short probes cannot
hide longer failures. Each comparison is generated explicitly against its named
preceding directory, without silently overwriting original raw measurements.
Separate minute calculation rows exclude deferred rendering; natural windows
include both. New frame reports include counts >=100 ms and p99. Ordinary
`ordinary-2` actually runs with three active NPCs. The 90-second natural stress
window also exercises later work changes beyond the previous 12-second probe.

```powershell
python -B artifacts/home-choice-2026-10-10/run_checks.py --godot <console-exe>
python -B artifacts/home-choice-2026-10-10/run_diagnostics.py --godot <GUI-exe> --output-root <fresh-directory> evening-lights-30 work-30 natural-30 ordinary-2 evening-natural-30 natural-long-30 natural-extended-30
python -B artifacts/home-choice-2026-10-10/analyze.py --directory complete --before-directory final
```
