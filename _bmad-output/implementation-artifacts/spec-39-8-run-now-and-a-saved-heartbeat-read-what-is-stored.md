---
title: 'Story 39.8: Run now and a saved heartbeat read what is stored'
type: 'bugfix'
created: '2026-11-06'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: 'Copy forced by the lane boundary: Lane B SettingsOps.HeartbeatValues drops the same five cache entries that Checks.Beat.Values(ref, 1) now drops; it can become Quit ##class(OcuTalon.Checks.Beat).Values(sessionRef, 1).'
    location: 'src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls HeartbeatValues (about line 350)'
    severity: 'low'
    footprint: 'in-epic'
    suggested_owner: '39-5-the-heartbeat-checklist-card-and-run-the-heartbeat-now'
---

<intent-contract>

## Intent

**Problem:** `Checks.Beat` reads a person's heartbeat values through `Data.Setting.Get`'s 60-second per-process cache, and the Checks job (pool size 1) reads every session on each per-minute tick. So a save followed at once by Run now is refused as `empty` (DW-803, Story 39.5 AC6 on the online demo), and a saved shorter interval waits for the beat already scheduled under the old one, although Saved says "Applies within a minute" (DW-780).

**Approach:** `RunNow` drops the Checks process's cache entries of that session's five heartbeat keys, then reads them through `Get` as before. Ticks keep reading through the cache. On each tick, a person who is on and whose stored `NextDueAt` was set from an interval longer than the one saved now gets a new due time: the time of the write that set it plus the new interval. If that time has passed, the beat runs at that tick.

## Boundaries & Constraints

**Always:**
- Values are read only through `OcuTalon.Data.Setting.Get`. The run-now path drops this process's cache entries of the session's five keys first. `RunDue` reads through the cache exactly as today (AC).
- **Reschedule rule.** The base is the newer of `LastBeatAt` and `LastSkipAt`. When a skip is newer and its `LastSkipReason` is `hours`, the stored `NextDueAt` stands. With no base, or an empty `NextDueAt`, nothing changes. When the base plus the saved interval (`NextDue(values, base, "")`) is earlier than the stored `NextDueAt`, that time replaces it. A later or equal time keeps the stored value.
- The reschedule applies only to a person who is on, has a row and was not left unsettled in this `RunDue`. It runs before the due test:
  - if the new time is due (at most `Process.DUESLACKSECONDS` after the tick), `Run` beats at once and its save is the only commit;
  - otherwise the row is saved once and publishes nothing (no `AddView`; lead ruling at the spec gate: AD-18's Event bullet names a beat, a skip and a result).
- Each person stays in its own Try/Catch. A failed reschedule save counts as one failure, like any other save.
- Tests save heartbeat settings with on = 0 on a running production, unless the test needs the person on. Every test removes its rows and settings afterwards (`BeatCase.OnAfterOneTest`, `Test.Checks.Beat.Forget`).

**Never:**
- Edit a Lane B file: `Data/Setting.cls`, `Core/**` (`SettingsOps` included), `Web/**`, `Msg/**`, `Live/**`, `web/**`, `Test/Core/**` or `Test/Web/**`.
- Edit Epic 17's or Epic 11's contended files.
- Call `Data.Setting.Seed` or `Set` from `Checks` (`SettingsOps` is the only run-time writer).
- Read a value from a global.
- Add a scheduler, task, timer or in-memory due state (AD-5, AD-18).
- Add user-facing text, a catalog key or a new event type.
- Change `Checks/Process.cls`, `BeatNow`, the seams' signatures or the cooldown, skip or cap rules.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Save then run now (DW-803) | The Checks process cached the session's checklist as empty less than 60 s ago. Another process then saves a checklist. | `BeatNow` answers `sent`: one Item goes to Intake, the mock logs one request, and that process's cache now holds the stored value. | A `RunNow` error status is answered `failed`, as today. |
| Tick after a save | The same stale cache, and the person is due. | `RunDue` reads the cached empty checklist: an `empty` skip, no Item. | none |
| Shorter interval, new time ahead (DW-780) | A beat at B left `NextDueAt` = B+60 min. The interval is now 30. The tick is at B+1 min. | `NextDueAt` becomes B+30 min, saved, with one view and no Item. The next tick writes nothing and gives no view. The tick at B+30 min beats. | A failed save counts as one failure, and the other people go on. |
| Shorter interval, time passed | A beat at B-40 min left `NextDueAt` = B+20 min. The interval is now 30. The tick is at B. | The beat runs at B: `LastBeatAt` = B, `NextDueAt` = B+30 min. One commit, one view. | none |
| Longer interval | A beat at B left `NextDueAt` = B+30 min. The interval is now 120. | `NextDueAt` is kept, with no write and no view. The beat at B+30 min sets `NextDueAt` = B+30 min+120 min. | none |
| A skip set it | A newer `cap` skip at S left `NextDueAt` = S+60 min. The interval is now 30. | `NextDueAt` becomes S+30 min. | none |
| Hours skip, off, no base | (a) The newest write is an `hours` skip. (b) The person is off. (c) The row has neither `LastBeatAt` nor `LastSkipAt`. | `NextDueAt` is untouched, with no write and no view. | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls`:
  - class doc: the `Values` bullet 5-7, the due bullet 8-9 and the views bullet 21-25;
  - `Values` 109-132;
  - `NextDue` 155-165, which is the sibling the reschedule reuses with reason "";
  - `RunDue` 390-443, whose due loop at 419-439 reads `Values(ref)` at 424, has the due test at 426 and calls `Run` at 433;
  - `RunNow` 449-480, which calls `Settle` at 458 and passes `..Values(sessionRef)` to `Run` at 473;
  - `Settle` 527, which reads `Values` at 539;
  - `AddView` 551 and `SettingKey` 570.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` (Lane B, read only):
  - `Get` 39-53: the cache entry is `^||OcuTalon.Setting(key) = $ListBuild(value, present, $ZHorolog)`, documented at 36-38;
  - `Set` and `Seed` drop it with `Kill ^||OcuTalon.Setting(key)` (61, 74);
  - it has no public drop method.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` `HeartbeatValues` (about 350, Lane B, private, read only) -- the sibling idiom: it kills the five keys' entries, then calls `Beat.Values`.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` `BeatNow` and the `BeatRunDue`/`BeatRunNow` seams (283) -- unchanged. `Tick` calls `RunDue` with all sessions.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` (no production; warm; fixed clocks in 2099):
  - the shapes to follow: `TestDueSelection` 315 and `TestRunNow` 439;
  - helpers: `Person` 851, `Put` 878, `SetRow` 870, `Open` 811, `Local` 838, `Plus` 844, `BValues` 933, `BDue` 981, `BNow` 986, `RowJson` 999, `ViewRefs` 1006 and `Forget` 909 (which deletes the Setting rows by key);
  - class doc 1-31.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` (running production; fresh):
  - the shape to follow: `TestBeatNowReachesIntake` 468 (a `BeatNow` through the `HEARTBEAT` service with `SendRequestSync` to `CHECKS`);
  - `TestBeatReachesIntake` 377;
  - class doc 1-46.
- `src/ocutalon/cls/OcuTalon/Test/Checks/BeatCase.cls`:
  - `SeedBeat` 53 (it writes on 1, interval 30, all day and the checklist);
  - `Beat` 67, `Due` 45, `Beatable` 34, `Findings` 16, `WaitDecision` 75 and `Marked` 87.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls`:
  - `Tick` 682 (synchronous) and `RealTick` 691;
  - `HEARTBEAT`, `CHECKS` and `TICKWAIT` at 139-144.
- Existing fixtures that the reschedule leaves alone:
  - `Test/Checks/Beat.cls` 541: the row is due anyway;
  - `Test/Web/HeartbeatApi.cls` 175: `NextDueAt` = `LastBeatAt`+30 at the default interval;
  - `Test/Core/SettingsHeartbeat.cls` 335: the person is off.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` (DW-803, DW-780):
  - `Values(sessionRef, stored As %Boolean = 0)`: when `stored` is 1, first `Kill ^||OcuTalon.Setting(..SettingKey(sessionRef, name))` for each name in `KEYS`. Then read as today.
  - `RunNow`: right after `views` is set to 0, `Set values = ..Values(sessionRef, 1)`. Pass `values` to `Run` in place of `..Values(sessionRef)`.
  - New private `Rescheduled(row, values) As %String`: the Always rule, through `NextDue(values, base, "")`. It answers the new due time, or "".
  - `RunDue`'s due loop: for an on person with a row, take `Rescheduled`, and set `row.NextDueAt` when it is not "".
    - The due test is unchanged.
    - Add an `ElseIf` for a rescheduled person who is not due: `$$$ThrowOnError(row.%Save())` and NO `AddView`: a reschedule publishes nothing (lead ruling at the spec gate, see Design Notes).
  - Update the three class-doc bullets and the docs of `Values`, `RunDue` and `RunNow`.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` -- two new tests and their class-doc entries:
  - `TestRunNowReadsStoredValues` covers the matrix rows Save then run now and Tick after a save:
    1. a due person with no checklist row;
    2. `BValues` caches the empty checklist;
    3. a Setting row for the checklist is saved with `%New`/`%Save`, so this process's entry stays (as another process's save leaves it);
    4. a precondition asserts that `BValues` still reads "";
    5. `BDue` gives no Item and an `empty` skip;
    6. `BNow` answers `sent`, with an Item whose text starts with the checklist;
    7. `BValues` now reads the checklist.
  - `TestSavedIntervalMovesNextDue` covers the other matrix rows: each `NextDueAt`, the views (`ViewRefs` and `RowJson`), the Items, and the second tick's no write and no view.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- two new tests and their class-doc entries:
  - `TestSaveThenRunNow` (AC 1, Integration AC):
    1. `Beatable`, then `SeedBeat(session, Due()+86400, "", "")`, then on = 0;
    2. a synchronous `Tick` at the clock's now, so the Checks job reads the empty checklist;
    3. `Data.Setting.Set` of a checklist with `[[mock:decide-ignore:<session>]]`;
    4. a `BeatNow` (`RequestedAt` = now) through `HeartbeatIn`, sent less than 50 s after the Tick started (asserted, so the cache is still live);
    5. the answer is `1|sent|<ItemId>|`, with one Item to Intake, a Decision and `Marked` = 1.
  - `TestShorterIntervalReschedules` (AC 2):
    1. `SeedBeat(session, t0+3600, marker checklist, "")`, then `LastBeatAt` = t0 on the row;
    2. `Tick(t0+60)`: `NextDueAt` = t0+1800, no Item, `Marked` 0, and no heartbeat event from this Tick (the reschedule publishes nothing);
    3. `Tick(t0+1800)`: one Item, `Marked` 1 after `WaitDecision`, and the row has `LastBeatAt` t0+1800 and `NextDueAt` t0+3600.

**Acceptance Criteria:**
- AC 1 (DW-803) -- Given a session whose heartbeat settings the Checks job read less than 60 s ago, when another process saves a checklist and a `BeatNow` follows at once, then `Checks.Beat.RunNow` drops that process's cache entries of the session's five keys and reads them through `Data.Setting.Get`, so the beat is sent, not refused as `empty`. And a Tick still reads through the cache (AD-18, AD-19).
- AC 2 (DW-780) -- Given a `NextDueAt` set by a beat (or by a skip other than hours) under a longer interval, when the person saves a shorter interval, then from the first tick that reads it the next beat is due at that write's time plus the new interval, or at once if that time has passed. A longer interval keeps the stored `NextDueAt` until the next beat, which uses the new interval (FR-63, AD-18, AD-19).
- AC 3 -- Given `Test.Checks` cases on the real tick and the CI mock, when they run, then they pin the save-then-run on a session the tick has already read, and the shorter-interval reschedule, each with a demonstrated mutation (Rule 19).
- Integration AC -- Given the real production, when `HeartbeatIn` sends the `Checks` item a `BeatNow` right after a save on a session the Tick has read, then `Checks` answers the `CommandResult` that `CommandsIn` turns into `POST /api/v1/heartbeat/run`'s 202 (`Ok` 1, `Outcome` `sent`, `Ref` the ItemId). The Item reaches Intake, and the CI mock logs exactly one request.

## Spec Change Log

- 2026-11-06 (lead, spec gate): a reschedule saves the row and publishes no heartbeat event (no AD-18 change); the Code Map, the AC 2 test steps, Shared surfaces and Consumed-by updated to match.

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-18: values read through `Get` on each tick; run now; state; nothing that decides due in memory; the Event bullet.
- AD-19: per-person values, read through `Get` with a 60-second cache; "applies within 60 seconds"; `SettingsOps` the only run-time writer.
- AD-12: one view per committed change.
- AD-5: restart-safe due state.
- AD-29 and AD-33: lanes. `.Data.Setting` is Lane B's (the spine's lane list) and is not edited here.
- Conventions row "Settings": product values through `Data.Setting.Get`, never read globals directly.
- AD-1 and AD-14 are not cited (U-268).

**Decided in-stage:**
- **How the cache is dropped.**
  - `Data.Setting` exposes no drop method (only `Get`, `Seed` and `Set`; the rest is private), and it is Lane B's.
  - So `Values(ref, 1)` kills this process's documented cache entries for the session's five keys, then reads through `Get`. This is the idiom of `Data.Setting.Set` and `Seed`, and of Lane B's `SettingsOps.HeartbeatValues` (Story 39.2).
  - No value is read from a global, so the Settings convention holds.
  - `Seed` is not used as a drop: it writes when a key is absent.
- **`RunNow` drops before `Settle`,** so a recorded result's view and the beat read the same stored values.
- **The reschedule's base is the write that set `NextDueAt`.**
  - The AC names a beat. A non-hours skip sets `NextDueAt` one interval on in the same way, so the same rule keeps "Applies within a minute" true after a skip.
  - Basing the rule on `LastBeatAt` alone would make every tick after a skip due, which writes a skip row every minute.
  - An hours skip's `NextDueAt` is a window start, not an interval, so it is kept.
- **A reschedule is saved and publishes nothing** (lead ruling at the spec gate, 2026-11-06, decide): AD-18's Event bullet names a beat, a skip and a result; a new event case would amend an AD's Rule, which is the orchestrator's (U7, U14). As with U-283's empty-checklist tick skip, the row is saved and no event is published. Consequence (inference, accepted): after a saved shorter interval the card's next check-in can show the old, later time until the next beat, which then comes sooner and publishes its event. The event-counting tests are unaffected.
- **On/off (DW-780) needs no change:**
  - an off person is skipped from the first tick that reads it;
  - a person turned on is due at once when `NextDueAt` has passed, else under the same reschedule rule.

**Extend, don't copy (Rule 2):**
- `Values` gains a parameter; there is no second reader.
- `Rescheduled` reuses `NextDue`.
- The three-line drop loop is the same as Lane B's private `SettingsOps.HeartbeatValues`. Lane A may not call `Core` (AD-1), and this story may not edit it. The unification (`HeartbeatValues` becoming `Quit Beat.Values(sessionRef, 1)`) is in frontmatter `deferred:`, suggested for 39.5's Lane B rework.

**Integration ACs:** the Integration AC above, on the real `Checks` item.

**Consumed-by:**
- 39.2's `POST /api/v1/heartbeat/run` (`CommandsIn` -> `BeatNow` -> `RunNow`): its 202 after a save.
- 39.5's card: save-then-run on the online demo; the card's next check-in follows the next beat's event (a reschedule publishes nothing). Its rework adds `Test.Web.HeartbeatApi`'s save-then-run 202 case.

**Consumes:**
- `Data.Setting.Get` (Lane B);
- `Data.HeartbeatBeat`;
- `Live.Payload.Heartbeat.FromRow` (39.7);
- `Process.Tick` and `BeatNow` (unchanged).

**Ledger inbox:**
- DW-803 is addressed by AC 1, the Integration AC, and the rows Save then run now and Tick after a save.
- DW-780 is addressed for the interval by AC 2 and the four reschedule rows. On/off needs no change (see above).
- Declined DW-780 (the hours part only). It is not in Story 39.8's acceptance criteria, which name the interval.
  - Today an hours skip's `NextDueAt` is the old window's next start. A narrower window is correct from there, and a wider one waits at most until then, under a day.
  - An earlier start needs the skip time read again against the new window, which is a rule the spine does not state.
  - For the lead to re-own or close: wontfix-accepted, reopen_if = a widened window still skips at its new start.

**Footprint:**
- `Checks/Beat.cls`, `Test/Checks/Beat.cls` and `Test/Checks/Heartbeat.cls`, all Lane A and in Epic 39's paths.
- None of them is contended by Epic 17 or Epic 11.

## Verification

`<lane>` is `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`.

**Run rules:**
- Every command is a foreground call with `timeout: 600000`, one test class or shard per call, never two at once.
- Slot D (`server: ocutalon-slot-d`, `namespace: OCUTALON`, identity FE850E91 via `iris_server_info`) is only for `iris_doc_load` and compiling; no production runs there.
- Tear down only your own tags, also after a failure.

**Shared surfaces:**
- the session's heartbeat event stream: unchanged (a reschedule publishes nothing);
- `Checks.Beat.Values`'s signature: an optional trailing argument; the callers (`SettingsOps.HeartbeatValues`, `Test.Checks.Heartbeat.ViewOf`, `Test.Checks.Runs` and `Test.Core.SettingsHeartbeat`) are unchanged;
- the Checks job's settings cache: `RunNow` refreshes only its session's five keys.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e39s8implw ci/warm.sh up`, once. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s8implw ci/iris.sh class OcuTalon.Test.Checks.Beat`. Expected: `CLASS ... passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s8impl ci/iris.sh class OcuTalon.Test.Checks.Heartbeat`, fresh, because it runs the production. Expected: passed; record the time.
- (once) the same, warm, one per call, for `OcuTalon.Test.Checks.Runs`, `OcuTalon.Test.Core.SettingsHeartbeat` and `OcuTalon.Test.Live.Payloads`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e39s8impl ci/iris.sh class OcuTalon.Test.Web.HeartbeatApi`, fresh: the consumer's regression. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e39s8impl ci/iris.sh shard lane-a@Checks`, then the same with `--reverse`, fresh, one per call (about 3 minutes each). Expected: passed.
- (once) `bash docker/tests/test-boundaries.sh`. Expected: exit 0.
- (once) `git diff --name-only 6172c4cb9e3c635978fe4a57ba39358ad24e458e` lists only the Footprint files and this spec. Expected: true.
- (once) `<lane> OCUTALON_RUN_TAG=e39s8implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s8impl ci/iris.sh teardown`, also after a failure.

**Pinning mutations.** For each one: apply it, observe red, revert to byte-identical, and record a `mutation:` line (Rule 19).
- AC 1: `RunNow` passes `..Values(sessionRef)` (no drop) to `Run`. Expected red: `Beat.TestRunNowReadsStoredValues` (`sent`) and, fresh, `Heartbeat.TestSaveThenRunNow`.
- AC 1, the tick keeps the cache: `RunDue` reads `..Values(ref, 1)`. Expected red: `TestRunNowReadsStoredValues` (the Tick's `empty` skip).
- AC 2: `Rescheduled` always answers "". Expected red: `Beat.TestSavedIntervalMovesNextDue` and, fresh, `Heartbeat.TestShorterIntervalReschedules`.
- AC 2, longer: `Rescheduled` answers base plus interval whenever it differs. Expected red: the Longer interval row.
- AC 2, base: `Rescheduled` uses `LastBeatAt` alone. Expected red: the A skip set it row.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
