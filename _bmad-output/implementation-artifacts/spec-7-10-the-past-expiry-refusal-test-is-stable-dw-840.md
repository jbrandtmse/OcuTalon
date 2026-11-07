---
title: 'Story 7.10: The past-expiry refusal test is stable (DW-840)'
type: 'bugfix'
created: '2026-11-07'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Test.Fix.Refused` `TestPastExpiryCannotStart` went red once in CI (`shards-2`, `lane-a@rest`, run 42314928349 on OCT-epic7 `079513571ebef52a4aad9294644e6d5fdfe57120`) at "the incident is resolved" (Refused.cls:100), the class at 34.03 s against about 3.6 s green: the 30 s `WAITRUN` wait ran out (DW-840). The lead's Task 0 measured the cause: the test's fixture incident keeps `Case.Fixture`'s default `LastAt` (2026-10-25T08:00:05Z), far more than `IncidentManager.QUIETSECONDS` (900 s) ago, so a real heartbeat Tick's quiet sweep sends `closeQuiet` for it; while it is `fixing` the table refuses that, but once the FixResult moves it to `resolved`, `resolved + closeQuiet -> closed` is accepted (AD-15), and a sweep landing between that move and the test's first poll leaves `WaitIncidentState` seeing `closed` until it times out. The product is correct; the fixture is stale.

**Approach:** A test-only fix in `TestPastExpiryCannotStart` alone: give its fixture `FirstAt` and `LastAt` of now (beside the existing `NoticedAt`), so the quiet sweep cannot close the incident while the test runs, following the sibling `Test/Fix/DryRun.cls:94`. Record the measured cause in the story's evidence folder. Every pin stays as it is.

## Boundaries & Constraints

**Always:**
- The test still proves, in order and unweakened: one final FixResult `1|0|3|0|0|0|0|0|NOSTART`; one request, `failed`; one FixRun with no copy, 3 targets, the reason, ended; the incident `resolved`; one `result.couldNotStart` notice with the request's Ref and its exact phone text; one audit Action entry; no OCUORDERS change.
- One contract comment at the changed fixture line says why FirstAt and LastAt are now and cites DW-840; the method's doc comment states the fixture's contract (its first and last failure are now). Comments state the contract, never history (Rule 14). ASCII only in code.
- Paths written in the spec and evidence file are repo-relative or placeholders (`test-boundaries.sh` scans every new file for local machine paths).

**Never:**
- No product code; no change to `Test/Watch/Case.cls` (shared helper, its `Fixture` defaults stay) or to any other test class or method (`TestNoApprovedRowNoRun` included).
- No assertion deleted, loosened, reordered or moved; no timeout or wait argument added, raised or removed (`WAITRUN` and every wait call keep their defaults); no skip or retry.
- No change to `IncidentManager.QUIETSECONDS`, the transition table, `Checks`, demo mode, or any public text.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Heartbeat sweeps during the test (DW-840) | Fixture `fixing`, FirstAt/LastAt/NoticedAt = now; real Ticks each minute; the lead's closeQuiet load (two jobs sending closeQuiet for every unclosed incident) | Every closeQuiet for this incident is answered `not_quiet` (IncidentManager re-checks `Settle.Quiet(LastAt, QuietNow, QUIETSECONDS)`); FixResult moves it to `resolved`, and `WaitIncidentState` sees `resolved`; the class passes (lead: 20 of 20 under load) | No error expected |
| A real defect: the incident never resolves | IncidentManager does not apply the final FixResult | `WaitIncidentState` returns `fixing` after 30 s; red at "the incident is resolved" | The red names the pin: a real product defect |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Test/Fix/Refused.cls` -- the only source file changed. `TestPastExpiryCannotStart` 68-113: doc comment 64-67 ("A fixing incident of session S over three real failed orders names R, ..."); **the fixture line 78** `Set row = ..Fixture(a, ids, ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (##class(OcuTalon.Data.Time).NowUtc())})`; the red pin 100 `..WaitIncidentState(incident, "resolved")`. `TestNoApprovedRowNoRun` 14-62 (its fixture is `open`, never waits for a state, and demo mode refuses `open + closeQuiet`): leave it.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- read-only. `Fixture` 842-870 sets `FirstAt` 2026-10-25T08:00:00Z and `LastAt` 2026-10-25T08:00:05Z (852-853), then applies `fields` as properties after them, so fields override the defaults. `WAITRUN` = 30 (130). `WaitIncidentState` 1856-1867 polls every 0.5 s.
- `src/ocutalon/cls/OcuTalon/Test/Fix/DryRun.cls:94-95` -- the sibling precedent to follow: `// LastAt is now, so that a heartbeat's quiet sweep (QUIETSECONDS) does not close the incident while its row is compared.` then `"LastAt": (##class(OcuTalon.Data.Time).NowUtc())` in its `Fixture` fields. Read-only.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- read-only evidence: class doc 3-8 (Tick: the quiet sweep first) and `Quiet` 419-431 (every incident not `closed` whose `LastAt` is more than `QUIETSECONDS` before now).
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- read-only: `QUIETSECONDS` = 900 (115); the `not_quiet` re-check on closeQuiet (1155).
- `src/ocutalon/cls/OcuTalon/Watch/Transitions.cls:15-19` -- read-only: `resolved + closeQuiet -> closed`; `open + closeQuiet -> closed only when demoMode is 0`.
- `src/ocutalon/cls/OcuTalon/Watch/Settle.cls:83-89` -- `Quiet(lastAt, now, seconds)`: `(now - last) > seconds`.
- `_bmad-output/implementation-artifacts/evidence/34-4/cause.md` -- the shape to follow for this story's `cause.md` (Story 34.4, DW-825). Read-only.
- `_bmad-output/implementation-artifacts/cycle-log-epic-7.md` -- the lead's `task0_measured` line (2026-11-07T14:10:48Z) holds the measured numbers this spec quotes. Read-only.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Test/Fix/Refused.cls` -- in `TestPastExpiryCannotStart` only, replace line 78 with the lead's proven shape:
  ```
  	// FirstAt and LastAt are now, so that a heartbeat's quiet sweep (QUIETSECONDS) does not close the incident between its move to resolved and the wait for it (DW-840).
  	Set now = ##class(OcuTalon.Data.Time).NowUtc()
  	Set row = ..Fixture(a, ids, ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now)})
  ```
  and in the doc comment (64-67) change "A fixing incident of session S over three real failed orders names R" to "A fixing incident of session S over three real failed orders, its first and last failure now, names R". Nothing else in the file changes. -- removes the stale LastAt the quiet sweep acts on (the measured cause); the comment states the contract.
- `_bmad-output/implementation-artifacts/evidence/7-10/cause.md` -- new, short (about 30 lines, the 34-4 shape): the red (run, head, pin, 34.03 s vs about 3.6 s), the cause (the Intent's chain, with the file:line anchors of the Code Map), the lead's measurement (load harness: an untracked subclass of Refused with two jobs sending closeQuiet back to back for every unclosed incident; old code red 2 of 11, "FAIL TestPastExpiryCannotStart: the incident is resolved", class 38-43 s; an old-shape copy recorded `resolved@0.08 s, closed@0.33 s` every run; the fix 20 of 20 under the same load), why the product is right (AD-15's row), the fix, and the other callers checked (Design Notes). Repo-relative paths only. -- AC 1 of the story asks that the cause be named; the epic's flake pattern records it here.

**Acceptance Criteria:**
- Given the changed `Refused.cls`, when it is diffed against the baseline, then the only code change is the fixture line of `TestPastExpiryCannotStart` (plus its `Set now` and comment lines) and one doc-comment phrase: every `$$$Assert*` line of the baseline is present byte-identical, no wait call or timeout argument changed, and `Case.cls` is untouched (DW-840).
- Given a fresh throwaway in lane B, when `ci/iris.sh class OcuTalon.Test.Fix.Refused` runs, then it prints `CLASS OcuTalon.Test.Fix.Refused passed` with both tests passing and no `FAIL` or `SKIP` line (DW-840).
- Given the story's evidence folder, when `evidence/7-10/cause.md` is read, then it names the cause (the quiet sweep's closeQuiet closing the stale-LastAt fixture after its move to resolved), the lead's old-code red (2 of 11) and the fix's 20 of 20 under the same load (DW-840).

## Spec Change Log

## Review Triage Log

## Design Notes

- **The cause, and why the product is right.** The quiet sweep (Checks, AD-18) and `resolved + closeQuiet -> closed` (AD-15's transition table) are the rule: a resolved incident whose last failure is older than 15 minutes closes on the next heartbeat. Only the fixture's 2026-10-25 LastAt made a seconds-old incident look 13 days quiet. The fix changes no AD's Rule and complies with AD-15, AD-18 and AD-22 (tests run in throwaways and CI only). AD-5 is untouched (no stored state changes).
- **Other `WaitIncidentState(..., "resolved")` callers checked (lead's claim, verified at planning).** `Test/Fix/{Waits,Results,Scale,Execute,Restart,Partial,Stopped,Runs}.cls` wait on real raised incidents (LastAt from their own fresh failures); `Test/Watch/Closing.cls:168` uses `Test.Data.Fixture.Incident`, whose LastAt is 2030 (future, never quiet). `Waits.cls:186`'s `..Fixture(a, ids)` incident F stays `open`, which demo mode protects from closeQuiet, and is never waited to `resolved`. `Refused.TestNoApprovedRowNoRun`'s fixture is `open` likewise. So only `TestPastExpiryCannotStart` carries the stale-LastAt race, and the change stays in that method.
- **Extend, don't copy (Rule 2).** No new helper; the fix follows `Test/Fix/DryRun.cls:94`'s inline pattern (LastAt now through `Fixture`'s `fields`). `Case.Fixture`'s default is left as it is: changing a shared helper is outside this story's footprint and could change other tests' state.
- **Integration ACs (Rule 1).** No consumers in this story (test-only fix). Consumed-by: none. Consumes: `Test.Watch.Case` `Fixture` (through its `fields` argument, unchanged).
- **NFRs (Rule 5).** No NFR changes.
- **Decided in-stage.** (1) FirstAt is set to now along with LastAt (the lead's proven diff), so FirstAt is never later than LastAt. (2) The doc comment gains one phrase rather than a new sentence (smaller). (3) `evidence/7-10/cause.md` is written by implement from this spec's numbers (the epic context's flake pattern; inside Epic 7's implementation artifacts); the load harness itself stays the lead's, untracked, and `proof.md` with run ids is the lead's after implement.
- **Ledger inbox.** DW-840 is addressed by the first Execution task and all three ACs.

## Verification

`<laneB>` stands for `env OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root (`<lock-dir>` is the main checkout's `.worktrees/.coordination/locks`). One command per foreground call with `timeout: 600000`; never two IRIS test runs in one message. These classes run only in throwaway stacks and CI (Rule 21), never on a slot.

**Commands:**
- (loop) `<laneB> OCUTALON_RUN_TAG=e7s10impl ci/iris.sh class OcuTalon.Test.Fix.Refused` -- one fresh throwaway, about 3-5 minutes. Expected: `CLASS OcuTalon.Test.Fix.Refused passed`, no `FAIL` or `SKIP`.
- (once) `<laneB> OCUTALON_RUN_TAG=e7s10impl ci/iris.sh teardown` -- after the run, also after a failure.
- (once) `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh`, one call each. Expected: PASS.
- (once) `git diff -- src/ocutalon/cls/OcuTalon/Test/Fix/Refused.cls` and `git diff --stat` -- expected: only the lines the first task names; no other source file.

No full-suite or shard run here: CI runs the shards (the CI-fresh arrangement). The lead owns the 20-of-20 load proof (done in Task 0, re-run after implement).

**Shared surfaces:** none.

Every test added or changed passes on a fresh environment, in either order.

mutation: fixture LastAt back to the Case default (2026-10-25) under the closeQuiet load → TestPastExpiryCannotStart red ("the incident is resolved"), lead Task 0

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (Halt after planning). Spec verified against the READY FOR DEVELOPMENT standard; DW-840 addressed by the first Execution task and all three ACs. Nothing implemented, nothing committed.
