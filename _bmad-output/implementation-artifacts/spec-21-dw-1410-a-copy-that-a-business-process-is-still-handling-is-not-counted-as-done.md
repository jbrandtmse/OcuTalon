---
title: 'DW-1410: A copy that a business process is still handling is not counted as done'
type: 'bugfix'
created: '2026-11-16'
status: 'ready-for-dev'
baseline_revision: '872d8cb59a21d87293be0a6926c90cb2345e5db4'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-dw-1205-a-copy-that-errors-is-not-counted-as-done-while-ens-still-holds-it.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1410, HIGH; Contest Planner rulings ~01:00Z and ~01:30Z Nov 16: "DW-1410 STAYS HIGH", "LEAD with the business-process instance check"):** a copy resent to a business process (BP) that waits for a reply is counted as done before the BP has finished with it.
- On the copy's first pass the BP sets the copy's header Completed (9) inside its own handler (`irislib/Ens/BusinessProcess.cls:461`) and again in the Actor (`Ens/Actor.cls:452`), before it knows whether the reply will succeed. The copy then reads Completed for the whole wait.
- The job lets go of the copy at the end of that pass (`Ens/Host.cls:646`). While the reply is handled, the job's active-message entry holds the reply header, not the copy (`Ens/Queue.cls:317`). So DW-1205's `inFlight` (`Watch/Reader.cls:809-835`) sees neither an entry nor a status change, and `Fix.Executor.Tally` (`Fix/Executor.cls:1036`) counts the copy as completed.
- When the reply pass fails, the copy goes Error only at `Actor.cls:483`. A run that counted it before then ends with wrong counts. These reach the FixRun row, the final FixResult, the user's notice, the Action audit entry and `/state`. `Fix.Run.Sweep` (`EndLeft` `Fix/Run.cls:300`, `EndMarked` `:262`) counts through the same `Read` and `Tally`, so it has the same exposure.
- Measured by the DW-1205 code review on the lane-C throwaway, with the DW-1205 fix in place, using a scratch BP that calls a BO with a reply and errors in `OnResponse`: 25 of 100 trials wrong with a ~1 ms reply, and 10 of 10 wrong with a 1 s reply. In each wrong trial the copy read `9` and not held for 1 to 3 s, then `8`. The old code counts it the same way.
- Triage (the ledger): this is not in the demo or the guide. Their resends go to `Demo.Orders.Translator`, which sends with no reply and completes on its first pass, or to a BO. It does hit user productions whose BPs (BPL included) call and wait, which the Planner rules are common.

**Approach (one boolean, the existing `inFlight`; no change of shape):**
- **Lead: the BP-instance check.** In `Watch.Reader.Current`'s evidence branch, the reader makes a further check for a header whose first read is Completed (9). The header is held while an `Ens.BusinessProcess` row of its session exists whose `%PrimaryRequestHeader` is the header and whose `%IsCompleted` is 0. The query is SQL on the class's table, through its `SessionId` index (`BusinessProcess.cls:131`). No index exists on `%PrimaryRequestHeader`.
- **The completion window: the reply-in-hand check.** IRIS deletes the instance (`Actor.cls:265`) before it writes the copy's final Error (`:483`). It then lets go of the reply header only after both (`Host.cls:646`). So in the same check the reader also holds the header while a job's active message (`$$$EnsActiveMessage`) is a response (Type 2) of the header's session that is addressed to the header's target. That is the BP's job, handling a reply for this copy. It also covers the BP's retry wait (`Actor.cls:388`, up to `RetryInterval`), during which no instance exists.
- **Order:** status (first read) → instance → reply in hand → DW-1205's entry check → second status read. With this order nothing is missed (Design Notes).
- **A failed read never counts the copy as done.** A throw in the new block (a failed prepare, `<PROTECT>`, `<UNDEFINED>`, SQLCODE < 0, or an SQL privilege error) sets `inFlight` 1. DW-1205's own entry read keeps its approved condition 2 unchanged.
- **The result goes into DW-1205's `inFlight`.** `Fix.Executor.Read`, `Tally`, `Look`, `Pass`, `Progress` and both Sweep branches already count an in-flight copy as running. They need no code change, only docs.
- **The run's time limit still bounds the wait.** A copy held past `WAITSECONDS` (60 s) ends the wait with the existing progress FixResult (`result.stillResending`) and `LOGWAIT`. It never hangs and is never counted done. A new canned test pins this, with mutations that would hang it or count it done (ruling: "Pin it").
- **The session-level signal is not used** (rejected as a mechanism by the ruling). Task 0 measures it only as a comparison.

## Boundaries & Constraints

**Always:**
- **Footprint (Lane A packages, AD-29; lane C makes the edits under the Planner's assignment, Veto item 2):**
  - `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`, in `Current`'s evidence branch: the new block before DW-1205's entry check, plus the class doc's Evidence bullet and `Current`'s doc.
  - `src/ocutalon/cls/OcuTalon/Fix/Executor.cls`: docs only (the class doc's wait bullet and `Read`'s doc).
  - Tests:
    - `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls`: three new methods, a fixture helper, cleanup and header bullets.
    - `src/ocutalon/cls/OcuTalon/Test/Fix/Executor.cls`: one new method and a header bullet.
  - The spine: `ARCHITECTURE-SPINE.md` AD-16, where DW-1205's sentence is amended word for word as given in Design Notes (Veto item 4).
  - This spec.
- The namespace switch stays in `Current` alone (AD-3). The new reads are inline code in `Current` and call no OcuTalon class there.
  - The instance read is SQL on the documented persistent class `Ens.BusinessProcess`, and nothing else reads it. The global `^Ens.BusinessProcessD` has no `$$$` macro, so it is never read directly.
  - Active-message entries are read only through `$$$EnsActiveMessage` (DW-1205 condition 2). The literal `Ens.ActiveMessage` appears in no added code line.
- The new block runs only for a header whose first read is Completed (`$$$eMessageStatusCompleted`). For any other status `Tally`'s verdict does not depend on it:
  - Queued, Delivered and the other open statuses are already running.
  - Error, Aborted, Discarded and Suspended are written to the copy only after its instance has completed or been deleted (`Actor.cls:265` before `:452`, `:465`, `:483`).
- Its two statements are prepared on first use inside the block's own Try, once per `Current` call, so that a prepare that fails (an SQL privilege, for example) holds the copy and never fails the evidence read.
- Locals carry the `flight` prefix, as DW-1205's do. ObjectScript stays ASCII. Comments state the contract, not review history.
- An entry of the statuses with no `inFlight` member (the probes' canned statuses) is not in flight (unchanged). Every existing test keeps its statuses and passes unchanged.

**Never:**
- Change `Fix/Run.cls`, `WAITSECONDS`, `WAITPAUSE`, `COPYDONE`, `COPYFAILED`, the FixResult, the FixRun class, any catalog key or text, `Watch.EvidencePack` or the code of `Executor.Read`, `Tally`, `Look`, `Pass` or `Progress`.
- Add a member to the snapshot or the statuses, or rename `inFlight`. Store it anywhere (DW-1205 Veto 3 stands).
- Write, kill or lock any Ens global or Ens table row from product code. The reader only reads.
- Use the session-level signal ("no message of the session still Queued, Delivered or held") in product code.
- Change DW-1205's entry-read Try/Catch, its data seam's top node or its second status read, other than wrapping them in `If 'flightHeld`.
- Delete, skip, tag off or weaken a test.

## I/O & Edge-Case Matrix

Copies are header ids registered on a FixRun. "Instance" means an `Ens.BusinessProcess` row with `%PrimaryRequestHeader` = the copy, `%SessionId` = the copy's session and `%IsCompleted` 0. "Reply in hand" means a job's `$$$EnsActiveMessage` value is a header of Type 2 (Response) whose SessionId and TargetConfigName equal the copy's.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 The defect | Three copies resent to a BP that calls a BO with a reply and then fails. Each reads Completed while the BP waits. | Each has an instance, so `inFlight` 1 and running. The run ends when the copies read Error: 3/3/0/3/0 with the reason of the lowest failed copy. | none |
| 2 Completion window | The instance is deleted (`Actor.cls:265`), the copy still reads Completed, and the job holds the reply (until `Host.cls:646`). | The reply is in hand, so `inFlight` 1. The next pass reads Error. | none |
| 3 Retry wait | `ReplyCodeActions` R (or `Retry` set): no instance during `RetryInterval` (`Actor.cls:388`). The copy reads Completed, then Delivered, then Completed again. | The reply is in hand for the whole retry, so running. | none |
| 4 BP completes OK | The reply pass succeeds. The instance is deleted, and the copy's final status stays Completed. | Running while the job still holds the reply, then completed: one more pass at most (0.5 s). Counts as today. | none |
| 5 Sync call inside the BP | The BP calls with `SendRequestSync`. The reply comes back on `_SyncCall:<job>` (`Host.cls:325`), which sets no entry (`Queue.cls:317`). | The copy is Delivered (`BusinessProcess.cls:264`) and its job still holds it as its active message for the whole call. So it is running through DW-1205 alone. Nothing new is needed. | none |
| 6 A BP that waits for nothing, or a BO | The demo's Translator (sends with no reply) or `OrdersForReview`. | No instance and no reply in hand: unchanged from DW-1205. | none |
| 7 Held past the limit | A copy held (instance, reply in hand or entry) past `WAITSECONDS`. | Running. One progress FixResult (Final 0, `result.stillResending`) and one `LOGWAIT`, as for a queued copy. Never a hang, and never counted done. Sweep (`EndLeft`) leaves the run until the copy is no longer held, then ends it. | none |
| 8 An instance that never completes | The reply was aborted, the called target is disabled and no reply comes, or the BP waits on an alarm for hours. | Running. As row 7: stillResending at the limit, and Sweep leaves the run, as it does today for a copy still queued at a disabled target. | none |
| 9 The new block's read fails | A prepare, SQL privilege, `<PROTECT>` or `<UNDEFINED>` error, SQLCODE < 0, or the test seam `^\|\|OcuTalonFlightSeam("process")`. | `inFlight` 1 (never done). The evidence read itself still gives `read`. | caught in the block |
| 10 Siblings in one session | Two copies of one original session, resent to the same BP. A job handles copy B's reply while copy A is already done. | A reads as in flight for that moment (one more pass). The counts are never wrong. | none |
| 11 Retained instances | `^Ens.Config("bp","RetainCompletedInstances")` set: the instance stays with `%IsCompleted` 1 (`Actor.cls:219-221`). | Not counted (the filter). The reply in hand covers the window as in row 2. | none |
| 12 Another status with an instance | A copy that reads Error (or Suspended) while an unfinished instance of it exists. | The block does not run, so DW-1205's verdict stands (failed again). | none |
| 13 Marked run (restart) | `EndMarked` with a held copy. | Counted as running, so it is cut off (Interrupted), as DW-1205 matrix 7. | none |
| 14 Other callers | `Watch.EvidencePack`, `Fix.Kind` (dry run, re-check), `RepairResend`'s `Good`, `Eval.Record.Capture`. | Same shape. Completed headers (`Good`'s) get the block's reads, and none of these callers reads `inFlight`. | none |

</intent-contract>

## Code Map

Line numbers are at the baseline `872d8cb59` (DW-1205's head `fded9d158` plus a log commit).

- `Watch/Reader.cls`:
  - `Include (Ensemble, EnsConstants, EnsErrors)` at L1. `$$$EnsActiveMessage` is `irislib/Ensemble.inc:123`. `$$$eMessageStatusCompleted` (9) and `$$$eMessageTypeResponse` (2) are `irislib/EnsConstants.inc:74`, `:79`.
  - Class doc Evidence bullet L42-55, with the `inFlight` sentence at L52-54. `Current` doc L603-622 (`inFlight` named at L612). `Current` L623.
  - The evidence branch prepares `headers` and `flightStatus` (L748-751).
  - Each failure is built at L802. `sessionId` = column 2 and `target` = column 5 are locals from L790-792. `isError` is set at L803.
  - DW-1205's block runs L804-835: comments L804-808; `flightHeld`/`flightFirst` L809-810; the Try with the data seam (top node) L811-816; the `$$$EnsActiveMessage` loop L818-826; Catch L827-829; the second read L830-834; `inFlight` L835. The failure is pushed at L871.
- `Fix/Executor.cls`:
  - Class doc wait bullet L41-44.
  - `Wait` L896, `Waiting` L928 (the limit test L938), `Pass` L951 (`LOGWAIT` L985), `Progress` L994, `Look` L1014.
  - `Tally` L1036 (the `inFlight` test L1047).
  - `Read` L1071 (doc L1066-1070; `inFlight` carried L1084).
- `Fix/Run.cls`: `EndMarked` L262, `EndLeft` L300 (`running > 0` L319). No change.
- Tests:
  - `Test/Fix/ExecutorProbe.cls`: `WAITSECONDS` 3 and `WAITPAUSE` 0.1. `Statuses` L167 holds the canned `StatusIs`/`StatusThen`/`ThenAfter` and `Reads`. `Waiting` L180 calls the product's.
  - `Test/Fix/Executor.cls`:
    - Model methods: `TestStillRunningAfterTheWait` L831 for the stillResending and `LOGWAIT` asserts, and `TestInFlightCopyIsStillRunning` L1844.
    - Helpers: `Canned`, `CarryJSON`, `Request`, `Send`, `LastResult`, `Render`, `Row`.
    - `OnAfterOneTest`'s `LOGWAIT` cleanup at L2789.
  - `Test/Watch/Evidence.cls`:
    - `OnAfterOneTest` L48 (kills `^||OcuTalonFlightSeam` and the fake entry), `SetEntry`/`KillEntry`, `FailureOf`.
    - `TestInFlightHeader` and `TestInFlightEntryReadFails` (L~380-476).
  - `Test/Watch/Case.cls`: `FixtureHeader` and `MakeFixtureHeader` L1045 (Type, Status and SessionId can be set; the target is `zzPollerTarget`).
- IRIS (`irislib`, read only), verified at the baseline:
  - `Ens/BusinessProcess.cls`: `%PrimaryRequestHeader` L86, `%IsCompleted` L97; indexes `TimeCreated` L129 and `SessionId` (on `%SessionId`) L131, and none on `%PrimaryRequestHeader`. Storage is `^Ens.BusinessProcessD` and `^Ens.BusinessProcessI` (L1403-1406), and subclasses (BPL included) share the extent.
  - First pass: the instance is saved at L258 before `%SessionId` is set at L259. It is saved again, with the session, by `SendRequestAsyncInternal` when a reply is required (L228). The copy is set Delivered at L264 and Completed at L461. `%IsCompleted` is set 1 at L479.
  - `Ens/Actor.cls`:
    - The handler runs at L179. On an error, `%IsCompleted` is set 1 at L215. The not-completed save is at L219-221. The completed instance is deleted at L265.
    - The retry loop: `Quit` L285, reset to the primary L287, the retry wait L388.
    - The copy is set Completed at L452, the error is logged at L482, and the copy is set Error at L483.
  - `Ens/Host.cls:646`: the active-message entry is killed. `Ens/Queue.cls:317`: it is set at dequeue, never for a `_SyncCall:` queue (`EnsQueuing.inc:11-12`).
  - `Ens/MessageHeader.cls:95-105`: a response's Type is 2, its Target is the request's Source, and its SessionId is the request's.
  - Ens's own reads of the same predicate: `Ens/Purge.cls:210-213` (`WHERE %SessionId = ... AND %IsCompleted <> '1'`) and the portal's `EnsPortal/BPInstances.cls:671-672` (filters by `%SessionId` and `%PrimaryRequestHeader`).

## Tasks & Acceptance

**Task 0 (measure first, on lane C's warm throwaway, tag e.g. `e21dw1410iw`, before any product change except where an item says after; record each result under `## Verification`; never a dev slot, Rule 21):**
1. **Rebuild the code review's scratch.**
   - Copy `ZzScratch.Setup`, `ZzScratch.Svc`, `ZzScratch.CallBP`, `ZzScratch.OkBO` (and its 1 s variant) and `ZzScratch.RespRace` from the code review's scratch folder (`edw1205cr/resp/` in the lead session's scratchpad) into your own scratchpad. Load them into the throwaway only. They are never committed. `Setup.Add()` adds the items to the Orders production.
   - Add these scratch variants in the same way:
     - (a) `ZzScratchRetryBP`: CallBP with `ReplyCodeActions` "E=R", `RetryInterval` 1 and `FailureTimeout` 3. Raise `RespRace`'s per-trial cap to 10 s for it.
     - (b) `ZzScratchSyncBP`: `OnRequest` calls the OkBO with `SendRequestSync`, then returns an error.
     - (c) `ZzScratchFanBP`: CallBP that also sends `SendRequestAsync(..., 0)` (no reply) to a disabled `ZzScratchOffBO`. If Ens refuses to queue to a disabled item, use an enabled BO whose `OnMessage` hangs 30 s (PoolSize 1), and record which you used.
     - (d) If time allows, a BPL that `<call>`s the OkBO and then fails. Record it either way; it is not a stop condition.
   - Load: one `yes > /dev/null` per core in the container for the run, killed after, as for DW-1205. Keep each call under the 10-minute cap and split runs where needed.
2. **The current code (DW-1205 only):**
   - CallBP, 1 ms reply: `Run(300)` unloaded and `Run(300)` loaded.
   - 1 s reply: `Run(30)` loaded.
   - RetryBP: `Run(20)`. SyncBP: `Run(100)` loaded.
   - Expect wrong > 0 for CallBP and RetryBP, and 0 for SyncBP (matrix 5). If CallBP gives 0 wrong in both 1 ms runs and in the 1 s run, stop with `## Clarification Needed`.
3. **The order at completion, observed.** Extend the scratch `RespRace.Watch` so that each status step also shows `i` (an instance exists, by the product's query) and `r` (a reply is in hand). Record one line per variant (CallBP 1 ms, CallBP 1 s, RetryBP) that shows the sequence `9i` … `9r` … `8`, that is the instance gone while the copy still reads 9.
   - By reading, the instance is deleted at `Actor.cls:265` before the final Error at `:483`.
   - If 20 watches never show `9r` without `i`, record that the window is too narrow to observe at this load. The reply-in-hand check then rests on the reading and on item 5's retry count.
4. **SQL facts.**
   - The plan of the instance query uses the `SessionId` index (`EXPLAIN`, or `$SYSTEM.SQL.Explain`). Record the plan's first line.
   - `$SYSTEM.SQL.Security.CheckPrivilege(<user>, 1, "Ens.BusinessProcess", "s")` compared with the same call for `Ens.MessageHeader`, for:
     - the user that OcuTalon's production jobs run as (where `Executor.Read` and Sweep run; `$Username` in a job of the OcuTalon production);
     - the service user (the tools' reads).
   - If a user that can read `Ens.MessageHeader` cannot read `Ens.BusinessProcess`, stop with `## Clarification Needed`: every Completed copy would then stay running until the limit, and a grant would be a security change for the gate.
   - Also confirm that the test helper can save a bare `Ens.BusinessProcess` row in OCUORDERS (`%New("zzPollerTarget")`). Otherwise use an SQL `INSERT`, and record which.
5. **The fix, measured (after the Execution tasks; restart the production first, since a warm stack's jobs keep the old code):**
   - CallBP 1 ms: `Run(300)` unloaded and `Run(300)` loaded. **Target 0 wrong in each.**
   - CallBP 1 s: `Run(30)` loaded. **Target 0 wrong.**
   - RetryBP: `Run(20)`, target 0 wrong. SyncBP: `Run(100)` loaded, target 0 wrong.
   - FanBP: `Run(30)`, target 0 wrong, and every trial ends before its cap (no false still-running).
   - The 0-wrong targets on CallBP are the push condition (as DW-1205's condition 1). If any is missed, do not push; stop with `## Clarification Needed`.
6. **The instance check alone.** Make the reply-in-hand test `&& 0` in the product code. Run RetryBP `Run(20)` and CallBP 1 ms `Run(300)` loaded, record both counts, then restore `Reader.cls` byte for byte (`cmp` against a copy taken before). This shows whether the reply-in-hand check is needed. If both are 0, record that and keep the check on the ordering argument (Design Notes).
7. **The session signal, as a comparison only (scratch emulation in `RespRace`, never product code).**
   - The rule under test: a copy is running when any header of its SessionId has Status 2 or 3, or is the value of a `$$$EnsActiveMessage` entry.
   - Record its wrong counts: CallBP 1 ms `Run(300)` loaded, and 1 s `Run(30)`.
   - On FanBP, record its false still-running count: the trials whose copies all reached a final status but that the signal still called running 5 s later.
8. **The time it costs.** Record `Test.Fix.Scale` (500 copies, fresh) before the change and after it, as two numbers. If the after figure is more than 10% slower, add a line about it. This is not a stop condition.

**Execution:**
- [ ] `Watch/Reader.cls` `Current`, evidence branch, right after `Do failure.%Set("isError", ...)` (L803). Keep DW-1205's lines and move `Set flightHeld = 0` and `Set flightFirst = result.%GetData(12)` above the new block.
  - New block, only `If flightFirst = $$$eMessageStatusCompleted`, in its own `Try { } Catch { Set flightHeld = 1 }`:
    - The test seam: `If $Data(^||OcuTalonFlightSeam("process"))`, kill that node and `$$$ThrowStatus($SYSTEM.Status.Error(5001, "flight seam"))`.
    - On first use in this call, prepare these two statements, each with `$$$ThrowOnError(...%Prepare(..., 1))`:
      - `flightProcess`: `SELECT TOP 1 ID FROM Ens.BusinessProcess WHERE %SessionId = ? AND %PrimaryRequestHeader = ? AND (%IsCompleted = 0 OR %IsCompleted IS NULL)`.
      - `flightReply`: `SELECT SessionId, TargetConfigName, Type FROM Ens.MessageHeader WHERE ID = ?`.
    - The instance: when `sessionId '= ""`, execute `flightProcess` with `(sessionId, id)`. A row means `flightHeld = 1`. An SQLCODE below 0 throws, and so lands in the Catch.
      - A header without a session is not looked up. Ens gives every header a session, and a resent copy keeps its original's (`ResendDuplicatedMessage`, `MessageHeader.cls:446`).
    - The reply in hand, if not held: `$Order` over `$$$EnsActiveMessage(flightJob)` with its value `flightId`, skipping `flightId = id` (DW-1205's check covers it).
      - Read each other value's SessionId, TargetConfigName and Type once per call. Cache them in the local `flightSeen(flightId)`; a header's three fields never change.
      - Held when Type = `$$$eMessageTypeResponse`, SessionId = `sessionId` and TargetConfigName = `target`.
  - DW-1205's Try/Catch and its second read, unchanged, inside `If 'flightHeld { ... }`. Its `Catch` still sets `flightHeld = 0`, which it can only reach while 0.
  - `Do failure.%Set("inFlight", flightHeld, "boolean")` as today.
  - Comments (contract, a few lines):
    - A business process sets its request Completed at each pass and lets go of it while it waits. So a Completed header is held while an unfinished instance of it exists, or while a job handles a reply for it (IRIS deletes the instance before it writes the final status).
    - A failed read of these holds the header.
    - The data seam `("process")` holds no code.
  - Class doc, Evidence bullet: the `inFlight` sentence becomes: "Each failure also carries inFlight, a boolean: 1 when IRIS still holds or still handles the header, that is when, after its row was read, the row is Completed and a business process instance of it is not complete (Ens.BusinessProcess, %PrimaryRequestHeader, %IsCompleted 0) or a job handles a response of its session addressed to its target, or it is the active message of a job of the namespace (Ensemble.inc's EnsActiveMessage), or a second read of its status, made after those checks, gives another status (IRIS sets an erroring message Completed just before Error, sets a business process's request Completed at each pass while it waits for replies, and lets go of it after). A failed read of the business process instances or of the replies counts as 1."
  - `Current`'s doc (L612): "(a boolean: IRIS still holds or still handles the header)".
- [ ] `Fix/Executor.cls`, docs only:
  - Class doc L42-43: "(IRIS still holds its header, or a business process still handles it; Reader.Evidence inFlight)".
  - `Read`'s doc L1069: "inFlight (Reader.Evidence's: 1 while IRIS still holds or still handles the copy)".
- [ ] `Test/Watch/Evidence.cls` (live, warm; header bullets for each new test; a property `Processes`, a comma list of `Ens.BusinessProcess` ids that `OnAfterOneTest` deletes in OCUORDERS, also after a failure):
  - Helper `FixtureProcess(header, session, completed) As %String`. It saves, in OCUORDERS, a bare `Ens.BusinessProcess` (`%New("zzPollerTarget")`; `%PrimaryRequestHeaderSetObjectId(header)`, `%SessionId`, `%IsCompleted`) and remembers its id. Use the SQL fallback if Task 0 item 4 says so.
  - New `TestBusinessProcessHoldsACopy` (matrix 1, 11, 12; AC 1):
    - Make a Status 9 header H (its session is H), a Status 9 header K and a Status 8 header E with the incident's own error.
    - Make an unfinished instance of H (session H), an unfinished instance of K **in H's session** (`%SessionId` H, `%PrimaryRequestHeader` K) and an unfinished instance of E (session E).
    - `Reader.Evidence(ORDERS, ORDERSPRODUCTION, "zzPollerTarget", "h<H>,h<E>", .snapshot)`:
      - H is `Completed|1` and a JSON boolean ("a Completed header whose business process is not complete is in flight").
      - E is `Error|0` ("an Error header is final, whatever its instance").
    - The live chain: over `..Fixture(owner, "<H>,<E>")` and an unsaved FixRun of H and E, `Executor.Read` gives `statuses.<H>.inFlight` 1, and `Tally` gives `0|1|1`.
    - Set H's instance `%IsCompleted` 1 (SQL `UPDATE` or reopen and save). Now H is `Completed|0` and `Tally` gives `1|1|0` ("a completed instance does not hold it").
    - Control: delete H's instance and leave K's (same session, other header). H is `Completed|0` ("another header's unfinished instance in its session does not hold it").
  - New `TestReplyInHandHoldsACopy` (matrix 2, 3; AC 2):
    - Make a Status 9 header H, and these headers in OCUORDERS:
      - R: Type 2, Status 3, SessionId H.
      - R2: Type 2, SessionId of its own.
      - Q: Type 1, Status 3, SessionId H.
    - With a fake entry (`SetEntry`) = R, H is `Completed|1` ("a job that handles a reply of its session to its target holds it").
    - With the entry = R2, H is `Completed|0` ("a reply of another session does not").
    - With the entry = Q, H is `Completed|0` ("a request of its session is not a reply in hand").
    - After `KillEntry`, H is `Completed|0`.
  - New `TestBusinessProcessReadFails` (matrix 9; AC 3):
    - A Status 9 header H with no instance and nothing held.
    - With `^||OcuTalonFlightSeam("process") = 1`: the outcome is `read`, the seam node is gone (`$Data` 0), and H is `Completed|1` ("a failed read of the business process instances never makes it done").
    - Then `Executor.Read` and `Tally`, with the seam set again, give running 1 and completed 0.
    - Without the seam, H is `Completed|0`.
- [ ] `Test/Fix/Executor.cls` (canned, warm; header bullet):
  - New `TestHeldCopyStopsAtTheWait` (matrix 7; AC 4), modelled on `TestStillRunningAfterTheWait`:
    - Three targets and three copies. `StatusIs`: all three `{"status": "Completed", "error": "", "target": "OrdersFromPartner", "inFlight": true}`.
    - `StatusThen`: all three Error with the incident's own error and no `inFlight`. `ThenAfter` 150, more passes than the probe's 3 s wait at 0.1 s can make.
    - `Send` returns OK. `host.Reads` > 1 and `host.Reads '> 150` ("the wait stopped at its limit and never read past it").
    - The request is `executing||`, and the run has a ResentAt and no EndedAt or counts.
    - Exactly one FixResult, with `final|...|reason` = `0|0|3|3|0|0|0|0|`, rendering "Still resending: 0 of 3 orders have gone through so far. I'll tell you when it's done."
    - No Action entry. One `LOGWAIT` warning naming the request, saying "3 of 3 copies".
    - A later `WaitNow` sends nothing and warns nothing.
- [ ] Spine (Veto item 4): the amended AD-16 sentence, word for word as in Design Notes. `updated:` is the day of the edit.
- [ ] This spec: the `## Verification` records (Task 0 and the mutation lines).

**Acceptance Criteria:**
1. Given a copy that reads Completed while an unfinished business process instance of it exists, then `Reader.Evidence` gives it `inFlight` true (a JSON boolean), `Executor.Read` carries it and `Tally` counts it as running. Once the instance is completed (or gone, with no reply in hand) it is completed.
   - mutation: the instance query's result ignored (`If flightRows.%Next() Set flightHeld = 1` made `If 0`) -> `TestBusinessProcessHoldsACopy` red ("... is not complete is in flight", the Tally line).
   - mutation: drop the `%IsCompleted` condition from the query -> red ("a completed instance does not hold it").
   - mutation: drop the `%PrimaryRequestHeader` condition (bind the session only) -> red ("another header's unfinished instance in its session does not hold it").
   - mutation: run the block for every status (drop the Completed condition) -> red ("an Error header is final").
2. Given a copy that reads Completed with no instance while a job handles a response of its session addressed to its target, then it is in flight, and a reply of another session or a request of its session does not hold it.
   - mutation: the reply-in-hand comparison made `If 0` -> `TestReplyInHandHoldsACopy` red ("a job that handles a reply ... holds it").
   - mutation: drop the SessionId comparison -> red ("a reply of another session does not").
   - mutation: drop the Type comparison -> red ("a request of its session is not a reply in hand").
3. Given a read of the instances or of the replies that fails, then the copy is held and the evidence read still reads.
   - mutation: the new block's Catch sets `flightHeld = 0` -> `TestBusinessProcessReadFails` red ("... never makes it done", running 1).
4. Given a copy that stays held for the whole wait, then the wait ends at `WAITSECONDS` with the progress FixResult (`result.stillResending`) and one `LOGWAIT`, never hangs and never counts the copy as done.
   - mutation: drop the limit in `Waiting` (L938 `If (start = "") || (now '< (start + ..#WAITSECONDS)) Continue` made `If (start = "") Continue`) -> `TestHeldCopyStopsAtTheWait` red ("never read past it", a final result 3|3|0|3|0 instead of the progress report). It ends without hanging, because `StatusThen` lets the copies settle at read 151.
   - mutation: count held copies as done (`Tally`'s `If $IsObject(entry) && entry.inFlight` made `If 0`) -> red (a final 3|3|3|0|0 "All 3 orders went through." at the first pass).
5. Given the order status → instance → reply in hand → entry → second status, no read lands in the completion window unseen (Design Notes). No unit test can drive the window. Its evidence is Task 0 item 5 (0 wrong) and item 6 (the count without the reply check).
6. Every existing test passes unchanged:
   - `Test.Fix.Executor` (including DW-1205's `TestInFlightCopyIsStillRunning`, `TestSweepLeavesAnInFlightCopy` and `TestSweepCutsOffAnInFlightCopyOfAMarkedRun`);
   - `Test.Watch.Evidence` (including `TestInFlightHeader` and `TestInFlightEntryReadFails`);
   - `Test.Fix.Partial`, `Test.Fix.Reroute`, `Test.Watch.Reader`, `Test.Watch.GoodMessages`, `Test.Fix.Recheck`, `Test.Eval.Record` and `Test.Fix.Scale`.

## Design Notes

**Governing ADs:**
- AD-16 (the resend bullet and DW-1205's sentence; Reconcile and Sweep: "whose registered copies have all completed or failed").
- AD-3 (`Watch.Reader` is the one reader, and `Current` the one switching method; its list "headers, event log, settings, queues, vital signs" gains business process instances, read in the same method).
- AD-33 (End and Mark stay the only writers of a run's end).

AD-16's DW-1205 sentence names only the active message and a changing status, so it is amended (Veto item 4). Nothing else in the spine describes how copy outcomes are read.

**Why the instance check leads, and why it is not enough alone.**
- On a reply-waiting BP, the instance is the one Ens record that says "not finished" for the whole wait.
  - It is saved with its session (`BusinessProcess.cls:228`, inside `SendRequestAsyncInternal`, whenever a reply is required) before the copy is first set Completed (`:461`).
  - A BP that does not complete always has a pending reply registered there, because with none pending `OnComplete` runs and `%IsCompleted` becomes 1 (`:463-479`). So the session-indexed lookup finds it whenever the copy reads Completed.
  - Before that save the copy reads Delivered (`:264`), which `Tally` already counts as running. The first save (`:258`) has no session yet (`:259`) and is never needed.
- At completion IRIS deletes the instance (`Actor.cls:265`, or saves it with `%IsCompleted` 1 at `:219-221` when instances are retained). This comes before `OnGetReplyAction`, the user's `OnError`, the retry wait (`:388`, up to `RetryInterval`, 5 s by default), `SetStatus(Completed)` (`:452`), the log line (`:482`) and only then `SetStatus(Error)` (`:483`).
- So the instance alone leaves a window in which the copy reads Completed, has no instance and is not the active message. That window can be seconds long when the BP retries.
- Through that window the job still holds the reply header R as its active message (set at R's dequeue, `Queue.cls:317`; killed at `Host.cls:646`, after `:483`). R is a response of the copy's session, addressed to the BP, which is the copy's target (`MessageHeader.cls:95-105`).

**Why this order, and why it is complete.** Write T_d for the instance's delete, T_e for the copy's Error, and [D_R, K_R] for R's entry, with D_R < T_d < T_e < K_R. The reader reads the status at t0 (Completed), the instance at t1, the replies at t2 and the status again at t3, with t0 < t1 < t2 < t3.
- If t1 < T_d, the instance holds the copy.
- Otherwise t2 > T_d > D_R. If t2 < K_R, the reply holds it. Otherwise t3 > K_R > T_e, so the second read sees Error, not Completed, and the copy is in flight.
- On the first pass the copy is the active message until its pass ends, and the instance (saved before the copy read Completed) is there from then on. So the instance check after the status read always sees one of the two.
- DW-1205's own argument (status → entry → status) is untouched, because its entry check still sits between the two status reads.
- The other order, replies before the instance, would leave a gap: replies read just before R is dequeued, and the instance read just after it is deleted.

**Why only for a Completed first read.**
- Every other open status is already running.
- Error, Aborted, Discarded and Suspended reach the copy only after its instance has completed (`Actor.cls:265` comes before `:452-483`).
- A Suspended copy whose BP left an instance behind is rightly counted as failed again.
- This keeps the new reads off the incidents' evidence reads (Error headers). `Good`'s Completed headers get them, at the cost below.

**Why a failed read holds the copy.** The brief and the ruling say a failed read never counts a copy as done. A failed instance read cannot be decided by the second status read, because during the wait the status does not change. So the block holds the copy, and the run's time limit bounds it (matrix 7, 9).
- The statements are prepared lazily inside the block. A privilege that a tools user lacks then never fails an evidence read, and `inFlight` is read by `Executor.Read` alone.
- No log line is added, because that would be new text. If the read failed for good in the waiter's own process, every run with a Completed copy would end stillResending. Task 0 item 4 is the guard and a stop condition, and the Planner may want a reopen_if for it.
- DW-1205's entry read keeps its approved condition 2 (a failed entry read goes to the second read).

**The data seam.** `^||OcuTalonFlightSeam("process")` is a subnode of DW-1205's process-private seam global. It holds data only (1), runs no code, is set by no product code, and is killed on use. DW-1205's code reads only the top node with `$Get`, and its `Kill` of the whole global happens only after the new block has run. `OnAfterOneTest` already kills the whole global.

**The reply-in-hand check is not the rejected session signal.**
- The session signal calls a copy running while any message of its session is Queued or Delivered. A fan-out or disabled leg keeps that true for good.
- The reply check holds a copy only while a job is executing a reply of its session, addressed to the copy's own target. That is the BP's own job, working for this copy. It ends when the job lets go, so it can never hold for good.
- A hung job falls to the time limit, as in DW-1205's matrix 6. Its one false hold is a sibling copy of the same session and target, for one pass (matrix 10).
- It is an addition to the Planner's lead design, so it is listed as Veto item 6.

**Ens internals.**
- `Ens.BusinessProcess` is a documented persistent class, and SQL on it is how Ens itself reads this predicate (`Ens/Purge.cls:210-213`, the portal's `EnsPortal/BPInstances.cls:671-672`). Its storage global has no `$$$` macro, so SQL is the only safe read.
- The `%`-named fields are the class's own SQL names (Ens's embedded SQL uses them unquoted, `Actor.cls:236-241`).
- The query reads at READ UNCOMMITTED and takes no lock, so it never waits on the Actor's exclusive open of the instance (`Actor.cls:87`).
- `$$$EnsActiveMessage` is read as in DW-1205.

**Cost.** For each evidence header whose first read is Completed:
- one indexed `SELECT TOP 1` (the session's instance rows, usually 0 to a few, filtered by header and state);
- when there is no instance, one `$Order` pass over the active-message entries (at most one per busy job of the namespace), with at most one point read of three columns per distinct entry header per `Current` call (cached).

For the waiter that is per Completed copy per pass (`WAITPAUSE` 0.5 s); for Sweep it is per Completed copy of each unended run past its wait, per Tick. DW-1205's costs are unchanged. Task 0 item 8 measures 500 copies.

**Spine amendment (Veto item 4), word for word.** In AD-16 (`ARCHITECTURE-SPINE.md` L608), replace the sentence that begins "A copy counts as completed or failed again only once IRIS has let go of it:" and ends "[ADDED 2026-11-15, DW-1205 and DW-494, Contest Planner spec-gate ruling]." with:

"A copy counts as completed or failed again only once IRIS has let go of it: while its header is still a job's active message, or it reads `Completed` while a business process instance of it is not complete (`Ens.BusinessProcess`, `%PrimaryRequestHeader` the copy, `%IsCompleted` 0) or a job handles a response of its session addressed to its target, or its status changes while `Watch.Reader` reads it, it is still running, because IRIS sets an erroring copy `Completed` just before `Error` and sets a business process's request `Completed` at each pass while the process still waits for replies; a failed read of those instances or responses counts the copy as running, and the 60 s wait still bounds every copy that runs [AMENDED 2026-11-16, DW-1410, Contest Planner spec-gate ruling; it read "A copy counts as completed or failed again only once IRIS has let go of it: while its header is still a job's active message, or its status changes while `Watch.Reader` reads it, it is still running, because IRIS sets an erroring copy `Completed` just before `Error` [ADDED 2026-11-15, DW-1205 and DW-494, Contest Planner spec-gate ruling]."]."

(The date is the day of the edit.)

**Ledger inbox:** DW-1410 (this spec). Its status line is recorded per the run's DW process at merge, with Task 0's numbers through `ledger.sh append`.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | None. No catalog key, notice, log text or UI string is added or changed. A run against a reply-waiting BP gives its correct counts, for example "0 of 3 orders went through. 3 failed again (...)" in place of a wrong "3 of 3 orders went through." The 1.0.12 release note's "Known limit" line (DW-1205 spec) is the Planner's text: drop it if this ships in 1.0.12. | Approve (nothing to rule). |
| 2 | (b) Cross-lane edits | `Watch.Reader` (code and docs), `Fix.Executor` (docs only), `Test.Watch.Evidence` and `Test.Fix.Executor` are Lane A packages. AD-16 is in the spine. Lane C makes the edits under the Planner's assignment (DW-1410 rulings ~01:00Z and ~01:30Z Nov 16: HIGH, lane C, after DW-1205's push and DW-1389). At plan time no unmerged `OCT-*` branch touches these source files. Three touch the spine (`OCT-epic11`, `OCT-epic23`, `OCT-epic25-s258`), none of them in AD-16's resend bullet. This branch is based on DW-1205's head `fded9d158`, which is not yet merged to feature. | Approve, as the Planner's lane C assignment. The lead merges after DW-1205 and serializes against any Lane A story on `Fix/Executor.cls` or `Watch/Reader.cls`. |
| 3 | (c) Stored data or schema | None. No class, property, column or storage change, and no new member: the result is DW-1205's transient `inFlight`. The reader only reads `Ens.BusinessProcess`. The tests save and delete fixture `Ens.BusinessProcess` and header rows in OCUORDERS on throwaways only (Rule 21), cleaned up after each test. | Approve, with no migration. |
| 4 | (d) Architecture change | AD-16's DW-1205 sentence is amended, word for word under Design Notes. A copy also stays running while its business process instance is not complete or a job handles a reply for it, a failed read holds it, and the 60 s wait bounds it. `Watch.Reader` reads one more Ens table (`Ens.BusinessProcess`, SQL, read only) inside its one switching method (AD-3). This contradicts no AD. | Approve the amended sentence verbatim. |
| 5 | (e) Product behaviour change | A run whose copies went to a reply-waiting BP ends when the BP finishes with them, not at the BP's first pass. This is later than today, and bounded by the existing 60 s wait. A copy still held at 60 s gets the existing progress FixResult (`result.stillResending`) and `LOGWAIT`, and Sweep ends the run once it is let go. A BP instance that never completes (an aborted reply, a disabled callee) leaves the run executing, as a copy queued for good does today. A failed read of the instances counts the copy as running. Runs against BOs and against BPs that wait for nothing (the demo, the guide) are unchanged. | Approve. The counts become correct, and every new wait falls back to the progress path that exists. |
| 6 | Design beyond the ruling | Besides the ruled BP-instance check, a narrow reply-in-hand check: a job's active message that is a response of the copy's session addressed to the copy's target. IRIS deletes the instance before it writes the copy's final Error (`Actor.cls:265` before `:483`) and keeps the reply as the job's active message until after it (`Host.cls:646`), including through a retry wait of up to `RetryInterval`. This is not the rejected session signal. It holds only while a job executes that reply, so it can never hold for good, and its one false hold is a sibling copy for one pass. Task 0 item 6 measures the instance check without it. | Approve. Or rule it out, in which case Task 0 item 6's count becomes the known residual. |

## Public text

None. No new or changed sentence. The existing results (`result.failedAgain`, `result.allThrough`, `result.stillResending`) are used as they are, and now get the right counts.

Release note (the Planner's text, not product text): if this ships in 1.0.12, the "Known limit" bullet of DW-1205's release note no longer applies.

**Findability:** no UI change.

## Verification

Lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag>`.
- Fresh runs leave `OCUTALON_WARM` unset. A warm stack's production jobs keep the old code, so the production-level classes run fresh, and the production is restarted before a post-fix probe.
- One test class per foreground call, `timeout: 600000`, each under about 3 minutes. Split a class by method if it runs longer. Never two `iris_execute_tests` calls in one message.

**Commands:**
- (once) `ci/warm.sh up` with the warm tag, then Task 0 items 1 to 4 and item 8's "before", all before any product edit.
- (loop) Warm, each `ci/iris.sh class <Class>`, expected to pass:
  - `OcuTalon.Test.Watch.Evidence`
  - `OcuTalon.Test.Fix.Executor`
- (once) Warm, each expected to pass:
  - `OcuTalon.Test.Watch.Reader`
  - `OcuTalon.Test.Watch.GoodMessages`
  - `OcuTalon.Test.Fix.Recheck`
  - `OcuTalon.Test.Eval.Record`
- (once) Fresh, expected to pass: `ci/iris.sh shard lane-a@Fix`, which includes `Partial`, `Reroute`, `Executor` and `Scale` (Task 0 item 8's "after"); also `OcuTalon.Test.Watch.Evidence`.
- (once) Task 0 items 5 to 7 on the warm stack, after the product change is compiled and the production restarted.
- (once) Run `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call: each exits 0.
- (once) `git diff --name-only 872d8cb59` lists only the footprint files. No added code line holds the literal `Ens.ActiveMessage`, a non-ASCII character or an absolute local path.
- (once, at the end, also after a failure) `ci/warm.sh down` with the warm tag.

**Mutations (Rule 19):**
- One `mutation:` line per AC 1 to 4, as listed under Acceptance Criteria. Record each as `mutation: <change> -> <test that went red>`.
- Revert each byte for byte (`cmp` against a copy taken before it), and check that `git status --short` and `git diff --stat` are as before.
- AC 5 is recorded with Task 0's numbers (items 5 and 6), not a unit test.

**Task 0 records:** (to fill)

## Auto Run Result

Status: ready-for-dev
Blocking condition: none (the spec gate: Veto items 1 to 6)
