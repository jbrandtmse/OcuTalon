---
title: 'Story 22.5: Poll a read-only MCP tool as a source'
type: 'feature'
created: '2026-11-12'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-3-call-mcp-tools-only-through-the-governed-proxy.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-4-hold-risky-and-unclassified-mcp-calls-for-approval.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** An admin can classify an MCP tool Read-only, but nothing can poll it. `McpOps` has no handler for `SetSourcePoll` or `RemoveSourcePoll`, so `CommandsIn` answers both `failed`. A `tool` request can only replay an approved call. The digest's coverage list has no source entries and no mailbox entry. Its not-checked case renders "Not everything: Jira. Everything else I checked passed.", not the UX sentence "Not checked: Jira (unreachable since 02:10). Everything else I checked passed."

**Approach:**
- **The row.** `McpOps` validates a source-poll command. It writes or removes a `BackgroundCheck` row of `Kind` `source` through new `Watch.Ops` row methods, audits the change and sends `CheckChanged`.
- **The run.** On each `Tick`, `Checks` sends each due source an asynchronous `tool` request through `Decide`. The request has provenance `untrusted` and carries only the source's Ref. Its runner calls `call_mcp_tool` once, with no model:
  - the bridge's new `Poll` class runs it on a governed manager that holds only the proxy;
  - the call map is seeded from a live listing by OcuTalon's own client.

  `Checks` records the run from the answer. A result not seen before becomes one untrusted Item for `Intake`.
- **Stopping.** A source whose tool is no longer Read-only stops polling, and admins get the accepted `mcp.sourceStopped` notice once.
- **The digest.** `Checks.Coverage` lists source rows at their own interval and adds the connected mailbox from the `emailPoll` mark. When nothing failed, the digest leads with the not-checked lines followed by "Everything else I checked passed.".

## Boundaries & Constraints

**Always:**
- **Lanes (U-177).** Lane A files only:
  - the bridge's `Process/Decide.cls`, `Adapter/Agent.cls`, `Policy/Gate.cls`, `Context.cls`, `Ext/McpServers.cls`, `Audit.cls` and the new `Poll.cls`;
  - `Mcp/**`, `Watch/Ops.cls`, `Data/BackgroundCheck.cls`, `Checks/**`, `Digest/Process.cls`, `Live/Payload/Check.cls` (its publisher's lane);
  - `Test/{Mcp,Bridge,Checks,Digest}/**`, Lane A rows only.
- **Order.** Implement only after Stories 22.3 and 22.4 are committed:
  - 22.3 gives `call_mcp_tool`, `Mcp.Proxy`, `Mcp.Client.ListTool`, `McpToolref`, the `MCP` call audit and `MCPDEMO`;
  - 22.4 gives `Agent.ProxyManager`, `Context.NoteReplayRefusal`/`ReplayRefusal` and `Attach.Toolref`.

  Use their names exactly as specified; read their specs' Code Maps first.
- **Governed like a built-in tool.** A poll's call goes through:
  - the gate: `UNREGISTERED`, `ClassifyMcp` at the live fingerprint, `U` on `OcuTalon_MCP_<server>`, the untrusted rule;
  - the step audit policy, which writes a step labelled "Running {tool} on {server}";
  - the proxy's re-list, cut and `MCP` audit entry.

  It never reaches AI Hub's MCP client and never calls a model.
- **Untrusted.** A poll's request has provenance `untrusted`. Only a safe, read-only classification runs, and anything else is denied (`UNTRUSTED`), never held. Results reach `Intake` only as untrusted Items, never as trusted output.
- **No false all-clear (AD-28).** A source counts as checked only when its runs in the window all passed. Otherwise it is not checked, with its reason. The reserved sentence still comes only from `Checks.Render`.
- **AD-5.** Nothing that decides "due", "seen" or "stopped" lives in memory. It lives on the row (`NextDueAt`, `Reported`).
- **Online demo.** `McpOps` refuses both verbs with `not_allowed` (its existing `Refusal`). No source row can exist there. `Checks` skips any `source` row when `Watch.Reader.OnlineDemo()` is 1, and the proxy refuses with `MCPDEMO`. The demo path, `Test.Bridge.Gate`, `Test.Bridge.Approval` and the replay path stay unchanged.

**Never:**
- Edit `Core.*`, `Web.*`, `web/**`, `Msg.*`, `Data.Precedent`, `Data.Setting`, `Channel.Email.*`, `Test/Contract/**`, `Test/Core/**`, `Test/Live/**` or any Lane B test.
  - If a Lane B test pins the old behaviour (for example `SetSourcePoll` answering `failed`, or the `check` payload's member list), stop with `## Clarification Needed`.
- Put an argument value, URL or secret in a request message, log, audit entry or notice. A poll's request carries the source's Ref only.
- Hold a poll's call, give it a grant, register an MCP server on any agent's own manager, put the proxy in any `TOOLSETS`, or add a production item, route, role, privilege, grant or resource.
- Build the Settings form or the rail's schedule line for a source (Lane B, Story 21.5), the docs (22.6), or listing through OcuTalon's client for turns (22.10).
- Delete, skip, tag off or shorten a test.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Set | `SetSourcePoll` from CommandsIn, origin `web_admin`, an admin's `SessionRef`. Server `zz`, tool `zz_lookup` (read-only), Name "Jira", Arguments `{"q":"mine"}`, IntervalMinutes 15. | One `source` row of that session: `Server`, `Tool`, `Arguments` as canonical JSON, `IntervalMinutes`, `DisplayName` "Jira", `AskedBy` the acting user, `CreatedAt` = `NextDueAt` = now. One `MCP` audit entry `source_set` (outcome `created`). One `CheckChanged`. The answer is Ok, outcome `saved`, `MESSAGESAVED`, with the row's Ref. | none |
| Update | The same session sets Name "Jira" again with new arguments or interval. | The same row and Ref, with new values and `NextDueAt` now. Audit outcome `updated`. One `CheckChanged`. | none |
| Refused | The tool is risky or unclassified; or the server or tool is unknown; or the name is blank or over 100 characters; or the arguments are not a JSON object, are over 4,000 characters, or hold `secret://` or `@{`; or the interval is outside 5 to 1,440 minutes; or the origin is not `web_admin`, it comes from a tool or context, or the install is the online demo. | Ok 0 with outcome `not_read_only`, `not_found`, `bad_name`, `bad_arguments`, `bad_interval` or `not_allowed` and its message. No row, audit entry or `CheckChanged`. | Wrong sender or origin: one warning (existing `Refusal`). |
| Remove | `RemoveSourcePoll` with a `source` row's Ref, from any admin. | The row is deleted. Audit `source_removed` (outcome `removed`). `CheckChanged` with `Stopped` 1. Ok, outcome `removed`. | No row, or the Ref is not a `source` row: Ok 0, `not_found`. |
| Server removed | `RemoveMcpServer` for a server with sources. | After the removal commits, each source of that server is removed as in Remove, with an audit entry and a `CheckChanged` each. | A source that fails to go: one warning; the removal stands. |
| Due, first run | A read-only source is due, and the mock answers "T-1 open". | One async `tool` request (provenance `untrusted`, Input `{"source":"<Ref>"}`) goes to Decide, then to TriageAgent. The mock logs one extra `tools/list` (the seed), then the proxy's `initialize`, `tools/list` and `tools/call`, all `client` `iris`. Steps: one, labelled "Running zz_lookup on zz". Audit: `MCP` `called`. No model request, no `Decision` row and no `decision` event. `Checks` records `passed`. `Reported` keeps the answer's hash and `baseline` 1. No Item is sent (the baseline). | none |
| New result | A later run gets "T-1 open\nT-2 open". | One Item goes to Intake: a new ItemId, the row's session, channel `system`, provenance `untrusted`, Subject "Jira", Text the answer. Intake's decision follows. The result is `passed`. | A failed send: one warning (`LOGFINDING`), not resent. |
| Seen before | A later run gets any answer already in `Reported.seen` (the newest 50 hashes). | No Item. `passed`. | none |
| Server down | The mock is stopped from 02:10. | Each run is `not_checked` with `REASONSOURCEUNREACHABLE`. The `CheckRun` Reason is `unreachable`. Coverage gives `digest.notCheckedUnreachable` with the time of the first run of the streak. | Timeout gives `REASONTIMEOUT` (Reason `timeout`). Any other refusal or denial gives `REASONREAD` (Reason `error`). |
| No longer read-only | The admin classifies the tool Risky, or the poll's seed finds it changed (`ClassifyMcp` clears it, 22.8). | That run and every later due run make no call. They record `not_checked` with `REASONNOTREADONLY` (CheckRun Reason `stopped`), and `Reported.stopped` is set. On the transition only, every admin session gets `mcp.sourceStopped` {source, tool, server, time}. Coverage gives `digest.notCheckedStopped` with the time of the first run of the streak. | A tool classified Read-only again resumes polling at the next due time and clears `stopped`. |
| Mailbox | `email.owner` is the session and the `emailPoll` mark exists. | One row "Mailbox", after the background-check rows. Rules:<br>- `passed` when `ok` 1 and `at` is in the window and at most 900 s before its end;<br>- `digest.notCheckedStale` {at} when ok but older than that;<br>- `digest.notCheckedUnreachable` {lastOkAt, else at} when `ok` 0 with `REASONUNREACHABLE`;<br>- `digest.notCheckedError` {at} for any other failed reason. | No mark, or another owner: no row. An unreadable mark gives `digest.notCheckedError`. |
| Digest lead | No row failed, at least one is not checked, and at least one passed. | The checks part is each not-checked row's coverage line in row order, then `checks.everythingElsePassed`. AllClear stays 0. The text reads "Not checked: Jira (unreachable since 02:10). Everything else I checked passed.". | Any failed row, or no passed row: the part is unchanged (`TestPartOrder` stays green). |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`.

- **The command side:**
  - `Mcp/Ops.cls`:
    - `MessageMap` L60-72; `Refusal` L494, which covers origin, sender, acting user and the demo.
    - `Classify` L210, the validate, save, audit and undo pattern; `McpData`/`Common` L525-554; `Answer`/`Failed` L555-571.
    - `Notify`/`Send` L413-456, the admin notices, with the seams `AdminSessions`, `Notice` and `WriteAudit`.
    - `Unregister` L167-199: TCOMMIT at L190. 22.4 inserts its cancel there too.
    - The class doc L3 says it has no handler for the source verbs.
  - `Watch/Ops.cls`:
    - `OnStart` L84-129 is the row-write pattern: lock, natural key, `%Save`, `Changed`.
    - `RefOf` L264; `Changed`/`SendChanged` L235-262; `KIND`/`QUEUEKIND` L29-34.
  - `Msg/Command/SetSourcePoll.cls` (`Server`, `Tool`, `Name`, `Arguments`, `IntervalMinutes`, `ActingUser`) and `RemoveSourcePoll.cls` (`SourceRef`): Lane B, read only. `Core/CommandsIn.cls` L359-360 routes both to McpOps.
  - `Mcp/ToolClassification.cls`: `ServerToolIndexOpen`, `Classification` (`read-only`, `risky` or `unclassified`) and `Fingerprint`. `Mcp/Server.cls` `NAMEPATTERN`.
- **The bridge side:**
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
    - `Admit` L852-858: tool needs provenance `user` and an approval Ref.
    - `RunnerFor` L868; `RUNNERS` L142 (`decide:TriageAgent`); `OnRequest` L325-362, where tool skips `Held` and `Precheck`.
    - `OnResponse` L404-453, where tool gets no retry or resend; `Conclude` L1384.
    - `ConcludeTool` L1489-1523, `RecordFallback` (about L1600-1660), `FireEvent` L1725 and `ResponseFromRow` L1766, which gives a tool Reply with no Text.
  - `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
    - `Answer` L791-843: tool goes to `Replay.Run` at L800.
    - `BuildAgent` L269-292: it needs a provider, so a replay fails `no_key` without one (Decide L180-199).
    - `Govern` L476, `BuildTurnManager` L610-660, `EndTurnTools` L701 and 22.4's `ProxyManager`.
  - `src/bridge/cls/OcuTalon/Bridge/Replay.cls` L68-131: the tool-run pattern (Context, StepBuffer, ExecuteTool, step records, release on every path). Copy its shape, not its approval steps.
  - `src/bridge/cls/OcuTalon/Bridge/Context.cls`:
    - `Begin` L68-86 copies Kind and Provenance and resets taint.
    - `SetMcpTools` L136-162 and `McpFingerprint` L164; 22.3's `McpToolref`; 22.4's `NoteReplayRefusal`/`ReplayRefusal`.
  - `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
    - `Decision` L171-207: the untrusted rule L182-183; `replay` (kind `REPLAYKIND`) L184-185 needs a grant for every call; taint L201-204.
    - `REPLAYKIND` L100; 22.3's `MCPPROXY` and its direct-proxy classification.
  - `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `REASONS` L27 and the defaults L30-57; 22.3's `ProxyToolSet`, 22.4's `ServerOf`. `Mcp/Attach.cls` overrides them (L20-60).
  - `src/bridge/cls/OcuTalon/Bridge/Audit.cls` L17-41 and L149-166: `SHAPEMCP` and `MCPCHANGES`; 22.3 adds `called`/`refused` and the call shape `change,server,tool,outcome`.
  - `Mcp/Proxy.cls` (22.3, 22.4): `Call` steps 1-5 (demo, rows, entry, header, `ListTool`, fingerprint), which 22.5 shares with `Listed`; the refusal word through `NoteReplayRefusal`.
  - `Core/BridgeSink.cls` L440-463 (read only): a `turn.step` is published only for the running turn's ItemId, so a poll's step reaches no chat.
- **The checks side:**
  - `Checks/Process.cls`:
    - `Tick` L216-284: insert after the queue block L246-257.
    - `DueOf` L875, `RowOf` L532 (`ROWCOLUMNS` L127), `Record` L608-641 (with `keep`, which leaves NextDueAt), `SendOwn` L391, `FindingItem` L704 and `Announce` L834.
    - The queue block L857-985 is the precedent for an appended block. `SendQuiet` L500 is the bounded-send precedent. There is no `OnResponse` yet.
  - `Data/BackgroundCheck.cls` -- storage values 1-15; the `RecordRun` trigger (on a `LastRunAt` change) calls `Checks.Coverage.RecordRun`.
  - `Checks/Coverage.cls`:
    - `Build` L128-162; `WatchRow` L273-333 (`MISSEDSECONDS` L41 is fixed at 180 s; the unreachable streak L313-321); `EntryOf` L386, which gives `DisplayName` for any non-production kind.
    - `ReasonOf`/`KeyOf` L463-477; `RecordRun` L479; `Add` L179.
  - `Checks/Render.cls` -- `Build` L46-78 orders the rows failed, then not checked, then passed. `checks.everythingElsePassed` exists in `Msg/Catalog/Watch.cls` L70 and is never returned today.
  - `Digest/Process.cls`:
    - parts L606-644 (the checks part L620: `{checkKey, whatFailed}`); `Verdict` L677-704 (`Render` L683, `allClear` L702);
    - `DigestNotification` L715; the Coverage seam L848.
  - `Channel/DigestText.cls` L1-12 (read only) renders the parts up to the first `AFTERLINES` key, then `lines`, then the rest. Check whether `Channel/Telegram/Out.cls` L13 and L164 rebuild the checks part from the CheckRows; if they do, the lead must apply there too (Lane A).
  - `Channel/Email/In.cls` `Owner()` L58 and `Channel/Email/Adapter.cls` `MARK` L38, `REASONUNREACHABLE` L41 and `Record` L312-333: read only. `Data/StatusMark.cls` `Get` L39.
  - `Msg/Catalog/Watch.cls` (accepted, unchanged):
    - `digest.notCheckedUnreachable` L504, `digest.notCheckedError` L512, `digest.notCheckedStale` L546 and `digest.notCheckedStopped` L561;
    - `mcp.sourceStopped` L1044-1084.
  - `Live/Payload/Check.cls` `FromRow` L45. `/v1/state` builds the same payload (`Web/Api.cls` L1401, read only).
- **Tests and fixtures:**
  - `Test/Mcp/Mock.cls` -- `tools/call` L313-317 answers "The mock ran <tool>". Add a settable answer.
  - `Test/Mcp/Attach.cls` -- the shadow runner, `Register`, `Use`, `Leaks` and `LoggedSecret`.
  - `Test/Mcp/Ops.cls` -- `TestOnlineDemo` L206, `TestRemove` L255.
  - `Test/Checks/Queues.cls` and `QueueProbe.cls` -- the Tick seam pattern.
  - `Test/Digest/Coverage.cls` -- `Run` L579, `Slots` L594, `TestUnreachableStreak` L335.
  - `Test/Digest/Compose.cls` `TestPartOrder` L316-344; `Test/Digest/AllClear.cls` `ProbeCase.Watched` L168.

## Tasks & Acceptance

**Execution:**

The tasks are grouped as Part A (row, coverage, digest; no bridge change) and Part B (the run). This makes the split in Design Notes mechanical if the lead applies it.

- [ ] **Task 0** (implement stage). Run on lane D's warm throwaway, tag `e22s5iw`, with scratch classes `ZzT5`, which are removed afterwards. Record each answer in `_bmad-output/implementation-artifacts/evidence/22-5-task0-poll.md`:
  1. **The manager.** In TriageAgent's job, build a standalone governed `%AI.ToolMgr` (`%New`, `RegisterToolSet(ProxyToolSet())`, `Govern`) with no `BuildAgent` and no model key. Then, inside a poll context, run `ExecuteTool("call_mcp_tool", {server, tool, arguments})`. Record:
     - whether the gate and the step audit run;
     - whether a step record is written;
     - what is returned for a result, for a proxy refusal and for a gate denial.

     If the standalone manager works, use it. If it fails, use 22.4's `ProxyManager` after `BuildAgent`; then a poll on an install with no key fails (`error`). Record the error text.
  2. **The async answer.** `Checks` (PoolSize 1) sends `SendRequestAsync(Decide, request, 1, <Ref>)` and gets the Reply in `OnResponse`, with `%SessionId` the Tick's session. A second `Tick` sent while the poll waits on a silent mock (`Mock.Silence`) is handled before the poll answers. Record the timings.
- [ ] **Part A** -- `src/ocutalon/cls/OcuTalon/Data/BackgroundCheck.cls` -- append:
  - `Server` (MAXLEN 40), `Tool` (128), `Arguments` (MAXLEN "", canonical JSON) and `IntervalMinutes` (`%Integer`), storage values 16-19. Each property's doc says "a source row's; empty for every other kind".
  - Kind's doc lists `production`, `queues` and `source`.
- [ ] **Part A** -- `Watch/Ops.cls`:
  - Append `Parameter SOURCEKIND = "source"`.
  - `SetSource(sessionRef, server, tool, name, arguments, intervalMinutes, askedBy, Output ref, Output created) As %Status`, under `Lock(sessionRef)`:
    - the natural key is (SessionRef, Kind `source`, DisplayName), so a repeat updates the row and keeps its Ref;
    - `CreatedAt` is set on a new row only; `NextDueAt` is now; the run fields are emptied on a new row.
  - `RemoveSource(ref, Output fields) As %Status`: deletes only a `source` row; `fields` returns `Fields(row)` before the delete; a missing row gives "" fields and OK.
  - `SourcesOf(server) As %DynamicArray`: the Refs of a server's source rows.
  - Append a class-doc bullet.
- [ ] **Part A** -- `Mcp/Ops.cls`:
  - Two `MapItem`s, `SetSourcePoll` to `OnSetSource` and `RemoveSourcePoll` to `OnRemoveSource`. Replace the doc sentence at L3.
  - `OnSetSource` runs, in order:
    1. `Refusal`;
    2. the matrix's validation (`NAMEPATTERN` and row, tool row, `read-only`, name, arguments, interval), with the canonical JSON through `%FromJSON`/`%ToJSON` (an empty value means `{}`);
    3. under `Lock(server)`, `Watch.Ops.SetSource`;
    4. `WriteAudit("MCP", {change: source_set, server, tool, outcome: created|updated} + Common)`. If the audit fails, the row is undone (deleted if new, restored if updated) and the outcome is `not_audited`;
    5. `CheckChanged` (`SendRequestAsync("Checks", …)`, Kind `source`, DisplayName);
    6. the answer, with `Ref` set.
  - `OnRemoveSource` does the same with `RemoveSource`, `source_removed` and `Stopped` 1.
  - In `Unregister`, after the commit: `RemoveSources(server, request)`, which runs `SourcesOf`, then removes, audits and sends `CheckChanged` for each.
  - New public `SourceStopped(source, tool, server, time) As %Status`: sends `mcp.sourceStopped` to every admin session through `AdminSessions`/`Send` (it extends `Notify`).
  - New parameters: the `MESSAGE*` texts under Public text, plus `INTERVALMIN` 5, `INTERVALMAX` 1440, `NAMEMAX` 100 and `ARGUMENTSMAX` 4000.
- [ ] **Part A** -- `src/bridge/cls/OcuTalon/Bridge/Audit.cls` -- `MCPCHANGES` gains `source_set` and `source_removed`, with 22.3's call shape `change,server,tool,outcome`.
- [ ] **Part A** -- `Checks/Process.cls` -- append only the parameters `SOURCEKIND` "source", `REASONSOURCEUNREACHABLE` and `REASONNOTREADONLY` (texts under Public text), so that Coverage can name them before Part B exists.
- [ ] **Part A** -- `Checks/Coverage.cls`:
  - **The missed gap.** In `WatchRow`, the gap for a `source` row is `IntervalMinutes`×60 + `MISSEDSECONDS`; every other kind keeps `MISSEDSECONDS`.
  - **The stopped streak.** `stopped` is treated like the unreachable streak: the time is the first run of the trailing `stopped` streak.
  - **ReasonOf.** It maps `REASONSOURCEUNREACHABLE` to `unreachable` and `REASONNOTREADONLY` to `stopped`.
  - **KeyOf.** It maps `stopped` to `KEYSTOPPED` = `digest.notCheckedStopped`.
  - **The mailbox.** `Build` appends the mailbox row (`MailboxRow`, the matrix's rules, with the seam `Mark()` = `StatusMark.Get("emailPoll")` and the seam `MailOwner()` = `Channel.Email.In.Owner()`), after the background-check rows. Add `ENTRYMAILBOX` and `MAILSTALESECONDS` 900.
  - Replace the doc's "There are no source rows until step 4."
- [ ] **Part A** -- `Checks/Render.cls` -- append `KEYELSEPASSED = "checks.everythingElsePassed"` and the pure `RestKey(rows) As %String`:
  - it gives `KEYELSEPASSED` when Render's ordered rows have no `failed` row, at least one `not_checked` and at least one `passed`;
  - otherwise it gives "".
- [ ] **Part A** -- `Digest/Process.cls`:
  - When `Render.RestKey(ordered)` is not "", the checks part becomes the `lines` entries of the watched not-checked rows, in order, followed by `{key: KEYELSEPASSED}`.
  - `CatalogKey`, `AllClear` and every other part stay as they are.
  - If Task 0 finds that Telegram rebuilds the part from the rows, apply the same in `Channel/Telegram/Out.cls`.
- [ ] **Part A** -- `Live/Payload/Check.cls` -- append `IntervalMinutes` (`intervalMinutes`), which `FromRow` sets from the row (empty for other kinds).
- [ ] **Part B** -- `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `PollCall(source, Output server, Output tool, Output arguments, Output toolref, Output fingerprint) As %String`:
  - the default answers `invalid`;
  - the answer is "" or a `REASONS` word, plus `notreadonly`.
- [ ] **Part B** -- `Mcp/Attach.cls` overrides `PollCall`:
  1. The `source` row by Ref gives server, tool and arguments; no row, or another kind, gives `invalid`.
  2. The `ToolClassification` row must be `read-only`; otherwise it answers `notreadonly`.
  3. `Mcp.Proxy.Listed(server, tool, .toolref, .fingerprint)` gives the live fingerprint through 22.3's client.
- [ ] **Part B** -- `Mcp/Proxy.cls`:
  - New `Listed(server, tool, Output toolref, Output fingerprint) As %String`, sharing `Call`'s steps 1-5 through one private method (Rule 2).
  - In any `tool`-kind context (a replay or a poll), every refusal calls `Context.NoteReplayRefusal(<word>)`.
  - It still writes no row.
- [ ] **Part B** -- `src/bridge/cls/OcuTalon/Bridge/Context.cls`:
  - New `IsPoll()`: Kind `tool` and Provenance `untrusted`.
  - New `SeedMcp(server, toolref, tool, fingerprint)`: sets node `mcp` and 22.3's server-to-toolref node.
  - The `NoteReplayRefusal`/`ReplayRefusal` doc says "a replay's or a poll's".
- [ ] **Part B** -- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `replay` becomes Kind `tool` and Provenance `user`.
  - In a poll (`IsPoll`), any call whose name is not `MCPPROXY` is denied `FAILED`. A proxy call is classified and checked as 22.3 specifies. There is no grant, and the untrusted rule applies.
  - Restate the class doc.
- [ ] **Part B** -- `src/bridge/cls/OcuTalon/Bridge/Poll.cls` (new). `Run(adapter, request, superSession, Output reply) As %Status` runs:
  1. Parse Input `{"source"}`; a value that is not a Ref is a failure Reply `invalid`.
  2. Build the manager (Task 0's variant).
  3. `Context.Begin`.
  4. `PollCall`; a non-empty word ends the run with that word.
  5. `SeedMcp`.
  6. `StepBuffer.Start`.
  7. `ExecuteTool(Gate.#MCPPROXY, {server, tool, arguments})`.
  8. Build the Reply:
     - Text: the value, only when `ReplayRefusal()` is "" and the call returned a value;
     - Tainted 1 when the call ran; ToolsRun; Steps; AgentStepCount; DurationMs;
     - FailureText: "" or one word (`unreachable`, `timeout`, `failed`, `changed`, `notfound`, `demo`, `denied` for a gate denial or `ToolAccessDenied`, `notreadonly` or `invalid`).

  The context, the step buffer and any swapped manager are ended or restored on every path. The class doc states the contract.
- [ ] **Part B** -- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- in `Answer`, a tool request whose Provenance is `untrusted` goes to `Poll.Run`; every other tool request goes to `Replay.Run` as now.
- [ ] **Part B** -- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - **Admit.** A tool request with provenance `untrusted` is admitted when its Input is the JSON `{"source": <a Ref>}`. A user tool request stays a replay.
  - **RunnerFor.** A poll goes to the `decide` runner of `RUNNERS`.
  - **No Decision row.** On every path (success, a runner failure, the timer), a poll writes no `Decision` row and fires no `decision.recorded`.
  - **The answer.** A poll is answered with the runner's Reply: its Text, Tainted, Steps and FailureText, plus `DecisionRef`. A timer gives Fallback 1, FallbackReason `timeout` and FailureText `timeout`.
  - Update the docs of `Admit`, `RunnerFor` and `ConcludeTool`.
- [ ] **Part B** -- `Checks/Process.cls`:
  - **Tick.** One new Try block after the queue block calls `RunSources(tickAt)`.
  - **The appended block** (`POLLITEM` "Decide" and the log parameters, beside Part A's `SOURCEKIND` and reason parameters):
    - **`RunSources`:** takes the due `source` rows (`DueOf`, `ROWCOLUMNS` plus the new columns, read by Ref) and skips them all on the demo. For each row:
      1. Schedule: one UPDATE sets `NextDueAt` = tick + `IntervalMinutes`.
      2. If the classification (seam `SourceClass(server, tool)`) is not `read-only`, record a stopped run now through `Record(…, keep 1)`. `SourceStopped` is sent on the transition.
      3. Otherwise send the async request: kind `tool`, provenance `untrusted`, a new ItemId, OwnerRef the row's session, TraceRef, channel `system`, Summary "Source poll", Input `{"source": Ref}`, completion key the Ref.
    - **`OnResponse`:** maps the Reply to the run (see the matrix) and calls `Record(row, tickAt, runAt, result, finding, reported, items, 1)`:
      - `denied` or `notreadonly` re-reads the classification: if it is not `read-only`, the run is stopped; otherwise it is `error`;
      - the first successful run is the baseline;
      - a new answer (SHA-256 hex not in `seen`) becomes one Item through `SourceItem`;
      - `Reported` is `{"seen": [newest 50], "baseline": 1, "stopped": ""|"not_read_only"}`.
    - The row is published as a `check` event (`Record` does it).
- [ ] **Part B** -- `Test/Mcp/Mock.cls` -- `Answer(port, text)` sets the `tools/call` text for `zz_lookup`, and `Stop` clears it.
- [ ] Tests (every matrix row; hermetic `Register`/`Leaks`; one class per call):
  - `Test/Mcp/SourceSet.cls` (new; McpOps with its seams) -- Set, Update, every Refused row, Remove, Server removed, demo, audit-failure undo, `CheckChanged` sent.
  - `Test/Mcp/SourceRun.cls` (new; shadow runner, mock and production on the warm stack):
    - the Due, first run, New result, Seen before, Server down and No longer read-only rows;
    - a changed tool cleared through `ClassifyMcp` and then stopped;
    - no model request in the CI mock's log for the poll, and one decide request for the new Item;
    - no `Decision` row; the step label; the `MCP` `called` entry;
    - the no-secret, no-URL and no-argument scan of messages, logs, audit and step labels (`LoggedSecret`).
  - `Test/Bridge/Poll.cls` (new) -- Admit (poll accepted, malformed refused, user tool unchanged), RunnerFor, the Gate poll rules (only the proxy, no grant, untrusted), no Decision row on the success and timer paths, the bridge-alone default `invalid`.
  - `Test/Bridge/Gate.cls` -- replay rows unchanged; a poll context denies a non-proxy call.
  - `Test/Checks/Render.cls` -- the `RestKey` rows (none failed with some not checked and some passed; a failed row; nothing passed; all passed).
  - `Test/Digest/Coverage.cls` -- the source interval gap, the stopped streak, the reason map rows and the Mailbox rows.
  - `Test/Digest/Compose.cls` -- `TestNotCheckedLead`, the fixture: source "Jira" with unreachable `CheckRun` rows from 02:10 local, the others passed. It pins the exact rendered text, AllClear 0 and that neither "Everything I checked passed." nor "Your IRIS system is healthy" appears. `TestPartOrder` is unchanged.
  - `Test/Mcp/Ops.cls` -- `TestRemove` asserts the sources are removed; `TestOnlineDemo` adds both verbs.

**Acceptance Criteria:**
- Given a source-poll command for a tool classified Read-only, when `McpOps` handles it, then one `BackgroundCheck` row of Kind `source` exists, owned by the command's admin session, with the tool, its canonical arguments and its interval. A tool that isn't Read-only is refused with `not_read_only` and writes nothing. Mutation: skip the classification check → `TestSetRefusedNotReadOnly` red.
- Given a due source poll, when `Checks` runs it on the Tick, then a `tool` request goes through `Decide`, and the runner runs `call_mcp_tool` with no model. The gate, the step audit (step "Running zz_lookup on zz") and the `MCP` `called` audit entry apply. Mutation: route the poll to the native tool → red (`TestPollRuns`: no `MCP` entry).
- Given a poll's answer not seen before (after the baseline), when it is recorded, then exactly one untrusted Item reaches `Intake` and gets an attention decision (the Integration AC: Intake consumes it, and one decide request appears in the model mock's log). The same answer again sends nothing. Mutation: skip the `seen` check → `TestSeenBefore` red.
- Given each run, when it is recorded, then the row's `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId` (the Tick's session) and `NextDueAt` (tick + interval) are set, one `CheckRun` row is written, and a `check` event carries `kind` `source` and `intervalMinutes`.
- Given a source whose tool was classified Risky, when it is next due, then no request reaches the mock, the run is `not_checked` with Reason `stopped`, every admin gets one `mcp.sourceStopped` (none on the next stopped run), and the digest line is `digest.notCheckedStopped`. Mutation: send the notice on every stopped run → red.
- Given the step 4 test (the mock down since 02:10 local in the fixture runs, everything else passed), when the digest is composed, then its parts lead the checks part with `digest.notCheckedUnreachable` {entry "Jira", time 02:10} and `checks.everythingElsePassed`. The text renders "Not checked: Jira (unreachable since 02:10). Everything else I checked passed.", and `AllClear` is 0. Mutation: keep `checks.notEverythingRestPassed` → `TestNotCheckedLead` red.
- Given the mailbox owner's session and an `emailPoll` mark with `ok` 0 and the unreachable reason, when coverage is built, then the Mailbox row is `digest.notCheckedUnreachable`. With `ok` 1 and a recent `at`, the row is passed. Mutation: list the mailbox as passed whatever `ok` says → red.
- Given an online-demo install, when either verb arrives or a Tick runs, then the verb answers `not_allowed`, no `source` row is written or run, and the demo path, `Test.Bridge.Gate` and the replay tests are unchanged.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-1: commands; `web_admin` only.
- AD-2: the bridge names no host class (`PollCall` is an extension).
- AD-4: ownership.
- AD-5: no state in memory.
- AD-6: `tool` request kind, "from step 4, a source poll"; no model; throwaway.
- AD-10: the gate, untrusted provenance, taint, the fingerprint at call time.
- AD-17: one audit writer.
- AD-18: `BackgroundCheck`, the source row type, `Checks` the run writer, `CheckRun`, the coverage rules.
- AD-21: "Source polls call `call_mcp_tool` through a `tool` request to `Decide`".
- AD-25: the demo.
- AD-28: the all-clear only from `Render`.
- AD-29: lanes.
- AD-30: untrusted items to `Intake`.
- AD-31: extensions.
- AD-32: notices are catalog keys.
- AD-33: one owner per table; `Checks` is the one publisher of `check`.

No AC contradicts an AD's Rule. AD-10 is silent on polls, so S19 below records the rule.

**Decided in-stage:**
1. **A result is the tool's whole text answer.** One new answer becomes one Item, de-duplicated by its SHA-256 against the newest 50 seen. The other readings were one Item per content part, or per JSON array element. Per part would need 22.3's proxy to return parts and would gain nothing for single-part tools such as the Jira example. 22.6 can document it.
2. **The first successful run is a baseline.** It records what it saw and sends no Item, as a production watch does (AD-18), so setting up a source does not flood the decisions.
3. **The poll runs on TriageAgent.** That is the `decide` runner. ChatAgent would queue polls behind users' turns. There is no new production item.
4. **The call map comes from a live listing.** The listing goes through OcuTalon's client (`PollCall` → `Proxy.Listed`) in the runner job, so `ClassifyMcp` clears a changed tool exactly as a turn's map does (22.8). The proxy then re-lists before `tools/call`, which costs one extra `tools/list` per poll (2 s bound). The other options were seeding the stored fingerprint (a changed tool would never be cleared) or AI Hub's listing (the hang residual).
5. **The request carries the source's Ref only.** Arguments stay in the row and never travel in a message.
6. **Polls are asynchronous.** `OnResponse` records them, so a silent server never blocks the Tick's production checks. A synchronous send could hold `Checks` past `MISSEDSECONDS` and mark watches missed. `NextDueAt` advances at the send.
7. **No `Decision` row for a poll.** It is no decision, it calls no model, and a row per poll would inflate `RunCost`'s decisions count (`Ownership` L1241).
8. **A stopped source keeps recording.** It records a not-checked run at each interval (Reason `stopped`) and calls nothing, so the digest says why. It resumes by itself once the tool is Read-only again.
9. **The limits.** The interval is 5 to 1,440 minutes and the arguments at most 4,000 characters, with no `secret://` or `@{`. The natural key is (session, `source`, name). The mailbox counts as stale after 900 s.
10. **Any admin may remove any source.** A source belongs to the session that set it, for its Items and its digest.
11. **Removing a server removes its sources.**
12. **The digest lead.** It applies only when nothing failed, so the failed case keeps its pinned wording (UX L788). The duplicate line in the coverage list below matches the failed case's pattern.
13. **No split inside this spec, but one is recommended (below).**

**Split recommendation (for the lead, at the spec gate; product default 6).** The story touches about 17 source files.
- **Part A** keeps 22.5 and can ship alone: the row, the verbs, coverage with the mailbox, the digest lead, the payload member. Its tests use `CheckRun` fixtures, and a source with no runs reads "didn't run", which is honest.
- **Part B** would be a new story, 22.11 "Run source polls through the governed proxy": the bridge's poll, the run, the Items and the stop.

The tasks are labelled for this split.

**Extend, don't copy (Rule 2):**
- `Poll.Run` follows `Replay.Execute`'s shape but runs no approval steps, so it is a separate class rather than a branch: the approval gate (`StartExecution`) must never apply to a poll.
- `Proxy.Listed` shares `Call`'s prefix. `SourceStopped` extends `Notify`/`Send`. `SetSource` follows `OnStart`.
- The run reuses `DueOf`, `Record`, `SendOwn` and `Announce`. The coverage reuses `WatchRow`'s streak, and the mailbox reuses `Add`.

**Integration ACs (Rule 1):** these are new:
- `Bridge.Poll`, `McpServersClass.PollCall`, `Watch.Ops.SetSource`/`RemoveSource`/`SourcesOf`, `Mcp.Ops.SourceStopped`, `Render.RestKey`, `Coverage.MailboxRow` and the `intervalMinutes` member.

Their consumers in this story are real:
- `Checks` → `Decide` → TriageAgent → `Intake`, which produces an ItemDecision (AC 3);
- `Digest` → `DigestText`, which produces the rendered sentence (AC 6);
- `McpOps` → `Checks`, which publishes the `check` event (AC 4).

**Consumes:**
- 22.2: the rows and the read-only classification.
- 22.3: `call_mcp_tool`, `Proxy`, `Client.ListTool`, `McpToolref` and the `MCP` audit.
- 22.4: `ProxyManager`, `NoteReplayRefusal` and `Attach.Toolref`. The hold path is not used: a poll is never held.
- 22.8: `ClassifyMcp` and `ClearChanged`.
- 22.9: the bounds.
- 17.5-17.7: coverage and the digest.
- 21.2: the `emailPoll` mark.
- 35.1/35.2: the verbs and the accepted keys.

**Consumed-by:**
- 21.5 (Lane B): the Settings form submits both verbs, and the rail renders a source's schedule from `intervalMinutes`.
- 22.6: documents polls, whole-answer results, the baseline and the stop.
- 22.10: keeps `PollCall`'s listing on OcuTalon's client.

**Contended edits (for the lead to route before implement):**
- `Mcp/Ops.cls` (Epic 21, lane C) -- **non-append changes, so they go to the orchestrator:**
  - two `MapItem`s inside `MessageMap`;
  - the class-doc sentence at L3 replaced;
  - one call inserted in `Unregister` after the commit, where 22.4 also inserts.

  Everything else is appended methods and parameters.
- `Checks/Process.cls` and `Data/BackgroundCheck.cls` (Story 36.1, plain-union ruling):
  - `Process`: one Try block inserted in `Tick` and a class-doc bullet; the rest is an appended block plus `OnResponse`;
  - `BackgroundCheck`: appended properties and storage values 16-19.
- `Checks/Coverage.cls` and `Checks/Render.cls` (Checks plain-union):
  - `Coverage`, non-append: `WatchRow`'s gap and streak, two `$Case` arms, one call in `Build`, one doc line;
  - `Render`: append only.

**Ledger inbox (Rule 17):** (none). DW-1210 and DW-1211 belong to 22.10, not here.

**Residual for the lead to route:** `Data.Precedent.KeyFor` (Lane B) has no key form for a poll Item (channel `system` without `Slots.production` gives ""). AD-21 names "the source for … polls", so precedents do not yet learn from source Items. Suggested owner: a Lane B story; this goes through the lead, never this stage.

**Spine updates for the lead (Rule 20):**
- S19 (AD-6 and AD-10): a `tool` request with provenance `untrusted` is a source poll:
  - its Input is `{"source": Ref}`, and it runs on the `decide` runner;
  - it runs exactly one `call_mcp_tool` on a governed proxy-only manager, with the map seeded by `PollCall`;
  - the gate admits only the proxy, with no grant and the untrusted rule;
  - there is no Decision row or event, and the Reply carries the answer text and a reason word.
- S20 (AD-31): `McpServersClass.PollCall`, default `invalid`.
- S21 (AD-18): the source columns; async runs; whole-answer results with a baseline; stopped runs with one `mcp.sourceStopped`; the `CheckRun` Reason `stopped`; the gap of interval + 180 s; the Mailbox entry from `emailPoll`; sources removed with their server.
- S22 (AD-28): `Render.RestKey` and the digest's not-checked lead.

## Veto items

1. **Stored columns.** `OcuTalon.Data.BackgroundCheck` gains `Server`, `Tool`, `Arguments` (the admin's JSON; never a secret: `secret://` and `@{` are refused) and `IntervalMinutes`, appended to the default storage. There is no new table, and retention is unchanged (rows live until removed; `CheckRun` keeps AD-27's purge).
   - Online demo: never written.
2. **A stored value.** `Digest.Data.CheckRun.Reason` gains `stopped`.
   - Online demo: never written.
3. **Outward actions.** Each due poll sends one `tools/list` (the seed) and then the proxy's `initialize`, `tools/list` and `tools/call` to an admin-registered server, every 5 to 1,440 minutes, bounded at 2/2/2/20 s.
   - Online demo: none (no row; `MCPDEMO`).
4. **Security posture.**
   - A poll runs with provenance `untrusted`, so only a Read-only tool runs, and it is never held.
   - The answer text is stored in the Reply message and the Item, as an email's body is (untrusted).
   - Arguments are only in the row, never in a message, log or audit entry.
   - Online demo: unchanged.
5. **An access rule.** Any admin may set or remove a source (origin `web_admin`). A source's Items and digest entry belong to the session that set it.
   - Online demo: refused.
6. **Notices.** The accepted `mcp.sourceStopped` goes to every admin session on a stop.
   - Online demo: never sent.
7. **Bridge request semantics and the extension (S19, S20).**
   - Online demo: no change.
8. **A live payload member.** The `check` event and `/v1/state` gain the optional member `intervalMinutes`.
   - Online demo: empty for every row.
9. **An AC part moved (veto window 7 and 8).** "So the page shows the source's schedule" needs a `source` branch in Lane B's `web/src/app/rail/rail-view.ts`.
   - This story already delivers the generic last run and result (L244-263) and publishes `nextDueAt` and `intervalMinutes`.
   - Proposed: a `DW-n` bullet on Lane B's Story 21.5 to render "Polled every {n} minutes" (text below, for 21.5's approval). Alternative: a ruled lane exception like 22.4's R1, a plain union with Epic 23's rail work.
   - Online demo: no sources.
10. No new route, privilege, role, grant, resource, production item, retention or web dependency.

## Public text

**New (needs approval):**

| File / parameter | Where it shows | Text |
| --- | --- | --- |
| `Checks/Process.cls` `REASONSOURCEUNREACHABLE` | a source's finding (rail, coverage row) | "Couldn't reach its MCP server" |
| `Checks/Process.cls` `REASONNOTREADONLY` | a stopped source's finding | "Its tool is no longer Read-only" |
| `Checks/Coverage.cls` `ENTRYMAILBOX` | the digest's coverage entry | "Mailbox" |
| `Mcp/Ops.cls` `MESSAGENOTREADONLY` | the Settings answer (21.5) | "Only a Read-only tool can be a source. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGESOURCENAME` | the Settings answer | "A source's name is 1 to 100 characters. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGESOURCEARGUMENTS` | the Settings answer | "A source's arguments must be a JSON object of up to 4,000 characters, with no secret in it. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGESOURCEINTERVAL` | the Settings answer | "A source is polled every 5 to 1,440 minutes. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGENOSOURCE` | the Settings answer | "There is no source with that reference. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGESOURCEREMOVED` | the Settings answer | "The source was removed." |
| (for 21.5, not shipped here) the rail's `checkScheduleSource` | the rail | "Polled every {n} minutes" |

**Existing, reused:**
- **From UX/PRD:** EXPERIENCE.md L173 and L611, UX-DR106 and UX-DR122: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed.", built from `digest.notCheckedUnreachable` and `checks.everythingElsePassed`.
- **From 35.1** (accepted, planner-2026-11-09-35.1): `mcp.sourceStopped` and `digest.notCheckedStopped`.
- **Already in use:**
  - `digest.notCheckedError`, `digest.notCheckedStale` and `digest.notCheckedTimeout`;
  - `REASONTIMEOUT` "No answer in time" and `REASONREAD` "Couldn't be read";
  - `MESSAGESAVED` "Saved", `MESSAGENOSERVER` and `MESSAGENOTOOL`;
  - `CommandsIn`'s refusal texts;
  - 22.3's step label "Running {tool} on {server}" and its `MCP*` refusals.
- **Not product text:** the Item's Subject is the admin's own source name.

**Findability (proposed, not decided):** no More to try item, because the feature is admin-only, MCP is off on the online demo, and there is no UI until 21.5. Story 22.6 carries the public explanation and could add a "New since 1.0.0" line beside its worked Jira example.

## Verification

Each `ci/iris.sh` call carries the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Check `ci/warm.sh status` first.
- Run `OCUTALON_RUN_TAG=e22s5iw ci/warm.sh up` once, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s5iw` on each class call.
- Run `ci/warm.sh down` at the end, even after a failure.
- One class per foreground call, with `timeout: 600000`; each must finish inside about 150 s.
- Never two `iris_execute_tests` calls in one message. Pass `server` `ocutalon-slot-d` and `namespace` `OCUTALON` on every IRIS MCP call.

**Commands:**
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.SourceSet` -- expected: `CLASS … passed`
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.SourceRun` -- expected: passed (warm stack, production)
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Poll` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Gate` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Decide` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Ext` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Ops` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Proxy` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Checks.Queues` -- expected: passed (the Tick is unchanged for queues)
- (loop) `ci/iris.sh class OcuTalon.Test.Checks.Runs` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Checks.Render` -- expected: passed (`RestKey` rows added here)
- (loop) `ci/iris.sh class OcuTalon.Test.Digest.Coverage` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Digest.Compose` -- expected: passed (`TestPartOrder` unchanged)
- (loop) `ci/iris.sh class OcuTalon.Test.Digest.AllClear` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Digest.TelegramText` -- expected: passed
- (loop) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-ci-config.sh` -- expected: exit 0

There are no `(once)` lines. CI runs the full suite, and the lead runs Rule 19's fresh-environment check.

**CI:** new_units: none. There is no new live unit and no new group. The new classes join existing shard pieces:
- `Test.Mcp.*` in `shard:lane-a@rest` (group `shards-2`, about 1,636 s of units planned against the 32-minute cap of 1,920 s, so about 280 s of headroom; this story adds about 60 to 120 s (inference));
- `Test.Bridge.Poll` in `shard:lane-a@Bridge` (`shards-9`, about 1,665 s planned, so about 255 s of headroom);
- the `Test.Digest` methods in `shard:lane-a@Install,Digest,Eval` (`shards`, a few seconds).

**Shared surfaces:**
- the `BackgroundCheck` columns;
- the `check` payload's members;
- `MCPCHANGES`;
- the `CheckRun` Reason values;
- the coverage rows, now with the Mailbox entry (tests that count rows: `Test.Digest.*`);
- the digest's checks part in the not-checked case;
- `Decide.Admit`'s tool rule;
- the gate's `replay` rule;
- `Ext.McpServers` (`Test.Bridge.Ext`);
- the mock's `tools/call` answer;
- `Ownership.AdminSessions` notices.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19):**

| Mutation | Test that goes red |
| --- | --- |
| Skip the read-only check in `OnSetSource` | `TestSetRefusedNotReadOnly` |
| The poll calls the native tool, or bypasses the gate | `TestPollRuns` |
| Skip the `seen` check | `TestSeenBefore` |
| Send the stop notice on every stopped run | `TestStoppedNotifiesOnce` |
| Keep `checks.notEverythingRestPassed` in the lead | `TestNotCheckedLead` |
| A source keeps the 180 s gap | `TestSourceIntervalGap` |
| Mailbox passed whatever `ok` says | `TestMailboxUnreachable` |
| A poll writes a Decision row | `TestPollNoDecisionRow` |
| The gate requires a grant in a poll | `TestPollNoGrant` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
