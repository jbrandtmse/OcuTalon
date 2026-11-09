---
title: 'Story 0.20: Rebalance the IRIS CI groups so every group finishes well under the 35-minute budget'
type: 'chore'
created: '2026-11-09'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
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

- `ci/units.sh`:
  - L26-27 `IRIS_GROUPS` (ten groups).
  - L29-116: the header history in the house style.
  - L117-131 `group_units`.
  - L137-177 `shard_unit_areas`: pieces are whole areas, `rest` is computed from the named pieces, and an area named twice returns 1.
  - L218 `NO_WEB_BUNDLE_UNITS`.
  - L20-21 `shard_areas`: lane-a has 12 areas and lane-b has 8.
- `ci/iris.sh`:
  - L712-748 `cmd_group` runs each unit as `bash ci/iris.sh <kind> <arg>` and passes no `--part`.
  - L14-19 and L353-429: `shard --part k/n` (contiguous class parts by count) exists for manual runs only.
  - L832 `groups`.
- `.github/workflows/ci.yml`:
  - L111 is the matrix `group:` list.
  - L1-2 is the "matrix of ten groups" comment.
  - L104 is `timeout-minutes: 40`, which stays.
- `docker/tests/test-ci-config.sh`:
  - L50-65 header.
  - L788-826: the shard-pieces rule (whole areas, each area once).
  - L1034-1148: the `groups` rule pins the ten names in order, with samples `g-seven`, `g-eight` and `g-nine`.
  - L1577-1617: `recipe` pins `groups` output and the `unknown group` list.
  - L1827-1849: piece-unit samples.
- `docker/tests/test-ci-changes.sh`:
  - L9-10 "all ten".
  - L146 `web_groups`: every group but production.
  - L177-198: each live script runs exactly its own group, and the sign-in trio runs three distinct groups.
- `docker/tests/test-release-sequence.sh`:
  - L2262-2274 `ovw_ci_claims` and L2336-2341: the overviewdoc pin "production holds live:security-overview" plus `NO_WEB_BUNDLE_UNITS`.
  - L2935: "live:memory-offline is a unit of shards-4".
  - This is a `docker/tests` check, not under `release/**`.
- `docker/tests/test-ci-warm.sh` L410 and `web/scripts/state-wait.test.mjs` L284 iterate `IRIS_GROUPS` generically. No layout pin.
- No hit in `release/**`.
- Contended: Epic 35 (`cd13b1ae`) adds the lane-a area `Mcp` (4 classes, 28-30 s) and the check `mcp-notices` to `ci/units.sh`. Whatever piece is `rest` takes `Mcp` at merge.

## Tasks & Acceptance

Pending the ruling below: the membership, piece names and release-tool hunk depend on it. No task is planned around the gap.

## Spec Change Log

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

**Architecture and links:**
- Governing ADs: AD-22 (its Rule says IRIS tests run "sharded by area", and the as-built CI runs pieces of whole areas) and AD-29 (lanes). `docs/` and `ci/` are Epic 0's to edit.
- Consumed-by: the `iris` CI jobs and `ci/changes.sh` (`group_input_pattern`).
- Consumes: the unit, area and class times that `ci/iris.sh` prints (`UNIT`, `CLASS` and `READY` lines).
- Rule 2: lane-a is split with the existing `shard:<name>@<areas>` pieces and the computed `rest`.
- DW-1025 is the problem this story resolves; the lead records its resolution.

**Measured: job wall time per group** (attempt in brackets; "red" is a flake per the dispatch, "cancelled" is the 40-minute limit):

| group | 42634825529 a3086148 | 42633085173 cd13b1ae | 42603815732 4cb52a8d | 42583599821 2a45f8bc |
|---|---|---|---|---|
| install-fresh | 38:11 (a1) | 39:23 red (a1)<br>39:37 (a2) | 34:16 (a1) | 31:44 (a1) |
| install-upgrade | 40:41 cancelled (a1) | 40:23 cancelled (a1)<br>40:30 cancelled (a2)<br>39:07 (a3) | 32:28 (a1) | 33:41 (a1) |
| production | 37:59 red (a1) | 38:01 (a1) | 39:18 (a1) | 36:38 (a1) |
| browser | 33:28 red (a1)<br>36:22 (a2) | 37:59 (a1) | 33:58 (a1) | 34:02 (a1) |
| shards | 39:09 (a1) | 36:58 (a1) | 37:35 (a1) | 38:08 (a1) |
| shards-2 | 41:20 cancelled (a1) | 41:28 cancelled (a1)<br>40:30 cancelled (a2)<br>41:11 cancelled (a3) | 38:32 red (a1)<br>38:59 (a2) | 39:20 (a1) |
| image | 35:03 (a1) | 40:28 cancelled (a1)<br>39:17 (a2) | 38:18 (a1) | 35:04 (a1) |
| shards-3 | 38:55 (a1) | 41:28 cancelled (a1)<br>41:21 cancelled (a2)<br>41:19 cancelled (a3) | 41:23 cancelled (a1)<br>41:21 cancelled (a2)<br>41:20 cancelled (a3) | 39:25 (a1) |
| shards-4 | 38:56 (a1) | 39:23 red (a1)<br>40:33 cancelled (a2)<br>40:21 cancelled (a3) | 40:26 cancelled (a1)<br>40:28 cancelled (a2)<br>40:28 cancelled (a3) | 39:06 (a1) |
| shards-5 | 34:05 (a1) | 36:11 (a1) | 30:38 (a1) | 31:54 (a1) |

**Measured: per-group overhead.** The overhead is the job time minus the sum of its units: checkout, `What changed`, the web bundle build, preflight and teardown. On every finished job it was 27-53 s; plan 53 s per group.

**Measured: unit seconds** (the maximum of the units that finished; "cut" means the unit was cancelled mid-run):

| unit (group today) | max s | run of max | a3086148 | cd13b1ae | 4cb52a8d | 2a45f8bc |
|---|---|---|---|---|---|---|
| shard:lane-a@rest (shards-2) | 2177 | cd13b1ae | 2110 | 2177 | 1950 | 1955 |
| shard:lane-a@Checks,Install,Watch,Eval (shards) | 1333 | a3086148 | 1333 | 1248 | 1297 | 1312 |
| shard:lane-b (image) | 1321 | cd13b1ae | 1225 | 1321 | 1262 | 1203 |
| shard:lane-a@Bridge (shards-5) | 1167 | cd13b1ae | 1088 | 1167 | 981 | 1032 |
| live:install-upgrade (install-upgrade) | 1112 | cd13b1ae | 1076 | 1112 | 826 | 893 |
| live:sign-in-2 (shards-4) | 1094 | cd13b1ae | 997 | 1094 | 1088 | 991 |
| live:install-start (install-fresh) | 1086 | cd13b1ae | 1024 | 1086 | 910 | 872 |
| live:sign-in-3 (shards-5) | 953 | cd13b1ae | 917 | 953 | 820 | 846 |
| live:sign-in (browser) | 915 | a3086148 | 915 | 868 | 791 | 810 |
| live:floor (shards-3) | 909 | cd13b1ae | 745 | 909 | 836 | 739 |
| live:online-demo (install-fresh) | 859 | cd13b1ae | 850 | 859 | 768 | 685 |
| shard:lane-a@Channel (shards-4) | 841 | cd13b1ae | 753 | 841 | 808 | 774 |
| live:demo-path (browser) | 773 | cd13b1ae | 677 | 773 | 697 | 658 |
| live:demo-switch (shards-3) | 650 | cd13b1ae | 559 | 650 | 637 | 572 |
| shard:lane-a@Agent (production) | 633 | cd13b1ae | 621 | 633 | 633 | 617 |
| live:reminder-restart (production) | 629 | 4cb52a8d | 575 | 582 | 629 | 560 |
| live:answers (browser) | 587 | cd13b1ae | 552 | 587 | 512 | 542 |
| live:online-allowance (install-upgrade) | 574 | a3086148 | 574 | 557 | 462 | 457 |
| live:online-demo-path (image) | 573 | cd13b1ae | 490 | 573 | 567 | 489 |
| live:memory-offline (shards-4) | 550 | a3086148 | 550 | 549 | cut | 545 |
| live:online-visitors (install-upgrade) | 545 | cd13b1ae | 503 | 545 | 444 | 438 |
| live:online-session (shards) | 498 | cd13b1ae | 496 | 498 | 497 | 495 |
| live:storage-roundtrip (image) | 487 | cd13b1ae | 340 | 487 | 407 | 361 |
| live:cards (shards) | 481 | a3086148 | 481 | 436 | 420 | 448 |
| live:install-script-live (install-fresh) | 404 | cd13b1ae | 376 | 404 | 337 | 308 |
| live:production-restart (production) | 399 | a3086148 | 399 | 386 | 379 | 372 |
| live:audit (shards-3) | 392 | 4cb52a8d | 314 | 374 | 392 | 307 |
| live:documents (shards-3) | 389 | 2a45f8bc | 356 | cut | cut | 389 |
| live:production (production) | 380 | 4cb52a8d | 359 | 352 | 380 | 353 |
| live:bundle-folder (shards-3) | 373 | cd13b1ae | 325 | 373 | 351 | 321 |
| live:session-data (shards-2) | 366 | 2a45f8bc | cut | cut | 362 | 366 |
| live:security-overview (production) | 296 | 4cb52a8d | 291 | 291 | 296 | 258 |
| live:compose-start (install-upgrade) | 208 | cd13b1ae | cut | 208 | 178 | 194 |
| live:build-inputs (image) | 21 | cd13b1ae | 17 | 21 | 18 | 15 |

**Measured: area class seconds** (the sum of each area's `CLASS` lines per job: min and max):

- Fix: 727 to 769 s
- Bridge: 703 to 744 s
- Docs: 532 to 633 s
- Watch: 505 to 514 s
- Channel: 457 to 471 s
- Core: 405 to 414 s
- Agent: 331 to 337 s
- Schedule: 233 to 274 s
- Eval: 241 to 266 s
- Memory: 229 to 255 s
- Install: 112 to 157 s
- Tools: 83 to 103 s
- Demo: 96 to 97 s
- Checks: 79 to 85 s
- Web: 61 to 70 s
- Digest: 39 to 44 s
- Data: 33 to 34 s
- Msg: 22 to 34 s
- Mcp (Epic 35 only): 28 to 30 s
- Contract: 14 to 17 s
- Live: 11 s

A shard unit also pays its stack start (`READY`) and teardown: 278 to 423 s per unit (`READY` 259 to 404 s).

**The intent gap (why planning stopped).** Ruling 2 says that every `shard:` unit runs in 900 s or less. AD-22's Rule ("sharded by area") and the dispatch's Rule 2 instruction ("every area in exactly one piece") make the smallest piece a whole area. Three lane-a areas exceed 900 s on their own:

| area as its own piece | class time | stack start and teardown | unit time |
|---|---|---|---|
| Bridge (already the piece `shard:lane-a@Bridge`) | 703-744 s | 278-423 s | 981-1,167 s, measured |
| Fix | 727-769 s | 282-379 s | 1,012-1,123 s, computed per run |
| Docs | 532-633 s | 282-379 s | 814-1,006 s, computed per run |

The cap therefore cannot be met with whole-area pieces. Two amendments would make it reachable:

- **A (recommended; minimal, no AD change).** The cap applies to every `shard:` unit of two or more areas. A single-area piece runs whole: today Bridge, Fix and Docs, at about 1,000 to 1,170 s each. The 32-minute group criterion stays unchanged.
- **B (a veto item: it amends AD-22).** An area may run in contiguous class parts:
  - Write a part as `shard:<name>@<piece>#k/n` and run it through the existing `ci/iris.sh shard --part k/n`.
  - This widens the footprint to `ci/iris.sh` `cmd_group` and `shard_unit_areas`.
  - It needs a new "every class in exactly one part" rule in `test-ci-config.sh`, with samples.

**Capacity, for information.** Under either option, the measured units come to about 25,700 s at the slowest times, counting the extra stack start each split pays. At about 1,690 s of units per group (29 minutes less 53 s), that needs at least 16 IRIS groups: the ten existing ones and at least six new ones, `shards-6` to `shards-11`. That is 16 or more IRIS jobs per run on 18 runner services. A trial packing with whole-area pieces put 17 groups at or under 29.0 minutes each.

**Noted, not blocking.** Three live units exceed the standing "about 1,000 s a unit" line on the slow run: `live:install-upgrade` 1,112 s, `live:sign-in-2` 1,094 s and `live:install-start` 1,086 s. Splitting live scripts is outside this footprint, and ruling 2 caps only `shard:` units. Each fits alone in a group under 29 minutes.

**Decided in-stage:**
- Measurement rules:
  - Unit times are the maximum over every finished attempt of the four runs.
  - The job overhead is the per-job maximum, 53 s.
  - Raw extracts are under `<scratchpad>/e0s20plan/`.
- Base for the plan: the group layout is identical on all four measured heads and on this branch's head `85c06b56`. That head is a descendant of `a3086148` and `2a45f8bc`.
- Totals pinned for the coverage check: 34 units, 218 lane-a and 132 lane-b classes.

## Verification

Not yet planned (blocked). Shared surfaces this story will change:
- `IRIS_GROUPS`
- the `ci.yml` matrix
- `group_units`
- `NO_WEB_BUNDLE_UNITS`, if a unit's membership demands it
- the checks/overviewdoc pin and the `live:memory-offline` pin in `docker/tests/test-release-sequence.sh`
- the `groups` and `recipe` pins in `docker/tests/test-ci-config.sh`
- the `web_groups` and "all ten" pins in `docker/tests/test-ci-changes.sh`

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: ruling 2's done criterion "EVERY unit shard (each shard: unit) is <= 900 s" cannot be met with whole-area pieces, which AD-22's Rule ("sharded by area") and the dispatch's Rule 2 instruction ("every area in exactly one piece") require. Three lane-a areas exceed 900 s alone on the measured runs: Bridge, already its own piece `shard:lane-a@Bridge`, at 981-1,167 s; Fix alone at 1,012-1,123 s; and Docs alone at 814-1,006 s. Each is 532-769 s of class time plus a 278-423 s stack start and teardown. Recommended amendment, one of: (A, recommended: minimal, no AD change) the cap reads "every shard: unit of two or more areas is <= 900 s; a single-area piece runs whole" (today Bridge, Fix and Docs, about 1,000-1,170 s), and the <= 32-minute group criterion stays unchanged; or (B, a veto item because it amends AD-22) an area may run in contiguous class parts, `shard:<name>@<piece>#k/n`, through the existing `ci/iris.sh shard --part k/n`, which widens the footprint to `ci/iris.sh` `cmd_group` and needs a new every-class-exactly-once rule in `test-ci-config.sh`. Either way the measured packing needs at least 16 IRIS groups (six new, `shards-6` to `shards-11`) to keep each group at or under about 29 minutes.
