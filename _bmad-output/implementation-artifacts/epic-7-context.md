# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. When a diagnosis finds a data-format cause, OcuTalon proposes repair and resend and works out a dry run that changes nothing. It raises one approval request whose targets are fixed, and it carries that request on the incident notice. After approval it re-checks each target, resends repaired copies, leaves the originals untouched, and reports how many went through ("All 50 orders went through."). It works for at least 500 messages. It never retries a failed resend, or acts on a changed target, without a new approval, and a resend cut short by a restart says how far it got. This turns Epic 5's diagnosed incident into an approved fix you can audit, and it moves the incident through awaiting approval, fixing and resolved.

## Stories

- Story 7.1: Repair and resend proposes a dry run that changes nothing
- Story 7.2: The incident notice carries the dry run and one approval request
- Story 7.3: Approved repairs are re-checked and resent
- Story 7.4: OcuTalon reports how many orders went through
- Story 7.5: A resend cut short by a restart says how far it got

## Requirements & Constraints

- **A repair is narrow.** It reformats one field with a reformatter registered in code: a date pattern or a number format from a fixed set. The model picks only the kind and its parameters (the field, the source format, the target format). No model-written code runs. A reformatter refuses any value that doesn't match its source format and never evaluates its input.
- **The dry run changes nothing.** It reports the affected count, one before-and-after example, what will be resent, and how many messages it left out because their field couldn't be read. A test snapshots the message headers and bodies, the production and item settings, and the queues in OCUTALON and OCUORDERS, and finds no change. The CI mock receives no request during the dry run, nor during an execution.
- **Targets are fixed when the request is raised.** Carrying out the request calls no model. Before acting, each target is re-checked: still failed, not resent, body unchanged, still in the request's scope. A target that changed is skipped with a plain reason and never acted on without a new approval.
- **The originals stay unchanged.** Each copy stays in its original's trace session, with the same `SuperSession`.
- **A copy that fails again** is reported and never retried without a new approval. Its failure counts against the fix: it never opens a new failure group or incident.
- **One `result` notification per run**, so every channel gets the same result at once. The resend writes one OcuTalon `Action` audit entry beside IRIS's own resend entries. It holds no key, token, password or Telegram identity.
- **Scale.** One request covers at least 500 messages. The test runs at exactly 500: 500 counted, 500 targets, 500 resent and 500 completed.
- **Rejection, expiry and cancellation.** On a rejection or an expiry, no `Execute` is sent and nothing in the watched production changes. A cancellation sends no outcome, and the incident stays as it is.
- **A fallback diagnosis, or a cause that isn't a data-format change,** gets no dry run and no request. Epic 5's fallback and no-fix notices stay as they are.
- **Same-cause failures that arrive after the notice** are never added to an existing request's targets. If the incident is awaiting approval, fixing or resolved, they settle by the same rule and then get their own dry run, request and notice. An Open incident only updates its count.
- **Approval before risk** holds in every configuration. The production's testing switch stays off. Each fix kind has a test that sends `Execute` without an approved row and expects nothing to happen.

## Technical Decisions

- **The answer path, as built (owner decision U-113).** On this branch, AD-11, AD-31 and AD-32 still describe the old answer path; Epic 6 amends them under U-120. As built, `AnswersIn` checks the session and who may answer. It then sends the answer synchronously to `AnswerOps`, whose production job calls `OcuTalon.Bridge.Approval.Answer`. From `Approval.Answer` onward nothing changed: `ApprovalHold` → `IncidentManager` → `FixExecutor` → `IncidentManager` → `Notify`. Epic 7 builds from `Approval.Answer` onward and never depends on how an answer reaches it. Tests answer by calling `Approval.Answer` directly.
- **Footprint.** `src/ocutalon/cls/OcuTalon/Fix/**`, `src/ocutalon/cls/OcuTalon/Test/Fix/**`, `src/bridge/**` (except `src/bridge/cls/OcuTalon/BridgeExample/**`, which is Epic 13's), `ci/mock/scenarios/A/**`, the merged Lane A areas `Watch/**`, `Checks/**` and `Tools/**`, and `Live/Payload/Incident.cls`. The web incident and approval cards and the web and phone answer path belong to Epic 6.
- **Fix kinds.** `OcuTalon.Fix.Kind` is the contract: `DryRun`, `Recheck` and `Execute` against fixed targets, a parameter schema, and a `RESOURCES` parameter. `RepairResend` declares `%Ens_MessageResend`. `RESOURCES` uses the tool form `resource:permission[,...]`. The service user's grants (`OcuTalonService` / `OcuTalonServiceRole`) and the security overview's privilege list are generated from it. The permission check uses `$SYSTEM.Security.CheckUserPermission` with one permission letter per call, because multi-letter checks proved unreliable on build 154. No role ever holds `%Ens_MessageEditResend`. The kind's parameter check runs inside the bridge's validation of `OcuTalon.Watch.Msg.DiagnosisPayload` (Watch may reference `Fix.Kind`). A reply that fails the check is `invalid` and takes Epic 5's fallback route.
- **Dependency rules.** Production components talk only through messages addressed by item name. `Execute` and `FixResult` are fixed: they get no new properties. So the dry-run ask from `IncidentManager` to `FixExecutor` needs its own area-internal message under `OcuTalon.Fix.Msg`. The bridge never references OcuTalon packages (a CI check), so the kind is stored on bridge rows as a string. `Checks` may call `OcuTalon.Fix.Run.Sweep()`.
- **The dry run.** It reads the group's failed messages through `OcuTalon.Watch.Reader` in the production's own namespace. Its targets are only the messages in the incident's scope: the session whose `TraceRef` is their `SuperSession`, or `instance`. It returns the target header ids and the stored `DryRun` JSON, with exactly the keys in `ApprovalRequest.DRYRUNKEYS`: `affected`, `resend`, `leftOut`, `field`, `before`, `after` and `itemNoun` (`{"one","other"}`).
- **Raising the request.** `IncidentManager` calls `Approval.Raise` once, with:
  - kind `fix` and the `IncidentRef`;
  - the targets and the exact change;
  - the `DryRun`;
  - the incident's `OwnerRef`;
  - `ResultTarget` `IncidentManager`;
  - the incident's trace session.

  `Raise` refuses to run inside an open transaction. It starts the hold synchronously, so OK means the request is held, and a failed `Raise` leaves nothing behind. `IncidentManager` then appends the new `Ref` to `Incident.RequestRefs`; it is the only writer of incident rows. For kind `fix`, the only contract column on the row is `DryRun`. Where the exact target header ids and the kind's parameters live is for the story to decide: appended bridge properties, since storage is append-only, or something else. `FixExecutor` must load the kind, targets and change from the row alone.
- **Approval row states.** `pending` moves to `approved`, `rejected`, `expired` or `cancelled`. `approved` moves to `executing`, then to `done` or `failed`, or straight to `failed` when a run can't start. `StartExecution` needs an approved row whose `ExpiresAt` is still ahead, and it fires no event. `FinishExecution(ref, done|failed|interrupted)` fires `approval.result`; an interrupted run leaves the row `failed`. Each change writes an `Approval` audit entry that names the approver for a run's start and end.
- **`IncidentManager` rules.**
  - It is the only writer of `Incident` and `FailureGroup` and the only publisher of `incident` events.
  - It moves the incident only by AD-15's transition table.
  - A request counts as pending while it is `pending`, or while it is `approved` and the incident is still `awaiting_approval`.
  - It refuses an `ApprovalOutcome` that the request's row doesn't show.
  - One fix runs at a time per incident. A `FixResult`'s own request never counts as waiting, and the earliest waiting request in `RequestRefs` order gets the next `Execute`.
  - It publishes only after commit, never inside a transaction, and each payload is the full current view.
  - `Live.Payload.Incident.FromRow` reads by object access only, never SQL (`/state` has no SQL grant). It opens each request by `Ref`. Each request's `Result` comes from the stored final counts (DW-272).
- **Notifications.**
  - Producers never render text; they send catalog keys and slots. The keys already exist: `incident.withFix`, `incident.laterRequest` and `result.*` in `OcuTalon.Msg.Catalog.Watch`, and the answered statuses in `Catalog.Core`.
  - Slots: times in UTC ISO 8601, counts as integers, `itemNoun` as `{one, other}`, and model-written slots as plain sentences without times.
  - The first request's `ApprovalRef` and the dry-run slots (`field`, `before`, `after`, `resend`) ride on the kind-`incident` notice. No separate `approval` notification goes out for the first request; kind `approval` is only for a later request.
  - `answered` and `result` notifications carry `ApprovalRef` and `IncidentRef`.
  - `IncidentManager` sends one notification per recipient from `Session.Recipients(ownerRef, incidentRef)`. It does this for an incident's fix requests; `BridgeSink` does not.
  - The with-fix notice goes through Epic 5's notice delivery and sets `NoticedAt` (DW-270).
- **`FixExecutor`.**
  - An `Execute` carries only `ApprovalRef`.
  - A refused `Execute` (pending, rejected, expired, cancelled, already executing or unknown) changes nothing and sends nothing.
  - When resources are missing, it sends a final `FixResult` with `Resent` 0 and a plain `Reason`, and closes the row with `FinishExecution` `failed`.
  - It resends from its one `New $NAMESPACE` method with `Ens.MessageHeader.ResendDuplicatedMessage(original, , target, newBody)`, building each body with the body class as resolved in that namespace.
  - It registers each new header id on the `FixRun` row and waits up to 60 s for each copy to complete or fail.
  - A stopped target production returns `ErrProductionNotRunning`, and that copy is reported as `Skipped` with a plain reason.
  - Measured on build 154 (no fallback needed): the copy runs in the target production, keeps the original's session and `SuperSession`, is marked `Resent`, and is audited by IRIS. 500 copies resend in under a second.
- **Recognising a copy that fails again.** `IncidentManager` already keys failures `h<HeaderId>` to skip ones it holds. It must also recognise a registered copy's header id and count its failure against the fix, not a failure group.
- **Restarts.** `OcuTalon.Install.Registry.CallAreas("Reconcile")` calls `Reconcile()` on every `OcuTalon.Install.Step.<Name>` class. The Fix area's `Reconcile()` marks running `FixRun`s interrupted and closes their rows through `FinishExecution` `interrupted`. On every `Tick`, `Checks` calls `Fix.Run.Sweep()` and sends each final `FixResult` to `IncidentManager`. Each run gets exactly one final result, and a run already reported never gets another. Sweep's still-running branch belongs to Story 30.5.
- **Audit.** Write through `OcuTalon.Bridge.Audit.Record("Action", data)` only. The members are exactly `irisUser`, `sessionRef`, `channel`, `action`, `target`, `result`, `counts` and `approvalRef`; `Record` refuses a missing or extra member. Tests read entries back by `UTCTimeStamp` range, polling with a timeout, because the audit indexes lag up to 60 s.
- **Tests and the mock.**
  - Tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`.
  - Lane A extends the mock only by adding scenario JSON files under `ci/mock/scenarios/A/`. New mock behaviour is Lane B's.
  - The mock logs every request to `/opt/ocutalon/mock-log/requests.jsonl`, which is the evidence for "no model request".
  - To get 50 failed orders without Break the feed, call `Partner.Send(count, dateFormat, traceRef, orderDate)` in OCUORDERS.
  - Times convert only through `OcuTalon.Data.Time`, or `Bridge.Time` inside the bridge.
  - Every persistent class commits its `Storage` block, and stored properties are append-only.

## UX & Interaction Patterns

- **Voice.** Numbers first, then the cause, then the choice. "Nothing was changed." appears in every rejection, expiry and couldn't-start text. The phone and Telegram say "becomes", not arrows.
- **Texts the tests assert** (UJ-1 fixture):
  - The dry-run paragraph: "Dry run: 50 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet."
  - A later request: "3 more orders failed since 14:20 ET, with the same cause. I can repair and resend all 3. Approve?", then its own dry run, then "Details and trace: on your OcuTalon page."
  - The results: "All 50 orders went through.", the failed-again and skipped partials, and "Nothing was resent: {reason}. Nothing was changed." (fixture reason "OcuTalon isn't allowed to resend messages in that production").
  - A restart: "The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval."
  - The catalog also has count-of-one forms.
- **On the page.** Each approval request card shows its own answered status ("Approved from {channel} at {time}") and its own result band, followed by "Recorded in the IRIS audit log." Those are Epic 6's. The demo guide's finish needs an approved fix and a resolved incident.

## Cross-Story Dependencies

- **Story order.** 7.1 (the kind and the dry run) → 7.2 (Raise, the notice, the outcomes, later requests) → 7.3 (`Execute`, re-check, resend) → 7.4 (results, audit, the 500-message test) → 7.5 (Reconcile and Sweep).
- **Already built by earlier epics.**
  - The `Approval` API: `Raise`, `Answer`, `StartExecution` and `FinishExecution`.
  - `ApprovalHold` sending `ApprovalOutcome`.
  - `Fix.Msg.Execute` and `FixResult`, and `IncidentManager`'s transition table (Story 5.5).
  - `Incident.RequestRefs`.
  - The catalog keys.
  - Story 5.8 leaves the usable data-format diagnosis stored but unnoticed, for 7.2 to notice.

  Still to build: `Fix.Executor` is a stub, and `Data.FixRun` holds only `ApprovalRef`, `IncidentRef` and `StartedAt`.
- **Needed files outside the footprint.** These go to the orchestrator as contended paths before anyone edits them:
  - Lane A tables under `Data/`: `Incident`, `FailureGroup`, and `FixRun`, which needs appended properties for the registered copies, the run state and the stored result.
  - An `Install/Step/<Area>` class for the fix kinds' `Grants()` and the Fix area's `Reconcile()`. The `Tools` step composes only the toolsets in `OcuTalon.Tools`.
  - Any change to `Msg/Catalog/Watch.cls`.
- **Epic 6 (live, Lane B)** renders the incident and approval cards and the results, and owns the answer path. Its AD-11/31/32 amendments don't change anything from `Approval.Answer` onward.
- **Later epics.**
  - Epic 30's Story 30.5 adds the mixed and still-running results on top of 7.4 and 7.5.
  - Epic 11 turns the demo path's incident, approval and result steps on end to end; until then they run on fixtures.
  - Epic 14's security overview lists the privileges declared in `RESOURCES`.
