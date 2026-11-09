---
title: 'Story 0.20: Rebalance the IRIS CI groups so every group finishes well under the 35-minute budget'
type: 'chore'
created: '2026-11-09'
status: 'done'
baseline_revision: 'cccbd78eec0497bdc08103ba82421fd3bb055dbc'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
baseline_commit: 'cccbd78eec0497bdc08103ba82421fd3bb055dbc'
---

<intent-contract>

## Intent

**Problem:** On the four measured CI runs every IRIS group's job took 31 to 41 minutes. `install-upgrade`, `shards-2`, `shards-3`, `shards-4` and `image` were cancelled at the 40-minute job limit with no failing test. The extra time is in "Run the group", where the tests have grown (DW-1025).

**Approach:** Move and split units only, using the measured unit, area and class times, so that every `iris (<group>)` job finishes in 32 minutes or less and every `shard:` unit in 900 s or less. Existing group names stay; new groups are added only as `shards-N`.

## Boundaries & Constraints

**Always:** Only moves and splits. Every unit, and every lane-a and lane-b area and test class, is in exactly one group or piece, and the suite totals before and after match (34 units, 12 lane-a areas with 218 classes, 8 lane-b areas with 132 classes, on base `85c06b56`). `IRIS_GROUPS`, the `ci.yml` matrix and `ci/iris.sh groups` agree. The ten existing check names keep reporting, and each still runs at least one unit. Pins of the old layout move to the new one in the same commit.

**Never:** No deleted, skipped, tagged-off or shortened test. No `timeout-minutes` raise and no longer deadline. No existing group renamed or removed. No product code. No edit under `release/**`. No CI rerun request beyond the two done-criterion runs.

</intent-contract>

## Code Map

- `ci/units.sh`: L26 `IRIS_GROUPS` and its comment; L29-33 the `group_units` contract comment ("lane-a runs in two pieces (DW-337) ..." is now wrong); L34-116 the header history (house style); L117-131 `group_units`; L137-177 `shard_unit_areas` (generic for every shard: `shard:lane-b@<areas>` and `shard:lane-b@rest` work today, verified with `ci/iris.sh classes lane-b@rest`); L218 `NO_WEB_BUNDLE_UNITS` (unchanged).
- `ci/iris.sh`: `cmd_group` L712-748 runs each unit in its own project, torn down on exit (two pieces of one shard in one group is safe). Read-only for this story.
- `.github/workflows/ci.yml`: L1-2 group-count comment, L111 matrix, L104 `timeout-minutes: 40` (stays).
- `docker/tests/test-ci-config.sh`: header L42-53 and L65; `units` rule L754-937 (PASS L934); `groups` rule L1034-1149; `inputs` sample pair L1299 (names the group of `live:install-script-live`; `mkinputs` copies the real `ci/units.sh`); `recipe` L1577-1617; `shard pieces` rule L1812-1863.
- `docker/tests/test-ci-changes.sh`: header L9-10 "all ten"; L146 `web_groups`. Everything else iterates `IRIS_GROUPS` or `group_units`.
- `docker/tests/test-release-sequence.sh`: L37 (header) and L2336 (comment) say production holds the overview unit; L2272 and L2340 pin it. L2935 (`live:memory-offline` in shards-4) stays true. Not under `release/**`.
- Generic, no edit: `docker/tests/test-ci-warm.sh` L410, `web/scripts/state-wait.test.mjs` L284, `ci/changes.sh`. No hit in `release/**` or `docs/`.
- Contended: Epic 35 (`cd13b1ae`) changes only `CHECK_SCRIPTS` (L12, `mcp-notices`) and `shard_areas lane-a` (L20, adds `Mcp`). No textual overlap with this story; `shard:lane-a@rest` absorbs `Mcp`.

## Tasks & Acceptance

**Execution:**
- `ci/units.sh` -- (1) L26: `IRIS_GROUPS="install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5 shards-6 shards-7 shards-8 shards-9 shards-10 shards-11"`; the comment ends "..., ten since Story 19.8's CI split, sixteen since Story 0.20's rebalance)". (2) L32-33: replace "lane-a runs in two pieces (DW-337): Checks, Install and Watch in shards, and the rest of its areas in shards-2, which also takes any area added to lane-a later." with "lane-a runs in eight pieces and lane-b in two (Story 0.20); shard:lane-a@rest in shards-2 takes any area added to lane-a later, and shard:lane-b@rest in shards-6 any area added to lane-b." (3) Append the history entry below after L116, wrapped at the file's width. (4) Replace the `group_units` cases with the table below. `NO_WEB_BUNDLE_UNITS` unchanged -- every unit still in it keeps reading no bundle, production holds only listed units, and no other group becomes all-listed.
- `.github/workflows/ci.yml` -- apply exactly the hunk under "Release-tool hunk" -- the matrix is the check names.
- `docker/tests/test-ci-config.sh` -- (a) `groups`: the wanted list (L1043-1044, L1072, PASS L1146) becomes the 16 names in order; add `mkgroups` cases `shards-6` to `shards-11`, one unit each (`live:documents`, `shard:lane-a@Docs`, `shard:lane-a@Watch`, `shard:lane-b@rest`, `live:sign-in-3`, `shard:lane-a@Fix`); add sample `g-ten` (the ten old names) with its pair `"g-ten|IRIS_GROUPS is '<the ten>', wanted"`; "ten" becomes "sixteen" at L1034, L1148 and header L50/L65. (b) `inputs` L1299: `group install-fresh` becomes `group shards-2`. (c) `recipe`: L1584 and L1592 take the 16 names; "ten groups" becomes "sixteen groups" at L1577, L1614 and L1617. (d) Extend `units` (Rule 2: extend, no new rule): its PASS line also states, computed from the tree, "the groups hold N units, L of them live scripts and S shard units" (today 38, 28, 10). (e) Extend `shard pieces`: for each shard of `SHARDS`, concatenate `shard_unit_areas` over that shard's units in the groups. Fail `[the shard units of <s> run the areas '<got>', wanted each of '<shard_areas>' once]` unless the sorted list equals the sorted `shard_areas`. The PASS line adds, computed, "(lane-a: 12 areas in 8 units, 218 classes; lane-b: 8 areas in 2 units, 132 classes)". Header bullets L42-46 name the new tallies.
- `docker/tests/test-ci-changes.sh` -- L146: `web_groups` holds the 15 groups other than production, in `IRIS_GROUPS` order; L9-10 "all ten" becomes "all sixteen" (twice).
- `docker/tests/test-release-sequence.sh` -- L2272: `group_units shards-5`, with lines "shards-5 holds live:security-overview" or "shards-5 LACKS live:security-overview"; L2340: the expected line "shards-5 holds live:security-overview". The comments at L37 and L2336 say "shards-5" in place of "production". L2935 is unchanged.

**History entry for `ci/units.sh`** (append after L116, verbatim words; no local path):
> Story 0.20 (2026-11-09; the Contest Planner's rulings on DW-1025, relayed by the orchestrator: 16 groups, each planned to about 29 minutes; every shard: unit of two or more areas at 900 s or less, a single-area unit whole; no longer timeout) added shards-6 to shards-11 and cut lane-a into eight pieces and lane-b into two. On ci runs 42634825529, 42633085173, 42603815732 and 42583599821 every iris job took 31 to 41 minutes, and install-upgrade, shards-2, image, shards-3 and shards-4 met the 40-minute timeout with no failing test. Planned from the largest unit seconds of those runs; a new piece is its areas' largest class seconds plus 423 s, the largest stack start and teardown measured; a job adds 53 s. Pieces: Agent 633, Bridge 1,167, Channel 841, Docs 1,056, Fix 1,192 and Watch 937 s, one area each; Install, Digest and Eval 890 s; lane-a's rest (Checks, Tools and Memory) 866 s, 896 s with Epic 35's Mcp area; lane-b's Contract, Core, Data and Live 899 s and its rest (Demo, Msg, Schedule and Web) 898 s. Groups, in seconds of units: install-fresh 1,659, install-upgrade 1,657, production 1,620, browser 1,632, shards 1,464, shards-2 1,636, image 1,615, shards-3 1,559, shards-4 1,644, shards-5 1,641, shards-6 1,660, shards-7 1,643, shards-8 1,570, shards-9 1,665, shards-10 1,544 and shards-11 1,673, so at most 1,726 s (28.8 minutes) a job (inference until a run measures them). live:memory-offline stays in shards-4: with live:documents beside it in shards-6, no packing keeps every group at or under 1,687 s of units (the best is 1,749 s, 30.0 minutes).

**The `group_units` table** (units in this order; `live:demo-path` first in browser):

| group | units |
|---|---|
| install-fresh | `live:install-start live:online-demo-path` |
| install-upgrade | `live:install-upgrade live:online-visitors` |
| production | `live:production live:production-restart shard:lane-a@Channel` |
| browser | `live:demo-path live:online-demo` |
| shards | `shard:lane-a@Install,Digest,Eval live:online-allowance` |
| shards-2 | `shard:lane-a@rest live:session-data live:install-script-live` |
| image | `live:storage-roundtrip live:build-inputs shard:lane-b@Contract,Core,Data,Live live:compose-start` |
| shards-3 | `live:floor live:demo-switch` |
| shards-4 | `live:sign-in-2 live:memory-offline` |
| shards-5 | `live:sign-in-3 live:security-overview live:audit` |
| shards-6 | `live:documents shard:lane-b@rest live:bundle-folder` |
| shards-7 | `shard:lane-a@Docs live:answers` |
| shards-8 | `shard:lane-a@Watch shard:lane-a@Agent` |
| shards-9 | `shard:lane-a@Bridge live:online-session` |
| shards-10 | `live:sign-in live:reminder-restart` |
| shards-11 | `shard:lane-a@Fix live:cards` |

Pieces: lane-a `rest` = Checks, Tools, Memory (+ Mcp at Epic 35's merge); lane-b `rest` = Demo, Msg, Schedule, Web. The `sign-in` trio is in three distinct groups (shards-10, shards-4, shards-5).

**Planned sums** (unit = largest measured seconds; a new piece = its areas' largest class seconds + 423 s; job = units + 53 s):

| group | units (s) | units | job s | min |
|---|---|---|---|---|
| install-fresh | install-start 1,086, online-demo-path 573 | 1,659 | 1,712 | 28.5 |
| install-upgrade | install-upgrade 1,112, online-visitors 545 | 1,657 | 1,710 | 28.5 |
| production | production 380, production-restart 399, lane-a@Channel 841 | 1,620 | 1,673 | 27.9 |
| browser | demo-path 773, online-demo 859 | 1,632 | 1,685 | 28.1 |
| shards | lane-a@Install,Digest,Eval 890, online-allowance 574 | 1,464 | 1,517 | 25.3 |
| shards-2 | lane-a@rest 866, session-data 366, install-script-live 404 | 1,636 (1,666 with Mcp) | 1,689 (1,719) | 28.1 (28.6) |
| image | storage-roundtrip 487, build-inputs 21, lane-b@Contract,Core,Data,Live 899, compose-start 208 | 1,615 | 1,668 | 27.8 |
| shards-3 | floor 909, demo-switch 650 | 1,559 | 1,612 | 26.9 |
| shards-4 | sign-in-2 1,094, memory-offline 550 | 1,644 | 1,697 | 28.3 |
| shards-5 | sign-in-3 953, security-overview 296, audit 392 | 1,641 | 1,694 | 28.2 |
| shards-6 | documents 389, lane-b@rest 898, bundle-folder 373 | 1,660 | 1,713 | 28.6 |
| shards-7 | lane-a@Docs 1,056, answers 587 | 1,643 | 1,696 | 28.3 |
| shards-8 | lane-a@Watch 937, lane-a@Agent 633 | 1,570 | 1,623 | 27.1 |
| shards-9 | lane-a@Bridge 1,167, online-session 498 | 1,665 | 1,718 | 28.6 |
| shards-10 | sign-in 915, reminder-restart 629 | 1,544 | 1,597 | 26.6 |
| shards-11 | lane-a@Fix 1,192, cards 481 | 1,673 | 1,726 | 28.8 |

Multi-area shard units: `lane-a@Install,Digest,Eval` 157+44+266 = 467 + 423 = 890; `lane-a@rest` 85+103+255 = 443 + 423 = 866 (896 with Mcp 30); `lane-b@Contract,Core,Data,Live` 17+414+34+11 = 476 + 423 = 899 (854 with lane-b's own largest overhead, 378); `lane-b@rest` 97+34+274+70 = 475 + 423 = 898 (853). Single-area units run whole (option A): Agent 633 (measured), Bridge 1,167 (measured), Channel 841 (measured), Fix 769+423 = 1,192, Docs 633+423 = 1,056, Watch 514+423 = 937. Sum of all units 25,882 s (25,912 with Mcp).

**Totals before / after** (base `85c06b56`):
- Group units: 34 / 38. Live: 28 / 28. Shard: 6 / 10.
- lane-a: 12 areas / 12 in 8 pieces; 218 classes / 218.
- lane-b: 8 areas / 8 in 2 pieces; 132 classes / 132.
- All: 350 classes / 350, each run once.
- Epic 35 adds no group unit. After its merge: 38 units; lane-a 13 areas, 222 classes (Mcp 4), in `rest`.
- The new checks compute these from the tree: scripts, area folders and class files. A unit dropped, or an area or class left out, fails them. An added script, area or class is counted, not pinned.

**Acceptance Criteria:**
- AC1. Given the new `ci/units.sh`, when `bash ci/iris.sh list` and `bash ci/iris.sh groups` run, then `IRIS_GROUPS` is the 16 names in the order above, each group prints exactly its row of the table, and `test-ci-config.sh`'s `groups` and `recipe` rules pass.
- AC2 (no weakening). Given the new layout, when `bash docker/tests/test-ci-config.sh` runs, then `units` and `shard pieces` pass. Each live script is in exactly one group, and each lane-a and lane-b area in exactly one piece, through the real `shard_unit_areas`. The 350 classes run once each. The PASS lines state 38 units (28 live, 10 shard), "lane-a: 12 areas in 8 units, 218 classes" and "lane-b: 8 areas in 2 units, 132 classes".
- AC3. Given `.github/workflows/ci.yml`, when `test-ci-config.sh`'s `matrix` rule runs, then the matrix list equals `ci/iris.sh groups`, and the file differs from base only by the hunk below.
- AC4. Given the new layout, when `bash docker/tests/test-ci-changes.sh` runs, then it passes 274 checks (268 before): each live script runs only its own group; `test-sign-in.sh` runs web, shards-10, shards-4 and shards-5; a web-only change runs the 15 groups other than production.
- AC5. Given `live:security-overview` in shards-5, when `test-release-sequence.sh overviewdoc` runs, then every group claims `docs/security-overview.md` and the pin "shards-5 holds live:security-overview" passes; `NO_WEB_BUNDLE_UNITS` still holds it.
- AC6. Given Epic 35's `shard_areas lane-a` with `Mcp`, when `shard_unit_areas lane-a@rest` is evaluated against the new `group_units`, then it answers `Checks Tools Memory Mcp`.
- AC7 (lead's done-criterion, not implement's). Given two clean `ci` runs of the same head, when the lead reads them, then every `iris (<group>)` job is at most 32 minutes, and every multi-area `shard:` unit (`lane-a@Install,Digest,Eval`, `lane-a@rest`, `lane-b@Contract,Core,Data,Live`, `lane-b@rest`) is at most 900 s.

## Release-tool hunk (for the Planner)

The exact change to `.github/workflows/ci.yml` (blob `80afa70` to `0acfe6e`); implement produces it byte for byte:

```diff
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -1,5 +1,5 @@
 # CI of Lane B (AD-22, AD-29; Story 0.7). Four jobs: `checks`, `install-macos` and `web` run on hosted runners; `iris` is a matrix of
-# ten groups that run the %UnitTest shards and the live scripts in throwaway compose projects on the self-hosted IRIS runner.
+# sixteen groups that run the %UnitTest shards and the live scripts in throwaway compose projects on the self-hosted IRIS runner.
 # The `checks` job lints install.sh and its hermetic test with ShellCheck (Story 10.1) before it runs the checks. The `install-macos` job runs
 # that hermetic test under macOS's own /bin/bash, which is bash 3.2 (Story 10.1).
 # Each `iris` job runs its group only when ci/changes.sh finds a change to that group's inputs (ci/units.sh); otherwise it skips
@@ -108,7 +108,7 @@ jobs:
     strategy:
       fail-fast: false
       matrix:
-        group: [install-fresh, install-upgrade, production, browser, shards, shards-2, image, shards-3, shards-4, shards-5]
+        group: [install-fresh, install-upgrade, production, browser, shards, shards-2, image, shards-3, shards-4, shards-5, shards-6, shards-7, shards-8, shards-9, shards-10, shards-11]
     env:
       IRIS_IMAGE: ocutalon-iris-base:2026.3.0AI.154.0
       OCUTALON_RUN_TAG: ${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.group }}
```

- New check names, exactly six: `iris (shards-6)`, `iris (shards-7)`, `iris (shards-8)`, `iris (shards-9)`, `iris (shards-10)`, `iris (shards-11)`.
- The 17 existing required check names are unchanged. No name changes or disappears. Whether the six become required is the Planner's call (a repository setting, outward).
- Test totals before and after:
  - `test-ci-config.sh`: 40 / 40 rules. Two rules are extended.
  - `test-ci-changes.sh`: 268 / 274 checks. Each new group adds one "outputs: --group" check.
  - `test-release-sequence.sh`: 26 / 26 rules. The 25 in the three batches pass, and `recut` reads no layout.
  - `test-boundaries.sh`: 10 / 10.
  - `%UnitTest`: 350 / 350 classes.
  - Live scripts: 28 / 28.

## Spec Change Log

- [ADDED 2026-11-09, Contest Planner ruling + orchestrator ruling, DW-1025] Planner APPROVED the `ci.yml` hunk ("sixteen groups" header, the 16-group matrix line, `timeout-minutes` unchanged) and the deviation (`live:memory-offline` stays in shards-4, L2935 unchanged, plus the listed moves). Merge conditions: the pushed `ci.yml` diff against feature is exactly those two lines; two clean runs on one head with every iris group at or under 32 minutes measured and every multi-area unit at or under 900 s, each group's measured maximum reported; a scan of `release/` and `ci/` for hard-coded required-check names or the group count (result: none found; `ci/changes.sh` and `ci/iris.sh` derive from `IRIS_GROUPS`). AD-22's as-built paragraph amended by the lead (ten to sixteen groups, the pieces).
- [ADDED 2026-11-09, Contest Planner ruling + orchestrator ruling, DW-1025] Re-plan after the Planner's rulings on the intent gap: option A (the 900 s cap applies to units of two or more areas; single-area units run whole), 16 groups with `shards-6` to `shards-11`, the three `test-release-sequence.sh` pins as a plain union, and DW-1032/DW-1033 ledgered for after voting (Design Notes). Status reset from blocked to draft for the re-plan.
- [ADDED 2026-11-09, Contest Planner ruling + orchestrator ruling, DW-1025] Plan stage. The Planner's binding CI capacity rulings 1-7 are recorded under Design Notes. Planning stopped at an intent gap on ruling 2's per-shard-unit cap (Auto Run Result).

## Design Notes

**Rulings [ADDED 2026-11-09, Contest Planner ruling + orchestrator ruling, DW-1025]** (they override the story block where the two differ):

1. **Scope.** Every IRIS group is in scope, not only the shards. Split `shard:lane-a@rest`, and add `shards-6`, `shards-7` and more as the measured times require. The fixed moves are:
   - `shards-6` holds `live:documents` (from shards-3) and `live:memory-offline` (from shards-4).
   - `live:security-overview` moves from production to shards-5, and the checks/overviewdoc pin moves in the same commit.
2. **Done.** Two clean runs of the same head show every IRIS job at 32 minutes or less and every `shard:` unit at 900 s or less. Balance from measured times. Plan each group's units plus its overhead to about 28-29 minutes on the slower run.
3. **No weakening.** A check proves that every unit, area and class is in exactly one group or piece, with matching totals before and after.
4. **Check names.** The ten `iris (<group>)` names stay. New names are only `iris (shards-N)`.
5. **Job limit.** There is no `timeout-minutes` raise.
6. **Reruns.** There are no reruns beyond the two done runs.
7. **Deadline.** Merged green on feature by 2026-11-10T13:00Z, as a minimal, mechanical change.

**Planner rulings on the intent gap [ADDED 2026-11-09, Contest Planner ruling + orchestrator ruling, DW-1025] (binding):**

1. **Option A.** The 900 s cap applies only to `shard:` units of two or more areas. A single-area unit runs whole (here Agent, Bridge, Channel, Docs, Fix, Watch). There is no AD-22 amendment and no change to `ci/iris.sh`. Each single-area unit sits in a group that meets the 32-minute rule on the slower run, beside units small enough to keep it there.
2. **Capacity confirmed.** 16 IRIS groups; the six new ones are exactly `shards-6` to `shards-11`, each packed to about 29 minutes, with no fuller groups. The 17 existing required check names stay.
3. **Pins.** The layout-only lines in `docker/tests/test-release-sequence.sh` are updated as a plain union. The lead lists them under `footprint_extensions`.
4. **After voting, ledgered** (not planned here): DW-1032 (option B, class parts per area; a single area over 1,400 s is a PLANNER REPORT before voting, never a split) and DW-1033 (shared stacks).
5. **Release-tool hunk** goes to the Planner at the spec gate with each suite's totals (section above).

**Architecture and links:**
- Governing ADs: AD-22 (IRIS tests "sharded by area", each shard unit in its own project; `live:demo-path` first in `browser`; `image` is the IRIS checks job, so `storage-roundtrip` and `build-inputs` stay there) and AD-29 (lanes; `ci/` and `.github/workflows/ci.yml` are Epic 0's). No AD changes. AD-22's "CI as built" paragraph lists the ten groups. The lead refreshes it at the merge gate as an as-built record with no rule change, as for every earlier rebalance. That is not an implement task.
- Consumed-by: the `iris` CI jobs (`ci/iris.sh group`), `ci/changes.sh` (`group_input_pattern`), and the release-sequence overview claims.
- Consumes: the `UNIT`, `CLASS` and `READY` lines of the four measured runs.
- Rule 2: lane-a and lane-b are cut with the existing `shard:<name>@<areas>` pieces and the computed `rest`. `shard_unit_areas` is shard-generic, so lane-b needs no `ci/iris.sh` change (verified: `ci/iris.sh classes lane-b@rest` gives 132 with no named lane-b piece; with the plan, 84 + 48). The no-weakening proof extends the `units` and `shard pieces` rules; there is no new rule.
- Integration ACs: no new service; AC4 (classifier) and AC5 (release-sequence claims) are the consumers' own checks.
- Ledger inbox for this key: none. DW-1025 is resolved by this story (the lead records it). DW-1032 and DW-1033 are cited only.

**Measured inputs** (four runs: 42634825529 `a3086148`, 42633085173 `cd13b1ae`, 42603815732 `4cb52a8d`, 42583599821 `2a45f8bc`; raw extracts under `<scratchpad>/e0s20plan/`):
- Job wall time: every group took 31-41 minutes. Cancelled at 40 minutes: install-upgrade, shards-2, image, shards-3 and shards-4. Per-job overhead (job minus units): 27-53 s; plan 53.
- Largest unit seconds:
  - shard units: lane-a@rest 2,177; lane-a@Checks,Install,Watch,Eval 1,333; lane-b 1,321; lane-a@Bridge 1,167; lane-a@Channel 841; lane-a@Agent 633.
  - live units, 909 s or more: install-upgrade 1,112, sign-in-2 1,094, install-start 1,086, sign-in-3 953, sign-in 915, floor 909.
  - live units, 773 s or less: online-demo 859, demo-path 773, demo-switch 650, reminder-restart 629, answers 587, online-allowance 574, online-demo-path 573, memory-offline 550, online-visitors 545, online-session 498, storage-roundtrip 487, cards 481.
  - live units, under 410 s: install-script-live 404, production-restart 399, audit 392, documents 389, production 380, bundle-folder 373, session-data 366, security-overview 296, compose-start 208, build-inputs 21.
- Area class seconds, largest:
  - Fix 769, Bridge 744, Docs 633, Watch 514, Channel 471, Core 414, Agent 337, Schedule 274, Eval 266, Memory 255.
  - Install 157, Tools 103, Demo 97, Checks 85, Web 70, Digest 44, Data 34, Msg 34, Mcp 30 (Epic 35), Contract 17, Live 11.
- Stack start and teardown per shard unit: 278-423 s (lane-b 313-378).
- Class counts at HEAD (`ci/iris.sh classes`):
  - lane-a: Agent 21, Bridge 39, Channel 14, Checks 9, Digest 22, Docs 17, Eval 22, Fix 19, Install 16, Memory 9, Tools 8, Watch 22.
  - lane-b: Contract 4, Core 56, Data 20, Demo 12, Live 4, Msg 3, Schedule 7, Web 26.

**Noted, not blocking.** On the slow run, three live units exceed the "about 1,000 s a unit" line: `live:install-upgrade` 1,112 s, `live:sign-in-2` 1,094 s and `live:install-start` 1,086 s. Ruling 2 caps only `shard:` units, and each fits in a group under 29 minutes. The multi-area pieces are planned at 866-899 s from worst-case figures (each area's largest class time plus the largest overhead). On one run the same pieces come to about 840-855 s (`cd13b1ae` attempt 1: lane-a rest with Mcp 465 + 379; lane-b 468 + 378 and 475 + 378). A done run that shows a multi-area unit over 900 s is a red done-criterion for the lead and the Planner. It is not a cue to split further in-stage (DW-1032).

**Decided in-stage:**
- **The `shards-6` fixed pair was not kept whole (the ruling's exception).** With both `live:documents` and `live:memory-offline` in shards-6 (939 s), that group can hold no other unit over 748 s. Fifteen units are over 843 s, and none of them may go to production (none is in `NO_WEB_BUNDLE_UNITS`). So 15 such units would share 14 groups, and two of them together are at least 1,700 s. An exact packing (MILP, every constraint below) gives at best 1,749 s of units, 30.0 minutes with overhead, over the 29-minute target. Alternative taken: `live:documents` moves to shards-6, and `live:memory-offline` stays in shards-4 (1,644 s, beside sign-in-2 once Channel leaves). That also leaves the L2935 pin true. `live:security-overview` moves to shards-5 as ruled.
- **Packing method.** An exact MILP over the 38 units minimised the number of units that change group (21), then the largest group (1,673 s). Constraints:
  - each group at or under 1,687 s of units (29 minutes less 53 s);
  - production only `NO_WEB_BUNDLE_UNITS` units;
  - install-fresh holds install-start, install-upgrade holds install-upgrade, and demo-path is first in browser;
  - image keeps storage-roundtrip and build-inputs (AD-22, the IRIS checks job);
  - security-overview is in shards-5;
  - the sign-in trio is in three groups;
  - every group has at least one unit.
- **What the constraints forced.** `shard:lane-a@Channel` (841 s) moves to production: it is the only `NO_WEB_BUNDLE_UNITS` unit large enough to keep the other 15 groups under the line. `shard:lane-a@Agent` leaves production but stays in `NO_WEB_BUNDLE_UNITS` (it still reads no bundle). Bridge cannot stay in shards-5 beside security-overview (no packing fits), so it moves to shards-9. `live:install-script-live` cannot stay in install-fresh (the best packing would then be 1,700 s), so the `inputs` sample at L1299 follows it to shards-2.
- **Piece cuts.** lane-a's small areas (Checks 85, Eval 266, Install 157, Digest 44, Memory 255, Tools 103; Mcp 30 later) fit two pieces of at most 477 s of classes each (900 less 423) in only one way: {Install, Digest, Eval} and {Checks, Tools, Memory} + Mcp. Watch (514) cannot pair with any area under the cap, so it runs alone. lane-b fits two pieces only as {Contract, Core, Data, Live} and the rest. Piece names list areas in `shard_areas` order.
- `test-release-sequence.sh`: besides the two pinning lines (L2272, L2340), the two comments that state the same fact (L37, L2336) are corrected (Rule 14). L2935 needs no change. The dispatch's "three lines" become four comment-or-pin lines, all layout-only.
- **"34 units" in the intent.** Base has 34 group units: 28 live units and 6 shard units. The approach and ruling 1 require splits, so the shard-unit count must change (6 to 10). The only reading that fits is that the tests still match: the same 28 live scripts, 12 + 8 areas and 218 + 132 classes, each run once. So the checks pin those derived totals, and the unit count goes from 34 to 38.
- `NO_WEB_BUNDLE_UNITS` is unchanged. Production holds only listed units, and no other group becomes all-listed, so `web_groups` is every group but production.
- **Dry run (planning only, scratch clone, not the worktree).** Applied: the table, the hunk and the pin edits above, without the (d)/(e) PASS-line tallies. `test-ci-config.sh` passed 40/40 in 65 s. `test-ci-changes.sh` passed 274 in 32 s. `test-release-sequence.sh overviewdoc static` passed. With `shard:lane-b@rest` dropped from shards-6, `units` and `shard pieces` went red.

## Verification

**Commands** (from the worktree root; each one call, at most about 150 s; local times measured on base):
- (loop) `bash docker/tests/test-ci-config.sh` -- expected: `test-ci-config: all rules passed`, 40 PASS lines (about 65 s).
  - The `units` PASS line names 38 units, 28 live and 10 shard.
  - The `shard pieces` PASS line names 350 classes, 10 pieces, "lane-a: 12 areas in 8 units, 218 classes" and "lane-b: 8 areas in 2 units, 132 classes".
- (loop) `bash docker/tests/test-ci-changes.sh` -- expected: `test-ci-changes: all checks passed`, 274 PASS (about 32 s).
- (loop) `bash -c 'diff <(bash ci/iris.sh groups) <(sed -n "s/^ *group: \[\(.*\)\]\$/\1/p" .github/workflows/ci.yml | tr -d " " | tr "," "\n") && bash ci/iris.sh groups | wc -l'` -- expected: no diff, `16`.
- (once) `bash docker/tests/test-release-sequence.sh libs refusals cut image overview overviewunit overviewdrift` -- expected: `PASS all rules` (about 49 s).
- (once) `bash docker/tests/test-release-sequence.sh overviewdoc ipmcheck push record hands resume notes gate` -- expected: `PASS all rules` (about 124 s).
- (once) `bash docker/tests/test-release-sequence.sh secret first word pushes ipm ipmfail ipmwait ipmnet ipmlib static` -- expected: `PASS all rules` (about 75 s).
- (once) `bash docker/tests/test-boundaries.sh` -- expected: `test-boundaries: all rules passed` (about 7 s).
- (once) `bash -c 'for s in lane-a lane-b; do echo "$s $(bash ci/iris.sh classes $s | wc -l)"; done; . ci/units.sh; for g in $IRIS_GROUPS; do group_units $g; done | tr " " "\n" | grep -c .'` -- expected: `lane-a 218`, `lane-b 132`, `38`.
- (once) `bash -c '. ci/units.sh; shard_areas() { case $1 in lane-a) echo "Agent Bridge Checks Fix Install Tools Digest Watch Eval Channel Memory Docs Mcp" ;; lane-b) echo "Contract Core Data Demo Live Msg Schedule Web" ;; *) return 1 ;; esac; }; shard_unit_areas lane-a@rest'` -- expected: `Checks Tools Memory Mcp` (AC6).
- (once) `git diff --stat -- .github/workflows/ci.yml` and `git diff -- .github/workflows/ci.yml` -- expected: exactly the Release-tool hunk (AC3).
- (once) `LC_ALL=C grep -n '[^[:print:][:space:]]' ci/units.sh docker/tests/test-ci-config.sh docker/tests/test-ci-changes.sh; grep -nE '/Users/|/private/|/home/' ci/units.sh .github/workflows/ci.yml` -- expected: no output.

**Mutations** (apply, observe red, revert, confirm `git status --short` and `git diff --stat` unchanged):
- AC1 mutation: drop `shards-11` from `IRIS_GROUPS` → `test-ci-config.sh` `groups` red ("IRIS_GROUPS is '...', wanted") and `matrix` red.
  - mutation: `shards-11` dropped from `IRIS_GROUPS` in `ci/units.sh` -> `test-ci-config.sh` `groups`, `matrix`, `units`, `demo-path` and `recipe` red (observed 2026-11-09; reverted, `ci/units.sh` byte-identical).
- AC2 mutation: drop `live:documents` from `shards-6` in `group_units` → `units` red ("docker/tests/test-documents.sh: the script is in 0 of ..."); and drop `shard:lane-b@rest` → `units` and `shard pieces` red (observed in the dry run).
  - mutation: `live:documents` dropped from `shards-6` in `group_units` -> `test-ci-config.sh` `units` red ("docker/tests/test-documents.sh: the script is in 0 of ...").
  - mutation: `shard:lane-b@rest` dropped from `shards-6` in `group_units` -> `test-ci-config.sh` `units` red ("4 area(s) of the shard lane-b are in no piece, and no piece is rest") and `shard pieces` red ("the shard units of lane-b run the areas 'Contract Core Data Live', wanted each of 'Contract Core Data Demo Live Msg Schedule Web' once").
- AC3 mutation: drop `shards-11` from the `ci.yml` matrix only → `test-ci-config.sh` `matrix` red.
  - mutation: `shards-11` dropped from the `ci.yml` matrix only -> `test-ci-config.sh` `matrix` red (reverted, `ci.yml` byte-identical).
- AC4 mutation: add `shard:lane-a@Watch` to `NO_WEB_BUNDLE_UNITS` (shards-8 becomes all-listed) → `test-ci-changes.sh` red on "web/** runs web and every group but production".
  - mutation: `shard:lane-a@Watch` added to `NO_WEB_BUNDLE_UNITS` -> `test-ci-changes.sh` red on "classifier: web/** runs web and every group but production" (shards-8 left out of the web groups) and on "outputs: --group shards-8".
- AC5 mutation: move `live:security-overview` from shards-5 to shards-10 → `test-release-sequence.sh overviewdoc` red.
  - mutation: `live:security-overview` moved from shards-5 to shards-10 in `group_units` -> `test-release-sequence.sh overviewdoc` red (the expected line "shards-5 holds live:security-overview" fails).
- AC6 mutation: name `shard:lane-a@Checks,Tools,Memory` in place of `shard:lane-a@rest` → the AC6 command prints `Mcp` alone, not `Checks Tools Memory Mcp`. Once Epic 35's area exists, `units` would also report "1 area(s) of the shard lane-a are in no piece, and no piece is rest".
  - mutation: `shard:lane-a@Checks,Tools,Memory` named in place of `shard:lane-a@rest` -> the AC6 command prints `Mcp` alone, not `Checks Tools Memory Mcp` (not a test: the AC6 command itself goes red).
- AC7: none in-stage. CI's two clean runs are the lead's done-criterion.

Shared surfaces: `IRIS_GROUPS`; the `ci.yml` matrix and the `iris (<group>)` check names; `group_units` and the output of `ci/iris.sh list` and `groups`; the `groups`, `recipe`, `inputs` (L1299), `units` and `shard pieces` pins in `docker/tests/test-ci-config.sh`; `web_groups` and "all ten" in `docker/tests/test-ci-changes.sh`; the overview placement pin in `docker/tests/test-release-sequence.sh`. `NO_WEB_BUNDLE_UNITS` is unchanged.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Review Triage Log

### 2026-11-09 - Review pass
- verdicts: 19 findings - high 0, medium 0, low 13, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: tests pin where `live:security-overview` (shards-5) and `live:install-script-live` (shards-2) sit, against the `groups` rule's "no placement pin" stance - the spec orders both pins (Tasks: test-release-sequence L2272/L2340; test-ci-config `inputs` L1299); a future rebalance edits them in its own commit, as this one does.
  - `[low]` `[reject]` Blind: the unit tally on `PASS units` and `PASS shard pieces` is printed, not compared - spec task (d)/(e) says the PASS line "states, computed from the tree"; a dropped unit, area or class already fails the script-in-one-group, area-once and class-once checks, and "an added script, area or class is counted, not pinned" (Tasks). Pinning the numbers would contradict the spec.
  - `[false]` `[reject]` Blind: no runner-capacity note for 16 jobs - Planner ruling 2 confirmed the capacity; a capacity note in `ci/units.sh` is not part of the story and runner capacity is an owner action (REL-4).
  - `[false]` `[reject]` Blind: group timings exist only as prose, no re-check - AC7 is the lead's done-criterion on two CI runs, labelled inference in the spec's words; no in-stage check can measure them.
  - `[low]` `[reject]` Blind: the 1,687 s threshold has no stated source - the history entry is the spec's verbatim text (Tasks); 1,687 = 29 minutes less the 53 s job overhead is in the spec's Packing method. Cosmetic.
  - `[low]` `[reject]` Blind: `shards-N` names no longer say what a group holds - the intent fixes new names to `shards-N` (Approach, Ruling 4). Cosmetic.
  - `[false]` `[reject]` Edge: the `ci.yml` line-2 comment edit is a second hunk beyond the matrix - the Release-tool hunk contains both hunks; `git diff` matches it byte for byte (blob 80afa70 to 0acfe6e).
  - `[low]` `[reject]` Edge: `bash ci/iris.sh classes` failure swallowed inside `piece_tally` and shown as 0 classes - the same call per shard is made earlier in the rule (`piece_all`) and fails the rule there; a guard here adds code for a state the rule already fails on.
  - `[low]` `[reject]` Edge: `i-reads-declared-example` names `shards-2` - same as the first row, spec-ordered.
  - `[low]` `[reject]` Verification-gap: the `PASS units` / `piece_tally` tallies cannot fail - same as the second row; the failing paths (`units` "in 0 of", `shard pieces` area mismatch) have recorded mutations.
  - `[low]` `[reject]` Verification-gap: AC6 has no in-suite pinning test - the spec defines AC6's check as the stubbed-`shard_areas` command in `## Verification`, with its mutation line; once Epic 35's area exists the `units` rule ("without rest cover every area", "no piece is rest") fails on a non-`rest` cut. An in-suite fixture is more than a direct correction.
  - `[low]` `[reject]` Verification-gap: the sign-in trio's three distinct groups is not pinned by any test - the spec leaves placement of whole units unpinned for rebalances (`groups` rule note); `test-ci-changes.sh` derives its expectation from the layout by design.
  - `[false]` `[reject]` Verification-gap: nothing locally verifies timing - AC7 is the CI done-criterion by design; AC1-AC6 are structural.
  - `[false]` `[reject]` Verification-gap (Other): `test-ci-warm.sh` patterns may not match the new `shards` row - the patterns (`^UNIT-PROCESS shard lane-a@[A-Za-z,]+`, `^UNIT-PROCESS live [a-z-]+`) match `shard:lane-a@Install,Digest,Eval live:online-allowance`, as the finding itself concludes.
  - `[false]` `[reject]` Intent: reading C ("34 units" must stay 34) - Design Notes "34 units in the intent" decided the base count is 34 (28 live, 6 shard) and the totals that must match are scripts, areas and classes: 28 / 12 + 8 / 350 hold.
  - `[low]` `[reject]` Intent: single-area units (Fix 1,192, Bridge 1,167, Docs 1,056, Watch 937 s) exceed 900 s - Planner ruling 1 (option A) caps only units of two or more areas; recorded in the Spec Change Log; DW-1032 ledgered. Not an intent gap.
  - `[low]` `[reject]` Intent: the 32-minute target is met only on paper - AC7 is the lead's done-criterion on two CI runs, outside implement.
  - `[low]` `[reject]` Intent: check names pinned only through the matrix; skipped groups still report - pre-existing behaviour of `ci/changes.sh`, untouched; the matrix equals `ci/iris.sh groups` (AC3).
  - `[low]` `[reject]` Intent: the spec title says 35 minutes, the intent 32, the comment about 29 - 35 is REL-4's budget, 32 the done-criterion, 29 the planning target (rulings 2); descriptive only.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Rebalanced the IRIS CI groups by moves and splits only: 16 groups (`shards-6` to `shards-11` added), lane-a in 8 pieces and lane-b in 2, 38 group units (28 live, 10 shard), 12 + 8 areas and 218 + 132 classes each run once. `ci.yml` carries exactly the Release-tool hunk.

**Files changed.**
- `ci/units.sh`: `IRIS_GROUPS`, `group_units` table, contract comment and the Story 0.20 history entry.
- `.github/workflows/ci.yml`: the Release-tool hunk only (header count, matrix).
- `docker/tests/test-ci-config.sh`: `groups`, `inputs`, `recipe` pins to 16 groups; `units` tally; `shard pieces` area-once check (`piece_shard_rows`) and tally.
- `docker/tests/test-ci-changes.sh`: `web_groups` (15 groups) and "all sixteen".
- `docker/tests/test-release-sequence.sh`: the four named lines (L37, L2272, L2336, L2340) now name shards-5.
- This spec: the `mutation:` lines under `## Verification`.

**Review.** 19 findings from four layers: 0 patches, 0 deferred, 19 rejected with the reasons in the Review Triage Log (spec-ordered pins, tallies informational by spec, AC7 is the CI done-criterion, Planner ruling 1 for single-area units). Follow-up review recommended: false (no patch).

**Verification.** `test-ci-config.sh` 40 PASS (units: 38 units, 28 live, 10 shard; shard pieces: 350 classes, lane-a 12 areas in 8 units 218 classes, lane-b 8 areas in 2 units 132 classes); `test-ci-changes.sh` 274 PASS; groups vs matrix no diff, 16; class and unit counts 218 / 132 / 38; AC6 prints `Checks Tools Memory Mcp`; `test-boundaries.sh` passed; no non-ASCII bytes and no local paths in the touched sources; `git diff` of `ci.yml` is the hunk (blob 80afa70 to 0acfe6e); no change under `release/**`, to `ci/iris.sh` or to any `timeout-minutes`. `test-release-sequence.sh` ran once in its three batches (implement stage), all PASS all rules. Mutations for AC1-AC5 observed red and reverted (lines in `## Verification`); AC6's is the command itself.

**Residual risks.** Group times are planning figures (inference) until AC7's two clean CI runs; Epic 35's `Mcp` area is checked only by the AC6 command until it merges; whether the six new check names become required is the Planner's call.
