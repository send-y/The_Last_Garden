# Final food review and resolution

Read-only review of the working-tree food diff against `4310641`, 11 October.
Reviewer did not run Godot, stage files or change code.

- Important/P2: duplicate IDs could leave an earlier food profile cached after
  a later record without food or with malformed food replaced the definition.
  Confirmed from source. Two regression cases failed before the fix and passed
  after it; schema validation now rejects the catalog before any item is cached.
- Minor: prove the reverse direction of independent seed capability. Addressed
  in this same pass: a fixture removes carrot's food property, eating refuses
  without state changes, and studied extraction still consumes the product and
  commits one seed RNG draw. No production behavior changed for this addition.

No second review was requested. Final correctness-suite results are recorded
in `checks.json`. Review does not establish FPS, visual quality or balance.

Implementation decisions recorded during execution:

1. Current checkout retained because the author requested a baseline commit
   followed by a readable diff. Cost: future unrelated edits require careful staging.
2. Item/food schema 4/1, legacy 3 accepted only without food. Cost: unsupported
   future fields require an explicit schema/consumer change.
3. Correctness tests resumed under the reviewed RED/GREEN plan; FPS work stays
   paused. Cost: no performance improvement claim can follow from this package.
4. Actions run as a Node scene so the inventory UI can resolve Session autoload.
   Cost: fixture must isolate Session and physical saves explicitly.
5. Unused UI CropCatalog removed after switching to item food. Cost: any future
   UI use of crop data must add its actual dependency.
6. Existing farming UI test reopens its selected item after viewport refresh;
   the old failure also reproduced on baseline. Cost: this checks a visible
   reopened menu; it does not assert preservation of an open menu across resize.
7. Duplicate IDs reject the entire item catalog before cache population.
   Cost: malformed content requires correction before the catalog can load.
8. The final suite ran directly and its command/results were recorded without
   rerunning only for a completion wrapper. Cost: the ledger completion is
   recorded manually rather than by that wrapper; logs/JSON remain the evidence.

Deferred design debt: `FirstNightContent` rename; tools are the next separate
result. Spoilage, quality and resident taste are not implemented in this package.
