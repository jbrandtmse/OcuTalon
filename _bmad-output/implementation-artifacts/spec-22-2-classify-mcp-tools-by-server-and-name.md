---
title: 'Story 22.2: Classify MCP tools by server and name (part 1: McpOps, the per-server resource, the classification table and Tools)'
type: 'feature'
created: '2026-11-11'
status: 'done'
baseline_revision: '68acfe4b960e59868eeb1530f40fec434032354b'
baseline_commit: '68acfe4b960e59868eeb1530f40fec434032354b'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/35-1-task0-mcp-attach.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** An admin can't yet add, remove or classify an MCP server's tools: `McpOps` is not a production item, `Tools(server)` is a stub, no `OcuTalon.Mcp.ToolClassification` table exists, the per-server IRIS resource `OcuTalon_MCP_<server>` is never made, and nobody tells admins when a server is unavailable, a tool shadows a built-in, or a classified tool changed.

**Approach:** Make `OcuTalon.Mcp.Ops` the `McpOps` item that handles `AddMcpServer`, `RemoveMcpServer` and `ClassifyTool` from `CommandsIn` (origin `web_admin` only, refused on the online demo), writing the `Mcp.Server` row, the new `ToolClassification` rows and the resource granted to the service role (through a new `Install.Step.Mcp` area), auditing each change and calling `RestartRunners()`. The runner's attach report gains each tool's fingerprint, and `RecordAttach` keeps one row per discovered tool, clears a classified tool whose fingerprint changed, and sends the three admin notices on transitions. `Tools(server)` reads the rows.

## Boundaries & Constraints

**Always:**
- Lane A files only (U-177): `Mcp/**`, the new `Install/Step/Mcp.cls`, the bridge's `Adapter/Agent.cls`, `Context.cls` and `Ext/McpServers.cls` (doc only), the Lane A region of `Production.cls`, `Test/Mcp/**`, the Lane A row in `Test/Install/Production.cls`, one appended line in `src/short-names.tsv`.
- Every handler re-checks the sender (`CommandsIn`) and `Origin` `web_admin` and refuses on an online-demo install, before any write. A command with an empty `ActingUser` is refused.
- Addresses: `https://` only, or `http://` to loopback (`127.0.0.1`, `localhost`, `[::1]`) for development. Any value containing `@{` is refused (AD-19).
- Audit only through `OcuTalon.Bridge.Audit.Record`. Notices only as `OcuTalon.Msg.Notification`s (kind `status`, catalog keys `mcp.serverUnavailable`, `mcp.toolShadowsBuiltIn` and `mcp.toolChanged`) to `Ownership.AdminSessions()`, once per transition, never per report.
- `%SYS` is reached only through `OcuTalon.Install.Step.Mcp` (AD-3). No secret, URL or AI Hub error text is ever stored, logged, audited or put in a notice.

**Never:**
- Edit `Core.SettingsOps`, `Core.CommandsIn`, `Web.*`, `web/**` or any Lane B test. Write the Config Store entry or the wallet secret (Story 21.4, DW-1041 ruling). Add a route.
- Change the gate, `Ext.Classification`, `Decide.ToolsReadOnly`, the per-turn manager or `BuildTurnManager` (proposed Story 22.8), cancel approval requests (22.4), or build `call_mcp_tool` (22.3).
- Use a real MCP server. Delete, skip, tag off or shorten a test.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Add | `AddMcpServer` from `CommandsIn`, `web_admin`, a valid new name, an `https://` or loopback `http://` URL | `Mcp.Server` row (`CreatedAt`), resource `OcuTalon_MCP_<s>` (no public permission) held `U` by `OcuTalonServiceRole`, MCP audit `added`, `RestartRunners()` once; `Ok 1`, outcome `added` | none |
| Bad address | `http://example.com/mcp`, `ftp://…`, empty, or `https://x/@{env:K}` | outcome `bad_address`; nothing written, no restart | refused |
| Bad or taken name | a name not matching `Server.NAMEPATTERN`, or a registered one | `bad_name` / `exists`; nothing written | refused |
| Wrong origin or sender | `Origin` `tool` (or a bridge context), `web_user`, `system`; a sender other than `CommandsIn`; an empty `ActingUser` | `not_allowed` with `CommandsIn` `MESSAGENOTFROMTOOL` (`tool`) or `MESSAGEADMINONLY`; nothing written, no restart | one warning, no secret |
| Online demo | any of the three verbs while `onlineDemo` is 1 | `not_allowed` with `CommandsIn` `MESSAGENOTALLOWED`; nothing written | refused |
| Remove | `RemoveMcpServer` for a registered server | its `ToolClassification` rows and row deleted, grant and resource removed, MCP audit `removed`, `RestartRunners()`; `Tools(s)` is then an error | unknown server: `not_found`, nothing changed |
| Classify | `ClassifyTool` `read-only`, `risky` or `unclassified` for a discovered tool | row's `Classification` set, its `Fingerprint` kept; Tool audit (`read-only` -> `safe`/`readOnly` 1, `risky` -> `risky`/0, `unclassified` -> `unclassified`/0; source the server's name); outcome `saved`, message "Saved" | unknown server or tool: `not_found`; another word: `bad_classification`; nothing changed |
| Audit fails | `Audit.Record` returns an error | add and classify are undone first; outcome `not_audited`, `MESSAGEFAILED` | one warning |
| Restart fails | `RestartRunners()` errors after the change is saved | change kept (the next start attaches it); outcome `failed`, `MESSAGEFAILED` | one warning |
| Attach report | `{"status":"attached","tools":[a,b],"fingerprints":{a:fa,b:fb},"refused":[c]}` | rows for a, b (new ones `unclassified` with their fingerprint) and c (`Fingerprint` ""); rows of tools no longer listed or refused are deleted | unknown server: error, nothing written (as today) |
| Tool changed | a classified row whose reported fingerprint differs | `unclassified`, new fingerprint, Tool audit `unclassified` (`irisUser` `$Username`, channel `system`), one `mcp.toolChanged` notice per admin session | unclassified row: fingerprint updated, no notice |
| Unavailable / shadow | row turns `unavailable` (from `attached` or ""); a name newly in `refused` | one `mcp.serverUnavailable` (`server`, `time` now UTC) / one `mcp.toolShadowsBuiltIn` (`server`, `tool`) notice per admin session | the same report again: no notice; an `AdminSessions` error: one warning |
| Tools | a registered server | `[{name, classification, status}]` sorted by name; status `refused` if in `RefusedTools`, else `unavailable` while `AttachStatus` is `unavailable`, else `available` | unknown or empty server: error |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` -- `Tools` stub (L19-23) to build; `RecordAttach` (L26-54) to extend; becomes the item. Pattern: `Watch/Ops.cls` MessageMap L58-67, `Answer` L265; online-demo and sender re-check pattern `Core/PrecedentOps.cls` L257-275 (Lane B: read only).
- `src/ocutalon/cls/OcuTalon/Mcp/Server.cls` -- row and `NAMEPATTERN`; storage and DEFAULTGLOBAL conventions to mirror.
- `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` -- `Servers`/`OnAttach`; header to update for the fingerprints.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` (read only) -- routes L297-301 (`owner` `McpOps`, `web_admin`), sync send L154 (120 s), message parameters L65-79.
- `src/ocutalon/cls/OcuTalon/Msg/Command/{AddMcpServer,RemoveMcpServer,ClassifyTool}.cls`, `Msg/CommandResult.cls` (read only) -- `Server`, `Url`, `Tool`, `Classification`, `ActingUser`; `Ok`, `Outcome`, `Message`.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` (read only) -- `RestartRunners()` L1367; `AuditData` L190 is the audit-data example; `SaveMcpEntry`/`RemoveMcpEntry` stubs L1389/L1396.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls` -- `Record(type, data)` L78; `SHAPEMCP`, `SHAPETOOL`, `MCPCHANGES`, `CLASSIFICATIONS`, `COMMON`; channel from `Msg.Enum CHANNEL`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` (read only) -- `AdminSessions(Output sc) As %List` L813. `Core/BridgeSink.cls` L415-436 -- `Notice` seam through `Core.NoticesIn.Send`, fan-out pattern. `Msg/Notification.cls`, `Msg/Enum.cls` `NOTIFICATIONKIND` L30. `Msg/Catalog/Watch.cls` L1044-1066 -- the three keys and slots.
- `src/ocutalon/cls/OcuTalon/Install/Step/{Roles,Tools,Demo,Users}.cls` -- `Roles.Compose`/`Add` (refuses a missing resource, L61-63) and `Apply` rewrite the role at every start; `Tools.Grants` is the area pattern; `Demo.ServiceRole` L478-499 is the `Security.Roles` Get/Modify pattern; `Users.#SERVICEROLE`. `Install/Registry.cls` `Areas()` finds a new area by itself (no `Order` change).
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- `AttachOne` L313 (keeps the `GetToolStatuses()` entries whose `tool_ref` is the spec; each has `description` and `parameters`, evidence L27-29), `ReportAttach` L371.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `ArgumentsHash` L172 over `Canonical` L186 (sorted keys): the fingerprint extends it.
- `src/ocutalon/cls/OcuTalon/Production.cls` -- Lane A markers L15/L68; last item `DocumentOps` L67.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- oracle `XData Items` L899-927 (Lane A rows).
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls` -- `Register` L428 (row, mock, wallet, Config Store entry), `Remove` L447, `Leftovers` L459, `Use` L402, `Guard` L417; TestAttach L104 (L132-138 the gate on the real toolref), TestUnavailable L160, TestShadow L177, TestReports L281, TestRequestServerDown L347.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/{Tools,Mock,Loopback,ZzServers}.cls` -- `TestToolsStub` (stub contract that changes); mock `Serve` L127-132 (queue 0, keep-alive -1), `OPENWAIT` L29; `TestBindsLoopbackOnly`.
- `src/short-names.tsv` L34 -- `McpServer` row format; enforced by `docker/tests/test-storage.sh`.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` (read only) -- `Source` L223, `RagCall` L234, `FromExtension` L406: evidence for the AC already met.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (DW-1038) -- on the lane's warm throwaway, set the mock's `ConnectionQueueSize` to 5 with `KeepAliveInterval` -1 and run `OcuTalon.Test.Mcp.Loopback`. If it stays green, keep the backlog and record the result in `## Verification`. If it goes red, revert and use the fallback in the `Test/Mcp/Attach.cls` task. Label how well it guards against CI load as (inference).
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/ToolClassification.cls` -- new `%Persistent` (header: Lane A, sole writer `Mcp.Ops`). Properties: `Server` (40), `Tool` (128), `Classification` (`unclassified`, `read-only` or `risky`; initial `unclassified`), `Fingerprint` (64), `ChangedAt` (UTC). Unique index on (`Server`, `Tool`). `DEFAULTGLOBAL` `^OcuTalonP.McpTool`, storage like `Server.cls`. It is the classification store, keyed by server and tool name.
- [ ] `src/short-names.tsv` -- append `McpTool	^OcuTalonP.McpTool	OcuTalon.Mcp.ToolClassification	A` -- required by `test-storage.sh`.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Mcp.cls` -- new area (extends `Install.Step`, runs no step):
  - `Grants()`: one `{role: Users.#SERVICEROLE, resource: "OcuTalon_MCP_"_Name, permission: "U"}` per `Mcp.Server` row whose resource exists. It skips a row without one, with `..Warn`, so a start never fails. It returns `[]` on an online-demo install.
  - `Grant(server)` and `Revoke(server)`: create the resource (description only, no public permission) and add `:U` to the service role, or remove both. Other grants stay as they are.
  - All `%SYS` work goes in `Security.*` methods with `New $NAMESPACE` (AD-3).
  - [RULED 2026-11-11, Contest Planner condition] `Grant`/`Revoke` are the ONE fixed privileged entry point: they take only a server name, build the name `OcuTalon_MCP_<server>` themselves, refuse any server name that fails `Server.NAMEPATTERN` (error, nothing changed), and touch only that resource and that one pair on `OcuTalonServiceRole`. `Test/Mcp/Ops.cls` gets `TestEntryPointRefusesOtherNames`: names such as "", "%All", "x;y", "x y", "../x", "1abc", "%Admin_Secure" and a 41-character name are refused, no resource is created and the service role's resource list is byte-identical before and after; and a valid add changes the role's list by exactly the one `OcuTalon_MCP_<server>:U` pair (no `%Admin_Secure`, `%All` or other `%Admin_*` resource added to any OcuTalon role).
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls`:
  - `MessageMap` for the three verbs, run in the order Validate, Register or Unregister, Audit, Restart, so Story 21.4's entry write goes in as one call: after Validate in add, after Unregister in remove.
  - Sender and origin re-check, online-demo refusal, address and name checks.
  - `Tools(server)` built.
  - `RecordAttach`: rows, fingerprints, stale-row delete, changed-tool clear, transition notices.
  - Public `ClearChanged(server, tool, fingerprint)` that the clear and the next story share.
  - Private overridable seams `OnlineDemo()`, `AdminSessions(.sc)`, `Notice(n)` and `Restart()` (the `BridgeSink`/`PrecedentOps` precedent). Result texts as parameters (Public text).
- [ ] `src/ocutalon/cls/OcuTalon/Production.cls` -- Lane A region: `<Item Name="McpOps" ClassName="OcuTalon.Mcp.Ops" PoolSize="1" Enabled="true"/>`; `Test/Install/Production.cls` -- the matching oracle row `{"lane":"A","name":"McpOps","class":"OcuTalon.Mcp.Ops","pool":1,"enabled":1,"stub":0,"settings":[]}`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- public `ToolFingerprint(description, parameters) As %String` = `ArgumentsHash({"description":…, "parameters":…})` (extends `Canonical`; no copy).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` and `Ext/McpServers.cls` -- `AttachOne` adds `fingerprints` (name -> `ToolFingerprint`) for the tools it keeps; the base class's doc states the report member. `Mcp/Attach.cls` header updated to match.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Ops.cls` (new) and `OpsProbe.cls` (probe subclass recording notices and restarts and switching the demo flag; it sets `%RequestHeader` the way `Test/Core/PrecedentOps.cls` L606 does) -- every matrix row except the runner build:
  - resource and role read back in `%SYS`;
  - audit entries read back with polling;
  - `Roles.Compose` includes the grant while the row exists, and nothing on the demo;
  - notices once per transition;
  - every fixture removed, none left behind.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Tools.cls` -- `TestToolsStub` becomes the built contract (unknown or empty server is an error, rows sorted, statuses); `Remove` also deletes `ToolClassification` rows.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls`:
  - TestAttach also asserts the zz_lookup and zz_delete_ticket rows: `unclassified`, with a 44-character fingerprint, listed by `Tools` as `available`.
  - TestShadow and TestUnavailable assert one notice each to a fixture admin session (a `Session` row with `AdminAtSignIn` 1, made and removed by the test).
  - New `TestCommands`, through the real `Commands.Submit` and `CommandsIn` with the production running: add -> row, resource, grant, audit and changed runner jobs; classify -> row and audit; remove -> all gone; origin `tool` -> refused.
  - `Remove`/`Leftovers` also cover classification rows, the resource and notices.
  - DW-1038: the mock backlog from Task 0, else a bounded retry (at most 3 tries, 1 s apart) around a mock-dependent attach or `AddTool`, with each retry logged.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Mock.cls`:
  - Task 0's queue size, if kept.
  - An optional per-port override of zz_lookup's description, kept in the mock's existing `^IRIS.Temp.OcuTalonMcpMock(port, …)` nodes and cleared by `Stop`, so a test can change a tool between two builds for the changed-tool AC.
  - Header updated.

**Review patches (first review pass; fresh subagent, tick when done):**
- [x] RP1 `src/ocutalon/cls/OcuTalon/Mcp/ToolClassification.cls` -- `Tool` gets `COLLATION = "EXACT"` (MCP tool names are case-sensitive), so `ServerToolIndexOpen` and the unique index tell `Foo` from `foo`. `Test/Mcp/Ops.cls`: a report with tools `Foo` and `foo` gives two rows with their own fingerprints and no clear on a repeat of the same report; `ClassifyTool` for `FOO` is `not_found`. Mutation line: remove the collation, observe red, revert.
- [x] RP2 `Mcp/Ops.cls` `AddressAllowed` -- a port must be 1 to 65535 (`0`, `99999` refused); `Test/Mcp/Ops.cls` `TestBadAddress` gains `:0`, `:65536`, `:99999` refused and `:65535` and `:1` allowed. Mutation line.
- [x] RP3 comments only: `Mcp/Attach.cls` class comment (RecordAttach now looks up the admins' sessions through `Ownership.AdminSessions` to send notices; say so, do not narrate history); `Test/Mcp/Mock.cls` header (state the `ConnectionQueueSize` 5 effect as a measured green `Loopback` run, with its guard against CI load labelled (inference)); `Install/Step/Mcp.cls` `Grant` doc (an existing pair on the resource is set to `U`; a resource that exists is left as it is).
- [x] RP4 `Test/Mcp/Ops.cls` -- (a) `ToolFingerprint` cases: a schema-only change differs, a description-only change differs, a key reorder in the schema is equal, blank parameters equal `{}`; the length is 44. (b) the real `Ops.OnlineDemo()` with the real `Public.Settings` `onlineDemo` flag at 1 (save and restore it as `TestRolesCompose` does; no `^||ZzOps("demo")` node): `AddMcpServer`, `RemoveMcpServer` and `ClassifyTool` answer `not_allowed` with `MESSAGENOTALLOWED` and write nothing. (c) `TestRecordAttachRows` gains: a classified listed tool that is then reported refused keeps its classification with an empty fingerprint (no audit, no notice); reported listed again it is cleared; a classified tool in an `attached` report with no `fingerprints` member is cleared (the fail-safe of Design Notes 12 and 13). (d) `TestClearChanged` asserts the notice its comment promises (or drop the claim from the comment). Mutation lines for (a), (b) and (c) (for (a) hash the description only; for (b) make `OnlineDemo` return 0; for (c) call `ClearRow` in `KeepRow`'s refused branch).
- [x] RP5 mutation lines still missing (Rule 19), each applied, observed red and reverted byte-identical (`cmp`), one line each in `## Verification`: Remove (skip `DeleteTools`, skip `Revoke`, skip the removed audit); Classify (blank `Fingerprint`, skip the Tool audit); changed tool (skip the Tool audit in `ClearRow`, skip the `changed` event so no `mcp.toolChanged` notice); AC 1 (skip the added audit, skip `Restart`); `Grants()` (drop the resource-exists check); AC 7 leak assertions (put the mock's address into `McpData`'s server value or into a `Failed` text, and show `TestCommands` or `Test.Mcp.Ops` goes red on the leak assertion itself, not on the add). Where one run of one class covers several, name the class once per line.

**Acceptance Criteria:**
- Given the production running with `McpOps`, when `Commands.Submit` sends `AddMcpServer` with origin `web_admin` and `CommandsIn` routes it, then the `CommandResult` is `Ok` 1 with `added`. The row and resource exist, the service role holds the resource with `U`, an `OcuTalon/MCP/MCP` `added` entry naming the acting user is in the audit log, and the runner items have new jobs.
- Given a shadow runner built with `McpServersClass` `OcuTalon.Mcp.Attach` and the loopback mock, when the build reports, then `Tools(server)` lists zz_delete_ticket and zz_lookup as `unclassified` and `available`, each row holding the fingerprint of its description and canonical input schema. Classifying zz_lookup `read-only` through `CommandsIn` keeps that fingerprint and audits it.
- Given a classified tool whose description or input schema the mock changes, when the next build reports, then the row is `unclassified` with the new fingerprint, a Tool audit entry `unclassified` exists, and each admin session gets one `mcp.toolChanged` notice.
- Given a registered server, when it is removed through `CommandsIn`, then its rows, resource and grant are gone, `Tools(server)` is an error, and the removal is audited.
- Given a start with registered servers, when the Roles step composes the roles, then `OcuTalonServiceRole` holds `OcuTalon_MCP_<server>:U` for each row whose resource exists. On an online-demo install it holds none.
- [RULED 2026-11-11, Contest Planner condition] Given `Install.Step.Mcp.Grant` or `Revoke` called with any name that fails `Server.NAMEPATTERN`, when it runs, then it returns an error, creates or deletes no resource and leaves `OcuTalonServiceRole` unchanged; and given a valid add, `OcuTalonServiceRole` gains exactly `OcuTalon_MCP_<server>:U` and no security-administration privilege (`%Admin_*`, `%All`).
- Given any test of this story, when its output, logs, audit entries and notices are searched, then the fixture secret and the mock's URL appear in none.

### Review Findings

Code review 2026-11-11 (follow-up review; layers blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, all on the session's model). 39 raw findings: 17 in 14 entries after grouping (high 0, medium 0, low 14), 22 rejected (listed below by root cause). No AD or Contest Planner CONDITION breach: `Grant`/`Revoke` build `OcuTalon_MCP_<server>` themselves, refuse any name failing `NAMEPATTERN` before any write, touch only that resource and that one pair, and add no `%Admin_*` or `%All`; only `Install.Step.Mcp` switches to `%SYS`.

- [x] [Review][Patch] The real `Ops.Restart()` (AC 1, "the runner items have new jobs") had no `mutation:` line; every restart line ran on the probe's counter [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:603] -- closed in-pass: mutation applied, `TestCommands` red, reverted; line under `## Verification`.
- [x] [Review][Patch] The AC 7 `Failed`-text leak variant was never run [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:159] -- closed in-pass: mutation applied, `TestNoAddressOrSecretInAnyText` red on the event-log scan only, reverted; line under `## Verification`.
- [x] [Review][Patch] `Test.Mcp.Ops` header named a test that does not exist (`TestGrantsSkipMissingResource`) [src/ocutalon/cls/OcuTalon/Test/Mcp/Ops.cls:15] -- the missing-resource skip is in `TestRolesCompose`; header corrected.
- [x] [Review][Patch] `Test.Mcp.Ops` header said `TestNoAddressOrSecretInAnyText` scans the stored row; it does not [src/ocutalon/cls/OcuTalon/Test/Mcp/Ops.cls:21] -- claim removed.
- [x] [Review][Patch] `Mcp.Ops` class comment said a refusal is always one warning; the online-demo refusal logs none (matching the matrix) [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:5] -- corrected.
- [x] [Review][Patch] `Mcp.Ops` class comment said the item answers every command with a `CommandResult`; it has no handler for `SetSourcePoll`/`RemoveSourcePoll` [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:2] -- corrected.
- [x] [Review][Patch] The classification words were in `Ops.CLASSIFICATIONS` and in `ToolClassification.CLASSIFICATIONS`, which nothing read [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:214] -- `Ops.Classify` now reads `ToolClassification.#CLASSIFICATIONS`; the `Ops` copy is removed.
- [x] [Review][Patch] `## Verification` Shared surfaces named `TestToolsStub`, which this story renamed `TestTools` -- corrected (tracking section).
- [x] [Review][Defer] `SetSourcePoll`/`RemoveSourcePoll` answer `failed` (was `not_built`) until Story 22.5 [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:62] -- deferred: DW-1137 `by-design` (Design Notes 17).
- [x] [Review][Defer] A classified tool that its server stops listing loses its row with no Tool audit and no notice [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:372] -- deferred: DW-1133 `wontfix-accepted` (fail-safe; reopen_if in the entry).
- [x] [Review][Defer] `docs/bridge-guide.md` omits the attach report's `fingerprints` member and `Context.ToolFingerprint` [docs/bridge-guide.md:317] -- deferred: DW-1134 `wontfix-accepted` (public doc text, pinned whole-line; reopen_if the section is next edited).
- [x] [Review][Defer] No test reaches the Grant-failure undo, the failed-Revoke rollback or `Change`'s resource drop [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:151] -- deferred: DW-1135 `wontfix-accepted` (needs a seam in the CONDITION's entry point).
- [x] [Review][Defer] `Install.Step.Mcp`'s role Get/edit/Modify repeats `Demo.ServiceRole`'s (Rule 2, weak reason) [src/ocutalon/cls/OcuTalon/Install/Step/Mcp.cls:130] -- deferred: DW-1136 `wontfix-accepted` (Demo.cls is outside this story's files).
- [x] [Review][Defer] Spine AD-21 (about L798) still says the mock sets a connection queue size of 0; Task 0 kept 5 -- handed to the lead as a Rule 20 spine update (S4); no code change.

Rejected:
- `maybe-false` (low if true): the remove's failed audit rolls back `Revoke`'s `%SYS` globals inside `TSTART`, so the re-`Grant` finds them and writes nothing, leaving IRIS's in-memory security tables saying no access -- `Security.Resources.Delete`'s doc confirms the in-memory update, but whether `TROLLBACK` restores the globals is unmeasured, and `CheckUserPermission` (22.3's gate check) computes from the role definitions (inference); `TestAuditFails` shows the resource and the pair are back. Real if a process check of `OcuTalon_MCP_<s>` fails after a remove whose audit failed.
- `low`: the undo branches ignore their own statuses (`Revoke`, `%DeleteId`, the restoring `%Save`) -- needs a failed audit and then a failed undo; the fix adds branches.
- `low`: an add's failed-audit undo deletes an `OcuTalon_MCP_<s>` resource that existed without a row -- that resource has no server and is OcuTalon's own name space; the end state is clean.
- `low`: `RemoveMcpServer`/`ClassifyTool` with a different letter case (`FOO` for `Foo`) -- the left-over pair claim is `false` (`Security.Resources.Delete` removes the resource from every role, per its doc); what remains is the audit naming the request's case and a lock keyed on it, reachable only by a hand-made request (21.4's page offers the stored names); the fix adds a helper.
- `low`: `Security.Roles` read-modify-write race between `Install.Step.Mcp.SetPair` and `Demo.ServiceRole` -- needs an add or remove during a demo-mode switch, and the Roles step re-declares both at the next start.
- `low`: a refused (empty-fingerprint) classified tool later listed with no fingerprint keeps its classification -- `AttachOne` sets a fingerprint for every attached tool (Design Notes 12), and 22.8's gate compares the call-time fingerprint; real if an attached report lists a tool with no fingerprint string.
- `false`: `Tools` lists stale rows as available when `AttachStatus` is "" -- tool rows exist only after an attached report, and the bridge reports only attached or unavailable.
- `low`: `RecordAttach` has no online-demo check -- no code makes an `Mcp.Server` row on the demo (`McpOps` refuses every verb there); real if the demo installer writes `Mcp.Server` rows.
- `false`: the `%Status` texts of `Tools` and `Install.Step.Mcp.ResourceOf` are new user-facing text -- they reach the event log, not a `CommandResult`; 21.4 renders its own text from the outcome.
- `false`: `TestOnlineDemoRealFlag`'s `$Data(^||ZzOps("demo")) = 0` cannot fail -- it is the test's precondition and goes red if the set-up ever sets the probe's switch.
- `low`: `TestRolesCompose`'s `>= 1` warning count could pass on another row's warning -- `found = 0` is the pin.
- `low`: `Test.Mcp.Ops` relies on the installer's role and audit events -- already `wontfix-accepted` as Rule 19 d in the first review; no new evidence.
- `low`: the spec's Execution tasks are unticked -- the fix edits the spec under review.
- `low`: `FINGERPRINTLENGTH` repeats `Fingerprint`'s `MAXLEN`, and `ResourceOf`'s error repeats "up to 39" -- a guard and an error text; no caller diverges.
- process: the implement stage sent two `ci/iris.sh` calls in one message, and its `Test.Mcp.Attach` green may have run an older McpOps job (Design Notes 23) -- this review's run of `Test.Mcp.Attach` on a fresh warm stack, with the final `Mcp.Ops` loaded at production start, passed (36.9 s).

## Spec Change Log

- 2026-11-11 (runner, rulings applied): the Contest Planner's rulings (verbatim under Design Notes) are applied. Public text 1-8 (the `MESSAGE*` table) is APPROVED verbatim: the implement stage uses those exact texts. Veto items accepted, with the CONDITION on the resource and grant met as stated under Design Notes (one fixed entry point, `Install.Step.Mcp.Grant`/`Revoke`, with a refusal test and a new AC). Spine S1-S3 written (items table; AD-21 "Step 4 build"). No More to try or README line.

- 2026-11-11 (runner, spec gate): the split proposal is accepted (unattended decide U5): Story 22.8 "Classify MCP calls by fingerprint in the gate" is inserted in epics.md and planned next; DW-174, DW-724 and DW-1013 are re-owned to it. The Veto items, the Public text table and spine updates S1-S3 go to the Contest Planner (via the orchestrator) before the implement stage; the implement stage uses the proposed texts only once the runner records them accepted here.

## Review Triage Log

### 2026-11-11 — Review pass
- verdicts: 43 findings — high 0, medium 7, low 35, false 0, maybe-false 1
- findings:
  - `[medium]` `[patch]` Blind 1: unique index on (Server, Tool) is case-insensitive, so `Foo` and `foo` share a row and are cleared on every attach — verified (default collation); fixed by RP1 (`COLLATION = "EXACT"`, `TestToolNamesAreCaseSensitive`, mutation line).
  - `[low]` `[reject]` Blind 2: `AttachOne` marks the server unavailable when one tool's fingerprint throws — AI Hub lists `parameters` from the server's JSON input schema, so non-JSON text is theoretical (`wontfix-theoretical`; real if AI Hub returned `parameters` as non-JSON text).
  - `[low]` `[reject]` Blind 3: an unavailable report wipes `RefusedTools`, so the shadow notice can repeat after a flap — by-design: 35.1 pins "unavailable has no refused tool" (`Test.Mcp.Tools`, `Test.Mcp.Attach`), and a server coming back with a refused name is newly refused.
  - `[low]` `[reject]` Blind 4: `Unregister` does not restore the grant when `Revoke` fails after a partial %SYS change — needs a mid-way %SYS API failure (`wontfix-theoretical`; `Revoke` removes the pair, then the resource, each one call).
  - `[low]` `[reject]` Blind 5: add discards the address and remove leaves the Config Store entry and secret — by-design: DW-1041 and the spec's Never line leave that write to Story 21.4.
  - `[low]` `[patch]` Blind 6: `AddressAllowed` accepts ports 0 and above 65535 — fixed by RP2 (1 to 65535, `TestBadAddress`, mutation line); host-character checks not added (a bad host only fails to attach).
  - `[low]` `[patch]` Blind 7: several cases untested (port forms, no `fingerprints` member, empty or long names) — port forms and the no-`fingerprints` case added (RP2, RP4c); empty and over-long names stay untested (`Skipped` is a one-line guard).
  - `[low]` `[reject]` Blind 8: `Classify` accepts a refused (shadowing) tool — by-design: the spec's "discovered tool" includes refused ones, and a refused tool can never be called.
  - `[low]` `[patch]` Blind 9: `Attach.cls` comment says no admin look-up, but `RecordAttach` notifies — comment corrected (RP3).
  - `[low]` `[patch]` Blind 10: `Mock` header states the backlog's CI-load effect as fact — hedged as (inference) (RP3).
  - `[medium]` `[patch]` Edge 1: collation — same root cause as Blind 1 (RP1).
  - `[medium]` `[patch]` Edge 2: `ClassifyTool` for `ZZ_LOOKUP` would change the `zz_lookup` row — same root cause (RP1; `FOO` is now `not_found`).
  - `[maybe-false]` `[reject]` Edge 3: `RemoveMcpServer` with a different case may leave a resource — IRIS resource names are probably case-insensitive (inference) and the UI offers registered names only; if true the harm is low.
  - `[low]` `[reject]` Edge 4: `OnAdd` Catch leaves an orphan row if `Register` throws — the calls return statuses; a throw after the save is theoretical (`wontfix-theoretical`).
  - `[low]` `[reject]` Edge 5: `Unregister` no re-grant when `Revoke` fails — same as Blind 4.
  - `[low]` `[reject]` Edge 6: bare `TROLLBACK` rolls back an outer transaction — the item runs at `$TLevel` 0 (`wontfix-theoretical`).
  - `[low]` `[reject]` Edge 7: flapping server repeats the shadow notice — same as Blind 3.
  - `[low]` `[reject]` Edge 8: a notice is lost if `AdminSessions` fails — by-design: the matrix says one warning and no re-send of the same report.
  - `[low]` `[reject]` Edge 9: fingerprint throw makes the server unavailable — same as Blind 2.
  - `[low]` `[reject]` Edge 10: a listed tool with a status other than available loses its row — by-design: the matrix deletes rows of tools no longer listed or refused.
  - `[low]` `[patch]` Edge 11: `AddressAllowed` host and port forms — the port range is fixed (RP2); same as Blind 6.
  - `[low]` `[reject]` Edge 12: `Grants()` does not check the cursor's SQLCODE after the loop — theoretical (`wontfix-theoretical`); the prepare and execute errors are warned.
  - `[low]` `[patch]` Edge 13: `WithPair` sets an existing pair to `U`, which the `Grant` doc said it leaves — doc corrected (RP3).
  - `[low]` `[reject]` Edge 14: `ClassifyTool` carries no fingerprint, so a tool can change between the admin's view and the command — by-design: the verb's shape is Lane B's and the spec binds the classification to the row's fingerprint at save time.
  - `[low]` `[reject]` Edge 15: claim that a failed `Revoke` rolls back and answers failed — same as Blind 4.
  - `[low]` `[reject]` Edge 16: `Tools` no longer answers OK with [] for an unknown server — by-design: the spec's contract; Story 21.4 consumes it.
  - `[medium]` `[patch]` Gap 1: dropping `parameters` from the fingerprint passes every test — verified; `TestToolFingerprint` added (RP4a, mutation line).
  - `[medium]` `[patch]` Gap 2: the real `OnlineDemo()` with the flag at 1 is never run — `TestOnlineDemoRealFlag` added (RP4b, mutation line).
  - `[low]` `[reject]` Gap 3: the real `Notice` to `NoticesIn.Send` never runs in a test — `Notice` is a one-line delegate (the `BridgeSink` precedent), `Test.Core.NoticesIn*` cover the service, `test-mcp-notices.sh` covers the keys and slots (`wontfix-accepted`, reopen_if a notice is not seen by an admin session in a real run).
  - `[medium]` `[patch]` Gap 4: refused-tool transitions and the no-`fingerprints` report are unpinned — cases added to `TestRecordAttachRows` (RP4c, mutation line).
  - `[medium]` `[patch]` Gap 5: ACs 1 to 5 and 7 lack mutation lines — 17 mutations applied, observed red and reverted (RP5); the `Failed`-text variant of the AC 7 leak mutation was not run.
  - `[low]` `[reject]` Gap 6: "one warning" outcomes are not counted — the outcomes and rows are asserted; the warning is a log line (`wontfix-accepted`, reopen_if a refusal stops being logged).
  - `[low]` `[patch]` Rule 19 a: expected fingerprints are computed with the function under test in `TestAttach` and `TestReports` — covered by the independent checks of RP4a (44 characters, schema-only change).
  - `[low]` `[patch]` Rule 19 b: `TestClearChanged` promises a notice it does not assert — asserted (RP4d).
  - `[low]` `[reject]` Rule 19 c: `Leftovers` runs after `Clean` — the in-test assertions carry the leak checks (`wontfix-accepted`).
  - `[low]` `[reject]` Rule 19 d: tests rely on the installer's role and instance-wide state — same as the Roles and Install tests of this epic (`wontfix-accepted`).
  - `[low]` `[reject]` Rule 19 e: `TestCommands` asserts a restart by job change and a hard-coded `Leftovers` string — `Overlap` carries the real check; the string is the helper's own contract (`wontfix-accepted`).
  - `[low]` `[reject]` Other 1: `Tools` returns an error for an unknown server — same as Edge 16.
  - `[low]` `[reject]` Other 2: `SetSourcePoll` and `RemoveSourcePoll` answer `failed` instead of `not_built` now that the item exists — Story 22.5 builds them, and no UI sends them yet (`wontfix-accepted`, reopen_if a UI sends them before 22.5).
  - `[low]` `[reject]` Intent 1: the tests mostly run on a probe subclass, with the real item in `TestCommands` only — `TestCommands` runs the real item through `CommandsIn`, and the real `OnlineDemo` is now covered (RP4b).
  - `[low]` `[reject]` Intent 2: a refused tool's row has an empty fingerprint, so a later listing clears its classification — by-design: Design Notes 12 and 13, fail-safe.
  - `[low]` `[reject]` Intent 3: `ClearChanged` leaves the row cleared when its audit fails — the status is an error and the admins are told; the matrix states no other outcome (`wontfix-accepted`).
  - `[low]` `[reject]` Intent 4: no restart on classify, the extra verbs and the mock backlog are not in the intent — recorded as Design Notes 11, 17 and Task 0.

## Design Notes

**Governing ADs (Rule 6):** AD-1 (commands through `CommandsIn`; origin `web_admin` only for the MCP verbs, L117), AD-2 (the bridge names no host package), AD-3 (only `Install.*` switches to `%SYS`), AD-10 (MCP classified by toolref first, a per-server resource), AD-17 (one audit writer; MCP and Tool shapes), AD-19 (secrets only as `secret://`; `@{` refused; DW-1041 ruling L635), AD-21 (MCP servers, `Tools(server)`, `McpOps` writes, every discovered tool has a row), AD-22 (loopback mock), AD-23 (installer areas), AD-24 (service user and role; the limits), AD-25 (online demo), AD-29 (lanes), AD-31 (`McpServersClass` report), AD-32 (notifications, producers never render), AD-33 (`McpOps` sole writer of both tables; items table L1383).

**AC 1's Config Store clause (runner note 2, DW-1041).** Lane B's Story 21.4 delivers it, per the ruling in AD-19 L635 ("Story 21.4 moves that write into `McpOps`"). This story writes no entry and no secret. `OnAdd` runs Validate, then Register (row, then resource and grant), then Audit, then Restart. `OnRemove` runs Unregister, then Audit, then Restart. 21.4 inserts one call: after Validate in add, and after Unregister in remove. This story's tests create the entry and the wallet secret as fixtures, as 35.1's `Attach.Register` does. This is consistent with AD-1 (no REST write), AD-19 and AD-21.

**ACs already met (evidence, nothing to build):**
- AC 8: MCP recognised first, annotations ignored.
  - `Gate.Source` L223-229 returns the `mcp:` toolref before `origin_class`; `RagCall` L234 excludes `mcp:`; `FromExtension` L406 reads no annotation.
  - Pinned by `Test.Bridge.Gate` TestMcpShadow L619, and by `Test.Mcp.Attach` TestAttach L132-138 (the real `mcp:remote:@{config:…}` toolref; the mock's `readOnlyHint` tool stays unclassified).
- The `CommandsIn` refusal of origin `tool` named in ACs 4 and 9: `CommandsIn` routes L297-301 and `Test.Core.CommandsStep4` (Story 35.2). This story adds `McpOps`'s own second check.

**Split proposal (product default 6; for the runner's ruling).** This spec plans part 1 only. Proposed sibling **Story 22.8, "Classify MCP calls by fingerprint in the gate"**, planned next in this epic, receives:
- AC 6 (the fingerprint map from `%Discover()` before `Chat` in the bridge context; the gate classifies through `ClassificationClass`, with missing, unclassified or changed counting as risky; read-only MCP tools map to safe plus read-only);
- AC 2's clause "the gate denies any call to them at once";
- AC 7 for a change found during a turn (it reports through `McpOps.ClearChanged`, built here);
- DW-174, DW-724 and DW-1013 (the amendment at the top of the story).

No AC is dropped. Every other AC and the 2026-11-09 notices amendment stay here.

**Ledger inbox (Rule 17):**
- DW-1038: addressed. Task 0, plus the `Test/Mcp/Attach.cls` and `Mock.cls` tasks.
- Declined DW-174: the toolref and metadata measurement in `%CanExecute` belongs with the gate's MCP classification, proposed Story 22.8. The remote form is already measured (35.1 Task 0 evidence L93-99), and this story changes no gate code.
- Declined DW-724: `ToolsReadOnly` counting attached servers needs 22.8's MCP classification lookup, proposed Story 22.8.
- Declined DW-1013: the bounded attach and listing timeout belongs with 22.8's per-turn listing (`%Discover` before `Chat`) and `BuildTurnManager`, proposed Story 22.8. The descriptor accepts no timeout key (`irislib/%AI/ConfigStore/MCPDescriptor.cls` L16), so the bound is an OcuTalon probe that still needs a Task 0 on a throwaway (inference).

**Decided in-stage:**
1. The Config Store clause goes to 21.4, as above.
2. The resource and grant go through a new `Install.Step.Mcp` area (in Epic 22's footprint): run-time `Grant`/`Revoke` called by `McpOps`, which has precedent in `SettingsOps` -> `Install.Step.Demo`. They are declared again at every start by `Grants()`, because `Roles.Apply` rewrites the role.
3. Notification kind `status`. Notices are sent only on a transition, so several runners and repeated builds send one notice.
4. Rows are also kept for refused tools. An attached report deletes the rows of tools it no longer lists.
5. One `Fingerprint` per row. A classification binds to the fingerprint the row holds when the admin classifies, and a different reported fingerprint clears it.
6. A classification change is audited as type `Tool` (`read-only` -> `safe` with `readOnly` 1), with `source` the server's name.
7. Refusals reuse `CommandsIn`'s existing sentences; "Saved" is the UX's (EXPERIENCE L362).
8. A failed restart keeps the saved change and answers `failed`.
9. An empty `ActingUser` is refused.
10. The fingerprint is `Context.ArgumentsHash` of `{description, parameters}`.
11. A classification restarts no runner: the gate reads the rows at call time, so only add and remove call `RestartRunners()`. The restart runs after the server's lock is released, so a runner's `RecordAttach` is never held back by it.
12. The report's `fingerprints` member is set only for an attached server; an unavailable report keeps its old shape. `RecordAttach` reads a missing member as no fingerprints.
13. An unavailable report keeps the tool rows. A refused tool has a row with an empty `Fingerprint` and keeps its classification; if it is listed later, the new fingerprint differs from the empty one, so a classified row is cleared (fail-safe). An unclassified row whose fingerprint changes only takes the new one, with no audit and no notice. A tool name that is empty or longer than 128 characters gets no row.
14. The seams (`OnlineDemo`, `AdminSessions`, `Notice`, `Restart`, `WriteAudit`) are private class methods, so `RecordAttach` and `ClearChanged` (class methods) share them with the handlers; the tests override them in `Test.Mcp.OpsProbe`. `TestShadow`, `TestUnavailable` and `TestChangedTool` use `Test.Mcp.ZzProbeAttach` (hands the report to the probe) with a real fixture admin session, so a notice is read in the test's own process; `TestAttach` and `TestCommands` use the real `Mcp.Attach` and `Mcp.Ops`.
15. The address check reads the host as a client would: scheme `https://` or `http://` in any letter case, no user information (`@` in the authority), an optional numeric port of at most five digits, no control character, space or backslash. `http://` needs a host of `127.0.0.1`, `localhost` or `[::1]`.
16. A remove runs in one transaction (tool rows, row, `Revoke`, audit). A failed `Revoke` rolls back and answers `failed`; a failed audit rolls back, grants the resource again and answers `not_audited`.
17. `SetSourcePoll` and `RemoveSourcePoll` (Story 22.5) are routed to `McpOps`, which now exists and handles neither: `CommandsIn` answers `failed`, where it answered `not_built` while the item was missing. No user interface sends them before 22.5 builds them.
18. The warm throwaway of tag `e22s2iw` refuses a changed non-class file (`src/short-names.tsv`), so the one `McpTool` line was taken out for the warm runs and put back before the script checks; the final tree has it.
19. `ToolClassification.Tool` collates EXACT, so the unique index and `ServerToolIndexOpen` tell `Foo` from `foo`. The class is new in this story, so no installed index needs a rebuild.
20. A port is 1 to 65535: its digits are read as a number, so `0`, `00000`, `65536` and `99999` are refused and a leading zero (`00080`) is read as 80.
21. A classified tool newly reported refused keeps its classification and has an empty fingerprint, with no Tool audit and no `mcp.toolChanged` notice. It still sends the `mcp.toolShadowsBuiltIn` notice, because it is a newly refused name; `TestRecordAttachRows` asserts the absence of the first two only.
22. The real `Ops.OnlineDemo()` is exercised through `OpsProbe` with its `^||ZzOps("demo")` node unset (the probe then calls `##super`): `TestOnlineDemoRealFlag` sets the real `onlineDemo` setting to 1 and restores it. `TestOnlineDemo` (the probe's switch) stays.
23. A warm throwaway's McpOps job keeps the class code it loaded before a class reload, so a mutation of `Mcp.Ops` that `TestCommands` must see is applied together with a temporary two-line shim in `TestCommands` that disables and enables the McpOps item (reverted byte-identical). The unmutated tests do not bounce the item, so a plain `TestCommands` run after an `Mcp.Ops` change can run the job's older code until the item restarts; CI starts the production fresh.

**Extend, don't copy (Rule 2):**
- The handlers follow `Watch.Ops`' `MessageMap` and `Answer`. `Answer` is a 7-line private helper of each operation and is copied (operations share no base).
- The sender and origin check follows `PrecedentOps.FromVerb`, a Lane B class that can't be extended.
- `Install.Step.Mcp` extends `Install.Step` like `Tools`, with `Demo.ServiceRole`'s Get/Modify.
- `ToolClassification` mirrors `Server`.
- `ToolFingerprint` extends `ArgumentsHash`.
- The notice seam mirrors `BridgeSink.Notice`.

**Integration ACs (Rule 1):**
- Consumer `CommandsIn` (real) sends the three verbs to `McpOps`; the effect is the row, resource, audit and restart (AC 1).
- Consumer `Mcp.Attach.OnAttach` (a real runner build against the mock) produces rows that `Tools` lists (AC 2).
- Consumer `Install.Step.Roles` composes the grant (AC 5).

**Consumes:**
- 35.1: `Mcp.Server`, `RecordAttach`, `Attach`, the mock.
- 35.2: the verbs, the `CommandsIn` routes, `RestartRunners()`, `AdminSessions()`.
- `Bridge.Audit`, `Catalog.Watch`'s `mcp.*` keys, `NoticesIn`.

**Consumed-by:**
- 21.4: `Tools(server)`, the verbs' handlers, the entry call site.
- 22.8 (proposed): rows and fingerprints for the gate, `ClearChanged`.
- 22.3: the resource, for the permission check.
- 22.4: `OnRemove` gains `Approval.Cancel`.
- 22.5: the read-only classification and the `SetSourcePoll` handler.

**Spine updates for the lead (Rule 20; extensions where the spine is silent):**
- S1: items table L1383 drops "not in the production until Story 22.2".
- S2: AD-21 Changes: the per-server resource is created and granted `U` to `OcuTalonServiceRole` at run time by `McpOps` through `Install.Step.Mcp`, declared again at every start by the area's `Grants()` from the rows, and declared on no online-demo install.
- S3: AD-21/AD-31 L1103: the attach report gains `fingerprints`. `RecordAttach` keeps a row per discovered tool (refused ones included), deletes rows no longer listed, clears a classified tool whose fingerprint changed, and sends the three admin notices (kind `status`) on transitions.


**Contest Planner rulings (verbatim)** [RULED 2026-11-11 ~13:40Z, Contest Planner under the owner's delegation, relayed by the orchestrator; source `<coordination>/prompts/epic-22-rulings-222-228-229.md`]:

> # Rulings, Epic 22 spec gate: 22.2, 22.8, 22.9 (2026-11-11 ~13:40Z; Contest Planner under the owner's delegation; verbatim terms)
> SPLIT ACCEPTED (22.8, 22.9 new; order 22.2, 22.8, 22.9, 22.3-22.7; DW-1041 respected). No More to try or README line (no UI, MCP off on the demo); 22.6's governance doc carries the public explanation later.
> PUBLIC TEXT 1-9: APPROVED verbatim.
> VETO 22.2: ACCEPTED: ToolClassification (no URL, secret or user), McpOps present on the demo refusing every MCP verb, the admin notices.
> CONDITION on the run-time resource OcuTalon_MCP_<server> and its U grant: state in the spec exactly which process creates the resource and grant, and with what privilege. The service role (and McpOps' job) must NOT gain %Admin_Secure, %All or any security-administration privilege to do it. Acceptable: the installer step declares them at start, or one fixed privileged entry point that can only create/grant/remove OcuTalon_MCP_* resources and is unit-tested to refuse any other name. If the design needs a broader privilege on a production job, STOP for a ruling before implementing.
> VETO 22.8: ACCEPTED as AD-10 already allows it, with two conditions:
> (1) the tool's fingerprint must match its classification at call time (a changed fingerprint makes it Unclassified, so it's held or denied as such); test that a rug-pull (same name, changed schema or description) is caught.
> (2) 22.6's governance doc must say plainly that a Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, so classify a tool Read-only only when you trust its server with what OcuTalon reads. Bring that sentence to the Planner at 22.6's gate.
> Unknown/removed servers denied, not held: ACCEPTED.
> VETO 22.9: ACCEPTED (2 s initialize probe to admin-registered servers only, the 60 s rest, no MCP server on the agent's own manager, side effects as listed).
> RESIDUAL: (a). Accept it now; 22.6 documents it; the AD-21 amendment (OcuTalon lists and offers MCP tools through its own bounded client) becomes a NEW story in Epic 22's backlog, after 22.7.
> GRAPH: lift 36.1's epic-22 wait entirely, plain-union rule for the Checks and BackgroundCheck files 22.5 also touches, marker [AMENDED 2026-11-11, Contest Planner ruling: footprint only, not a real dependency].
> NEXT-FREE-LANE ORDER: (1) the memory-documents-remember phrase fix (DW-1123, ~30 min), (2) 36.1, then the step-5 chain (36.2, 37.1, 24, 23.4, 23.8; 23.3's plan to the Planner first), (3) 25.3.
> ORCHESTRATOR U7 spine wording S1-S11: fine under these conditions.

**How this spec meets the 22.2 CONDITION** (runner, 2026-11-11): the resource `OcuTalon_MCP_<server>` and its `U` grant to `OcuTalonServiceRole` are created and removed by `McpOps`' production job (the `McpOps` item, `OcuTalon.Mcp.Ops`), whose privilege is the Interoperability system user's, which AD-24's limits already state (the production runs as that user); nothing is added to it. The ONLY code that touches `%SYS` for this is one fixed entry point, `OcuTalon.Install.Step.Mcp.Grant(server)` and `Revoke(server)` (AD-3). It derives the resource name itself as `OcuTalon_MCP_` + the server name, refuses (returns an error and changes nothing) any server name that fails `OcuTalon.Mcp.Server`'s `NAMEPATTERN`, and only creates/deletes that one resource and adds/removes that one `resource:U` pair on `OcuTalonServiceRole`, leaving every other resource and role untouched. `OcuTalonServiceRole` gains only `OcuTalon_MCP_<server>:U`; neither it nor `McpOps` gains `%Admin_Secure`, `%All` or any security-administration privilege. At start, `Install.Step.Mcp.Grants()` declares the same pairs from the rows (none on an online demo). No broader privilege on a production job is needed, so no STOP.

## Veto items

- **Resource and grant.** `OcuTalon_MCP_<server>` (no public permission), created at run time and granted `U` to `OcuTalonServiceRole` by `McpOps` through `Install.Step.Mcp` (a `%SYS` write by an `Install.*` method, AD-3), and removed with the server.
  - The service user is a privilege profile only (AD-24 limits).
  - Online demo: `McpOps` refuses add, remove and classify, so no resource, row or grant can exist, and `Grants()` declares none.
- **New stored table.** `OcuTalon.Mcp.ToolClassification` (`Server`, `Tool`, `Classification`, `Fingerprint`, `ChangedAt`; global `^OcuTalonP.McpTool`). It holds no URL, secret or user name. Rows live only as long as their server, and a tool the server stops offering loses its row at the next attach.
  - Online demo: always empty.
- **New production item `McpOps`** in the shared production.
  - Online demo: present, but it refuses every MCP verb with a plain reason.
- **Admin notices** (internal chat notices, no outward action). Online demo: never sent, since no server can exist there.

## Public text

**New, proposed** (parameters of `OcuTalon.Mcp.Ops`, the `Message` of its `CommandResult`). The implement stage uses each text only after the runner accepts it:

| Parameter | Text |
| --- | --- |
| `MESSAGEADDED` | "The MCP server was added. Its tools count as risky until an admin classifies them." |
| `MESSAGEREMOVED` | "The MCP server was removed, so its tools can't be used." |
| `MESSAGEADDRESS` | "An MCP server's address must start with https:// (or point to this computer, for development). Nothing was changed." |
| `MESSAGENAME` | "An MCP server's name is a letter followed by up to 39 letters, digits or underscores. Nothing was changed." |
| `MESSAGEEXISTS` | "An MCP server with that name already exists. Nothing was changed." |
| `MESSAGENOSERVER` | "There is no MCP server with that name. Nothing was changed." |
| `MESSAGENOTOOL` | "That MCP server has no tool with that name. Nothing was changed." |
| `MESSAGECLASSIFICATION` | "A tool is Unclassified, Read-only or Risky. Nothing was changed." |

**Already given verbatim:**
- "Saved" (EXPERIENCE L362).
- `CommandsIn` `MESSAGEADMINONLY`, `MESSAGENOTFROMTOOL`, `MESSAGENOTALLOWED` and `MESSAGEFAILED` (L65-79).
- The keys `mcp.serverUnavailable`, `mcp.toolShadowsBuiltIn` and `mcp.toolChanged` (accepted in 35.1).

## Verification

Each `ci/iris.sh` call carries the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`. Use the warm stack: `OCUTALON_RUN_TAG=e22s2iw ci/warm.sh up` once, `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s2iw` on each class call, and `ci/warm.sh down` at the end, even after a failure. Run one call at a time in the foreground with `timeout: 600000`.

**Commands:**
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Ops` -- expected: `CLASS … passed`
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Tools` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Attach` -- expected: passed (needs the production; warm stack)
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Loopback` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Install.Production` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Gate` -- expected: passed (the `Context` change)
- (loop) `bash docker/tests/test-storage.sh`, `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-mcp-notices.sh` -- expected: exit 0

No `(once)` lines. The full suite is left to CI (groups `shards` and `shards-2`), and the lead runs Rule 19's fresh-environment check.

**Shared surfaces:**
- the production's item list (`Test.Install.Production` oracle);
- the `Tools(server)` contract (`Test.Mcp.Tools` TestTools, which replaced TestToolsStub);
- the attach report shape (`Test.Mcp.Attach` TestReports, `ZzServers`);
- the resources of `OcuTalonServiceRole` (`Roles.Compose`, the generated security overview);
- `src/short-names.tsv` (`test-storage.sh`);
- the `Mcp.Server` and `ToolClassification` rows (the Attach tests' `Leftovers`);
- notifications to admin sessions.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Task 0 result (DW-1038), 2026-11-11, warm throwaway `e22s2iw`, build 154U:** the mock's `ConnectionQueueSize` is now 5 (`Mock` `BACKLOG`) with `KeepAliveInterval` -1, and `OcuTalon.Test.Mcp.Loopback` stayed green (3.1 s), so the backlog is kept and the bounded-retry fallback is not used. `Test.Mcp.Attach` passed in 37 to 40 s on each of its four unmutated full runs after the change. The guard against CI load is (inference): the queue holds up to 5 connections that arrive while the single mock job answers another, where the old queue of 0 refused them; no loaded-CI run was made.

**Mutations (Rule 19), each applied, observed red, reverted (`cmp` byte-identical to the saved file):**
- mutation: dropped `|| (origin '= ..#ORIGIN)` from `Ops.Refusal` -> `Test.Mcp.Ops` `TestWrongSender` red (web_user, system and empty origins carried out).
- mutation: `AddressAllowed` ends `Quit 1` instead of the loopback test -> `Test.Mcp.Ops` `TestBadAddress` red.
- mutation: `Ops.Register` does not call `Install.Step.Mcp.Grant` -> `Test.Mcp.Ops` `TestAdd` red (resource and pair missing), with `TestRemove`, `TestRolesCompose` and `TestEntryPointRefusesOtherNames`.
- mutation: `Install.Step.Mcp.Grants()` without its online-demo line -> `Test.Mcp.Ops` `TestRolesCompose` red.
- mutation: `Ops.KeepRow` ends `Quit $$$OK` instead of `ClearRow` -> `Test.Mcp.Attach` `TestChangedTool` red.
- mutation: `RecordAttach` raises the unavailable event on every unavailable report -> `Test.Mcp.Ops` `TestNotices` red.
- mutation: `Ops.Tools` without the `RefusedTools` test -> `Test.Mcp.Tools` `TestTools` red.
- mutation: `AttachOne` without `Set report.fingerprints = fingerprints` -> `Test.Mcp.Attach` `TestAttach` red (also `TestChangedTool`, `TestCommands`, `TestReports`).
- mutation: the `McpOps` item taken out of `Production.cls` -> `Test.Install.Production` `TestDefinition` red and `Test.Mcp.Attach` `TestCommands` red.
- mutation: `Install.Step.Mcp.ResourceOf` with `{0,60}` in place of `NAMEPATTERN` -> `Test.Mcp.Ops` `TestEntryPointRefusesOtherNames` red (the 41-character name is accepted by Grant and Revoke).
- mutation: `Ops.McpData` names the command's `Url` as the audit entry's `server` -> `Test.Mcp.Attach` `TestCommands` red (the add is no longer answered added).
- mutation (RP1): `ToolClassification.Tool` without `COLLATION = "EXACT"` -> `Test.Mcp.Ops` `TestToolNamesAreCaseSensitive` red (Foo and foo share one row, the repeat clears it, `FOO` is found).
- mutation (RP2): `AddressAllowed` without the 1 to 65535 test on the port -> `Test.Mcp.Ops` `TestBadAddress` red (`:0`, `:65536`, `:99999`, `:00000` accepted).
- mutation (RP4a): `Context.ToolFingerprint` hashes the description only (the `parameters` member not set) -> `Test.Mcp.Ops` `TestToolFingerprint` red (a schema-only change gives the same fingerprint).
- mutation (RP4b): `Ops.OnlineDemo` ends `Quit 0` -> `Test.Mcp.Ops` `TestOnlineDemoRealFlag` red (all three verbs are carried out while the `onlineDemo` setting is 1).
- mutation (RP4c): `Ops.KeepRow` calls `ClearRow` in its refused branch -> `Test.Mcp.Ops` `TestRecordAttachRows` red (a classified tool reported refused loses its classification, with an audit entry and an `mcp.toolChanged` notice).
- mutation (RP5, Remove), one line per change, all `Test.Mcp.Ops` `TestRemove` red: `Unregister` skips `DeleteTools` (the tool rows stay); skips `Revoke` (the resource and the grant stay); skips the `removed` audit (the log holds `added` only; `TestAuditFails` also red).
- mutation (RP5, Classify): `Ops.Classify` blanks the row's `Fingerprint` -> `Test.Mcp.Ops` `TestClassify` red (the row no longer keeps its fingerprint); `Classify` skips the Tool audit -> `Test.Mcp.Ops` `TestAuditFails` red (a failed audit is no longer answered `not_audited`) and `TestClassify` errors on the missing entry.
- mutation (RP5, changed tool): `ClearRow` skips the Tool audit -> `Test.Mcp.Ops` `TestChangedTool` and `TestClearChanged` red; `ClearRow` does not set `events("changed", tool)` -> `Test.Mcp.Ops` `TestChangedTool`, `TestClearChanged` and `TestRecordAttachRows` red (no `mcp.toolChanged` notice).
- mutation (RP5, AC 1): `Register` skips the `added` audit -> `Test.Mcp.Ops` `TestAdd` red (also `TestAuditFails`, `TestRemove`, `TestRestartFails`, `TestBadNameAndTaken`); `Restarted` skips `Restart()` -> `Test.Mcp.Ops` `TestAdd` red (the restart count is 0; also `TestRemove`, `TestRestartFails`).
- mutation (RP5, `Grants()`): `Install.Step.Mcp.Grants` without the `ResourceExists` check -> `Test.Mcp.Ops` `TestRolesCompose` red (a row whose resource is missing still declares its pair, and no warning is raised).
- mutation (RP5, AC 7 leak): `Register` gives `McpData` the server value `<name> <Url>`, with the McpOps item bounced first (Design Notes 23) -> `Test.Mcp.Attach` `TestCommands` red on "no OcuTalon audit entry holds the mock's address or the secret" and on no other assertion. The `Failed`-text variant was not run.

**QA stage (2026-11-11, warm throwaway `e22s2qa`), tests added or changed (QA):**
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Ops.cls` (QA): new `TestNoAddressOrSecretInAnyText` (AC 7: a marked address and a marked credential in the failure text of an attach report show in no result of add, bad address, taken, bad name, wrong sender, failed audit, failed restart, classify, bad classification and remove, in no notice, audit entry, event-log row; with positive controls); `TestEntryPointRefusesOtherNames` now runs all Grants, checks, then all Revokes, checks (a Revoke could undo what a Grant made), and snapshots and restores the OcuTalon roles and OcuTalon_MCP_ resources in its clean-up (`Guard`/`Restore`) so a wrong refusal leaves nothing for the next test.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls` (QA): `Leaks` also looks in the notices that the probe recorded, for the secret and for the mock's address.

**QA mutations (Rule 19), each applied, observed red, reverted (`cmp` byte-identical to the saved copy; `git status --short` shows only the two QA test files):**
- mutation (AC 7, result message): `OnAdd` answers `bad_address` with `MESSAGEADDRESS _ " " _ request.Url` -> `Test.Mcp.Ops` `TestNoAddressOrSecretInAnyText` red on "no result holds the address or the credential" (also `TestBadAddress`, by its exact message).
- mutation (AC 7, notice): `RecordAttach` sets `events("unavailable")` to the report's reason and `Notify` adds it to the `mcp.serverUnavailable` slots -> `Test.Mcp.Ops` `TestNoAddressOrSecretInAnyText` red on "no notice holds the address or the credential" and on no other assertion.
- mutation (AC 7, notice, real secret): the same `Ops` change plus `AttachOne` putting `GetErrorText(sc)` (which holds the secret) in `report.reason` -> `Test.Mcp.Attach` `TestUnavailable` red on "the secret, which AI Hub's error text holds, shows in none of the places that are checked"; with the `Leaks` notice lines taken out (HEAD's `Attach.cls`) the same mutations leave that assertion green (only the row assertion is red), so the new place is what pins it.
- mutation (online demo, per verb): `OnAdd`, `OnRemove` and `OnClassify` each skip `Refusal` while `OnlineDemo()` is true -> `Test.Mcp.Ops` `TestOnlineDemo` and `TestOnlineDemoRealFlag` red on "an add on the online demo is refused", "a remove is refused" and "a classification is refused" (and on nothing written / no grant).
- mutation (condition AC, refusal half): `Grant` and `Revoke` ignore `ResourceOf`'s error and build `OcuTalon_MCP_<name>` themselves -> `Test.Mcp.Ops` `TestEntryPointRefusesOtherNames` red on "Grant refuses" / "Revoke refuses" for 11 of the 12 names, and on "after the Grants no resource is created or deleted" and "the resources of every OcuTalon role ... are byte-identical".
- mutation (condition AC, valid add half): `WithPair` also appends `%Admin_Secure:U` -> `Test.Mcp.Ops` `TestEntryPointRefusesOtherNames` red on "the service role gained exactly OcuTalon_MCP_<server>:U" and "no OcuTalon role gained an %All or %Admin_ resource".
- mutation (Remove of an unknown server): `Unregister` answers `removed` and asks for a restart when there is no row -> `Test.Mcp.Ops` `TestRemove` red ("removing '...' is not_found" for the four names, "no runner was restarted") and `TestNoAddressOrSecretInAnyText`.
- mutation (`Tools` of an unknown or empty server): `Ops.Tools` answers OK for a missing row -> `Test.Mcp.Tools` `TestTools` red ("Tools of 'zzmcpnosuch' is an error", "Tools of '' is an error").

**Code review mutations (Rule 19, 2026-11-11, warm throwaway `e22s2cr`), each applied, observed red, reverted (`cmp` byte-identical to the saved copy; `git status --short` unchanged):**
- mutation (AC 7, the `Failed` text variant): `Register`'s failed-audit branch passes `"... so it was undone " _ request.Url` to `Failed` -> `Test.Mcp.Ops` `TestNoAddressOrSecretInAnyText` red on "no event-log row holds the address or the credential" and on no other assertion.
- mutation (AC 1, the real restart): `Ops.Restart()` ends `Quit $$$OK` instead of calling `SettingsOps.RestartRunners()`, with the McpOps item bounced at the start of `TestCommands` (Design Notes 23; the two-line shim reverted with it) -> `Test.Mcp.Attach` `TestCommands` red on "the runner items have new jobs" and "none of the runner jobs of before is still alive"; every `Test.Mcp.Ops` restart line runs on the probe's counter, so this is the real seam's pin.

**Pinning mutations to record (Rule 19):** each mutation should turn the named test red.

| Mutation | Test that goes red |
| --- | --- |
| Drop the origin re-check | `Test.Mcp.Ops` origin test |
| Accept `http://example.com` | the address test |
| Skip `Grant` | the add test (resource read-back) |
| Skip the `Grants()` online-demo branch | the roles test |
| Do not clear on a changed fingerprint | the changed-tool test |
| Notify on every report | the notice-once test |
| Ignore `RefusedTools` in `Tools` | `Test.Mcp.Tools` |
| Remove `fingerprints` from `AttachOne` | `Test.Mcp.Attach` TestAttach |
| Remove the `McpOps` item | TestCommands and `Test.Install.Production` |

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Mcp.Ops` is the `McpOps` item: it handles `AddMcpServer`, `RemoveMcpServer` and `ClassifyTool` (sender and `web_admin` origin re-checked, refused on the online demo, address and name checks, audit, restart), keeps one `ToolClassification` row per discovered tool from the attach report (new fingerprints, stale-row delete, changed-tool clear, three admin notices once per transition) and answers `Tools(server)`. The resource `OcuTalon_MCP_<server>` and its `U` grant go only through `Install.Step.Mcp.Grant`/`Revoke` (refuse any name failing `NAMEPATTERN`; no `%Admin_*` or `%All`), declared again at every start by `Grants()` (none on the online demo). Task 0 (DW-1038) kept the mock's `ConnectionQueueSize` 5.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls`: the item, `Tools`, `RecordAttach`, `ClearChanged`, seams.
- `src/ocutalon/cls/OcuTalon/Mcp/ToolClassification.cls`: new stored table (exact-case tool names); `src/short-names.tsv`: one line.
- `src/ocutalon/cls/OcuTalon/Install/Step/Mcp.cls`: new area (`Grant`, `Revoke`, `Grants`).
- `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls`, `src/bridge/cls/OcuTalon/Bridge/{Context,Adapter/Agent,Ext/McpServers}.cls`: fingerprints in the attach report (`Context.ToolFingerprint`).
- `src/ocutalon/cls/OcuTalon/Production.cls` and `Test/Install/Production.cls`: the `McpOps` item and its oracle row.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/{Ops,OpsProbe,ZzProbeAttach}.cls` new; `{Attach,Mock,Tools}.cls` extended.

**Review.** 43 findings (medium 7, low 35, maybe-false 1). Patches applied: 5 medium entries (case-sensitive tool names, fingerprint test, real online-demo test, refused and no-fingerprint transitions, missing mutation lines) and 5 low (port range, comments x3, `TestClearChanged` notice). Deferred: none. Rejected: see the triage rows, each with its reason.

**Follow-up review recommended: true.** Patched mediums: 5 entries (7 findings). Unverified risk: the AC 7 leak assertions were shown red only by the address-in-audit-server mutation (through a temporary shim that bounces the `McpOps` item, Design Notes 23), and the `Failed`-text variant was not run; a warm stack's `McpOps` job keeps older class code after an `Ops` change.

**Verification.** On the warm throwaway `e22s2iw`: `Test.Mcp.Ops`, `Test.Mcp.Tools`, `Test.Mcp.Attach` (38 s), `Test.Mcp.Loopback`, `Test.Install.Production` (one SKIP, `TestStepHelpers`, because the production runs in that namespace) and `Test.Bridge.Gate` passed after the last patch; `test-storage.sh`, `test-ci-config.sh`, `test-class-rules.sh`, `test-mcp-notices.sh` and `test-boundaries.sh` exit 0. Not run: the full suite and the Rule 19 fresh-environment forward and reverse check (left to the lead and CI).

**Residual risks.**
- `SetSourcePoll` and `RemoveSourcePoll` answer `failed` (was `not_built`) until Story 22.5.
- The notice tests stop at the probe seam (the real `Notice` is a one-line delegate).
- Classify does not restart the runners (Design Notes 11).
- The Config Store entry and the wallet secret are written by Story 21.4 (DW-1041).
- Two `ci/iris.sh class` calls (`Tools` with `Loopback`, then `Production` with `Gate`) were sent in one message, against the one-per-message rule; all passed.
