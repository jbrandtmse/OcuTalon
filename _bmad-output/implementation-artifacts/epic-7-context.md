# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. For a data-format cause, OcuTalon proposes repair and resend with a dry run that changes nothing. It raises one approval request fixed to exact targets and carries it on the incident notice; failures that arrive later get their own dry run and request in the same incident. After approval it re-checks each target, resends repaired copies, leaves the originals untouched and reports how many went through ("All 50 orders went through."), for at least 500 messages. It never retries a failed resend, or acts on a changed target, without a new approval, and a resend cut short by a restart says how far it got. This turns Epic 5's diagnosed incident into an approved fix you can audit, moving the incident through awaiting approval, fixing and resolved.

## Stories

- Story 7.1: Repair and resend proposes a dry run that changes nothing (done)
- Story 7.2: The incident notice carries the dry run and one approval request (done)
- Story 7.6: Later failures in the same incident get their own dry run and approval request (next; split from 7.2)
- Story 7.3: Approved repairs are re-checked and resent
- Story 7.4: OcuTalon reports how many orders went through
- Story 7.5: A resend cut short by a restart says how far it got

## Requirements & Constraints

- **A repair is narrow.** It reformats one field with a reformatter registered in code (date patterns and number formats from a fixed set). The model picks only the kind and its parameters (field, source format, target format). No model-written code runs. A reformatter refuses a value that doesn't match its source format and never evaluates its input.
- **What is approved is exactly what runs (owner decision U-126).** The card, the notice and the executor read one record: the `ApprovalRequest` row's `FixKind`, `FixParameters`, `FixTargets` and `DryRun`, all written from one dry-run ask and its one answer. `FixExecutor` loads the kind, targets and change from the row alone.
- **No model, and no change before approval.**
  - The CI mock receives no request during a dry run or an execution.
  - A dry run, a rejection or an expiry changes nothing in OCUTALON or OCUORDERS. A rejection or expiry sends no `Execute`.
  - A cancellation sends no outcome, and the incident stays as it is.
- **Re-check before resending.** Each target must still be failed, not resent, unchanged in its body and inside the request's scope. A changed target is skipped with a plain reason and never acted on without a new approval. Parse and check each id in `FixTargets`: `Raise` checks only that it is non-empty.
- **The originals stay unchanged.** Each copy stays in its original's trace session, with the same `SuperSession`. The incident's trace links to the copies by their registered header ids.
- **A copy that fails again** is reported and never retried without a new approval. It is recognised by its registered header id and counts against the fix; it never opens a new failure group or incident.
- **Later requests (7.6).**
  - Same-cause failures that join after the notice never join an existing request's fixed targets.
  - While the incident is awaiting approval, fixing or resolved, they settle by the same rule and get their own dry run, request and notice.
  - An Open incident (fallback, no fix, rejected or expired) only updates its count.
  - Each approved request gets its own `FixRun`, and one fix runs at a time per incident.
- **Results and audit.** Each run sends one `result` notification, so every channel shows the same result at once. It writes one OcuTalon `Action` audit entry beside IRIS's own resend entries. The entry holds no key, token, password or Telegram identity.
- **Scale.** One request covers at least 500 messages. The test runs at exactly 500: 500 counted, 500 targets, 500 resent, 500 completed.
- **No fix to propose.**
  - A fallback diagnosis, or a cause that isn't a data-format change, gets no dry run and no request.
  - A data-format diagnosis whose dry run is refused or finds nothing to resend, or whose `Raise` fails, takes Epic 5's no-fix notice (U-127; no new public text).
- **Approval before risk** in every configuration. The production's testing switch stays off. Each fix kind has a test that sends `Execute` with no approved row and expects nothing to happen.

## Technical Decisions

- **The answer path, as amended in the spine under U-120.** `AnswersIn` → `AnswerOps` (synchronous) → `Approval.Answer` → `ApprovalHold` → `ApprovalOutcome` → `IncidentManager` → `FixExecutor` → `IncidentManager` → `Notify`. Epic 7 builds from `Approval.Answer` onward. Tests answer by calling `Answer(ref, action, channel, irisUser, sessionRef)` directly.
- **Fix kinds.** `OcuTalon.Fix.Kind` is the contract:
  - `DryRun`, `Recheck` and `Execute` against fixed targets, with a parameter schema.
  - A `RESOURCES` parameter, `resource:permission[,...]`, which generates the service role's grants.
  - Permission checks use `$SYSTEM.Security.CheckUserPermission`, one letter per call. No role ever holds `%Ens_MessageEditResend`.
- **Messages.**
  - `Fix.Msg.Execute` (`ApprovalRef` only) and `Fix.Msg.FixResult` (`ApprovalRef`, `IncidentRef`, `Final`, `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted`, `Reason`) get no new properties.
  - The dry-run ask is `Fix.Msg.DryRun`, answered by `DryRunResult`.
  - Items are addressed only by name.
  - The bridge never references OcuTalon packages (a CI check), so a fix kind is a plain string on bridge rows.
- **The approval row.**
  - `Raise` refuses inside an open transaction. It starts the hold synchronously: OK means held, and a failure leaves nothing.
  - A `fix` row requires `FixKind`, `FixParameters` (one JSON object) and `FixTargets` (ascending, comma-separated header ids).
  - States: `pending` → `approved`, `rejected`, `expired` or `cancelled`. `approved` → `executing` → `done` or `failed`, or straight to `failed` when a run can't start.
  - `StartExecution` needs an approved row whose `ExpiresAt` is ahead, and fires nothing.
  - `FinishExecution(ref, done|failed|interrupted)` fires `approval.result`. `interrupted` leaves the row `failed`.
  - Every change writes an `Approval` audit entry.
- **`IncidentManager`.**
  - It is the only writer of `Incident` and `FailureGroup`, and the only publisher of `incident` events. It publishes after commit, each payload the full current view.
  - It moves the incident only by AD-15's transition table, which already covers overlapping requests, a waiting `Execute` and interrupted results.
  - It refuses an `ApprovalOutcome` or `FixResult` that the row doesn't show.
  - A request counts as pending while it is `pending`, or while it is `approved` and the incident is still `awaiting_approval`. The earliest waiting request in `RequestRefs` order gets the next `Execute`.
  - `Live.Payload.Incident.FromRow` (Lane A's, per AD-33, though it lives under `Live/`) uses object access only, because `/state` has no SQL grant. It opens each request by `Ref`.
- **Notifications.**
  - Producers send catalog keys and slots, never text: times in UTC ISO 8601, counts as integers, `itemNoun` as `{one, other}`, and model-written slots as plain sentences without times.
  - For an incident's fix requests, `IncidentManager` (not `BridgeSink`) sends one notification per recipient from `Session.Recipients(ownerRef, incidentRef)`.
  - Kind `approval` is only for a later request (`incident.laterRequest`, with the same dry-run slots as `incident.withFix`).
  - `answered` and `result` carry `ApprovalRef` and `IncidentRef`, so the chat and the phone edit their message in place.
  - The answered keys are `answered.approved` (7.3's), `answered.rejected` and `answered.expired`, never the `…By` forms.
- **Result texts (spine convention).** Every `result` producer (7.3, 7.4, 7.5 and Epic 30's Story 30.5) picks its key from the stored result fields in the order the page uses. The first match wins:
  - `State` `executing` → `result.stillResending`.
  - `Interrupted` > 0 → `result.interrupted`, with `remaining` = total − completed.
  - Every count 0 and `Reason` set → `result.couldNotStart`, with `reason`.
  - `FailedAgain` > 0 and `Skipped` > 0 → `result.failedAndSkipped`.
  - `FailedAgain` > 0 → `result.failedAgain`, with `failReason` = `Reason`.
  - `Skipped` > 0 → `result.skipped`.
  - Otherwise → `result.allThrough`.
  - The other slots, as each key needs them: `count`, `itemNoun`, `completed`, `failedAgain`, `skipped`.
- **`FixExecutor`.**
  - A refused `Execute` (pending, rejected, expired, cancelled, already executing or unknown) changes nothing and sends nothing.
  - If the service user lacks the kind's `RESOURCES`, it sends a final `FixResult` with `Resent` 0 and a plain `Reason`, then calls `FinishExecution` `failed`.
  - It resends from its one `New $NAMESPACE` method with `Ens.MessageHeader.ResendDuplicatedMessage(original, , target, newBody)`. It builds each body with the body class as resolved in that namespace, registers each new header id on the `FixRun`, and waits up to 60 s per copy.
  - A stopped target production returns `ErrProductionNotRunning`, and that copy is `Skipped` with a plain reason.
  - Measured on build 154: 500 copies resend in under a second, and IRIS audits each one.
- **`Data.FixRun`** holds only `ApprovalRef`, `IncidentRef` and `StartedAt`. It needs appended properties for the registered copies, the run state and the stored final counts. Stored properties are append-only, and every persistent class commits its `Storage` block.
- **Restarts.**
  - `Install.Registry.CallAreas("Reconcile")` calls `Reconcile()` on every `Install.Step.<Name>`.
  - The Fix area's `Reconcile()`, in `Install.Step.Fix`, marks each running `FixRun` interrupted, never resumes it, and closes its row with `FinishExecution` `interrupted`.
  - On every `Tick`, `Checks` calls `Fix.Run.Sweep()` beside its existing quiet sweep and sends each final `FixResult` to `IncidentManager`: exactly one per run, never a second.
  - Sweep's still-running branch is Story 30.5's.
- **Audit.** Write only through `OcuTalon.Bridge.Audit.Record("Action", data)`, with exactly `irisUser`, `sessionRef`, `channel`, `action`, `target`, `result`, `counts` and `approvalRef`. Tests read entries by `UTCTimeStamp` range, polling with a timeout, because the indexes lag up to 60 s.
- **Tests and the mock.**
  - Tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`, run on throwaways.
  - The mock logs every request to `/opt/ocutalon/mock-log/requests.jsonl`, the evidence for "no model request".
  - To get failed orders without Break the feed, call `Partner.Send(count, dateFormat, traceRef, orderDate)` in OCUORDERS. UJ-1's live case is 50 `MM/DD/YYYY` orders with the mock's existing `diagnosis` scenario.
  - Times convert only through `OcuTalon.Data.Time` (`Bridge.Time` in the bridge).

## UX & Interaction Patterns

- **Voice.** Numbers first, then the cause, then the choice. "Nothing was changed." ends every rejection, expiry and couldn't-start text. The phone and Telegram say "becomes", not arrows.
- **Texts the tests assert (UJ-1 fixture).**
  - Dry run: "Dry run: 50 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet."
  - Later request: "3 more orders failed since 14:20 ET, with the same cause. I can repair and resend all 3. Approve?", then its own dry run, then "Details and trace: on your OcuTalon page."
  - Approved: "Approved from {channel} at {time}".
  - Results: "All 50 orders went through."; the failed-again and skipped partials ("48 of 50 … I won't retry them without a new approval.", "47 of 50 … they need a new approval."); and "Nothing was resent: {reason}. Nothing was changed." (fixture reason: "OcuTalon isn't allowed to resend messages in that production").
  - Restart: "The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval."
  - The catalog also has count-of-one forms.
- **On the page (Epic 6's, built).** Each request card shows its own answered status and result band, followed by "Recorded in the IRIS audit log." The page renders results from the payload's `Requests[].State` and `Result`.

## Cross-Story Dependencies

- **Story order.** 7.6 → 7.3 → 7.4 → 7.5. Until 7.3, `FixExecutor` keeps `STUB = 1` and answers only `DryRun` (every other request gets error 5003). So 7.6 checks approvals and `Execute` through `IncidentManager`'s seams (`Test.Watch.IncidentProbe`).
- **Built by 7.1.**
  - `Fix.Kind` and `Fix.Kind.RepairResend`: parameters `field,sourceFormat,targetFormat`, `RESOURCES` `%Ens_MessageResend:U`, `FieldWords`, and a read-only `DryRun` through `Watch.Reader`.
  - Targets are plain header ids, ascending. The base `Recheck`/`Execute` return NotImplemented; they are 7.3's.
  - `Fix.Reformat`; `Install.Step.Fix.Grants()` (where 7.5's `Reconcile()` belongs); `Bridge.ReplyCheck`.
  - Test helpers: `Test.Fix.Snapshot` (`Take`, `Diff`) for "nothing changed", and `Test.Watch.Case`'s fixtures.
- **Built by 7.2.**
  - `IncidentManager.Propose`/`Proposed`/`NoFix`. The asynchronous dry-run ask uses key `dryrun` in the incident's trace session. `Raise` runs at `$TLevel` 0. A save that fails after `Raise` cancels the request.
  - The seams `SendDryRun`, `RaiseRequest`, `CancelRequest` and `AnswerNotice`, plus `Notice.WithFixSlots`.
  - The new `Ref` is appended to `Incident.RequestRefs`. A rejected or expired outcome sends `answered` in the session where the outcome arrives.
  - The with-fix notice's `count` is `NoticeCount`, and its `resendCount` is the dry run's `resend`.
- **What 7.6 must design** (from 7.2's notes):
  - Today a settle waiter starts only for a new incident, and `Waiting` stops once `NoticeCount` is set.
  - `RepairResend.DryRun` reads all of the group's `Seen`, so a later dry run must leave out the earlier requests' `FixTargets`.
  - Recording when the later failures began, and which keys each request covered, needs new stored state on `Incident` or `FailureGroup`. That is a schema veto.
  - It reuses `Propose`/`Proposed`, with `incident.laterRequest` and kind `approval`.
- **Built by Epic 6 (merged):** the incident and approval cards, the result band, `AnswerOps`, and the simulated phone's in-place edit by `ApprovalRef`. Epic 6's `Test.Demo.IncidentManagerDouble` does not extend `IncidentManager`.
- **Open ledger items.**
  - Story 7.4:
    - DW-272: store the final `FixResult` counts so each request in the payload carries its `Result`.
    - DW-318: the dry run reads only `Seen`, capped at the newest 1000 keys by `Settle.SEENMAX`. Past 1000 failures, `affected` and `resend` fall below `Count` with nothing saying so. Make the count honest and pin it.
    - DW-292: `FromRow` fills `groups`, `requests`, `evidence` and `traceTargets` for `/state`.
  - Story 7.3: DW-347 reopens unless 7.3's verification includes a mutation that turns `Test.Fix.Raise`'s "OCUORDERS did not change" check red.
  - DW-345 (terminal): Sweep covers `FixRun`s only, not a lost dry-run answer.
  - DW-328 is on the owner's decision sheet: Fix's references to `Watch.Reader`, `FailurePoller.Scope`, `ItemNoun` and `Transitions` stay as they are.
- **Contended paths now** (ask the orchestrator before editing):
  - Epic 9 (live): `Eval/**`, `Test/Eval/**`, `eval/**`, `.github/workflows/lane-a.yml`.
  - Epic 8 (live): `Schedule/**`, `Core/Commands*.cls`, `Data/{StatusMark,Time,Reminder}.cls`, `Test/Live/**` beyond the shared `Test/Live/Payloads.cls` entries (so new DW-272 and DW-292 tests of `FromRow` go in `Test/Watch/**`, or as entries in `Payloads.cls`), `ci/iris.sh`.
  - Waiting:
    - Epic 15: every `Install/**` file other than `Install/Step/Fix.cls`.
    - Epic 13: `src/bridge/cls/OcuTalon/BridgeExample/**`, and its own `ci/mock/scenarios/A/bridge-example-*.json` files (a NEW scenario file of Epic 7's under `ci/mock/scenarios/A/` is no collision; the existing `diagnosis` scenario serves 7.4).
    - Epic 10: `ci/mock/**`, `docker/**`, `Core/AnswersIn*`.
    - Epic 16: `Core/BridgeSink*`, `Test/{Web,Data}/**`. In `Test/Data/Tables.cls`, edit only Lane A's own entry, as 7.2 did.
  - Lane A's own and not contended: `Fix/**`, `Test/Fix/**`, `src/bridge/**`, `Watch/**`, `Checks/**`, `Tools/**`, `Msg/Catalog/Watch.cls`, `Test/{Watch,Bridge}/**`, `Install/Step/Fix.cls`, Lane A's Data tables (`Incident`, `FailureGroup`, `FixRun`, `Bridge.Data.*`), and the lane-a entry in `ci/units.sh`.
- **Later epics.**
  - Epic 30's Story 30.5 adds the still-running and mixed results.
  - Epic 11 turns the demo path's incident, approval and result steps on end to end; until then Epic 6 runs them on fixtures.
  - Epic 14 lists `RESOURCES`.
  - Epic 9's Story 9.5, Epic 12's Story 12.6 and Epic 29's Story 29.4 wait for Epic 7 to merge.
