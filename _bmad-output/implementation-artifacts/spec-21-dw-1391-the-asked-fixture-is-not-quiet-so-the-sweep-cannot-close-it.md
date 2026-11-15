---
title: 'DW-1391: The asked fixture is not quiet, so the sweep cannot close it'
type: 'bugfix'
created: '2026-11-15'
status: 'done'
baseline_revision: 'e6edc855913a13ba1f08815f01ea417c7397c55c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/7-10/cause.md'
warnings: []
deferred:
  - summary: >-
      The closeQuiet hammer that shows the race lives only in the scratchpad, so AC 1 is a one-time measurement and no run in the repo or CI repeats it.
    evidence: |-
      The spec bans the ZzScratch hammer classes from the repo (Task 0). The guard in Incident makes the stale-fixture cause deterministic; only a different route to the same race (a test that builds an incident outside the helper) would escape it.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Fix/Asked.cls, src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls
    severity: low
---

<intent-contract>

## Intent

**Problem (DW-1391; test-only):** `Test.Fix.Asked` `TestSuspendAndUndo` failed once in CI. The run was feature ci 43735777142 attempt 1 (7622f6df8, 25.6's merge, which touches no Fix file), job 132877963172 on ocutalon-ci-38, shards-11. The two failed asserts were L117 "the same ask again is already_asked" and L118 "with the ruled message". L119 ("no second request is raised and no second dry run is asked") passed.

**Cause (inference; the same mechanism as DW-840, Story 7.10, and NOT DW-1205/DW-494's race):**
- The fixture incident is quiet. `Asked.Incident` (L400) sets `LastAt` = `..T(-3600)` (L402), more than `IncidentManager.QUIETSECONDS` (900 s) before now.
- Every heartbeat Tick runs the quiet sweep first: `Checks/Process.cls` `Sweep` L470 and `Quiet` L497, whose `Settle.Quiet` test is at L503. It sends `closeQuiet` to the production's `IncidentManager`, which re-checks the quiet at L1622 and finds the stale `LastAt` quiet too.
- The production's `IncidentManager` opens the incident while it is still resolved. The test's shadow `IncidentManager` then saves `awaiting_approval` with the suspend request. The production then saves `closed` over it (`Move` L1432, save L1442, no version check): a lost update.
- The second ask finds the incident closed. `suspend_item` may not be asked on a closed incident (`Fix.Kind.AskedClosed`), so the answer is `not_found` at L1076, before `AlreadyAsked` (L1115) runs. That is why L119 stayed green.
- There is no product impact. `IncidentManager` has PoolSize 1, so in production one job applies both events in turn. Only the test's second, shadow instance makes the lost update possible.

**Approach (test-only):** the fixture incident is fresh, so the sweep never takes it.
- `Asked.Incident` sets `LastAt` = `..T(0)` (and the group's `LastAt` with it).
- A guard asserts that the stored incident is not quiet (`Settle.Quiet(...)` = 0), so a later edit that makes the fixture stale again goes red at once, deterministically.
- `Test/Fix/PartnerDraft.cls` has the same fixture (`Incident` L563, `LastAt` L565, group L589). It is the same race: a resolved, noticed incident there is quiet too, and a Tick's `closeQuiet` closes it under the test. Its exposed pins are `TestStateNeverMoves` ("the state and the open variant are as they were", L400) and every second ask, `TestAlreadyAsked` among them. It gets the same fix and guard.

## Boundaries & Constraints

**Always:**
- **Footprint (Lane A test package `OcuTalon.Test.Fix`; lane C makes the edits):**
  - `src/ocutalon/cls/OcuTalon/Test/Fix/Asked.cls`: `Incident` (the incident's and the group's `LastAt`, and the guard); a header line.
  - `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls`: `Incident`, the same; a header line.
  - This spec.
- `FirstAt` stays `..T(-7200)` and `NoticedAt` stays `..T(-6600)`, so `FirstAt` is still not later than `LastAt` and the incident is still noticed.
- The guard reads the stored row (`OcuTalon.Data.Incident` `RefIndexOpen(ref).LastAt`), not the local value, and asserts `##class(OcuTalon.Watch.Settle).Quiet(<that>, ##class(OcuTalon.Data.Time).NowUtc(), ##class(OcuTalon.Watch.IncidentManager).#QUIETSECONDS)` = 0, with the label "the fixture incident is not quiet, so no heartbeat closes it under the test".
- Every pin, wait and timeout of both classes is unchanged. 23.3's `TestUndoRollbackAsked` (`Asked.cls` L157) uses the same helper, so the fix covers it too. Its exposed pin is L178 "the incident's state did not move".

**Never:**
- Change any product class (`IncidentManager`, `Checks`, `Settle`, `Transitions`), `Test/Watch/IncidentProbe.cls` or `Test/Data/Fixture.cls`.
- Stop the heartbeat, the Checks item or the production in a test.
- Delete, skip, tag off or weaken a test.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 The race, old fixture | `LastAt` = now-3600, and a closeQuiet lands between the production `IncidentManager`'s open and the shadow's save. | Old code: L117 and L118 red (`not_found`). | none |
| 2 Fixed fixture | `LastAt` = now. | Checks' `Quiet` does not list it, and `IncidentManager` would answer `not_quiet` (L1622). No close, so the asks are as pinned. | none |
| 3 The guard | Any `Incident(...)` call. | One passing assert per fixture incident. With `LastAt` back at -3600 it is red at every call. | none |
| 4 PartnerDraft | The same fixture and state set. | As 1 to 3. | none |
| 5 A caller passes `LastAt` in `fields` | No caller does today. | The guard holds such a caller to a fixture that is not quiet. | none |

</intent-contract>

## Code Map

Line numbers are at the baseline `f56f50d86` (23.3 merged). The ledger's numbers came before 23.3 and are corrected here: `Asked.cls:337` is now L402, and the `IncidentManager` lines moved by +5 to +13.

- `Test/Fix/Asked.cls`:
  - `TestSuspendAndUndo` L99, with the failed asserts at L117 and L118 and the green L119.
  - `TestUndoRollbackAsked` L157 (23.3), with its exposed pin at L178.
  - `T` L394.
  - `Incident` L400: `LastAt` L402, group `LastAt` L424.
  - Header L1-14.
- `Test/Fix/PartnerDraft.cls`: `TestAlreadyAsked` L196, `TestStateNeverMoves` L367 (pin L400), `T` L557, `Incident` L563 (`LastAt` L565, group `LastAt` L589). Its incidents are of namespace `ZZNS`, like `Asked`'s.
- `Checks/Process.cls`: `Sweep` L470, `Quiet` L497 (`Settle.Quiet` L503).
- `Watch/Settle.cls`: `Quiet` L83.
- `Watch/IncidentManager.cls`: `QUIETSECONDS` L145, `Asked` L1072 (`not_found` L1076), `AlreadyAsked` call L1115, `Move` L1432 (save L1442), and the closeQuiet re-check L1622.
- `Fix/Kind/UndoRollback.cls`: `MOVES` 0 and `ASKEDSTATES` "open,resolved,closed". So `undo_rollback` is asked on a closed incident, and in 23.3's test only the state pin is exposed.
- The 7.10 precedent: `_bmad-output/implementation-artifacts/evidence/7-10/cause.md` (the same mechanism, measured 2 of 11 red on the old code and 20 of 20 green with a fresh `LastAt`).

## Tasks & Acceptance

**Task 0 (measure first, on lane C's warm throwaway `e21dw1391iw`, before the edit; record each result under `## Verification`):**
1. **The hammer (the 7.10 harness shape).** The 7.10 harness is untracked, so rebuild it in your scratchpad as the scratch package `ZzScratch`, which is never committed and is loaded into the throwaway only:
   - `ZzScratch.AskedHammer Extends OcuTalon.Test.Fix.Asked` and `ZzScratch.DraftHammer Extends OcuTalon.Test.Fix.PartnerDraft`.
   - Each one's `OnBeforeAllTests` JOBs two loops that run until a stop flag. Back to back, each loop sends `closeQuiet` for every unclosed `OcuTalon_Data.Incident` of namespace `ZZNS`, through `##class(OcuTalon.Core.Commands).Submit(<an OcuTalon.Msg.IncidentCommand, Verb closeQuiet>, "timer", .result)`, so that the production's own `IncidentManager` applies it, as Checks' sweep does.
   - `OnAfterAllTests` sets the flag and waits for both jobs to end.
   - If `Submit` refuses origin `timer` from a test job, use the origin that `CommandsIn` accepts for `closeQuiet`, and record which.
   - Run `ci/iris.sh class ZzScratch.AskedHammer` 40 times on the old code. Expect at least one red at L117/L118 (or at L178, `TestUndoRollbackAsked`). Record the count of reds and the asserts.
   - Run `ZzScratch.DraftHammer` 10 times on the old code and record its reds.
   - If AskedHammer shows no red in 40 runs, record it and go on. The fix rests on the 7.10 measurement and on the deterministic guard (AC 2). This is not a stop condition.
2. **After the edit:** AskedHammer 40 of 40 green and DraftHammer 10 of 10 green. Any red stops the work with `## Clarification Needed` and the failed asserts, since that would mean another cause.

**Execution:**
- [ ] `Test/Fix/Asked.cls` `Incident`:
  - `"LastAt": (..T(0))` in place of `..T(-3600)`, and `Set group.LastAt = ..T(0)`.
  - After the incident is saved, the guard (see Boundaries).
  - Doc: "... with a failure group of 3 orders at OrdersFromPartner, whose last failure is now, so that the quiet sweep of the heartbeat never closes it under the test; its Ref."
  - Header: one line after the class description: "The fixture incidents' last failure is now: a quiet one (more than IncidentManager QUIETSECONDS old) would be closed by a heartbeat Tick's closeQuiet while a test runs."
- [ ] `Test/Fix/PartnerDraft.cls` `Incident`: the same three edits and the same header line.
- [ ] This spec: the `## Verification` records (Task 0 and the mutation lines).

**Acceptance Criteria:**
1. Given the closeQuiet hammer, when `Test.Fix.Asked` and `Test.Fix.PartnerDraft` run, then every test passes (Task 0 item 2: 40 of 40 and 10 of 10).
   - mutation: `Asked.Incident` `LastAt` back to `..T(-3600)` (the guard removed too, so that only the race can turn it red) -> AskedHammer red at L117/L118 or L178 in at least one of 40 runs (Task 0 item 1's count is the baseline for this; if Task 0 item 1 saw no red, record that this mutation is not observable by the hammer and rely on AC 2).
2. Given any fixture incident of either helper, then it is not quiet when the test starts.
   - mutation: `Asked.Incident` `LastAt` back to `..T(-3600)`, with the guard kept -> `Test.Fix.Asked` red at the guard in every test ("the fixture incident is not quiet ...");
   - mutation: the same in `PartnerDraft.Incident` -> `Test.Fix.PartnerDraft` red at the guard.
3. Every existing pin of both classes passes unchanged without the hammer (warm), 23.3's `TestUndoRollbackAsked` included.

## Design Notes

**Why the fixture, not the product.** The quiet sweep (AD-18) and `resolved + closeQuiet -> closed` (AD-15's table) are the rule. Only the fixture's stale `LastAt` makes a seconds-old incident look an hour quiet. The lost update needs two `IncidentManager` jobs, and the product has one (PoolSize 1). The test's shadow instance is the second.

**Why a guard.** The race is rare (one CI red). A fresh `LastAt` removes it, but only the guard turns a regression of the fixture red on every run, which is what Rule 19 wants as a mutation that shows.

**Why the group's LastAt too.** The quiet sweep reads only the incident's `LastAt`. The group's is changed with it so that the fixture stays consistent (an incident's `LastAt` is the latest of its groups', `IncidentManager` L466-468). `PartnerWarning`'s facts read the incident's `LastAt` ("Last failure: ..."), and `PartnerDraft` compares them with the kind's own rendering of the same incident, so no literal changes.

**Not in this spec.** `Test/Watch/Summary.cls` L878 has the same fixture shape (`LastAt` `..T(-3600)`). It is outside this footprint and was not investigated (it tests `closeQuiet` on purpose at L164). The lead may file a ledger candidate.

**Ledger inbox:** DW-1391 (this spec). Its status line is recorded per the run's DW process at merge.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | None. | Approve (nothing to rule). |
| 2 | (b) Cross-lane edits | Two test classes of the Lane A package `OcuTalon.Test.Fix` (`Asked`, `PartnerDraft`). Lane C makes the edits as part of the DW-1205 family that the Planner assigned to lane C. `Asked.cls` was in 23.3's footprint; 23.3 is merged, and this edit touches only the `Incident` helper, which 23.3 did not change. | Approve. |
| 3 | (c) Stored data or schema | None. Test fixtures only. | Approve. |
| 4 | (d) Architecture | None. No AD is touched. | Approve. |

## Public text

None.

**Findability:** no UI change.

## Verification

Lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21dw1391iw`.
- One test class per foreground call, `timeout: 600000`, each under about 3 minutes. Never two `iris_execute_tests` calls in one message.
- Each hammer run is one foreground call. The 40 runs are a loop of separate calls, or one shell loop that stays under the 10-minute cap; split it if it does not.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e21dw1391iw ci/warm.sh up`, then Task 0 item 1 on the old code.
- (loop) Warm, each `ci/iris.sh class <Class>`, expected to pass:
  - `OcuTalon.Test.Fix.Asked`
  - `OcuTalon.Test.Fix.PartnerDraft`
- (once) Warm, expected to pass: `OcuTalon.Test.Fix.AskedTurns`, `OcuTalon.Test.Fix.PartnerTurns`.
- (once) Task 0 item 2 (the hammers on the new code).
- (once) `bash docker/tests/test-class-rules.sh`: exit 0.
- (once) `git diff --name-only f56f50d86` lists only the footprint files.
- (once, at the end, also after a failure) `OCUTALON_RUN_TAG=e21dw1391iw ci/warm.sh down`. The `ZzScratch` classes go with the stack.

**Mutations:** as listed under Acceptance Criteria (AC 3 is the regression list). Record each as `mutation: <change> -> <test that went red>`. Revert it byte for byte, and check that `git status --short` and `git diff --stat` are as before.

**Task 0 records (implement stage, lane C warm throwaway `e21dw1391iw`, Nov 15):**
- **Harness.** `ZzScratch.AskedHammer` and `ZzScratch.DraftHammer` (subclasses of `Test.Fix.Asked` and `Test.Fix.PartnerDraft`) were written under `<scratch>` and loaded into the warm container only (`docker cp` + `$SYSTEM.OBJ.LoadDir`); never in the repo. Each `OnBeforeAllTests` JOBs two loops that, back to back, read every unclosed `OcuTalon_Data.Incident` of namespace `ZZNS` and send `closeQuiet` (origin `timer`) until a stop flag; `OnAfterAllTests` sets the flag and waits for both jobs. One deviation from the Task 0 text: `Commands.Submit` answers `unknown_command` for an `IncidentCommand` (CommandsIn's table has no such class, `Core/CommandsIn.cls` L5), so the loops send it as Checks' sweep does, to the production's own `IncidentManager`: `Ens.Director.CreateBusinessService("CommandsIn")` then `service.SendRequestSync("IncidentManager", command, .answer, 10)` with `Origin` "timer". The hammer is effective: on the old fixture the answers were `closed`, `not_allowed` and `not_found`; on the fixed one `not_quiet` (353 and 339 in a run).
- **Runner.** `ci/iris.sh class` refuses a class outside `Test/<Area>/`, so a `<scratch>` script runs the hammer classes through `%UnitTest.Manager.RunTest(":<Class>", "/noload/nodelete/norecursive")` in the warm container, the same call as `ci/iris.sh` `class_script`, and prints the failed asserts. About 1 s per run.
- **Baseline (old code, no hammer).** `Test.Fix.Asked` and `Test.Fix.PartnerDraft` passed warm.
- **Old code, AskedHammer: 39 of 40 red** (1 green). Failed asserts: `TestSuspendAndUndo` "the same ask again is already_asked" and "with the ruled message" in 36 runs (the L117/L118 pair), "and asking to undo again raises nothing" in 3; `TestRejectedAndExpired` (an exposed test not named in the spec) "expired: the incident is open with that variant" 10, "rejected: ..." 7, "and the session is told" 5, "with the answered notice of the request" 5. `TestUndoRollbackAsked` (L178) was not red in 40 runs; it is covered by the fix and the guard all the same.
- **Old code, DraftHammer: 10 of 10 red.** Failed asserts (assert lines over the 10 runs): `TestDraftRequest` "and tells the session that the draft failed" 9 and "its input is exactly what Agent.Input renders ..." 6; `TestRefusals` "and are not allowed" 5 and "demo mode off: no contact, so NOCONTACTS" 4; `TestAllowance` "with the flag off there is no limit" 4, "with a sixth notice, 20 simulated emails: refused" 3 and "with ALLOWANCE" 3; `TestAlreadyAsked` (approved: 3 asserts) 1. `TestStateNeverMoves` was not red in these 10 runs.
- **Fixed code, AskedHammer: 40 of 40 green. DraftHammer: 10 of 10 green** (Task 0 item 2 and Planner ruling (e)).
- **Fixed code, no hammer, warm:** `Test.Fix.Asked`, `Test.Fix.PartnerDraft`, `Test.Fix.AskedTurns` and `Test.Fix.PartnerTurns` all passed.
- **DW-1398 (`Test/Watch/Summary.cls`) is not folded; it stays a separate DW.** Reading of the file, confirming the Planner's: the stale -3600 is in three places (`Incident` L878's `LastAt`, the group helper `Group` L929, and `Resolved`'s default `lastOffset` = -3600, L936/L943); `TestClosingLines` L163 passes -3600 on purpose (`Resolved(owner, .quiet, , , -3600)`) to build a quiet incident for `closeQuiet` (L164), so a "not quiet" guard cannot hold in `Incident`, and the change is more than one line. No Summary hammer was built.
- **Gates.** `bash docker/tests/test-class-rules.sh` exit 0. `bash docker/tests/test-boundaries.sh` exit 0, run at finalize after the absolute paths of the `## Planner Rulings` section were scrubbed (the implement run saw its `paths` rule fail on exactly those paths and nothing else).

**Mutations (each reverted byte for byte: backup copy, `cmp` after, `git diff --stat` as before):**
- mutation: `Asked.Incident` `LastAt` back to `..T(-3600)`, guard kept -> `Test.Fix.Asked` red at the guard "the fixture incident is not quiet, so no heartbeat closes it under the test" in every test that builds an incident (all but `TestNoticeKeys`, which builds none).
- mutation: `PartnerDraft.Incident` `LastAt` back to `..T(-3600)`, guard kept -> `Test.Fix.PartnerDraft` red at the guard in 10 of its 11 tests.
- mutation: `Asked.Incident` `LastAt` back to `..T(-3600)`, guard removed -> `Test.Fix.Asked` green warm (the race is invisible without load), AskedHammer red in 40 of 40 runs (`TestSuspendAndUndo` L117/L118 in 39, `TestRejectedAndExpired`, "and asking to undo again raises nothing").
- mutation: `PartnerDraft.Incident` `LastAt` back to `..T(-3600)`, guard removed -> `Test.Fix.PartnerDraft` green warm, DraftHammer red in 10 of 10 runs.


## Planner Rulings (binding; Contest Planner, Nov 15 about 19:40Z; they override any line above that disagrees)

These bind the implement stage. They add no product change; this spec's intent contract is unchanged.

- **Baseline.** `baseline_revision` is the branch HEAD at the implement stage's entry (`e6edc8559`, which includes feature 8c71bef6e with 23.3). Read `git diff --name-only <baseline>` for the footprint check, not `f56f50d86`.
- **(a) Separate commit.** DW-1391 lands as its own commit on `OCT-epic21-dw1205`, before DW-1205. Touch no `Fix/*` product file, no `Watch/*` product file and nothing else in DW-1205's footprint. The DW-1205 + DW-494 spec sits in this tree: do not implement it.
- **(b) Task 0 comes first, on the lane-C warm throwaway `e21dw1391iw`, before any change to a tracked file.** Build `ZzScratch.AskedHammer` and `ZzScratch.DraftHammer` as the Task 0 text says, under the scratchpad (see Runtime), and load them into the throwaway only (for example `docker cp` into the warm iris container, then `$SYSTEM.OBJ.Load` there; find the container with `OCUTALON_RUN_TAG=e21dw1391iw ci/warm.sh status`). Never put them in the repo. Show the OLD code red. Expected: `Test.Fix.Asked:TestSuspendAndUndo` red at L117/L118, or `TestUndoRollbackAsked` at L178, in some of 40 runs; PartnerDraft's exposed tests red under the hammer. Record the counts under `## Verification`. If it does not reproduce in 40 runs, record that and still apply the fix (the guard assert makes it deterministic).
- **(c) DW-1398** is `Test/Watch/Summary.cls:878`'s quiet fixture (`LEDGER_ID_COUNTER=<the main worktree's .worktrees/.coordination/ledger-next-id> bash _bmad/scripts/ledger.sh _bmad-output/implementation-artifacts/deferred-work.md show DW-1398`).
  - FOLD it into this commit ONLY IF it is the same one-line `LastAt` change (plus the same `Settle.Quiet` guard) AND the hammer covers it: the hammer must show the Summary test red under the hammer with the old fixture, and green with the fix.
  - Otherwise leave `Summary.cls` untouched and record in `## Verification` why it stays a separate DW.
  - The planner's reading, to be checked by you against the file and recorded: `Summary.cls` is NOT the same one-line change. `Incident` (L878), the group helper (L929) and the `Resolved` default `lastOffset` = -3600 (L938) all carry the stale -3600; `TestClosingLines` L163 passes -3600 on purpose to build a quiet incident for `closeQuiet` (L164), so a "not quiet" guard cannot hold in `Incident` and the change is more than one line. If you confirm this, do not fold, do not build a Summary hammer, and record the lines as evidence. Fold only if your reading of the file contradicts this.
- **(d) Rule 19 mutations.** (1) `LastAt` back to `..T(-3600)` with the guard kept: every test of the class goes red at the guard. (2) `LastAt` back to `..T(-3600)` without the guard: the hammer goes red. Do (1) for `Asked` and for `PartnerDraft`; do (2) for `Asked` (and `PartnerDraft` if cheap). Revert each byte for byte: `cp` a backup first and `cmp` after. Record `mutation: <change> -> <test that went red>`.
- **(e) Fixed code under the hammer:** 40 of 40 green for `Asked`, 10 of 10 for `PartnerDraft`. Then run each touched class whole once (warm, no hammer), plus `Test.Fix.AskedTurns` (and `PartnerTurns`).
- **(f)** Run `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh` before finalizing; both must exit 0.
- **(g) Rule 14.** Add nothing beyond this spec.
- **(h) IRIS MCP.** If you use IRIS MCP tools at all, name the explicit server profile `ocutalon-slot-c`, namespace OCUTALON. Never a demo or shared server, never `ocutalon-aihub-test`. One `iris_execute_tests` call per message, never two in one message. Prefer the `ci/` scripts and `docker exec`; they are the supported route.

**Runtime (Rule 21, lane C only).** On every `ci/iris.sh` and `ci/warm.sh` call set `OCUTALON_LOCK_DIR=<main worktree root>/.worktrees/.coordination/locks/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 story=DW-1391 stage=implement'`. Warm: `OCUTALON_RUN_TAG=e21dw1391iw ci/warm.sh up`, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21dw1391iw ci/iris.sh class <Class>[:<Method>]`, then `OCUTALON_RUN_TAG=e21dw1391iw ci/warm.sh down` (also after a failure). Keep the lane lock while the stack is up. Tear down everything you start. Never touch another lane's containers (lane D's `e21s11d` stack), the `ocutalon-slot-*` containers, `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, or any other `ocutalon-warm-*`/`ocutalon-t0*` stack. Never read `.env`. No absolute local path in a tracked file (keep this section's paths out of anything but this spec's own text, and write them relative where you can). Never read or write the `.worktrees/.coordination/unattended` path and never run `_bmad/scripts/unattended-inbox.sh`.
- Scratch (hammer classes, logs, backups) only under `<scratch>/edw1391impl/`. Earlier investigation artifacts are in `<scratch>/edw1391/`.
- Run every command in the foreground with `timeout: 600000`; each call under about 9 minutes, so split the 40-run loops (for example 8 to 10 runs per call, depending on the timing you measure). Tests are stateful: one class per call, never two test runs in one message.
- **Git.** Verify `git rev-parse --show-toplevel` equals the working directory and `git branch --show-current` is `OCT-epic21-dw1205` before editing. Do not commit, push, reset, rebase, stash, checkout or switch. The tree must end holding exactly: the two test classes, this spec.
- **No absolute local path in the spec.** In the text you add to the spec (`## Verification` records), write `<scratch>` for the scratch folder and relative paths otherwise. (The Rulings section's absolute paths were scrubbed at finalize.)
- **Provider outage.** If a model call answers 503, or 403 "Please run /login", stop at once, leave the tree as it is, and report `PROVIDER:`.

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 19 findings - high 0, medium 0, low 15, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the "39" of the guard-removed mutation reads as a stale count against "36+3" of the old-code run - the two are different run sets (39 of 40 vs 40 of 40); the fix is a spec wording edit.
  - `[low]` `[reject]` Blind: the guard uses `NowUtc()`, not the `QuietNow()` seam - they agree, and no test overrides the seam; a hypothetical, with more complexity to fix.
  - `[low]` `[reject]` Blind: the guard reads the incident's `LastAt` and not the group's - the quiet sweep and `closeQuiet` read only the incident's (spec Design Notes); the group line is consistency only.
  - `[low]` `[reject]` Blind: the guard message names no caller - Boundaries fix the label; a one-line label is enough for a fixture helper.
  - `[low]` `[patch]` Blind: the `test-boundaries.sh` gate record says fail - patched: the record now says exit 0 after the scrub (run at finalize).
  - `[low]` `[reject]` Blind: line numbers L936/L943 vs L938 of the DW-1398 evidence - the file has the helper's default at L936 and its use at L943; the fix edits the spec.
  - `[low]` `[reject]` Blind: doc-comment placement and a double blank line - cosmetic; the spec dictated the header line.
  - `[low]` `[reject]` Edge: an empty or malformed `LastAt` in `fields` passes the guard - no caller passes `LastAt`; the product's `closeQuiet` uses the same predicate, so such a row is not closed either.
  - `[low]` `[reject]` Edge: the same finding for `PartnerDraft`.
  - `[false]` `[reject]` Edge: `RefIndexOpen(ref)` may be empty - the ref was returned by `Fixture.Incident` and saved on the line before; if it were empty the assert errors loudly.
  - `[false]` `[reject]` Edge: the same for `PartnerDraft`.
  - `[low]` `[reject]` Edge: the group's `LastAt` is not guarded - same as the Blind row.
  - `[low]` `[patch]` Edge: the gates claim at the spec's Verification is stale - patched with the Blind gate row.
  - `[false]` `[reject]` Edge: the hammer sends through `CommandsIn`, not `Commands.Submit` - the deviation is recorded in Verification and the hammer measured red on the old code.
  - `[low]` `[defer]` Verification gap: AC 1 rests on a scratch-only hammer, so no standing check repeats it - by design of the spec; recorded in `deferred`.
  - `[low]` `[reject]` Verification gap: AC 3 has no `mutation:` line - AC 3 restates that the unchanged suite passes (no mutable change); the fix edits the spec.
  - `[low]` `[reject]` Verification gap: no test pins the group's `LastAt` - no product code reads it (the finding's own evidence); no named harm.
  - `[low]` `[patch]` Verification gap, other: the boundaries gate record is stale - patched with the Blind gate row.
  - `[false]` `[reject]` Intent alignment auditor: descriptive report (readings A and D; the diff implements both); it claims no defect.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: `Asked.Incident` and `PartnerDraft.Incident` now build a fresh fixture incident (incident and group `LastAt` = now) and assert, after the save, that `Settle.Quiet` is 0 for the stored row, so the heartbeat's quiet sweep cannot close it under the test. Test-only; no product file.
- Files changed: `src/ocutalon/cls/OcuTalon/Test/Fix/Asked.cls` (helper, guard, header line), `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls` (the same), this spec (Verification records, Planner Rulings, triage log).
- DW-1398 (`Test/Watch/Summary.cls`): not folded; it stays a separate DW (see Verification).
- Review: 19 findings (high 0, medium 0, low 15, false 4); patches applied: 1 group (the gates record, 3 rows); deferred: 1 (the hammer is not in the repo); the rest rejected with reasons in the triage log.
- Follow-up review recommendation: false (no high patched).
- Verification: old code under the hammer, AskedHammer 39 of 40 red and DraftHammer 10 of 10 red; fixed code 40 of 40 and 10 of 10 green; the guard mutations red in every incident-building test; `Test.Fix.Asked`, `PartnerDraft`, `AskedTurns` and `PartnerTurns` green warm; `test-class-rules.sh` and `test-boundaries.sh` exit 0.
- Residual risk: the race is shown only under the scratch hammer; the standing protection is the guard.
