---
title: 'Story 8.1: The heartbeat ticks every minute and catches up once after a restart'
type: 'feature'
created: '2026-10-24'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Schedule.HeartbeatIn` is an Epic 0 stub and no Task Manager task calls it, so nothing ticks: `Checks` never runs, Story 8.2's stalled warning has no tick to read, and a restart leaves no record of the minutes it missed (FR-32).

**Approach:** One Task Manager task, declared in `OcuTalon.Install.Step.Schedule.Tasks()`, runs every minute and calls the adapterless `HeartbeatIn`, which sends one `OcuTalon.Msg.Tick` to `Checks`, then records the tick time and any gap of whole minutes in `OcuTalon.Data.StatusMark`. After downtime the next run sends one catch-up tick. While the production is not running, the task ends quietly and records nothing.

## Boundaries & Constraints

**Always:**
- Times are UTC strings `YYYY-MM-DDThh:mm:ssZ`, read and made only through `OcuTalon.Data.Time` (AD-18).
- Minutes count by the clock minute: `missed` = (the minute of this tick − the minute of the previous tick) − 1, and never below 0. `CatchUp` is 1 exactly when `missed` > 0.
- `HeartbeatIn` sends the tick asynchronously, so it never waits for a check. It sends first, then records the gap mark (when `missed` > 0), then the tick mark. It sends only when the class behind its target `Checks` (`$$$ConfigClassName("Checks")` in the running production) carries no `STUB`; while that class is Lane A's stub it sends nothing and still records both marks, so no error row is written and the stalled warning stays real (ruling U-52). A failed send records nothing, so the next run catches up. It works under one lock (5 s); a run that can't take the lock ends OK and sends nothing. It writes no event-log row when it succeeds.
- The task ends with OK and sends nothing when `OcuTalon.Production` is not the running production, or when `CreateBusinessService("HeartbeatIn")` says the production is stopped, stopping or quiescent, or the item is disabled. The codes come from Task 0 (b). Any other failure is returned and shows in the task history.
- `Tick` and `StatusMark` keep their schema: no property is added, because none is needed (AD-5). Marks go through `StatusMark.Record`/`Get` only.
- Tests run in throwaways or CI (Rule 21). Each test puts back what it changed, even after a failure: the `Checks` item's class, the task's `Suspended` value, the production running with every item, its fixture marks and `^OcuTalonTest("ChecksDouble")`.

**Never:**
- No edit to Lane A's files (`OcuTalon.Checks.*`, `OcuTalon.Test.Agent.*`), to contended paths, to `Install/Registry.cls` or `Install/Step/Tasks.cls` (AD-33). The one exception is HeartbeatIn's row of `Test/Core/ProductionItems.cls` (orchestrator ruling); no other row or line of that file changes.
- No change to `ReminderOps` or `ReminderTimer`; they belong to Stories 8.3 to 8.5.
- No sleeping until the minute boundary. Waits poll up to a stated ceiling.
- No literal non-ASCII characters in code (Rule 14).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First tick | no `heartbeatTick` mark | Tick: `PreviousTickAt` "", `CatchUp` 0; no gap mark | none |
| Next minute | previous 12:00:00Z, now 12:01:00Z (or 12:00:59Z to 12:01:02Z) | `CatchUp` 0, missed 0, no gap | none |
| Same minute | previous 12:00:10Z, now 12:00:50Z | `CatchUp` 0, missed 0, no gap | none |
| One run missed | previous 12:00:00Z, now 12:02:00Z | `CatchUp` 1, missed 1, gap `{start 12:00:00Z, end 12:02:00Z, missed 1}` | none |
| Seven minutes down | previous now − 7 min | one Tick, `CatchUp` 1, `PreviousTickAt` = the old one, missed 6 | none |
| Unreadable previous | mark value `garbage` | treated as a first tick: `PreviousTickAt` "", no gap | none |
| Previous in the future | previous later than now (clock moved back) | `PreviousTickAt` kept, `CatchUp` 0, no gap | none |
| Production stopped | the task runs while `OcuTalon.Production` is stopped | status OK in the task history, no Tick header, marks unchanged | quiet end |
| Checks is a stub | the class behind `Checks` carries `STUB` (Lane A's `OcuTalon.Checks.Process` until Story 5.6) | no Tick sent, no Tick header; the tick mark and any gap mark are recorded as for a send; no new error row | none (ruling U-52) |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatIn.cls`: the stub. It has `Parameter STUB = 1` and a 5003 handler; both go.
- `src/ocutalon/cls/OcuTalon/Msg/Tick.cls`: `TickAt`, `PreviousTickAt` and `CatchUp` already cover every AC. Read only.
- `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls`: `Record(mark, value)` (an empty value deletes the row) and `Get(mark)`. Read only.
- `src/ocutalon/cls/OcuTalon/Data/Time.cls`: `NowUtc`, and `ToLocal`'s `$ZDateTimeH(utc,3,7,...)` parse. It gains two helpers.
- `src/ocutalon/cls/OcuTalon/Install/Step/Digest.cls`: the sibling area that only declares; `Install.Step.Schedule` follows it.
- `src/ocutalon/cls/OcuTalon/Install/Step/Tasks.cls:33-82`: `Check` requires a name that starts `OcuTalon` and a class that extends `%SYS.Task.Definition`. `Create` returns at once when `FindId(name)` finds the task; otherwise it sets `$Property` from `task:{}`, `NameSpace=$Namespace` and `RunAsUser=$Username`. Read only.
- `src/ocutalon/cls/OcuTalon/Install/Task/Purge.cls`: the sibling task class (`Parameter TaskName`, `OnTask`).
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls:14,20-35`: `Tasks` runs before `Production` in `Order()`. `Areas()` finds `Install.Step.Schedule` by its name, so the registry needs no edit.
- `src/ocutalon/cls/OcuTalon/Core/Commands.cls:30-32` and `Demo/Orders/Partner.cls:93-95`: the `CreateBusinessService` + `ProcessInput` pattern.
- `src/ocutalon/cls/OcuTalon/Production.cls:65`: `HeartbeatIn` (pool 0, enabled) in lane B's region, with target `Checks` at line 42 in lane A's region. No change.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls:645-660` `UseItemClass`/`RestoreItemClass`, `:117` `WaitAllRun`, `:437` `HeaderMark`: Lane A's test helpers. Reuse them; never edit them.
- `src/ocutalon/cls/OcuTalon/Test/Tools/CommandsDouble.cls`: the double pattern (it records to `^OcuTalonTest(...)`). `ChecksDouble` follows it.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` `Run()`: the product's start, which waits until every item runs. Tests use it to start the production again.
- `docker/tests/lib-live.sh` `settle_scheduler`: DW-28. A stop right after a production update fails unless `Ens.ScheduleHandler` is idle. Read only.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls:139-172` `TestStubsAnswer`: compares each item's `STUB` with the oracle rows (lane B's rows are in `Test/Core/ProductionItems.cls:33`, a contended path) and requires no new `OcuTalon.*` log rows.
- `ci/units.sh:15-21`: `shard_areas`. `test-ci-config.sh` fails until a new `Test.<Area>` joins a shard.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure, labelled; implement stage, warm throwaway). (a) After the `Tasks` step creates the declared task, record `NextScheduledDate`/`NextScheduledTime` (expect within 60 s) and confirm the next run happens. That `DailyEndTime` 0 covers the whole day is (inference), from InterSystems' own every-minute task `%SYS.Task.DeepSeeUpdate.Schedule`. (b) Record the status code of `CreateBusinessService("HeartbeatIn")` with `OcuTalon.Production` stopped, and while it stops. (c) Record whether `ProcessInput` accepts no input object. Write the results under Design Notes.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Time.cls`: add `Seconds(utc) As %String` (whole seconds on one fixed scale; "" for an unreadable time) and `AddSeconds(utc, seconds) As %String` (a UTC time; "" for an unreadable one). The heartbeat counts minutes with them, and tests build "7 minutes ago" with them.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/Heartbeat.cls` (new): parameters `TICKMARK = "heartbeatTick"`, `GAPMARK = "heartbeatGap."` and `TARGET = "Checks"`. `Next(previous, now, Output missed) As OcuTalon.Msg.Tick` is pure and follows the matrix. `Record(tick, missed) As %Status` writes the gap mark `heartbeatGap.<PreviousTickAt>` = `{"start","end","missed"}`, then the tick mark = `TickAt`. `Gaps(fromUtc, toUtc) As %DynamicArray` returns the gaps that overlap the window, oldest first.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatIn.cls`: delete `STUB` and the stub handler. `OnProcessInput` takes the lock, reads the previous tick (`StatusMark.Get`), calls `Next` with `Data.Time.NowUtc()`, sends with `SendRequestAsync(TARGET, tick)`, then calls `Record`. It returns the Tick as `pOutput`.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatTask.cls` (new): extends `%SYS.Task.Definition` with `Parameter TaskName = "OcuTalon heartbeat"`. `OnTask` applies the production rule from Always, then calls `CreateBusinessService` and `ProcessInput`.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls` (new; not in `Order()`): `Tasks()` returns one entry, `{"name":"OcuTalon heartbeat","taskClass":"OcuTalon.Schedule.HeartbeatTask","description":...,"task":{"TimePeriod":0,"TimePeriodEvery":1,"DailyFrequency":1,"DailyFrequencyTime":0,"DailyIncrement":1,"DailyStartTime":0,"DailyEndTime":0,"StartDate":(+$Horolog),"RescheduleOnStart":1}}`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ChecksDouble.cls` (new): an `Ens.BusinessProcess` that stands in for `Checks` (AD-29). Its `OnRequest` appends `$ListBuild(TickAt, PreviousTickAt, CatchUp, the header id)` to `^OcuTalonTest("ChecksDouble","ticks")`, waits `^OcuTalonTest("ChecksDouble","hang")` seconds when that is set, and answers OK. Commit its compiler-generated `Storage` block.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/HeartbeatLogic.cls` (new; needs no production): every matrix row through `Next`, the two `Data.Time` helpers, and `Gaps` over fixture gap marks dated 2001 (deleted afterwards), inside, outside and across the window.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` (new; throwaways and CI only): `OnBeforeAllTests` puts `ChecksDouble` behind `Checks` (`UseItemClass`), and `OnAfterAllTests` restores everything listed under Always. The methods are `TestTaskDeclared` (AC 1, 2), `TestCatchUp` (AC 3, 4; the real task suspended) and `TestStoppedThenStarted` (AC 5, 6).
- [ ] `ci/units.sh`: add `Schedule` to `lane-b`'s `shard_areas` (`Contract Core Data Demo Live Msg Schedule Web`).
- [ ] Orchestrator ruling (Clarification 1, option (a), a one-time footprint extension): in `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:33`, change HeartbeatIn's row from `"stub": 1` to `"stub": 0`. Touch no other row or line of the file (it is Epic 2's contended `Test/Core/**`).
- [ ] Ruling U-52 (veto): in `HeartbeatIn.OnProcessInput`, send only when the class behind `TARGET` (`$$$ConfigClassName(TARGET)`) carries no `STUB` (`+$Parameter(class,"STUB")` = 0); otherwise skip the send and record the marks exactly as after a send. `TestStubSkipped` in `Test/Schedule/Heartbeat.cls` pins it (AC 7).

**Acceptance Criteria:**
1. Given a fresh throwaway start that ran the installer steps, when `%SYS.Task` is queried, then exactly one task has `TaskClass` `OcuTalon.Schedule.HeartbeatTask` and `NameSpace` `OCUTALON`. It is named `OcuTalon heartbeat`, carries the declared schedule fields, comes from `Install.Step.Schedule.Tasks()`, and its next run is within 60 s. When the `Tasks` step runs again, there is still one task, with the same ID and schedule. (FR-32, AD-18, AD-23)
2. Given that task's definition, when it is read, then `RescheduleOnStart` is 1, so a start drops the runs it missed instead of replaying them. (The class dictionary says so on build 154, measured on slot C on 2026-10-24.)
3. Given the production running, the double behind `Checks`, the real task suspended, the `heartbeatTick` mark set 7 minutes back and the double set to hang 5 s, when `HeartbeatTask.OnTask()` runs, then it returns OK in under 5 s. The double records exactly one tick: `CatchUp` 1, `PreviousTickAt` the old time, `TickAt` the new mark. Exactly one `Ens.MessageHeader` goes from HeartbeatIn to Checks since the mark, with body `OcuTalon.Msg.Tick` (Visual Trace). No tick is sent for any missed minute. (FR-32, NFR-20, AD-1, AD-18)
4. Given the same run, when `Heartbeat.Gaps` is read over the last 10 minutes, then it returns one gap, `{start: the old time, end: TickAt, missed: 6}` (missed is computed from the minutes of the two times). A tick one minute after the previous one adds no gap. (FR-32)
5. Given `OcuTalon.Production` stopped (with the scheduler settled first, DW-28) and the tick mark set 3 minutes back, when the Task Manager runs the task (`RunNow`), then its history has no error, no HeartbeatIn header is written and both marks are unchanged. When the Production step starts the production again, the next scheduled run (ceiling 75 s) is the single catch-up tick: `PreviousTickAt` is the mark from before the stop, the double records it once, its header exists, and its history has no error. (FR-32, AD-23)
6. Given the built item, when `OcuTalon.Test.Install.Production.TestStubsAnswer` runs, then `HeartbeatIn` carries no `STUB` and the oracle agrees: its row in `Test/Core/ProductionItems.cls` reads `"stub": 0` (orchestrator ruling, Clarification 1). (AD-29, Story 11.5)
7. Given the production running with Lane A's stub `OcuTalon.Checks.Process` behind `Checks` (its own class, the double removed), the real task suspended and the tick mark set 3 minutes back, when `HeartbeatTask.OnTask()` runs, then it returns OK, no `Ens.MessageHeader` goes from `HeartbeatIn` to `Checks` since the mark, the tick mark is the new tick time, one gap mark (missed 2) is recorded, and no new `Ens_Util.Log` row of type error or alert is written since the mark (ruling U-52; AD-29). (FR-32)

## Spec Change Log

- 2026-10-24, lead spec gate (runner C, unattended): Clarification 2 ruled U-52 (veto: option (b), HeartbeatIn sends no Tick while the class behind `Checks` carries `STUB`; marks still recorded; matrix row, task and AC 7 added). Clarification 3 ruled U-53 (veto: gap marks as planned; spine Consistency Conventions row "Status marks" added, Rule 20). Clarification 1 (contended `Test/Core/ProductionItems.cls`) sent to the orchestrator.
- 2026-10-24, orchestrator ruling on Clarification 1 (U14, category decide, policy 47276b4): option (a). A one-time footprint extension for `Test/Core/ProductionItems.cls`, HeartbeatIn's row only (line 33, `"stub": 1` to `"stub": 0`); no other row or line. The task is unblocked and AC 6 restated; status set to `ready-for-dev` by the lead.

## Review Triage Log

## Design Notes

**Governing ADs:** AD-1 (the adapterless service through `CreateBusinessService`/`ProcessInput`; the tick is a production message), AD-5 (no schema change; `ChecksDouble` commits its `Storage` block), AD-18 (the heartbeat, `StatusMark`, `Data.Time`), AD-22 (`%UnitTest` under `OcuTalon.Test.Schedule` in shard `lane-b`; throwaways), AD-23 (`Tasks()` declares; the core's step creates the task once), AD-26 (each tick starts its own session, as a business service does by default), AD-29 and AD-33 (lanes: `Checks` and `Test.Agent` are Lane A's; a double stands in for `Checks`).

**Integration ACs:** AC 3 and AC 5 show the consumer `Checks`, here the `ChecksDouble` stand-in (AD-29; Story 5.6 builds the real one), receiving the tick and recording it.

**Consumed-by:**
- Story 5.6: `Checks` runs the due checks on each `Tick`, once after a catch-up.
- Story 8.2: `StatusMonitor` and `/state` read `Get("heartbeatTick")` for `heartbeatStalled`.
- Story 17.5: the digest reads `Heartbeat.Gaps(from, to)` to count checks that missed a run.

**Consumes:**
- `StatusMark.Record`/`Get` (Story 0.12).
- `Data.Time` (Epic 0).
- `Install.Step.Tasks` (Story 0.2).
- `RunnerFixture.UseItemClass`, `RestoreItemClass`, `WaitAllRun` and `HeaderMark` (Lane A, Story 1.10, used by tests only).

**Extend, don't copy:** `Install.Step.Schedule` follows the `Install.Step.Digest` pattern (an area that only declares), and `HeartbeatTask` follows `Install.Task.Purge`. `ChecksDouble` copies the pattern of `Test.Tools.CommandsDouble`, not its code: a business process that records ticks is a different host type. The tests reuse RunnerFixture rather than copy it. The DW-28 settle wait is an ObjectScript copy of `lib-live.sh`'s shell line, because that file is contended and written in another language.

**Decided in-stage:**
- The minute-bucket rule for `missed` and `CatchUp` (matrix). It reads "more than one minute" as at least one scheduled minute with no tick, so a run a few seconds late is not a gap.
- One mark per gap, `heartbeatGap.<start UTC>`. The step-2 digest needs every gap in its window, and keeping only the latest gap could hide an earlier one, which would be a false all-clear. Gap rows are kept like every other mark (see Clarification Needed 3).
- The mark names `heartbeatTick` and `heartbeatGap.`.
- A disabled `HeartbeatIn` ends quietly, so the stalled warning shows it.
- `SuspendOnError` and `Expires` keep their defaults, so a failed run is retried on the next minute and a late run never doubles up.
- The real-schedule wait happens only after the restart in AC 5. AC 3 calls `OnTask` in the test process with the real task suspended.

**Rulings (lead spec gate, unattended, policy 47276b4):**
- Orchestrator ruling on Clarification 1 (U14, decide): option (a). Epic 8 may change HeartbeatIn's row of `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls` (line 33, `"stub": 1` to `"stub": 0`) and nothing else in that file. The file's header says Lane B edits its own rows when it builds one of its items; Epic 2's edits to the file (lines 18-19, 24, 26-28) merge cleanly with it, and a conflict at integrate-forward would be a plain union. Reported under `footprint_extensions:`.
- U-52 (veto, Clarification 2): option (b). While the class behind `Checks` carries `STUB`, `HeartbeatIn` sends no Tick and records the marks. Rejected (a), Lane A's stub answering a Tick with OK: another lane's file (AD-29, AD-33), and AD-29's Rule that every unbuilt item answers "not implemented". Rejected (c): contended `docker/tests`, and it would hide real error rows. No release runs the skip (Story 11.5 refuses an enabled stub), and Epic 5's built `Checks` receives every tick with no change here.
- U-53 (veto, Clarification 3): the gap marks as planned. Recorded in the spine as the Consistency Conventions row "Status marks" (Rule 20), not as an AD-18 amendment: AD-18 is cited by other open epics' specs, so the runner leaves its Rule text alone (doctrine U7, U14).

**Recommended spine line for the lead (Rule 20; applied as the Conventions row "Status marks", see U-53):** AD-18 gains "HeartbeatIn also records each gap of more than one clock minute as the mark `heartbeatGap.<start>` (`{start,end,missed}`), read through `OcuTalon.Schedule.Heartbeat.Gaps(from,to)`; the task sets `RescheduleOnStart` 1 (Story 8.1)."

**Shard time:** the run adds about 1 to 2 minutes to `lane-b` (the 75 s ceiling plus a stop and a start). Record the class timings in Rule 21's section.

## Verification

Variables in every `ci/iris.sh` and `ci/warm.sh` call: `L="OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=implement'"`, written out in full on each call. Every call runs in the foreground with `timeout: 600000`, one per call.

**Commands:**
- `(once, first)` `$L OCUTALON_RUN_TAG=e8s1implw ci/warm.sh up`. Run it after `Install/Step/Schedule.cls` exists, so the start creates the task. Expected: the warm stack is ready.
- `(loop)` `$L OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s1implw ci/iris.sh class OcuTalon.Test.Schedule.HeartbeatLogic`. Expected: `CLASS ... passed`.
- `(loop)` the same command for `OcuTalon.Test.Schedule.Heartbeat`. Expected: passed. AC 1 is proven again on the fresh shard, because a warm start predates later edits.
- `(loop)` the same command for `OcuTalon.Test.Install.Production`, then `OcuTalon.Test.Install.Registry`. Expected: passed (once ruling 1 is applied).
- `(once)` `$L OCUTALON_RUN_TAG=e8s1impl ci/iris.sh shard lane-a`, then `shard lane-b`, then `shard lane-a --reverse`, then `shard lane-b --reverse`. Expected: every `CLASS` line passed.
- `(once)` `$L OCUTALON_RUN_TAG=e8s1impl ci/iris.sh live production`, then `live production-restart`, then `live install-upgrade`, one per call. Expected: all pass, `check_clean_start` included (ruling U-52 keeps the stub `Checks` free of ticks).
- `(once)` `bash ci/checks.sh`. Expected: every block PASS (storage, test-ci-config).
- `(once, last, also after a failure)` `$L OCUTALON_RUN_TAG=e8s1implw ci/warm.sh down`, then `$L OCUTALON_RUN_TAG=e8s1impl ci/iris.sh teardown`.

**Shared surfaces:**
- The Task Manager task list (a new `OcuTalon heartbeat` task at every start).
- `Registry.Areas()` (gains `Install.Step.Schedule`).
- `HeartbeatIn`'s `STUB` (Story 11.5's release check, and the oracle row in `Test/Core/ProductionItems.cls`).
- The event log after a start (ticks into the stub `Checks`; ruling 2).
- `StatusMark` rows (the new marks).
- `ci/units.sh` lane-b areas, and Rule 21's lane-b class count.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Clarification Needed

1. **RULED by the orchestrator (option (a), one-time extension, HeartbeatIn's row only) — kept for the record. Contended path.** Building `HeartbeatIn` deletes its `STUB`, so `OcuTalon.Test.Install.Production.TestStubsAnswer` needs HeartbeatIn's oracle row changed. The row is line 33 of `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls` (`"stub": 1` → `"stub": 0`), and that file is in Epic 2's `Test/Core/**`. The file says lane B edits its own rows when it builds an item, and the edit is one line. Recommended: authorize Epic 8 to make this one-line edit.
2. **RULED U-52 (veto, option (b)) — kept for the record. Cross-lane: the stub `Checks` logs an error.** Once the task exists, the first tick after every production start reaches Lane A's stub `OcuTalon.Checks.Process`. The stub answers `<Ens>ErrBPTerminated` and writes an error row: Story 0.6 measured this stub behaviour (`test-production.sh` row 16), and `lib-live.sh` `check_clean_start` warns that such calls write error rows. Ens.Actor logs a repeated text only once per job (inference, from its source). So the tick fails `check_clean_start` in `docker/tests/test-production.sh` (row 14) and `test-production-restart.sh` (first start) whenever it lands before that check, and it can fail Lane A's `OcuTalon.Test.Agent.Runners`, which asserts that no Type 2 or 6 row appears after its mark. Epic 8 owns none of these files (AD-33; `docker/tests` is contended by Epics 2 and 10). Options:
   - (a) Lane A's `Checks` stub answers an `OcuTalon.Msg.Tick` with OK and no response, and keeps 5003 for every other request. `TestStubsAnswer` sends `Ens.StringRequest`, so it stays green. Recommended.
   - (b) `HeartbeatIn` skips the send while the class behind `Checks` carries `STUB`. This narrows the epic's second criterion (a Tick reaches `Checks`) on a real install until Epic 5, so it is ask-first.
   - (c) The live checks ignore `Checks`' not-implemented rows. Those paths are contended.
3. **RULED U-53 (veto, as planned) — kept for the record. Veto window: stored data (recommended as planned).** Gaps become `StatusMark` rows `heartbeatGap.<start>`, with no schema change and no purge: one row per outage, kept like every other mark.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Plan round 1 halted `blocked` on three intent gaps; all three are ruled (orchestrator: Clarification 1, option (a); lead: U-52 and U-53, veto). The lead applied the rulings and set `ready-for-dev` (re-dispatch protocol: the rest of the plan stands).
