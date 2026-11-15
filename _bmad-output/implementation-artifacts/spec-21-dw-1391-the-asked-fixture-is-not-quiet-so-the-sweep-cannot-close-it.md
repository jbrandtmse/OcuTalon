---
title: 'DW-1391: The asked fixture is not quiet, so the sweep cannot close it'
type: 'bugfix'
created: '2026-11-15'
status: 'ready-for-dev'
baseline_revision: 'f56f50d86844050634bbb8a065e777f34483e0ec'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/7-10/cause.md'
warnings: []
deferred: []
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

**Task 0 records:** (to be written by the implement stage)

## Auto Run Result

Status: ready-for-dev
Blocking condition: none. The spec gate has no item to rule (test-only).

- Summary: the plan only; nothing is implemented.
- Size: small. Two test classes, about 6 changed lines and 6 doc lines each. No product file. No oversized warning.
