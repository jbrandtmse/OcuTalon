---
title: 'Story 22.11: Run source polls through the governed proxy'
type: 'feature'
created: '2026-11-14'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-5-poll-a-read-only-mcp-tool-as-a-source.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 22.5 (Part A) gives an admin a `source` row, its coverage entry and the digest's not-checked lead, but nothing runs a source: `Checks` reads only `production` and `queues` rows, so every source reads "didn't run". `Decide` refuses an untrusted `tool` request, so a poll has no governed path to `call_mcp_tool`. Three ledger items also land here: a source can be named "Mailbox" (DW-1325), a source polled less often than the digest span reads stale (DW-1327), and a repointed source keeps its old seen results (DW-1328). The digest's "I checked" sentence also says "the Mailbox" where the Planner ruled "the mailbox".

**Approach:**
- **The run.** On each Tick, `Checks` sends every due `source` row one asynchronous `tool` request (provenance `untrusted`, Input `{"source":"<Ref>"}`) through `Decide`. `Decide` admits it as a poll, runs it on the `decide` runner (TriageAgent) and writes no `Decision` row. The runner's new `Bridge.Poll` runs exactly one `call_mcp_tool` on a standalone governed manager that holds only the proxy, with its call map seeded from a live listing through the new `PollCall` extension. No model is called.
- **The record.** `Checks.OnResponse` records the run. A result not seen before, after the first successful run (the baseline), becomes one untrusted Item for `Intake`.
- **The stop.** A source whose tool is no longer Read-only makes no call. It records `stopped`, and admins get the accepted `mcp.sourceStopped` once per transition.
- **The three ledger items:**
  - `McpOps` refuses the name "Mailbox" with its own outcome (DW-1325).
  - Coverage lets a source's latest earlier run count when it is within max(window, interval + 180 s) of the window's end (DW-1327).
  - A repoint starts the source afresh (DW-1328, **CONFIRM**).
- **The digest sentence** names the connected mailbox "the mailbox" (Planner ~12:45Z).

## Boundaries & Constraints

**Always:**
- **Lanes (AD-29).** Lane A files only:
  - the bridge's `Process/Decide.cls`, `Adapter/Agent.cls`, `Policy/Gate.cls`, `Context.cls`, `Ext/McpServers.cls` and the new `Poll.cls`;
  - `Mcp/{Attach,Proxy,Ops}.cls`, `Watch/Ops.cls`, `Checks/{Process,Coverage}.cls`, `Data/BackgroundCheck.cls` (doc only), `Digest/Data/CheckRun.cls` (doc only), `Digest/Process.cls`;
  - `Test/{Mcp,Bridge,Checks,Digest}/**`, Lane A rows only.
- **Governed like a built-in tool (AD-10, AD-21).** A poll's call goes through:
  - the gate: `UNREGISTERED`, the extension's classification at the live fingerprint, `U` on `OcuTalon_MCP_<server>`, and the untrusted rule (only safe and read-only runs; anything else is `UNTRUSTED`, never held);
  - the step audit, which writes one step labelled "Running {tool} on {server}";
  - the proxy's re-list, fingerprint check, cut and one `MCP` `called`/`refused` audit entry.

  It never reaches AI Hub's MCP client and never calls a model. In a poll the gate admits only `call_mcp_tool`, and no grant is needed or taken.
- **Untrusted (AD-30).** Results reach `Intake` only as Items with provenance `untrusted`. A result never approves, classifies, changes a setting or adds a server.
- **AD-5.** "Due", "seen", "baseline" and "stopped" live on the row (`NextDueAt`, `Reported`, `CreatedAt`), never in memory.
- **AD-33.** `Checks` alone writes the run fields (`LastRunAt`, `Result`, `Finding`, `LastRunHeaderId`, `Reported`), each with one SQL `UPDATE` keyed by `Ref`. `NextDueAt` is also written by `Checks`, except that `Watch.Ops.SetSource` sets it to now on a save (22.5). A source removed meanwhile is never re-created, and its answer sends no Item.
- **The latest run counts (AD-18, DW-1326).** There is no "all runs passed" rule.
- **Online demo (AD-21, AD-25).** `Checks` runs no `source` row when `Watch.Reader.OnlineDemo()` is 1. `McpOps` refuses both verbs (22.5), and the proxy refuses with `MCPDEMO`. MCP never runs on the demo, and a test pins it.
- **Approved public text stays verbatim** (22.5's nine strings, 35.1's keys, and the two Planner texts under Public text).

**Never:**
- Edit `Core.*`, `Web.*`, `web/**`, `Msg.*`, `Data.Precedent`, `Data.Setting`, `Channel.*`, `Test/Contract/**`, `Test/Core/**`, `Test/Live/**` or any Lane B test. If a Lane B test pins the old behaviour, stop with `## Clarification Needed`.
- Put an argument value, URL or secret in a request message, log, audit entry, step label or notice. A poll's request carries the source's Ref only.
- Hold a poll's call, give it a grant, register an MCP server on an agent's own manager, put the proxy in any `TOOLSETS`, or add a production item, route, role, privilege, grant, resource, table or column.
- Take Story 21.5's scope: the Settings source form, the source list, the rail's "Polled every {n} minutes" line and the HTTP mapping of McpOps outcomes. Also out of scope: the docs (22.12) and listing through OcuTalon's client for turns (22.10, declined).
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
| 8 Reserved name (DW-1325) | `SetSourcePoll` with Name "Mailbox", " mailbox " or "MAILBOX". | Ok 0, outcome `reserved_name`, message `MESSAGESOURCERESERVED`. No row, no audit entry, no `CheckChanged`. | "My Mailbox" and "Mailboxes" are accepted. |
| 9 Long interval (DW-1327) | A 24 h digest window and a 48 h source with no run in the window. Its latest run passed, 30 h before the window's end. | `passed`, checked at that run. | The same run 50 h before the end: `digest.notCheckedStale` {that time}. A run before the row's `CreatedAt` never counts. |
| 10 Repoint (DW-1328, CONFIRM) | An update of "Jira" with a different server, tool or arguments. | The same Ref. `CreatedAt` and `NextDueAt` become now. The next successful run is a baseline: `Reported` starts afresh (seen, baseline and stopped) and no Item is sent. Coverage counts only runs since the repoint. CheckRun rows are kept. | An update that changes only the interval or the name's letter case keeps `CreatedAt` and `Reported`. |
| 11 Digest sentence | The session watches the Orders production, a source "Jira" and the mailbox. | "I checked the Orders production, Jira and the mailbox." (and the `digest.checkedQuiet` variant). Coverage lines, the lead, `whatFailed` and check rows keep "Mailbox". | none |
| 12 Other tool requests | An untrusted `tool` request whose Input is not `{"source": <Ref>}`; or a user `tool` request. | The first is refused by `Admit`, naming `Provenance`, as today. The second is a replay, unchanged. | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/cls/OcuTalon/Bridge/` (shown as `Bridge/`). Line numbers are at `aa94694a` (feature `f138fcf8` merged; 22.5 and 22.6 done).

- **Decide** (`Bridge/Process/Decide.cls`):
  - `RUNNERS` L142 (`decide:TriageAgent,…`; no `tool` entry).
  - `OnRequest` L328-365. L334 answers from an existing Decision row; `tool` skips the reply class (L340), `Held` (L346) and `Precheck` (L357). L352-354: runner "" → `FailUnroutable` + `RecordFallback` (writes a row).
  - `OnResponse` L407-451: the timer L411-415 → `TryRetry` → `RecordFallback` (L745; `Retryable` L553 is 0 for tool); `EmitSteps` L419; `Conclude` L448.
  - `Admit` L846-864: L856 requires Provenance `user` for `tool`, L857 `Approval.IsRef(ItemId)`.
  - `RunnerFor` L869-884 (a tool request takes the `tool_call` row's Runner).
  - `Conclude` L1378 (L1389 → `ConcludeTool`).
  - `ConcludeTool` L1515-1548: the `StillApproved` bare Reply with no row (L1519-1522) is the no-row precedent; the other failures go to `RecordFallback`; success saves a row (L1537-1544), `FireEvent` (L1546), `ResponseFromRow` (L1547).
  - `RecordFallback` L1662-1692; `FireEvent` L1751; `ResponseFromRow` L1786 (tool branch L1792-1801).
- **Bridge messages:**
  - `Bridge/Msg/Request.cls`: Kind 9, Provenance 12, Input 15, ItemId 18, Summary 21, DecisionRef 24, OwnerRef 27, TraceRef 30, Channel 33. There is no SessionRef.
  - `Bridge/Msg/Reply.cls`: Text, Tainted, ToolsRun, Steps, FailureText (MAXFAILURE 2000); from `Result`: Fallback, FallbackReason, AgentStepCount, DurationMs.
  - `Bridge/Msg/Enum.cls`: PROVENANCE L9, REQUESTKIND L12.
- **Runner** (`Bridge/Adapter/Agent.cls`):
  - `Answer` L909-958: L919 sends `tool` to `Replay.Run`.
  - `BuildAgent` L279-303 needs the provider (no key fails).
  - `Govern` L499-504 (Private); `ProxyManager` L788-808 (a new `%AI.ToolMgr` with only `ProxyToolSet`, governed; L799 refuses when the agent is not built); `RestoreTools` L812.
- **The pattern to follow** (`Bridge/Replay.cls`): `Run` L55-80; `Execute` L83-156 (`Context.Begin` L104-107, `StepBuffer.Start(0)` L111, `ExecuteTool` L118, `ReplayRefusal` L119, done test L123, `StepRecords`/`StepsJson` L137-138, release on every path L142-146, Reply L148-155); `ProxyCall` L163-183.
- **Context** (`Bridge/Context.cls`):
  - `Begin` L72-89 copies Kind and Provenance and resets taint; `End` L92; `Active` L98.
  - `SetMcpTools` L154-188; `McpFingerprint` L192; `McpToolref` L205; `McpServerOf` L244; `TakeGrant` L298; `ApprovedFingerprint` L317.
  - `NoteReplayRefusal`/`ReplayRefusal` L326-340. There is no `IsPoll` or `SeedMcp` yet.
- **Gate** (`Bridge/Policy/Gate.cls`):
  - `UNREGISTERED` L118, `UNTRUSTED` L122, `REPLAYKIND` L125, `MCPPROXY` L139.
  - `Decision` L208-254: `replay = (Kind = "tool")` L213; classification L215, unregistered L216; taint ignored in a replay L221; the untrusted rule L222; the replay grant branch L223-229; report and taint L242-251.
  - `ReplayToolref` L361; `ClassificationOf` L513; `ReportStep` L601-609; `FromMcp` L629 (needs `McpFingerprint` from the map, L644); `FromProxy` L654.
- **The step label:** `Bridge/Adapter/StepBuffer.cls` `LabelFor` L222 and `McpLabel` L235-262 need the seeded map (L257).
- **Extension:** `Bridge/Ext/McpServers.cls` `REASONS` L37 and the defaults L40-74 (no `PollCall`). `Mcp/Attach.cls` overrides at L31-105; `Toolref` L79-83 (Attach only).
- **Proxy** (`Mcp/Proxy.cls`):
  - `Call` L38-54: `approved` L40, the demo L41 (seam `OnlineDemo` L194-197; the `MCPDEMO` sentence is `Tools/McpCall.cls` L37).
  - `Noted` L58-62 calls `NoteReplayRefusal` only when `approved` is not empty, so a poll's refusal is not noted today.
  - `Registered` L67-75.
  - `Run` L78-103: the class L80, entry L81-85, header L86-87, `Client.ListTool` L88, `Attach.Toolref` L90, fingerprint L93-97, `CallTool` L98.
  - `Reason` L139-142 (demo, changed, failed, timeout; plus address, credential, notfound); `Audit` L166-185. There is no `Listed`.
  - `Mcp/Client.cls` `ListTool(url, header, tool, Output definition, ByRef session)` L60.
- **Checks** (`Checks/Process.cls`, 996 lines; PoolSize 1 in `Production.cls` L62; it has no `OnResponse`):
  - doc L1-87 (queue rows L78-85); `ROWCOLUMNS` L127 (positions 8 and 9 read by `DueOf`/`RowOf`, so append only).
  - `REASON*` L151-159 (`REASONTIMEOUT` L155, `REASONREAD` L157); `SYSTEMCHANNEL` L201.
  - `OnRequest` L203-213; `Tick` L216-284, with the queue block L243-255. **Insert the source block at L256**, before `SettingHistory` and the beats.
  - `SendOwn` L392-406; `TraceOf` L491-496; `Due` L508-511; `RowOf` L533-536.
  - `Record(row, tickAt, runAt, result, finding, reported, items, keep)` L609-630: keep leaves `NextDueAt` (L612); quits on `%ROWCOUNT<1` (L618); items via `SendOwn` (L619-625); `Announce(FromRow)` (L626-628). The `BackgroundCheck` trigger writes the CheckRun row.
  - `FindingItem` L705-718; `Changed` L811-832; `Announce` L835-841; `SendFinding` L852-855 (the Intake seam).
  - `DueOf` L876-888; `QueueDue` L891-894; `RunQueues` L897-965 (the appended-block precedent).
  - 22.5's `SOURCEKIND` L982, `REASONSOURCEUNREACHABLE` L985, `REASONNOTREADONLY` L989.
  - Online demo through `Watch.Reader.OnlineDemo()` (L520, L569).
- **Coverage** (`Checks/Coverage.cls`):
  - `MISSEDSECONDS` L49; `ENTRYMAILBOX` L66; `Build` L144-179 (the `kind` stamp L175, `MailboxRow` L177).
  - `WatchRow` L292-352: spanStart L295-297, paused L298-305, `Runs` L306; **no run in the span: L307-314** (`EarlierRun` L308; stale L309-310; missed L311-312); allowed gap L316-319; latest-run rules L330-351.
  - `Runs` L455-464; `EarlierRun` L467-472 (selects `RanAt` only).
  - `ReasonOf` L537-541; `KeyOf` L544-547; `RecordRun` L553-563 (its doc L550-551 omits the source reasons).
- **Rows:**
  - `Data/BackgroundCheck.cls`: `NextDueAt` L35, `LastRunAt` L38, `LastRunHeaderId` L47, `Reported` L50 (doc L49: production shape only), `Server` L53, `Tool` L56, `Arguments` L59, `IntervalMinutes` L62; the trigger L66-71.
  - `Digest/Data/CheckRun.cls`: the `Reason` doc L22 omits `stopped`.
- **Watch.Ops** (`Watch/Ops.cls`): `FIELDS` L71; `SetSource` L232-269 (both paths set DisplayName to Interval and `NextDueAt` L252-258; never touches `Reported`, `CreatedAt` after creation, or the run fields); `RemoveSource` L273-300; `SourcesOf` L303-312; `RefOf` L357-371; `Lock` L374-378.
- **McpOps** (`Mcp/Ops.cls`):
  - doc L3-12 and L34-37; `MESSAGE*` L56-86.
  - `OnSetSource` L192-225: the name trimmed L206, `bad_name` L207, arguments L208-209, interval L210-211.
  - `SaveSource` L435-466; `ClearChanged` L640 (once-per-transition precedent); `Notify` L748-773; `Send` L776-789; `Answer` L890; the seams `AdminSessions` L927, `Notice` L933, `WriteAudit` L945. No `SourceStopped` yet.
- **Catalog** (read only, `Msg/Catalog/Watch.cls`): `digest.checkedQuiet` L468, `digest.checked` L475, `digest.notCheckedUnreachable` L504, `digest.notCheckedStale` L546, `digest.notCheckedStopped` L561, `mcp.toolChanged` L1060, **`mcp.sourceStopped` L1076** (35.1's accepted wording; slots source, tool, server, time).
- **Items** (read only): `Msg/Item.cls` (ItemId, SessionRef, Channel, Provenance, Text, Subject, CatalogKey, Slots); `Msg/Enum.cls` L36 `CHANNEL` includes `system`; `Checks/Beat.cls` L544-550 is the untrusted-Item precedent.
- **Digest** (`Digest/Process.cls`): `Finish` L505-530 (L517 pushes `"the "_entry` unless the row is a source); `Verdict` L576-613 (`sources` L604; mailbox-only test L607).
- **Tests and fixtures:**
  - `Test/Mcp/Mock.cls`: `Call(port, mode, value)` L144 (mode `text` sets the `tools/call` answer; no Mock change is needed), `Stop` L87, `Silence` L108, `Speak` L114, `Requests` L168, `Calls` L181, `Describe` L95.
  - `Test/Mcp/SourceSet.cls`: `TestSetRefused` L150 (`bad_name` block L166-172), `TestUpdate` L103, helpers `Run` L531, `Refuse` L541, `SetCommand` L548, `MakeRows` L601, `Clean` L671, `Leftovers` L693.
  - `Test/Mcp/SourceSetProduction.cls` (extends `Test.Core.InProduction`): `Submit` L172, `Clean` L254.
  - `Test/Mcp/Attach.cls`: `Runner` L1818, `Use` L1824, `Register` L1849, `LoggedSecret` L2077, `Leaks` L2125. `Test/Mcp/Proxy.cls` `TestDemo` L287.
  - `Test/Checks/Queues.cls` `Host` L544, `Tick` L570; `Test/Checks/QueueProbe.cls` L13-19 (the Tick seam pattern); `Test/Checks/Probe.cls` `SendFinding` L176-191.
  - `Test/Digest/Coverage.cls`: `TestStale` L308, `TestSourceIntervalGap` L360, `TestStoppedStreak` L388; helpers `Source` L821, `Run` L845, `Slots` L860, `Built` L875.
  - `Test/Digest/Compose.cls` L493-509 (`TestCheckedListSourceBare`: it expects "the Mailbox" today).
  - `Test/Bridge/Decide.cls` `TestRefusedRequests` L281 (L289-290: untrusted tool refused naming Provenance; stays), `TestToolRequest` L327.
  - `Test/Bridge/Gate.cls`: `TestReplayKeepsThePermissionAndProvenanceRules` L2584, `TestReplayGovernance` L2639.
  - `Test/Bridge/Ext.cls` `TestExtensionBases` L183.
- **CI:** `ci/units.sh`. `Test.Mcp.*` and `Test.Checks.*` run in `shard:lane-a@rest` (`shards-2`), `Test.Bridge.*` in `@Bridge` (`shards-9`), and `Test.Digest.*` in `@Install,Digest,Eval` (`shards`). There is no new area.

## Tasks & Acceptance

**Execution:**

- [ ] **Task 0** (implement, before code). Run on lane D's warm throwaway (tag `e22s11iw`) with scratch classes `ZzT11*`, removed afterwards. Record the answers in `_bmad-output/implementation-artifacts/evidence/22-11-task0-poll.md`:
  1. **The manager.** In TriageAgent's job, with no `BuildAgent` and no model key, build a governed `%AI.ToolMgr` that holds only `ProxyToolSet()`. In a poll context (Kind `tool`, Provenance `untrusted`, map seeded), run `ExecuteTool("call_mcp_tool", {server, tool, arguments})`. Record:
     - that the gate and the step audit run, and the step's label;
     - the answer for a result, for a proxy refusal and for a gate denial.

     22.4's evidence (`evidence/22-4-task0-replay.md`) measured the same manager after `BuildAgent`. If it fails without the agent, use `BuildAgent` + `ProxyManager`; then a poll on a keyless install records `error`. Record the text.
  2. **The async answer.** `Checks` sends `SendRequestAsync("Decide", request, 1, <Ref>)` and gets the Reply in `OnResponse`, with `%SessionId` the Tick's session. Show that a second Tick is handled while a poll waits on a silent mock (`Mock.Silence`), and record the timings. If the Checks job is held instead, stop with `## Clarification Needed` (AD-18's one-minute Tick).
  3. **Steps with no Decision row.** `EmitSteps` with the request's DecisionRef and no `Decision` row stores the step and shows it in the Tick's trace. Record the row.
  4. **The wire.** The exact mock request sequence of one poll (the seed listing, then the proxy's requests). If it differs from approved veto 3, record the measured one.
- [ ] `Bridge/Ext/McpServers.cls` -- add `PollCall(source, Output server, Output tool, Output arguments, Output toolref, Output fingerprint) As %String`. The default answers `invalid`. The answer is "" or one word of a new `POLLREASONS` (`invalid,notreadonly,notfound,unreachable,timeout,failed,changed,demo`). Doc bullet.
- [ ] `Mcp/Attach.cls` -- override `PollCall`:
  1. the `source` row by Ref (no row or another kind gives `invalid`);
  2. the `ToolClassification` row must be `read-only`, else `notreadonly`;
  3. `Mcp.Proxy.Listed(server, tool, .toolref, .fingerprint)` gives the live fingerprint.

  Arguments come from the row only.
- [ ] `Mcp/Proxy.cls`:
  - Add `Listed(server, tool, Output toolref, Output fingerprint) As %String`. It shares `Run`'s prefix (rows, entry, header, `ListTool`, `Toolref`, fingerprint) through one private method that `Run` also calls (Rule 2).
  - It answers "" or a refusal word (`demo` first on the online demo). It writes no row and no audit entry.
  - `Noted` also notes the refusal word when `Context.IsPoll()`.
- [ ] `Bridge/Context.cls` -- add:
  - `IsPoll()`: Kind `tool` and Provenance `untrusted` in the active context;
  - `SeedMcp(server, toolref, tool, fingerprint)`: one entry through `SetMcpTools`.

  The `NoteReplayRefusal`/`ReplayRefusal` doc says "a replay's or a poll's".
- [ ] `Bridge/Policy/Gate.cls` -- in `Decision`:
  - the `replay` branch applies to Kind `tool` with Provenance `user` only;
  - in a poll (`IsPoll`), a call whose name is not `MCPPROXY` is denied `FAILED`;
  - a proxy call is classified through `FromProxy` with the toolref from the seeded map (`McpToolref`), not a grant. `TakeGrant` is not called, and the untrusted rule (L222) and taint apply.

  Restate the class doc.
- [ ] `Bridge/Adapter/Agent.cls`:
  - Split `ProxyManager`'s build and govern into a public `PollManager(Output manager) As %Status`, which needs no agent. `ProxyManager` calls it, then swaps the manager in (Rule 2).
  - In `Answer`, before L919, a tool request with Provenance `untrusted` goes to `Poll.Run`.
- [ ] `Bridge/Poll.cls` (new) -- `Run(adapter, request, superSession, Output reply) As %Status`:
  1. Parse Input `{"source"}`. A value that is not a Ref is a failure Reply `invalid`.
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
  - **`Admit`.** A `tool` request with Provenance `untrusted` is admitted only when its Input is exactly `{"source": <a Ref>}`. Any other untrusted tool request is refused naming `Provenance`, as today.
  - **`RunnerFor`.** A poll gets the `decide` runner of `RUNNERS`.
  - **No Decision row.** On every path a poll can take (success, a runner failure, the timer, no runner), it answers a bare Reply (the `StillApproved` pattern, L1519-1522) and writes no `Decision` row and no `decision.recorded`.
  - **The answer.** The Reply carries the runner's Text, Tainted, Steps, ToolsRun and FailureText. The timer gives Fallback 1, FallbackReason `timeout` and FailureText `timeout`. Steps go to AgentSteps as for any request.
  - Restate the docs of `Admit`, `RunnerFor` and `ConcludeTool`.
- [ ] `Checks/Process.cls`:
  - Append `Server, Tool, IntervalMinutes` to `ROWCOLUMNS`; `RowOf` adds `server`, `tool` and `interval`.
  - **`Tick`:** one Try block at L256 calls `RunSources(tickAt)`, logging like the queue block. Class-doc bullet.
  - **The appended block** (`POLLTARGET` "Decide", `LOGPOLL*`):
    - **`RunSources(tickAt)`.** It returns at once on the online demo. For each row of `DueOf(tickAt, SOURCEKIND)`:
      1. One UPDATE sets `NextDueAt` = tick + `IntervalMinutes`×60.
      2. If the seam `SourceClass(server, tool)` is not `read-only`, it records a stopped run now (`Record(…, keep 1)`), and `StopNotice` runs on the transition.
      3. Otherwise the seam `SendPoll(request, ref)` sends the request: `SendRequestAsync(POLLTARGET, request, 1, ref)`, with the fields of matrix row 1, Summary "Source poll" and TraceRef from `TraceOf`.
    - **`OnResponse`.** It re-reads the row by Ref (`SourceRow`); a missing row records nothing. The baseline rule: when the row's `LastRunAt` is "" or before its `CreatedAt`, `Reported` starts as `{}`. Then it maps the Reply:
      - "" with Text: `passed`. The first success sets `baseline` 1 with no Item; after that, a new SHA-256 hex hash becomes one Item (`SourceItem`) and joins `seen` (newest 50);
      - `unreachable` gives `REASONSOURCEUNREACHABLE`; `timeout` gives `REASONTIMEOUT`;
      - `denied`, `notreadonly` or `changed` re-reads `SourceClass`. Not read-only means stopped (as in step 2); otherwise `REASONREAD`;
      - anything else gives `REASONREAD`.

      A passed run clears `stopped`. It calls `Record(row, tickAt, now, result, finding, reported, items, 1)`.
    - **`SourceItem(row, text)`:** matrix row 2's fields.
    - **`StopNotice(row, time)`** (seam): calls `Mcp.Ops.SourceStopped`.
- [ ] `Mcp/Ops.cls`:
  - Append the public `SourceStopped(source, tool, server, time) As %Status`. It sends `mcp.sourceStopped` to every `AdminSessions()` session through `Send`, extending `Notify`. A failed read is one warning.
  - **DW-1325.** In `OnSetSource`, after L207: when the trimmed name equals `Checks.Coverage.#ENTRYMAILBOX` in any letter case, answer `reserved_name` with the new `MESSAGESOURCERESERVED`. Add a class-doc bullet and add the word to the outcome list.
- [ ] `Watch/Ops.cls` -- **DW-1328, the one switch.** Add `Parameter REPOINTRESETS = 1`. In `SetSource`, on an existing row, when `REPOINTRESETS` is 1 and the stored `Server`, `Tool` or `Arguments` (`%EXACT`) differ from the new values, set `CreatedAt` = now. Doc: "a source's CreatedAt is when its target was set". Setting the parameter to 0 is the "keep" reading (Veto items).
- [ ] `Checks/Coverage.cls`:
  - **DW-1327.** At L307-314, for a `source` row with `IntervalMinutes` > 0:
    - `EarlierRun` also returns the run's result, reason and finding, and only from a run at or after the row's `CreatedAt`;
    - when `Apart(earlier, toUtc)` ≤ max(`Apart(fromUtc, toUtc)`, `IntervalMinutes`×60 + `MISSEDSECONDS`), the row takes that run through the latest-run rules (L330-351). Otherwise it is stale as today. Every other kind is unchanged.
  - Fix the `RecordRun` doc (L550-551) and the class doc.
- [ ] `Digest/Process.cls` -- **the ~12:45Z ruling.** In `Finish` L517, an entry equal to `Checks.Coverage.#ENTRYMAILBOX` whose row is not a source renders as the new `Parameter MAILBOXINSENTENCE = "the mailbox"`. Nothing else changes (Design Notes list). Restate doc item 3.
- [ ] `Data/BackgroundCheck.cls` and `Digest/Data/CheckRun.cls` (docs only):
  - `Reported` gains the source shape;
  - `CreatedAt` gains the repoint sentence;
  - `Reason` lists `stopped`.
- [ ] Tests. Every matrix row; hermetic fixtures removed after each test; one class per call:
  - **`Test/Bridge/Poll.cls` (new):**
    - `TestAdmitPoll`: accepted; malformed refused; a user tool request unchanged;
    - `TestRunnerForPoll`;
    - `TestPollNoDecisionRow`: success and timer paths, through a Decide shadow;
    - `TestPollOnlyProxy`: a non-proxy call in a poll context is `FAILED`;
    - `TestPollNoGrant`: a read-only proxy call runs with no grant;
    - `TestPollRiskyDenied`: `UNTRUSTED`;
    - `TestPollCallDefault`: the bridge-alone `invalid`.
  - **`Test/Bridge/Gate.cls`:** no edit. Its replay rows (L2584, L2639) must stay green, which proves that the poll branch leaves the replay rule unchanged. The poll's gate rows are in `Test/Bridge/Poll.cls`.
  - **`Test/Bridge/Ext.cls`:** `TestExtensionBases` gains `PollCall`.
  - **`Test/Mcp/SourceRun.cls` (new).** It uses a Checks probe in the `QueueProbe` pattern, with the seams `SendPoll`, `SourceClass`, `StopNotice` and `SendFinding`, and feeds Replies to `OnResponse`:
    - `TestFirstRunBaseline`, `TestNewResult`, `TestSeenBefore` (newest 50), `TestEmptyAnswer`;
    - `TestUnreachable`, `TestTimeout`, `TestOtherFailure`;
    - `TestStoppedBeforeSend`, `TestStoppedAfterDenial`, `TestStoppedNotifiesOnce`, `TestResume`;
    - `TestNextDueAtAtSend`, `TestRemovedMeanwhile`;
    - `TestOnlineDemoNoPoll` (the probe flag and the real `onlineDemo` setting);
    - `TestRepointBaseline`: an update with new arguments, then a passed run, sends no Item.
  - **`Test/Mcp/SourceRunProduction.cls` (new; extends `InProduction`; the mock MCP server).** It drives a real Tick → Decide → TriageAgent → mock → Checks → Intake:
    - `TestPollRuns`: one `MCP` `called` entry; the step "Running zz_lookup on zz"; no `Decision` row for the poll's ItemId; no model request for the poll;
    - `TestNewResultReachesIntake` (the Integration AC): one decide request in the model mock's log and one `ItemDecision` for the Item;
    - `TestNoSecretLeaks` (`LoggedSecret`, `Leaks`): no argument, URL or secret in messages, logs, audit entries or step labels.
  - **`Test/Mcp/SourceSet.cls`:**
    - `TestSetRefusedReservedName`: "Mailbox", " mailbox " and "MAILBOX" are refused, and "My Mailbox" is accepted;
    - `TestRepointMovesCreatedAt`: server, tool and arguments each move it, and an interval-only update keeps it.
  - **`Test/Digest/Coverage.cls`:**
    - `TestSourceLongIntervalCurrent` (30 h);
    - `TestSourceLongIntervalStale` (50 h);
    - `TestSourceEarlierRunBeforeCreatedAt`;
    - `TestStoppedStreak` with real `stopped` rows from `ReasonOf`.
  - **`Test/Digest/Compose.cls`:** `TestCheckedListSourceBare` expects "the mailbox". Add `TestCheckedListMailboxLower` (both variants), which also asserts that the coverage line keeps "Mailbox".

**Acceptance Criteria:**

- Given a due Read-only source, when `Checks` runs it on the Tick, then a `tool` request goes through `Decide` and `call_mcp_tool` runs once with no model: the gate, the step "Running zz_lookup on zz" and one `MCP` `called` entry apply, and no `Decision` row is written. Mutation: the poll's runner skips the gate (an ungoverned manager) → `TestPollRuns` red (no step). Mutation: the poll writes a Decision row → `TestPollNoDecisionRow` red.
- Given a poll's answer not seen before, after the baseline, when it is recorded, then exactly one untrusted Item reaches `Intake` and gets an attention decision. The same answer again sends nothing. Mutation: skip the `seen` check → `TestSeenBefore` red.
- **Integration AC.** Given the real production with a baselined source whose mock answer changes, when the next Tick's poll is recorded, then consumer `Intake` reads the Item that `Checks` sent and produces an `ItemDecision`, with one decide request in the model mock's log. Mutation: `SourceItem` not sent → `TestNewResultReachesIntake` red.
- Given each run, when it is recorded, then the row's `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId` (the Tick's session) and `NextDueAt` (tick + interval, set at the send) are set, one CheckRun row is written, and a `check` event carries `kind` `source`, `lastRunAt`, `result`, `traceHeaderId` and `intervalMinutes`. Mutation: `Record` without keep → `TestNextDueAtAtSend` red.
- Given a source whose tool became Risky, Unclassified or changed, when it is next due, then no `tools/call` reaches the mock, the run is `not_checked` with Reason `stopped`, and every admin gets one `mcp.sourceStopped` (none on the next stopped run). Mutation: notify on every stopped run → `TestStoppedNotifiesOnce` red.
- Given a poll context, when any call other than `call_mcp_tool` is made, then the gate denies it, and a read-only proxy call runs with no grant. Mutation: allow any name in a poll → `TestPollOnlyProxy` red. Mutation: require a grant → `TestPollNoGrant` red.
- Given the online demo, when a Tick runs with a `source` row present, then no poll request is sent and nothing is recorded. Mutation: drop the demo return in `RunSources` → `TestOnlineDemoNoPoll` red.
- **DW-1325.** Given a `SetSourcePoll` named "Mailbox", " mailbox " or "MAILBOX", when McpOps handles it, then it answers `reserved_name` with "That name belongs to the connected mailbox. Choose another name." and writes no row, audit entry or `CheckChanged`. Mutation: compare without the case fold → `TestSetRefusedReservedName` red. Mutation: compare the untrimmed `request.Name` → red.
- **DW-1327.** Given a 24 h digest window and a 48 h source with no run in the window, when coverage is built, then a passed run 30 h before the window's end counts (`passed`), and one 50 h before is stale. Mutation: drop the earlier-run rule → `TestSourceLongIntervalCurrent` red. Mutation: ignore the age limit → `TestSourceLongIntervalStale` red.
- **DW-1328 (CONFIRM).** Given a source updated with a different server, tool or arguments, when it next runs successfully, then that run is a baseline (no Item), and coverage counts only runs since the update. An interval-only update keeps `CreatedAt`. Mutation: `REPOINTRESETS` 0 → `TestRepointMovesCreatedAt` and `TestRepointBaseline` red.
- **The ~12:45Z ruling.** Given a digest covering the Orders production, "Jira" and the mailbox, when it is composed, then it reads "I checked the Orders production, Jira and the mailbox.", and the coverage line still names "Mailbox". Mutation: restore `"the "_entry` for the mailbox → `TestCheckedListMailboxLower` red.

## Spec Change Log

- 2026-11-14 (plan). **Contest Planner, ~09:40Z Nov 14 (BINDING), quoted from `<coordination>/prompts/epic-22-rulings-20261113-1715.md`:**
  - "**DW-1325 (in 22.11):** a source name that equals "Mailbox", ignoring case and surrounding spaces, is REFUSED. Nothing is written, and it gets its own reason code. Text, verbatim: "That name belongs to the connected mailbox. Choose another name." Test it with "Mailbox", " mailbox " and "MAILBOX", plus a mutation."
    - Built into matrix row 8, AC DW-1325, `TestSetRefusedReservedName`, the new outcome `reserved_name` (Veto items, contract) and Public text (APPROVED).
  - "**DW-1326:** the LATEST run counts, per AD-18. […] Failures still come as their own notices, which is why latest is enough."
    - Resolved; no work here. The Always list keeps the latest-run rule, and no "all runs passed" rule is added.
  - "**DW-1327 (in 22.11):** staleness compares against max(window, interval). Tests: a 48 h poll whose last run was 30 h ago is NOT stale in a 24 h digest; a 48 h poll whose last run was 50 h ago IS stale."
    - Built into matrix row 9, AC DW-1327, the two Coverage tests and the AD-18 amendment (Spine updates). The 180 s slack is kept, because AD-18's Part A record already gives a source "the interval plus 180 s".
- 2026-11-14 (plan). **Contest Planner, ~12:45Z Nov 14 (BINDING; in 22.11)**, quoted from the same file:
  - "The digest sentence reads: "I checked the Orders production, Jira and the mailbox." Lowercase "mailbox" ONLY where it runs inside a sentence. Anywhere "Mailbox" is a LABEL (a coverage list heading, a Settings entry), leave it as it is. List each place ENTRYMAILBOX renders and say which one changes (put the list in 22.11's gate). Pin the sentence, with a mutation. DW-1325's reserved-name check stays case-insensitive."
  - This ruling was found in the rulings file and was not in the plan dispatch. Built into matrix row 11, the last AC, `TestCheckedListMailboxLower` and the Design Notes list.
- 2026-11-14 (plan). **DW-1328 is NOT settled.**
  - The ledger entry and the orchestrator's dispatch line say a repointed source keeps its state.
  - The `epics.md` bullet says reset it.
  - The rulings file has no Planner text.

  Planned as the `epics.md` reading, behind the one switch `Watch.Ops.REPOINTRESETS`, and listed as **CONFIRM (DW-1328)** under Veto items.

- 2026-11-14 (lead). **Gate ruled, Contest Planner ~13:20Z Nov 14:** SPLIT approved. Matrix rows 8-11, the DW-1325 (`Mcp/Ops.cls` `OnSetSource`), DW-1327 (`Checks/Coverage.cls`), DW-1328 switch (`Watch/Ops.cls` `REPOINTRESETS`) and mailbox-sentence (`Digest/Process.cls`) tasks, their tests and ACs move to Story 22.13 (`spec-22-13-keep-source-names-staleness-and-repoints-honest-on-the-cover.md`). DW-1328 is RESET (confirmed); 22.11 keeps the baseline rule (first good run since `CreatedAt`) and `TestRepointBaseline`. Task 0 gains the STOP: due polls adding more than 10 s to the median triage decision time, or any triage decision missing its timeout, go to the Planner. `reserved_name` in 21.5 is lane C's cross-lane bullet. Status reset to `draft` for a re-plan of the poll run after 22.13 merges.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-2 and AD-31: the bridge names no host class; `PollCall` is an extension method.
- AD-5: state on rows.
- AD-6: a `tool` request is "one governed tool call, either an approved call's replay or, from step 4, a source poll", with no model.
- AD-9: steps from the step audit.
- AD-10: one gate, the untrusted rule, the fingerprint at call time.
- AD-12: `check` events and `/v1/state`.
- AD-17: one audit writer.
- AD-18: `Checks` runs due rows and records them; the source row; coverage; CheckRun. Amended for DW-1327.
- AD-21: "Source polls (step 4) call `call_mcp_tool` through a `tool` request to `Decide`"; no MCP on the demo.
- AD-25: the demo.
- AD-28: the all-clear only from `Render`; the not-checked lead.
- AD-29: lanes.
- AD-30: untrusted Items go to `Intake`.
- AD-32: notices are catalog keys.
- AD-33: `Checks` is the run-field writer and the one `check` publisher.

No AC contradicts an AD's Rule except DW-1327, which amends AD-18's staleness rule for sources by the Planner's ruling. No NFR trips Rule 5. One residual risk: TriageAgent (PoolSize 1) runs each poll, so a slow server holds triage decisions for up to about 28 s, plus 22.9's about 31 s hang residual, per due source. This is inference and Task 0 measures it. 22.5's plan accepted it (ChatAgent would queue polls behind users' turns).

**Carried from 22.5's "Moved to 22.11", re-checked against `aa94694a`:**
- The earlier plan's `Gate.ClassifyMcp` is `FromMcp`/`FromProxy`.
- Proxy's demo sentence lives in `Tools/McpCall.MCPDEMO`.
- `ProxyManager` needs the agent, so `PollManager` is split out of it.
- `Test/Mcp/Mock` already has a settable answer (`Call(port, "text", value)`), so no Mock change is needed.
- `Record` writes CheckRun through the table trigger.
- The Request has `OwnerRef`, not SessionRef.

**Decided in-stage (kept from 22.5's gate-reviewed plan):**
1. **A result is the tool's whole text answer**, de-duplicated by SHA-256 against the newest 50.
2. **The first successful run is a baseline.** This settles the epic context's open question; 22.5's matrix row 1 already says so. It is also the first success since `CreatedAt` (DW-1328).
3. **The poll runs on TriageAgent.**
4. **The map is seeded from a live listing** (`PollCall` → `Proxy.Listed`), so 22.8 clears a changed tool.
5. **The request carries the Ref only.**
6. **The run is async, and `NextDueAt` advances at the send.**
7. **A poll gets no `Decision` row.**
8. **A stopped source keeps recording** and resumes by itself.

**Decided in-stage (new):**
9. An empty answer is `passed` and never an Item.
10. The mailbox in a sentence is matched as `entry = ENTRYMAILBOX` on a non-source row, the same test `Verdict` L607 already uses, so no `kind` value is added and AD-18's `kind` sentence stands.
11. A `source` row named "Mailbox" written before this story is left alone. 22.5 is unreleased, so no install has one.
12. The plan stage started with one uncommitted line in the tree: the lead's own `stage_spawned` write-ahead row in `cycle-log-epic-22.md`. It was treated as bookkeeping, not a dirty tree.

**ENTRYMAILBOX's renderings (for the gate; the ~12:45Z ruling):**
1. `digest.checked`/`digest.checkedQuiet` "I checked {checked}": a sentence. **Changes** to "the mailbox".
2. `checks.notEverything*` "Not everything: {whatFailed}.": the entries as a list after a colon, where productions also stand bare ("Orders production"). **Unchanged** ("Mailbox"); the gate may rule it a sentence.
3. The coverage lines and the digest lead (`digest.passed`, `digest.notChecked*` {entry}): list labels. **Unchanged.**
4. The check rows on the page and in Telegram (`Render` rows' `entry`): labels. **Unchanged.**
5. `Verdict`'s mailbox-only test (L607) and the stored `Named`: logic and data. **Unchanged.**

**Extend, don't copy (Rule 2):**
- `PollManager` is split out of `ProxyManager`, and `Proxy.Listed` shares `Run`'s prefix.
- `Poll.Run` follows `Replay.Execute`'s shape but is its own class, because the approval steps (`StartExecution`, the grant, the lock) must never apply to a poll.
- `RunSources` follows `RunQueues`, and `SourceDue` follows `QueueDue`.
- `OnResponse` reuses `Record`, `SendOwn` and `Announce`.
- `SourceItem` follows `FindingItem`/`Beat`.
- `SourceStopped` extends `Notify`/`Send`.
- The reserved-name check extends `OnSetSource`'s name step.
- `EarlierRun` is extended in place.

**Integration ACs (Rule 1):**
- The new surfaces are `Bridge.Poll`, `PollCall`, `Proxy.Listed`, `Context.IsPoll`/`SeedMcp`, `Agent.PollManager`, `Checks.RunSources`/`OnResponse`, `Mcp.Ops.SourceStopped` and the outcome `reserved_name`.
- Consumers in this story:
  - `Intake` produces an `ItemDecision` from a poll Item (`TestNewResultReachesIntake`, real production);
  - `Checks.Coverage.Build` reads the CheckRun rows the run wrote (`TestStoppedStreak`, real `stopped` rows);
  - `Decide` → TriageAgent → `Bridge.Poll` (`TestPollRuns`).

**Consumes:**
- 22.5: the source rows, `REASON*`, the coverage source branch.
- 22.3: `call_mcp_tool`, `Proxy`, `Client.ListTool`, the `MCP` audit.
- 22.4: `ProxyManager`, `NoteReplayRefusal`, `Attach.Toolref`.
- 22.8: the extension's classification and `ClearChanged`.
- 22.9: the bounds.
- Epic 30: the `tool` request path in `Decide`.
- AD-30: `Intake`.
- 35.1: `mcp.sourceStopped` and `digest.notCheckedStopped`.

**Consumed-by:**
- 21.5 (Lane B): it maps `reserved_name` (Veto 1) and renders the source's run from the `check` events.
- 22.12: the docs (the baseline, whole answers, the stop and the reserved name).

**Story 21.5 and edit order.** 21.5's spec (lane C, `ready-for-dev`) edits `Web/McpSettings.cls`, `Core/SettingsOps.cls` and `web/**` only, so it shares no file with this story. The shared contract is McpOps' outcome list: 21.5 answers any unknown word with 500 `server_error`. Until a `DW-n` bullet on 21.5 maps `reserved_name` to 400 `bad_source` `{name}` with McpOps' message, the Settings page would show a server error for this refusal (Veto 1).

**Contended edits (for the lead):**
- `Checks/Process.cls`: one Try block in `Tick` and an appended block (Epic 23/36 plain union).
- `Mcp/Ops.cls`: one inserted check in `OnSetSource`, plus appended methods and parameters.
- `Bridge/Process/Decide.cls`, `Adapter/Agent.cls` and `Policy/Gate.cls`: non-append branches.
- `Checks/Coverage.cls`: `WatchRow` L307-314 and `EarlierRun`.
- `Digest/Process.cls`: L517.

**Ledger inbox (Rule 17).** `LEDGER slice 22-11-run-source-polls-through-the-governed-proxy` holds:
- DW-1325 (routed; ruled) and DW-1327 (routed; ruled): both addressed here;
- DW-1328 (routed): planned behind the switch, **CONFIRM**.

DW-1326 is resolved (latest run).

**Residual for the lead to route.** `Data.Precedent.KeyFor` (Lane B) has no key form for a poll Item, so precedents do not learn from source Items (AD-21 names "the source for … polls").

**Spine updates for the lead (Rule 20; S-labels left to the lead, since S20 is taken):**
1. **AD-18, the digest bullet's `stale` clause.** The amended text:

   > "`stale` when its latest run is before the span, except that a source takes its latest run at or after its `CreatedAt` as current when that run is within max(the window, its interval plus 180 s) of the window's end [AMENDED 2026-11-14, Story 22.11, Contest Planner ruling ~09:40Z Nov 14 (DW-1327); it read "`stale` when its latest run is before the span"]"

   In the Part A record, "it is stale after the interval plus 180 s" gains "(DW-1327)".
2. **AD-18, a record "Source polls, Part B (Story 22.11)":**
   - async `tool` requests with the Ref only, and `NextDueAt` set at the send;
   - whole-answer results with SHA-256 hashes (newest 50), and the first success since `CreatedAt` as a baseline;
   - untrusted Items (channel `system`, Subject the source's name);
   - a stop (a classification other than Read-only, before the send or after a denial) recorded as Reason `stopped`, with one `mcp.sourceStopped` per transition, and resuming by itself;
   - never on the online demo.

   If DW-1328 is CONFIRMED as reset: "a repoint (server, tool or arguments) moves `CreatedAt` to the repoint, so coverage and the baseline start afresh; CheckRun rows are kept".
3. **AD-6/AD-10, a record.** A `tool` request with Provenance `untrusted` is a source poll:
   - its Input is `{"source": Ref}`, and it runs on the `decide` runner;
   - it makes one `call_mcp_tool` on a standalone governed proxy-only manager, with the map seeded by `PollCall`;
   - the gate admits only the proxy, with no grant, under the untrusted rule;
   - it writes no `Decision` row or event, and the Reply carries the answer text and one reason word.
4. **AD-31.** `McpServersClass.PollCall`, default `invalid`.

**Split recommendation (oversized, multiple goals).** About 17 source files.
- Split line: **22.11** keeps the run (the bridge, `Checks`, `SourceStopped`, the Checks half of DW-1328).
- A small Lane A story takes the coverage and naming items: DW-1325 (`Mcp/Ops.cls`), DW-1327 (`Checks/Coverage.cls`), the `REPOINTRESETS` switch (`Watch/Ops.cls`) and the mailbox sentence (`Digest/Process.cls`). These need no bridge change.

Not split here.

## Veto items

**Approved for 22.11 at 22.5's gate (veto 1-10, kept; tags as ruled):**
- 2: CheckRun Reason `stopped` (written here).
- 3: outward actions, the seed listing plus the proxy's requests, every 5 to 1,440 minutes, bounded 2/2/2/20 s. Online demo: none.
- 4: the security posture (untrusted, never held; the answer stored in the Reply and the Item; arguments only in the row). Online demo: unchanged.
- 6: `mcp.sourceStopped` to every admin session. Online demo: never sent.
- 7: bridge request semantics and the `PollCall` extension (22.5 labelled them S19/S20; the spine has since used S20, so the lead relabels). Online demo: no change.

**NEW:**
1. **NEW reason code (contract): `reserved_name`**, McpOps' answer to `SetSourcePoll` for the name "Mailbox" (DW-1325, ruled).
   - Readers: 21.5's `Web.McpSettings` answer table (to map to 400 `bad_source` `{name}`; it needs a `DW-n` bullet on 21.5, another lane's planned story, so it goes through the orchestrator), `Test.Mcp.SourceSet`, and 22.12's docs.
   - Online demo: never reached (`not_allowed` comes first).
2. **CONFIRM (DW-1328): a repointed source.**
   - Reading A (`epics.md`, planned; `REPOINTRESETS` 1): an update that changes server, tool or arguments moves the row's `CreatedAt` to now.
     - The next success is a baseline, and `Reported` (seen, baseline, stopped) starts afresh.
     - Coverage counts only runs since the repoint.
     - The CheckRun rows are kept and purged by AD-27 as usual. They are not deleted, because they record what ran, and deleting them would be a data change.
     - A same-target update keeps everything.
     - Stored meaning: a source's `CreatedAt` becomes "when its target was set". Checks stays the only writer of run fields (AD-33).
   - Reading B (the ledger and dispatch line; `REPOINTRESETS` 0): the repointed source keeps its seen hashes, baseline and history. Its first poll compares the new target's answers with the old target's, so every current result of the new target arrives as a new Item, and the old target's runs keep counting in coverage.
   - **Recommendation: A.** It avoids an Item flood and a coverage entry made from another target's runs.
   - Online demo: no source rows.
3. **Spine amendment (AD-18) for DW-1327:** ruled, recorded under Spine updates. Online demo: no source rows.

No new route, privilege, role, grant, resource, table, column, retention, production item or web dependency.

## Public text

**APPROVED (Planner ~09:40Z Nov 14, DW-1325), verbatim:**

| File / parameter | Where it shows | Text |
| --- | --- | --- |
| `Mcp/Ops.cls` `MESSAGESOURCERESERVED` | the Settings answer (21.5) for `reserved_name` | "That name belongs to the connected mailbox. Choose another name." |

**APPROVED (Planner ~12:45Z Nov 14):** `Digest/Process.cls` `MAILBOXINSENTENCE` "the mailbox", in "I checked the Orders production, Jira and the mailbox."

**Existing, reused:**
- **From 35.1 (accepted):** `mcp.sourceStopped` (the stop notice, "The source {source} stopped polling at {time}, because its tool {tool} on {server} is no longer Read-only. Your digest lists it as not checked.") and `digest.notCheckedStopped`.
- **From 22.5 (approved):** `REASONSOURCEUNREACHABLE`, `REASONNOTREADONLY`.
- **Already in use:** `REASONTIMEOUT`, `REASONREAD`, `digest.notCheckedStale`, `digest.notCheckedUnreachable`; 22.3's step label "Running {tool} on {server}" and its `MCP*` refusals.
- **Not product text:** a poll Item's Subject (the admin's source name) and Text (the tool's answer).

**NEW:** none.

**Findability:** none here; there is no UI until 21.5, and 22.12 documents the source.

## Verification

Each `ci/iris.sh` and `ci/warm.sh` call carries the lane's variables:
`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s11iw`; fresh runs use `OCUTALON_RUN_TAG=e22s11i`.
- Run one test class per foreground call, with `timeout: 600000`. Each must finish inside about 150 s.
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
  - `OcuTalon.Test.Mcp.SourceSet`
  - `OcuTalon.Test.Mcp.Proxy`
  - `OcuTalon.Test.Digest.Coverage`
  - `OcuTalon.Test.Digest.Compose`
- (once) Warm, each `ci/iris.sh class <Class>` -- expected: passed:
  - `OcuTalon.Test.Bridge.Runner`
  - `OcuTalon.Test.Bridge.Approval`
  - `OcuTalon.Test.Mcp.Approval`
  - `OcuTalon.Test.Mcp.Attach`
  - `OcuTalon.Test.Mcp.Ops`
  - `OcuTalon.Test.Mcp.SourceSetProduction`
  - `OcuTalon.Test.Checks.Queues`
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Digest.AllClear`
  - `OcuTalon.Test.Digest.TelegramText`
  - `OcuTalon.Test.Watch.Ops`
  - `OcuTalon.Test.Msg.Catalog`
- (once) `bash docker/tests/test-boundaries.sh` (the bridge names no OcuTalon class), `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-ci-config.sh`, one per call -- expected: exit 0.
- (once) `OCUTALON_RUN_TAG=e22s11iw ci/warm.sh down` -- also after a failure.
- (once) Fresh: `OCUTALON_RUN_TAG=e22s11i ci/iris.sh class OcuTalon.Test.Mcp.SourceRunProduction`, then `OCUTALON_RUN_TAG=e22s11i ci/iris.sh teardown` -- expected: passed on a fresh stack, then torn down.

**CI:** no new unit, group or area. The new `Test.Mcp.*` classes join `shards-2` and `Test.Bridge.Poll` joins `shards-9`, adding about 60-120 s (inference).

**Shared surfaces:**
- `Decide.Admit`'s tool rule (`Test.Bridge.Decide`);
- the gate's replay rule (`Test.Bridge.Gate`, `Test.Mcp.Approval`);
- `Ext.McpServers`' methods (`Test.Bridge.Ext`);
- `Proxy`'s shared prefix (`Test.Mcp.Proxy`);
- `ROWCOLUMNS` and `RowOf` (`Test.Checks.*`);
- McpOps' outcome list;
- the `CheckRun` Reason values;
- coverage of a source with no run in the window (`Test.Digest.Coverage` `TestStale`);
- the "I checked" sentence (`Test.Digest.Compose`, `Test.Digest.EvalCase`);
- `Ownership.AdminSessions` notices.

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
| Drop the demo return in `RunSources` | `TestOnlineDemoNoPoll` |
| Reserved-name check without the case fold, or on the untrimmed name | `TestSetRefusedReservedName` |
| Drop the DW-1327 earlier-run rule | `TestSourceLongIntervalCurrent` |
| Ignore the age limit | `TestSourceLongIntervalStale` |
| `REPOINTRESETS` 0 | `TestRepointMovesCreatedAt`, `TestRepointBaseline` |
| `"the "_entry` for the mailbox | `TestCheckedListMailboxLower` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning); nothing implemented. Open for the lead: CONFIRM (DW-1328) and the NEW reason code `reserved_name` (Veto items); the AD-18/AD-6/AD-10/AD-31 spine records (Design Notes); the ENTRYMAILBOX list for the gate; and a `DW-n` bullet on 21.5 for `reserved_name`.
