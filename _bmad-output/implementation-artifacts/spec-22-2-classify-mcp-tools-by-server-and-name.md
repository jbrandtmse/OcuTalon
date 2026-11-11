---
title: 'Story 22.2: Classify MCP tools by server and name (part 1: McpOps, the per-server resource, the classification table and Tools)'
type: 'feature'
created: '2026-11-11'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
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

**Acceptance Criteria:**
- Given the production running with `McpOps`, when `Commands.Submit` sends `AddMcpServer` with origin `web_admin` and `CommandsIn` routes it, then the `CommandResult` is `Ok` 1 with `added`. The row and resource exist, the service role holds the resource with `U`, an `OcuTalon/MCP/MCP` `added` entry naming the acting user is in the audit log, and the runner items have new jobs.
- Given a shadow runner built with `McpServersClass` `OcuTalon.Mcp.Attach` and the loopback mock, when the build reports, then `Tools(server)` lists zz_delete_ticket and zz_lookup as `unclassified` and `available`, each row holding the fingerprint of its description and canonical input schema. Classifying zz_lookup `read-only` through `CommandsIn` keeps that fingerprint and audits it.
- Given a classified tool whose description or input schema the mock changes, when the next build reports, then the row is `unclassified` with the new fingerprint, a Tool audit entry `unclassified` exists, and each admin session gets one `mcp.toolChanged` notice.
- Given a registered server, when it is removed through `CommandsIn`, then its rows, resource and grant are gone, `Tools(server)` is an error, and the removal is audited.
- Given a start with registered servers, when the Roles step composes the roles, then `OcuTalonServiceRole` holds `OcuTalon_MCP_<server>:U` for each row whose resource exists. On an online-demo install it holds none.
- Given any test of this story, when its output, logs, audit entries and notices are searched, then the fixture secret and the mock's URL appear in none.

## Spec Change Log

- 2026-11-11 (runner, spec gate): the split proposal is accepted (unattended decide U5): Story 22.8 "Classify MCP calls by fingerprint in the gate" is inserted in epics.md and planned next; DW-174, DW-724 and DW-1013 are re-owned to it. The Veto items, the Public text table and spine updates S1-S3 go to the Contest Planner (via the orchestrator) before the implement stage; the implement stage uses the proposed texts only once the runner records them accepted here.

## Review Triage Log

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
- the `Tools(server)` contract (`Test.Mcp.Tools` TestToolsStub);
- the attach report shape (`Test.Mcp.Attach` TestReports, `ZzServers`);
- the resources of `OcuTalonServiceRole` (`Roles.Compose`, the generated security overview);
- `src/short-names.tsv` (`test-storage.sh`);
- the `Mcp.Server` and `ToolClassification` rows (the Attach tests' `Leftovers`);
- notifications to admin sessions.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

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

Status: ready-for-dev
Blocking condition: none
