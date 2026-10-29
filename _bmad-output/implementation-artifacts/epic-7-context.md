# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. For a data-format cause, OcuTalon proposes repair and resend with a dry run that changes nothing. It raises one approval request fixed to exact targets and carries it on the incident notice; failures that arrive later get their own dry run and request in the same incident. After approval it re-checks each target, resends repaired copies, leaves the originals untouched and reports how many went through ("All 50 orders went through."), for at least 500 messages. It never retries a failed resend, or acts on a changed target, without a new approval, and a resend cut short by a restart says how far it got. This turns Epic 5's diagnosed incident into an approved fix you can audit, moving the incident through awaiting approval, fixing and resolved.

## Stories

- Story 7.1: Repair and resend proposes a dry run that changes nothing (done)
- Story 7.2: The incident notice carries the dry run and one approval request (done)
- Story 7.6: Later failures in the same incident get their own dry run and approval request (done)
- Story 7.3: Approved repairs are re-checked and resent (done)
- Story 7.4: OcuTalon reports how many orders went through (next)
- Story 7.5: A resend cut short by a restart says how far it got

## Requirements & Constraints

- **A repair is narrow.** It reformats one field with a reformatter registered in code (date patterns and number formats from a fixed set). The model picks only the kind and its parameters (field, source format, target format). No model-written code runs. A reformatter refuses a value that doesn't match its source format and never evaluates its input.
- **What is approved is exactly what runs (owner U-126), per request.** The card, the notice and the executor read one record: the `ApprovalRequest` row's `FixKind`, `FixParameters`, `FixTargets` and `DryRun`. `FixExecutor` works from the row alone. A later request takes the first request's kind and parameters, and its targets from its own window only.
- **No model, and no change before approval.**
  - The CI mock receives no request during a dry run or an execution.
  - A dry run, a rejection or an expiry changes nothing in OCUTALON or OCUORDERS and sends no `Execute`. A cancellation sends no outcome, and the incident stays as it is.
- **Re-check before resending.** Each target must still be failed, not resent, unchanged in its body and inside its own request's `FixTargets`. A changed target is skipped with a plain reason and never acted on without a new approval.
- **The originals stay unchanged.** Each copy stays in its original's trace session, with the same `SuperSession`. The incident's trace links to the copies by their registered header ids.
- **A copy that fails again** is reported and never retried without a new approval. It is recognised by its registered header id and counts against the fix. It never opens a new failure group or incident, and never reaches `Record` as a later failure, so it never starts a later round (Story 7.4; until then such a copy still joins its group).
- **Each request's result is its own.** Two approved requests of one incident make two `FixRun` rows with their own `ApprovalRef` (U-134, pinned by 7.3). Once copies were resent, each request's final `FixResult`, `FixRun` and result notice carry its own counts, and neither run's copies count in the other's (U-140, Story 7.4). One fix runs at a time per incident; the earliest waiting request gets the next `Execute`.
- **Every approved request ends.** No request may stay `approved` with its incident `fixing` and no result (DW-380).
- **Results and audit.** Each run sends one `result` notification, so every channel shows the same result at once. It writes one OcuTalon `Action` audit entry beside IRIS's own resend entries (Story 7.4; none is written yet). The entry holds no key, token, password or Telegram identity.
- **Scale.** One request covers at least 500 messages. The test runs at exactly 500: 500 counted, 500 targets, 500 resent, 500 completed.
- **No fix to propose.** A fallback diagnosis or a non-data-format cause gets no dry run and no request. A first dry run that is refused, finds nothing, or whose `Raise` fails takes Epic 5's no-fix notice (U-127). A later round that cannot raise sends nothing and logs one warning for an error (U-133).
- **Approval before risk** in every configuration. The production's testing switch stays off. Each fix kind has a test that sends `Execute` with no approved row and expects nothing to happen.

## Technical Decisions

- **The answer path (spine, U-120).** `AnswersIn` → `AnswerOps` → `Approval.Answer` → `ApprovalHold` → `ApprovalOutcome` → `IncidentManager` → `FixExecutor` → `IncidentManager` → `Notify`. Tests answer by calling `Answer(ref, action, channel, irisUser, sessionRef)` directly.
- **Fix kinds.** `OcuTalon.Fix.Kind` is the contract: `DryRun`, `Recheck` and `Execute` against fixed targets, a parameter schema, `RESOURCES` (`resource:permission[,...]`, which generates the service role's grants) and `NOTALLOWED` (required of every kind that declares `RESOURCES`). Permission checks use `$SYSTEM.Security.CheckUserPermission`, one letter per call (the bridge's `Gate.MissingOf`). No role ever holds `%Ens_MessageEditResend`.
- **Messages.** `Fix.Msg.Execute` (`ApprovalRef` only), `Fix.Msg.FixResult` (`ApprovalRef`, `IncidentRef`, `Final`, `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted`, `Reason`), `Fix.Msg.DryRun` and `DryRunResult` get no new properties. Items are addressed by name. The bridge never references OcuTalon packages, so a fix kind is a plain string on bridge rows.
- **The approval row.** States `pending` → `approved`, `rejected`, `expired` or `cancelled`; `approved` → `executing` → `done` or `failed`, or straight to `failed` when a run can't start. `StartExecution` needs an approved row whose `ExpiresAt` is ahead. `FinishExecution(ref, done|failed|interrupted)` fires `approval.result`; `interrupted` leaves the row `failed`. `Approval.Expire` moves only pending rows. Every change writes an `Approval` audit entry.
- **`IncidentManager`** is the only writer of `Incident` and `FailureGroup` and the only publisher of `incident` events (after commit, each payload the full current view). It moves the incident only by AD-15's transition table and refuses an `ApprovalOutcome` or `FixResult` the row doesn't show. A `FixResult`'s own request never counts as waiting. It answers an accepted approval with `answered.approved` and every accepted final or interrupted `FixResult` with one `result` notification (no `DecisionRef`; a progress `FixResult` sends none). If the slots can't be built it logs one warning (`LOGRESULT`) and still makes the move. `PurgeOne` deletes an incident's `FixRun` rows with it.
- **Later requests (built by 7.6).** Each ask marks its window on the incident's failure groups (`AskedFrom`/`AskedTo`, keys of `Seen`), and the dry run reads only that window, so a failure is never in two requests. Error paths put the marks back; a refused or empty dry run keeps them. An Open incident only updates its count.
- **Notifications.** Producers send catalog keys and slots, never text: UTC ISO 8601 times, integer counts, `itemNoun` as `{one, other}`. `IncidentManager` sends one notification per recipient from `Session.Recipients(ownerRef, incidentRef)`. `answered` and `result` carry `ApprovalRef` and `IncidentRef`, so the chat and the phone edit their message in place. A result's noun is the request's dry-run `itemNoun`, else the incident's.
- **Result texts (spine convention, built as `Notice.ResultKey`/`ResultSlots`).** Every `result` producer (7.4, 7.5, Story 30.5) picks its key from the stored result fields, first match wins:
  - row `executing` → `result.stillResending`;
  - `Interrupted` > 0 → `result.interrupted` (`remaining` = total − completed);
  - every count 0 and `Reason` set → `result.couldNotStart`;
  - `FailedAgain` and `Skipped` > 0 → `result.failedAndSkipped`; `FailedAgain` → `result.failedAgain` (`failReason` = `Reason`); `Skipped` → `result.skipped`;
  - otherwise `result.allThrough`. So a final result must count every copy: one with `Completed` below `Total` and nothing else set still reads "All … went through".
- **`FixExecutor` as built by 7.3.** It refuses (one info line, nothing sent) an `Execute` whose row is not approved, is past `ExpiresAt`, or is unknown. A run that can't start calls `FinishExecution` `failed`, then sends a final `FixResult` with `Resent` 0, `Total` = the row's target count and one reason:
  - `NOTALLOWED`: the service user lacks the kind's `RESOURCES` ("OcuTalon isn't allowed to resend messages in that production");
  - `UNUSABLE`: the row can't be used ("OcuTalon couldn't read the approved fix", U-141);
  - `NOREAD`: the re-check can't read the production, or any error before the first copy ("OcuTalon couldn't read the failed messages in that production").
  Otherwise it calls `StartExecution`, saves one `FixRun`, re-checks every target (`Recheck`, through `Watch.Reader`; "not resent" is IRIS's own `Resent <ids>` mark), reads the plan again in `Execute`, and resends from its one `New $NAMESPACE` method with `Ens.MessageHeader.ResendDuplicatedMessage`, saving each copy's header id to `FixRun.Copies` as it goes. Skip reasons are one sentence naming the message, through `Redact.Text`. A run that resent nothing closes `done` with `Skipped` = `Total` and the lowest-id target's reason.
- **What 7.3 left for 7.4 (U-140).** A run that resent copies ends after its last registration, inside FixExecutor's job, with its row `executing`, its incident `fixing` and no `FixResult`. 7.4 adds the 60-second wait, `Completed`/`FailedAgain` with its reason, `FinishExecution`, the close and the `Action` entry. FixExecutor is `PoolSize 1` and also answers every dry-run ask, so the wait must run where it can't hold another incident's notice past AD-15's 35 s (DW-381). A run's skipped targets are not stored: they are `FixTargets` less the copies' originals (each copy's header names its original).
- **`Data.FixRun`**: `ApprovalRef`, `IncidentRef`, `StartedAt` and `Copies` (list of header ids, owner U-139), one row per approved request taken up, couldn't-start included. Copy recognition adds `Index … On Copies(ELEMENTS)`; the run state and the stored final counts (DW-272) are appended properties of 7.4 and 7.5. Stored properties are append-only, and every persistent class commits its `Storage` block.
- **Restarts (7.5).** `Install.Registry.CallAreas("Reconcile")` calls `Reconcile()` on every `Install.Step.<Name>`. The Fix area's `Reconcile()`, in `Install.Step.Fix`, marks each running `FixRun` interrupted, never resumes it, and closes its row with `FinishExecution` `interrupted`. On every `Tick`, `Checks` calls `Fix.Run.Sweep()` (a new class) and sends each final `FixResult` to `IncidentManager`: exactly one per run, each request's own. A crash between a resend and its registration loses that one id. Sweep's still-running branch is Story 30.5's.
- **Audit.** Write only through `OcuTalon.Bridge.Audit.Record("Action", data)`, with exactly `irisUser`, `sessionRef`, `channel`, `action`, `target`, `result`, `counts` and `approvalRef`. Tests read entries by `UTCTimeStamp` range, polling with a timeout, because the indexes lag up to 60 s.
- **Tests and the mock.** `%UnitTest` classes under `OcuTalon.Test.<Area>`, run on throwaways. The mock logs every request to `/opt/ocutalon/mock-log/requests.jsonl`, the evidence for "no model request"; a test must fail when that log is missing. For failed orders call `Partner.Send(count, dateFormat, traceRef, orderDate)` in OCUORDERS; UJ-1's live case is 50 `MM/DD/YYYY` orders with the mock's existing `diagnosis` scenario. Times convert only through `OcuTalon.Data.Time` (`Bridge.Time` in the bridge). Take OCUORDERS snapshots only after `Case.WaitSettled`.

## UX & Interaction Patterns

- **Voice.** Numbers first, then the cause, then the choice. "Nothing was changed." ends every rejection, expiry and couldn't-start text. The phone and Telegram say "becomes", not arrows.
- **Texts the tests assert (UJ-1 fixture).**
  - Dry run: "Dry run: 50 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet."
  - Later request: "3 more orders failed since 14:20 ET, with the same cause. I can repair and resend all 3. Approve?", then its own dry run, then "Details and trace: on your OcuTalon page."
  - Approved: "Approved from {channel} at {time}".
  - Results: "All 50 orders went through."; "48 of 50 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval."; "47 of 50 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval."; "Nothing was resent: {reason}. Nothing was changed."
  - Restart: "The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval."
  - The catalog also has count-of-one forms. New public wording (DW-368, DW-380) is a veto-window item.
- **On the page (Epic 6's, built).** Each request card shows its own answered status and result band, followed by "Recorded in the IRIS audit log." The page renders results from the payload's `Requests[].State` and `Result`.

## Cross-Story Dependencies

- **Story order.** 7.4 → 7.5.
- **Built by 7.1, 7.2, 7.6.** `Fix.Kind.RepairResend` (parameters `field,sourceFormat,targetFormat`, `RESOURCES` `%Ens_MessageResend:U`, `FieldWords`), `Fix.Reformat`, `Install.Step.Fix.Grants()` (where 7.5's `Reconcile()` belongs); `IncidentManager.Propose`/`Ask`/later waiter and the seams `SendDryRun`, `RaiseRequest`, `CancelRequest`, `AnswerNotice`; `Notice.WithFixSlots`. Test helpers: `Test.Fix.Snapshot` (`Take`, `Diff`), `Test.Fix.Later` (two requests in one incident on a real production, the base for 7.4's two-results pin), `Test.Watch.Case`, `IncidentProbe`.
- **Built by 7.3.** `Fix.Executor` (above), `RepairResend.Recheck`/`Execute`, `Reader.Evidence`'s `resent` flag, `FixRun.Copies`, `Notice.ResultKey`/`ResultSlots`, `answered.approved` and the result notice. Tests: `Test.Fix.{Executor,ExecutorProbe,Recheck,Execute,Refused,Runs}`; `Case` gains `ExecutesOf`, `FixResultsOf`, `RunOf`, `WaitIncidentState`, `WaitSettled`, `SendExecute`, `SetOrderDate`. No 7.3 test makes a copy fail again. `Runs.TestStoppedProductionSkipsEveryCopy` pins a stopped production's copies as `Skipped`.
- **What 7.4 and 7.5 take.** 7.4: the end of a run that resent copies, copy recognition by `Copies`, the result per request, the `Action` entry, the 500-message run. 7.5: `FixRun` and the `executing` row for `Reconcile` and `Sweep` (which also own a row a failed `FinishExecution` left `executing`), and `ResultKey` for the interrupted result.
- **Built by Epic 6 (merged):** the incident and approval cards, the result band, `AnswerOps`, and the simulated phone's in-place edit by `ApprovalRef`. Epic 6's `Test.Demo.IncidentManagerDouble` does not extend `IncidentManager`.
- **Open ledger items, Story 7.4:**
  - DW-272: store the final `FixResult` counts so each request in the payload carries its `Result`.
  - DW-318: the dry run reads only `Seen`, capped at the newest 1000 keys (`Settle.SEENMAX`), so past 1000 failures `affected` and `resend` fall below `Count` with nothing saying so, and more than 1000 joining during one ask empties a window. Make the count honest and pin it.
  - DW-292: `Live.Payload.Incident.FromRow` (object access only; `/state` has no SQL grant) fills `groups`, `requests`, `evidence` and `traceTargets`.
  - DW-368: a stopped production renders `result.skipped`'s "had changed since the dry run"; give it an honest result (its plain reason or a key of its own).
  - DW-380: an approved request whose `ExpiresAt` passes before FixExecutor takes its `Execute`, or whose `StartExecution` fails, is refused silently and stays `approved`/`fixing`; end it as couldn't start. It becomes reachable once 7.4's wait holds a later request's `Execute`.
  - DW-381: the 60-second wait must not block dry-run asks (above).
- **Other open items.** DW-365 (`decision-pending`, owner): a later request reuses the first diagnosis's `fixSummary`, whose count could contradict the later round's; don't change it ad hoc. DW-345 (terminal): a later ask never answered leaves `AskingSince` set. DW-328 (owner sheet): Fix's references to `Watch.Reader`, `FailurePoller.Scope`, `ItemNoun` and `Transitions` stay as they are.
- **Contended paths now** (ask the orchestrator before editing):
  - Not yet in this branch (Epics 8 and 10 merged into the feature branch): `Schedule/**`, `Msg/Tick.cls`, `ci/iris.sh`, `Test/Live/**` beyond the shared `Test/Live/Payloads.cls` entries; `Core/{SessionOps,AnswersIn,StatusMonitor,Allowance,Trace}*.cls`, `Data/{Pairing,Delivery,StatusMark}.cls`, `Web/Api.cls` beyond shared entries. So DW-272/DW-292 tests of `FromRow` go in `Test/Watch/**` or `Payloads.cls` entries, and 7.5's Sweep call goes in `Checks`.
  - Live: Epic 9 (`Eval/**`, `Test/Eval/**`, `eval/**`, `.github/workflows/lane-a.yml`); Epic 16 (web and public paths, `Core/BridgeSink*`, `Test/{Web,Data}/**`; in `Test/Data/Tables.cls` edit only Lane A's entries).
  - Waiting: Epic 15 (every `Install/**` file but `Install/Step/Fix.cls`); Epic 13 (`src/bridge/cls/OcuTalon/BridgeExample/**`, its `ci/mock/scenarios/A/bridge-example-*.json`, and `Test/Install/Production.cls`, where Lane A changes only its own `FixExecutor` row). A new Epic 7 scenario file under `ci/mock/scenarios/A/` is no collision.
  - Lane A's own: `Fix/**`, `Test/Fix/**`, `src/bridge/**`, `Watch/**`, `Checks/**`, `Tools/**`, `Msg/Catalog/Watch.cls`, `Test/{Watch,Bridge}/**`, `Install/Step/Fix.cls`, Lane A's Data tables (`Incident`, `FailureGroup`, `FixRun`, `Bridge.Data.*`), and the lane-a entry in `ci/units.sh`.
- **Later epics.** Story 30.5 adds the still-running and mixed results. Epic 11 turns the demo path's incident, approval and result steps on end to end. Epic 14 lists `RESOURCES`. Stories 9.5, 12.6 and 29.4 wait for Epic 7 to merge.
