---
title: 'An approved tool call runs exactly once, with no model'
type: 'feature'
created: '2026-10-30'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A risky tool call in a user's turn is held as a `tool_call` approval request (Story 3.6), but approving it does nothing. `Approval.HoldResponse` sends nothing for an approved `tool_call`, `Decide` and the runner answer kind `tool` with "not implemented", and the row does not record which tool class made the call or which runner made it. The hold can also lose its delivery: an answered or expired row whose hold ended without delivering (DW-192), or a late start that creates a task after `Raise` deleted the row (DW-195). Story 2.8's live `approval.result` path is never fired for a tool call (DW-99).

**Approach:**
- On approval, `ApprovalHold` sends a `tool` request (the approval `Ref` in `ItemId`) through `Decide` to the runner the row names.
- That runner calls `StartExecution`, sets a context with provenance `user`, the `Ref` and a process-private grant built from the row, and calls `..Agent.ToolManager.ExecuteTool` with exactly the stored call. It then writes the action audit entry and calls `FinishExecution`, which fires `approval.result`. No AI session is opened and no model is called.
- The gate consumes the grant at the first matching call, and denies every other call in that context.
- The row gains `ToolSource` and `Runner` (DW-194).
- The hold never ends while its row is pending or owes an outcome, it refuses a late start, and `Reconcile` delivers what lost holds owed.

## Boundaries & Constraints

**Always:**
- "Runs exactly once" is the owner's guarantee (NFR-13). `StartExecution`'s atomic `approved` to `executing` change is the single gate of a run. A repeated answer, a repeated or concurrent replay, a `Reconcile` and a second `ExecuteTool` inside one replay never run the call a second time.
- The replay goes through `ExecuteTool` and the whole policy chain: the gate's classification, permissions and provenance rules, then the grant in place of rule 4, then the step audit. The approval path stays governed exactly as it is.
- The grant lives only in the runner's process (`^||` global), is built from the `executing` row (name, the hash of the canonical arguments, source), is consumed at the first matching call, and is gone when the context ends.
- The gate never modifies the replayed call. The runner passes exactly the row's `ToolName` and `ToolArguments`.
- No model request is made for a `tool` request. Decide skips its precheck, and the runner never calls `Chat` or creates an AI session for it. The mock's request log is the evidence.
- The caller learns the outcome only through the row (`Result`, `FinishedAt`, `ToolName`) and `approval.result` (`{"ref"}`). The tool's result text reaches no row column, no `Reply`, no `Decision` row and no event payload. It appears only in the step record of the trace, like any tool step.
- Every state change goes through the `Approval` API under its lock (AD-11). `ApprovalHold` gains no property and no method: the logic stays in `Approval` (AD-5).
- The bridge names no OcuTalon package (AD-2). Only `Bridge.Audit.Record` writes the audit log (AD-17). No callback (gate, tool, renderer) calls into AI Hub's native library (AD-6).
- New persistent properties are appended. The existing `Storage` block stays, and the compiler-appended slots are exported back verbatim (AD-5).

**Never:**
- Never edit Lane B classes (`Core.BridgeSink`, `Conversation`, `Data.Ownership`, `Live.*`), `Install/**`, `Production.cls`, `ApprovalHold`'s members, or `Msg.Request`'s properties.
- Never raise a new approval request from a replay context. Never retry a replayed call that failed.
- No new public text and no catalog key. A replay denial reuses the gate's `FAILED` sentence.
- No `SystemNote` producer (Lane B's; see Design Notes).
- Never run these tests on slot A.

## I/O & Edge-Case Matrix

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Approved call replays (AC 1, 3) | ChatAgent runs `ZzReplayAgent`; the gate holds `zz_replay_send` with args `{"b":2,"a":{"y":1.0,"x":"é"}}` in a context with Runner `ChatAgent`; the row is approved through `Answer` | Hold sends one `tool` request (ItemId = Ref) to `Decide`, which sends it to `ChatAgent`. The tool ran exactly once (`^OcuTalonTest("Replay","ran",…)` = 1). Row `done` with `Result` done and `FinishedAt` set. One Decision row of kind `tool`, ItemId = Ref, Outcome `act`. The host sink got `approval.result` `{"ref":Ref}` once, owned by the row's OwnerRef, with the row `done`. Zero model POSTs between the mark taken before `Answer` and the row being `done`. | -- |
| 2 | Real consumer (DW-99, Integration AC) | As 1, with the production's own HostSinkClass (`Core.BridgeSink`) and the row owned by a real session | That session's live stream gets an `approval` event with `ref` = Ref, `state` done and `result` done, after the replay | -- |
| 3 | Repeated answer (AC 4) | Approve, then approve again (and reject) | Second and later answers `already_answered`; the tool ran once | -- |
| 4 | Repeated replay (AC 4) | After 1: (a) a second `tool` request for the Ref to `Decide`; (b) the same request straight to the runner; (c) `Reconcile` | (a) answered from the recorded `tool` row, runner not reached; (b) `StartExecution` refused, no `FinishExecution`, failure reply; (c) nothing started. Ran once. | -- |
| 5 | Gate, replay context (AC 2) | Context Kind `tool` with a grant from an `executing` row | First call matching name, canonical-arguments hash (key order and number spelling ignored) and source: allowed and the grant consumed. A second matching call is denied `FAILED`, and `ExecuteTool` raises `<%AICore>ToolAccessDenied`. A call differing in name, an argument value or source: denied `FAILED`, grant kept. No grant: denied `FAILED`. None of these raises an approval request. | Fails closed |
| 6 | Source on a replay (AC 2, Task 0) | (a) metadata without `origin_class` and a grant whose source is X; (b) live: the row's ToolSource names another class than the tool's | (a) the source comes from the grant (the row) and the call is allowed; (b) `origin_class` arrives, so the call is denied, the row is `failed` and the tool ran 0 times | -- |
| 7 | Tool raises | Live: approve `zz_replay_throw` | Row `failed` (Result failed); action entry result failed; `approval.result` fired; no retry | -- |
| 8 | Couldn't start | Approved row past `ExpiresAt` when the runner takes it | `FinishExecution(failed)`, row `failed`; no action entry; tool ran 0; failure reply | -- |
| 9 | Unroutable row | (a) Approved `tool_call` row with empty `Runner`; (b) no row, or a fix row | Decide sends to no runner and answers a fallback Reply (reason error), recorded like any fallback. Ran 0. (a) is closed `failed` through `FinishExecution`; (b) leaves every row unchanged. | -- |
| 10 | Audit read-back (AC 5) | Test answers and the replay runs | `Test.Bridge.AuditLog.Wait` finds the Approval entry (change answered) and the Action entry (action = ToolName, result done, approvalRef = Ref), each with its time, `irisUser` = the answerer and `sessionRef` | Polls with a timeout |
| 11 | DW-192, task outside Answer | Hold's task completed with Approve while the row is pending | The hold re-arms (a new task and a timer from `ExpiresAt`), stays live, and the row stays pending. A later `Answer` approve is delivered once. | -- |
| 12 | DW-192, Expire fails | Hold timer fires while the test holds the row's lock past 7 s | Row still pending, so a retry timer (`RETRYSECONDS`) is set. After the lock is released: row `expired`, one `ApprovalOutcome` expired to `ResultTarget`. | Warning names the Ref |
| 13 | DW-192, Reconcile delivers | Fixture rows with no hold: an expired fix row with `ResultTarget`, no outcome message and `ExpiresAt` within 7 days; an approved `tool_call` | One `ApprovalOutcome` expired; one replay (ran once). A fix row that already has its outcome message, or is older than 7 days, and cancelled, done and failed rows get no hold. | -- |
| 14 | DW-195, late start | A pending fixture row; `StartHold` while `ApprovalHold` is disabled (times out after `STARTSECONDS`); then enable | The late start is refused by its age: no Workflow task, no timer, no live hold, row unchanged | Error names the Ref and the age |
| 15 | DW-194, row fields | A held call | Row `ToolSource` = the gate's source (`origin_class` or the `mcp:` toolref), `Runner` = the context's runner item. `Raise` refuses either on a fix. | Refusal names the field |
| 16 | No result text | As 1; `zz_replay_send` returns `ZZ-REPLAY-RESULT-5182` | The marker is in no column of the approval row or the Decision row, not in Decide's Reply to the hold, and not in any recorded sink payload | -- |

</intent-contract>

## Code Map

Paths: `src/bridge/cls/OcuTalon/Bridge/…` is shortened to `Bridge/…`, and `src/ocutalon/cls/OcuTalon/Test/…` to `Test/…`.

**The hold and the approval API**
- `Bridge/Approval.cls`:
  - `:46-53` LOCKSECONDS, STARTSECONDS (10) and TASKSECONDS.
  - `:74-125` Raise/SaveAndStart: deletes the row when StartHold errs, which DW-195 races with.
  - `:133-168` StartHold.
  - `:171-212` Validate: the tool_call/fix field rules; add ToolSource and Runner here.
  - `:367-386` StartExecution (`ahead` = 1) and FinishExecution (`approved`→failed only with failed).
  - `:395-442` Move/MoveLocked.
  - `:466-492` Audited: started and finished name the approver.
  - `:559-578` Hold.
  - `:592-625` HoldResponse: step 5 sends nothing for an approved tool_call (`:615`); the expiry key delivers the row's state (`:611-612`).
  - `:629-644` LiveHold/IsLive.
  - `:653-688` Reconcile, whose pass 2 is pending rows only.
  - `:691-700` OwnedByLiveHold.
- `Bridge/Process/ApprovalHold.cls:1-33`: one property, OnRequest and OnResponse, each one line. `Test.Bridge.Approval` HoldIsFrozen pins it. Unchanged.
- `Bridge/Service/ApprovalStart.cls:10-23`: the synchronous send, with STARTSECONDS.
- `Bridge/Msg/ApprovalOutcome.cls`: SQL table `OcuTalon_Bridge_Msg.ApprovalOutcome`, with `ApprovalRef`. Reconcile's "already sent" check reads it.

**The row, the request and the context**
- `Bridge/Data/ApprovalRequest.cls:30-75`: properties. `:83-162`: Storage, slots 1-23 (`^OcuTalonBP.ApprovalD`).
- `Bridge/Msg/Request.cls`: Kind, Provenance, Input, ItemId, Summary, OwnerRef, TraceRef, Channel and ThreadSessionId. Unchanged; `Test.Bridge.Contracts:118-135` pins it.
- `Bridge/Msg/Reply.cls`: Text, ToolsRun, Steps, FailureText and Busy.
- `Bridge/Context.cls:13` FIELDS, `:59-75` Begin, `:90-108` Current/Put. It lives in `^||OcuTalonBP.Context` and is already a callback helper.

**The gate**
- `Bridge/Policy/Gate.cls`:
  - `:89-116` %CanExecute/Check.
  - `:119-135` Decision: permissions `:125`, then provenance/taint `:127`, then Hold `:128`, then ReportStep and taint.
  - `:139-162` Hold: the row from the call and the context.
  - `:165-170` Source.
  - `:347-375` ArgumentsOf/ArgumentsObject: an object, or a JSON string.

**Decide**
- `Bridge/Process/Decide.cls`:
  - `:97` RUNNERS.
  - `:235-264` OnRequest: one decision per item at `:240`, ReplyClass for non-turn kinds at `:244-248`, Held, Precheck, send and timer.
  - `:303-342` OnResponse: RunnerFor again at `:306`, ReplyClass at `:336-339`.
  - `:481-494` Admit: tool gives NotImplemented at `:486`, and an empty Input is refused.
  - `:498-507` RunnerFor.
  - `:526-541` CheckSettings: only turn skips ReplyClass.
  - `:739-807` Conclude.
  - `:887-918` RecordFallback.
  - `:1009-1024` ResponseFromRow, which refuses turn rows; tool must give a Reply.
  - `:975-995` FireEvent.

**The runner**
- `Bridge/Adapter/Agent.cls`:
  - `:145-162` BuildAgent.
  - `:305-336` Answer: tool gives NotImplemented at `:309`, then the Input check, then `Context.Begin(request, superSession)` at `:316`.
  - `:401-444` Converse: StepBuffer.Start, ReadStats, Usage. The replay uses none but StepBuffer.
  - `:528-549` StepRecords/StepsJson, reused.
  - `:638-661` Inventory: the precedent for a non-Chat use of `..Agent.ToolManager`.
- `Bridge/Operation/AgentRunner.cls:24-38` OnMessage: its doc comment says "not implemented".
- `Bridge/Policy/StepAudit.cls:22-38` records name, origin_class, args and result per call.
- `Bridge/Adapter/StepBuffer.cls:37-46, 74-83, 104, 140` Start, Tool, Records and End.

**The audit**
- `Bridge/Audit.cls:22-36`: the shapes. Action is `action,target,result,counts,approvalRef` plus `irisUser,sessionRef,channel`, and its description is "<action>: <result>".
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls:500-521` ActionEntry: the field sibling, which the bridge cannot call (AD-2).

**Lane B, read only**
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls:55-57, 84-129`: all five `approval.*` events go to `Approved`, which reads `Ownership.Approval(ref, recipient)` and publishes `"approval"` with `Live/Payload/Approval.cls:64-77` (ref, kind, state, toolName, result, finishedAt, …).
- `Core/BridgeSink.cls:132-144`: `decision.recorded` has no Kind filter, but the rail shows `kind = 'decide'` only (`web/src/app/rail/rail-view.ts:327`; `Ownership.cls:722`). So a `tool` Decision row is not shown.
- No Lane B code sets `SystemNote` (only `Bridge/Adapter/Agent.cls:474-482` reads it).
- `src/ocutalon/cls/OcuTalon/Production.cls:18-36`:
  - Decide: HostSinkClass `OcuTalon.Core.BridgeSink`.
  - ApprovalHold, pool 1.
  - ApprovalStartIn.
  - Triage, Diagnosis and ChatAgent (`OcuTalon.Agent.Chat`).
  - OcuTalonApprovals.
  - Unchanged.

**Tests and fixtures**
- `Test/Bridge/Approval.cls`, live on the throwaway's production (`Ready()` 1544):
  - Raising: `NewRow` 1554, `Raise` 1575, `RaiseHeld` 2141, `FixtureRow(state, expiresIn, kind)` 2160, `Age` 1876.
  - Answering: `Answerer()` 2130 (user `ocutalon`), `Complete(taskId)` 1814 (outside Answer).
  - Waiting and reading: `WaitTask` 1736, `WaitHoldSettled` 1759, `WaitHoldGone` 1784, `HoldRequests` 2285, `Outcomes`/`WaitOutcomes`/`AssertOneOutcome` 2241-2282.
  - Sinks: `AssertEvents` 2296, `UseSharedSink` 2359.
  - Clean-up: `Clean` 1996, `Remove` 2031.
  - The tests that change: `ApprovedToolCallRunsNothing` 890 (becomes the replay), `HoldActsOnlyOnTheRowsAnswer` 1431 (re-arm), `ReconcileLeavesSettledRows` 713 (delivery), `StartTimesOut` 580 (DW-195), `TimerDeliversAnUndeliveredAnswer` 1467, and the `GIVENFIELDS` 91 and `RowText` 2199 lists.
- `Test/Bridge/Gate.cls`:
  - `Begin` 1595, `Call` 1939, `Meta` 1945, `Verdict` 1952, `AssertHeld` 1676.
  - `RunDenied` 2204-2250: a bare `%AI.ToolMgr` with RegisterToolSet, Gate, StepAudit, Context.Begin, StepBuffer.Start and ExecuteTool.
  - `TestDeveloperRiskyEndToEnd` 843 and `TestPrivilegeInProductionRunnerJob` 1128: rejected, expired and held calls never run. These stay green.
- `Test/Bridge/Decide.cls`: `TestRefusedRequests` 232-233 pins tool as 5003. `NewRecorder` 2780 and `ZzDecide` record the sends.
- `Test/Bridge/Runner.cls`: `TestUnbuiltKinds` 483-528 pins tool as 5003 with 0 mock requests. `NewRunner(agentClass,…)` 987 is a shadow host whose `%ConfigName` is `ZzRunner`.
- `Test/Agent/RunnerFixture.cls`:
  - `UseAgent(item, agentClass, .saved)` 524 swaps AgentClass and AgentAllowList and restarts the item; `RestoreAgent` 535 puts them back.
  - `SinkCalls(type)` 781.
  - `FindRequests` 918.
- `Test/Bridge/ZzGateTool.cls:187-198` `Ran`/`Mark`: the run counter in `^OcuTalonTest(...)`, the pattern for the new fixture tool. `Test/Bridge/ZzGateAgent.cls` is the agent sibling.
- `Test/Bridge/ProbeSink.cls`: `^||ZzProbeSink(n)` = `$LB(type, owner, payload, $TLevel, rowExists, markExists, lockHeld, approvalState)`, and shared mode.
- `Test/Bridge/AuditLog.cls:23, 30, 61`: `Now()`, `Entries(...)`, and `Wait(since, source, type, event, marker, username, count=1, seconds=10)`. Approval's `AssertEntry` 2078 is the shape check.
- Mock log: `Test/Contract/Mock.cls:471, 484` `LogMark()`/`LogSince(mark, .entries)`. `Test/Watch/Case.cls:1477` `Posts(mark)` counts POST `/v1/messages`.
- `Test/Data/Tables.cls:179-209`: ApprovalRequest's contract, an exact props list. This is our own entry.
- `Test/Bridge/CodeRules.cls:64-73` CALLBACKBASES/CALLBACKHELPERS (Context, Approval, Data.ApprovalRequest and Decide are already there), `:137` CHATTERS, `:143` SESSIONCALLS. `docker/tests/test-class-rules.sh:3` bridge-refs.
- `ci/units.sh:17`: `Bridge` is in lane-a, so `Test.Bridge.*` runs in CI group `shards-2` (`@rest`). No `ci/units.sh` change.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 -- measure on the warm stack and record under Design Notes "Measured": (a) what `ExecuteTool` does for a tool that raises: does it raise, or return an object without `value`? (b) the ApprovalStart header's `TimeCreated` as the hold sees it (`hold.%PrimaryRequestHeader.TimeCreated`, UTC) and the age of a start taken late (row 14); (c) the result of row 6b, which confirms `origin_class` in the runner job. Both rules below are planned either way.
- [ ] `Bridge/Data/ApprovalRequest.cls` -- append `ToolSource As %String(MAXLEN = 512)` ("the class or MCP toolref the gate classified a held call by") and `Runner As %String(MAXLEN = 128)` ("the runner item whose job held the call"). Keep the Storage block. Compile on slot A and write back the compiler's appended `<Value name="24">`/`"25"` verbatim -- DW-194 (V1).
- [ ] `Bridge/Context.cls` -- the runner field and the grant:
  - a `Runner` field, in FIELDS, set by `Begin(request, superSession, runner = "")`;
  - `Grant(ref)`, which builds `^||OcuTalonBP.Context("grant")` = `$LB(ref, ToolName, ArgumentsHash(ToolArguments), ToolSource)` from the row, only when the row is a `tool_call` in state `executing`, else returns an error;
  - `TakeGrant(name, arguments, source) As %Boolean`, which kills the grant on a match;
  - `GrantSource()`;
  - `ArgumentsHash(arguments)`: an object or JSON text, made canonical (object keys sorted recursively, arrays in order, numbers as `+value`, strings and literals by type), then SHA-256 of the UTF-8 text, base64.
  - The grant is not in FIELDS, so `Current`/`Put` never expose or set it. `Begin`/`End` kill it.
  - -- AC 2, process-private.
- [ ] `Bridge/Policy/Gate.cls` -- the replay context:
  - `Hold` gets the source and sets `ToolSource` = source and `Runner` = `context.Runner`.
  - In `Decision`, when `context.Kind = "tool"`: an empty source is taken from `GrantSource()` before classification (row 6a). After the permission and provenance checks, `TakeGrant` replaces rule 4: a match runs ReportStep and the taint, then allows; anything else is `Denial(FAILED)`, never `Hold`.
  - Update the class comment.
  - -- AC 2, DW-194.
- [ ] `Bridge/Replay.cls` (NEW) -- `Run(adapter As OcuTalon.Bridge.Adapter.Agent, request, superSession, Output reply) As %Status`, the runner's replay, in AC 1's order:
  1. `Approval.StartExecution(ItemId)`. When it refuses and the row is still `approved` with `ExpiresAt` past, call `FinishExecution(ref, "failed")` (couldn't start). Any other refusal changes nothing. Either way, reply with FailureText and ToolsRun 0.
  2. Once started, in a try: `adapter.BuildAgent()`, `Context.Begin(request, superSession, runner)`, `Context.Grant(ref)`, `StepBuffer.Start(0)`, then `adapter.Agent.ToolManager.ExecuteTool(row.ToolName, {}.%FromJSON(row.ToolArguments))`. The result is done when it returns a result with `value`, else failed (Task 0a). A raise is failed, and its redacted, cut text becomes the FailureText. The returned value is discarded.
  3. One Action entry through `Audit.Record`: action = ToolName, target = ToolSource, result, counts {}, approvalRef = Ref, irisUser = AnsweredBy, sessionRef = OwnerRef when it is a Ref, channel = AnsweredChannel else system. Then `FinishExecution(ref, result)`. A failed write or finish is a warning naming the Ref.
  4. Reply: no Text, no HostData, Tainted 0, ToolsRun 1, Steps from `StepRecords`.
  5. Context and StepBuffer end on every path.
  6. No `Chat`, no session, no Usage row.
  - -- AC 1, 3, 5.
- [ ] `Bridge/Adapter/Agent.cls` -- `Answer`: kind `tool` returns `##class(OcuTalon.Bridge.Replay).Run($this, request, superSession, .reply)` before the Input check. Every other kind's `Context.Begin` passes `..BusinessHost.%ConfigName` as the runner. Make `BuildAgent` callable by Replay, and update the doc comments. `AgentRunner.cls` gets a doc comment only -- AC 1, DW-194.
- [ ] `Bridge/Process/Decide.cls` -- kind `tool`:
  - Admit requires Provenance `user` and an ItemId that is a Ref (`Approval.IsRef`), and does not require an Input.
  - One decision per item: `ResponseFromRow` gives a tool row a Reply (DecisionRef, Outcome, Fallback, FallbackReason, totals).
  - The runner is the row's `Runner`, found by `RunnerFor` with the request (OnRequest and OnResponse).
  - No ReplyClass, no Held probe, no Precheck.
  - Send and timer as for the other kinds.
  - Unroutable (row 9): `RecordFallback(error)`, after `Approval.FinishExecution(ref,"failed")` only for an approved `tool_call` row with an empty Runner. A missing row or a fix row is never changed.
  - Conclude for tool: a reply without FailureText records Outcome `act` with no reasons; one with FailureText goes to RecordFallback.
  - Update the comments.
  - -- AC 1, AC 4 (a repeat is answered from the row).
- [ ] `Bridge/Approval.cls` -- the hold and the API:
  - Parameters: `DECIDEITEM` "Decide", `RETRYSECONDS` 5, `DELIVERYDAYS` 7, `STARTMARGIN` 2.
  - `Validate`: a fix with ToolSource or Runner set is refused.
  - `Hold`, in order:
    1. Refuse a start whose header age is at least STARTSECONDS - STARTMARGIN (error naming the Ref and the age; an unreadable header proceeds).
    2. Then read the row. A pending row is armed through a private `Arm(hold, row, withTask)` (the task and the timer), shared with HoldResponse.
    3. An approved, rejected or expired row gets a delivery hold: `SetTimer(1, "expiry")` and no task.
    4. Any other state is an error.
  - `HoldResponse`:
    1. Approved tool_call (task or expiry key): send a `tool` Request (Kind tool, Provenance user, ItemId Ref, OwnerRef, TraceRef, Channel = AnsweredChannel else system, Summary = ToolName cut to 80, ThreadSessionId = the hold's session) to DECIDEITEM, key `replay`, response required.
    2. Key `replay`: nothing, but a warning when the row is still `approved`.
    3. After a task response whose action the row does not show: a pending row is re-armed with a task; an approved, rejected or expired row gets `SetTimer(1,"expiry")`, so the expiry step delivers what the row shows.
    4. After an expiry whose row is still pending: `SetTimer(RETRYSECONDS,"expiry")`.
  - `Reconcile` pass 3: every approved `tool_call` row with no live hold, and every approved, rejected or expired fix row with a ResultTarget, no live hold, `ExpiresAt` within DELIVERYDAYS and no `ApprovalOutcome` with its `ApprovalRef`, gets `StartHold(ref, "", TraceRef)`. Failures are combined.
  - Update the class and method comments.
  - -- AC 1, DW-192, DW-195.
- [ ] `Test/Bridge/ZzReplayTool.cls`, `ZzReplayTools.cls`, `ZzReplayAgent.cls` (NEW fixtures; ZzGateTool/ZzGateAgent pattern):
  - `zz_replay_send(…)` is risky in code. It counts runs in `^OcuTalonTest("Replay","ran",name)` and returns `{"note":"ZZ-REPLAY-RESULT-5182"}`.
  - `zz_replay_throw` is risky and raises an error when run.
- [ ] `Test/Bridge/Gate.cls` -- add in-process tests for row 5, row 6a and row 15 (AssertHeld checks ToolSource; a context begun with a runner checks Runner), and the hash cases (key order, `1.0` vs `1`, a changed nested value, array order). The row 5 governance test is a `RunDenied` sibling that runs ExecuteTool twice in one granted replay context: ran 1, then ToolAccessDenied. Fixture `executing` rows are saved and deleted by the test.
- [ ] `Test/Bridge/Decide.cls` -- replace the tool 5003 pin with recorder tests: Admit rules; the send goes to the row's Runner with no precheck; a recorded tool row answers a repeat as a Reply with no send; row 9.
- [ ] `Test/Bridge/Runner.cls` -- replace `TestUnbuiltKinds`' tool case. With a shadow `NewRunner("OcuTalon.Test.Bridge.ZzReplayAgent")` and fixture rows, test rows 4b, 7 and 8, a success reply (no Text, ToolsRun 1, a tool step), the grant gone after `Run`, and 0 mock requests (`LogMark`/`LogSince`).
- [ ] `Test/Bridge/Approval.cls` -- the live tests, with ChatAgent swapped to `ZzReplayAgent` via `UseAgent` and restored in `Clean`:
  - the held row comes from `Gate.Check` in a context begun with runner `ChatAgent` and `Meta("OcuTalon.Test.Bridge.ZzReplayTool")`;
  - rows 1, 2, 3, 4a, 4c, 6b, 9 (live), 10, 11, 12, 13, 14 and 16;
  - `ApprovedToolCallRunsNothing`, `HoldActsOnlyOnTheRowsAnswer`, `ReconcileLeavesSettledRows` and `StartTimesOut` are rewritten to the new rules, and `GIVENFIELDS`/`RowText` gain the two fields.
  - Each test creates and removes its own rows, holds, tasks and swaps.
- [ ] `Test/Data/Tables.cls` -- our own ApprovalRequest entry gains `"ToolSource": "%String(MAXLEN=512)"` and `"Runner": "%String(MAXLEN=128)"` -- DW-194.

**Acceptance Criteria:**
- Given an approved `tool_call` request, when ApprovalHold handles the outcome, then a `tool` request carrying its Ref goes through `Decide` to the row's runner. That runner calls `StartExecution`, sets a context with provenance `user`, the Ref and a process-private grant, calls `..Agent.ToolManager.ExecuteTool` through the whole policy chain and records `FinishExecution`, and the mock's log holds no model request for it (rows 1, 9).
- Given a live grant, when the gate sees the replayed call, then it consumes the grant at the first call matching name, canonical-arguments hash and source, and it denies a replay with no live grant, which `ExecuteTool` raises as `ToolAccessDenied` (row 5). And whether `metadata.origin_class` arrives on a replay is recorded from Task 0 and row 6b, with the row-source fallback in place (row 6a).
- Given the replay finishes, when ApprovalHold receives its result, then `HostSinkClass` has received `approval.result` with the Ref, the real `Core.BridgeSink` has published the `approval` event, and no result text left the trace (rows 1, 2, 16; DW-99).
- Given the NFR-13 tests in `OcuTalon.Test.Bridge`, when they run, then an approved request runs the call exactly once even when the answer or the replay is repeated (rows 3, 4, 5).
- Given a test answers a request and replays its approved test tool, when it reads the audit log back through `Test.Bridge.AuditLog.Wait`, then it finds the approval entry and the action entry, each with time, IRIS user and session (row 10).
- Given a hold whose delivery was lost, or a late start, when the hold or `Reconcile` runs, then rows 11 to 14 hold (DW-192, DW-195). And a held call's row names its source and runner (row 15, DW-194).

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6).**
- AD-10: the replay, the grant, its consumption, the denial and the source fallback. The gate's `top_k` and MCP rewrites are not built yet; nothing here rewrites a call.
- AD-11: the row is the truth, and changes only through the API under the lock. The hold acts on the row.
- AD-6: kind `tool` makes no model request, goes through Decide and a runner, and is never linked.
- AD-30: approved tool calls report back through the HostSink; the `SystemNote` is Lane B's (below).
- AD-31: `approval.result` fires after commit, in the job that changed state (the runner's), through `Decide.FireEvent`.
- AD-17: Approval and Action entries only through `Audit.Record`; tests poll.
- AD-5: append-only storage, and ApprovalHold frozen. The hold's state stays in the row.
- AD-2: the bridge names no OcuTalon package (the Action-entry builder is a bridge copy of `Fix.Executor.ActionEntry`'s shape).
- AD-33: Lane B classes are read only.
- AD-26: the replay request travels in the hold's trace session.
- AD-29: Lane A's bridge.
- AD-22: throwaway stacks.

**V1. DW-194 is a stored-data change. For the lead's ruling (veto window: how stored data is kept).**
- **Chosen:** two appended properties, `ApprovalRequest.ToolSource` (MAXLEN 512) and `Runner` (MAXLEN 128). The gate fills them from its own source and from the context's runner item. Fix rows refuse them. Old rows have them empty, and Decide closes such an approved row as failed (row 9) rather than guess a runner.
- **Rejected:**
  - (a) Deriving them from the decision's trace: the source of a held call exists only in its denied step's `AgentStep` message, which the message purge removes, and AD-11 makes the row the truth.
  - (b) Deriving the runner from the request kind (RUNNERS): the row holds no `DecisionRef` either, so a column is needed anyway, and a developer's runner item (FR-5) is not in RUNNERS.
  - (c) Packing them into `ResultTarget` or `ToolArguments`: ResultTarget drives `ApprovalOutcome` delivery, and ToolArguments is the exact call.
- **Recommendation:** add the two columns. The CI storage diff stays append-only (slots 24 and 25), and `Test.Data.Tables` gains our own two entries.
- **Lead rulings (spec gate, 2026-10-30):**
  - V1 kept: the two appended columns — veto item U-170 (the owner may reverse it before the release).
  - AD-6 read literally (decide; U7 step 1, comply first): the replay uses a throwaway AI session that is never linked — `NewSession`, released unsaved, as the "If the lead reads it literally" note below describes (about 3 lines). No model request is made on it. A test pins that no `ConversationLink` names it.
  - `Context.Runner` writable by tool code stands (decide): tools are developer code, and the gate copies it into the row at hold time.
  - Lane B need (1), the next turn's `SystemNote`: filed as DW-443 (`escalated`, for the decision sheet; recommended route: Story 31.2, Lane B). Not this story's work.
  - The residual `executing` tool_call row after a crash mid-replay: filed as DW-444 (`routed owner=burndown`). Not this story's work; the exactly-once guarantee holds (the call is never re-run).

**Decided in-stage.**
- The approval Ref travels in the request's `ItemId`. So `Msg.Request` is unchanged, and Decide's one-decision-per-item index (ItemId, Kind) also answers a repeated replay from its row. `Summary` = ToolName. A tool request has no Input, and Decide refuses one whose Provenance is not `user`.
- **The replay opens no AI session.** `ExecuteTool` needs none (measured below), so nothing is linked, saved or counted. AD-6's "throwaway AI session that is never linked" is read as satisfied by having no session. If the lead reads it literally, the replay calls `NewSession` and releases it unsaved (about 3 lines).
- The grant is built from the `executing` row, not from the request. A replay context denies every call that does not match it, with the existing `FAILED` sentence (no new text). It never holds. Classification, permissions and provenance still run first.
- The canonical hash is described under the Context task. Number spellings are normalised because IRIS keeps numeric text as written, while AI Hub hands the audit policy a re-serialised JSON (measured).
- `Context.Runner` is in FIELDS, so `Current()` carries it. Like Kind and Provenance it can be Put by tool code; tools are developer code, not untrusted content.
- The result is done when `ExecuteTool` returns, and failed when it raises or the result has no `value` (Task 0a). A failed replay is never retried.
- Couldn't start: only an approved row past `ExpiresAt` is closed failed by the runner. A refusal by lock timeout leaves it `approved`. The hold logs it, and `Reconcile` delivers it again at the next start.
- The Action entry is written only for a run that started. A couldn't-start run is visible in the Approval "finished" entry.
- The hold never ends while its row is pending or owes an outcome (re-arm, retry, delivery hold). `Reconcile` reads the `ApprovalOutcome` message as the record of a sent fix outcome, with a 7-day horizon (DELIVERYDAYS). Messages are kept 90 days (Story 30.2), so the record never vanishes within the horizon, and no new storage is needed.
- The late-start check uses the start message's header age, with a 2-second margin under STARTSECONDS. The residual race (a hold slower than the margin between its check and its reply) is (inference) negligible, and Reconcile still cancels orphan tasks at start.
- The live replay tests go into `Test.Bridge.Approval` to reuse its helpers rather than copy them into a new class (Rule 2).
- No change to `Answer`'s order. Its `approval.answered` fires after its unlock, and the replay cannot start before that unlock (StartExecution takes the same lock). Story 31.2 should read the row's state rather than rely on event order.
- Not planned (residual, no AC): an `executing` tool_call row left by a crash or restart mid-run stays `executing`. Closing it as `interrupted` at start would also hit a live replay when tests call `Reconcile`. The lead may route it.

**Measured at planning (Task 0, slot A, build 154, read-only and process-local: a bare `%AI.ToolMgr` with `ProbeTools` and `StepAudit` only, context OwnerRef `eval`, nothing persistent written).**
- `ExecuteTool("zz_context_probe", {"b":2,"a":{"y":1.0,"x":"e"}})` returned `{"timing":0.0174,"value":{"seen":1}}`.
- The audit policy got `origin_class` = `OcuTalon.Test.Bridge.ProbeTool`, the implementing class (not the toolset), and arguments `{"a":{"x":"e","y":1.0},"b":2}` (keys sorted, `1.0` kept). So `origin_class` arrives through `ExecuteTool` on build 154 (with Story 3.2's measurement for the auth policy). The runner-job case is row 6b.
- IRIS round-trips `{"a":1.0,"b":1e2,"c":0.50,"d":-0}` unchanged.

**Contended edits:** none. `Test/Data/Tables.cls` is shared by entry, and only our own ApprovalRequest entry changes.

**Lane B needs (AD-33), not planned:**
- (1) Nothing turns `approval.result` into the next turn's code-written `SystemNote` (the tool, done or failed, and the time; AD-30). `Conversation` (or `Core.BridgeSink`) would read the row through `Ownership.Approval` (ToolName, Result, FinishedAt) and set it on the session's next turn. Story 31.2's criteria name notifications, not the note, so the lead may route it.
- (2) `Live.Payload.Approval` needs nothing new.

**Integration ACs (Rule 1).** Matrix row 2: `Core.BridgeSink` (Lane B, the real HostSinkClass of the throwaway's production) reads the replay's `approval.result` and publishes the `approval` live event with state done to the owning session.
- **Consumed-by:**
  - Story 31.2: tool-call `answered`/`result` notifications from `BridgeSink`, which waits for Epic 30.
  - Story 13.2: the example's own risky tools replayed.
  - Story 2.8: the rail's approval updates (DW-99).
  - Lane B's `SystemNote` need, above.
- **Consumes:**
  - The `Approval` API (Stories 3.4, 3.5) and the gate and `Raise` (3.2, 3.6).
  - `Decide` and the runner (Epic 0, Story 1.x).
  - `Bridge.Audit` and `Test.Bridge.AuditLog` (3.7).
  - `Core.BridgeSink` (2.8, read only).
  - `RunnerFixture.UseAgent`, `Contract.Mock.LogMark`/`LogSince` and `Watch.Case.Posts`.

**Extend, don't copy (Rule 2).**
- `Arm` is extracted from `Hold` and reused by `HoldResponse`.
- The delivery hold reuses HoldResponse's expiry step.
- Reconcile pass 3 extends `Reconcile`.
- `Replay` reuses `BuildAgent`, `StepBuffer` and `StepRecords`/`StepsJson`.
- The Action entry's fields copy `Fix.Executor.ActionEntry`'s shape, because the bridge cannot name `OcuTalon.Fix` (AD-2).
- The Zz fixtures follow `ZzGateTool`/`ZzGateAgent`. They are separate because a new tool on `ZzGateAgent` would change the Gate tests' agent.
- The Gate replay governance test is a sibling of `RunDenied`, with the second call allowed by a grant.

**Spine note for the lead (Rule 20), optional.**
- AD-11's row list could name `ToolSource` and `Runner`.
- AD-10's replay could say that the grant is built from the executing row, that the replay opens no AI session, and that the request carries the Ref in `ItemId`.

**Ledger inbox (Rule 17):**
- DW-99: addressed (row 2, the replay task).
- DW-192: addressed (rows 11-13, the Approval task).
- DW-194: addressed (row 15, V1).
- DW-195: addressed (row 14, Task 0b).

**Files outside "Ours":** `Test/Data/Tables.cls` (shared by entry). Every other file is in `src/bridge/**` or `Test/{Bridge,Agent}/**`, or is new.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. The fresh tag is `e30s3i` and the warm tag `e30s3iw`.
- One command per tool call, in the foreground, with `timeout: 600000`. Never run two IRIS test runs in one message. The harness moves a call to the background after about 180 s; poll it to completion in loops of under 170 s, and never start a second copy.
- **Throwaway stacks only.** These tests create approval rows, Workflow tasks, timers, grants, audit entries and an agent swap. The recipe is `ci/iris.sh class|shard` with the lane's variables: warm for the loop, and fresh for the (once) shards, which also prove the start's Reconcile change.
- On `ocutalon-slot-a` (`server` `ocutalon-slot-a`, `namespace` `OCUTALON`, checked with `iris_server_info`, build 154), only load and compile the changed classes (`iris_doc_load`, `baseDir` `src/bridge/cls` or `src/ocutalon/cls`). Then export ApprovalRequest's compiled Storage block back into the file.
- Tear down only your own tags, after a failure too.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e30s3iw ci/warm.sh up`, once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s3iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Bridge.Gate`
  - `OcuTalon.Test.Bridge.Decide`
  - `OcuTalon.Test.Bridge.Runner`
  - `OcuTalon.Test.Bridge.Approval` (first with Task 0)
  - `OcuTalon.Test.Bridge.CodeRules`
  - `OcuTalon.Test.Bridge.Contracts`
  - `OcuTalon.Test.Bridge.Ext`
  - `OcuTalon.Test.Data.Tables`
  - `OcuTalon.Test.Core.BridgeSink` (consumer, unchanged)
- (once) `bash ci/checks.sh`. Expected: every script passes (bridge-refs and storage included).
- (once) `<lane> OCUTALON_RUN_TAG=e30s3i ci/iris.sh shard lane-a --part k/6` for k = 1 to 6, fresh, one call each. Expected: passed, with each part's time recorded.
- (once) `<lane> OCUTALON_RUN_TAG=e30s3i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e30s3iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s3i ci/iris.sh teardown`, also after a failure.

**Shared surfaces:**
- **The ApprovalRequest contract** (+2 columns): `Test.Data.Tables`, and Approval's `GIVENFIELDS`/`RowText`.
- **`Context.FIELDS`** (+Runner): ProbeTool's snapshot, `Test.Bridge.Runner` TestContext, `Test.Bridge.Ext` and `Test.Core.CommandsContext` iterate it. Search for exact lists.
- **Kind `tool`** is now served: `Test.Bridge.Decide` and `Test.Bridge.Runner` pinned 5003.
- **The hold's rules:** the four Approval tests named in the Code Map, and `Test.Bridge.Gate` AssertHeld.
- **Reconcile** now starts holds for answered and expired fix rows with a ResultTarget, and for approved `tool_call` rows. Search the test trees (`Test/Fix`, `Test/Watch`, `Test/Core`, `Test/Web`, `Test/Data/Fixture`) for approval rows left in those states, and confirm each test removes its rows. Approval's Reconcile tests assert on their own Refs only.
- **ChatAgent's agent** is swapped during the live tests and restored in `Clean`.
- **CI time:** the new tests run in `shards-2` (lane-a@rest). Expect about +2 minutes (inference) on its 20.8 measured.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte-identically (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1, row 1 | HoldResponse keeps "an approved tool_call sends nothing" | the replay test (ran 0, row approved) |
| AC 1, no model | Replay runs `adapter.Converse` (Chat) instead of ExecuteTool | the replay test (model POSTs > 0); Runner's mock-log test |
| AC 2, row 5 | `TakeGrant` does not kill the grant | the Gate governance test (ran 2) |
| AC 2, row 5 | the replay context falls through to `Hold` | the Gate no-grant test (a new pending row, HELD not FAILED) |
| AC 2, row 6 | the gate ignores metadata's source in a tool context (always the grant's) | row 6b (the tool runs) |
| AC 2, row 6a | the fallback to `GrantSource()` is dropped | the Gate fallback test (denied) |
| AC 2, hash | `ArgumentsHash` keeps key order | the Gate hash test |
| AC 3, row 1 | Replay passes sinkClass `OcuTalon.Bridge.Ext.HostSink` to FinishExecution | the shared-sink `approval.result` assertion |
| DW-99, row 2 | the same mutation | row 2 (no `approval` event) |
| AC 3, row 16 | Reply.Text = the tool's `value` %ToJSON | row 16 |
| AC 4, row 4 | Replay ignores StartExecution's refusal | row 4b (ran 2) |
| AC 4, row 4a | Decide's tool path skips the one-decision-per-item check | row 4a (runner reached, failure reply recorded) |
| AC 5, row 10 | Replay writes no Action entry | row 10 (`Wait` times out) |
| row 8 | the past-expiry branch is dropped | row 8 (row stays approved) |
| row 9 | Decide routes tool by `RunnerFor("turn")` | row 9 (runs; the empty-Runner row is not failed) |
| DW-192, row 11 | the task re-arm is dropped | row 11 (hold gone) |
| DW-192, row 12 | the expiry retry is dropped | row 12 (no outcome) |
| DW-192, row 13 | Reconcile pass 3 is dropped | row 13 |
| DW-195, row 14 | the age check is dropped | row 14 (task and live hold appear) |
| DW-194, row 15 | Gate.Hold omits Runner | row 15 |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
