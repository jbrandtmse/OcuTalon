---
title: 'DW-1410: A copy that a business process is still handling is not counted as done'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
baseline_revision: '89fa33d6aa0a928faf75635d5964f56f872ae560'
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

### Review Findings

Code review stage (full mode, four layers, diff `89fa33d6a`..`17d5b904e` without bookkeeping). 19 findings: high 0, medium 2, low 11, false 6. Code review actions: 0 decision-needed, 4 patched (tests only), 1 deferred (ledger occurrence), 14 rejected. No product code changed.

- [x] [Review][Patch] (medium, verification-gap) The instance query's bindings were not pinned for a copy whose session is not its own id, as with every real resent copy: every instance fixture read had `%SessionId` = the header's id, so `%Execute(id, id)` passed every test. `TestBusinessProcessHoldsACopy` now also reads the sibling (Completed, session = the first header, an unfinished instance of its own) and asserts `Completed|1`. [src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls:587]
- [x] [Review][Patch] (low, verification-gap) `TestReplyInHandHoldsACopy`'s "once the job lets go of the reply" step went from not held to not held; the entry is now set back to the reply before `KillEntry`, so the step goes from held to not held. [src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls:634]
- [x] [Review][Patch] (low, edge-case-hunter) `TestReadOrderStatusInstanceReplyEntry` went on after a fixture instance failed to save, so the later read-order asserts would fail with misleading messages; it now quits there. [src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls:711]
- [x] [Review][Patch] (low, blind-hunter) The final `Test.Watch.Evidence` (19 methods, with QA's BPL and routing-engine instances) had run on build 154 only; it now passes fresh on build 109 (Verification, code review records).
- [x] [Review][Defer] (medium, acceptance-auditor+blind-hunter) `Test.Watch.Reader` `TestDisabledItemsInStoredOrderAcrossAStopAndAStart` is red in 4 of 4 fresh lane-C runs, so AC 6 is not literally met for that class [src/ocutalon/cls/OcuTalon/Test/Watch/Reader.cls] — deferred: pre-existing; it fails the same way with `Reader.cls` at `89fa33d6a` (`e21dw1410qr2`), the test reads the production state, not the evidence branch, and it is DW-626 (routed owner=burndown); an occurrence with these run tags was appended (`by=cr`).
- Confirmed: implement's rejected mediums (matrix 8: an instance that never completes holds its copy, so the wait ends stillResending and Sweep leaves the run executing) are the approved Veto 5 and matrix 8 behaviour, the same as a copy queued for good at a disabled target; the rejections stand.
- Confirmed: the reply-in-hand check cannot hold for good (it holds only while a job's active message is that reply, and a hung job falls to `WAITSECONDS`), and it cannot hold a copy of another session (`TestReplyInHandHoldsACopy` and `TestReplyInHandJudgesEachCopy`, both with mutations).

**Rejected:**
- (low, blind-hunter+edge-case-hunter) A failed instance or reply read holds the copy silently, with no log line: by-design. The spec rules out new log text (Design Notes, "Why a failed read holds the copy"), and Task 0 item 4 showed the job user `_Ensemble` (`%All`) can read `Ens.BusinessProcess`. It can reopen only through a spec amendment.
- (low, blind-hunter) The block's reads also run for callers that never read `inFlight` (Good, the dry run, EvidencePack, `Eval.Record`): by-design (matrix 14, Cost). `Test.Fix.Scale` did not slow down, and a flag would add a parameter.
- (low, blind-hunter) The reply match could use the reply's `BusinessProcessId` to drop replies to the original's own live instance: by-design. Matrix 10's one-pass false hold is approved, the counts are never wrong, and the fix adds a query and a branch.
- (low, blind-hunter) Task 0's records repeat items 2, 3 and 7 and run out of order: the fix edits the spec, and a reader is not misled (the numbers agree).
- (low, acceptance-auditor) The Verification footprint command names `872d8cb59`, but the baseline moved to `89fa33d6a`: the fix edits the spec. The check at `89fa33d6a` is recorded under Verification instead: footprint files plus bookkeeping only.
- (low, edge-case-hunter) `TestHeldCopyStopsAtTheWait`'s `Reads > 1` could fail if one read took over 3 s: wontfix-theoretical. QA's 5 runs under 16-core load passed, and so did this review's warm run.
- (low, edge-case-hunter) The upper bound `Reads '> 150` lets a wait that overruns up to fivefold pass: by-design. The gate approved the test as specified; its job is "never hangs", pinned by the drop-the-limit mutation.
- (low, edge-case-hunter) "sets a business process's request Completed at each pass" is loose (`Actor.cls:285` quits before the reset to the primary on a non-final response pass, so only request and retry passes and completion set it): by-design. It is the gate's verbatim AD-16 text and the spec's own doc text, and the mechanism the code relies on (the copy stays Completed through the wait) holds.
- (false, blind-hunter) The Auto Run Result leaves out QA's tests and runs: it covers the implement pass only (Rule 14); QA's work is under Verification's QA records.
- (false, blind-hunter) The last assert of `TestBusinessProcessHoldsACopy` is mislabelled: at that point the only unfinished instance in the header's session is the sibling's, which is exactly the label's case, and the `%PrimaryRequestHeader` mutation went red there.
- (false, acceptance-auditor) QA's three extra tests and `Retarget` go beyond the footprint: they are in the footprint's `Test/Watch/Evidence.cls`, and `Retarget` updates a fixture header the test made, in OCUORDERS on a throwaway (Veto 3).
- (false, acceptance-auditor) `deferred-work.md` changed at implement: that was the sanctioned `ledger.sh append` of the push numbers (the Auto Run Result lists it), and bookkeeping is out of the review diff by the stage prompt.
- (false, acceptance-auditor) Task 0 item 1(a) used `E=RF` and not `E=R`: the recorded reason holds (`E=R` ends the copy Completed, so no count of it can be wrong).
- (false, edge-case-hunter) An instance whose `%SessionId` is NULL hides a waiting process: the save at `BusinessProcess.cls:228`, the one a reply-required call makes, follows `:259`, so it carries the session. Actor's session-less fallback `UPDATE` (`Actor.cls:219-236`) runs only after a failed save, and `SaveExit` (`:199-215`) has by then set `%IsCompleted` 1, so that row is never a waiting instance.

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

## Spec gate rulings (Contest Planner, ~02:30Z Nov 16, BINDING): APPROVED, all items

- Design: the read order (status, instance, reply in hand, DW-1205's entry check, second status read) APPROVED. Veto 6 (reply in hand) APPROVED; its one false hold for a single pass is accepted; Task 0 still measures the instance-only check for the record. Any failed read holds the copy (prepare, SQL privilege, <PROTECT>, <UNDEFINED>, negative SQLCODE); the 60 s wait bounds it. TestHeldCopyStopsAtTheWait with its two mutations APPROVED.
- Task 0 is a HARD GATE:
  - STOP if the executor's or the sweep's users lack SELECT on Ens.BusinessProcess: report which grant is missing; never add a grant without the Planner.
  - PUSH CONDITION: 0 wrong in 300 at 1 ms, unloaded and loaded; 0 wrong in 30 at 1 s; no false "still running" on the fan-out with a disabled leg.
  - Record Fix.Scale before and after; a slowdown over 10% goes back to the Planner.
- (a) No new public text (if DW-1410 ships in 1.0.12 the Planner drops DW-1205's "known limit" release-note line). (b) Cross-lane GRANTED (Watch.Reader, Fix.Executor docs, the two test classes, AD-16); merges after DW-1205. (c) No stored-data change. (d) The AD-16 sentence is REPLACED verbatim as given in this spec. (e) Behaviour approved as described.

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

**Run split (stage prompt, binding):** Task 0 items 1 to 4, item 2, item 3, item 7 and item 8's "before" are done and recorded below, on the lane-C warm throwaway with tag `e21dw1410iw` (already up; the lane lock is held by the stage agent: do not run `ci/warm.sh up` or `down`, and use it for the `(loop)` and `(once)` warm classes only). The implement subagent does the Execution tasks, the warm test classes, and the Rule 19 mutation runs (record each `mutation:` line under Verification; revert byte for byte with `cmp`; the two approved time-limit mutations for AC 4 are (a) drop the limit in `Waiting` and (b) `Tally`'s `inFlight` test made `If 0`). The stage agent itself does Task 0 items 5, 6 and the push-condition runs, the fresh runs (`lane-a@Fix`, `Test.Watch.Evidence`) on builds 154 and 109, `Scale` after, the scripts and the lint.

**Task 0 records:**
- Setup (lane C warm throwaway, tag `e21dw1410iw`, build 154; scratch classes in the lead's scratch folder only, never committed): `ZzScratch.CallBP` (1 ms `OkBO`), `SlowBP` (the 1 s operation), `RetryBP` (CallBP with `ReplyCodeActions` `E=RF`, `RetryInterval` 1, `FailureTimeout` 3), `SyncBP` (`SendRequestSync` then an error), `FanBP` (a no-reply send to the disabled `ZzScratchOffBO`, then the CallBP call), and `RespRace` in OCUTALON (Run, Watch with `i` and `r`, the session-signal emulation). Ens queues to a disabled item without error: the leg's header stays Queued (Status 2) for good. The BPL variant (item 1d) is recorded below.
- Item 1, retry wait: the spec's `E=R` ends the copy Completed (9), not Error, after `FailureTimeout` (`finalReplyAction`'s else branch turns the error into OK and logs a warning), so no count of it can be wrong. The scratch uses `E=RF`, which ends the copy Error (8) after the 3 s.
- Item 4 (the gate, passed): the production's jobs, where `Executor.Read` and Sweep run, run as `_Ensemble` (role `%All`); `CheckPrivilege(<user>, 1, <table>, "s")` in OCUORDERS gives `_Ensemble` 1 for `Ens.BusinessProcess` and 1 for `Ens.MessageHeader`. The service user `OcuTalonService` (role `OcuTalonServiceRole`) gives 0 for both, so no user can read `Ens.MessageHeader` and not `Ens.BusinessProcess`. A bare `Ens.BusinessProcess` row saves in OCUORDERS with `%New("zzPollerTarget")` (`%PrimaryRequestHeaderSetObjectId`, `%SessionId`, `%IsCompleted`). The instance query's plan: "Read index map Ens.BusinessProcess.SessionId, using the given %SessionId, and looping on ID", then the master map, with the other conditions tested per row.
- Item 2 (the current code, DW-1205 only; `Run` = trials with 3 copies each; wrong = a count of completed while the copy ends Error): CallBP 1 ms `Run(300)` unloaded 83 wrong; loaded 131 wrong (16 `yes`, killed after); 1 s reply `Run(30)` loaded 30 wrong; RetryBP (`E=RF`) `Run(20)` 20 wrong; SyncBP `Run(100)` loaded 0 wrong (matrix 5); FanBP `Run(30)` 11 wrong.
- Item 3, order at completion (`i` an instance exists by the product's query, `r` a reply is in hand, `a` the header is a job's active message; ms since the send): CallBP 1 ms `9i@2.3 9ir@2.6 9r@2.9 8@3.1`; CallBP 1 s `9i@2.5 9ir@1002.5 9r@1003.4 8@1003.6`; RetryBP `9ir@2.5 9r@3.1 3r@1003.9 9i@1004.1 9ir@1005.9 9r@1006.2 3ir@2007.0 9i@2007.3 9ir@2009.6 9r@2010.0 3r@3010.9 3ir@3011.0 9i@3011.2 9ir@3013.3 9r@3013.6 8@3014.0`. Every watch (6 of CallBP 1 ms, 3 of 1 s, 6 of RetryBP) shows `9r` without `i` before `8`: the instance is gone while the copy still reads Completed and the job still holds the reply.
- Item 7 (the session signal, scratch emulation, DW-1205's `Reader` untouched): CallBP 1 ms `Run(300)` loaded 66 wrong; 1 s `Run(30)` loaded 9 wrong; FanBP `Run(30)` 30 of 30 trials still called running at the 5 s cap although all three copies had reached Error (false still-running).
- Item 8, before (`Test.Fix.Scale`, 500 copies): fresh 22.29 s; warm 22.19, 20.22 and 20.24 s.

- Item 1d, the BPL variant (`ZzScratch.BplBP`: `<call>` async to the OkBO, `<sync>`, then `<throw>`; a `<sequence>` wrapper is required): it shows the same sequence (`9i@2.0 9ir@2.8 9r@3.5 8@3.6`, `9ia 9i 9ir 9r 8`), and `Run(100)` on the fixed code, loaded, gave 0 wrong. The old code was not run on it.
- Item 5, the fix measured (the warm stack was taken down and brought up again after the last product edit, so its production jobs run the final code: the image is built from the tree at that start; scratch classes loaded after; `Reader.cls` is byte-identical to the file the stack started with, `cmp`; build 154): CallBP 1 ms `Run(300)` unloaded 0 wrong (reads 460, 206 in flight); loaded 0 wrong (reads 699, 583 in flight); 1 s reply `Run(30)` loaded 0 wrong; RetryBP `Run(20)` 0 wrong, none ended at the cap; SyncBP `Run(100)` loaded 0 wrong; FanBP `Run(30)` 0 wrong, 0 of 30 trials ended at the 5 s cap (no false still-running); BplBP `Run(100)` loaded 0 wrong. The push condition holds (0 wrong in 300 at 1 ms unloaded and loaded, 0 in 30 at 1 s, no false still-running on the fan-out).
- Item 6, the instance check alone (the reply-in-hand condition made `If 0 && ...`, compiled, run, then `Reader.cls` restored with `cp` and checked with `cmp`): RetryBP `Run(20)` 11 wrong; CallBP 1 ms `Run(300)` loaded 10 wrong. So the reply-in-hand check is needed: the instance check alone leaves the completion window.
- Item 7 (the session signal, for the record): wrong 66 of 300 (CallBP 1 ms, loaded) and 9 of 30 (1 s, loaded) while still calling every FanBP trial (30 of 30) running at the 5 s cap.

- Item 8, after (`Test.Fix.Scale`, 500 copies, fresh stack inside the `lane-a@Fix` shard, build 154): 18.67 s, against 22.29 s before (fresh) and 20.2 to 22.2 s (warm): no slowdown, so no line is needed.
- Fresh runs, build 154, final code (`ci/iris.sh`, one per call): `shard lane-a@Fix` passed (29 classes, 1029 s; `Test.Fix.Executor` 42.15 s, `Test.Fix.Recheck` 1.66 s, `Test.Fix.Partial` 48.82 s, `Test.Fix.Reroute` 7.24 s; one existing SKIP, DW-399, in `TestRunOfAStoppedWaiterEnds`); `Test.Watch.Evidence` passed (16 methods, 3.29 s).
- `Test.Watch.Reader`, fresh, build 154: 17 of 18 pass; `TestDisabledItemsInStoredOrderAcrossAStopAndAStart` fails ("stopped, with the disabled items: suspended") in both runs. With `Reader.cls` put back to HEAD (the DW-1205 code) the same class fails the same way in the same test on a fresh stack, so it is not this change: it is the ledger's DW-626 flake (same text, seen in CI on unchanged reruns). `Reader.cls` restored with `cp` and `cmp`, tree unchanged. The six failures the implement subagent saw on the warm stack were caused by the scratch items in that stack's Orders production.
- Fresh runs, build 109 (`IRIS_IMAGE` the 2027.1.0AI.109.0 community image, final code): `shard lane-a@Fix` passed (29 classes, 1034 s; `Test.Fix.Scale` 20.05 s); `Test.Watch.Evidence` passed (16 methods, 3.36 s).
- Scripts and lint: `bash docker/tests/test-boundaries.sh` exit 0 (all rules passed); `bash docker/tests/test-class-rules.sh` exit 0 (all rules passed); the spine lint reports 12 findings, all low, as at the baseline (none added).
**Implementation records** (implement subagent, lane C warm throwaway `e21dw1410iw`, build 154; HEAD `89fa33d6a`, uncommitted):
- Warm-stack note: `ci/iris.sh class` refused to run ("FAIL WARM stale: src/ocutalon/csp/3rdpartylicenses.txt changed since warm up", the file was rewritten at 17:51, after the warm up at about 17:32; only classes reload and the stage agent owns `ci/warm.sh down` and `up`). The classes were therefore loaded into the warm container with `docker exec ... iris session IRIS -U OCUTALON` (`$SYSTEM.OBJ.Load` of the bind-mounted `/opt/ocutalon/warm-src/...` files, then `Compile` with `cb-d`), and run with the very `class_script` of `ci/iris.sh` (one class or method per call). Scripts are in the scratch folder only. The stack's stored manifest is unchanged, so the stage agent still needs `ci/warm.sh down` and `up` before any later `ci/iris.sh` call on this tag.
- Warm, whole classes, build 154: `Test.Watch.Evidence` passed (16 methods, 2.9 s; the three new ones in), `Test.Fix.Executor` passed (48 methods, 45.6 s; the new one in), `Test.Watch.GoodMessages` passed (10 methods, 132.5 s), `Test.Fix.Recheck` passed (3 methods, 62.4 s), `Test.Eval.Record` passed (20 methods, 51.3 s).
- `Test.Watch.Reader` on the warm stack: 18 methods, 6 fail (`TestDisabledBySystemDefaultSetting`, `TestDisabledItems`, `TestDisabledItemsInStoredOrderAcrossAStopAndAStart`, `TestFailuresState`, `TestFailuresStateCodes`, `TestStoppedProduction`: the asserts list `ZzScratchOffBO`, the stage agent's scratch item that Task 0 added to the Orders production, as a disabled item, and the state reads suspended where the tests expect stopped). They test disabled items and the production state, not the evidence branch that this change edits. They need a stack without the scratch items: the stage agent's fresh run decides.
- `bash docker/tests/test-class-rules.sh` exit 0 ("all rules passed"). `git diff --name-only` lists the spec, the spine, `Watch/Reader.cls`, `Fix/Executor.cls`, `Test/Watch/Evidence.cls` and `Test/Fix/Executor.cls`. No added code line holds `Ens.ActiveMessage`, a non-ASCII character or an absolute local path.

**Mutation records** (warm `e21dw1410iw`, build 154; each mutation applied, loaded, the one test method run, then reverted with `cp` and `cmp` against a copy taken before it, `git status --short` and `git diff --stat` the same as before, and the class reloaded):
- AC 1: mutation: `If flightRows.%Next() Set flightHeld = 1` made `If 0 Set flightHeld = 1` -> `TestBusinessProcessHoldsACopy` red ("a Completed header whose business process is not complete is in flight", "Read carries inFlight", "Tally gives completed 0, failed again 1, running 1").
- AC 1: mutation: drop ` AND (%IsCompleted = 0 OR %IsCompleted IS NULL)` from the query -> `TestBusinessProcessHoldsACopy` red ("a completed instance does not hold it", "Tally gives completed 1, failed again 1, running 0").
- AC 1: mutation: `AND %PrimaryRequestHeader = ?` made `AND ? IS NOT NULL` (the session only, the same parameters) -> `TestBusinessProcessHoldsACopy` red ("a completed instance does not hold it", "Tally gives completed 1, failed again 1, running 0", "another header's unfinished instance in its session does not hold it").
- AC 1: mutation: `If flightFirst = $$$eMessageStatusCompleted {` made `If 1 {` -> `TestBusinessProcessHoldsACopy` red ("an Error header is final, whatever its instance", "Read carries inFlight", both Tally lines).
- AC 2: mutation: the reply-in-hand condition made `If 0 && (...)` -> `TestReplyInHandHoldsACopy` red ("a job that handles a reply of its session to its target holds it").
- AC 2: mutation: drop `&& ($List(flightInfo, 1) = sessionId)` -> `TestReplyInHandHoldsACopy` red ("a reply of another session does not").
- AC 2: mutation: drop `&& ($List(flightInfo, 3) = $$$eMessageTypeResponse)` -> `TestReplyInHandHoldsACopy` red ("a request of its session is not a reply in hand").
- AC 3: mutation: the new block's Catch sets `flightHeld = 0` -> `TestBusinessProcessReadFails` red ("a failed read of the business process instances never makes it done: it is in flight", "Tally counts the copy as running, never completed").
- AC 4: mutation: drop the limit in `Waiting` (`If (start = "") || (now '< (start + ..#WAITSECONDS)) Continue` made `If (start = "") Continue`) -> `TestHeldCopyStopsAtTheWait` red ("the wait stopped at its limit and never read past it: 151 reads", then the request, the FixRun, the result, the audit, the `LOGWAIT` and the later-wait asserts); it ended without a hang, 15.5 s, at read 151.
- AC 4: mutation: `Tally`'s `If $IsObject(entry) && entry.inFlight {` made `If 0 {` -> `TestHeldCopyStopsAtTheWait` red (1 read, the copies counted done at the first pass, and every later assert).
- AC 2 (review patch): mutation: drop `&& ($List(flightInfo, 2) = target)` from the reply-in-hand condition -> `TestReplyInHandHoldsACopy` red ("a reply of its session addressed to another target does not"); reverted with `cp` and `cmp` against a copy taken before, `git status --short` and `git diff --stat` as before, `Test.Watch.Evidence` green again (warm, 16 methods).

**QA records** (QA stage, lane C; warm tag `e21dw1410qw` for the test work, build 154; `Reader.cls` untouched by QA, `cmp` against a copy at the start and after every mutation):
- Gaps checked against the ACs and the matrix:
  - The read order (AC 5). The window itself cannot be driven, but the order of the checks can be pinned with data only, through the two seams. The new block runs only for a first read of Completed, before the entry check, and the entry check runs only when that block did not hold the header: a header held by an instance, by a reply in hand or by a failed instance read leaves DW-1205's status seam (`^||OcuTalonFlightSeam`) unread, and one that nothing holds takes it. `TestReadOrderStatusInstanceReplyEntry` pins that. Not pinnable: the order of the instance check and the reply-in-hand check (both give held, so no data shows which ran first), and the second status read after the entry check beyond DW-1205's own `TestInFlightEntryReadFails`. The reply-in-hand check itself runs with no instance (`TestReplyInHandHoldsACopy`, AC 2).
  - A failed read holds the copy. The instance read is pinned by `TestBusinessProcessReadFails` and now also by its place in the order. The reply read cannot be made to fail with data: every entry value tried (non-numeric, 1e999, a list, a header id that does not exist) gives SQLCODE 0 and no row, and a missing header is read as "not a reply" (now pinned, below). A failed prepare (inside the same Try as both reads, so the same Catch holds the copy) cannot be seeded without a user that lacks SELECT on `Ens.BusinessProcess`, which means a role and a user in `%SYS`, a security change that a test must not make. The `("process")` seam throws before the prepare, so it pins the Catch and not that the prepare is inside the Try. Recorded, not pinned: reopen_if a production user loses SELECT on `Ens.BusinessProcess` (the review's own reopen).
  - A reply in hand for a different copy of the same session and target (matrix 10): `TestReplyInHandJudgesEachCopy` reads four Completed copies at once (two of one session) against two jobs' replies and two entries whose header cannot be read. The copy and its sibling are both held, a copy of a session with no reply in hand is not, and the hold ends when that job lets go of its reply (a second Tally shows 4 completed). The false hold is bounded by the job's entry, it keeps no state, and no copy of another session is held by it. An entry whose header does not exist or cannot be read holds nothing and never throws.
  - A BPL business process instance (shared extent): `TestBusinessProcessOfAnyKindHoldsACopy` saves unfinished instances of `Ens.BusinessProcessBPL` and of `EnsLib.MsgRouter.RoutingEngine` (a hand-coded subclass): both hold a Completed header, and once completed neither does. The scratch BPL run (`Run(100)`, 0 wrong) in Task 0 is the live evidence.
  - The SQL statements prepared lazily inside Try: see the failed-read item above (the Catch is pinned, the position of the prepare is not).
- New pins, each demonstrated red then reverted byte for byte (`cmp` against the copy taken before; `git status --short` as before; class reloaded and green after):
  - mutation: the DW-1205 block's wrapper `If 'flightHeld {` made `If 1 {` -> `TestReadOrderStatusInstanceReplyEntry` red ("the entry check did not run for a header that the instance held", "... the reply in hand held", "and the entry check did not run after it").
  - mutation: the same wrapper made `If 0 {` -> `TestReadOrderStatusInstanceReplyEntry` red ("with nothing holding it, the entry check runs ...", "the entry check took the seam").
  - mutation: the new block's `If flightFirst = $$$eMessageStatusCompleted {` made `If 1 {` -> `TestReadOrderStatusInstanceReplyEntry` red ("an Error header is not held by its instance", "the block of the instances did not run for it").
  - mutation: `FROM Ens.BusinessProcess WHERE` made `FROM Ens.BusinessProcessBPL WHERE` -> `TestBusinessProcessOfAnyKindHoldsACopy` red ("an unfinished instance of a BPL process holds its header, and so does one of a subclass of the extent ...").
  - mutation: `FROM Ens.BusinessProcess WHERE` made `FROM EnsLib.MsgRouter.RoutingEngine WHERE` -> `TestBusinessProcessOfAnyKindHoldsACopy` red (same assertion, and "completed instances of either kind do not hold their headers").
  - mutation: `WHERE %SessionId = ?` made `WHERE ID NOT IN (SELECT ID FROM Ens.BusinessProcessBPL) AND %SessionId = ?` -> `TestBusinessProcessOfAnyKindHoldsACopy` red (the BPL assertion).
  - mutation: `If '$Data(flightSeen(flightId)) {` made `If '$Data(flightSeen) {` -> `TestReplyInHandJudgesEachCopy` red (each copy judged by its own session, both Tally lines).
  - mutation: `(flightInfo '= "") && (` made `(` -> `TestReplyInHandJudgesEachCopy` red (the same assertions: an entry that names no header threw and held every copy).
  - mutation: `$List(flightInfo, 2) = target)` made `$List(flightInfo, 2) = target) && (id = sessionId)` (hold only the copy whose id is its session, which no resent copy is) -> `TestReplyInHandJudgesEachCopy` red ("... the copy and its sibling are held by the reply of their session ...", "Tally counts the three held copies as running ...").
- Test changes: `Test/Watch/Evidence.cls` only (three methods, `ReadsOf`, a `class` argument on `FixtureProcess`/`MakeProcess`, the `:1` to `:4` entry cleanup, header bullets). No product change by QA. `bash docker/tests/test-class-rules.sh` exit 0. No added line holds a non-ASCII character or an absolute local path.
- Regression on fresh lane-C stacks (one throwaway per run, tags `e21dw1410qa1-5`, `qb1-5`, `qc1-5`; one `yes > /dev/null` per core, 16, started in the container once it was ready and gone with it): `Test.Fix.Partial` 5/5 passed (48.98 to 54.22 s), `Test.Fix.Reroute` 5/5 passed (8.11 to 10.77 s), `Test.Fix.Executor` 5/5 passed (46.47 to 48.85 s, the new `TestHeldCopyStopsAtTheWait` in). `Test.Watch.Evidence` fresh with the QA tests: passed.
- DW-626: `Test.Watch.Reader` `TestDisabledItemsInStoredOrderAcrossAStopAndAStart` fails on a fresh stack the same way on HEAD (run `e21dw1410qr1`) and with `Reader.cls` at `89fa33d6a` (run `e21dw1410qr2`, `Reader.cls` put back with `cp` and `cmp`): "stopped, with the disabled items: suspended|[PartnerOrdersIn,OrdersToWarehouse]", no other test of the class failed. The ledger's DW-626 has the same test and the same text ("stopped, with the disabled items: suspended") in repeated occurrences, on units with no Watch change. It matches; it is not this change.

**Code review records** (code review stage, lane C; warm tag `e21dw1410cw` and fresh tag `e21dw1410cf`; HEAD `17d5b904e`; no product change by the review):
- Warm, build 154, before the patches: `Test.Watch.Evidence` passed (3.54 s) and `Test.Fix.Executor` passed (40.83 s, `TestHeldCopyStopsAtTheWait` in).
- Test patches (`Test/Watch/Evidence.cls` only; see Review Findings). Then warm `Test.Watch.Evidence` passed (2.90 s).
- mutation: `flightProcess.%Execute(sessionId, id)` made `flightProcess.%Execute(id, id)` -> `TestBusinessProcessHoldsACopy` red ("a Completed copy in another header's session (a resent copy keeps its original's) is held by its own unfinished instance"), the only red. Reverted with `cp` and `cmp` against a copy taken before; `git status --short` and `git diff --stat` were as before, `Reader.cls` is at HEAD, and `Test.Watch.Evidence` was green again warm (2.88 s).
- Fresh, build 109 (`IRIS_IMAGE` the `irishealth-community:2027.1.0AI.109.0` image), the final class with the review patches: `ci/iris.sh class OcuTalon.Test.Watch.Evidence` passed (3.59 s; stack ready in 136 s).
- No product code was patched, so the fresh `lane-a@Fix` shard and the push-condition probe were not re-run; implement's runs on this `Reader.cls` stand.
- `bash docker/tests/test-class-rules.sh` exit 0. `git diff --name-only 89fa33d6a` (the baseline now) lists only the spec, the spine, `Watch/Reader.cls`, `Fix/Executor.cls`, the two test classes and the bookkeeping files (`cycle-log-epic-21.md`, `deferred-work.md`).
- AD-3 grep over the added lines of `git diff 89fa33d6a`: no raw `^Ens` global, no `Xecute`, no `@` indirection, no literal `Ens.ActiveMessage`, no non-ASCII and no absolute local path. The only `Execute` hits are `%SQL.Statement`'s `%Execute`. The new reads sit in `Current`'s evidence branch, under its one `New $NAMESPACE` / `Set $NAMESPACE = namespace` (L642-644).
- The probe evidence here (Task 0 items 5-7, `Scale`) matches DW-1410's two `by=implement` ledger notes.

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 27 findings — high 0, medium 5, low 16, false 6, maybe-false 0
- findings:
  - `[false]` `[reject]` (intent-alignment) Tests exercise reader fixtures and canned statuses, not a live BP — the live surface is Task 0 items 5-6 (real BP, real BO reply, real Actor), run on the throwaway and recorded under Verification; AC 5 says no unit test can drive the window.
  - `[false]` `[reject]` (intent-alignment) The instance filter `%IsCompleted = 0 OR %IsCompleted IS NULL` and the no-session skip are the spec's own query and rule (Execution task, Matrix), not a divergence.
  - `[false]` `[reject]` (blind-hunter) The comment 'IRIS deletes the instance before it writes the final status' is Actor.cls:265 (`%DeleteId` after `%IsCompleted` 1, unless RetainCompletedInstances); BusinessProcess.cls only marks it, so the claim holds.
  - `[low]` `[reject]` (blind-hunter) AD-16's 'the 60 s wait still bounds every copy that runs' is the Planner's verbatim sentence (spec gate: REPLACED verbatim); the run staying executing with a held copy is matrix rows 7 and 8 and Veto 5, approved. Residual risk noted in Auto Run Result.
  - `[low]` `[reject]` (blind-hunter) No-session case: the spec states 'A header without a session is not looked up' and why (Ens gives every header a session); a header without one falls to DW-1205's checks. Not worth a test.
  - `[low]` `[reject]` (blind-hunter) Only the instance read has a seam by the spec's single data seam; both reads share one Try, so the Catch mutation pins both. A real SQL failure needs a privilege-less user (Task 0 item 4 checked the grant); reopen_if=a production user loses SELECT on Ens.BusinessProcess.
  - `[low]` `[reject]` (blind-hunter) `IS NULL` branch mirrors Ens's own predicate (Purge.cls:210-213); a NULL row cannot be produced by the Actor; no user-reachable failure.
  - `[low]` `[reject]` (blind-hunter) Two scans and cost on large resends: the cache bounds queries; Task 0 item 8 measured Test.Fix.Scale (500 copies) before and after.
  - `[false]` `[reject]` (blind-hunter) The 2026-11-16 stamp is the UTC day of the edit (IRIS and the spec's `created` are 2026-11-16); the spec says the date is the day of the edit.
  - `[low]` `[reject]` (blind-hunter) The AD-16 sentence is long because the Planner's verbatim text is; spec-bound, not editable here.
  - `[false]` `[reject]` (blind-hunter) The bare `Ens.BusinessProcess` fixture saves and reads in OCUORDERS (Task 0 item 4 and the three new tests pass, Evidence 16 methods).
  - `[low]` `[reject]` (blind-hunter) TestHeldCopyStopsAtTheWait is the approved 'Pin it' test with its two approved time-limit mutations (AC 4); it is meant to pin the wait's limit, not the reader.
  - `[medium]` `[reject]` (edge-case-hunter) A BP instance that never completes keeps `inFlight` 1, so Sweep leaves the run executing: this is matrix row 8 and Veto 5, approved ('as it does today for a copy still queued at a disabled target'); closed by-design, residual risk noted.
  - `[medium]` `[reject]` (edge-case-hunter) Same root cause as the row above (persistent held copy feeds Sweep): by-design, matrix 8.
  - `[low]` `[reject]` (edge-case-hunter) A sessionless reply matching a sessionless copy: Ens gives every header a session; theoretical (wontfix-theoretical).
  - `[low]` `[reject]` (edge-case-hunter) Siblings of one session and target hold each other for one pass: matrix row 10, accepted by the gate; the counts are never wrong.
  - `[low]` `[reject]` (edge-case-hunter) Per-copy instance query on a 500-copy session: indexed by session and the rows are the unfinished instances only; Scale measured.
  - `[low]` `[reject]` (edge-case-hunter) The `flightSeen` cache holds only fields that never change per header; a header unreadable now is read as not-a-reply and the next pass re-reads it. Bounded by the active-message entries of one call.
  - `[false]` `[reject]` (edge-case-hunter) The control assertion does pin the PrimaryRequestHeader condition: mutation 3 (drop it) went red on 'another header's unfinished instance in its session does not hold it'.
  - `[medium]` `[reject]` (edge-case-hunter) The claim 'never hangs' is about the wait (it ends at WAITSECONDS with the progress FixResult), as TestHeldCopyStopsAtTheWait pins; the run staying executing is the approved matrix row 7/8 behaviour. Same root as the first row.
  - `[medium]` `[reject]` (verification-gap) The read order is not pinned by a committed test: spec AC 5 says no unit test can drive the window; its evidence is Task 0 items 5 and 6 (0 wrong; the instance check alone leaves 11 of 20 and 10 of 300 wrong). By-design.
  - `[medium]` `[patch]` (verification-gap) The reply's target comparison had no test or mutation. Patched: TestReplyInHandHoldsACopy makes a reply of the copy's session addressed to another target (Retarget helper) and asserts Completed|0; mutation recorded and shown red, reverted byte for byte.
  - `[low]` `[reject]` (verification-gap) `%SQLCODE < 0` throw lines have no test: they are DW-1205's own pattern, a privilege-less user is not producible in a warm test, and Task 0 item 4 checked the grant of the users that run the reads; reopen_if=a production user loses SELECT on Ens.BusinessProcess.
  - `[low]` `[reject]` (verification-gap) Spec status fields mismatch (Auto Run Result 'ready-for-dev') is the finalization step's to set; not a code issue.
  - `[low]` `[reject]` (verification-gap) AC 5 has no pinning test and AC 6 no mutation line: AC 5 is recorded with Task 0 numbers by the spec's own rule, AC 6 is the regression suite.
  - `[low]` `[reject]` (verification-gap) The DW-1205 top-node seam can leak to a later header when the new block holds the header: test-only, in this process, killed by OnAfterOneTest; no shipped test sets both.
  - `[low]` `[reject]` (verification-gap) A failed second prepare re-prepares for each later Completed header of the call: correct (a failure holds the copy) and bounded by the call.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `Watch.Reader.Current` now holds a header whose first read is Completed while a business process instance of it is not complete (SQL on `Ens.BusinessProcess` through the session index) or a job handles a response of its session addressed to its target; any failed read of those holds the copy. DW-1205's entry check and second status read run after it, only when the header is not already held. `Fix.Executor`, `Tally`, `Read` and Sweep are unchanged (docs only), so a held copy is counted as running, bounded by the existing 60 s wait. AD-16's DW-1205 sentence is replaced with the spec's verbatim.

**Files.**
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`: the new block, the class and `Current` docs.
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls`: docs only.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls`: `TestBusinessProcessHoldsACopy`, `TestReplyInHandHoldsACopy` (with the review patch for the reply's target), `TestBusinessProcessReadFails`, fixtures and cleanup.
- `src/ocutalon/cls/OcuTalon/Test/Fix/Executor.cls`: `TestHeldCopyStopsAtTheWait`.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: AD-16 sentence replaced, `updated:` refreshed.
- `_bmad-output/implementation-artifacts/deferred-work.md`: the push-condition numbers appended to DW-1410 (`ledger.sh append`).
- This spec.

**Review.** 27 findings from four layers: high 0, medium 5, low 16, false 6. One patch applied (medium: the reply's target comparison had no pin; a test and a mutation line were added). Everything else rejected with the reason in the triage log (by-design for the matrix 7/8/10 behaviours, false for claims the code or the mutation runs disprove, low for theoretical or cost-only items). Follow-up review: false (no high patched).

**Verification.** Task 0 gate passed (the job user `_Ensemble` has SELECT on `Ens.BusinessProcess`). Push condition measured after the fix on the lane-C throwaway: 0 wrong in 300 at 1 ms unloaded and loaded (the old code: 83 and 131 wrong), 0 in 30 at 1 s (old: 30), RetryBP 0 in 20 (old: 20), SyncBP 0 in 100, FanBP 0 in 30 with no false still-running (old: 11 wrong), BPL 0 in 100. The instance check alone: RetryBP 11 of 20 and CallBP 1 ms loaded 10 of 300 wrong. The session signal: 66 of 300 and 9 of 30 wrong, and 30 of 30 false still-running on the fan-out. `Test.Fix.Scale` 22.29 s before, 18.67 s after (build 154) and 20.05 s (build 109). Fresh `lane-a@Fix` and `Test.Watch.Evidence` pass on builds 154 and 109. The mutation lines are recorded above, each red then reverted byte for byte.

**Residual risks.**
- A business process instance that never completes (an aborted reply, a disabled callee, a long alarm) holds its copy for good: the wait ends at 60 s with the progress result, and Sweep leaves the run executing, as it does today for a copy queued at a disabled target (matrix 8, Veto 5; approved).
- `Test.Watch.Reader` `TestDisabledItemsInStoredOrderAcrossAStopAndAStart` fails on a fresh stack both with and without this change (DW-626 flake family).
- The order argument (AC 5) has no committed test; its evidence is the throwaway measurements above.
