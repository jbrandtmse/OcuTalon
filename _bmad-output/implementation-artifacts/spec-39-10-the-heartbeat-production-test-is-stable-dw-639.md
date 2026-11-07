---
title: 'Story 39.10: The heartbeat production test is stable (DW-639)'
type: 'bugfix'
created: '2026-11-07'
status: 'done'
baseline_revision: '16724981da54eb8d7e6f045d80614024076b1946'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Test.Schedule.Heartbeat` `TestAfterAllTestsNothingSaved` fails at "and the production runs every item" (`Install.Step.Production.NotRunning()` not empty) in CI's `image` job (`shard:lane-b`), about once in a few runs (DW-639: 3 heads in 6 hours on 2026-11-07, earlier ones since 2026-11-03), and each red goes green on one rerun. The planning stage could not reproduce it or confirm the cause inside its timebox (see TIMEBOX under Design Notes), and the CI logs do not say which item was missing.

**Approach (orchestrator ruling 2026-11-07 ~12:10Z, option (a): diagnostics only):** the pin's failure message names the missing items and the state of their jobs, so the next CI occurrence identifies the cause. Nothing else changes: no wait, no precondition, no fixture change; the bounded wait is NOT landed (no reproduction, so it would break the proof rule). DW-639 stays a flake class.

## Boundaries & Constraints

**Always:**
- Test-only: `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` (and, only if `StateOf` cannot be called as it is, nothing else: `RunnerFixture.StateOf` is reused unchanged).
- The pin keeps its predicate, its moment and its text: right after `other.OnAfterAllTests()`, `Install.Step.Production.NotRunning()` is read ONCE into a variable, with no wait, and asserted equal to `""`. The message stays "and the production runs every item" on a pass; on a failure it adds ": <items> (<`RunnerFixture.StateOf` of them>)".
- No shown text changes (39.10 changes no product string).

**Never:**
- Delete, skip or weaken any assertion of the class; add a wait or a precondition; move the pin; use `NotRunningNow()` for the pin; raise any existing bound.
- Change `RunnerFixture.cls`, `Install/Step/Production.cls` or any other product class; change `ci/units.sh` (Epic 19's), `release/*`, `eval/run.sh` or the IPM scripts.
- Run tests on `ocutalon-slot-d` or any other slot or instance; load the shared Docker VM.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Settled production | every enabled item has its job | pin passes with the message "and the production runs every item" (unchanged) | none |
| Call disturbs the production (mutation) | `OnAfterAllTests` first stops an item | pin fails at once; its message names the item and its job state (`StateOf`) | red, as before, now with the item named |
| The CI flake recurs | an item missing at the instant of the read | the same red as before, now naming the item and its state | the next occurrence's message decides the fix (a later story) |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` -- the class under repair. `TestAfterAllTestsNothingSaved` (L596-612) is the first test method by name (`%UnitTest.Manager` collects `Test*` methods in name order, `irislib/%UnitTest/Manager.cls` L1341-1364), so it runs right after `OnBeforeAllTests` (L104-118), whose `UseItemClass(ITEM, DOUBLE)` restarts Checks. Its last line (L611) is the pin. `Restore` (L154-186) checks the same `NotRunning()` at the class's end and has never failed in CI.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- `WaitAllRun` (L127-135, polls `NotRunningNow` once a second up to `WAITSECONDS`), `NotRunningNow` (L141-154: `NotRunning` minus items whose System Default Settings `Enabled` row is 0, DW-591), `StateOf` (L164-182: row, runtime flag and jobs of each item), `UseItemClass` / `ChangeSettings` (L619-651, L712-721: save, `UpdateProduction(60)`, `WaitAllRun`). Every existing call of `WaitAllRun` passes no argument.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` -- READ-ONLY. `NotRunning` (L141-164): an item is missing when it is enabled, has a pool and no `Alive` job whose status is not in `DEADSTATUSES` (`error,halted,terminated`); `Starting` entries do not count.
- `irislib/Ens/Job.cls` -- READ-ONLY reference. `EnumerateFetch` (L854-875): `State` is `Dead` for `Z`-prefixed entries, `Starting` for `X`-prefixed ones, else `Alive`.
- `ci/iris.sh` -- the runner (`class`, `shard <name>[@<Area>,...] [--part k/n]`, `teardown`); `ci/warm.sh` (`up`, `down`, `status`). Unchanged.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` -- in `TestAfterAllTestsNothingSaved`, read the pin's `NotRunning()` once into a variable and assert on it, with the message "and the production runs every item" followed, only when it is not empty, by ": <items> (<`$ClassMethod(..#FIXTURE, "StateOf", <items>)`>)" (check `StateOf`'s signature in `RunnerFixture.cls` L164-182 and call it as it is). Update the method's doc comment (the failure message names the missing items and their state, DW-639) and the class header's `(QA) TestAfterAllTestsNothingSaved` line if it describes the message. No other change.

**Acceptance Criteria:**
- AC 1 (DW-639, diagnostics) -- Given `TestAfterAllTestsNothingSaved`, when its pin fails, then the failure line names every missing item and its job state; when it passes, its message is unchanged.
- AC 2 -- Given the mutation "the first line of `OnAfterAllTests` stops an item" (Verification), when the class runs on a fresh stack, then the pin is red at once and its message names that item and its state (demonstrated, reverted, tree byte-identical).
- AC 3 -- Given `Test.Schedule.Heartbeat` on a fresh stack, when `shard lane-b@Schedule` runs forward and with `--reverse`, then every class passes (the standing criterion).

## Spec Change Log

- 2026-11-07 ~12:10Z (orchestrator ruling, decide, option (a), matching the Planner's 11.27 ruling on an unreproduced flake): the story is narrowed to step 1, diagnostics only. The planned `WaitAllRun(every)` extension, the precondition control, the Task 0 load runs and the 20-of-20 proof are dropped from this story (no reproduction, so the fix would break the proof rule). DW-639 stays a flake class and is closed at the burn-down with the residual "diagnostics landed; fix on next named occurrence", not as resolved.

## Review Triage Log

### 2026-11-07 - Review pass
- verdicts: 16 findings - high 0, medium 0, low 5, false 11, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: no fix, no wait, the test is as flaky as before - the intent (ruling, option (a)) is diagnostics only; the story title is the DW's, the Spec Change Log records the narrowing.
  - `[low]` `[reject]` Blind: the message duplicates `RunnerFixture.NotRunningText()` - that helper reads `NotRunningNow()`, which the intent forbids for the pin; the inline text is one expression and calls `StateOf` unchanged as the spec says.
  - `[false]` `[reject]` Blind: the pin should use `NotRunningNow()` - the intent says never use it for the pin (it would hide an item with an Enabled row 0).
  - `[low]` `[reject]` Blind, Edge, VG, Intent: `NotRunning()` can return "OcuTalon.Production is not running", which `StateOf` prints as an item with `row -, runtime flag 0, jobs none` - the sentence still names the cause, `StateOf` does not throw on it (read), the case is unlikely in this test and a guard would add a branch; cosmetic.
  - `[false]` `[reject]` Blind: the mutation covers one branch only - AC 2 asks for one demonstrated mutation (Rule 19), recorded with the observed message; the other `StateOf` branches are the fixture's, reused unchanged.
  - `[false]` `[reject]` Blind: 254.51 s run cost - the mutation ran inside one call's cap (Rule 18); not a defect of the change.
  - `[false]` `[reject]` Blind, Edge, VG: the spec's Auto Run Result still says ready-for-dev - written at finalize.
  - `[low]` `[reject]` Blind: the item name appears twice in the message - that is `StateOf`'s format, which the intent says to reuse unchanged.
  - `[low]` `[reject]` Edge, VG, Intent: `StateOf` reads a later enumeration than `NotRunning()` - inherent to the specified message (no wait, one read); the message names the item, which is the story's goal.
  - `[false]` `[reject]` Edge: `StateOf` may throw on the failure path - read: it only builds a result set and reads the settings; the only call that could fail is the fixture's own `SnapshotDefault`, which `NotRunningNow` also uses on every wait.
  - `[false]` `[reject]` Edge: the read is after three more assertions, not immediately after the call - the position of the pin is unchanged from before (the intent keeps its moment); the assertions in between do not touch the production.
  - `[low]` `[reject]` VG: no executing test pins the message text - the intent allows no extra structure; Rule 19's evidence is the recorded mutation, applied, red with the item named, reverted, tree byte-identical.
  - `[false]` `[reject]` VG: Rule 19 results (no unfalsifiable assertion, `mutation:` line present, hermeticity excluded by the ruling) - no defect.
  - `[false]` `[reject]` Intent: the observed message is local, not the CI log - the CI runner prints the same `FAIL <test>: <message>` line (the DW's own logs show it); not a defect of the change.
  - `[false]` `[reject]` Intent: the diff edits the spec - the spec is the story's own tracking artifact.
  - `[false]` `[reject]` remaining descriptive readings (R1 to R4) - the diff implements R1 and R3; no divergence needs action.

## Design Notes

**TIMEBOX (planning stage, 10:57Z to 12:04Z; cause not confirmed).** Measured on lane D throwaways (`e39s10plan`, `e39s10planw`), old code, the pin's value captured by a temporary probe (reverted, tree byte-identical):
- Reproduction: 0 red in 7 runs of the class: alone on a warm stack x3 (unthrottled, and twice at `--cpus 0.6`); warm `lane-b@Data,Demo,Live,Msg,Schedule` at 2 CPUs; fresh `shard lane-b --part 2/2` (53 classes, 593 s of classes alone, so over one call's 10 minutes: never run it in one call again); warm `lane-b@Live,Msg,Schedule` at 1 CPU; the CI order on one warm stack at 1.5 CPUs (`@Contract,Core` 265 s, `@Data,Demo,Live,Msg` 154 s, then the class). The probe read the pin 2 to 19 ms after `OnBeforeAllTests` ended, `""` each time.
- Ruled out: (1) the Checks swap itself: 56 swaps (`UseItemClass` / `RestoreItemClass`), 40 of them at 0.6 CPU, `NotRunning()` polled for 3 s after each return: 0 misses; the only gap is the new job's `Starting` entry, 11 to 15 ms, inside `WaitAllRun`. (2) A swap while the Checks job is busy (the double hanging 8 s on a Tick): `UpdateProduction` waits for it (8.97 s), the new job is up at return, 0 misses in 3. (3) The `Ens.Job:Enumerate` fetch race on a steady production (DW-772's shape): 215,626 `NotRunning()` calls and as many enumerations over 150 s spanning the minute task's runs: 0 misses, 0 fetch errors. (4) DW-591's shape (an `Enabled` row 0 with runtime flag 1, which `NotRunningNow` hides from `WaitAllRun`): after `Core.PersonaAnswers` (starts and stops TelegramIn/Out) both have row 0, flag 0, no job; the in-container sampler showed row `-` for every other item. (5) Spontaneous job deaths: the warm stack's event log held no "Terminating Job" row and `^Ens.JobStatus` no `Z` ghost entry after the runs.
- Sampler (an in-container IRIS job reading `NotRunning()` every 10 ms over three piece runs): every non-empty reading was a test's own restart (Checks swaps; production stop and start in `TestStoppedThenStarted` and `Schedule.Reminders`, about 1.4 s; agent runner and ReminderOps restarts in `Schedule.ReminderChat`, about 20 ms; FailurePoller paused 10.1 s by `Demo.Production`'s `PauseReading`).
- CI evidence (runs 42353010024, 42341818725, 42339077292, 42334354717, attempt 1): only this test failed; `Restore`'s check of the same predicate at the class's end passed every time; the class began 7.5 to 7.7 min after the stack's READY; start seconds 18 to 55 in the minute (no minute-boundary pattern). The CI logs do not name the missing item (the message has no value), hence Task 0's diagnostics.
- Structural finding (read, not inferred): this pin is the only check in `lane-b` that samples `NotRunning()` without waiting; every other readiness check (`WaitAllRun`, `Install.Step.Production.Start`) waits up to 60 s. So a transient outage of any item at that instant fails it while every other class absorbs it, and the test acts without first establishing its own precondition (Rule 19: wait for the system to signal ready before acting).
- Leading hypothesis (inference): an item that is still coming up, or restarting, in the first milliseconds after `OnBeforeAllTests` on a loaded CI host, caused by the setup's `UpdateProduction` or an earlier class. Not a product cause on present evidence.

**[Superseded by the ruling of ~12:10Z; kept for the next occurrence's story] Decision table for a red that names the item (the cause decides the fix; record it as `cause:` under Verification):**
- The missing item is Checks, or another item a test or the setup restarted, shown `Starting` or `jobs none` and clearing within seconds: test-side; the planned precondition fixes it.
- An item whose job died (`Dead`, `last was: ...`, `terminated`, `error`) with no test stopping it: `PRODUCT CAUSE:` with the event-log rows; no fix in this story; stop for a ruling.
- An item that never comes back within 60 s: a leftover of an earlier class (out of footprint): record it as a `deferred:` item naming the class; the precondition's control then fails with the item named (a real red), and the stage stops with a clarification for the runner.

**[Superseded; the precondition is not landed] Why a precondition would not weaken the pin.** The test pins "OnAfterAllTests of a class that saved nothing leaves the production as it is". "As it is" presumes a production that ran every item before the call; the test never established that. The pin's predicate, its moment (immediately after the call) and its text stay; the control is a new assertion, bounded and reported, that fails on a production that does not come up. A call that stops or restarts an item still turns the pin red (the mutation AC). The bound is the fixture's existing `WAITSECONDS`; no existing bound is raised.

**Decided in-stage:** (superseded by the ruling: no precondition, no fixture change, no load proof in this story.)

**Extend, don't copy (Rule 2):** `RunnerFixture.StateOf` is reused for the message; nothing is copied.

**Integration ACs:** no service is introduced (a message change in one test). **Consumes:** `Install.Step.Production.NotRunning`, `RunnerFixture.StateOf`.

**Governing ADs:** AD-22 (tests in throwaway stacks, sharded by area; the CI recipe), AD-23 (the Production step owns `NotRunning`; read-only here), AD-29 (lanes: both files are Lane A's test code; the home lane is A).

**Ledger inbox:** DW-639 is addressed by AC 1-3 (diagnostics); the fix itself is declined in this story by the ruling (no reproduction) and waits for the next named occurrence. Declined DW-639 (the fix only): not reproduced; ruled diagnostics-only.

**Footprint:** `Test/Schedule/Heartbeat.cls` and this spec. Not touched by any in-flight epic's diff (checked against `origin/OCT-epic11`, `-epic19`, `-epic4`, `-epic17`, `-epic34` at planning).

## Verification

`<lane>` is `OCUTALON_LOCK_DIR=<lock-dir>/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`; scratch files go under `<scratchpad>/e39s10impl/`.

**Run rules:** one runner command per foreground call with `timeout: 600000`, never two at once; at most one fresh (`e39s10impl`) throwaway; tear down only that tag, also after a failure; no test runs on `ocutalon-slot-d`.

**Shared surfaces:** `Test.Schedule.Heartbeat`'s pin message (no other test reads it).

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**ci_groups:** `image` (`shard:lane-b`, which runs `Test.Schedule.Heartbeat`). No bound or group changes.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e39s10impl ci/iris.sh class OcuTalon.Test.Schedule.Heartbeat`. Expected: passed.
- (once) mutation on a fresh stack: first line of `OnAfterAllTests` `Do ##class(Ens.Director).TempStopConfigItem("SimPhoneOut", 1)`; run the class as above. Expected: `TestAfterAllTestsNothingSaved` red at the pin, its message naming SimPhoneOut and its state; revert; `git status --short` and `git diff --stat` byte-identical to before. Record it as a `mutation:` line with the observed message.
- (once) `<lane> OCUTALON_RUN_TAG=e39s10impl ci/iris.sh shard 'lane-b@Schedule'`, then the same with `--reverse`, one per call. Expected: every class passed.
- (once) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, one per call. Expected: exit 0.
- (once) `<lane> OCUTALON_RUN_TAG=e39s10impl ci/iris.sh teardown`, also after a failure.

**Pinning mutations:** AC 1/2: the `TempStopConfigItem` mutation above.

mutation: first line of `OnAfterAllTests` = `Do ##class(Ens.Director).TempStopConfigItem("SimPhoneOut", 1)`; `ci/iris.sh class OcuTalon.Test.Schedule.Heartbeat` on a fresh stack (e39s10impl): `CLASS OcuTalon.Test.Schedule.Heartbeat failed 254.51s`, `FAIL TestAfterAllTestsNothingSaved: and the production runs every item: SimPhoneOut (SimPhoneOut row -, runtime flag 1, jobs none)`; reverted, `git status --short` and `git diff` byte-identical to before the mutation.

## Auto Run Result

Status: done
Blocking condition: none

Summary: `TestAfterAllTestsNothingSaved` reads `Install.Step.Production.NotRunning()` once into `missing` right after `other.OnAfterAllTests()` (no wait, same predicate and moment) and asserts it equals `""`. The message stays "and the production runs every item" on a pass; on a failure it adds ": <items> (<`RunnerFixture.StateOf` of them>)". DW-639 stays a flake class (diagnostics landed; fix on the next named occurrence).

Files changed:
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` - the pin, the method's doc comment and the class header's `(QA)` line.
- this spec - frontmatter, the `mutation:` line, triage log and result.

Review: 4 layers, 16 triage rows (similar findings from several layers grouped per row). Patches applied 0, deferred 0, rejected 16 (reasons in the triage log). Follow-up review recommended: false.

Verification (lane D, fresh throwaway `e39s10impl`, torn down): `ci/iris.sh class OcuTalon.Test.Schedule.Heartbeat` passed (91.74 s); the mutation turned the pin red with the item named (`mutation:` line above), reverted with the tree byte-identical; `shard lane-b@Schedule` forward passed (7 classes, 431 s; Heartbeat 82.03 s) and `--reverse` passed (7 classes, 382 s; Heartbeat 102.16 s); `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh` exit 0.

Residual risks: the next CI occurrence's message decides the fix; the state in the message is a second enumeration taken just after the pin's read.
