---
title: 'A resend cut short by a restart says how far it got'
type: 'feature'
created: '2026-10-29'
status: 'done'
baseline_revision: 'f84b5474b99faa7b52f71bea26b198df972e07af'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      Test.Fix.Stopped asserts that OrdersFromPartner starts again within WAITSECONDS - 10 (50) seconds of R1's ResentAt, which a slow CI runner could miss.
    evidence: |-
      The class stops and starts FixExecutor (TempStopOwn, TempStartOwn, up to two 10-second lock waits) between R1's ResentAt and the restart of the copies' item, then asserts
      the elapsed seconds are at most MARGIN. It passed twice on the developer machine (85 s for the class) and printed no elapsed value. A CI run that shows the elapsed seconds (the
      assertion message names it on a failure) would settle it; if it fails there, the margin or the order of the steps needs to change.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Fix/Stopped.cls:24
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Since Story 7.4, FixExecutor ends every run it waits for. A run whose job is gone never ends, though. That is either a run cut short when IRIS, or the installer's production restart, stopped it, or a run whose waiter stopped on a quiesce or terminate request while the production kept running (DW-395). Its request stays `executing` and its incident `fixing`. The user never hears how far the resend got, and nothing says the run will not be picked up again.

**Approach:**
- At the next start, the Reconcile step calls the Fix area's new `Reconcile()` declaration. It finds each run that started before the production's current start and has not ended, and:
  - marks it interrupted;
  - closes its request through `Approval.FinishExecution(ref, "interrupted")`, so the row ends `failed`.

  Nothing is resumed or resent.
- On each heartbeat `Tick`, `Checks` calls the new `OcuTalon.Fix.Run.Sweep()`. Sweep returns one final `FixResult` for:
  - each interrupted run not yet reported, with the count that went through;
  - each run that no waiter ended, although its copies all completed or failed inside its 60-second wait (DW-395).
- Checks sends each result to IncidentManager. IncidentManager moves the incident and sends `result.interrupted` ("The resend stopped when OcuTalon restarted: 3 of 5 orders went through. The other 2 need a new approval.").
- One lock per run, and one writer of a run's end, make every run end exactly once, whichever job ends it.
- A catalog test pins the three keys.

## Boundaries & Constraints

**Always:**
- **The row and the run are the truth (AD-11, AD-16).** This story adds no stored property, message property, production item, table, message class or catalog key.
- **One writer of a run's end (AD-33).** FixExecutor's class methods `End` and `Mark` are the only code that writes a `FixRun`'s end fields: `EndedAt`, `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted` and `Reason`.
  - **The lock.** Each writes under the run's lock, `^OcuTalon.Fix.Run(<FixRun id>)` (`RUNLOCK`), which it waits for at most `RUNLOCKSECONDS` (2). If it cannot take the lock, another job is ending the run, so the caller leaves the run alone.
  - **`End(run, counts, interrupted, Output sc) As %Boolean`.** It reads the stored `EndedAt` and `Interrupted` with `EndedAtGetStored` and `InterruptedGetStored`, never `%Reload`, so the caller's object is kept. It refuses (gives 0, writes nothing):
    - a run that has ended;
    - for a normal end (`interrupted` 0), a run that `Mark` marked (`Interrupted` > 0 and no `EndedAt`);
    - for an interrupted end, a run that is not marked.

    Otherwise it sets `EndedAt` (UTC now) and the counts from `counts` (`interrupted` defaults to 0), saves, and gives 1. A failed save also gives 1, with the error in `sc`, so the caller goes on as Story 7.4's Finish does.
  - **`Mark(run, total, Output sc) As %Boolean`.** It refuses a run that has ended or is already marked. Otherwise it sets `Total` and `Interrupted` to `total` (the number of targets) and saves.
  - **The callers:** FixExecutor's `Finish` (every end of Story 7.4), `Fix.Run.Interrupt` (Reconcile) and `Fix.Run.Sweep` (Checks). Only the job whose `End` wrote then closes the request, writes the `Action` entry and builds the `FixResult`.
- **FixExecutor (Story 7.4's end, extended rather than copied):**
  - `Finish` calls `End` for a run that has an Id. When `End` refuses, `Finish` closes nothing, audits nothing and sends nothing, and logs one Type 4 line (`LOGENDED`: the Ref and why).
  - `Waiting` leaves out a marked run.
  - Five bodies become public class methods, and the instance methods and seams call them, so Story 7.4's behaviour and its probe stay as they are:
    - `Read`, from `Statuses`;
    - `Tally`, from `Look`'s counting;
    - `FailReason`, which becomes a class method;
    - `ActionEntry`, from `Audit`'s data;
    - `ResultOf`, from `Report`'s `FixResult`: `Final` 1, and `Interrupted` 1 when `counts.interrupted` > 0.
  - `Read` also gives each copy's `at`, its header's `timeProcessed` from `Reader.Evidence`.
  - `Tally` also gives `lastAt`: the latest `at`, in seconds (`Settle.Seconds`), of the copies that are done. It is "" when a copy that is done has no `at`.
- **Reconcile (AD-5, AD-16, AD-23):**
  - **The declaration.** `Install.Step.Fix.Reconcile()` calls `ReconcileWith("OcuTalon.Fix.Run")`. `ReconcileWith` calls that class's `Interrupt(.problems)`, records each problem as one `Warn` line (WARN Reconcile ...), and returns `Interrupt`'s status. That status is an error only when the runs cannot be read.
  - **Which runs.** `Interrupt` goes through every `FixRun` with no `EndedAt` (the seam `Unended`). It takes a run when both hold:
    - its `StartedAt` is before the production's current start. `Started()` gives that start as a UTC stamp, from `^Ens.Runtime("StartTime")` (Task 0 (a)).
    - its request's row is `executing`.
  - **What it does.** For each run it takes, under the run's lock, it calls `Mark` (unless the run is marked already) and then `FinishExecution(ref, "interrupted")`.
  - **Problems.** Each is one problem line, and `Interrupt` goes on:
    - A failed mark: the row is not closed.
    - A failed close: the run stays marked, and Sweep closes the row.
    - No start time: nothing is marked.
  - It is idempotent. It never resends, never waits and sends no `FixResult`.
- **Sweep (AD-16, AD-18).** `Fix.Run.Sweep()` returns a `%ListOfObjects` of final `FixResult`s and resends nothing. It goes through every `FixRun` with no `EndedAt` (`Unended`), each under its lock. A run it cannot lock is skipped this Tick.
  - **A marked run (interrupted):**
    1. If the row is still `executing`, it is closed first (`FinishExecution` interrupted). If that close fails, Sweep logs one Type 3 warning and leaves the run for the next Tick.
    2. The copies are read (the seam `Statuses`, which calls `Read`) and counted (`Tally`).
    3. The counts are:
       - `Total`: the row's targets, else the stored `Total`;
       - `Resent`: `Copies.Count()`;
       - `Completed` and `FailedAgain`, from `Tally`;
       - `Skipped`: 0;
       - `Interrupted`: `Total` - `Completed` - `FailedAgain`, at least 0 (the targets that the restart cut off);
       - `Reason`: `FailReason`, when `FailedAgain` > 0.
    4. `End` (interrupted).
    5. One `Action` entry with the result `interrupted`.
    6. Its `FixResult` (`ResultOf`).

    A read that is not `read` and a missing incident count no copy as completed or failed. So does a read that throws, which also logs one Type 3 warning. A run whose row is gone is ended with its counts, and no entry or result is made.
  - **An unmarked run that no waiter ends (DW-395).** Sweep takes a run when every one of these holds:
    - `ResentAt` is set;
    - its wait is over: now is at least `ResentAt` + FixExecutor's `WAITSECONDS`;
    - its row is `executing`;
    - the read is `read`;
    - no copy is still running;
    - `lastAt` is set and is before `ResentAt` + `WAITSECONDS`. An empty `lastAt` never qualifies, because Sweep cannot tell when the copies were done.

    Sweep ends it as the waiter would have:
    - Story 7.4's counts: `Skipped` = `Total` - `Resent`, and `Interrupted` 0;
    - `End`, then `FinishExecution(ref, "done")` (a failure logs one Type 3 warning, and the rest goes on);
    - one `Action` entry with the result `done`;
    - its `FixResult`.
  - **Sweep leaves these alone:**
    - a run inside its wait (the waiter's);
    - a run with a copy still running, or whose last copy finished after its wait (Story 30.5's);
    - a run with no `ResentAt` (the next start's Reconcile ends it);
    - a run whose row is not `executing`.
  - **Its log lines.** One Type 4 line for each run it ends (`LOGSWEPT`). An exception for one run logs one Type 3 warning, and the next run is still swept.
- **Checks (AD-18, AD-26):**
  - On each `Tick`, after the quiet sweep and before the due checks, `Checks.Fixes()` takes the results of `Fix.Run.Sweep()` (the seam `FixRunSweep`).
  - It sends each to IncidentManager asynchronously, with no answer wanted (the seam `SendFixResult`).
  - Each goes in the incident's trace session (its `TraceHeaderId`, when set), with the request's `TraceRef` as `SuperSession`. Both are put back after each send.
  - A Sweep that throws logs one Type 3 warning (`LOGFIXES`). A failed send logs one (`LOGFIX`, with the Ref), and the others still go. The quiet sweep, the fixes and the due checks each have their own Try/Catch.
  - Checks calls no other Fix code: the dependency rule allows only `Fix.Run.Sweep()`.
- **IncidentManager, Notice, the payload and the page keep their code.** IncidentManager accepts the `FixResult` from Checks as it accepts one from FixExecutor: `Owns`, AD-15's table, `Notice.ResultKey` and `ResultSlots`, and the event after the commit. The row is closed before the result goes, so the key is `result.interrupted`, never `result.stillResending`.
- **Rules that apply throughout:**
  - Log text goes through `Redact.Text`.
  - Producers send keys and slots only (AD-32).
  - Rule 14 applies.
  - The mock logs no request.
  - The testing switch stays off.
  - Tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`, and they run only on throwaways. Classes that drive the production's IncidentManager, FixExecutor or Checks run fresh.

**Never:**
- Nothing of Story 30.5:
  - no in-progress `FixResult` (`Final` 0) and no producer of `result.stillResending`;
  - no "reported in progress" mark;
  - no end for a run whose copies finished after its wait.
- Reconcile, Sweep and Checks never resend or resume anything. There is no retry without a new approval, and never a second `FixResult` for a run.
- No stored property, no `Storage` change, no AD edit, no new grant and no new public text.
- No edit to:
  - `web/**`, `Msg/Catalog/**`, `Watch/Notice.cls`, `Watch/Transitions.cls`, `Watch/Reader.cls` or `Live/Payload/Incident.cls`;
  - `Schedule/**`, `Msg/Tick.cls`, `Core/**`, `ci/**`, `docker/**` or `src/bridge/**`;
  - `Install/**` beyond `Install/Step/Fix.cls`, or `Test/Install/**`, `Test/Msg/**` or `Test/Live/**`.
- Nothing for DW-368, DW-384 or DW-365 (escalated or waiting for the owner).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Cut short by a restart (live, AC 1 to AC 3; `Restart`) | S's incident is noticed with R1 pending over 5 failed orders.<br>FixExecutor is stopped (`TempStopOwn`), then R1 is approved through `Approval.Answer` and the incident is `fixing`.<br>The test plays the run that was cut short:<br>- `StartExecution(R1)`;<br>- a `FixRun` with `StartedAt` now and no `ResentAt`, locked by the test;<br>- the kind's `Execute` over R1's first 3 targets, with OrdersFromPartner running, so 3 copies complete.<br>A first Reconcile step runs (the next row). Then `StartedAt` is backdated to "2000-01-01T00:00:00Z", and the Reconcile step runs again. FixExecutor is started again, the test lets go of the run's lock, and a fixture `Tick` goes to Checks. | **After the Reconcile step:**<br>- R1 is `failed`, with Result `interrupted`;<br>- the run has `Total` 5 and `Interrupted` 5, and no `EndedAt`;<br>- there is no FixResult.<br>FixExecutor's queued Execute, if it was queued, is refused. The run keeps its 3 copies, and R1 has no other FixRun.<br>**After the Tick:**<br>- exactly one FixResult: R1, the incident, `Final` 1, `Interrupted` 1, 5/3/3/0/0. Checks sent it, in the incident's trace session with R1's TraceRef;<br>- the FixRun has `EndedAt`, 5/3/3/0/0 and `Interrupted` 2;<br>- the incident is `resolved`.<br>**What S sees:**<br>- one result Notification, `result.interrupted` {count 5, completed 3, remaining 2}. It renders "The resend stopped when OcuTalon restarted: 3 of 5 orders went through. The other 2 need a new approval.", and has Delivery rows in web and phone;<br>- the last incident event and `/state` list R1 `failed`, with the result {total 5, resent 3, completed 3, failedAgain 0, skipped 0, interrupted 2};<br>- targets 4 and 5 have no copy.<br>**The audit and the mock:** one OcuTalon `Action` entry with the result `interrupted` and the counts; the mock logs no request. | none |
| Started after the start (live; `Restart`, first pass) | The same run while its `StartedAt` is still now | The Reconcile step leaves it: R1 stays `executing`, and the run is not marked. | none |
| Reconcile again (live; `Restart`) | A second Reconcile step over the marked run | Nothing changes, and R1 is not closed a second time. | none |
| No second result (live, AC 3; `Restart` and `Stopped`) | Two more fixture `Tick`s after each result, with the real heartbeat's Ticks as well. Also a run that FixExecutor ended: Raised over 3 orders, approved, `done`. | Each run has exactly one FixResult, across all senders and sessions, and one result Notification. | none |
| Waiter stopped (live, DW-395, AC 4; `Stopped`) | OrdersFromPartner is stopped. R1, over 3 orders, is approved, and its copies stay `Queued` while the waiter waits.<br>FixExecutor is stopped and started again, so the waiter quits.<br>OrdersFromPartner is started, and the copies complete inside R1's 60 s. | - A Tick inside the wait changes nothing.<br>- A Tick after `ResentAt` + 60 s ends the run:<br>&nbsp;&nbsp;- R1 is `done`, and its FixRun holds 3/3/3/0/0 with `Interrupted` 0;<br>&nbsp;&nbsp;- Checks sends one FixResult (`Final` 1, `Interrupted` 0);<br>&nbsp;&nbsp;- S gets `result.allThrough`, "All 3 orders went through.";<br>&nbsp;&nbsp;- one `Action` entry `done`;<br>&nbsp;&nbsp;- the incident is `resolved`.<br>- A further Tick gives nothing. | none |
| Left for the waiter or for Story 30.5 (probe; `Executor`) | Unmarked runs:<br>- inside the wait, with every copy done;<br>- past the wait, with a copy `Queued`;<br>- past the wait, with the last `at` after the wait;<br>- with no `ResentAt`;<br>- with its row `done`. | Sweep returns nothing, and none of them gets an `EndedAt`. | none |
| Interrupted counts (probe) | Marked runs:<br>- 5 targets and 3 copies, 2 `Completed` and 1 `Queued`;<br>- 3 targets and 3 copies, all `Completed`;<br>- 3 copies, 1 `Completed` and 2 `Error`;<br>- a read that is `unreadable`, a read that throws, and a missing incident. | - 5/3/2/0/0 with `Interrupted` 3: `result.interrupted`, with remaining 3.<br>- 3/3/3/0/0 with `Interrupted` 0: `result.allThrough`.<br>- 3/3/1/2/0 with `Interrupted` 0 and the fail reason: `result.failedAgain`.<br>- An unreadable read: `Completed` 0 and `Interrupted` = `Total`, with one warning for the read that throws. | logged |
| The row first (probe) | A marked run whose row is still `executing`; then one whose close fails | - The row is closed `interrupted` before the result comes back, so `Notice.ResultKey` gives `result.interrupted`.<br>- A failed close: no result and no `EndedAt`, and one Type 3 warning. The next Sweep reports the run. | logged |
| Reconcile's problems (probe) | `Started()` gives nothing; a close fails | - No start time: nothing is marked, and there is one problem.<br>- A failed close: the run is marked, and there is one problem.<br>- `ReconcileWith` turns the problems into WARN lines and returns OK. | WARN lines |
| A locked run (probe) | Another job holds `^OcuTalon.Fix.Run(id)` | Sweep returns nothing for the run and writes nothing. | none |
| FixExecutor meets a marked or ended run (probe) | - `End` on an ended run;<br>- a normal `End` on a marked run;<br>- an interrupted `End` on an unmarked run;<br>- the probe's waiter over a marked run. | - Each `End` gives 0 and writes nothing.<br>- `Waiting` leaves the marked run out, and Finish sends, closes and audits nothing (one Type 4 line). | none |
| Checks sends the results (Checks probe; `Runs`) | Canned Sweep results for two fixture requests, the first send failing; then a Sweep that throws | - Both sends are recorded after the quiet sweep, each with its incident's TraceHeaderId and its request's TraceRef.<br>- The failed send logs one `LOGFIX` warning, and the second still goes.<br>- The process's own session is back afterwards.<br>- A Sweep that throws logs one `LOGFIXES` warning, and the due checks still run. | logged |
| The three texts (`NoticeText`) | `result.failedAndSkipped`, `result.stillResending` and `result.interrupted` | - Each key's entry is in `Msg.Catalog.Watch`, with the slots that `ResultSlots` builds for it.<br>- Each key renders P16's text, and its count-of-one form, on web, phone, mailbox and telegram. | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless stated. Line numbers are as of `70eac00`.

**Changed (product):**
- `Fix/Executor.cls` (762 lines):
  - the doc, L3-51;
  - parameters: `WAITSECONDS` L70, `COPYDONE` and `COPYFAILED` L77-79, the `LOG*` texts L82-100;
  - `Run` L279-322, `CouldNotStart` L327 and `Close` L345 (an instance seam; the probe overrides it);
  - `Finish` L357-377: it calls `End`;
  - `Audit` L383-408: its data becomes `ActionEntry`;
  - `WriteAudit` L411;
  - `Report` L419-444: its `FixResult` becomes `ResultOf`;
  - `Wait` L465;
  - `Waiting` L497-513: its SQL at L501 leaves out marked runs;
  - `Pass` L518;
  - `Look` L556-588: its count at L564-581 becomes `Tally`;
  - `Statuses` L594-609: its body becomes `Read`, with `at` added;
  - `FailReason` L615 (it becomes a class method) and `Own` L634.
- `Fix/Run.cls`: new.
- `Install/Step/Fix.cls` (33 lines): the doc L1-4, and `Reconcile`/`ReconcileWith` to add.
- `Checks/Process.cls` (369 lines):
  - the doc L1-31 and the `LOG*` texts L91-105;
  - `Tick` L120-143: the fixes go between the quiet sweep (L124-128) and the due checks;
  - the quiet sweep's private `Sweep` L146 keeps its name;
  - `SendQuiet` L197 is the pattern for the new seams.
- Docs only:
  - `Data/FixRun.cls`: L1-9 (it names FixExecutor as the only writer) and `Interrupted` L34-46. The Storage block is unchanged.
  - `Fix/Msg/FixResult.cls`: L1-6.
  - `Live/Payload/Part/IncidentRequestResult.cls`: L20.
  - `Watch/IncidentManager.cls`: L58 and L1162 ("from FixExecutor").

**Read only:**
- `Install/Registry.cls`:
  - `Order` L14: Reconcile runs right after Production;
  - `Areas` L20;
  - `CallAreas` L78: every area, sorted by name; each failure names its area, and the other areas still run.
- `Install/Step/Reconcile.cls` L5-8.
- `Install/Step/Approvals.cls` L8-11: the sibling declaration.
- `Install/Step.cls`: `Reconcile` L30, `Warn` L52, `TakeWarnings` L58.
- `Install/Step/Production.cls` L13-21 and L67-74: every start restarts the production (`RestartProduction` is `StopProduction` plus `StartProduction`), or recovers or starts it, before Reconcile runs.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `FinishExecution` L380: `interrupted` moves a row from `executing` to `failed`, with Result `interrupted`;
  - `Move` L392;
  - `Reconcile` L653: the sibling pass over every row.
- `Watch/Notice.cls`: `ResultKey` L177 (`executing` first, then `Interrupted`) and `ResultSlots` L192 (`remaining` at L226).
- `Watch/IncidentManager.cls`:
  - `Result` L1164: final means `Final` or `Interrupted`;
  - `Owns` L1037 and `ResultNotice` L1179.
- `Watch/Transitions.cls` L118-127: `fixing` with `finished`.
- `Live/Payload/Incident.cls` L70-72 and L141-150: a request has a result once its run has an `EndedAt`.
- `web/src/app/approvals/approval-view.ts` L338-395, `resultView`: `interrupted` > 0 gives `result.interrupted`, with remaining = total - completed.
- `Msg/Catalog/Watch.cls` L192-234: the three keys and their `one` forms.
- `Msg/Catalog.cls`: `Render` L51, `RenderAt` L64 and `Entry` L79 (which gives `class`).
- `Watch/Reader.cls` L339: Evidence's failure has `timeProcessed`, `status` and `targetConfigName`.
- `Watch/Settle.cls`: `Seconds` L99.
- IRIS reference source:
  - `irislib/Ens/Director.cls`: L104 (`$$$EnsRuntime("StartTime")` is set to `$$$timeUTC` at `StartProduction`) and `RestartProduction` L323;
  - `irislib/Ens/MessageHeaderBase.cls` L28: `TimeProcessed` is the time of the last status change;
  - `irislib/Ensemble.inc` L116: `EnsRuntime` is `^Ens.Runtime`.
- UX: `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` L680-698, the result texts and their count-of-one forms.

**Tests to reuse or change:**
- `Test/Fix/Executor.cls`:
  - fixtures: `Owner` L1105, `Incident` L1113, `Request` L1129, `Canned` L1297;
  - locks: `HoldLock` L1320, `TryLock` L1338, `LockIsFree` L1347, `ReleaseLock` L1305;
  - `OnAfterOneTest` L130, `Warnings` L1424, `Infos` L1408.
- `Test/Fix/ExecutorProbe.cls`: `Statuses` L148 (it calls `##super`), `Waiting` L161 and `Close` L223.
- `Test/Checks/Probe.cls`: the `SendQuiet` pattern and `^||ChecksProbe`.
- `Test/Checks/Runs.cls`: `Host` L464, `Incident` L503, `Tick` L547, `Warnings` L623 and `TestQuietSweep` L308.
- `Test/Watch/Case.cls`:
  - `Raised` L1490;
  - `TempStopItem` L1049, `TempStartItem` L1058 and `TempItem`, for OCUORDERS only (`TempItem` gains a namespace), and `PutBack` L454;
  - `SendTick` L613;
  - `FixResultsOf` L1786: the results from FixExecutor to IncidentManager in one trace session;
  - waits: `WaitState` L1659, `WaitIncidentState` L1676, `WaitCompleted` L1718;
  - reads: `Runs` L1619, `RunOf` L1636, `NoticeBodies` L1338, `StateIncident` L1384, `ResultOf` L1398, `LastIncident` L1408, `Posts` L1432, `Joined` L1912 and `AssertDeliveredIn`.
- `Test/Bridge/AuditLog.cls`: `Now`, `Entries` and `Wait`.
- `Test/Watch/NoticeText.cls`: `TestResultKeys` L322 reads the UX fixtures from `Test.Msg.Catalog`'s XData; the new test sits beside it.
- `Test/Fix/Results.cls` and `Test/Fix/Waits.cls`: the live patterns to follow (Raised, Answer, the waits, Delivery rows, the audit and `Posts`).
- `Test/Install/Registry.cls` L229-245 and `Test/Bridge/Approval.cls` L623 onward run the Reconcile step and assert its status. Read only; they must stay green.

## Tasks & Acceptance

**Execution:**

*Task 0.* Run these on the stage's first fresh throwaway, and record the results under `## Verification`:
- (a) `^Ens.Runtime("StartTime")` in OCUTALON:
  - its value and format;
  - that `Ens.Director.RestartProduction` changes it;
  - that a FixRun of an Execute handled after the start has a `StartedAt` at or after it, as `Started()` converts it.

  If it is unset or unusable, `Started()` uses the instance start (now less `$ZHOROLOG`); record that.
- (b) A copy's `timeProcessed` from `Reader.Evidence`:
  - for a `Completed` copy: within a second of when it completed (`NowUtc` before and after);
  - for a `Queued` copy: its value.

  If a `Completed` copy does not carry its completion time, the DW-395 branch cannot tell its runs from Story 30.5's. HALT `blocked` with the measured values.
- (c) An Execute that IncidentManager sends to a FixExecutor stopped by `TempStopConfigItem` (OCUTALON): is it queued and handled after the start, or refused at the send (with IncidentManager's warning)? Either way holds for the tests; record which.
- (d) Stopping FixExecutor with `TempStopConfigItem` while its waiter waits:
  - the waiter's job ends within about a second;
  - the run stays `executing`, with `ResentAt` set and no FixResult (DW-395, before the fix);
  - after the item is started again, no job holds `^OcuTalon.Fix.Wait`.
- (e) A FixResult that Checks sends: its header's `SessionId` is the incident's `TraceHeaderId`, its `SuperSession` is the request's `TraceRef`, and its source is Checks. Checks' own session is back after the send.
- (f) `##class(OcuTalon.Data.FixRun).EndedAtGetStored(id)` and `InterruptedGetStored(id)` read the stored values while the job holds a changed object.
- (g) The class time of each new or changed live class. Split any class whose time passes about 180 s.

*Product code (in dependency order):*
- `Fix/Executor.cls`:
  - Parameters: `RUNLOCK` "^OcuTalon.Fix.Run", `RUNLOCKSECONDS` 2 and `LOGENDED`.
  - `ClassMethod End` and `ClassMethod Mark`, as under Always.
  - Lift into public class methods, which the existing methods then call: `Read`, `Tally`, `FailReason`, `ActionEntry` and `ResultOf`.
  - `Finish` calls `End`, and on a refusal logs `LOGENDED` and does nothing else.
  - `Waiting` leaves out marked runs.
  - Class doc: the one writer of the end and the run lock; Sweep and Reconcile as callers; a waiter that stops leaves its runs to Sweep (DW-395).
  - Why: AC 1 to AC 5.
- `Fix/Run.cls` (new, Lane A):
  - `Interrupt(Output problems As %DynamicArray) As %Status` and `Sweep() As %ListOfObjects`;
  - the class-method seams `Unended`, `Started`, `Statuses` (which calls `Executor.Read`), `Close` (`FinishExecution`) and `WriteAudit` (`Bridge.Audit.Record`);
  - its `LOG*` texts, `LOGSWEPT` among them;
  - the class doc.
  - Why: AC 1 to AC 5, and DW-395.
- `Install/Step/Fix.cls`: `Reconcile()` and `ReconcileWith(class)`, and the doc. Why: AC 1.
- `Checks/Process.cls`:
  - `Fixes()`, the seams `FixRunSweep()` and `SendFixResult(result)`, and `LOGFIXES` and `LOGFIX`;
  - `Tick` calls `Fixes()` between the quiet sweep and the due checks;
  - the class doc.
  - Why: AC 2.
- Docs only:
  - `Data/FixRun.cls`: the end's writer and the meaning of `Interrupted`;
  - `Fix/Msg/FixResult.cls`: who sends it, and `Interrupted`;
  - `Live/Payload/Part/IncidentRequestResult.cls`: `interrupted`;
  - `Watch/IncidentManager.cls`: a FixResult comes from FixExecutor or from Checks.

  Why: each doc states the contract (Rule 14).

*Tests:*
- `Test/Fix/RunProbe.cls` (new): a `Fix.Run` whose seams read `^||FixRunProbe`:
  - `Unended`: narrowed to the test's incidents;
  - `Started`: the stamp the test gives;
  - `Statuses`: canned per run, as JSON {copy id: {status, error, target, at}}, with an outcome, or a read that throws;
  - `Close`: fails for the Refs the test lists, else the product's;
  - `WriteAudit`: records the entry;
  - `Reset`.
- `Test/Fix/Executor.cls` (probe; warm):
  - new tests:
    - `TestInterruptMarksOnlyRunsCutByTheRestart`
    - `TestReconcileWarnsAndGoesOn`
    - `TestSweepReportsAnInterruptedRunOnce`
    - `TestSweepInterruptedCounts`
    - `TestSweepClosesTheRowFirst`
    - `TestSweepEndsARunNoWaiterEnded`
    - `TestSweepLeavesRunsOfTheWaiterAndOfStory305`
    - `TestSweepSkipsALockedRun`
    - `TestEndRefusesAnEndedOrMarkedRun`
  - The test process holds each fixture run's lock from the run's save to `OnAfterOneTest`, so the production's own Sweep never takes it on a real Tick. In `TestSweepSkipsALockedRun` a `HoldLock` job holds it instead.
  - The class doc.
- `Test/Checks/Probe.cls`:
  - `FixRunSweep` gives the canned results (none by default), or throws;
  - `SendFixResult` records {approvalRef, sessionId, superSession}, and fails for the Refs the test lists;
  - a separate `Order` log gets one entry per send, `quiet:<incident Ref>` or `fix:<approval Ref>`, so a test can check that the quiet sweep came first. `Quieted` keeps its shape, so the existing Checks tests are unchanged.
- `Test/Checks/Runs.cls`: `TestTickSendsTheSweptResults`, the "Checks sends the results" row.
- `Test/Fix/Restart.cls` (new; live; fresh):
  - `TestRestartSaysHowFarItGot`: AC 1, AC 2 and AC 3, and Integration. The test holds the run's lock from its save until just before its own Tick, so no real Tick sweeps the run early.
  - `TestReportedRunGetsNoSecondResult`: AC 3.
- `Test/Fix/Stopped.cls` (new; live; fresh): `TestRunOfAStoppedWaiterEnds`, for AC 4, the inside-the-wait half of AC 5, and DW-395.
- `Test/Watch/Case.cls`:
  - `TempItem` gains a namespace, for `TempStopOwn` and `TempStartOwn` on OcuTalon.Production's items. `PutBack` puts them back.
  - `FixResultsFor(ref)`: every FixResult body of the Ref, from any sender and in any session, with its header's source, session and super session.
  - The doc.
- `Test/Watch/NoticeText.cls`: `TestRestartAndResendTexts`, AC 6.

**Acceptance Criteria:**
- **AC 1 (Integration).** Given a `FixRun` still running when IRIS stopped (its `StartedAt` before the production's current start, its row `executing`, no `EndedAt`), when the Reconcile step calls the Fix area's `Reconcile()` declaration at the next start, then:
  - the run is marked interrupted and never resumed: no copy, Execute, wait or FixResult follows from it;
  - its request is closed through `Approval.FinishExecution` with the result `interrupted`, which leaves it `failed`;
  - a run that started after that start is left as it is.
- **AC 2 (Integration).** Given that run, when Checks handles the next heartbeat Tick, then:
  - Checks calls `OcuTalon.Fix.Run.Sweep()`, which returns the run's final FixResult (`Final` 1, `Interrupted` set, and its counts);
  - Checks sends it to IncidentManager in the incident's trace session;
  - IncidentManager moves the incident by AD-15's table with the interrupted result;
  - S's result Notification uses `result.interrupted`, with the count that went through and the number that need a new approval;
  - the incident event and `/state` list the request's stored result;
  - one `Action` entry records the run;
  - the mock logs no request.
- **AC 3.** Given runs that have been reported (the interrupted run after its result, and a run that FixExecutor ended), when Checks gets more fixture Ticks, and the real heartbeat's, then Sweep returns no FixResult for them: each run has exactly one final FixResult.
- **AC 4 (DW-395).** Given a run whose waiter stopped on a quiesce or terminate request while the production kept running, and whose copies all completed or failed within its 60-second wait, when Checks handles a Tick after that wait, then:
  - Sweep ends the run as FixExecutor would have: its counts, `done`, and one `Action` entry;
  - Checks sends its one final FixResult.
- **AC 5.** Given any of these runs, when Sweep runs, then it returns nothing for the run and leaves its request `executing` (the waiter's run, or Story 30.5's):
  - a run inside its wait;
  - a run whose wait ended with a copy still running;
  - a run whose last copy finished after the wait.
- **AC 6.** Given the three catalog keys, when the catalog test runs, then each key:
  - exists in `OcuTalon.Msg.Catalog.Watch` with its slots;
  - renders through `Msg.Catalog.Render`, the path every `*Out` operation uses, on web, phone, mailbox and telegram;
  - reads as P16's text (EXPERIENCE.md › Results), its count-of-one form included.

## Spec Change Log

- 2026-10-29, spec gate (lead): V1 and V2 ruled as veto items U-153 and U-154 (kept as planned); the spine gains the Conventions row "Fix runs"; kept as one story.

## Review Triage Log

### 2026-10-29 - Review pass
- verdicts: 43 findings - high 0, medium 8, low 29, false 5, maybe-false 1
- findings (B = blind hunter, E = edge case hunter, G/O/R/V/H = verification gap, I = intent alignment; a group shares one root cause):
  - Group A, EndLeft ends the run, then closes the request:
    - `[low]` `patch` B1: a failed close leaves a finished run with an executing request - the Always bullet orders End, then the close, and residual risk 4 names it (needs a FinishExecution fault); the order stays, the notice is conservative (still resending), no false all-clear; patched: the test now reads the notice from the row
    - `[low]` `patch` E1: same, and a close that throws loses the entry and the result - patched: the close is inside a Try/Catch (entry and result still come)
    - `[medium]` `patch` G3: `AssertDone` rendered run C's notice with the literal state done while its row stays executing - patched: it renders from the row (result.stillResending for C)
    - `[low]` `patch` I4: the key in the close-failure case (same as G3)
    - `[low]` `patch` I5: a thrown close in the DW-395 branch (same as E1)
  - Group B, Started() and the start boundary:
    - `[medium]` `patch` B6 / G2: the real `Started()` had no direct test - patched: `Executor.TestStartedIsTheProductionStart`
    - `[low]` `patch` I1, I2: the restart is played and the start comparison was read from code - covered by the same test and Task 0 (a)
  - Group C, failure branches without tests:
    - `[medium]` `patch` B7 / G1: a failed save of the end, a failing audit write, End and Mark refused by a held lock - patched: `Executor.TestSweepGoesOnWhenTheEndFails`, the lock refusals in `TestSweepSkipsALockedRun`, seams `SpoilSave` and `AuditThrows` in `RunProbe`
    - `[low]` `patch` G4: a run with no StartedAt and one that started in the second of the start were untested - patched in `TestInterruptMarksOnlyRunsCutByTheRestart`
  - Group D, tests that could not fail:
    - `[medium]` `patch` V1: the "left alone" test passes if Sweep throws on every run - patched: it asserts no warning and the read count (4)
    - `[medium]` `patch` H1: `Restart` read the step's warnings without draining leftovers of earlier tests - patched: it drains them first
  - Group E, structure:
    - `[low]` `patch` B8: the new header bullets sat between FixExecutor's outcome list and its sub-bullets - patched: moved after them
    - `[medium]` `patch` B9: the run-lock hold helpers were written twice (Test.Fix.Executor, Test.Watch.Case) - patched: one set of class methods in `Case`, called by the Executor test
  - `[low]` `reject` B2, E3: the final result is lost when its send fails or Checks stops after the end is saved - spec-bound (a failed send logs LOGFIX and the others go; never a second result; no stored property, so no unsent marker); the same at-most-once as FixExecutor's own Report
  - `[low]` `reject` B3: a marked run ends at the first Tick although a copy may still complete - spec-bound (V2, residual risk 3: counted as cut off, never as completed)
  - `[low]` `reject` B4, E5: runs that nothing ends stay in Unended - the Always bullets leave them alone; the table has one row per approved fix, so the scan is small
  - `[low]` `reject` B5: MarkOne skips a run with no StartedAt or no row without a problem line - the intent takes only runs with a start before and an executing row
  - `[low]` `reject` B10: the spec's Auto Run Result is stale - finalize writes it (a fix that edits the spec)
  - `[low]` `reject` E2: the Catch body of Sweep itself throws - needs a storage fault; the fix adds a guard
  - `[false]` `reject` E4: End gives 0 for a lock timeout or an exception, so the waiter drops the run - the lock is held by the job that ends the run, and for an exception Sweep's unmarked branch ends the run after its wait
  - `[false]` `reject` E6: a copy's timeProcessed with a fraction - Reader.cls:339 always gives "YYYY-MM-DDTHH:MM:SSZ"; Task 0 (b) measured it
  - `[false]` `reject` E7 (claim): AC 2 says Interrupted set - V2 (veto U-154, kept) sets it when targets were cut off; a run that lost nothing reports its own result
  - `[low]` `reject` G5: no test for a send that throws in Fixes - SendRequestAsync returns a status and the failed-send case is pinned
  - `[maybe-false]` `defer` O1: Stopped's 50-second margin between ResentAt and the restart of OrdersFromPartner could fail on a slow runner - the pass printed no value; settled by `used` in a CI run (medium if true: a flaky CI run)
  - `[low]` `reject` O2: the acquire-probe of the wait lock could land before the waiter takes it - a window of microseconds, and WaitQueued runs first
  - `[low]` `reject` O3: FreeRuns runs before the fixtures are deleted - only on an early Quit, where the test has failed already
  - `[low]` `reject` O4: Hold ignores a failed TakeRun - the fixture run is new, so nobody holds its lock
  - `[low]` `reject` R1, R2, R3, R4, R5: parts of AC 1 to AC 5 with no own mutation line - Rule 19 asks one demonstrated mutation per AC, and each AC has at least one; AC 3's Ticks are guarded three times over, which the AC 3 line says
  - `[low]` `reject` V2: Stopped's second lock check passes whatever the product does - its first check pins the property
  - `[low]` `reject` I3: exactly-once under contention is tested in sequence - the lock refusals are now pinned (Group C)
  - `[low]` `reject` I6: a failed save in Sweep gives no result - decided in-stage (no duplicate result); now tested (Group C)
  - `[low]` `reject` I7: Mark stores at least 1, an empty StartedAt is left, Started falls back to the instance start - decided in-stage; the last two are now tested
  - `[false]` `reject` I8: helpers moved into Case may clash with a subclass - no other test class defines them
  - `[false]` `reject` I9: SendFixResult is typed on FixResult - a type reference; Checks calls only Fix.Run.Sweep() (Test.Bridge.CodeRules passes)

## Design Notes

**V1. Sweep ends the runs that a stopped waiter left (DW-395). For the lead's ruling: AD-16's Rule names two kinds of run that Sweep reports, and this is a third.**
- **Chosen:** Sweep's unmarked branch, as under Always. It ends exactly the runs that a live waiter would have ended:
  - their wait is over;
  - every copy is done;
  - the last copy was done inside the wait.

  The counts, the close (`done`), the entry and the result come from FixExecutor's own `End`, `Tally`, `FailReason`, `ActionEntry` and `ResultOf`. So the result is the one the waiter would have sent, only later.
- **How Sweep tells these runs from Story 30.5's (the question in the spawn).**
  - On disk the two look the same: `ResentAt` set, no `EndedAt`, the row `executing`.
  - The copies' headers, read in the same Evidence pass, tell them apart:
    - If every copy was done before the wait ended (`lastAt` < `ResentAt` + `WAITSECONDS`), the waiter should have ended the run, and Sweep ends it.
    - If a copy is still running, or was done after the wait, a live waiter would have dropped the run too (`LOGWAIT`). That run is Story 30.5's (in progress, then final), and Sweep leaves it.
  - Sweep never touches a run inside its wait, so it cannot race a live waiter. The demo path's run, which the waiter ends in about a second, never meets it.
- **Rejected:**
  - A waiter restart. No FixExecutor job wakes up without a message:
    - `OnInit` would hold up the item's start for up to 60 s;
    - a keepalive adapter was rejected in 7.4's V2;
    - an Execute that resumes a wait contradicts AD-16 ("already executing" changes nothing and sends nothing);
    - Sweep taking `WAITLOCK` would make a new run's Execute return with no waiter. Its result would then be up to two minutes late, on the demo path too.
  - Ending every run past its wait once its copies are done. That would end Story 30.5's runs without their in-progress report, which means building 30.5's branch here and moving scope between epics.
- **AD-16.** AD-16 says nothing about a waiter that stops, and no AD text changes. Spine note for the lead (Rule 20): AD-16's Sweep sentence could name this kind of run, or a "Fix runs" Conventions row could.

**V2. The counts of an interrupted run, and what `FixRun.Interrupted` means. For the lead's ruling: the veto window covers how stored data is kept.**
- **Chosen:**
  - `Interrupted` = `Total` - `Completed` - `FailedAgain`: the targets that the restart cut off. They were not resent, or they were resent and not done when Sweep counted.
  - It is stored on the run and shown in the payload. `FixResult.Interrupted` is 1 when it is above 0.
  - `Skipped` is 0. A run's skips are never stored, so a skipped target counts as cut off; it needs a new approval as well.
- **What that gives:**
  - `result.interrupted` is used exactly when at least one target is cut off, and its `remaining` (`Total` - `Completed`) is then at least 1: "The other 2 need a new approval."
  - When the restart cut nothing off (every copy done, for example copies that completed after the start), the result is the run's own: `result.allThrough`, or `result.failedAgain` with its reason.
  - The interrupted key with remaining 0 would read "The other 0 need a new approval." That is not true, so it is rejected.
  - Either way the row stays `failed` with Result `interrupted`, so the request records the interruption (AD-11).
  - Copies that cannot be read count as cut off, never as completed, as in the waiter (no false all-clear).
- **The storage:** no stored property changes. Story 7.4 always stored 0. The docs of `FixRun.Interrupted` and the payload's `interrupted` said "did not reach", which this story refines to "cut off".

**Spec gate rulings (lead, 2026-10-29; policy 6df0676):**
- V1 (Sweep ends the runs a stopped waiter left, DW-395): ruled `veto`, inbox U-153, kept as planned. The spine gains the Conventions row "Fix runs" (Rule 20 light path); AD-16's text is unchanged.
- V2 (`Interrupted` = the targets cut off; a run that lost nothing reports its own result): ruled `veto`, inbox U-154, kept as planned.
- Size: kept as one story (decide; the 7.7 seam is not taken).

**The two points the epic context asked this spec to rule:**
1. **The row is closed before the result.** Reconcile closes the row. If that close failed, Sweep closes it before it counts, and returns no result while it cannot close it. So `Notice.ResultKey` never sees `executing` for an interrupted result.
2. **Who writes the end.** FixExecutor's `End` and `Mark` write `Interrupted` and the end for every caller (FixExecutor itself, Reconcile and Sweep), under the run's lock. `FixRun`'s doc is corrected to say so. FixExecutor's `ResultOf` builds every `FixResult`. FixExecutor sends its own results, and Checks sends the ones that Sweep returns (AD-16, AD-18).

**Where the Fix area's `Reconcile()` lives.** It goes in `Install.Step.Fix`, this epic's own file. The Reconcile step's `CallAreas("Reconcile")` calls every area's `Reconcile()` by class name (Registry L78), right after the Production step (L14). No other `Install/**` file changes, so nothing contended is edited.

**The start boundary.**
- A run counts as cut off when it started before the production's current start.
- Every start, whether the Docker after-start or IPM, runs the Production step, which restarts, recovers or starts the production. So no job of an earlier start is left, and an IRIS stop is one such restart.
- A run that started after the start (an Execute handled between the Production and Reconcile steps) is live, and Reconcile leaves it.
- A production restarted outside the installer, from the portal, runs no Reconcile. Its waiter quiesced as in DW-395, so Sweep's unmarked branch ends such a run when its copies were done inside its wait. The others wait for the next start, or for Story 30.5.

**Decided in-stage (small, reversible, within the intent):**
- **Reconcile's problems.** A problem with one run is a WARN line, and the step returns OK. The sibling Approvals step fails the step instead, but one row that cannot be closed must not stop a start, and Sweep closes it at the next Tick. A read of the runs that fails still fails the step, as in the sibling.
- **`RUNLOCKSECONDS` is 2.** A lock is held only while a run is being ended, so a run that cannot be locked is being ended by another job.
- **The fixes run after the quiet sweep in a Tick,** so an incident just resolved is not closed in the same Tick, and before the due checks.
- **Every run that Sweep ends gets one `Action` entry,** `interrupted` or `done`, with Story 7.4's five counts. So "Recorded in the IRIS audit log." holds for the interrupted band too.
- **A marked run whose row is gone** is ended with its counts, and no entry or result is made: there is no request to tell.
- **Sweep logs one Type 4 line for each run it ends.**
- **The restart in the tests.** The test plays the run that was cut short, with FixExecutor stopped, as the criterion says ("a test leaves a `FixRun` row running, then runs the `Reconcile` step"). No live restart unit is needed, so Epic 8's and Epic 15's units stay as they are.
- **Probe tests hold their fixture runs' locks,** because the production's real Checks sweeps every minute on a fresh stack.
- **`ReconcileWith(class)`** lets a probe test drive the declaration. `Reconcile()` passes it `OcuTalon.Fix.Run`.
- **Implement stage (small, reversible, inside this story):**
  - **A failed save of the end in Sweep.** When `End` gives 1 with a failed save, Sweep logs one Type 3 warning (`LOGSAVE`), sends no result and leaves the run for the next Tick, so a result never goes out twice for a run. `Finish` goes on as Story 7.4 did.
  - **`End` and `Mark` give 0 with the reason in `sc`** (an error status) for a refusal, a lock they cannot take, and, for `Mark`, a failed save. `Finish` puts that reason in its `LOGENDED` line. `Mark` stores `Interrupted` as at least 1.
  - **The run lock** has two public class methods, `Executor.TakeRun(id)` and `FreeRun(id)`, which `End`, `Mark`, `Fix.Run` and the tests use.
  - **`Interrupt` leaves a run with an empty `StartedAt`.** `Started()` drops the fraction of `^Ens.Runtime("StartTime")` ("YYYY-MM-DD hh:mm:ss.fff", UTC) and falls back to the instance start.
  - **`Fix.Run`'s log texts** are `LOGCLOSE`, `LOGREAD`, `LOGSAVE`, `LOGAUDIT`, `LOGSWEEP` and `LOGSWEPT` (Type 4).
  - **Test helpers shared by the live classes** moved to `Test.Watch.Case`: `WaitResent`, `WaitQueued` and `SecondsSince` (lifted from `Test.Fix.Waits`), `RequestState`, `HoldRun`, `LetGoRun`, `FreeRuns`, `WaitFixResults` and `WaitResultNotices`. `Restart` also calls `End` on the ended run, because Sweep's own guards keep a second result from going out, so Ticks alone cannot show a broken `End`.
  - **Review pass (implement stage).** `Fix.Run.EndLeft` closes the request inside a Try/Catch, so a close that throws logs `LOGCLOSE` and the entry and the result still come, as a close that fails does. `Test.Watch.Case` holds the one set of run-lock helpers (`HoldRun`, `LetGoRun`, `FreeRuns`, class methods over `^||RunHolds`), and `Test.Fix.Executor` calls them. The close-first order stays for the marked branch only: the unmarked branch ends, then closes, as the Always bullet says (residual risk 4).

**Ledger inbox:**
- DW-395: AC 4, the "Waiter stopped" row and V1.

**Governing ADs:**
- AD-1: items by name.
- AD-3: one reader; `Fix.Run` switches no namespace.
- AD-5: state survives a restart; the reconciler; no new property.
- AD-11: the row; `FinishExecution` with `interrupted`.
- AD-12: the event after the commit.
- AD-15: the table; IncidentManager as the one writer.
- AD-16: Reconcile, Sweep, exactly one result, no retry.
- AD-17: the `Action` entry through `Bridge.Audit`.
- AD-18: Checks sends Sweep's results on each Tick.
- AD-22: throwaways and the mock log.
- AD-23: the Reconcile step after the Production step; areas declare `Reconcile()`.
- AD-26: the result's trace session.
- AD-29: Lane A.
- AD-32: the `result` kind, keys and slots only.
- AD-33: owners; no new item or table; `FixRun` is Lane A's.

Conventions: "Result texts", "Audit entries", "Messages" and "Redaction".

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Integration ACs:**
  - AC 1: the Reconcile step reaches `Install.Step.Fix.Reconcile`, and through it `Fix.Run.Interrupt`, through the registry.
  - AC 2: Checks consumes `Fix.Run.Sweep()`; IncidentManager consumes the `FixResult`; WebChatOut and SimPhoneOut deliver the notice.
- **Consumes:**
  - 7.4: the `FixRun` end fields, the waiter and `Finish`.
  - 7.3: the executor, `Copies`, `ResultKey` and `ResultSlots`.
  - 5.6 and Epic 8: Checks and the heartbeat.
  - 3.x: `FinishExecution` and `Bridge.Audit`.
  - 5.5: the transitions.
  - Epic 0: the catalog keys.
  - Epic 6: the page's band.
  - 5.2: `Reader.Evidence`.
- **Consumed-by:**
  - Story 30.5: it adds the in-progress report at the wait's end, and Sweep's branch for runs reported in progress, reusing `Sweep`, `End` and the run lock.
  - Epic 11: the demo path.
  - Epic 6's page: its band, unchanged.

**Extend, don't copy (Rule 2):**
- `Fix.Run` extends FixExecutor's end. It calls `End`, `Tally`, `FailReason`, `ActionEntry`, `ResultOf` and `Read`, which are lifted from `Finish`, `Look`, `FailReason`, `Audit`, `Report` and `Statuses`.
- `Install.Step.Fix.Reconcile` follows `Install.Step.Approvals.Reconcile`, and `Interrupt` follows the every-row pass of `Bridge.Approval.Reconcile`.
- `Checks.Fixes` is one more part of `Tick`'s handling, like the quiet sweep. Its seams follow `SendQuiet`.
- One copy, with its reason: `Fixes`' session switch copies the six lines of `Executor.Report`. The dependency rule lets Checks call only `Fix.Run.Sweep()`, so it cannot call FixExecutor's code.
- `RunProbe` follows `ExecutorProbe`'s seams.
- The new tests reuse `Test.Fix.Executor`'s fixtures and lock jobs.
- `Case.FixResultsFor` sits beside `FixResultsOf`, which reads one sender in one session; the exactly-once check counts every sender and session.
- `TempItem` gains a namespace rather than a second copy.

**Spine notes for the lead (Rule 20 candidates):**
- V1's kind of run, in AD-16's Sweep sentence or a "Fix runs" Conventions row.
- The run lock and FixExecutor's `End` as the one writer.

**Residual risks:**
1. A run whose `ResentAt` save failed waits for the next start's Reconcile.
2. A run whose copies run past its wait still hangs until Story 30.5 (7.4's residual risk 2).
3. A copy queued at the restart that completes after Sweep counted shows as cut off ("need a new approval"), though it went through. This is not a false all-clear, and no new request covers its target.
4. A row whose `FinishExecution` failed after its result (7.4's `LOGFINISH`) stays `executing`, and its result shows as still resending. This is theoretical: it needs a lock or storage fault.
5. A stop that falls between `CouldNotStart`'s save and its end leaves an approved row with a `FixRun`, which Reconcile does not take. The window is milliseconds wide; theoretical.
6. A real Tick during a probe test waits up to 2 s for each fixture run the test holds.

**Size and split (for the lead).**
- This story is planned as one (`oversized`).
- If the lead splits it, the seam is a sibling Story 7.7, "A run whose waiter stopped still ends". It takes DW-395: V1, AC 4, AC 5, `Test.Fix.Stopped`, and the unmarked branch with its probe tests.

**Footprint:**
- `Fix/**`, `Test/Fix/**`, `Checks/Process.cls`, `Test/Checks/{Probe,Runs}.cls`, `Install/Step/Fix.cls` and `Test/Watch/{Case,NoticeText}.cls`.
- Docs only: `Data/FixRun.cls`, `Live/Payload/Part/IncidentRequestResult.cls` and `Watch/IncidentManager.cls`.
- No shared entry changes, and nothing contended is touched. The new `Test.Fix.*` classes join the lane-a shard by their area, so `ci/units.sh` stays as it is.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root.
- Run one command per tool call, with `timeout: 600000`, in the foreground. Never run two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll such a run to completion in bounded foreground calls before doing anything else.
- **Tests run only on throwaways, never on `ocutalon-slot-a`.** Load and compile every changed file on slot A first (MCP `server` `ocutalon-slot-a`, `namespace` `OCUTALON`), to catch compile errors. Slot A lacks Epic 8's and Epic 10's classes, so load from the tree whichever of them the changed classes need.
- `Restart`, `Stopped`, `Checks.Heartbeat` and the other classes that drive the production run fresh.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e7s5iw ci/warm.sh up`, once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s5iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`. The classes:
  - `OcuTalon.Test.Fix.Executor`
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Watch.NoticeText`
  - `OcuTalon.Test.Fix.Kind`
  - `OcuTalon.Test.Bridge.CodeRules`
  - `OcuTalon.Test.Watch.Lifecycle`
  - `OcuTalon.Test.Live.Payloads`
- (loop) `<lane> OCUTALON_RUN_TAG=e7s5i ci/iris.sh class <Class>`, fresh, one call per class. Expected: passed. The classes:
  - `OcuTalon.Test.Fix.Restart` (first, with Task 0)
  - `OcuTalon.Test.Fix.Stopped`
  - `OcuTalon.Test.Checks.Heartbeat`
  - `OcuTalon.Test.Fix.Results`
  - `OcuTalon.Test.Fix.Waits`
  - `OcuTalon.Test.Fix.Partial`
  - `OcuTalon.Test.Fix.Runs`
  - `OcuTalon.Test.Fix.Execute`
  - `OcuTalon.Test.Bridge.Approval`
  - `OcuTalon.Test.Install.Registry`
- (once) `<lane> OCUTALON_RUN_TAG=e7s5i ci/iris.sh shard lane-a --part k/12` for k = 1 to 12, one call each. Story 7.4's 87 classes took 394 s, 534 s and 445 s in thirds on a fresh stack; there are about 90 with this story. Expected: passed. Record each part's time.
- (once) `<lane> OCUTALON_RUN_TAG=e7s5i ci/iris.sh shard lane-b --part k/4` for k = 1 to 4, one call each. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e7s5i ci/iris.sh live production-restart`, a real restart through the after-start, with Fix's Reconcile in the Reconcile step. Expected: passed.
- (once) `bash ci/checks.sh`. Expected: every script passes.
- (once) `<lane> OCUTALON_RUN_TAG=e7s5iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e7s5i ci/iris.sh teardown`. Run both after a failure too.

**Shared surfaces:**
- **The Reconcile step's areas.** `Install.Step.Fix` now declares `Reconcile()`. `Test.Install.Registry.TestReconcileStep` and `Test.Bridge.Approval`'s Reconcile-step tests assert the step's status. It stays OK, because Fix's Reconcile marks only runs started before the production's start.
- **Checks' Tick.**
  - `Test.Checks.Runs` drives a shadow instance, and the probe's `FixRunSweep` gives no result by default.
  - `Test.Checks.Heartbeat` sends real Ticks and asserts only on its own rows.
- **FixExecutor's `Finish` and `Waiting`.** `Test.Fix.Executor`'s existing probe tests use unmarked runs, which behave as before.
- **The meaning of `Interrupted`.** `Test.Live.Payloads` uses fixture values, and the page's `resultView` tests (Epic 6) keep their code.
- **The production's real Sweep runs on every Tick of a running stack.** A test that leaves behind a marked run, or a run whose copies were done in its wait, sees it ended by a real Tick. Probe tests hold their fixture runs' locks.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte-identically, and record a `mutation: … → …` line here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | `Install.Step.Fix` loses `Reconcile()` | `Restart.TestRestartSaysHowFarItGot` (R1 stays `executing`) |
| AC 1, the boundary | `Interrupt` takes every unended `executing` run, whatever its `StartedAt` | `Restart` (the first pass marks R1), `Executor.TestInterruptMarksOnlyRunsCutByTheRestart` |
| AC 1, never resumed | `Waiting` keeps marked runs | `Executor.TestEndRefusesAnEndedOrMarkedRun` |
| AC 2 | `Tick` skips `Fixes()` | `Restart` (no result), `Runs.TestTickSendsTheSweptResults` |
| AC 2, the row first | Sweep counts and returns a marked run without closing its `executing` row | `Executor.TestSweepClosesTheRowFirst` |
| AC 2, the session | `Fixes` keeps the process's own session | `Runs.TestTickSendsTheSweptResults`, `Restart` (the header's session) |
| AC 2, the counts | `Interrupted` = `Total` - `Resent` | `Executor.TestSweepInterruptedCounts` |
| AC 3 | `End` ignores the stored `EndedAt` | `Executor.TestSweepReportsAnInterruptedRunOnce`, `Restart` (one FixResult after more Ticks) |
| AC 3, the lock | Sweep takes no run lock | `Executor.TestSweepSkipsALockedRun` |
| AC 4 | Sweep has no unmarked branch | `Stopped.TestRunOfAStoppedWaiterEnds`, `Executor.TestSweepEndsARunNoWaiterEnded` |
| AC 5, the wait | The unmarked branch also takes runs inside their wait | `Stopped` (the Tick inside the wait), `Executor.TestSweepLeavesRunsOfTheWaiterAndOfStory305` |
| AC 5, the copy times | The unmarked branch ignores `lastAt` | `Executor.TestSweepLeavesRunsOfTheWaiterAndOfStory305` |
| AC 6 | `result.interrupted`'s one form reads "The other 1 need a new approval." | `NoticeText.TestRestartAndResendTexts` |
| FixExecutor's refusal | `Finish` ignores `End`'s refusal | `Executor.TestEndRefusesAnEndedOrMarkedRun` |

**Task 0 results (implement stage, 2026-10-29; a scratch measurement class on fresh throwaway e7s5i, removed afterwards).**
- (a) `^Ens.Runtime("StartTime")` is "2026-10-29 17:11:27.941": UTC, "YYYY-MM-DD hh:mm:ss.fff". `Ens.Director.RestartProduction` changed it to "2026-10-29 17:12:15.879". A FixRun of an Execute handled after that has StartedAt "2026-10-29T17:12:26Z", after "2026-10-29T17:12:15Z", which is `Started()`'s conversion (fraction dropped). `Started()` uses it; the instance start (now less `$ZHOROLOG` seconds) is only the fallback.
- (b) `timeProcessed` of a Completed copy is its completion time: the copies completed in the second between `NowUtc` before ("2026-10-29T17:11:50Z") and after ("2026-10-29T17:11:50Z"), and their timeProcessed is "2026-10-29T17:11:50Z". A Queued copy's timeProcessed equals its timeCreated ("2026-10-29T17:11:46Z"). So the DW-395 branch can tell its runs from Story 30.5's; no halt.
- (c) An Execute sent to FixExecutor stopped by `TempStopConfigItem` is queued (header status 2), no IncidentManager warning is logged, R1 stays approved, and after the item starts the Execute is handled (R1 ran to done).
- (d) Stopping FixExecutor while its waiter waits: the waiter let go of `^OcuTalon.Fix.Wait` within 0.08 s; the run stayed executing with ResentAt set, no EndedAt and no FixResult; after the item was started again nothing held the lock, and R1 stayed executing after its copies completed (DW-395, before the fix).
- (e) Asserted live by `Restart` and `Stopped`: the FixResult that Checks sent has source Checks, target IncidentManager, SessionId the incident's TraceHeaderId and SuperSession the request's TraceRef. Checks' own session is back after each send (`Runs.TestTickSendsTheSweptResults`).
- (f) `EndedAtGetStored(id)` and `InterruptedGetStored(id)` read the stored values ('' and '') while the job held an object with EndedAt "2001-01-01T00:00:00Z" and Interrupted 5; after the save they read those values.
- (g) Class times on this machine (fresh stack ready in 84 to 93 s): Restart 38 s, Stopped 85 s, Results 44 s, Waits 42 s, Partial 38 s, Runs 60 s, Execute 53 s, Checks.Heartbeat 3.5 s, Bridge.Approval 28 s, Install.Registry 2.4 s. Warm: Executor 20 s, Checks.Runs 0.1 s, NoticeText 0.2 s, Kind 0.1 s, CodeRules 1.5 s, Lifecycle 0.2 s, Payloads 0.3 s. No class passes 180 s, so none is split.

**Pinning mutations (implement stage; each applied on a throwaway, observed red, reverted byte-identically from a backup, with `git status --short` and `git diff --stat` unchanged).**
- mutation: `Install.Step.Fix.Reconcile` renamed away -> `Restart.TestRestartSaysHowFarItGot` red (R1 not failed, run not marked, no FixResult)
- mutation: `Interrupt` takes every unended executing run whatever its `StartedAt` -> `Executor.TestInterruptMarksOnlyRunsCutByTheRestart` red and `Restart.TestRestartSaysHowFarItGot` red (the first pass marks the run)
- mutation: `Waiting` keeps marked runs -> `Executor.TestEndRefusesAnEndedOrMarkedRun` red
- mutation: `Tick` skips `Fixes()` -> `Runs.TestTickSendsTheSweptResults` red and `Restart.TestRestartSaysHowFarItGot` red (no FixResult)
- mutation: Sweep counts and returns a marked run without closing its executing row -> `Executor.TestSweepClosesTheRowFirst` red
- mutation: `Fixes` keeps the process's own session and SuperSession -> `Runs.TestTickSendsTheSweptResults` red and `Restart.TestRestartSaysHowFarItGot` red (the header's session)
- mutation: `Interrupted` = `Total` - `Resent` -> `Executor.TestSweepInterruptedCounts` red
- mutation: `End` ignores the stored `EndedAt` -> `Executor.TestSweepReportsAnInterruptedRunOnce` and `Executor.TestEndRefusesAnEndedOrMarkedRun` red and `Restart.TestRestartSaysHowFarItGot` red (its direct `End` on the ended run; the Ticks alone stay green, because Sweep's `Unended` and `One` guards also keep the run from a second result)
- mutation: Sweep takes no run lock -> `Executor.TestSweepSkipsALockedRun` red
- mutation: Sweep has no unmarked branch -> `Executor.TestSweepEndsARunNoWaiterEnded` red and `Stopped.TestRunOfAStoppedWaiterEnds` red
- mutation: the unmarked branch also takes runs inside their wait -> `Executor.TestSweepLeavesRunsOfTheWaiterAndOfStory305` red and `Stopped.TestRunOfAStoppedWaiterEnds` red (the Tick inside the wait)
- mutation: the unmarked branch ignores `lastAt` -> `Executor.TestSweepLeavesRunsOfTheWaiterAndOfStory305` red
- mutation: `result.interrupted`'s one form reads "The other 1 need a new approval." -> `NoticeText.TestRestartAndResendTexts` red
- mutation: `Finish` ignores `End`'s refusal -> `Executor.TestEndRefusesAnEndedOrMarkedRun` red
- mutation (review pass): `Fix.Run.Ended` gives 1 after a failed save -> `Executor.TestSweepGoesOnWhenTheEndFails` red
- mutation (review pass): `Fix.Run.Entry` lets a failed audit write escape -> `Executor.TestSweepGoesOnWhenTheEndFails` red
- mutation (review pass): `Fix.Run.EndLeft` lets a close that throws escape -> `Executor.TestSweepGoesOnWhenTheEndFails` red
- mutation (review pass): `Fix.Run.Started` ignores `^Ens.Runtime("StartTime")` -> `Executor.TestStartedIsTheProductionStart` red
- mutation (review pass): `Interrupt` takes a run with no `StartedAt` -> `Executor.TestInterruptMarksOnlyRunsCutByTheRestart` red
- mutation (review pass): `EndLeft` throws for every run -> `Executor.TestSweepLeavesRunsOfTheWaiterAndOfStory305` red (its no-warning and read-count checks; it stayed green before them) and `TestSweepGoesOnWhenTheEndFails` red
- mutation (review pass): `Executor.End` does not take the run lock -> `Executor.TestSweepSkipsALockedRun` red

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-29).**
- The story is planned in full against the READY FOR DEVELOPMENT standard.
- The plan stage checked slot A's identity (build 154, OCUTALON) and read one global. The production does not run there, so `^Ens.Runtime("StartTime")` is unset. It used no throwaway; Task 0 belongs to the implement stage.

The lead rules these items at the spec gate. Each is planned as recommended, and none blocks the build:
- **V1 (AD-16 is silent; a spine note).** Sweep's unmarked branch ends the runs that a stopped waiter left (DW-395), and only those whose copies were all done inside their wait. That leaves Story 30.5's runs to it. No AD text changes.
- **V2 (veto window: how stored data is kept).**
  - The counts: `Interrupted` = `Total` - `Completed` - `FailedAgain`, and `FixResult.Interrupted` = `Interrupted` > 0.
  - When the restart cut nothing off, the result is the run's own (`result.allThrough` or `result.failedAgain`), never "The other 0 need a new approval."
  - No stored property is added or changed.

Also:
- There is no schema change, no new public text and no new item, message or key.
- There is no NFR tripwire.
- Nothing contended is touched, and there is no footprint extension. The Reconcile declaration lives in `Install/Step/Fix.cls`, this epic's own.
- An optional split is offered: a sibling 7.7 would take DW-395.

**Implement stage (2026-10-29).**
- **Summary.** A run that a restart cut short, or whose waiter stopped, now ends exactly once and tells the user how far it got:
  - FixExecutor's `End` and `Mark` are the one writer of a run's end, under a per-run lock (`^OcuTalon.Fix.Run(<id>)`).
  - The Fix area's `Reconcile()` (`Install.Step.Fix`) calls `Fix.Run.Interrupt`: it marks each run that started before the production's current start, and closes its request `failed` with the result `interrupted`. It resends and resumes nothing.
  - On each Tick, `Checks.Fixes()` takes the final FixResults of `Fix.Run.Sweep()` and sends them to IncidentManager in the incident's trace session. Sweep ends a marked run with its counts (`Interrupted` = targets cut off) and, for DW-395, a run that no waiter ended when its copies were all done inside its wait.
  - No stored property, item, message class, catalog key or public text was added (V1 and V2 as ruled; `Fix.Run` is the one new product class).
- **Files changed.**
  - Product: `Fix/Executor.cls` (End, Mark, TakeRun, FreeRun, public Read, Tally, FailReason, ActionEntry and ResultOf; Finish calls End; Waiting leaves out marked runs), `Fix/Run.cls` (new: Interrupt, Sweep and the seams), `Install/Step/Fix.cls` (Reconcile, ReconcileWith), `Checks/Process.cls` (Fixes and its seams, called between the quiet sweep and the due checks).
  - Docs only: `Data/FixRun.cls`, `Fix/Msg/FixResult.cls`, `Live/Payload/Part/IncidentRequestResult.cls`, `Watch/IncidentManager.cls`.
  - Tests: `Test/Fix/RunProbe.cls`, `Test/Fix/Restart.cls` and `Test/Fix/Stopped.cls` (new); `Test/Fix/Executor.cls` (11 new tests), `Test/Fix/ExecutorProbe.cls`, `Test/Fix/Waits.cls` (three helpers moved to `Case`); `Test/Checks/Probe.cls`, `Test/Checks/Runs.cls`; `Test/Watch/Case.cls`, `Test/Watch/NoticeText.cls`.
- **Review.** 43 findings from four layers: high 0, medium 8, low 29, false 5, maybe-false 1 (the Review Triage Log has each row).
  - Patched (five groups, all medium): the close inside `EndLeft` is in a Try/Catch and the test reads the notice from the row's state (group A); `Started()` has its own test (B); a failed save of the end, a failing audit write, a close that throws and a held lock now have tests (C); the "left alone" test checks no warning and the read count, and `Restart` drains leftover step warnings (D); the header bullets moved and the run-lock helpers are one set in `Test.Watch.Case` (E).
  - Deferred: one (`Test.Fix.Stopped`'s 50-second margin on a slow runner, maybe-false, medium if true), in the frontmatter `deferred:` list.
  - Rejected with a reason: 26 (spec-bound at-most-once and the close order, residual risks 3 and 4, Rule 19 per-AC lines, theoretical windows, and five false findings).
- **Follow-up review recommended: true.** Five medium groups were patched, and two touched shared code that every `Test.Watch.Case` class runs (the run-lock holds are now process-global class methods, called from each `OnAfterOneTest`) or the running production (`Fix.Run.EndLeft`). The loop, both shards and `production-restart` passed after the patches, but a second pass should confirm the dedupe and the new failure tests.
- **Verification performed.**
  - Task 0 (a) to (g), recorded under `## Verification`; no halt condition.
  - Slot A: all changed classes loaded and compiled before the review; the final load follows the commit.
  - The `(loop)` lines after the last patch, all passed: warm `Test.Fix.Executor` (24.9 s; green again after the seven reviewer-pass mutations were reverted), `Test.Checks.Runs`, `Test.Watch.NoticeText`, `Test.Fix.Kind`, `Test.Bridge.CodeRules`, `Test.Watch.Lifecycle`, `Test.Live.Payloads`; fresh `Test.Fix.Restart` (40.2 s), `Test.Fix.Stopped` (84.5 s), `Test.Checks.Heartbeat` (6.0 s), `Test.Fix.Results` (42.1 s), `Test.Fix.Waits` (41.3 s), `Test.Fix.Partial` (37.7 s), `Test.Fix.Runs` (61.1 s), `Test.Fix.Execute` (55.7 s), `Test.Bridge.Approval` (28.4 s), `Test.Install.Registry` (2.5 s). A fresh stack was ready in 98 to 137 s.
  - `(once)`: `shard lane-a --part k/12`, 12 parts, 89 classes, all passed (277, 212, 148, 111, 136, 275, 301, 244, 117, 187, 267 and 185 s); `shard lane-b --part k/4`, 78 classes, all passed (156, 105, 343 and 220 s); `live production-restart` passed (the Reconcile step ran with Fix's `Reconcile()`); `bash ci/checks.sh` passed (all scripts).
  - Matrix Test Audit: every matrix row has a covering test that ran and passed (Restart, Stopped, the Executor probe tests, `Checks.Runs.TestTickSendsTheSweptResults`, `NoticeText.TestRestartAndResendTexts`).
  - Pinning mutations: 14 from the implement pass and 7 from the review pass, each applied on a throwaway, red, reverted byte-identically; the lines are under `## Verification`.
  - Both stacks (`e7s5iw`, `e7s5i`) were torn down.
- **Residual risks.**
  - The spec's residual risks 1 to 6 stand.
  - A close that fails after the end is saved in `EndLeft` leaves the request executing with a "still resending" notice (residual risk 4; the test now says so).
  - A final FixResult is sent at most once: if the send fails after the end is saved, the incident stays `fixing` (spec-bound; no stored property to mark it).
  - `Test.Fix.Stopped` passes with a margin of 50 seconds from `ResentAt` (deferred above); the first CI run settles it.
