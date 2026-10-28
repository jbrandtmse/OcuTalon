---
title: 'Story 8.1: The heartbeat ticks every minute and catches up once after a restart'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: '1939c9ce8a82c7484d914dec680a245ea498142f'
baseline_commit: '1939c9ce8a82c7484d914dec680a245ea498142f'
review_loop_iteration: 0
followup_review_recommended: true
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

### Review Findings

Code review of 2026-10-24 (first review; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all at the session's model; diff `1939c9c..HEAD` plus QA's uncommitted tests and two untracked fixtures). 29 rows from the layers (32 claims once three compound rows were split), plus 2 from the reviewer's own Rule 2 check; 12 entries survived triage: high 0, medium 4, low 8. Each entry: severity / fix-risk / footprint / spec-status.

- [x] [Review][Patch] `HeartbeatTask.Quiet`'s fallback (`Quit ..Stopped()`, the run that a stop overtakes after the task's own check) was pinned by no test: `Quit 0` left every test green [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:307] - medium / low (one assertion in a method that already stops the production) / in-story / clear. Sources: blind-hunter, verification-gap. Fixed: `TestStoppedThenStarted` asserts, while the production is stopped, that `Quiet(<Ens>ErrBusinessDispatchNameNotRegistered)` is 1 (`TestQuiet` shows the same code is 0 while it runs); mutation line under `## Verification`.
- [x] [Review][Patch] `TestRecordKeepsTickWhenGapFails` wrote and compared the marks with the real task live (the previous test's `OnAfterOneTest` resumes it), so a scheduled run between the two `Marks()` reads turned it red [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:395] - medium (Rule 19 hermeticity) / low / in-story / clear. Sources: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor. Fixed: the method holds the task first (`SuspendTask`).
- [x] [Review][Patch] `Prepare` did not fully hold off the real task: it swapped the class behind Checks before suspending, `HoldTask` waited only for a run that already held the lock (and ignored `$Test`), a run that began before the suspension could still send and record after `Prepare` returned, and a Tick in flight could be recorded by the double after the record was killed [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:647] - medium (Rule 19: acts before the system under test is idle) / med (the shared helper of every live test) / in-story / clear. Sources: blind-hunter, edge-case-hunter, verification-gap. Fixed: `Prepare` suspends first, then swaps, then waits for Checks to be idle (`Settle`, the DW-28 check extended to any item with its own job; `SettleScheduler` calls it) and clears the gap marks; `HoldTask` checks `$Test` and holds the heartbeat lock until `ResumeTask`, so a run that slipped past the suspension waits its 5 s and ends without sending or recording, while the tests' own runs in this process take the lock again (incremental).
- [x] [Review][Patch] `Test.Schedule.Heartbeat.WaitFor(node, value, seconds)` was a near-copy of `Test.Agent.RunnerFixture.WaitFor(node, seconds)` (src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls:158), which the class already reuses, with no stated reason [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:620] - medium (Rule 2) / low / in-story / clear. Source: reviewer (Rule 2 check). Fixed: the copy is deleted and `TestLockBusy` calls RunnerFixture's (its node is only ever set to 1).
- [x] [Review][Patch] "in a session of its own" asserted `header.SessionId > 0`, which every header satisfies (AD-26 as the spec cites it) [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:256] - low / low / in-story / clear. Sources: blind-hunter, acceptance-auditor. Fixed: `SessionId` equals the header's own id (the Tick opens its session; `Ens.BusinessService` clears `%SessionId` before each `ProcessInput`); demonstrated with a mutation (below).
- [x] [Review][Patch] `Restore` dropped the statuses of its mark writes, so `OnAfterAllTests` returned OK with a mark left wrong [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:161] - low / low / in-story / clear. Source: blind-hunter. Fixed: both writes append to the returned status.
- [x] [Review][Patch] `WaitForSafeMinute` waited for the next minute with no ceiling in code (Never: "Waits poll up to a stated ceiling") [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:710] - low / low / in-story / clear. Source: acceptance-auditor. Fixed: a 16 s deadline.
- [x] [Review][Patch] AC 7's two absence checks counted only HeartbeatIn-to-Checks headers whose body is a Tick, narrower than the AC's "no `Ens.MessageHeader` goes from `HeartbeatIn` to `Checks`" [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:358] - low / low / in-story / clear. Source: acceptance-auditor. Fixed: both count every HeartbeatIn header (`HeartbeatHeaders`); AC 7's mutation re-run red (below).
- [x] [Review][Defer] `Heartbeat.Gaps` lists the `heartbeatGap.` family with a read-only SELECT, while the spine's "Status marks" row says marks are read through `Get(mark)` [src/ocutalon/cls/OcuTalon/Schedule/Heartbeat.cls:65] - deferred: low / med / in-story / spec-bound in tension (the same row names `Gaps` as the family's reader, `Get` cannot enumerate, and the Code Map keeps `StatusMark` read-only); DW-169 wontfix-accepted (`reopen_if` in the ledger). Source: acceptance-auditor.
- [x] [Review][Defer] The QA fixtures `HeartbeatTaskElsewhere` and `HeartbeatTaskMissingItem` extend `%SYS.Task.Definition` and ship in `OcuTalon.PKG`, so a judges' Task Manager wizard can list them as task types (inference) [src/ocutalon/cls/OcuTalon/Test/Schedule/HeartbeatTaskElsewhere.cls:5] - deferred: low / med (removing them reshapes `HeartbeatTask`'s production code and two tests) / in-story / clear; DW-170 wontfix-accepted. Source: acceptance-auditor.
- [x] [Review][Defer] `Settle`/`SettleScheduler` repeat `lib-live.sh`'s `settle_scheduler` (DW-28) with a weak stated reason ("another language": the shell line is ObjectScript too) [src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:868] - deferred: low (Rule 2, weak reason) / low / out-of-footprint (`docker/tests` is contended) / clear; DW-171 wontfix-accepted. Source: reviewer (Rule 2 check).
- [x] [Review][Defer] Rule 21's lane-b class count (24) and class timings were not updated for `Test.Schedule` (the Design Notes' "Shard time" asks for it) [_bmad/custom/skill-rules.md] - deferred: low / low / out-of-footprint (agent-context file; the lead's decide-tier append) / clear; DW-172 wontfix-accepted. Source: blind-hunter.

**Rejected** (verdict and reason, one line each):
- false - BH3, AC 5's "the double records it once" checked right after the first tick: it fails when one run sends more than one Tick naming the old tick (the per-minute replay "once" guards); a second run re-sending a catch-up is pinned by `TestCatchUp` ("the tick mark moved on", and the next-minute half).
- false - EH3, `Prepare`'s bare `$$$ConfigClassName("Checks")`: `RunningReason` has just shown that `OcuTalon.Production` runs, and Checks is an item of it (Production.cls:42), so the runtime node exists.
- false - VG-O3, "and the same schedule" barely fails: it checks AC 1 as worded; "leaves an existing task alone" is Story 0.2's step, pinned by `Test.Install.Registry` `TestTasksStep`.
- false - AA3 (second part), the fixed `Hang 2` in `AssertStubSkipped`: an absence check needs a bounded wait, and the synchronous header check before it is the strong one (as in the implement review's VG-O6).
- false - AA7, AC 5 restarts with `Install.Step.Production.Start()`, not `Run()`: `Start()` is the Production step's start that `Run()` ends with; `Run()`'s eval switch and seeding are install-time and do not bear on the heartbeat.
- false - AA10 (second part), the QA files are uncommitted: the lead commits them after the smoke gate; not a defect.
- low, by-design - BH7, the asynchronous-send margin (hang 5 s, assert under 5 s): AC 3 fixes both numbers, and a synchronous send cannot return before the double's 5 s `Hang` ends (the mutation measured 5.01 s).
- low, by-design - BH8, no IRIS-restart test of the heartbeat: AC 2 and the epic ("a test checks this on the task's definition") scope a restart to `RescheduleOnStart` 1; AC 5 covers the production stop and start.
- low, by-design - AA2, AC 1's "within 60 s" observed as a run in the history within 75 s: Decided in-stage, because the next-run columns are not reliable (Task 0 (a), measured).
- low, rejected - BH10, EH5, AA10 (first part), the Auto Run Result's file list, method count and residual risks predate the QA stage, and the cycle log's `mutations_demonstrated=7` counts a re-run: the fix edits the spec's per-pass record (Rule 14) and the lead's cycle log; QA's additions are recorded under `## Verification`.
- low, rejected - EH4, `Next` with an empty or unreadable `now` would make `Record` delete the tick mark: `HeartbeatIn` always passes `Data.Time.NowUtc()`; a guard for a caller that does not exist.
- low, rejected - AA4, `Gaps` compares bounds as strings and does not validate them: the contract says UTC `YYYY-MM-DDThh:mm:ssZ`, for which string order is time order; validation is a guard with no caller to need it.
- low, wontfix-theoretical - AA9, `Quiet`'s fallback also swallows a `ProcessInput` failure when a stop coincides: it takes a store failure and a stop in the same run; the Design Notes' quiet rule ("a failure after which the production no longer runs") is the documented behaviour. Real if a task history ever shows an OK run whose Tick or marks are missing with the production running.

Rule 3: the story has no user-facing surface of its own (a background task; Story 8.2 shows its stalled warning), and its tests run against the real Task Manager and production on throwaways (`TestTaskDeclared`, `TestStoppedThenStarted`), so real-runtime evidence is present either way. Rule 6: AD-1, AD-5, AD-18, AD-22, AD-23, AD-26, AD-29, AD-33 and rulings U-52 and U-53 match the code; the ProductionItems change is HeartbeatIn's row only.

## Spec Change Log

- 2026-10-24, lead spec gate (runner C, unattended): Clarification 2 ruled U-52 (veto: option (b), HeartbeatIn sends no Tick while the class behind `Checks` carries `STUB`; marks still recorded; matrix row, task and AC 7 added). Clarification 3 ruled U-53 (veto: gap marks as planned; spine Consistency Conventions row "Status marks" added, Rule 20). Clarification 1 (contended `Test/Core/ProductionItems.cls`) sent to the orchestrator.
- 2026-10-24, orchestrator ruling on Clarification 1 (U14, category decide, policy 47276b4): option (a). A one-time footprint extension for `Test/Core/ProductionItems.cls`, HeartbeatIn's row only (line 33, `"stub": 1` to `"stub": 0`); no other row or line. The task is unblocked and AC 6 restated; status set to `ready-for-dev` by the lead.

## Review Triage Log

### 2026-10-24 - Review pass
- verdicts: 33 findings - high 0, medium 4, low 23, false 6, maybe-false 0
- findings:
  - `[low]` `[patch]` BH1: `$$$ConfigClassName` is a bare global read, so `TargetBuilt`'s no-class branch is dead and `Restore` can raise - verified: `Set x = ^Ens.Runtime("ConfigItem","NoSuchItem","ClassName")` raises `<UNDEFINED>` on the warm stack; both reads wrapped in `$Get`.
  - `[low]` `[patch]` BH2: a failed `OnBeforeAllTests` still runs `OnAfterAllTests`, and `Restore` would start a production the class never stopped - verified in `%UnitTest.Manager` (`exit` block calls `OnAfterAllTests` after a failed `OnBeforeAllTests`); `OnAfterAllTests` now returns at once unless `Saved`.
  - `[medium]` `[patch]` BH3: failed send, failed gap-mark write, disabled item and quiet codes have no test (same root cause as VG1, VG2, IA2) - added `TestSendFails`, `TestRecordKeepsTickWhenGapFails`, `TestDisabledItem` and `TestQuiet`, each with a mutation line.
  - `[low]` `[reject]` BH4: send-then-record makes a catch-up at-least-once when `Record` fails - by-design: the order send, gap mark, tick mark is in the intent contract, and a failed `Record` (a store error) costs one more catch-up Tick.
  - `[low]` `[patch]` BH5: `Gaps` can return a false all-clear - the JSON-array case is real (an array reads as a gap: `a.start` is `a[0]`); guarded with `%IsA("%Library.DynamicObject")` and a `TestGaps` row. The unchecked `SQLCODE` of a SELECT on a table that exists, and unvalidated bounds (the contract says UTC times), are theoretical and left.
  - `[false]` `[reject]` BH6: `WaitRuns`/`RunErrors` may judge a run that has not finished - `%SYS.Task.History` rows are written when a job completes (class doc), and no heartbeat row on the stack has `LastFinished` 0 (query on the warm stack).
  - `[false]` `[reject]` BH7: the time-zone tests may pass without a zone taking effect - `$SYSTEM.Process.TimeZone("America/New_York")` makes `ToLocal("2026-11-01T06:30:00Z")` read 01:30 on the warm stack; the `RestoreZone` mapping of an undefined zone concerns a test process only.
  - `[low]` `[reject]` BH8: gap marks are never aged out - by-design: ruling U-53 keeps one row per outage like every other mark, with no purge.
  - `[low]` `[patch]` BH9: the lock name is a repeated literal (now `Heartbeat.#LOCK`, used by `HeartbeatIn` and the tests); a lock timeout leaves no trace - left, the spec says the run ends OK and sends nothing, and Story 8.2's stalled warning is the signal (wontfix-accepted, reopen_if a lock timeout is seen on a real install).
  - `[low]` `[patch]` BH10: inaccurate comments - `TestStoppedThenStarted` no longer claims AC 6, and the Install.Step.Schedule comment no longer claims a measurement over "the afternoon" for the whole-day window.
  - `[low]` `[patch]` EH1: undefined-node read in `TargetBuilt` - same root cause as BH1.
  - `[low]` `[reject]` EH2: second catch-up Tick after a failed `Record` - same as BH4 (by-design).
  - `[low]` `[reject]` EH3: a lock timeout writes no log row - same as BH9 (wontfix-accepted, reopen_if above).
  - `[low]` `[reject]` EH4: a stuck `Checks` lets Ticks queue up - the send is asynchronous by the intent contract; a bounded queue is Checks' and Story 8.2's concern (wontfix-accepted, reopen_if Epic 5's tests show a queue of Ticks after an outage).
  - `[low]` `[patch]` EH5: a gap mark holding a JSON array aborts or pollutes `Gaps` - same as BH5 (patched).
  - `[low]` `[reject]` EH6: a failed gap SELECT returns an empty array - theoretical: the table exists in the same namespace, and a failed SELECT on it is a larger fault than a missing gap.
  - `[false]` `[reject]` EH7: `AddSeconds` with `1E200` raises - it returns "" on the warm stack, as documented.
  - `[low]` `[patch]` EH8: `ChecksDouble` counted before it recorded the tick, so a reader could see the count without the tick - the tick is set first, then the count.
  - `[low]` `[patch]` EH9: `Prepare` killed the double's record before suspending the task - the task is suspended first; `TestStoppedThenStarted` takes its record, header and history marks after the stop.
  - `[low]` `[patch]` EH10: `TestStoppedThenStarted` maps to AC 5 and AC 6 - the comment is corrected (same as BH10); AC 6 is `TestStubsAnswer`.
  - `[medium]` `[patch]` VG1: a failed send and a failed gap-mark write are pinned by no test - `TestSendFails` and `TestRecordKeepsTickWhenGapFails` added (mutation lines written).
  - `[medium]` `[patch]` VG2: the disabled-item branch of `Quiet` is pinned by no test - `TestDisabledItem` (the item disabled and enabled again through `EnableService`) and `TestQuiet` added.
  - `[low]` `[patch]` VG3: `TimePeriodEvery`, `DailyStartTime` and `DailyEndTime` are compared only with the declaration - the literal assertion now covers all seven fields; the fresh-stack mutation `"DailyStartTime": 43200` is red on it alone.
  - `[low]` `[patch]` VG-O1: mutation lines are not literally `mutation:` and some clauses have none - lines rewritten as `mutation: ...`; one mutation per AC is the rule, not one per assertion.
  - `[low]` `[patch]` VG-O2: `ChecksStub` has no executed host until Story 5.6 - `TestStubFixtureSkipped` runs it today.
  - `[false]` `[reject]` VG-O3: `WaitRuns(0, ...)` accepts any past run - that is its purpose there: a gate that the first run happened before the next-run read, which `SecondsToNextRun` then waits to be in the future.
  - `[low]` `[patch]` VG-O4: a scheduled run could land between the record kill and the stop in `TestStoppedThenStarted` - the marks are taken after the stop.
  - `[low]` `[patch]` VG-O5: same as EH9 (patched).
  - `[false]` `[reject]` VG-O6: `Hang 2` is a fixed delay - an absence assertion needs a bounded wait, and the synchronous header check before it is the strong one.
  - `[low]` `[reject]` VG-O7: restoring the found tick mark lets the real task record a gap for the minutes the tests held it - an honest record on a throwaway (wontfix-accepted, reopen_if a later story's test asserts `Gaps` over a window that includes this class's run time).
  - `[false]` `[reject]` IA1: `OnTask` is called in the test process - the ACs say "when `HeartbeatTask.OnTask()` runs"; the Task Manager's own run is exercised by AC 1 and AC 5.
  - `[medium]` `[patch]` IA2: intent items without a test (failed send, failed gap mark, quiet codes, no event-log row on success) - covered by the tests added for BH3; `TestCatchUp` now asserts no event-log row of HeartbeatIn on success (mutation line written).
  - `[low]` `[reject]` IA3: smaller divergences (a mark restore restamps `RecordedAt`; `Seconds`/`AddSeconds`/`Gaps`/`RescheduleOnStart` are additions; `Gaps` reads marks with SQL) - all stated in the spec's tasks or Design Notes; `StatusMark` has no list method and is read-only here.

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
- (Implement stage.) `Heartbeat.Gaps` counts a gap that only touches the window (its end equals `fromUtc`, or its start equals `toUtc`) as overlapping, and an empty bound leaves that side open. A false all-clear in the digest is worse than one gap too many.
- The heartbeat lock is `Lock +^OcuTalonP.HeartbeatLock:5` (a name under the private prefix, no data behind it).
- The task's quiet rule is: not the running production (checked before any call, because `CreateBusinessService` writes one error row to the event log for every call made while the production is not running, measured), or a failure that is `ErrProductionQuiescent`, `ErrConfigDisabled` or `ErrProductionNotRunning`, or a failure after which the production no longer runs. A stop that lands between the check and the call can still write that one row.
- `Data.Time.Seconds` reads with `$ZDateTimeH(date time, 3, 1)` with no zone, so the scale is the same in every process zone and across the repeated hour of a daylight-saving change. It gives "" for dates outside 1840-12-31 to 9999-12-31 (`LASTSECOND`).
- `TestTaskDeclared` asserts AC 1's "next run within 60 s" as a run in the Task Manager's history within `RUNSECONDS` (75 s) after the check, not as a read of the task's `DayNextScheduled`/`TimeNextScheduled` (the spec's `NextScheduledDate`/`NextScheduledTime` do not exist on `%SYS.Task`; see Task 0 (a)). Between runs those columns hold the start of the last run, and they jump ahead at a run (measured, below).
- `TestLockBusy` (not an acceptance criterion) pins the lock rule of Always: a job runs the task while the test holds the lock. `Test.Schedule.ChecksStub` is a stub used by `TestStubSkipped` only once Lane A's class behind `Checks` no longer carries `STUB` (Story 5.6), so the test keeps pinning ruling U-52 after Epic 5 without a change to this epic's files.
- Clock-minute races: the tests that set a mark "N minutes back" wait (up to 15 s) for a clock second of 45 or less, and compute the expected `missed` from the minutes of the two times as well as asserting the spec's 6, 2 and 0.
- Every test class puts the tick mark back to the value it found, and all gap marks back to the set it found, while the real task is held suspended; the real task then records one honest gap for the minutes the tests held it (and, with Lane A's stub behind `Checks`, sends no Tick for it).
- (Review pass.) `Heartbeat.Gaps` lists the gap marks with a read-only `SELECT` on `OcuTalon_Data.StatusMark`, because `StatusMark` is read-only for this story and has no list method; marks are written and the tick mark is read only through `Record`/`Get`. The lock name is `Heartbeat.#LOCK`. `HeartbeatIn` reads the class behind `Checks` with `$Get`, so an item with no runtime node sends and fails with its reason instead of raising.
- (Review pass.) `TestTaskDeclared` opens the task object again (after releasing the first) before it compares the schedule after the Tasks step ran again, because `%OpenId` of an object that is still held returns the held instance and the comparison would read the same fields twice. `TestStubFixtureSkipped` runs the `ChecksStub` fixture today, so that `TestStubSkipped` can fall back to it after Story 5.6 with a fixture that has run.

**Rulings (lead spec gate, unattended, policy 47276b4):**
- Orchestrator ruling on Clarification 1 (U14, decide): option (a). Epic 8 may change HeartbeatIn's row of `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls` (line 33, `"stub": 1` to `"stub": 0`) and nothing else in that file. The file's header says Lane B edits its own rows when it builds one of its items; Epic 2's edits to the file (lines 18-19, 24, 26-28) merge cleanly with it, and a conflict at integrate-forward would be a plain union. Reported under `footprint_extensions:`.
- U-52 (veto, Clarification 2): option (b). While the class behind `Checks` carries `STUB`, `HeartbeatIn` sends no Tick and records the marks. Rejected (a), Lane A's stub answering a Tick with OK: another lane's file (AD-29, AD-33), and AD-29's Rule that every unbuilt item answers "not implemented". Rejected (c): contended `docker/tests`, and it would hide real error rows. No release runs the skip (Story 11.5 refuses an enabled stub), and Epic 5's built `Checks` receives every tick with no change here.
- U-53 (veto, Clarification 3): the gap marks as planned. Recorded in the spine as the Consistency Conventions row "Status marks" (Rule 20), not as an AD-18 amendment: AD-18 is cited by other open epics' specs, so the runner leaves its Rule text alone (doctrine U7, U14).

**Recommended spine line for the lead (Rule 20; applied as the Conventions row "Status marks", see U-53):** AD-18 gains "HeartbeatIn also records each gap of more than one clock minute as the mark `heartbeatGap.<start>` (`{start,end,missed}`), read through `OcuTalon.Schedule.Heartbeat.Gaps(from,to)`; the task sets `RescheduleOnStart` 1 (Story 8.1)."

**Shard time:** the run adds about 1 to 2 minutes to `lane-b` (the 75 s ceiling plus a stop and a start). Record the class timings in Rule 21's section.

**Task 0 results (measured on the warm throwaway `e8s1implw`, IRIS 2026.3.0AI build 154, 2026-10-24, unless marked (inference)):**
- (a) The task. The Tasks step created it at 13:28:22 (task history "Create OcuTalon heartbeat"). Its first `DayNextScheduled`/`TimeNextScheduled` read day 67867 and 60 (00:01:00 of the start date, already past). The Task Manager's first pass wrote the history note "Task Has Expired for 2026-10-24 00:01 Continuing from 2026-10-24 13:28" and ran the task at 13:29:00, 38 s after the creation. From then on it ran once at every minute boundary (13:29:00 to 13:43:00 and after, one history row each, `Status` 1, `Error` "Success"), and the next run was always the following minute (33 s ahead at 13:32:27). The tick mark followed each run. So `DailyEndTime` 0 does not narrow the schedule over the afternoon measured here (13:29 to 13:43 and later, container clock); that it covers the whole day stays (inference), from InterSystems' own every-minute task `%SYS.Task.DeepSeeUpdate.Schedule`. The next run is within 60 s once the first pass is done. (Measured in the review pass, on the warm stack, with fresh SQL reads of the columns every 2 s: between runs `TimeNextScheduled` is the start of the last run (52705 reads 52680, 52741 reads 52740) and it later reads a run ahead (52801 reads 52860), so it is no reliable "next run" and the test observes the history instead.) The properties are `DayNextScheduled` and `TimeNextScheduled` ($H day and seconds, a "~" list for several times a day); `NextScheduledDate`/`NextScheduledTime` do not exist. `LastSchedule`, `LastStarted` and `LastFinished` are $H strings. History of a failed run: `Status` holds the error status ("0 ..."), `Error` is empty and `ER` is set; a run that returned OK has `Status` 1, `Error` "Success" and an empty `ER`.
- (b) `CreateBusinessService("HeartbeatIn")`. Running: OK. Production stopped: `<Ens>ErrBusinessDispatchNameNotRegistered` ("Business dispatch name 'HeartbeatIn' is not registered to run"), with `IsProductionRunning` 0. While it stops: `IsProductionRunning` turns 0 at the start of the stop and the status is that same code for the whole stop (polled every 50 ms: one OK, then NotRegistered until stopped); no `ErrProductionQuiescent` was seen. While it starts: the same code until `IsProductionRunning` is 1, and OK from the next poll on. Item disabled (`EnableConfigItem`): `<Ens>ErrConfigDisabled` with `IsProductionRunning` 1, and `HeartbeatTask.OnTask()` returned OK. During an `UpdateProduction` that restarts `Checks`: OK throughout. `ErrProductionQuiescent` is returned by `CreateBusinessService` and by `ProcessInput` when `Ens.Job.ShouldBeQuiescent()` is true (inference, from `Ens.Director` and `Ens.BusinessService` source); it stays in the quiet list. Every call made while the production is not running also wrote one type 2 row to the event log, with an empty `ConfigName` (12 calls, 12 rows); so the task checks `IsProductionRunning` first.
- (c) `ProcessInput` takes no input object: `ProcessInput("", .out)`, `ProcessInput(, .out)` and `ProcessInput()` each returned OK, and `out` is the Tick. The task passes "".
- Class timings on the warm stack: `HeartbeatLogic` 0.02 to 0.06 s; `Heartbeat` 105 to 138 s (`TestStoppedThenStarted` 80 to 100 s of it, `TestCatchUp` 5 to 13 s, `TestLockBusy` 5 s, `TestStubSkipped` 3 to 6 s, `TestTaskDeclared` about 2 s). The lane-b shard grows by about 2 minutes.

## Verification

Variables in every `ci/iris.sh` and `ci/warm.sh` call: `L="OCUTALON_LOCK_DIR=<the lane-c lock folder named in the dispatch> OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=implement'"`, written out in full on each call. Every call runs in the foreground with `timeout: 600000`, one per call.

**Commands:**
- `(once, first)` `$L OCUTALON_RUN_TAG=e8s1implw ci/warm.sh up`. Run it after `Install/Step/Schedule.cls` exists, so the start creates the task. Expected: the warm stack is ready.
- `(loop)` `$L OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s1implw ci/iris.sh class OcuTalon.Test.Schedule.HeartbeatLogic`. Expected: `CLASS ... passed`.
- `(loop)` the same command for `OcuTalon.Test.Schedule.Heartbeat`. Expected: passed. AC 1 is proven again on the fresh shard, because a warm start predates later edits.
- `(loop)` the same command for `OcuTalon.Test.Install.Production`, then `OcuTalon.Test.Install.Registry`. Expected: passed (once ruling 1 is applied).
- `(once)` `$L OCUTALON_RUN_TAG=e8s1impl ci/iris.sh shard lane-a`, then `shard lane-b`, then `shard lane-a --reverse`, then `shard lane-b --reverse`. Expected: every `CLASS` line passed.
- `(once)` `$L OCUTALON_RUN_TAG=e8s1impl ci/iris.sh live production`, then `live production-restart`, then `live install-upgrade`, one per call. Expected: all pass, `check_clean_start` included (ruling U-52 keeps the stub `Checks` free of ticks).
- `(once)` `bash ci/checks.sh`. Expected: every block PASS (storage, test-ci-config).
- `(once, last, also after a failure)` `$L OCUTALON_RUN_TAG=e8s1implw ci/warm.sh down`, then `$L OCUTALON_RUN_TAG=e8s1impl ci/iris.sh teardown`.

**Mutations (Rule 19).** Each is applied to the file, run on the warm stack `e8s1implw` (the `HeartbeatLogic` class reloads the changed classes, then the one test method runs), reverted to a byte-identical file (`cmp`), and the same method is run green again on the same stack. After the patches of the review pass, `OcuTalon.Test.Schedule.Heartbeat` passed as a whole (139 s warm), and `HeartbeatLogic`, `Test.Install.Production` and `Test.Install.Registry` passed.
- mutation: AC 1, `TestTaskDeclared`: `Install/Step/Schedule.cls` declares `"DailyIncrement": 2` instead of 1 (warm: the task made from the right declaration differs from it) -> red on "the task carries the declared DailyIncrement". On a fresh stack (`ci/iris.sh class`, tag `e8s1impl`, the task made from the mutated declaration) `"DailyStartTime": 43200` -> red on "it runs every minute, all day" alone, since the task then equals its declaration.
- mutation: AC 1, the run within a minute, `TestTaskDeclared`: the real task suspended before the test (a saved `Suspended` 1) -> red on "the task is not suspended" and on "the next run comes within a minute: the Task Manager ran the task within 75 s"; resumed, the method is green again.
- mutation: AC 2, `TestTaskDeclared`: the same file declares `"RescheduleOnStart": 0` -> red on "AC 2: the declaration sets RescheduleOnStart 1" and "the task carries the declared RescheduleOnStart".
- mutation: AC 3, `TestCatchUp`: `HeartbeatIn` sends with `SendRequestSync` instead of `SendRequestAsync` -> red on "OnTask returns in under 5 s, not after the check" (5.01 s). A second mutation, `Heartbeat.Next` never sets `CatchUp` -> red on "its CatchUp is 1" (and in `HeartbeatLogic`).
- mutation: AC 4, `TestCatchUp`: `Heartbeat.Record` writes no gap mark (`If 0 {`) -> red on "Gaps over the last 10 minutes reads one gap". A second mutation, `Next` without the `- 1` (a next-minute tick counts one missed minute) -> red on the gap JSON, "adds no gap" and "and no gap mark of its own", and in `HeartbeatLogic`.
- mutation: AC 5, `TestStoppedThenStarted`: `HeartbeatTask.Stopped()` always returns 0, so the task calls `CreateBusinessService` on a stopped production -> red on "its history has no error" and "and the quiet end wrote no error row to the event log".
- mutation: AC 6, `Test.Install.Production` `TestStubsAnswer`: `Parameter STUB = 1` put back into `HeartbeatIn` -> red on "HeartbeatIn: OcuTalon.Schedule.HeartbeatIn does not carry STUB", "answers code 5003", "gives no response".
- mutation: AC 7, `TestStubSkipped` and `TestStubFixtureSkipped`: `HeartbeatIn.TargetBuilt()` always returns 1 -> both red on "no message header goes from HeartbeatIn to Checks" and "and still no message header after a wait" (Lane A's stub answers 5003 and writes the error row).
- mutation: Always, lock, `TestLockBusy`: `HeartbeatIn` ignores the lock result (`If 0 Quit $$$OK`) -> red on "nothing was sent" and "and no mark changed".
- mutation: Always, a failed send records nothing, `TestSendFails`: `HeartbeatIn` records the marks whatever the send returned -> red on "and neither the gap mark nor the tick mark is recorded" and "that names the old tick, with CatchUp 1".
- mutation: Always, a failed gap mark leaves the tick mark, `TestRecordKeepsTickWhenGapFails`: `Heartbeat.Record` ignores the status of the gap mark (`If 0 Quit sc`) -> red on "a gap mark that cannot be written returns its status" and "and the tick mark is left as it was".
- mutation: Always, a disabled item ends OK, `TestDisabledItem` and `TestQuiet`: `HeartbeatTask.Quiet` without `$$$EnsErrConfigDisabled` in its list -> `TestDisabledItem` red on "OnTask returns OK" and `TestQuiet` red on "code <Ens>ErrConfigDisabled ends a run quietly".
- mutation: Always, no event-log row on success, `TestCatchUp`: `HeartbeatIn` writes `$$$LOGINFO("tick sent")` after a send -> red on "a run that succeeds writes no event-log row of HeartbeatIn".
- mutation: `Heartbeat.Gaps` leaves out a gap mark that is not a JSON object, `HeartbeatLogic` `TestGaps`: the `%IsA("%Library.DynamicObject")` guard removed -> red on "the window keeps the gaps that overlap it, oldest first" and "the whole day keeps every readable gap" (a JSON array reads as a gap).
- Not pinned by a test (implement stage; both closed by the QA stage below): the quiescent code of the quiet rule on a real production (it was not reproducible, see Task 0 (b); `TestQuiet` pins the mapping with the code), and `OnAfterAllTests` leaving a production alone when `OnBeforeAllTests` failed (no deterministic way to fail it).

**QA stage (gap audit; tests marked `(QA)`).** Files:
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` (QA, seven methods added, nothing removed): `TestFirstTick`, `TestUnreadableMark`, `TestMarkInTheFuture` (matrix rows "First tick", "Unreadable previous", "Previous in the future", through the task on the running production), `TestQuiescent` (the quiescent code on a real production: the test process is made quiescent through the job-request node of its own job, which only `Ens.Job.ShouldBeQuiescent` of that job reads, so the production goes on), `TestFailureReturned` (a failure that is not a quiet one is returned by `OnTask`), `TestOtherProduction` (another production than `OcuTalon.Production` is the one the task belongs to), `TestAfterAllTestsNothingSaved` (`OnAfterAllTests` of an instance that saved nothing, which is the state a failed `OnBeforeAllTests` leaves).
- `src/ocutalon/cls/OcuTalon/Test/Schedule/HeartbeatTaskElsewhere.cls` (QA, new): `HeartbeatTask` with `PRODUCTION` set to a production that does not exist; no Task Manager task has this class.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/HeartbeatTaskMissingItem.cls` (QA, new): `HeartbeatTask` with `ITEM` set to a service that the production does not have; no Task Manager task has this class.

Mutations of the QA stage (Rule 19; warm stack `e8s1qaw`, one test method run per mutation after a reload, reverted to a byte-identical file (`cmp`, and `shasum` of every file of `Schedule/` and `Test/Schedule/` equal to the sums before the first mutation), the method green again after the revert):
- mutation: matrix rows "First tick" and "Unreadable previous", `TestFirstTick` and `TestUnreadableMark`: `Heartbeat.Record` skips the tick mark when the Tick has no `PreviousTickAt` (`If tick.PreviousTickAt = "" Quit $$$OK`; a heartbeat that never records its first tick, or never replaces a garbage mark) -> both red on "its TickAt is the new tick mark" and "the tick mark is a time that is not ''". `HeartbeatLogic` cannot see it (`Next` is pure).
- mutation: matrix row "Previous in the future", `TestMarkInTheFuture`: `Heartbeat.Record` leaves the tick mark alone when it would move it back (`If tick.PreviousTickAt ] tick.TickAt Quit $$$OK`) -> red on "its TickAt is the new tick mark", "the tick mark is a time that is not '<the future mark>'" and "and it is up to now".
- mutation: Always, quiet rule, quiescent code on a real production, `TestQuiescent`: `HeartbeatTask.Quiet` without `$$$EnsErrProductionQuiescent` in its list -> `TestQuiescent` red on "OnTask returns OK => ERROR <Ens>ErrProductionQuiescent", and `TestQuiet` red on its code row. The control assertion shows that the platform's own `CreateBusinessService` gives that code while the production runs.
- mutation: Always, "any other failure is returned", `TestFailureReturned`: `HeartbeatTask.OnTask` ends OK on every failure (`If $$$ISERR(sc) Quit $$$OK`) -> red on "OnTask returns the failure" and on the code row. `TestQuiet` and `TestDisabledItem` stay green under this mutation (they check `Quiet` and the disabled item, not that `OnTask` returns the others), which was the hole.
- mutation: Always, "OcuTalon.Production is not the running production", `TestOtherProduction`: `HeartbeatTask.Stopped` ignores which production runs (`Quit 0` in place of `Quit running '= ..#PRODUCTION`) -> red on "no HeartbeatIn header is written", "and neither mark changed" and "and sends the Tick" (the control run of the real task then adds a second header).
- mutation: `OnAfterAllTests` after a failed `OnBeforeAllTests`, `TestAfterAllTestsNothingSaved`: the `If '..Saved Quit $$$OK` guard removed from `Test.Schedule.Heartbeat.OnAfterAllTests` -> red on "OnAfterAllTests returns OK => ERROR #5001: The task OcuTalon heartbeat has Suspended 0 after the tests, not " and on both sentinel records (`Restore` ran on an instance that saved nothing).
- re-run (not a new mutation): AC 7, the mutation `HeartbeatIn.TargetBuilt()` always 1, now read in full on `TestStubFixtureSkipped`: red on "no message header goes from HeartbeatIn to Checks", on "no error or alert row was written: 2: Checks: ERROR <Ens>ErrBPTerminated ... #5003: Not implemented" and on "and still no message header after a wait". So the error-row half of AC 7 is not a vacuous assertion.
- Runs after the QA tests were added: `Heartbeat` 143 s on the warm stack, and in `shard lane-b` forward 167 s and reversed 166 s on fresh stacks (`HeartbeatLogic` 0.04 s); the shard took 235 s reversed (26 classes). The seven added methods take about 1 s together (the single runs of each method report 0.003 to 0.2 s).
- Not pinned, by choice: the `$$$ConfigClassName` no-class branch of `HeartbeatIn.TargetBuilt` (reaching it takes the runtime node of a running item away, which would break the production for its other jobs); the faithful stop-and-start variant of `OnAfterAllTests` after a failed `OnBeforeAllTests` (a stop and a start cost about 30 s of shard time for an assertion the sentinel version already makes: that failure quits before any property is set, so the instance is a new one).

Mutations of the code review (Rule 19; warm stack `e8s1crw`, the whole `OcuTalon.Test.Schedule.Heartbeat` class run through `ci/iris.sh class` per mutation, the file put back from a saved copy and `cmp`-checked, and `shasum` of every file of `Schedule/` and `Test/Schedule/` equal to the sums of the patched tree after the last revert):
- mutation: Always, quiet rule, a run that a stop overtakes after the task's own check, `TestStoppedThenStarted`: `HeartbeatTask.Quiet` ends with `Quit 0` instead of `Quit ..Stopped()` -> red on "a run that a stop overtakes ends quietly: CreateBusinessService gives not registered while the production is stopped", and on nothing else (before the review no test went red under it).
- mutation: AD-26 as cited (each Tick opens its own session), `TestCatchUp`: `HeartbeatIn` sets `..%SessionId = 1` before the send -> red on "in a session of its own, which Visual Trace shows: the Tick opens it" alone (the earlier `SessionId > 0` passed it).
- re-run (the absence checks of AC 7 now count every HeartbeatIn header): `HeartbeatIn.TargetBuilt()` always 1 -> `TestStubFixtureSkipped` and `TestStubSkipped` both red on "no message header goes from HeartbeatIn to Checks", "no error or alert row was written: 2: Checks: ERROR <Ens>ErrBPTerminated ... #5003: Not implemented" and "and still no message header after a wait".
- Runs after the review's patches: `Heartbeat` passed warm (177.5 s; per method, `TestStoppedThenStarted` 103 s, `TestTaskDeclared` 54 s, waiting for the next minute's run, `TestCatchUp` 5.1 s, `TestLockBusy` 5.1 s, every other under 3.1 s), passed again on the same stack after the last revert (173.4 s), and passed on a fresh stack (`ci/iris.sh class`, tag `e8s1cr`, 177.8 s, ready 53 s).

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

Status: done
Blocking condition: none

**Summary.** One Task Manager task, `OcuTalon heartbeat` (declared by `Install.Step.Schedule.Tasks()`, every minute, `RescheduleOnStart` 1), runs `HeartbeatTask`, which calls the adapterless `HeartbeatIn` through `CreateBusinessService`/`ProcessInput`. `HeartbeatIn` takes one lock (5 s), builds the Tick with `Heartbeat.Next` (minute-bucket `missed`, one catch-up Tick after downtime), sends it asynchronously (never to a `Checks` class that carries `STUB`, ruling U-52), then records the gap mark `heartbeatGap.<start>` and the tick mark `heartbeatTick` (`Heartbeat.Record`). The task ends OK and records nothing when `OcuTalon.Production` is not running or `HeartbeatIn` is disabled. `Heartbeat.Gaps(from, to)` reads the gaps for Story 17.5. `Data.Time` gained `Seconds` and `AddSeconds`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Data/Time.cls`: `Seconds`, `AddSeconds`, `LASTSECOND` (a zone-independent second scale).
- `src/ocutalon/cls/OcuTalon/Schedule/Heartbeat.cls` (new): `TICKMARK`, `GAPMARK`, `TARGET`, `LOCK`, `Next`, `Record`, `Gaps`.
- `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatIn.cls`: the stub replaced (no `STUB`).
- `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatTask.cls` (new): the task, the production rule and the quiet codes.
- `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls` (new): `Tasks()` declares the heartbeat.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/{ChecksDouble,ChecksStub,HeartbeatInFailing,HeartbeatLogic,Heartbeat}.cls` (new): the double, two fixtures and the two test classes (13 methods; `Heartbeat` runs in throwaways and CI only).
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls`: HeartbeatIn's row `"stub": 1` to `"stub": 0` (the orchestrator's one-time footprint extension; nothing else in the file).
- `ci/units.sh`: `Schedule` joins `lane-b`'s areas.
- This spec: Design Notes (Task 0 results, decisions), Verification (mutation lines), the Review Triage Log.

**Review findings.** 33 findings from the four layers: high 0, medium 4, low 23, false 6, maybe-false 0 (see the Review Triage Log). Patched (19 findings in 13 entries by root cause): the `$$$ConfigClassName` bare read, `OnAfterAllTests` after a failed `OnBeforeAllTests`, the tests for a failed send / a failed gap-mark write / a disabled item / the quiet codes / no event-log row on success, the JSON-array gap mark in `Gaps`, the lock name as `Heartbeat.#LOCK`, two inaccurate comments, the AC 1 literal fields, the `ChecksStub` fixture that no test ran, and three test races. Deferred: none (`deferred: []`). Rejected with the reason in the log: 14 rows (by-design: send-then-record order, no gap purge; accepted: lock timeout without a log row, Ticks queued behind a stuck `Checks`, the gap the tests cause on a throwaway; theoretical: a failed SELECT on the mark table; false: six, each with its refutation).

**Follow-up review recommended: true.** Two medium entries were patched (missing tests for the Always clauses), and that test code (`TestSendFails`, `TestRecordKeepsTickWhenGapFails`, `TestDisabledItem`, `TestQuiet`, `TestStubFixtureSkipped`, `HeartbeatInFailing`, and the changed `TestTaskDeclared`) was written after the layers had read the diff. The unverified risk is a flaky or vacuous assertion in that code. It ran green in `Heartbeat` on the warm stack and in `shard lane-b` forward and reversed on fresh stacks, and each new pinning test has a demonstrated mutation. Patched counts by verdict: medium 2 entries (4 findings), low 11 entries (15 findings).

**Verification performed.**
- `(loop)`, warm stack `e8s1implw`, after the last patch: `HeartbeatLogic` passed, `Heartbeat` passed (139 s), `Test.Install.Production` passed, `Test.Install.Registry` passed.
- `(once)`, fresh stacks `e8s1impl`, after the last patch: `shard lane-a` passed (41 classes, 377 s), `shard lane-b` passed (26 classes, 254 s), `shard lane-a --reverse` passed (362 s), `shard lane-b --reverse` passed (226 s; `Heartbeat` 156 s), `live production` passed (row 14 reports no error or alert in the event log at the start), `live production-restart` passed, `live install-upgrade` passed, `bash ci/checks.sh` passed (every block).
- Mutations (Rule 19): 17 demonstrated red and green again, byte-identical after each revert (the lines are in `## Verification`).
- Teardown: `ci/warm.sh down` and `ci/iris.sh teardown`; `docker ps` shows no container of the tags `e8s1impl` and `e8s1implw`.

**Residual risks.**
- A stop of the production that lands between `HeartbeatTask`'s `IsProductionRunning` check and `CreateBusinessService` still writes one error row (measured: every such call writes one), which could trip a live check that asserts no error rows at that moment.
- `TimeNextScheduled` is not a reliable next-run time (measured), so AC 1's "next run within 60 s" is asserted as a run in the history within 75 s; `Heartbeat` therefore takes about 140 to 156 s (the `lane-b` shard grows by about 2.5 minutes). Rule 21's class counts (lane-b 24 classes) are stale: lane-b has 26.
- `Heartbeat.Gaps` lists marks with a read-only SELECT on `OcuTalon_Data.StatusMark`, since the class has no list method.
- When the tests end, the real task records one gap for the minutes it was held suspended (accepted, on a throwaway).
- Not pinned by a test: the quiescent code on a real production, and `OnAfterAllTests` leaving the production alone after a failed `OnBeforeAllTests`.
- Reported footprint extensions: `Test/Core/ProductionItems.cls` (HeartbeatIn's row, ruled). The spec's Verification line 1 no longer holds the local lock path (it failed the `test-boundaries.sh` paths rule); it says `<the lane-c lock folder named in the dispatch>`.
- Shared-scratchpad incident: a helper named `mutate.py` that another runner's `run-mut.sh` calls was overwritten by this stage's first helper and then re-created with the interface `run-mut.sh` uses (`mutate.py apply <file> <old> <new>`, one exact match); the stage's own helpers moved to `scratchpad/e8s1/`.
