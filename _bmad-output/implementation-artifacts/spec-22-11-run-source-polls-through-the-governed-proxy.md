---
title: 'Story 22.11: Run source polls through the governed proxy'
type: 'feature'
created: '2026-11-14'
status: 'done'
baseline_revision: '71f69aae4af59a4a5a3343107b9eaab190303262'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-5-poll-a-read-only-mcp-tool-as-a-source.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-13-keep-source-names-staleness-and-repoints-honest-on-the-cover.md'
warnings: ['oversized']
deferred:
  - summary: >-
      A run recorded in the same second as the repoint that moves CreatedAt keeps the old history (the start-afresh rule is "LastRunAt before CreatedAt", strictly).
    evidence: |-
      StateOf reads Reported unless CreatedAt follows LastRunAt; with LastRunAt equal to CreatedAt (second resolution) the earlier target's seen hashes stay for the next run, which could send one extra Item or hide one.
      Tests age LastRunAt before a repoint (TestRepointBaseline). The window is one second per repoint.
    location: >-
      src/ocutalon/cls/OcuTalon/Checks/Process.cls StateOf
    severity: low
  - summary: >-
      Option (a) caps the whole install at one poll per Tick, so N sources need N Ticks to be polled once, and more sources than their interval in minutes fall behind interval + 180 s and read stale.
    evidence: |-
      RunSources reads the in-flight state once and the first poll sent sets it for the rest of the Tick, whatever the source's answer time; the in-flight mark is install-wide, so one session's silent source also delays every other session's sources.
      The pre-ruled check 2 (3 silent sources) holds; a fleet larger than the shortest interval (5 minutes) is not covered. Oldest-NextDueAt-first ordering keeps the waiting sources from starving. The remedies are the Planner's options (b) a dedicated poll runner or (c) TriageAgent PoolSize 2, both of which need a ruling.
    location: >-
      src/ocutalon/cls/OcuTalon/Checks/Process.cls RunSources, PollInFlight
    severity: medium (escalated to the Contest Planner)
  - summary: >-
      A poll's answer is cut at the tool-result room (the step's token budget) like any tool result, so a change beyond the cut that leaves the total length alone is not seen.
    evidence: |-
      Tools.McpCall.CallMcpTool passes ..Room() - used to Proxy.Call, and the answer carries the cut note with the shown and total counts; Poll.Run takes the value as it comes, and SHA-256 covers what was shown. A change in the total length changes the note and so the hash.
      Not measured against a tool whose answer exceeds the room.
    location: >-
      src/ocutalon/cls/OcuTalon/Tools/McpCall.cls CallMcpTool, src/bridge/cls/OcuTalon/Bridge/Poll.cls Run
    severity: medium (unverified)
  - summary: >-
      Proxy.Listed's online-demo word has no test of its own.
    evidence: |-
      The demo is held back at Checks.RunSources and by the proxy's MCPDEMO refusal on call_mcp_tool; a direct Listed call on the demo is not asserted.
    location: >-
      src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls Listed
    severity: low
  - summary: >-
      DW-1346's allowance (interval + max(180 s, 60 s x the sources that are not stopped)) does not cover three sources whose polls each run to Decide's 60 s timer: the third waits about 240 s against 180 s.
    evidence: |-
      With one poll in flight at a time, a source behind another waits that poll's time plus the alignment to the next Tick, up to about 120 s for each source ahead of it (a poll answered inside a Tick lets the next go at the next Tick; one that runs to the timer misses it), so 3 such sources read stale or missed for waiting alone. The ruling fixes 60 s per source, and for 3 sources it equals the old 180 s, so no test of 3 can tell the two apart; TestSlowQueueOfThreeNotStale uses 5 sources and the ruling's numbers.
      A rule of 120 s per source (max(180 s, 120 s x sources)) would cover it; that changes a ruled number, so it is the Planner's.
    location: >-
      src/ocutalon/cls/OcuTalon/Checks/Coverage.cls SourceSlack, QUEUESECONDS
    severity: >-
      medium (RESOLVED 2026-11-14 by the Contest Planner's ruling ~23:00Z, option (1), QUEUESECONDS 120; see the Spec Change Log and the ledger line DW-1346)
  - summary: >-
      Test.Digest.Coverage's source boundary tests (TestSourceLongIntervalStale, three sources) hold only while the install has at most three sources that are not stopped.
    evidence: |-
      PollingSources counts every non-stopped source row of the install, so a leftover source row on the stack widens the allowance of the boundary assertions (one second past interval + 180 s). They are Lane B tests this story may not edit; the fresh stack and the stories' own clean-up leave none, and the warm stack ran them green.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Digest/Coverage.cls TestSourceLongIntervalStale
    severity: low
  - summary: >-
      A lost poll answer holds the in-flight mark for INFLIGHTSECONDS (150 s), which delays each later source by about 180 s, more than the 120 s per source that the allowance gives; a Decide timer raised above 60 s (up to MAXTIMER, 110 s) does the same.
    evidence: |-
      Edge Case Hunter (code review of the DW-1346 ruled pass): the allowance is sized for a poll that runs to the default 60 s timer plus a Tick (about 120 s per source). The in-flight mark is option (a)'s, and the timer setting is Decide's; neither was changed here and the ruling fixed QUEUESECONDS at 120. Coverage's class doc, AD-18 and the evidence now say the allowance covers the default timer only.
    location: >-
      src/ocutalon/cls/OcuTalon/Checks/Coverage.cls QUEUESECONDS; src/ocutalon/cls/OcuTalon/Checks/Process.cls INFLIGHTSECONDS
    severity: low
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

     **Pre-ruled (Contest Planner ~15:10Z Nov 14, binding):** if either limit is crossed in any mode, do NOT halt yet. Apply option **(a)** automatically: at most ONE poll in flight (`RunSources` sends no new poll while one is outstanding, keyed on the row's in-flight state on the row, AD-5; the other due sources wait for the next Tick, their `NextDueAt` left unchanged). Then MEASURE AGAIN in all four modes. (a) passes only if BOTH hold:
     1. the STOP criteria pass: the median adds no more than 10 s, AND no triage decision misses its timeout;
     2. with 3 silent sources due at once, every due source still polls within its interval + 180 s, so no source is marked stale only because of queuing. Pin this with a test (`TestOneInFlightNoQueueStale` in `Test/Mcp/SourceRun.cls`, with a mutation: drop the in-flight check, or let a queued source wait past interval + 180 s, turns it red).

     If (a) fails either check, HALT `blocked` with `## Clarification Needed` beginning `PLANNER REPORT:` and the before and after numbers per mode. Options (b) (a dedicated poll runner) and (c) (TriageAgent PoolSize 2) need the Planner's ruling and are never taken here. Either way, record the before (and, if (a) was applied, after) numbers per mode in the evidence file and in the stage's final report: the lead reports them in PART READY.
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

- [x] **Rework iteration 1 (implement; scope is closed: exactly the two items below; nothing in Lane B, `web/**`, `README.md`, `GUIDE.md`, `docs/**`, `release/**`, `.github/**`, `Tools/McpCall.cls`; never edit, skip or weaken an existing Epic 21 or Lane B test; no new public text; Task 0 is not re-measured and `evidence/22-11-task0-poll.md` keeps its numbers).**
  1. **The eight open `- [ ] [Review][Patch]` items under `### Review Findings` (five MED, three LOW; read each in full).** Close each in the code, tests or docs it names, tick its `[ ]` to `[x]` and append one line to it saying how it was closed. Each MED's new or changed test gets a demonstrated mutation (Rule 19: apply it alone, observe the named test red, revert byte-identically, `git status --short` and `git diff --stat` as before) recorded as a `mutation:` line under `## Verification` and a row of its table. Rule 2: for the near-copied helpers extend or call the existing ones (`Test/Bridge/Gate.cls`, `Test/Bridge/Decide.cls`, `Test/Mcp/SourceRunProduction.cls` `Poll()`), or state the reason in `## Design Notes`. The double warning on a failed admins read is closed in `Checks/Process.cls` `StopNotice` (`Mcp.Ops.Notify`'s warning is the one). Doc fixes replace the wrong claim, never narrate (Rule 14). Do not change option (a) itself, and do not touch the `inflight` member (DW-1350 is RATIFIED). DW-1347 is not this story's work.
  2. **DW-1346 (Contest Planner ~20:40Z Nov 14, binding; quoted in the Spec Change Log).** One poll per Tick STAYS. The coverage allowance of a source becomes **interval + max(180 s, 60 s x the number of sources due together)**, so a source that only waits in the queue is never marked stale or missed. Apply it wherever `Checks/Coverage.cls` computes a source's allowance: the gap check in `WatchRow` (`allowed`) and 22.13's carried-run `Current` (both use `IntervalMinutes` x 60 + `MISSEDSECONDS` today); update the class doc lines that state the allowance. Decide "the number of sources due together" from the code: option (a)'s cap is install-wide, so the count of `source` rows that are not stopped (the `Reported.stopped` member) is acceptable; compute it once per `Build`, keep it a read in Coverage with no new column, and record the choice and why under `## Design Notes` (Decided in-stage). Test (`Test/Mcp/SourceRun.cls`, with the probe seams already there): 3 slow sources due at once, each poll held near Decide's 60 s timer (the code review estimated about 240 s for the third), none is marked stale or missed by `Checks.Coverage.Build`; update `TestOneInFlightNoQueueStale` if it shares the allowance. Mutation: revert to interval + 180 s in Coverage (both places) -> that test red. Do not edit the AD-18 spine records: the stage agent updates them after this pass.

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
- **Rework (DW-1346).** Given 3 sources due together whose polls each take about Decide's 60 s timer, when the digest is built, then none is marked stale or missed (a source's allowance is interval + max(180 s, 60 s x the number of sources due together)). Mutation: revert the allowance to interval + 180 s -> the DW-1346 test red.

### Review Findings

Code review 2026-11-14 (Tier 1, full mode; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all completed; diff `149cf20a..2e2b6ec0` over `src` and the evidence). Each line: severity, fix-risk, footprint, spec-status. Open patch items go to the one bounded MED iteration (first review); the quota hold at 20:00Z left no time to run a warm stack and demonstrate their mutations in this pass.

- [x] [Review][Patch] [med; fix-risk low; in-story; clear] The admin notice `mcp.sourceStopped` is never asserted through the real `NoticesIn` path: `TestSourceStoppedNotice` and `TestStopThroughTheRealSeams` replace `Mcp.Ops.Notice` with `OpsProbe`, and `TestStopThenResume` (real production) checks the stopped run but not the notice. Add a production assertion that each admin session receives one `mcp.sourceStopped` (none on the next stopped run), with a mutation line. Graded MED, not HIGH: Rule 3's real-runtime test of the deliverable exists (`SourceRunProduction`, Intake's `ItemDecision`); the unverified hop is the shared `Notice` -> `NoticesIn.Send` line [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRunProduction.cls:215] (acceptance-auditor) -- Closed (rework 1): `TestStopThenResume` makes the fixture session an admin at its sign-in and asserts, on the real production, one `mcp.sourceStopped` (the four slots) in the NoticesIn to Notify messages of its trace for the stopped run and none for the next stopped run; mutations in `## Verification`.
- [x] [Review][Patch] [med; fix-risk low; in-story; clear] `TestOneInFlightNoQueueStale` cannot fail on its queue-wait half: `waited` is `At(3) - At(0)` (two test constants, 180) against `MISSEDSECONDS` (180), and the stale mark is computed from `INFLIGHTSECONDS` itself, so `INFLIGHTSECONDS` 3600 stays green. Use a fixed mark age (e.g. 160 s, plus one just under the limit) and take the wait from the probe's `Polls()` keys; record the second mutation ("a queued source waits past interval + 180 s") [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls:524] (verification-gap+acceptance-auditor) -- Closed (rework 1): marks of a fixed age (140 s still holds, 160 s holds nothing) pin `INFLIGHTSECONDS`, and the `INFLIGHTSECONDS` 3600 mutation turns the test red (`## Verification`). The wait read from the `Polls()` keys was dropped: the keys hold the real send time, not the Tick's, so `waited <= allowed` could not fail (the review of rework 1); the allowance itself is pinned by `TestSlowQueueOfThreeNotStale`.
- [x] [Review][Patch] [med; fix-risk low; in-story; clear] AC 4's `check` event is not asserted from a published event: `TestFirstRunBaseline` builds `Live.Payload.Check.FromRow` from the stored row (probe Kind `zzsources`, no `lastRunAt`), and no production test reads the `check` event of a source run (`kind` `source`, `lastRunAt`, `result`, `traceHeaderId`, `intervalMinutes`) [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls:106] (verification-gap+acceptance-auditor) -- Closed (rework 1): `TestPollRuns` reads the published `check` event of the run (kind `source`, `passed`, `intervalMinutes`, `lastRunAt`, the Tick's `traceHeaderId`); mutation in `## Verification`.
- [x] [Review][Patch] [med; fix-risk low; in-story; clear] Rule 19: `TestOnlineDemoNoPollInProduction` sends a Tick, waits a fixed `Hang 6`, then asserts nothing happened, with no signal that Checks handled the Tick; wait on the Tick header's completion before asserting [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRunProduction.cls:184] (verification-gap) -- Closed (rework 1): the fixed `Hang 6` is replaced by `Settled`, which waits for Checks to complete the Tick's own header before the assertions; mutation in `## Verification`.
- [x] [Review][Patch] [med; fix-risk low; in-story; clear] Rule 2 near-copies with no stated reason: `Test/Bridge/Poll.cls` `Sentence`, `SinkTypes` and `Rows` repeat `Test/Bridge/Gate.cls` `Sentence` and `Test/Bridge/Decide.cls` `SinkTypes`/`Rows`; in `Test/Mcp/SourceRunProduction.cls`, `Tick()` repeats the Tick-sending body of `Poll()`. Reuse the existing helpers or state the reason [src/ocutalon/cls/OcuTalon/Test/Bridge/Poll.cls] (acceptance-auditor) -- Closed (rework 1): `SourceRunProduction` `Poll()` calls `Tick()`; `Test.Bridge.Poll` takes `Rows` from `RunnerFixture.DecisionRowCount` and `SinkTypes`/`SinkCalls` from new `ProbeSink.Types`/`Calls`; `Sentence` stays, with the reason in `## Design Notes`; mutation in `## Verification`.
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] A failed read of the admins is two warnings on the Checks path (`Mcp.Ops.Notify`'s and `Checks.StopNotice`'s LOGPOLL line), against the task's "one warning"; Fix Pack [src/ocutalon/cls/OcuTalon/Checks/Process.cls StopNotice] (acceptance-auditor) -- Closed (rework 1): `Checks.Process` `StopNotice` no longer logs (`Mcp.Ops.Notify`'s warning is the one); `TestStopNoticeFailureIsOneWarning`, mutation in `## Verification`.
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] Docs not brought up to date: `Decide` `OnRequest` and the `OnResponse` completion-key doc omit the poll branches; `Mcp.Ops` `Notify` doc omits `events("stopped")`; `PollAnswer`'s doc omits `DurationMs`; `POLLREASONS`' `notfound` ("no classification") differs from `Proxy.Listed`'s use (server not registered); Fix Pack [src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls] (blind-hunter) -- Closed (rework 1): `Decide` `OnRequest` and `OnResponse` docs state the poll branches, `Mcp.Ops` `Notify` doc names `events("stopped")`, `PollAnswer`'s doc names `DurationMs`, and `POLLREASONS`' `notfound` doc says no classification row or an unregistered server.
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] `TestPollRuns`' class doc claims one CheckRun row but the test does not assert it; Fix Pack [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRunProduction.cls:76] (acceptance-auditor) -- Closed (rework 1): `TestPollRuns` asserts one CheckRun row with no Reason.
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] "A source that has never run first" was false: the key `nextDueAt_"|"_position` sorts an empty `NextDueAt` after every timestamp (only fixtures make one; `Watch.Ops.SetSource` always sets it). Patched the `RunSources` doc and the AD-18 record to the code's order (doc only) [src/ocutalon/cls/OcuTalon/Checks/Process.cls:1037] (all four layers)
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] The `Poll` class doc said "Tainted is 1 when the call ran"; the code sets it only when the tool's text comes back (a refusal returns none, and no poll consumer reads it). Doc patched to the code [src/bridge/cls/OcuTalon/Bridge/Poll.cls:15] (blind-hunter+edge-case-hunter+acceptance-auditor)
- [x] [Review][Patch] [med; fix-risk low; in-story; clear] The evidence's "a silent poll holds the mark at most about 26 s" is the measured one-page mock, not a code bound: per-request 2 s limits (up to 10 `tools/list` pages) and S11 trickling let a poll run to Decide's 60 s timer, so 3 such sources could take about 240 s (inference). Code-review note added to the evidence; the residual joins DW-1346 [_bmad-output/implementation-artifacts/evidence/22-11-task0-poll.md:73] (verification-gap)
- [x] [Review][Defer] [med; fix-risk high; out-of-footprint; clear] One poll per Tick for the whole install (known item 2) [src/ocutalon/cls/OcuTalon/Checks/Process.cls RunSources] -- deferred: DW-1346, decision-pending (Planner: options (b)/(c), or a send from OnResponse) (blind-hunter)
- [x] [Review][Defer] [med; fix-risk med; out-of-footprint; clear] A poll's answer is cut at the tool-result room (known item 3; the Item and hash hold the cut note) [src/bridge/cls/OcuTalon/Bridge/Poll.cls] -- deferred: DW-1347, escalated (the fix is in `Tools/McpCall.cls`) (edge-case-hunter)
- [x] [Review][Defer] [med; fix-risk low; in-story; spec-bound] The `inflight` member of `Reported` is beyond the approved `{seen, baseline, stopped}` shape (known item 1). Reviewer's judgment: it follows the pre-ruling's letter ("the row's in-flight state on the row", no column), holds a time only and exists only while a poll is outstanding, so no rework; it is a stored-format change for the Planner to ratify [src/ocutalon/cls/OcuTalon/Checks/Process.cls MarkInFlight] -- deferred: DW-1350, decision-pending (human=Planner)
- [x] [Review][Defer] [low; fix-risk low; in-story; clear] A run recorded in the same second as a repoint keeps the old history [src/ocutalon/cls/OcuTalon/Checks/Process.cls StateOf] -- deferred: DW-1348, wontfix-accepted (edge-case-hunter; the implement stage's deferral)
- [x] [Review][Defer] [low; fix-risk low; in-story; clear] `Proxy.Listed`'s demo word has no test of its own [src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls Listed] -- deferred: DW-1349, wontfix-accepted (the implement stage's deferral)

**Checked and holding.** The skip after `OnError`: `irislib/Ens/BusinessProcess.cls` calls `OnError` (L339) and then, when it answers OK, `OnResponse` (L435) for the same key in the same in-memory instance (`%Save` between them keeps transient properties), so the transient `ErroredKey` makes the second call a no-op and a failed poll records once; `OnError` returns an error only for keys that are not a poll's, where `ErroredKey` is not set. The `OPSCLASS`/`RealSeams` seams: `OPSCLASS` is a class parameter that only the probe overrides, `$ClassMethod` with it calls `SourceStopped(source, tool, server, time)` in the order Ops declares, and `RealSeams` runs the parent's `SourceClass` and `StopNotice` through `##super`, so `TestStopThroughTheRealSeams` exercises the production code up to `Mcp.Ops.Notice`. The ADs: AD-6, AD-10, AD-18, AD-21, AD-30, AD-31 and AD-33 hold (no Rule 6 mismatch); the Integration AC is real-production (`TestNewResultReachesIntake`). Task 0's numbers match the code (`MAXTIMER` 110, `INFLIGHTSECONDS` 150; 12774.5 - 28 and 5734.5 - 28). Rule 20: the four spine records were applied by this review.

**Rejected:**
- (blind) A `changed` stop never resolves until the next attach or turn: spec-bound, `by-design` (Design Notes 11: the next attach clears the row, 22.8).
- (blind+edge) A server that drops between the seed listing and the proxy's reads `error`, not `unreachable`: true (`Proxy.Reason` keeps `unreachable` only in `outcome`), but only in a window of seconds between two listings, and the fix plumbs a new word: low, rejected.
- (blind+edge) A late answer clears a newer poll's mark: needs a mark older than 150 s while `Decide` answers within 110 s of its `OnRequest`; `wontfix-theoretical` (real if Decide's queue held a poll over 40 s).
- (edge) A throw in `SourceAnswer`, or between `MarkInFlight` and the send's Try, leaves the mark: it goes stale after 150 s by design; low, rejected.
- (edge) A clock moved back keeps the mark busy for the step plus 150 s: `wontfix-theoretical`.
- (edge) A source made stopped while its own poll is in flight: a poll lasts at most Decide's timer against a 5-minute minimum interval; `wontfix-theoretical` (as at the implement review).
- (edge) `TimerSeconds` set to 12-25 s frees the mark while TriageAgent still runs the call: a configuration edge that only adds triage delay already bounded by Decide's timer; low, rejected.
- (edge) An empty MCP text could arrive as a non-string value and read `failed`: maybe-false and low (the proxy returns `{"text": ""}`, a string); rejected.
- (blind) A send that fails records no CheckRun row: coverage then reads the source as missed (no false all-clear); the fix adds a branch; low, rejected.
- (blind) A Busy reply to a poll would read as passed: false; the runner answers Busy only for a linked turn, and `Bridge.Poll` never sets it.
- (auditor) Task 0 items 1 and 2 deviated from their procedure: item 1's real path (TriageAgent, Kind `tool`, the seeded map) is pinned by `TestPollRuns`; item 2's second Tick follows from `Ens.BusinessProcess`, which persists an instance awaiting an async answer and frees the job; low, rejected.
- (auditor) `Decide.OnRequest`'s no-runner poll branch is untested: `RunnerFor` always maps a poll to `decide`; `wontfix-theoretical`.
- (auditor) `Mcp/Ops.cls` edits `Notify`'s middle, not only an appended method: the task says "extending Notify's loop"; `by-design` (a merge note for the lead).

**Re-review (rework 1).** Code review 2026-11-14 (Tier 1, full mode; scoped to the rework commit, `git diff ddc72f70 61b4e4ea` over `src`, the planning artifacts and the evidence; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all completed, none failed). Each line: severity, fix-risk, footprint, spec-status. 35 raw findings: 7 entries after grouping (high 1, medium 4, low 2), 13 rejected.

- [x] [Review][Patch] [high; fix-risk low; in-story; clear] Rule 6: the amended AD-18 Part B said a source that only waits in the queue "is never marked stale or missed", and `Coverage`'s class doc, `QUEUESECONDS` and `SourceSlack` docs said the same ("up to QUEUESECONDS later for each source ahead of it"); the code allows 60 s per source, while a poll that runs to Decide's timer delays each source behind it by up to the timer plus a Tick, which the spine's own measured record and the spec's Design Notes 22 admit. Wording only, no behaviour [ARCHITECTURE-SPINE.md AD-18 Part B; src/ocutalon/cls/OcuTalon/Checks/Coverage.cls] (acceptance-auditor+blind-hunter+edge-case-hunter) -- Resolved inline: Part B now says the allowance covers a queue of polls that each answer within a Tick and names the residual (DW-1346, decision-pending), and the three Coverage docs state the allowance and what it does not cover; `lint_spine.py` still the 10 pre-existing low placeholders.
- [x] [Review][Patch] [med; fix-risk low; in-story; clear] Rule 14: the AD-21 measured record and `evidence/22-11-task0-poll.md` still said the 3-silent-sources result is "pinned by `TestOneInFlightNoQueueStale`", whose wait assertion the rework removed; the test pins the one-at-a-time sends and the 150 s mark, and the allowance is `TestSlowQueueOfThreeNotStale`'s [ARCHITECTURE-SPINE.md AD-21 measured record; evidence/22-11-task0-poll.md:75] (acceptance-auditor+edge-case-hunter) -- Resolved: both say what each test pins and that the 120 s is the measurement; no number changed.
- [x] [Review][Patch] [med; fix-risk low; in-story; clear] Rule 19 hermeticity: `TestSlowQueueOfThreeNotStale` flips its five fixture rows to the real Kind with `NextDueAt` "" (due), so a real Tick of the running production (shown running on the warm stack) would poll them, record them stopped (no classification row for `zz`) and change `PollingSources`' count under the oracle [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls:577] (verification-gap+edge-case-hunter) -- Resolved: the rows get `NextDueAt` 2099 (`DueOf` skips them); mutation re-run in `## Verification`.
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] `TestSlowQueueOfThreeNotStale`'s `AssertTrue(60 * (count - 1) > 180, ...)` compares two constants and cannot fail [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls:588] (verification-gap+blind-hunter) -- Resolved: removed.
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] `Checks.Process` `StopNotice`'s doc said "a failed stop notice is one warning in all"; `Mcp.Ops` `Send` warns once for each admin session whose notice fails [src/ocutalon/cls/OcuTalon/Checks/Process.cls StopNotice] (edge-case-hunter) -- Resolved: the doc says one warning of `Send` for that admin session, and Checks adds none.
- [x] [Review][Defer] [med; fix-risk med; in-story; spec-bound] DW-1346's residual: the ruled allowance (60 s per non-stopped source; 180 s for three) does not cover the ruling's own scenario (3 polls each held near Decide's 60 s timer, the third about 240 s), so the rework AC as worded (3 sources) is not met and `TestSlowQueueOfThreeNotStale` (5 sources, synthetic CheckRun times 60 x i apart) pins the formula, not the queue's real waits; a raised `TimerSeconds` (up to 110 s) or a dropped answer (`INFLIGHTSECONDS` 150 s) widens it [src/ocutalon/cls/OcuTalon/Checks/Coverage.cls QUEUESECONDS, SourceSlack] (blind-hunter+edge-case-hunter+acceptance-auditor) -- deferred: DW-1346 decision-pending (owner burndown, for the Planner; occurrence appended), recommendation max(180 s, 120 s x sources); mirrored in the spine's `## Deferred`. The formula is the binding ruling and is not changed here.
- [x] [Review][Defer] [med; fix-risk low; out-of-footprint; clear] Rule 19: `Coverage.PollingSources` counts the install's non-stopped source rows, so `Test.Digest.Coverage`'s source boundary tests now depend on rows they did not create: one leftover row turns `TestSourceLongIntervalStale` red (shown on the warm stack, `## Verification`), two turn `TestSourceIntervalGap` red; its docs also still state interval + 180 s [src/ocutalon/cls/OcuTalon/Test/Digest/Coverage.cls TestSourceLongIntervalStale, TestSourceIntervalGap] (verification-gap+acceptance-auditor) -- deferred: DW-1353 escalated (owner burndown): Lane B's `Test/Digest/**`, which this story may not edit; the smallest fix is `Test.Digest.CoverageProbe` overriding `PollingSources` to count the test's own rows. Supersedes the `deferred:` frontmatter item's "low".

**Rejected (re-review):**
- (blind+edge) The allowance has no cap, so a saturated queue (more sources than one poll a minute serves) reads passed at a lower rate than the interval: inherent in the ruled formula; `by-design`.
- (blind) The two-stopped and four-stopped cases both expect 180 s: low; the named mutations (stopped counted, no floor) are red.
- (blind+verification-gap) `TestSlowQueueOfThreeNotStale` is weaker on a stack with leftover sources, and `others` is not asserted 0: low; the oracle is right for any count, the mutations were observed red on a clean stack, and asserting 0 would make the test's result depend on leftovers.
- (blind) `OtherSources` repeats `PollingSources`' parsing: low; an independent oracle on purpose (`PollingSources` is Private, and calling it would make the oracle the code under test).
- (blind) `Watch.Ops.#SOURCEKIND` against `Checks.Process.#SOURCEKIND`: false; both are "source".
- (blind+edge) `Rows` lost `OR Ref = ?`: false; Decide writes a Decision row with the request's ItemId, unique on (ItemId, Kind) (verification-gap).
- (blind) `StopNotice`'s warning no longer names the source, the `StopNotice` warning clean-up is dead, and "Checks adds none" is always true: the one warning is the task's (Notify's), the clean-up is harmless, and the assertion is the pin of "StopNotice logs again", observed red; low.
- (blind) `PollingSources` falls back to 0 silently: low; the fallback is the 180 s floor (a stale reading, never a false all-clear), and a log line adds a branch.
- (edge+auditor) The count is read at the build, not when the runs happened: low; the task's "compute it once per Build", recorded in Design Notes 21.
- (edge) "No second notice" reads before a late duplicate: false; NoticesIn's Send runs inside the Tick's handling and `Settled` waits for that header (as in the rework's review).
- (edge) Other tests change the count between `OtherSources` and `Build`: tests run one at a time; the production's Checks is the real mechanism, fixed above.
- (verification-gap) `TestPollRuns`' `Answered()` waits for any Decide answer, not this poll's: low; it needs another source poll during the test, and no other source row exists on a clean stack.
- (auditor) The implement pass edited the AD-18 records it was told to leave to the stage agent: process only; the records are reviewed and corrected in this pass (the first two items).

**Re-review (DW-1346 ruled change).** Code review 2026-11-15 (Tier 1, full mode; scoped to `git diff 71f69aae 5857c554` over `src`, the planning artifacts and the evidence; layers blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, all subagents, from the epic worktree). The code matches the ruling: `QUEUESECONDS` 120 is the one constant, N is `PollingSources` (every non-stopped source of the install, no column), the floor is `MISSEDSECONDS`, and the three-source test is kept with literal oracles. No HIGH and no Rule 6 contradiction. `lint_spine.py`: the 10 pre-existing low placeholder findings. **Runtime proof pending:** the release quiet window (lead, 2026-11-15T00:35Z) tore down this review's lane D warm stack (`e22s11cr3w`) during its start, so the patches below are applied but not compiled or run (the lead committed them as `e45d62d7`, "unverified"); the proof the lead must run before any push is listed after the items.

- [x] [Review][Patch] [med; fix-risk low; in-story; clear] Rule 19 hermeticity: `TestSlowQueueOfThreeNotStale` asserted `OtherSources()` = 0, so any non-stopped real-Kind source row left by another class or session (`Test.Mcp.SourceRunProduction`, `SourceSet` and `SourceSetProduction` write such rows; DW-1353 saw one on a warm stack), or a source an admin configured on a dev slot, turned it red with no defect in `Coverage`, and the literal oracles then failed in a cascade; this reversed rework 1's re-review reject ("asserting 0 would make the test's result depend on leftovers") [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls:589] (blind-hunter+verification-gap+edge-case-hunter) -- applied (UNVERIFIED, see the proof below): new test-only `Test/Mcp/SourceRunCoverage.cls` (a `Checks.Coverage` subclass, like `Test/Digest/CoverageProbe.cls`) overrides `PollingSources` as Coverage's own count (`##super()`) less `^||SourceRunCoverage("others")`; `ResultsOf` sets that to `OtherSources()` just before each `Build` and builds through the probe; `OnAfterOneTest` resets it; the precondition assertion is gone. The test's own rows are still counted by the real `PollingSources`, so the three ruled mutations still reach it (a stopped row counted adds the test's two stopped rows and any stopped other rows, which only widens the allowance).
- [x] [Review][Patch] [med; fix-risk low; in-story; clear] Truthfulness: the residual "a timer raised above 60 s ... is not covered" (Coverage class doc "a slower timer for instance, still reads stale or missed", AD-18 Part B, the AD-21 measured record, the evidence's Rework note 2) is false: `PollInFlight` holds the queue only until the answer, `Decide` answers within its timer (`MAXTIMER` 110 s at most) and Ticks are 60 s apart, so with any timer the next source goes at the second Tick after a send, about 120 s; only a lost answer (the 150 s mark, the third Tick, about 180 s) is not covered [src/ocutalon/cls/OcuTalon/Checks/Coverage.cls:28-31; ARCHITECTURE-SPINE.md AD-18 Part B and the measured record; evidence/22-11-task0-poll.md Rework note 2] (acceptance-auditor+blind-hunter+edge-case-hunter) -- applied: the four places now say a raised timer only narrows the margin before that Tick and name the lost answer as the case not covered; the `QUEUESECONDS` doc says "60 seconds by default, 110 at most". Wording only. The `### Ruled change pass` summary in `## Auto Run Result` still carries the old residual sentence (a pass record, left as written).
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] "May be up to interval + max(...) late" reads as the whole gap being lateness (a 15-minute source 21 minutes late); the code allows the runs to be interval + slack apart, that is slack late beyond the interval [src/ocutalon/cls/OcuTalon/Checks/Coverage.cls:28; ARCHITECTURE-SPINE.md AD-18 Part B] (blind-hunter+acceptance-auditor) -- applied: "apart", and "up to max(180 s, 120 s x those sources) late beyond its interval".
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] The AD-21 measured record kept the ~20:40Z amendment ("60 s x ... a residual for the Planner") as live prose ahead of the ~23:00Z one, so it stated two allowances; the evidence's first Rework note read as current [ARCHITECTURE-SPINE.md measured record; evidence/22-11-task0-poll.md:84] (blind-hunter+acceptance-auditor) -- applied: the record now states the 120 s allowance once under both markers, with the ~20:40Z text kept as `[it read ...]`; the evidence note is marked "superseded by Rework note 2 below".
- [x] [Review][Patch] [low; fix-risk low; in-story; clear] "About 120 s per source behind a timer-length poll" is stated as fact though nothing measures it (the test writes `CheckRun` rows 120 x i apart; Task 0 measured a 26 s poll) [Coverage.cls class doc; AD-18; evidence] (blind-hunter) -- applied: labelled "(inference from the code)" in each place.
- [ ] [Review][Patch] [low; fix-risk low; in-story; clear] Rule 19: the upper bound (the run 1300 s before the end of the span reads `not_checked`) has no `mutation:` line; every recorded mutation narrows the allowance. The surviving band is `QUEUESECONDS` 100 to 133, not "121 to 139" as the ruled pass's triage reject says [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls 1300 s assertion] (verification-gap) -- open, runtime only: mutation `QUEUESECONDS` 180 -> `TestSlowQueueOfThreeNotStale` red on "1300 seconds ... no longer stands"; then write its `mutation:` line in `## Verification`.

**Proof the patches need (lane D warm throwaway after the quiet window, one class per call):** (1) `Test.Mcp.SourceRun` green (the new `SourceRunCoverage` compiles and the class passes); (2) hermeticity: insert one non-stopped real-Kind `source` row of another session (`NextDueAt` 2099, as `zzcr2leftover` in rework 1's re-review), `Test.Mcp.SourceRun` green, then the mutation `SourceRunCoverage.PollingSources` without the subtraction (`Quit ##super()`) -> `TestSlowQueueOfThreeNotStale` red ("1300 seconds ... no longer stands"), revert, delete the row; (3) the three ruled mutations again through the probe (`QUEUESECONDS` 60, no floor, a stopped source counted) -> red, each reverted with `cmp`; (4) `QUEUESECONDS` 180 -> red (the open item); (5) `Test.Digest.Coverage` green. Record each as a `mutation:` line in `## Verification`.

**Rejected (DW-1346 re-review):**
- (blind+verification-gap+auditor) The rename rewrote the spec's older records (five-source messages under the new name): fixing it edits the spec's history; the ruled pass's block already notes it.
- (verification-gap) The AC "Rework (DW-1346)" in Tasks & Acceptance still says 60 s x the sources: a spec edit; for the lead (a Rule 5 restatement of the ruled numbers).
- (edge) The allowance grows without a cap with N (30 sources, 3,600 s): the ruled formula (N is every non-stopped source of the install); `by-design`. A source whose poll fails records `not_checked` at once, so the allowance only delays `missed` for a source with no run.
- (edge) Derive `QUEUESECONDS` from the timer in effect: false for the timer (see the second item); the lost-answer case is the ruled one constant, `by-design`, and is documented.
- (verification-gap) The oracles leave `QUEUESECONDS` 100 to 133 passing: low; the ruling asks for literal oracles of the three-source case and its mutation (60) is red; a tighter pair adds complexity.


**Proof of the DW-1346 re-review patches (lead, after QUIET OFF; new lane-D warm stack `e22s11pfw`, lane D's warm and throwaway locks held for the whole proof, torn down after):**
- (once) `OcuTalon.Test.Mcp.SourceRun` -- passed (the new `Test/Mcp/SourceRunCoverage.cls` compiles).
- (once) one leftover non-stopped source row of another session in the install -- `OcuTalon.Test.Mcp.SourceRun` still passed.
- mutation: `SourceRunCoverage.PollingSources` reduced to `Quit ##super()` (with the leftover row) → `TestSlowQueueOfThreeNotStale` red; reverted (`cmp` identical), row deleted, class green.
- mutation: `QUEUESECONDS` 60 → `TestSlowQueueOfThreeNotStale` red; reverted (`cmp` identical).
- mutation: `SourceSlack` without the 180 s floor → `TestSlowQueueOfThreeNotStale` red; reverted (`cmp` identical).
- mutation: `PollingSources` counting a stopped source → `TestSlowQueueOfThreeNotStale` red; reverted (`cmp` identical).
- mutation: `QUEUESECONDS` 180 (the upper bound) → `TestSlowQueueOfThreeNotStale` red; reverted (`cmp` identical).
- (once) `OcuTalon.Test.Digest.Coverage` -- passed; `OcuTalon.Test.Mcp.SourceRun` -- passed on the restored tree.

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

- 2026-11-14 (lead). **Re-gate APPROVED, Contest Planner ~15:10Z Nov 14 (BINDING)**, quoted from `<coordination>/prompts/epic-22-rulings-20261113-1715.md`:
  - "**Veto 1, the reason words** (invalid, notreadonly, notfound, unreachable, timeout, failed, changed, demo, denied): APPROVED. They are never shown, and never produced on the demo."
  - "**Veto 2, Reported's stored shape** ({"seen": up to 50 SHA-256 hashes, "baseline", "stopped"}): APPROVED. Hashes only, no new column, never written on the demo."
  - "**The runner's own calls are accepted:** an answer from before a repoint is dropped (the key is <Ref>|<sentAt>); a changed tool counts as stopped; `stopped` means the latest run; a stopped run is not the baseline; SeedMcp writes the map entry directly."
  - "## Task 0 pre-ruling: If the triage limit trips, apply option **(a)** automatically: at most ONE poll in flight. Then MEASURE AGAIN in all four mock modes (answering, silent, Silence, Stall). (a) passes only if BOTH hold: 1. The STOP criteria pass: the median adds no more than 10 s, AND no triage decision misses its timeout. 2. With 3 silent sources due at once, every due source still polls within interval + 180 s, so no source is marked stale only because of queuing. PIN THAT with a test. If (a) fails either check, STOP (`PLANNER REPORT:`). Options (b) and (c) need the Planner's ruling. Report the before and after numbers in PART READY either way."
  - Built into Task 0 item 5 (the pre-ruled path and `TestOneInFlightNoQueueStale`). Veto items 1 and 2 are now APPROVED.

- 2026-11-14 (lead). **Rulings for the rework, Contest Planner ~20:40Z Nov 14 (BINDING)**, quoted from `<coordination>/prompts/epic-22-rulings-20261113-1715.md`:
  - "**DW-1350: RATIFIED.** `inflight` is a transient member of Reported, present only while a poll is out, with no column, and never written on the demo."
  - "**DW-1346:** one poll per Tick STAYS, because it protects triage. But staleness must not flag a source that is only waiting in the queue. In the rework pass, the allowance becomes: interval + max(180 s, 60 s × the number of sources due together). Test it with 3 slow sources due at once: none is marked stale. Add a mutation."
  - "**DW-1347:** a low DW for lane C, after 21.5: compare the hash of the FULL tool result, taken BEFORE the tool-result cut. It does not block 22.11."
  - Rework iteration 1 (code review's five MED and three LOW open `[Review][Patch]` items, plus DW-1346's allowance) re-opens the story; `status` set to `in-progress`.

- 2026-11-14 (lead, after the re-review). **DW-1353 closed in-story:** `Test/Digest/CoverageProbe.cls` (Story 22.5's file, Lane A) now overrides `PollingSources` with `^||CoverageProbe("polling")` (0 by default), so no other session's or test's source row changes a source's allowance in `Test.Digest.Coverage`. Proof on a new lane-D stack (`e22s11lpw`): with three leftover non-stopped source rows of another session, `Test.Digest.Coverage` passed; mutation (override removed) turned `TestSourceIntervalGap` and `TestSourceLongIntervalStale` red; reverted byte-identically. The re-review's HIGH (an AD-18 wording overclaim, no behaviour change) is accepted as resolved inline. DW-1346's ruled formula leaves three polls held near Decide's 60 s timer stale (the ruling's own 3-source test cannot pass at 60 s per source); `TestSlowQueueOfThreeNotStale` uses five sources; decision-pending with the Planner (recommendation about 120 s per source).

- 2026-11-14 (lead). **DW-1346 ruled, Contest Planner ~23:00Z Nov 14 (BINDING)**, quoted from `<coordination>/prompts/epic-22-rulings-20261113-1715.md`: "The allowance becomes: interval + max(180 s, QUEUESECONDS × N), with QUEUESECONDS = 120 as ONE constant. N counts every non-stopped source in the install. It is computed in Checks.Coverage, with no column. KEEP the 3-slow-sources test (none marked stale), and add a mutation: QUEUESECONDS back to 60 turns it red. The AD-18 and docs wording fix ("never marked stale" removed) is accepted. The new wording states the allowance plainly, without "never"." Status set to `in-progress` for this ruled change (a lead-dispatched implement pass, then a scoped re-review).

- 2026-11-14 (lead). **Ruled change DW-1346, implement items (Contest Planner ~23:00Z Nov 14, binding; exactly this, scope closed; this pass edits only the files named here):**
  1. `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls`: `Parameter QUEUESECONDS` 60 -> 120, as the one constant. The allowance stays interval + max(MISSEDSECONDS (180 s), QUEUESECONDS x N), N = every non-stopped source in the install (`PollingSources`, no column). Restate the class doc, `QUEUESECONDS`'s doc and `SourceSlack`'s doc to state the allowance plainly ("a source may be up to interval + max(180 s, 120 s x the non-stopped sources) late before it reads stale or missed"), with no "never" and no claim beyond what the code does; keep the honest residual note only if it is still true at 120 s (a poll that runs to Decide's 60 s timer plus a Tick is about 120 s per source).
  2. `src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls` `TestSlowQueueOfThreeNotStale`: 3 slow sources due at once (not 5), each poll held as long as Decide's timer plus a Tick (the third source's second run about 240 s after its due time: spacing 120 s per source), and assert NONE is marked stale or missed (both the in-span gap check and the carried-run `Current`). Keep the stopped-source branches (fewer non-stopped sources give a smaller allowance, and one gives the 180 s floor) adjusted to 3 sources. Prefer literal oracles from the ruling's numbers over recomputing the code's formula. Rename the test to drop "Never" (`TestSlowQueueOfThreeNotStale`), updating every reference (this spec, `evidence/22-11-task0-poll.md`, the spine, the class docs). Mutations required, each applied alone, the named test observed red, then reverted byte-identically (`cmp` with a saved copy): `QUEUESECONDS` back to 60 -> that test red; `SourceSlack` without the 180 s floor -> red; `PollingSources` counting a stopped source -> red.
  3. `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: update the AD-18 records that state the allowance (the Part A allowance sentence, 22.13's stale clause, the Part B one-in-flight record, the measured-numbers record, and the `## Deferred` DW-1346 row) to 120 s per source, plainly, with an `[AMENDED 2026-11-14, Story 22.11, Contest Planner ruling ~23:00Z Nov 14 (DW-1346, option (1))]` marker and the old text; remove the DW-1346 `## Deferred` row or mark it resolved. Run `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` and confirm only the 10 pre-existing low findings.
  4. `_bmad-output/implementation-artifacts/evidence/22-11-task0-poll.md`: one line noting the allowance is now 120 s per source (no measured number changes).
  5. This spec: update Design Notes item 22, the Pinning mutations table and the Mutations demonstrated list for the rename, the 3-source test, QUEUESECONDS 120 and the new mutation records.
  (The lead appends the ledger line and commits; the subagent does neither.)

## Review Triage Log

### 2026-11-14 -- Review pass
- verdicts: 32 findings -- high 0, medium 10, low 21, false 1, maybe-false 0
- findings:
  - `[medium]` `[defer]` Blind: one poll per Tick for the whole install (plus the starvation of waiting sources and the claim of check 2 beyond 3 sources; Edge 3 and Edge 10 share the root cause) -- the pre-ruled option (a); ordering oldest-first patched (see Edge 3), the capacity itself deferred to the Planner's (b)/(c)
  - `[low]` `[reject]` Blind: PollInFlight scans and parses every source row each Tick -- tens of rows at most, once a minute; a column or filter is more than a direct correction
  - `[false]` `[reject]` Blind: a Busy reply recorded as passed -- OnRequest returns Busy only when 'tool && Held (Decide.cls L345); a poll is kind tool, so Decide never answers it Busy
  - `[medium]` `[patch]` Blind and Edge: PollCall accepts arguments that are not a JSON object -- PollCall answers invalid unless the parsed arguments are a dynamic object; TestPollRunWords pins arrays and numbers (mutation recorded)
  - `[medium]` `[defer]` Blind: a poll's answer is cut at the tool-result room -- the tool's own bound applies; the cut note carries the lengths; deferred with the evidence
  - `[medium]` `[patch]` Blind and Verification gap: TestOneInFlightNoQueueStale compared two constants -- it now asserts the third source's send set NextDueAt at the Tick of step 3 and measures the wait against the coverage's allowance
  - `[low]` `[patch]` Blind and Verification gap: TestSourceStoppedNotice never checked the render -- it now asserts the rendered notice holds the source, tool and server
  - `[low]` `[reject]` Blind: the SHA-256 hex helper exists three times -- the tests compute the oracle independently on purpose, and a shared helper would make the oracle the code under test
  - `[low]` `[reject]` Blind and Edge: ProxyManager builds a manager before the agent check, and its message changed -- a discarded manager costs nothing and no test or reader pins the old wording
  - `[low]` `[reject]` Blind: the Gate class doc has two steps numbered 5 -- the doc already numbers its alternatives 5 (replay, other contexts)
  - `[low]` `[patch]` Blind: the Verification table lacked two mutation rows -- added with the others
  - `[medium]` `[patch]` Edge: OnError then OnResponse records a failed poll twice -- read in irislib Ens.BusinessProcess: a handled error is followed by OnResponse for the same key; ErroredKey makes the second call a no-op; TestOtherFailure counts the CheckRun rows and the announcements (mutation recorded)
  - `[low]` `[patch]` Edge: SendPoll that throws leaves the in-flight mark -- the send is in a Try and a thrown error clears the mark like an error status
  - `[medium]` `[patch]` Edge: the lowest ID always wins when more sources are due than one Tick sends -- RunSources runs the due rows oldest NextDueAt first (RowOf carries it); TestOldestDueFirst (mutation recorded)
  - `[low]` `[reject]` Edge: a stopped record or a late answer wipes the mark while a poll runs -- a stopped source makes no call, and a poll lasts at most 110 seconds against an interval of at least 5 minutes: wontfix-theoretical
  - `[low]` `[reject]` Edge: a new hash is stored before its Item is sent, so a failed send is not retried -- matrix row 2 says one warning, not resent: by-design
  - `[low]` `[reject]` Edge: a stop notice that fails is not retried -- matrix row 5 says once per transition and one warning: by-design
  - `[low]` `[reject]` Edge: Decide's timer ends before the runner on a long poll -- TimerSeconds 60 against a poll of at most about 26 seconds; wontfix-theoretical
  - `[medium]` `[patch]` Verification gap: a proxy refusal after the seed listing was unpinned -- TestPollRunWords holds the tools/call past its bound and asserts the word timeout with no text (mutation recorded)
  - `[medium]` `[patch]` Verification gap: the real StopNotice and SourceClass never ran -- OPSCLASS and the probe's RealSeams run them; TestStopThroughTheRealSeams (mutation recorded)
  - `[low]` `[defer]` Verification gap: Proxy.Listed's demo word is untested -- the demo is held at RunSources and by MCPDEMO; deferred; the SeedMcp key checks got TestSeedMcpKeys
  - `[medium]` `[patch]` Verification gap: TestPollRuns asked ItemIdKindIndexExists with one argument, so it could not fail -- it counts the Decision rows of the ItemId by SQL
  - `[low]` `[reject]` Verification gap: TestFirstRunBaseline asserts the session the test set on the shadow -- the assertion pins that Checks carries its own session to the send; kept
  - `[low]` `[patch]` Verification gap: three ACs lacked a mutation line -- recorded (recording, stopped); the no-model half and the triage-delay AC are closed with a reason in Verification
  - `[low]` `[patch]` Verification gap: TestPollRunWords made its fixture row due, so the production's own Checks could poll it -- the fixture row's NextDueAt is 2099
  - `[low]` `[reject]` Verification gap: SourceRun flips fixture rows to the real Kind for a moment -- a window of milliseconds in a class that runs in one second
  - `[low]` `[reject]` Verification gap: SourceRunProduction waits a fixed 1.1 seconds before its Tick -- it then waits on LastRunAt up to 40 seconds, whichever Tick ran
  - `[medium]` `[reject]` Verification gap and Intent: the inflight member beyond the approved Reported shape -- pre-ruled (a) puts the in-flight state on the row and no column is allowed; decided in-stage (note 17) and flagged to the Planner in the report
  - `[low]` `[reject]` Intent: rows 3 to 9 are pinned at the Checks seam and the bridge layers, rows 1 and 2 end to end -- the spec's own test list; the wire is covered by TestPollRuns and TestPollRunWords
  - `[low]` `[reject]` Intent: the stopped check is made in Checks and again in PollCall -- the two are the spec's (before the send, and after a denial or a change)
  - `[low]` `[reject]` Intent: a run recorded in the same second as a repoint keeps the old history -- already deferred
  - `[low]` `[reject]` Intent: Checks maps the word demo to error -- no poll runs on the demo, so it is a backstop only

### 2026-11-14 -- Review pass (rework 1)
- verdicts: 24 findings -- high 0, medium 4, low 19, false 1, maybe-false 0
- findings:
  - `[medium]` `[defer]` Blind, edge, verification-gap and intent-alignment: the ruled allowance (60 s per source; 180 s for 3) does not cover the Planner's own scenario (3 slow polls, the third at about 240 s), and the test uses 5 sources -- spec-bound: the formula is the binding ruling (Design Notes 21, 22); deferred as decision-pending for the Planner with the 120 s per source recommendation
  - `[medium]` `[patch]` Blind, edge and verification-gap: the `waited <= allowed` assertion of TestOneInFlightNoQueueStale cannot fail (the `Polls()` keys hold the real send time) -- removed; the 140 s and 160 s mark ages pin INFLIGHTSECONDS (mutation 3600 red) and the NextDueAt assertion pins the Tick of the send
  - `[medium]` `[patch]` Blind and verification-gap: TestSlowQueueOfThreeNotStale's oracle copies the formula from Coverage's constants and the floor is never reached -- the oracle uses the ruling's literals (60, 180); a four-of-five-stopped case reaches the floor; mutations QUEUESECONDS 30 and no floor red
  - `[medium]` `[defer]` Verification-gap: Test.Digest.Coverage's boundary tests depend on the install's source count -- Lane B tests that this story may not edit; deferred low (recorded in `deferred:`)
  - `[low]` `[patch]` Verification-gap: TestPollRuns' CheckRun assertion had no mutation line -- mutation `RecordRun` writes no row, red; recorded
  - `[low]` `[patch]` Edge and verification-gap: `RunEvents(1)` returns at the first event, so a duplicate check event is not seen -- TestPollRuns waits for Decide's answer to be handled (`Answered`) before reading the events
  - `[low]` `[patch]` Blind and verification-gap: the ProbeSink `Types` doc says "moved" (history) -- reworded to the contract
  - `[low]` `[patch]` Edge: OtherSources read the stopped state by substring where PollingSources parses it -- it parses the same member
  - `[low]` `[reject]` Blind and edge: QUEUESECONDS is a literal where Decide's timer is a setting -- the 60 s is the ruling's number; a raised timer is the same residual as the first finding
  - `[low]` `[reject]` Blind and edge: the allowance grows with the source count and loosens miss detection -- inherent in the ruled formula (a source that waits in a queue of N is allowed to); by-design
  - `[low]` `[reject]` Blind and edge: PollingSources counts every owner's rows, due or not -- the cap of option (a) is install-wide; Design Notes 21 records the choice
  - `[low]` `[reject]` Edge: PollingSources treats an unreadable or non-string stopped as not stopped -- Process writes `stopped` as a string only; a bad Reported counts one source more, which widens the allowance, never narrows it
  - `[false]` `[reject]` Edge: StopNotices("no second notice") reads before a late duplicate -- the verification-gap layer read that NoticesIn.Send runs ProcessInput inside the Tick's handling, and Settled waits for that header, so the NoticesIn to Notify header exists when the Tick completes
  - `[low]` `[reject]` Edge: StopNotices counts a Notify header whatever its status -- the headers are read after Settled, and the mutation "StopNotice sends nothing" and "notice on every stopped run" turn the test red
  - `[low]` `[reject]` Edge: the 140 s mark leaves a 10 s margin -- the mark is written in the same process just before the Tick (milliseconds)
  - `[low]` `[reject]` Blind: the check event's traceHeaderId is compared with the row's LastRunHeaderId -- the AC says the Tick's session id; the row's value is pinned against the Tick by TestFirstRunBaseline
  - `[low]` `[reject]` Blind and verification-gap: `Rows` lost the `OR Ref = ?` half -- a Decision row of a poll would carry the request's ItemId (Decide writes the request's ItemId); the poll-branch mutation still turns the test red
  - `[low]` `[reject]` Blind: StopNotice ignores the status of SourceStopped -- Mcp.Ops warns on every failing path and TestStopNoticeFailureIsOneWarning pins the read of the admins
  - `[low]` `[reject]` Verification-gap: Test/Digest/Coverage.cls:363's comment states the old allowance -- Lane B file, which this story may not edit
  - `[low]` `[reject]` Blind: spec bookkeeping (the rework task still open, review_loop_iteration) -- the task is ticked at finalize; the loop count is for bad_spec loopbacks
  - `[low]` `[reject]` Blind: the evidence says "option (a) passes both checks" under the 240 s note -- the note's own sentence and the rework note say what holds; the evidence keeps its numbers by instruction
  - `[low]` `[reject]` Blind: the DW-1346 AC (3 sources) is not tested as worded -- same root cause as the first finding
  - `[low]` `[reject]` Intent: the rework edits Coverage.cls, which the intent contract lists under Never -- the Contest Planner's ruling DW-1346 (binding, ~20:40Z Nov 14) names it
  - `[low]` `[reject]` Intent: the count is "non-stopped source rows", not "sources due together" -- Design Notes 21 (the cap is install-wide); an upper bound

### 2026-11-14 -- Review pass (ruled change DW-1346, option (1))
- verdicts: 21 findings -- high 0, medium 1, low 15, false 5, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: the spine's Part B and measured records and the evidence say the 120 s "covers" a timer-length poll without saying it is the default 60 s timer (Decide's timer can be raised to MAXTIMER 110 s) -- patched: the spine's two statements and the evidence note now say "the default 60 s timer" and that a raised timer or a lost answer holding the in-flight mark is not covered.
  - `[low]` `[reject]` Blind: three stacked amendment layers for one number in four places of the spine -- the ruling asked for the amendment marker with the old text; the stack is the spine's own convention, and a rewrite is churn.
  - `[low]` `[reject]` Blind: the spine's DW-1346 row is removed while the ledger's last DW-1346 line still reads decision-pending -- the ledger line `status=resolved-by:22-11-...` is appended in this same pass (item 5), so the tracker and the spine agree at the commit.
  - `[low]` `[reject]` Blind: the 1200 s and 1300 s oracles leave the exact 1260 s boundary open (QUEUESECONDS 121 to 139 would pass) and N = 2 or 4 is not tested -- the ruling asks for literal oracles of the 3-source case; a tighter pair is more complexity than a cosmetic gain, and the three required mutations are pinned.
  - `[low]` `[reject]` Blind: the class description hard-codes numbers that sit beside the constant -- the ruling asks for the allowance stated plainly with its numbers; "the one constant" is the ruling's own words.
  - `[low]` `[reject]` Blind: the evidence's Check 2 body still says "interval + 180 s" -- the two rework notes right below it give the current rule, and the measured text is history.
  - `[low]` `[defer]` Edge: a lost answer holds the in-flight mark 150 s, which delays each later source about 180 s, beyond 120 s per source -- option (a)'s INFLIGHTSECONDS predates this change, and the ruling fixed 120; recorded in `deferred`.
  - `[low]` `[patch]` Edge: a Decide timer above 60 s is not covered by the 120 s -- the same wording patch as the first row (Coverage's class doc already said it).
  - `[low]` `[reject]` Edge: the install-wide count widens one session's allowance (20 sources give 2400 s) -- the ruling: "N counts every non-stopped source in the install"; the queue is install-wide.
  - `[low]` `[reject]` Edge: the spec's rework AC and items still say 60 s -- the last Spec Change Log entry (the ruling) and the amended Design Notes 21 and 22 supersede them; an edit of the build's spec for history is out of triage's scope.
  - `[medium]` `[patch]` Verification gap: with another non-stopped source row in the install the test's `If 'others` assertions skip and the three mutations can survive while the class stays green -- patched: the test now asserts first that no other source of the install is polling (a failing assertion, not a skip), the guards are gone, and the class doc says so; the three mutations were observed red again after the patch.
  - `[low]` `[reject]` Verification gap: the rework-1 mutation lines quote the deleted five-source body -- an edit of the spec's history; a note was added to the ruled-pass block saying which lines describe the shipped test, and the three observations of the shipped test are there.
  - `[low]` `[reject]` Verification gap, other: the spec's rework AC and items 47, 49 and 253 still say 60 s -- same as above (the Spec Change Log's ruling supersedes them).
  - `[low]` `[patch]` Verification gap, other: the class doc described the guarded assertions as unconditional -- fixed with the patch above (no guards remain).
  - `[low]` `[reject]` Verification gap, other: 120 s hard-codes the default timer with no test tying them -- the accepted residual, now stated in the docs; a test tying a setting to a constant would be new scope.
  - `[false]` `[reject]` Intent: "KEEP" may mean the five-source test stays -- the ruling and the lead's instruction say 3 slow sources instead of 5; the stopped-source branches are kept, adjusted to 3.
  - `[false]` `[reject]` Intent: no mutation record is in the diff -- the diff excluded the spec; the records are in `## Verification` (the ruled-pass block).
  - `[false]` `[reject]` Intent: the diff edits `Checks/Coverage.cls`, in the contract's Never list -- the ruling puts the computation in `Checks.Coverage`, and earlier rework passes edited it under the Planner's rulings.
  - `[false]` `[reject]` Intent: the intent block still says "inside interval + 180 s" -- the intent contract is read-only; the amendment is in the Spec Change Log.
  - `[low]` `[reject]` Intent: the allowance is a reader-side change and the queue is unchanged, so it covers up to 120 s per source -- true and documented in the class doc and AD-18; no defect.
  - `[false]` `[reject]` Intent: a "never" remains in "runs before its CreatedAt never count" and a stale-mark comment -- neither is a statement of the allowance; the ruling removed "never" from the allowance wording only.

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
17. **(implement) The in-flight mark is the `inflight` member of a source row's `Reported`** (the send time of the one outstanding poll; Task 0 item 5's pre-ruled option (a), "the row's in-flight state on the row"). It adds no column, exists only while a poll is outstanding, and the record of the answer writes `Reported` without it; it is a member beyond the approved `{seen, baseline, stopped}`, flagged to the Planner.
18. **(implement) After `OnError` the host calls `OnResponse` for the same key** (`Ens.BusinessProcess`, read in `irislib`), so `OnError` notes the key (`ErroredKey`, transient) and `OnResponse` skips that call once: a failed poll records once.
19. **(implement) Due sources run oldest `NextDueAt` first** (never-run first), so that option (a)'s one poll a Tick never passes over a waiting source for one that is due again.
20. **(implement) `Checks.Process.OPSCLASS`** names the class whose `SourceStopped` tells the admins (`Mcp.Ops`); `Test.Mcp.SourceProbe` points it at `Test.Mcp.OpsProbe` and, with `RealSeams` 1, runs the real `SourceClass` and `StopNotice`.
16. A poll's `turn.step` reaches no chat: `BridgeSink.Step` publishes only for the running turn's ItemId (read, not changed).

**Decided in-stage (rework 1, DW-1346):**
21. **The allowance of a source is interval + max(180 s, 120 s x the sources that are not stopped).** [AMENDED 2026-11-14, DW-1346 ruled, Contest Planner ~23:00Z: `QUEUESECONDS` is 120, the one constant; it read 60 s.] `Checks.Coverage` reads the count once for each `Build` (`PollingSources`: the `source` rows of the install whose `Reported.stopped` is empty, with no new column) and passes the slack (`SourceSlack`) to `WatchRow` (`allowed`, rule 3) and to `Current` (the carried run). The count is install-wide because option (a)'s cap is: one poll per Tick serves every session's sources, so all of them can wait in the same queue. A stopped source sends no poll and records at once, so it does not wait and is not counted. A read that fails counts 0, which leaves the old 180 s.
22. **The DW-1346 test uses three sources.** [AMENDED 2026-11-14, DW-1346 ruled, Contest Planner ~23:00Z: it used five sources because, with 60 s per source, three gave the old 180 s and no test of three could tell the allowances apart; at 120 s per source three give 360 s, so the ruling's three-source case is the test.] `TestSlowQueueOfThreeNotStale` queues three sources due together whose polls each run to Decide's 60 s timer plus a Tick (source i running 120 x i seconds late, 240 s for the third) and asserts none is stale or missed, in the span (the gap, 900 + 360 s) and before it (`Current`: a run 1200 s before the end of the span stands, one 1300 s before does not). With two of the three stopped (one counts) the allowance is the 180 s floor: the source that waited 240 s reads not checked in the span, and a run 1050 s before the end of the span stands (it would not with the floor removed, 120 s). Its oracles are the ruling's numbers as literals (360 s, 180 s, 1200, 1300, 1050), not Coverage's constants and no copy of the formula, so each mutation (`QUEUESECONDS` 60, no floor, a stopped source counted) turns it red; the test asserts first that no other non-stopped source of the install exists (`OtherSources` is 0, as on a fresh stack), so a stack that holds one fails loudly and the mutations cannot survive quietly (the code review's patch; it was a skip). The residual note of the review (a poll that runs to the timer and a Tick delays each source ahead of it about 120 s, 240 s for the third) is covered by the 120 s: three such sources read stale or missed only beyond interval + 360 s.

**Rule 2 near-copies in `Test/Bridge/Poll.cls` (rework 1):** `Rows` now calls `RunnerFixture.DecisionRowCount`, and `SinkTypes` and `SinkCalls` call the new `ProbeSink.Types` and `ProbeSink.Calls`; `SourceRunProduction` `Poll()` calls `Tick()`. `Sentence` stays a copy of `Test.Bridge.Gate`'s: that one is a Private class method of a test class that this story must not edit (Task list: `Test/Bridge/Gate.cls`: no edit), `Test.Bridge.Poll` extends `Test.Mcp.JobFixture` and so cannot inherit it, and two other test classes (`Tools.Email`, `Core.ConversationFiles`) keep the same six-line copy. `Test.Bridge.Decide`'s own `SinkTypes` stays, for the same reason.

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

**NEW at this gate, APPROVED (Contest Planner ~15:10Z Nov 14):**
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
| The poll's runner uses an ungoverned manager (`PollManager` skips `Govern`) | `TestPollRuns` |
| `Decide.OnResponse` poll branch off (a poll goes through `Conclude`) | `TestPollNoDecisionRow` |
| Option (a) applied (Task 0 item 5): drop the in-flight check in `PollSource` | `TestOneInFlightNoQueueStale` |
| OnError and the host's OnResponse for the same key both record | `TestOtherFailure` |
| Due sources run in the order of their rows, not oldest NextDueAt first | `TestOldestDueFirst` |
| `Proxy.Noted` does not note a poll's refusal | `TestPollRunWords` |
| `Attach.PollCall` accepts arguments that are not a JSON object | `TestPollRunWords` |
| `StopNotice` swaps the tool and the server in the call to `Mcp.Ops` | `TestStopThroughTheRealSeams` |
| A stopped source is polled (the stopped check dropped) | `TestStoppedBeforeSend` |
| A passed run recorded as failed | `TestNewResult` |
| Rework 1: the coverage's allowance of a source back to interval + `MISSEDSECONDS`, in `WatchRow` and `Current` (DW-1346) | `TestSlowQueueOfThreeNotStale` |
| Rework 1: `PollingSources` counts a stopped source too | `TestSlowQueueOfThreeNotStale` |
| Rework 1: `INFLIGHTSECONDS` 3600, so a queued source waits past interval + 180 s | `TestOneInFlightNoQueueStale` |
| Rework 1: `StopNotice` sends nothing | `TestStopThenResume` |
| Rework 1: a notice on every stopped run (`wasStopped` dropped) | `TestStopThenResume` |
| Rework 1: `Announce` does not publish the check event | `TestPollRuns` |
| Rework 1: `RunSources` without its `PollsOff` return | `TestOnlineDemoNoPollInProduction` |
| Rework 1: `Decide.OnResponse` poll branch off (on the changed `Rows` and `SinkTypes` helpers) | `TestPollNoDecisionRow` |
| Rework 1: `StopNotice` logs its own warning again | `TestStopNoticeFailureIsOneWarning` |
| Rework 1: `Coverage` `QUEUESECONDS` 30, or `SourceSlack` without the 180 s floor | `TestSlowQueueOfThreeNotStale` |
| DW-1346 ruled: `Coverage` `QUEUESECONDS` back to 60 (the allowance 180 s for three sources) | `TestSlowQueueOfThreeNotStale` |
| DW-1346 ruled: `SourceSlack` without the 180 s floor (`Quit slack`) | `TestSlowQueueOfThreeNotStale` |
| DW-1346 ruled: `PollingSources` counts a stopped source too | `TestSlowQueueOfThreeNotStale` |
| Rework 1: `Coverage.RecordRun` writes no CheckRun row | `TestPollRuns` |

**Mutations demonstrated (Rule 19; each applied alone, the named test observed red, then reverted byte-identically, `git status --short` and `git diff --stat` as before):**

- mutation: `Adapter.Agent` `PollManager` no longer calls `Govern` (an ungoverned manager) -> `Test.Mcp.SourceRunProduction:TestPollRuns` red ("the one step of the poll is labelled for the tool and the server"). Note: a runner job keeps the class it started with, so `TestPollRuns` restarts TriageAgent first (`PointRunner`, which also points its key at the CI mock so that a model request would show); without the restart the mutation was not seen.
- mutation: `Decide.OnResponse` poll branch off (`If 0 {`), so the poll goes through `Conclude` -> `Test.Bridge.Poll:TestPollNoDecisionRow` red.
- mutation: `RecordSource` without the `seen` check (`ElseIf (hash '= "")`) -> `Test.Mcp.SourceRun:TestSeenBefore` red.
- mutation: `RecordSource` does not insert the `SourceItem` -> `Test.Mcp.SourceRunProduction:TestNewResultReachesIntake` red ("one Item went from Checks to Intake").
- mutation: `RecordSource` calls `Record` without keep (the last argument 1 dropped) -> `Test.Mcp.SourceRun:TestNextDueAtAtSend` red.
- mutation: `RecordSource` notifies on every stopped run (`If outcome = "stopped"`) -> `Test.Mcp.SourceRun:TestStoppedNotifiesOnce` red.
- mutation: `Gate.Decision` allows any name in a poll (`If 0 && (name '= ..#MCPPROXY)`) -> `Test.Bridge.Poll:TestPollOnlyProxy` red.
- mutation: `Gate.Decision` treats a poll as a replay (`replay = (context.Kind = ..#REPLAYKIND)`, so a grant is required) -> `Test.Bridge.Poll:TestPollNoGrant` red.
- mutation: `StateOf` ignores `CreatedAt` in the start-afresh rule -> `Test.Mcp.SourceRun:TestRepointBaseline` red.
- mutation: `SourceAnswer` drops the `sentAt` check (`If 0 {`) -> `Test.Mcp.SourceRun:TestAnswerBeforeRepoint` red.
- mutation: `RunSources` drops its demo return -> `Test.Mcp.SourceRun:TestOnlineDemoNoPoll` red.
- mutation: `PollSource` drops the in-flight check (`If 'stopped && busy Quit 0`) -> `Test.Mcp.SourceRun:TestOneInFlightNoQueueStale` red.
- mutation: `OnResponse` does not skip the call that follows `OnError` for the same key (`If 0 && ...`) -> `Test.Mcp.SourceRun:TestOtherFailure` red ("(error status) one CheckRun row is written and the run is announced once").
- mutation: `RunSources` orders the due rows by their position, not by NextDueAt -> `Test.Mcp.SourceRun:TestOldestDueFirst` red.
- mutation: `Proxy.Noted` drops `|| IsPoll()` -> `Test.Bridge.Poll:TestPollRunWords` red ("(call timeout) a call that the proxy refuses after the listing is the word timeout").
- mutation: `Attach.PollCall` drops the JSON-object check -> `Test.Bridge.Poll:TestPollRunWords` red ("arguments that are a JSON array").
- mutation: `StopNotice` passes the server where the tool belongs -> `Test.Mcp.SourceRun:TestStopThroughTheRealSeams` red (the notice's slots).
- mutation: `PollSource` never reads the source as stopped (`Set stopped = 0`) -> `Test.Mcp.SourceRun:TestStoppedBeforeSend` red (and `TestStoppedNotifiesOnce`, `TestStoppedCoverage`): the "each run is recorded" and "stopped" ACs are pinned by these.
- mutation: `RecordSource` records a passed run as `failed` -> `Test.Mcp.SourceRun:TestNewResult` red (and `TestResume`, `TestOneInFlightNoQueueStale`): the "each run is recorded" AC.
- The "no model" half of AC 1 is pinned by the model-mock log assertion in `TestPollRuns` (zero model requests); the poll path holds no model client, so no one-line mutation makes it call one (accepted). The triage-delay AC has no automated test: it rests on `evidence/22-11-task0-poll.md`.

**Rework iteration 1 (lane D warm throwaway, tag `e22s11riw`; each mutation applied alone, the named test observed red, then reverted from a saved copy with `cmp` identical and the class green again on the same stack):**

- mutation: `Checks.Coverage` `WatchRow` and `Current` use interval + `MISSEDSECONDS` again -> `Test.Mcp.SourceRun:TestSlowQueueOfThreeNotStale` red ("(in the span) the source that waited 240 seconds beyond its interval reads passed with 300 seconds allowed"; "the run of the last source, 1150 seconds before the end of the span, stands").
- mutation: `PollingSources` counts a stopped source (`If 'stopped` dropped) -> `Test.Mcp.SourceRun:TestSlowQueueOfThreeNotStale` red ("(with two of the five stopped) the source that waited 240 seconds beyond its interval reads not_checked with 180 seconds allowed").
- mutation: `INFLIGHTSECONDS` 3600 (a queued source waits past interval + 180 s) -> `Test.Mcp.SourceRun:TestOneInFlightNoQueueStale` red ("a mark 160 seconds old holds nothing: a third poll is sent"). The first try was red by an `<INVALID OREF>` of the missing third poll; the test now stops on the failed assertion.
- mutation: `StopNotice` sends nothing -> `Test.Mcp.SourceRunProduction:TestStopThenResume` red ("the admin session got one mcp.sourceStopped through the real NoticesIn").
- mutation: `RecordSource` notifies on every stopped run (`&& 'wasStopped` dropped) -> `Test.Mcp.SourceRunProduction:TestStopThenResume` red ("and sends no second notice").
- mutation: `Announce` does not publish (`Set sc = $$$OK`) -> `Test.Mcp.SourceRunProduction:TestPollRuns` red ("one check event carries the run"). `TestPollRuns` now restarts the Checks item first (a job keeps the class it started with).
- mutation: `RunSources` without its `PollsOff` return -> `Test.Mcp.SourceRunProduction:TestOnlineDemoNoPollInProduction` red (the Tick sent a poll request; the row, the CheckRun rows and the control follow), read after `Settled`, with no fixed wait.
- mutation: `Decide.OnResponse` poll branch off (`If 0 {`) -> `Test.Bridge.Poll:TestPollNoDecisionRow` red, through the shared `RunnerFixture.DecisionRowCount` and `ProbeSink.Types` helpers.
- mutation: `StopNotice` logs its own warning again -> `Test.Mcp.SourceRun:TestStopNoticeFailureIsOneWarning` red ("and Checks adds none").
- Review pass of rework 1 (patches to the rework's own tests; each mutation applied alone, the named test observed red, then reverted from a saved copy with `cmp` identical and `git status --short` unchanged, and the class green again on the same stack):
  - mutation: `Coverage.SourceSlack` returns `MISSEDSECONDS` (the old allowance in both places) -> `Test.Mcp.SourceRun:TestSlowQueueOfThreeNotStale` red ("(in the span) the source that waited 240 seconds beyond its interval reads passed with 300 seconds allowed").
  - mutation: `Coverage` `QUEUESECONDS` 30 -> `TestSlowQueueOfThreeNotStale` red (same lines: the oracle holds the ruling's 60).
  - mutation: `SourceSlack` without the 180 s floor (`Quit slack`) -> `TestSlowQueueOfThreeNotStale` red ("(with four of the five stopped) the source that waited 120 seconds beyond its interval reads passed with 180 seconds allowed").
  - mutation: `PollingSources` counts a stopped source (`If 'stopped` dropped) -> `TestSlowQueueOfThreeNotStale` red ("(with two of the five stopped) ... reads not_checked with 180 seconds allowed").
  - mutation: `INFLIGHTSECONDS` 3600 -> `TestOneInFlightNoQueueStale` red ("a mark 160 seconds old holds nothing: a third poll is sent").
  - mutation: `Coverage.RecordRun` writes no CheckRun row (`Quit`) -> `Test.Mcp.SourceRunProduction:TestPollRuns` red ("one CheckRun row is written, with no Reason (passed)"; `TestStopThenResume` and `TestNoSecretLeaksOnFailure` also red).
  - mutation: `Process.Announce` does not publish (`Set sc = $$$OK`) -> `TestPollRuns` red ("one check event carries the run"), now read after Decide's answer was handled (`Answered`).
- Code review, re-review of rework 1 (lane D warm throwaway, tag `e22s11cr2w`; the mutation applied alone, the class observed red, reverted from a saved copy with `cmp` identical, `git status --short` and `git diff --stat` unchanged, and the class green again on the same stack):
  - mutation: `Coverage.SourceSlack` returns `MISSEDSECONDS` (`Quit ..#MISSEDSECONDS`) -> `Test.Mcp.SourceRun:TestSlowQueueOfThreeNotStale` red ("(in the span) the source that waited 240 seconds beyond its interval reads passed with 300 seconds allowed"; "the run of the last source, 1150 seconds before the end of the span, stands (the allowance is 1200 seconds)"), after the review's patch that gives its five fixture rows `NextDueAt` 2099 (never due for the production's own Checks) and drops its constant-only assertion.
  - hermeticity, shown: one non-stopped `source` row of another session (Ref `zzcr2leftover`, `NextDueAt` 2099) inserted on the warm stack -> `Test.Digest.Coverage:TestSourceLongIntervalStale` red ("and one a second older is stale"); the row deleted -> green. Lane B's test; DW-1353.
- Green on the warm stack after the reverts: `Test.Mcp.SourceRun`, `Test.Mcp.SourceRunProduction`, `Test.Bridge.Poll`, `Test.Bridge.Gate`, `Test.Bridge.Decide`, `Test.Bridge.Ext`, `Test.Mcp.Proxy`, `Test.Digest.Coverage`, `Test.Digest.AllClear` and `Test.Checks.Runs`.

**DW-1346 ruled pass (lane D warm throwaway, tag `e22s11qw`; `QUEUESECONDS` 120, `TestSlowQueueOfThreeNotStale` with three sources; each mutation applied alone to `Checks/Coverage.cls`, the class `Test.Mcp.SourceRun` observed red, reverted from a saved copy with `cmp` identical and `git status --short` as before; `Test.Mcp.SourceRun` green before and after, then `Test.Digest.Coverage` green):**

- mutation: `QUEUESECONDS` 60 -> `Test.Mcp.SourceRun:TestSlowQueueOfThreeNotStale` red ("(in the span, three sources) the source that waited 240 seconds beyond its interval reads passed"; "the run of the third source, 1200 seconds before the end of the span, stands (the allowance is 900 + 360 seconds)").
- mutation: `SourceSlack` without the 180 s floor (`Quit slack`) -> `TestSlowQueueOfThreeNotStale` red ("with two of the three stopped, the run of the third source, 1050 seconds before the end of the span, stands (the floor: 900 + 180 seconds)").
- mutation: `PollingSources` counts a stopped source (`If 'stopped` dropped) -> `TestSlowQueueOfThreeNotStale` red ("(in the span, one source counts) the source that waited 240 seconds beyond its interval reads not_checked").
- spine lint (`lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`): 10 findings, all low, as before.
- Review pass of the ruled change (same tag; the three mutations applied again alone after the review's patch, each reverted from a saved copy with `cmp` identical, the class green again after): `QUEUESECONDS` 60 -> `TestSlowQueueOfThreeNotStale` red (the two messages above); `SourceSlack` without the floor -> red ("... 1050 seconds before the end of the span, stands (the floor: 900 + 180 seconds)"); `PollingSources` counting a stopped source -> red ("(in the span, one source counts) ... reads not_checked"). Note: the mutation lines of rework 1 above that quote "five" sources, 1150 s or "allowed" describe the earlier five-source body of this test; the observations of the shipped three-source test are the ones in this block.

**QA pass (lane D warm throwaway, tag `e22s11qw`; tests only; one test file changed, `src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRunProduction.cls` (QA), five tests added on the real production):**

- `TestSourceRemovedInFlight`, `TestServerRemovedInFlight` (matrix 6 on the real Checks, Decide, TriageAgent and a silent mock; the source row, or the server with its tool rows, sources and entry, is removed while the poll waits; no row is made again, no CheckRun row, no Item to Intake, no `check` event).
- `TestOnlineDemoNoPollInProduction` (matrix 7: a real `source` row, the real `onlineDemo` setting 1, a Tick to the real Checks: no Checks to Decide request, the mock hears nothing, the row as it was; control: with the setting back the same row is polled).
- `TestStopThenResume` (matrix 5 on the real classification rows: risky gives `not_checked`, Reason `stopped`, no request reaches the mock; read-only again polls, passes, clears `stopped`, is the baseline).
- `TestNoSecretLeaksOnFailure` (no argument value, URL or secret in a message, event-log row, audit entry, step label, finding or CheckRun row after a 401 poll, a stopped run and a poll of a mock that is down).
- Each restarts the Checks item first (a job keeps the class it started with). Whole class `OcuTalon.Test.Mcp.SourceRunProduction` passed on the warm stack with the five new tests (45 s).
- mutation: `RunSources` without its `PollsOff` return -> `Test.Mcp.SourceRunProduction:TestOnlineDemoNoPollInProduction` red ("the Tick sent no poll request to Decide", "the row is as it was", "no CheckRun row", and the control's two assertions).
- mutation: `PollSource` never reads the source as stopped (`Set stopped = 0`) -> `Test.Mcp.SourceRunProduction:TestStopThenResume` red ("no poll request went to Decide"; the run still ends stopped, because `PollCall` refuses `notreadonly` before any request reaches the mock).
- mutation: `RecordSource` logs the row's Arguments in a warning for a run that is not passed -> `Test.Mcp.SourceRunProduction:TestNoSecretLeaksOnFailure` red ("no event-log row holds the argument value or the URL"; `TestNoSecretLeaks` on the success path stays green).
- mutation: `SourceAnswer` makes the row again when it finds none (`%New`, Ref, Kind, `%Save`) -> `Test.Mcp.SourceRunProduction:TestSourceRemovedInFlight` and `TestServerRemovedInFlight` red ("the row is not made again"). No smaller mutation turns them red: `SourceAnswer`'s missing-row return and `Record`'s `%ROWCOUNT` check each stop a recording alone, so the removal's answer is inert by two layers.
- Each mutation applied alone, reverted from a saved copy (`cmp` identical) with `git status --short` unchanged.

**Notes of the implement stage (Task 0 and its result are in `evidence/22-11-task0-poll.md`):**

- Option (a) WAS applied: before it, `Call(port, "silent")` added 12746 ms to the median triage decision (limit 10000 ms); after it, every mode passes both limits (medians 27, 5734.5, 16 and 15 ms against a baseline of 28 ms; no decision with Fallback 1 or a timeout). The in-flight mark is `inflight` (the send time) in the source row's `Reported`, which is a member beyond the approved `{seen, baseline, stopped}` shape: it exists only while a poll is outstanding, holds a time, no column is added, and the record of the answer writes `Reported` without it.
- `Test.Mcp.SourceRunProduction` extends `Test.Mcp.JobFixture` (the zzmcp fixtures) and not `Test.Core.InProduction`, because both are test cases; it repeats InProduction's clean-up.
- `Test.Bridge.Poll` also pins `Poll.Run` with OcuTalon's `PollCall` (`TestPollRunWords`) and `Agent.PollManager` with no agent built.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** On each Tick `Checks.RunSources` sends every due `source` row one asynchronous untrusted `tool` request through `Decide`, oldest `NextDueAt` first and at most one poll in flight (Task 0 item 5's option (a), pre-ruled). `Decide` admits it as a poll, runs it on TriageAgent, and answers a bare Reply with no `Decision` row. `Bridge.Poll` makes one governed `call_mcp_tool` on a proxy-only manager seeded by `PollCall`. `Checks.OnResponse` records the run: the first success since `CreatedAt` is a baseline, a new SHA-256 of the whole answer is one untrusted Item for `Intake`, a source whose tool is no longer Read-only stops with one `mcp.sourceStopped`, and nothing runs on the online demo.

**Task 0.** Option (a) WAS applied: before it, `Call(port, "silent")` added 12746 ms to the median triage decision (limit 10000 ms); after it every mode passes (medians 27, 5734.5, 16 and 15 ms against a baseline of 28 ms; no decision with Fallback 1 or a timeout). The numbers per mode are in `evidence/22-11-task0-poll.md`.

**Files.** Bridge: `Poll.cls` (new), `Adapter/Agent.cls` (`PollManager`, the poll branch of `Answer`), `Context.cls` (`IsPoll`, `SeedMcp`), `Ext/McpServers.cls` (`PollCall`, `POLLREASONS`), `Policy/Gate.cls` (the poll branch), `Process/Decide.cls` (`Admit`, `RunnerFor`, `PollAnswer`). Product: `Checks/Process.cls` (`RunSources`, `OnResponse`, `OnError`, `RecordSource`, `SourceItem`, the seams), `Mcp/Attach.cls` (`PollCall`), `Mcp/Proxy.cls` (`Listed`, `Listing`, `Noted`), `Mcp/Ops.cls` (`SourceStopped`), `Data/BackgroundCheck.cls` and `Digest/Data/CheckRun.cls` (docs). Tests: `Test/Bridge/Poll.cls`, `Test/Mcp/SourceRun.cls`, `Test/Mcp/SourceProbe.cls`, `Test/Mcp/SourceRunProduction.cls` (new), `Test/Bridge/Ext.cls`.

**Review.** 32 findings (a finding that two layers reported is one row): 12 patched (the double record after `OnError`, oldest-first order, a refusal after the seed, the real stop seams, non-object arguments, three vacuous or weak assertions, three missing mutation lines, a send that throws, the fixture row's due time), 3 deferred (option (a)'s capacity of one poll per Tick install-wide, a cut answer, `Listed`'s demo word; the same-second repoint was deferred by the implement pass), the rest rejected with reasons in the Review Triage Log (one was false: a Busy reply cannot reach a poll).

**Verification.** Warm, one class per call, after the last patch: `Test.Bridge.Poll`, `Gate`, `Decide`, `Ext`, `Test.Mcp.SourceRun`, `SourceRunProduction`, `Proxy`, `Test.Bridge.Runner`, `Approval`, `Test.Mcp.Approval`, `Attach`, `Ops`, `SourceSet`, `SourceSetProduction`, `Test.Checks.Queues`, `Runs`, `Test.Digest.Coverage`, `AllClear`, `Test.Watch.Ops`, `Test.Msg.Catalog` all passed (`Test.Bridge.Poll` once more after the last test patch); `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` exit 0; `SourceRunProduction` passed on a fresh stack (tag `e22s11i`), then torn down. Every row of the Pinning mutations table was observed red and reverted byte-identically.

**Residual risks.** (1) The in-flight mark is an `inflight` member of `Reported`, beyond the approved shape (Design Notes 17): flagged to the Planner. (2) Option (a)'s capacity (deferred, escalated). (3) The skip after `OnError` rests on the kernel's `Ens.BusinessProcess` source and is exercised in the test by calling `OnResponse` as the host does, not by a live failed call. Follow-up review recommended: true (two or more medium findings patched; the unverified risk is (3) and the new test seams `OPSCLASS` and `RealSeams`).

### Rework iteration 1 (this pass only)

**Closed.** The eight `[Review][Patch]` items (each ticked with how it was closed) and DW-1346: `Checks.Coverage` allows a source its interval + max(180 s, 60 s x the sources that are not stopped) in the gap check and in `Current` (`SourceSlack`, `PollingSources`, read once for each `Build`, no column; Design Notes 21 and 22). The AD-18 spine records (Part A, 22.13's stale clause, Part B and the measured record) carry the `[AMENDED 2026-11-14, Story 22.11 rework, Contest Planner ruling ~20:40Z Nov 14 (DW-1346)]` marker with the old text; `lint_spine.py` reports only the 10 pre-existing low placeholder findings. The evidence file keeps its numbers and gains one rework note. DW-1350 is ratified (no work) and DW-1347 goes to lane C.

**Files.** `Checks/Coverage.cls` (the allowance), `Checks/Process.cls` (`StopNotice` no longer logs), `Mcp/Ops.cls`, `Bridge/Process/Decide.cls`, `Bridge/Ext/McpServers.cls` (docs), tests `Test/Mcp/SourceRun.cls`, `Test/Mcp/SourceRunProduction.cls`, `Test/Bridge/Poll.cls`, `Test/Bridge/ProbeSink.cls`; the spine and the evidence note.

**Review (rework 1).** 24 findings: high 0, medium 4, low 19, false 1. Patched: the vacuous `waited` assertion (removed; the mark ages pin it), the formula-copying oracle of `TestSlowQueueOfThreeNotStale` (literals, plus a four-stopped case for the floor), the missing mutation line of `TestPollRuns`' CheckRun row, `RunEvents`' early return, a doc that narrated history, `OtherSources`' substring read. Deferred: the formula's residual for the Planner (below) and `Test.Digest.Coverage`'s dependence on the install's source count. The rest rejected with reasons in the Review Triage Log. Patched counts: medium 2, low 4.

**Verification.** Warm (tag `e22s11riw`, one class per call), after the last patch: `Test.Bridge.Poll`, `Gate`, `Decide`, `Ext`, `Test.Mcp.SourceRun`, `SourceRunProduction`, `Proxy` (loop), then `Test.Bridge.Runner`, `Approval`, `Test.Mcp.Approval`, `Attach`, `Ops`, `SourceSet`, `SourceSetProduction`, `Test.Checks.Queues`, `Runs`, `Test.Digest.Coverage`, `AllClear`, `Test.Watch.Ops`, `Test.Msg.Catalog` all passed; `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` exit 0; `SourceRunProduction` passed on a fresh stack (tag `e22s11ri`), torn down; the warm stack is down. Every mutation of the rework (the table rows and the `mutation:` lines of `## Verification`) was observed red and reverted byte-identically.

**[Superseded 2026-11-14 by the Planner's ruling ~23:00Z (DW-1346, option (1)), see the last Spec Change Log entry and "Ruled change pass" below.] Residual risk (for the Planner; deferred, decision-pending).** The ruled allowance gives 60 s per source, so for three sources it is 180 s, the old figure: three polls that each run to Decide's 60 s timer leave the third at about 240 s, and it still reads stale or missed for waiting. The test uses five sources and the ruling's numbers (Design Notes 22). A rule of 120 s per source would cover it. Follow-up review recommended: true, for that risk (two medium patches).

Status: done
Blocking condition: none

### Ruled change pass (DW-1346, option (1); Contest Planner ~23:00Z Nov 14)

Status: done
Blocking condition: none

**Summary.** `Checks.Coverage` `QUEUESECONDS` is 120 (the one constant): a source may be up to interval + max(180 s, 120 s x the non-stopped sources of the install) late before it reads stale or missed, stated plainly in the class doc and the docs of `QUEUESECONDS` and `SourceSlack`, with the honest residual (a timer above the default 60 s, or a lost answer that holds the in-flight mark, is not covered). `TestSlowQueueNeverStale` is now `TestSlowQueueOfThreeNotStale`: three slow sources due together, each poll held for Decide's timer plus a Tick (the third about 240 s late), none stale or missed in the span and in `Current`, literal oracles, the stopped-source branches adjusted (one counts: the 180 s floor), and a loud precondition that no other source of the install is polling. AD-18's allowance records (Part A, Part B, the digest record, the measured record) carry the `[AMENDED 2026-11-14, Story 22.11, ... (DW-1346, option (1))]` marker with the old text, and the DW-1346 `## Deferred` row is removed. The evidence has one line for it. The ledger has `DW-1346 status=resolved-by:22-11-...`.

**Files.** `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls`, `src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls`, `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, `_bmad-output/implementation-artifacts/evidence/22-11-task0-poll.md`, `_bmad-output/implementation-artifacts/deferred-work.md` (the ledger line), this spec.

**Review.** 21 findings: high 0, medium 1, low 15, false 5. Patched: the test's loud precondition (medium; it was a skip that let mutations survive on a dirty stack) and the "default 60 s timer" wording (low, two findings, plus a doc fix). Deferred: one low (a lost answer's in-flight mark delays a source beyond 120 s). The rest rejected with reasons in the Review Triage Log.

**Verification.** Lane D warm stack, tag `e22s11qw`, one class per call: `Test.Mcp.SourceRun`, `Test.Digest.Coverage`, `Test.Mcp.SourceRunProduction` (after the patch, and `SourceRun` again after it), `Test.Digest.AllClear` all passed; `Test.Mcp.SourceSetProduction` ran before `SourceRun` and left no polling source. `bash docker/tests/test-class-rules.sh` exit 0. The spine lint gives the 10 pre-existing low findings. Mutations, each alone, observed red and reverted byte-identically (`cmp`): `QUEUESECONDS` 60, `SourceSlack` without the 180 s floor, `PollingSources` counting a stopped source (messages in `## Verification`). Warm stack torn down.

**Residual risks.** The 120 s per source covers the default 60 s timer plus a Tick; a timer up to `MAXTIMER` (110 s) or a lost answer holding the in-flight mark (150 s) delays a source by more and it can still read stale or missed (deferred, low). Follow-up review recommended: false (one medium patched, no high).
