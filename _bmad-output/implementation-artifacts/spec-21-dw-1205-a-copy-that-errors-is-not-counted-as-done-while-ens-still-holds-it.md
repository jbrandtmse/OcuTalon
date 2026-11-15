---
title: 'DW-1205 + DW-494: A copy that errors is not counted as done while Ens still holds it'
type: 'bugfix'
created: '2026-11-15'
status: 'done'
baseline_revision: 'd15f7e86116144f32f39b7bfc9328eb388d969f8'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-dw-1391-the-asked-fixture-is-not-quiet-so-the-sweep-cannot-close-it.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1205 and DW-494, one product race; Contest Planner ruling ~17:20Z Nov 15: "Investigate BOTH together. If they share a cause, fix both in one change"):** a run whose copies all fail again can end with one copy counted as completed.
- When a copy errors, Ens first sets its header Completed (9) and only then Error (8): `irislib/Ens/Actor.cls:452` then `:483` for a business process, `irislib/Ens/BusinessOperation.cls:384` then `:412` for an operation. Each is an SQL `UPDATE` of the header (`Ens/MessageHeader.cls` `SetStatus` `:160`), committed at once. Through the whole window the header is still the job's active message, `^Ens.ActiveMessage(<system>:<job>)`, which Ens kills only after the handler returns (`Ens/Host.cls` `OnTask` exit `:646`).
- `Fix.Executor.Look` (`Fix/Executor.cls:1013`) reads the copies through `Read` (`:1067`, which calls `Watch.Reader.Evidence`, `:1075`). `Tally` (`:1034`) counts a status of `Completed` as a finished copy (`:1045`). When no copy is left running (`:1024`), `Look` ends the run through `Finish` (`:1028`).
- So a read that lands in the window ends a run whose three copies all fail as 3/3/1/2/0 instead of 3/3/0/3/0. The wrong counts reach the FixRun row, the final FixResult, the user's notice, the Action audit entry and `/state`.
- `Fix.Run.Sweep` uses the same `Read` and `Tally` (`Fix/Run.cls` `EndMarked` `:283`, `EndLeft` `:318`, `Statuses` `:415-418`), so it has the same exposure.
- Measured in the investigation (a throwaway-only probe built from the product's own `Reader.Evidence` and `Executor.Tally`): 7 of 300 trials wrong unloaded (2.3%), 14 of 300 under load (4.7%). At test level it was 0 of 75 locally, where copies settle in about 2 ms.
- DW-494 (`Test.Fix.Partial` `TestCopiesFailAgain` and `TestSomeFailAgainAndSomeHadChanged`, 10 occurrences on runners ci-3 to ci-20, across shards-2 and shards-11) and DW-1205 (`Test.Fix.Reroute` `TestFailedAgainIsNotRetried`, two reds: ci 43235350028 and ci 43728223291 on ocutalon-ci-16) have this one cause. Every red fails only the count-derived asserts. The +20 s on those runs is `WaitResultOf` waiting out its hold.

**Approach (one product change for both):**
- **The reader says when Ens still holds a header.** In `Watch.Reader.Current`, evidence branch, each failure gains `inFlight`, a JSON boolean. It is 1 when, after the header's row was read, the header id is the value of some `$$$EnsActiveMessage(job)` of the namespace, or when a second read of the header's status, made after that check, gives another status. The order is what makes it complete: Ens sets Completed, then Error, then kills the entry. So a Completed read whose entry is already gone is always followed by an Error that the second read sees.
- **The executor counts a copy that is in flight as running.** `Fix.Executor.Read` carries `inFlight` into each statuses entry. `Tally` counts a copy as running when its entry is in flight, whatever its status. `Look`, `Pass`, `Progress` and both Sweep branches need no change of their own, because they all count through `Tally`.

## Boundaries & Constraints

**Always:**
- **Footprint (all Lane A packages, AD-29; lane C makes the edits, see Veto item 2):**
  - `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`: `Current`, evidence branch: the `inFlight` member; the class doc's Evidence and Good bullets; the doc of `Current`.
  - `src/ocutalon/cls/OcuTalon/Fix/Executor.cls`: `Read` carries `inFlight`; `Tally` counts an in-flight copy as running; the class doc (the wait bullet) and the docs of `Read` and `Tally`.
  - Tests: `src/ocutalon/cls/OcuTalon/Test/Fix/Executor.cls` (two new methods, header bullets) and `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls` (one new method, its cleanup, a header bullet).
  - The spine record: `ARCHITECTURE-SPINE.md` AD-16, one sentence added, word for word as in Design Notes (Veto item 4).
  - This spec.
- The namespace switch stays in `Current` alone (AD-3). While it is in the production's namespace, `Current` calls no OcuTalon class, so the check is inline code there. It reads the global through the `$$$EnsActiveMessage` macro of `Ensemble.inc`, which `Reader` already includes, and never spells out `^Ens.ActiveMessage`.
- `inFlight` is set with `%Set("inFlight", <0 or 1>, "boolean")`, as `isError` is (`Reader.cls:798`). It is on every failure of an evidence read, so `Good`'s failures carry it too.
- An entry of the statuses with no `inFlight` member (the probes' canned statuses) is not in flight. Every existing test keeps its statuses and passes unchanged.
- ObjectScript stays ASCII. Comments state the contract, not review history.

**Never:**
- Change `Fix/Run.cls`, `WAITSECONDS`, `WAITPAUSE`, `COPYDONE`, `COPYFAILED`, the FixResult, the FixRun class, any catalog key or text, or `Watch.EvidencePack`.
- Store `inFlight` anywhere: not in a FixRun, an ApprovalRequest, a FixResult or a log line. It lives only in the transient snapshot and statuses objects.
- Write, kill or lock any Ens global from product code. The reader only reads.
- Delete, skip, tag off or weaken a test.

## I/O & Edge-Case Matrix

Copies are header ids registered on a FixRun. "Held" means that the header id is the value of some `$$$EnsActiveMessage(job)` in the production's namespace.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 The race (DW-1205, DW-494) | 3 copies that all fail again. At one pass, copy 1 reads Completed and is held; copies 2 and 3 read Error. | Copy 1 is `inFlight` 1, so `Tally` gives running 1 and the run does not end. At the next pass copy 1 reads Error and is not held: the run ends 3/3/0/3/0 with the reason of the lowest failed copy. | none |
| 2 Completed and let go | Status Completed, not held, and the second read is still Completed. | `inFlight` 0; completed, as today. | none |
| 3 Changed between the reads | Status Completed at the first read; the entry is gone at the check; the second read gives Error. | `inFlight` 1 (running); the next pass counts it from its new status. | none |
| 4 A success still held | Completed and held (between `SetStatus(9)` and the kill at `OnTask`'s exit). | Running for one more pass (`WAITPAUSE` 0.5 s), then completed. Same counts as today. | none |
| 5 An error still held | Error and held. | Running for one more pass, then failed again. Same counts as today. | none |
| 6 A job that hangs while it holds a copy | Held past `WAITSECONDS` (60 s). | Running. The waiter sends its one progress FixResult (Final 0, `result.stillResending`) and logs `LOGWAIT`, exactly as for a copy that is still queued. Sweep leaves the run while the copy is in flight and ends it once Ens lets go of the header, or recovers it to its queue (`Ens/Job.cls:416-419`, `Ens/Director.cls:394-397`) and it runs to an end. | none |
| 7 A marked run (restart) | `Fix.Run.EndMarked` with a copy in flight. | Counted as running, so it is one of the targets cut off (Interrupted). At a start Ens recovers every active message and kills its entry (`Ens/Director.cls:394-397`), so only a copy taken up again after the start can be in flight. | none |
| 8 The read is not read | outcome `unreadable`, `not_current` or a throw. | Unchanged: every copy is running (Tally), and Sweep leaves the run. | as today |
| 9 Other Evidence and Good callers | `Watch.EvidencePack`, `Fix.Kind` (dry run, re-check), `RepairResend` (Good), `Eval.Record.Capture`. | Each failure gains `inFlight`. None reads it. The pack, the dry run and the re-check are unchanged (each copies named fields only). A snapshot that `Eval.Record` writes from now on carries the member (an author-run file, see Veto item 3). | none |

</intent-contract>

## Code Map

Line numbers are at the baseline `f56f50d86` (23.3 merged). The investigation's numbers were taken before 23.3, which moved `Fix/Executor.cls` by +14 lines and `Fix/Run.cls` by +25. They are corrected here.

- `Watch/Reader.cls`:
  - `Include (Ensemble, EnsConstants, EnsErrors)` at L1. `$$$EnsActiveMessage` is `^Ens.ActiveMessage` (`irislib/Ensemble.inc:123`).
  - `Current` L620. The evidence branch prepares `headers` (L744-748: one row per id, with `Status` as column 12) and builds each failure at L797 (`status` from column 12), with `isError` at L798. The failure is pushed at L834.
  - Ens runtime state is already read in this method: `^Ens.Configuration("csp", "Activity", name, "stopped")` (L654), `$$$GetHostMonitor` (L685), and `$$$EnsProdModCounterGet` and `$$$EnsRuntime` (L921).
  - Class doc: Evidence bullet L42-51, Good bullet L60-63. `Current` doc L600-619.
- `Fix/Executor.cls`:
  - Class doc wait bullet L41-44 ("A copy is completed when its status is Completed ...").
  - `Look` L1013: `Tally` L1022, `running > 0` L1024, `Finish` L1028.
  - `Tally` L1032-1055 (doc L1032-1033; the `COPYDONE` branch L1045).
  - `Read` L1063-1082 (doc L1063-1066; `Evidence` L1075; the statuses entry L1079).
- `Fix/Run.cls`: `EndMarked` L262 (Tally L283), `EndLeft` L300 (Tally L318, `running > 0` L319), `Statuses` L415-418. No change.
- Tests:
  - `Test/Fix/ExecutorProbe.cls`: `StatusIs`, `StatusThen`, `ThenAfter` and `Reads` (canned reads; `Statuses` seam).
  - `Test/Fix/Executor.cls`: the two-read pattern is `TestResentRunEndsWithItsCounts` L661 (L695-718). `Canned` L2354, `CannedAt` L2576, `AssertCounted` L2242. The Sweep helpers are `UnmarkedRun` L2515 and `AssertDone` L2626, with `TestSweepEndsARunNoWaiterEnded` L1795 as the model.
  - `Test/Fix/RunProbe.cls`: `Feed` L28 and `Reads` L71.
  - `Test/Watch/Evidence.cls`: `OnAfterOneTest` L48. `Test/Watch/Case.cls`: `FixtureHeader` L1038 (Status 9 allowed), `Fixture` L932 (incident and group over headers), `MakeFixtureHeader` L1046.
- Ens order of events, verified in `irislib` at the baseline: `Ens/Actor.cls:452` (Completed) and `:483` (Error); `Ens/BusinessOperation.cls:384` (Completed) and `:412` (Error); `Ens/Host.cls:646` (kill of the entry at `OnTask`'s exit); `Ens/Queue.cls:317` and others (the entry is set at dequeue).

## Tasks & Acceptance

**Task 0 (measure first, on lane C's warm throwaway `e21dw1205iw`, before any product change; record each result under `## Verification`):**
1. **The race is still there after 23.3.**
   - Copy the investigation's scratch probe classes `ZzScratch.Race` and `ZzScratch.Probe` from the investigation's scratchpad folder `edw1205/` into your own scratchpad. Load them into the throwaway only. They are never committed and never go to a dev slot.
   - Run `##class(ZzScratch.Race).Run(300)` (unloaded) and the same under load. Use the investigation's load if its notes give it; otherwise use two JOBbed busy loops in the container for the length of the run, plus `backlog` 10, and record which load you used.
   - Expect `wrong` > 0 under load. If both runs give 0 wrong out of 300, stop with `## Clarification Needed`: the race may have gone with 23.3.
   - Also record one `ZzScratch.Probe.Watch(3)` line that shows a `9a` (Completed while held) before the `8`.
2. **The fix, measured (after the Execution tasks):**
   - In your scratch copy of `Race`, build each statuses entry as the fixed `Read` builds it (`status` and `inFlight` from the failure), and drop the scratch `fixed` emulation.
   - Run `Run(300)` unloaded and under the same load. Target: 0 wrong out of 300 under load.
   - Then drop the second status read from the product code (keep the `$$$EnsActiveMessage` check), run once more under load and record the count, then restore the product code byte for byte. This shows whether the second read is needed; see Verification on what to record when it shows 0.
3. **The time it costs.** Record the duration of `Test.Fix.Scale` (500 copies, fresh) before and after the change, as two numbers. If the after figure is more than 10% slower, add a line about it under Verification. This is not a stop condition.

**Execution:**
- [ ] `Watch/Reader.cls` `Current`, evidence branch:
  - Next to `headers`, prepare once (evidence only) a statement that reads one header's `Status` by `ID`.
  - Right after `Do failure.%Set("isError", ...)` (L798), work out `inFlight` for header `id`:
    - `$Order` over `$$$EnsActiveMessage(job)` with its value. Held when a value equals `id`.
    - If it is not held, read the header's status again with the prepared statement. In flight when the row is found and its status differs from `result.%GetData(12)`. A header that the second read no longer finds is not in flight.
    - Use locals with their own prefix (for example `flightJob`, `flightId`, `flightHeld` and `flightRead`), as the method does for `cfg*` and `st*`. An SQLCODE below 0 throws like the other reads.
  - `Do failure.%Set("inFlight", flightHeld, "boolean")`.
  - Class doc, Evidence bullet: add "Each failure also carries inFlight, a boolean: 1 when IRIS still holds the header, that is when, after its row was read, it is the active message of a job of the namespace (Ensemble.inc's EnsActiveMessage), or a second read of its status, made after that check, gives another status (IRIS sets an erroring message Completed just before Error, and lets go of it after)." The Good bullet says that its failures carry inFlight too. In `Current`'s doc, the evidence sentence names the member.
- [ ] `Fix/Executor.cls`:
  - `Read` L1079: the entry gains `inFlight` (`Do entry.%Set("inFlight", +failure.inFlight, "boolean")`, or the same in the literal). The doc lists it: "inFlight (Reader.Evidence's: 1 while IRIS still holds the copy's header)".
  - `Tally`: before the `COPYDONE` test, a copy whose entry is an object with `inFlight` true is running. The doc: "running (a copy the read gives as in flight, whatever its status; any other status, a header the read lacks, and every copy when the outcome is not read)".
  - Class doc L42-43: "A copy that the read gives as in flight (IRIS still holds its header; Reader.Evidence inFlight) is still running, whatever its status. Otherwise a copy is completed when its status is Completed and failed again when it is Error, Aborted, Discarded or Suspended; any other status, a header the read lacks and a read that does not give read are still running."
- [ ] `Test/Fix/Executor.cls` (canned, warm; header bullets for both):
  - New `TestInFlightCopyIsStillRunning` (matrix 1, 4):
    - A: an incident with the group of `ORDERDATETEXT`; 3 targets, 3 copies. First read: copy 1 is `{"status": "Completed", "error": "", "target": "OrdersFromPartner", "inFlight": true}`, and copies 2 and 3 are Error with the incident's own error. `StatusThen`, from read 2: all three Error with that error.
      - Assert `Reads` = 2 ("a copy that is Completed but still in flight is still running: the wait read twice").
      - `AssertCounted(..., "done|done|finished", "3|3|0|3|0", "the order date still wasn't accepted", ..., "0 of 3 orders went through. 3 failed again (the order date still wasn't accepted). I won't retry them without a new approval.")`.
    - B: all three Completed at read 1, copy 1 in flight; all Completed at read 2. `Reads` = 2 and 3/3/3/0/0, "All 3 orders went through."
  - New `TestSweepLeavesAnInFlightCopy` (matrix 1 on the Sweep path, `EndLeft`):
    - An unmarked run past its wait (`UnmarkedRun`, `ResentAt` `Stamp(-100)`) whose copies are `CannedAt`: copy 1 Completed with `inFlight` true, copies 2 and 3 Error with the incident's own error.
    - The first `Sweep` returns no result for it: no EndedAt, the row still executing, no Action entry.
    - After `Feed` gives all three Error, the next `Sweep` ends it with `AssertDone(..., "3|3|0|3|0", "the order date still wasn't accepted", "result.failedAgain", "0 of 3 orders went through. 3 failed again (the order date still wasn't accepted). I won't retry them without a new approval.", "done|done|finished", ...)`.
- [ ] `Test/Watch/Evidence.cls` (live, warm; header bullet):
  - New `TestInFlightHeader` (matrix 1-3 at the reader; `Executor.Read` and `Tally` live):
    - Make a Status 9 fixture header H (`FixtureHeader({"Status": 9})`) and an Error fixture header E.
    - Set a fake entry `^Ens.ActiveMessage("zzOcuTalonTest:"_$Job) = H` in OCUORDERS through a small test helper that switches namespace itself. Remember it in a property; `OnAfterOneTest` kills it, also after a failure. `zzOcuTalonTest` is no system name, so no Ens job ever reads that node as its own.
    - `Reader.Evidence(ORDERS, ORDERSPRODUCTION, "zzPollerTarget", "h<H>,h<E>", .snapshot)` is read. H is Completed with `%GetTypeOf("inFlight")` boolean and `inFlight` 1. E has `inFlight` 0, a boolean.
    - Over `..Fixture(owner, "<H>,<E>")` and an unsaved `OcuTalon.Data.FixRun` whose `Copies` are H and E, `Fix.Executor.Read` gives `statuses.<H>.inFlight` 1, and `Tally` gives completed 0, failedAgain 1, running 1.
    - After the entry is killed: `Evidence` gives H `inFlight` 0, and `Tally` gives completed 1, failedAgain 1, running 0.
- [ ] Spine (Veto item 4): the sentence under Design Notes, word for word, and `updated:` 2026-11-15 (or the day of the edit).
- [ ] This spec: the `## Verification` records (Task 0 and the mutation lines).

**Acceptance Criteria:**
1. Given a run whose copies all fail again, when a pass reads one copy as Completed while Ens still holds it, then the run does not end at that pass, and it ends 3/3/0/3/0 with the reason once the copy reads Error.
   - mutation: drop the `inFlight` test in `Tally` -> `TestInFlightCopyIsStillRunning` red ("the wait read twice": 1 read; counts 3/3/1/2/0).
2. Given a copy that completed but is still held, then the run ends one pass later with the same counts as today.
   - mutation: the same `Tally` mutation -> `TestInFlightCopyIsStillRunning` case B red (1 read).
3. Given Sweep and a run past its wait with a copy in flight, then Sweep leaves the run, and it ends the run with the right counts once no copy is in flight.
   - mutation: the same `Tally` mutation -> `TestSweepLeavesAnInFlightCopy` red (a result 3/3/1/2/0 at the first Sweep).
4. Given a header that a job holds, then `Reader.Evidence` gives it `inFlight` true as a JSON boolean, and false once the job lets go of it.
   - mutation: drop the `$$$EnsActiveMessage` loop -> `TestInFlightHeader` red ("inFlight 1 while a job holds it");
   - mutation: set the member without the "boolean" type -> `TestInFlightHeader` red ("a JSON boolean").
5. Given a held copy, then `Executor.Read` carries `inFlight` and the live `Tally` counts the copy as running.
   - mutation: drop `inFlight` from `Read`'s entry -> `TestInFlightHeader` red ("Read carries inFlight", "running 1").
6. Given a status that changes between the first read and the check (matrix 3), then the header is in flight. No test can drive this deterministically without fault injection in the reader. Its evidence is Task 0 item 2 (0 wrong out of 300 under load with the fix) and the ordering argument in Design Notes. A mutation that drops the second read is recorded under Verification with the probe's count, not with a unit test.
7. Every existing test passes unchanged: `Test.Fix.Executor`, `Test.Fix.Partial` (DW-494's two methods), `Test.Fix.Reroute` (DW-1205's method), `Test.Watch.Evidence`, `Test.Watch.Reader`, `Test.Watch.GoodMessages`, `Test.Fix.Recheck`, `Test.Eval.Record` and `Test.Fix.Scale`. The read-count asserts of `Test.Fix.Executor` (`host.Reads` = 1 or 2, `RunProbe` `Reads`) stay as they are.

## Design Notes

**Governing ADs:**
- AD-16 (the resend bullet "waits up to 60 s for each copy to complete or fail"; the Reconcile and Sweep bullet "whose registered copies have all completed or failed"; the Conventions row "Fix runs").
- AD-3 (`Watch.Reader` is the one reader of a production, and `Current` the one switching method; its list "headers, event log, settings, queues, vital signs" stays true, since this reads headers).
- AD-33 (End and Mark stay the only writers of a run's end).

Nothing in them is contradicted. AD-16 says when a copy is complete without saying how that is read, so the rule that defines it is added there (Veto item 4). No other spine record describes how copy outcomes are read.

**Why both checks, in this order.** Ens's order for an erroring copy is `SetStatus(9)`, then `SetStatus(8)`, then the kill of the active-message entry at `OnTask`'s exit. Each `SetStatus` is an SQL `UPDATE` committed at once.
- The reader reads the status first (Completed), then looks for the entry. If the entry is still there, the copy is held. If it is gone, Ens has already run `SetStatus(8)`, so the second read, made after the check, sees Error.
- The other order (entry first, status second) leaves a window: a copy taken up and erroring between the two reads would read Completed with no entry.
- A held header with no status change (a success in its last instant) costs one more pass of 0.5 s.

**Why the executor, not the reader, decides "running".** The reader reports what IRIS shows (a status, and whether IRIS still holds the header). `Tally` is the one place that turns a read into counts, for the waiter and for Sweep alike (AD-16, AD-33). So one test in `Tally` fixes the waiter (`Look`), the progress report (`Pass`, `Progress`) and both Sweep branches.

**The Sweep path (Fix/Run.cls).** Nothing beyond the same `Read` and `Tally`:
- `EndLeft` already leaves a run with a copy running (L319), so it waits for an in-flight copy and ends the run on a later Tick (matrix 6).
- `EndMarked` counts a running copy as cut off (`Interrupted` = Total - Completed - FailedAgain). That is right for a copy in flight at a sweep after a restart, and Ens's own start recovery means only a copy taken up again after the start can be in flight (matrix 7).
- `Run.cls`'s doc names `Executor.Tally` as the count, so its text stays true.

**Ens internals.** `^Ens.ActiveMessage` is not a documented API. `Reader` already reads Ens runtime state directly in the same method: `^Ens.Configuration("csp","Activity",...,"stopped")`, the host monitor (`$$$GetHostMonitor`), `$$$EnsProdModCounterGet` and `$$$EnsRuntime`. Through the macro, the global's name has one home (`Ensemble.inc`). Ens's own portal and monitor read it the same way (`EnsPortal/Queues.cls:536`, `Ens/MonitorService.cls:312`). The documented alternative, the `Ens.Job` `Enumerate` query (whose `ActiveMessage` column reads the same global, `Ens/Job.cls:864`), costs a query over every job for each header, for the same answer. If a later IRIS renames the global, the macro moves with it. If the global ever stops being written, `inFlight` falls back to the second status read alone, which narrows the window without closing it, and no test breaks silently, since `TestInFlightHeader` writes the global itself and so keeps passing.

**The entry-read seam (gate condition 2).** The entry read sits in its own Try/Catch in `Reader.Current`. A throw (`<UNDEFINED>`, `<PROTECT>` or any other) ends the loop as "not held by the entry check" and goes on to the second status read; a failed read is never "done". To test it, `Current` reads the process-private global `^||OcuTalonFlightSeam` at the entry-read point, inside the Try: when it holds code, the global is killed and the code is run with `Xecute`. A test sets it to a line that changes the header's status and throws, which is a failed entry read plus a status change between the two reads. It is five lines, calls no OcuTalon class (AD-3), writes no Ens global, and is set by no product code, so it is never set in production. `TestInFlightEntryReadFails` is its one user.

**Cost.** For each evidence header: one `$Order` pass over the active-message entries (at most one per job of the namespace) and, for a header not held, one more point read by ID. For the waiter that is per copy per pass; Task 0 item 3 measures 500 copies.

**For lane A:** DW-494's and DW-1205's tests need no change. `Test.Fix.Partial` and `Test.Fix.Reroute` go green on the product fix.

**Spine amendment (Veto item 4), word for word.** In AD-16, after the sentence "It registers each new header id, waits up to 60 s for each copy to complete or fail, and sends `FixResult` with `Total`, `Resent`, `Completed`, `FailedAgain` (with a plain reason) and `Skipped`." insert:

"A copy counts as completed or failed again only once IRIS has let go of it: while its header is still a job's active message, or its status changes while `Watch.Reader` reads it, it is still running, because IRIS sets an erroring copy `Completed` just before `Error` [ADDED 2026-11-15, DW-1205 and DW-494, Contest Planner spec-gate ruling]."

**Ledger inbox:** DW-1205 and DW-494 (this spec). Each one's status line is recorded per the run's DW process at merge.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | None. No catalog key, notice, log text or UI string is added or changed. The counts, results and notices become correct; for example "0 of 3 orders went through. 3 failed again (...)" in place of a wrong "1 of 3 orders went through. 2 failed again (...)". | Approve (nothing to rule). |
| 2 | (b) Cross-lane edits | Every product and test file is in a Lane A package (`Fix.Executor`, `Watch.Reader`, `Test.Fix.Executor`, `Test.Watch.Evidence`), plus the spine record. Lane C makes the edits under the Contest Planner's ruling (~17:20Z Nov 15: "DW-1205 is REAL ... Lane C OWNS it"), after 23.3's merge as ruled. At plan time no in-flight `OCT-*` branch touches these source files. Three branches touch the spine (`OCT-epic11`, `OCT-epic24`, `OCT-epic25-s258`), none of them in AD-16. | Approve, as the Planner's lane C assignment. The lead serializes the merge against any Lane A story that touches `Fix/Executor.cls` or `Watch/Reader.cls`. |
| 3 | (c) Stored data or schema | None. No class, property, column or storage change. `inFlight` is a transient member of the reader's snapshot JSON and of the executor's statuses object. Nothing persists either object: the FixRun stores only counts, the dry run and the re-check copy named fields, and the evidence pack copies named fields. The one writer of a whole snapshot is `Eval.Record.Capture`, an author-run tool that writes `eval/<case>/snapshot.json` and never runs in a flow of the product. A case recorded from now on carries `"inFlight":false` per failure. The committed eval files are unchanged, and replay ignores the member. | Approve, with no migration. |
| 4 | (d) Architecture addition | One sentence added to AD-16 (word for word under Design Notes): a copy counts as done only once IRIS has let go of it. It refines AD-16's "complete or fail" and contradicts no AD. `Watch.Reader` reads one more piece of Ens runtime state, `^Ens.ActiveMessage` through `$$$EnsActiveMessage`, inside its one switching method (AD-3). | Approve. |
| 5 | Product behaviour change | A run can end one pass (`WAITPAUSE`, 0.5 s) later than today, when its last copy is still held by its job at a pass. A copy held by a hung job counts as running: the run gets the existing 60 s progress FixResult (`result.stillResending`) and `LOGWAIT`, as a queued copy does today, and Sweep ends it once Ens lets go of or recovers the header. Before the fix, such a run ended at once and could count an erroring copy as completed. | Approve. The counts become correct, the delay is at most one pass in normal running, and the hung case falls back to the progress path that already exists. |

## Public text

None. No new or changed sentence. The existing result texts (`result.failedAgain`, `result.allThrough`, `result.stillResending`) are used as they are, and are now given the right counts.

**Findability:** no UI change.

## Spec gate rulings (Contest Planner, ~19:40Z Nov 15, BINDING)

APPROVED with conditions. This is a real defect in released versions and a 1.0.12 fix; the release notes will say so plainly.
- (a) No new public text: APPROVED. (b) Cross-lane edits (Fix.Executor, Watch.Reader, their tests, the spine): GRANTED. (c) No stored-data change: APPROVED (inFlight is transient; the committed eval files stay unchanged). (d) The AD-16 sentence: APPROVED verbatim. (e) Behaviour: APPROVED (a copy held by a hung job gets the existing 60 s result.stillResending plus LOGWAIT).

CONDITIONS:
1. Task 0's load probe must show 0 wrong counts in 300 BEFORE the push. Record the numbers (old code and fixed code, unloaded and loaded) here and in DW-1205 and DW-494 through `ledger.sh append`.
2. `^Ens.ActiveMessage` is read ONLY through `$$$EnsActiveMessage`, never by the global name. When the entry read fails (`<UNDEFINED>` or `<PROTECT>`), the status, entry, status double read decides on its own; NEVER treat the copy as "done". A test forces the entry read to fail and shows the copy is still counted correctly (with its `mutation:` line).
3. Run `Test.Fix.*` and `Test.Watch.Evidence` once locally on BOTH IRIS build 154 and build 109 (the README promises 109), and record both results here.
4. DW-1391 is a SEPARATE commit, landed before DW-1205 (done: pushed as OCT-epic21-dw1391).
5. DW-1398 (Test/Watch/Summary.cls quiet fixture) stays its own DW (not folded into DW-1391).

## Run overrides (binding, from the implement stage prompt)

- Baseline: `baseline_revision` is HEAD at the implement entry (`d15f7e861`, which holds DW-1391's commit and 23.3). This commit holds DW-1205 + DW-494 only. Read `git diff --name-only d15f7e861` where Verification says `f56f50d86`.
- Condition 1 (the load probe): the lead of this run measures it (old code, fixed code, and without the second read; 300 trials unloaded and 300 under CPU load, one `yes` per core in the container) on the lane-C warm throwaway and writes it under Verification. A warm stack's production jobs keep the old code after a recompile, so the production is restarted before the post-fix probe.
- Condition 2 (the entry read):
  - `^Ens.ActiveMessage` is read ONLY through `$$$EnsActiveMessage`. The literal `Ens.ActiveMessage` must not appear in any added code line (grep the diff; the macro name `EnsActiveMessage` is fine).
  - The entry read sits inside its own Try/Catch. On `<UNDEFINED>`, `<PROTECT>` or any other throw the loop ends with "not held by the entry check" and the code goes on to the second status read. A failed read is NEVER "done", and never "not in flight" without that second read.
  - Add a test that forces the entry read to fail and shows the copy is still counted correctly. To show that the second read decides, the status of the header has to change between the first read and the second read while the entry read fails. Use a minimal `[Internal]` seam in `Reader.Current` (no new public surface): for example a process-private global read inline at the entry-read point (never a call into another OcuTalon class, AD-3), which a test sets to make the read throw and to change the header's status right there. Justify it in this spec under Design Notes, and keep it a few lines. Its `mutation:` line: treat a failed read as "not in flight" and skip the second status read -> that test goes red.
- Condition 3 (two builds): the lead runs `Test.Fix.*` and `Test.Watch.Evidence` on build 154 and on build 109 after the code is final. The implementation subagent does not run on 109.
- Rule 19: every pin gets a `mutation:` line, demonstrated red, then reverted byte for byte (`cmp` against a copy taken before the mutation).
- The IRIS MCP tools, if used at all, take the explicit profile `ocutalon-slot-c`, namespace OCUTALON. The warm throwaway of this run is tag `e21dw1205iw`, lane C, already up (the lead started it; `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21dw1205iw ci/iris.sh class <Class>`).

## Verification

Lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21dw1205iw`.
- Fresh runs leave `OCUTALON_WARM` unset. `FixExecutor` is code of the running production, so a warm stack's jobs keep their old code, and the production-level classes must run fresh.
- One test class per foreground call, `timeout: 600000`, each under about 3 minutes (a fresh call includes its stack). Split a class by method if it runs longer. Never two `iris_execute_tests` calls in one message.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e21dw1205iw ci/warm.sh up`, then Task 0 item 1, before any product edit.
- (loop) Warm, each `ci/iris.sh class <Class>`, expected to pass:
  - `OcuTalon.Test.Fix.Executor`
  - `OcuTalon.Test.Watch.Evidence`
- (once) Warm, each expected to pass:
  - `OcuTalon.Test.Watch.Reader`
  - `OcuTalon.Test.Watch.GoodMessages`
  - `OcuTalon.Test.Fix.Recheck`
  - `OcuTalon.Test.Eval.Record`
- (once) Fresh, each expected to pass:
  - `OcuTalon.Test.Fix.Partial`
  - `OcuTalon.Test.Fix.Reroute`
  - `OcuTalon.Test.Fix.Scale` (Task 0 item 3's "after" figure)
- (once) Task 0 item 2 on the warm stack, after the product change is compiled there.
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call: exit 0.
- (once) `git diff --name-only f56f50d86` lists only the footprint files.
- (once, at the end, also after a failure) `OCUTALON_RUN_TAG=e21dw1205iw ci/warm.sh down`.

**Mutations:** one per AC as listed under Acceptance Criteria (AC 7 is the regression list). Record each as `mutation: <change> -> <test that went red>`. Revert it byte for byte, and check that `git status --short` and `git diff --stat` are as before. For AC 6, record the probe count with the second read dropped (Task 0 item 2). If it shows 0 wrong, record that the window is too narrow to observe at this load, and that the second read stays on the ordering argument (Design Notes).

**Task 0 records:** (lane C warm throwaway `e21dw1205iw`, build 154; scratch `ZzScratch.Race` and `ZzScratch.Probe` loaded into the throwaway only; load = one `yes > /dev/null` per core (16) inside the container for the run, killed after; `backlog` 0; each trial sends 3 failing orders and counts with the product's `Reader.Evidence` and `Executor.Tally`)
- Item 1, the current code (after 23.3): unloaded 12 wrong of 300 (4.0%); under CPU load 21 wrong of 300 (7.0%). Every wrong trial counted 3 copies as 1 completed and 2 failed again (one trial 2 and 1), while the headers all ended Error (8). The race is still there.
- Item 1, `ZzScratch.Probe.Watch(3)`, three runs, each showing `9a` (Completed while held) before `8a` and `8`: `1818: 2@11.6 2a@12.6 3a@12.9 9a@13.1 8a@13.5 8@13.5`, `1821: 2@6.4 2a@8.0 3a@8.4 9a@8.8 8a@9.0 8@9.1`, `1825: 2@6.4 2a@10.0 3a@10.5 9a@10.8 8a@11.1 8@11.2`.
- Item 2, the fixed code (the scratch `Race` builds each statuses entry from `status` and `inFlight` of the failure, as `Executor.Read` does; the product's own `Reader` and `Tally` are compiled on the throwaway; the probe runs in a new process, so it runs the new code): unloaded 0 wrong of 300 (86 reads saw a copy in flight); under CPU load 0 wrong of 300 (253 in-flight reads). Condition 1 holds.
- Item 2, without the second status read (the `$$$EnsActiveMessage` check kept, the status compare made `&& 0`, then `Reader.cls` restored byte for byte with `cmp`): under CPU load 2 wrong of 300, each a copy read Completed with `inFlight` false that ended Error. So the second read is needed.
- Summary of Condition 1: old code unloaded 12/300, old code loaded 21/300, fixed unloaded 0/300, fixed loaded 0/300, fixed without the second read loaded 2/300.
- Item 3, `Test.Fix.Scale` (500 copies, a fresh stack, class time as the runner prints it): 21.50 s before the change, 22.14 s after (+3%, within the 10% bound; the second run is inside the `lane-a@Fix` shard).
- Condition 3, build 154 (default `IRIS_IMAGE`), fresh: `ci/iris.sh shard lane-a@Fix` (the 29 classes of `Test.Fix.*` that hold tests, incl. `Executor`, `Partial`, `Reroute`, `Scale`) passed, 29 of 29; `Test.Fix.Partial` and `Test.Fix.Reroute` also passed run alone on a fresh stack; `Test.Watch.Evidence` passed (fresh).
- Condition 3, build 109 (`IRIS_IMAGE` the 2027.1.0AI.109.0 image, `$ZV` in the stack: "2027.1.0AI (Build 109U)"), fresh: the same shard `lane-a@Fix` passed, 29 of 29 (`Executor` 39.5 s, `Partial` 48.4 s, `Reroute` 7.0 s, `Scale` 19.9 s); `Test.Watch.Evidence` passed. No `docker tag` alias was needed. The helper classes of `Test/Fix` (`ExecutorProbe`, `ExecutorProbeLong`, `RunProbe`, `Snapshot`, `ZzKind`) hold no tests.
- Warm, build 154 (the implementation pass): `Test.Fix.Executor`, `Test.Watch.Evidence`, `Test.Watch.Reader`, `Test.Watch.GoodMessages`, `Test.Fix.Recheck` and `Test.Eval.Record` passed.
- Spine lint: 12 low findings both at `d15f7e861` (before this change) and after it (the `{...}` tokens of other lines); the stage prompt's baseline of 10 is out of date and this change adds none.
- Scripts: `bash docker/tests/test-boundaries.sh` exit 0 ("all rules passed"); `bash docker/tests/test-class-rules.sh` exit 0 ("all rules passed"). The diff has no added code line with the literal `Ens.ActiveMessage`, no non-ASCII added line and no absolute local path in a tracked file.

**Mutation records** (warm `e21dw1205iw`, build 154; each mutation applied, run, then reverted with `cmp` against a copy taken before it, and `git status --short` and `git diff --stat` the same as before):
- AC 1 and AC 2: mutation: drop the `inFlight` test in `Tally` (`If $IsObject(entry) && entry.inFlight` made `If 0`) -> `TestInFlightCopyIsStillRunning` red (A: "the wait read twice", counts 3|3|0|3|0 and the text; B: "the wait read twice").
- AC 3: mutation: the same `Tally` mutation -> `TestSweepLeavesAnInFlightCopy` red ("the first Sweep returns no result", "the run has no EndedAt ...", and the next Sweep's result).
- AC 4: mutation: drop the `$$$EnsActiveMessage` loop (`Set flightJob = ""` in place of the `$Order`) -> `TestInFlightHeader` red ("inFlight 1 while a job holds it", "Read carries inFlight", "Tally gives completed 0, failed again 1, running 1").
- AC 4: mutation: set the member without the "boolean" type -> `TestInFlightHeader` red ("inFlight is a JSON boolean", "also a JSON boolean").
- AC 5: mutation: drop `inFlight` from `Read`'s entry -> `TestInFlightHeader` red ("Read carries inFlight", "Tally gives completed 0, failed again 1, running 1").
- Condition 2: mutation: a failed entry read counts as "not in flight" and skips the second status read (the Catch sets a skip flag that the second read tests) -> `TestInFlightEntryReadFails` red ("a failed read of the entries does not make it done: the second read of the status gives another status, so it is in flight").
- AC 6, the second read dropped as a unit mutation (`If 'flightHeld {` made `If 0 {`) -> `TestInFlightEntryReadFails` red, the same assert. The probe's count with the second read dropped (Task 0 item 2) is the lead's.

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 21 findings - high 0, medium 0, low 13, false 8, maybe-false 0 (rows merge a finding that two layers reported)
- findings:
  - `[low]` `[reject]` (blind) `Xecute` of `^||OcuTalonFlightSeam` in shipped `Reader.Current` - a process-private global cannot be set from outside the process, the cost is one `$Get` per header, and condition 2 of the gate asks for a forced entry-read failure with a minimal Internal seam justified in the spec (Design Notes). A test-build-only seam is a larger change. wontfix-accepted, reopen_if the package is scanned and the `Xecute` is flagged by the owner.
  - `[low]` `[reject]` (edge) the same seam, "gate it on a test-only flag" - same reason; the global is the flag.
  - `[low]` `[reject]` (blind) a failed entry read leaves no log line - a log line is new text, and the spec says "No new public text"; the degraded mode still never counts a copy as done. by-design.
  - `[low]` `[reject]` (blind, edge) a failed second status read (or its prepare) throws out of `Current` and makes the whole read "not read" - the spec says "An SQLCODE below 0 throws like the other reads"; the outcome then makes every copy running, which is the safe side. by-design.
  - `[low]` `[reject]` (blind, edge) a stale active-message entry of a dead job keeps a copy running - Ens recovers or kills the entries at a start and when a job's handler returns (`Ens/Job.cls:416-419`, `Ens/Director.cls:394-397`); Matrix row 6 gives the hung-job path (60 s progress result, Sweep ends the run once Ens lets go). wontfix-theoretical, would become real if Ens left an entry behind for a job that ended.
  - `[false]` `[reject]` (edge) a header gone at the second read counts as done - the spec says a header that the second read no longer finds is not in flight (Execution), and the header's absence means the first status stands; the probe's 0 of 300 shows no wrong count from it.
  - `[false]` `[reject]` (edge) a finished copy still held at `EndMarked` is counted as cut off - Matrix row 7 states exactly this, and Ens's start recovery means only a copy taken up again after the start can be in flight.
  - `[low]` `[reject]` (edge, blind) the `Good` path runs the entry scan and a second read too - the spec says `inFlight` is on every failure of an evidence read, so `Good`'s failures carry it; a skip would change the shape that the spec fixes. by-design.
  - `[low]` `[reject]` (edge) a test process killed between `SetEntry` and `OnAfterOneTest` leaves a fake entry - the key `zzOcuTalonTest:<job>` is no system name, so no Ens job reads it, and only a production start would look at it. wontfix-theoretical.
  - `[low]` `[reject]` (blind) no test for a failed entry read with an unchanged status giving inFlight 0, and `Good`'s `inFlight` has no assertion - the failed read with a changed status is the pinned case (mutation recorded); adding a test is outside the spec's footprint. wontfix-accepted, reopen_if a mutation that treats every failed read as in flight is found to matter.
  - `[false]` `[reject]` (blind) `inFlight` is undocumented where the evidence shape is consumed, and goes to the model through the tools - the tools read through `Watch.EvidencePack`, which copies named fields only (spec Veto item 3), so the member never reaches a tool's output; the Reader docs name it.
  - `[false]` `[reject]` (blind) the Task 0 records and the Run overrides contradict each other - the override says the lead measures, and the lead did; the "is the lead's" wording in the mutation record points at the same numbers. A fix would edit the spec, which triage rejects.
  - `[false]` `[reject]` (verification-gap) AC 7 has no `mutation:` line - AC 7 is the list of existing tests that must stay green, not a pin.
  - `[false]` `[reject]` (verification-gap) the Verification commands' results are not recorded - recorded now under Verification (Scripts line).
  - `[low]` `[reject]` (verification-gap) `## Auto Run Result` still read "ready-for-dev" - rewritten at finalize, no code change.
  - `[low]` `[reject]` (verification-gap) the end-to-end race has no committed test - AC 6 says that no test can drive it without fault injection; the probe numbers are the evidence.
  - `[low]` `[reject]` (verification-gap) a test process killed mid-test leaves a fake entry - same as the edge row above.
  - `[low]` `[reject]` (intent) the executor tests feed canned `inFlight` statuses, the reader tests use a fake entry, and the double read is tested through the seam - by the spec's own design (Execution and AC 6); the live reader-to-tally chain is `TestInFlightHeader` and the probe.
  - `[low]` `[reject]` (intent) the seam is product code run by one test - same as the first row.
  - `[false]` `[reject]` (intent) `inFlight` may reach stored data through snapshots - the one writer of a whole snapshot is `Eval.Record.Capture`, an author-run tool (Veto item 3, approved); no FixRun, ApprovalRequest, FixResult or log line stores it.
  - `[false]` `[reject]` (intent) the lead's probe is not the product's `Read` - the probe calls the product's `Reader.Evidence` and `Executor.Tally`, with the entry built as `Read` builds it; `TestInFlightHeader` runs `Read` itself.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: a copy that Ens still holds is counted as running. `Watch.Reader.Current` gives each evidence failure `inFlight` (the header is a job's active message, read through `$$$EnsActiveMessage`, or a second status read after that check gives another status; a failed entry read falls through to the second read and is never "done"); `Fix.Executor.Read` carries it and `Tally` counts an in-flight copy as running, so the waiter and both Sweep branches get the right counts. AD-16 gains the approved sentence.
- Files changed: `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` (inFlight, the entry-read seam, docs), `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` (Read, Tally, docs), `src/ocutalon/cls/OcuTalon/Test/Fix/Executor.cls` (two methods), `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls` (two methods, cleanup), `ARCHITECTURE-SPINE.md` (AD-16 sentence), `_bmad-output/implementation-artifacts/deferred-work.md` (probe notes on DW-1205 and DW-494), this spec.
- Review findings: 21 rows from four layers; 0 high, 0 medium, 13 low, 8 false; 0 patches applied, 0 deferred, 21 rejected with their reasons in the triage log.
- Follow-up review recommendation: `false` (no patch was applied).
- Verification: Task 0 and condition 1 to 3 numbers, mutation lines, scripts and builds under `## Verification`: probe old 12/300 unloaded and 21/300 loaded, fixed 0/300 and 0/300, without the second read 2/300 loaded; `Test.Fix.*` shard 29 of 29 and `Test.Watch.Evidence` on builds 154 and 109; `Test.Fix.Scale` 21.50 s to 22.14 s; both scripts exit 0; the spine lint has 12 low findings at the baseline and after.
- Residual risks: the `Xecute` seam in `Reader.Current` (process-private, set only by `TestInFlightEntryReadFails`); a copy held by a hung job counts as running until Ens lets go (Matrix row 6, approved).

## QA Pass (2026-11-15, lane C, build 154)

Tests only; no product change. Warm stack `e21dw1205qw` for the mutations, a freshly started stack `e21dw1205qr` (no product class reloaded after its start) for the regression; both torn down.

**1. The Xecute seam (`^||OcuTalonFlightSeam`, `Reader.Current`), assessed for the lead and the review**
- No rule bans it today. `Test.Bridge.CodeRules.ToolCodeClean` (no XECUTE) runs over `OcuTalon.Tools` classes and tool providers only; `Test.Bridge.Keys` (`INDIRECTION`) over the bridge's `Status`; `Test.Fix.Reformat` `TestStaticScan` over `Fix.Reformat` and `RepairResend`. `Watch.Reader` is in `CodeRules` `READERCLASSES`, but the callback rule scanned there looks only for `%AI` references and Python, and `test-class-rules.sh` has no Xecute rule. The class-rules and boundaries scripts exit 0 with it. AD-10 and the tool-class rule show the intent: shipped code that a tool can reach runs no Xecute.
- Risk is low (a process-private global, set by no product code, killed on use) but it is the only `Xecute` in `src/`, in a class the AI Hub callback runs, and the next scan that is widened to `READERCLASSES` (or an Open Exchange or security scan) flags it.
- Narrower seam, validated on the warm stack (applied temporarily, reverted byte for byte): the seam holds a status number, not code. The entry read throws and the second read is compared with the seeded status instead of the row's; no Xecute and no write to an Ens global. A genuine failure is not feasible in a throwaway (it needs a global mapping change in %SYS that would also break the running production's jobs).
- Recommendation: replace the Xecute with the data seam below. With the seeded status 8 and the header really Completed (9), `TestInFlightEntryReadFails` passes (green); with `If 'flightHeld {` made `If 0 {` it is red ("a failed read of the entries does not make it done ..."). The same seam also lets the test add the control the review asked for: a failed entry read whose seeded status equals the row's gives inFlight 0.
```
 Set flightHeld = 0
+Set flightFirst = result.%GetData(12)
 Try {
   Set flightSeam = $Get(^||OcuTalonFlightSeam)       // a status number, set by a test only
   If flightSeam '= "" {
     Kill ^||OcuTalonFlightSeam
-    Xecute flightSeam
+    Set flightFirst = flightSeam
+    $$$ThrowStatus($SYSTEM.Status.Error(5001, "flight seam"))
   }
   ... $Order loop unchanged ...
 }
 ...
-If flightRead.%Next() && (flightRead.%GetData(1) '= result.%GetData(12)) Set flightHeld = 1
+If flightRead.%Next() && (flightRead.%GetData(1) '= flightFirst) Set flightHeld = 1
```
In the test: `Set ^||OcuTalonFlightSeam = 8` in place of the Xecute string, no UPDATE of the header.

**2. Gaps against the ACs and the matrix**
- BO and BP paths: the reader is host-agnostic (it reads the header's status and the entry, `Ens/Queue.cls:317` sets the entry for every host, `Ens/Host.cls:646` kills it; BP `Actor.cls:452`/`:483`, BO `BusinessOperation.cls:384`/`:412` have the same Completed, Error, kill order). The live tests use a BP (`OrdersFromPartner`, Translator). A scratch probe (never committed, loaded in the throwaway only) sent failing messages to a BO (`OrdersForReview`, given a WarehouseOrder) under CPU load: 5 runs (300 and 300 trials with backlog 10, 300 with backlog 10 that also counted, 100 and 100 with backlog 100; each pair with and without `inFlight`), 0 wrong in every run; in the 500 trials that counted, 0 reads saw a copy Completed while held and 46 saw a held header (Error, kept running by the rule). The BO's Completed-to-Error window was too narrow to observe (the BO finishes in about 1 ms); the BP window is the one that produced the reds. No BO test added: it would be the same code path and could not be made to fail.
- A successful copy briefly held, then let go: covered (`TestInFlightCopyIsStillRunning` B: Completed + inFlight, then Completed; `TestInFlightHeader`: held then killed, running 1 then completed 1).
- A header in `^Ens.ActiveMessage` for an unrelated job: covered by `TestInFlightHeader` (the fake entry holds H; E is not held and gives inFlight 0, and Tally running 1 only for H). mutation: treat any entry as holding the header (`If flightId = id` made `If flightId '= ""`) -> `TestInFlightHeader` red ("a header that no job holds has inFlight 0", "Read carries inFlight", "Tally gives completed 0, failed again 1, running 1"); reverted, `cmp` equal.
- `Fix/Run.cls` Sweep `EndMarked` with an in-flight copy at restart (Matrix 7): REAL GAP, no test. Added `TestSweepCutsOffAnInFlightCopyOfAMarkedRun` in `Test/Fix/Executor.cls`: a marked run of 3 targets and 3 copies, two Completed and in flight and one Completed, ends 3|3|1|0|0 with Interrupted 2, the key `result.interrupted` and the text "1 of 3 orders went through. The other 2 need a new approval." mutation: drop the `inFlight` test in `Tally` (`If $IsObject(entry) && entry.inFlight {` made `If 0 && ...`) -> the new test red (counts 3|3|1|0|0, Interrupted 1, key, text, the stored run), `TestSweepCutsOffAnInFlightCopyOfAMarkedRun` green again after the revert (`cmp` equal, `git status` and `git diff --stat` as before).

**3. Regression at the real level** (fresh stack, one `yes` per core (16) in the container, killed after): `Test.Fix.Reroute` 10/10 passed (7.1 s to 15.4 s), `Test.Fix.Partial` 10/10 passed (51 s to 73 s). `Test.Fix.Executor` 1 of 1 and `Test.Watch.Evidence` 1 of 1 passed warm, with the new test in; `bash docker/tests/test-class-rules.sh` exit 0.

**Findings for the lead**
- A SYNC-queue copy (`$$$queueIsNotSyncQueue` is false, `Ens/Queue.cls:317`) never has an active-message entry, so for it only the second status read protects; it leaves a window of a few ms between the two reads. The resend path sends asynchronously, so no fix copy is affected today.
- A marked run (restart) counts a copy that is Completed and in flight as cut off (Matrix 7, approved): the user is told that the copy needs a new approval although it is about to complete. Rare (only a copy taken up again after the start can be in flight); recorded, no change.
