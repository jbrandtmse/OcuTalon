---
title: 'Story 22.4: Hold risky and unclassified MCP calls for approval'
type: 'feature'
created: '2026-11-11'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-3-call-mcp-tools-only-through-the-governed-proxy.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-8-classify-mcp-calls-by-fingerprint-in-the-gate.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-9-bound-mcp-attach-and-listing-with-a-timeout.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Stories 22.8, 22.9 and 22.3, the gate holds a risky or unclassified MCP call, but the held row does not bind the tool's fingerprint, and its approval cannot run: the replay calls the native tool on the agent's own manager, which holds no MCP server (22.9), so it fails with `ToolNotFound`. Nothing stops a replay of a tool that changed after the request was raised. Removing a server leaves its pending requests answerable.

**Approach:**
- The gate holds an MCP call (native `mcp:` call or direct `call_mcp_tool`) as one `tool_call` row in native form (tool, canonical arguments, the server's toolref) plus the turn map's fingerprint in a new `ToolFingerprint` column.
- On approval, Story 30.3's replay is extended: an MCP row runs `call_mcp_tool {server, tool, arguments}` on a governed manager that holds only the proxy toolset. The gate takes the one-use grant on the call's native triple. The proxy compares the live listing with the approved fingerprint and refuses a change unrun, and the replay closes the row failed and reports it.
- `McpOps`' removal cancels the server's pending requests through `Approval.Cancel`.

## Boundaries & Constraints

**Always:**
- **Lanes (U-177).** Lane A files only:
  - the bridge's `Approval.cls`, `Context.cls`, `Policy/Gate.cls`, `Adapter/Agent.cls`, `Adapter/StepBuffer.cls`;
  - footprint extensions `Bridge/Replay.cls`, `Bridge/Data/ApprovalRequest.cls`, `Bridge/Ext/McpServers.cls`;
  - `Mcp/**` and `ci/mock/scenarios/A/**`;
  - `Test/{Mcp,Bridge}/**`, Lane A rows only.
- **Extend 30.3's replay (Rule 2).** `ApprovalHold` -> `Decide` -> runner `Replay.Run` -> `StartExecution` -> `Context.Grant` -> `ExecuteTool` -> `Record`/`FinishExecution` stays the one path. Add an MCP branch to it; never write a second replay.
- **AD-2.** The bridge names no OcuTalon class. The server name of a toolref comes from the new `McpServersClass.ServerOf(toolref)` extension (default `""`). The bridge alone has no MCP server, so it holds and replays no MCP call.
- **Exactly once (NFR-13).**
  - `StartExecution` (approved to executing, under the row lock) is the single gate of a run.
  - The gate's grant is consumed at the first matching call.
  - A replay with no live grant, or a second replay, gets `ToolAccessDenied` (the gate's `Denial`), and the server gets no `tools/call`.
- **As approved.** The replay sends exactly the row's tool and arguments to the row's server. The proxy re-lists the tool and runs it only if the live fingerprint equals the row's `ToolFingerprint`.
- **Fail closed.** These deny with no hold, or fail with no run:
  - a held MCP call with no fingerprint in the turn map;
  - an empty `ServerOf`;
  - a server mismatch between the call and the grant;
  - an unregistered server (22.8, replays included);
  - any proxy refusal.
- **Online demo.** No MCP server can be registered there, so no MCP hold, replay or cancel can happen. The demo's built-in approval path (fix kinds, UJ-1) is unchanged, and `Test.Bridge.Gate`, `Test.Bridge.Approval`, `Test.Bridge.Decide` and the demo path stay green.

**Never:**
- Edit `Core.SettingsOps`, `Core.CommandsIn`, `Core.BridgeSink`, `Core.Conversation`, `Web.*`, `web/**`, or any Lane B test. `Core.BridgeSink` changes only under ruling R1: ONE branch in `Core.BridgeSink` and ONE row in `Test.Core.ToolCallNotices`, as a plain union with Epic 21 (lane C) [ADDED 2026-11-11, orchestrator ruling R1 (cross-lane exception)].
- Edit `Install.Step.Mcp.Grant`/`Revoke`, or add a privilege, grant, resource, route or table.
- Register an MCP server on the agent's own manager, or put the proxy in any `TOOLSETS`.
- Return the tool's result to the conversation, use a real MCP server or a real channel, or delete, skip or shorten a test.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Hold | a user's turn calls risky `zz_delete_ticket` natively (the map holds its fingerprint) | one `tool_call` row: ToolName `zz_delete_ticket`, ToolArguments canonical, ToolSource the server's toolref, ToolFingerprint the map's, Runner, OwnerRef; the model gets `HELD`; the mock logs no `tools/call` | none |
| Hold, direct proxy call | the model calls `call_mcp_tool {server, tool, arguments}` for an unclassified tool | the same native-form row (toolref from 22.3's `McpToolref(server)`) | no toolref or no fingerprint in the map: no row, `FAILED` |
| Approved replay | the row is approved (web, Telegram or phone; tests use `Approval.Answer`) | `Decide` -> runner: `StartExecution`, grant, `call_mcp_tool` on the replay manager, the mock logs exactly one `tools/call` for it, `FinishExecution` `done`, one `MCP` `called` entry and one `Action` entry; the next turn's `SystemNote` names the tool `done`; no result text in any reply, column or event | none |
| Changed before replay | between the hold and the approval, the mock changes the tool's description (case 2: its schema) | the proxy refuses with `MCPCHANGED`, the mock logs no `tools/call`, the row ends `failed`, one `MCP` `refused` entry (outcome `changed`), and the owner gets the result notice (R1) | never run |
| No grant / second replay | `call_mcp_tool` in a `tool` context with no grant, or `Replay.Run` again on a finished Ref | `ToolAccessDenied`; or the start is refused; either way no `tools/call` | none |
| Server removed, pending | `RemoveMcpServer` while a request for its tool is pending | after the removal commits, each pending `tool_call` row with that toolref is `cancelled` through `Approval.Cancel`, with the admin as canceller, an `Approval` entry `cancelled`, and `approval.cancelled` fired to the HostSink; `Answer` then gives `already_answered` or `not_found` and nothing runs | a cancel that fails: one warning naming the Ref; the removal stands |
| Server removed, approved | the row is approved before the removal and replays after it | the gate denies `UNREGISTERED` (22.8); the row ends `failed`; no request | none |
| Built-in / developer tool | any existing `tool_call` hold or replay | unchanged; ToolFingerprint stays empty; Raise refuses a fingerprint on a non-MCP row | none |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `Decision` L158: replay source fallback L163, `TakeGrant` L171-172, `Hold` call L173. `Hold` L197-224 builds the row.
  - `Source` L227 and `IsMcp`.
  - 22.3 adds `MCPPROXY`, the direct-proxy classification through `McpToolref(server)` and `McpFingerprint`, and the rewrite. Read its spec's Gate task before you edit.
  - The sentences are at L60-90: `HELD`, `FAILED` and `DENIEDCODE`.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `Grant` L123 (`$ListBuild(Ref, ToolName, hash, ToolSource)`), `TakeGrant` L147, `GrantSource` L163, `ArgumentsHash` L172, 22.8's node `mcp`, and 22.3's `McpToolref`.
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls`:
  - `Execute` L68-131 (`BuildAgent`, `Context.Begin`, `Grant`, `ExecuteTool(row.ToolName, …)` L98, result L99-103, `Record` L190, `CloseUnstarted` L170).
  - `INTERRUPTEDTEXT` L35 is the internal FailureText precedent.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - `BuildTurnManager` L486-541 (new manager, `Govern` L398, swap of `Agent.ToolManager` L537-540) and `EndTurnTools` L545 (restore). These are the precedent for the replay manager.
  - `Answer` L643 routes kind `tool` to `Replay.Run`.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- `LabelFor` L155 (22.3's MCP label rule).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `Raise` L103, its tool_call validation L214-220, `Cancel` L423, `StartExecution` L437, `FinishExecution` L447.
  - The audit facts L512-520; the replay through the hold L752-795.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- properties L13-82. `ToolSource` and `Runner` (L79, L82) are the precedent for a column added later ("empty for a row held before this property existed"). The storage is `Default`, values 1-25.
- `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- 22.9's `Probe` and 22.3's `ProxyToolSet`. `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` overrides them; `ENTRYPREFIX` L12 and the entry `AI.MCP.OcuTalon_<name>` L23.
- `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls` (22.3) -- `Call` steps 2 (row not unclassified) and 5 (fingerprint against the classification row).
- `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls`:
  - `OnRemove` L99 and `Unregister` L167-199 (TCOMMIT L190): insert the cancel after a successful commit, before `Restarted`.
  - `McpData`/`Common` L525-554 give the admin's irisUser, sessionRef and origin.
  - `OnlineDemo` L585.
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls` (Lane B, read only):
  - The notice rules L20-37. `ServerOf` L272 parses the attach form, which is why the row keeps the native form.
  - approval.result L248-251 maps Result `done`/`failed`/`interrupted` to `toolCall.done`/`toolCall.failed`. approval.cancelled sends no notice, but its approval event is published.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` L42-46 and `ToolNote` L808 (read only) -- the code-written next-turn note from the row's ToolName, State and FinishedAt.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` L1068 -- `mcp.replayToolChanged` {tool, server} (accepted text).
- Tests:
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls` `TestApprovedToolCallReplays` L1578, `TestReplayDeniesAnotherSource` L1724, and `ZzReplayAgent`/`ZzReplayTool(s)` (the replay fixtures).
  - `Test/Bridge/Gate.cls` `TestReplayGrant` L1773, `TestReplaySourceFallback` L1868, `TestHeldRowNamesSourceAndRunner` L1943, and the scenario-driven held turn L1128-1196 (`gate-held-then-note`).
  - `Test/Mcp/Attach.cls` (shadow runner with the mock, `Register`, `Leaks`, `LoggedSecret`); `Test/Mcp/Ops.cls` `TestRemove` L255 and `TestOnlineDemo` L206.
  - `Test/Mcp/Mock.cls` -- `zz_delete_ticket` (risky) L224, the 22.2 description override (zz_lookup), and `Requests`.
- `ci/mock/scenarios/A/gate-held-then-note.json` -- the scenario shape to copy.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement stage, lane A's warm throwaway, after 22.3 is committed; scratch classes `ZzT4`, removed afterwards). Record each answer in `_bmad-output/implementation-artifacts/evidence/22-4-task0-replay.md`:
  1. On a governed `%AI.ToolMgr` that holds only `ProxyToolSet()`, swapped in as `Agent.ToolManager`, `ExecuteTool("call_mcp_tool", {server, tool, arguments})` in a `tool` context reaches the gate. Record its `toolref`, `call` and `metadata` (`origin_class`), and that the step audit runs.
  2. When the proxy's tool method refuses, record what `ExecuteTool` returns: a refusal text, or an error status, or a throw.
  3. Adding property 26 `ToolFingerprint` and compiling keeps existing rows readable, and they read `""`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- `Property ToolFingerprint As %String(MAXLEN = 64)`. Its doc: "the fingerprint of an MCP tool at the hold; empty for every other request and for a row held before this property existed". Storage value 26 is appended.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `Raise`: a `tool_call` whose ToolSource starts `mcp:` requires a non-empty ToolFingerprint. Any other request with one is refused (`Refuse`).
  - New `CancelPending(source, sinkClass, channel, irisUser, sessionRef, Output count) As %Status`. It cancels, through `Cancel`, every `tool_call` row in the state `pending` whose ToolSource equals `source` exactly. A row that fails gives one warning naming its Ref, and the rest go on; the first error is returned. An empty `source` is an error.
  - Update the class doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `ServerOf(toolref) As %String`, default `""`. `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` overrides it: the name only for exactly `mcp:remote:@{config:AI.MCP.`_ENTRYPREFIX_<name>`}` with a name matching `Server.NAMEPATTERN`; otherwise `""`. Also add `Attach.Toolref(server)`, its inverse, for `McpOps`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Context.cls`:
  - `Grant` adds the row's ToolFingerprint as the 5th list element.
  - `TakeGrant`, on success, keeps `$ListBuild(source, name, fingerprint)` in the process-private node `approved`, outside FIELDS, until `End`.
  - New `ApprovedFingerprint(tool) As %String`: the fingerprint when the node names that tool, else `""`.
  - New `NoteReplayRefusal(word)` and `ReplayRefusal()`, a process-private reason word for the replay, also cleared by `End` and `Begin`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `Hold` for an MCP call (an `mcp:` source, or a direct `MCPPROXY` call) writes the native triple: tool name, the tool's arguments, the toolref. It also writes `McpFingerprint(toolref, tool)` as ToolFingerprint. With no toolref or no fingerprint, it raises nothing and denies `FAILED`.
  - In a replay, a direct `MCPPROXY` call takes `GrantSource()` as its toolref only when `ServerOf(GrantSource())` equals the call's `server`. Otherwise the toolref is `""` (unclassified, so the grant fails). The call is then classified and checked, `UNREGISTERED` and the resource included, and `TakeGrant` runs on (tool, the tool's arguments, toolref).
  - The class doc names the MCP hold and replay.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- new `ProxyManager(Output manager) As %Status`:
  - It builds a `%AI.ToolMgr` that holds only `ProxyToolSet()`, governs it (`Govern`) and swaps it in as `Agent.ToolManager`, keeping `OwnTools`. `EndTurnTools` (or one shared restore) puts the own manager back on every path.
  - An empty `ProxyToolSet()` is an error.
  - Extend `BuildTurnManager`/`EndTurnTools`; do not copy them.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Replay.cls` -- the MCP branch of `Execute`, for a row whose ToolSource `IsMcp`:
  - `server = ServerOf(row.ToolSource)`; an empty one fails with no call.
  - `adapter.ProxyManager()`, then `ExecuteTool(Gate.#MCPPROXY, {"server": server, "tool": row.ToolName, "arguments": <row.ToolArguments as an object>})`.
  - The result is `done` only when the call returned a value and `Context.ReplayRefusal()` is `""`. Otherwise it is `failed`, with FailureText 22.3's `MCPCHANGED` for the word `changed` and the proxy's refusal sentence for any other word. Under ruling R1, the word `changed` finishes the row with result `changed`.
  - The own manager is restored on every path.
  - Update the class doc's steps 2 and 4.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- in `LabelFor`, a proxy call in a replay whose tool equals the approved node's gets `MCPLABEL`, with the server from the call. Its slot rules are 22.3's ruled ones (plain text, 64 characters).
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls` -- when `Context.ApprovedFingerprint(tool)` is non-empty (a replay):
  - step 2 requires the server row only, not the classification row;
  - step 5 compares the live fingerprint with the approved one;
  - every refusal calls `Context.NoteReplayRefusal(<the reason word>)`, and a changed fingerprint gives `changed`.
  - The `MCP` audit entry is 22.3's (`refused`, outcome `changed`). There is still no row write.
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` -- after `Unregister` commits a removal, `Approval.CancelPending(Attach.Toolref(server), , <the command's channel>, <irisUser>, <sessionRef>, .count)`. A failure is one warning: the removal and its answer stand. Update the class doc.
- [ ] `ci/mock/scenarios/A/mcp-held-replay.json` (new; marker `mcp-held-replay`) -- the shape of `gate-held-then-note`: reply 1 is `toolUse` `zz_delete_ticket` `{"id": "T-1"}` in a user's turn, and reply 2 is a fixed text. The next-turn note is asserted with `Core.Conversation.ToolNote(<a Turn of the owner created after the replay finished>)`, the way `Test.Core.ConversationTurns` L773 does: it names `zz_delete_ticket` `done`. No second model turn is needed.
- [ ] Tests (the I/O matrix rows):
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/Approval.cls` (new; shadow runner, the mock, production on the warm stack; hermetic `Register`/`Leaks`):
    - `TestHeldThenReplayed`, the end-to-end AC.
    - `TestChangedBeforeReplay`: description, then schema, through the mock's override (classify `zz_lookup` Risky).
    - `TestSecondReplay`, `TestNoGrant`, `TestRemovedWhilePending`, `TestRemovedWhileApproved`, `TestNoFingerprintNoHold`, and the no-secret, no-URL and no-argument-value scan.
  - `Test/Bridge/Approval.cls` -- the Raise rows (fingerprint required for `mcp:`, refused otherwise) and the `CancelPending` rows. Built-in replay rows unchanged.
  - `Test/Bridge/Gate.cls` -- the native-form hold of a direct proxy call, the server mismatch on a replay, and the built-ins unchanged.
  - `Test/Bridge/Ext.cls` -- the `ServerOf` default.
  - `Test/Mcp/Ops.cls` -- `TestRemove` asserts the cancel (count, state, audit), and `TestOnlineDemo` stays green.

**Acceptance Criteria:**
- [RULED 2026-11-11, Contest Planner condition 1] Given a pending MCP-free approval request created on a 1.0.7 install (the upgrade harness), when the install is upgraded to this build, then the request still reads, shows and resolves (both approve and reject), with `ToolFingerprint` empty.
- [RULED 2026-11-11, condition 2(a)] Given a held MCP call whose tool then changes ONLY its description (same name, same input schema), when the approved request replays, then it is refused unrun (the fingerprint is SHA-256 hex over the canonical server id, tool name, input schema and description, from Story 22.8).
- [RULED 2026-11-11, condition 2(b)] Given an approved MCP request, when it replays, then the fingerprint is checked against a fresh `tools/list` on the same connection (the same proxy client session) immediately before `tools/call`, with no model turn in between, and the arguments sent are byte-equal to the ones stored on the row and shown on the card (never regenerated).
- [RULED 2026-11-11, condition 2(c)] Given a pending MCP request, when its server is removed and the request is then approved, then the approval is refused and no request goes out to any server; and cancelling the same request twice is a no-op (no second audit entry or event).
- [RULED 2026-11-11, condition 2(d)] Given a cancelled MCP request, when its card is shown, then it uses only existing accepted wording; if none fits, the implement stage stops and the text goes to the Planner before commit.
- [RULED 2026-11-11, condition 2(e)] Given an MCP call with no fingerprint, when the gate or `Raise` handles it, then it is refused (fail closed), never raised or run.
- [RULED 2026-11-11, condition 3] Given an approved replay, when it goes out through Story 22.3's proxy, then 22.3's conditions (a)-(e) hold unchanged (no credential in any body, trace, log or audit entry; VerifyPeer on, plain http only to this computer; the result taints and is cut; audit holds server, tool and outcome only; stop if the wallet read is missing).
- [RULED 2026-11-11, condition 4] Given a stored toolref that `ServerOf` does not know, or the default `ServerOf` returning "", when the call is classified or replayed, then it counts as unclassified: it is HELD and never auto-run (tested).
- Given a user's turn calls an MCP tool that is risky or unclassified (natively, and as a direct `call_mcp_tool`), when the gate decides, then exactly one `tool_call` row exists holding the server's toolref, the tool, the canonical arguments and the tool's fingerprint with an empty DryRun, the model gets `HELD`, and the mock logs no `tools/call`. Mutation: Hold writes no ToolFingerprint → `TestHeldThenReplayed` red.
- Given that request approved through `Approval.Answer`, when `ApprovalHold` replays it, then `Decide` routes a `tool` request to the runner that held it, the mock logs exactly one `tools/call` with the approved arguments, the row ends `done`, the agent's own manager still holds no MCP server and no proxy (`TestToolInventory` unchanged), and the next turn's `SystemNote` names the tool `done` while no reply, column or event holds the result text. Mutation: Replay calls `ExecuteTool(row.ToolName, …)` → red (`ToolNotFound`).
- Given the tool's description (and, separately, its input schema) changed after the hold, when the approved request replays, then nothing reaches `tools/call`, the row ends failed, one `MCP` `refused` entry (outcome `changed`) exists, and the owner gets a result notice: `mcp.replayToolChanged` {tool, server} under R1, otherwise `toolCall.failed`. Mutation: the proxy compares with the classification row instead of the approved fingerprint → red.
- Given a replay without a live grant, or a second replay of the same Ref, when it reaches the gate or the start, then it is denied with `ToolAccessDenied` or refused at `StartExecution`, and the mock's `tools/call` count stays at one. Mutation: `TakeGrant` keeps the grant → red.
- Given a server with a pending request for its tool, when `McpOps` removes it, then the row is `cancelled` through `Approval.Cancel` with an `Approval` audit entry naming the admin, `approval.cancelled` reaches the HostSink, and a later `Answer` approves nothing. Mutation: skip `CancelPending` → `TestRemovedWhilePending` red.
- Given the mock's risky `zz_delete_ticket` with no platform policy covering it, when the automated test asks for it in a user's turn (scenario `mcp-held-replay`), then it doesn't run before approval, runs once after it, and the IRIS audit log (read back with polling) holds the request's `Approval` entries (raised, approved), the `MCP` `called` entry and the replay's `Action` entry.
- Given an online-demo install, when the suite runs, then `Test.Mcp.Ops` `TestOnlineDemo` and the built-in approval tests are green, and no MCP row can be raised, because no server can be registered.

## Spec Change Log

- 2026-11-11 (runner, rulings applied): the Contest Planner's 22.4 rulings (verbatim under Design Notes) are applied: veto items 1-4 accepted with conditions, each now an AC; the fingerprint redefinition moves into Story 22.8; the demo test already exists in 22.2.

- 2026-11-11 (runner): R1 ruled by the orchestrator (both parts, verbatim under Design Notes); spine S15-S18 written; veto items still pending with the Contest Planner.

- 2026-11-11 (runner, spec gate): validated (no split). R1 (Lane B `Core.BridgeSink` branch + `FinishExecution` result `changed`), the Veto items and spine updates S15-S18 go to the Contest Planner/orchestrator before the implement stage; until R1 is recorded as ruled with both parts, the implement stage builds the specified fallback. This story implements only after Stories 22.8, 22.9 and 22.3 are committed.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: the bridge names no host class.
- AD-6: a replay calls no model.
- AD-10: the hold, the replay, the grant and the fingerprint.
- AD-11: the row is the truth; `Cancel`; MCP removal cancels.
- AD-17: audit.
- AD-21: the proxy, "OcuTalon calls".
- AD-22: the mock.
- AD-25: the online demo.
- AD-29: lanes.
- AD-30: the next-turn note.
- AD-31: extensions and the HostSink.
- AD-33: one owner per table (the bridge owns `ApprovalRequest`; `McpOps` only calls its API).

None of the ACs contradicts an AD's Rule. S15 refines AD-10's replay bullet without changing what it guarantees.

**Decided in-stage:**
1. **Native-form row.** The row keeps (tool, arguments, toolref), because `Core.BridgeSink.ServerOf` and `InputsOf` (Lane B) render "Run {tool} on {server}" from exactly those columns, and `Conversation.ToolNote` names `ToolName`.
2. **The replay runs the proxy directly** on a governed manager that holds only the proxy toolset, swapped in for the call (`BuildTurnManager`'s precedent). It never runs the native name: the own manager holds no MCP server (22.9), and registering the proxy there would offer it in later requests (22.3's Consumed-by).
3. **The grant is matched on the native triple.** A direct proxy call's grant is matched on (tool, arguments, toolref), with the toolref taken from the grant only when `ServerOf` gives back the call's server. So a code-built replay call that names another server cannot take the grant.
4. **The approved fingerprint rules a replay.** It is not the classification row: an unclassified tool's exact call can be approved and run, and any change since the hold is refused.
5. **No fingerprint, no hold.** An MCP call missing from the turn map is denied with the existing `FAILED`: a row that could never replay would promise a run that cannot happen.
6. **Cancel after the commit.** The cancel runs after the removal commits, so the gate already denies new holds (`UNREGISTERED`). An approved row that is not yet run fails at the gate instead (AD-11 permits only pending to cancelled).
7. **No split.** This is about 9 source files against the product default of 6. Hold, replay and the changed-fingerprint refusal cannot ship apart, and the cancel is about 15 lines in `Ops` plus `CancelPending`. Splitting the cancel out would add a story for one call site.
8. **The replay's step label** uses the approved node, so it names the server and tool with no map.

**Extend, don't copy (Rule 2):**
- the replay is 30.3's `Replay.Execute`;
- the replay manager reuses `BuildTurnManager`'s `Govern` and swap;
- the grant is `Context.Grant`/`TakeGrant`;
- the refusal is 22.3's proxy and `MCPCHANGED`;
- the cancel is `Approval.Cancel`;
- `Attach.ServerOf` mirrors the attach form. `Core.BridgeSink.ServerOf` (Lane B) keeps its copy, and the unification is routed as a LOW `wontfix-accepted`, with `reopen_if` = a third parser of the form appears.

**Integration ACs (Rule 1):** these are new:
- `ApprovalRequest.ToolFingerprint`;
- `Approval.CancelPending`;
- `McpServersClass.ServerOf`/`Attach.Toolref`;
- `Agent.ProxyManager`;
- `Context.ApprovedFingerprint`/`ReplayRefusal`.

Their consumers in this story are the real `Replay`, `Gate`, `Mcp.Proxy` and `McpOps`, exercised against the loopback mock and a running production (ACs 1-6, `Test.Mcp.Approval`).

**Consumes:**
- 30.3: the replay path.
- 22.2: rows, `ToolFingerprint`, `McpOps.Unregister`, the mock.
- 22.8: the map, `McpFingerprint`, `UNREGISTERED`.
- 22.9: the own manager holds no MCP server.
- 22.3: `call_mcp_tool`, `Mcp.Proxy`, `McpToolref`, `ProxyToolSet`, `MCPCHANGED`, the `MCP` audit shapes.
- 31.5: the tool-call notices.
- AD-30: `ToolNote`.

**Consumed-by:**
- 22.5: a poll's `tool` request runs `call_mcp_tool` through `Agent.ProxyManager`.
- 22.6: documents the held call, the exact-once replay, the changed-tool refusal and removal cancelling.
- 22.10: keeps the replay route when listing moves to OcuTalon's client.

**Ledger inbox (Rule 17):** (none).

**Footprint extensions:** `Bridge/Replay.cls`, `Bridge/Data/ApprovalRequest.cls`, `Bridge/Ext/McpServers.cls`, `Bridge/Adapter/StepBuffer.cls`.

## Veto items

1. **A stored column.** `OcuTalon.Bridge.Data.ApprovalRequest.ToolFingerprint` (`%String`, 64) is appended to the default storage, empty on existing rows, and kept under the existing purge (AD-27). There is no new table and no retention change.
   - Online demo: always empty (no MCP rows).
2. **The approval guarantees, made stronger, not weaker.** An MCP approval runs only at the fingerprint it was raised for. The removal of a server cancels its pending requests, in the admin's name. `Raise` refuses an MCP `tool_call` without a fingerprint.
   - Online demo: the built-in path is unchanged.
3. **Outward actions.** An approved replay sends one `initialize`, one `tools/list` and one `tools/call` to the admin-registered server, through 22.3's bounded proxy. Nothing else is new.
   - Online demo: none.
4. **Extension contract.** `McpServersClass.ServerOf(toolref)` (S17).
5. No new privilege, role, grant, resource, route or web dependency.

## Clarification Needed

**Contest Planner rulings (verbatim)** [RULED 2026-11-11 ~14:50Z, Contest Planner under the owner's delegation, relayed by the orchestrator; source `<coordination>/prompts/epic-22-rulings-224.md`]:

> # Rulings, Story 22.4 (hold risky and unclassified MCP calls) spec gate (Contest Planner, 2026-11-11 ~14:50Z; owner's delegation; verbatim terms)
> VETO 1-4 ACCEPTED with conditions; R1 and S15-S18 (orchestrator) NOTED.
> 1. ToolFingerprint column: ACCEPTED. Condition: the upgrade harness creates a pending approval request on 1.0.7, then upgrades, and that request still reads, shows and resolves (approve and reject both) with the new column empty.
> 2. Approval guarantees: ACCEPTED.
>  (a) The fingerprint is SHA-256 hex over a canonical form of the server id, the tool name, its input schema AND its description. A test that changes only the description gets refused unrun.
>  (b) The replay checks the fingerprint against a fresh tools/list on the same connection, immediately before tools/call, with no model turn in between. It sends exactly the arguments shown on the card (byte-equal, never regenerated).
>  (c) CancelPending race: a test removes the server, then approves; the approval is refused and no call goes out. Cancelling twice is a no-op.
>  (d) A cancelled card uses existing wording only. If no existing sentence fits, the text comes to the Planner before commit.
>  (e) No fingerprint means refuse (fail closed).
> 3. Outbound replay through 22.3's bounded proxy: ACCEPTED. All of 22.3's conditions (a)-(e) apply unchanged.
> 4. McpServersClass.ServerOf: ACCEPTED. Condition: an unknown toolref, or the default implementation returning empty, is treated as unclassified, so it is HELD and never auto-run. Test it.
> DEMO: MCP stays OFF on the online demo. If 22.2 doesn't already have one, add a demo-mode test showing that MCP server registration is refused.

**How this spec applies them** (runner, 2026-11-11): each condition is an acceptance criterion below. Condition 2(a) changes the fingerprint's definition: `OcuTalon.Bridge.Context.ToolFingerprint` becomes SHA-256 hex (64 characters) over a canonical form of {server id, tool name, input schema, description}; because Story 22.8 implements first and compares fingerprints at call time, that change is made in Story 22.8 (task added to its spec), and 22.4 relies on it. DEMO: Story 22.2 already has the demo-mode refusal tests (`Test.Mcp.Ops` `TestOnlineDemo`, `TestOnlineDemoRealFlag`: add, remove and classify refused on the online demo), so no new test is needed.

**R1 RULED** [ADDED 2026-11-11, orchestrator ruling R1 (cross-lane exception)]: "22.4's R1 is APPROVED, both parts. (a) FinishExecution accepts the new result "changed" (spine S18, AD-11). (b) A ruled lane exception: 22.4 may add ONE branch to Lane B's OcuTalon.Core.BridgeSink and ONE row to Test.Core.ToolCallNotices, as a plain union with Epic 21 (lane C). Re-check origin/OCT-epic21's diff on those files before implement; any overlapping hunk is a Clarification. Spine S15-S18 are approved as additive. 22.4's veto items are with the Planner." So the implement stage builds the R1 path (not the fallback) after the runner re-checks `git diff origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic21 -- src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls src/ocutalon/cls/OcuTalon/Test/Core/ToolCallNotices.cls` (an overlapping hunk stops it as a Clarification). Spine S15-S18 written. The veto items are still with the Contest Planner; the implement stage waits for that ruling.

**R1 (Lane B change, escalated per runner note 4).** The accepted result text `mcp.replayToolChanged` can reach the owner only if `Core.BridgeSink`'s approval.result rule (L248-251, Lane B) can tell a changed-tool failure apart. The row's Result is today `done`, `failed` or `interrupted`.

Recommended ruling:
- (a) `Approval.FinishExecution` accepts a fourth result, `changed`. The row's state is failed with Result `changed`, which is the `interrupted` precedent (AD-11 amendment S18).
- (b) A ruled footprint extension lets this story add one branch to `Core.BridgeSink` approval.result: `changed` gives `mcp.replayToolChanged` {tool = ToolName, server = ServerOf(ToolSource)}. It also adds one row to `Test.Core.ToolCallNotices`.

Fallback if (b) is declined: the replay finishes `failed`, so the owner gets `toolCall.failed`, which is true. The refusal is audited (`MCP` `refused`, outcome `changed`). The mapping is routed to a Lane B story with a `DW-n` bullet. Neither (a) nor `changed` ships without (b), because the current sink sends nothing for an unknown Result. The implement stage builds the fallback unless the runner has recorded R1 as ruled with both (a) and (b). Everything else in this story is independent of R1.

**Spine updates for the lead (Rule 20):**
- S15 (AD-10, "Replaying an approved call"): an MCP `tool_call` row (ToolSource `mcp:`) is replayed as `call_mcp_tool {server, tool, arguments}` on a governed manager that holds only `ProxyToolSet()`, swapped in for the call. The grant is matched on the native triple, with the toolref taken from the grant only when `ServerOf` equals the call's server. The proxy runs it only at the row's `ToolFingerprint` and refuses a change unrun.
- S16 (AD-11): an MCP `tool_call` row carries `ToolFingerprint` (required for an `mcp:` source, refused otherwise). `Approval.CancelPending(source, …)` cancels a source's pending `tool_call` rows through `Cancel`; `McpOps` calls it after a removal commits.
- S17 (AD-31): `McpServersClass.ServerOf(toolref)`, default `""`.
- S18 (AD-11, only under R1): `FinishExecution` result `changed`.

## Public text

No new text. These existing texts are reused:
- `Gate.HELD`, `Gate.FAILED` and 22.3's `MCPCHANGED` and `MCPLABEL`;
- `mcp.replayToolChanged` (accepted; reaches the owner only under R1);
- `toolCall.requestOnServer` (the UX's no-dry-run text);
- `toolCall.done` and `toolCall.failed`;
- `Ops.MESSAGEREMOVED`, which is unchanged.

The replay's FailureText is internal, like `INTERRUPTEDTEXT`.

## Verification

Each `ci/iris.sh` call carries the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Check `ci/warm.sh status` first.
- Run `OCUTALON_RUN_TAG=e22s4iw ci/warm.sh up` once, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s4iw` on each class call.
- Run `ci/warm.sh down` at the end, even after a failure.
- One class per foreground call, with `timeout: 600000`. Never two `iris_execute_tests` calls in one message. Pass `server` `ocutalon-slot-a` and `namespace` `OCUTALON` on every IRIS MCP call.

**Commands:**
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Approval` -- expected: `CLASS … passed` (warm stack, production)
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Approval` -- expected: passed (built-in replay rows unchanged)
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Gate` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Ops` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Proxy` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Ext` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Decide` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Agent.Runners` -- expected: passed (TestToolInventory unchanged)
- (loop) `ci/iris.sh class OcuTalon.Test.Core.ToolCallNotices` -- expected: passed (read only; under R1, with its new row)
- (loop) `bash docker/tests/test-mock.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-ci-config.sh` -- expected: exit 0

There are no `(once)` lines. CI runs the full suite (the shards, `live:install-upgrade` for the new column, `live:demo-path`), and the lead runs Rule 19's fresh-environment check.

**Shared surfaces:**
- the `ApprovalRequest` columns and `Raise`'s validation (`Test.Bridge.Approval`, `ApprovalRows`);
- the gate's hold and replay rows;
- the `Ext.McpServers` base (`Test.Bridge.Ext`);
- the `MCP` and `Approval` audit entries;
- the mock's request log and its scenarios;
- `McpOps`' removal;
- the agent's own tool manager (`TestToolInventory`).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19):**

| Mutation | Test that goes red |
| --- | --- |
| Hold writes no ToolFingerprint | `Test.Mcp.Approval` `TestHeldThenReplayed` (and the Raise row) |
| Replay runs `row.ToolName` natively | `TestHeldThenReplayed` |
| Proxy compares with the classification row | `TestChangedBeforeReplay` |
| `TakeGrant` keeps the grant | `TestSecondReplay` / `TestNoGrant` |
| Skip `CancelPending` in `Unregister` | `TestRemovedWhilePending`, `Test.Mcp.Ops` `TestRemove` |
| Grant source taken without the `ServerOf` check | the Gate server-mismatch row |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
