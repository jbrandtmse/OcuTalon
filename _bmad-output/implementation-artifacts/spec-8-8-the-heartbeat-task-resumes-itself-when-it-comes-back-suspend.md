---
title: 'Story 8.8: The heartbeat task resumes itself when it comes back Suspended'
type: 'bugfix'
created: '2026-11-09'
status: 'done'
baseline_revision: 'fbd9b13310d2fdbbcd7023412c90fa3eb36d2ef5'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the 1.0.5 online demo, after an update, the Task Manager task `OcuTalon heartbeat` came back Suspended (1), with SuspendOnError 0 and its last run OK. Nothing resumes it. The Tasks step leaves an existing task alone, so no tick runs: the "Background checks have paused" banner shows, the digest says "Not checked: Orders production", and watches never fire (DW-1018). `release/demo-host-check.sh` can't see any of this.

**Approach:**
- The Schedule area's `Reconcile()` resumes the heartbeat task when it is Suspended and reports it with one `Install.Step.Warn` line. Every start path already calls it: the after-start script's `Reconcile` step, an IPM install's `Registry.Run("ipm")`, and `ReconcileIn` on a production start that the Production step didn't make.
- A task that isn't Suspended, or doesn't exist, is left alone, with no line.
- `release/demo-host-check.sh` gets a `--heartbeat FILE|-` input. It is the one-line JSON a host command prints, brought in the same way as `--zone` and `--demo-status`. The script fails `heartbeat-tick` on a tick more than 3 minutes old and `heartbeat-task` on a Suspended or missing task.

## Boundaries & Constraints

**Always:**
- **One resume, by name.** The task is found with `##class(%SYS.Task).FindId(name)`, as `Install.Step.Tasks.Create` finds it.
  - Its Suspended value is read from storage with `##class(%SYS.Task).SuspendedGetStored(id)`, never from an open object. `%OpenId` hands back an OREF the process already holds, with a stale `Suspended`; this was measured in Task 0 (M5).
  - Only a non-zero value is resumed, with `##class(%SYS.Task).Resume(id)`. Values 1 and 2 are both resumed.
  - `Resume` also returns OK for a task that isn't Suspended (M1), so the guard alone decides whether a line is written.
- **Nothing else changes.** No second task, no `%Save` of the task, no new property value. The schedule (`TimePeriod`, `TimePeriodEvery`, `DailyFrequency`, `DailyFrequencyTime`, `DailyIncrement`, `DailyStartTime`, `DailyEndTime`, `StartDate`, `RescheduleOnStart`), `RunAsUser`, `NameSpace`, `TaskClass`, `Description` and the id stay as they were. M1 measured that `Resume` changes none of them.
- **Errors.** A failed `Resume` returns its status, which `CallAreas` reports as `STEP Reconcile FAILED`. Nothing is swallowed (Decided 3).
- **Lines.** The line text is the PUBLIC TEXT of Design Notes, exactly. The registry writes it as `WARN Reconcile <text>`, and ReconcileIn as the Event Log Warning `ReconcileIn: <text>`. No banner, digest or catalog text changes.
- **The host check.**
  - It stays read-only. It sends no new request, opens no new public read, and runs no host command in its code lines. Row 15 of `test-online-host.sh` pins that: no `ocutalon-demo`, `ssh` or `scp`.
  - Its new lines follow the script's `PASS|FAIL|SKIP <id> <text>` grammar and exit codes.
- **Tests.** Every test added or changed passes on a fresh environment, in either order.
- **Source text.** ASCII only, comments that state the contract (Rule 14), and no local absolute path in a committed file.

**Never:**
- Don't edit these (Lane A's installer core, Epic 41's unit, Epic 11's contended file, the shared helpers):
  - `src/ocutalon/cls/OcuTalon/Install/Step/Tasks.cls`, `Install/Registry.cls`, `Install/Step.cls`, `Install/ReconcileIn.cls`, `Install/Step/Reconcile.cls`;
  - `docker/tests/test-reminder-restart.sh`, `docker/tests/test-ci-config.sh`, `docker/tests/lib-live.sh`, `docker/tests/lib-online.sh`;
  - any `OcuTalon.Test.Install.*` class.
- No new privilege, role, grant or resource. Nothing is granted to `OcuTalonUser`.
- No `/api/v1` route is added or changed.
- No new CI group, and no change to any other group's units.
- Don't take DW-485 (the allow-hyperevent check) or anything else from DW-446.
- Don't recreate, `%Save` or re-declare the task, and don't change `Tasks()`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Suspended 1 at start | Heartbeat task exists, `Suspended` 1 (as on the demo) | `Suspended` 0, every other property and the id unchanged, one task of that name; exactly one line `the task "OcuTalon heartbeat" was suspended, so it was resumed` | none |
| Suspended 2 | `Suspended` 2 (suspended and rescheduled) | the same as Suspended 1 | none |
| Not suspended | `Suspended` 0 | the task untouched, no line | none |
| Missing | No task of that name (ReconcileIn path, or deleted by hand) | nothing created or changed, no line, status OK | none |
| Resume fails | `Resume` returns an error | that status is returned, and the Reconcile step reports it | `CallAreas` names the area |
| Host: fresh, running | `--heartbeat` JSON `lastTick` 40 s before `now`, `suspended` 0 | `PASS heartbeat-json`, `PASS heartbeat-tick`, `PASS heartbeat-task`; exit 0 when nothing else fails | none |
| Host: boundary | age exactly 180 s / 181 s | 180 passes; 181 is `FAIL heartbeat-tick ... more than 3 minutes`, exit 1 | none |
| Host: suspended | `suspended` 1 or 2 | `FAIL heartbeat-task the heartbeat task is suspended (Suspended <n>)`, exit 1 | none |
| Host: task missing | `suspended` `"missing"` | `FAIL heartbeat-task the heartbeat task does not exist`, exit 1 | none |
| Host: no tick | `lastTick` "" or not ISO UTC | `FAIL heartbeat-tick the input has no readable lastTick and now`, exit 1 | none |
| Host: not JSON | no line of the input starts with `{`, or that line isn't a JSON object | `FAIL heartbeat-json the input holds no JSON object line`; the other two ids aren't printed | none |
| Host: no input | no `--heartbeat` | `SKIP heartbeat no --heartbeat input given`, exit 3 when nothing fails (like `zone`) | none |
| Host: usage | `--heartbeat` with no value; two of the three inputs `-` | exit 2 with one message on stderr, nothing sent | usage() |

</intent-contract>

## Code Map

**The resume (Lane B, Epic 8's own class):**
- `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls`:
  - `Reconcile()` is at `:15-25`. It re-arms the reminders, warns per orphan reminder at `:22`, and returns `sc` at `:24`. The resume joins it there.
  - `HEARTBEATTASK` is at `:13`, and `Tasks()` at `:28-46`, unchanged. The class header, `:1-8`, gets one bullet for the resume.
- Callers, read only:
  - `src/ocutalon/cls/OcuTalon/Install/Step/Reconcile.cls:7` calls `Registry.CallAreas("Reconcile")`.
  - `Install/Registry.cls`: `Order()` is at `:14` (`... "Tasks", ... "Production", "Reconcile", ...`). `Run` prints `WARN <step> <line>` at `:64-68`. `CallAreas`, at `:118-132`, calls every area and appends each failure, naming the area. `Ipm()` runs `Run("ipm")` at `:91`.
  - `Install/ReconcileIn.cls:92-114` takes the warnings around `Reconcile.Run()` and logs each as `$$$LOGWARNING("ReconcileIn: "_line)`.
- `Install/Step.cls:52-55` is `Warn(text)`, `:66-77` is `TakeWarnings()`, and `:60` is `Caller()` (not needed).
- `Install/Step/Tasks.cls:51-72`, `Create`, is the sibling: `FindId(name)`, then a task created as `RunAsUser=$Username` in `$Namespace`. Read only.
- `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatTask.cls` is the task class, unchanged. `OnTask` ends OK while the production doesn't run.
- `src/ocutalon/cls/OcuTalon/Schedule/Heartbeat.cls` (read only): `TICKMARK` is `heartbeatTick` at `:16`, `GAPMARK` is at `:19`, and `STALLSECONDS` is 180 at `:29`.

**Tests, as siblings:**
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` (read only):
  - `ScheduleOf(task)` at `:883` is a ClassMethod, reusable. It lists the schedule fields plus `Suspended`.
  - `TaskCount(name)` at `:871` is a ClassMethod.
  - `SettleScheduler()` is at about `:893`.
  - `HoldTask`/`ResumeTask` at `:692-724` suspend the real task with `%Save`, and `Restore` asserts that `Suspended` is put back.
  - Its production restarts go through `Install.Step.Production.Start()`, which holds the start lock, so ReconcileIn skips them.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/StallFixture.cls:39-60` (`Hold`) and `:100-112` (`Release`) suspend the real task during the web heartbeat and banner specs. `SecondInWindow()` (5 to 45 s) is at `:115`, but it is Private.
- `src/ocutalon/cls/OcuTalon/Test/Install/ReconcileIn.cls:52-92` is the pattern for driving ReconcileIn in a unit test. It takes a shadow instance (`Ens.Host.GetShadowInstance("class||OcuTalon.Install.ReconcileIn")`), calls `OnInit` (`ByStep` 0), then `OnProcessInput`, and counts `Ens_Util.Log` rows of this job by type and text. `Rows` and `LastRow` are Private, in Lane A's file.

**Live unit siblings:**
- `docker/tests/test-reminder-restart.sh:33-36` covers `live_start`. Its first start is at `:142-153`, and the plain restart at `:206-234`: `dc stop iris`, `dc start iris`, `wait_started_ready 300`, a TIMING line, then the `STEP Reconcile OK` / `WARN Reconcile` grep. `:366-373` is the end. Read only.
- `docker/tests/lib-live.sh` (read only):
  - `live_start` is at `:63`, `dc` at `:249`, `pass`/`fail`/`die` at `:279-289`, and `wait_until` at `:292`;
  - `iris_script` at `:316` keeps `CHK|` lines;
  - `started_at` is at `:345`, `start_log` at `:355`, `wait_started_ready` at `:383` and `log_steps` at `:673`;
  - `check_clean_start` at `:796` counts Event Log types 2 and 6 only.

**CI registration:**
- `ci/units.sh:134` is the `shards` line: `shard:lane-a@Install,Digest,Eval live:online-allowance`. Append ` live:heartbeat-restart`.
- `ci/units.sh:117-127` holds the Story 0.20 comment block. Append one comment paragraph after `:127`.
- `group_input_pattern` (`:248`) claims `docker/tests/test-heartbeat-restart.sh` for `shards` by itself. `IRIS_INPUT` claims `lib-live.sh`.
- `docker/tests/test-ci-config.sh`'s `units`/`inputs` rules count from the tree, and no pin names the `shards` units, so it needs no edit.

**The host check (Lane A release tooling, named in the story's files):**
- `release/demo-host-check.sh`:
  - the header: usage at `:3`, the check list at `:7-24`, and the host inputs at `:42-43`;
  - `usage()` is at `:57-61`, and argument parsing at `:80-104`; the `--zone` case is at `:92-96`;
  - the one-stdin rule is at `:111`;
  - `read_input` is at `:137-146`, and `iso_re` at `:276`;
  - `run_normal` ends at `:394-396` (`check_demo_status`, `check_zone`);
  - `check_zone` at `:439-450` is the sibling; `check_demo_status` at `:398-437` shows the JSON pattern (`jq -e`, `fromdateiso8601`, as at `:309`);
  - the summary and exit codes are at `:524-527`.
- `docker/tests/test-online-host.sh`:
  - the header rows are at `:13-26`; fixtures at `:308-315`; `run_script` and `full` at `:322-347`;
  - `expect_run` (exact FAIL and SKIP id sets) is at `:364`, and `line_has` at `:381`;
  - row 1 is at `:383-400`, with its id list at `:396-397`;
  - rows 9 to 12 are at `:655-712`, and `usage_case` at `:716-735`;
  - `host_status_bad`, `seq 1 25`, is at `:882-893`, with its PASS text at `:900`.
- `release/demo-host-checks.md`: run 1 is at `:23-28`, the criteria table at `:38-64` (H1 to H25), and the licence-unit note at `:79` (a terminal takes one connection).

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls`:
  - Add `ClassMethod ResumeTask(name As %String) As %Status`:
    - find the task with `FindId`; when there is none, quit OK;
    - read `SuspendedGetStored(id)`; when it is 0, quit OK;
    - otherwise call `Resume(id)`, and on OK, `..Warn("the task """ _ name _ """ was suspended, so it was resumed")`;
    - return the status.
  - `Reconcile()` returns `$SYSTEM.Status.AppendStatus(sc, ..ResumeTask(..#HEARTBEATTASK))`. The reminder re-arm runs first, unchanged.
  - Doc comments state the contract: Tasks() creates the task once, and Reconcile resumes it at every start. DW-1018 and AC 1 to 3.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ResumeProbeTask.cls` (new) -- `Extends %SYS.Task.Definition` with `OnTask` quitting `$$$OK` and a `TaskName` parameter. It is the probe tests' task class, so a probe can never tick the heartbeat, and `Heartbeat.TaskCount()` (counted by `HeartbeatTask`) never sees it. THROWAWAY/CI-only header, as `HeartbeatTaskElsewhere` has.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/TaskResume.cls` (new; Rule 2: a new class, not `Test.Schedule.Heartbeat`, Decided 5) -- AC 5, with DW-1018 rows 1 to 4 of the matrix:
  - **Probe task.** Each probe test creates its own task in `OnBeforeOneTest`:
    - the name is `ZzResumeProbe <$Job>-<n>`, outside the `OcuTalon` prefix;
    - its class is `ResumeProbeTask`, in this namespace, `RunAsUser` `$Username`;
    - it runs every minute, with `StartDate` +365 days, so it never runs.
    - `OnAfterOneTest` deletes it by id, and kills the warnings with `TakeWarnings`.
  - `TestNotSuspended`: `ResumeTask(name)` is OK, there are no warnings, and `ScheduleOf`, `RunAsUser`, `NameSpace`, `TaskClass`, `Description` and the id are equal before and after. Read each from a fresh `%OpenId` after the earlier OREF is killed.
  - `TestSuspended`, for flag 1 and flag 2: after `Suspend(id, flag)`, `ResumeTask` is OK and `SuspendedGetStored` is 0. The warnings are exactly one line, `the task "<name>" was suspended, so it was resumed`. The other properties are unchanged, `TaskCount(name)` is 1 and the id is the same.
  - `TestMissing`: `ResumeTask("ZzResumeProbe missing <$Job>")` is OK, with no warnings and `TaskCount` 0.
  - **The real task (the wiring):**
    - `TestReconcileResumesHeartbeat`: save the real task's stored `Suspended` as `found`, then wait for clock second 5 to 45, at most 21 s. Put the task in the state the test needs: `Resume` when it is suspended, then `Suspend(id, 1)`.
      - `Install.Step.Schedule.Reconcile()` is OK and the task is at 0.
      - The heartbeat line occurs exactly once among the warnings. Count lines equal to the text, since orphan-reminder lines may also appear.
      - The schedule is unchanged.
    - `TestReconcileLeavesHeartbeat`: with the task at 0, `Reconcile()` gives no heartbeat line and changes no property.
    - Both restore `found` in `OnAfterOneTest` (`Suspend(id, found)` when it is not 0).
  - `TestReconcileInResumes` -- the Integration AC: suspend the real task (the same guard and restore), take the shadow `ReconcileIn` instance, and `OnInit` with `ByStep` 0. Every item runs: wait up to 60 s, as the sibling does. Call `OnProcessInput`.
    - This job has exactly one Event Log row of type 3 with Text `ReconcileIn: the task "OcuTalon heartbeat" was suspended, so it was resumed`, and the task is at 0.
    - Copy the 10-line row count of `Test.Install.ReconcileIn` (Private, in Lane A's file); the reason goes in the class header.
  - The class header lists the tests and states that the real task's `Suspended` is restored.
- [ ] `docker/tests/test-heartbeat-restart.sh` (new, executable; on `lib-live.sh`, in the style of `test-reminder-restart.sh`; label `t88h`) -- AC 4, with AC 1 and 2 on the after-start surface:
  1. **First start.** `dc up -d --build`, `live_track_image`, `wait_started_ready 400`, PASS. Read one line: the task's id, `Heartbeat.ScheduleOf`, `RunAsUser`, `TaskCount("OcuTalon heartbeat")`, `SuspendedGetStored` (must be 0) and the tick mark.
  2. **Suspend.** `##class(%SYS.Task).Suspend(id, 1)`, then PASS when `SuspendedGetStored` is 1.
  3. **Restart 1.**
     - `dc stop iris`, `dc start iris`, `wait_started_ready 300`, and print `TIMING restart 1 (task suspended): <s>s to ready`.
     - The log has `STEP Reconcile OK` and exactly one line `WARN Reconcile the task "OcuTalon heartbeat" was suspended, so it was resumed`.
     - Then `wait_until 120`: `SuspendedGetStored` is 0 AND the `heartbeatTick` mark is at or after the container's start stamp (`started_at | cut -c1-19`, compared as ISO UTC text). On PASS, print `TIMING first tick <s>s after ready`.
     - The task has the same id, `ScheduleOf` and `RunAsUser`, and `TaskCount` is 1.
  4. **Restart 2, not suspended.** The same stop and start. The log has `STEP Reconcile OK` and no `WARN Reconcile the task` line, and the task is unchanged (same id, `ScheduleOf` and 0).
  5. `check_clean_start "after both restarts"`, a TIMING total, and the usual final lines with `$fails`.
  - The header states what it pins and what it needs (Rule 14). Unset `OCUTALON_EVAL`, as the sibling does.
- [ ] `ci/units.sh`:
  - append ` live:heartbeat-restart` to the `shards)` line (`:134`);
  - append one comment paragraph after `:127` with the measured figures under `ci_groups` (Design Notes). The unit reads no web bundle, but it isn't added to `NO_WEB_BUNDLE_UNITS` (Decided 6).
- [ ] `release/demo-host-check.sh` -- the RELEASE TOOL hunks of Design Notes, exactly. DW-1018.
- [ ] `docker/tests/test-online-host.sh` -- the test hunks of Design Notes. DW-1018.
- [ ] `release/demo-host-checks.md` -- the doc hunks of Design Notes. DW-1018.

**Acceptance Criteria:**
- **AC 1 (DW-1018).** **Given** the heartbeat task exists with `Suspended` 1 or 2, **when** OcuTalon starts, **then** the task's stored `Suspended` is 0, and exactly one line names it:
  - **through the after-start script:** `WARN Reconcile the task "OcuTalon heartbeat" was suspended, so it was resumed` in `/durable/ocutalon-after-start.log`;
  - **through ReconcileIn:** one Event Log Warning `ReconcileIn: the task "OcuTalon heartbeat" was suspended, so it was resumed`;
  - **through an IPM install:** the same `WARN Reconcile` line in the install output. `Registry.Run("ipm")` runs the same Reconcile step, so `TestReconcileResumesHeartbeat` pins it, and no live IPM run is added in this story;
  - **and** there is still one task of that name, with the same id, schedule, `RunAsUser`, `NameSpace`, `TaskClass` and `Description`.
- **AC 2.** **Given** the task exists with `Suspended` 0, **when** OcuTalon starts, **then** the task is unchanged and no line naming it is written.
- **AC 3.** **Given** no task of that name, **when** the resume runs, **then** it returns OK, creates and changes nothing, and writes no line. On the after-start path, the Tasks step creates the task as today and the Reconcile step finds it at 0.
- **AC 4 (live).** **Given** a throwaway stack whose heartbeat task was suspended, **when** the container is restarted, **then** within 120 s of the start ending ready the task is at 0 and `heartbeatTick` holds a tick taken after the restart. A second restart with the task running writes no resume line. The unit `live:heartbeat-restart` runs in CI group `shards`.
- **AC 5.** **Given** the unit tests in `OcuTalon.Test.Schedule.TaskResume`, **when** they run on a throwaway, **then** the not-suspended, suspended (1 and 2) and missing cases, and the Reconcile and ReconcileIn wiring, pass. The real task's `Suspended` is as it was found afterwards.
- **AC 6 (host check).** **Given** `--heartbeat` evidence whose `lastTick` is more than 180 s before its `now`, or whose `suspended` is not 0, **when** `release/demo-host-check.sh` runs in the normal state, **then** it prints `FAIL heartbeat-tick ...` or `FAIL heartbeat-task ...` and exits 1. With fresh evidence and `suspended` 0, all three `heartbeat-*` checks pass. Without the input, it prints `SKIP heartbeat` and exits 3. It sends no request it didn't send before.

## Spec Change Log

- 2026-11-10 (lead, spec gate): the Contest Planner's ruling recorded under Design Notes, "Spec gate: ruling" [AMENDED 2026-11-10, Contest Planner ruling]. The texts are approved as written. The doc hunk (3b) must give a paste-ready, read-only host command naming `ocutalon-demo-iris` and reading the stored Suspended value, and must say that the 180 s threshold equals the banner's. The AD-18 line is written in the spine by the lead.

## Review Triage Log

### 2026-11-10 -- Review pass
- verdicts: 29 findings (rows group findings that share a root cause) -- high 0, medium 2, low 27, false 0, maybe-false 0; 11 patched, 18 rejected
- findings:
  - `[low]` `[patch]` blind 1 / edge 9 -- `ci/units.sh` comment sizes the unit at 350 to 450 s while the local run was 521 s -- the comment now states the local figure and that CI's is the one to confirm
  - `[low]` `[patch]` blind 2 -- `test-heartbeat-restart.sh` fails on lib-live's 540 s default locally -- the header names `OCUTALON_LIVE_DEADLINE=1200` (CI's value)
  - `[low]` `[patch]` blind 3 / edge 4 -- `resumed_since` used a locale `sort` -- now `LC_ALL=C sort`; the fraction part is `[reject]`: `NowUtc()` writes whole seconds (`Data.Time.NowUtc`)
  - `[low]` `[reject]` blind 4 / edge 1 -- Reconcile now fails when Resume fails, against "warns without failing" -- spec-bound: Decided 3 makes a failed Resume an error; the doc comment says both; row 5 is now pinned by `TestResumeFails` and `TestReconcileReportsFailedResume`
  - `[low]` `[reject]` blind 5 / edge 3 -- `FindId` resumes one of two same-named tasks -- no path creates a second (`Tasks.Create` finds by name first), wontfix-theoretical
  - `[low]` `[reject]` blind 6 / intent 1 -- a stale capture passes `heartbeat-tick` -- spec-bound: the tick is compared with the `now` printed beside it (Design Notes 1f3); the Planner prints the file at the run
  - `[low]` `[reject]` blind 7 -- a killed run leaves a probe task -- its StartDate is a year ahead and it exists only on throwaways, wontfix-theoretical
  - `[low]` `[reject]` blind 8 / gap other 2 -- plan bullets remain beside the `mutation:` lines -- the fix is a spec edit; the `mutation:` lines carry the results
  - `[low]` `[reject]` edge 2 -- Resume OK while the stored value stays non-zero -- Resume is one SQL UPDATE (measured, M1); no such state is reachable
  - `[medium]` `[patch]` edge 5 / gap other 1 -- `HoldRow` waited 5 s for the lock-holding job, and a late job could block the restore -- the wait is 10 s, twice the job's own lock wait
  - `[low]` `[reject]` edge 6 -- `suspended` "0" as a string passes -- the host command prints a number; theoretical
  - `[low]` `[reject]` edge 7 -- a tick later than now passes -- spec-bound (Decided 7); now pinned by the `hb-future` fixture (see the gap row)
  - `[low]` `[patch]` edge 8 -- the doc says the check fails exactly when the page shows the banner, but an empty tick fails the check only -- the sentence now says "for a readable tick" and names the empty case (flagged to the lead as a narrowing of the ruling's wording)
  - `[low]` `[patch]` gap 1 -- AC 5 "restored afterwards" had no assertion or mutation -- `RestoreRealTask` asserts it at the end of each real-task test; mutation recorded
  - `[low]` `[patch]` gap 2 -- AC 4 had no mutation line -- demonstrated on the live unit (3 checks red); recorded
  - `[low]` `[patch]` gap 3 -- the negative-age rule had no fixture -- `hb-future.txt` (age -30) added to row 17, expecting exit 0
  - `[low]` `[reject]` gap 4 -- no fractional-second fixture -- `NowUtc()` and the tick mark are whole seconds; theoretical
  - `[low]` `[reject]` intent 2-7 -- descriptive divergences (extra FAIL conditions and usage errors the intent does not name, failed Resume status, IPM path pinned through the shared Reconcile, plain restart in place of an update flow, banner not observed directly, no new request) -- each is in the spec's Design Notes or Acceptance Criteria as written; nothing to patch

## Design Notes

**Governing ADs:**
- **AD-18:** the heartbeat is a Task Manager task declared in the Schedule step's `Tasks()`. `StatusMonitor` stalls past 3 minutes, which sets the host check's 180 s.
- **AD-19:** the seed rule. The task's definition is seed and is never rewritten; `Suspended` is run state, which the resume clears.
- **AD-22:** a throwaway for the destructive live unit, the units in `ci/units.sh`, and the groups.
- **AD-23:**
  - the after-start order (`Tasks`, then `Production`, then `Reconcile`), and IPM's `Registry.Run("ipm")`;
  - ReconcileIn on every other production start, and idempotent `Reconcile()` declarations;
  - `Warn` for a non-fatal condition;
  - "Who owns the steps": Lane A's core is untouched.
- **AD-24:** no new role or grant; `OcuTalonUser` is unchanged.
- **AD-25:** the host check stays read-only and opens no new public read.
- **AD-29:** Lane B's files, run on runner C. The `release/` and `test-online-host.sh` hunks are Lane A's, named in the story's file list (owner-approved), so report them as `footprint_extensions`.
- **Checked:** no AC contradicts an AD's Rule.
- **Spine note for the lead (Rule 20):** AD-23 says the core's task step "leaves an existing task's schedule and properties alone". With this story, the Schedule area's `Reconcile()` resumes a Suspended heartbeat task at every start, so a deliberate Task Manager suspension of that one task doesn't survive a start. The recommended one-line addition to AD-23 and AD-18 is in the final report.

**Task 0 measurements** (2026-11-10 UTC, slot C task 1007 and the lane-C warm throwaway `e8s8pw`, both build 154):
- **M1, the API** (slot C, task 1007):
  - `##class(%SYS.Task).Suspend(ID, Flag=1)` and `Resume(ID)` are ClassMethods of `%SYS.TaskSuper` that return `%Status`.
  - `Suspend(1007,1)` gave Suspended 1; `Resume` gave 0. `Suspend(1007,2)` gave 2; `Resume` gave 0. Through both, `DisplayNextScheduled`, `TimeNextScheduled`, `DailyFrequency`, `DailyIncrement`, `StartDate`, `RescheduleOnStart` and `RunAsUser` were unchanged.
  - `Resume` of a task that isn't suspended returns 1, and of a missing or empty id `ERROR #7419 ... (SQLCODE=100)`.
  - Task 1007 was left at 0, ticking, with `RunAsUser` `_SYSTEM`.
- **M2, the values:** the property says 0 is not suspended, 1 is suspended and left in the queue, and 2 is suspended, removed and rescheduled. This story resumes both 1 and 2. The Task Manager's own suspension sets 1 (M4).
- **M3, the callers** (throwaway):
  - the after-start session is `irisowner` with `%All`, which is also the task's `RunAsUser` there;
  - ReconcileIn's job runs as `_Ensemble` with `%All`, `%DB_OCUTALON_CODE`, `%DB_OCUTALON_DATA` and `%EnsRole_ProdPrivs_OCUTALON`;
  - after `$SYSTEM.Security.Login` as test users: `%Developer` alone could `Resume(1007)` but couldn't create a task (`ERROR #921: Operation requires %Admin_Task:USE privilege`). `%Manager` could do both. `%Operator` couldn't run code in OCUTALON at all.
  - So `Resume` needs no more than `Create` already does: an IPM installer that created the task can resume it, and so can a less privileged upgrader.
- **M4, the cause on the demo (the mechanism reproduced, the demo itself inference):**
  - With task 1007 at 0 and ticking, deleting the class `OcuTalon.Schedule.HeartbeatTask` for one minute boundary left the task at **Suspended 1, Status 1, Error "Success", LastFinished the previous run**. That is exactly the demo's state: "last run OK, SuspendOnError 0". The run that failed in Task Manager code recorded nothing.
  - Reloading the class didn't resume it. A restart (`docker stop -t 60` / `start`, 27 s to ready) left it at 1, with no tick 4 minutes later.
  - (inference) On the demo, the update's in-place upgrade recompiles the package (after-start step 2), and a minute boundary inside that compile suspended the task. The Reconcile step runs after that load, so it repairs it in the same start.
- **M5, a pitfall:** after `%OpenId(1007)` in a process, `Resume` and then `%OpenId(1007)` again returned the cached OREF with Suspended 1. `SuspendedGetStored(id)` reads storage.
- **M6, a prototype of the planned code** (throwaway only, not in the tree):
  - Suspended 1, then restart: the log had `STEP Reconcile OK`, then `WARN Reconcile the task "OcuTalon heartbeat" was suspended, so it was resumed`. Ready came 27 s after `docker stop`, and the first new tick 60 s after ready, at the next minute boundary.
  - Suspended 2: the same through `Reconcile()` directly. A missing name gave OK and no line. At 0 there was no line.
  - ReconcileIn path: a stop and start of the production through `Ens.Director` (not the Production step) resumed the task within 6 s, with one Event Log Warning row (type 3) `ReconcileIn: the task "OcuTalon heartbeat" was suspended, so it was resumed`.
  - After a resume, the next run was the next minute boundary, with one catch-up gap mark (`missed` 4).
- **M7, the host evidence command** (throwaway): the command in the doc hunk printed the IRIS banner, then `{"lastTick":"2026-11-10T01:29:01Z","now":"2026-11-10T01:29:41Z","suspended":0}`. `grep '^{' | tail -n 1` with jq `fromdateiso8601` gave an age of 40 s.
- **Teardown.** The throwaway was removed by `ci/warm.sh down` (1 project, nothing left over), and the tree was clean.

**Spec gate: privilege — none (measured: Task 0 M3).** The after-start caller (`irisowner`, `%All`) and ReconcileIn's job (`_Ensemble`, `%All`) both resumed the task. `Resume` succeeded for a user holding only `%Developer`, where creating a task needs `%Admin_Task:USE`, so every installer that can run the Tasks step can resume. No role, grant, resource or privilege is added, and `OcuTalonUser` is untouched.

**Spec gate: PUBLIC TEXT.** Every new user- or admin-visible string, verbatim. No banner, digest or catalog text changes.
- `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls`, the new `ResumeTask`, planned at about `:36`. The Warn text is `the task "OcuTalon heartbeat" was suspended, so it was resumed`. The name comes from `HEARTBEATTASK`. It reaches:
  - the after-start log and IPM output as `WARN Reconcile the task "OcuTalon heartbeat" was suspended, so it was resumed`;
  - the Event Log, through ReconcileIn, as `ReconcileIn: the task "OcuTalon heartbeat" was suspended, so it was resumed`.
- `release/demo-host-check.sh`:
  - `:3`, the usage comment: `#   bash release/demo-host-check.sh <base-url> [--state normal|busy|maintenance] [--demo-status FILE|-] [--zone FILE|-] [--heartbeat FILE|-]`
  - `:59`, `usage()`: `usage: bash release/demo-host-check.sh <base-url> [--state normal|busy|maintenance] [--demo-status FILE|-] [--zone FILE|-] [--heartbeat FILE|-]`
  - about `:100`: `demo-host-check: --heartbeat needs a file or -`
  - `:111`, unchanged text, now over three inputs: `demo-host-check: at most one input may be - (standard input)`
  - `check_heartbeat`, about `:455-485`:
    - `SKIP heartbeat no --heartbeat input given`
    - `PASS heartbeat-json the input holds a JSON object`
    - `FAIL heartbeat-json the input holds no JSON object line`
    - `PASS heartbeat-tick the last tick is <n> s old`
    - `FAIL heartbeat-tick the last tick is <n> s old, more than 3 minutes`
    - `FAIL heartbeat-tick the input has no readable lastTick and now`
    - `PASS heartbeat-task the heartbeat task is not suspended`
    - `FAIL heartbeat-task the heartbeat task is suspended (Suspended <n>)`
    - `FAIL heartbeat-task the heartbeat task does not exist`
    - `FAIL heartbeat-task suspended is <value>, not 0, 1, 2 or missing`
  - Header comment lines (`:20-22`, `:42-43`):
    - `#                heartbeat-*  the heartbeat's last tick and its task, from one line that a terminal on the host prints, piped in with --heartbeat: the tick is at most 3 minutes old and the task is not suspended (DW-1018);`
    - `# \`ocutalon-demo status\`, the TZ of the IRIS container and the heartbeat line are the Planner's to read on the host; this script runs none of them and takes their output from a file or standard input.`
- `release/demo-host-checks.md`: the run 1 text, the H26 row and the new section, in the RELEASE TOOL block.

**Spec gate: RELEASE TOOL.** The hunks the lead relays to the Planner.

1. `release/demo-host-check.sh`:
   - a. **Header.**
     - `:3` and `:59` get ` [--heartbeat FILE|-]`.
     - After the `zone` entry (`:22`), add the `heartbeat-*` entry above.
     - `:42-43` becomes the sentence above.
   - b. **Arguments.**
     - Initialise `heartbeat_src=""` beside `zone_src` (`:79`).
     - Add a `--heartbeat)` case after `--zone)` (`:92-96`), in its shape: `[ $# -ge 2 ] || usage "--heartbeat needs a file or -"`.
   - c. **One stdin** (`:111`): count the inputs equal to `-` among `demo_status_src`, `zone_src` and `heartbeat_src`, and give the same usage message when there is more than one.
   - d. **Read before any request** (after `:146`): `if [ -n "$heartbeat_src" ]; then read_input "$heartbeat_src" "$work/heartbeat.txt"; fi`.
   - e. **`run_normal`** calls `check_heartbeat` after `check_zone` (`:395`). The busy and maintenance states ignore the input, as they do `--zone`.
   - f. **`check_heartbeat`**, after `check_zone`:
     1. With no source, `skip heartbeat ...` and return.
     2. Take the last line starting with `{`: `tr -d '\r' < "$work/heartbeat.txt" | grep '^{' | tail -n 1 > "$work/heartbeat.json"`. If it is empty, or `jq -e 'type == "object"'` fails, `fail heartbeat-json ...` and return. Otherwise `pass heartbeat-json`.
     3. The age, with jq: when `lastTick` and `now` are both strings matching `$iso_re`, it is `(now | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) - (lastTick | ...)`, an integer; otherwise none.
        - With no age: `FAIL heartbeat-tick the input has no readable lastTick and now`.
        - Age over 180: `FAIL ... <n> s old, more than 3 minutes`.
        - Otherwise (a negative age included, as `Heartbeat.Stalled` treats a tick later than now): `PASS ... <n> s old`.
     4. `suspended` (`jq -r '.suspended'`):
        - `0`: PASS;
        - `1` or `2`: `FAIL ... suspended (Suspended <n>)`;
        - `missing`: `FAIL ... does not exist`;
        - anything else: `FAIL ... suspended is <value>, not 0, 1, 2 or missing`, where the value is `jq -c` of the field, cut to 40 characters.
     - It sends no request. Exit codes come from the existing summary.
2. `docker/tests/test-online-host.sh`:
   - a. **Header.** Add `row 17  --heartbeat (DW-1018)`, and change "H1 to H25" to "H1 to H26" at `:26`.
   - b. **Fixtures**, after `:315`: `write_hb_fixture <file> <age s> <suspended JSON>` writes the two IRIS banner lines (`Node: x, Instance: IRIS`, a blank line, `OCUTALON>`), then one JSON line `{"lastTick":<now - age>,"now":<now>,"suspended":<v>}` (built by `jq -nc` with `now | floor | todate`), then `OCUTALON>`. The banner pins that only the JSON line counts.
     - Fixtures: `hb.txt` (40, 0), `hb-180.txt` (180, 0), `hb-181.txt` (181, 0), `hb-old.txt` (240, 0), `hb-s1.txt` (40, 1), `hb-s2.txt` (40, 2), `hb-missing.txt` (40, `"missing"`), `hb-notick.txt` (`lastTick` ""), `hb-bad.txt` (`not json` only) and `hb-odd.txt` (`suspended` `"x"`).
   - c. **`full`** (`:347`) gets `--heartbeat "$tmp/hb.txt"`. Every run in rows 9 to 12 that names `--demo-status` or `--zone` explicitly also gets `--heartbeat "$tmp/hb.txt"`, so their expected exit codes and SKIP sets stay as they are. Row 1's id list (`:396-397`) adds `heartbeat-json heartbeat-tick heartbeat-task`.
   - d. **Row 17.** One run per case, through `expect_run` (exact FAIL and SKIP sets) and `line_has` for the texts:
     - `hb.txt` exit 0;
     - `hb-180` exit 0, and `hb-181` exit 1 with `heartbeat-tick` and "more than 3 minutes";
     - `hb-old` exit 1 `heartbeat-tick`;
     - `hb-s1` and `hb-s2` exit 1 `heartbeat-task`, "(Suspended 1)" and "(Suspended 2)";
     - `hb-missing` exit 1 `heartbeat-task`, "does not exist";
     - `hb-notick` exit 1 `heartbeat-tick`;
     - `hb-bad` exit 1 `heartbeat-json` only;
     - `hb-odd` exit 1 `heartbeat-task`;
     - `--heartbeat -` with `run_stdin` exit 0;
     - no `--heartbeat`, exit 3 with SKIP `heartbeat`.
     - Each with `--demo-status "$tmp/ds.json" --zone "$tmp/zone.txt"`.
   - e. **Usage cases.** Add `usage_case "--heartbeat without a value" X=1 --heartbeat` and `usage_case "two inputs on standard input (zone and heartbeat)" X=1 --zone - --heartbeat -`.
   - f. **The check list.** `host_status_bad`'s `seq 1 25` becomes `seq 1 26`, and its PASS and FAIL texts say H1 to H26.
3. `release/demo-host-checks.md`:
   - a. **Run 1** (`:23`) adds the heartbeat line (`--heartbeat`), and "at most one of the two" becomes "at most one of the three". The example command adds `--heartbeat heartbeat.txt`.
   - b. **A new section after "The probe's host interface", `## The heartbeat input (DW-1018, H26)`.**
     - The Planner reads it on the host, outside the cap (a terminal takes one licence unit; see "The licence units"), with:

       ```
       printf '%s\n' 'Set id=##class(%SYS.Task).FindId("OcuTalon heartbeat") Write !,{"lastTick":(##class(OcuTalon.Data.StatusMark).Get("heartbeatTick")),"now":(##class(OcuTalon.Data.Time).NowUtc()),"suspended":($Select(id="":"missing",1:##class(%SYS.Task).%OpenId(id).Suspended))}.%ToJSON(),!' 'Halt' \
         | docker exec -i <iris container> iris session IRIS -U OCUTALON > heartbeat.txt
       ```

       This is the command measured in M7.
     - The script reads the last line that starts with `{`. It fails `heartbeat-tick` when `now - lastTick` is over 180 s, and `heartbeat-task` when `suspended` is not 0.
     - A host-side fix is no longer needed from 1.0.6: the next start resumes the task.
   - c. **H26** in the criteria table: `| H26 | DW-1018: the heartbeat ticks (last tick at most 3 minutes old) and its task is not suspended | \`heartbeat-*\` | Run 1 with \`--heartbeat\` | pending |`.

**Spec gate: ruling** [AMENDED 2026-11-10, Contest Planner ruling] (owner delegation, ~02:10Z, relayed by the orchestrator; the verbatim ruling is in the coordination folder's `epic-8-rulings-88.md`):
- **Approved as written:** the resume line in its three forms (the `Schedule.cls` Warn text, the after-start/IPM `WARN Reconcile ...` line, the Event Log Warning `ReconcileIn: ...`); every `check_heartbeat` PASS/FAIL/SKIP line, the usage lines and the usage error above; the `--heartbeat FILE|-` input, with `SKIP heartbeat` and exit 3 when it is absent, like the other optional inputs. The Planner adds `--heartbeat` to Run 1 in the runbook.
- **Conditions the doc hunk (3b) must meet** (checked by the lead before PART READY):
  1. `release/demo-host-checks.md` gives the exact host command that prints the JSON line, ready to paste, with `ocutalon-demo-iris` as the example container name (not a `<placeholder>`), and the doc says plainly that the command is read-only: it never resumes or changes the task. The command reads only (`FindId`, `StatusMark.Get`, `Data.Time` now, and the stored Suspended value through `##class(%SYS.Task).SuspendedGetStored(id)` rather than `%OpenId(...).Suspended`, as the product code does); re-measure it on the throwaway (M7) after the change.
  2. The `heartbeat-tick` FAIL threshold (more than 180 s) is the same number as the page banner's stall threshold (`OcuTalon.Schedule.Heartbeat` `STALLSECONDS` 180, which `StatusMonitor` uses for `heartbeatStalled`), and the doc line says so: the host check fails exactly when the page would show the stalled banner. If the implementation finds the two numbers differ, that is a blocker to report, not a silent choice.
- **The AD-18 line** is approved by the orchestrator (U14) and written by the lead in the spine, marked `[ADDED 2026-11-10, Story 8.8]`.

**Decided in-stage (implement):**
- The doc's banner sentence is narrowed (review): for a readable tick `heartbeat-tick` fails exactly when the page would show the banner, and the doc says that an empty or unreadable tick also fails the check where the page shows no banner (`Heartbeat.Stalled` returns 0 for those). The 180 s equality with `STALLSECONDS` is stated unchanged. The lead should ratify this narrowing with the Planner's ruling condition 2.
- Matrix row 5 (Resume fails) is covered by `TestResumeFails` (probe task) and `TestReconcileReportsFailedResume` (real task, through `Reconcile()`). A failing `Resume` is provoked by a second job holding the task's row lock (`^|"^^"_$ZU(12)|SYS("Task","TaskD",id)`, measured on slot C: `Resume` returns `ERROR #7419 ... (SQLCODE=-110)` after 10 s and the stored Suspended stays 1). A past `EndDate` and a deleted `RunAsUser` do not make `Resume` fail (measured).
- `Test.Schedule.TaskResume` creates its probe task only for `TestNotSuspended` and `TestSuspended`. `Snapshot` compares the id, `ScheduleOf` without its `Suspended` field, `RunAsUser`, `NameSpace`, `TaskClass`, `Description` and `Name`, each from a fresh `%OpenId` inside a class method (no OREF held by the caller).
- `test-heartbeat-restart.sh` needs more than the 540 s default deadline of `lib-live.sh` on a loaded developer machine (521 s of work, 8:53 wall including the build): run it locally with `OCUTALON_LIVE_DEADLINE=1200`, which is CI's value. The measured TIMING lines: restart 1 (task suspended) 26 s to ready, first tick 62 s after ready, restart 2 44 s.
- The doc command was re-measured on the lane-C warm throwaway (SuspendedGetStored form): `{"lastTick":"2026-11-10T02:13:00Z","now":"2026-11-10T02:13:44Z","suspended":0}`.

**Decided:**
1. **Where the resume lives.** It is in `Install.Step.Schedule` (`ResumeTask` called from `Reconcile()`), as the lead expected. The Reconcile declaration is the one hook all three start paths share, and it runs after `Tasks` and the package load.
   - A method in `OcuTalon.Schedule.*` would add a class and a cross-class call for four lines.
   - Making it a by-name method keeps the probe tests off the real task.
2. **What "resumed" means.** Any non-zero `Suspended` is resumed: 2 is also a suspension (M2). That covers both the Task Manager's own value (1, M4) and a by-hand suspension with reschedule.
3. **A failed `Resume` is an error, not a Warn.** This follows the sibling (`Reminder.Reconcile`'s status is returned). M3 measured no reachable failure for the real callers, and silent loss of the heartbeat is the bug being fixed.
4. **"Within 2 minutes of the restart"** is pinned as 120 s from the start ending ready (`wait_started_ready`), with the seconds from `docker start` printed. Both readings hold: the measured restart takes 23 s on CI and 27 s here, and the first tick comes at most about 60 s after ready. This is the observable restated so it can be measured; the intent is unchanged.
5. **A new test class (Rule 2).** `Test.Schedule.TaskResume` is new instead of more tests in `Test.Schedule.Heartbeat`. That class swaps the Checks item for a double, needs the production running and takes 140 to 206 s of real Task Manager waits. The resume tests need none of that: they run in seconds on probe tasks.
   - Reused helpers: `Heartbeat.ScheduleOf` and `Heartbeat.TaskCount` (ClassMethods) and `Heartbeat.SettleScheduler`.
   - Copied: the Event Log row count from `Test.Install.ReconcileIn` (Private, in Lane A's file), with the reason in the class header.
6. **`NO_WEB_BUNDLE_UNITS` isn't extended.** `shards` holds units that read the bundle, so appending changes no skip, and it would touch one more contended list.
7. **The host check's tick rule** mirrors `Heartbeat.Stalled`: over 180 s is stale, and a tick later than now isn't. An empty or unreadable tick fails, because a live demo that never ticked is the fault this check exists for.

**The two-minute live unit and the restart sibling.** `test-heartbeat-restart.sh` copies the plain-restart shape of `test-reminder-restart.sh`, `:206-234`, because Epic 41 now owns that file and it can't be extended (lead's ruling).

**Integration ACs.** The consumers are `OcuTalon.Install.Step.Reconcile` (after-start and IPM) and `OcuTalon.Install.ReconcileIn` (a production start the Production step didn't make).
- `TestReconcileInResumes`: ReconcileIn reads `Reconcile()`'s warning and writes one Event Log Warning row naming the task.
- The live unit: the after-start registry writes `WARN Reconcile ...`, and the task ticks within 120 s.
- **Consumed-by:** `OcuTalon.Install.Step.Reconcile` (Story 0.2's step; after-start and `Registry.Run("ipm")`) and `OcuTalon.Install.ReconcileIn` (Story 15.2), so that every start resumes the heartbeat (FR-32).
- **Consumes:** `%SYS.Task` (`FindId`, `SuspendedGetStored`, `Resume`), `OcuTalon.Install.Step.Warn`, and `OcuTalon.Schedule.Reminder.Reconcile` (unchanged).
- **Ledger.** DW-1018 is addressed by the Schedule.cls, TaskResume, live unit and three host-check tasks, AC 1 to 6. No other entry is owned by this key.
- **Routes.** No `/api/v1` route is added or changed, so the real-HTTP route rule doesn't apply.
- **Residual risk (inference).** A suspension that happens after the start's Reconcile, or after ReconcileIn's one reconcile (for example a Task Manager job timeout under load later on), isn't resumed until the next start. The host check's `heartbeat-*` lines are what catch it. This is out of scope.

**new_units:** `live:heartbeat-restart` (`docker/tests/test-heartbeat-restart.sh`): one first start, two plain restarts and a wait for the tick of at most 120 s. Estimated at about 350 to 450 s on CI (inference): `live:compose-start` is 173 to 191 s for a start, and a plain restart took 23 s in `live:reminder-restart` (run 42730214385). Locally: 27 s to ready per restart and a first tick 60 s after ready (M6). The first start took 276 s on the loaded developer machine.

**ci_groups:** `shards`, which becomes `shard:lane-a@Install,Digest,Eval live:online-allowance live:heartbeat-restart`. It is the existing IRIS group with the most headroom on the two newest full green runs.
- Group unit seconds, then job seconds:
  - `shards` 1,233 / 1,267 (run 42730214385, OCT-epic41) and 1,346 / 1,376 (run 42718893543, OCT-epic20);
  - `shards-7` 1,341 / 1,377 and 1,288 / 1,321;
  - `image` 1,287 / 1,323 and 1,353 / 1,382;
  - `shards-3` 1,266 / 1,302 and 1,386 / 1,425;
  - `shards-10` 1,451 / 1,486. It holds `live:reminder-restart`, which is contended (Epic 41), so it was ruled out.
- Projected `shards`: about 1,700 to 1,800 s of units, about 30 minutes a job. That is inside REL-4's 35 minutes and the 40-minute timeout, and over Story 0.20's planned 29 minutes by about a minute (inference until a run measures it).
- Never `production`, `browser`, `install-fresh` or `install-upgrade`; no new group.
- `docker/tests/test-ci-config.sh` needs no edit.

## Verification

Lane C on the developer machine: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-c`, `OCUTALON_TEST_WEB_PORT=52803` and `OCUTALON_LOCK_OWNER='epic=8 stage=implement'` on every `ci/iris.sh`/`ci/warm.sh` call. The warm tag is `e8s8iw` and the fresh tag `e8s8i`. Every test or build call passes `timeout: 600000`, and IRIS MCP calls name `server` and `namespace`.

**Commands:**
- (loop) `OCUTALON_RUN_TAG=e8s8iw ci/warm.sh up` once, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s8iw ci/iris.sh class OcuTalon.Test.Schedule.TaskResume` -- expected: `CLASS ... passed`, in seconds (TaskResume's Reconcile and ReconcileIn tests wait at most about 21 + 60 s).
- (once) `OCUTALON_RUN_TAG=e8s8i ci/iris.sh live heartbeat-restart` -- expected: `test-heartbeat-restart: all checks passed` with the TIMING lines. It is about 150 to 300 s locally (276 s for a first start on a loaded machine), and a live unit can't be split, so give it the full 600 s timeout.
- (once) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s8iw ci/iris.sh class OcuTalon.Test.Schedule.Heartbeat` -- expected: passed. Story 8.1's single task and catch-up are unchanged. It is 140 to 206 s, one class.
- (once) the same with `OcuTalon.Test.Schedule.Stalled`, then with `OcuTalon.Test.Schedule.Reminders`, then with `OcuTalon.Test.Install.ReconcileIn`, one call each -- expected: passed.
- (once) `bash docker/tests/test-online-host.sh` -- expected: `test-online-host: all checks passed`. It took 169 s in planning before the about 12 new runs, about 2 s each, so allow 600 s. It is one hermetic script and can't be split.
- (once) `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-ci-changes.sh`, then `bash docker/tests/test-boundaries.sh`, one per call -- expected: each passes, with the unit counted in `shards`.
- (once) `OCUTALON_RUN_TAG=e8s8iw ci/warm.sh down` at the stage's end, and after a failure, then `OCUTALON_RUN_TAG=e8s8i ci/iris.sh teardown`.
- The full shards (`lane-b@rest`, `lane-a@*`) and the other groups are left to CI.

**Mutations (Rule 19; the implement stage records each result as `mutation: ... -> ...`):**

- mutation: AC 1 -- drop the `ResumeTask` call from `Reconcile()` (`Quit sc`) -> `TestReconcileResumesHeartbeat` (the task stays at 1, the heartbeat line occurs 0 times) and `TestReconcileInResumes` (no Warning row, task at 1) red on the warm stack; reverted, tree byte-identical. The live unit's resume check was not re-run under this mutation (a 9-minute run); it is the same Reconcile call, shown red by M4.
- mutation: AC 4 (live unit) -- `Quit sc` in place of `Quit $SYSTEM.Status.AppendStatus(sc, ..ResumeTask(..#HEARTBEATTASK))` in `Reconcile()` -> `ci/iris.sh live heartbeat-restart` fails 3 checks: "restart 1: the log has no STEP Reconcile OK, or not exactly one '...was suspended, so it was resumed' line", "restart 1: the task is not at 0, or no tick was taken after the start, within 120 s of ready" and "restart 2: the task changed or is not at 0" (the task stays at 1 across both restarts); reverted, byte-identical.
- mutation: AC 5 (the real task's Suspended is as it was found) -- `Quit $$$OK` at the top of `PutBack()` in `Test.Schedule.TaskResume` -> `TestReconcileReportsFailedResume` ("its stored Suspended is as the test found it") and, through the task it leaves at 1, `TestReconcileResumesHeartbeat` red on the warm stack; reverted, byte-identical.
- mutation: matrix row 5 (Resume fails) -- `Set sc = $$$OK` right after the `Resume` call in `ResumeTask` -> `TestResumeFails` ("a Resume that fails returns its status", "and writes no line") and `TestReconcileReportsFailedResume` red on the warm stack; reverted, byte-identical.
- mutation: AC 2 -- remove the `SuspendedGetStored` guard -> `TestNotSuspended` ("and writes no line") and `TestReconcileLeavesHeartbeat` ("no heartbeat line is written") red; reverted, byte-identical.
- mutation: AC 3 -- `If id = "" Quit $SYSTEM.Status.Error(5001, "no task")` -> `TestMissing` ("ResumeTask returns OK") red; reverted, byte-identical.
- mutation: AC 6 -- both applied in one run of `bash docker/tests/test-online-host.sh`: the limit 180 changed to 240, and `0 | 1)` for the PASS case of `suspended` -> row 17 red for `hb-181` (exit 0, no `heartbeat-tick` FAIL, no "more than 3 minutes" text), `hb-old` (240 s), `hb-s1` (no `heartbeat-task` FAIL, no "(Suspended 1)" text): 5 checks failed; reverted, byte-identical.
- AC 1: drop the `ResumeTask` call from `Reconcile()`. Expect `TestReconcileResumesHeartbeat`, `TestReconcileInResumes` and the live unit's resume check to go red (M4 showed the task staying at 1 with no tick).
- AC 2: remove the `SuspendedGetStored` guard. Expect `TestNotSuspended` red, from a line.
- AC 3: quit an error on an empty id. Expect `TestMissing` red.
- AC 6: change 180 to 240. Expect the row 17 `hb-181` case red. Treat `suspended` 1 as a pass, and expect `hb-s1` red.

**Shared surfaces:**
- **The host check's output.** A normal run of `release/demo-host-check.sh` without `--heartbeat` now has `SKIP heartbeat` and exits 3, so `test-online-host.sh` rows 1 and 9 to 12 and `full` get the input.
- **The check list.** `release/demo-host-checks.md` gains H26, and the H1 to H25 loop becomes H1 to H26.
- **Start lines.** The after-start log's `WARN Reconcile` lines and ReconcileIn's Event Log Warning rows appear only when the task was suspended. `test-reminder-restart.sh`'s `grep -q` tolerates an extra line, and `check_clean_start` counts types 2 and 6 only.
- **The real task's `Suspended`.** `Test.Schedule.Heartbeat`, `Stalled` and `StallFixture` (web heartbeat and banner specs) hold it suspended, but no Reconcile and no non-Production-step start runs during a hold. The new tests restore it.
- **The groups.** The `shards` unit list in `ci/units.sh` gains one unit; no pin names it.
- **The standing criterion.** Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `Install.Step.Schedule.Reconcile()` now resumes the `OcuTalon heartbeat` task when its stored Suspended value is 1 or 2 (`ResumeTask`, read through `SuspendedGetStored`, resumed with `Resume`) and writes one `Warn` line; a task at 0, or none, is left alone with no line; a failed `Resume` is returned. `release/demo-host-check.sh` takes `--heartbeat FILE|-` and prints `heartbeat-json`, `heartbeat-tick` (fails over 180 s, the banner's `STALLSECONDS`) and `heartbeat-task`, or `SKIP heartbeat` (exit 3).

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls`: `ResumeTask`, and `Reconcile()` calls it.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ResumeProbeTask.cls` (new): the probe tests' task class.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/TaskResume.cls` (new): not-suspended, suspended (1, 2), missing, failed Resume (row lock held by another job), Reconcile and ReconcileIn wiring, and the restore of the real task.
- `docker/tests/test-heartbeat-restart.sh` (new): the live unit (first start, suspend, restart 1, restart 2).
- `ci/units.sh`: `live:heartbeat-restart` in `shards`, and the comment paragraph.
- `release/demo-host-check.sh`, `release/demo-host-checks.md`, `docker/tests/test-online-host.sh`: the `--heartbeat` input, the H26 row and the row 17 cases.

**Review.** 4 layers, 29 findings: 11 patched (the units comment figure, the live unit's deadline note and `LC_ALL=C sort`, the lock-holder wait of 10 s, the doc's banner sentence narrowed, the `RestoreRealTask` assertion, the `hb-future` fixture, and two mutation lines), 18 rejected with reasons in the triage log, none deferred. Follow-up review recommended: false (one medium entry patched, no high).

**Verification (all on lane C).** `Test.Schedule.TaskResume` passed on the warm stack (the loop, after every patch); `Test.Schedule.Heartbeat` (85 s), `Stalled` (24 s), `Reminders` (87 s) and `Test.Install.ReconcileIn` (0.5 s) passed; `bash docker/tests/test-online-host.sh` passed (97 runs, 214 s) after the last patch; `test-ci-config.sh`, `test-ci-changes.sh` and `test-boundaries.sh` passed; `ci/iris.sh live heartbeat-restart` passed (restart 1 48 s to ready, first tick 58 s after ready, restart 2 24 s; total 522 s with `OCUTALON_LIVE_DEADLINE=1200`). Mutations: AC 1, 2, 3, 4, 5, 6 and matrix row 5 each demonstrated red and reverted byte-identical (see `## Verification`).

**Residual risks.**
- `shards` becomes about 30 minutes a job (inference until a CI run measures it); locally the unit took 522 s on a loaded machine.
- The doc's banner sentence is narrower than the ruling's wording (an empty tick fails the check; the page shows no banner): the lead should ratify it.
- Footprint extensions (AD-29): `release/demo-host-check.sh`, `release/demo-host-checks.md`, `docker/tests/test-online-host.sh`.
- The spine needs the one-line addition to AD-18 and AD-23 that the spec's Design Notes give (Reconcile resumes a Suspended heartbeat task at every start); the lead writes it.
- During the stage, one slot-C probe task row was wiped by hand and removed with `%BuildIndices` in `%SYS` (slot C task 1007 stayed at Suspended 0; no probe task or scratch class remains).
