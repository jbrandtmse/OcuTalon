---
title: "Story 39.11: The install's production check doesn't name an item that is turned off by default"
type: 'bugfix'
created: '2026-11-08'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `Install.Step.Production.NotRunning()` decides whether an item should run from the production's runtime flag (`$$$ConfigIsEnabled`) alone. Ens itself takes an item's effective Enabled from its System Default Settings row, and `Runners()` in the same class already does. So an item turned off by its row (TelegramIn without a bot: row 0) that Ens still holds at runtime flag 1 with no job is named as "not running". It fails the install's start wait, ReconcileIn's wait and the tests that read the check (DW-978; every DW-639 red that Story 32.7 classified shows TelegramIn with row 0, runtime flag 1 and no job).

**Approach:** First, Task 0 (run by the lead): measure how Ens comes to hold flag 1 against row 0. Then `NotRunning()` also leaves out an item whose applicable Enabled row is 0, as Ens and `Runners()` read that row; otherwise the runtime flag decides, as today (lead ruling at the spec gate: exactly the Planner's scope). The row rule lives in one private helper that `NotRunning()` and `Runners()` share. Each case gets a pinning test with a demonstrated mutation.

## Boundaries & Constraints

**Always:**
- `NotRunning()` keeps its signature, its comma-list result, its "OcuTalon.Production is not running" sentence and its alive-job rule (`Alive`, status not in `DEADSTATUSES`). The only change is the enabled test. Its doc comment states the new contract exactly (Rule 14).
- `Runners()` behaves exactly as before. It only calls the shared helper.
- The new tests create the row and runtime-flag state they assert on, and put both back as they found them (also when an assertion fails). They never start, stop or update a production. They run with a running production in throwaways and CI only, against the CI mock. Never a real model key, never a real bot.
- Every test added or changed passes on a fresh environment, in either order.

**Never:**
- No user-facing string changes (a needed one is a `PUBLIC TEXT:` clarification). Don't delete, weaken or move any existing pin; invert the TelegramParked pin, don't drop it. Add no waits and raise no timeouts.
- Don't touch `Test/Agent/RunnerFixture.cls`, `Test/Schedule/Heartbeat.cls` (its lines ~180 and ~612 stay as they are), `ci/units.sh`, `Core/**`, `Agent/Input.cls`, `Agent/Triage.cls`, `Install/Step/Core.cls`, `Web/Api.cls`, chat/digest/SimPhone code or `Data/Purge.cls`.
- The implement stage's tasks don't depend on Task 0's outcome. A Task 0 cause outside `Install/Step/Production.cls` is reported (PLANNER REPORT), not fixed.

## I/O & Edge-Case Matrix

The item is TelegramIn (pool 1) with no alive job, on a running OcuTalon.Production. "Row" is its System Default Settings row of Enabled. "Flag" is `$$$ConfigIsEnabled`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Turned off by its row (DW-978) | row 0, flag 1 | not named | none |
| Off by row and flag | row 0, flag 0 | not named (as today) | none |
| Meant to run by its row | row 1, flag 1 | named | none |
| Row on, flag stale off | row 1, flag 0 | not named (as today: the flag still decides unless the row is 0; lead ruling) | none |
| No row | no row, flag 1 | named (as today) | none |
| No row, flag off | no row, flag 0 | not named (as today) | none |
| Item has a live job | any row, flag 1, alive job | not named (as today) | none |
| Production not running | — | "OcuTalon.Production is not running" (unchanged) | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` -- `NotRunning()` L152-177: the class to fix. The enabled test is L172 (`If '$Get($$$ConfigIsEnabled(item)) Continue`), the pool test L173. `Runners()` L179-199 holds the row rule inline at L192 (`$Select(##class(Ens.Config.DefaultSettings).%GetSetting(production, item.Name, item.ClassName, "", "Enabled", .override): override, 1: item.Enabled)`). That is the sibling the helper extends (Rule 2). The class header (L27-28) says "An item runs when it is enabled ...": it stays as written, since "enabled" now means the same in both methods. `Include Ensemble` is already at L1.
- `irislib/Ensemble.inc` L140-151 -- `$$$ConfigRoot`, `$$$ConfigClassName(item)` (L141), `$$$ConfigIsEnabled` (L144), `$$$ConfigChecksum` (L145), `$$$ConfigPoolSize` (L151), all under `^Ens.Runtime("ConfigItem", item, ...)`. Read-only.
- `irislib/Ens/Director.cls` -- read-only evidence. `getProductionItems` L1084: effective Enabled = SDS row if any, else the definition flag. L1131: `IsEnabled` = that value. Registration L1326-1348 writes `$$$ConfigIsEnabled` and `$$$ConfigChecksum`, but only for items in `pToStartConfig`. `findProductionDifferences` L984-1016: an item is re-registered when it is new, when its checksum changed, or when its job count differs from its effective pool. `actualizeProductionDifferences` L1286: a failed job stop (`Ens.Job.StopJobs` inside the update timeout) quits before registration. `EnableConfigItem` L1572-1636 with an SDS override: SQL-updates the row, then calls `UpdateProduction(GetRunningProductionUpdateTimeout())`.
- `irislib/Ens/Config/Item.cls` L245-257 -- `Checksum()` includes the SDS-overridden Enabled. So a row flip changes the checksum, and the next update that runs to its end re-registers the flag.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- where the new pins go (Lane A, in shard `lane-a@...Install...`). No `Include` today, so add `Include Ensemble` for `$$$ConfigIsEnabled`. Its header (L1-37) promises "Nothing here starts, stops or updates a production" and lists every test: add the new test and the TelegramIn row and flag it writes. `OnAfterOneTest` (L72-82) is where restores go (the `AutoStartSaved` pattern). `TestStepHelpers` L488-525 shows the running-production skip idiom.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- reuse it, don't edit it: `SnapshotDefault` L787, `PutDefault` L799, `RestoreDefault` L821 (the row by `DefaultId` L780), `Jobs(item)` L185 (alive job ids). `NotRunningNow` L136-154 filters exact `||*||Enabled` rows of 0 out of `NotRunning()`. After the fix that filter is redundant but harmless, since `NotRunning()` already drops every row-0 item.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramParked.cls` -- `TestReadinessFollowsTheRow` L112-128. L118 pins today's divergence ("the production's own check names TelegramIn while its runtime flag says enabled and it has no job") and must be inverted. L119-120 (NotRunningNow empty, WaitAllRun ends at once) and L124-126 (row 1, so TelegramIn is reported) keep holding. Header L8-10 describes the test and must be updated. `OnBeforeOneTest`/`OnAfterOneTest` L56-78 save and put back the rows and the flag.
- Consumers of `NotRunning()`: `Install.Step.Production.StartLocked` L136-144 (the start wait and its error text); `Install.ReconcileIn.OnProcessInput` L55 (its "waiting for these items" warning); `Test.Agent.RunnerFixture.NotRunningNow` (behind `WaitAllRun`, `Restart`, `ReadyReason`, `NotRunningText`); tests: `Test/Schedule/Heartbeat.cls` L180 and L612, `Test/Agent/Runners.cls` L162-278 and `AssertRefused` L606-612, `Test/Agent/Models.cls` L136 and L150, `Test/Agent/Conversation.cls` L160, `Test/Install/ReconcileIn.cls` L62-65, `Test/Bridge/WebStatus.cls` L345, `Test/Core/AnswersInWebRoles.cls` L110, `Test/Digest/Store.cls` L585, `Test/Install/Production.cls` L521.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` -- add one private class method, for example `ItemEnabled(production, item, class, flag) As %Boolean`. It returns the Enabled row that applies to the item (`Ens.Config.DefaultSettings.%GetSetting(production, item, class, "", "Enabled", .value)`, any specificity) when one exists, else `flag`, as 1 or 0. Its doc comment says so. In `NotRunning()`, keep L172 (`If '$Get($$$ConfigIsEnabled(item)) Continue`) and the pool test, and add right after L172 `If '..ItemEnabled(..#PRODUCTION, item, $Get($$$ConfigClassName(item)), 1) Continue` (an item is skipped when its runtime flag is off, as today, or when the Enabled row that applies to it is 0). In `Runners()`, L192 becomes `Set enabled = ..ItemEnabled(production, item.Name, item.ClassName, item.Enabled)`, and its `$Select(enabled: 1, 1: 0)` is unchanged. Rewrite `NotRunning()`'s doc comment to its contract: the items that are enabled by the production's runtime flag and not turned off by an Enabled row of 0 that applies to them (as Ens and Runners read that row), have a pool and no alive job that is not in error; the not-running sentence; empty when every item runs. -- DW-978, Rule 2 (one rule, two callers).
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- add `TestNotRunningFollowsTheRow`, plus properties and an `OnAfterOneTest` branch that put TelegramIn's Enabled row (`RunnerFixture.SnapshotDefault`/`RestoreDefault`) and its runtime flag (`$Data` and value, killed when it was undefined) back as found. Steps: (1) skip (`$$$AssertSkipped`, naming why) when OcuTalon.Production does not run here, or when TelegramIn has an alive job (`RunnerFixture.Jobs`), because it can't be stopped here; (2) assert that TelegramIn has a pool; (3) for each matrix row from "Turned off by its row" to "No row, flag off", set the row (`RunnerFixture.PutDefault`, or `%DeleteId(RunnerFixture.DefaultId(...))` for no row) and the flag, then assert whether `$ListFind($ListFromString(NotRunning()), "TelegramIn")` names it. Each message names the row, the flag and the expectation. Update the class header (what is written and put back, and the test's bullet). -- DW-978 AC 1 and AC 2.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramParked.cls` -- invert L118 to `$$$AssertNotTrue(...)` with the message "the production's own check leaves out TelegramIn while its Enabled row is 0, even with its runtime flag set". After the row is set to 1 (after L124), add one assertion: `NotRunning()` names TelegramIn. Update header L8-10 so it says that `NotRunning()` itself now follows the row. Change nothing else. -- Rule 19 (a shared surface), Integration AC.
- `src/ocutalon/cls/OcuTalon/Test/**` (read; edit only the three files above) -- search for every other assertion that `NotRunning()` names, or omits, an item whose Enabled row is 0, or whose row is 1 with flag 0 (start from the Code Map's consumer list). Update any that pin the old shape, and record what you found under Verification (`Shared surfaces:`). Expected: none besides TelegramParked L118. `Runners.AssertRefused` names refused runners, which have no row of 0.

**Acceptance Criteria:**
- AC 1 (DW-978) -- Given TelegramIn on a running OcuTalon.Production with its Enabled row 0, runtime flag 1 and no job, when `Install.Step.Production.NotRunning()` is read, then it does not name TelegramIn (`Test.Install.Production` `TestNotRunningFollowsTheRow`; TelegramParked's inverted L118 on a parked stack).
- AC 2 (DW-978) -- Given TelegramIn with no job and runtime flag 1, when its row is 1, or it has no row, then `NotRunning()` names it. With flag 0 it is not named, whatever the row (unchanged).
- AC 3 -- Given the fixture production of `TestRunnerModels`/`TestSeedModels`, when `Runners()` and `UnresolvedRunners()` run, then their results are as before (the existing tests pass unchanged).
- AC 4 (Integration; consumer `RunnerFixture.NotRunningNow`/`WaitAllRun`) -- Given a parked stack with TelegramIn's flag set to 1, when the restarts' wait reads the check, then `NotRunningNow()` is empty and `WaitAllRun()` returns 1 at once (TelegramParked L119-120, unchanged).
- AC 5 -- Given the story's diff, when it is read, then it changes no user-facing string: no catalog, web or message text, and the sentences of `NotRunning()`, `StartLocked` and `ReconcileIn` are byte-identical.

## Spec Change Log

- 2026-11-08 (lead, spec gate): row 1 / flag 0 is not named (lead ruling under Design Notes); Approach, matrix row 4, the `NotRunning()` task, AC 2 and the AC 1 mutation updated to match. Task 0 to be filled by the lead before the implement spawn.

## Review Triage Log

## Design Notes

### Task 0

Run by the lead after the spec gate, before the implement spawn. Timebox 45 minutes. Old code, nothing changed in the tree. Use a lane-C warm throwaway (`<lane> OCUTALON_RUN_TAG=e39s11t0w ci/warm.sh up`, which parks Telegram and runs the CI mock). The slot `ocutalon-slot-c` has no CI mock, so `LiveCase.Enable` cannot run there. Run each probe as an IRIS session on that stack's `iris` service in namespace `OCUTALON` (the project comes from `ci/warm.sh status`; `docker compose -p <project> exec -T iris iris session IRIS -U OCUTALON < <scratchpad>/e39s11t0/<n>.txt`). Finish with `ci/warm.sh down` with the same tag, also after a failure.

Facts read beforehand (read, not measured): `Item.Checksum()` includes the SDS Enabled, so a row flip 1 to 0 changes the item's checksum. An update that runs to its end then re-registers `IsEnabled` from the row. "An update whose checksum and job count are unchanged" registers nothing, so it can only keep a flag that already disagrees with a matching checksum.

Hypotheses:
- **H1, a disable whose stop times out.** `LiveCase.Disable` → `EnableConfigItem(item, 0, 1)` writes row 0 and calls `UpdateProduction(timeout)`. The job doesn't stop inside the timeout, so the update quits before registration (`actualizeProductionDifferences` L1286), and `IsEnabled` stays 1 with the old checksum. The job then ends on its own, and `AwaitStop` sees no job and asks for no further update. Result: row 0, flag 1, no job, until the next update that runs to its end.
- **H2, a row written during another update.** The row flips between `getProductionItems` and the registration, so the flag and checksum are registered from the old row. Persists until the next update.
- **H3, a runtime flag written by hand with a matching checksum.** `TelegramParked` sets `$$$ConfigIsEnabled` to 1 and puts back a value it saved. A saved stale 1 survives every update, because the checksum and job count are unchanged; only a restart clears it.

Probe (each step prints one line; use `^Ens.Runtime("ConfigItem","TelegramIn",...)` directly, since a session has no macros): `CHK|<label>|row=<SnapshotDefault value or ->|flag=<IsEnabled>|sum=<registered Checksum>|def=<Checksum() of the definition item TelegramIn>|jobs=<RunnerFixture.Jobs>|named=<$ListFind of TelegramIn in NotRunning()>`. Steps:
1. `base` on the parked stack. Expected: row 0, flag 0, sum = def, no job, named 0.
2. `LiveCase.Enable("TelegramIn", .rows)`, then probe `enabled`.
3. H1: `EnableConfigItem("TelegramIn", 0, 0)`, then `UpdateProduction(0.1)`; print the update's status text, then probe `h1-update`. If the update succeeds, re-enable and retry at most 3 times; if it never fails, record "H1 timeout not reproduced".
4. Poll once a second for up to 60 s until no job, then probe `h1-gone`.
5. `UpdateProduction(10)`, then probe `h1-next`: does a later update repair the flag?
6. H3, from the parked state: set the flag to 1 by hand, `UpdateProduction(10)`, probe `h3`, then set the flag back to 0.
7. `BotApi.Park()`, probe `end`, `ci/warm.sh down`. H2 only if time remains; otherwise record "H2 not measured".

Record every CHK line (row, flag, checksum and def, jobs before and after) and the update status texts under `Result:`. A cause in Ens or in test code (`LiveCase`, `TelegramParked`, `BotApi`) is reported as a PLANNER REPORT and is not fixed here. A cause inside `Install/Step/Production.cls` may add one task, which the lead writes in.

Result: (the lead fills this in after Task 0)

**Decided in-stage:**
- Semantics (superseded at the spec gate, see the lead ruling below): the plan had the row decide in both directions (row 1 with flag 0 named).

**Lead ruling at the spec gate (2026-11-08, category=decide, policy=5086036):** `NotRunning()` only gains the row-0 skip; with a row of 1 or no row the runtime flag decides as today, so row 1 / flag 0 stays not named. Rejected: the row deciding in both directions. Why: the Planner ruled the fix exactly ("`NotRunning()` skips items whose System Default Enabled row is 0"); naming row-1/flag-0 items widens the check that gates the install's start wait and ReconcileIn, and would add a new failure in the window between a row write and its update (`SetEval`, `LiveCase.Enable` write the row first); after any start or completed update the flag matches the row, so the narrower rule is no false all-clear. The helper still carries the shared row rule (Rule 2).
- One private helper, used by both methods (Rule 2). `Runners()`'s behaviour is unchanged (AC 3), and its inline `$Select` is its only change. Like Ens and `Runners()`, the helper reads the row at any specificity. `RunnerFixture.NotRunningNow` checks only the exact `||*||` row, so it is a subset: redundant now, still correct, and left alone.
- The pins use TelegramIn, the real item of DW-978, in `Test.Install.Production` (Lane A, in a shard already, so no `ci/units.sh` change). They need no park or update, so the class keeps its "nothing starts, stops or updates" promise. The test skips only when the production doesn't run or TelegramIn has a job (a stack with a bot). CI stacks are parked, so the test runs there.
- The class header of `Install.Step.Production` stays as it is.

**Extend, don't copy (Rule 2):** the helper extends `Runners()` L192, the existing row rule. The tests reuse `RunnerFixture.SnapshotDefault`/`PutDefault`/`RestoreDefault`/`DefaultId`/`Jobs` unchanged.

**Integration ACs:** no new service; AC 4 is the consumer-level AC. **Consumed-by** (existing): `Install.Step.Production.Start`/`StartLocked` (start wait and its failure text), `Install.ReconcileIn` (its wait and warning), `Test.Agent.RunnerFixture.NotRunningNow` (`WaitAllRun`, `Restart`, `ReadyReason`, `NotRunningText`), and the tests listed in the Code Map. **Consumes:** `Ens.Config.DefaultSettings.%GetSetting`, the Ens runtime config (`$$$ConfigRoot`, `$$$ConfigClassName`, `$$$ConfigIsEnabled`, `$$$ConfigPoolSize`), `Ens.Job:Enumerate`.

**Governing ADs:** AD-23 (the Production step waits until every enabled item runs, and an item runs when it has a running job; this story fixes the meaning of "enabled"), AD-5 (enabled state that an install may change lives in System Default Settings; the production class holds structure), AD-22 (tests that need the running production run in throwaways and CI; shards), AD-29 (Lane A: `Install.Step.*`, `Test.Install`, Telegram's `Test.Channel`), AD-6 (only through `Runners()`, which stays unchanged). Also checked and not governing: AD-3 (namespaces) and AD-28 (`NotRunning()` is no all-clear). No AC contradicts an AD.

**Ledger inbox:** DW-978 is addressed by AC 1, AC 2 and Task 0.

**Footprint:** the three source files above and this spec. `footprint_extensions:` covers `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`, `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` and `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramParked.cls`, all outside epic-39's `paths_hint`.

## Verification

`<lane>` is `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`. Scratch files go under `<scratchpad>/e39s11impl/`. Fresh tag `e39s11i`, warm tag `e39s11iw`.

**Run rules:** one runner command per foreground call (`timeout: 600000`), each sized to about 150 s; never two at once. At most one fresh and one warm stack. Tear down only these tags, also after a failure. No test runs on `ocutalon-slot-c` or any other instance. Leave whole-shard runs (`lane-a`, `lane-a@Channel`) to CI.

**Shared surfaces:** `NotRunning()`'s result for an item with an Enabled row of 0 (the TelegramParked pin at L118, inverted) and the meaning of "enabled" for the check's consumers (Code Map list). The implement stage records its search here.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**ci_groups:** `shards` (`shard:lane-a@Checks,Install,Watch,Eval`) and `shards-4` (`shard:lane-a@Channel`). No group or bound changes.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e39s11iw ci/warm.sh up` once, then `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s11iw ci/iris.sh class OcuTalon.Test.Install.Production`. Expected: passed, with no SKIP for `TestNotRunningFollowsTheRow`.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s11iw ci/iris.sh class OcuTalon.Test.Channel.TelegramParked`. Expected: passed, no SKIP.
- (once) Mutations, on the warm stack, one class per call. After each revert, the class must be green again on the same stack, and `git status --short` and `git diff --stat` must be byte-identical:
  - AC 1: delete the added row-0 line (the `ItemEnabled` call) from `NotRunning()`. Expected: `TestNotRunningFollowsTheRow` is red at row 0 / flag 1, and TelegramParked is red at the inverted pin.
  - AC 2: the helper returns 0 whenever a row exists. Expected: `TestNotRunningFollowsTheRow` is red at row 1 / flag 1.
  - AC 3: the helper ignores the row (`Quit flag`). Expected: `Test.Install.Production` `TestRunnerModels` is red.
  - Record each as `mutation: <change> → <test> red: <message>`.
- (once) Order, on the warm stack: `class OcuTalon.Test.Install.Production` then `class OcuTalon.Test.Channel.TelegramParked`, then the two in the opposite order, one per call. Expected: all passed.
- (once) Fresh: `<lane> OCUTALON_RUN_TAG=e39s11i ci/iris.sh shard 'lane-a@Install'`, then the same with `--reverse`, then `ci/iris.sh class OcuTalon.Test.Channel.TelegramParked`, one per call. If a piece runs over about 150 s, split it with `--part k/2`. Expected: every class passed.
- (once) `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-boundaries.sh`, one per call. Expected: exit 0.
- (once) `<lane> OCUTALON_RUN_TAG=e39s11iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s11i ci/iris.sh teardown`, also after a failure.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
