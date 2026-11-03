---
title: "Story 13.2: The example's own tools wait for approval when they are risky"
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_revision: 'fbd1b31f117a17769d2189a4610d58f5999b733a'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The bridge example decides items, but its agent has no tools. So nothing yet shows a production developer that the bridge governs their own tools: classification by a setting, a held call as an IRIS Workflow approval request, and the replay of an approved call.

**Approach:**
- Give the example agent a toolset of its own with three tools: a read-only one, a risky one and an unclassified one, each with a step label.
- Add the three approval items to the example production.
- Classify the tools and name the approval role only through System Default Settings rows, as a developer would.
- Extend `release/standalone-bridge.sh` so the standalone-bridge job proves each classification case in its throwaway namespace: the hold, the answers, the replay, rejection, expiry, untrusted denial and the audit.

## Boundaries & Constraints

**Always:**
- Example classes name no OcuTalon package other than `OcuTalon.Bridge` and their own (AD-2). Tool and toolset classes name `%AI` only on their Class line, run no Python and make no `%AI` call (AD-6). Tools return a dynamic object, never pre-encoded JSON.
- The tools hold no classification of their own: no `CLASSIFICATION*`, `READONLY*`, `TRUSTEDOUTPUT*` or `RESOURCES*` parameter and no `Classify*` method. The developer's classification comes only from `Decide`'s `ToolClassification` setting (AD-10, AD-31), so that code never decides first.
- Each tool declares its own step label (`STEPLABEL<NAME>`). A label holds no argument and no model text (AD-9).
- The production definition holds structure only. `ToolClassification` and `ApprovalRole` are System Default Settings rows that the script writes for `OcuTalon.BridgeExample.Production` (AD-5, AD-19). No extension class is named (AD-31).
- `ExampleTriage` sets the decide request's `ThreadSessionId` to its own session. `Approval.Raise` then puts the approval request and its Workflow task in the item's trace session (AD-26).
- Answers go only through `OcuTalon.Bridge.Approval.Answer`. The script writes an `ApprovalRequest` row's state never: the one fixture write is the expiry row's `ExpiresAt`, moved into the past the way `Test.Bridge.Approval`'s fixtures do it (AD-11).
- Every check runs only in the script's throwaway namespace `OCUBRIDGE`. Every live wait is a poll with a deadline, and the audit read-back polls for up to 180 s (AD-17, AD-22).

**Never:**
- No change to any existing `src/bridge/cls/OcuTalon/Bridge/**` file. The example uses the bridge's approval code as it stands.
- No new mock behaviour. Only new scenario files `ci/mock/scenarios/A/bridge-example-tool-*.json`.
- No MCP tool, no `%AI` call inside a tool, and no data-changing SQL in a tool. No developer guide (Story 13.3).
- No role, user or setting written outside the throwaway. The example is never started in OCUTALON.
- No sampling parameter, and no new third-party dependency.

## I/O & Edge-Case Matrix

The tools, all in `OcuTalon.BridgeExample.Tools`:
- `example_count_items`: classified safe with `readOnly` 1.
- `example_forward_item`: classified risky.
- `example_archive_item`: has no entry, so it is unclassified.

`ExampleApprover` holds the role in `ApprovalRole`. `ExampleViewer` does not.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Read-only | An untrusted item with `[[mock:bridge-example-tool-read]]`. The mock calls `example_count_items` | The tool runs without approval: one `AgentStep` of kind tool, status ok, label "Counting the example's items", in the item's session. No `ApprovalRequest` row is added. The decision is usable and routed | No error expected |
| Risky held | A `user` item with `[[mock:bridge-example-tool-risky]]`. The mock calls `example_forward_item` `{"team":"operations"}` | The tool does not run (no line from it in the event log). Its step is denied with the HELD sentence. One row is added: `tool_call`, `pending`, the exact name and arguments, `ToolSource` the tools class, `Runner` `TriageAgent`, `RequiredRole` `ExampleApprover`. The item's session holds the denied step, `ApprovalStartIn>ApprovalHold:ApprovalStart` and `ApprovalHold>OcuTalonApprovals:TaskRequest`. Decision `act`, routed to `ExampleNotifyOut` | No error expected |
| Unclassified held | A `user` item with `[[mock:bridge-example-tool-unclassified]]`. The mock calls `example_archive_item` `{}` | The same as Risky held, for `example_archive_item` with `ToolArguments` `{}` | No error expected |
| Not allowed | `Answer(risky Ref, "approve", "system", "ExampleViewer", "")` | `not_allowed`. The row stays `pending` and nothing runs | No error expected |
| Approve | `Answer(risky Ref, "approve", "system", "ExampleApprover", "")` | `done`. Within 60 s the row is `done` with `Result` `done`. The session gains `ApprovalHold>Decide:Request` (kind `tool`) and one ok step labelled "Forwarding the item". The runner's `Reply` has `ToolsRun` 1 and no `FailureText`. The tool's event-log line appears exactly once, and the mock's log gains no request | Polls up to 60 s |
| Second answer | `Answer(risky Ref, "reject", ...)` by `ExampleApprover` | `already_answered`, with the winner's action `approve`. The tool's line count stays 1 | No error expected |
| Rejected | `Answer(unclassified Ref, "reject", "system", "ExampleApprover", "")` | `done`. The row is `rejected`, and `example_archive_item` never runs | No error expected |
| Expired | A second risky `user` item. Its row's `ExpiresAt` is moved 1 s into the past, then `Answer(..., "approve", ...)` | `expired`. The row is `expired`, and the tool's line count stays 1 | No error expected |
| Untrusted | An untrusted item with `[[mock:bridge-example-tool-untrusted]]`. The mock calls forward, then archive, then count | Forward and archive are denied with the UNTRUSTED sentence, and no row is added. Only `example_count_items` runs (one ok step) | No error expected |
| Audit | after the rows above | Within 180 s, `%SYS.Audit` holds these entries, each with its UTC time, `irisUser` and `channel` `system`: `Approval` answered/approved (by `ExampleApprover`), `started` and `finished`/`done`, the `Action` entry (action `example_forward_item`, result `done`, its `approvalRef`), and `Approval` answered/rejected and `expired` | Polls up to 180 s |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`. Read-only.
  - Check order: lines 7-51.
  - Classification: `ClassificationOf` (197). Code decides first: a `Classify<NAME>`/`Classify` method, else the parameters `CLASSIFICATION<NAME>`/`CLASSIFICATION`. Then `EntryFor` (304), the setting's JSON array `{class,tool,classification[,readOnly][,trustedOutput]}`. Then the extension.
  - `Decision` (131), line 142: an untrusted or tainted turn runs only calls that are safe with `readOnly` 1. Every other call gets `UNTRUSTED` and never reaches the hold.
  - `Hold` (158) raises the `tool_call` request with `ToolArguments` set to the arguments' `%ToJSON()`.
  - A safe call's result taints the turn unless `trustedOutput` is set. So a `user` scenario calls its held tool first, before any read-only tool.
  - Its `HELD` and `UNTRUSTED` sentences are at lines 69 and 78.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`. Read-only.
  - `STARTITEM` `ApprovalStartIn`, `HOLDITEM` `ApprovalHold`, `WORKFLOWROLE` `OcuTalonApprovals` (lines 37-44). Raise needs all three items in the running production.
  - `Raise` (94): the session comes from `context.ThreadSessionId` (`SaveAndStart`, 133).
  - `Answer` (277): results `done`, `already_answered`, `expired`, `not_found`, `not_allowed`. `HoldsRole` (350) reads `$SYSTEM.Security.GetUserRecursedRoleSet`, which needs `%Admin_Secure:USE`, so the script calls it from a privileged session.
  - `Audited` (488): the entry fields `irisUser`, `sessionRef`, `channel`, `ref`, `kind`, `change`, `from`, `to`, `outcome`, `target`, `ownerRef`.
  - `HoldResponse`/`Replay` (660, 732) send the kind-`tool` request to `Decide`.
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls`. Read-only. `Run` calls `StartExecution`, then `ExecuteTool(ToolName, ToolArguments)` under a one-shot grant, then the `Action` entry (`ActionEntry`: action, target, result, approvalRef, irisUser, sessionRef, channel), then `FinishExecution`. No model request.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`. Read-only.
  - Kind `tool` goes to the row's `Runner` (`RunnerFor`, 549).
  - Settings `ApprovalRole` (202, default `OcuTalonUser`) and `ToolClassification` (209), both category Bridge.
  - `ServiceUser` (197) is read only for a tool that declares `RESOURCES`, and the example's tools declare none.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls:19` `ValueFor`: the definition, then System Default Settings, read live in any job. So both rows apply with no restart. `WriteDefault` (41) is the bridge's row writer.
- `src/bridge/cls/OcuTalon/Bridge/Service/ApprovalStart.cls`, `Process/ApprovalHold.cls`. Read-only: the two item classes added. `OcuTalon.Production` lines 22, 23 and 36 show their pool sizes: `ApprovalStartIn` 0, `ApprovalHold` 1, `OcuTalonApprovals` (`EnsLib.Workflow.Operation`) 1.
- `src/bridge/cls/OcuTalon/Bridge/Installer.cls:116-201`. Read-only. It already creates the `OcuTalonApprovals` Workflow role and its one member, `OcuTalonWorkflow`, in the namespace.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls:155` `LabelFor`, and `ToolParameter`: `NAME` is the tool name in upper case with `_` and `-` removed. `Policy/StepAudit.cls`: a denial is a step with status `denied` and the denial text.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzReplayTool.cls`, `ZzReplayTools.cls`, `ZzReplayAgent.cls`. Read-only patterns:
  - an `%AI.Tool` with class methods;
  - an `%AI.ToolSet` with `DependsOn` and `XData Definition` `<Tool Name=... Class=... Method=.../>`;
  - an agent `TOOLSETS` parameter.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls:2274`. Read-only. The fixture that moves a row's `ExpiresAt` with `Time.PlusSeconds(now, expiresIn)` and `%Save`.
- `src/bridge/cls/OcuTalon/BridgeExample/Agent.cls`. `TOOLSETS` "", and its INSTRUCTIONS say "You have no tools."
- `src/bridge/cls/OcuTalon/BridgeExample/Triage.cls`. `RequestFor` (class method) sets no `ThreadSessionId`. `OnRequest` sends it.
- `src/bridge/cls/OcuTalon/BridgeExample/Production.cls`. Nine items and four settings.
- `release/standalone-bridge.sh`:
  - check 3 writes the `ProviderConfig` row (line 143);
  - `F_ALIVE` (8 items, line 155) and `F_APPLY`;
  - `item_check` (`Send(subject,body,,.iid)`, line 249), `row_set`/`row_del`, `F_FIND`, `F_AWAIT`, `F_DECISION`;
  - section 5d, keeps-running (line 477);
  - `F_MOCKLOG` with `log-markers` (line 499), `keysearch`, and `audit_rows` with `wait_until 180` (line 545);
  - every `CHK|jobs|8` and every "eight".
- `docker/tests/test-bridge-example.sh`: the rules `spine-rows` (Example* items only) and `scenarios` (`one_scenario`, line 178; `break_scenario`, line 207).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls`:
  - `TestAgent` line 36 asserts `TOOLSETS` "" ("it has no toolset"), and its header (lines 5-7) says "no toolset";
  - `TestProduction` (63-98) pins the nine items.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls:455` holds the count 9.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ExampleTriage.cls` `TestRequestFor` pins every field of the request.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`. Read-only. `TestCallbackRule` scans every OcuTalon tool and toolset class, the example's included.
- `ARCHITECTURE-SPINE.md:1260`. The example row of the Production items table: "beside its `Decide`, `TriageAgent` and `AgentSteps`".
- `ci/mock/mock.mjs:35-39`. Read-only. The reply index is the number of assistant messages after the newest user text message, so `replies[0]` is the tool call and `replies[1]` the final JSON. `ci/mock/test/constants.test.mjs:86` checks tool names only for mockkey scenarios, so marker scenarios may name the example's tools.

## Tasks & Acceptance

**Execution:**
- `src/bridge/cls/OcuTalon/BridgeExample/Tools.cls` (new). An `%AI.Tool` with `Include Ensemble`, and three class methods, each with a doc comment the model reads:
  - `CountItems()` returns `{"items": n}`, from `SELECT COUNT(*)` of `OcuTalon_BridgeExample_Msg.Item`;
  - `ForwardItem(team As %String = "")` writes one `$$$LOGINFO` line `ExampleTools: example_forward_item ran` and returns `{"forwarded": 1}`. It ignores the team's text;
  - `ArchiveItem()` writes `ExampleTools: example_archive_item ran` and returns `{"archived": 1}`.

  The step labels are `STEPLABELEXAMPLECOUNTITEMS` "Counting the example's items", `STEPLABELEXAMPLEFORWARDITEM` "Forwarding the item" and `STEPLABELEXAMPLEARCHIVEITEM` "Archiving the item". Nothing else is declared (see Boundaries). Rationale: the developer's own tools.
- `src/bridge/cls/OcuTalon/BridgeExample/ToolSet.cls` (new). An `%AI.ToolSet` `[ DependsOn = OcuTalon.BridgeExample.Tools ]`, with `<ToolSet Name="BridgeExampleTools">` holding `example_count_items`, `example_forward_item` and `example_archive_item`, mapped to those methods.
- `src/bridge/cls/OcuTalon/BridgeExample/Agent.cls`:
  - `TOOLSETS` = `OcuTalon.BridgeExample.ToolSet`;
  - INSTRUCTIONS: replace "You have no tools." with a short paragraph. It names the three tools and their purpose. It says a tool that changes something may be held for a person's approval or denied, that such a call must not be repeated, and that the answer is still the one JSON object. Keep every phrase that `TestAgent` checks, and no `{{`;
  - the doc comment says it has a toolset.
- `src/bridge/cls/OcuTalon/BridgeExample/Triage.cls`. `RequestFor(item, sessionId As %Integer = "")` sets `ThreadSessionId` to `sessionId` when it is above 0. `OnRequest` passes `..%SessionId`. Update the doc comments. Rationale: AD-26, so that the hold joins the item's session.
- `src/bridge/cls/OcuTalon/BridgeExample/Production.cls`. Append three items:
  - `ApprovalStartIn` (`OcuTalon.Bridge.Service.ApprovalStart`, pool 0);
  - `ApprovalHold` (`OcuTalon.Bridge.Process.ApprovalHold`, pool 1);
  - `OcuTalonApprovals` (`EnsLib.Workflow.Operation`, pool 1).

  There are no new settings: twelve items and four settings. The doc comment names them, and says that `ToolClassification` and `ApprovalRole` are rows the developer writes.
- `ci/mock/scenarios/A/bridge-example-tool-read.json`, `-tool-risky.json`, `-tool-unclassified.json`, `-tool-untrusted.json` (new). Each is a marker scenario with the file's name. `replies[0]` is the `toolUse` of the matrix: read is count; risky is forward `{"team":"operations"}`; unclassified is archive `{}`; untrusted is the list forward, archive, count. `replies[1]` is valid DecisionPayload JSON text with reasons and a confidence: `tellnow` for read and untrusted, and `act` for risky and unclassified.
- `release/standalone-bridge.sh`:
  - Check 3 also writes two rows with `row_set`: `Decide` `ToolClassification`, set to the JSON array of the matrix's two entries, and `Decide` `ApprovalRole` `ExampleApprover`.
  - In `%SYS`, check 3 creates the role `ExampleApprover` and the users `ExampleApprover` (with that role) and `ExampleViewer` (no role), login-disabled. They are throwaway fixtures. If a disabled user gets no roles from `GetUserRecursedRoleSet`, enable both users with a random password generated in `$tmp` and never printed, and record that under Design Notes.
  - `F_ALIVE` gains `ApprovalHold` and `OcuTalonApprovals`, and every count of 8 becomes 10.
  - Check 4 adds three lines: `ValueFor` of both rows; `Gate.ClassificationOf` for each tool (`safe:1:setting`, `risky:0:setting`, `:0:`); and the agent's toolset.
  - `item_check` takes an optional provenance (default untrusted) that it passes to `Send`.
  - A new section 5e, after 5d, runs the matrix rows in order: Read-only, Risky held, Unclassified held, Not allowed, Approve, Second answer, Rejected, Expired, Untrusted. Each row reads the new count of `ApprovalRequest` rows, the tool lines it expects in the event log, the steps of the session (label, status, and the denial sentence in `Summary`) and the session's trace headers. Approve compares the mock log's POST count before and after.
  - Section 6:
    - `log-markers` adds the four new markers;
    - `keysearch` adds the `ApprovalRequest` `ToolArguments`;
    - the audit read-back also waits up to 180 s for the six entries of the Audit row, matched by `ref` in `EventData`, and prints their `irisUser` and `channel`.
  - Rewrite the header's check list, and keep the PASS/FAIL lines and exit 1 on any failure.
- `.github/workflows/lane-a.yml`. The header comment only: the job also proves the example's governed tools. If a developer-machine run takes over 7 minutes, record it under Design Notes. The deadline (1200) and `timeout-minutes` (25) stay.
- `docker/tests/test-bridge-example.sh`. The `scenarios` rule also checks the four tool scenarios: each is named for its file and matched by its marker, and `replies[0]` calls the matrix's tools with the matrix's arguments. Every `toolUse` name is a `Tool Name` of `ToolSet.cls`. `replies[1]` is valid JSON with the matrix's outcome and no sampling key. Add one `break_scenario` that breaks each property, and update the header and the PASS text.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ExampleTools.cls` (new; the lane-a shard's Bridge area holds it). Unit tests that start nothing:
  - `TestToolSet`: discovery lists exactly the three tools with provider `OcuTalon.BridgeExample.Tools`, and the agent's `TOOLSETS` names the toolset;
  - `TestLabels`: each `LabelFor` is the label above and never `GENERICLABEL`;
  - `TestNoCodeClassification`: for each tool, `Gate.HookFor` is "", and `ToolParameter` gives "" for `CLASSIFICATION`, `READONLY`, `TRUSTEDOUTPUT` and `RESOURCES`;
  - `TestTools`: each method returns its object, and forward and archive each write their one line. The test deletes the rows it wrote.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ExampleTriage.cls`. `TestRequestFor` also asserts `ThreadSessionId` for a given session id (and empty for none).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls`, under the orchestrator's ruling. In `TestProduction`, change only the lines that pin the item list: the header bullet, the method comment, the item count 12, the pool check (the two services have pool 0) and the name list with the three new items last. The settings total stays 4, and the `Decide` and `TriageAgent` assertions stay. In `TestAgent`, change line 36 to expect `OcuTalon.BridgeExample.ToolSet` ("it has its toolset"), and change the header's "no toolset" to "its toolset" (runner ruling 2026-11-02, Design Notes "Runner rulings"; reported as a footprint extension).
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`, under the orchestrator's ruling. In `TestExampleInstalledNotStarted`, change only the count line 9 to 12, and the words "nine items" in its comment and message.
- `ARCHITECTURE-SPINE.md:1260`. The example row's parenthetical becomes "beside its `Decide`, `TriageAgent`, `AgentSteps`, `ApprovalStartIn`, `ApprovalHold` and `OcuTalonApprovals`". No AD text changes. Then run the spine lint.

**Acceptance Criteria:**
1. Given `OCUBRIDGE` holding only `src/bridge/` and the example production running with its twelve items (ten jobs Alive), when the example's agent calls `example_count_items`, then it runs without approval and its call is an ok tool step in the decision's trace session. Its classification comes from the `ToolClassification` row (`by` setting), and no tool class declares one in code.
2. Given a `user` item whose scenario calls `example_forward_item`, and another whose scenario calls `example_archive_item`, when the gate decides each call, then neither tool runs. Each call is one `pending` `tool_call` row holding the exact name, arguments and source, raised through `Approval.Raise`, with a `TaskRequest` to `OcuTalonApprovals`. The denied step, the `ApprovalStart` message and the `TaskRequest` are all in the item's trace session.
3. Given the pending risky request, when `ExampleApprover` approves it through `Approval.Answer`, then `ApprovalHold` replays it through `Decide` to `TriageAgent` with no model request. The tool runs exactly once, and the row ends `done`. A second answer returns `already_answered`, and `ExampleViewer`'s answer returns `not_allowed`; neither runs anything.
4. Given a pending request, when it is rejected, or answered after its expiry, then the tool does not run and the row is `rejected` or `expired`.
5. Given the answers above, when the IRIS audit log is read in `%SYS`, then within 180 s it holds each entry of the matrix's Audit row, with its time, `irisUser` and `channel`.
6. Given an untrusted item whose scenario calls forward, archive and count, when the gate decides, then forward and archive are denied with the UNTRUSTED sentence, no request is raised, and only `example_count_items` runs.
7. Given a push, when lane-a's standalone-bridge job runs `release/standalone-bridge.sh`, then it fails unless every case above passes (one per classification, plus the untrusted case), together with every check of Story 13.1, with no risky or unclassified tool line in the event log beyond the one approved run.
8. Given the spine, when the change lands, then the example row names the three approval items, and the spine lint reports no new finding (the base tree's four placeholder findings are DW-180).

## Spec Change Log

- 2026-11-02, runner (Epic 13 lead), after plan round 1 (blocked: intent gap on `Test/Bridge/Example.cls` `TestAgent` line 36): ruled (a), extend the footprint ruling to that one assertion and the header's two words; the plan's Clarification Needed section is resolved and removed; status set to ready-for-dev. Nothing else in the spec changed.

## Review Triage Log

### 2026-11-02 - Review pass
- verdicts: 25 findings - high 0, medium 1, low 18, false 6, maybe-false 0 (routes: patch 4, reject 21)
- findings:
  - `[low]` `patch` Blind: the agent prompt change is not pinned by any test - added `ExampleTools.TestAgentInstructions` (the three tool names, "held for a person's approval or denied", "Never repeat a call that was held or denied", "the one JSON object", no "You have no tools", no template token); mutation recorded.
  - `[false]` `reject` Blind: `ForwardItem` ignores `team` - the Task fixes that ("It ignores the team's text"); the held arguments are pinned on the `ApprovalRequest` row.
  - `[low]` `reject` Blind: the "never ran" checks follow a fixed `Hang 3` - every such row first reads the row's final state, which `Answer` sets before it returns (`rejected`, `expired`, `already_answered`); the sleep is margin, and the fix (more polling) is more than a direct correction.
  - `[false]` `reject` Blind: the audit read-back checks the UTC time only for presence, and hard-codes `irisUser` - `%SYS.Audit.UTCTimeStamp` is always set by the audit writer, and the measured run shows `ExampleApprover` on all six entries (mutation: channel `web` -> red).
  - `[low]` `reject` Blind: the dummy-key search covers only `ApprovalRequest.ToolArguments` among the approval stores - the Task names exactly that table, and no scenario can plant a key in an argument (no new mock behaviour allowed).
  - `[low]` `reject` Blind: `TestTools` cleanup runs after the asserts and deletes by text prefix - only this test writes "ExampleTools: " lines in the unit shard's namespace, and a failure leaves two harmless log rows.
  - `[low]` `reject` Blind: `TestToolSet` discovers the tools class again - a different class from the toolset's, so it checks the tool class offers exactly three methods; cosmetic.
  - `[false]` `reject` Blind: runtime growth unchecked against the 25-minute limit - Design Notes 14 records the measured 5 min 43 s against deadline 1200 and `timeout-minutes` 25.
  - `[low]` `reject` Blind: the spine class column lacks `ToolSet` and `Tools` - the Task changes only the item parenthetical and says no AD text changes; cosmetic.
  - `[low]` `reject` Blind: no error text when the role creation fails - a failed role fails the `role` check and then the `approver-holds` check; the cause is one line away.
  - `[low]` `reject` Edge: `F_STATE` on an empty `aref` aborts the session - only reachable after an earlier row already failed; the run fails either way.
  - `[low]` `reject` Edge: an empty row ref makes the audit read-back match any entry - only reachable after an earlier row failed, which already fails the script.
  - `[false]` `reject` Edge: `F_TRACE` reads the replay once without a poll - `F_STATE` (final) waits for `done`, which `Replay` sets after the reply; the measured runs are stable.
  - `[low]` `reject` Edge/Intent: the role is `ExampleApprovers`, not `ExampleApprover` as the matrix says - IRIS refuses a user and a role of one name (measured); Design Notes 9 records the decision. The intent-contract text is left as it is (read-only) and the lead may amend it.
  - `[medium]` `patch` Gap: AC 8 (the spine row names) has no pinning check - `spine-rows` now requires the example row to name each approval item that the production holds, with two broken samples; mutation recorded.
  - `[low]` `reject` Gap: the dummy-key search of `ApprovalRequest.ToolArguments` cannot fail - the same shape as the file's other searches; a positive control needs a key in a tool argument, which needs new mock behaviour.
  - `[low]` `patch` Gap: mutation lines are missing for the Rejected row, the Second answer row, the "no model request" count, the audit triple, and the unit tests - each applied, observed red, reverted byte-identical, and recorded below.
  - `[low]` `patch` Gap: the `tool_scenario` cross-check against the ToolSet's tool names and the name and status checks are not pinned - added three samples (`tool-risky-name`, `tool-untrusted-status`, a ToolSet without one tool); mutation recorded.
  - `[low]` `reject` Gap: the rows of 5e depend on order, on absolute log counts and on `Hang 3` - one script in a fresh throwaway namespace by design; each row names its own preconditions in the expected lines.
  - `[low]` `reject` Gap: the audit time is checked for presence only - same as the Blind row above.
  - `[false]` `reject` Intent: reading B (live-behaviour tests in the unit shard) - the intent names the standalone-bridge job and the script as the proof; reading A is the spec's.
  - `[false]` `reject` Intent: `irisUser` for the non-answer entries - measured: all six entries show `ExampleApprover`.
  - `[low]` `reject` Intent: the shard has no test that asserts a hold - the script does, as the intent says.
  - `[low]` `reject` Intent: the collateral edits (prompt, spine, header comments, `RequestFor`) follow from the intent; no divergence.
  - `[low]` `reject` Intent: matrix details are checked by count or substring - they are exact in the script's expected lines.

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: references only to the bridge; the standalone path.
- AD-5: the definition is structure, and the rows hold values.
- AD-6: tools make no `%AI` call; the `tool` kind of replay.
- AD-9: steps, labels and denials as steps.
- AD-10: classification order, untrusted and taint, and hold and replay.
- AD-11: `Raise`, `ApprovalStartIn`, `ApprovalHold`, Workflow, the role, `Answer`'s results, the states and the 24 h expiry.
- AD-17: the audit entries and their late rows.
- AD-19: `ApprovalRole` and `ToolClassification` are host settings.
- AD-22: marker scenarios only, and the throwaway.
- AD-26: `ThreadSessionId`.
- AD-29: Lane A files, and lane-a's job.
- AD-31: no extension class.
- AD-33: the ownership row.

No AC contradicts an AD's Rule.

**Integration AC (Rule 1):** AC 7. The consumer is lane-a's standalone-bridge job. It drives the example's tools through `release/standalone-bridge.sh` against a real throwaway IRIS and the mock, and fails the build unless every case passes.

**Consumed-by:** Story 13.3. Its guide documents the toolset, the `ToolClassification` and `ApprovalRole` rows and the `Answer` call, and the job runs the guide's commands. **Consumes:** `Policy.Gate`, `Approval` (`Raise`, `Answer`), `ApprovalStartIn`, `ApprovalHold`, `Replay`, `Decide`, `EnsLib.Workflow.Operation`, `Audit` and the mock. All of them run for real in the throwaway.

**Extend, don't copy (Rule 2):** `Tools`/`ToolSet` follow the shape of `ZzReplayTool`/`ZzReplayTools`. Those are test fixtures that the example cannot reference (AD-2), so the example's are its own. The script's new checks extend `item_check`, `row_set`, `F_ALIVE` and the audit poll; no helper is copied.

**Ledger inbox:** none.

**U-223:** `docs/security-overview.md` is not merged (`git ls-files` is empty on 2026-11-02). The example's tools make no MCP calls, and this story makes no "this release" statement.

**Decided in-stage:**
1. `ApprovalStartIn` is added as a third item, beside the epic's `ApprovalHold` and `OcuTalonApprovals`. `Raise` starts every hold through `ApprovalStartIn` (`Approval.STARTITEM`), so a held call without it is denied FAILED, and AC 2 cannot hold. The three are appended last, so that 13.1's item order stays.
2. `ToolClassification` and `ApprovalRole` are System Default Settings rows, not definition settings. AD-5 makes them values an admin may change. A value in the definition would hide a row (`ValueFor` reads the definition first). `ValueFor` reads both live, so they need no apply.
3. The approval role is `ExampleApprover`, a role that the script creates in the throwaway with two test users, so "whatever its developer sets" is shown by a role that is not OcuTalon's. These are test fixtures in a throwaway only, and no product code creates a role or a user.
4. The read-only tool is classified `safe` with `readOnly` 1, and no `trustedOutput`. Each `user` scenario calls its held tool first, because the result of a safe tool taints the turn (`Gate.Decision`, line 149), and a later risky call would be denied UNTRUSTED instead of held.
5. The tools declare no `RESOURCES`. A permission check reads `Decide`'s `ServiceUser` (default `OcuTalonService`), a user that a namespace with no OcuTalon does not have.
6. "The tool runs once" is shown three ways: the tool's own event-log line (count exactly 1), the replay's one ok step, and the row's `done`. "No model request" is shown by the mock log's POST count, unchanged across the approval.
7. Expiry is made by moving the row's `ExpiresAt` 1 s into the past (the fixture of `Test.Bridge.Approval:2274`), then calling `Answer`. Waiting 24 hours is not possible in CI, and the state still changes only through the API.
8. Answers use channel `system`. A production developer answers from their own code, and `system` is in `Msg.Enum` `CHANNEL`.

9. The approval role is `ExampleApprovers`, not `ExampleApprover` (measured on build 154: `Security.Users.Create` refuses a user and a role of one name, ERROR #942). The users stay `ExampleApprover` (holds the role) and `ExampleViewer` (holds none); the `ApprovalRole` row and the held rows' `RequiredRole` are `ExampleApprovers`. The matrix text `RequiredRole ExampleApprover` reads as the role that the user `ExampleApprover` holds; the answers, the audit `irisUser` and `Answer`'s user are `ExampleApprover` as written.
10. Login-disabled users work (measured on build 154): `GetUserRecursedRoleSet` gives a disabled user its roles, so neither user is enabled and no password file exists. The password that `Users.Create` needs is generated inside the IRIS session and printed nowhere.
11. `item_check` takes the provenance from the variable `ITEM_PROVENANCE` set on the call (`ITEM_PROVENANCE=user item_check ...`), default untrusted, so its positional arguments stay as they were.
12. A row reads its session's tool steps by polling for up to 60 s until the session holds the count the row expects (`wantSteps`), because the replay's step reaches AgentSteps after the row is `done`. The held rows' `ToolArguments` are exactly `{"team":"operations"}` and `{}` (measured).
13. The replay's request, steps and reply are in the item's own session (measured), so the Approve row reads them from `sid`.
14. Run time (developer machine, ARM): a full run of `release/standalone-bridge.sh` took 5 min 43 s (the run with three mutations; a green run is shorter); under the 7 minutes of the Task, so the deadline (1200) and `timeout-minutes` (25) stay.
15. The spine lint reports 8 placeholder findings (4 lines carry the tokens) on the base tree and on this tree alike (DW-180): no new finding.
16. `OcuTalon.Test.Web.GuideApi` `TestRunAgain` (Lane B, `Demo.Guide`) failed once in `shard lane-b --part 2/2`, passed alone on a fresh stack and passed in the same shard on a second run: a flake that does not touch this story.

**Runner rulings (2026-11-02, Epic 13 lead):**
- Footprint, `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls`: besides `TestProduction`'s item-list lines (orchestrator ruling), `TestAgent`'s toolset assertion (line 36, now `OcuTalon.BridgeExample.ToolSet`, "it has its toolset") and the header's "no toolset" may change. No live or waiting epic branch changes this file (checked against origin/OCT-epic12, 14, 15, 31 and 40), it is outside Epic 13's paths_hint and uncontended, so it is a reported footprint extension (Rule 11 (b)); category decide. Rejected: a second example agent (the production would stop running the agent `TestAgent` pins, and `TestProduction`'s `AgentClass` line would change anyway).

**Size and split.** The estimate is about 3.5 to 4 hours of implementation, most of it the script's section 5e and its audit read-back. If the runner wants about 3 hours, the split I propose is:
- 13.2, with AC 1, 2, 6, 7 (its cases) and 8: the tools, the items, the held requests in the trace, and the untrusted denial;
- a sibling, with AC 3, 4 and 5: the answers, the replay, rejection, expiry and the audit.

The split is the runner's decision.

## Verification

`<lane B>` = `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=13 stage=<stage>'`. `<tag>` is `e13s2` followed by the stage's letter (implement `i`, QA `q`, review `r`), and the warm tag is `<tag>w`. Every IRIS run goes to a lane B throwaway: the script's own project, or the warm stack. Slot B is only for load, compile and read-only probes. Run every command in the foreground of its own call with `timeout: 600000`, and make one IRIS test call per message.

**Commands:**
- `(loop)` `bash docker/tests/test-class-rules.sh`. Expected: every rule PASS (`bridge-refs` scans `Tools` and `ToolSet`).
- `(loop)` `bash docker/tests/test-mock.sh`. Expected: 0 failures, and the four new scenario files load.
- `(loop)` `bash docker/tests/test-bridge-example.sh`. Expected: `spine-rows` and `scenarios` PASS.
- `(loop)` Warm: `<lane B> OCUTALON_RUN_TAG=<tag>w bash ci/warm.sh up` once. Then, one per call, `<lane B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=<tag>w bash ci/iris.sh class <C>` for `OcuTalon.Test.Bridge.ExampleTools`, `.ExampleTriage`, `.Example`, `.ExampleRouting`, `.CodeRules` and `OcuTalon.Test.Install.Production`. Then `bash ci/warm.sh down` with the same variables, also after a failure. Expected: each `CLASS ... passed`.
- `(loop)` `<lane B> OCUTALON_RUN_TAG=<tag> bash release/standalone-bridge.sh`. The throwaway is the script's own `sbridge` project of tag `<tag>`. Expected: every check PASS, `standalone-bridge: all checks passed`, exit 0, in about 4 to 6 minutes on ARM (inference). Then run `<lane B> OCUTALON_RUN_TAG=<tag> bash ci/iris.sh teardown`, which should remove 0 projects.
- `(once)` `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: only the base tree's four placeholder findings (DW-180).
- `(once)` `bash docker/tests/test-storage.sh`, then `bash docker/tests/test-ci-config.sh`, then `bash ci/checks.sh`. Expected: all pass. There is no new persistent class, and `ExampleTools` sits in lane-a's Bridge area.
- `(once)` Fresh: `<lane B> OCUTALON_RUN_TAG=<tag> bash ci/iris.sh shard lane-a --part k/6` for k = 1 to 6, then `bash ci/iris.sh shard lane-b --part k/2` for k = 1 to 2, one per call, then teardown. Expected: every `CLASS ... passed`, `STACK ...: project`, and no `WARM` line.
- `(once)` `git diff --stat -- src/bridge/cls/OcuTalon/Bridge ci/mock/mock.mjs ci/mock/server.mjs ci/compose.ci.yml ci/units.sh .github/workflows/ci.yml docker/tests/lib-live.sh`. Expected: empty. In `Test/Bridge/Example.cls` and `Test/Install/Production.cls`, `git diff` shows only the lines of their Task.

**Pinning mutations (Rule 19).** The implement stage applies each, records it as `mutation: ... -> ...`, and reverts. The rows through AC 6 run in one script run where possible.
- AC 1: add `Parameter CLASSIFICATIONEXAMPLECOUNTITEMS = "risky";` to `Tools.cls`. Expected red: `ExampleTools.TestNoCodeClassification`, and the script's read-only row and its `ClassificationOf` line.
- AC 2: `Triage.OnRequest` stops passing `..%SessionId`. Expected red: the held rows' trace check (the `ApprovalStart` and the `TaskRequest` are not in the item's session).
- AC 3: `ForwardItem` raises an error after its line. Expected red: the Approve row (the row is `failed` and the replay's step is error).
- AC 3 (roles): the fixture also gives `ExampleViewer` the role `ExampleApprover`. Expected red: the Not allowed row. This is a fixture mutation, because the role check is the bridge's code, which is out of the footprint.
- AC 4: skip the `ExpiresAt` move. Expected red: the Expired row (`done`, not `expired`).
- AC 5: the read-back matches `outcome` `approvedX`. Expected red: the audit read-back within 180 s. This is a test mutation: the entries are the bridge's.
- AC 6: `RequestFor` always sets `Provenance` `user`. Expected red: the Untrusted row (rows are raised), and `ExampleTriage.TestRequestFor`.
- AC 7: remove the `OcuTalonApprovals` item. Expected red: the script's start check (`jobs` 9 of 10) and `Example.TestProduction`, and the script exits 1.
- AC 8: remove the three names from the spine row. Expected red: none of the commands above sees it, so the lead checks it by review.

17. (review pass) The role-name deviation of item 9 is kept: the matrix and Task text name the role `ExampleApprover`, but IRIS refuses a role and a user of one name, so the code keeps the role `ExampleApprovers`. The intent-contract text is read-only and is reported to the lead.

**Pinning mutations recorded (Rule 19).** Each was applied, observed red and reverted; every file was then byte-identical to its backup (`cksum`).
- mutation: `Parameter CLASSIFICATIONEXAMPLECOUNTITEMS = "risky";` in `Tools.cls` -> red: `ExampleTools.TestNoCodeClassification` (2 asserts: "declares no CLASSIFICATION", "declares no parameter of that kind"), and in the script the `ClassificationOf` line (`risky:0:code`, wanted `safe:1:setting`) and the read-only row (step `denied`, wanted `ok`; `untrusted-steps` 1)
- mutation: `Triage.OnRequest` stops passing `..%SessionId` -> red: the risky held, unclassified held and expired rows (`approval-trace` `0:0`, wanted `1:1`) and the Approve row (the replay is not in the item's session: `replay-request` `0:`, the step list lacks the ok step)
- mutation: `ForwardItem` raises an error after its line -> red: the Approve row (`state` `failed`, `result` `failed`, the replay's step `error`, `replay-reply` `1:0`), and the rows after it
- mutation: the fixture also gives `ExampleViewer` the role `ExampleApprovers` -> red: first the fixture check (`viewer-holds` 1, wanted 0; the script aborts); with that expectation flipped as well, the Not allowed row (`answer` `done`, wanted `not_allowed`; `state` `executing`) and the Approve row (`already_answered`), and the audit read-back (`irisUser` `ExampleViewer`)
- mutation: the `ExpiresAt` move is skipped -> red: the Expired row (`answer` `done`, wanted `expired`; `state` `failed` here with the forward mutation, and `forward-runs` 2, wanted 1)
- mutation: the audit read-back matches `outcome` `approvedX` -> red: the six-entry read-back after 180 s (`audit-answered-approved` `none`)
- mutation: `RequestFor` always sets `Provenance` `user` -> red: `ExampleTriage.TestRequestFor` ("an item with no Provenance is untrusted"), and in the script the Untrusted row (`rows-added` 2, `held-steps` 2, `untrusted-steps` 0) and every earlier row that sends an untrusted item
- mutation: the `OcuTalonApprovals` item removed from the production -> red: `Example.TestProduction` ("it has twelve items", "the items are the twelve of the example, in that order") and the script's start check (`jobs` 9, wanted 10), which aborts the run with exit 1
- mutation: the three names removed from the spine row (AC 8) -> red: `test-bridge-example.sh` `spine-rows` ("does not name the approval item ApprovalStartIn / ApprovalHold / OcuTalonApprovals"); reverted (cksum identical). The review pass added this check.
- mutation: the tool-name cross-check of `tool_scenario` replaced by `true` -> red: `scenarios` ("the rule does not flag a tool name that the ToolSet does not hold"); reverted
- mutation: `Agent.cls` INSTRUCTIONS lose "Never repeat a call that was held or denied"; `ToolSet.cls` loses `example_archive_item`; `Tools.cls` gets the label "Forwarding" and `CountItems` answers `count` instead of `items` -> red, one run: `ExampleTools.TestAgentInstructions`, `TestToolSet` (3 tools, each once), `TestLabels` and `TestTools` ("whose items is a number"); reverted (cksum identical)
- mutation: Second answer is given by `ExampleViewer`; the Rejected row sends `approve`; `posts_after` counts one more request -> red, one script run: the Second answer row (2 of 5 values), the Rejected row (3 of 5 values; the archive tool ran) and "the mock's log gained model requests across the approval (14 before, 15 after)"; reverted (cksum identical)
- mutation: the audit read-back expects channel `web` -> red: the six-entry read-back after 46 s (6 of 6 values differ); reverted (cksum identical)

**Shared surfaces:**
- the example production's item list, which `Test.Bridge.Example:TestProduction`, `Test.Install.Production:TestExampleInstalledNotStarted` and the script's `F_ALIVE` assert;
- the example agent's `TOOLSETS` (`Test.Bridge.Example:TestAgent`);
- `ExampleTriage`'s request fields (`TestRequestFor`);
- the mock's scenario set (`test-bridge-example.sh` `scenarios`; `constants.test.mjs` reads the example's classes for `MOCKKEY`, which is unchanged);
- the spine's Production items table (`spine-rows`, Example* names only).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The bridge example gets its own toolset (`Tools`, `ToolSet`): a read-only tool, a risky one and an unclassified one, each with a step label and no classification in code. The agent has the toolset and new instructions. `Triage` sets `ThreadSessionId` to the item's session. The example production gains `ApprovalStartIn`, `ApprovalHold` and `OcuTalonApprovals` (twelve items, four settings). Four marker scenarios drive the tools. `release/standalone-bridge.sh` writes the `ToolClassification` and `ApprovalRole` rows, creates the throwaway approval role and users, and proves the nine matrix rows and the six audit entries in section 5e and 6.

**Files changed.**
- `src/bridge/cls/OcuTalon/BridgeExample/Tools.cls`, `ToolSet.cls` (new): the three tools and their toolset.
- `src/bridge/cls/OcuTalon/BridgeExample/Agent.cls`, `Triage.cls`, `Production.cls`: toolset and instructions; `RequestFor(item, sessionId)`; the three approval items.
- `ci/mock/scenarios/A/bridge-example-tool-{read,risky,unclassified,untrusted}.json` (new): marker scenarios.
- `release/standalone-bridge.sh`: rows, fixtures, ten jobs, section 5e, audit read-back; `.github/workflows/lane-a.yml`: header comment only.
- `docker/tests/test-bridge-example.sh`: tool scenarios, spine-row check of the approval items, break samples.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ExampleTools.cls` (new), `ExampleTriage.cls`; `Example.cls` and `Test/Install/Production.cls` (footprint extensions, the lines of the rulings only).
- `ARCHITECTURE-SPINE.md`: the example row names the three approval items.

**Review findings.** 25 findings: 4 patched (agent prompt pin; AC 8 spine-row check; missing mutation lines; tool-scenario cross-check pin), 21 rejected with reasons in the triage log, 0 deferred, 0 intent gaps.

**Follow-up review recommended:** false (one medium patched; no high).

**Verification.** `test-class-rules`, `test-mock`, `test-bridge-example`, `test-storage`, `test-ci-config` and `ci/checks.sh` pass. Warm classes `ExampleTools` (also after the patch), `ExampleTriage`, `Example`, `ExampleRouting`, `CodeRules` and `Install.Production` pass. `release/standalone-bridge.sh` passed all checks on the implementation pass (the patch pass changed no file it reads); the lane-a shards 1 to 6 and lane-b shards 1 and 2 passed (a `GuideApi.TestRunAgain` flake in lane-b part 2, passed on a second run and alone). The forbidden-path `git diff --stat` is empty. Every pinning mutation is recorded under Verification.

**Residual risks.** The matrix and Task text name the approval role `ExampleApprover`; the code uses the role `ExampleApprovers` because IRIS refuses a role and a user of one name (Design Notes 9 and 17). The intent-contract text may be amended by the lead. The lint of the spine shows 8 placeholder findings, as on the base tree (DW-180).
