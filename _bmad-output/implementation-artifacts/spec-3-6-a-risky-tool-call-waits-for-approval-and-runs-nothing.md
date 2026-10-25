---
title: 'Story 3.6: A risky tool call waits for approval and runs nothing'
type: 'feature'
created: '2026-10-25'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-10 rule 4, the AD-11 Raise bullet, the AD-26 "Commands and notices from inside a turn" bullet, the AD-31 HostSink contract, the AD-6 callback bullet, and the Consistency Conventions rows "Tool classification" and "Approval requests")'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The gate denies every risky or unclassified call in a user's turn with the placeholder `NEEDSAPPROVAL` and raises nothing, so the user's risky tool can never be approved. `Raise` also has two flaws when it runs inside a host job: it would commit the caller's open transaction (DW-187), and it leaves the job without its session and with the wrong current header (DW-191).

**Approach:**
- In the gate's result branch, a risky or unclassified call raises one `tool_call` request through `Approval.Raise`. It runs from inside `%CanExecute`, in the bridge context, and is then denied with "held for your approval; nothing was run.".
- `Raise` refuses to run inside an open transaction.
- `StartHold` puts back the job's session and current header ids after its `ApprovalStartIn` round trip.
- The NFR-13 tests show that a held, rejected or expired request runs nothing.

## Boundaries & Constraints

**Always:**
- **The decision order stays as it is** (`Gate.Decision`):
  1. the call checks (`FAILED`);
  2. the classification;
  3. the permissions (`NOPRIVILEGE`);
  4. provenance and taint (`UNTRUSTED`);
  5. the result: a safe call is allowed; every other call is held.
  So an untrusted or tainted turn, a missing privilege and a failed check never raise a request.
- **The held call.** The gate builds an unsaved `ApprovalRequest` with these fields:
  - `Kind` `tool_call`;
  - `ToolName` the call's name;
  - `ToolArguments` the call's arguments as given. An object is stored as its `%ToJSON()`, a JSON text that is not blank is stored verbatim, and no arguments are stored as `{}`. The call itself is never modified;
  - `OwnerRef` and `TraceRef` from the context;
  - no `ResultTarget`, `IncidentRef` or `DryRun`.
  It calls `Raise(row, .ref, sinkClass)` with the gate's own `sinkClass` (empty: Decide's `HostSinkClass`). Raise takes the trace session and the SuperSession from the bridge context (AD-26), so the gate passes neither.
  - **Raise OK:** the call is denied with the new parameter `HELD` = `held for your approval; nothing was run.`, which replaces `NEEDSAPPROVAL`. A held call fires no `turn.step` and does not taint the turn. Its only event is Raise's `approval.raised`.
  - **Raise fails:** the call is denied with `FAILED`, and `Check`'s one redacted warning names the tool, its source and Raise's error. Nothing is held, so the denial never says it is.
- **DW-187.** `Raise` refuses when `$TLevel` is above 0, before anything is written. The refusal names `$TLevel` and its value, and the caller's transaction is left open and unchanged. Measured at planning: `$TLevel` is 0 inside `%CanExecute` in the runner job.
- **DW-191.** `StartHold` saves `$$$JobSessionId` and `$$$JobCurrentHeaderId` (`Ensemble.inc` :36-37) before `ProcessInput` and puts them back afterwards: a defined value is set back, an undefined one is killed again. This also happens after an error status or an exception. Every caller benefits: the gate, Reconcile and Epic 5's `IncidentManager`.
- **`CodeRules` `CALLBACKHELPERS`** gains `OcuTalon.Bridge.Approval`, `OcuTalon.Bridge.Service.ApprovalStart`, `OcuTalon.Bridge.Ids` and `OcuTalon.Bridge.Time`, the classes that `Raise` runs inside the callback. They make no `%AI` call and run no Python (AD-6).
- The gate keeps no instance property. The bridge names no OcuTalon package (AD-2).
- **Tests run on throwaway stacks only, through `ci/iris.sh` and `ci/warm.sh`.**
  - Every OwnerRef a gate test creates is tracked under `^OcuTalonTest("Gate","owners")`.
  - The cleanup runs before and after each test, so it also covers a failed earlier run. It tracks every approval row of those owners in `Test.Bridge.Approval`'s refs and runs that class's `Clean`. So every held request is ended and deleted, and every lock job is released.
  - A test that holds a call first checks that the production is ready (`RunnerFixture.ReadyReason`).

**Never:**
- No change to `Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`, `Hold`, `HoldResponse`, `Reconcile`, `ApprovalHold` or `Service.ApprovalStart`. No new `ApprovalRequest` column, and no new message class or event type.
- No replay, no live grant and no `tool` request (Story 30.3). No audit entry (Story 3.7). No de-duplication of repeated calls.
- No edit to a contended path or to `src/ocutalon/cls/OcuTalon/Test/Agent/**`: reuse `RunnerFixture` and `Test.Contract.Mock` as they are.
- No test run, Workflow change or setting change on `ocutalon-slot-a`. No sleep race: concurrency goes through a held lock. No wait longer than `LOCKSECONDS` is added.

## I/O & Edge-Case Matrix

Terms used in the table:
- **A user's turn:** a context begun with provenance `user`, untainted, and a tracked OwnerRef.
- **The sink:** `ProbeSink` passed as the gate's `sinkClass`.
- **Held** means:
  - exactly one row for the owner, `pending`, with `RequiredRole` `OcuTalonUser` and the fields named in the row;
  - its task exists (`WaitTask`) and exactly one hold is live;
  - the sink got exactly one call, `approval.raised`, with the OwnerRef and `{"ref"}`, at `$TLevel` 0, with the row existing and pending;
  - no `turn.step` fired, the taint is unchanged and the tool method did not run.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Risky call held | A user's turn, with the context's `ThreadSessionId` set to a session the test took from an earlier held call's hold (as 3.4's `TestCallerSession` does) and `SuperSession` set to a new Ref. `zz_gate_held` (risky in code) with `{"value":1,"nested":{"b":2,"a":1}}`. | Denied with `HELD`. Held: `ToolName` `zz_gate_held`, `ToolArguments` the object's `%ToJSON()` exactly, the context's `OwnerRef` and `TraceRef`, and `ResultTarget`, `IncidentRef` and `DryRun` empty. The hold's start is in the context's session with its SuperSession. | -- |
| 2 | Other held calls | A user's turn: (a) `zz_gate_held` with the arguments as JSON text `{"value":2}`; (b) with no arguments; (c) unclassified `zz_gate_risky`, with no setting; (d) the MCP call `mcp:zzserver`/`zz_mcp_other`; (e) through `%CanExecute`, with Decide's `HostSinkClass` set to ProbeSink | Each is denied with `HELD` and is held. `ToolArguments` is (a) the text verbatim, (b) `{}`, (c) and (d) `{}`. `ToolName` is the call's name. In (e) the setting's sink got `approval.raised`. | -- |
| 3 | Never held | (a) A safe call in a user's turn; (b) an untrusted turn and a tainted turn calling `zz_gate_held`, `zz_approve_requests` and `zz_mcp_safe`; (c) a risky tool that declares a resource the service user lacks; (d) no context, or a malformed call | (a) Allowed; (b) `UNTRUSTED`; (c) `NOPRIVILEGE`; (d) `FAILED`. No approval row exists for the owner, and the sink got no `approval.raised`. | -- |
| 4 | Raise fails | A user's turn calling `zz_gate_held`. (a) Another job holds `LOCK ^OcuTalon.Bridge.Approval` (`HoldLockInJob`). (b) DW-187: the test runs `TSTART` first. | Denied with `FAILED` in both cases. One gate warning names `zz_gate_held` and the failure: (a) after about `LOCKSECONDS`, the lock; (b) at once, `$TLevel`. No row or start exists for the owner, and the sink got no call. In (b), `$TLevel` is still 1 afterwards. The test counts the warning and the rows before it rolls back, because the warning row is written inside the open transaction. | Fail closed (AD-10). |
| 5 | DW-191 | (a) `Raise` of a tool_call row, from the test process with `%Ensemble("SessionId")` and `%Ensemble("CurrentHeaderId")` set to known values, and again with both undefined. (b) The production's `ChatAgent` job running `ZzGateAgent` (`UseAgent`): a user's turn with the marker `gate-held-then-note`, in which the model calls `zz_gate_held` and then `zz_gate_note` in one response. | (a) Raise is OK. Both values are unchanged afterwards, and undefined ones stay undefined. The test kills both afterwards. (b) `zz_gate_held` is held: its row and task exist, its step is denied with `HELD`, and it did not run, since the next request carries no `{"ran":"zz_gate_held"}`. `zz_gate_note` ran. Its event-log row has the `SessionId` of the runner's request header and that header's id as `MessageId`. | -- |
| 6 | NFR-13: rejected | Shadow runner of `ZzGateAgent` (`Turn`, the scenario `gate-risky`). Decide's `ToolClassification` setting makes `zz_gate_risky` risky. Then `Answer(ref,"reject","web",<ANSWERER>,"",.w)`. | The turn's step is denied with `HELD`, and the model's next request carries `HELD`. The row holds the exact call (`zz_gate_risky`, `{}`, the request's OwnerRef) and is held. Answer gives `done` and the row is `rejected`. Afterwards (`WaitHoldSettled`) the hold has ended, and in its session it sent only its TaskRequest and AlarmRequest. `StartExecution` is refused. The tool never ran (`^\|\|ZzGateRan`). | -- |
| 7 | NFR-13: expired | A second turn as in row 6. The row is aged to expire 1 minute ago (`Age`), then answered `approve`. | Answer gives `expired` and the row is `expired`. `StartExecution` is refused. The hold sent only its TaskRequest and AlarmRequest. The tool never ran. | -- |
| 8 | Governance runs | `TestEveryRiskyBuiltInIsDenied` and `TestGovernanceSample` through `RunDenied` | Every tool that is not safe is still denied with one denied step, and its method does not run. Each held call's row is removed by the cleanup. | -- |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` -- the change.
  - Class comment (:3-38): step 5 and "takes no lock" (:36) are rewritten.
  - `NEEDSAPPROVAL` (:47) becomes `HELD`.
  - `Check` (:89-103) catches a thrown status as `FAILED` plus `Warn`; a failed Raise reuses that path.
  - `Decision` (:106-122): the result branch is at :115.
  - `ArgumentsOf` (:300-312) gives an object, a text or "" (reuse it).
  - `ReportStep` (:212) is the sink pattern.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `Raise` (:65-86). `Validate` (:132-167) and `Refuse` (:170) hold the refusal pattern for the `$TLevel` check.
  - `SaveAndStart` (:89-115) already takes the session and SuperSession from the context (:101-106).
  - `StartHold` (:120-129) is where the restore goes.
  - Class comment (:3-17).
- `src/bridge/cls/OcuTalon/Bridge/Service/ApprovalStart.cls` and `Context.cls` -- read only (the context's `FIELDS`, and `Put` for the session fields).
- IRIS (`irislib/`), read only:
  - `Ens/BusinessService.cls`:
    - `ProcessInput` (:44-86) commits every open transaction (:62) and kills `$$$JobSessionId` (:79);
    - `preProcessInput` kills it too (:100);
    - `SendRequestSync` sets `$$$JobCurrentHeaderId` to the start's header (:167).
  - `Ens/Util/Log.cls:86-88`: event-log rows read both ids.
  - `Ens/BusinessOperation.cls:146-158`: the runner's own ids are set per request. Its response is built from the request header, so it was never affected (measured).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls` -- extend it.
  - Class comment (:1-38); `OnBeforeOneTest` and `OnAfterOneTest` (:106-146).
  - Risky-call tests asserting `NEEDSAPPROVAL`:
    - `TestRiskyByCodeAndUnclassified` (:215) is extended for rows 1 and 2;
    - the same assertion is in `TestDeveloperSetting` (:236), `TestMalformedSettingFailsClosed` (:266), `TestArgumentDependent` (:310), `TestOddValues` (:335), `TestSameNameAnotherClass` (:359), `TestMcpShadow` (:370), `TestExtension` (:395), `TestCallContentCannotClassify` (:434), `TestCanExecute` (:523), `TestAnyRequestKindAndProvenance` (:779) and `TestTaintFollowsTrustedOutput` (:919).
  - `TestSentences` (:696) checks the sentences.
  - `TestDeveloperRiskyEndToEnd` (:574) is extended for rows 6 and 7.
  - `TestSeveralPairsAndPrivilegeBeforeApproval` (:728) covers row 3c.
  - `TestPrivilegeInProductionRunnerJob` (:814) is extended in place for row 5b.
  - The live approval-row guards: `AssertSafeReadOnlyOnly` (:1134; the comment at :1164) and `TestSuspiciousRequestActsOnNothing` (:1050; the comment at :1110).
  - Helpers: `Begin` (:1117), `Verdict` and `Decided` (:1199-1211), `ApprovalRows` (:1227; its comment changes), `Clean` (:1277), `Guard` (:1285), `Turn` (:1297) and `RunDenied` (:1441).
  - Sink-count assertions (`+$Get(^||ZzProbeSink)`) are at :156-964.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls` -- the helpers to reuse:
  - `Clean` (:1727), `Remove` (:1762), `TaskIds` (:1443), `WaitTask` (:1467), `WaitHoldSettled` (:1490), `HoldMessages` (:1402), `HoldRequests` (:1934), `Age` (:1607), `HoldLockInJob` (:1263) and `ANSWERER` (:80);
  - the refs tracking under `^OcuTalonTest("Approval","refs")`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- `CALLBACKHELPERS` (:56) and its comment (:51-55); the class comment (:6).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateTool.cls`, `ZzGateInjection.cls` (the toolset of six tools) and `ZzGateAgent.cls` (its comment lists the markers).
- `ci/mock/scenarios/A/gate-taint-parallel.json` -- the shape of a response with two tool calls.
- Read only:
  - `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`: `NewRequest` (:276, with an `ownerRef`), `Send` (:262), `UseAgent` (:524), `PointKeys` (:456), `ReadyReason` (:306), `HeaderMark` (:437), `EventMark` (:182), `Warnings` (:1037), `WaitFor` (:158), `UseItemSetting` (:617) and `ToolResults` (:969);
  - `Test.Contract.Mock` `LogMark` and `LogSince`.

## Tasks & Acceptance

**Execution:**
- [ ] `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `Raise` refuses at `$TLevel > 0` through `Refuse`, before anything is written (DW-187);
  - `StartHold` saves and restores `$$$JobSessionId` and `$$$JobCurrentHeaderId` around `ProcessInput`, as in Boundaries, also after an exception (DW-191);
  - the comments of `Raise`, `StartHold` and the class state the contract.
  - Why: rows 4b and 5.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `HELD` replaces `NEEDSAPPROVAL`;
  - a private helper builds the row from the context and the call and raises it with `sinkClass`. On error it throws Raise's status, which `Check` turns into `FAILED` and a warning;
  - the class comment's step 5, its lock sentence and the trace session (AD-26) are rewritten as contracts.
  - Why: rows 1 to 4, AD-10, AD-11.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateTool.cls`: a new tool method `Note` for `zz_gate_note`, declared safe and read-only by its parameters. It records `Ran("zz_gate_note")` and logs one event-log info row (`$$$LOGINFO`). `ZzGateInjection.cls`: add the tool and update the comment ("seven tools"). `ZzGateAgent.cls`: the comment names the new marker. `ci/mock/scenarios/A/gate-held-then-note.json` (new): the first reply calls `zz_gate_held` `{}` and `zz_gate_note` `{}`, and the second reply is text. Why: row 5b.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls`:
  - make `Clean`, `TaskIds`, `WaitHoldSettled` and `Age` public, and turn `WaitTask`, `HoldMessages` and `HoldRequests` into public class methods (they keep no instance state);
  - add the public `TrackOwner(owner)`, which tracks every row of the owner under the refs;
  - add `TestRaiseKeepsTheCallersJobIds` (row 5a);
  - update the class comment.
  - Why: Rule 2, row 5a.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls`:
  - Helpers:
    - an `Owner()` helper (a new Ref, tracked) used by `Begin`, `RunDenied` and `Turn`;
    - the cleanup in `OnBeforeOneTest` and `OnAfterOneTest` (Boundaries);
    - `Guard(production)` that also checks `ReadyReason`;
    - `SinkCalls(type)`, which counts the private sink's calls of one type.
  - Existing tests:
    - every `NEEDSAPPROVAL` becomes `HELD`, and `TestSentences` checks `HELD` exactly;
    - the sink-count assertions after a held call count `turn.step` and `approval.raised` apart;
    - the "Cannot fail until Story 3.6" comments go.
  - Extended tests:
    - `TestRiskyByCodeAndUnclassified` covers rows 1 and 2, with `TestCanExecute` for 2e;
    - `TestSeveralPairsAndPrivilegeBeforeApproval` and `AssertSafeReadOnlyOnly` assert no row (row 3);
    - `TestDeveloperRiskyEndToEnd` covers rows 6 and 7;
    - `TestPrivilegeInProductionRunnerJob` gets a third turn (row 5b, with a tracked owner through `NewRequest` and `Send`).
  - New: `TestFailedRaiseIsDeniedWithFailed` (row 4).
  - The class comment names what each test pins.
  - Why: rows 1 to 8, Rule 19.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- add the four classes to `CALLBACKHELPERS`, and update its comment and the class comment. Why: AC 5, AD-6.

**Acceptance Criteria:**
- Given a user's turn calls a risky or unclassified tool (a developer test tool classified risky in the bridge setting), when the gate decides the call, then:
  - it calls `Approval.Raise` with kind `tool_call` holding the exact call (name, arguments as given, OwnerRef, TraceRef), through the synchronous round trip to `ApprovalStartIn` from inside `%CanExecute`, in the turn's trace session, so the request is pending and held before the call is denied;
  - the call is denied with "held for your approval; nothing was run.", which the denied step and the model's next request carry after AI Hub's prefix;
  - the tool does not run, and the HostSink gets `approval.raised` once and no `turn.step`.
  - Rows 1, 2, 5b and 6 hold (FR-7, FR-8, NFR-13, AD-10, AD-11, AD-26, AD-31).
- Given a call that is safe, in an untrusted or tainted turn, missing a privilege, or failing the call checks, when the gate decides it, then no approval request exists for its owner afterwards: Story 3.3's row counts can now fail. Row 3 holds (FR-7, NFR-14, AD-10).
- Given `Raise` fails (a lock timeout, an open transaction), when the gate holds a call, then the call is denied with `FAILED`, never `HELD`. One warning names the tool and the failure, and no row, hold or event is left. A caller's open transaction is never committed. Row 4 holds (AD-10, DW-187).
- Given `Raise` runs from a host job, when the job logs after it, then the job's session and current header are still its own. Row 5 holds (DW-191, AD-26).
- Given the classes that `Raise` runs inside AI Hub's callback, when `Test.Bridge.CodeRules` runs, then they are in `CALLBACKHELPERS` and pass the callback rule (AD-6).
- Given the NFR-13 tests in `OcuTalon.Test.Bridge`, when they run, then the risky test tool never runs without an approved request, and a rejected or expired request runs nothing. Rows 6 to 8 hold (FR-7, NFR-13).
- Given the fresh `shard lane-a`, `shard lane-b`, `live production`, `live production-restart` and `live demo-path`, when they run, then every class and unit passes.
- DW-187: Approval.Raise inside an open transaction: its ApprovalStartIn ProcessInput commits every open transaction level of the caller, and the hold's job cannot see an uncommitted row; measure the TLevel inside %CanExecute before the gate calls Raise (ledger; routed by harvest 2026-10-25, effect corrected by 3.4's review) -- addressed by row 4b, the `Raise` task and the planning measurement.
- DW-191: Approval.StartHold runs ApprovalStartIn's ProcessInput in the caller's job, which replaces the job's session and current header ids; from the runner's job the gate's later event-log rows would lose their session; restore them after the call, or start the hold another way (ledger; routed by cr 2026-10-25) -- addressed by row 5, the `StartHold` task and the planning measurement.

## Spec Change Log

- 2026-10-25, lead spec gate: no AD is amended. The plan's Rule 20 points went into the Consistency Conventions row "Approval requests" (light path): the gate's held-call fields, `HELD`, the failed-Raise denial, the transaction refusal and the restored job ids. Nothing to rule in the veto window: `HELD` is the sentence the AC and AD-10 fix, the transaction refusal only tightens, and no stored data, privilege or public text changes. The Cross-epic gap for Story 30.3 (the row stores neither the tool's source class nor the runner) is filed as DW-194, routed to 30-3.

## Review Triage Log

## Design Notes

**Architecture decisions:**
- **AD-10:** rule 4. The order before it stays, so an offer never becomes a request. Fail closed: a lock timeout or a failed Raise means `FAILED`.
- **AD-11:** `Raise` and `ApprovalStartIn` are the one way in, the row is the truth, and the state methods are unchanged.
- **AD-26:** the hold joins the turn's thread through the context's `ThreadSessionId`, and DW-191 keeps the runner's own session.
- **AD-31:** `approval.raised` goes to the gate's sink, after the unlock.
- **AD-6:** no `%AI` call in the callback chain (`CodeRules`). **AD-9:** the denial reaches the step through `%LogDenial`.
- **AD-5:** `ApprovalHold` is unchanged. **AD-2:** the bridge stays self-contained. **AD-22:** tests run on throwaways. **AD-29 and AD-33:** these files are Lane A's.
- No AC contradicts an AD's Rule. AD-11 says the hold sends `ApprovalOutcome` on rejection or expiry. A gate row has no `ResultTarget`, so it sends nothing, which the Conventions row "Approval requests" already allows ("an empty ResultTarget sends nothing"). The user learns of the answer through the HostSink events (AD-31).

**Measured at planning** (warm throwaway `e3s6pw`, build 154; torn down afterwards). A probe `ClassificationClass` ran inside the gate's `%CanExecute` in the production `ChatAgent` job (user `_Ensemble`, running `ZzGateAgent`):
- `$TLevel` was 0 before and after a `Raise` of a tool_call row.
- `Raise` returned OK in 0.018 s.
- Before the Raise, `$$$JobSessionId` was 4 and `$$$JobCurrentHeaderId` 4, the runner's request. After it, the session was undefined and the header was 5, the `ApprovalStart` header (DW-191 confirmed).
- An event-log row written after the Raise had an empty `SessionId` and `MessageId` 5.
- The runner's `Reply` header kept session 4.
- Cleanup cost: `Cancel` took 0.048 s, and the hold was gone 0.097 s after the call.
- A call of a tool the agent does not have (`list_productions`, scenario `usage-turn`) never reaches the gate: it gets "Tool 'list_productions' not found" and no step. So the `chat`, `tool-loop` and `usage-turn` tests raise nothing.

**Decided in-stage:**
- **The sentence parameter is renamed** from `NEEDSAPPROVAL` to `HELD`. Its text is the AC's sentence plus the period every gate sentence ends with, as `TestSentences` requires.
- **A failed Raise denies with `FAILED`.** `HELD` would claim a request that does not exist. The denial reuses `Check`'s throw-and-warn path, and no new sentence is needed.
- **The stored arguments.** An object is stored as its `%ToJSON()`, a JSON text verbatim, and no arguments as `{}`. `Raise`'s validation refuses anything that is not a JSON object, so such a call is denied with `FAILED`.
- **The row's other fields.** `OwnerRef` and `TraceRef` come from the context. There is no `ResultTarget`, so the hold sends no outcome. The trace session comes through `Raise`'s context fallback.
- **Each held call is its own request**: there is no de-duplication.
- **Any request kind** with provenance `user` and no taint is held alike, as the gate decides every kind alike. Story 30.3's live grant comes before rule 4 for `tool` replays.
- **DW-187: refuse, don't work around.** Inside a transaction, `ProcessInput` would commit the caller's work, and the hold could not see an uncommitted row. `Raise` is the guard, so every caller gets it. The measurement shows the gate's own path is at level 0.
- **DW-191: restore in `StartHold`.** It is the one place every caller passes, including Reconcile and Epic 5's `IncidentManager`.
- **`CALLBACKHELPERS`** also gets the three classes that `Raise` calls in the callback, not only `Approval`.
- **Test hygiene:**
  - Gate tests track owners, because the gate does not return the Ref. The cleanup reuses `Test.Bridge.Approval`'s refs and `Clean`.
  - `TestPrivilegeInProductionRunnerJob` is extended in place and keeps its name: `PointKeys` and `UseAgent` cost about 8 s once, and the ledger's DW-173 note cites the name.
  - Row 5b needs a new fixture tool, because nothing in the runner logs after a held call on the normal path.
  - Row 7 ages the row and answers it, rather than waiting for the timer.

**For the lead (Rule 20; the plan does not write the spine):** extend the Conventions row "Approval requests" with these points:
- the gate's held call: `ToolName`, `ToolArguments` as given, `OwnerRef` and `TraceRef` from the context, no `ResultTarget`, and the denial `held for your approval; nothing was run.`;
- a failed Raise denies with `FAILED`;
- `Raise` refuses at `$TLevel` above 0;
- `StartHold` keeps the caller's job session and current header.
No stored data, privilege or public text changes. The sentence is the one AD-10 and the AC fix.

**Cross-epic:**
- **Epic 13** (`OcuTalon.BridgeExample.*`): from this story, a risky call of its agent is denied with `FAILED` instead of being held, because its production has no `ApprovalStartIn`, `ApprovalHold` or `OcuTalonApprovals` item. Its agent has no tools today. To hold calls it would need three things:
  - those three items (`OcuTalon.Bridge.Service.ApprovalStart`, `OcuTalon.Bridge.Process.ApprovalHold`, `EnsLib.Workflow.Operation` named `OcuTalonApprovals`);
  - the Workflow role and user that `Bridge.Installer.SetUpApprovals` sets up;
  - an `ApprovalRole` value on its Decide.
- **Lane B's `BridgeSink` (Stories 2.6 and 2.8)** now receives `approval.raised` for user-owned `tool_call` rows with no incident, and turns it into the approval card and notice.
- **Story 30.3:** the row stores neither the tool's source class nor the runner that made the call. AD-10's replay compares the source and routes to that runner. 30.3 adds them (a stored-data change in its own veto window) or derives them.

**Rule 2 (extend, don't copy):**
- `Gate.Decision`'s result branch reuses `ArgumentsOf` and `Check`'s failure path.
- `Raise`'s new refusal uses `Refuse`.
- The tests extend `Test.Bridge.Gate`'s helpers and tests and its `ZzGate*` fixtures.
- `Test.Bridge.Approval`'s helpers are made public, not copied.

**Integration ACs:**
- The production `ChatAgent` job runs the gate, which raises through the real `ApprovalStartIn`, `ApprovalHold` and `OcuTalonApprovals`. The observable effects are the denied step, the model's next request, a held row and the runner's event-log session (row 5b).
- The shadow runner's turn is answered and expired through 3.5's real `Answer` (rows 6 and 7).

**Consumes:**
- From Story 3.4: `Raise`, `StartHold` and the hold.
- From Story 3.5: `Answer` and `StartExecution`.
- From Story 3.3: `Context`, the provenance step and `ApprovalRows`.
- From Epic 1: `RunnerFixture` and the mock.

**Consumed-by:**
- **Lane B, Stories 2.6 and 2.8:** `BridgeSink` publishes `approval.raised` and sends notices.
- **Stories 6.2 and 12.7:** `AnswersIn` answers gate requests.
- **Story 3.7:** audits.
- **Story 30.3:** the replay.
- **Story 14.1:** lists classifications.

**Footprint:**
- Every edit is in `src/bridge/**` (not `BridgeExample`), `src/ocutalon/cls/OcuTalon/Test/Bridge/**` and `ci/mock/scenarios/A/` (a new file, not `bridge-example.json`).
- No footprint extension, and no contended path is edited.

**Ledger inbox:**
- DW-187 is addressed by row 4b and the `Raise` task.
- DW-191 is addressed by row 5 and the `StartHold` task.
- Both Task 0 measurements were taken at planning (above). Row 5b repeats the DW-191 measurement as an assertion.

**Shard time (inference):**
- **Existing gate tests now hold calls:** about 45 to 50 of them in `Test.Bridge.Gate`, 15 of them in the governance sample's three runs. At about 0.02 to 0.05 s per Raise and about 0.1 to 0.15 s per cleanup (measured: 0.1 s), they add about 6 to 10 s.
- **New tests:** the lock case adds about 2 s (`LOCKSECONDS`); rows 5 to 7 add about 2 to 4 s.
- **Total:** about 10 to 16 s, putting the fresh `lane-a` shard at about 430 to 466 s against the 480 s line. No split is planned.
- **If the measured fresh `lane-a` passes 480 s,** the implement stage stops with a clarification and does not edit `ci/units.sh`. It reports the per-class times and proposes a third Lane A shard holding the `Install` area (`SHARDS`, `shard_areas` and the `shards)` line of `group_units`).

## Verification

**Targets:**
- `ocutalon-slot-a` (namespace `OCUTALON`) is for `iris_doc_load` compiles only, after `iris_server_info` shows build 154. Pass `server` and `namespace` on every MCP call.
- Everything else runs through `ci/iris.sh` and `ci/warm.sh`. Never `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, slot B or slot C. No push, and never read `.env`.
- Run each command from the worktree root, in the foreground with `timeout: 600000`, one per call.
- The tags: fresh `e3s6i` and warm `e3s6iw` (implement); `e3s6q` and `e3s6qw` (QA); `e3s6r` and `e3s6rw` (review). Each stage puts its own tags and stage name on the line.
- Create `gate-held-then-note.json` before the first `warm.sh up`. A later change under `ci/mock` refuses warm runs until `down` and `up`.

**Commands:**
- (loop) `bash ci/checks.sh` -- expected: every block passes, `boundaries` and `class-rules` included. About 20 s.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s6iw bash ci/warm.sh up` -- expected: a ready warm stack (about 60 s). Run it once at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e3s6iw bash ci/iris.sh class <Class>`, one call per class -- expected: `CLASS ... passed` after a `WARM reloaded` line. The classes are `OcuTalon.Test.Bridge.Gate`, `OcuTalon.Test.Bridge.Approval`, `OcuTalon.Test.Bridge.CodeRules` and `OcuTalon.Test.Bridge.Conversation` (its agent `ZzGateAgent` gains a tool).
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s6iw bash ci/warm.sh down` -- at the stage's end, and after a failure.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s6i bash ci/iris.sh shard lane-a` -- expected: every class passes. About 430 to 470 s; run it alone in its call and record the time (480 s line).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s6i bash ci/iris.sh shard lane-b` -- expected: every class passes. About 70 s.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s6i bash ci/iris.sh live production` -- expected: PASS.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s6i bash ci/iris.sh live production-restart` -- expected: PASS. Reconcile's `StartHold` runs at every start.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s6i bash ci/iris.sh live demo-path` -- expected: PASS (UJ-1 is unchanged).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s6i bash ci/iris.sh teardown` -- expected: nothing tagged `e3s6i` is left.

**Shared surfaces:**
- **The gate's sentence:** `NEEDSAPPROVAL` becomes `HELD`. Search the trees for `NEEDSAPPROVAL`, `needs an approval` and `risky or not classified`. Every hit is in `Test.Bridge.Gate` (the anchors in the Code Map).
- **Approval rows, holds and Workflow tasks** are now written by the gate in a user's turn. Only `Test.Bridge.Gate` makes such calls, and its cleanup removes them. Every other mock scenario calls tools that code classifies safe, or a tool the agent lacks, which never reaches the gate (measured). `Test.Bridge.Approval`'s `RowCount` deltas are unaffected.
- **ProbeSink's private call counts** gain one `approval.raised` per held call, in `Test.Bridge.Gate`.
- **`CALLBACKHELPERS`** grows by four classes (`TestCallbackRule` counts them).
- **`Test.Bridge.Approval`'s helpers** become public class methods.
- **`ZzGateInjection`** gains `zz_gate_note` (seven tools), so `ZzGateAgent` offers one more tool. `Test.Bridge.Conversation` runs that agent; `TestGovernanceSample` reads only `ZzGateTools` and is unaffected.
- **A new mock scenario.**
- **`StartHold` no longer leaves a caller's ids killed.**
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19; record each as `mutation: ... -> ...` here):

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `TestRiskyByCodeAndUnclassified` | the result branch denies without raising (no row); or `ToolArguments` is always `{}`; or Raise gets no `sinkClass` |
| AC 1 | `TestDeveloperRiskyEndToEnd` | the gate returns OK after raising (the tool runs) |
| AC 2 | `TestUntrustedTurnRunsOnlySafeReadOnly` | the result branch moves before the provenance check (an untrusted call raises a row) |
| AC 2 | `TestSeveralPairsAndPrivilegeBeforeApproval` | the permission check moves after the result branch |
| AC 3 | `TestFailedRaiseIsDeniedWithFailed` | the gate returns `HELD` whatever Raise returns; or `Raise`'s `$TLevel` refusal is removed (`$TLevel` is 0 afterwards and a row exists) |
| AC 4 | `TestRaiseKeepsTheCallersJobIds`, `TestPrivilegeInProductionRunnerJob` | `StartHold` does not restore the two ids |
| AC 5 | `TestCallbackRule` | a `%AI` reference is put on a code line of `Approval` |
| AC 6 | `TestDeveloperRiskyEndToEnd` | `StartExecution` accepts a rejected or expired row; or the gate allows the call after raising |
| sentence | `TestSentences` | `HELD`'s text changes |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (halted after planning).** The spec passed the READY-FOR-DEVELOPMENT check.
- **DW-187 and DW-191** were measured in the production runner job on the warm throwaway `e3s6pw` (build 154), which is torn down. Design Notes, "Measured at planning", has the results.
- **Footprint:** no footprint extension, and no contended path is edited.
- **Lead items:** one Rule 20 recommendation for the spine's "Approval requests" row (Design Notes).
- **Shard time:** the estimate keeps the fresh `lane-a` shard under 480 s, with a contingency in Design Notes.
