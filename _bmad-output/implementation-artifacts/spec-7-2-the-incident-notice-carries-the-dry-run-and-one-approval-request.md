---
title: 'The incident notice carries the dry run and one approval request'
type: 'feature'
created: '2026-10-27'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Since Story 5.8, a usable data-format diagnosis (fix kind `repair_resend`, parameters checked by 7.1's kind) is stored and never noticed. Story 7.1 built the dry run that `FixExecutor` answers, but nothing asks for it. Nothing raises the approval request, sends the with-fix notice, or turns a rejection or an expiry into an answered status. So UJ-1 stops at the diagnosis.

**Approach:** At the notice step, `IncidentManager` asks `FixExecutor` for the dry run with `Fix.Msg.DryRun`. When the answer comes back, it calls `OcuTalon.Bridge.Approval.Raise` once. The row holds the fixed targets, the kind and its validated parameters, the `DryRun` JSON, the owner, `ResultTarget` and the incident's trace session. `IncidentManager` then appends the Ref to `Incident.RequestRefs` and moves the incident to `awaiting_approval`. It sends one kind-`incident` `incident.withFix` notification per recipient, carrying the `ApprovalRef` and the dry-run slots. A rejected or expired outcome moves the incident through AD-15's table and sends an `answered` notification. To hold the fix's kind, parameters and targets, the bridge's `ApprovalRequest` row gains three stored properties (V1). **Scope note:** this spec covers the proposed cut of the story. Its fifth group of criteria (later requests in the same incident) goes to a sibling story (see `## Auto Run Result`).

## Boundaries & Constraints

**Always:**
- `IncidentManager` is the only writer of `Incident` and `FailureGroup` and the only publisher of `incident` events. It moves an incident only through `OcuTalon.Watch.Transitions.Next` and publishes only after its save (AD-12, AD-15, AD-33).
- The dry run is asked asynchronously:
  - from the waiter (the `Settle` instance), in the incident's trace session, with a response required and its own completion key;
  - the waiter's persisted instance is the state (AD-5).
- The kind and the parameters come from the checked diagnosis payload. They travel in the `Fix.Msg.DryRun` ask and are read back from that ask when the answer arrives. No `Incident` column holds them.
- One `Raise` per with-fix notice:
  - Kind `fix`, the incident's `IncidentRef` and `OwnerRef`, and `ResultTarget` `IncidentManager`.
  - `TraceRef` is the waiter's `SuperSession` when that is a 22-character Ref, else empty (an `instance` incident).
  - `DryRun` is the `DryRunResult`'s JSON as given. `FixKind` and `FixParameters` (a JSON object) come from the ask. `FixTargets` is the result's `Targets` as given: header ids, ascending, comma-separated.
  - The incident's `TraceHeaderId` and the waiter's `SuperSession` are passed as `Raise`'s `sessionId` and `superSession`, so the hold joins the incident's trace session (AD-11, AD-26).
  - `Raise` runs with `$TLevel` 0, after the table has accepted `raised` and the slots are built.
- The with-fix notice:
  - It uses `OcuTalon.Watch.Notice`'s with-fix slots: `count` (`NoticeCount`), `time` (`FirstAt`, UTC ISO 8601), `itemNoun` `{one, other}`, `cause`, `fixSummary`.
  - It adds the dry run's `field`, `before`, `after`, and `resendCount` (the dry run's `resend`, an integer).
  - It is sent through Epic 5's `Deliver`: `NoticedAt`, the state `awaiting_approval` and `RequestRefs` are saved in one save, then one copy goes to each `Session.Recipients` session, each followed by the `incident` event.
  - It carries the `ApprovalRef`. No notification of kind `approval` is sent for the first request (AD-15, AD-32).
- An `answered` notification goes out for a rejected or an expired outcome that the table accepts:
  - `answered.rejected` with `{channel: AnsweredChannel, time: AnsweredAt}`, or `answered.expired` with `{time: ExpiresAt}`;
  - it carries `ApprovalRef` and `IncidentRef`;
  - one copy per recipient, through the same `Move`/`Tell` as the `incident` event.
- The bridge names no OcuTalon package outside `OcuTalon.Bridge`, so `FixKind` is a plain string and `Raise` never validates it against `Fix.Kind` (AD-2). Stored properties are append-only, and the `Storage` blocks are committed.
- Producers never render text (AD-32). Warnings go through `Bridge.Redact.Text`. Rule 14 applies: ASCII escapes, and comments that state the contract.
- Tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`. Tests that drive the running production run only on throwaway stacks, never on `ocutalon-slot-a`.

**Never:**
- No later-request flow (the proposed sibling story):
  - same-cause failures after the notice keep today's behaviour: the count is updated and an `incident` event published;
  - no `approval`-kind notification and no `incident.laterRequest`;
  - no change to `RepairResend.DryRun`'s choice of keys;
  - no new `FixRun`.
- Nothing that belongs to a later story:
  - Story 7.3: no `Execute`/`Recheck` work, no change to `Fix/Executor.cls`, and no `answered.approved` notification;
  - Story 7.4: no `result` notification and no stored counts (DW-272);
  - Story 7.5: no `Reconcile`/`Sweep`.
- No edit to `Core/BridgeSink.cls` or `Test/Demo/IncidentManagerDouble.cls` (Epic 6, contended), `Live/Payload/*`, `Msg/Catalog/*.cls`, `Watch/Transitions.cls`, `Fix/Kind/**` or `Fix/Msg/**`.
- No mock scenario: the existing `diagnosis` scenario serves.
- No stored property other than V1's three. No edit to any AD.
- No `[Language = python]`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| With fix (UJ-1; DW-270, DW-271) | The case `eval/orders-date-format` records: 50 orders `MM/DD/YYYY` through `Partner.Send` with session S's TraceRef, S watching Orders, the mock's `diagnosis` scenario. | One `Fix.Msg.DryRun` to `FixExecutor`, in the incident's trace session.<br>One `ApprovalRequest`: `fix`, the IncidentRef, owner S, `pending`, `ResultTarget` `IncidentManager`, `TraceRef` S's, `FixKind` `repair_resend`, `FixParameters` `{"field":"OrderDate","sourceFormat":"MM/DD/YYYY","targetFormat":"YYYY-MM-DD"}`, `FixTargets` the 50 ids ascending, `DryRun` `{50, 50, 0, "order date", "10/16/2026", "2026-10-16", {order, orders}}`. Its live hold is in the incident's trace session.<br>The incident row: `awaiting_approval`, no variant, `NoticedAt` set, `RequestRefs` the Ref.<br>One Notification for S: `incident`, `incident.withFix`, `ApprovalRef` the Ref, `DecisionRef` the row's, slots `count 50`, `time` = `FirstAt` (the first failure's), the noun, `cause`, `fixSummary`, `field "order date"`, `before "10/16/2026"`, `after "2026-10-16"`, `resendCount 50`. No Notification of kind `approval`.<br>S's stream for the incident, in Seq order: `noticed`, `settling`, `diagnosing`, then `incident` with `requests` `[{ref, "pending"}]`.<br>The mock logged only the diagnosis's 2 requests. | none |
| No fix (Epic 5) | fallback (any reason), `unknown`, or a category with no fix | Epic 5's notice and variant, unchanged. No `DryRun` header, no `ApprovalRequest` naming the incident, `RequestRefs` empty, `ApprovalRef` "". | Epic 5's route |
| Dry run refused (V2) | `DryRunResult.Reason` set, for example the failed orders are of another scope | `incident.noFix`, `open` `no_fix`, to each recipient. No request. One Type 3 warning naming the incident and the redacted reason. | the no-fix route |
| Nothing to resend (V2) | `Reason` "" and `Targets` "" (nothing reads in the source format) | as above, with no warning | the no-fix route |
| Raise fails (V2) | `Raise` returns an error (for example the `ApprovalRole` setting is empty) | No row, hold or event (Raise's contract). The no-fix notice and one Type 3 warning. | the no-fix route |
| Ask not sent (V2) | the send of the `DryRun` fails, `OnError` arrives for its key, or the payload has no fix kind | the no-fix notice and one Type 3 warning | the no-fix route |
| Save fails after Raise | `Deliver`'s save of the incident fails | `Approval.Cancel(ref, , "system")`, so nothing stays approvable. One Type 3 warning. The incident stays unnoticed and nothing is sent. | logged |
| Slots can't be built | the with-fix slots fail (no cause, no fix summary, a dry run without `field`/`before`/`after` or with `resend` < 1) | nothing is raised, one Type 3 warning, the row stays unnoticed (as in 5.8) | logged |
| Gone first | the incident is closed, noticed or deleted while the `DryRun` is on its way | nothing raised, sent or saved, and no error | dropped |
| Instance, watchers (local install) | untagged failures of Orders, sessions A and B watch Orders, C does not | Exactly one request names the incident (owner `instance`, `TraceRef` ""). A and B each get one with-fix Notification carrying its Ref; C gets none. | none |
| Rejected | `Approval.Answer(ref, "reject", "web", <answerer>, S)`; no other request pending, no fix running | The hold's outcome moves the incident to `open` `rejected`.<br>One `answered` Notification per recipient: `answered.rejected` `{channel "web", time AnsweredAt}`, `ApprovalRef`, `IncidentRef`, in the incident's trace session.<br>The `incident` event lists `[{ref, "rejected"}]`. No `Execute` header. An OCUORDERS snapshot shows no change. | none |
| Expired | the hold's timer fires (the test's fixture: `Age`, then a re-armed hold) | `open` `expired`, `answered.expired` `{time ExpiresAt}`, the same negatives | none |
| Rejected or expired while another is pending, or while fixing | fixture rows (probe) | The state stays `awaiting_approval` or `fixing`, and the `answered` notification still goes out. | none |
| Cancelled | `Approval.Cancel(ref)` | No `ApprovalOutcome` reaches `IncidentManager`. The incident stays `awaiting_approval`, `NoticedAt` is unchanged, no new Notification. | none |
| Refused outcome | a repeat, another incident's request, an outcome the row does not show | nothing sent (5.5's `Drop`) | Type 4 line |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`, `ci/` or `eval/`. Line numbers are as of `e15bf0f`.

**`Watch/IncidentManager.cls`**, the class this story changes most:
- `OnResponse` L152 handles only the `Settle` request (the diagnose key, else the alarm). `OnError` L164 handles the diagnose key only.
- `Answered` L406 parses the payload at L417; `fixKind` and `fixParameters` are there and are not stored. It calls `Notice(ref)` at L437.
- `Notice` L466 quits at L472 when `Notice.Key` is "", which is the with-fix case.
- `Deliver` L489 already takes `approvalRef`; it returns nothing today. `Move` L508 saves when the row is modified, then calls `Tell` with the notification.
- `Apply` L528, `Facts` L544 and `Owns` L565 read `RequestRefs` (5.5). `Outcome` L649 (approved, rejected or expired, as the row shows it), `Event` L673, `Drop` L683.
- The seams `SendExecute` L595 and `SendNotice` L740. `Open` L746. `Tell` L762 sends one copy per recipient, then publishes.
- The class doc's notice and states bullets are at L34-50.

**`Watch/Notice.cls`:** `Key` L46 (`data_format_change` gives "" at L50), `Variant` L55, `Slots` L64 (refuses when `Key` is ""), `WithFixSlots` L91 (5.8 built it for this story) and `Common` L107.

**`Watch/Transitions.cls`:** L94 (`open`, not noticed, + `raised` gives `awaiting_approval`), L108-114 (rejected or expired gives `open` with the variant unless `pending`), L119 (`fixing` stays). Pure; no change.

**`src/bridge/cls/OcuTalon/Bridge/Approval.cls`:**
- `Raise` L72 refuses at `$TLevel` > 0 (L75). Its `sessionId` and `superSession` are optional arguments.
- `Validate` L169: the `tool_call` branch L183-186, the `fix` branch L187-192, the owned fields L197.
- `IsRef` L213 is public. `Answer` L247, `Cancel` L348.
- `HoldResponse` L584 sends no outcome for a cancelled task (L599-607). `Reconcile` L645 re-arms holds from `ExpiresAt`.
- Its comment says IncidentManager is a caller of `StartHold` (L130).

**`src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls`:** the properties L12-66 and `Storage` L76-137; Value 20 is `FinishedAt`.

**The Fix area (7.1's):** `Fix/Executor.cls` `DryRun` always answers OK; a refusal leaves `Targets` and `DryRun` empty and puts a plain sentence in `Reason`. `Fix/Msg/DryRun.cls` holds `IncidentRef`, `FixKind` and `Parameters`; `Fix/Msg/DryRunResult.cls` holds `IncidentRef`, `Targets`, `DryRun` and `Reason`.

**Read only, unchanged:**
- `Live/Payload/Incident.cls` `Details` L119-128 already lists `requests` `{ref, state}` from `RequestRefs`, by object access (DW-271's reader).
- `Core/BridgeSink.cls` L69-89 publishes only `approval` live events, no Notification.
- `Data/Ownership.cls` L54 `APPROVALVISIBLE`: a session-owned request is visible to its owner at once; an `instance` request only once the incident's `NoticedAt` is set.

**Catalog, notifications and delivery:**
- The catalog keys: `Msg/Catalog/Watch.cls` L78 `incident.withFix` (its dry-run paragraph renders `{count}` for "affected"); `Msg/Catalog/Core.cls` L99 `answered.rejected` and L116 `answered.expired`.
- `Msg/Catalog.cls` `CHANNELNAMES` L41 (`web`, `phone`, `telegram`) and `Render`/`RenderAt`.
- `Msg/Notification.cls` holds the fields.
- `Channel/WebChat/Out.cls` L48 records a non-card kind as a `Delivery` row with its kind and `ApprovalRef` (the Integration consumer).

**The recorded case and the mock:** `eval/orders-date-format/case.json` (50 orders, `MM/DD/YYYY`; `snapshot.json` is the recorded pack) and `ci/mock/scenarios/A/diagnosis.json` (mock key `diagnosis`, `repair_resend`). IncidentManager builds packs only from live incidents (`EvidencePack.Build` L84), and a dry run needs the live failed messages.

**Test helpers:**
- `Test/Watch/Case.cls`:
  - set-up: `Session` (via `Test/Core/InProduction.cls` L100), `SetOnlineDemo` L226 (restored by `PutBack`), `PointKeys` L388, `Watch` L459, `Fail` L545, `WaitFailed` L578, `HeaderIds` L591, `Fixture` L603, `SampleOrder` L639, `ClearMark` L866;
  - batches and waits: `SendBatch` L1038 (use the real item `OrdersFromPartner` with real header ids), `WaitIncident` L1108, `WaitRow` L1136, `WaitDiagnosed` L1152, `WaitAnswered` L1221;
  - notifications: `NoticeBodies` L1184, `Notifications` L1199, `WaitNotices` L1208;
  - clean-up: `OnAfterOneTest` L164, `DropIncidentRows` L1255. Today they leave approval rows, holds and tasks.
- `Test/Core/Observe.cls`: `Events` L46, `LastLog` L80, `Warnings` L88, `DeliveryRows` L16.
- `Test/Data/Fixture.cls`: `SessionHeaders` L433, `Between` L450, `Approval` L102 (a row saved directly, with a fields argument).
- `Test/Agent/RunnerFixture.cls`: `DefaultId` L663, `RememberDefault` L715, `RestoreDefaults` L727.
- `Test/Contract/Mock.cls`: `LogMark` L365, `LogSince` L378.
- `Test/Fix/Snapshot.cls`: `Take` L22, `Diff` L131.
- `Test/Bridge/Approval.cls`:
  - helpers: `ANSWERER` "ocutalon" L93, `NewRow` L1552, `Refusals` L1578, `WaitTask` L1724, `Age` L1864, `Clean` L1984 (public; `Remove`s each tracked Ref), `TrackOwner` L2036;
  - `TestTimerExpires` L1013 shows the expiry recipe (`Age(ref, 86460, -60)`, delete the live hold, then `Reconcile`), and `TestCancel` L1104 shows that a cancel sends no outcome;
  - `Outcomes` L2229 is an instance method, so another class writes its own query.
- `Test/Watch/IncidentProbe.cls`: `Sent` L14, `Executed` L20, and overrides of `Move` L36, `SendExecute` L47 and `SendNotice` L70. Its `Answer` calls `OnResponse` with the diagnose key. A shadow instance cannot `SendRequestAsync`, and `Raise` would really run, so every new send needs a seam.
- `Test/Watch/Tell.cls`: `TestNoticeToEachRecipient` L125, `Diagnosis` L280, `Setup` L291 (two watchers of an `instance` ZZNS incident). Probe tests, run warm.
- `Test/Watch/Lifecycle.cls`: `TestApprovalOutcomes` L246, `Request` L842 (via `Fixture.Approval`), `Link` L850.
- `Test/Watch/NoticeText.cls`: `Render` L107 and `TestWithFix` L172 (the UJ-1 text from fixture slots).
- `Test/Watch/Notices.cls`: `TestNoticeVariants` L30 (its Notification lookup L95-100, its order check L113-122) and `TestInstanceNotice` L177.
- `Test/Watch/Closing.cls` `HeldRequest` L176 builds a fix row at L203-209 and sets the `ApprovalRole` default aside at L189-190.

**Tests whose expectations this story changes (shared surface; verified by reading):**
- `Test/Watch/Diagnose.cls` `TestDemoDiagnosis` L45: the negatives at L79, L84 and L85 ("not noticed").
- `Test/Watch/Incidents.cls`:
  - `TestBurstThroughThePoller` L67: L87 (`open`), L102, L119-121;
  - `TestTwoSessions`: L271-283 (no event before the notice, then the fixture `Notice`);
  - `TestInstanceShared`: L313, L322-323 (the fixture `Notice`), L330-341;
  - the class doc L8-11 and L21-26.
- `Test/Fix/DryRun.cls` `TestInvalidRepairTakesTheFallbackRoute` L454: L483-487 ("stored with no notice").
- `Test/Bridge/Approval.cls`: `NewRow("fix")` (every fix `Raise`) and `Refusals`.
- `Test/Watch/Closing.cls` `HeldRequest`: a fix row with none of the three fields.
- `Test/Data/Tables.cls` L179-205: `ApprovalRequest`'s exact contract (an entry shared by entry; the entry is Lane A's).
- Probably unaffected (inference from reading), but run: `Test.Checks.Turns.TestFailingOrdersInTheChat` (it now raises a request; its assertions filter by turn), `Test.Watch.Closing`, `Test.Watch.Notices`, `Test.Demo.Production` (lane-b) and `Test.Agent.Decide`. The browser demo path stays a fallback (no model key).

## Tasks & Acceptance

**Execution:**
- Task 0 (measure on the stage's first fresh throwaway; record the results in `## Verification`):
  - (a) The first fresh run of `OcuTalon.Test.Watch.Diagnose` after the IncidentManager change shows that `Raise` from IncidentManager's job works: OK, a live hold, and the hold's start header in the incident's `TraceHeaderId` session. Expected (inference): Ens commits no framework transaction around `OnResponse` (`irislib/Ens/BusinessProcess.cls` L439 only warns about a user's open one), and `StartHold` runs from a production job, as the gate's does.
  - (b) The seconds from the `diagnosing` event to the with-fix Notification for 50 orders. Expected (inference): under 3.
  - (c) The `diagnosis-late` window (6 s) is long enough for `Incidents`' negatives.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` (V1):
  - Append `FixKind` (`%String(MAXLEN = 32)`: the fix kind's name), `FixParameters` (`MAXLEN ""`: the kind's validated parameters as one JSON object, the exact change) and `FixTargets` (`MAXLEN ""`: the fixed targets as the dry run gave them).
  - Append Storage `Value` 21, 22 and 23 in that order. The doc names no OcuTalon package.
  - Why: AD-11 (fixed targets, exact change) and AD-16 (the executor loads all three from the row alone, Story 7.3).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - In `Validate`, after the existing checks of each branch (so every earlier refusal keeps naming its own field): a `tool_call` refuses a non-empty `FixKind`, `FixParameters` or `FixTargets`; a `fix` refuses an empty `FixKind`, a `FixParameters` that is not a JSON object (`IsJsonObject`) and an empty `FixTargets`. Each refusal names the field.
  - Update `Raise`'s doc step 1.
  - Why: AD-11, AD-16.
- `Watch/Notice.cls`:
  - `WithFixSlots(incident, Output sc, dryRun As %DynamicObject = "")`: given a dry run, it adds `field`, `before`, `after` and `resendCount` (`+dryRun.resend`). It refuses (in `sc`) a dry run missing any of the three texts, or with `resend` below 1.
  - `Slots(incident, groups, Output sc, key As %String = "")`: a given key replaces `Key(incident)`, so the no-fix route of a data-format incident uses `KEYNOFIX`.
  - Update the class doc.
  - Why: AC 3, V2. Rule 2: extends 5.8's builders.
- `Watch/IncidentManager.cls`:
  - Parameters: `DRYRUNKEY` ("dryrun"), `RESULTTARGET` ("IncidentManager"), `ANSWEREDKIND` ("answered"), `KEYREJECTED` ("answered.rejected"), `KEYEXPIRED` ("answered.expired"), `LOGPROPOSE` ("IncidentManager could not propose the fix of incident ").
  - `Answered` passes the usable payload's `{fixKind, fixParameters}` to `Notice`. `Notice(ref, fix As %DynamicObject = "")`: when `Notice.Key` is "", it calls `Propose`.
  - `Propose(incident, fix)`: with a fix kind, it sends one `Fix.Msg.DryRun` (`IncidentRef`, `FixKind`, `Parameters` = `fixParameters` as JSON) through the new seam `SendDryRun` (`SendRequestAsync(FIXEXECUTOR, ask, 1, DRYRUNKEY)`). A failed send, or no fix kind, takes `NoFix` with one Type 3 warning.
  - `OnResponse` with `DRYRUNKEY` and a `DryRunResult` calls `Proposed(request.IncidentRef, callrequest, callresponse)`. `OnError` with `DRYRUNKEY` calls `NoFix` with one Type 3 warning and returns OK.
  - `Proposed(ref, ask, result)`, in this order:
    1. it acts only when `Open(incident)`;
    2. a `Reason` takes `NoFix` with a warning; an empty `Targets` takes `NoFix` with no warning;
    3. `Transitions.Next(state, 0, "raised", , .to, .variant)`; a refusal raises nothing;
    4. it builds the slots with `WithFixSlots(incident, .sc, dryRun)`; a failure is a warning and nothing more;
    5. it builds the row (Always), then calls `RaiseRequest(row, .ref, incident.TraceHeaderId, ..%SuperSession)`, a seam over `Approval.Raise`; an error is a warning plus `NoFix`;
    6. on OK, it appends the Ref to `RequestRefs` (comma-separated, in raised order; DW-271) and calls `Deliver(incident, to, variant, Notice.#KEYWITHFIX, slots, ref)`;
    7. when that save fails, it calls `CancelRequest(ref)` (a seam over `Approval.Cancel(ref, , "system")`) and logs one warning.
  - `Deliver` returns `Move`'s status.
  - `NoFix(incident)`: `Notice.Slots(incident, , .sc, Notice.#KEYNOFIX)`, then `Next(state, 0, "notice", {"variant": "no_fix"})`, then `Deliver` with `KEYNOFIX`.
  - `Outcome`: for an accepted `rejected` or `expired`, it builds the `answered` Notification (Always) and passes it through `Event` and `Apply` (each gains a trailing `notification` argument) to `Move`. A refused event sends nothing. `approved` gets none here (7.3).
  - Update the class doc's notice and states bullets.
  - Why: AC 1-8, DW-270, DW-271.
- `Test/Watch/IncidentProbe.cls`:
  - Override `SendDryRun`: it records `{incidentRef, fixKind, parameters}` into `DryRuns`; `FailDryRun` makes it fail.
  - Override `RaiseRequest`: it records each row's fields, and `sessionId` and `superSession`, into `Raised`; it returns `RaiseRef` (a fixed fixture Ref unless one is set), or an error when `FailRaise` is set.
  - Override `CancelRequest`: it records into `Cancelled`.
  - Add the helper `Dried(ref, ask, result)`, which calls `OnResponse` with `DRYRUNKEY`.
  - Update the class doc.
- `Test/Watch/Case.cls`:
  - `DropIncidentRows` tracks every `ApprovalRequest` whose `IncidentRef` is a dropped incident's (under `^OcuTalonTest("Approval","refs")`). When any was tracked, it then calls `Test.Bridge.Approval.Clean()`, which ends holds and tasks and deletes the rows.
  - Lift `Closing.HeldRequest`'s answerer check and `ApprovalRole` set-aside into `ApprovalReady()`, with the restore in `OnAfterOneTest`, for Closing and `Test.Fix.Raise`.
  - Why: Rule 19 hermeticity: `Test.Bridge.Approval` counts rows and holds instance-wide.
- `Test/Watch/Diagnose.cls` `TestDemoDiagnosis` (DW-270; AC 1, AC 3, AC 7):
  - After `WaitAnswered`, wait for `NoticedAt` and one Notification, then assert the With fix row of the matrix in full.
  - Render the received notification's slots: `Catalog.Render("incident.withFix", slots, "phone")` contains "Dry run: 50 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet."
  - The incident's trace session holds the `DryRun` to `FixExecutor`, its answer, and the send to `Notify`.
  - `Web.Api.StateBody` of S lists the incident's `requests` as the event does.
  - `Observe.DeliveryRows(S)` holds one `incident` row with the `ApprovalRef`.
  - `LogSince` holds exactly 2 `POST /v1/messages` requests.
  - This replaces L79, L84 and L85. Update the class doc.
- `Test/Watch/Incidents.cls`:
  - `TestBurstThroughThePoller`: replace L87, L102 and L119-121 with "the with-fix notice follows": `awaiting_approval`, `NoticedAt` set, one `incident.withFix` Notification, and the ownership read listing the incident.
  - `TestTwoSessions` and `TestInstanceShared`: their window before the notice was the stored with-fix diagnosis.
    - Prefix their first failure's text with `[[mock:diagnosis-late]] `, and assert the negatives after `diagnosing` while the delayed reply is on its way.
    - Then wait for the real notice (`WaitRow` `NoticedAt`) instead of the fixture `Notice`, and count `incident` events and Notifications from a mark taken after it. `TestInstanceShared`: A and B each have one with-fix notice, and the fourth failure adds one event each and no notification.
  - Update the class doc.
- `Test/Watch/Notices.cls` `TestNoticeVariants` (AC 2): each of the four incidents has an empty `RequestRefs`, no `ApprovalRequest` with its `IncidentRef`, and no `OcuTalon.Fix.Msg.DryRun` header in its trace session.
- `Test/Watch/NoticeText.cls` (pure): `TestWithFix` also builds the slots from a dry-run object and renders the UJ-1 text; refuses a dry run without `field`, and one with `resend` 0; and `Slots(row, , .sc, KEYNOFIX)` of a data-format row gives `cause` and `groups`.
- `Test/Watch/Tell.cls` (probe, warm):
  - `TestRaisedGetsTheWithFixNotice` (AC 1, AC 3): `Answer` with a valid `data_format_change` diagnosis records one ask and sends nothing. Then `Dried` with a fixture result gives:
    - the recorded row's fields;
    - `sessionId` = `TraceHeaderId`;
    - two Sent `incident.withFix` notices, one per watcher, each with `ApprovalRef` = `RaiseRef` and the nine slots;
    - the row `awaiting_approval`, with `RequestRefs` set and `NoticedAt` set.
  - `TestNoFixRoutes` (V2): `Reason`, empty `Targets`, `FailRaise`, `FailDryRun`, and a payload with no fix kind. Each gives `incident.noFix` per watcher, `open` `no_fix`, an empty `RequestRefs` and the warnings of the matrix.
  - `TestSaveFailureCancelsTheRequest`: with `FailMove`, `Cancelled` holds the Ref and nothing is sent.
  - `TestGoneBeforeTheDryRun`: closed, noticed and deleted rows get nothing.
  - Extend `Diagnosis` for a fix payload.
- `Test/Watch/Lifecycle.cls` `TestApprovalOutcomes` (AC 5): an accepted rejected or expired outcome Sends one `answered` notice per recipient with the key, slots, `ApprovalRef` and `IncidentRef`; the fixture rows get `AnsweredChannel`/`AnsweredAt` through `Fixture.Approval`'s fields. It is also sent when the state stays `awaiting_approval` or `fixing`. A refused outcome Sends none.
- `Test/Fix/DryRun.cls` `TestInvalidRepairTakesTheFallbackRoute`: the valid repair's incident gets one recorded ask (`repair_resend` with the parameters) and no notice yet. Replaces L483-487.
- `Test/Fix/Raise.cls` (new; extends `Test.Watch.Case`; throwaway, fresh):
  - Its incidents come from real failed orders: through `SendBatch` (owner S, item `OrdersFromPartner`, real header ids), or through the real poller for the `instance` test.
  - `TestInstanceWatchers` (AC 4): `SetOnlineDemo("")`; A and B watch Orders, C does not; `ClearMark`; `Fail(3, "")`.
  - `TestRejectChangesNothing` (AC 5, AC 7): `ApprovalReady`; `Snapshot.Take(OCUORDERS)` before the answer and again after the outcome; `Diff` empty; no `Execute` header in the trace session. `answered.rejected` renders "Rejected from the web chat at …. Nothing was changed."
  - `TestExpiryChangesNothing` (AC 5): `Age`, delete the hold, `OcuTalon.Bridge.Approval.Reconcile()`.
  - `TestCancelSendsNoOutcome` (AC 6): no `ApprovalOutcome` header from `ApprovalHold` with the Ref, after the hold ends.
  - `TestUnscopedOrdersGetTheNoFixNotice` (AC 8): `Fail(2, "")` delivered for owner S; the dry run's `Reason`.
  - Each test removes its rows (Case).
- `Test/Bridge/Approval.cls`: `NewRow("fix")` sets `FixKind` "zz_fix", `FixParameters` `{"field":"OrderDate"}` and `FixTargets` "101,102,103". `Refusals` gains seven cases: `fix` with an empty `FixKind`, a `FixParameters` of "" and of "[1]", or an empty `FixTargets`; `tool_call` with a `FixKind`, `FixParameters` or `FixTargets`.
- `Test/Watch/Closing.cls`: `HeldRequest` sets the three fields and uses `Case.ApprovalReady`.
- `Test/Data/Tables.cls`: `ApprovalRequest`'s contract gains `FixKind` `%String(MAXLEN=32)`, `FixParameters` `%String(MAXLEN=)` and `FixTargets` `%String(MAXLEN=)` (Lane A's own entry).

**Acceptance Criteria:**
- AC 1: Given the 50 failed orders of the With fix row and the mock's diagnosis scenario, when `IncidentManager` reaches the incident notice, then it calls `Approval.Raise` exactly once with the row of the matrix and moves the incident to `awaiting_approval`, and S's stream shows `noticed`, `settling`, `diagnosing`, then the notice, in that order (DW-270).
- AC 2: Given a fallback diagnosis, or a cause that is not a data-format change, when the notice step runs, then no dry run is asked and no approval request names the incident, and Epic 5's fallback or no-fix notice is sent as before.
- AC 3: Given the raised request, when the with-fix notice is sent:
  - each recipient's one kind-`incident` Notification carries the request's `ApprovalRef` and the slots `field`, `before`, `after` and `resendCount` from the dry run, never text;
  - no kind-`approval` Notification is sent;
  - its slots render through `Catalog.Render` to the UJ-1 "Dry run:" paragraph;
  - `WebChatOut` records an `incident` `Delivery` row with that `ApprovalRef` (Integration AC).
- AC 4: Given an `instance` incident on a local install watched by two sessions, when its request is raised, then exactly one request with its `IncidentRef` exists, and each watcher's notice carries that request's `ApprovalRef`, while a non-watcher gets none.
- AC 5: Given the request is rejected (or expires), when `ApprovalHold` sends `ApprovalOutcome` to `IncidentManager`:
  - the incident moves per AD-15's table (to `open` `rejected` or `expired` when nothing else is pending or running);
  - each recipient gets one `answered` Notification with the request's `ApprovalRef` and `IncidentRef`, which renders "Rejected from {channel} at {time}. Nothing was changed." (or "Expired at {time}. Nothing was changed.");
  - no `Execute` is sent, and nothing in OCUORDERS changes.
- AC 6: Given a raised request, when it is cancelled, then no `ApprovalOutcome` reaches `IncidentManager`, and the incident stays `awaiting_approval` with no new notification.
- AC 7 (DW-271): Given the raised request, when the `incident` event is published and `/state` is read, then each lists the request with its `Ref` and `State` (`pending`, then `rejected` after the rejection), read through `RequestRefs` by `FromRow` with no SQL.
- AC 8 (V2): Given a usable data-format diagnosis whose dry run is refused, finds nothing to resend, or whose `Raise` fails, when the notice step runs, then no request stays approvable and the incident gets Epic 5's no-fix notice (`open` `no_fix`), with one Type 3 warning for an error.

## Spec Change Log

- 2026-10-28, spec gate (lead): the split is ruled (decide, U5's split rule): the later-request criterion and both of its And clauses moved verbatim to the new Story 7.6, "Later failures in the same incident get their own dry run and approval request", planned next after 7.2 and before 7.3 (epics.md). V1 ruled as a veto item (U-126, kept unless the owner reverses it) and the spine's Conventions row "Approval requests" amended to name `FixKind`, `FixParameters` and `FixTargets`. V2 ruled as a veto item (U-127). DW-270's bullet amended (Rule 5 apply-and-report) to the live case the recorded snapshot records. Status reset from `blocked` to `ready-for-dev`; nothing else in the plan changed.

## Review Triage Log

## Design Notes

**Size and the split (the blocking ruling).** Story 7.2 as written has five groups of criteria and two ledger entries. Groups 1-4 with DW-270 and DW-271 already touch about 16 files (the tasks above). Group 5, later requests, is its own design problem:
- Failures that join after the notice need a settle waiter of their own. Today a waiter starts only for a new incident (IncidentManager L176-186), and `Waiting` stops once `NoticeCount` is set (L752-756).
- They need a dry run that leaves out the targets of earlier requests and the failures they already considered. `RepairResend.DryRun` reads all of `Seen` (L98-119).
- They need new stored state on `Incident` or `FailureGroup`: when the later failures began, and which keys a request covered. That is a second schema veto.
- They need the kind-`approval` notification with `incident.laterRequest`'s slots ("{count} more … since {time}"), and its tests.

The proposed cut is in `## Auto Run Result`. This spec is planned in full for the part that stays.

**V1. Where the fix's kind, parameters and targets live (schema change, veto window; the lead rules it at the spec gate).**
- **Chosen:** append `FixKind`, `FixParameters` and `FixTargets` to `OcuTalon.Bridge.Data.ApprovalRequest` (Lane A, AD-33; stored properties append-only; Storage Values 21-23). `Raise` requires them for `fix` and refuses them for `tool_call`.
- **Rejected:**
  - Reusing `ToolName`/`ToolArguments`: `Raise` refuses both for a fix (L190-191), the spine's convention gives them to `tool_call`, and Lane B's approval payload shows them as a tool's.
  - Putting the targets in `DryRun`: its keys are exactly `DRYRUNKEYS` (7.1's tests, Lane B's `Part.DryRun`), and 500 ids do not belong on the card.
  - A Lane A table keyed by Ref: AD-16 says the row alone.
- **Reversal:** stop writing and validating the three; the properties stay, empty (append-only). No data migration is needed: no row has them yet.
- **Spine:** the Conventions row "Approval requests" says a fix's only contract column is `DryRun`, "whose message scope is the failure group its IncidentRef names" (the Story 3.4 ruling). It needs the light-path amendment naming the three (Rule 20, the lead's write).

**V2. A data-format diagnosis whose fix cannot be proposed (public-text claim, veto window).** The dry run can be refused, find nothing to resend, or `Raise` can fail; AD-15 defines the with-fix notice only for "a valid dry run".
- **Chosen (a):** Epic 5's no-fix notice (`incident.noFix`, `open` `no_fix`; "None of my fixes applies to this, so I'm not proposing one. Nothing was changed."), plus one Type 3 warning for an error. It is honest when nothing can be repaired, close when the production can't be read, and keeps no false all-clear and nothing approvable.
- **Rejected:**
  - (b) the fallback notice with the reason `error`: it claims the cause was not worked out, which is false;
  - (c) leaving the incident unnoticed with a warning: 50 failures would go unsaid.
- **Spine:** AD-15's variants could note the route (the lead's call).

**Decided in-stage (small, reversible, within the intent):**
- The dry run is asked asynchronously, with its own completion key. A synchronous call would hold IncidentManager's one job for the dry run's reads; AD-5 keeps the state on the persisted waiter.
- The kind and the parameters ride on the ask and are read back from it (`callrequest`), so no `Incident` column is needed.
- The order inside `Proposed` is: the table, the slots, then `Raise`. So a refusal or an unbuildable slot raises nothing. A failed save after `Raise` cancels the request (channel `system`), so nothing stays approvable that no incident lists.
- `ResultTarget` is a parameter naming the item `IncidentManager`, like `FIXEXECUTOR` and `NOTIFY` (AD-1). `TraceRef` is the waiter's `SuperSession` when it is a Ref, else empty (`Raise` refuses anything else).
- `Raise` runs even when nobody is told (an `instance` incident on the online demo, owner `eval`): the row is the truth, and it expires.
- The answered keys:
  - `answered.rejected` and `answered.expired` are used, not the `…By` forms: naming the user on a multi-user local install is the page's (6.2).
  - The expired time is `ExpiresAt`.
  - `DecisionRef` is empty on `answered`.
  - The approved status is 7.3's.
- The `answered` notification goes out in the session in which the outcome arrives. That is the incident's trace session, because the hold joined it at `Raise`; a hold that `Reconcile` re-armed has its own session (AD-26's rule).
- `count` stays `NoticeCount` (5.8's builder), and the catalog's dry-run paragraph renders "{count} … affected". The dry run's `affected` is not a slot (the AC names four extra slots). Both are 50 in UJ-1; they differ only when failures joined during the diagnosis, or for DW-318's cap.
- **DW-270's "recorded date-format snapshot" is read as the live case it records.** That case is `eval/orders-date-format`: 50 `PartnerOrder`s, `MM/DD/YYYY`, through `Partner.Send`, with the mock's `diagnosis` scenario. IncidentManager builds packs only from live incidents, and a dry run must read the live failed messages. A wording amendment of the bullet is the lead's (Rule 5, apply and report).

**Governing ADs:**
- AD-1: items by name (`FixExecutor`, `IncidentManager` as the `ResultTarget`).
- AD-2: the bridge boundary (`FixKind` is a string).
- AD-4: scope; the watchers of an `instance` incident.
- AD-5: the persisted waiter and the asynchronous ask.
- AD-11: `Raise`'s row, the row as the truth, a cancel sends no outcome.
- AD-12: the full view after the commit.
- AD-13: `FromRow` uses no SQL.
- AD-15: `raised`, `rejected` and `expired` rows; `NoticedAt` at the notice; the three variants; the first request's `ApprovalRef` on the notice.
- AD-16: the stored dry run; the executor trusts only the row.
- AD-17: the approval audit, unchanged.
- AD-22: throwaways and the mock log.
- AD-26: the incident's trace session.
- AD-29: Lane A.
- AD-31: `HostSink` unchanged.
- AD-32: kinds `incident` and `answered`, slots only.
- AD-33: one writer and one publisher.

Conventions: "Approval requests" (V1), "Incident notice", "Messages", "Redaction".

**Integration ACs, Consumes, Consumed-by (Rules 1 and 2):**
- **Integration ACs:**
  - `WebChatOut` records the with-fix and answered notifications as `Delivery` rows carrying the `ApprovalRef` (AC 3; `Raise` tests).
  - `Catalog.Render` of the received slots gives the UJ-1 paragraph (AC 3).
  - `/state` (`Web.Api.StateBody`) lists the request (AC 7).
  - The real hold sends the outcome that `IncidentManager` turns into the answered notice (AC 5).
- **Consumes:**
  - 7.1: `Fix.Msg.DryRun`/`DryRunResult` and `FixExecutor`'s dry run.
  - 5.8: `Notice`, `Deliver`, `Tell`, `WithFixSlots`, `RequestRefs`, `FromRow`'s `requests`.
  - 5.5: `Transitions`, `Facts`, `Owns`, `Outcome`.
  - Epic 0 and Story 3.x: `Approval.Raise`/`Answer`/`Cancel`, `ApprovalHold`, `Reconcile`.
  - Epic 0: the catalog keys.
  - 0.10: `Partner.Send`; the mock's `diagnosis` scenario.
- **Consumed-by:**
  - 7.3: `FixExecutor` loads `FixKind`, `FixParameters` and `FixTargets` from the row alone; the approved answered status extends `Outcome`'s builder; `Recheck` compares against `FixTargets` and the stored `DryRun`.
  - 7.4: the `result` notification; DW-272's stored counts.
  - The proposed sibling: later requests reuse `Propose`/`Proposed` with `incident.laterRequest`, kind `approval`, and the earlier requests' `FixTargets`.
  - Epic 6 (6.1-6.4): it renders the notice with Approve and Reject and edits the answered message in place by `ApprovalRef`.
  - Epic 11: the demo path end to end.

**Extend, don't copy (Rule 2):**
- `Proposed` and `NoFix` deliver through 5.8's `Deliver`/`Move`/`Tell`.
- `Notice.WithFixSlots` and `Slots` gain optional arguments.
- The answered notice rides `Move`'s existing notification argument.
- The new seams follow `SendNotice`/`SendExecute`.
- DW-270's pin extends `TestDemoDiagnosis` instead of a second 50-order run.
- The probe tests extend `Tell` and `Lifecycle`.
- The approval set-up is lifted from `Closing` into `Case`.
- The clean-up reuses `Test.Bridge.Approval.Clean`.

**Ledger inbox:**
- DW-270: addressed by AC 1 and AC 3, the With fix row, and the `TestDemoDiagnosis` task.
- DW-271: addressed by AC 7, `Proposed`'s append, and the `TestDemoDiagnosis` and `TestRejectChangesNothing` tasks.

**Notes for the lead and Epic 6 (no action here):**
- `approval.raised` fires inside `Raise`, before `NoticedAt`. So a session owner gets the `approval` event at once, while an `instance` incident's watchers first see the request in the `incident` event's `requests` (`APPROVALVISIBLE`). This is Epic 6's rendering concern; BridgeSink is unchanged.
- The `answered` channel slot renders only `web`, `phone` and `telegram`. That is the catalog's rule, and it is fine for the answer paths that exist.

**Spec-gate rulings (lead, 2026-10-28):**
- The split: ruled `decide` (a split into a sibling planned next in the same epic, within `limits.split_children`). Story 7.6 takes group 5 verbatim; this spec's cut stands as planned.
- V1: ruled `veto` (schema), inbox U-126, recommended keep. The Conventions row "Approval requests" now names the three fields (Rule 20 light path, by the runner). Build as planned; a reversal is a fix story.
- V2: ruled `veto` (a claim in public text in an edge case), inbox U-127, recommended keep. The route uses the existing `no_fix` variant that AD-15 already defines, so no AD-15 amendment is made.
- DW-270: its bullet in epics.md now reads the live case the recorded snapshot records (Rule 5 tier 1, apply and report).

**Spine notes for the lead (Rule 20; candidates only):**
- The Conventions row "Approval requests" (V1).
- AD-15's notice variants (V2, if ruled).
- DW-270's wording: the live recorded case.

**Footprint:** every file is in the stage's footprint or its merged Lane A areas: `src/bridge/**`, `Watch/**`, `Test/Watch/**`, `Test/Fix/**`, `Test/Bridge/**`, and `Test/Data/Tables.cls` (its own entry). No contended path is touched.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root.
- Run one command per tool call, each with `timeout: 600000`, in the foreground.
- Never put two IRIS test runs in one message.
- **Tests run only on throwaways, never on `ocutalon-slot-a`.**
- Classes whose tests drive the running production run fresh, because a warm stack's production jobs keep the classes they loaded: `IncidentManager`, and `ApprovalHold` reading the changed row class.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e7s2iw ci/warm.sh up`, once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s2iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Watch.Tell`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Watch.Transitions`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Bridge.CodeRules`. Expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e7s2i ci/iris.sh class <Class>`, fresh, one call per class: `OcuTalon.Test.Watch.Diagnose` (first: Task 0), `OcuTalon.Test.Fix.Raise`, `OcuTalon.Test.Watch.Incidents`, `OcuTalon.Test.Watch.Notices`, `OcuTalon.Test.Watch.Closing`, `OcuTalon.Test.Fix.DryRun`, `OcuTalon.Test.Bridge.Approval`, `OcuTalon.Test.Checks.Turns`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e7s2i ci/iris.sh shard lane-a --part 1/4`, then `2/4`, `3/4` and `4/4`, each in its own call. Record each part's time; if one runs past 480 s, use `k/5`.
- (once) `<lane> OCUTALON_RUN_TAG=e7s2i ci/iris.sh shard lane-b`. Expected: passed (it covers `Test.Data`, `Test.Demo` and `Test.Live`).
- (once) `<lane> OCUTALON_RUN_TAG=e7s2i ci/iris.sh live storage-roundtrip`. Expected: passed (`ApprovalRequest`'s committed Storage block).
- (once) `bash ci/checks.sh`. Expected: every script passes (boundaries, storage blocks, class rules: the bridge names no OcuTalon package).
- (once) `<lane> OCUTALON_RUN_TAG=e7s2iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e7s2i ci/iris.sh teardown`. Run both also after a failure.

**Shared surfaces:**
- **`ApprovalRequest`'s columns and `Raise`'s fix rules.** Changed: `Test.Data.Tables` (contract), `Test.Bridge.Approval` (`NewRow`, `Refusals`) and `Test.Watch.Closing.HeldRequest`. Checked by the `storage-roundtrip` live unit.
- **A usable data-format diagnosis is now noticed with a fix**, ending 5.8's R2 (a).
  - Changed: `Test.Watch.Diagnose.TestDemoDiagnosis`; `Test.Watch.Incidents` (`TestBurstThroughThePoller`, `TestTwoSessions`, `TestInstanceShared`, the class doc); `Test.Fix.DryRun.TestInvalidRepairTakesTheFallbackRoute`; `Test.Watch.IncidentProbe` (seams).
  - Run unchanged: `Test.Checks.Turns`, `Test.Watch.Notices`, `Test.Watch.Closing`, `Test.Demo.Production`.
- **Approval requests that IncidentManager raises in tests** are removed with their incidents (`Case.DropIncidentRows`), so `Test.Bridge.Approval`'s instance-wide row and hold counts stay its own.
- **The answered notification on a rejected or expired outcome:** `Test.Watch.Lifecycle` (the probe's `Sent`), and `Test.Watch.Closing.TestRejectThroughTheHold` (it asserts only events).
- **`Watch.Notice`'s builders** gain optional trailing arguments; existing callers are unchanged.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply (Rule 19).** The implement stage applies each one, observes red, reverts byte-identically, and records `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 raise | `Proposed` skips `RaiseRequest` and delivers with an empty `ApprovalRef` | `Diagnose.TestDemoDiagnosis` (fresh), `Tell.TestRaisedGetsTheWithFixNotice` |
| AC 1 row | `Proposed` sets `FixTargets` to "" | `Tell.TestRaisedGetsTheWithFixNotice`; `TestDemoDiagnosis` (`Raise` refuses, so no-fix) |
| AC 1 session | `RaiseRequest` passes no `sessionId` | `TestDemoDiagnosis` (the hold is not in the trace session) |
| AC 1 state | `Proposed` delivers with the state `open` | `Tell.TestRaisedGetsTheWithFixNotice`, `TestDemoDiagnosis` |
| AC 2 | `Notice` proposes for every usable diagnosis (no `Key` check) | `Notices.TestNoticeVariants` (a `DryRun` header) |
| AC 3 slots | `WithFixSlots` leaves out `resendCount` | `NoticeText.TestWithFix`, `TestDemoDiagnosis` (render) |
| AC 3 kind | `Proposed` also sends a kind-`approval` copy | `TestDemoDiagnosis` |
| AC 4 | `Proposed` raises once per recipient | `Raise.TestInstanceWatchers` |
| AC 5 answered | `Outcome` passes no notification | `Raise.TestRejectChangesNothing`, `Lifecycle.TestApprovalOutcomes` |
| AC 5 key | the expired outcome uses `answered.rejected` | `Raise.TestExpiryChangesNothing`, `Lifecycle` |
| AC 5 no Execute | `Transitions`' rejected row returns `OWN` | `Raise.TestRejectChangesNothing` (an `Execute` header), `Watch.Transitions` |
| AC 6 | `HoldResponse` sends `rejected` for a cancelled task | `Raise.TestCancelSendsNoOutcome` |
| AC 7 / DW-271 | `Proposed` does not append to `RequestRefs` | `TestDemoDiagnosis` (`requests` `[]`), `Raise.TestRejectChangesNothing` (the outcome is refused) |
| AC 8 / V2 | a `Reason` leaves the row unnoticed (no `NoFix`) | `Raise.TestUnscopedOrdersGetTheNoFixNotice`, `Tell.TestNoFixRoutes` |
| bridge | `Validate` skips the `FixTargets` check | `Bridge.Approval.TestRefused` |
| save failure | `Proposed` does not cancel after a failed save | `Tell.TestSaveFailureCancelsTheRequest` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

(Lead, 2026-10-28: the split was ruled at the spec gate and the status reset; the plan stage's original halt follows for the record.) Original: intent gap: split proposal for Story 7.2. As written, it is too large for one implement pass. Its fifth group of criteria (later requests) needs four things of its own: a settle waiter for failures after the notice; a dry run that leaves out earlier requests' targets and considered keys; new stored state on Incident or FailureGroup (a second schema veto); and the kind-approval notification with incident.laterRequest and its tests. That comes on top of groups 1-4 with DW-270 and DW-271, which touch about 16 files. Proposed exact cut: 7.2 keeps groups 1-4 (Raise at the with-fix notice and no request for a fallback or no-fix diagnosis; the notice carrying the ApprovalRef and the dry-run slots, with its render test; the instance incident's watchers; rejection, expiry and cancellation) and DW-270 and DW-271. A new sibling story, planned next in Epic 7 (after 7.2, before 7.3), "Later failures in the same incident get their own dry run and approval request", takes group 5 verbatim: the criterion "Given same-cause failures that join the incident after its notice, while it is awaiting approval, fixing or resolved …" with both of its And clauses (the later-request render test, and "failures that join an Open incident only update its count"). This spec is planned in full for the cut; once the cut is ruled, set its status to ready-for-dev. Two items for the same spec gate (veto window, not blocking): V1, the schema change (ApprovalRequest gains FixKind, FixParameters and FixTargets; the Conventions row "Approval requests" is amended), and V2 (a data-format diagnosis whose dry run is refused or empty, or whose Raise fails, gets Epic 5's no-fix notice).

**Planned, not implemented.** No source file was changed. No IRIS call was made, and no throwaway was started: everything was investigated read-only from the worktree at `e15bf0f`. Task 0 lists the three measurements left for the implement stage, each marked (inference) above.
