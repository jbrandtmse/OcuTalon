---
title: 'Approved repairs are re-checked and resent'
type: 'feature'
created: '2026-10-28'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Since Story 7.2, approving a fix request moves its incident to `fixing`, and `IncidentManager` sends `FixExecutor` an `Execute`. But `FixExecutor` is still a stub (`STUB = 1`, error 5003 for everything but a dry run), and `RepairResend` has no `Recheck` or `Execute`. The approval also gets no `answered.approved` notice, and no `FixResult` ever comes back. So nothing approved is ever carried out, and a request whose run cannot start leaves its incident `fixing` without a word to the user.

**Approach:** `IncidentManager` answers an accepted approved outcome with `answered.approved`. For every accepted final `FixResult` it sends one `result` notification, whose key it picks by the Result texts convention. `FixExecutor` gets a real `Execute`, working from the `ApprovalRequest` row alone:
- it refuses any row that is not approved or is past its expiry;
- it ends an approved run that cannot start with a couldn't-start `FixResult`;
- otherwise it starts the run, writes its `FixRun` and re-checks each of the row's `FixTargets` through `Watch.Reader`;
- it resends a repaired copy of each target that passes, from its one `New $NAMESPACE` method, and registers each copy's header id on the `FixRun` (`Copies`, V1).

A run that resent nothing ends with its own final `FixResult`. How a run that resent copies ends (the 60-second wait and its counts) is Story 7.4's (V2).

## Boundaries & Constraints

**Always:**
- **The row is the truth (AD-11, AD-16, U-126).** `FixExecutor` reads the kind, the parameters and the targets only from the row's `FixKind`, `FixParameters` and `FixTargets`. `Execute` carries only `ApprovalRef`. `Execute` and `FixResult` gain no property.
- **FixExecutor's order for one `Execute`** (PoolSize 1):
  1. **Refused.** No row; `Kind` is not `fix`; `State` is not `approved`; or `ExpiresAt` is not after now (UTC stamps, compared as text). The handler writes, sends and resends nothing, logs one Type 4 info line (`LOGREFUSED`, naming the Ref and why) and answers OK.
  2. **Couldn't start: the row is unusable** (V3, `UNUSABLE`). This covers: the kind is not registered (`Fix.Kind.ForName`); `FixParameters` is not one JSON object; `FixTargets` is not made of positive whole numbers that strictly ascend; or the row's incident is missing or closed.
  3. **Couldn't start: no resources.** The kind's `RESOURCES` holds a pair that the `ServiceUser` setting's user does not hold. It is checked one letter per `$SYSTEM.Security.CheckUserPermission` call, through `Bridge.Policy.Gate.MissingOf`. The reason is the kind's `NOTALLOWED`: "OcuTalon isn't allowed to resend messages in that production" for `repair_resend`.
  4. **`Approval.StartExecution(ref)`.** An error here is refused, as in step 1.
  5. **The run.**
     - Save the run's `FixRun` (`ApprovalRef`, `IncidentRef`, `StartedAt`).
     - Run the kind's `Recheck` over all the row's targets before any resend.
     - Run the kind's `Execute` over the targets that passed.
- **Couldn't start (steps 2 and 3):**
  - The run's `FixRun` is saved, with no copies.
  - `FinishExecution(ref, "failed")` is called (it accepts the row while it is still `approved`).
  - Then one `FixResult` goes to `IncidentManager`: `Final` 1, `Total` = the number of entries in `FixTargets`, `Resent`, `Completed`, `FailedAgain` and `Skipped` all 0, and the plain `Reason`.
  - A re-check that cannot read the production at all ends the same way after `StartExecution`, with `failed`, the reason `NOREAD` (V3) and one Type 3 warning. That is Reader giving no `read`, or an error thrown before any resend.
- **How a run ends:**
  - **It resent nothing** (every target was skipped). It calls `FinishExecution(ref, "done")` and sends one final `FixResult`: `Total` N, `Resent`, `Completed` and `FailedAgain` 0, `Skipped` N, and `Reason` = the first skipped target's plain reason.
  - **It resent at least one copy.** The run ends after its last registration. Its row stays `executing`, its incident stays `fixing`, and it sends no `FixResult` (V2: the wait and the counts are Story 7.4's).
  - No final result ever goes out before its copies are counted, so the product never sends a false all-clear.
- **The re-check** (`RepairResend.Recheck`) reads each target through `Watch.Reader.Evidence` (the incident's namespace and production, the first failure group's `ItemName`) with its new `resent` flag. A target passes only if all of these hold:
  - its header still exists, in status `Error`;
  - its scope (`FailurePoller.Scope` of its `SuperSession`) is the incident's owner;
  - no header of its session names it as resent (a `Resent <ids>` description);
  - it still has its body;
  - the field is a stored datatype property of the body's class, and its value still reads in the source format (`Fix.Reformat.Convert`).

  Every other target is skipped with one plain reason that names it. `Recheck` and `DryRun` share one helper for the target test (Rule 2).
- **The resend** (`RepairResend.Execute` calls `Fix.Executor.Resend`; AD-3, AD-16), one copy at a time:
  - The repaired value is worked out (`Convert`) in the home namespace, before the switch.
  - In the production's namespace, calling no OcuTalon class there, the original's header and body are opened. The copy is built only if the header is still `Error` and the field still holds the value that the re-check read.
  - The copy is `%ConstructClone(0)` of the body (its class as resolved in that namespace), with the field set through the compiled dictionary's property.
  - It is sent with `Ens.MessageHeader.ResendDuplicatedMessage(original, .newId, <the original's TargetConfigName>, copy)`.
  - Back in the home namespace, `newId` is appended to the `FixRun`'s `Copies` and saved.
  - A status of `ErrProductionNotRunning`, or any other refusal, skips that copy with a plain reason.
  - The originals are never changed.
- **IncidentManager.** It stays the only writer of `Incident` and publishes only after its commit (AD-12, AD-15, AD-33).
  - **An accepted `approved` outcome** sends each recipient one Notification of kind `answered`:
    - key `answered.approved`, slots `{channel: AnsweredChannel, time: AnsweredAt}`;
    - `ApprovalRef` and `IncidentRef` set, no `DecisionRef`;
    - sent through the same `Move` and `Tell` as the event, also while the incident is `fixing`.
  - **An accepted final `FixResult`** (`Final` or `Interrupted`) sends each recipient one Notification of kind `result`, with `ApprovalRef` and `IncidentRef` set and no `DecisionRef`.
    - Its key comes from `Notice.ResultKey`, first match wins:
      1. the row is `executing`: `result.stillResending`;
      2. `Interrupted`: `result.interrupted`;
      3. every count is 0 and `Reason` is set: `result.couldNotStart`;
      4. `FailedAgain` and `Skipped`: `result.failedAndSkipped`;
      5. `FailedAgain`: `result.failedAgain`;
      6. `Skipped`: `result.skipped`;
      7. otherwise `result.allThrough`.
    - It carries the slots that its key declares: `count` (= `Total`), `itemNoun` (from the row's `DryRun`, else the incident's `ItemNoun`), `completed`, `failedAgain`, `skipped`, `remaining` (= `Total` − `Completed`), and `failReason` and `reason` (= `Reason`).
  - A progress `FixResult`, and a refused one, send none.
- **No model call.** The mock logs no request during a run (AD-16, AD-22). The production's testing switch stays off.
- **Rules that apply throughout:**
  - Producers send keys and slots only (AD-32).
  - Log text goes through `Bridge.Redact.Text`.
  - Stored properties are append-only, with their `Storage` blocks committed (AD-5, AD-33).
  - Rule 14 applies.
  - Tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`. Tests that drive the production run only on throwaways, fresh.

**Never:**
- Nothing of a later story:
  - 7.4: the 60-second wait; the `Completed` and `FailedAgain` counts of resent copies and their reason; the `FinishExecution` of a run that resent copies; recognising a copy's failure by its header id; the stored result counts (DW-272); the `Action` audit entry; the 500-message run; DW-318; DW-292;
  - 7.5: `Reconcile` and `Sweep`;
  - 30.5: the still-running result.
- No retry. A copy is resent once per approved run, and a skipped target is never acted on without a new approval.
- No `%Ens_MessageEditResend` and no new grant: 7.1's `%Ens_MessageResend:U` serves.
- No edit to:
  - `Install/**` and `Core/**` (the test oracle `Test/Install/Production.cls` changes only Lane A's `FixExecutor` row);
  - `Msg/Catalog/**`, `Fix/Msg/**`, `Watch/Transitions.cls` and `Live/Payload/**`;
  - `Test/Data/Fixture.cls`, `Test/Demo/**` and `Test/Live/**`;
  - `Eval/**`, `ci/mock/**` and `docker/**`.
- No stored property other than V1's `Copies`. No edit to any AD. No new catalog key. No `[Language = python]`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Approved (live) | S's incident is awaiting approval. R1 is pending over 3 failed orders (`10/16/2026`). Then `Approval.Answer(R1, "approve", "web", ANSWERER, S)`. | **At once:**<br>- the incident is `fixing`;<br>- S gets one `answered.approved` Notification (channel web, time `AnsweredAt`, R1, the incident) in the incident's trace session; it renders "Approved from the web chat at …", and WebChatOut records its answered Delivery row with R1;<br>- one `Execute`, carrying only R1's Ref, goes out in the trace session.<br>**Then:**<br>- the row is `executing`;<br>- there is one `FixRun` (R1, the incident, `StartedAt`) whose `Copies` are 3 new header ids;<br>- each copy is in its original's session with its `SuperSession`, its description is `Resent <original>`, its body class is its original's, its `OrderDate` is `2026-10-16` and its other fields are equal; it completes;<br>- the originals and their bodies are unchanged (Snapshot);<br>- there is no FixResult and no result Notification yet (V2);<br>- the mock logs no request. | none |
| Second Execute | An `Execute` for R1 while R1 is `executing` | Refused: still one FixRun and 3 copies | one info line |
| Approved while fixing (probe) | The incident is `fixing`: R1 is executing and R2 is approved | It stays `fixing`. R2 gets `answered.approved`, and no Execute goes out (Story 7.6's rows). | none |
| Refused (live and probe) | For every registered kind: a row `pending`, `rejected`, `expired`, `cancelled` or `executing`; an `approved` row past `ExpiresAt`; a `tool_call`; an unknown Ref | No FixRun, the row unchanged, no FixResult, no copy and OCUORDERS unchanged, with the testing switch off | one info line each |
| No resources (live) | R1 is approved, and the service role does not hold `%Ens_MessageResend` | - One FixRun, with no copies; the row is `failed` (`Result` failed).<br>- One FixResult: R1, the incident, `Final` 1, `Total` 3, every count 0 and `Reason` NOTALLOWED.<br>- The incident is `resolved`.<br>- One `result.couldNotStart` Notification with R1, which renders "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed."; WebChatOut records its result Delivery row.<br>- No copy is made. | none |
| Unusable row (probe; live through Closing; V3) | An approved row with the kind `zz_fix`, parameters that are not an object, the targets `101,abc` or `102,101`, or a closed incident | As "No resources", with the reason UNUSABLE | none |
| Changed targets (live) | Six targets: one is unchanged; one is Completed; one has an `OrderDate` in the target format; one is outside S's scope; one was resent by hand; one has lost its header | Only the unchanged one passes. The other five are skipped, each with a plain reason of its own that names it. | none |
| Unreadable (probe, V3) | The re-check cannot read: Reader gives `unreadable` or `not_current` | A FixRun; the row `failed`; a FixResult with every count 0 and `Reason` NOREAD; `result.couldNotStart` | logged |
| Nothing resent (live) | Every target of R1 has changed since the dry run | - The row is `done`.<br>- The FixResult has `Total` 3, `Skipped` 3, `Resent` 0, and `Reason` = the first skip's reason.<br>- One `result.skipped` Notification: "0 of 3 orders went through. 3 had changed since the dry run, …" | none |
| Production stopped (live, V4) | The Orders production is stopped when R1 runs | Every copy is skipped with "the production isn't running" and no header is made; otherwise as "Nothing resent" | none |
| Two requests (live, U-134) | R1 over 3 orders (their bodies changed) and R2 over 2 later failures; both are approved | - Two FixRun rows, R1's and R2's, run one at a time: R1's FixResult comes before R2's single `Execute` in the trace session.<br>- R1's FixResult and its `result.skipped` Notification carry R1's Ref and R1's counts.<br>- R2's `Copies` are copies of R2's targets only. | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless stated. Line numbers are as of `5308f3e`.

**Fix area (changed):**
- `Fix/Executor.cls` (68 lines):
  - `STUB` L14;
  - `OnMessage` L16: `DryRun`, else 5003;
  - `DryRun` L23 and `Work` L49: the model for opening the incident and the kind (`ForName`) and for a redacted plain reason.
- `Fix/Kind.cls`:
  - `RESOURCES` L22, `KINDS` L25, `ForName` L54;
  - the base `Recheck` L104 and `Execute` L112, both not implemented. `Test.Fix.Kind.TestContract` L53 pins their first three argument names and the 5003 error.
- `Fix/Kind/RepairResend.cls`:
  - `RESOURCES` L18, `ERRORSTATUS` L21, `CheckParameters` L24;
  - `DryRun` L92. Its per-failure target test is at L113-121 (status, scope, body) and its field read at L145-146 (`Convert`). These are the parts to lift into the shared helper.
- `Fix/Reformat.cls`: `Convert(value, source, target, .result)` (pure).
- `Data/FixRun.cls`: `ApprovalRef`, `IncidentRef`, `StartedAt`; `ApprovalRefIndex`, `IncidentRefIndex`; Storage Values 1-4.

**Bridge (read, plus one lift):**
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `StartExecution` L370: approved and ahead becomes executing, with no event;
  - `FinishExecution` L380: done, failed or interrupted; `failed` is also accepted from approved; it fires `approval.result`;
  - `Move` and `MoveLocked` L395-445 write each change's Approval audit entry.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`: `Resources` L198 (the parser); `MissingPrivilege` L228 (private; its loop is the one to lift).

**Watch:**
- `Watch/Reader.cls`:
  - `Evidence` L190;
  - `Current` L242 is the one switching method. The evidence header query is at L285, the failure object at L332, and its push at L357.
  - `Test/Bridge/CodeRules.cls` L79 `WATCHREADS`: `Current` calls no OcuTalon class.
- `Watch/FailurePoller.cls`: `Scope` L132.
- `Watch/IncidentManager.cls`:
  - parameters `ANSWEREDKIND` L165 and `KEYREJECTED`/`KEYEXPIRED` L167-169;
  - `Notification` L948, `Move` L963, `Apply` L984, `Facts` L1000, `Owns` L1021;
  - `Execute` L1037: sent in the trace session;
  - `Outcome` L1105;
  - `AnswerNotice` L1119: gives "" for approved;
  - `Result` L1140: sends no notification;
  - `Event` L1153, `Tell` L1242;
  - the class doc's states bullet L55-64.
- `Watch/Notice.cls`: the doc L1-21; `WithFixSlots` L102, the model for a builder.
- Read only: `Watch/Transitions.cls` (`awaiting_approval` + approved gives `fixing`, OWN; `fixing` + finished gives EARLIEST, `awaiting_approval` or `resolved`); `Msg/Catalog/Core.cls` L80 `answered.approved` (`channel`, `time`); `Msg/Catalog/Watch.cls` L151-243, the seven `result.*` keys and their slots.

**Consumers and the platform (read only):**
- `Channel/WebChat/Out.cls` L27 `INCIDENTKINDS`: records the `answered` and `result` Delivery rows with their `ApprovalRef`.
- `Core/BridgeSink.cls`: `approval.result` becomes an approval live event, with no Notification.
- `Demo/Orders/`: `Partner.Send` L83 (asynchronous); `Translator` (its DTL accepts the repaired date); `PartnerOrder.OrderDate`.
- `irislib/Ens/MessageHeader.cls` (reference source, never loaded):
  - `ResendDuplicatedMessage` L443;
  - `NewDuplicatedMessage` L458. It refuses with `ErrProductionNotRunning`. The clone keeps `SessionId` and `SuperSession`. `Description` becomes `Resent <id>`, then `,<earlier ids>` or `: <description>`. It saves a persistent new body, and the resend is audited.

**Tests to reuse or change:**
- `Test/Watch/Case.cls`:
  - requests and messages: `Raised` L1366, `Noticed` L1393, `Answered` L1407, `NoticeBodies` L1263, `AssertDelivered` L1280, `Requests` L276, `HeadersBetween` L290;
  - instance changes put back by `PutBack` L411: `RevokeRole` L358, `StopOrders`/`StartOrders` L1000-1031;
  - orders and fixtures: `Fixture` L693, `Fail` L635, `WaitFailed` L668, `HeaderIds` L681;
  - clean-up: `DropIncidentRows` L1443.
- `Test/Watch/Lifecycle.cls`:
  - `TestApprovalOutcomes` L258 asserts at L276 and L351 that approved sends no answered notice;
  - `TestFixResults` L357; the `Result` helper L1066; `Answers` L942; `TestFixMessages` L828 (the property pin for AC 2).
- `Test/Watch/Closing.cls`: `TestApproveSendsExecuteToFixExecutor` L108-155 ("the stub refuses it"); its row comes from `HeldRequest` L157 with `FixKind` `zz_fix`; its doc is L13-16.
- `Test/Fix/DryRun.cls`: `Ask` L80 sends from `SimMailboxIn`; `TestOtherRequest` L467 expects 5003.
- `Test/Fix/Raise.cls`: `TestRejectChangesNothing` L65 and `Unchanged` L209 (DW-347).
- `Test/Fix/Later.cls`: the two-request set-up and `WAITLATER`.
- `Test/Fix/Snapshot.cls`: `Take`, and `Diff(before, after, allowedSessions, allowedIn)`.
- `Test/Watch/IncidentProbe.cls`: the seam pattern for a probe subclass.
- `Test/Contract/Mock.cls`: `LogMark`, `LogSince`.
- `Test/Install/Production.cls`: the doc L13, the FixExecutor row with `"stub": 1` at L628, and `TestStubsAnswer` L140.
- `Test/Data/Tables.cls`: the `FixRun` entry at L561.
- `Test/Watch/NoticeText.cls`: `Render` L128 and `ZONE`.
- `Test/Data/Fixture.cls` (read only): `Incident` L81 and `Approval` L102, which take fields.

## Tasks & Acceptance

**Execution:**

*Task 0.* Run it on the stage's first fresh throwaway and record the results in `## Verification`:
- (a) A `ResendDuplicatedMessage(original, , target, clone)` copy: its `SessionId`, `SuperSession`, `Description`, `Resent` value, body class and new body id. Check that the original header and body are unchanged (Snapshot), and that the copy completes.
- (b) With Orders stopped: the status that the call gives, and that no header is made.
- (c) `CheckUserPermission` is 0 in FixExecutor's job right after `RevokeRole`.
- (d) The class time of each new live class. Split any class whose call runs past about 180 s.
- (e) The seconds from the approval to the registered copies, and to the copies' Completed status. These set `WAITRUN` and `WAITCOPY` (default 30 each).
- (f) A `FixRun` saved after the switch back from OCUORDERS reads back in OCUTALON.

*Product code (in dependency order):*
- `Data/FixRun.cls` (V1):
  - Append `Copies As list Of %String(MAXLEN = 20)`: the registered copy header ids, in resend order, as Storage Value 5.
  - Doc: one row per approved request that FixExecutor takes up.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`: lift `MissingOf(value, where)` (public) out of `MissingPrivilege`, which then calls it.
- `Watch/Reader.cls`:
  - `Evidence(…, resent = 0)`: with `resent` 1, each failure gains `resentBy`, the ids of the headers of its session whose `Description` lists it after `Resent ` and before any `:`. This is read in `Current`.
  - Default callers are unchanged.
  - Doc.
- `Fix/Kind.cls`:
  - Add `Parameter NOTALLOWED`: the plain reason of a run that cannot start without `RESOURCES`; empty in the base.
  - `Execute` gains a trailing `run As OcuTalon.Data.FixRun = ""`.
  - Doc for `Recheck` and `Execute`. The base stays not implemented.
- `Fix/Kind/RepairResend.cls`:
  - `NOTALLOWED` = "OcuTalon isn't allowed to resend messages in that production".
  - `Recheck` and `Execute`, per Always. `DryRun`, `Recheck` and `Execute` share one private target test (Rule 2).
  - Doc.
- `Fix/Executor.cls`:
  - Delete `STUB`.
  - `OnMessage` routes `DryRun` and `Execute`; any other class is error 5001, naming it.
  - `Execute`, per Always.
  - `ClassMethod Resend(namespace, plan, run, Output resent, Output skipped)`: the one `New $NAMESPACE` method.
  - Seams for the probe: `SendResult(result)` (`SendRequestAsync` to `MANAGER` "IncidentManager"), `Missing(class)`, `Check(class, …)` and `Carry(class, …)`.
  - Parameters `UNUSABLE`, `NOREAD`, `LOGREFUSED`, `LOGFINISH` and `LOGRESULT`. A failed `FinishExecution` or a failed send logs one Type 3 warning, and the `FixResult` still goes.
  - Rewrite the class doc.
- `Watch/Notice.cls`:
  - Add `ResultKey(state, result)` and `ResultSlots(key, result, noun, Output sc)` (pure), with slot integers where empty counts are 0.
  - Doc.
- `Watch/IncidentManager.cls`:
  - Parameters `KEYAPPROVED` ("answered.approved") and `RESULTKIND` ("result").
  - `AnswerNotice` covers approved.
  - `Result` builds the result Notification for a final or interrupted result and passes it to `Event`.
  - Doc (the states bullet).
  - Why: AC 1 and AC 5.

*Tests:*
- `Test/Fix/ExecutorProbe.cls` (new): overrides the four seams, recording into `Results`. A test can set `MissingIs`, `CheckIs` and `CarryIs`. It is no production item.
- `Test/Fix/Executor.cls` (new; probe; warm):
  - `TestRefusedStates` (AC 4)
  - `TestCouldNotStartRoutes` (AC 5, V3: NOTALLOWED and every unusable row)
  - `TestUnreadable` (V3)
  - `TestNothingResent` (row done; Skipped N)
  - `TestResentRunSendsNoResult` (V2)
  - Each test asserts the `FixRun` rows, the row's state and `Result`, and the recorded `FixResult`.
- `Test/Fix/Recheck.cls` (new; live; fresh): `TestChangedTargetsAreSkipped` (AC 6, the "Changed targets" row, through the real Reader).
- `Test/Fix/Execute.cls` (new; live; fresh):
  - `TestApprovedRepairsAreResent` (AC 1, 3, 7; Integration): the "Approved" and "Second Execute" rows. Snapshot `Diff` with `allowedSessions` = the originals' sessions and `allowedIn` OCUORDERS has no line. `LogMark()` > 0.
  - `TestCouldNotStart` (AC 5; Integration): `RevokeRole("%Ens_MessageResend")`, then the "No resources" row.
- `Test/Fix/Refused.cls` (new; live; fresh): `TestNoApprovedRowNoRun` (AC 4).
  - It asserts that `OcuTalon.Production` is running, with `TestingEnabled` 0.
  - For each class of `Fix.Kind.Classes()`, the "Refused" rows go to the real item from `SimMailboxIn`, over a `Case.Fixture` incident of real failed orders, so a wrong run would resend.
- `Test/Fix/Runs.cls` (new; live; fresh):
  - `TestTwoApprovedRequestsRunOneEach` (AC 8, U-134): the "Two requests" row, with R1's bodies rewritten in OCUORDERS to the target format.
  - `TestStoppedProductionSkipsEveryCopy` (AC 7, V4): `StopOrders`, then the "Production stopped" row.
- `Test/Watch/Case.cls`:
  - `RaisedTwo(name, .a, .ref, .first, .second)`: `Raised`, then `Fail(2, S's trace)`, then a wait for two requests. `WAITLATER` is lifted here from `Later`.
  - `Runs(incidentRef)`: the FixRun rows as objects.
  - `Header(namespace, id)`: a header with its body.
  - `DropIncidentRows` also deletes the incident's FixRun rows.
  - Doc.
- `Test/Watch/Lifecycle.cls`:
  - `TestApprovalOutcomes`: approved now sends one `answered.approved`, `{channel web, time 2030-01-01T10:00:00Z}`, also while fixing.
  - New `TestResultNotices`: one result Notification per recipient for each accepted final result, with its key, slots and Refs (couldNotStart, skipped, allThrough, interrupted); none for progress or a refused result.
  - Doc.
- `Test/Watch/NoticeText.cls`:
  - `TestResultKeys`: every convention row and its precedence; the slots per key; the renders of the UX fixtures, among them "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed." and "All 50 orders went through."
  - `TestApprovedText`: "Approved from the web chat at 14:20 ET."
- `Test/Watch/Closing.cls`: `TestApproveSendsExecuteToFixExecutor`.
  - After the Execute is handled, the zz_fix row ends as couldn't start (UNUSABLE). One FixResult request goes back in the trace session; the row is `failed`; the incident is `resolved`; there is one `result.couldNotStart` Notification.
  - It still gets no type-2 answer.
  - "fixing" is asserted on the first event only.
  - Doc.
- `Test/Fix/DryRun.cls`: `TestOtherRequest` expects 5001 naming `Ens.StringRequest`; doc.
- `Test/Fix/Kind.cls`: `TestContract` checks that the base declares `NOTALLOWED`, checks RepairResend's `NOTALLOWED`, and keeps the `Execute` call.
- `Test/Data/Tables.cls` (own entry): `FixRun` gains `"Copies": "list Of %String(MAXLEN=20)"`.
- `Test/Install/Production.cls` (Lane A's row and doc; a footprint extension): `FixExecutor` becomes `"stub": 0`, with "FixExecutor (built in Story 7.3)" in the doc.

**Acceptance Criteria:**
- **AC 1.** Given a pending fix request, when it is approved and ApprovalHold sends `ApprovalOutcome` to `IncidentManager`, then:
  - the incident moves to `fixing`;
  - each recipient gets one `answered` Notification with the request's `ApprovalRef` and `IncidentRef`, which renders "Approved from {channel} at {time}";
  - `IncidentManager` sends `FixExecutor` one `Execute` that carries only the `ApprovalRef`;
  - while another fix of the incident runs, the `Execute` waits for that fix's final `FixResult`.
- **AC 2.** Given the Fix messages, when their senders and handlers are built, then `Execute` and `FixResult` keep exactly Story 5.5's properties.
- **AC 3.** Given an `Execute`, when `FixExecutor` handles it, then:
  - it loads the kind, the targets and the change from the `ApprovalRequest` row alone;
  - it starts only after `StartExecution` has atomically moved the row from approved, and not expired, to executing, and only if the service user holds the kind's `RESOURCES` (`CheckUserPermission`);
  - the mock receives no request.
- **AC 4.** Given an `Execute` whose row is pending, rejected, expired, cancelled, already executing or unknown, when `FixExecutor` handles it, then no copy is built or resent, the row is unchanged and no `FixResult` is sent. This test runs for every registered kind, with the testing switch off.
- **AC 5 (Integration).** Given an approved `Execute` whose service user lacks the kind's `RESOURCES`, when `FixExecutor` handles it, then:
  - no copy is built;
  - `IncidentManager` gets a `FixResult` with its `ApprovalRef`, its `IncidentRef`, `Final` 1, `Resent` 0 and the plain `Reason`;
  - the row is closed `failed` through `FinishExecution`;
  - the incident leaves `fixing` per AD-15's table;
  - each recipient's `result` Notification carries the request's Refs, and WebChatOut records it, rendering "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed."
- **AC 6.** Given an approved request, when `RepairResend.Recheck` runs before any resend, then each target is compared with its state in the dry run (still failed, not resent, body unchanged, still in the request's scope), and a changed target is skipped with a plain reason and never acted on.
- **AC 7.** Given the targets that pass, when `RepairResend.Execute` runs, then:
  - each one gets a repaired copy, built with the registered reformatter on the body class as resolved in the production's namespace;
  - each copy is resent with `ResendDuplicatedMessage(original, , target, newBody)` from `FixExecutor`'s one `New $NAMESPACE` method, and its header id is registered on the `FixRun`;
  - a test finds every original header and body unchanged, each copy in its original's trace session with the same `SuperSession`, and the copies by the `FixRun`'s registered header ids;
  - when the production isn't running, each copy it couldn't take is skipped with a plain reason.
- **AC 8.** Given two approved requests of one incident, when their `Execute`s go one at a time, then each run writes its own `FixRun` row with its own `ApprovalRef`, and each result that the run sends is its own (V2 covers the rest).

## Spec Change Log

- 2026-10-28, spec gate (lead): V1, V2 and V3 ruled as veto items U-139, U-140 and U-141 (kept as planned; V2 adds the two-results pin to Story 7.4 in `epics.md`); V4 routed to Story 7.4 as DW-368. The FixExecutor row of `Test/Install/Production.cls` (Epic 13's contended file) is asked of the orchestrator.
- 2026-10-28, spec gate (lead): the orchestrator allowed the `Test/Install/Production.cls` row and doc-clause edit (decide); recorded under Design Notes.

## Review Triage Log

## Design Notes

**V1. `FixRun.Copies` (a schema change, in the veto window; the lead rules it).**
- **Chosen:** one appended stored property, `Copies As list Of %String(MAXLEN = 20)` (Storage Value 5). It is saved after each copy, so a cut-off run still shows how far it got (Story 7.5).
- **Why a list:** Story 7.4 recognises a failed copy by its header id, which an index on the list's elements serves (`Index … On Copies(ELEMENTS)`, Story 7.4's to add). A comma-separated string could never be indexed, and a stored type never changes (AD-5).
- **Rejected:**
  - A copy table: that is a new table, and AD-33 would need a spine change.
  - An `array` keyed by copy id: the original is already named in each copy's `Description`.
  - Properties for the run's state or its counts: those are Stories 7.5 and 7.4 (DW-272).
- **Reversal:** stop writing it. The property stays empty (append-only), and no row has it yet.

**V2. The end of a run that resent copies stays Story 7.4's (an AC split, in the veto window; flagged, not decided).**
- Story 7.4's first criterion owns this end: the 60-second wait, `Completed` and `FailedAgain` with its reason, `FinishExecution`, and `IncidentManager` "records the result against its request".
- In 7.3 such a run ends after its last registration, with its row `executing` and no `FixResult`. A final result sent earlier would read "All N … went through" before anything was counted.
- 7.3 pins its own half of AC 8's "each request's result is its own": each run's own `FixRun` and `ApprovalRef`, each run's targets taken from its own row only, and every result that 7.3 sends (couldn't start, nothing resent) carrying its own Ref and counts.
- **Proposed:** Story 7.4 adds the pin "two approved requests' results are each their own" for runs that resent copies.
- **Rejected:** moving the wait into 7.3. It brings `FailedAgain`, its reason text and the copy recognition with it, which is about half of 7.4.

**V3. Two couldn't-start reasons that UX does not give (public text, in the veto window).** UX gives only the resources reason. These two render as "Nothing was resent: {reason}. Nothing was changed.":
- `UNUSABLE`, "the approved fix could not be read": an approved row that FixExecutor cannot use (unknown kind, parameters that are not an object, malformed targets, incident gone or closed). `Test.Watch.Closing`'s `zz_fix` row reaches it live.
- `NOREAD`, "OcuTalon couldn't read the failed messages in that production": the re-check cannot read the production.
- **Rejected:** refusing these silently, which would leave the incident `fixing` with no end.

**V4. A stopped production renders as "had changed since the dry run" (a public-text claim in an edge case; for the lead or the owner; it does not block).**
- AD-16 counts a copy that a stopped production refuses as `Skipped`, with a plain reason.
- The Result texts convention then picks `result.skipped`, whose text claims that the orders had changed since the dry run.
- 7.3 keeps AD-16 and the convention as they are written (no new text), and `Runs.TestStoppedProductionSkipsEveryCopy` pins that.
- **Recommended:** the owner decides whether a stopped production needs wording of its own, which is a UX gap.

**Spec gate rulings (lead, 2026-10-28; policy 6df0676):**
- V1 (`FixRun.Copies`): ruled `veto`, inbox U-139, kept as planned.
- V2 (the end of a run that resent copies stays 7.4's): ruled `veto`, inbox U-140: Story 7.4 gains the acceptance criterion "two approved requests' results are each their own once copies were resent" in `epics.md`. This story pins the results it sends itself.
- V3 (the two couldn't-start reasons): ruled `veto`, inbox U-141, kept as planned.
- V4 (a stopped production renders as "had changed since the dry run"): routed to Story 7.4, which owns the result texts, as DW-368 (with its `DW-368:` bullet in 7.4's block). This story keeps AD-16 and the convention as written and pins the Skipped counts only; it adds no text.
- `Test/Install/Production.cls` (contended: Epic 13 lists the file): the orchestrator ruled (a) allowed, as decide (policy 6df0676, 2026-10-28T22:4xZ). Change ONLY Lane A's own `FixExecutor` row (L628, `"stub": 1` to `"stub": 0`) and the `TestStubsAnswer` doc clause (about L13: add "FixExecutor (built in Story 7.3)" next to the other built items). Nothing else in the file changes; the row is shared by row, like `Test/Core/ProductionItems.cls`. Epic 9 (live) also edits that doc line and its own EvalIn/EvalSink rows (L626-627) on its branch; that is a plain union at its integrate-forward, so keep the edit to the row and the clause minimal.

**Decided in-stage (small, reversible, within the intent):**
- **The order of the checks** is FixExecutor's order above. A refused `Execute` is one info line and OK. A `FixRun` is written for each approved request that FixExecutor takes up, couldn't start included ("one per approved request" in the data model), so that 7.4 can store that request's result there.
- **The order of a couldn't start** is `FinishExecution` first, then the `FixResult`, so the event that follows shows the row as `failed`. `Total` is the number of `FixTargets` entries.
- **The result of a finished run** is `done` for a run that started and reached its end; `failed` is only for couldn't start and `NOREAD`.
- **"Body unchanged"** is read as the dry run judged it: the body is still there, the field is a stored datatype property, and its value still reads in the source format. The copy is built only if the value still equals what the re-check read. No digest is kept, because U-126 fixes the row's columns. Residual risk 3 follows from this.
- **"Not resent"** is read as IRIS's own mark: a `Resent <ids>` description in the original's session, which also covers a resend from the portal. It is read through Reader, under AD-3.
- **"The incident's trace links to the copies"** is read as: the `FixRun` named by the request's Ref and the incident's Ref holds the copies' header ids, and the `Execute` lies in the incident's trace session. Showing links to the copies on the page is Epic 6's and Epic 11's.
- **The field on the copy** is set through the compiled dictionary's stored, non-calculated datatype property whose `Name` equals the field exactly, so a parameter never names a method or a getter.
- **The result Notification** carries no `DecisionRef`, as `answered` does not. A progress `FixResult` sends none (Story 30.5).
- **FixExecutor's other requests** get error 5001, which names the class (IncidentManager's pattern).

**Copy recognition is Story 7.4's.** Its criterion reads "its failure, recognised by its registered header id, is attributed to the fix instead of opening a new failure group or incident". 7.3 registers each id (V1) and pins the registration, and no 7.3 test makes a copy fail again.

**Ledger inbox:** this story owns no entries. For DW-347 (`wontfix-accepted`), the Verification mutation "DW-347" turns `Test.Fix.Raise.TestRejectChangesNothing`'s OCUORDERS check red, so its reopen probe is met.

**Governing ADs:**
- AD-1: items by name.
- AD-2: the bridge's `Gate.MissingOf`.
- AD-3: Reader reads, and Executor's one switch resends.
- AD-4: scope.
- AD-5: append-only storage.
- AD-11: the row and the API.
- AD-12: publishing after the commit.
- AD-15: the table and the one writer.
- AD-16: the executor.
- AD-17: the Approval entries come through the API; the Action entry is Story 7.4's.
- AD-22: throwaways and the mock log.
- AD-24: no `%Ens_MessageEditResend`.
- AD-26: the sessions.
- AD-29: Lane A.
- AD-32: kinds `answered` and `result`, slots only.
- AD-33: the owners.

Conventions: "Result texts", "Approval requests", "Later requests", "Audit entries", "Messages", "Redaction".

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Integration ACs:**
  - AC 5: WebChatOut records the `result` Delivery row, and `Catalog.Render` gives the couldn't-start text.
  - AC 1: WebChatOut records the `answered` Delivery row.
  - `IncidentManager` turns `FixExecutor`'s `FixResult` into the move and the notice.
- **Consumes:**
  - 7.1: `Fix.Kind`, `Reformat`, the grant, `Snapshot`.
  - 7.2: the row's columns, `Outcome`, `Move` and `Tell`.
  - 7.6: one `Execute` per approved request, and the two requests.
  - 5.5: `Transitions`, `Result`. 5.1: `Reader`.
  - Story 3.x: `StartExecution` and `FinishExecution`.
  - Epic 0: the keys and the messages. Epic 6: `WebChatOut`, `SimPhoneOut`. 0.10: the Orders production.
- **Consumed-by:**
  - 7.4: the wait and its counts; `Copies` for the recognition (it adds the element index); DW-272's stored result; the Action entry; the 500-message run.
  - 7.5: `FixRun` and `executing` for `Reconcile`; `ResultKey` for the interrupted result.
  - 30.5: `result.stillResending`.
  - Epic 6: editing the answered and result messages in place by `ApprovalRef`.
  - Epic 11: the demo path. Epic 14: `RESOURCES` and `NOTALLOWED`.

**Extend, don't copy (Rule 2):**
- `Gate.MissingOf` is lifted out of `MissingPrivilege`.
- `Reader.Evidence` gains a flag: no second reader and no second switching method.
- `ResultKey` sits beside `WithFixSlots`.
- `AnswerNotice` gains the approved case, and `Result` uses `Event`'s notification argument.
- One target test is shared by `DryRun`, `Recheck` and `Execute`.
- `ExecutorProbe` follows `IncidentProbe`.
- `Case.RaisedTwo` calls `Raised`, and `WAITLATER` is lifted into `Case`.

**Spine notes for the lead (Rule 20 candidates):**
- A Conventions row "Fix runs": `FixRun.Copies`, the couldn't-start routes and their reasons, and the end-of-run split between 7.3 and 7.4.
- V4's ruling.

**Residual risks:**
1. Until Story 7.4, a copy that fails again joins its group as a later failure.
2. Until Story 7.4, a run that resent copies stays `executing` and `fixing`.
3. A change to another field since the dry run is not seen, because no digest is kept.
4. A crash between a resend and its registration loses that one id (Story 7.5).
5. The resends carry IRIS's own audit and the Approval entries, and no OcuTalon `Action` entry yet (Story 7.4).

**Size:** planned as one story (`oversized`). If the lead splits it, the seam is 7.3a and 7.3b:
- 7.3a: the approved notice, FixExecutor's gate (refusals and couldn't start) and the result notice (AC 1-5);
- 7.3b: the re-check, the resend, `Copies` and the two runs (AC 6-8).

**Footprint:** `Fix/**`, `Data/FixRun.cls`, `Watch/{IncidentManager,Notice,Reader}.cls`, `src/bridge/**` (`Gate`), `Test/Fix/**`, `Test/Watch/**`, and `Test/Data/Tables.cls` (its own entry). The footprint extension (Rule 11(b)) is `Test/Install/Production.cls`, Lane A's `FixExecutor` row and its doc line, which removing `STUB` requires. No contended path is touched.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root.
- Run one command per tool call, with `timeout: 600000`, in the foreground, and never two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll such a run to completion in bounded foreground calls before doing anything else.
- **Tests run only on throwaways, never on `ocutalon-slot-a`.**
- Classes driven by IncidentManager and FixExecutor run fresh.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e7s3iw ci/warm.sh up`, once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s3iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Watch.Tell`, `OcuTalon.Test.Fix.Executor`, `OcuTalon.Test.Fix.Kind`, `OcuTalon.Test.Bridge.Gate`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Install.Production`. Expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e7s3i ci/iris.sh class <Class>`, fresh, one call per class: `OcuTalon.Test.Fix.Execute` (first, with Task 0), `OcuTalon.Test.Fix.Runs`, `OcuTalon.Test.Fix.Refused`, `OcuTalon.Test.Fix.Recheck`, `OcuTalon.Test.Fix.Raise`, `OcuTalon.Test.Fix.Later`, `OcuTalon.Test.Fix.DryRun`, `OcuTalon.Test.Watch.Closing`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e7s3i ci/iris.sh shard lane-a --part k/12` for k = 1 to 12, one call each. Earlier, 78 classes took 395, 248 and 432 s in thirds; with this story there are about 83. Expected: passed. Record each part's time.
- (once) `<lane> OCUTALON_RUN_TAG=e7s3i ci/iris.sh shard lane-b --part k/3` for k = 1 to 3, one call each. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e7s3i ci/iris.sh live storage-roundtrip`. Expected: passed (`FixRun`'s Storage block).
- (once) `bash ci/checks.sh`. Expected: every script passes.
- (once) `<lane> OCUTALON_RUN_TAG=e7s3iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e7s3i ci/iris.sh teardown`. Run both after a failure too.

**Shared surfaces:**
- FixExecutor is no longer a stub. This changes `Test.Install.Production` (the oracle row and the doc), `Test.Fix.DryRun.TestOtherRequest` and `Test.Watch.Closing.TestApproveSendsExecuteToFixExecutor`.
- `answered.approved` is now sent. This changes `Test.Watch.Lifecycle.TestApprovalOutcomes` (L276, L351) and its doc.
- A result Notification now goes out with every accepted final `FixResult`. In `Lifecycle`, `TestFixResults` and `TestLaterRequestWhileFixing` read `Sent` before their results and stay unchanged.
- `FixRun`'s columns: `Test.Data.Tables`, the `storage-roundtrip` unit and the storage checks of `ci/checks.sh`.
- The `Fix.Kind` contract: `Test.Fix.Kind.TestContract`.
- `Reader.Evidence`'s new flag defaults to 0, so `Test.Watch.Reader`, `Test.Watch.Evidence` and `EvidencePack` stay unchanged. `Gate.MissingOf`: `Test.Bridge.Gate` stays unchanged.
- In `Case`: `DropIncidentRows` also deletes FixRun rows, `WAITLATER` moves there (Later inherits it), and `RaisedTwo` is new.
- The lane-a shard gains five test classes.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte-identically, and record a `mutation: … → …` line here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | `AnswerNotice` gives "" for approved | `Lifecycle.TestApprovalOutcomes`, `Execute.TestApprovedRepairsAreResent` |
| AC 2 | a property is added to `FixResult` | `Lifecycle.TestFixMessages` |
| AC 3 row alone | Executor takes the targets from the incident's groups (`AskedKeys`) instead of `FixTargets` | `Runs.TestTwoApprovedRequestsRunOneEach` (R2's copies and `Total`) |
| AC 3 atomic | Executor skips `StartExecution` | `Execute` (the row is not `executing`; a second Execute adds a FixRun and copies) |
| AC 3 and 5, resources | `Missing` always gives "" | `Execute.TestCouldNotStart` |
| AC 4 | the approved check is dropped and `StartExecution`'s error is ignored | `Refused.TestNoApprovedRowNoRun`, `Executor.TestRefusedStates` |
| AC 5, notice | `Result` passes no notification | `Execute.TestCouldNotStart`, `Lifecycle.TestResultNotices` |
| AC 5, finish | couldn't start skips `FinishExecution` | `Executor.TestCouldNotStartRoutes`, `Execute.TestCouldNotStart` |
| AC 6 | `Recheck` passes every target | `Recheck.TestChangedTargetsAreSkipped`, `Runs` (R1 resends) |
| AC 6, resent | `Evidence` ignores `resent` | `Recheck` (the target resent by hand passes) |
| AC 7, repair | `Resend` sends no new body | `Execute` (the copies' `OrderDate`) |
| AC 7, originals | `Resend` repairs, saves and resends the original body | `Execute` (the Snapshot diff) |
| AC 7, registration | `Copies` is never appended | `Execute`, `Runs` |
| AC 7, stopped | `ErrProductionNotRunning` ends the run with an error | `Runs.TestStoppedProductionSkipsEveryCopy` |
| AC 8 | a run reuses the incident's first `FixRun` | `Runs` |
| V2 | a final `FixResult` (`Completed` = `Resent`) is sent after the resend | `Execute` ("no FixResult yet"), `Executor.TestResentRunSendsNoResult` |
| key order | `ResultKey` tests `Skipped` before `FailedAgain` | `NoticeText.TestResultKeys` |
| DW-347 | `IncidentManager.Apply` also executes OWN for rejected, and the Executor skips its state check and ignores `StartExecution`'s error | `Raise.TestRejectChangesNothing` ("OCUORDERS did not change") |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-28).** This story is planned in full against the READY FOR DEVELOPMENT standard. The plan stage made no runtime call (no slot read and no throwaway); Task 0 belongs to the implement stage.

Four items need the lead's ruling at the spec gate. Each is planned as recommended, and none blocks the build:
- **V1 (veto, schema):** `FixRun.Copies`, a list of the copies' header ids, appended.
- **V2 (veto, AC split):** how a run that resent copies ends stays Story 7.4's. Proposed: Story 7.4 adds the pin for two requests' results.
- **V3 (veto, public text):** two new couldn't-start reasons, `UNUSABLE` and `NOREAD`.
- **V4 (for the owner, not blocking):** a stopped production renders `result.skipped`'s "had changed since the dry run".

There is one footprint extension: `Test/Install/Production.cls`, Lane A's row. There is no AD amendment, no NFR tripwire and no contended path. DW-347's reopen probe is met by the mutation of that name.
