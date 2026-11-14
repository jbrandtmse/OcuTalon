---
title: 'Story 22.5: Poll a read-only MCP tool as a source'
type: 'feature'
created: '2026-11-14'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
warnings: ['oversized']
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


**Scope of this story (Part A, Contest Planner ruling C, 2026-11-12; epics.md 22.5 `[AMENDED 2026-11-14]`).** The intent block above is preserved verbatim and is shared with Story 22.11. This story delivers its matrix rows **Set, Update, Refused, Remove, Server removed, Mailbox and Digest lead**, the coverage side of **Server down** and **No longer read-only** (the digest line that a recorded run gives), and the McpOps half of the **Online demo** rule. The run, the Items, the stop and the bridge belong to Story 22.11 (Design Notes, "Moved to 22.11"). No `source` row is run in this story: `Checks` reads only `production` and `queues` rows (`DueOf`), so a source shows as "didn't run" until 22.11.

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/` or `web/`. Line numbers are at `6d36d945` (after 22.4, 21.4, 22.7, 22.3, 22.9).

- **The command side:**
  - `Mcp/Ops.cls` (22.4's and 21.4's edits merged):
    - class doc L1-28; L3 says it has no handler for the source verbs, so `CommandsIn` answers `failed` (DW-1137).
    - `MESSAGE*` L47-65; `MessageMap` L72-85 (three `MapItem`s).
    - `OnClassify` L134-149 is the handler shape: `Refusal`, `Lock(server)`, Try, `Lock -`.
    - `Unregister` L190-225: TSTART L203, row deletes and `Revoke`, `WriteAudit` and TROLLBACK on failure, TCOMMIT L215, then 22.4's `CancelPending` L221, 21.4's `DropEntry(stored)` L222, `Set restart = 1` L223. `stored` (L196) is the row's own name (`NameGetStored`).
    - `Classify` L302-324: validate, save, audit, undo.
    - `Refusal` L586-601 (21.4's rule, reused unchanged): not the sender `CommandsIn`, origin not `web_admin`, origin `tool` or `Bridge.Context.Active()`, or an empty `ActingUser` gives `not_allowed` with `CommandsIn` `MESSAGENOTFROMTOOL` or `MESSAGEADMINONLY` and one warning; the online demo (`OnlineDemo()` L677) gives `not_allowed` with `MESSAGENOTALLOWED`.
    - `Lock` L610; `McpData` L617; `Common` L639; `Answer` L647 (no `Ref` argument); `Failed` L658; the seams `OnlineDemo` L677, `AdminSessions` L683, `Notice` L689, `Restart` L695, `WriteAudit` L701.
  - `Watch/Ops.cls`:
    - `KIND` L29, `QUEUEKIND` L32, `FIELDS` L64, `CHECKS` L67, `LOGCHANGED` L69.
    - `OnStart` L84-128 is the row-write pattern (lock, natural key, `%Save`, answer).
    - `Fields` L222; `Changed` L235 and `SendChanged` L256 are instance methods of WatchOps' own item, so McpOps cannot call them.
    - `RefOf` L264-276 (one SQL branch per kind's natural key); `Lock` L279 (`^OcuTalon.Watch(sessionRef)`); `Answer` L286 (with `ref`).
  - `Data/BackgroundCheck.cls`: `Kind` doc L15; `Reported` L45; the `RecordRun` trigger L52-55; storage values 1-15.
  - Read only: `Msg/Command/SetSourcePoll.cls` L6-21 (`Server` 40, `Tool` 128, `Name` 100, `Arguments`, `IntervalMinutes`, `ActingUser`), `RemoveSourcePoll.cls` L6-9 (`SourceRef`, `ActingUser`), `Msg/CommandResult.cls` `Ref` L15, `Core/CommandsIn.cls` routes L364-365, `Checks/Msg/CheckChanged.cls`.
  - `Mcp/Server.cls` `NAMEPATTERN` L12; `Mcp/ToolClassification.cls` `CLASSIFICATIONS` L17, `Tool` EXACT collation L23, `ServerToolIndexOpen`.
- **The audit:** `src/bridge/cls/OcuTalon/Bridge/Audit.cls`: doc L4-5 and L35-36; `SHAPEMCPCALL` L37; `MCPCHANGES` L46; `CALLCHANGES` L49; the outcome rule (one lower-case word, at most 24 letters) L85.
- **The checks side:**
  - `Checks/Process.cls`: `REASON*` L151-159. `Due` L507 and `DueOf` L876 select one Kind, so no `source` row runs. `Changed` L811-831 publishes `Live.Payload.Check.FromRow(row)` for a start and a stopped payload from the message's fields. Append parameters only, at the end of the class.
  - `Checks/Coverage.cls`:
    - doc L1-27 (L4: "There are no source rows until step 4."); `MISSEDSECONDS` L41; `KEY*` L89-105; `KIND` L108; `NOTCHECKED` L111.
    - `Build` L128-162: the background-check loop L152-160, after which the mailbox row goes.
    - `Add` L179; `WatchRow` L273-333: the gap comparison L306, the unreachable streak L316-324.
    - `EntryOf` L386 (any non-production kind is its `DisplayName`); `ReasonOf` L463-468; `KeyOf` L470-474; `RecordRun` L479-490.
  - `Checks/Render.cls`: `KEY*` L17-26; `Build` L46-78 orders failed, then not checked, then passed; `Row` L81-95.
- **The digest:**
  - `Digest/Process.cls`: doc L28-37 (the parts list); `Finish` L488-560, the checks part at L516; `Verdict` L573-601 (Render's `ordered` at L580); `Joined` L669; the `Rows` seam L680.
  - Read only: `Channel/DigestText.cls` renders the parts up to the first `AFTERLINES` key, then the `lines`, then the rest, one piece per line. `Channel/Telegram/Out.cls` L192-193 renders a digest through `DigestText`, so nothing there rebuilds the checks part and it needs no change.
  - Read only, the mailbox: `Channel/Email/In.cls` `Owner()` L91 (`email.owner`, a SessionRef); `Channel/Email/Adapter.cls` `MARK` L47, `REASONUNREACHABLE` L54, `Record` L382-401 (`{at, ok, reason, lastOkAt}`); `Data/StatusMark.cls` `Get` L39.
  - Read only, the catalog (`Msg/Catalog/Watch.cls`): `checks.everythingElsePassed` L70, `digest.notCheckedUnreachable` L504, `digest.notCheckedError` L512, `digest.notCheckedStale` L546, `digest.notCheckedStopped` L561.
- **The payload:** `Live/Payload/Check.cls`: `Finding` L33, then `TraceHeaderId` L36; `FromRow` L45-63. `/v1/state` builds rail checks with `FromRow` (`Web/Api.cls` L1458, read only).
- **Tests and fixtures:**
  - `Test/Mcp/OpsProbe.cls` (doc L1-9, seams L48-86); `Test/Mcp/Ops.cls`: `TestOnlineDemo` L215, `TestOnlineDemoRealFlag` L236, helpers `Run` L776, `MakeServer` L822, `MakeTool` L830, `MakeAdmin` L842, `Clean` L984.
  - `Test/Digest/CoverageProbe.cls` (the seam subclass); `Test/Digest/Coverage.cls`: `TestReasonMap` L315, `TestUnreachableStreak` L335, `Run` L579, `Slots` L594.
  - `Test/Digest/Compose.cls` `TestPartOrder` L322; `Test/Checks/Render.cls`; `Test/Bridge/Audit.cls` `TestMcpCallShape` L67.
  - `Test/Eval/Watch.cls` `TestFields` L139: `FIELDS` must name every stored property. `Test/Eval/Report.cls` `TestWatchEveryField` L865: its value table (L878) needs a value for every `FIELDS` name.
- **Lane B pins** (the lane exception in Design Notes):
  - `Test/Data/Tables.cls` L555-576: the `BackgroundCheck` contract.
  - `Test/Live/Payloads.cls` L1278-1293: the `Payload.Check` contract.
  - `web/src/app/live/payloads.ts` L345-359 `CheckPayload` is generated by `web/scripts/payloads.mjs`. Its `--check` runs in `npm run build` (`web/package.json` L13). `web/scripts/payloads.test.mjs` L119 requires `traceNamespace` then `traceUrl` last.

## Tasks & Acceptance

**Execution:**

- [ ] `src/ocutalon/cls/OcuTalon/Data/BackgroundCheck.cls`:
  - Append `Server` (`%String`, MAXLEN 40), `Tool` (MAXLEN 128), `Arguments` (MAXLEN "", the admin's JSON) and `IntervalMinutes` (`%Integer`), as storage values 16-19.
  - Each property's doc says "a source row's; empty for every other kind". The `Kind` doc lists `production`, `queues` and `source`.
- [ ] `src/ocutalon/cls/OcuTalon/Watch/Ops.cls` (the row methods; AD-18's one creator class):
  - Append `Parameter SOURCEKIND = "source"`, and append `Server,Tool,Arguments,IntervalMinutes` to `FIELDS`.
  - Extend `RefOf` with a `source` branch, whose natural key is (SessionRef, Kind, DisplayName).
  - Add `SetSource(sessionRef, server, tool, name, arguments, intervalMinutes, askedBy, Output ref, Output created) As %Status`. It follows `OnStart`'s pattern, under `Lock(sessionRef)`:
    - a repeat of the natural key updates that row and keeps its Ref;
    - a new row gets a new Ref, `CreatedAt` now and empty run fields;
    - every save sets `NextDueAt` to now.
  - Add `RemoveSource(ref, Output fields) As %Status`:
    - it deletes only a row of Kind `source`, under `Lock` of its session;
    - `fields` is `Fields(row)` read before the delete;
    - a missing row, or another kind, gives "" fields and OK.
  - Add `SourcesOf(server) As %DynamicArray`: the Refs of that server's `source` rows, in ID order.
  - Add a class-doc bullet: the source row (AD-18), created and removed only through these methods, which McpOps calls.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Audit.cls`:
  - Append `source_set,source_removed` to `MCPCHANGES` and to `CALLCHANGES`, so that they take `SHAPEMCPCALL` (`change,server,tool,outcome`).
  - Restate the docs at L4-5 and L35-36: the call shape is "a proxy call, or a source set or removed by McpOps".
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` (after 22.4's and 21.4's lines; Design Notes, edit order):
  - **The map and the doc.** Add two `MapItem`s: `SetSourcePoll` to `OnSetSource` and `RemoveSourcePoll` to `OnRemoveSource`. Replace the L3 sentence with one bullet for each verb.
  - **`OnSetSource`** runs, in order:
    1. `Refusal(request, "SetSourcePoll")`;
    2. the session: a `SessionRef` that is empty or has no `Data.Session` row answers `failed` (CommandsIn `MESSAGEFAILED`), with one warning;
    3. the server: it must match `NAMEPATTERN` and have a row, else `not_found` `MESSAGENOSERVER`;
    4. the tool: it must have a `ToolClassification` row, else `not_found` `MESSAGENOTOOL`; its classification must be `read-only`, else `not_read_only` `MESSAGENOTREADONLY`;
    5. the name, trimmed: it must be 1 to `NAMEMAX` characters with no control character, else `bad_name` `MESSAGESOURCENAME`;
    6. the arguments: "" means `{}`. Otherwise they must parse to a JSON object, whose `%ToJSON()` text is at most `ARGUMENTSMAX` characters and holds neither `secret://` (in any letter case) nor `@{`, else `bad_arguments` `MESSAGESOURCEARGUMENTS`;
    7. the interval: a whole number from `INTERVALMIN` to `INTERVALMAX`, else `bad_interval` `MESSAGESOURCEINTERVAL`;
    8. under `Lock(server)`, in one transaction (`Unregister`'s pattern): `Watch.Ops.SetSource` with the server row's stored name, the normalised arguments and `AskedBy` the `ActingUser`, then `WriteAudit("MCP", {change: source_set, server, tool, outcome: created|updated} + Common)`. An audit failure rolls back and answers `not_audited`;
    9. after the commit, `Changed(ref, sessionRef, 0, "source", displayName)`;
    10. the answer: Ok, outcome `saved`, `MESSAGESAVED` and the row's `Ref`. `Answer` gains an optional `ref`, as `Watch.Ops.Answer` has.
  - **`OnRemoveSource`** runs `Refusal`, then opens the row by `SourceRef`. No row, or another kind, answers `not_found` `MESSAGENOSOURCE`. Then, under `Lock` of the row's server, in one transaction: `Watch.Ops.RemoveSource`, then the audit `source_removed` (outcome `removed`). An audit failure rolls back and answers `not_audited`. After the commit it calls `Changed(ref, owner, 1, "source", displayName)` and answers Ok, `removed`, `MESSAGESOURCEREMOVED`.
  - **`RemoveSources(server, request)`** (private): for each Ref from `SourcesOf(server)`, it removes the row and audits it (`source_removed`, in the remover's name) in its own transaction, then calls `Changed`. A failure is one warning and leaves that source. `Unregister` calls it between L222 (`DropEntry`) and L223.
  - **`Changed(...)` and the seam `SendChanged(message)`**: the `CheckChanged` (Kind `source`, empty Namespace and Production), sent with `..SendRequestAsync(..#CHECKS, message)`. A failed send is one warning.
  - **New parameters:** the five `MESSAGE*` under Public text; `CHECKS` "Checks"; `INTERVALMIN` 5, `INTERVALMAX` 1440, `NAMEMAX` 100 and `ARGUMENTSMAX` 4000.
- [ ] `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- append only `SOURCEKIND` "source", `REASONSOURCEUNREACHABLE` and `REASONNOTREADONLY` (texts under Public text), each with a doc line naming Story 22.11 as their run's writer.
- [ ] `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls`:
  - **The gap.** In `WatchRow`, a `source` row's gap is `IntervalMinutes`×60 + `MISSEDSECONDS`. Every other kind, and a source with no interval, keeps `MISSEDSECONDS`.
  - **The stopped streak.** `KeyOf` maps `stopped` to the new `KEYSTOPPED` (`digest.notCheckedStopped`). Its time is the first run of the trailing streak of `stopped` runs, as for unreachable.
  - **The reasons.** `ReasonOf` maps `REASONSOURCEUNREACHABLE` to `unreachable` and `REASONNOTREADONLY` to `stopped`.
  - **The mailbox.** After the background-check loop, `Build` adds `MailboxRow(sessionRef, fromUtc, toUtc, rows, lines)`. It uses `Add`, and the private seams `Mark()` (`StatusMark.Get(Channel.Email.Adapter MARK)`) and `MailOwner()` (`Channel.Email.In.Owner()`). There is no row unless `MailOwner()` is the session and the mark is not "". Its rules:
    - passed when `ok` is 1, `fromUtc` ≤ `at` ≤ `toUtc`, and `at` is at most `MAILSTALESECONDS` before `toUtc`;
    - `digest.notCheckedStale` {entry, time `at`} for any other mark with `ok` 1 (finding `FINDINGSTALE`);
    - `digest.notCheckedUnreachable` {entry, time `lastOkAt`, else `at`} when `ok` is 0 with the adapter's `REASONUNREACHABLE` (finding the mark's reason);
    - `digest.notCheckedError` {entry, time `at`} for `ok` 0 with any other reason, and {entry, time now} for a mark that cannot be read.
  - Add `ENTRYMAILBOX` and `MAILSTALESECONDS` 900. Replace the doc's L4 sentence, and describe the source gap, `stopped` and the mailbox.
- [ ] `src/ocutalon/cls/OcuTalon/Checks/Render.cls`:
  - Append `KEYELSEPASSED = "checks.everythingElsePassed"`.
  - Append the pure `RestKey(rows) As %String` over Render's output rows. It gives `KEYELSEPASSED` when no row is `failed`, at least one is `not_checked` and at least one `passed`. Anything else gives "", and it never throws. Add a doc bullet.
- [ ] `src/ocutalon/cls/OcuTalon/Digest/Process.cls`:
  - Add the private `Lead(rows, lines, vitals) As %DynamicArray`. Over the watched rows (those after the vitals), when `Render.RestKey` of Render's ordered rows is not "", it returns the `lines` of the watched rows that Render classes `not_checked`, in row order. Otherwise it returns [].
  - In `Finish`, when `Lead` is not empty, the checks part (L516) becomes those lines followed by `{key: KEYELSEPASSED, slots: {}}`.
  - `CatalogKey`, `AllClear`, `Verdict`, the eval path and every other part stay unchanged. Restate doc item 3.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Check.cls` -- add `IntervalMinutes` (`%Integer`, `%JSONFIELDNAME = "intervalMinutes"`) right after `Finding`, so the generated interface keeps `traceUrl` last. `FromRow` sets it from the row, which leaves it empty for other kinds.
- [ ] **Lane exception (routed by the lead before implement; Design Notes).** Without a recorded ruling in `## Spec Change Log`, implement stops with `## Clarification Needed`, as the intent's Never rule says. With it:
  - `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls`: the `BackgroundCheck` contract gains the four properties;
  - `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`: the `Payload.Check` contract gains `"IntervalMinutes": "%Integer(%JSONFIELDNAME=intervalMinutes)"`;
  - `web/src/app/live/payloads.ts`: regenerated with `node web/scripts/payloads.mjs`, which adds the one generated line `intervalMinutes?: number;`.
- [ ] Tests (every matrix row this story owns; hermetic fixtures, removed after each test; one class per call):
  - **`Test/Mcp/OpsProbe.cls`:** add a `SendChanged` seam that records each `CheckChanged` in `^||ZzOps("changed", n)` and sends nothing.
  - **`Test/Mcp/SourceSet.cls` (new),** through the probe's shadow handler with sender `CommandsIn`:
    - `TestSet` and `TestUpdate`: the row's values, the Ref kept, one `CheckChanged` each, and the `MCP` audit entry `source_set` `created`/`updated`, with no argument in it;
    - `TestSetRefusedNotReadOnly`: risky and unclassified tools;
    - `TestSetRefused`: each other refusal row, plus the unknown session; each writes no row, no audit entry and no `CheckChanged`;
    - `TestRemoveSource`, including another admin's removal and `not_found`;
    - `TestServerRemovedRemovesSources`: audit order `removed`, then `source_removed`, and another server's source untouched;
    - `TestSourceAuditFails`: both verbs roll back;
    - `TestOnlineDemoSources`: the probe flag and the real `onlineDemo` setting; each verb is `not_allowed`, with no row;
    - `TestCoverageReadsTheSource` (the Integration AC): `Test.Digest.CoverageProbe.Build` for the session gives the entry "Jira", not checked with `digest.notCheckedMissed` and no runs, and `Live.Payload.Check.FromRow` of the row gives `kind` `source` and `intervalMinutes` 15.
  - **`Test/Mcp/Ops.cls`:** `TestOnlineDemo` and `TestOnlineDemoRealFlag` add both verbs.
  - **`Test/Bridge/Audit.cls`:** `TestMcpCallShape` adds `source_set` and `source_removed` to the call shape; `added` keeps the old one.
  - **`Test/Checks/Render.cls`:** `TestRestKey` covers each of these: none failed with some not checked and some passed; one failed; nothing passed; all passed; not an array.
  - **`Test/Digest/CoverageProbe.cls`:** add `Mark` and `MailOwner` seams from `^||CoverageProbe("mark")` and `^||CoverageProbe("owner")`.
  - **`Test/Digest/Coverage.cls`:**
    - `TestSourceIntervalGap`: runs 15 minutes apart pass, and a gap over 15×60+180 s is missed;
    - `TestStoppedStreak`;
    - `TestReasonMap` gains the two new phrases;
    - `TestMailboxPassed`, `TestMailboxStale`, `TestMailboxUnreachable`, `TestMailboxError`, `TestMailboxOtherOwner`.
  - **`Test/Digest/Compose.cls` `TestNotCheckedLead`:** a real `source` row "Jira" (through `Watch.Ops.SetSource`, `CreatedAt` 02:10 local) has unreachable CheckRun rows every 15 minutes from 02:10 to the window's end, and a `queues` row has passed runs. The rows come from `CoverageProbe.Build`. It pins:
    - the checks part, `[digest.notCheckedUnreachable {entry Jira, time 02:10}, checks.everythingElsePassed]`;
    - the rendered text, which holds the line "Not checked: Jira (unreachable since 02:10)." followed by the line "Everything else I checked passed.";
    - AllClear 0, and neither "Everything I checked passed." nor "Your IRIS system is healthy" in the checks part.

    `TestPartOrder` is unchanged.
  - **`Test/Eval/Report.cls`:** in `TestWatchEveryField`, the value table gains `Server`, `Tool`, `Arguments` and `IntervalMinutes`. It is a Lane A test that Rule 19 requires; see Design Notes.

**Acceptance Criteria:**

- Given a `SetSourcePoll` for a tool classified Read-only from an admin's session, when `McpOps` handles it, then one `BackgroundCheck` row of Kind `source` exists, owned by that session, with the server, the tool, the arguments as JSON and the interval. A risky or unclassified tool is refused with `not_read_only` and writes nothing. Mutation: skip the classification check → `TestSetRefusedNotReadOnly` red.
- Given a session with a `source` row, when `Checks.Coverage.Build` runs (the Integration AC: consumer `Coverage`, reading the row that `McpOps` wrote), then the row is the entry named by `DisplayName`. It counts as checked only when its recorded runs in the window passed with gaps of at most `IntervalMinutes`×60+180 s; otherwise it is not checked with its reason (unreachable, error, timeout, stopped or missed). Mutation: keep the 180 s gap for a source → `TestSourceIntervalGap` red.
- Given the mailbox owner's session and an `emailPoll` mark with `ok` 0 and the unreachable reason, when coverage is built, then the Mailbox row is `digest.notCheckedUnreachable`. With `ok` 1 and a recent `at` in the window it is passed. Mutation: list the mailbox as passed whatever `ok` says → `TestMailboxUnreachable` red.
- Given the step 4 fixture (source "Jira" unreachable since 02:10 local, the other check passed), when the digest is composed, then its checks part leads with `digest.notCheckedUnreachable` {Jira, 02:10} and `checks.everythingElsePassed`, it renders as the two lines in the Tasks, and `AllClear` is 0. Mutation: keep `checks.notEverythingRestPassed` in the lead → `TestNotCheckedLead` red.
- Given a server with sources, when `RemoveMcpServer` commits, then each of its `source` rows is removed and audited with one `CheckChanged`, and other servers' sources stay. Mutation: drop the `RemoveSources` call → `TestServerRemovedRemovesSources` red.
- Given an online-demo install, when either verb arrives, then it answers `not_allowed` and no `source` row is written. The demo path and every existing `Test.Mcp.Ops` row are unchanged. Mutation: skip `Refusal` in `OnSetSource` → `TestOnlineDemoSources` red.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-1: commands, `web_admin` only (`Refusal`).
- AD-4: the row belongs to the command's session.
- AD-5: "due" and "stale" live on rows and the mark, never in memory.
- AD-12: the payload is owned by its publisher's lane, and its TypeScript interface is generated in `web/`, which is why the lane exception covers `payloads.ts`.
- AD-17: one audit writer.
- AD-18: the source row type, `Watch.Ops` the one creator, `Checks` the run writer, `CheckChanged`, the coverage rules.
- AD-19: no secret in the arguments.
- AD-21: the verbs; no MCP on the online demo.
- AD-25: the demo.
- AD-28: the all-clear and the reserved sentences come only from `Checks.Render` (`RestKey`).
- AD-29: lanes.
- AD-32: catalog keys.
- AD-33: one owner per table and event; `Checks` publishes `check`.

AD-6, AD-10 and the S-records S11 and S12 govern the poll and move with it to 22.11. No "S20" record exists in the spine at `6d36d945` (searched). No AC contradicts an AD's Rule, and no NFR trips Rule 5.

**Moved to 22.11 (ruling C; one line each):**
- `src/bridge/.../Poll.cls` (new): the poll runner on a governed proxy-only manager.
- `Ext/McpServers.cls` `PollCall` (default `invalid`) and the `Mcp/Attach.cls` override.
- `Mcp/Proxy.cls` `Listed`, and `NoteReplayRefusal` in poll contexts.
- `Context.cls` `IsPoll` and `SeedMcp`.
- `Policy/Gate.cls`: a poll admits only the proxy, with no grant and the untrusted rule.
- `Adapter/Agent.cls`: a tool request with provenance `untrusted` goes to `Poll.Run`.
- `Process/Decide.cls`: `Admit`, `RunnerFor`, and no `Decision` row for a poll.
- `Checks/Process.cls` `RunSources`, `OnResponse` and `SourceItem` (the Tick block). 22.5 adds only the three parameters.
- `Mcp/Ops.cls` `SourceStopped` (the `mcp.sourceStopped` notice).
- `Test/Mcp/Mock.cls`: a settable `tools/call` answer.
- Task 0 (the standalone manager and async-answer measurements).
- The tests `Test/Mcp/SourceRun.cls`, `Test/Bridge/Poll.cls` and the Gate's poll rows, with the mutations `TestPollRuns`, `TestSeenBefore`, `TestStoppedNotifiesOnce`, `TestPollNoDecisionRow` and `TestPollNoGrant`.
- The decided items on whole-answer results, the baseline, TriageAgent, the live listing, the Ref-only request, async runs, no Decision row and a stopped source that keeps recording.
- The residual `Data.Precedent.KeyFor` (no key form for a poll Item).
- `Digest.Data.CheckRun.Reason`'s doc gains `stopped` with 22.11, its first writer.

**ACs already met by delivered code:** none. `Mcp/Ops.cls` L3 and its three `MapItem`s show no handler, so `CommandsIn` answers `failed` (DW-1137, by design until 22.5). `Coverage` has no source branch and no mailbox row (L4). `Render` never returns `checks.everythingElsePassed`. The prerequisites are delivered: the catalog keys (35.1), the verbs and routes (35.2), the `emailPoll` mark (21.2), and `Refusal`, `Unregister` and the 22.4 cancel (21.4, 22.4).

**`Mcp/Ops.cls` edit order:** 22.4 (done), then 21.4 (done), then 22.5. 22.5 adds lines after 21.4's:
- two `MapItem`s;
- the L3 doc sentence replaced;
- one call in `Unregister` after 21.4's `DropEntry` (L222);
- appended methods and parameters;
- `Answer` gains an optional `ref`.

Story 21.5 (lane C) implements only after 22.5 merges (ruling D). 22.5 builds no Settings route, form, list or rail line; "Polled every {n} minutes" and `SettingsOps.ListMcp`'s `sources` are 21.5's. 21.5's spec relays this story's outcomes and `MESSAGE*` texts verbatim: `saved` with `Ref`, `removed`, `not_read_only`, `not_found`, `bad_name`, `bad_arguments`, `bad_interval`, `not_allowed`, `not_audited` and `failed`.

**Lane exception (for the lead to route before implement; NEW, see Veto item 11).** The approved columns and payload member break three Lane B pins, which the intent's Never list forbids this story to edit:
- `Test.Data.Tables` (the table contract);
- `Test.Live.Payloads` (the payload contract);
- `web/src/app/live/payloads.ts`, which the web build's `payloads.mjs --check` requires to match the class. Without it, the `web` job and every browser unit go red.

Each is a mechanical append, with precedent: 22.4 and 22.7 each added one entry to `Test.Data.Tables`. `payloads.test.mjs` needs no change, because `IntervalMinutes` sits before the trace fields. Alternative, if the lead declines: move the payload member to 21.5. That is a scope move, owner-only. The column pin has no alternative, since the columns are AD-18's.

**Decided in-stage:**
1. **A Lane A test outside the intent's list.** `Test/Eval/Report.cls`'s value table must follow `FIELDS` (Rule 19). `Test.Eval.Watch` needs no edit once `FIELDS` names the new columns.
2. **A command with no session row** answers `failed` with CommandsIn's existing `MESSAGEFAILED`. The admin route always sends one, so no new outcome or text is added.
3. **The name.** It is trimmed, and a control character makes it `bad_name`. The natural key matches it in any letter case (`DisplayName`'s default collation), and an update stores the name as last given.
4. **The arguments** are normalised by `%FromJSON`/`%ToJSON`, with member order kept. The length limit applies to that text, and `secret://` is matched in any letter case.
5. **Transactions.** The row change and its audit entry share one transaction, as in `Unregister` (Rule 2: extend the sibling), instead of an undo. `CheckChanged` goes after the commit.
6. **Names and locks.** The row stores the `Mcp.Server` row's own name, so `RemoveSources` finds it under `stored`. A remove locks the row's server.
7. **The mailbox window rule is conservative (AD-28).** An ok mark outside the window, or more than 900 s before its end, is stale, never passed.
8. **The digest lines.** The two sentences render as consecutive lines, because `DigestText` puts one piece on each line. The test pins both lines.
9. **`digest.checked` composition is unchanged** ("the " + entry). See Public text NEW 1.
10. **Approved items kept from the earlier plan:** the limits; any admin may remove any source; removing a server removes its sources; the lead applies only when nothing failed, so `TestPartOrder` and the failed case keep their wording.
11. **`multiple-goals` is cleared.** What remains is one epic story's ACs about one source entry's place on the coverage list.

**Extend, don't copy (Rule 2):**
- `SetSource` extends `OnStart`'s row write; `RefOf` gains a branch.
- `OnSetSource` and `OnRemoveSource` follow `OnClassify` with `Unregister`'s transaction; `Answer` follows `Watch.Ops.Answer`.
- `MailboxRow` reuses `Add`; the stopped streak reuses the unreachable streak's loop.
- `RestKey` reads Render's own ordered rows.
- **A copy, with its reason:** McpOps' `Changed`/`SendChanged` (about 15 lines) repeat `Watch.Ops.Changed`/`SendChanged`, because a `SendRequestAsync` must be made by the sending item's own instance.

**Integration ACs (Rule 1):** the new surfaces are `Watch.Ops.SetSource`/`RemoveSource`/`SourcesOf`, McpOps' two handlers, `Render.RestKey`, `Coverage.MailboxRow` and the `intervalMinutes` member. Their consumers in this story:
- `Checks.Coverage.Build` reads the row that `McpOps` wrote (AC 2, `TestCoverageReadsTheSource`);
- `Digest` → `DigestText` renders the lead (AC 4);
- `Live.Payload.Check.FromRow`, which `Checks.Changed` and `/v1/state` use, carries `intervalMinutes`.

**Consumes:**
- 22.2: the tool rows and classifications.
- 21.4 and 22.4: `Refusal` and `Unregister`.
- 35.1 and 35.2: the verbs and keys.
- 17.5-17.7: coverage and the digest.
- 21.2: the `emailPoll` mark.
- 23.7: the queue row, the precedent for a non-production kind.

**Consumed-by:**
- 22.11: it runs the rows (`Server`, `Tool`, `Arguments`, `IntervalMinutes`, `NextDueAt`), writes `REASON*` findings and `stopped` runs, and sends `mcp.sourceStopped`.
- 21.5: the form, the list and the rail's schedule line, from the verbs, outcomes, columns and `intervalMinutes`.
- 22.12: the docs.
- 23.8: `sql_query` rows are scheduled by `IntervalMinutes` (AD-18).

**Contended edits (for the lead):**
- `Mcp/Ops.cls`: the edit order above.
- `Checks/Process.cls`: appended parameters only.
- `Data/BackgroundCheck.cls`: appended; 23.8 appends after it, from storage value 20.
- `Checks/Coverage.cls`, non-append: `WatchRow`'s gap and streak, two `$Case` arms, one call in `Build`, the doc.
- `Checks/Render.cls`: append only.
- The lane exception above.

**Ledger inbox (Rule 17):** `LEDGER slice 22-5-poll-a-read-only-mcp-tool-as-a-source` is empty.

**Spine updates for the lead (Rule 20):**
- AD-18: the source columns; the gap of interval + 180 s; the Mailbox entry from `emailPoll` (owner session only, 900 s, the conservative window); sources removed with their server; the CheckRun Reason `stopped` mapping.
- AD-28: `Render.RestKey` and the digest's not-checked lead.

The poll records (the earlier plan's S19 to S21 run parts) go with 22.11.

## Veto items

Approved by the Contest Planner (veto 1-10), kept verbatim. The scope tags in brackets are new.

1. **Stored columns.** `OcuTalon.Data.BackgroundCheck` gains `Server`, `Tool`, `Arguments` (the admin's JSON; never a secret: `secret://` and `@{` are refused) and `IntervalMinutes`, appended to the default storage. There is no new table, and retention is unchanged (rows live until removed; `CheckRun` keeps AD-27's purge).
   - Online demo: never written.
   - [22.5]
2. **A stored value.** `Digest.Data.CheckRun.Reason` gains `stopped`.
   - Online demo: never written.
   - [22.5 maps it in coverage; 22.11 writes it]
3. **Outward actions.** Each due poll sends one `tools/list` (the seed) and then the proxy's `initialize`, `tools/list` and `tools/call` to an admin-registered server, every 5 to 1,440 minutes, bounded at 2/2/2/20 s.
   - Online demo: none (no row; `MCPDEMO`).
   - [22.11]
4. **Security posture.**
   - A poll runs with provenance `untrusted`, so only a Read-only tool runs, and it is never held.
   - The answer text is stored in the Reply message and the Item, as an email's body is (untrusted).
   - Arguments are only in the row, never in a message, log or audit entry.
   - Online demo: unchanged.
   - [22.5 keeps arguments out of every audit entry, log and notice; the rest is 22.11's]
5. **An access rule.** Any admin may set or remove a source (origin `web_admin`). A source's Items and digest entry belong to the session that set it.
   - Online demo: refused.
   - [22.5]
6. **Notices.** The accepted `mcp.sourceStopped` goes to every admin session on a stop.
   - Online demo: never sent.
   - [22.11]
7. **Bridge request semantics and the extension (S19, S20).**
   - Online demo: no change.
   - [22.11]
8. **A live payload member.** The `check` event and `/v1/state` gain the optional member `intervalMinutes`.
   - Online demo: empty for every row.
   - [22.5]
9. **An AC part moved (veto window 7 and 8).** "So the page shows the source's schedule" needs a `source` branch in Lane B's `web/src/app/rail/rail-view.ts`.
   - This story already delivers the generic last run and result (L244-263) and publishes `nextDueAt` and `intervalMinutes`.
   - Proposed: a `DW-n` bullet on Lane B's Story 21.5 to render "Polled every {n} minutes" (text below, for 21.5's approval). Alternative: a ruled lane exception like 22.4's R1, a plain union with Epic 23's rail work.
   - Online demo: no sources.
   - [ruled: 21.5]
10. No new route, privilege, role, grant, resource, production item, retention or web dependency.
    - [holds for 22.5]
11. **NEW: a lane exception (not a veto category; listed for visibility).** Three Lane B files each get a mechanical edit (Design Notes):
    - one generated line in `web/src/app/live/payloads.ts`;
    - one contract entry in `Test/Live/Payloads.cls`;
    - four in `Test/Data/Tables.cls`.

    It adds no web dependency, route or behaviour. Online demo: no change.

## Public text

**Approved (the nine strings, verbatim):**

| File / parameter | Where it shows | Text |
| --- | --- | --- |
| `Checks/Process.cls` `REASONSOURCEUNREACHABLE` | a source's finding (rail, coverage row), written by 22.11 | "Couldn't reach its MCP server" |
| `Checks/Process.cls` `REASONNOTREADONLY` | a stopped source's finding, written by 22.11 | "Its tool is no longer Read-only" |
| `Checks/Coverage.cls` `ENTRYMAILBOX` | the digest's coverage entry | "Mailbox" |
| `Mcp/Ops.cls` `MESSAGENOTREADONLY` | the Settings answer (21.5) | "Only a Read-only tool can be a source. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGESOURCENAME` | the Settings answer | "A source's name is 1 to 100 characters. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGESOURCEARGUMENTS` | the Settings answer | "A source's arguments must be a JSON object of up to 4,000 characters, with no secret in it. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGESOURCEINTERVAL` | the Settings answer | "A source is polled every 5 to 1,440 minutes. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGENOSOURCE` | the Settings answer | "There is no source with that reference. Nothing was changed." |
| `Mcp/Ops.cls` `MESSAGESOURCEREMOVED` | the Settings answer | "The source was removed." |

"Polled every {n} minutes" belongs to 21.5 and is not shipped here.

**NEW (for the Planner):**
1. **The digest's "I checked" part with source and mailbox entries.** The existing `digest.checked` composition puts "the " before every watched entry. A digest that watches the Orders production, a source "Jira" and the mailbox therefore reads "I checked the Orders production, the Jira and the Mailbox." No string is added or changed, but the rendering is new. Online demo: no source or mailbox row, so it never shows there.

   Recommended: accept for this release. Alternative: a follow-up story that names source rows without "the ", which needs the row's kind on the coverage row (a shared-surface change).

**Existing, reused:**
- **From UX/PRD:** EXPERIENCE.md L173 and L611, UX-DR106, UX-DR122: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed.", built from `digest.notCheckedUnreachable` and `checks.everythingElsePassed`.
- **From 35.1** (accepted): `digest.notCheckedStopped`.
- **Already in use:**
  - `digest.notCheckedError`, `digest.notCheckedStale` and `digest.notCheckedMissed`;
  - `FINDINGSTALE`;
  - the email adapter's `REASON*` texts, as the mailbox row's finding;
  - `MESSAGESAVED`, `MESSAGENOSERVER` and `MESSAGENOTOOL`;
  - CommandsIn's `MESSAGEFAILED` and its refusal texts.

**Findability:** none in this story, because there is no UI until 21.5. Story 22.12 documents the source.

## Verification

Each `ci/iris.sh` and `ci/warm.sh` call carries the lane's variables:
`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s5iw`; fresh runs use `OCUTALON_RUN_TAG=e22s5i`.
- Run one class per foreground call, with `timeout: 600000`. Each must finish inside about 150 s.
- Never put two `iris_execute_tests` calls in one message. Pass `server` `ocutalon-slot-d` and `namespace` `OCUTALON` on every IRIS MCP call (read-only lookups).

**Commands:**
- (once) `ci/warm.sh status`, then `OCUTALON_RUN_TAG=e22s5iw ci/warm.sh up` -- expected: a ready warm stack.
- (loop) Warm, each `ci/iris.sh class <Class>` -- expected: `CLASS … passed`:
  - `OcuTalon.Test.Mcp.SourceSet`
  - `OcuTalon.Test.Mcp.Ops`
  - `OcuTalon.Test.Bridge.Audit`
  - `OcuTalon.Test.Checks.Render`
  - `OcuTalon.Test.Digest.Coverage`
  - `OcuTalon.Test.Digest.Compose`
  - `OcuTalon.Test.Digest.AllClear`
  - `OcuTalon.Test.Eval.Watch`
- (once) Warm, each `ci/iris.sh class <Class>` -- expected: passed:
  - `OcuTalon.Test.Eval.Report`
  - `OcuTalon.Test.Watch.Ops`
  - `OcuTalon.Test.Core.CommandsStep4`
  - `OcuTalon.Test.Digest.TelegramText`
  - `OcuTalon.Test.Digest.RecordTrigger`
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Checks.Queues`
- (once, after the lane exception) Warm, `ci/iris.sh class OcuTalon.Test.Data.Tables` and `ci/iris.sh class OcuTalon.Test.Live.Payloads` -- expected: passed.
- (once) `cd web && node scripts/payloads.mjs --check && node --test scripts/payloads.test.mjs` -- expected: exit 0.
- (once) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-storage.sh` and `bash docker/tests/test-ci-config.sh`, one per call -- expected: exit 0.
- (once) `OCUTALON_RUN_TAG=e22s5iw ci/warm.sh down` -- also after a failure.
- (once) Fresh: `OCUTALON_RUN_TAG=e22s5i ci/iris.sh class OcuTalon.Test.Mcp.SourceSet`, then `OCUTALON_RUN_TAG=e22s5i ci/iris.sh teardown` -- expected: passed on a fresh stack, then torn down.

**CI:** no new unit or group. `Test.Mcp.SourceSet` joins `shard:lane-a@rest` (`shards-2`), and the `Test.Digest` methods join `shard:lane-a@Install,Digest,Eval` (`shards`), each a few seconds (inference). A web-input change (`Live/`, `web/`) also runs the `web` job.

**Shared surfaces:**
- `BackgroundCheck`'s columns: `Test.Data.Tables`, `Test.Eval.Watch` `FIELDS`, and `Test.Eval.Report`'s value table. `Fields` JSON in `Test.Eval.In` and `WatchOwners` stays consistent by construction.
- The `check` payload's members: `Test.Live.Payloads`, `web/src/app/live/payloads.ts` and `payloads.test.mjs`.
- `MCPCHANGES` and `CALLCHANGES`: `Test.Bridge.Audit`.
- The `CheckRun` Reason values (`stopped`).
- The coverage rows: the Mailbox row appears only for the mailbox owner's session.
- The digest's checks part when nothing failed and something was not checked.
- McpOps' `MessageMap` and `Answer`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19):**

| Mutation | Test that goes red |
| --- | --- |
| Skip the read-only check in `OnSetSource` | `TestSetRefusedNotReadOnly` |
| A source keeps the 180 s gap | `TestSourceIntervalGap` |
| Mailbox passed whatever `ok` says | `TestMailboxUnreachable` |
| Keep `checks.notEverythingRestPassed` in the lead | `TestNotCheckedLead` |
| Drop `RemoveSources` from `Unregister` | `TestServerRemovedRemovesSources` |
| Skip `Refusal` in `OnSetSource` | `TestOnlineDemoSources` |
| `KeyOf` maps `stopped` to the error key | `TestStoppedStreak` |
| `RestKey` ignores failed rows | `TestRestKey` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
