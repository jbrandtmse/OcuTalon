---
title: 'Story 22.11: Run source polls through the governed proxy'
type: 'feature'
created: '2026-11-14'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-5-poll-a-read-only-mcp-tool-as-a-source.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-13-keep-source-names-staleness-and-repoints-honest-on-the-cover.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 22.5 (Part A) gives an admin a `source` row, its coverage entry and the digest's not-checked lead, but nothing runs a source: `Checks` reads only `production` and `queues` rows, so every source reads "didn't run". `Decide` refuses an untrusted `tool` request, so a poll has no governed path to `call_mcp_tool`. [AMENDED 2026-11-14, re-plan after the split (Planner ~13:20Z item 1): the three ledger items and the digest sentence moved to Story 22.13, merged; see the Spec Change Log]

**Approach:**
- **The run.** On each Tick, `Checks` sends every due `source` row one asynchronous `tool` request (provenance `untrusted`, Input `{"source":"<Ref>"}`) through `Decide`. `Decide` admits it as a poll, runs it on the `decide` runner (TriageAgent) and writes no `Decision` row. The runner's new `Bridge.Poll` runs exactly one `call_mcp_tool` on a standalone governed manager that holds only the proxy, with its call map seeded from a live listing through the new `PollCall` extension. No model is called.
- **The record.** `Checks.OnResponse` records the run. A result not seen before, after the first successful run since the row's `CreatedAt` (the baseline), becomes one untrusted Item for `Intake`.
- **The stop.** A source whose tool is no longer Read-only makes no call. It records `stopped`, and admins get the accepted `mcp.sourceStopped` once per transition.

## Boundaries & Constraints

**Always:**
- **Lanes (AD-29).** Lane A files only:
  - the bridge's `Process/Decide.cls`, `Adapter/Agent.cls`, `Policy/Gate.cls`, `Context.cls`, `Ext/McpServers.cls` and the new `Poll.cls`;
  - `Mcp/{Attach,Proxy,Ops}.cls` (`Ops`: one appended method), `Checks/Process.cls`, `Data/BackgroundCheck.cls` (doc only), `Digest/Data/CheckRun.cls` (doc only);
  - `Test/{Mcp,Bridge}/**`, Lane A rows only.
- **Governed like a built-in tool (AD-10, AD-21).** A poll's call goes through:
  - the gate: `UNREGISTERED`, the extension's classification at the live fingerprint, `U` on `OcuTalon_MCP_<server>`, and the untrusted rule (only safe and read-only runs; anything else is `UNTRUSTED`, never held);
  - the step audit, which writes one step labelled "Running {tool} on {server}";
  - the proxy's re-list, fingerprint check, cut and one `MCP` `called`/`refused` audit entry.

  It never reaches AI Hub's MCP client and never calls a model. In a poll the gate admits only `call_mcp_tool`, and no grant is needed or taken.
- **Untrusted (AD-30).** Results reach `Intake` only as Items with provenance `untrusted`. A result never approves, classifies, changes a setting or adds a server.
- **AD-5.** "Due", "seen", "baseline" and "stopped" live on the row (`NextDueAt`, `Reported`, `CreatedAt`), never in memory.
- **AD-33.** `Checks` alone writes the run fields (`LastRunAt`, `Result`, `Finding`, `LastRunHeaderId`, `Reported`), each with one SQL `UPDATE` keyed by `Ref`. `NextDueAt` is also written by `Checks`, except that `Watch.Ops.SetSource` sets it to now on a save (22.5). A source removed meanwhile is never re-created, and its answer sends no Item.
- **Baseline (DW-1328, RESET, ruled ~13:20Z item 2).** The first successful run since the row's `CreatedAt` is a baseline with no Item. 22.13's `Watch.Ops.SetSource` moves `CreatedAt` on a repoint; this story reads it.
- **The latest run counts (AD-18, DW-1326).** There is no "all runs passed" rule.
- **Online demo (AD-21, AD-25).** `Checks` runs no `source` row when `Watch.Reader.OnlineDemo()` is 1. `McpOps` refuses both verbs (22.5), and the proxy refuses with `MCPDEMO`. MCP never runs on the demo, and a test pins it.
- **Approved public text stays verbatim** (22.5's strings and 35.1's keys, under Public text).

**Never:**
- Edit `Core.*`, `Web.*`, `web/**`, `Msg.*`, `Data.Precedent`, `Data.Setting`, `Channel.*`, `Checks/Coverage.cls`, `Watch/Ops.cls`, `Digest/Process.cls`, `Test/Contract/**`, `Test/Core/**`, `Test/Live/**`, `Test/Digest/**` or any Lane B test. If a Lane B test pins the old behaviour, stop with `## Clarification Needed`.
- Put an argument value, URL or secret in a request message, log, audit entry, step label or notice. A poll's request carries the source's Ref only.
- Hold a poll's call, give it a grant, register an MCP server on an agent's own manager, put the proxy in any `TOOLSETS`, or add a production item, route, role, privilege, grant, resource, table or column.
- Take Story 21.5's scope (the Settings source form, the source list, the rail's "Polled every {n} minutes" line, the HTTP mapping of McpOps outcomes), 22.12's (the docs) or 22.10's (declined).
- Delete, skip, tag off or shorten a test.

## I/O & Edge-Case Matrix

Rows 1-5 are 22.5's shared intent rows, unchanged in meaning. Fixtures: server `zz`, tool `zz_lookup`, source "Jira", interval 15.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Due, first run | A Read-only source is due; the mock answers "T-1 open". | One async `tool` request goes to Decide, then to TriageAgent. It has provenance `untrusted`, a new ItemId, OwnerRef the row's session, channel `system` and Input `{"source":"<Ref>"}`. `NextDueAt` is tick + 15 min at the send. The mock logs the seed listing, then the proxy's `initialize`, `tools/list` and `tools/call`, all from client `iris`. There is one step, "Running zz_lookup on zz", and one `MCP` `called` audit entry. There is no model request, no `Decision` row and no `decision.recorded`. `Checks` records `passed`, and `Reported` = `{"seen":[<hash>],"baseline":1,"stopped":""}`. No Item is sent (the baseline). | none |
| 2 New result | A later run gets "T-1 open\nT-2 open". | One Item goes to Intake: a new ItemId, the row's session, channel `system`, provenance `untrusted`, Subject "Jira" and Text the answer. Intake's decision follows. The result is `passed`, and the hash joins `seen` (the newest 50 are kept). | A failed send: one warning (`LOGFINDING`), not resent. |
| 3 Seen before | A later run's answer hashes to a value already in `seen`. | No Item. `passed`. | An empty answer is `passed` and is never an Item. |
| 4 Server down | The mock is stopped from 02:10. | Each run is `not_checked` with `REASONSOURCEUNREACHABLE` (CheckRun Reason `unreachable`). Coverage gives `digest.notCheckedUnreachable` {time of the streak's first run}. | Decide's timer, or the proxy's `timeout`, gives `REASONTIMEOUT`. Any other failure word gives `REASONREAD` (`error`). |
| 5 No longer read-only | The tool is classified Risky or Unclassified, or the seed listing finds it changed (22.8 clears it). | That run and every later due run make no `tools/call`. They record `not_checked` with `REASONNOTREADONLY` (Reason `stopped`) and set `Reported.stopped` `not_read_only`. On the transition only, every admin session gets `mcp.sourceStopped` {source, tool, server, time}. Coverage gives `digest.notCheckedStopped`. | Classified Read-only again: the next due run polls and clears `stopped`. |
| 6 Removed meanwhile | The source, or its server, is removed while its poll is in flight. | The answer updates no row (`%ROWCOUNT` 0). There is no CheckRun row, no Item and no `check` event. | none |
| 7 Online demo | `onlineDemo` 1 and a `source` row fixture. | The Tick sends no poll request and records nothing. A direct `call_mcp_tool` is refused with `MCPDEMO`. | none |
| 8 Other tool requests | An untrusted `tool` request whose Input is not `{"source": <Ref>}`; or a user `tool` request. | The first is refused by `Admit`, naming `Provenance`, as today. The second is a replay, unchanged. | none |
| 9 Repoint (DW-1328, RESET) | "Jira" is updated with new arguments through `Watch.Ops.SetSource` (22.13 moves `CreatedAt` to now). | The next successful run is a baseline: `Reported` starts afresh (seen, baseline, stopped) and no Item is sent. | An answer to a poll sent before the repoint records nothing. |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `Bridge/` (`src/bridge/cls/OcuTalon/Bridge/`). Line numbers are at `5fafee78` (feature `f403bf66`: 22.13 and 25.5 merged), re-checked. Since the last plan (`aa94694a`) no bridge file, `Checks/Process.cls`, `Mcp/Proxy.cls`, `Mcp/Attach.cls` or the Mcp/Bridge/Checks test fixtures changed; `Mcp/Ops.cls`, `Coverage`, `Watch/Ops`, `Digest/Process` and the Digest tests did (22.13).

- **Decide** (`Bridge/Process/Decide.cls`):
  - `RUNNERS` L142 (`decide:TriageAgent,…`); `TimerSeconds` L242 (60); `STEPSITEM` L164.
  - `OnRequest` L328-365: `Admit` L331; the Decision-row replay by `ItemIdKindIndexExists` L334 (a poll's ItemId is new, so it never hits); `tool` skips the reply class (L340), `Held` (L346) and `Precheck` (L357); L352-354: runner "" → `FailUnroutable` + `RecordFallback` (writes a row).
  - `OnResponse` L407-451: the timer L411-415 → `TryRetry` → `RecordFallback`; `EmitSteps` L419; `Conclude` L448.
  - `EmitSteps` L782-796 (to `AgentSteps`, keyed by DecisionRef); `Admit` L846-864 (L856 Provenance `user` for `tool`, L857 `Approval.IsRef`); `RunnerFor` L869-884; `HeldBeforeUpdate` L889; `FailUnroutable` L899.
  - `Conclude` L1378 (→ `ConcludeTool`); `ConcludeTool` L1515-1548 (the `StillApproved` bare Reply with no row, L1519-1522, is the no-row precedent; success saves a row, `FireEvent`, `ResponseFromRow`); `RecordFallback` L1662; `FireEvent` L1751; `ResponseFromRow` L1786.
- **Bridge messages:** `Bridge/Msg/Request.cls` (Kind, Provenance, Input, ItemId, Summary, DecisionRef, OwnerRef, TraceRef, Channel; no SessionRef); `Bridge/Msg/Reply.cls` (Text, Tainted, ToolsRun, Steps, FailureText with MAXFAILURE 2000, Fallback, FallbackReason, AgentStepCount, DurationMs); `Bridge/Msg/Enum.cls` PROVENANCE, REQUESTKIND.
- **Runner** (`Bridge/Adapter/Agent.cls`): `BuildAgent` L279; `Govern` L499 (Private instance method); `ProxyManager` L788-808 (builds and governs a proxy-only `%AI.ToolMgr`, L799 refuses when the agent is not built, then swaps it in); `RestoreTools` L812; `Answer` L909, L919 sends `tool` to `Replay.Run`.
- **The pattern to follow** (`Bridge/Replay.cls`): `Run` L55; `Execute` L83 (`Context.Begin` L106, `StepBuffer.Start(0)` L111, `ExecuteTool` L118, `ReplayRefusal` L119); `ProxyCall` L163.
- **Context** (`Bridge/Context.cls`): `Begin` L72-89 (copies Kind and Provenance, taint 0); `End` L92; `Active` L98; `SetMcpTools` L154-188 (the key checks, `MCPKEYMAX`, the `MCP`/`MCPSERVERS` nodes); `McpFingerprint` L192; `McpToolref` L205; `McpServerOf` L244; `TakeGrant` L298; `ApprovedFingerprint` L317; `NoteReplayRefusal`/`ReplayRefusal` L326-340. No `IsPoll` or `SeedMcp` yet.
- **Gate** (`Bridge/Policy/Gate.cls`): `UNREGISTERED` L118, `UNTRUSTED` L122, `REPLAYKIND` L125, `MCPPROXY` L139; `Decision` L208-254 (`replay = (Kind = "tool")` L213; classification L215; unregistered L216; taint ignored in a replay L221; the untrusted rule L222; the replay grant branch L223-229; `ReportStep` and taint L242-251); `ReplayToolref` L361; `ClassificationOf` L513; `ReportStep` L601-609 (fires `turn.step`); `FromMcp` L629 (needs `McpFingerprint`); `FromProxy` L654-670 (non-replay: `McpToolref(server)` from the map).
- **Step label:** `Bridge/Adapter/StepBuffer.cls` `LabelFor` L222, `McpLabel` L235.
- **Extension:** `Bridge/Ext/McpServers.cls` `REASONS` L37, `Servers` L40, `Probe` L48, `OnAttach` L54, `ProxyToolSet` L60, `ServerOf` L66, `ToolsReadOnly` L74 (no `PollCall`). `Mcp/Attach.cls` (107 lines) overrides L31-90; `Toolref` L79.
- **Proxy** (`Mcp/Proxy.cls`, 199 lines): `Call` L38-54 (`approved` L40, demo L41); `Noted` L58-62 (notes only when `approved` is set); `Registered` L67; `Run` L78-103 (the classification check L80; the shared prefix for `Listed`: entry L81-85, header L86-87, `Client.ListTool` L88, `Attach.Toolref` L90, fingerprint L91-96; the compare L97, `CallTool` L98); `Reason` L139; `Audit` L166; `OnlineDemo` L194. `Tools/McpCall.cls` `MCPDEMO` L37.
- **Checks** (`Checks/Process.cls`, 996 lines; Ens.BusinessProcess, PoolSize 1; no `OnResponse`; the Tick comes async from `HeartbeatIn`):
  - `ROWCOLUMNS` L127 (positions 8 and 9 read by `DueOf`/`RowOf`: append only); `REASONTIMEOUT` L155, `REASONREAD` L157; `SYSTEMCHANNEL` L201.
  - `OnRequest` L203-213; `Tick` L216-284, queue block L243-255. **Insert the source block at L256**, before `SettingHistory`.
  - `SendOwn` L392-406; `TraceOf` L491; `RowOf` L533; `Record(row, tickAt, runAt, result, finding, reported, items, keep)` L609-630 (keep leaves `NextDueAt`; quits on `%ROWCOUNT<1`; items via `SendOwn`; `Announce`); `FindingItem` L705; `Announce` L835; `SendFinding` L852 (the Intake seam); `DueOf` L876-888; `QueueDue` L891; `RunQueues` L897; `SOURCEKIND` L982, `REASONSOURCEUNREACHABLE` L985, `REASONNOTREADONLY` L989; online demo through `Watch.Reader.OnlineDemo()` (L520).
- **Coverage (read only, 22.13's):** `Checks/Coverage.cls` `Build` L147, `EarlierRun` L478, `Current` L497, `ReasonOf` L569-573 (maps `REASONNOTREADONLY` → `stopped`, `REASONSOURCEUNREACHABLE` → `unreachable`, `REASONTIMEOUT` → `timeout`, else `error`), `RecordRun` L585.
- **Watch.Ops (read only, 22.13's):** `Watch/Ops.cls` `REPOINTRESETS` L46; `SetSource` L239 (L251 moves `CreatedAt` on a repoint).
- **McpOps** (`Mcp/Ops.cls`, 956 lines): `Notify` L754-779 (the loop over `AdminSessions`); `Send` L782-795 (Kind `status`); `AdminSessions` L933; `Notice` L939; all ClassMethods. No `SourceStopped`.
- **Rows:** `Data/BackgroundCheck.cls` `Reported` doc L50 (production shape only), `Server` L54, `Tool` L57, `Arguments` L60, `IntervalMinutes` L63, `CreatedAt` doc L31-32 (22.13). `Digest/Data/CheckRun.cls` `Reason` doc L22 omits `stopped`.
- **Read only:** `Msg/Catalog/Watch.cls` `mcp.sourceStopped` L1076 (slots source, tool, server, time); `Msg/Item.cls`; `Checks/Beat.cls` L544-550 (the untrusted-Item precedent); `Core/BridgeSink.cls` `Step` L443-469 (publishes `turn.step` only for the running turn's ItemId, so a poll's step reaches no chat); `Live/Payload/Check.cls` (kind, intervalMinutes, traceHeaderId).
- **Tests and fixtures:**
  - `Test/Mcp/Mock.cls`: `Stop` L87, `Silence` L108, `Speak` L114, `Stall`, `Call(port, mode, value)` L144 (modes `text`, `silent`, …), `Requests` L168, `Calls` L181.
  - `Test/Mcp/OpsProbe.cls` (seams `AdminSessions`, `Notice`; `Notices` L30, `NoticeCount` L43).
  - `Test/Mcp/Attach.cls`: `Runner` L1818, `Use` L1824, `Register` L1849, `LoggedSecret` L2077, `Leaks` L2125. `Test/Mcp/Proxy.cls` `TestDemo` L287. `Test/Mcp/SourceSetProduction.cls` (extends `Test.Core.InProduction`): `Submit` L172, `Clean` L254.
  - `Test/Checks/QueueProbe.cls` (the probe pattern, extends `Test/Checks/Probe.cls`, whose `SendFinding` L176 keeps Items); `Test/Checks/Queues.cls` `Host` L544, `Tick` L570.
  - `Test/Bridge/Decide.cls` `TestRefusedRequests` L281 (L289-290: untrusted tool with no Input refused naming Provenance; stays), `TestToolRequest` L327; `Test/Bridge/Gate.cls` `TestReplayKeepsThePermissionAndProvenanceRules` L2584, `TestReplayGovernance` L2639; `Test/Bridge/Ext.cls` `TestExtensionBases` L183.
- **CI:** `ci/units.sh` L136-155. `Test.Mcp.*` runs in `shard:lane-a@rest` (`shards-2`), `Test.Bridge.*` in `shard:lane-a@Bridge` (`shards-9`). No new area.

## Tasks & Acceptance

**Execution:**

- [ ] **Task 0** (implement). On lane D's warm throwaway (tag `e22s11iw`) with scratch classes `OcuTalon.Test.Mcp.ZzT11*`, removed afterwards. Record every answer and number in `_bmad-output/implementation-artifacts/evidence/22-11-task0-poll.md`. Items 1-4 run before any code:
  1. **The manager.** In TriageAgent's job, with no `BuildAgent` and no model key, build a governed `%AI.ToolMgr` that holds only `ProxyToolSet()`. In a poll context (Kind `tool`, Provenance `untrusted`, map seeded), run `ExecuteTool("call_mcp_tool", {server, tool, arguments})`. Record that the gate and the step audit run, the step's label, and the answer for a result, a proxy refusal and a gate denial. 22.4's evidence (`evidence/22-4-task0-replay.md`) measured the same manager after `BuildAgent`. If it fails without the agent, use `BuildAgent` + `ProxyManager`; a poll on a keyless install then records `error`. Record the text.
  2. **The async answer.** `Checks` sends `SendRequestAsync("Decide", request, 1, "<Ref>|<sentAt>")` and gets the Reply in `OnResponse`, with `%SessionId` the Tick's session. Show that a second Tick is handled while a poll waits on a silent mock (`Mock.Silence`), with the timings. If the Checks job is held instead, stop with `## Clarification Needed` (AD-18's one-minute Tick).
  3. **Steps with no Decision row.** `EmitSteps` with the request's DecisionRef and no `Decision` row stores the step and shows it in the Tick's trace. Record the row.
  4. **The wire.** The exact mock request sequence of one poll (the seed listing, then the proxy's requests). If it differs from approved veto 3, record the measured one.
  5. **The triage delay (Planner ~13:20Z Notes; binding).** Run this as soon as the Checks → Decide → `Bridge.Poll` path is built and compiles, before the test tasks. In the warm stack's real production with the model mock, send 10 untrusted Items to `Intake`, about 3 s apart, and take each triage decision's time from Decide's request to its `DecisionResponse` (from the message headers' times; the `Decision` row's duration when it holds one). Run it once with no source row (the baseline), then with 3 due Read-only sources on the mock in each mode: answering (`text`), `Call(port, "silent")` (tools/call held past its 20 s bound), `Silence` (every request silent) and `Stall` (headers, then no body). One mode per foreground call, each under about 150 s; Ticks sent by the scratch class. Record per mode: the median, the maximum, the count of decisions with `Fallback` 1 or `FallbackReason` `timeout`, and the polls' durations.

     **STOP to the Planner if due source polls add MORE THAN 10 s to the median triage decision time, or make ANY triage decision miss its timeout.**

     If either limit is crossed in any mode, the implement stage HALTs with `## Clarification Needed`, naming the mode, the baseline and polled medians, the maximum and the missed-timeout count (Design Notes lists options for the Planner).
- [ ] `Bridge/Ext/McpServers.cls` -- add `PollCall(source, Output server, Output tool, Output arguments, Output toolref, Output fingerprint) As %String`. The default answers `invalid`. The answer is "" or one word of a new `POLLREASONS` (`invalid,notreadonly,notfound,unreachable,timeout,failed,changed,demo`). Doc bullet.
- [ ] `Bridge/Context.cls` -- add `IsPoll()` (Kind `tool` and Provenance `untrusted` in the active context) and `SeedMcp(server, toolref, tool, fingerprint) As %Status` (one map entry and one server entry, with `SetMcpTools`' key checks through a shared private helper). The `NoteReplayRefusal`/`ReplayRefusal` docs say "a replay's or a poll's".
- [ ] `Mcp/Proxy.cls`:
  - Add `Listed(server, tool, Output toolref, Output fingerprint) As %String`. It shares `Run`'s prefix (entry, header, `ListTool`, `Toolref`, fingerprint) through one private method that `Run` also calls (Rule 2).
  - It answers "" or a refusal word (`demo` first on the online demo). It writes no row and no audit entry.
  - `Noted` also notes the refusal word when `Context.IsPoll()`. Restate the class doc.
- [ ] `Mcp/Attach.cls` -- override `PollCall`:
  1. the `source` row by Ref (no row, or another kind, gives `invalid`);
  2. the `ToolClassification` row must be `read-only`, else `notreadonly` (no row: `notfound`);
  3. `Mcp.Proxy.Listed(server, tool, .toolref, .fingerprint)`; its word, if any, is the answer;
  4. a live fingerprint that differs from the row's `Fingerprint` gives `changed`.

  Arguments come from the row only.
- [ ] `Bridge/Policy/Gate.cls` -- in `Decision`:
  - the `replay` branch applies to Kind `tool` with Provenance `user` only;
  - in a poll (`IsPoll`), a call whose name is not `MCPPROXY` is denied `FAILED`;
  - a poll's proxy call is classified through `FromProxy` with the seeded map's toolref, never a grant. `TakeGrant` is not called, and the untrusted rule (L222) and taint apply.

  Restate the class doc.
- [ ] `Bridge/Adapter/Agent.cls`:
  - Split `ProxyManager`'s build and govern into a public `PollManager(Output manager) As %Status`, which needs no agent. `ProxyManager` calls it, then swaps the manager in (Rule 2).
  - In `Answer`, before L919, a tool request with Provenance `untrusted` goes to `Poll.Run`.
- [ ] `Bridge/Poll.cls` (new) -- `Run(adapter, request, superSession, Output reply) As %Status`:
  1. Parse Input `{"source"}`. A value that is not a Ref gives a failure Reply `invalid`.
  2. `PollManager` (or Task 0's fallback).
  3. `Context.Begin`.
  4. `PollCall`: a non-empty word ends the run with that word.
  5. `SeedMcp`.
  6. `StepBuffer.Start`.
  7. `ExecuteTool(MCPPROXY, {server, tool, arguments})`.
  8. The Reply:
     - Text: the answer's value, only when `ReplayRefusal()` is "";
     - Tainted 1 when the call ran; ToolsRun; Steps; AgentStepCount; DurationMs;
     - FailureText "" or one word: a `POLLREASONS` word, or `denied` for a gate denial.

  The context, the step buffer and the manager are released on every path. Class doc: the contract, and that no host class is named (AD-2).
- [ ] `Bridge/Process/Decide.cls`:
  - **`Admit`.** A `tool` request with Provenance `untrusted` is admitted only when its Input is exactly `{"source": <a Ref>}` (`Approval.IsRef` is not required). Any other untrusted tool request is refused naming `Provenance`, as today.
  - **`RunnerFor`.** A poll gets the `decide` runner of `RUNNERS`.
  - **No Decision row.** On every path a poll can take (success, a runner failure, the timer, no runner), it answers a bare Reply (the `StillApproved` pattern) and writes no `Decision` row and no `decision.recorded`.
  - **The answer.** The Reply carries the runner's Text, Tainted, Steps, ToolsRun and FailureText. The timer gives Fallback 1, FallbackReason `timeout` and FailureText `timeout`. Steps go to `AgentSteps` as for any request.
  - Restate the docs of `Admit`, `RunnerFor` and `ConcludeTool`.
- [ ] `Mcp/Ops.cls` -- append the public `SourceStopped(source, tool, server, time) As %Status`. It sends `mcp.sourceStopped` to every `AdminSessions()` session through `Send`, extending `Notify`'s loop. A failed read of the admins is one warning. Class-doc bullet.
- [ ] `Checks/Process.cls`:
  - Append `Server, Tool, IntervalMinutes` to `ROWCOLUMNS`; `RowOf` adds `server`, `tool` and `interval`.
  - **`Tick`:** one Try block at L256 calls `RunSources(tickAt)`, logging like the queue block. Class-doc bullet.
  - **The appended block** (`POLLTARGET` "Decide", `LOGPOLL*`):
    - **`RunSources(tickAt)`.** It returns at once on the online demo. For each row of `DueOf(tickAt, SOURCEKIND)`:
      1. One UPDATE sets `NextDueAt` = tick + `IntervalMinutes`×60.
      2. If the seam `SourceClass(server, tool)` is not `read-only`, it records a stopped run now (`Record(…, keep 1)`), and `StopNotice` runs on the transition.
      3. Otherwise the seam `SendPoll(request, key)` sends the request: `SendRequestAsync(POLLTARGET, request, 1, "<Ref>|<sentAt>")`, with the fields of matrix row 1, Summary "Source poll" and TraceRef from `TraceOf`, in the Tick's session.
    - **`OnResponse`.** It re-reads the row by Ref (`SourceRow`). A missing row records nothing, and so does a `sentAt` before the row's `CreatedAt` (an answer for the target before a repoint). When the row's `LastRunAt` is "" or before its `CreatedAt`, `Reported` starts as `{}`. Then it maps the Reply:
      - "" with Text: `passed`. A success while `Reported.baseline` is not 1 sets it to 1 and sends no Item; after that, a new SHA-256 hex hash of the whole answer becomes one Item (`SourceItem`) and joins `seen` (newest 50);
      - `notreadonly` or `changed`: stopped (as in step 2); `denied` re-reads `SourceClass`: not read-only means stopped, otherwise `REASONREAD`;
      - `unreachable` gives `REASONSOURCEUNREACHABLE`; `timeout` gives `REASONTIMEOUT`; anything else gives `REASONREAD`.

      Every run that is not a stop clears `stopped`. It calls `Record(row, sentAt, now, result, finding, reported, items, 1)` (with keep 1 the tick argument sets nothing).
    - **`SourceItem(row, text)`:** matrix row 2's fields.
    - **`StopNotice(row, time)`** (seam): calls `Mcp.Ops.SourceStopped`.
- [ ] `Data/BackgroundCheck.cls` and `Digest/Data/CheckRun.cls` (docs only): `Reported` gains the source shape; `Reason` lists `stopped`.
- [ ] Tests. Every matrix row; hermetic fixtures removed after each test; one class per call:
  - **`Test/Bridge/Poll.cls` (new):** `TestAdmitPoll` (accepted; malformed refused; a user tool request unchanged); `TestRunnerForPoll`; `TestPollNoDecisionRow` (success and timer paths, through a Decide shadow); `TestPollOnlyProxy` (a non-proxy call in a poll context is `FAILED`); `TestPollNoGrant` (a read-only proxy call runs with no grant); `TestPollRiskyDenied` (`UNTRUSTED`); `TestPollCallDefault` (the bridge-alone `invalid`).
  - **`Test/Bridge/Gate.cls`:** no edit. Its replay rows (L2584, L2639) must stay green, which proves the poll branch leaves the replay rule unchanged.
  - **`Test/Bridge/Ext.cls`:** `TestExtensionBases` gains `PollCall`.
  - **`Test/Mcp/SourceRun.cls` (new)** with a Checks probe `Test/Mcp/SourceProbe.cls` (the `QueueProbe` pattern: seams `SendPoll`, `SourceClass`, `StopNotice`, `SendFinding`; a probe `SOURCEKIND`), feeding Replies to `OnResponse`:
    - `TestFirstRunBaseline`, `TestNewResult`, `TestSeenBefore` (newest 50), `TestEmptyAnswer`;
    - `TestUnreachable`, `TestTimeout`, `TestOtherFailure`;
    - `TestStoppedBeforeSend`, `TestStoppedAfterDenial`, `TestStoppedChanged`, `TestStoppedNotifiesOnce`, `TestResume`;
    - `TestNextDueAtAtSend`, `TestRemovedMeanwhile`;
    - `TestRepointBaseline` (an update with new arguments through `Watch.Ops.SetSource`, then a passed run, sends no Item and resets `seen`) and `TestAnswerBeforeRepoint` (an answer sent before the move records nothing);
    - `TestOnlineDemoNoPoll` (the probe flag and the real `onlineDemo` setting);
    - `TestStoppedCoverage` (a recorded stopped run; `Checks.Coverage.Build` gives `digest.notCheckedStopped`);
    - `TestSourceStoppedNotice` (`OpsProbe.SourceStopped`: two admins each get `mcp.sourceStopped` with the four slots; an admins read error is one warning).
  - **`Test/Mcp/SourceRunProduction.cls` (new; extends `Test.Core.InProduction`; the mock MCP server).** A real Tick → Decide → TriageAgent → mock → Checks → Intake:
    - `TestPollRuns`: one `MCP` `called` entry; the step "Running zz_lookup on zz"; no `Decision` row for the poll's ItemId; no model request for the poll;
    - `TestNewResultReachesIntake` (the Integration AC): one decide request in the model mock's log and one `ItemDecision` for the Item;
    - `TestNoSecretLeaks` (`LoggedSecret`, `Leaks`): no argument, URL or secret in messages, logs, audit entries or step labels.

**Acceptance Criteria:**

- Given a due Read-only source, when `Checks` runs it on the Tick, then a `tool` request goes through `Decide` and `call_mcp_tool` runs once with no model: the gate, the step "Running zz_lookup on zz" and one `MCP` `called` entry apply, and no `Decision` row is written. Mutation: the poll's runner uses an ungoverned manager → `TestPollRuns` red (no step). Mutation: the poll writes a Decision row → `TestPollNoDecisionRow` red.
- Given a poll's answer not seen before, after the baseline, when it is recorded, then exactly one untrusted Item reaches `Intake`; the same answer again sends nothing. Mutation: skip the `seen` check → `TestSeenBefore` red.
- **Integration AC.** Given the real production with a baselined source whose mock answer changes, when the next Tick's poll is recorded, then consumer `Intake` reads the Item that `Checks` sent and produces an `ItemDecision`, with one decide request in the model mock's log. Mutation: `SourceItem` not sent → `TestNewResultReachesIntake` red.
- Given each run, when it is recorded, then `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId` (the Tick's session) and `NextDueAt` (tick + interval, set at the send) are set, one CheckRun row is written, and a `check` event carries `kind` `source`, `lastRunAt`, `result`, `traceHeaderId` and `intervalMinutes`. Mutation: `Record` without keep → `TestNextDueAtAtSend` red.
- Given a source whose tool became Risky, Unclassified or changed, when it is next due, then no `tools/call` reaches the mock, the run is `not_checked` with Reason `stopped` (coverage: `digest.notCheckedStopped`), and every admin gets one `mcp.sourceStopped` (none on the next stopped run). Mutation: notify on every stopped run → `TestStoppedNotifiesOnce` red.
- Given a poll context, when any call other than `call_mcp_tool` is made, then the gate denies it, and a read-only proxy call runs with no grant. Mutation: allow any name in a poll → `TestPollOnlyProxy` red. Mutation: require a grant → `TestPollNoGrant` red.
- **Baseline (DW-1328, RESET).** Given a source repointed through `Watch.Ops.SetSource`, when it next runs successfully, then that run is a baseline (no Item, `seen` afresh), and an answer to a poll sent before the repoint records nothing. Mutation: ignore `CreatedAt` in the start-afresh rule → `TestRepointBaseline` red. Mutation: drop the `sentAt` check → `TestAnswerBeforeRepoint` red.
- Given the online demo, when a Tick runs with a `source` row present, then no poll request is sent and nothing is recorded. Mutation: drop the demo return in `RunSources` → `TestOnlineDemoNoPoll` red.
- **Triage delay (Task 0 item 5).** Given 3 due sources in each mock mode, when 10 triage decisions run, then the evidence file records the medians, the maximum and the missed timeouts, and neither STOP limit is crossed (else the HALT above).

## Spec Change Log

- 2026-11-14 (plan). **Contest Planner, ~09:40Z Nov 14 (BINDING):** DW-1325 (refuse "Mailbox"), DW-1326 (the latest run counts) and DW-1327 (staleness against max(window, interval)) were planned here. [Superseded by the split below; DW-1326 stays as the Always rule.]
- 2026-11-14 (plan). **Contest Planner, ~12:45Z Nov 14 (BINDING):** "the mailbox" inside the digest sentence. [Superseded by the split below.]
- 2026-11-14 (plan). DW-1328 was not settled; planned behind `Watch.Ops.REPOINTRESETS` as CONFIRM. [Settled: RESET, below.]
- 2026-11-14 (lead). **Gate ruled, Contest Planner ~13:20Z Nov 14:** SPLIT approved. Matrix rows 8-11, the DW-1325 (`Mcp/Ops.cls` `OnSetSource`), DW-1327 (`Checks/Coverage.cls`), DW-1328 switch (`Watch/Ops.cls` `REPOINTRESETS`) and mailbox-sentence (`Digest/Process.cls`) tasks, their tests and ACs move to Story 22.13 (`spec-22-13-keep-source-names-staleness-and-repoints-honest-on-the-cover.md`). DW-1328 is RESET (confirmed); 22.11 keeps the baseline rule (first good run since `CreatedAt`) and `TestRepointBaseline`. Task 0 gains the STOP: due polls adding more than 10 s to the median triage decision time, or any triage decision missing its timeout, go to the Planner. `reserved_name` in 21.5 is lane C's cross-lane bullet. Status reset to `draft` for a re-plan of the poll run after 22.13 merges.
- 2026-11-14 (re-plan, after 22.13 merged at `f403bf66`). Applied the ~13:20Z split, quoted from `<coordination>/prompts/epic-22-rulings-20261113-1715.md`:
  - "1. **SPLIT: approved.** […] 22.11 keeps the poll run: the bridge, Checks and the stop notice."
  - "2. **DW-1328: RESET is confirmed.** History starts over, the next good run sets a baseline with no Item, coverage counts only runs since the repoint, and an interval or letter-case-only change keeps everything."
  - Notes: "Triage delay (22.11's Task 0): STOP to the Planner if due source polls add MORE THAN 10 s to the median triage decision time, or make ANY triage decision miss its timeout." and "Precedents for source Items: file a LOW burndown DW" (DW-1334).
  - **Intent block amended** (by the ruling and the lead's re-plan dispatch): the Problem's ledger and mailbox sentences, the Approach's "three ledger items" and "digest sentence" bullets, and matrix rows 8-11 (reserved name, long interval, repoint, digest sentence) removed; row 12 is now row 8; a new row 9 holds the baseline half of DW-1328 that stays here. The Lanes list drops `Watch/Ops.cls`, `Checks/Coverage.cls`, `Digest/Process.cls` and the Digest tests; `Mcp/Ops.cls` keeps only `SourceStopped`.
  - Removed: the DW-1325/1327/1328-switch/Digest tasks, ACs, tests and mutation rows; the CONFIRM veto item; the `reserved_name` veto item and the two Planner public texts (now 22.13's, approved); the split recommendation; the `multiple-goals` warning.
  - Added: Task 0 item 5 (the measured STOP); `TestAnswerBeforeRepoint`, `TestStoppedChanged`, `TestStoppedCoverage`, `TestSourceStoppedNotice`; the probe class `Test/Mcp/SourceProbe.cls`; the completion key `<Ref>|<sentAt>`.
  - Code Map re-checked line by line at `5fafee78`.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-2 and AD-31: the bridge names no host class; `PollCall` is an extension method.
- AD-5: state on rows.
- AD-6: a `tool` request is "one governed tool call, either an approved call's replay or, from step 4, a source poll", with no model; the `Busy` reply is the precedent for a reply with no `Decision` row.
- AD-9: steps from the step audit.
- AD-10: one gate, the untrusted rule, the fingerprint at call time.
- AD-12: `check` events and `/v1/state`.
- AD-17: one audit writer.
- AD-18: `Checks` runs due rows and records them; the source row (Part A and its 22.13 amendment: a repoint moves `CreatedAt`); coverage; CheckRun.
- AD-21: "Source polls (step 4) call `call_mcp_tool` through a `tool` request to `Decide`"; the proxy's bounds and the S11 residual; no MCP on the demo.
- AD-25: the demo. AD-28: the all-clear only from `Render`. AD-29: lanes.
- AD-30: untrusted Items go to `Intake`; `Decide` sends only steps besides its response.
- AD-32: notices are catalog keys. AD-33: `Checks` is the run-field writer and the one `check` publisher.

No AC contradicts an AD's Rule. No NFR trips Rule 5: the Planner's two triage-delay limits are measurable (Task 0 item 5).

**Delivered by 22.13 (merged; not this story's work):**
- DW-1325: `Mcp/Ops.cls` `OnSetSource` answers `reserved_name` with `MESSAGESOURCERESERVED` (L213, L83).
- DW-1327: `Checks/Coverage.cls` `EarlierRun` (L478, a `CreatedAt` bound) and `Current` (L497) let a source's latest run since `CreatedAt` count within max(window, interval + 180 s).
- DW-1328's switch: `Watch/Ops.cls` `REPOINTRESETS` (L46); `SetSource` moves `CreatedAt` on a repoint (L251).
- Both mailbox sentences: `Digest/Process.cls` `MAILBOXINSENTENCE` (L83, L522, L631).
- The AD-18 amendments for DW-1325, DW-1327 and DW-1328.

**Out of scope (ledgered):** DW-1334 (LOW, `owner=burndown`, Planner ~13:20Z Notes): `Data.Precedent.KeyFor` (Lane B) has no key form for a poll Item, so precedents do not learn from source Items.

**Triage delay: the risk Task 0 item 5 measures (inference).** TriageAgent has PoolSize 1, so a poll holds triage decisions behind it. A silent `tools/call` holds it about 20 s (the client bound); a trickling server about 31-36 s (S11, measured in 22.10's ruling H). With 3 due silent sources, a decision queued behind them could wait about 60 s, Decide's `TimerSeconds`, so the "any decision misses its timeout" limit is the likelier one. If the STOP fires, options for the Planner (none is taken here): (a) at most one poll in flight, the next due sources waiting for the next Tick; (b) a dedicated poll runner item (a NEW production item: veto); (c) TriageAgent PoolSize 2 (a production setting).

**Carried from 22.5's "Moved to 22.11", re-checked at `5fafee78`:** the earlier plan's `Gate.ClassifyMcp` is `FromMcp`/`FromProxy`; the proxy's demo sentence is `Tools/McpCall.MCPDEMO`; `ProxyManager` needs the agent, so `PollManager` is split out of it; `Test/Mcp/Mock` already has a settable answer (`Call(port, "text", value)`) and the slow modes, so no Mock change; `Record` writes CheckRun through the table trigger; the Request has `OwnerRef`, not SessionRef.

**Decided in-stage (kept from 22.5's gate-reviewed plan):**
1. **A result is the tool's whole text answer**, de-duplicated by SHA-256 against the newest 50.
2. **The first successful run since `CreatedAt` is a baseline** (DW-1328 RESET, ruled).
3. **The poll runs on TriageAgent.**
4. **The map is seeded from a live listing** (`PollCall` → `Proxy.Listed`), so a changed tool is refused before the call.
5. **The request carries the Ref only.**
6. **The run is async, and `NextDueAt` advances at the send.**
7. **A poll gets no `Decision` row.**
8. **A stopped source keeps recording** and resumes by itself.
9. An empty answer is `passed` and never an Item.

**Decided in-stage (this re-plan):**
10. **An answer for the pre-repoint target records nothing.** The completion key is `<Ref>|<sentAt>` (`MasterPendingResponse.CompletionKey` has no length limit); a `sentAt` before the row's `CreatedAt` is dropped like a removed row. Otherwise the old target's answer would become the new target's baseline and every new result would arrive as an Item (22.13's review left this case to 22.11).
11. **`changed` reads as stopped.** The gate counts a tool whose fingerprint changed as unclassified (AD-10, AD-21), so "no longer Read-only" is true; the stop notice goes once, and the next attach clears the row (22.8).
12. **`stopped` is the latest run's state:** every run that is not a stop clears it, so a later stop always notifies once.
13. **`SeedMcp` writes the entry directly** (with `SetMcpTools`' key checks, shared) rather than through `SetMcpTools`, because `PollCall` returns a fingerprint, not a description and schema.
14. The baseline test is "`Reported.baseline` is not 1" after the start-afresh rule, so a stopped run before the first success does not use up the baseline.
15. Task 0 item 5 runs after the poll path is built, because there is nothing to measure before it; it still runs before the tests and the review, and it HALTs the stage.
16. A poll's `turn.step` reaches no chat: `BridgeSink.Step` publishes only for the running turn's ItemId (read, not changed).

**Extend, don't copy (Rule 2):**
- `PollManager` is split out of `ProxyManager`, and `Proxy.Listed` shares `Run`'s prefix.
- `Poll.Run` follows `Replay.Execute`'s shape but is its own class, because the approval steps (`StartExecution`, the grant, the lock) must never apply to a poll.
- `SeedMcp` shares `SetMcpTools`' key checks.
- `RunSources` follows `RunQueues`; `OnResponse` reuses `Record`, `SendOwn` and `Announce`; `SourceItem` follows `FindingItem`/`Beat`.
- `SourceStopped` extends `Notify`/`Send`; `SourceProbe` extends `Test.Checks.Probe` as `QueueProbe` does.

**Integration ACs (Rule 1):**
- The new surfaces are `Bridge.Poll`, `PollCall`, `Proxy.Listed`, `Context.IsPoll`/`SeedMcp`, `Agent.PollManager`, `Checks.RunSources`/`OnResponse` and `Mcp.Ops.SourceStopped`.
- Consumers in this story: `Intake` produces an `ItemDecision` from a poll Item (`TestNewResultReachesIntake`, real production); `Checks.Coverage.Build` reads the CheckRun rows the run wrote (`TestStoppedCoverage`); `Decide` → TriageAgent → `Bridge.Poll` (`TestPollRuns`); `NoticesIn` takes `SourceStopped`'s notices (`TestSourceStoppedNotice`, through `OpsProbe`).

**Consumes:** 22.5 (the source rows, `REASON*`, the coverage source branch); 22.13 (the moved `CreatedAt`, `Coverage.Current`); 22.3 (`call_mcp_tool`, `Proxy`, `Client.ListTool`, the `MCP` audit); 22.4 (`ProxyManager`, `NoteReplayRefusal`, `Attach.Toolref`); 22.8 (the extension's classification, `ClearChanged`); 22.9 (the bounds); Epic 30 (the `tool` path in `Decide`); AD-30 (`Intake`); 35.1 (`mcp.sourceStopped`, `digest.notCheckedStopped`).

**Consumed-by:** 21.5 (Lane B) renders the source's run from the `check` events; 22.12 documents the run (the baseline, whole answers, the stop).

**Story 21.5.** 21.5's spec (lane C) edits `Web/McpSettings.cls`, `Core/SettingsOps.cls` and `web/**` only, so it shares no file with this story.

**Contended edits (for the lead):** `Checks/Process.cls` (one Try block in `Tick`, appended `ROWCOLUMNS` columns and an appended block; Epic 23/36 plain union); `Mcp/Ops.cls` (one appended method); `Bridge/Process/Decide.cls`, `Adapter/Agent.cls` and `Policy/Gate.cls` (non-append branches).

**Ledger inbox (Rule 17).** `LEDGER slice 22-11-run-source-polls-through-the-governed-proxy` is empty (checked at `5fafee78`): DW-1325, DW-1327 and DW-1328 were re-owned to 22.13 and resolved there; DW-1326 is resolved; DW-1334 is `burndown`'s.

**Spine updates for the lead (Rule 20; S-labels left to the lead):**
1. **AD-18, a record "Source polls, Part B (Story 22.11)":** async `tool` requests with the Ref only, and `NextDueAt` set at the send; whole-answer results with SHA-256 hashes (newest 50) in `Reported`, and the first success since `CreatedAt` as a baseline (an answer to a poll sent before a repoint records nothing); untrusted Items (channel `system`, Subject the source's name); a stop (a classification other than Read-only or a changed tool, before the send or after a denial) recorded as Reason `stopped`, with one `mcp.sourceStopped` per transition, resuming by itself; never on the online demo.
2. **AD-6/AD-10, a record.** A `tool` request with Provenance `untrusted` is a source poll: its Input is `{"source": Ref}` and it runs on the `decide` runner; it makes one `call_mcp_tool` on a standalone governed proxy-only manager, with the map seeded by `PollCall`; the gate admits only the proxy, with no grant, under the untrusted rule; it writes no `Decision` row or event, and the Reply carries the answer text and one reason word.
3. **AD-31.** `McpServersClass.PollCall`, default `invalid`, with its `POLLREASONS`.
4. **Task 0 item 5's numbers**, once measured, as a measured fact under AD-21's S11 residual.

## Veto items

**Approved for 22.11 at 22.5's gate (veto 1-10; tags as ruled), kept:**
- 2: CheckRun Reason `stopped` (written here). Online demo: never written.
- 3: outward actions: the seed listing plus the proxy's requests, every 5 to 1,440 minutes, bounded 2/2/2/20 s. Online demo: none.
- 4: the security posture (untrusted, never held; the answer stored in the Reply and the Item; arguments only in the row). Online demo: unchanged.
- 6: `mcp.sourceStopped` to every admin session. Online demo: never sent.
- 7: bridge request semantics and the `PollCall` extension (22.5 labelled them S19/S20; the lead relabels). Online demo: no change.

**NEW:**
1. **NEW reason codes (contract words, within veto 7's scope, listed for the gate):** `PollCall`'s and a poll Reply's `FailureText` words `invalid`, `notreadonly`, `notfound`, `unreachable`, `timeout`, `failed`, `changed`, `demo` and `denied`. Bridge-to-host only; never shown to a person; `Checks` maps them to the existing findings. Online demo: never produced (no poll runs).
2. **NEW stored format (a source row's `Reported`, no column):** `{"seen": [at most 50 SHA-256 hex hashes of whole answers], "baseline": 1, "stopped": "" | "not_read_only"}`. Hashes only: the answer text is never stored on the row. Kept until the row is removed. Online demo: never written.

No new route, privilege, role, grant, resource, table, column, retention, production item, web dependency or extension class.

## Public text

**NEW:** none.

**Existing, reused:**
- **From 35.1 (accepted):** `mcp.sourceStopped` ("The source {source} stopped polling at {time}, because its tool {tool} on {server} is no longer Read-only. Your digest lists it as not checked.") and `digest.notCheckedStopped`.
- **From 22.5 (approved):** `REASONSOURCEUNREACHABLE` ("Couldn't reach its MCP server"), `REASONNOTREADONLY` ("Its tool is no longer Read-only").
- **Already in use:** `REASONTIMEOUT`, `REASONREAD`, `digest.notCheckedUnreachable`, `digest.notCheckedStale`; 22.3's step label "Running {tool} on {server}" and its `MCP*` refusals.
- **Not product text:** a poll Item's Subject (the admin's source name) and Text (the tool's answer); the `LOGPOLL*` operator log lines (no argument, URL or secret).
- **Approved at 22.13, not this story's:** `MESSAGESOURCERESERVED`, `MAILBOXINSENTENCE`.

**Findability:** no UI here (21.5 renders the run; 22.12 documents it).

## Verification

Each `ci/iris.sh` and `ci/warm.sh` call carries the lane's variables:
`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s11iw`; fresh runs use `OCUTALON_RUN_TAG=e22s11i`.
- One test class per foreground call, with `timeout: 600000`; each must finish inside about 150 s (Task 0 item 5: one mock mode per call).
- Never two `iris_execute_tests` calls in one message. Pass `server` `ocutalon-slot-d` and `namespace` `OCUTALON` on every IRIS MCP call (read-only lookups).

**Commands:**
- (once) `ci/warm.sh status`, then `OCUTALON_RUN_TAG=e22s11iw ci/warm.sh up` -- expected: a ready warm stack.
- (loop) Warm, each `ci/iris.sh class <Class>` -- expected: `CLASS … passed`:
  - `OcuTalon.Test.Bridge.Poll`
  - `OcuTalon.Test.Bridge.Gate`
  - `OcuTalon.Test.Bridge.Decide`
  - `OcuTalon.Test.Bridge.Ext`
  - `OcuTalon.Test.Mcp.SourceRun`
  - `OcuTalon.Test.Mcp.SourceRunProduction`
  - `OcuTalon.Test.Mcp.Proxy`
- (once) Warm, each `ci/iris.sh class <Class>` -- expected: passed:
  - `OcuTalon.Test.Bridge.Runner`, `OcuTalon.Test.Bridge.Approval`
  - `OcuTalon.Test.Mcp.Approval`, `OcuTalon.Test.Mcp.Attach`, `OcuTalon.Test.Mcp.Ops`, `OcuTalon.Test.Mcp.SourceSet`, `OcuTalon.Test.Mcp.SourceSetProduction`
  - `OcuTalon.Test.Checks.Queues`, `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Digest.Coverage`, `OcuTalon.Test.Digest.AllClear`
  - `OcuTalon.Test.Watch.Ops`, `OcuTalon.Test.Msg.Catalog`
- (once) `bash docker/tests/test-boundaries.sh` (the bridge names no OcuTalon class), `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-ci-config.sh`, one per call -- expected: exit 0.
- (once) `OCUTALON_RUN_TAG=e22s11iw ci/warm.sh down` -- also after a failure.
- (once) Fresh: `OCUTALON_RUN_TAG=e22s11i ci/iris.sh class OcuTalon.Test.Mcp.SourceRunProduction`, then `OCUTALON_RUN_TAG=e22s11i ci/iris.sh teardown` -- expected: passed on a fresh stack, then torn down.

**CI:** no new unit, group or area. The new `Test.Mcp.*` classes join `shards-2` and `Test.Bridge.Poll` joins `shards-9`, adding about 60-120 s (inference).

**Shared surfaces:** `Decide.Admit`'s tool rule (`Test.Bridge.Decide`); the gate's replay rule (`Test.Bridge.Gate`, `Test.Mcp.Approval`); `Ext.McpServers`' methods (`Test.Bridge.Ext`); `Proxy`'s shared prefix (`Test.Mcp.Proxy`); `ROWCOLUMNS` and `RowOf` (`Test.Checks.*`); the `CheckRun` Reason values (`Test.Digest.Coverage`); `Ownership.AdminSessions` notices; TriageAgent's queue (every production test that waits on a triage decision).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19):**

| Mutation | Test that goes red |
| --- | --- |
| The poll's runner uses an ungoverned manager | `TestPollRuns` |
| A poll writes a Decision row | `TestPollNoDecisionRow` |
| Skip the `seen` check | `TestSeenBefore` |
| `SourceItem` not sent | `TestNewResultReachesIntake` |
| `Record` without keep in `OnResponse` | `TestNextDueAtAtSend` |
| Notify on every stopped run | `TestStoppedNotifiesOnce` |
| Any name allowed in a poll | `TestPollOnlyProxy` |
| The gate requires a grant in a poll | `TestPollNoGrant` |
| Ignore `CreatedAt` in the start-afresh rule | `TestRepointBaseline` |
| Drop the `sentAt` check | `TestAnswerBeforeRepoint` |
| Drop the demo return in `RunSources` | `TestOnlineDemoNoPoll` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Re-planned only (halt after planning); nothing implemented. Open for the lead: the two NEW veto items (the poll reason words; `Reported`'s source shape); the AD-18/AD-6/AD-10/AD-31 spine records (Design Notes); Task 0 item 5's STOP, which the implement stage measures and HALTs on.
