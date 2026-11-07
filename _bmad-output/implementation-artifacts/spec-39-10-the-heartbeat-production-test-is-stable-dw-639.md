---
title: 'Story 39.10: The heartbeat production test is stable (DW-639)'
type: 'bugfix'
created: '2026-11-07'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Test.Schedule.Heartbeat` `TestAfterAllTestsNothingSaved` fails at "and the production runs every item" (`Install.Step.Production.NotRunning()` not empty) in CI's `image` job (`shard:lane-b`), about once in a few runs (DW-639: 3 heads in 6 hours on 2026-11-07, earlier ones since 2026-11-03), and each red goes green on one rerun. So a red on the image shard does not mean a real defect. The planning stage could not confirm the cause inside its timebox (see TIMEBOX under Design Notes).

**Approach:** Measure first: the assertion names the missing items and their state, and Task 0 reproduces the red under a CI-like load run and identifies the item. Then make the test read a settled state: before it calls `OnAfterAllTests`, it waits (bounded, reported) until every enabled item runs, by the same predicate the pin uses; the pin after the call stays an immediate, raw `NotRunning()` check. The fix lands only with its proof: the old code red under the load run, the fixed code 20 of 20 under the same load.

## Boundaries & Constraints

**Always:**
- Test-only: `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` and its fixture `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`. Any cause found in product code is recorded as `PRODUCT CAUSE:` and stops the story for a ruling before any product change.
- The pin keeps its predicate and its moment: right after `other.OnAfterAllTests()`, `Install.Step.Production.NotRunning()` must be `""`, read once, with no wait. Its message keeps the text "and the production runs every item" and adds, when it fails, the missing items and `RunnerFixture.StateOf` of them.
- The new wait is a precondition, asserted as a control: "control: every item runs before the call". It is bounded by the fixture's `WAITSECONDS` (60) and, when it is not met, fails with the items and their state. It uses `NotRunning()` (every enabled item with a pool), not `NotRunningNow()`.
- The 20-of-20 proof and the old-code red run under the same load, on lane D throwaways only, each command inside one 10-minute foreground call.
- No shown text changes (39.10 changes no product string).

**Never:**
- Delete, skip or weaken any assertion of the class; move the pin after a wait; use `NotRunningNow()` for the pin; raise `WAITSECONDS`, `RECORDSECONDS`, `RUNSECONDS`, `RUNNOWSECONDS` or any other existing bound.
- Change `Install/Step/Production.cls` or any other product class; change `ci/units.sh` (Epic 19's), `release/*`, `eval/run.sh` or the IPM scripts.
- Load the shared Docker VM to make load: throttle only this stage's own throwaway (`docker update --cpus <n>` on its own iris container).
- Run tests on `ocutalon-slot-d` or any other slot or instance.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Settled production | every enabled item has its job | control passes at once; `OnAfterAllTests` returns OK; pin passes | none |
| Item still coming up when the test begins | an item restarting (no job, or `Starting`) at the test's start | control waits until it runs (within 60 s), then the call and the pin as above | none; the wait time is in no assertion |
| Item never comes up | an item with no job for 60 s | control fails naming the item and its state (`StateOf`); the call and pin still run | a red that names the item, never a silent pass |
| Call disturbs the production (mutation) | `OnAfterAllTests` stops an item | pin fails at once, naming the item and its state | red, as before the fix |
| Product cause | Task 0 shows an item's job dying on its own (Dead, `terminated`, `error`) | no fix planned in this story | `PRODUCT CAUSE:` recorded, story stops for a ruling |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` -- the class under repair. `TestAfterAllTestsNothingSaved` (L596-612) is the first test method by name (`%UnitTest.Manager` collects `Test*` methods in name order, `irislib/%UnitTest/Manager.cls` L1341-1364), so it runs right after `OnBeforeAllTests` (L104-118), whose `UseItemClass(ITEM, DOUBLE)` restarts Checks. Its last line (L611) is the pin. `Restore` (L154-186) checks the same `NotRunning()` at the class's end and has never failed in CI.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- `WaitAllRun` (L127-135, polls `NotRunningNow` once a second up to `WAITSECONDS`), `NotRunningNow` (L141-154: `NotRunning` minus items whose System Default Settings `Enabled` row is 0, DW-591), `StateOf` (L164-182: row, runtime flag and jobs of each item), `UseItemClass` / `ChangeSettings` (L619-651, L712-721: save, `UpdateProduction(60)`, `WaitAllRun`). Every existing call of `WaitAllRun` passes no argument.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` -- READ-ONLY. `NotRunning` (L141-164): an item is missing when it is enabled, has a pool and no `Alive` job whose status is not in `DEADSTATUSES` (`error,halted,terminated`); `Starting` entries do not count.
- `irislib/Ens/Job.cls` -- READ-ONLY reference. `EnumerateFetch` (L854-875): `State` is `Dead` for `Z`-prefixed entries, `Starting` for `X`-prefixed ones, else `Alive`.
- `ci/iris.sh` -- the runner (`class`, `shard <name>[@<Area>,...] [--part k/n]`, `teardown`); `ci/warm.sh` (`up`, `down`, `status`). Unchanged.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` -- Task 0 (diagnostics, then measure, before the fix): read the pin's `NotRunning()` once into a variable and assert on it, with the message "and the production runs every item" followed, when it is not empty, by ": <items> (<StateOf of them>)". Then run the Task 0 load (Verification) with this version and record each run's result, the missing item and its state. Classify the cause with the matrix's last row and the Design Notes' decision table before any further change.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- extend `WaitAllRun` with an optional `every As %Boolean = 0`: with 1 it polls `##class(OcuTalon.Install.Step.Production).NotRunning()` instead of `NotRunningNow()`, same bound and pace; the default is unchanged for every existing caller. Its doc comment states both modes.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` -- in `TestAfterAllTestsNothingSaved`, before `other.OnAfterAllTests()`: `Do $$$AssertTrue($ClassMethod(..#FIXTURE, "WaitAllRun", 1), "control: every item runs before the call"_<": items (StateOf)" when not>)`. The pin after the call stays as Task 0 left it. Update the method's doc comment (what it pins and what it needs: a production running every item, waited for) and the class header's `(QA) TestAfterAllTestsNothingSaved` line to match.

**Acceptance Criteria:**
- Given the Task 0 load run (Verification) with the diagnostics-only version, when it runs, then at least one run is red at the pin and its message names the missing item and its state; the measurement (runs, reds, item, state, timing) is written under `## Verification` as `measured:` lines. If no run is red within the Task 0 budget, the stage stops with `## Clarification Needed` (TIMEBOX-2: not reproduced; diagnostics ready to ship alone) and lands no fix.
- Given the cause Task 0 found is test-side (an item the setup or an earlier class restarted, still coming up), when the fixed class runs 20 times under the same load, then it passes 20 of 20, and every run's control and pin pass.
- Given the mutation "`OnAfterAllTests` first stops an item" (Verification), when the fixed class runs, then the pin is red at once with the item named, so the precondition does not hide a production the call disturbed.
- Given `Test.Schedule.Heartbeat` on a fresh stack, when `shard lane-b@Schedule` runs forward and with `--reverse`, then every class passes (the standing criterion).

## Spec Change Log

## Review Triage Log

## Design Notes

**TIMEBOX (planning stage, 10:57Z to 12:04Z; cause not confirmed).** Measured on lane D throwaways (`e39s10plan`, `e39s10planw`), old code, the pin's value captured by a temporary probe (reverted, tree byte-identical):
- Reproduction: 0 red in 7 runs of the class: alone on a warm stack x3 (unthrottled, and twice at `--cpus 0.6`); warm `lane-b@Data,Demo,Live,Msg,Schedule` at 2 CPUs; fresh `shard lane-b --part 2/2` (53 classes, 593 s of classes alone, so over one call's 10 minutes: never run it in one call again); warm `lane-b@Live,Msg,Schedule` at 1 CPU; the CI order on one warm stack at 1.5 CPUs (`@Contract,Core` 265 s, `@Data,Demo,Live,Msg` 154 s, then the class). The probe read the pin 2 to 19 ms after `OnBeforeAllTests` ended, `""` each time.
- Ruled out: (1) the Checks swap itself: 56 swaps (`UseItemClass` / `RestoreItemClass`), 40 of them at 0.6 CPU, `NotRunning()` polled for 3 s after each return: 0 misses; the only gap is the new job's `Starting` entry, 11 to 15 ms, inside `WaitAllRun`. (2) A swap while the Checks job is busy (the double hanging 8 s on a Tick): `UpdateProduction` waits for it (8.97 s), the new job is up at return, 0 misses in 3. (3) The `Ens.Job:Enumerate` fetch race on a steady production (DW-772's shape): 215,626 `NotRunning()` calls and as many enumerations over 150 s spanning the minute task's runs: 0 misses, 0 fetch errors. (4) DW-591's shape (an `Enabled` row 0 with runtime flag 1, which `NotRunningNow` hides from `WaitAllRun`): after `Core.PersonaAnswers` (starts and stops TelegramIn/Out) both have row 0, flag 0, no job; the in-container sampler showed row `-` for every other item. (5) Spontaneous job deaths: the warm stack's event log held no "Terminating Job" row and `^Ens.JobStatus` no `Z` ghost entry after the runs.
- Sampler (an in-container IRIS job reading `NotRunning()` every 10 ms over three piece runs): every non-empty reading was a test's own restart (Checks swaps; production stop and start in `TestStoppedThenStarted` and `Schedule.Reminders`, about 1.4 s; agent runner and ReminderOps restarts in `Schedule.ReminderChat`, about 20 ms; FailurePoller paused 10.1 s by `Demo.Production`'s `PauseReading`).
- CI evidence (runs 42353010024, 42341818725, 42339077292, 42334354717, attempt 1): only this test failed; `Restore`'s check of the same predicate at the class's end passed every time; the class began 7.5 to 7.7 min after the stack's READY; start seconds 18 to 55 in the minute (no minute-boundary pattern). The CI logs do not name the missing item (the message has no value), hence Task 0's diagnostics.
- Structural finding (read, not inferred): this pin is the only check in `lane-b` that samples `NotRunning()` without waiting; every other readiness check (`WaitAllRun`, `Install.Step.Production.Start`) waits up to 60 s. So a transient outage of any item at that instant fails it while every other class absorbs it, and the test acts without first establishing its own precondition (Rule 19: wait for the system to signal ready before acting).
- Leading hypothesis (inference): an item that is still coming up, or restarting, in the first milliseconds after `OnBeforeAllTests` on a loaded CI host, caused by the setup's `UpdateProduction` or an earlier class. Not a product cause on present evidence.

**Decision table for Task 0's red (the cause decides the fix; record it as `cause:` under Verification):**
- The missing item is Checks, or another item a test or the setup restarted, shown `Starting` or `jobs none` and clearing within seconds: test-side; the planned precondition fixes it.
- An item whose job died (`Dead`, `last was: ...`, `terminated`, `error`) with no test stopping it: `PRODUCT CAUSE:` with the event-log rows; no fix in this story; stop for a ruling.
- An item that never comes back within 60 s: a leftover of an earlier class (out of footprint): record it as a `deferred:` item naming the class; the precondition's control then fails with the item named (a real red), and the stage stops with a clarification for the runner.

**Why the precondition does not weaken the pin.** The test pins "OnAfterAllTests of a class that saved nothing leaves the production as it is". "As it is" presumes a production that ran every item before the call; the test never established that. The pin's predicate, its moment (immediately after the call) and its text stay; the control is a new assertion, bounded and reported, that fails on a production that does not come up. A call that stops or restarts an item still turns the pin red (the mutation AC). The bound is the fixture's existing `WAITSECONDS`; no existing bound is raised.

**Decided in-stage:**
- The precondition sits in the test, not in `OnBeforeAllTests`, so the test is self-contained (Rule 19) and the other tests' timing does not change.
- The precondition uses `NotRunning()` (every enabled item with a pool), the pin's own predicate, not `NotRunningNow()`: otherwise an item hidden by an `Enabled` row 0 would pass the control and fail the pin.
- Proof load = the shortest Task 0 load that went red (fresh `--part 3/4` first, else the CI-order cycle); the 20 runs repeat exactly it.

**Extend, don't copy (Rule 2):** `WaitAllRun(every)` extends the fixture's own wait (the sibling `Install.Step.Production.StartLocked` poll is product code and stays untouched); `StateOf` is reused for the messages.

**Integration ACs:** `WaitAllRun(1)` is consumed by `TestAfterAllTestsNothingSaved` (the precondition AC). **Consumed-by:** `OcuTalon.Test.Schedule.Heartbeat` (this story). **Consumes:** `Install.Step.Production.NotRunning`, `RunnerFixture.StateOf`.

**Governing ADs:** AD-22 (tests in throwaway stacks, sharded by area; the CI recipe), AD-23 (the Production step owns `NotRunning`; read-only here), AD-29 (lanes: both files are Lane A's test code; the home lane is A).

**Ledger inbox:** DW-639 is addressed by all four ACs (cause measured, test-only fix, 20 of 20 under load, fresh check).

**Footprint:** the two files above and this spec. Not touched by any in-flight epic's diff (checked against `origin/OCT-epic11`, `-epic19`, `-epic4`, `-epic17`, `-epic34` at planning).

## Verification

`<lane>` is `OCUTALON_LOCK_DIR=<lock-dir>/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`; scratch files go under `<scratchpad>/e39s10impl/`.

**Run rules:** one runner command per foreground call with `timeout: 600000`, never two at once; at most one fresh (`e39s10impl`) and one warm (`e39s10implw`) throwaway; tear down only those tags, also after a failure; no test runs on `ocutalon-slot-d` (identity check with `iris_server_info` before any compile there). Load is made only with `docker update --cpus <n>` on this stage's own iris container (`ci/warm.sh status` names its project).

**Shared surfaces:** `RunnerFixture.WaitAllRun` (a new optional argument; every existing caller passes none and keeps its behaviour); `Test.Schedule.Heartbeat`'s messages (no other test reads them).

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**ci_groups:** `image` (`shard:lane-b`, which runs `Test.Schedule.Heartbeat`); the fixture's compile reaches every shard group (`shards`, `shards-2`, `shards-4`, `image`), with no behaviour change for them. No bound or group changes.

**Commands:**
- (once) Task 0, fresh load: `<lane> OCUTALON_RUN_TAG=e39s10impl ci/iris.sh shard lane-b --part 3/4` (classes 55-81 of today's 107, `Data.Setting` to `Schedule.ReminderZone`; check the PART line), one per call, up to 6 calls. Expected: a red at the pin names the item; record each run as `measured:`.
- (once) Task 0, CI-order load if the fresh one stays green: `<lane> OCUTALON_RUN_TAG=e39s10implw ci/warm.sh up`, `docker update --cpus 1.5 <its iris container>`, then `OCUTALON_WARM=1 ... ci/iris.sh shard 'lane-b@Contract,Core'` (about 265 s), `shard 'lane-b@Data,Demo,Live,Msg'` (about 154 s), `class OcuTalon.Test.Schedule.Heartbeat` (about 100 s), one per call; `ci/warm.sh down` between cycles; up to 3 cycles. An in-container sampler (a scratch routine that records each change of `NotRunning()` with `StateOf`, every 10 ms, into a scratch global of the throwaway; never a tracked file) may run during the cycle.
- (loop) after the fix: the same load as the red, 20 runs, each run its own call(s). Expected: 20 of 20 green; control and pin pass in each.
- (once) mutation on a fresh stack: first line of `OnAfterAllTests` `Do ##class(Ens.Director).TempStopConfigItem("SimPhoneOut", 1)`; `<lane> OCUTALON_RUN_TAG=e39s10impl ci/iris.sh class OcuTalon.Test.Schedule.Heartbeat`. Expected: `TestAfterAllTestsNothingSaved` red at the pin naming SimPhoneOut; revert; `git status --short` and `git diff --stat` byte-identical to before.
- (once) `<lane> OCUTALON_RUN_TAG=e39s10impl ci/iris.sh shard 'lane-b@Schedule'`, then the same with `--reverse`, one per call. Expected: every class passed.
- (once) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh`, one per call. Expected: exit 0.
- (once) `<lane> OCUTALON_RUN_TAG=e39s10implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s10impl ci/iris.sh teardown`, also after a failure.

**Pinning mutations:** the precondition AC: the control removed is the old code, red under the load (Task 0's measurement). The pin AC: the `TempStopConfigItem` mutation above.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
