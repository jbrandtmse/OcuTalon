# Story 7.11 (DW-675): the alarm job's schedule call inside the snapshot window - evidence (implement stage, 2026-11-08)

Class paths that do not start with `src/` are under `src/ocutalon/cls/OcuTalon/`. IRIS sources are cited by their repo-relative `irislib/` path and paraphrased.

## The CI occurrences and the cause
`Test/Fix/DryRun.cls` `TestFiftyOrdersChangeNothing` and `Test/Watch/GoodMessages.cls` `TestFewerThanTwentyGood` went red when `Snapshot.Diff` reported
`<ns> header <id> is new: session <s>, from Ens.ScheduleService to Ens.ScheduleHandler`. Seen on three heads: Story 7.8's fresh check (header 564), OCT-epic17
321dcad7 (twice) and OCT-epic32 cf04f99a (run 42472273728); it blocked the merges of Epic 17 and Story 32.6.

When `Ens.Alarm` cannot open a timer's request header, it logs an error and jobs off `Ens.ScheduleService.CallScheduleService()` to ask the schedule handler to
re-check the production (`irislib/Ens/Alarm.cls` about 94-112). `CallScheduleService` creates the business service and runs `ProcessInput`, whose `OnProcessInput`
sends one async request to `Ens.ScheduleHandler` (`irislib/Ens/ScheduleService.cls` 8-22). That is one new header, in a new session, at a time no test controls.
Both hosts are auto-added to every production (`irislib/Ens/Director.cls` 761-767), so it can happen in OCUTALON and OCUORDERS alike.
`Ens.ScheduleHandler.OnRequest` runs `UpdateProduction`, which first calls `Ens.Director.UpdateProduction`; it sends a request to `Ens.Alarm` only when that update fails
or an enabled item has a `Schedule` (`irislib/Ens/ScheduleHandler.cls` 14-81). No item sets one, in OCUTALON (`Production.cls` 90-92) or OCUORDERS (`Demo/Orders/Production.cls`).
Such a follow-on request is not excused and still gives a line. `recreatePrimaryRequestHeader` (`irislib/Ens/ScheduleHandler.cls` 579-585) builds a header with the same source and target.

## The rule (test-only, `Test/Fix/Snapshot.cls`)
`DiffCategory` leaves out a header whose `SourceConfigName` is `Ens.ScheduleService` and whose `TargetConfigName` is `Ens.ScheduleHandler` (`SCHEDULESERVICE`, `SCHEDULEHANDLER`), in every namespace:
- a new one (beside the allowed-session check, before the `Ens.Alarm` wake-up check);
- a changed one when both the before row and the after row are such a header (any change of the row: it completes, or ends in another status).
Still a line: such a header missing after, another target, another source, the reverse direction, any other header of the call's session, and a header that stops (or starts) being such a header.
`SnapshotDiff.TestScheduleWritesAreNotChanges` pins each of these, in OCUTALON and in another namespace; the HeartbeatIn, allowed-session and running-timer rules are unchanged.
AD-16: a schedule call's header has no body (`OnProcessInput` sends `$$$NULLOREF`), and `Fix/Executor.cls` `Resend` copies only a header whose body it can read (else code
`body`), so the fix never writes such a header and the rule cannot hide a change the fix makes.

## The forced-condition harness (untracked `Test/Fix/ZzScheduleWindow.cls`, deleted)
Warm lane-A stack, `ITERATIONS = 20`. Method body (the strict variant; the old-code run and the first fixed run asserted `planted >= 1` in its place and had no `newTotal` assertion):
```
Method TestPlantedScheduleCall()
{
	For n = 1:1:..#ITERATIONS {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
		Do rs.%Next()
		Set top = +rs.%GetData(1)
		Do ##class(OcuTalon.Test.Fix.Snapshot).Take($ListBuild($Namespace, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE), .before)
		Do $$$AssertStatusOK(##class(Ens.ScheduleService).CallScheduleService(), "iteration "_n_": the schedule call ran")
		Do ##class(OcuTalon.Test.Fix.Snapshot).Take($ListBuild($Namespace, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE), .after)
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Ens.ScheduleService' AND TargetConfigName = 'Ens.ScheduleHandler'", top)
		Do rs.%Next()
		Set planted = +rs.%GetData(1)
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ?", top)
		Do rs.%Next()
		Set newTotal = +rs.%GetData(1)
		Do $$$AssertEquals(planted, 1, "iteration "_n_": the forced condition held ("_planted_" planted)")
		Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
		Do $$$AssertEquals(lines.%Size(), 0, "iteration "_n_": no line: "_lines.%ToJSON())
		Do $$$AssertEquals(newTotal, 1, "iteration "_n_": exactly one new header in OCUTALON")
		Do $$$LogMessage("iteration "_n_": planted="_planted_" newHeadersInOCUTALON="_newTotal_" lines="_lines.%ToJSON())
	}
}
```
- Old `Snapshot.cls`: red 20 of 20. Every iteration gave exactly one line, the planted header's, with no other line:
  `OCUTALON header 5 is new: session 5, from Ens.ScheduleService to Ens.ScheduleHandler` (iteration 1; headers 5 to 24 over the 20 iterations). The "forced condition held" assertion passed each time.
- With the fix: 20 of 20 green. A stricter run of the same harness asserted that each iteration planted exactly 1 header and wrote exactly 1 new header in OCUTALON (planted = 1 and new headers = 1, 20 of 20). OCUORDERS gave no line either; the harness calls `CallScheduleService` in OCUTALON only, so OCUORDERS got no schedule call, and the rule there is pinned by SnapshotDiff's rows only.
  In these runs the schedule call wrote only that one header (new headers counted in OCUTALON), so the rule had no follow-on write to excuse.

## Mutations (Rule 19; warm SnapshotDiff call, then revert with shasum, `git status --short` and `git diff --stat` identical, class green again)
- mutation: deleted the new-header `If ..ScheduleWrite(columns) Continue` line in `DiffCategory` -> `TestScheduleWritesAreNotChanges` red: 3 FAIL lines (the new header gives a line in OCUTALON and in ZZNS, and the same-session case gives 2 lines). Reverted: `IDENTICAL`, SnapshotDiff passed.
- mutation: `ScheduleWrite` tests the source only -> `TestScheduleWritesAreNotChanges` red: 3 FAIL lines (other target, a header that stops being a schedule call's, and one that becomes one). Reverted: `IDENTICAL`, SnapshotDiff passed.

- mutation (review pass): deleted the changed-row `Continue` line in `DiffCategory` -> `TestScheduleWritesAreNotChanges` red: 4 FAIL lines (a header that was in before and completes, and one that ends in another status, in OCUTALON and ZZNS). Reverted: `IDENTICAL`, SnapshotDiff passed.
- mutation (review pass): `ScheduleWrite` tests the target only -> `TestScheduleWritesAreNotChanges` red: 1 FAIL line (a new header from another source to the schedule handler). Reverted: `IDENTICAL`, SnapshotDiff passed.

Re-run at code review (warm lane-A, after the negative cases moved into the OCUTALON and ZZNS loop; each reverted with shasum, `git status --short` and `git diff --stat` identical, SnapshotDiff green again):
- delete the new-header `Continue` line: 4 FAIL lines (the new header and the same-session case, in each namespace).
- `ScheduleWrite` tests the source only: 6 FAIL lines (other target, stops being one, becomes one, in each namespace).
- delete the changed-row `Continue` line: 4 FAIL lines (completes, ends in another status, in each namespace).
- `ScheduleWrite` tests the target only: 2 FAIL lines (other source, in each namespace).
- `ScheduleWrite` also accepts the reverse direction: 2 FAIL lines (the reverse-direction case, in each namespace).
- `DryRun` passed on the same stack afterwards (7.01 s).

## What was not investigated
Which timer lost its request header in the three CI occurrences, and why, was not investigated: the story excuses the alarm job's schedule call in the oracle, as the Planner scoped it, and does not explain the trigger. The harness plants the header with the same call the alarm job makes, so it proves the rule against a real window, not the origin of the trigger.
The changed-row excusal covers any change between two such rows (it completes or ends in another status); `SnapshotDiff` pins status 2 to 9 and 2 to 6. It has no real-window
run: `Take` waits for empty queues first, so every planted header was new and complete in "after", and only the new-header line ran.
The queue counts are read after the headers in `TakeIn`, and the rule excuses no queue: a schedule call that lands after the queue wait while the handler has not yet
taken it gives `<ns> queues Ens.ScheduleHandler changed` (not seen in the three CI occurrences; inference).

## Callers run (warm lane-A stack, after the review patches, one per call)
`SnapshotDiff` 0.02 s, `DryRun` 6.41 s, `GoodMessages` 112.44 s, `Execute` 52.01 s, `Raise` 59.17 s, `Refused` 3.21 s, `Runs` 60.57 s and `Recheck` 1.63 s: each `CLASS ... passed`, no `FAIL` line. (Before the review patches: `DryRun` 7.67 s, `GoodMessages` 107.57 s, `Execute` 52.39 s, `Raise` 61.66 s, `Refused` 3.36 s, `Runs` 59.68 s, `Recheck` 1.93 s, all passed.)
