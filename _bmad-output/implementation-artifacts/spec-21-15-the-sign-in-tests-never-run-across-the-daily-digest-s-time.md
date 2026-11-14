---
title: "Story 21.15: The sign-in tests never run across the daily digest's time"
type: 'bugfix'
created: '2026-11-14'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** On feature a5fc95e9, CI run 43573005917 (`iris (shards-10)`, live:sign-in) failed `chat/chat.spec.ts` C1 and `sign-in/shell.spec.ts` row 8. The README account's chat held the daily digest notice. The suite started at 07:57:30Z, so C1 ran at about 08:01Z. `Digest.Process` (`src/ocutalon/cls/OcuTalon/Digest/Process.cls` :4-8, `TIMEDEFAULT` "08:00" at :80, read at :215) makes every session due once today's `digest.time` falls after its `CreatedAt`. The stack seeded the README session just before 08:00, and the run crossed it. The snapshot's chat merges turns, incidents and notices (`Web/Api.cls` `ChatItems` :1400-1447), so the empty chat panel never showed. DW-1081's shell row 8 occurrences fit the same window: the Nov 10 job 129700562519 failed at 08:03:16Z, and the Nov 11 run 42981966109 failed at 08:0x.

**Approach:** Test-only. `docker/tests/test-sign-in.sh` (all three projects) seeds `digest.time` to the instance-zone clock 12 hours from now, prints it, and fails if it is within 2 hours of the instance clock now. The specs that save a digest time keep away from the run too.

## Boundaries & Constraints

**Always:** no product change and no new text (Contest Planner, ~09:15Z Nov 14). The seed uses `OcuTalon.Data.Time` (`NowUtc`, `AddSeconds`, `ToLocal`, which converts in the instance zone with its daylight-saving time), so no zone offset brings the time back inside the run. The time of day is taken modulo 24 hours. The guard compares the stored value (`Data.Setting.Fresh`) with the instance clock, either way round the day.

**Never:** limit the seed to one project; change `Digest.Process`, its default or AD-18; weaken C1, row 8, E7 or S10.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|----------|--------------|---------------------------|
| Normal seed | any instance time | `DIGEST digest.time HH:MM, instance clock HH:MM, N minutes apart` with N 718 to 720, and a PASS line |
| Midnight wrap | instance clock 13:30 | digest.time 01:30 (modulo 24 h) |
| Guard | `OCUTALON_DIGEST_SHIFT_SECONDS=3600` | about 60 minutes apart: the script dies before the browser run |
| Bad shift | a non-number | the script dies naming the value |

</intent-contract>

## Code Map

- `docker/tests/test-sign-in.sh`: after the seeded events (Story 0.5's block), the new "Story 21.15 (DW-1081)" block. `OCUTALON_DIGEST_SHIFT_SECONDS` (43200 by default) exists only to show the guard's failure.
- `web/e2e/settings/settings.spec.ts` S10: it saved a fixed `06:45` (or `06:46`) for a moment, which a run near that clock could cross. It now saves the stored time plus one minute, modulo 24 hours.
- `web/e2e/settings/email.spec.ts` E7: it reads the stored time and channels (`digestValues`), posts with `before.time`, and puts `before` back. It assumes no 08:00 default, so it is unchanged.
- `web/e2e/heartbeat-card.spec.ts` "08:00" is the heartbeat schedule's own default, not the digest's, so it is unchanged.

## Tasks & Acceptance

- [x] The seed and its guard in `test-sign-in.sh`.
- [x] S10's saved time is relative to the stored one.
- [x] E7 checked: no assumption to fix.
- [x] DW-1081 reclassified to this story.

**Acceptance Criteria:** the two of epics.md Story 21.15.

## Spec Change Log

- 2026-11-14 (lead, Contest Planner ~09:15Z ruling): chartered from the Epic 21 runner's diagnosis of feature red a5fc95e9.

## Verification

Lane C: `OCUTALON_LOCK_DIR=<worktree parent>/.coordination/locks/lane-c`, `OCUTALON_TEST_WEB_PORT=52803`, run tag `e21s15`.
- `ci/iris.sh build` (once).
- The guard's failure path (once): `OCUTALON_DIGEST_SHIFT_SECONDS=3600 ci/iris.sh live sign-in --part 4/4` -> fails at the guard, before the browser run.
- `ci/iris.sh live sign-in --part 2/4` (holds chat.spec C1) and `--part 4/4` (holds shell.spec row 8), once each -> pass, and print the DIGEST line.
- `ci/iris.sh live sign-in-2 --part 9/12` (holds email.spec E7) and `--part 11/12` (holds settings.spec S10), once each -> pass.
- `bash docker/tests/test-boundaries.sh` (once) -> pass.

## Auto Run Result

Status: done
Blocking condition: none

Results on lane C (tag `e21s15`, 2026-11-14), on OCT-epic21-s2115 from feature a5fc95e9:
- The guard's failure path: `OCUTALON_DIGEST_SHIFT_SECONDS=3600 ci/iris.sh live sign-in --part 4/4` printed "DIGEST digest.time 10:01, instance clock 09:01, 60 minutes apart" and died with "FAIL the daily digest's time 10:01 is within 2 hours of the instance clock 09:01" before the browser run. The stack was torn down.
- `live sign-in --part 2/4` (chat.spec C1): all checks passed; "DIGEST digest.time 21:03, instance clock 09:03, 720 minutes apart".
- `live sign-in --part 4/4` (shell.spec row 8): all checks passed (21:08 against 09:08).
- `live sign-in-2 --part 9/12` (email.spec E7 passed): all checks passed (21:11 against 09:11).
- `live sign-in-2 --part 11/12` (settings.spec S10 passed with the relative time): all checks passed (21:14 against 09:14).
- `test-boundaries.sh`, `test-ci-config.sh` and `tsc -p tsconfig.e2e.json` pass.
- mutation: the seed block removed -> a run that starts before 08:00 instance time and crosses it fails C1 and row 8 (shown by CI run 43573005917 on a5fc95e9, the same tree without the block); the guard -> shown by the 3600 s run above.

Residual risk: `Digest.Process` reads `digest.time` through `Data.Setting.Get`, which caches a value for 60 seconds in its process. A stack seeded within the 60 seconds before 08:00 instance time could still send one digest. That window is one minute a day instead of the length of a run. Closing it would need a product change, which this story does not make.
