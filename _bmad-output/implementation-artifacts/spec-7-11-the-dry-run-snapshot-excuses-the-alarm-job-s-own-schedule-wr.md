---
title: "Story 7.11: The dry-run snapshot excuses the alarm job's own schedule writes (DW-675)"
type: 'bugfix'
created: '2026-11-08'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The "nothing changed" tests (`OcuTalon.Test.Fix.DryRun` `TestFiftyOrdersChangeNothing`, `OcuTalon.Test.Watch.GoodMessages` `TestFewerThanTwentyGood`) go red when IRIS's alarm job starts a schedule call inside the snapshot window (DW-675). When `Ens.Alarm` finds a timer whose request header cannot be opened, it jobs off `Ens.ScheduleService.CallScheduleService()`, which sends one new header from `Ens.ScheduleService` to `Ens.ScheduleHandler` in a new session, at a time no test controls. `Snapshot.Diff` counts it as a change of the fix. It has been seen in CI on three heads (7.8's fresh check, header 564; OCT-epic17 321dcad7 twice; OCT-epic32 cf04f99a, run 42472273728), and it blocks the merges of Epic 17 and Story 32.6.

**Approach:** A test-only change to the shared oracle `OcuTalon.Test.Fix.Snapshot`: `DiffCategory` also leaves out a header whose source is `Ens.ScheduleService` and whose target is `Ens.ScheduleHandler`, in any namespace. It excuses such a header when it is new, and a change of one that was already in "before" (it completes). It excuses nothing else. A stack-free pinning test in `OcuTalon.Test.Fix.SnapshotDiff` covers the rule and its negative cases. An untracked forced-condition harness plants a real header inside a real Take window: the old code gives a line, and the fix passes 20 of 20.

## Boundaries & Constraints

**Always:**
- The excusal needs the exact source `Ens.ScheduleService` and the exact target `Ens.ScheduleHandler` on the same header row. A header from `Ens.ScheduleService` to any other target, one from any other source to `Ens.ScheduleHandler`, one from `Ens.ScheduleHandler` to `Ens.ScheduleService`, any other header in the planted header's session, and such a header missing after each still give a line.
- The HeartbeatIn-session, allowed-session and `Ens.Alarm` running-timer rules behave byte-for-byte as before. The new rule sits beside them in `DiffCategory`. Its two config names are class parameters beside `HEARTBEAT` and `ALARM`.
- The Snapshot class description documents the new excusal, and SnapshotDiff's description lists the new test. Comments state the contract and never the history (Rule 14). Code is ASCII only.
- The evidence file cites IRIS sources by repo-relative `irislib/...` path and line, and paraphrases them. It never copies InterSystems code. Paths in the spec and the evidence are repo-relative or placeholders (`test-boundaries.sh` scans them).
- IRIS work runs only on lane-A throwaways through `ci/iris.sh` and `ci/warm.sh`, with the lane values on every call (see Verification).

**Never:**
- No change outside `src/ocutalon/cls/OcuTalon/Test/Fix/Snapshot.cls`, `src/ocutalon/cls/OcuTalon/Test/Fix/SnapshotDiff.cls` and this story's implementation artifacts. That rules out product code, `Test/Watch/GoodMessages.cls`, `Test/Fix/DryRun.cls` and the other callers, `Test/Checks/Snapshot.cls` (an unrelated heartbeat snapshot), `ci/`, `docker/`, `release/*.sh`, `eval/` and the IPM scripts.
- Don't widen or excuse by session, and don't excuse a follow-on write of the schedule call. If the harness shows any line other than the planted header's under the fix, stop with `## Clarification Needed` and don't widen the rule.
- Don't delete, loosen or reorder any existing assertion, and don't add or raise a timeout, wait, skip or retry.
- Never use the dev slot `ocutalon-slot-a` or any other instance. Never use a real model key.
- Don't commit the forced-condition harness.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Alarm job's schedule call inside the window (DW-675) | "after" adds a header with source `Ens.ScheduleService` and target `Ens.ScheduleHandler`, in OCUTALON or in any other namespace | No line | The old code gives `<ns> header <id> is new: session <s>, from Ens.ScheduleService to Ens.ScheduleHandler` |
| Such a header completes (DW-675) | The header is in "before" (status 2, Queued) and "after" (status 9, Completed), with the same source and target in both rows | No line | — |
| Such a header missing after | The header is in "before" and not in "after" | One line: `headers <id> is missing after` | — |
| Other target, other source, or reverse direction | A new header from `Ens.ScheduleService` to `Other`, from `Other` to `Ens.ScheduleHandler`, or from `Ens.ScheduleHandler` to `Ens.ScheduleService` | One line each, with its text checked | — |
| The rest of the schedule call's session | A new header from `Ens.ScheduleService` to `Ens.ScheduleHandler`, plus a new header from `A` to `B` in the same session | One line, for the `A` to `B` header | — |
| A changed row that is no longer a schedule write | In "before" the header goes from `Ens.ScheduleService` to `Ens.ScheduleHandler`; in "after" it goes from `Ens.ScheduleService` to `Other` | One line: `headers <id> changed` | — |
| Real window (forced condition) | Warm lane-A stack with the production running: Take "before", `Ens.ScheduleService.CallScheduleService()` in OCUTALON, Take "after" | At least one planted header is present, and Diff gives no line, 20 of 20. The old code gives the planted header's line | Any other line under the fix: `## Clarification Needed` |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Test/Fix/Snapshot.cls`: the oracle, and the file this story changes.
  - Class description 3-18. Its bullets 9-11 cover new headers, allowed sessions and HeartbeatIn, and 13-17 cover running timers. Add the new rule as its own bullet after 17.
  - Parameters `HEARTBEAT` (26) and `ALARM` (29). Add `SCHEDULESERVICE` and `SCHEDULEHANDLER` after `ALARMIN` (32).
  - `DiffCategory` 161-198. The changed-row branch is 169-171 (`If $Data(pending(key)) Continue`). The new-header loop is 182-197: allowed sessions at 188, the `ALARM` wake-up at 189-192, and the line text at 193.
  - `Column(columns, name)` 218-229 reads a header row's column. Pass it `$Piece(value, $Char(30), 1)`, as the loop does at 186.
- `src/ocutalon/cls/OcuTalon/Test/Fix/SnapshotDiff.cls`: the stack-free tests, which this story extends.
  - Description 1-15, with one bullet per test.
  - Helpers: `Row(session, source, target, status)` 33-45, `TakenIn` 25-31, `Lines(namespace, was, now)` 102-106, and `One(lines)` 108-112, which checks a single line's text.
  - Follow the shape of `TestRunningTimersAreNotChanges` 114-171.
- Callers (read-only). These are the `Consumed-by` list.
  - `Test/Fix/DryRun.cls` 99-114: Take of `$Namespace` and ORDERS, then `Diff(before, after, session)`.
  - `Test/Watch/GoodMessages.cls` 188-193: the same shape.
  - `Test/Fix/Execute.cls` 55-299, `Raise.cls` 72-212, `Refused.cls` 45-113, `Runs.cls` 220-253 and `Recheck.cls` 67-212.
  - Each asserts `lines.%Size() = 0`, so an extra excusal cannot turn any of them red. No test asserts a line for a ScheduleService header: `grep -rn ScheduleService src/` finds only `Test/Schedule/Heartbeat.cls`'s idle wait and `Test/Agent/ErrorRowsMark.cls`'s log text.
- IRIS sources, read-only. They are gitignored, so search them with an explicit path (CLAUDE.md).
  - `irislib/Ens/Alarm.cls` about 94-112: an unopenable request header leads to `$$$LOGERROR` and `Job ##class(Ens.ScheduleService).CallScheduleService()`.
  - `irislib/Ens/ScheduleService.cls` 8-22: `CallScheduleService` runs `CreateBusinessService("Ens.ScheduleService")` and `ProcessInput`, and `OnProcessInput` sends `SendRequestAsync("Ens.ScheduleHandler", $$$NULLOREF)`.
  - `irislib/Ens/Director.cls` 761-767: `Ens.ScheduleService` and `Ens.ScheduleHandler` are auto-added to every production, so they exist in OCUTALON and OCUORDERS alike.
  - `irislib/Ens/ScheduleHandler.cls` 14-18 and 26-81: `OnRequest` leads to `UpdateProduction`, which sends an `Ens.Alarm` request only when an enabled item has a `Schedule`. 579-585: `recreatePrimaryRequestHeader` also builds a header with this source and target.
- `src/ocutalon/cls/OcuTalon/Production.cls` 90-92: no item sets a `Schedule`. So the planted call should write only the one header (inference until the harness measures it).
- `ci/warm.sh` (usage 1-35) and `ci/iris.sh` (usage 1-51). `class` accepts any non-abstract class with a `Method Test...` under `Test/<Area>/`, whether or not it is tracked (428-436). The warm stack mounts `./src` and reloads new or changed classes.
- `_bmad-output/implementation-artifacts/evidence/7-10/cause.md`: the shape to follow for this story's evidence. Read-only.

## Tasks & Acceptance

**Execution:**
1. Start the warm lane-A stack (Verification). Write the untracked harness `src/ocutalon/cls/OcuTalon/Test/Fix/ZzScheduleWindow.cls`, which `Extends %UnitTest.TestCase`.
   - It has `Parameter ITERATIONS = 20` and one method `TestPlantedScheduleCall`.
   - Each iteration:
     - Read the highest header id with `%SQL.Statement` (never `&sql`).
     - `Snapshot.Take($ListBuild($Namespace, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE), .before)`.
     - Run `$$$AssertStatusOK(##class(Ens.ScheduleService).CallScheduleService(), ...)`.
     - Take "after".
     - Count the headers above that id with this source and target, and assert there is at least 1 ("the forced condition held").
     - Assert that `Diff(before, after).%Size() = 0`, with the lines' JSON in the message.
     - `$$$LogMessage` the iteration, the planted count and the lines.
   - Run it once against the unchanged Snapshot. It is the old code, so expect red in every iteration whose planted count is at least 1, each with the planted header's line. Record the k-of-20 count and one line. This is the forced condition's old-code red (DW-675). It also measures whether the schedule call writes anything else (Never list).
2. `src/ocutalon/cls/OcuTalon/Test/Fix/Snapshot.cls`: add the excusal (DW-675).
   - Add the parameters `SCHEDULESERVICE = "Ens.ScheduleService"` and `SCHEDULEHANDLER = "Ens.ScheduleHandler"`, each with a one-line doc comment.
   - Add a private `ScheduleWrite(columns) As %Boolean`: the row's `SourceConfigName` is `SCHEDULESERVICE` and its `TargetConfigName` is `SCHEDULEHANDLER`.
   - In `DiffCategory`'s changed-row branch, when the category is `headers`, `Continue` if both the before row and the after row are schedule writes.
   - In the new-header loop, `Continue` if `ScheduleWrite(columns)`. Put it after the allowed-session check and before the `ALARM` wake-up check.
   - Add a class-description bullet that states the rule, its namespace independence, what it leaves out (new, completing) and what still counts (missing after, other target, other source, the rest of its session). Name `Ens.Alarm`'s job off `Ens.ScheduleService.CallScheduleService()` as the writer.
3. `src/ocutalon/cls/OcuTalon/Test/Fix/SnapshotDiff.cls`: add `TestScheduleWritesAreNotChanges`, which covers every hand-made row of the I/O matrix (DW-675).
   - Use `Row`, `Lines` and `One`, with the names taken from `##class(OcuTalon.Test.Fix.Snapshot).#SCHEDULESERVICE` and `#SCHEDULEHANDLER`.
   - Cover OCUTALON and `ZZNS`.
   - Check the line text of the other-target, other-source, reverse, same-session, missing and changed cases.
   - Add one description bullet for the test.
4. Run the harness again after the fix: 20 of 20 green, with at least one planted header in each iteration. If one call nears 150 s, set `ITERATIONS` to 10 and run the class twice. Then delete `ZzScheduleWindow.cls`, so the tree holds only the reviewed files. The next warm run deletes the class from the stack.
5. `_bmad-output/implementation-artifacts/evidence/7-11/cause.md`: a new file of about 40 lines, in the 7-10 shape. It covers:
   - The CI occurrences and the cause, cited from the irislib anchors above and paraphrased.
   - The rule and its exact scope.
   - The harness, its method body in a fenced block (our code), and both runs (old code k of 20 red with one line, and the fix 20 of 20 with the planted counts).
   - The two mutations.
   - The callers that were run.

**Acceptance Criteria:**
- Given "before" and "after" snapshots that differ only by a new header from `Ens.ScheduleService` to `Ens.ScheduleHandler`, when `Snapshot.Diff` compares them, then it gives no line. Both of these show it: `TestScheduleWritesAreNotChanges` passes, and the real-window harness gives the old code's line and then the fix's 20 of 20 with the header planted each time (DW-675).
- Given a header from `Ens.ScheduleService` to any other target, from any other source to `Ens.ScheduleHandler`, or any header that counts today, when `Diff` compares the snapshots, then each still gives its line: the matrix's negative rows and the unchanged `TestNewHeaders` and `TestRunningTimersAreNotChanges` pass. Removing the new-header excusal turns `TestScheduleWritesAreNotChanges` red (DW-675).
- Given the snapshot's consumers `DryRun`, `GoodMessages`, `Execute`, `Raise`, `Refused`, `Runs` and `Recheck`, when each runs once on the warm lane-A stack after the fix, then each prints `CLASS <name> passed` with no `FAIL` line. The lead's fresh check runs them forward and reversed (DW-675; Integration AC).
- Given the change, when `git diff --stat` is read, then only `Snapshot.cls`, `SnapshotDiff.cls`, `evidence/7-11/cause.md` and this spec differ, and no existing `$$$Assert*` line of `SnapshotDiff.cls` changed.

## Spec Change Log

## Review Triage Log

## Design Notes

- **Architecture decisions (Rule 6).**
  - AD-16: the dry run changes nothing, and this oracle is what proves it. `FixExecutor`'s writes are resends and FixResults to its own targets, never a header from `Ens.ScheduleService` to `Ens.ScheduleHandler`. So the excusal cannot hide a fix's change, and AD-16's Prevents line is kept.
  - AD-22: tests are `%UnitTest` classes under `OcuTalon.Test.<Area>` and run only in throwaways and CI.
  - AD-29: `Test/Fix` belongs to lane A.
  - No AC contradicts an AD.
- **Extend, don't copy (Rule 2).** The rule extends `Snapshot.DiffCategory` beside the HeartbeatIn and `Ens.Alarm` excusals and reuses `Column`. The new test extends `SnapshotDiff` with `Row`, `Lines` and `One`. The harness is a scratch copy of a caller's Take, Diff and assert, and is never committed.
- **Integration ACs (Rule 1).** This story changes an existing shared test helper and adds no service. AC 3 is the Integration AC, run against a real production.
  - Consumed-by: `OcuTalon.Test.Fix.DryRun`, `Test.Watch.GoodMessages`, `Test.Fix.Execute`, `Raise`, `Refused`, `Runs`, `Recheck` and `SnapshotDiff`: each Diff of a "nothing changed" proof.
  - Consumes: `Ens.MessageHeader`'s SQL columns, through `Column`.
- **Decided in-stage.**
  - (1) A change of a schedule-write header that was already in "before" is excused when both rows have the source and target. It is the same background writer completing its request, as the `Ens.Alarm` running-timer rule excuses a request's completion. A "missing after" stays a line.
  - (2) The excusal is per header, never per session, because the Planner's scope says "nothing else". Other headers in the schedule call's session still count.
  - (3) The rule holds in every namespace the snapshot covers (the lead's decision): `Ens.ScheduleService` and `Ens.ScheduleHandler` are auto-added to every production.
  - (4) The forced-condition harness is an untracked scratch class, run on the warm stack and deleted before finalize, as in Story 7.10. A committed method would run `Ens.ScheduleHandler`'s `UpdateProduction` 20 times in the shards job, and SnapshotDiff is stack-free by contract. The harness source is kept in `evidence/7-11/cause.md`.
  - (5) The callers' assertion messages ("and a timer that was already running") are left as they are. The Snapshot class description is the contract, and the callers are outside the footprint.
  - (6) The harness plants the header with `CallScheduleService()`, the exact path the alarm job takes.
- **NFRs (Rule 5).** No NFR is touched.
- **Ledger inbox.** DW-675 is addressed by Tasks 1-5 and every AC. DW-868 and DW-639 stay out of scope.

## Verification

`<laneA>` stands for `env OCUTALON_LOCK_DIR=<lock-dir>/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=7 stage=<stage>'`, run from the worktree root. `<lock-dir>` is the main checkout's `.worktrees/.coordination/locks`. The warm tag is `e7s11implw`.

Rules for every command:
- One command per foreground call, with `timeout: 600000`, sized to finish in about 150 s.
- Never two IRIS test runs in one message.
- Lane-A throwaways only, never `ocutalon-slot-a`.
- The lane-a lock is shared with Epic 41. A `LOCK waiting` line, or exit 75 from `warm.sh up`, is normal: wait 30-90 s and retry.

**Commands:**
- (once) `<laneA> OCUTALON_RUN_TAG=e7s11implw ci/warm.sh up`. It takes about 60-100 s.
- (loop) `<laneA> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s11implw ci/iris.sh class OcuTalon.Test.Fix.ZzScheduleWindow`.
  - Before the fix, expected red: `FAIL` lines with the planted header's line.
  - After the fix, expected `CLASS ... passed`, 20 of 20, with an estimated 40-90 s (inference).
- (loop) `<laneA> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s11implw ci/iris.sh class OcuTalon.Test.Fix.SnapshotDiff`. It takes a few seconds. Expected: `CLASS OcuTalon.Test.Fix.SnapshotDiff passed`, with no `FAIL`.
- (once) The same warm `class` call for each of `OcuTalon.Test.Fix.DryRun`, `OcuTalon.Test.Watch.GoodMessages` (about 115 s), `OcuTalon.Test.Fix.Execute`, `OcuTalon.Test.Fix.Raise` (61-147 s measured), `OcuTalon.Test.Fix.Refused`, `OcuTalon.Test.Fix.Runs` and `OcuTalon.Test.Fix.Recheck`, one per call. Expected: `passed` each.
- (once) `<laneA> OCUTALON_RUN_TAG=e7s11implw ci/warm.sh down` at the end, also after a failure. If it fails, run `<laneA> OCUTALON_RUN_TAG=e7s11implw ci/iris.sh teardown`.
- (once) After the harness is deleted, run `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh`, one call each. Expected: PASS.
- (once) `git status --short` and `git diff --stat`. Expected: only the files of AC 4, and no `ZzScheduleWindow.cls`.

**Mutations (Rule 19).** Before each one, record `shasum` of `Snapshot.cls`, `git status --short` and `git diff --stat`. Apply the change, run the warm SnapshotDiff call, revert, and confirm that all three match. A red counts only if the class is green again on the same stack after the revert.
- mutation: delete the new-header `If ..ScheduleWrite(columns) Continue` line in `DiffCategory` → `TestScheduleWritesAreNotChanges` red at the "no line" assertion for a new header from `Ens.ScheduleService` to `Ens.ScheduleHandler` (AC 1). The harness's old-code run is this same red on a real window.
- mutation: make `ScheduleWrite` test the source only, dropping the target condition → `TestScheduleWritesAreNotChanges` red at the other-target line (AC 2).

**Fresh-environment check (the lead's; Rule 19 and Rule 21).** Use fresh lane-A throwaways, never warm, forward and then `--reverse`.
- Run `ci/iris.sh class OcuTalon.Test.Fix.SnapshotDiff`.
- Run `ci/iris.sh shard lane-a@Fix --part k/n`, with n sized so that each part's start and tests fit about 150 s. The Fix area's classes include SnapshotDiff and every Fix caller.
- `OcuTalon.Test.Watch.GoodMessages` takes about 115 s plus a fresh start, which goes past one call's budget. It runs in a split the lead's harness allows, or in CI's `shards` job.

**Shared surfaces:** `OcuTalon.Test.Fix.Snapshot.Diff`'s lines, which every caller asserts to be empty. The change only removes lines, and no test asserts a schedule-write line.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
