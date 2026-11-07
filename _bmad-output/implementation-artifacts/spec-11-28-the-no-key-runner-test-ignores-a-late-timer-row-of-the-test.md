---
title: 'Story 11.28: The no-key runner test ignores a late timer row of the test before it'
type: 'bugfix'
created: '2026-11-07'
status: 'done'
baseline_revision: 'b7710d2db03715613fbbd9a507cc85488a45b253'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Test.Agent.Runners.TestStartsWithNoKey`'s last check, "the event log holds no error or alert row since the mark", fails in CI shards-2 (lane-a@rest) on a loaded host (DW-688). `RunnerFixture.ErrorRows(mark)` keeps every Type 2 or 6 row after the mark, so a late Ens.Alarm row "Message '<n>' can not be found, timer event ignored" turns the test red. That row comes from an earlier test's timer, whose request header that test's clean-up deleted.

**Approach:** Test-only. `ErrorRows` gets an optional header mark: with it, an Ens.Alarm Type 2 timer-ignored row for a header id at or below the mark is left out. Every other row is kept. `TestStartsWithNoKey` takes the header mark next to `errorMark` and passes it on. A new test class pins the narrowed rule with real Ens.Alarm rows.

## Boundaries & Constraints

**Always:**
- `ErrorRows(mark, headerMark = "")`. With `headerMark` = "", behaviour, output format and the SQL-failure row stay exactly as today. With a header mark, a row is left out only when all four hold: Type is 2, ConfigName is `Ens.Alarm`, the Text starts with `Message '<n>' can not be found, timer event ignored` with `<n>` one or more digits, and `<n>` <= `headerMark`. Every other row is kept, in the same "<type>: <item>: <text>" form and order.
- The header mark is the existing `RunnerFixture.HeaderMark()` (MAX(ID) of Ens.MessageHeader), taken right after `errorMark` at Runners.cls line 207.
- The Runners.cls diff stays inside `TestStartsWithNoKey`: its doc comment (lines 149-152) and its body (153-229). Epic 19 (in flight) edits only REMINDERTOOLS (~72) and TestToolInventory (~314-335), so the two diffs union cleanly.
- The assertion text at line 228, the control block (lines 185-195, `ErrorRows(controlMark)` with one argument) and every other assertion stay unchanged.
- New test methods go in the new class `OcuTalon.Test.Agent.ErrorRowsMark`, in the Agent area, so `ci/units.sh` already sends it to lane-a@rest. Its tests need the production running (`RunnerFixture.ReadyReason`, as `Runners.Ready` does). They wait by polling with a ceiling, never a fixed long Hang. They delete what they created: AlarmRequest bodies, remaining headers of the planting, synthetic log rows, and the Ens.Alarm rows they waited for, by ID. No planted timer outlives its test: if a planted timer's row has not appeared, OnAfterOneTest polls for it once more up to the same ceiling before it deletes.
- Every test added or changed passes on a fresh environment, in either order.

**Never:**
- No product code change. If the cause turns out to be in the product, HALT `blocked` `intent gap` naming it before any product edit.
- No pin deleted or weakened. No timeout, deadline or ceiling raised as the fix. Runners' WAITSECONDS and RunnerFixture's WAITSECONDS/SENDSECONDS are unchanged.
- No change to `Test/Schedule/Heartbeat.cls`, to `Test/Watch/Poller.cls` (its own private ErrorRows), to `ci/units.sh`, or to any Runners.cls line outside TestStartsWithNoKey.
- No absolute path, lock folder, scratchpad or worktree path in any committed file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Pre-mark timer (real) | Ens.Alarm Type 2 timer-ignored row, header id <= headerMark, row ID > eventMark | Left out of `ErrorRows(eventMark, headerMark)`; present in `ErrorRows(eventMark)` | A row not seen within the poll ceiling fails the test, naming the header id |
| Post-mark timer (real) | Same text, header id > headerMark | Present in both calls | as above |
| Boundary | Synthetic Ens.Alarm Type 2 row, `<n>` = headerMark, and one with headerMark+1 | The first is left out, the second kept | none |
| Other config | Synthetic Type 2 row with the same text for a pre-mark id, ConfigName not `Ens.Alarm` | Kept | none |
| Other text | Synthetic Ens.Alarm Type 2 rows: `<n>` empty or not all digits (`Message '' ...`, `Message '12x' ...`); other wording after a pre-mark id | Kept | none |
| Alert type | Synthetic Ens.Alarm Type 6 row with the timer-ignored text for a pre-mark id | Kept (only Type 2 is left out) | none |
| No header mark | Any of the above with headerMark "" | Every row kept (today's behaviour) | SQL failure still gives the one "SQL ..." row |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` (1210 lines). Class header 3-62 (line 37 describes ErrorRows; line 9 lists HeaderMark). `Send` 316-326 (CreateBusinessService("ApprovalStartIn"), SendRequestSync with SENDSECONDS). `HeaderMark` 493-499 is the existing mark to reuse. `ErrorRows` 830-846. `EventMark` 239-244. `ReadyReason` 363-369.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls` (648 lines). `TestStartsWithNoKey` doc 149-152, body 153-229. `errorMark` is taken at 207 (`$ClassMethod(fixture, "EventMark")`). The final check is at 228. `Ready()` 468-474 is the readiness pattern. `OnAfterOneTest` 123-147.
- `irislib/Ens/Alarm.cls:99-111` (read-only). When `Ens.MessageHeader.%OpenId(<request header id>)` fails, it writes `$$$LOGERROR("Message '"_tRequestHeaderId_"' can not be found, timer event ignored. Timer ID ='<h>'. ... Sent request to ScheduleHandler to check for production differences.")`. `<n>` is the request header id, and it is "" when the timer data is corrupt. `irislib/Ens/AlarmRequest.cls:18`: `Timeout As %String`.
- Unchanged one-argument callers: `Test/Schedule/Heartbeat.cls:319, 380` and `Runners.cls:186` (the control).
- Synthetic log row precedent: `Test/Watch/Case.cls:985-998` (`Ens.Util.Log` %New, Type, ConfigName, Text, TimeLogged, %Save). That one is private and switches to OCUORDERS, so the new class has its own short helper for OCUTALON.
- `ci/units.sh:20`: lane-a areas include `Agent`. `docker/tests/test-ci-config.sh` "test classes" discovers new classes without a count pin.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:
  - Add the optional `headerMark` argument to `ErrorRows`, with the rule of Boundaries (read the full Text or its first 200 characters; the prefix fits).
  - Add an optional trailing `seconds` argument to `Send`; empty means SENDSECONDS, so every caller keeps today's call.
  - Update ErrorRows' doc comment and the class-header bullet (line 37) to state the contract.
  - DW-688. AC1, AC2.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls`, in TestStartsWithNoKey only:
  - After line 207, add `Set headerMark = $ClassMethod(fixture, "HeaderMark")`.
  - Line 228 passes `errorMark, headerMark`.
  - Add one sentence to the method doc comment: a timer-ignored row of a header from before the mark is not this test's.
  - DW-688. AC3.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Agent/ErrorRowsMark.cls` (new, `Extends %UnitTest.TestCase`), with a header that says what it pins and what it needs:
  - `TestTimerRowsAroundTheMark` (real rows). Plant timer A, then take eventMark (`EventMark`) and headerMark (`HeaderMark`), then plant timer B. Poll, with a ceiling, until both rows have ID > eventMark. Control first: assert A's row ID > eventMark, so the left-out case is not vacuous. Then assert membership by header id: A is absent from and B present in `ErrorRows(eventMark, headerMark)`, and both are present in `ErrorRows(eventMark)`.
  - To plant a timer: an `Ens.AlarmRequest` with a canonical-number Timeout (e.g. `3`, never a trailing zero like `5.50`, which reads as 0 s), sent with `RunnerFixture.Send("Ens.Alarm", req, .resp, , 1)`. Then find its header (`TargetConfigName = 'Ens.Alarm'`, `MessageBodyClassName = 'Ens.AlarmRequest'`, `MessageBodyId = req.%Id()`) and `Ens.MessageHeader.%DeleteId` it. A's Timeout must be long enough that its row lands after the marks.
  - `TestOtherRowsKept` (synthetic rows of the Matrix's Boundary, Other config, Other text and Alert type rows, plus the no-header-mark row). Membership assertions only, never whole-list equality: unrelated production rows can appear.
  - OnAfterOneTest deletes what each test created (Boundaries).
  - AC1, AC2.
- [ ] This spec: Verification results and one `mutation:` line per AC.

**Acceptance Criteria:**
- AC1 (the narrowed rule, DW-688). Given real Ens.Alarm timer-ignored rows for one header from before and one from after the header mark, both landing after the event mark, when `ErrorRows(eventMark, headerMark)` is read, then the pre-mark row is absent and the post-mark row is present. The test fails if either is wrong, and `ErrorRows(eventMark)` holds both.
- AC2 (still fails on rows it must see). Given each synthetic row of the Matrix, when ErrorRows is read with and without the header mark, then only the `<n>` <= headerMark Ens.Alarm Type 2 timer-ignored row is ever left out.
- AC3 (Integration: consumer Runners). Given `OcuTalon.Test.Agent.Runners` with timers planted around TestStartsWithNoKey's window, when the class runs, then TestStartsWithNoKey is green 20 of 20 and its assertions are unchanged. The unchanged class failed 2 of 3 under the same planting with CI's message (lead, Task 0). Without planting, the class is green on the warm stack.
- AC4 (existing callers). Given Heartbeat's one-argument calls, when `OcuTalon.Test.Schedule.Heartbeat` runs, then it is green with no change to its file.

## Spec Change Log

## Review Triage Log

### 2026-11-07 - Review pass
- verdicts: 14 rows (findings of the same root cause across layers share a row) - high 0, medium 5, low 6, false 2, maybe-false 0, descriptive 1
- findings:
  - `[medium]` `patch` Blind: planting may delete the header before Ens.Alarm takes the request up (thin margin on a loaded host); also Edge #2 and Verification-gap #1, one root cause - fixed: `Plant` now polls (ceiling ROWSECONDS) until the header leaves Created/Queued before `Drop`, failing with the header id otherwise.
  - `[medium]` `patch` Edge #1, Verification-gap other finding, Intent-alignment fresh-environment note: `TestOtherRowsKept` low-number case assumes a header with id >= 1 exists - fixed: the number is 0 when the header mark is below 1.
  - `[low]` `patch` Blind #2, Edge #4: cleanup polls the whole log (`WaitRow(id, 0)`) - fixed: `OnBeforeOneTest` records the event mark in `Mark`, cleanup passes it.
  - `[low]` `patch` Blind: `Plant` discards the `Send` status - fixed: the status text goes into the "has a header" failure message.
  - `[low]` `patch` Blind: the fixture class-header line is over-long - fixed: wrapped.
  - `[false]` `reject` Intent-alignment: the mark may not cover an earlier test's header - TestStartsWithNoKey sends many requests before its mark (Ask/Send to each runner), so the MAX(ID) is above any earlier test's headers.
  - `[false]` `reject` Edge #6: headers created between the two marks fall outside the filter - the two marks are taken on adjacent lines; a header between them is at or below the header mark, which only leaves out a timer row, never hides one of this test's own messages (they are created after both).
  - `[low]` `reject` Blind #1: TestOtherRowsKept has no GuardReason - it writes only synthetic Ens.Alarm rows it deletes itself; sibling tests (Test.Watch.Case) do the same without a guard; the header's CI-only sentence is the project's Rule 21 process, not code.
  - `[medium]` `reject` Blind #3, Edge #3: cleanup may wait up to ROWSECONDS per unseen timer - spec-bound: "OnAfterOneTest polls for it once more up to the same ceiling"; a ceiling is not raised or lowered by this story.
  - `[medium]` `reject` Blind: Heartbeat still reads ErrorRows(eventMark) without the header mark (also Verification-gap other finding) - spec-bound: Never "no change to Heartbeat", AC4 pins the one-argument form; no Heartbeat failure is recorded.
  - `[low]` `reject` Blind: cascade of noise when a synthetic row fails to write - only follows a failure that is already reported.
  - `[low]` `reject` Edge #5: a timer row with an empty `<n>` stays unfiltered - spec-bound (digits, one or more) and pinned by the Matrix row Other text.
  - `[medium]` `reject` Verification-gap #2: no committed test pins that Runners passes the header mark - spec-bound: AC3 is the lead's planted 20-of-20 run on the consumer; a deterministic pin needs a planted timer in Runners' window, which the spec excludes (Runners diff stays inside TestStartsWithNoKey's few lines).
  - `[-]` `reject` Intent-alignment (3 descriptive items: readings A/B/C, surface of tests versus the DW-688 sequence, unrequested `Send` argument) - descriptive; `Send`'s optional argument is spec task D4; the consumer surface is AC3's lead-side run.

## Design Notes

**Root cause (lead's Task 0 measurement, 2026-11-07, warm lane-A throwaway; recorded, not repeated).**
- ErrorRows(mark) keeps any Type 2/6 row of any ConfigName after the mark.
- Ens.Alarm writes the timer-ignored Type 2 row when a pending timer wakes and its request header is gone (Alarm.cls:103-106). Many test classes delete headers with `Ens.MessageHeader.%DeleteId`.
- The window from errorMark (207) to the check (228) is under 0.4 s on a fast host and longer on a loaded one.
- With real dangling timers waking every 0.1 s around the window (the planting above, from a service made by `Ens.Director.CreateBusinessService("ApprovalStartIn")`), the unchanged class failed 2 of 3 runs with exactly CI's message. Without planting it passed.
- The cause is the test's reader, not the product: Ens.Alarm behaves as documented for a header a test deleted.

**Governing ADs.**
- AD-22: `%UnitTest` classes under `OcuTalon.Test.<Area>`, sharded by area. CI tests include "the production starting with no model key"; this story keeps that test's pins.
- AD-19 / FR-38: a start with no key writes no error row. Still pinned: a Decide timer, or any row of this test's own messages, has a header id above the mark and is kept.
- AD-29: Lane A files; the Agent area runs in lane-a.
- No AC contradicts an AD's Rule or Prevents line. NFRs: none unmeasurable.

**Rule 1/2.**
- Integration AC: AC3 (consumer `Runners.TestStartsWithNoKey`).
- Consumed-by: Story 11.28's `Runners.TestStartsWithNoKey` (the header-mark argument). Heartbeat keeps the one-argument form.
- Consumes: `RunnerFixture.HeaderMark`, `EventMark`, `Send`, `ReadyReason`, and the real `Ens.Alarm` host.
- Extend, don't copy: ErrorRows is extended in place, `Send` gets the timeout argument rather than a second CreateBusinessService copy, and the mark is the existing `HeaderMark`. The new class's synthetic-row helper is a deliberate short copy of `Test.Watch.Case.MakeSessionLog`, because that one is private, switches to OCUORDERS and sets session fields, and is outside this story's files.

**Ledger (Rule 17).** DW-688 is addressed by every task and AC1-AC3. Nothing is declined.

**Decided in-stage.**
- D1. I reuse `HeaderMark()` instead of adding the lead's proposed `MessageMark()`: it already is "the highest Ens.MessageHeader ID now" (RunnerFixture.cls:493-499, used by ~60 callers), and a second copy would violate Rule 2. The argument and variable are named `headerMark` to match.
- D2. Only Type 2 is left out. Ens.Alarm writes this row with `$$$LOGERROR` (Type 2), and an alert-type row is kept, which is the narrower reading of "every other Type 2 or Type 6 row still fails".
- D3. The boundary is `<n>` <= headerMark: a header with the mark's own id existed when the mark was taken.
- D4. `Send` gains an optional `seconds` argument so the planting can make a 1 s sync call. Today's callers are unchanged.
- D5. The new tests assert membership, not whole-list equality, so an unrelated production row cannot turn them red. The non-vacuity control asserts that the pre-mark row lands after the event mark.

## Verification

Every command runs from the worktree root after `git rev-parse --show-toplevel` matches it, each in its own foreground call with `timeout: 600000`, one test class per call. The warm stack `e11s28lw` belongs to the lead: never `ci/warm.sh up/down` it. Use no IRIS MCP target other than `ocutalon-slot-a` / `OCUTALON`. `<warm>` below stands for `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s28lw OCUTALON_LOCK_DIR=<lock-dir>/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement'`.

**Commands:**
- (loop) `<warm> ci/iris.sh class OcuTalon.Test.Agent.ErrorRowsMark`. Expected: `CLASS ... passed`, no FAIL or SKIP (AC1, AC2).
- (loop) `<warm> ci/iris.sh class OcuTalon.Test.Agent.Runners`. Expected: passed (AC3, unplanted).
- (once) `<warm> ci/iris.sh class OcuTalon.Test.Schedule.Heartbeat`. Expected: passed (AC4; about 150-210 s).
- (once) The order check, three calls in sequence: `<warm> ci/iris.sh class OcuTalon.Test.Agent.ErrorRowsMark`, the same again, then `<warm> ci/iris.sh class OcuTalon.Test.Agent.Runners`. Expected: all passed, so no planted timer or row leaks into a later run.
- (once) `bash docker/tests/test-ci-config.sh`. Expected: `PASS test classes` (the new class is discovered in lane-a).
- (once) `git diff -U0 -- src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls`. Expected: every hunk lies inside TestStartsWithNoKey (its doc comment and body, base lines 149-229). No hunk touches REMINDERTOOLS or TestToolInventory.
- (once) `git diff --stat -- . ':(exclude)_bmad-output'`. Expected: exactly RunnerFixture.cls, Runners.cls and the new ErrorRowsMark.cls.
- (once, lead-side, not implement) the planted-timer run of `OcuTalon.Test.Agent.Runners` on the warm lane-A throwaway, 20 of 20 green with the fix (AC3). Task 0 already recorded the old code red 2 of 3.

**Rule 19.**
- Shared surfaces: `RunnerFixture.ErrorRows` (its callers: Runners, Heartbeat), `RunnerFixture.Send` (many callers; the new argument is optional), and the event log and message headers (rows the new class creates and deletes).
- Every test added or changed passes on a fresh environment, in either order.
- Mutations to demonstrate. For each one, observe red, restore byte-identical, and write it as a `mutation:` line:
  - AC1: ignore `headerMark` in the comparison (leave out every timer-ignored row) → TestTimerRowsAroundTheMark red on the post-mark row.
  - AC1: drop the header-mark filter → red on the pre-mark row.
  - AC2: drop the ConfigName check → TestOtherRowsKept red on the other-config row.
  - AC2: accept a non-digit `<n>` → red on `12x`.
  - AC3: (lead, Task 0) the unchanged class under planting → red 2 of 3.
  - AC4: with `headerMark` "", leave out every Ens.Alarm row → TestTimerRowsAroundTheMark red on "`ErrorRows(eventMark)` holds both". This pins the one-argument form Heartbeat relies on.

**Mutation results (implement, 2026-11-07, warm lane-A `e11s28lw`; each restored byte-identical from a backup, checksum compared).**
- mutation: AC1 - `TimerIgnoredAtOrBelow` ends `Quit 1` (every timer-ignored row left out) -> `ErrorRowsMark` red: TestTimerRowsAroundTheMark "the row of header <B> (above the mark) is kept" and TestOtherRowsKept "above-mark row is kept".
- mutation: AC1 - the `Continue` condition made `0` (header-mark filter dropped) -> red: "the row of header <A> (at or below the mark) is left out" and TestOtherRowsKept below-mark and low-number.
- mutation: AC2 - the `config = "Ens.Alarm"` test removed -> TestOtherRowsKept red: "the other-config row is kept".
- mutation: AC2 - `If number '? 1.N Quit 0` replaced by `If number = "" Quit 0` -> TestOtherRowsKept red: "the letter-number row is kept".
- mutation: AC4 - with `headerMark` "", every Ens.Alarm row left out -> red: "without the header mark / with an empty header mark, the below-mark, above-mark, low-number and empty-number rows are kept" (the one-argument form Heartbeat relies on).
- mutation: AC3 - lead, Task 0: the unchanged class under planting, red 2 of 3.

## Auto Run Result

Status: done
Blocking condition: none

Summary: `RunnerFixture.ErrorRows(mark, headerMark = "")` leaves out only a Type 2 Ens.Alarm "Message '<digits>' can not be found, timer event ignored" row whose number is at or below the header mark; `Send` takes an optional `seconds`; `Runners.TestStartsWithNoKey` takes `HeaderMark` next to `errorMark` and passes it to its last check; the new `ErrorRowsMark` class pins the rule with two real Ens.Alarm timers and eight synthetic rows.

Files changed:
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`: header mark argument, `TimerIgnoredAtOrBelow` helper, `Send` seconds argument, doc comments.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls`: three hunks inside TestStartsWithNoKey.
- `src/ocutalon/cls/OcuTalon/Test/Agent/ErrorRowsMark.cls`: new test class (TestTimerRowsAroundTheMark, TestOtherRowsKept).

Review findings: 5 patches applied (2 medium, 3 low), none deferred, 9 rejected with the reasons in the Review Triage Log. Follow-up review recommended: false (no high patched; two medium patched, both test-hardening).

Verification (warm lane-A `e11s28lw`, one class per call): `ErrorRowsMark` passed (after patches, three times in all, 8 s); `Runners` passed (42 s, twice); `Schedule.Heartbeat` passed (86 s, unchanged file); `docker/tests/test-ci-config.sh` PASS test classes (282 classes, shards hold them all); Runners.cls hunks lie at base lines 152, 207 and 228 only; `git diff --stat` outside `_bmad-output`: exactly RunnerFixture.cls, Runners.cls and ErrorRowsMark.cls. Five mutations red then restored byte-identical (see Verification). Matrix rows: Pre-mark/Post-mark/No header mark (real) by TestTimerRowsAroundTheMark; Boundary, Other config, Other text, Alert type, No header mark by TestOtherRowsKept; the SQL-failure row is unchanged code, not exercised by a new test.

Residual risks: AC3's planted-timer 20-of-20 run on `Runners` is the lead's step and is not recorded here. In `TestTimerRowsAroundTheMark` timer A (8 s) must wake after the marks are taken, which holds unless the host stalls the test for several seconds between planting and the marks. Design decisions D1-D5 stand as written.
