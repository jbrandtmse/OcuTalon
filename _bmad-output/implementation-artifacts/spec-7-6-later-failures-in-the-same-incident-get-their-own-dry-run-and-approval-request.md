---
title: 'Later failures in the same incident get their own dry run and approval request'
type: 'feature'
created: '2026-10-28'
status: 'done'
baseline_revision: '0be77b16ab1e63aee854fc8a6ed7a06f03471635'
baseline_commit: '0be77b16ab1e63aee854fc8a6ed7a06f03471635'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Since Story 7.2, an incident with a fix gets one dry run and one approval request at its notice. Same-cause failures that join it afterwards only raise its count: no settle waiter starts for them (`IncidentManager.Begin` and `Check` stop once `NoticeCount` is set), `RepairResend.DryRun` would read every key of the group's `Seen` (so a second dry run would re-target what the first request already holds), and nothing records when the later failures began. So later failures are counted but never proposed, and a user could not approve them without approving more than they were shown.

**Approach:** Each dry-run ask records the window of failures it covers, as two marks per failure group (`AskedFrom`, `AskedTo`: keys of `Seen`), and the dry run reads only that window. Same-cause failures that join after an ask, while the incident awaits approval, is fixing or is resolved, start a later round: `IncidentManager` stores when the first of them arrived (`Incident.LaterSince`) and starts a waiter in the incident's trace session. The waiter settles the round by the same rule, then asks `FixExecutor` for a dry run of the new window only. It uses the kind and parameters of the incident's first request, and holds the round's time in `Incident.AskingSince` while the ask is on its way. On the answer, `IncidentManager` raises one request of its own, appends it to `RequestRefs`, moves the incident per AD-15's table and sends each recipient one kind-`approval` `incident.laterRequest` notification with its `ApprovalRef`. An open incident only counts. These are four appended stored properties (V1, a schema veto). The "own `FixRun`" clause depends on 7.3's `Execute` (V3).

## Boundaries & Constraints

**Always:**
- `IncidentManager` is the only writer of `Incident` and `FailureGroup` and the only publisher of `incident` events. It moves an incident only through `OcuTalon.Watch.Transitions.Next` and publishes only after its save (AD-12, AD-15, AD-33). Every state lives in rows and in the persisted waiter instances (AD-5). A waiter alarm is at most 120 s (`Settle.Alarm`).
- **Windows.** Every dry-run ask, the first included, first moves each group's marks: `AskedFrom` := `AskedTo`, then `AskedTo` := the last key of `Seen`. It saves the marks (with the incident's own fields that the caller set) in one transaction, and only then sends the ask. The window of the newest ask is `Settle.Window(Seen, AskedFrom, AskedTo)`. `FixExecutor`'s dry run reads each group's window, or its whole `Seen` when the group has no marks (7.1's rows and fixtures). A request's fixed targets therefore come only from its own window, and a failure is never in two windows.
- **Later failures.** A fresh key that joins a not-new incident is a later failure when its group has an `AskedTo` and the incident is not open-and-noticed. `Record` then sets `LaterSince` to the earliest `FailedAt` of the later failures (min, like `FirstAt`).
  - When `LaterSince` goes from empty to set on a noticed incident, `Batch` starts one later waiter: a `Settle` request to itself with `%SessionId` = the incident's `TraceHeaderId` (AD-26) and the batch's `SuperSession` kept.
  - On an unnoticed incident (the first ask is on its way), no waiter starts. The first answer's raise route starts one after its notice, and its no-fix route clears `LaterSince`.
  - An open, noticed incident (fallback, no_fix, rejected, expired) gets no `LaterSince`: it only updates its count.
- **The later waiter** (a `Settle` whose incident's `NoticeCount` is set; its alarms use the completion key `laterSettle`) re-reads the row on each wake:
  - The incident is gone, closed, or has no `LaterSince`: it ends.
  - The incident is open: it clears `LaterSince` and ends.
  - `Settle.Wait(LaterSince, LastAt, now, quiet, max)` > 0: it sets an alarm for that long.
  - An ask is on its way (`AskingSince` set): it re-checks after `quiet` seconds (one ask at a time per incident).
  - Otherwise it asks (`AskLater`):
    - It reads `FixKind` and `FixParameters` from the incident's first request row. If that row is missing or has no kind, it logs one Type 3 warning, clears `LaterSince` and ends.
    - If no group holds a key after its `AskedTo`, it clears `LaterSince` and ends.
    - Otherwise: `AskingSince` := `LaterSince`, `LaterSince` := "", the marks move, and one `Fix.Msg.DryRun` goes out (completion key `laterDryRun`, from the waiter, so in the incident's trace session).
- **The later answer** (`Proposed` with `later` 1; it acts only when the incident exists, is not closed and has `AskingSince` set). It always clears `AskingSince`, then:
  - `Reason` → one warning, no request. Empty `Targets` → no request.
  - Otherwise `Transitions.Next(state, 1, "raised")` must accept (awaiting_approval → awaiting_approval, fixing → fixing, resolved → awaiting_approval). A refusal, which is an open incident, raises nothing.
  - The slots are `Notice.WithFixSlots(incident, .sc, dryRun, count, time)`: count = the number of keys in the windows, time = the round's `AskingSince`.
  - The row is built exactly as for the first request: kind `fix`, the incident, its owner, `ResultTarget` `IncidentManager`, `TraceRef`, and the ask's kind and parameters with the result's targets and dry run (U-126). `RaiseRequest` runs at `$TLevel` 0 with the incident's `TraceHeaderId` and `SuperSession`.
  - The Ref is appended to `RequestRefs`, and `Move` saves the row and sends one Notification per recipient: `Kind` `approval`, `CatalogKey` `incident.laterRequest`, the Ref as `ApprovalRef`, the incident's Ref and `DecisionRef`. Then it publishes the `incident` event.
  - A save that fails after `Raise` cancels the request (`CancelRequest`) and logs one warning.
- One `Execute` per approved request, one at a time per incident, by 5.5's table: `awaiting_approval` + approved → `Execute` own; `fixing` + approved waits; `fixing` + final with a waiting request → `Execute` the earliest waiting in `RequestRefs` order.
- No model call: a later round asks only `FixExecutor` (AD-16), and the mock logs no request for it.
- Producers send keys and slots, never text (AD-32). Warnings go through `Bridge.Redact.Text`. Rule 14: ASCII escapes, and comments that state the contract.
- Stored properties are append-only, and their `Storage` blocks are committed (AD-5, AD-33).
- Tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`. Tests that drive the running production run only on throwaways, fresh, never on `ocutalon-slot-a`.

**Never:**
- Nothing of a later story:
  - 7.3: no `Execute`/`Recheck` handler, no change to `Fix/Executor.cls`, no `FixRun` row written (V3), no `answered.approved`;
  - 7.4: no `result` notification and no stored counts;
  - 7.5: no `Reconcile`/`Sweep`.
- No edit to:
  - `Watch/Transitions.cls` (it already holds every row this story uses);
  - `Msg/Catalog/*.cls`, `Live/Payload/*`, `Fix/Msg/**` (AD-16 lists their properties) or `src/bridge/**`;
  - `Core/BridgeSink.cls`, `Test/Demo/**`, `Test/Msg/**`, `Test/Live/**` or `Test/Data/**` beyond `Tables.cls`'s own two entries.
- No change to the first notice's key, slots or count.
- No new public text: a later round that cannot raise a request sends nothing (V2).
- No mock scenario. No stored property other than V1's four. No edit to any AD. No `[Language = python]`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Later request, awaiting (live) | S's incident `awaiting_approval` with R1 over 3 failed orders, then 2 more same-cause orders fail with S's TraceRef | At once: `Count` 5, `NoticeCount` 3, one `incident` event with count 5, and R1's `FixTargets`, `DryRun` and state unchanged.<br>After the settle: one `DryRun` to `FixExecutor` in the incident's trace session.<br>R2: `fix`, `pending`, owner S, R1's `FixKind`/`FixParameters`, `FixTargets` = the 2 new ids ascending, `DryRun` `{2, 2, 0, "order date", "10/16/2026", "2026-10-16", {order, orders}}`, its hold in the trace session.<br>The row: `awaiting_approval`, `RequestRefs` "R1,R2", `NoticedAt` unchanged, `LaterSince` and `AskingSince` empty.<br>S gets one `approval` Notification: `incident.laterRequest`, `ApprovalRef` R2, slots `count 2`, `time` = the first new failure's `FailedAt`, `itemNoun`, `fixSummary`, `field`, `before`, `after`, `resendCount 2`. It renders "2 more orders failed since …, with the same cause. I can … Approve?" plus its Dry run paragraph.<br>`WebChatOut` records an `approval` Delivery row with R2. The event and `/state` list R1 and R2 `pending`. The mock logs no request. | none |
| Later rejected while R1 pending | `Approval.Answer(R2, "reject", "web", …)` | Stays `awaiting_approval`. One `answered.rejected` with R2's Ref per recipient. The event lists R2 `rejected`. No `Execute`. | none |
| Fixing (probe) | `fixing`, R1 `executing`, later round raised | Stays `fixing`. The `approval` notice goes out. R2 approved → no `Execute`. R1 final `FixResult` → exactly one `Execute` (R2) in the trace session. R2 final → `resolved`. | none |
| Resolved (probe) | `resolved`, later round raised | `awaiting_approval`, the `approval` notice | none |
| Open only counts | open with `fallback`, `no_fix`, `rejected` or `expired`; same-cause failures join | `Count` and the `incident` event only. `LaterSince` stays empty, no waiter, no `DryRun`, no request, no Notification. | none |
| Still gathering | waiter wakes with `Settle.Wait` > 0 | an alarm for those seconds; nothing asked | none |
| One ask at a time | round 2 settles while round 1's ask is on its way | re-check after `quiet` s, no second ask. After round 1's answer, round 2 asks only its own window, and its `time` is its own first failure's. | none |
| After the first ask (stragglers) | failures join after the first ask, before its answer | `LaterSince` set, no waiter. The raise route starts the later waiter after the notice. The no-fix route clears `LaterSince`. | none |
| Later dry run refused (V2) | `Reason` set | no request and no Notification. `AskingSince` cleared, the state unchanged, one Type 3 warning (`LOGLATER`, the redacted reason). | logged |
| Nothing to resend (V2) | `Reason` "" and `Targets` "" | as above, with no warning | none |
| Raise fails / ask not sent / error answer / slots unbuildable (V2) | `Raise` error, a send error, `OnError` for `laterDryRun`, or a dry run without `field`/`before`/`after` or with `resend` < 1 | as "refused": nothing raised or sent, `AskingSince` cleared, one warning | logged |
| Opened during the ask | R1 rejected (open) before the answer | nothing raised or sent, `AskingSince` cleared, no warning | dropped |
| Save fails after Raise | `Move`'s save fails | `CancelRequest(R2)`, nothing sent, one warning | logged |
| Gone | the incident is closed or deleted before the wake or the answer | nothing written, raised or sent, no error | dropped |
| No first request row | R1's row missing | one warning, `LaterSince` cleared, nothing asked | logged |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless stated. Line numbers are as of `2a6fa80`.

**`Watch/IncidentManager.cls`** (the class this story changes most):
- The class doc L1-72: the notice bullet L34-54 and the states bullet L55-64. Parameters L77-164.
- `OnResponse` L182: diagnose key, then dryrun key, else `Check`. `OnError` L198.
- `Batch` L211: it starts waiters only for `added = "new"` (L223-225) and publishes the event for noticed non-new incidents (L226-228).
- `Record` L234: the fresh keys loop L285-305, where `added` is set at L305. `Find` L318.
- `Start` L348 clears `%SessionId`. `Begin` L360 quits when `'Waiting`, so a noticed incident gets nothing. `Check` L376 is the settle rule: `SetTimer(Alarm(seconds), ALARMKEY)` L382, then `NoticeCount` and `Diagnose`.
- `Answered` L445 → `Notice` L507 → `Propose` L532 (builds and sends the ask through `SendDryRun` L553).
- `Unproposed` L560. `Proposed` L579-637: `Open` check, Reason, Targets, table, dry-run parse, `WithFixSlots`, the row L609-618, `RaiseRequest` L619, the append L625, `Deliver` L626, the cancel L627-631.
- `NoFix` L654. `Deliver` L670 builds the Notification at L673-679, then calls `Move` L690.
- `Apply` L711, `Facts` L727 (pending/waiting/earliest), `Owns` L748, `Execute` L764, `Outcome` L832, `Result` L867, `Event` L880. `Open` L953, `Waiting` L959, `Tell` L969.

**Pure and data classes:**
- `Watch/Settle.cls`: `Values` L56, `Wait` L70, `Alarm` L90, `Hold` L111 (`Seen` stays oldest first and is cut to `SEENMAX` = 1000).
- `Watch/Notice.cls`: `KEYWITHFIX` L28, `WithFixSlots` L94-121, `Common` L124 (count = `NoticeCount`, time = `FirstAt`).
- `Watch/Transitions.cls` L104-135: awaiting/fixing/resolved + raised, fixing + approved waits, finished with waiting → `EARLIEST`. Read only.
- `Fix/Kind/RepairResend.cls` `DryRun` L90: L98-105 reads every `h` key of each group's `Seen`.
- `Data/Incident.cls`: `RequestRefs` L81, Storage Value 26 L165-167. `Data/FailureGroup.cls`: `ErrorSummary` L38, Storage Value 11 L94-96, `OfIncident` L49.

**Read only, unchanged consumers:**
- `Msg/Catalog/Watch.cls` L99 `incident.laterRequest` (slots `count`, `itemNoun`, `time`, `fixSummary`, `field`, `before`, `after`, `resendCount`; an undeclared slot such as `cause` is ignored, as `Test.Msg.Catalog.TestExtraSlots` shows).
- `Channel/WebChat/Out.cls` L50-53 records an `approval` notification as a Delivery row with its `ApprovalRef`.
- `Live/Payload/Incident.cls` `Details` L138-147 lists every `RequestRefs` entry with `Ref` and `State`.
- `Data/Ownership.cls` L54 `APPROVALVISIBLE`.
- `Test/Demo/SimPhoneOut.cls` L342-365 (Epic 6) renders a later request as its own phone message.

**Test helpers:**
- `Test/Watch/IncidentProbe.cls`: overrides `Move` L62, `SendExecute` L73, `SendDryRun` L82, `RaiseRequest` L91, `CancelRequest` L102 and `SendNotice` L124; helpers `Dried` L147, `Undried` L155, `Answer` L164.
- `Test/Watch/Tell.cls`: `PARAMETERS`/`DRYRUN` L46-48, `Group` L498 (empty `Seen`), `Diagnosis` L524, `Ask` L543, `Result` L553, `Logged` L564, `Setup` L588 (two watchers of an `instance` ZZNS incident), `Host` L602. `TestRaisedGetsTheWithFixNotice` L272 is the model for the new probe tests.
- `Test/Watch/Lifecycle.cls`: `TestFixResults` L348; helpers `Incident` L850, `Request` L867, `Link` L901, `SetRequest` L909, `Outcome` L976, `Result` L987.
- `Test/Data/Fixture.cls` (read only): `Incident` L81 and `Approval` L102 take a fields object (`FixKind`, `FixParameters`, `FixTargets`, `LaterSince`, …).
- `Test/Watch/Case.cls`:
  - set-up: `Fail` L629, `WaitFailed` L662, `Fixture` L687, `Group` L1172, `WaitCount` L1212, `WaitRow` L1220;
  - notifications and the page: `NoticeBodies(ref, kind)` L1257, `AssertDelivered` L1274, `Listed` L1291, `StateIncident` L1300, `Notifications` L1313, `WaitNotices` L1322;
  - requests and the trace: `ApprovalReady` L247, `Requests` L270, `HeadersBetween` L284, `HoldInSession` L296;
  - clean-up: `DropIncidentRows` L1371 removes requests, holds and tasks.
- `Test/Fix/Raise.cls`: the private helpers `Raised` L214, `Noticed` L241, `Answered` L255, `NoticeSessionOf` L269 and `Unchanged` L277 (lifted to `Case` by this story).
- `Test/Contract/Mock.cls`: `LogMark` L365, `LogSince` L378.
- `Test/Watch/NoticeText.cls` `TestWithFix` L172. `Test/Msg/Catalog.cls` L19 `NOW` = "2026-10-16T18:20:00Z" and L1233 the UX fixture (read only).
- `Test/Watch/Settle.cls` `At` L35, `TestHold` L87.
- `Test/Fix/DryRun.cls`: `Params` L73, `Ask` L80, `TestTargetsAscendAcrossGroups` L241 (no marks: every group's whole `Seen` is still read).

**Tests whose expectations this story changes (shared surface; verified by reading):**
- `Test/Watch/Incidents.cls` `TestInstanceShared` L300-366: its fourth failure (L347) now starts a later round. "No notification" and "no second request" hold only until that round settles (≥ 10 s). The class doc L21-27.
- `Test/Data/Tables.cls` L498-556: the `Incident` and `FailureGroup` contracts (Lane A's own entries).
- Run unchanged:
  - `Test.Watch.Incidents.TestTrickle` (its later failure lands on an open or unnoticed incident);
  - `Test.Watch.Diagnose`, `Test.Fix.Raise` and `Test.Fix.DryRun` (the first ask now writes marks; with no marks the whole `Seen` is read);
  - `Test.Watch.Notices`, `Test.Watch.Closing`, `Test.Checks.Turns` and `Test.Demo.Production` (lane-b).

## Tasks & Acceptance

**Execution:**
- Task 0 (on the stage's first fresh throwaway; record the results in `## Verification`):
  - (a) The seconds from the second `Fail` to the `approval` Notification in `Test.Fix.Later`. Expected (inference): about 15 (one poll, 10 s quiet, a dry run under 1 s); it sets `WAITLATER` (default 30).
  - (b) The class time of `Test.Fix.Later` on a fresh stack. If the call runs past about 180 s, split the class in two, one test each.
  - (c) The later waiter's `Settle` header and the later `DryRun` lie in the incident's `TraceHeaderId` session.
  - (d) The second `Partner.Send` joins the same group (one incident, `Count` 5).
- `Data/FailureGroup.cls` (V1):
  - Append `AskedFrom` and `AskedTo` (`%String(MAXLEN = 32)`), Storage Values 12 and 13 in that order.
  - Add the instance method `AskedKeys()`: `Settle.Window(..Seen, ..AskedFrom, ..AskedTo)`, or `..Seen` when both marks are empty.
  - Doc: what each mark means (Always, "Windows").
- `Data/Incident.cls` (V1): append `LaterSince` and `AskingSince` (`%String(MAXLEN = 20)`, UTC), Storage Values 27 and 28; doc per Always.
- `Watch/Settle.cls`: `Window(seen, from, to)` (pure):
  - It gives the keys of `seen` after `from` up to and including `to`, comma-separated, in order.
  - `from` empty or not in `seen`: it starts at the first key.
  - `to` empty, not in `seen`, or not after the start: "".
  - Update the class doc.
- `Fix/Kind/RepairResend.cls`: `DryRun` reads each group's `AskedKeys()` instead of `Seen` (L101); update the class doc. Why: AC 1 (a later dry run never re-targets an earlier request's window).
- `Watch/Notice.cls`:
  - Add `KEYLATER` ("incident.laterRequest").
  - `WithFixSlots(incident, Output sc, dryRun = "", count = "", time = "")`: a given count replaces `count` and must be a whole number of at least 1; a given time replaces `time` and must not be empty. Otherwise it refuses in `sc`.
  - Update the class doc. Rule 2: extends the with-fix builder.
- `Watch/IncidentManager.cls`:
  - Parameters: `LATERALARMKEY` ("laterSettle"), `LATERDRYRUNKEY` ("laterDryRun"), `APPROVALKIND` ("approval"), `LOGLATER` ("IncidentManager could not raise the later request of incident ").
  - `Record`/`Batch`: the later-failure rule (Always); `added` = "later" when `LaterSince` went from empty to set on a noticed incident; `Batch` calls `StartLater` for it. `StartLater(incident)` calls `Start(ref, incident.TraceHeaderId)`; a failed send logs one warning and clears `LaterSince` (save).
  - `Start(ref, session = "")`: `%SessionId` := session for the send. `Begin`: a `NoticeCount` already set goes to `Later(ref)`.
  - `OnResponse`: `LATERALARMKEY` → `Later`; `LATERDRYRUNKEY` with a `DryRunResult` → `Proposed(ref, callrequest, callresponse, 1)`. `OnError`: `LATERDRYRUNKEY` → `Unproposed(ref, text, 1)`, OK.
  - `Later(ref)` and `AskLater(incident)` per Always. The seam `LaterAlarm(seconds)` = `SetTimer(Settle.Alarm(seconds), LATERALARMKEY)`.
  - `Ask(incident, kind, parameters, key)`, shared by `Propose` and `AskLater`: it moves the marks, saves them with the incident in one transaction, then sends through `SendDryRun(ask, key = DRYRUNKEY)`.
  - `Proposed(ref, ask, result, later = 0)` and `Unproposed(ref, error, later = 0)`: the first-request route is unchanged except for two things. The raise route starts the later waiter after `Deliver` when `LaterSince` is set, and `NoFix` clears `LaterSince`. The later route is per Always. Every early exit clears `AskingSince` through `Unask(incident)` (a plain save; a failure logs one warning).
  - `Notification(incident, kind, key, slots, approvalRef)`, lifted from `Deliver` and used by both routes.
  - Update the class doc (a later-requests bullet).
  - Why: AC 1-4 and AC 6.
- `Test/Watch/IncidentProbe.cls`:
  - Override `Start`, which records `{ref, sessionId}` in `Started`, and `LaterAlarm`, which records seconds in `Alarms`. `SendDryRun` also records the `key`.
  - Add the helpers `Wake(ref)` (`OnResponse` with `LATERALARMKEY`), `LaterDried(ref, ask, result)` and `LaterUndried(ref, error)`.
  - Update the doc.
- `Test/Watch/Case.cls`:
  - Lift `Raised`, `Noticed`, `Answered` and `NoticeSessionOf` from `Test.Fix.Raise` (Rule 2), with the parameters they read (`WAITHOLD`; the order count becomes `Raised`'s trailing argument, default 3). `Raise` calls them.
  - `Listed(payload, index = 0)` reads the index-th request.
  - Update the class doc.
- `Test/Watch/Settle.cls` `TestWindow` (pure): the first ask (`from` ""), a later window, an empty window (`from` = `to`), `from` trimmed out of `seen`, `to` trimmed, and `to` "".
- `Test/Watch/NoticeText.cls` `TestLaterRequest` (AC 5, pure):
  - The row's `FixSummary` is "repair and resend all 3". `WithFixSlots(row, .sc, dryRun{resend 3, field "order date", before "10/16/2026", after "2026-10-16"}, 3, "2026-10-16T18:20:00Z")`.
  - `RenderAt("incident.laterRequest", slots, "telegram", "2026-10-16T18:20:00Z", 1)` equals the UX fixture text of `Test.Msg.Catalog` L1233 exactly, and `web` equals its `web` text.
  - A count of 0 and an empty time are refused.
- `Test/Watch/Tell.cls` (probe, warm). Fixture: `Setup`, `Group` with `Seen` "h101,h102,h103" and `AskedTo` "h103", and R1 from `Fixture.Approval` with `FixKind` repair_resend, `PARAMETERS` and `FixTargets` "101,102,103". Failure times are 2 minutes ago, so the rule has ended.
  - `TestLaterRequestToEachWatcher` (AC 1-3): every step of the "Later request, awaiting" row on the probe, with no warning logged.
  - `TestLaterRequestStates` (AC 3, AC 6): resolved becomes awaiting_approval, while each open variant only counts (no `Started`, `LaterSince` empty).
  - `TestOneAskAtATime`, `TestStragglersOfTheFirstAsk`, `TestStillGathering` (an alarm of the remaining seconds), and `TestLaterNoRequestRoutes` (V2: every logged or dropped row).
  - `TestSaveFailureCancelsTheLaterRequest` (`FailMove`).
- `Test/Watch/Lifecycle.cls` `TestLaterRequestWhileFixing` (AC 4, probe, warm): the "Fixing" row. R2's row is made with `Fixture.Approval` and given to the probe as `RaiseRef`, so `Outcome` and `Result` find it.
- `Test/Fix/DryRun.cls` `TestAskedWindow` (fresh):
  - 5 real failed orders in one group's `Seen`. Marks `AskedFrom` = the 2nd key, `AskedTo` = the 4th: the targets are the 3rd and 4th ids, `affected` 2.
  - Marks "" and the 2nd: the first two ids.
  - `from` = `to`: the `Reason` "no failed message of its scope".
- `Test/Fix/Later.cls` (new; extends `Test.Watch.Case`; throwaway, fresh; class doc per Rule 14):
  - `TestLaterFailuresGetTheirOwnRequest` (AC 1, 2, 3; Integration). `Raised("later", …)`, then `LogMark`, then `Fail(2, S's TraceRef)`, `WaitFailed(5)`, and a wait up to `WAITLATER` for 2 requests. It asserts the whole "Later request, awaiting" row:
    - the render prefix "2 more orders failed since " and the exact Dry run paragraph;
    - `AssertDelivered(a, "approval", R2)`, `Listed(…, 1)` on the event and on `StateIncident`;
    - 2 `DryRun` headers in the trace session (`HeadersBetween`), the hold in the session (`HoldInSession`), `LogSince` with no `POST /v1/messages`.
    - Then it runs the "Later rejected while R1 pending" row.
  - `TestOpenIncidentOnlyCounts` (AC 6): `Raised`, then reject R1 (open `rejected`), then `Fail(2)`. `WaitCount(ref, 5)` and one more `incident` event; `LaterSince` empty. After `quiet` + 3 s: one request, no `approval` Notification, one `DryRun` header.
  - The incidents, requests and holds go with `DropIncidentRows`.
- `Test/Fix/Raise.cls`: use `Case`'s lifted helpers; behaviour unchanged.
- `Test/Watch/Incidents.cls` `TestInstanceShared` and its doc:
  - After the fourth failure: R1's `FixTargets` unchanged and `LaterSince` = the fourth failure's time.
  - Keep "no notification and no second request yet" (well within the 10 s settle).
- `Test/Data/Tables.cls` (Lane A's own entries): `Incident` gains `LaterSince` and `AskingSince` `%String(MAXLEN=20)`; `FailureGroup` gains `AskedFrom` and `AskedTo` `%String(MAXLEN=32)`.

**Acceptance Criteria:**
- AC 1: Given an incident awaiting approval, fixing or resolved whose request R1 holds fixed targets, when same-cause failures join it, then R1's `FixTargets`, `DryRun` and state never change, and once the failures settle by the same rule (`Settle.Wait` from the first of them), `FixExecutor` is asked for a dry run of only those failures, and one new request R2 of the same kind and parameters is raised over them alone and appended to `RequestRefs`. The mock logs no request.
- AC 2: Given R2 is raised, when the notice goes out, then each recipient session gets exactly one Notification of kind `approval` with `incident.laterRequest`, R2's `ApprovalRef`, the incident's Ref and the slots of the new failures and their own dry run (`count`, `time` = the first of them, `resendCount` = R2's `DryRun.resend`), which renders "{count} more {itemNoun} failed since {time}, with the same cause. …". `WebChatOut` records an `approval` Delivery row with R2's Ref, and the `incident` event and `/state` list R1 and R2 (Integration AC).
- AC 3: Given R2 is raised, when the table applies `raised`, then `awaiting_approval` stays `awaiting_approval` (and a rejection of R2 while R1 is pending keeps it there, with R2's `answered.rejected`), `fixing` stays `fixing`, and `resolved` becomes `awaiting_approval`.
- AC 4: Given the incident is fixing with R1's run, when R2 is approved, then no `Execute` is sent; when R1's final `FixResult` arrives, exactly one `Execute` goes out, for R2, in the incident's trace session; and R2's own final `FixResult` resolves the incident. R2's `FixRun` row is Story 7.3's `Execute` (V3).
- AC 5: Given the UX fixture slots, when the later-request entry of `OcuTalon.Msg.Catalog.Watch` renders the slots that `Notice.WithFixSlots` builds, then the text is "3 more orders failed since 14:20 ET, with the same cause. I can repair and resend all 3. Approve?", then its own "Dry run:" paragraph and "Details and trace: on your OcuTalon page."
- AC 6: Given an open incident (fallback, no fix, rejected or expired), when same-cause failures join it, then only its count and its `incident` event change: no waiter, dry run, request or Notification.

### Review Findings

Code review, 2026-10-28. Tier full-opus (no `model-overrides.yaml`). Layers: blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, all of which ran. 22 raw findings grouped into 11 entries (high 1, med 5, low 5); 8 rejected. Patches applied: 7. Deferred to the ledger: 4. Decision-needed: 0.

**The lead's item (a failed later round's lost window): agreed and patched.** AD-15's Rule reads: "Same-cause failures that arrive after the notice and that no request covers settle by the same rule, then get their own dry run and their own approval request". The spine's "Later requests" row adds that a failure "is never lost". V2 (U-133) rules only what such a round sends.
- Error routes now put the marks back (`AskedTo := AskedFrom`), so the round's failures are in the next round's window. The error routes are: the ask not sent, an error answer, an unusable dry run or slots, a failed `Raise`, and a request cancelled after a failed save.
- A refused dry run, an empty `Targets` and an open incident keep their marks, because those failures were judged. So does a request that was raised and could not be cancelled, because it still holds the window.
- Residual: with no further failure, nothing re-asks. This is the same shape as residual risk 2 (a failed `StartLater`), and V2 accepts that the round sends nothing. A retry needs new state, which V1 rules out.

- [x] [Review][Patch] **HIGH**: a later round that failed after its marks moved left its failures in no window forever; QA's probe pinned it. [`Watch/IncidentManager.cls` `Unask`, `Decline`, `AskLater`, `Unproposed`, `Proposed`] (blind+edge+gap)
  - Fix: `Unask(incident, unmark)` puts each group's `AskedTo` back to `AskedFrom` in one transaction with clearing `AskingSince`. It acts only while `AskingSince` is stored, which proves the ask's marks were saved and nothing moved them since. A round that gathers meanwhile takes the earlier time (`LaterSince := AskingSince` when that is earlier).
  - Tests: QA's probe is replaced by `Tell.TestFailedLaterRoundRejoinsTheNextRound`, with eight cases: five restored, two judged, and uncancelled. The probe gained `FailCancel`.
  - fix-risk med: product error routes only; the first-request route is unchanged. Footprint in-story.
- [x] [Review][Patch] MED: `Incidents.TestInstanceShared` asserted transient state (`LaterSince`, no notification, one request) with no guard. On a slow run past the 10 s quiet time it fails a correct product. [`Test/Watch/Incidents.cls` `TestInstanceShared`] (edge+gap)
  - Fix: the three assertions are made only if `Settle.Wait` still says, after the reads, that the round's rule was running, as `Later` does. R1's targets are asserted always.
  - fix-risk low: test only. In-story (Rule 19 hermeticity).
- [x] [Review][Patch] MED: AC 1's "R1's `FixTargets` and `DryRun` never change" was checked only before the later round. A later route that rewrote R1 stayed green; M5 showed it. [`Test/Watch/Tell.cls` `TestLaterRequestToEachWatcher`, `Test/Fix/Later.cls`] (gap)
  - Fix: R1 is read again after R2 in both tests.
  - fix-risk low. In-story.
- [x] [Review][Patch] LOW: the probe's `Marks` opened the groups that `Ask` still held in memory, so "the marks were saved before the send" could not catch a set-in-memory, send, then save order. M4 confirmed it: green with the old probe, red with the new one. [`Test/Watch/IncidentProbe.cls` `Marks`] (blind)
  - Fix: `Marks` reads the marks by SQL.
  - fix-risk low. In-story.
- [x] [Review][Patch] LOW: "the mock logged no request" passed when the mock's log was missing. [`Test/Fix/Later.cls` `TestLaterFailuresGetTheirOwnRequest`] (gap)
  - Fix: the test asserts `LogMark() > 0`, which holds because R1's diagnosis is in the log.
  - fix-risk low. In-story.
- [x] [Review][Patch] LOW: two assertion messages claimed a window check while comparing the probe's canned targets. [`Test/Watch/Tell.cls` `TestOneAskAtATime`, `TestStragglersOfTheFirstAsk`] (gap)
  - Fix: reworded; the window is pinned by the marks assertions.
  - fix-risk low. In-story.
- [x] [Review][Patch] LOW: `Watch.Msg.Settle`'s class doc named only the first settle waiter. [`Watch/Msg/Settle.cls`] (blind)
  - Fix: the doc now names the later waiter too, sent in the incident's trace session.
  - fix-risk low. In-epic (Watch).
- [x] [Review][Defer] MED, unverified (maybe-false): a later request reuses the first diagnosis's `fixSummary`. A count that a live model writes into it, like the UX fixture's "repair and resend all 50", would contradict the round's own count and resend. [`Watch/IncidentManager.cls` `Proposed`; `Agent/Diagnosis.cls`] (blind; the implement triage said maybe-false)
  - Deferred: a live diagnosis would settle it. The mock's summary has no count. The fix is a product or UX call: a count-free prompt rule (which changes the first notice's UX shape) or other later text.
  - **DW-365** `decision-pending` owner=burndown, note=human. fix-risk med.
- [x] [Review][Defer] MED, theoretical: a later ask that is never answered leaves `AskingSince` set, and every later round of the incident re-checks every quiet seconds until it closes. [`Watch/IncidentManager.cls` `Later`] (edge)
  - Same root cause as **DW-345** (a dry run that `FixExecutor` never answers; residual risk 1). An occurrence was appended; DW-345 stays `wontfix-theoretical`.
- [x] [Review][Defer] MED: more than `SEENMAX` (1000) failures joining during one ask trims `AskedTo` out of `Seen`, so the window reads empty. [`Watch/Settle.cls` `Window`, `Data/FailureGroup.cls` `AskedKeys`] (edge)
  - The `SEENMAX` cap is **DW-318**'s (routed to 7-4-ocutalon-reports-how-many-orders-went-through). An occurrence was appended.
- [x] [Review][Defer] LOW: the spine's Conventions row "Later requests" names only incidents awaiting approval, fixing or resolved. It misses the stragglers of the first ask and the failed round's failures rejoining the next window. [`ARCHITECTURE-SPINE.md` Conventions] (auditor)
  - The spine is the lead's (Rule 20 light path).
  - **DW-366** `wontfix-accepted`, reopen_if in the note.

**Rejected:**
- `low` (blind) The first request's window includes failures that joined during the diagnosis, so the first notice's count (`NoticeCount`) can be below its dry run's resend.
  - The fix edits the spec's Always "Windows" bullet: the first window ends at the ask, a Decided in-stage choice. The count/resend shape is 7.2's first notice (pre-existing), and this story narrowed it. UJ-1's burst settles before the diagnosis.
- `low` (edge) Incidents noticed before 7.6 have no `AskedTo`, so their later failures only count.
  - No release has shipped; V1's reversal says "no row has them yet". The fix is a migration.
- `low` (edge) A failed `StartLater` send whose `Unlater` save also fails strands `LaterSince`.
  - This needs two infrastructure failures in a row, and the fix adds guards.
- `low` (edge) An exception between a successful `Raise` and `Move` leaves an unlisted pending request.
  - Nothing between them throws in practice, and it is 7.2's shape. `IncidentManager` refuses outcomes for unlisted requests, and the patched catch keeps the marks when a request was raised.
- `low` (edge) After a restore, a round with no gathering round takes its own first failure as `{time}`.
  - Spec-bound by residual risk 2 ("whose `{time}` is then that round's own"). The patch already gives the earlier time to a round that gathers during the failed ask.
- `low` (edge) `NoticeText` sets TZ to "" when it was undefined.
  - This is the same restore as `Test.Msg.Catalog`. `TimeZone` has no unset, and the throwaway's default zone is UTC.
- `low` (auditor) `Unproposed` logs the warning of an error answer even for a stale or gone later ask.
  - The warning carries `FixExecutor`'s own error, which is real whatever became of the incident. 7.2's route and `Refused` log the same way. The matrix's "no error" is the handler's status, and it is OK.
- `low` (auditor) The residual-risk numbering differs between Design Notes, the QA notes and the Auto Run Result.
  - The fix edits the spec under review.

**Rule checks:**
- Rule 3: `Test.Fix.Later` runs the deliverable in its real runtime: the production on a throwaway, with the real poller, `FixExecutor`, `Raise`, hold and `WebChatOut`. It asserts the Delivery row and the `/state` body. No web code changed; the card is Epic 6's.
- Rule 6: AC 1 to AC 6 were checked against AD-1, 5, 11, 12, 13, 15, 16, 22, 26, 29, 32 and 33 and the Conventions row. The one mismatch was AD-15's "that no request covers", which the first patch fixes.
- Rule 2: no unjustified copy.
- Rule 1: AC 2 is the Integration AC.
- Rule 5: no NFR workaround.
- Rule 14: no non-ASCII bytes in the added lines.

## Spec Change Log

- 2026-10-28, spec gate (lead): V1, V2 and V3 ruled as veto items U-132, U-133 and U-134 (kept as planned; V3 moves the `FixRun` row pin to Story 7.3 in `epics.md`); the spine gains the Conventions row "Later requests". Nothing else in the plan changed.

## Review Triage Log

### 2026-10-28 — Review pass
- verdicts: 32 findings — high 0, medium 7, low 19, false 5, maybe-false 1
- findings:
  - `[low]` `[reject]` Marks are never restored when a later round fails (send, raise or save error, error answer, refused or empty dry run), so its failures are in no window (blind, edge) — a refused or empty dry run is V2's specified end state, and the error paths are infrastructure failures that log one warning; restoring needs state beyond a direct correction and changes the pinned end state (Design Notes, residual risks 1 and 2 carry the same shape). reopen_if: a refused or failed later round is seen in a live run leaving failures that no request covers.
  - `[low]` `[reject]` `AskingSince` can stay set (a non-result answer; a restart between the ask's commit and its send) and the waiter re-checks every quiet seconds (blind, edge) — the answer to a dry run is always a `DryRunResult` (`Fix/Executor.cls` DryRun "Always OK"), and a lost ask is residual risk 1 (DW-345, theoretical; 7.5's sweep). reopen_if: an incident is seen with `AskingSince` older than the ask timeout.
  - `[low]` `[reject]` Nothing caps the later requests of one incident (blind) — one request per settled round is AC 1; a cap or merge is a product call. reopen_if: a demo run shows a stream of later requests for one incident.
  - `[low]` `[patch]` `Later` returns the raw `%Save` status of an open incident (blind, intent) — now `Unlater` and `Quit $$$OK`, as every other clear; pinned by `Tell.TestLaterWakeEnds` (open).
  - `[low]` `[reject]` `AskLater` logs one text for a missing row, a foreign row and an empty kind (blind) — cosmetic: one warning that names the incident, and the tests assert exactly one.
  - `[medium]` `[patch]` Several new branches have no test (blind) — the open branch and the no-newer-key branch of the wake are now pinned (`Tell.TestLaterWakeEnds`), the marks-before-send order too; the rest (`Windowed` 0, `Unask`'s read failure, the `Begin` routing that `Later` exercises in production) is theoretical or already covered by the production test.
  - `[low]` `[reject]` `Raised` no longer follows `Raise.ORDERCOUNT` (blind, edge) — the spec makes the count `Raised`'s trailing argument with default 3; `ORDERCOUNT` still drives `Raise`'s own test.
  - `[false]` `[reject]` `NoticeText.OnAfterOneTest` skips a parent's cleanup (blind) — `%UnitTest.TestCase` defines none, and `Test.Msg.Catalog` restores its zone the same way.
  - `[low]` `[reject]` (edge) the same root cause as the first row: marks never restored.
  - `[low]` `[reject]` (edge) the same root cause as the second row: `AskingSince` stuck.
  - `[low]` `[reject]` A failed `LaterAlarm` or a throwing `Later` leaves `LaterSince` set and no waiter starts again (edge) — an alarm that cannot be set is an infrastructure error with the framework's own log, and the first settle waiter has the same shape. reopen_if: such an error is seen in a log.
  - `[maybe-false]` `[reject]` The later slots reuse the first diagnosis' `fixSummary`, which may name the first round's count (edge) — `Agent/Diagnosis.cls` defines it as the words that complete "I can ..." and the mock's is count-free; what a live model writes could settle it, and the harm would be low (one sentence).
  - `[low]` `[reject]` (edge) the same root cause as the `ORDERCOUNT` row.
  - `[false]` `[reject]` The claim that every early exit of the later route clears `AskingSince` (edge) — the one exit that does not is an answer that is not a `DryRunResult`, which `FixExecutor` never sends.
  - `[medium]` `[patch]` `Later`'s open branch is never executed by a test (gap) — `Tell.TestLaterWakeEnds` case open (mutation: the branch removed → red).
  - `[low]` `[patch]` The wake of a deleted incident and a window with no newer key have no test (gap) — `Tell.TestLaterWakeEnds` cases gone and nonewer; the foreign-request guard stays untested (it only widens "missing").
  - `[low]` `[patch]` The `Later.*` integration tests had no observed red (gap) — three mutations run and recorded under Verification (open, session, count).
  - `[medium]` `[patch]` `Later.TestOpenIncidentOnlyCounts` takes its baselines before the rejection's side effects are out (gap) — it waits for the answered Notification and the open incident event first.
  - `[medium]` `[patch]` One later waiter per round is not pinned (gap) — `Tell.TestStillGathering` joins a second batch (mutation: `laterWas` ignored → red).
  - `[medium]` `[patch]` `TestStillGathering` cannot tell `LastAt` from `LaterSince` (gap) — failures nine and two seconds old; the alarm must be 6 to 8 s (mutation: `LaterSince` for both → red).
  - `[medium]` `[patch]` The marks-before-send order is not pinned (gap) — the probe records the level and the stored marks at the send; `TestLaterRequestToEachWatcher` asserts them (mutation: send above `TSTART` → red).
  - `[low]` `[reject]` Some assertions are labelled as window checks but compare a canned result (gap) — the window is pinned by the marks assertions and `DryRun.TestAskedWindow`.
  - `[medium]` `[patch]` The open-incident `Wake` assertion in `TestLaterRequestStates` is vacuous for `Later`'s open branch (gap) — the same root cause as the open-branch row; pinned by `TestLaterWakeEnds`.
  - `[low]` `[reject]` The "at once" block of `Later.TestLaterFailuresGetTheirOwnRequest` asserts transient states (gap) — the poller's `CallInterval` is 3 s and the quiet time 10 s, so the block has about 5 s of margin; Task 0 measured 10.6 s to R2. reopen_if: a CI red at "one request" or "the new count has an incident event" in `Later`.
  - `[low]` `[reject]` `Quit` in the inner `While` loops of `TestLaterRequestStates` leaves only the loop (gap) — error paths of a failed `Setup` or `Host` only.
  - `[low]` `[reject]` No test joins failures out of time order, so "min" and "first" are the same (gap) — the poller sends ascending stamps; unlikely.
  - `[false]` `[reject]` The tests assert on the probe, not the production (intent) — the spec puts the matrix rows on the probe and the integration on `Test.Fix.Later`, which runs the real production (mutations: session, open).
  - `[false]` `[reject]` A non-`DryRunResult` answer leaves `AskingSince` (intent) — the same as the `FixExecutor` row above.
  - `[low]` `[reject]` Nothing times `AskingSince` out (intent) — residual risk 1 (DW-345; 7.5).
  - `[low]` `[patch]` `Later` returns the `%Save` status of an open incident (intent) — the same root cause as the fourth row.
  - `[low]` `[reject]` The first-answer routes that raise nothing and send no notice leave `LaterSince` set on an unnoticed incident (intent) — those routes leave the incident unnoticed (7.2's behaviour), and an unnoticed incident gets no later round.
  - `[false]` `[reject]` The first request that names another incident is treated as missing (intent) — Design Notes "Decided in-stage": such a row is not the incident's first request.

## Design Notes

**V1. Where the later rounds live (schema change, veto window; the lead rules it).**
- **Chosen:** four appended stored properties on Lane A's tables (AD-33): `FailureGroup.AskedFrom` and `AskedTo` (Values 12-13), and `Incident.LaterSince` and `AskingSince` (Values 27-28).
  - The marks fix each ask's window in IncidentManager's one job, before the ask goes out, so `FixExecutor` reads exactly it. A failure is never in two requests, and a failure that joins during an ask is never lost.
  - `LaterSince` is the gathering round's first failure, which drives the settle rule and the `{time}` slot (UX: "`{time}` is the first of the new failures").
  - `AskingSince` keeps the asked round's `{time}` while the next round gathers, and marks an ask on its way.
- **Rejected:**
  - New properties on `Fix.Msg.DryRun`/`DryRunResult`: AD-16 lists their properties, so that would be an AD amendment.
  - A failure group per round: it splits one cause into several groups, and changes 5.8's `groups` slot and `Find`.
  - Key sets instead of marks: the same number of properties, and an empty window loses its end.
  - One JSON column: opaque to tests and to SQL.
  - Properties on the IncidentManager BP: AD-5 keeps its state in rows.
- **Reversal:** stop writing the four. The properties stay empty (append-only), the dry run reads the whole `Seen` again (7.1's behaviour), and later failures only count (5.8's). No migration: no row has them yet.

**V2. A later round that cannot raise a request (a public-behaviour edge, veto window).** This covers a refused dry run, nothing to resend, a failed `Raise`, an ask not sent and unbuildable slots.
- **Chosen:** send nothing, and log one Type 3 warning for an error. The incident's count has already reached every recipient through the `incident` event, and the page shows it.
- **Rejected:** the no-fix notice. It is defined for an un-noticed incident only (the table refuses `notice` on a noticed one), and new text would be public text that is not in the UX.
- This matches 7.2's route for the first request in spirit (U-127: no new text).

**V3. "Each approved request gets its own `FixRun`" (an AC move, veto window; flagged, not decided).**
- `FixRun` rows are written by `FixExecutor`'s `Execute` (AD-16), which is Story 7.3's (`STUB = 1` until then).
- This story delivers and pins `IncidentManager`'s half: one `Execute` per approved request, one at a time, the earliest waiting next (AC 4).
- **Proposed:** move the `FixRun` row half to Story 7.3, as an added acceptance pin: "two approved requests of one incident make two `FixRun` rows, each with its own `ApprovalRef`". It is not on a release gate: UJ-1 has one request.

**Spec gate rulings (lead, 2026-10-28; policy 6df0676):**
- V1 (schema): ruled `veto`, inbox U-132, kept as planned (the four appended properties). The spine's Conventions row "Later requests" records the window marks and the round state (Rule 20 light path).
- V2 (a later round that cannot raise a request sends nothing, one warning for an error): ruled `veto`, inbox U-133, kept as planned.
- V3 (the `FixRun` row per approved request): ruled `veto`, inbox U-134: moved to Story 7.3 as an added acceptance criterion in `epics.md` ("two approved requests of one incident make two `FixRun` rows, each with its own `ApprovalRef`"); Story 7.6's criterion carries the `[AMENDED]` marker. This story pins `IncidentManager`'s half (AC 4).

**Decided in-stage (small, reversible, within the intent):**
- Completion keys `laterSettle` (alarms) and `laterDryRun` (the ask) tell the later waiter's events apart from the first waiter's. The mode of `Begin` comes from the row: `NoticeCount` is set.
- The later waiter joins the incident's trace session, like `Execute` does (L768-771). AD-26 gives each incident chain one session. The first waiter still starts the session.
- The kind and parameters of a later ask come from the incident's first request row: the same cause gives the same fix. U-126 holds per request, because each row is built from its own ask and answer.
- The first dry run's window is now `Seen` at the time of the ask, not at `FixExecutor`'s read. A failure that joins in between becomes the first later round instead of riding into the first request unseen.
- Failures that join after the first ask but before its answer (stragglers) are later failures. They become a later round only if the first request is raised. AD-15's "after the notice" read so that no failure falls between two windows.
- `count` is the number of keys in the round's windows, as the first notice's count is `NoticeCount`. The later notification also carries `cause` (an undeclared slot the catalog ignores), because it reuses `WithFixSlots` (Rule 2). Its `DecisionRef` is the incident's.
- One ask at a time per incident. A round that settles while another ask is on its way re-checks every `quiet` seconds.
- A later answer that arrives when `AskingSince` is empty is stale and dropped.
- Decided in-stage (implement):
  - `WithFixSlots(incident, .sc, dryRun, count, time)` declares `count` and `time` without defaults and tests `$Data`: an argument that is passed counts as given, also when it is empty (so an empty time is refused, as the matrix asks), and one that is left out does not. With `= ""` defaults the two cases could not be told apart.
  - `Unask` reads the incident again before it clears `AskingSince`, so that a change the caller made and did not save (the appended request of a failed save) is never saved with it. A failed `Ask` in `AskLater` also clears `LaterSince`: when the marks' transaction rolled back, the stored `LaterSince` would otherwise stay set and no later waiter would start for further failures.
  - `AskLater` also treats a first-request row that names another incident as missing.
  - `IncidentProbe` gets `FailStart` (a refused waiter send) so that `StartLater`'s warning and its clearing of `LaterSince` are tested (`TestLaterNoRequestRoutes`, case `start`).
  - `Case.Incidents` also gives `laterSince` and `askingSince`; `Tell.Group` and `Lifecycle.Group` take the `Seen` set and the marks as optional trailing arguments.
  - `NoticeText.TestLaterRequest` sets the process zone to America/New_York (as `Test.Msg.Catalog` does) and puts it back in `OnAfterOneTest`, because the UX fixture's "14:20 ET" is the zone's rendering of 18:20Z.
- Decided in-stage (review): `Later` clears `LaterSince` of an open incident through `Unlater` (a failed save is one warning, never an error status). `IncidentProbe.SendDryRun` records the transaction level and the stored marks at the moment of the send, so the marks-before-send order is pinned. `Tell.TestLaterWakeEnds` pins the wake that ends without an ask (open, gone, no newer key). `Later.TestOpenIncidentOnlyCounts` takes its baselines after the rejection's answered Notification and incident event are out.

**Governing ADs:**
- AD-1: items by name.
- AD-5: rows and persisted waiters are the state; append-only storage; alarms ≤ 120 s.
- AD-11: `Raise`, the row is the truth, a cancel sends no outcome.
- AD-12: the full view after the commit; `Requests` lists every request.
- AD-13: `FromRow` and `OfIncident` use no SQL.
- AD-15: the later-request bullet, the transition table and one writer.
  - "One instance per new failure group" stays true for first settles. A later round gets its own waiter because its rule is "the same rule".
- AD-16: the stored dry run, the executor trusts the row, and `FixRun` per run (V3).
- AD-22: throwaways and the mock log. AD-26: the incident's trace session. AD-29: Lane A.
- AD-32: kind `approval` only for a later request; slots only. AD-33: the tables' owner.

Conventions: "Incident notice", "Approval requests", "Times", "Messages", "Redaction".

**Integration ACs, Consumes, Consumed-by (Rules 1 and 2):**
- **Integration ACs (AC 2):**
  - `WebChatOut` records the `approval` Delivery row with R2's Ref.
  - `Catalog.Render` of the received slots gives the later-request text.
  - `/state` (`Web.Api.StateBody`) and the `incident` event list R1 and R2.
  - The real hold of R2 sends the rejection that `IncidentManager` turns into R2's answered notice.
- **Consumes:**
  - 7.2: `Propose`, `Proposed`, `NoFix`, `Deliver`, `Move`, `Tell`, `RequestRefs`, and the row's `FixKind`, `FixParameters` and `FixTargets`.
  - 7.1: `FixExecutor`'s dry run and `RepairResend.DryRun`.
  - 5.5: `Transitions`, `Facts`, `Apply`, `Execute`. 5.3: `Record`, `Settle`, the waiter.
  - Epic 6: `WebChatOut`, `SimPhoneOut` and the card for kind `approval`.
  - Epic 0: `incident.laterRequest`.
- **Consumed-by:**
  - 7.3: `Execute` per approved request, its `FixRun` (V3), and `Recheck` against each row's own `FixTargets`. A copy that fails again must never reach `Record` as a later failure (AD-15).
  - 7.4: the result per request. DW-318's `SEENMAX` cap also bounds a window when more than 1000 failures join during one ask.
  - 7.5: one final `FixResult` per run, each request's own.
  - Epic 6: the second request card. Lane B's Telegram: Approve and Reject on kind `approval`.

**Extend, don't copy (Rule 2):**
- `Start` gains a session argument.
- `Propose` and `AskLater` share `Ask`.
- `Proposed` and `Unproposed` gain a `later` flag instead of a sibling copy.
- `Notification` is lifted out of `Deliver`.
- `WithFixSlots` gains `count` and `time` (no `LaterSlots`).
- `SendDryRun` gains a key.
- `Window` sits beside `Settle.Hold`, and `AskedKeys` is shared by `RepairResend` and `IncidentManager`.
- `Later` is `Check`'s counterpart with a different end (an ask, not a diagnosis). It shares `Settle.Values`/`Wait`/`Alarm` and is a separate method because `Waiting` and `NoticeCount` do not apply.
- Tests: the probe tests extend `Tell` and `Lifecycle`. `Raised`, `Noticed`, `Answered` and `NoticeSessionOf` are lifted from `Raise` into `Case`, and `Listed` gains an index.

**Ledger inbox:** none.

**Residual risks:**
1. An ask that is never answered (DW-345, theoretical) leaves `AskingSince` set, and later rounds of that incident re-check every `quiet` seconds until it closes.
2. A failed `StartLater` send (theoretical) clears `LaterSince`. Those failures join the next round's window, whose `{time}` is then that round's own.
3. The `SEENMAX` cap (DW-318, 7.4's).

**Footprint:** `Data/{Incident,FailureGroup}.cls` (Lane A tables), `Watch/**`, `Fix/Kind/RepairResend.cls`, `Test/Watch/**`, `Test/Fix/**`, and `Test/Data/Tables.cls` (own entries). No contended path.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root.
- Run one command per tool call with `timeout: 600000`, in the foreground, and never two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll such a run to completion in bounded foreground calls before anything else, and never abandon it.
- **Tests run only on throwaways, never on `ocutalon-slot-a`.**
- `IncidentManager`- and `FixExecutor`-driven classes run fresh, because a warm stack's production jobs keep the classes they loaded.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e7s6iw ci/warm.sh up`, once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s6iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Watch.Settle`, `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Watch.Tell`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Watch.Transitions`, `OcuTalon.Test.Data.Tables`. Expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e7s6i ci/iris.sh class <Class>`, fresh, one call per class: `OcuTalon.Test.Fix.Later` (first: Task 0), `OcuTalon.Test.Fix.DryRun`, `OcuTalon.Test.Fix.Raise`, `OcuTalon.Test.Watch.Incidents`, `OcuTalon.Test.Watch.Diagnose`, `OcuTalon.Test.Watch.Notices`, `OcuTalon.Test.Watch.Closing`, `OcuTalon.Test.Checks.Turns`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e7s6i ci/iris.sh shard lane-a --part k/12` for k = 1 to 12, one call each (77 classes took 381, 187 and 428 s in thirds after the integrate-forward). Expected: passed. Record each part's time.
- (once) `<lane> OCUTALON_RUN_TAG=e7s6i ci/iris.sh shard lane-b --part k/3` for k = 1 to 3, one call each. Expected: passed (`Test.Data`, `Test.Demo`, `Test.Live`).
- (once) `<lane> OCUTALON_RUN_TAG=e7s6i ci/iris.sh live storage-roundtrip`. Expected: passed (the two Storage blocks).
- (once) `bash ci/checks.sh`. Expected: every script passes (storage blocks, boundaries, class rules).
- (once) `<lane> OCUTALON_RUN_TAG=e7s6iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e7s6i ci/iris.sh teardown`. Run both also after a failure.

**Shared surfaces:**
- **`Incident` and `FailureGroup` columns:**
  - `Test.Data.Tables` (changed);
  - the `storage-roundtrip` unit and `ci/checks.sh`'s storage checks.
- **Same-cause failures after an ask now start later rounds:**
  - changed: `Test.Watch.Incidents.TestInstanceShared` and its class doc;
  - run unchanged: `TestTrickle`, `Test.Watch.Diagnose`, `Test.Fix.Raise`, `Test.Checks.Turns` and `Test.Demo.Production`.
- **The dry run reads the window of its ask:** `Test.Fix.DryRun` (fixtures without marks still read the whole `Seen`).
- **`IncidentProbe`'s new overrides** (`Start`, `LaterAlarm`) and `SendDryRun`'s recorded key: the existing tests that use it (`Tell`, `Lifecycle`) are unchanged.
- **`Case`'s lifted helpers** and `Listed`'s index: `Raise` (changed to use them), `Diagnose` (unchanged calls).
- Requests that IncidentManager raises are removed with their incidents (`Case.DropIncidentRows`), so `Test.Bridge.Approval`'s instance-wide counts stay its own.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply (Rule 19).** The implement stage applies each one, observes red, reverts byte-identically, and records `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 later round | `Record` never sets `LaterSince` | `Later.TestLaterFailuresGetTheirOwnRequest`, `Tell.TestLaterRequestToEachWatcher` |
| AC 1 window | `RepairResend.DryRun` reads `group.Seen` again | `DryRun.TestAskedWindow`, `Later.TestLaterFailuresGetTheirOwnRequest` (R2's targets) |
| AC 1 no double cover | `Ask` leaves `AskedFrom` empty for a later ask, so R2's window starts at `Seen`'s first key | `Tell.TestLaterRequestToEachWatcher` (the marks), `Later` (R2's targets hold R1's ids) |
| AC 2 kind | the later notice is sent with kind `incident` | `Tell.TestLaterRequestToEachWatcher`, `Later` (`AssertDelivered`) |
| AC 2 Ref | the later notice has an empty `ApprovalRef` | the same |
| AC 2 time | `AskLater` does not move `LaterSince` to `AskingSince` | `Tell.TestOneAskAtATime`, `Later` (`time`) |
| AC 3 states | `Later` ends for `resolved` | `Tell.TestLaterRequestStates` |
| AC 4 waits | `Apply` executes `OWN` for `approved` while fixing | `Lifecycle.TestLaterRequestWhileFixing` |
| AC 5 | `WithFixSlots` ignores a given count | `NoticeText.TestLaterRequest` |
| AC 6 | `Record`'s later rule ignores the open-and-noticed check, and `Later` does not end on open | `Later.TestOpenIncidentOnlyCounts`, `Tell.TestLaterRequestStates` |
| one ask | `Later` ignores `AskingSince` | `Tell.TestOneAskAtATime` |
| stragglers | the raise route does not call `StartLater` | `Tell.TestStragglersOfTheFirstAsk` |
| V2 | a later `Reason` keeps `AskingSince` | `Tell.TestLaterNoRequestRoutes` |
| trace | `StartLater` starts the waiter with session "" | `Tell.TestLaterRequestToEachWatcher` (`Started`), `Later` (`HeadersBetween`) |
| window arithmetic | `Window` includes `from` | `Settle.TestWindow` |

**Task 0 results (implement stage, first fresh throwaway, tag `e7s6i`):**
- (a) About 10.6 s from the second `Fail` (after it was sent) to R2 listed on the incident (`WaitFailed(5)` included), measured once with a temporary assertion; the approval Notification follows in the same second. Below the inference of 15 s, because the quiet time runs from the failures' own time, not from the poll. `WAITLATER` stays 30.
- (b) `Test.Fix.Later` on a fresh stack: 52.9 to 54.8 s of class time over five runs (135 to 149 s for the whole call, 82 to 96 s of it the stack start). No split.
- (c) The incident's `TraceHeaderId` session holds 2 `Settle` request headers (the first waiter's and the later waiter's), 2 `DryRun` headers to `FixExecutor`, and R2's `ApprovalStart` (`HoldInSession`). `Later` asserts all three.
- (d) The second `Partner.Send` joins the same group: one incident, `Count` 5, `NoticeCount` 3, exactly two requests.

**Loop results (implement stage):**
- Warm (`e7s6iw`): `Test.Watch.Settle`, `NoticeText`, `Tell` (15.4 s), `Lifecycle`, `Transitions`, `Test.Data.Tables` passed.
- Fresh (`e7s6i`), class time: `Test.Fix.Later` 52.9 s, `DryRun` 4.5 s, `Raise` 61.2 s, `Test.Watch.Incidents` 106.6 s, `Diagnose` 44.2 s, `Notices` 27.7 s, `Closing` 29.2 s, `Test.Checks.Turns` 8.8 s: all passed.
- The static `test-class-rules.sh`, `test-storage.sh` and `test-boundaries.sh` pass. The `(once)` lines are the parent's.

**Pinning mutations applied (Rule 19), each observed red and reverted byte-identically (md5 of the file equals its backup):**
- mutation: `Record` never sets `LaterSince` (`If later && ...` made `If 0 && ...`) → red: `Tell.TestLaterRequestToEachWatcher`, `TestLaterRequestStates`, `TestStragglersOfTheFirstAsk`, `TestStillGathering`, `TestLaterNoRequestRoutes`, `TestOneAskAtATime` and `TestSaveFailureCancelsTheLaterRequest`.
- mutation: `RepairResend.DryRun` reads `group.Seen` again (fresh stack) → red: `DryRun.TestAskedWindow` (all five of its checks).
- mutation: `Ask` sets `AskedFrom` to "" instead of `AskedTo` → red: `Tell.TestLaterRequestToEachWatcher` (the marks) and `TestOneAskAtATime`.
- mutation: the later notice is sent with kind `incident` → red: `Tell.TestLaterRequestToEachWatcher`.
- mutation: the later notice has an empty `ApprovalRef` → red: `Tell.TestLaterRequestToEachWatcher`.
- mutation: `AskLater` sets `AskingSince` to the clock instead of `LaterSince` → red: `Tell.TestOneAskAtATime`, `TestLaterRequestToEachWatcher` and `TestLaterNoRequestRoutes`.
- mutation: `Later` ends for `resolved` → red: `Tell.TestLaterRequestStates`.
- mutation: `Apply` executes `OWN` for `approved` while fixing → red: `Lifecycle.TestLaterRequestWhileFixing` (and `TestApprovalOutcomes`).
- mutation: `WithFixSlots` ignores a given count → red: `NoticeText.TestLaterRequest`.
- mutation: `Record`'s later rule ignores the open-and-noticed check and `Later` does not end on open → red: `Tell.TestLaterRequestStates`.
- mutation: `Later` ignores `AskingSince` → red: `Tell.TestOneAskAtATime`.
- mutation: the raise route does not call `StartLater` → red: `Tell.TestStragglersOfTheFirstAsk`.
- mutation: a later refusal (`Decline`) keeps `AskingSince` → red: `Tell.TestLaterNoRequestRoutes`.
- mutation: `StartLater` starts the waiter with session "" → red: `Tell.TestLaterRequestToEachWatcher` (`Started`), `TestLaterRequestStates`, `TestOneAskAtATime`, `TestStragglersOfTheFirstAsk` and `TestLaterNoRequestRoutes`.
- mutation: `Window` includes `from` → red: `Settle.TestWindow`.
- Every mutated run but the `RepairResend` one was on the warm stack (the probe's shadow instances run in the test process, so a reloaded class takes effect); the `RepairResend` one needed a fresh stack. After the reverts every warm class and a fresh `DryRun` and `Later` passed again. The review pass added the mutations below.

**Review-pass additions (Rule 19), each observed red and reverted byte-identically (md5 of the file equals its backup):**
- mutation: `Record`'s later rule ignores the open-and-noticed check and `Later` does not end on open (fresh stack) → red: `Later.TestOpenIncidentOnlyCounts` ("the incident stays open and no round gathers", "and the dry run was asked once": the quiet time plus 3 s outlasts the regressed round).
- mutation: `Start` sets `%SessionId` to "" instead of the session given (fresh stack) → red: `Later.TestLaterFailuresGetTheirOwnRequest` ("two dry runs went to FixExecutor in the incident's trace session", "and the later waiter's Settle lies in it too").
- mutation: `Windowed` returns `incident.NoticeCount` → red: `Tell.TestLaterRequestToEachWatcher` (the count slot and the rendered text) and `Tell.TestOneAskAtATime`.
- mutation: the open branch of `Later` is removed (`If 0 {`) → red: `Tell.TestLaterWakeEnds` (case open: an open incident gets a dry run).
- mutation: `Record`'s `added` ignores `laterWas` (a waiter for every batch of a round) → red: `Tell.TestStillGathering` ("one waiter for the round").
- mutation: `Later` passes `LaterSince` for both `LastAt` and `LaterSince` to `Settle.Wait` → red: `Tell.TestStillGathering` (the alarm is 1 s, not 6 to 8).
- mutation: `Ask` sends the dry run before it saves the marks (the send above `TSTART`) → red: `Tell.TestLaterRequestToEachWatcher` ("the marks were saved and the transaction was over when the ask was sent").

**Verification pass after the review patches (implement stage, 2026-10-28):**
- Warm (`e7s6iw`): `Test.Watch.Settle`, `NoticeText`, `Tell` (15.5 s), `Lifecycle`, `Transitions` and `Test.Data.Tables` passed.
- Fresh (`e7s6i`), class time: `Test.Fix.Later` 52.9 s (call 135 s), `DryRun` 4.5 s, `Raise` 63.8 s, `Test.Watch.Incidents` 106.6 s (call 188 s), `Diagnose` 45.0 s, `Notices` 27.2 s, `Closing` 29.8 s, `Test.Checks.Turns` 8.7 s: all passed.
- `shard lane-a --part k/12`, k = 1 to 12, all passed (77 classes): 238, 184, 97, 125, 106, 100, 195, 87, 103, 263, 211 and 110 s per call. `shard lane-b --part k/3`, k = 1 to 3, all passed (64 classes): 134, 172 and 100 s. `live storage-roundtrip` passed (81 classes with a committed Storage block, including the four new properties). `bash ci/checks.sh`: every script passed.
- Matrix Test Audit: every row of the I/O matrix has a covering test that ran and passed in the output above (live rows: `Later.TestLaterFailuresGetTheirOwnRequest`, `Later.TestOpenIncidentOnlyCounts`; probe rows: `Tell`, `Lifecycle.TestLaterRequestWhileFixing`).

**QA pass (2026-10-28, tags `e7s6qa` fresh and `e7s6qaw` warm; no product code changed, no file added):**
- Audit: AC 1 to AC 6 and every row of the I/O matrix have a pinning test, and the 22 recorded `mutation:` lines name tests that exist. Four gaps are filled below: the live (`Test.Fix.Later`) halves of AC 2's Integration clause, AC 3's rejection clause and U-126 had no observed red; the changed tests needed their lines refreshed.
- (QA) `Test/Fix/Later.cls` changed:
  - `TestLaterFailuresGetTheirOwnRequest` asserts U-126 per request: R2's targets share no order with R1's (`Shared`), and R2's `DryRun.resend` equals the number of R2's `FixTargets`.
  - It no longer reads transient state by luck. The count is awaited by its row and by the incident event that carries it (`WaitCounted`, whichever batch brings it). The event after R2's Notification is awaited (`WaitLast`: Tell sends the Notification first, then publishes). "`LaterSince` is set" and "one request" are asserted only if `Settle.Wait` still said the rule ran after they were read (the waiter asks no earlier), else a log message says so. The `before` baselines are gone.
  - `TestOpenIncidentOnlyCounts` takes no baseline of events and checks the event that carries the count 5 (open, `NoticeCount` 3, R1 rejected). The sleep that stays waits for something not to happen.
  - Evidence that the old test was timing-fragile: with `Hang 14` after `WaitCount` (a late read), the shipped test failed 3 assertions ("LaterSince is set", "carrying the count 5 and listing R1 only", "still one request"), and the new one passed.
- (QA) `Test/Watch/Tell.cls` changed:
  - `TestStillGathering` bounds the alarm by the clock time that passed (`seconds + elapsed >= quiet - 3`, `seconds <= quiet - 2`) instead of a fixed two-second slack.
  - `TestFailedLaterRoundLeavesItsFailuresUncovered` (new, probe, three cases: the ask cannot be sent, FixExecutor answers an error, the raise fails). It pins today's behaviour of a later round that fails after its marks moved (residual risk 1; V2): one `LOGLATER` warning, no Notification, no request, `Count` 5 and the one incident event with it stay, no round open, and the marks stay (`h103>h105`), so the next round's ask covers `h106` only (`h105>h106`) and no ask covers `h104` and `h105`. The marks assertions go red when a fix restores the marks.
- Order: `Later`'s two tests also passed with the second renamed to run first (one run, test-only rename, restored).

**Pinning mutations added by QA (Rule 19), each observed red and reverted byte-identically (md5 of the file equals its backup, `git status --short` unchanged):**
- mutation: `Ask` sets `AskedFrom` to "" instead of `AskedTo` (fresh) → red: `Later.TestLaterFailuresGetTheirOwnRequest` ("R2's targets share no order with R1's: 2,3,4 and 2,3,4,5,6", the targets, the dry run, the count and the rendered text). U-126, targets.
- mutation: R2's row takes R1's `DryRun` (`row.DryRun` from the first request when `later`) (fresh) → red: `Later.TestLaterFailuresGetTheirOwnRequest` ("with its own dry run", "R2's dry run resends as many orders as R2 has targets"). U-126, resend.
- mutation: the later notice is sent with `NOTICEKIND` instead of `APPROVALKIND` (fresh) → red: `Later.TestLaterFailuresGetTheirOwnRequest` ("S has one approval Notification", "WebChatOut recorded one approval Delivery row with the request's Ref"). AC 2, Integration.
- mutation: `Facts` ignores a pending request (`If 0 || ...`) (fresh) → red: `Later.TestLaterFailuresGetTheirOwnRequest` ("the incident stays awaiting approval, with both requests", "and the event lists R2 as rejected"). AC 3, R2's rejection while R1 is pending. The last three ran together in one fresh run; each red is its own assertion.
- mutation: `Record`'s later rule ignores the open-and-noticed check and `Later` does not end on open (fresh, re-run after `TestOpenIncidentOnlyCounts` changed) → red: `Later.TestOpenIncidentOnlyCounts` ("the incident stays open and no round gathers", "and the dry run was asked once"). AC 6.
- mutation: `Proposed` skips `CancelRequest` after a failed save → red: `Tell.TestSaveFailureCancelsTheLaterRequest` (and `TestSaveFailureCancelsTheRequest`). Matrix row "Save fails after Raise".
- mutation: `AskLater` puts the marks back (`AskedTo := AskedFrom`) when the ask cannot be sent → red: `Tell.TestFailedLaterRoundLeavesItsFailuresUncovered` (case ask: "the marks stay where the ask put them", "no ask covers h104 and h105"). Residual risk 1. Superseded by the code review: the product now puts the marks back on the error routes, and the test is `Tell.TestFailedLaterRoundRejoinsTheNextRound`; see the code-review lines below.
- mutation: `Later` passes `LaterSince` for both `LastAt` and `LaterSince` to `Settle.Wait` (re-run after `TestStillGathering` changed) → red: `Tell.TestStillGathering` (the alarm is 1, not 7 to 8).

**QA runs (tags `e7s6qaw` warm, `e7s6qa` fresh; class time, `CLASS ... passed`):**
- Warm `Test.Watch.Tell`: passed on the unchanged tree (16.0 s) and five times on the edited, unmutated tree (15.5, 15.4, 15.5, 15.5 and, as the final re-run, 15.5 s), among them after each mutation's revert. It failed only in the three mutated runs above.
- Fresh `Test.Fix.Later`: passed on the unchanged tree (52.3 s; call 134 s) and on the edited, unmutated tree (54.0, 55.1 and, as the final re-run, 53.4 s; calls 131 to 158 s, of which 77 to 104 s is the stack start). Also passed with the second test run first (55.6 s) and, for the edited test, with a late read (`Hang 14`, test-only, 59.4 s). It failed in the three mutated runs above and, for the shipped test, with the late read.
- `bash ci/checks.sh` after the last run: every script passed (87 s). Both stacks were torn down (`ci/warm.sh down` for `e7s6qaw`, `ci/iris.sh teardown` for `e7s6qa`), and `git rev-parse HEAD` is unchanged.

**Code-review pass (2026-10-28, tags `e7s6crw` warm and `e7s6cr` fresh, lane A).** Patches: the error routes of a later round put the marks back (`Unask` with unmark); the probe reads the marks by SQL and gains `FailCancel`. Tests: `Tell.TestFailedLaterRoundRejoinsTheNextRound` replaces QA's `TestFailedLaterRoundLeavesItsFailuresUncovered`; R1 is read again after the round (`Tell`, `Later`); `Later` checks that the mock log exists; `Incidents.TestInstanceShared` guards its transient assertions with `Settle.Wait`. See `### Review Findings`.

**Pinning mutations added by the code review (Rule 19).** Each was observed red on the warm stack, reverted from the saved patched copy (md5 equal), and followed by a green `Tell` on the same stack:
- mutation: in `Unask` with unmark, `AskedTo` is left as it is (`Set group.AskedTo = group.AskedTo`) → red: `Tell.TestFailedLaterRoundRejoinsTheNextRound`, cases ask, error, slots, raise and save ("an error puts the marks back", "its window holds the failed round's h104 and h105 with h106"). The lead's item: an error round's failures are not lost.
- mutation: `Decline` puts the marks back for a judged dry run as well (`Unask(incident, 1)`) → red: `Tell.TestFailedLaterRoundRejoinsTheNextRound`, cases reason and targets ("a judged dry run ... keeps the marks", "its window is h106 only"). V2's judged rounds.
- mutation: `Unask` does not give the gathering round the earlier time (the `LaterSince := AskingSince` line removed) → red: `Tell.TestFailedLaterRoundRejoinsTheNextRound`, case error ("takes the failed round's earlier time", and the next ask's time).
- mutation: the failed-save route puts the marks back although the cancel failed (`Unask(incident, 1)`) → red: `Tell.TestFailedLaterRoundRejoinsTheNextRound`, case uncancelled ("keeps the marks", "its window is h106 only").
- mutation: `Ask` sets the marks on the objects, sends, and only then saves → red: `Tell.TestLaterRequestToEachWatcher` ("the marks were saved and the transaction was over when the ask was sent") and every case of `TestFailedLaterRoundRejoinsTheNextRound` ("with the round's window saved first"). With the probe's old `Marks`, which opened the rows, the same mutation left `Tell` green. Always: marks saved before the send.
- mutation: `Proposed`'s later route also writes the round's targets into R1 and saves it → red: `Tell.TestLaterRequestToEachWatcher` ("and R1 is still as it was after the round"), and no other test. AC 1, "R1 never changes".

**Code-review runs (class time, `CLASS ... passed`):**
- Warm `e7s6crw`: `Test.Watch.Tell` passed 16.0 s on the patched tree, then 15.5 s after each revert. It passed 16.1 s and 15.5 s again after the uncancelled case was added (a second `warm up`). `Test.Watch.Lifecycle` passed twice (0.21 s; 19 probe tests).
- Fresh `e7s6cr`, all passed:
  - `Test.Fix.Later`: 52.9 s, call 152 s.
  - `Test.Watch.Incidents`: 106.4 s, call 192 s.
  - `Test.Watch.Tell`: 16.1 s, call 102 s, before the test-only uncancelled case.
  - `Test.Fix.Raise`: 61.6 s, call 147 s.
- `bash ci/checks.sh`: every script passed (92 s, and 88 s after the last test edit).
- Both stacks were torn down, with no `e7s6cr` container left.
- Slot A got `Watch.IncidentManager`, `Watch.Msg.Settle`, `Test.Watch.IncidentProbe`, `Test.Watch.Tell`, `Test.Fix.Later` and `Test.Watch.Incidents` (loaded and compiled `ck-d`); no test ran there.

## Auto Run Result
Status: done
Blocking condition: none

**Plan stage (2026-10-28).** Planned in full against the READY FOR DEVELOPMENT standard. The plan stage made no runtime call: no slot read and no throwaway; Task 0 is the implement stage's. Three items need the lead's ruling at the spec gate. Each is planned as recommended, and none blocks the build:
- **V1 (veto, schema):** four appended stored properties: `Incident.LaterSince`, `Incident.AskingSince`, `FailureGroup.AskedFrom`, `FailureGroup.AskedTo`. Recommend keep. Design Notes give the rejected alternatives and the reversal.
- **V2 (veto, public behaviour in an edge case):** a later round that cannot raise a request sends no notification, and logs one Type 3 warning for an error. Recommend keep (no new public text; the count reaches every recipient through the `incident` event).
- **V3 (veto, AC move):** the "each approved request gets its own `FixRun`" half of the criterion depends on Story 7.3's `Execute` (`FixExecutor` writes `FixRun` rows; `STUB = 1` until 7.3). This story delivers `IncidentManager`'s half: one `Execute` per approved request, serialized (AC 4). Proposed: add to Story 7.3 the pin "two approved requests of one incident make two `FixRun` rows". Flagged, not decided.

No AD amendment, no NFR tripwire, no contended path. Ledger inbox: none.

**Implement and review stage (2026-10-28).** Status done; HEAD at the start was `0be77b16ab1e63aee854fc8a6ed7a06f03471635`.
- **Implemented:** the four stored properties (`FailureGroup.AskedFrom`/`AskedTo`, `Incident.LaterSince`/`AskingSince`, Storage Values 12-13 and 27-28), `Settle.Window`, `FailureGroup.AskedKeys`, `RepairResend.DryRun` reading the ask's window, `Notice.KEYLATER` and `WithFixSlots` with a given count and time, and in `IncidentManager` the marks-before-send `Ask`, the later-failure rule in `Record`/`Batch`, `StartLater`, `Later`/`AskLater`/`LaterAlarm`, the `later` flag of `Proposed`/`Unproposed`, and `Notification` lifted out of `Deliver`. Tests: `Test.Fix.Later` (new, two production tests), six `Tell` tests and `TestLaterWakeEnds`, `Lifecycle.TestLaterRequestWhileFixing`, `DryRun.TestAskedWindow`, `Settle.TestWindow`, `NoticeText.TestLaterRequest`; `Case` lifted `Raised`, `Noticed`, `Answered` and `NoticeSessionOf` from `Test.Fix.Raise`; `IncidentProbe` gained the later seams.
- **Files changed:** `Data/FailureGroup.cls`, `Data/Incident.cls`, `Watch/Settle.cls`, `Watch/Notice.cls`, `Watch/IncidentManager.cls`, `Fix/Kind/RepairResend.cls`, `Test/Data/Tables.cls`, `Test/Fix/{DryRun,Raise}.cls`, `Test/Fix/Later.cls` (new), `Test/Watch/{Case,IncidentProbe,Incidents,Lifecycle,NoticeText,Settle,Tell}.cls` (all under `src/ocutalon/cls/OcuTalon/`).
- **Review:** 32 findings from four layers (high 0, medium 7, low 19, false 5, maybe-false 1). Patches applied: `Later`'s open branch through `Unlater`; `Tell.TestLaterWakeEnds`; one waiter per round and the alarm basis in `TestStillGathering`; the marks-before-send pin (probe level and marks); the baseline wait in `Later.TestOpenIncidentOnlyCounts`; seven mutation lines. Deferred: none. Rejected, with reasons in the Review Triage Log: marks not restored when a round fails (V2's end state; reopen_if a failed round leaves failures uncovered in a live run), `AskingSince` never timing out (residual risk 1), no cap on later requests (a product call; AC 1), a failed alarm or a throwing wake (infrastructure), cosmetic log text, `Raised`'s default count (spec), transient "at once" assertions (about 5 s of margin), and five claims that do not hold.
- **Follow-up review recommended: true.** Five medium entries were patched. The unverified risk: the new `Tell` tests and the baseline wait of `Later.TestOpenIncidentOnlyCounts` have one green run each on this tree plus their mutation reds, and have not been run in reverse order or repeated.
- **Verification:** see `## Verification` (Task 0, the loop classes, 12 lane-a parts, 3 lane-b parts, `storage-roundtrip`, `ci/checks.sh`, 15 mutations plus 7 from the review). Slot A gets the classes after the commit; no test ran on it.
- **Residual risks:** (1) the failures of a later round that failed after its marks moved sit in no window, so no request covers them (a warning is logged); (2) an ask that is never answered leaves `AskingSince` set (DW-345); (3) `SEENMAX` bounds a window (DW-318); (4) an incident can collect many later requests.
