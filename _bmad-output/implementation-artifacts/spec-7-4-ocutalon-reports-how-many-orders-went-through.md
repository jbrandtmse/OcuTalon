---
title: 'OcuTalon reports how many orders went through'
type: 'feature'
created: '2026-10-28'
status: 'done'
baseline_revision: '9924a173c58c6526ec834aa630483946358bdfb4'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Since Story 7.3 an approved fix resends repaired copies and registers each copy's header id on its `FixRun`. Then the run simply stops (U-140): the request stays `executing` and the incident `fixing`. No `FixResult`, result notice or OcuTalon `Action` audit entry is ever produced. The incident payload and `/state` show no result for any request (DW-272, DW-292). A copy that fails again also joins its group as if it were a new failure. And `FixExecutor` (PoolSize 1) also answers every dry-run ask, so a 60-second wait in its job would hold up other incidents' notices (DW-381).

**Approach:**
- `FixExecutor` waits up to 60 seconds for the run's registered copies. It counts them and stores the counts on the run's `FixRun`. It closes the request, writes one `Action` entry and sends the one final `FixResult`.
- `IncidentManager` moves the incident and tells the recipients, as it already does (Story 7.3). The incident payload's request entry now carries the stored result, for events and for `/state` alike.
- `IncidentManager` drops the failure of a registered copy, so the copy never joins a group.
- The wait never holds a dry run: the item gets PoolSize 2, and exactly one job at a time waits, for every run that is waiting.
- The dry run counts the failures that `Seen` no longer lists (DW-318).
- An approved request whose `StartExecution` fails gets an ending (half of DW-380).
- All of this holds for one request of 500 orders.

## Boundaries & Constraints

**Always:**
- **The row is the truth (AD-11, AD-16, U-126).** Every count and the kind come from the request's row and its own `FixRun`. `Execute`, `FixResult`, `DryRun` and `DryRunResult` gain no property. No new production item, message class, table or catalog key is added.
- **The end of a run that resent copies (AD-16):**
  - The run saves `ResentAt` (UTC now) on its `FixRun` after its last registration, then calls `Wait`. A run that errs after its first registered copy also waits, with the copies it has (7.3's V2 end is replaced).
  - The wait lasts `WAITSECONDS` (60) after `ResentAt`.
  - Each pass reads the run's copies through `Watch.Reader.Evidence` and its keys `h<copy id>`, with the incident's namespace, its production and its first group's `ItemName`. This keeps AD-3's one reader; the executor gets no second switch.
  - A copy is **completed** when its status is `Completed`.
  - It has **failed again** when its status is `Error`, `Aborted`, `Discarded` or `Suspended`.
  - Any other status, a header the snapshot lacks, and a read that does not give `read` all count as **still running**.
  - When every copy is completed or failed again, the run ends (Finish, below) with the result `done`.
  - A run whose copies are not all done when its 60 seconds are up is no longer waited for. The pass that drops it logs one Type 3 warning (`LOGWAIT`: the request, and how many copies are still running). Nothing is stored or sent, so the request stays `executing` and the incident `fixing`. Story 30.5 reports such a run as still in progress, and its Sweep sends the final result.
  - No final result ever goes out with a copy uncounted, so the product never gives a false all-clear.
- **One waiter (DW-381):**
  - `Production.cls` gives `FixExecutor` PoolSize 2 (Lane A's region).
  - `Wait` takes `LOCK +WAITLOCK:0` (`^OcuTalon.Fix.Wait`). If another job already holds it, `Wait` returns at once: the job that holds it finishes this run too.
  - The holder makes a pass every `WAITPAUSE` seconds (0.5) over every waiting run (`Waiting`: `ResentAt` set, `EndedAt` empty, the request's row `executing`, still inside its 60 seconds). It stops when no run waits, or when `Ens.Job` says the job should quiesce or terminate.
  - After it unlocks, the holder looks once more. If a run is waiting and it can take the lock again, it goes on.
  - So at most one job of the item waits at any time, and the other job answers dry runs and starts other runs.
- **The counts (one `FixResult` per run, each the request's own, U-140).** For a run that resent copies:
  - `Total` is the number of `FixTargets` entries.
  - `Resent` is `Copies.Count()`.
  - `Completed` and `FailedAgain` are as above.
  - `Skipped` is `Total` - `Resent`.
  - `Interrupted` is 0.
  - `Reason` is the fail reason when `FailedAgain` > 0, else empty.

  A run that resent nothing, and one that could not start, keep Story 7.3's counts and Reason. These are stored and sent the same way.
- **The fail reason** is that of the failed copy with the lowest id. Its error text is `ErrorText.Text` of Evidence's `error`.
  - If `Settle.Pattern` of that text equals the `ErrorPattern` of one of the incident's groups whose `ItemName` is the copy's `targetConfigName`, the reason is "the " + `RepairResend.FieldWords(field)` + " still wasn't accepted". This is the UX example.
  - Otherwise it is `ErrorText.Summary` of the text, without its closing full stop.
  - With no text at all, it is `Watch.Notice` `NOERRORTEXT` ("no error text").
  - Every reason goes through `Redact.Text` and is at most 1000 characters.
- **Finish: the one end of every run** (it extends 7.3's `Report`; the runs that could not start and those that resent nothing take it too):
  1. The counts and `EndedAt` (UTC now) are saved on the run's `FixRun`, when it has an Id.
  2. `Approval.FinishExecution(ref, done|failed)`.
  3. One `Action` entry is written through `Bridge.Audit.Record` (`WriteAudit` seam). Its members:
     - `action`: the row's `FixKind`;
     - `target`: "<production> in <namespace>" of the incident;
     - `result`: `done` or `failed`;
     - `counts`: {`total`, `resent`, `completed`, `failedAgain`, `skipped`}, as numbers;
     - `approvalRef`: the row's Ref;
     - `irisUser`: the row's `AnsweredBy`, else `$Username`;
     - `channel`: the row's `AnsweredChannel`, else `system`;
     - `sessionRef`: the row's `OwnerRef` when that is a 22-character Ref, else empty (`Approval.Audited`'s rule).
  4. The `FixResult` is sent to IncidentManager.
  - A failed save, close or audit write logs one Type 3 warning each (`LOGRUN`, `LOGFINISH`, `LOGAUDIT`), and the `FixResult` still goes.
- **The trace session (AD-26).** Every `FixResult` goes out with `..%SessionId` set to the incident's `TraceHeaderId` and `..%SuperSession` to the row's `TraceRef`; both are put back afterwards. This also holds for a run that another job's waiter finishes. With no incident, the current session is kept.
- **StartExecution fails (DW-380, its first half).** When `StartExecution` (a new `Start` seam) returns an error, the row is opened again.
  - If it is still `approved` and its `ExpiresAt` is ahead, the run ends as couldn't start, with the reason `NOSTART` ("OcuTalon couldn't start the resend"; veto V3).
  - Otherwise the Execute is refused, as in Story 7.3.
  - `Refusal` keeps 7.3's checks, the past-expiry one included (see the declined half under Design Notes).
- **IncidentManager (AD-15):**
  - `Record` skips every failure that has a `HeaderId` for which `Data.FixRun.CopyOf(batch.Namespace, HeaderId)` names a run. So a registered copy adds no count, no `Seen` key and no time. It opens no group or incident and never sets `LaterSince`.
  - Nothing else in IncidentManager changes. Its existing `Result`, `Event`, `Move` and `Tell` carry the moves, the event and the notice, and they publish only after the commit (AD-12).
- **The payload (DW-272, DW-292; AD-12, AD-13).**
  - `Live.Payload.Incident.FromRow` sets each listed request's `Result` from `Data.FixRun.OfRequest(ref)` when that run has `EndedAt` set. The fields are `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted` and `Reason`.
  - A run without `EndedAt`, and a request with no run, have no result.
  - `OfRequest` uses `ApprovalRefIndexExists` and `%OpenId` only, and compares the Ref exactly. `/state` runs with no SQL grant.
  - `/state`'s groups, evidence and trace targets are Story 5.8's `FromRow`, unchanged.
- **Seen's cap (DW-318).** `FailureGroup.Unlisted(.known)` (pure) gives how many failures of the group's window `Seen` no longer lists:
  - no marks, or an empty `AskedFrom` with `AskedTo` in `Seen`: max(0, `Count` - the keys of `Seen`), known;
  - an `AskedFrom` that is in `Seen`: 0, known;
  - an `AskedFrom` or an `AskedTo` that `Seen` has dropped: unknown.

  `RepairResend.DryRun` adds each group's unlisted failures to `affected` (so they count in `leftOut` as well). For an unknown group it returns an error status with a plain sentence. A later round then raises nothing and logs its warning (7.6, U-133); a first request takes the no-fix route.
- **Rules that apply throughout:**
  - Producers send keys and slots only (AD-32).
  - Log text goes through `Redact.Text`.
  - Stored properties are append-only, with their `Storage` blocks committed (AD-5, AD-33).
  - Rule 14 applies.
  - The mock logs no request during a run.
  - The testing switch stays off.
  - Tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`, run only on throwaways. Classes that drive IncidentManager or FixExecutor run fresh.

**Never:**
- Nothing of a later story:
  - 7.5: `Reconcile`, `Sweep` and interrupted counts;
  - 30.5: the in-progress `FixResult`, Sweep's still-running branch and the in-progress notice.
- DW-368's new wording and the past-expiry half of DW-380 (both declined; see Design Notes).
- No retry: a copy that failed again, and a skipped target, are never resent without a new approval.
- No edit to:
  - `web/**`, `Msg/Catalog/**`, `Fix/Msg/**`, `Live/Payload/Part/**`, `Watch/Transitions.cls` and `Watch/Reader.cls` (unless Task 0 (b) calls for the `bodies` flag);
  - `Core/**`, `Install/**`, `Eval/**`, `ci/mock/**`, `docker/**` and `src/bridge/**`;
  - `Test/Install/Production.cls` beyond Lane A's `FixExecutor` row.
- No stored property but V1's. No property on `FailureGroup`, no AD edit, no `%Ens_MessageEditResend` and no new grant.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| All went through (live, UJ-1; `Results`) | S's incident awaits approval: R1 is pending over 50 failed orders, with the mock's `diagnosis` scenario. Then `Approval.Answer(R1, "approve", "web", ANSWERER, S)`. | **The run:**<br>- 50 copies, all `Completed`;<br>- R1's `FixRun`: 50/50/50/0/0, `Interrupted` 0, `Reason` "", `ResentAt` and `EndedAt` set;<br>- R1 is `done`;<br>- one `FixResult` (R1, the incident, `Final` 1) in the incident's trace session;<br>- the incident is `resolved`.<br>**What S sees:**<br>- exactly one result Notification (`result.allThrough`, count 50, R1, the incident), rendering "All 50 orders went through.";<br>- WebChatOut records its result Delivery row;<br>- the last incident event and `/state` (`Case.StateIncident`) list R1 `done` with `result` {total 50, resent 50, completed 50, failedAgain 0, skipped 0, interrupted 0}, and `/state` keeps its groups, evidence and trace targets.<br>**The audit and the mock:**<br>- one OcuTalon `Action` entry (ANSWERER, S, web, `repair_resend`, the Orders production in OCUORDERS, `done`, the counts, R1), with no key, token, password or Telegram identity;<br>- IRIS's own resend entry for each copy;<br>- the mock logs no request. | none |
| Some had changed (live; `Partial`) | R1 is over 5 orders; 2 of them are rewritten to the target format before the approval | - 3 copies; the `FixResult` is 5/3/3/0/2 with an empty Reason;<br>- `result.skipped` renders "3 of 5 orders went through. 2 had changed since the dry run, so I skipped them; they need a new approval.";<br>- the 2 rewritten orders get no copy;<br>- the incident is `resolved`. | none |
| Copies fail again (live; `Partial`) | R1 is over 3 orders. Before the approval, the test sets R1's `FixParameters` target format to `DD/MM/YYYY`. | - The 3 copies fail at OrdersFromPartner with the incident's own pattern.<br>- The `FixResult` is 3/3/0/3/0 with Reason "the order date still wasn't accepted"; it renders "0 of 3 orders went through. 3 failed again (the order date still wasn't accepted). I won't retry them without a new approval."<br>- The copies' failures are in a `FailureBatch`, but the incident's `Count`, its group's `Count` and its `Seen` are unchanged. S has no other incident, `LaterSince` stays empty and no later request comes.<br>- R1 gets no other Execute, `FixRun` or copy, and no header names a copy as resent. | none |
| Later request pending (live; `Results`) | R1 and R2 are pending (`RaisedTwo`); only R1 is approved | - After R1's result (`allThrough`, 3), the incident is `awaiting_approval`.<br>- Its event lists R1 `done` with its result, and R2 `pending` with none. | none |
| Two resent runs (live, U-140; `Runs`) | R1 is over 3 orders, one of them rewritten; R2 is over 2 later failures; both are approved | - R1's `FixResult` (3/2/2/0/1) comes before R2's one Execute; the incident stays `fixing` in between.<br>- R2's `FixResult` is 2/2/2/0/0; then the incident is `resolved`.<br>- The notices are R1's `result.skipped` (2 of 3) and R2's `result.allThrough` (2).<br>- Each run's `Copies` are copies of its own targets only, and the two sets share none. Each `Action` entry has its own counts. | none |
| A wait holds no notice (live, DW-381; `Waits`) | OrdersFromPartner is temporarily stopped (`TempStopConfigItem`, Task 0 (e)); R1, over 3 orders, is approved. Then a `FailureBatch` gives session S2 a new incident B, with an old failed sample order (`Case.SampleOrder`, `SendBatch`). | - R1's 3 copies stay `Queued`, and R1 is `executing` with no `EndedAt`.<br>- Meanwhile B is noticed with its fix (`NoticedAt` set, `awaiting_approval`, one `incident.withFix` Notification): its dry run was answered by FixExecutor's other job.<br>- Once OrdersFromPartner starts again, inside R1's 60 s, R1 ends with `allThrough`. | none |
| Still running after the wait (probe) | The canned copies stay `Queued`, and the probe's `WAITSECONDS` is short | - No `FixResult` and nothing stored (`EndedAt` empty); the request stays `executing`.<br>- One Type 3 warning names it and the copies still running. | logged |
| One waiter for every run (probe) | The test holds the probe's wait lock; R1 (incident A) and R2 (incident B) are executed | - Each Execute returns with no `FixResult`, and both runs wait.<br>- Once the lock is free, one `Wait` sends two `FixResult`s, each with its own Ref and counts.<br>- Each is sent with its own incident's `TraceHeaderId` and its row's `TraceRef`. | none |
| Counts and reasons (probe) | 50 targets and 50 copies: 48 `Completed` and 2 `Error` with the incident's pattern; then 47 `Completed` copies of 50 targets; then other errors and statuses | - 50/50/48/2/0: renders "48 of 50 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval."<br>- 50/47/47/0/3: renders "47 of 50 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval."<br>- Another error gives its own first sentence; no text gives "no error text".<br>- `Aborted`, `Discarded` and `Suspended` fail again; `Created`, `Queued`, `Delivered`, `Deferred` and a missing header are still running. | none |
| StartExecution fails (probe, DW-380) | An approved request whose `ExpiresAt` is ahead; `StartIs` error | - Couldn't start: one `FixRun`; the row is `failed`.<br>- One `FixResult`: `Total` N, every count 0, Reason "OcuTalon couldn't start the resend".<br>- One `Action` entry.<br>- A pending, cancelled or executing row still gets 7.3's refusal. | none |
| A registered copy fails (live; `Test.Watch.Incidents`) | S's incident from fixture batches, and a `FixRun` of it whose `Copies` hold C | - A batch of S with C and a fresh F: only F joins (`Count` +1; `Seen` gains F only).<br>- C in another namespace's batch joins that namespace's incident. | none |
| 500 orders (live; `Scale`) | One request over exactly 500 failed orders, then approved | - The dry run's `affected` and `resend` are 500; `FixTargets` holds 500 ids.<br>- The `FixResult` is 500/500/500/0/0, and the notice reads "All 500 orders went through." | none |
| Past Seen's cap (live; `DryRun`, DW-318) | A fixture group whose `Count` is 2 above its keys, with no marks; then a group whose `AskedFrom` is not in its `Seen` | - The first: `affected` = the listed ones + 2, `resend` = the listed ones, `leftOut` 2.<br>- The second: refused with a plain Reason and no targets. | none |
| FromRow (Payloads entry) | Requests with an ended `FixRun`, a running one, and another Ref's run | - Only the ended run's request has `result`, with its 7 fields. | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless stated. Line numbers are as of `64a900a`.

**Changed (product):**
- `Fix/Executor.cls` (445 lines):
  - doc L3-36; `Execute` L126 (StartExecution L148-152; Run L153);
  - `Refusal` L158 (the expiry check L163 stays), `Unusable` L175;
  - `Run` L228: it saves the run L234-238; its post-run branch L252-260 (`If copies > 0 Quit` L258) is where the wait goes;
  - `CouldNotStart` L266, `Close` L283, `Report` L293 (to become the one Finish), `FirstReason` L312;
  - `SendResult` L327 (a seam), `Resend` L355 (the only switch; unchanged), `SkipReason` L431 (it already uses `RepairResend.FieldWords`).
- `Data/FixRun.cls` (52 lines): `Copies` L19, indexes L21-23, Storage L25-50.
- `Data/FailureGroup.cls`: `Seen` L20, `AskedFrom`/`AskedTo` L40-46, `AskedKeys` L71 (the sibling of `Unlisted`).
- `Watch/Settle.cls`: `Seconds` L98 (private; made public for the deadline), `Hold` L113 (keeps the newest `SEENMAX` keys), `Window` L134.
- `Fix/Kind/RepairResend.cls`:
  - `DryRun` L101: the group loop L109-131 and `affected`/`leftOut` L148-178;
  - `Plan` L232, `Standing` L275, `FieldWords` L62.
- `Watch/IncidentManager.cls`: doc L1-99; `Record` L292 (its failure loop L297-321, the copy filter at L298).
  - Read only: `Result` L1160, `ResultNotice` L1175, `Apply` L996, `Facts` L1012, `Execute` L1049 (the session pattern to copy for the FixResult), `Tell` L1301.
- `Live/Payload/Incident.cls`: the `FromRow` doc L62-72 and the requests loop L132-141.
- `Production.cls`: L44, `FixExecutor` PoolSize 1.

**Read only:**
- `Watch/Reader.cls`: `Evidence` L193. Its failure object gives `status` as the display text, `error` (the exact log row, else the session's row of the target) and `targetConfigName`. It reads bodies, the item, the event log and the trace.
- `Watch/Notice.cls`: `NOERRORTEXT` L81, `ResultKey`/`ResultSlots` (Story 7.3; `failReason` must not be empty).
- `Watch/ErrorText.cls`: `Text` L59, `Summary` L67.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`: `StartExecution` L370, `FinishExecution` L380 (failed also from approved), `Audited` (the approver rule).
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls`: `SHAPEACTION` L24 and `Record` L78.
- `Demo/PartnerTrigger.cls` L43-55: the model for an Action entry's data.
- `Msg/Catalog/Watch.cls` L151-243: the seven `result.*` keys. `Web/Api.cls`: `StateBody` L584 and `ChatItems` L672 call `FromRow`.
- `web/src/app/approvals/approval-view.ts` L351 `resultView`: the page derives the key from `requests[].result`, by the same convention.
- `irislib/Ens/MessageHeader.cls`: `ResendDuplicatedMessage` L443; `NewDuplicatedMessage` refuses a target that is not running. `irislib/Ens/Director.cls`: `TempStopConfigItem` L2467. `irislib/Ens/Job.cls`: `ShouldBeQuiescent` L370 and `ShouldTerminate` L378.
- UX `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` L672-682 (Results).

**Tests to reuse or change:**
- `Test/Watch/Case.cls`:
  - set-up: `Raised(…, orders)` L1392, `RaisedTwo` L1499, `Fixture` L719 (it leaves the group's `Count` empty), `SendBatch` L1154, `Batches`/`Ids` L909/L951;
  - waits: `WaitState` L1560, `WaitIncidentState` L1577, `RunOf` L1537, `FixResultsOf` L1675, `WaitCompleted` L1619;
  - reads and changes: `NoticeBodies` L1289, `AssertDelivered` L1306, `StateIncident` L1333, `Stream` L1282, `SetOrderDate` L1691, `StopOrders` L1026, `PutBack` L437, `DropIncidentRows` L1469.
- `Test/Bridge/AuditLog.cls`: `Now`, `Entries` and `Wait`.
- `Test/Fix/DryRun.cls`: `Ask` L80 (to lift into `Case`), `SENDWAIT` L32.
- `Test/Fix/ExecutorProbe.cls`: its seams and overrides.
- `Test/Fix/Executor.cls`:
  - `TestRefusedStates` L91 (the past-expiry case stays refused);
  - `TestStartExecutionRefusesWhatTheRefusalCheckLetsThrough` L138 (unchanged);
  - `TestNothingResent` L371;
  - `TestResentRunSendsNoResult` L405 (to replace).
- `Test/Fix/Execute.cls`:
  - `TestApprovedRepairsAreResent`: L85 says executing, L114-117 says no FixResult and still fixing;
  - `TestRunsTheRowsTargetsOnly` L280 (executing).
- `Test/Fix/Runs.cls`: L13-14 and L51 (R2 stays executing).
- `Test/Watch/Incidents.cls` (SendBatch tests), `Test/Watch/Settle.cls` `TestWindow` L113.
- `Test/Live/Payloads.cls`: `TestFromRowEvidence` L249 (its request has no run, so no result: it stays) and `TestIncidentFromRowReadsNoSql` L302.
- `Test/Data/Tables.cls` L561 (the `FixRun` entry), `Test/Install/Production.cls` L628 (Lane A's `FixExecutor` row, `"pool": 1`).

## Tasks & Acceptance

**Execution:**

*Task 0.* Run these on the stage's first fresh throwaway, and record the results in `## Verification`:
- (a) With `Index CopiesIndex On Copies(ELEMENTS)`:
  - `SELECT ID FROM OcuTalon_Data.FixRun WHERE FOR SOME %ELEMENT(Copies) (%VALUE = ?)` finds a run by a copy id, and its plan uses the index;
  - `ApprovalRefIndexExists(ref, .id)` gives the run's id.
- (b) The time of one `Reader.Evidence` over 50 and over 500 copy keys. Over 5 s for 500, `Evidence` gains `bodies As %Boolean = 1` (Rule 2: one reader) and the wait passes 0.
- (c) Which channels record a Delivery row for one result Notification of a demo session.
- (d) IRIS's own resend audit entries: their EventSource, EventType and Event, and how each one names its copy.
- (e) A copy resent to OrdersFromPartner while it is stopped by `TempStopConfigItem("OrdersFromPartner")` stays `Queued`, and it completes after `TempStopConfigItem(…, 0)`. If such an item refuses the copy instead, record that, drop `Waits`, leave AC 8 to the probe's `TestOneWaiterFinishesEveryRun`, and report the gap under `## Auto Run Result` for the lead.
- (f) A copy whose target format is `DD/MM/YYYY` fails at OrdersFromPartner with an error whose `Settle.Pattern(ErrorText.Text(…))` equals the group's `ErrorPattern`.
- (g) With PoolSize 2, two FixExecutor jobs run, and a `DryRun` is answered while the other job waits.
- (h) The class time of each new or changed live class. Split any class whose class time passes about 180 s.

*Product code (in dependency order):*
- `Data/FixRun.cls` -- V1:
  - Append `ResentAt` and `EndedAt` (`%String(MAXLEN = 20)`), `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped` and `Interrupted` (`%Integer`), and `Reason` (`%String(MAXLEN = 1000)`). The Storage block gets values 6 to 14 from the compiler. A name that `$SYSTEM.SQL.IsReservedWord` flags keeps its name and gets an `SqlFieldName`.
  - Add `Index CopiesIndex On Copies(ELEMENTS)`.
  - Add `ClassMethod OfRequest(ref)`: object access only; the run of the Ref, compared exactly, or "".
  - Add `ClassMethod CopyOf(namespace, headerId)`: SQL over `CopiesIndex`, joined to the run's incident's `Namespace`; the run's `ApprovalRef`, or "".
  - Doc.
  - Why: DW-272, AC 4 and AC 9.
- `Data/FailureGroup.cls` -- `Method Unlisted(Output known As %Boolean) As %Integer`, pure, by the rule in Always; doc. Why: DW-318.
- `Watch/Settle.cls` -- `Seconds` loses `[ Private ]` and gets a doc. The deadline uses it (Rule 2).
- `Fix/Kind/RepairResend.cls` -- in `DryRun`, add each group's `Unlisted` to `affected`; an unknown group gives an error status with a plain sentence. Doc. Why: AC 10.
- `Fix/Executor.cls`:
  - Parameters: `WAITSECONDS` 60, `WAITPAUSE` 0.5, `WAITLOCK` "^OcuTalon.Fix.Wait", `NOSTART`, `LOGWAIT`, `LOGAUDIT`.
  - Seams: `Start(ref)` (StartExecution), `Statuses(incident, run, Output statuses)` (Reader.Evidence of the copies), `Waiting()` (the waiting runs, by SQL) and `WriteAudit(data)` (Audit.Record).
  - `Execute`: StartExecution's error as in Always.
  - `Run`: a run with copies saves `ResentAt` and calls `Wait`.
  - `Wait`, the counts, the fail reason, and Finish (it replaces `Report`; every end calls it). `Report` sets the session.
  - Rewrite the class doc: PoolSize 2 and the one waiter replace "one job takes one request at a time".
  - Why: AC 1, 3, 5, 7, 8 and 11.
- `Production.cls` -- FixExecutor `PoolSize="2"`, in Lane A's region. Why: AC 8.
- `Watch/IncidentManager.cls` -- `Record` skips registered copies; class doc (the batch bullet and AD-15's attribution). Why: AC 4.
- `Live/Payload/Incident.cls` -- `Details` sets `Result` from `FixRun.OfRequest` for an ended run; `FromRow` doc. Why: AC 9.

*Tests:*
- `Test/Fix/ExecutorProbe.cls` -- add:
  - `StartIs` (error);
  - `StatusIs` (JSON {copy id: {status, error, target}});
  - `Incidents` (`Waiting` narrowed to the test's incidents);
  - `Audits` (what `WriteAudit` recorded);
  - `Sessions` (`..%SessionId` and `..%SuperSession` at each `SendResult`);
  - `Parameter WAITLOCK = "^OcuTalon.Test.Fix.Wait"`, `WAITSECONDS = 3` and `WAITPAUSE = 0.1`, so a probe never meets the running production's waiter.
  - `Run`, `CouldNotStart` and `Close` follow their new signatures.
- `Test/Fix/Executor.cls` (probe; warm):
  - new: `TestResentRunEndsWithItsCounts` (the "Counts and reasons" row, both UX renders), `TestFailReasons`, `TestStillRunningAfterTheWait`, `TestOneWaiterFinishesEveryRun` (AC 7 and AC 8), `TestStartExecutionFailsForAnApprovedRequest` (AC 11), `TestEveryRunWritesOneActionEntry` (AC 5: couldn't start, nothing resent, resent);
  - changed: `TestNothingResent` and `TestCouldNotStartRoutes` also assert the stored counts and the Action entry;
  - delete: `TestResentRunSendsNoResult`.
- `Test/Fix/Results.cls` (new; live; fresh) -- `TestAllFiftyWentThrough` (AC 1, 2, 5, 9; Integration; the "All went through" row) and `TestLaterRequestPendingAfterTheResult`.
- `Test/Fix/Partial.cls` (new; live; fresh) -- `TestSomeHadChanged` and `TestCopiesFailAgain` (AC 3, AC 4).
- `Test/Fix/Waits.cls` (new; live; fresh) -- `TestNoticeSentDuringAWait` (AC 8; the "A wait holds no notice" row), with `TempStartItem` in its clean-up.
- `Test/Fix/Scale.cls` (new; live; fresh) -- `TestFiveHundredOrders` (AC 6), with its own run bound of 120 s.
- `Test/Fix/Runs.cls`:
  - `TestTwoApprovedRequestsRunOneEach`: R2 now ends with its own result (2/2/2/0/0) and the incident is resolved;
  - new `TestTwoResentRunsHaveTheirOwnResults` (AC 7, U-140);
  - doc.
- `Test/Fix/Execute.cls`:
  - `TestApprovedRepairsAreResent`: R1 ends `done`, with one `FixResult` (3/3/3/0/0), one `result.allThrough` and a `resolved` incident; the second Execute is still refused;
  - `TestRunsTheRowsTargetsOnly` waits for `done`;
  - doc.
- `Test/Fix/DryRun.cls` -- `TestUnlistedFailuresAreCounted` and `TestUncountableWindowIsRefused` (AC 10).
- `Test/Watch/Incidents.cls` -- `TestRegisteredCopyIsNotAFailure` (AC 4).
- `Test/Watch/Settle.cls` -- `TestUnlisted`: each case of the rule, pure, on rows in memory.
- `Test/Watch/Case.cls`:
  - `AskDryRun`, lifted from `DryRun.Ask` with its clean-up;
  - `TempStopItem`/`TempStartItem`, put back by `PutBack`;
  - `SetFixParameters(ref, json)`;
  - doc.
- `Test/Live/Payloads.cls` (entries) -- add `TestFromRowRequestResult` (the "FromRow" row). `TestIncidentFromRowReadsNoSql` also scans `Data.FixRun` `OfRequest`.
- `Test/Data/Tables.cls` (its own entry) -- the 9 `FixRun` properties and `CopiesIndex`.
- `Test/Install/Production.cls` (Lane A's row) -- `FixExecutor` `"pool": 2`.

**Acceptance Criteria:**
- **AC 1 (Integration).** Given an approved request whose run resent copies, when each copy has completed or failed within FixExecutor's 60-second wait, then:
  - FixExecutor stores the run's counts on its `FixRun`, closes the request `done` through `Approval.FinishExecution`, and sends IncidentManager one `FixResult`. It carries the request's `ApprovalRef` and `IncidentRef`, `Final` 1, `Total`, `Resent`, `Completed`, `FailedAgain` and `Skipped`, and a plain `Reason` for copies that failed again.
  - IncidentManager moves the incident by AD-15's table: `resolved`; `awaiting_approval` while a later request is pending; or `fixing` with the waiting request's Execute sent, while an approved request waits.
  - It publishes the incident event, whose `requests` entry for the request carries that result.
  - It sends each recipient one `result` Notification with the request's `ApprovalRef` and `IncidentRef`.
- **AC 2 (Integration).** Given 50 failed orders diagnosed through the mock's `diagnosis` scenario under `ci/mock/scenarios/A/`, their dry run and an answer through `Approval.Answer`, when the execution ends, then S gets exactly one `result` Notification. Its catalog entry renders "All 50 orders went through.", WebChatOut records it, and so does each other channel of S that keeps Delivery rows (Task 0 (c)).
- **AC 3.** Given copies that failed again or targets that were skipped, when the result is sent, then:
  - it reads as E › Results' partial texts ("48 of 50 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval." and "47 of 50 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval.");
  - that partial result is its request's result as the incident moves by AD-15's table.
- **AC 4.** Given a copy that failed again, when FailurePoller reports its failure, then IncidentManager recognises it by its registered header id, adds it to no failure group or incident and starts no later round. The copy is never resent without a new approval.
- **AC 5.** Given a completed resend, when a test reads the IRIS audit log, polling with a timeout, then it finds one OcuTalon `Action` entry written through `OcuTalon.Bridge.Audit`, beside IRIS's own resend entries:
  - it has the time, the approving IRIS user, the `SessionRef`, the channel and the target production;
  - it has the counts resent, completed, failed again and skipped;
  - it holds no key, access token, password or Telegram identity.
- **AC 6.** Given 500 failed orders from one cause, when one request covers them and is approved, then:
  - the dry run counts 500;
  - the request holds 500 fixed targets;
  - the result reports 500 resent and 500 completed;
  - the test runs at exactly 500 messages.
- **AC 7 (U-140).** Given two approved requests of one incident whose runs resent copies, when each run's copies have completed or failed again within the wait, then each request's `FixResult`, `FixRun` and result notice carry its own counts and its own `ApprovalRef`. Neither run's copies count in the other's.
- **AC 8 (DW-381).** Given a run that waits on its copies, when another incident settles and IncidentManager asks FixExecutor for its dry run, then that incident's with-fix notice is sent while the run still waits.
- **AC 9 (DW-272, DW-292; Integration).** Given an incident whose request's run has ended, when `/state` is built (`Web.Api.StateBody`) or the incident event is published, then the incident's `requests` entry for that request carries its stored result (`total`, `resent`, `completed`, `failedAgain`, `skipped`, `interrupted`, `reason`), read by object access only.
- **AC 10 (DW-318).** Given a failure group whose window holds failures that `Seen` no longer lists, when the dry run is worked out, then:
  - those failures count as affected and as left out;
  - a window whose start or end `Seen` has dropped gets no dry run.
- **AC 11 (DW-380).** Given an approved, unexpired request whose `StartExecution` fails, when FixExecutor handles its Execute, then the run ends as couldn't start, with the reason "OcuTalon couldn't start the resend".

## Spec Change Log

- 2026-10-29, spec gate (lead): V1, V2 and V3 ruled as veto items U-146, U-147 and U-148 (kept as planned); DW-368 escalated and DW-380's past-expiry half split into DW-384 (escalated) for the decision sheet; kept as one story.

## Review Triage Log

### 2026-10-29 — Review pass
- verdicts: 34 findings — high 0, medium 4, low 25, false 5, maybe-false 0
- findings (layer order: blind-hunter 1-8, edge-case-hunter 9-19, verification-gap 20-26, intent-alignment 27-34):
  - 1. `[low]` `[reject]` Wait re-reads full Evidence for every copy each pass; Waiting re-opens timed-out runs — Task 0 (b) measured 0.27 s for 500 keys; the scan covers only stuck runs and runs at demo scale; an index would be a schema change (V1/U-146).
  - 2. `[low]` `[patch]` Look's exception is swallowed in Pass without a log — Evidence throws on a namespace fault, so Pass now logs one Type 3 warning per run (LOGLOOK, Redact); the other parts are not defects: Wait's own catch logs (LOGWAIT "(any)"), runs stranded by a stopped holder are Story 7.5's Sweep (Residual risk 3), and an exception after the close is not reachable (Audit has its own Try, Report and the send return statuses).
  - 3. `[low]` `[patch]` Pass's doc says "request still executing" but the code checks EndedAt only — nothing in this story closes an executing request without an EndedAt, so no spurious warning is reachable; the doc comment now says what the code does.
  - 4. `[medium]` `[patch]` A run that errs after its first copy is untested — Executor.Run waits for such a run by the spec ("Always"), and no test could register a copy and then fail; the probe's canned Carry takes a "fail" member and `TestRunThatErredAfterACopyStillWaits` pins it. Skipped = Total - Resent and Interrupted 0 are the spec's counts (Story 7.5 sets Interrupted), so the wording part is by-design.
  - 5. `[low]` `[reject]` A failed ResentAt save leaves the run invisible to the waiter — spec Residual risk 3 accepts it (the request stays executing for Story 7.5's Sweep); making Finish run there would send a result with copies uncounted.
  - 6. `[low]` `[reject]` Quiesce/terminate, CopyOf fallback, save failure and the real cross-job send are untested; WAITNOTICE wording — each needs a new seam for a rare path; the cross-job case is pinned on the probe (`TestOneWaiterFinishesEveryRun`) and the real second job by `Waits`; reopen_if=a production stop is observed to wait out a hung waiter. The WAITNOTICE doc is reworded (see 25).
  - 7. `[low]` `[patch]` `Case.cls` doc narrates history ("lifted here") — Rule 14: reworded to the contract (grouped with 26).
  - 8. `[low]` `[reject]` CopyOf runs one SQL join per failure, outside the Try — `%ExecDirect` gives an SQLCODE rather than throwing, so the documented fallback to "" holds; one cached indexed read per failure is far under the poll's cost.
  - 9. `[low]` `[reject]` ResentAt save fails after copies were resent, the run never waits — same root cause as 5.
  - 10. `[low]` `[reject]` Carry throws after the first copy: unreached targets count as Skipped and the error is lost — Skipped = Total - Resent, Interrupted 0 and a Reason only for copies that failed again are the spec's counts; the error is logged (LOGRECHECK, now pinned by the new test).
  - 11. `[low]` `[reject]` A copy that finishes in the last WAITPAUSE before the deadline is not counted — the window is at most 0.5 s of 60; the run stays executing for Story 7.5's Sweep and no false all-clear goes out.
  - 12. `[low]` `[reject]` Waiting() throws after the unlock, outside the Try — needs an SQL failure; Execute's own result is unaffected.
  - 13. `[low]` `[patch]` Look throws on every pass silently — same root cause as 2; fixed by the LOGLOOK warning.
  - 14. `[low]` `[reject]` An incident with no failure group makes Evidence not_current for ever — a run exists only for an approved request whose dry run needed a group (Plan refuses without); no group is deleted while its incident lives.
  - 15. `[low]` `[reject]` An incident without a TraceHeaderId sends the result in the holder's session — an approved request exists only after the diagnosis that sets it; the spec keeps the current session only for "no incident".
  - 16. `[low]` `[reject]` Waiting() scans FixRun every pass with no index — same root cause as 1.
  - 17. `[low]` `[reject]` CopiesIndex does not cover FixRun rows that predate it — V1: no released row has the new properties; 7.3's rows exist on dev stacks only, and a fresh install has none.
  - 18. `[low]` `[patch]` Class doc says every run ends once in Finish, but a run whose ResentAt cannot be saved does not — the class doc now says that such a run is not waited for (grouped with 5).
  - 19. `[low]` `[reject]` LOGWAIT is logged only for a run a pass looked at first — a run that no pass saw before its deadline is a crash leftover or a late Wait, which Story 7.5's Sweep ends.
  - 20. `[low]` `[reject]` The Wait loop's quiesce and error exits have no test — same root cause as 6.
  - 21. `[medium]` `[patch]` The branch for a run that erred after its first copy is untested — same root cause as 4; the new test is pinned by a mutation.
  - 22. `[medium]` `[patch]` Created, Queued, Delivered, Deferred and a missing header were pinned only together — `TestResentRunEndsWithItsCounts` now runs each state on its own beside a completed copy; mutations (Deferred as failed; a missing header as completed) go red.
  - 23. `[medium]` `[patch]` `Results` asserts that no Delivery row of the mailbox channel exists for the result — SimMailboxOut keeps its rows with an empty kind and Ref, so the count is 0 whatever happens; the assertion is removed (AC 2 asks for the channels that do keep a row, which the two positive assertions pin).
  - 24. `[false]` `[reject]` AC bullets have no mutation line of their own — Rule 19 asks one mutation per AC, and every one of the 11 ACs has at least one `mutation:` line (the layer says so).
  - 25. `[low]` `[reject]` Waits' worst case (Hang 2, WaitIncident 20 s, WAITNOTICE 40 s) can pass R1's 60 s — the matrix row fixes the design; the class took 32 s on the stack and B was noticed within seconds of the settle window; the WAITNOTICE doc no longer says "far inside".
  - 26. `[low]` `[patch]` Comments state history ("as it was before copies were registered", "refused as before", "as in Story 7.3") — Rule 14: reworded to the contract.
  - 27. `[false]` `[reject]` The unit class runs on seams and not on the real item — the real item is pinned by `Results`, `Partial`, `Waits`, `Scale`, `Runs` and `Execute` on fresh stacks (all passed); the probe covers the branches a real production cannot reach.
  - 28. `[false]` `[reject]` /state's no-SQL rule is checked by a source scan, not as the REST user — Design Notes decided AC 9's surface (`Web.Api.StateBody`); a real HTTP test belongs to contended `Test/Live/**`.
  - 29. `[false]` `[reject]` `ApprovalRefIndexExists` on a non-unique index — Task 0 (a) measured that it exists and gives the run's id; `Payloads` and `Results` call it.
  - 30. `[low]` `[patch]` Pass logs LOGWAIT for any run that leaves the waiting set — same root cause as 3.
  - 31. `[low]` `[patch]` Read throws on every pass, so LOGWAIT says "some" — same root cause as 2.
  - 32. `[low]` `[reject]` No group, never ends — same root cause as 14.
  - 33. `[low]` `[reject]` A run older than 60 s at holder start is never seen — same root cause as 19.
  - 34. `[false]` `[reject]` Changes outside the intent's listed surfaces (`Settle.Seconds` public, lifted test helpers, flipped 7.3 assertions) — each is a task of the plan.

## Design Notes

**V1. The stored results of a run (a schema change, in the veto window; the lead rules it).**
- **Chosen:** nine appended `FixRun` properties and `CopiesIndex`, as in the tasks.
  - The counts mirror `FixResult` (DW-272: "the final FixResult's counts are stored").
  - `EndedAt` marks a final result.
  - `ResentAt` starts the 60 s, so another job can wait for the run (DW-381), and Stories 7.5 and 30.5 can tell a running run from a finished one.
  - `Interrupted` is 0 here; Story 7.5 sets it.
- **Why FixRun:** it is the request's own row (one per approved request taken up), and Lane A's.
  - The bridge's `ApprovalRequest` stays fix-agnostic (AD-2).
  - `Incident` has no row per request.
- **Rejected:**
  - one JSON `Result` column, which cannot be queried, unlike `FixResult`'s typed fields;
  - a copy table, which AD-33 would need to list;
  - `FailureGroup` counters for DW-318, which `Unlisted` makes unnecessary.
- **Reversal:** stop writing the properties. They stay empty (append-only), and no released row has them.

**V2. Where the wait runs (DW-381; a production change in Lane A's region, in the veto window).**
- **Chosen:** FixExecutor gets PoolSize 2, with one waiting job at a time, under `WAITLOCK`, which finishes every waiting run.
  - The wait stays FixExecutor's, and FixExecutor sends every `FixResult`, as AD-15 and AD-16 say.
  - A dry run never waits behind a wait: the other job is free.
  - Lane A's oracle row in `Test/Install/Production.cls` follows. That file is Epic 13's; the row is shared by row, as the orchestrator ruled in Story 7.3.
- **Rejected:**
  - PoolSize 2 with each run waiting in its own job: two hung waits block a dry run again.
  - A new waiting item, a business process or Checks' tick: that is a second sender of `FixResult`, which AD-15 and AD-16 do not have, and AD-18's tick comes only once a minute.
  - A business-process executor: it rewrites 7.3's executor and its probe.
  - A keepalive adapter: it has no message context to send in, and is exotic.
  - A self-sent wait message: a Fix message class that AD-16 does not list.

**V3. New public text (in the veto window; the lead rules it).**
- `NOSTART`, "OcuTalon couldn't start the resend". It renders "Nothing was resent: OcuTalon couldn't start the resend. Nothing was changed." It is the only wording DW-380's addressed half needs, and it begins with OcuTalon like U-141's reasons.
- The fail reason, "the {field} still wasn't accepted". It is UX's example, with `FieldWords`, and is given only when the copy failed with the incident's own error. Otherwise the copy's own first sentence is given, else the existing "no error text".

**Declined (for the lead; each needs a ruling above this story):**
- Declined DW-368: an honest stopped-production result needs one of two things:
  - an AD-16 amendment: a production that isn't running when the run starts ends it as couldn't start, with `Skipped` 0, so the existing `result.couldNotStart` gives "Nothing was resent: that production isn't running. Nothing was changed.";
  - a new key, with a "Result texts" row and the page's own selection (`web/src/app/approvals/approval-view.ts`, `web/**`, contended).

  AD-16 says a stopped production is "reported per copy as Skipped", and the page picks `result.skipped` from `skipped` > 0. Recommended: the AD-16 amendment, then route it to Story 7.5 or a sibling.
- Declined DW-380 (the past-expiry half): AD-16's Rule lists the refused Executes that "change nothing and send nothing" (pending, rejected, expired, cancelled, already executing, unknown). Story 7.3 read "expired" as including an approved row past its `ExpiresAt` (its Refusal step 1, and DW-380's own note: spec-bound). Ending that row as couldn't start therefore needs an AD-16 amendment. Recommended: amend AD-16 so that an approved row past its `ExpiresAt` ends as couldn't start, with `NOSTART`, and add one line to `Refusal`. The StartExecution half is addressed (AC 11): a lock or save failure on an approved, unexpired row is "an approved run [that] can't start" (AD-11).

**Spec gate rulings (lead, 2026-10-29; policy 6df0676):**
- V1 (nine `FixRun` properties and `CopiesIndex`): ruled `veto`, inbox U-146, kept as planned.
- V2 (FixExecutor PoolSize 2 with one waiting job under `WAITLOCK`; Lane A's FixExecutor oracle row in `Test/Install/Production.cls` follows, shared by row as the orchestrator ruled for 7.3 — change only that row's `pool`): ruled `veto`, inbox U-147, kept as planned.
- V3 (`NOSTART` "OcuTalon couldn't start the resend"; the fail reason "the {field} still wasn't accepted"): ruled `veto`, inbox U-148, kept as planned.
- Declined DW-368: accepted as declined here; the entry is `escalated` for the epic's decision sheet (an AD-16 amendment, which U7 (c) makes the owner's, or a new key with the page's selection). Build nothing for it.
- Declined DW-380's past-expiry half: split into DW-384 (`escalated`, the same reason); DW-380 stays this story's for its StartExecution half (AC 11). Build nothing for the past-expiry half.
- Size: kept as one story (decide; the 7.7 seam is not taken).

**Ledger inbox:**
- DW-272: V1 and AC 9.
- DW-292: AC 9. Story 5.8's `FromRow` already fills `/state`'s groups, evidence, trace targets and requests (`Web.Api.ChatItems` calls it). This story adds each request's result, and `Results` pins the whole `/state` entry, so the entry is complete.
- DW-318: AC 10.
- DW-368: declined (above).
- DW-380: AC 11 for its first half; its second half is declined (above).
- DW-381: V2 and AC 8.

**Decided in-stage (small, reversible, within the intent):**
- **"IncidentManager records the result against its request"** is read as follows. The request's own `FixRun` carries the counts, written by FixExecutor just before it sends the `FixResult`, so the event that IncidentManager publishes for the accepted move already shows them. IncidentManager accepts the `FixResult` only for its own request (`Owns`, 7.3). IncidentManager stays the only writer of `Incident` and `FailureGroup`, and `FixRun` keeps one writer (AD-33).
- **The 60 seconds** run from the last registration (`ResentAt`), so no copy waits less than 60 s.
- **Done statuses.** `Aborted`, `Discarded` and `Suspended` count as failed again: they will not go through on their own. An unreadable copy is never counted as completed.
- **One `Action` entry per run that ends,** couldn't-start and nothing-resent runs included, each with its result and counts. It makes the page's "Recorded in the IRIS audit log." true under every result band. `target` names the namespace as well, because production names can repeat across namespaces.
- **A run that resent copies and has no failures** stores an empty `Reason`. `result.skipped` has no reason slot, and its skip reasons were never stored (7.3).
- **DW-318** is counted without new storage. A window keeps all its keys while its `AskedFrom` is still in `Seen`, because `Hold` drops the oldest keys first. A window that `Seen` has cut cannot be counted, so it gets no dry run rather than a count that is too low. The first window takes the dropped keys from `Count`.
- **`CopyOf` checks the namespace,** because header ids are per namespace. A copy's failure is dropped whatever its scope.
- **Tests set the fail-again case** by writing the pending row's `FixParameters` (a fixture, before any answer), because a valid repair always passes the Orders transform.
- **AC 9's surface is `Web.Api.StateBody`,** the body that `/state` serves (`Case.StateIncident`). A real HTTP test belongs in `Test/Live/**`, and the page band's tests in `web/e2e`, which are both contended now. The page's band is Epic 6's `resultView`, pinned by its own tests, and Epic 11's demo-path test covers the whole way.
- **The probe's timing parameters** (`WAITSECONDS`, `WAITPAUSE`, `WAITLOCK`) are read as `..#…` in the executor's instance methods, so the probe's values apply to it.
- **Implement stage (2026-10-29).**
  - **The 60 seconds are counted from `ResentAt`, a stamp to the second,** so a run waits between 59 and 60 s of real time (the stamp cuts the fraction). The probe test allows that one second.
  - **`Reader.Evidence` gets no `bodies` flag:** 500 copy keys took 0.27 s (Task 0 (b)).
  - **IRIS's own Resend audit entry names the copy** (its new header id and body id, with the original's session), not the original (Task 0 (d)); the AC 5 test finds each copy by its header id.
  - **`FixRun.OfRequest` uses `ApprovalRefIndexExists`,** which the compiler generates for the non-unique `ApprovalRefIndex` too (Task 0 (a)); the index folds case, so `OfRequest` compares the Ref exactly after the open.
  - **`Waiting()` gives the FixRun ids that wait,** and the holder drops a run it has looked at and that no longer waits (its time is up, its request still executing) with one LOGWAIT warning in the pass that notices it, counting the copies of its last look. A run that no pass has seen is never warned about, and a run past its time is never looked at again.
  - **A missing incident or an unreadable copy is "still running":** the run then ends by the time-up rule, never as completed.
  - **`FailReason` strips one closing full stop** from the first sentence (`ErrorText.Summary` keeps the stop of the sentence that it finds); a sentence the text has no full stop for is kept as it is.
  - **`Finish` redacts and cuts the reason once** (1000 characters), so the FixRun and the FixResult carry the same text.
  - **An Action entry's approver is the row's `AnsweredBy`, else the job's `$Username`;** its channel is `AnsweredChannel`, else `system`; its session is the row's `OwnerRef` when that is a Ref, else empty.
  - **`Report` sets `..%SessionId` only when the incident has a `TraceHeaderId`,** and `..%SuperSession` to the row's `TraceRef` whenever the incident exists; both are put back.
  - **`CopyOf` gives "" when its read fails,** so a failure whose copy cannot be told is taken for a new one, as before 7.4.
  - **The probe's `Waiting` gives no run when `Incidents` is empty,** so a probe never finishes a run of the running production; the probe's lock, wait time and pause are its own.
  - **Test helpers are lifted, not copied:** `Case` holds `AskDryRun` (from `DryRun.Ask`), `Posts` (from `Test.Fix.Execute`), `Joined` and `Originals`, and `Case.Runs` also gives the stored result of each run.
- **Review patches (2026-10-29).**
  - **A look that throws logs once.** `Pass` logs one Type 3 warning per run (`LOGLOOK`, a log text like `LOGWAIT`, redacted) when `Look` throws, and counts the copies as still running. Without it the only trace was a later `LOGWAIT` that blamed copies still running. `Reader.Evidence` throws when a namespace cannot be read.
  - **Tests.** The probe's canned `Carry` takes a `fail` member (copies registered, then an error), and its `StatusOutcome` takes `throw`. `Test.Fix.Executor` gains `TestRunThatErredAfterACopyStillWaits` (a Run bullet under Always that no test pinned) and a throwing read in `TestStillRunningAfterTheWait`. `TestResentRunEndsWithItsCounts` runs each of Created, Queued, Delivered, Deferred and a missing header on its own beside a completed copy. `Results` loses an assertion that could not fail (SimMailboxOut keeps its Delivery rows with an empty kind and Ref).
  - **Docs.** The class doc says that a run whose `ResentAt` cannot be saved is not waited for, as a run whose time is up is not; `Pass`'s doc says what its code checks; Rule 14 wording fixes in `FixRun`, `Test.Fix.Executor`, `Test.Watch.Case` and `Test.Fix.Waits`.

**Governing ADs:**
- AD-1: items by name.
- AD-3: Reader reads the copies, and Resend stays the one switch.
- AD-4: scope.
- AD-5: append-only storage.
- AD-11: the row; `FinishExecution` from approved.
- AD-12: the payload after the commit.
- AD-13: `/state` with no SQL.
- AD-15: the table; a copy's failure is attributed to the fix; the one writer.
- AD-16: the wait, the counts and the executor.
- AD-17: the `Action` entry through `Bridge.Audit`.
- AD-22: throwaways and the mock log.
- AD-26: the result's trace session.
- AD-29: Lane A.
- AD-32: the `result` kind, slots only.
- AD-33: owners, and no new item or table.

Conventions: "Result texts", "Watch failures", "Later requests", "Audit entries", "Approval requests", "Incident notice" (FromRow by object access), "Messages", "Redaction", "SQL reserved words".

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Integration ACs:**
  - AC 1, AC 2 and AC 9: IncidentManager turns FixExecutor's `FixResult` into the move, the event (whose payload carries the request's result) and the notice; WebChatOut records it; `Web.Api.StateBody` lists the result.
  - AC 4: `IncidentManager.Record` uses `FixRun.CopyOf`.
- **Consumes:**
  - 7.3: `Fix.Executor`, `FixRun.Copies`, `Recheck`/`Execute`, `ResultKey`/`ResultSlots`.
  - 7.6: windows, `RaisedTwo`, one Execute at a time.
  - 7.2: `RequestRefs`.
  - 5.8: `FromRow`'s parts.
  - 5.2 and 5.3: FailurePoller and `Record`.
  - 3.x: `FinishExecution`, `Audit.Record`.
  - Epic 6: WebChatOut and the page's `resultView` (already built).
  - 0.10: Orders.
- **Consumed-by:**
  - 7.5: `EndedAt`, `Interrupted` and the counts, for `Reconcile` and `Sweep`. The waiter skips a row that is no longer `executing`.
  - 30.5: runs with `ResentAt` set and `EndedAt` empty past their 60 s, and the in-progress result.
  - Epic 6's page: the result band.
  - Epic 11: the demo path.

**Extend, don't copy (Rule 2):**
- Finish extends 7.3's `Report`, and every end calls it.
- The wait reads through `Reader.Evidence`.
- `Settle.Seconds` is made public, not copied.
- `Unlisted` sits beside `AskedKeys`.
- `FixRun.OfRequest` serves `FromRow`, the executor and the tests.
- The fail reason uses `RepairResend.FieldWords`, as `SkipReason` does, and `Notice.NOERRORTEXT`.
- The probe's new seams follow its existing ones.
- `Case.AskDryRun` is lifted from `DryRun.Ask`.

**Spine notes for the lead (Rule 20 candidates):**
- A "Fix runs" Conventions row: the stored counts on `FixRun`, PoolSize 2 with the one waiter, `CopyOf`, and the end at 60 s with copies still running (Story 30.5).
- The declined DW-368 and DW-380 items, if the lead amends AD-16.

**Residual risks:**
1. A copy that fails before its id is registered (a window of milliseconds; FailurePoller polls every 3 s) would still join its group (inference).
2. A copy that hangs leaves its request `executing` and its incident `fixing` until Story 30.5.
3. A failed `ResentAt` save leaves the run unwaited, `executing`, for Story 7.5's Sweep.
4. A failure downstream of a completed copy (a forward of it) is a new failure of another item, by design.
5. DW-368, and the past-expiry half of DW-380, stand until they are ruled.

**Size and split (for the lead).** This story is planned as one (`oversized`, `multiple-goals`). If the lead splits it, the seam is a sibling Story 7.7, "OcuTalon handles at least 500 orders in one request": AC 6, AC 10 (DW-318), `Test.Fix.Scale` and the DryRun, Settle and RepairResend tasks. Everything else stays in 7.4. The 500-message criterion would then move to a sibling planned next in this epic (decide for the lead).

**Footprint:** `Fix/**`, `Test/Fix/**`, `Data/{FixRun,FailureGroup}.cls`, `Watch/{IncidentManager,Settle}.cls` (and `Watch/Reader.cls` only by Task 0 (b)), `Live/Payload/Incident.cls`, and `Test/Watch/**`. Shared entries and rows: `Production.cls` (Lane A's region), `Test/Live/Payloads.cls`, `Test/Data/Tables.cls` and Lane A's `FixExecutor` row of `Test/Install/Production.cls`. No contended path is touched. New `Test.Fix.*` classes join the lane-a shard by area, so `ci/units.sh` is unchanged.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root.
- Run one command per tool call, with `timeout: 600000`, in the foreground, and never two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll such a run to completion in bounded foreground calls before doing anything else.
- **Tests run only on throwaways, never on `ocutalon-slot-a`.** Load and compile every file on slot A before a throwaway uses it (a compile error made 7.3's stack never become healthy).
- Classes driven by IncidentManager and FixExecutor run fresh. So does every check of `Production.cls`'s pool.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e7s4iw ci/warm.sh up`, once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s4iw ci/iris.sh class <Class>`, one call per class, for each of these: `OcuTalon.Test.Fix.Executor`, `OcuTalon.Test.Watch.Settle`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Fix.Kind`, `OcuTalon.Test.Bridge.CodeRules`. Expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e7s4i ci/iris.sh class <Class>`, fresh, one call per class, for each of these: `OcuTalon.Test.Fix.Results` (first, with Task 0), `OcuTalon.Test.Fix.Partial`, `OcuTalon.Test.Fix.Waits`, `OcuTalon.Test.Fix.Runs`, `OcuTalon.Test.Fix.Execute`, `OcuTalon.Test.Fix.Scale`, `OcuTalon.Test.Fix.DryRun`, `OcuTalon.Test.Watch.Incidents`, `OcuTalon.Test.Fix.Refused`, `OcuTalon.Test.Fix.Recheck`, `OcuTalon.Test.Fix.Later`, `OcuTalon.Test.Fix.Raise`, `OcuTalon.Test.Watch.Closing`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e7s4i ci/iris.sh shard lane-a --part k/12` for k = 1 to 12, one call each. 83 classes took 387 s, 339 s and 434 s in thirds on a fresh stack; there are about 87 with this story. Expected: passed. Record each part's time.
- (once) `<lane> OCUTALON_RUN_TAG=e7s4i ci/iris.sh shard lane-b --part k/3` for k = 1 to 3, one call each. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e7s4i ci/iris.sh live storage-roundtrip` (FixRun's Storage block), then `<lane> OCUTALON_RUN_TAG=e7s4i ci/iris.sh live production` (the item's pool). Expected: passed.
- (once) `bash ci/checks.sh`. Expected: every script passes.
- (once) `<lane> OCUTALON_RUN_TAG=e7s4iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e7s4i ci/iris.sh teardown`. Run both after a failure too.

**Shared surfaces:**
- FixRun's columns and index: `Test.Data.Tables`, the `storage-roundtrip` unit and `ci/checks.sh`'s storage checks.
- FixExecutor's pool: `Test.Install.Production` (Lane A's row) and the `production` unit.
- A run that resent copies now ends. This changes `Test.Fix.Execute` (L85, L114-117, L280), `Test.Fix.Runs` (L13-14, L51) and `Test.Fix.Executor.TestResentRunSendsNoResult`, which is replaced. Search `Test/**` for "Story 7.4's" and for assertions of `executing` after an approval.
- The payload's `requests[].result` is now filled for ended runs. `Test.Live.Payloads.TestFromRowEvidence` keeps "no result" (its request has no run). `Case.Listed` reads only the Ref and the state.
- A registered copy's failure is no longer grouped (no 7.3 test makes a copy fail).
- The dry run's `affected` gains unlisted failures. `Case.Fixture` leaves the group's `Count` empty, so the existing DryRun, Raise and Later tests are unchanged.
- The lane-a shard gains four classes.
- Every test added or changed passes on a fresh environment, in either order.

**Task 0 results (implement stage, 2026-10-29; two fresh throwaways of tag e7s4i, ready in 83 s and 82 s on this machine).**
- (a) `SELECT ID FROM OcuTalon_Data.FixRun WHERE FOR SOME %ELEMENT(Copies) (%VALUE = ?)` found the run by a copy id; `ApprovalRefIndexExists(ref, .id)` gave the run's id (it exists on the non-unique index). The plans (read with `EXPLAIN` through `iris_sql_analyze` on slot A, where the compiled class has the index) read `OcuTalon_Data.FixRun.CopiesIndex` (cost 905.69), and `CopyOf`'s join reads `FixRun(R).CopiesIndex`, then `Incident(I).RefIndex`. `CopyOf` gave the Ref for the copy as text and as a number, "" for another namespace and "" for an unknown copy.
- (b) One `Reader.Evidence` over 50 copy keys took 0.20 s and over 500 keys 0.27 s (500 failed orders, the item OrdersFromPartner; the event log is capped at 100 rows). That is far under 5 s, so `Evidence` gets no `bodies` flag and the wait reads everything.
- (c) The result Notification of a demo session S gave a Delivery row in two channels: `web` (WebChatOut) and `phone` (SimPhoneOut), one each, beside the `incident` and `answered` rows of the same two channels. No other channel kept a row.
- (d) IRIS's resend entry is `EventSource` `%Ensemble`, `EventType` `%Message`, `Event` `Resend`, description "Resend Message", and its data reads "Message identification: MessageHeaderId = <id>, MessageBodyClassName = OcuTalon.Demo.Orders.PartnerOrder, MessageBodyId = <id>, SessionId = <id>". It names the COPY: `MessageHeaderId` is the copy's new header id (the one registered on the FixRun) and `MessageBodyId` the copy's own body, while `SessionId` is the original's session (confirmed with 50 copies: the first entry read `MessageHeaderId = 52 ... MessageBodyId = 51 ... SessionId = 2`). There was one per copy (three for three, and 50 for 50), written within 0.1 s of the approval entry. OcuTalon's own Action entry (`OcuTalon/Action/Action`, "repair_resend: done") followed 0.03 s after the Approval "finished" entry, with the data of the spec and `irisUser` "ocutalon", `channel` "web".
- (e) With `TempStopConfigItem("OrdersFromPartner")` the Resend accepted the three copies: they stayed `Queued` (status 2) for the 3 s waited, the request stayed `executing`, and after `TempStopConfigItem(…, 0)` they completed; the run then ended `done` (3/3/3/0/0) and the incident resolved. `Waits` is kept.
- (f) A copy with the target format `DD/MM/YYYY` (3 orders) failed at OrdersFromPartner with "The order date was not in the expected format. Expected YYYY-MM-DD, got '16/10/2026'.", whose `Settle.Pattern` equals the group's `ErrorPattern` ("… got '#/#/#'."). The run ended 3/3/0/3/0 with the reason "the order date still wasn't accepted" and `result.failedAgain`; the incident's `Count` (3), the group's `Count` and `Seen` were unchanged and the incident resolved.
- (g) With PoolSize 2 two FixExecutor jobs were alive (2836 and 2837). While R1's three copies sat `Queued` and R1 was `executing`, a `DryRun` was answered in 0.01 s (targets 11,12,13).
- (h) Class times on a fresh stack (ready in 77 to 109 s): `Fix.Results` 42.05 s, `Fix.Partial` 37.31 s, `Fix.Waits` 32.14 s, `Fix.Runs` 63.53 s, `Fix.Execute` 53.38 s, `Fix.Scale` 20.12 s, `Fix.DryRun` 6.30 s, `Watch.Incidents` 109.23 s, `Fix.Refused` 1.16 s, `Fix.Recheck` 1.56 s, `Fix.Later` 54.36 s, `Fix.Raise` 64.02 s and `Watch.Closing` 29.37 s; warm, `Fix.Executor` 11 s and the other eight warm classes under 2 s. None passes 180 s, so no class is split.

**Commands run (implement stage, tags e7s4iw and e7s4i).**
- `ci/warm.sh up`: READY in 83 s. Warm `ci/iris.sh class`: `Fix.Executor` passed 11.0 s, `Watch.Settle` 0.01 s, `Live.Payloads` 0.32 s, `Data.Tables` 0.31 s, `Install.Production` 0.42 s, `Watch.NoticeText` 0.17 s, `Watch.Lifecycle` 0.21 s, `Fix.Kind` 0.09 s, `Bridge.CodeRules` 1.42 s.
- Fresh `ci/iris.sh class`: the 13 classes above all passed (times in (h)).
- `ci/iris.sh shard lane-a --part k/12`, k = 1 to 12, all passed, 87 classes: 248 s (8 classes), 182 s (8), 137 s (8), 97 s (7), 102 s (7), 162 s (7), 275 s (7), 207 s (7), 124 s (7), 193 s (7), 255 s (7) and 174 s (7), each including a ready time of 77 to 109 s.
- `ci/iris.sh shard lane-b --part k/3`, k = 1 to 3, all passed: 139 s (22 classes), 169 s (21) and 101 s (21).
- `ci/iris.sh live storage-roundtrip` passed (82 compiled classes, FixRun's Storage block equals its committed block); `ci/iris.sh live production` passed; `bash ci/checks.sh` passed (every script; 701 PASS lines).

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte-identically, and record a `mutation: … → …` line here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1, counts | the wait counts `Error` as completed | `Partial.TestCopiesFailAgain`, `Executor.TestResentRunEndsWithItsCounts` |
| AC 1, close | Finish skips `FinishExecution` | `Results` (R1 is done), `Executor` |
| AC 1, end | the first pass sends the result, with running copies counted as completed | `Executor.TestStillRunningAfterTheWait` |
| AC 2 | IncidentManager's `Result` passes no notification | `Results.TestAllFiftyWentThrough` |
| AC 3, reason | the fail reason always gives the copy's own sentence | `Partial.TestCopiesFailAgain`, `Executor.TestFailReasons` |
| AC 4 | `Record` keeps registered copies | `Partial.TestCopiesFailAgain`, `Incidents.TestRegisteredCopyIsNotAFailure` |
| AC 5 | Finish writes no Action entry | `Results.TestAllFiftyWentThrough`, `Executor.TestEveryRunWritesOneActionEntry` |
| AC 6 | `Run` passes Carry only the first 499 targets | `Scale.TestFiveHundredOrders` |
| AC 7 | the waiter counts every waiting run's copies into one result | `Runs.TestTwoResentRunsHaveTheirOwnResults`, `Executor.TestOneWaiterFinishesEveryRun` |
| AC 8, pool | FixExecutor PoolSize 1 | `Waits.TestNoticeSentDuringAWait` (B is noticed only once R1's wait ends) |
| AC 8, lock | a run waits in its own job while another job holds the lock | `Executor.TestOneWaiterFinishesEveryRun` |
| AC 8, session | the FixResult goes in the waiter's own session | `Executor.TestOneWaiterFinishesEveryRun` |
| AC 9 | `FromRow` leaves `result` empty | `Results` (the event and `/state`), `Payloads.TestFromRowRequestResult` |
| AC 10 | `Unlisted` gives 0 | `DryRun.TestUnlistedFailuresAreCounted`, `Settle.TestUnlisted` |
| AC 11 | a `StartExecution` error is always refused | `Executor.TestStartExecutionFailsForAnApprovedRequest` |

**Mutations done (Rule 19).** Each mutation was applied to the working tree only (never loaded on slot A), the named tests were run (probe tests warm, live tests on a fresh stack), and the file was restored from a backup (the checksums and `git diff --stat` equalled their values before):
- mutation: the wait counts `Error` as completed (`Look`: `Set completed = completed + 1` for a copy that failed again) -> red `Executor.TestResentRunEndsWithItsCounts`, `Executor.TestFailReasons`, `Executor.TestOneWaiterFinishesEveryRun` (warm) and `Partial.TestCopiesFailAgain` (fresh)
- mutation: Finish skips `FinishExecution` (the `Close` call removed) -> red `Results.TestAllFiftyWentThrough` ("R1 is done"; fresh) and `Executor.TestCouldNotStartRoutes`, `TestNothingResent`, `TestResentRunEndsWithItsCounts` and six more (warm)
- mutation: the first pass sends the result, with running copies counted as completed (`Look`: `Set completed = completed + 1` for a copy still running) -> red `Executor.TestStillRunningAfterTheWait` and `Executor.TestResentRunEndsWithItsCounts` (warm)
- mutation: IncidentManager's `Result` passes no notification (`..Event(incident, event, result.ApprovalRef, "")`) -> red `Results.TestAllFiftyWentThrough` ("S has exactly one result Notification" and both Delivery rows) and `Results.TestLaterRequestPendingAfterTheResult` (fresh)
- mutation: the fail reason always gives the copy's own sentence (`FailReason`: the `Own` test replaced by 0) -> red `Executor.TestFailReasons`, `Executor.TestResentRunEndsWithItsCounts`, `Executor.TestOneWaiterFinishesEveryRun` (warm) and `Partial.TestCopiesFailAgain` (fresh)
- mutation: `Record` keeps registered copies (the `CopyOf` line removed) -> red `Partial.TestCopiesFailAgain` ("the incident's Count is unchanged ...") and `Incidents.TestRegisteredCopyIsNotAFailure` (fresh)
- mutation: Finish writes no Action entry (the `Audit` call removed) -> red `Results.TestAllFiftyWentThrough` ("the audit log holds one OcuTalon Action entry") (fresh) and `Executor.TestEveryRunWritesOneActionEntry`, `TestCouldNotStartRoutes`, `TestNothingResent` and three more (warm)
- mutation: `Run` passes Carry only the first 499 targets (`$Piece(passed, ",", 1, 499)`) -> red `Scale.TestFiveHundredOrders` ("the FixRun holds 500 copies"; fresh)
- mutation: the waiter counts every waiting run's copies into one result (`Look`: Resent adds the copies of the runs before, kept in a global) -> red `Runs.TestTwoResentRunsHaveTheirOwnResults` (fresh) and `Executor.TestOneWaiterFinishesEveryRun` (warm)
- mutation: FixExecutor PoolSize 1 (`Production.cls`) -> red `Waits.TestNoticeSentDuringAWait` ("B is noticed while R1 waits"; fresh)
- mutation: a run waits in its own job while another job holds the lock (`Wait`: the `If '$Test Quit` removed) -> red `Executor.TestOneWaiterFinishesEveryRun` ("neither sent a FixResult", "both runs wait"; warm)
- mutation: the FixResult goes in the waiter's own session (`Report`: the `..%SessionId` assignment removed) -> red `Executor.TestOneWaiterFinishesEveryRun` (both "trace session" assertions; warm)
- mutation: `FromRow` leaves `result` empty (`Incident` payload: the result block under `If 0`) -> red `Payloads.TestFromRowRequestResult` (warm) and `Results.TestAllFiftyWentThrough` (the event and /state) and `Results.TestLaterRequestPendingAfterTheResult` (fresh)
- mutation: `Unlisted` gives 0 (`Set unlisted = 0`) -> red `Settle.TestUnlisted` (warm) and `DryRun.TestUnlistedFailuresAreCounted` (fresh)
- mutation: a `StartExecution` error is always refused (`Execute`: the NOSTART branch under `If 0`) -> red `Executor.TestStartExecutionFailsForAnApprovedRequest` (warm)
- mutation (beyond the table): `OfRequest` does not compare the Ref exactly (the `ApprovalRef '= ref` test removed) -> red `Payloads.TestFromRowRequestResult` ("OfRequest ... compares it exactly"; warm)
- mutation (beyond the table): `DryRun` does not refuse a window that `Seen` has cut (the `'known` test under `If 0`) -> red `DryRun.TestUncountableWindowIsRefused` (fresh)

**Mutations done for the review patches (Rule 19; warm `Test.Fix.Executor`, each file restored from a backup, `git status --short` and `git diff --stat` equal to their values before, green again on the same stack; no mutated file was loaded on slot A).**
- mutation: `Deferred` counted as failed again (`COPYFAILED` gains `Deferred`) -> red `Executor.TestResentRunEndsWithItsCounts` ("Deferred: the wait read twice" and the counts of the second read)
- mutation: a header the read lacks counted as completed (`Look`: `|| (status = "")`) -> red `Executor.TestResentRunEndsWithItsCounts` ("missing: the wait read twice") and `Executor.TestStillRunningAfterTheWait`
- mutation: a run that erred after a copy ends as couldn't start (`Run`: `If copies = 0` replaced by `If 1`) -> red `Executor.TestRunThatErredAfterACopyStillWaits` (the request, the counts, the reason and the stored result)
- mutation: a look that throws logs nothing (`Pass`: `If '$Data(last(id, "fault"))` replaced by `If 0`) -> red `Executor.TestStillRunningAfterTheWait` ("one Type 3 warning names the request, however many passes threw")
- mutation: a look that throws logs on every pass (the same line replaced by `If 1`) -> red `Executor.TestStillRunningAfterTheWait` (the same assertion)

**Verification after the review patches (stage `implement`, tags e7s4iw and e7s4i).**
- Warm, `ci/warm.sh up` 83 s: the 9 listed classes passed (`Fix.Executor` 15.3 s, the rest under 1.5 s).
- Fresh, one class per call: `Fix.Results` 43.6 s, `Fix.Partial` 37.7 s, `Fix.Waits` 31.6 s, `Fix.Runs` 63.6 s, `Fix.Execute` 54.5 s, `Fix.Scale` 20.1 s, `Fix.DryRun` 5.1 s, `Watch.Incidents` 111.5 s, `Fix.Refused` 1.3 s, `Fix.Recheck` 1.2 s, `Fix.Later` 54.8 s, `Fix.Raise` 62.2 s and `Watch.Closing` 29.8 s, all passed.
- `shard lane-a --part k/12`, k = 1 to 12, all passed: 271 s, 173 s, 124 s, 102 s, 126 s, 173 s, 276 s, 199 s, 96 s, 171 s, 255 s and 171 s (each includes a ready time of 77 to 109 s); `shard lane-b --part k/3` passed: 133 s, 169 s and 100 s.
- `live storage-roundtrip` and `live production` passed; `bash ci/checks.sh` passed (701 PASS lines); both stacks were torn down (0 leftovers).

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-28).** The story is planned in full against the READY FOR DEVELOPMENT standard. The plan stage made no runtime call: no slot read and no throwaway. Task 0 belongs to the implement stage.

The lead rules these items at the spec gate. Each is planned as recommended, and none blocks the build:
- **V1 (veto, schema).** Nine appended `FixRun` properties and `CopiesIndex On Copies(ELEMENTS)`.
- **V2 (veto, production structure; DW-381).** `FixExecutor` gets PoolSize 2 in Lane A's region of `Production.cls`, and one waiting job finishes every waiting run. Lane A's `FixExecutor` oracle row follows. No AD is amended.
- **V3 (veto, public text).** `NOSTART`, "OcuTalon couldn't start the resend"; and the fail reason "the {field} still wasn't accepted" (UX's example).
- **Declined, for a ruling above this story:**
  - DW-368: it needs an AD-16 amendment, or a new key in the page's own selection (`web/**`, contended).
  - DW-380's past-expiry half: AD-16's refused list.

  The recommended AD-16 amendment for each is under Design Notes.
- **Optional split (decide for the lead).** A sibling Story 7.7 would take the 500-message criterion and DW-318.

The `oversized` and `multiple-goals` warnings are set. There is no NFR tripwire and no contended path, and no footprint extension beyond Lane A's oracle row, which Story 7.3's ruling already allowed.

**Implement and review (2026-10-29).**

*Summary.* An approved run that resent copies now ends. `FixExecutor` waits up to 60 seconds from `ResentAt` for the copies through `Watch.Reader.Evidence`, counts them, stores the counts and `EndedAt` on the run's `FixRun`, closes the request through `Approval.FinishExecution`, writes one OcuTalon `Action` entry through `Bridge.Audit` and sends the one final `FixResult` in the incident's trace session. `FixExecutor` has PoolSize 2, and one job at a time waits (`WAITLOCK`) for every waiting run, so a dry run is answered during a wait (DW-381). `IncidentManager.Record` drops the failure of a registered copy (`FixRun.CopyOf`). The incident payload lists each ended request's stored result for events and `/state` (`FixRun.OfRequest`, object access only). The dry run counts the failures that `Seen` no longer lists and refuses a window that `Seen` has cut (DW-318). An approved, unexpired request whose `StartExecution` fails ends as could not start (`NOSTART`; DW-380's first half). DW-368 and DW-380's past-expiry half are not built.

*Files changed* (under `src/ocutalon/cls/OcuTalon/`):
- `Data/FixRun.cls`: nine appended properties, `CopiesIndex`, `OfRequest`, `CopyOf`.
- `Data/FailureGroup.cls`: `Unlisted`.
- `Watch/Settle.cls`: `Seconds` public.
- `Fix/Kind/RepairResend.cls`: `DryRun` counts unlisted failures and refuses a cut window.
- `Fix/Executor.cls`: parameters, seams (`Start`, `Statuses`, `Waiting`, `WriteAudit`), `Wait`, `Pass`, `Look`, `FailReason`, `Finish`, `Audit`, `Report`, the `NOSTART` branch, class doc.
- `Watch/IncidentManager.cls`: `Record` skips registered copies; doc.
- `Live/Payload/Incident.cls`: each ended request's `Result`.
- `Production.cls` and `Test/Install/Production.cls` (Lane A's row only): FixExecutor PoolSize 2.
- Tests: new `Test/Fix/{Results,Partial,Waits,Scale}.cls`; changed `Test/Fix/{Executor,ExecutorProbe,Runs,Execute,DryRun}.cls`, `Test/Watch/{Case,Incidents,Settle}.cls`, `Test/Live/Payloads.cls`, `Test/Data/Tables.cls`.

*Review.* Four layers reported 34 findings: high 0, medium 4, low 25, false 5 (triage log above).
- **Patches applied (12 findings, 7 root causes):**
  - three medium: the untested run that erred after a copy (`TestRunThatErredAfterACopyStillWaits`), the still-running states pinned only together (each state on its own), and an assertion in `Results` that could not fail (removed);
  - four low: a swallowed look exception (`LOGLOOK`, once per run), `Pass`'s doc, the class doc for a run whose `ResentAt` cannot be saved, and Rule 14 wording in three files (the `WAITNOTICE` doc was reworded along with the rejected timing finding).
- **Deferred:** none.
- **Rejected (22):**
  - false (5): AC bullets without their own mutation line (Rule 19 asks one per AC), the probe-versus-real-item remark, the `/state` source scan, `ApprovalRefIndexExists` on a non-unique index (Task 0 (a)), and the changes outside the listed surfaces (planned).
  - low (17), with reasons in the log: the unindexed `Waiting` scan and the per-pass `Evidence` read (measured 0.27 s for 500 keys), a failed `ResentAt` save (Residual risk 3), unreached targets counted as Skipped (the spec's counts), a copy that finishes in the last 0.5 s, a throwing `Waiting` after the unlock, an incident without a group or `TraceHeaderId`, `CopiesIndex` over pre-existing rows, a run no pass saw before its deadline, untested quiesce and error exits of `Wait`, and the `Waits` timing.
- Follow-up review recommended: `true` (three medium entries were patched). The unverified risk: no CI runner has run the story's fresh classes. `Test.Fix.Waits` must restart OrdersFromPartner inside R1's 60 seconds after waiting for B's notice, which took 32 s in all on the developer machine; the runner is about three times as slow on CPU, and a slow run could turn it red.

*Verification.* Recorded under `## Verification`, the second pass after the patches: 9 warm and 13 fresh classes, `shard lane-a` 12 parts (87 classes) and `shard lane-b` 3 parts, `live storage-roundtrip`, `live production` and `bash ci/checks.sh` all passed; every Matrix row has a covering test that ran and passed; 22 mutations (17 from the implement pass, 5 for the patches) each went red in the named tests and were reverted. Task 0's results are under `## Verification` as well.

*Residual risks.*
- A failed `ResentAt` save, a holder that stops on an error or on quiesce, and a copy that finishes in the last 0.5 s of the wait leave the request executing until Story 7.5's Sweep.
- `Waiting()` reads every `FixRun` with a `ResentAt` and no `EndedAt` on each 0.5 s pass, with no index; stuck runs are re-read until the Sweep ends them.
- An instance with the old production definition needs a production update for the PoolSize change.
- DW-368 and the past-expiry half of DW-380 stand (escalated for the decision sheet).
