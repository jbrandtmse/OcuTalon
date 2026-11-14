---
title: 'Story 21.4: Add, remove and classify MCP servers and tools in Settings'
type: 'feature'
created: '2026-11-12'
status: 'in-progress'
baseline_revision: '96bbbcd8ecb47dfd42eafb0b83cf1785d8099cd1'
review_loop_iteration: 1
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-35-3-send-events-to-ocutalon-through-a-webhook.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-2-classify-mcp-tools-by-server-and-name.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/35-1-task0-mcp-attach.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** An admin cannot manage MCP servers: `Web.Api` has no `/v1/settings/mcp` route, the page has no Tools and MCP servers section, and `SettingsOps.SaveMcpEntry`/`RemoveMcpEntry` are stubs, so an added server has a `Mcp.Server` row but no Config Store entry or wallet secret, and no runner can attach it. DW-1041: AD-1 forbids that write in the REST process.

**Approach:** Four admin-checked routes in a new `Web.McpSettings` (forwarded like `Web.HookSettings`). The secret goes REST -> `SecretHandoff` -> `McpOps`, and McpOps' own job writes and removes the wallet secret and the `AI.MCP.OcuTalon_<server>` entry (the ruled Lane A edit). The read is a new read-only command, `ListMcpServers`, answered by `SettingsOps` in its production job from `Mcp.Attach.Servers`, `Mcp.Ops.Tools(server)`, the entry's address and a pending-request count. A new Settings section shows the server list, Add server, a confirmed Remove and the tools table. The section, the routes and both handlers are off on the online demo, which shows a plain line instead. The changed-tool banner moves to a sibling story (Design Notes, proposed split).

## Boundaries & Constraints

**Always:**
- Every change is a command with origin `web_admin`, submitted through `Commands.Submit` by the admin-checked route (`OnPreDispatch` 403 `not_admin` first). The REST process writes no table, wallet or Config Store object, and reads none of Lane A's tables. The GET reads through `ListMcpServers`.
- The secret is never put in a command, message, log, trace, audit entry, global, answer, GET or test output. The route puts it into `SecretHandoff`, the command carries only `Handoff` (`secret://handoff/<name>`), McpOps takes it once, and the route discards the handoff on every path (`HookSettings.Hand`'s rule). Each value is checked before anything is put into the handoff: the name against `Mcp.Server` `NAMEPATTERN`, the address against `Mcp.Ops.AddressAllowed`, any `@{` in the name, address or secret, and the secret's shape. A failure is a field error, and nothing is offered, submitted or written.
- McpOps keeps its order and its undo-on-failure. Add: Validate, Register (row, `Install.Step.Mcp.Grant`, then the new entry write), Audit, Restart. A failed entry write or audit undoes the entry, the grant and the row. Remove: Unregister (tool rows, row, revoke and audit in one transaction), commit, then 22.4's merged cancel of the server's pending requests (`CancelPending`, unchanged), then the entry and wallet drop (a failed drop is one warning, and the answer stays `removed`), Restart. An error text from the wallet or the Config Store is never logged. A fixed reason is logged instead.
- Online demo (`onlineDemo` 1): every MCP settings route answers 409 `not_available` with T1 before it reads the body, `ListMcpServers` and McpOps refuse, the section shows T1 in place of its content, and no MCP endpoint runs.
- Only accepted or listed text ships (Public text). Every test added or changed creates and removes its own `zz` servers, rows, entries, wallet collections, mock jobs and approval fixtures, and passes on a fresh environment, in either order.

**Never:**
- The changed-tool banner (`settings.toolChangedBanner`; proposed split, 21.9); source polls (21.5); cancelling pending requests at removal (22.4's merged `CancelPending` call in `Unregister` stays exactly as it is; this story adds no cancelling); a server edit or secret replacement (remove and add again); a security-overview change.
- Any Lane A edit beyond Code Map "Lane A (ruled DW-1041 exception)"; a grant to `OcuTalonUser`/`OcuTalonAdmin`; a new SQL grant; an unchecked prepare outside `ALLOW_UNCHECKED`; a real MCP server or credential (the IRIS-side `Test.Mcp.Mock` only); a More to try item.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| List | README admin, GET `/v1/settings/mcp`. Servers `zzA` (attached; 3 tool rows: read-only, risky and refused, unclassified) and `zzB` (never attached) | 200 `{"servers":[{name,address,status,tools,unclassified,pending}],"tools":[{server,name,classification,status}]}`, sorted by name. `zzA` is `attached`, 3, 1, 0. `zzB` has status `""` and 0, 0, 0. No secret, no `secret://` reference, no fingerprint | A failed read is 500 `server_error` |
| Add with secret | `{"name":"zzA","address":"http://127.0.0.1:<mock>/mcp","secret":"<24 random>"}` | 200 `{"result":"added","message":MESSAGEADDED}`. Row, resource and grant. Entry `AI.MCP.OcuTalon_zzA`: `url`, plus the secret as a `secret://OcuTalon_MCP_zzA.Key#token` reference (bearer, Task 0). Wallet key `OcuTalon_MCP_zzA.Key` holds the secret. One `MCP` audit entry `added`. Runners restarted. After a runner build, the mock saw the credential (`matched`), and GET lists the mock's tools `unclassified` | -- |
| Add without secret | no `secret`, or `""` | As above, with the no-credential entry form (Task 0 b). No wallet collection | -- |
| Add refused | non-loopback `http://`; user info; a query string or fragment (any `?` or `#`, T12; ruling B2); `@{` in a value; a bad name; an existing name; a secret that is not a string, is over 4,096 characters or has a space or control character | 400 `bad_mcp_server`, `fields` {name/address/secret: text}: MESSAGENAME, MESSAGEADDRESS, MESSAGEEXISTS (`exists`, from McpOps), `settings.refusedExpansion` (`@{`), T6 | A route-checked case offers nothing to the handoff. An McpOps refusal (`exists`, or its own name or address check) is mapped to its field after the handoff is discarded. Nothing is written or audited either way |
| Add write fails | The handoff cannot be taken (an already-taken or unknown uri), or the entry or wallet write fails | McpOps answers `failed`. No row, resource, grant, entry, collection or key is left. One warning with a fixed text. Route: 500 `server_error` | The page reloads the list |
| Remove | DELETE `/v1/settings/mcp/servers/zzA`, after the dialog; one pending `tool_call` row of `zzA` | 200 `{"result":"removed","message":MESSAGEREMOVED}`. Row, tool rows, resource, grant, entry, key and collection are gone. The pending row is `cancelled` (22.4's `CancelPending`, merged). One `MCP` audit entry `removed`. GET lists no `zzA` | Unknown name: 404 `not_found` |
| Classify | POST `/v1/settings/mcp/classify` `{"server","tool","classification":"read-only"}` | 200 `{"result":"saved","message":"Saved"}`. Row `read-only`. A `Tool` audit entry | Unknown server or tool: 404. Another word or shape: 400 `bad_classification` |
| Not an admin | LIVE `OcuTalonUser`, each of the four routes | 403 `not_admin`; nothing submitted | -- |
| Online demo | `onlineDemo` 1, any route, any body | 409 `not_available` + T1 before the body is read. `ListMcpServers` answers `not_available` | Nothing offered, submitted or written |
| From a tool | each of the five MCP verbs and `ListMcpServers`, origin `tool` and inside a bridge context | refused `not_allowed` with the chat text; nothing reaches McpOps or SettingsOps | -- |
| Remove dialog | `Jira` with 12 tool rows and 1 pending `tool_call` row, toolref `mcp:remote:@{config:AI.MCP.OcuTalon_Jira}` | "Remove Jira? Its 12 tools go at once, and 1 pending approval request for them is canceled." Other counts use T7's forms | -- |

</intent-contract>

## Code Map

Line numbers are those of this branch after the Epic 22 merge (`3d94a219`: 22.9, 22.3, 22.4) at `b3fdf16c`. Story 21.14 is implementing in this worktree now (uncommitted). For the files it changes (Design Notes "Contended edits"), the numbers are those of the committed tree, and implement re-reads them after 21.14 lands.

- `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` (Lane A; the ruled exception):
  - The class doc :1-24. The remove-order sentence :8-11 already names 22.4's cancel ("then, once the removal has committed, the cancel of the pending approval requests ... (Approval CancelPending ...)"); 21.4 adds the entry and wallet drop after it. The sentence ":13-14 the Config Store entry and the wallet secret that hold them are not written here" is replaced.
  - `MessageMap` :61-74 (22.5 adds two `MapItem`s; not touched here). `OnAdd` :77, `OnRemove` :100.
  - `Register` :140-164: `Grant` :151, its undo :152-155, `WriteAudit` :156, the audit undo :157-161, the answer :163.
  - `Unregister` :168-201: `TSTART` :176, `TCOMMIT` :192, the error quit :197, then 22.4's `Do ..CancelPending(server, request)` :198, `Set restart = 1` :199 and the answer :200.
  - `CancelPending` :203-216 (22.4; read only): its own `Try`, and one warning on a failure. It is the sibling of the drop call's shape.
  - `AddressAllowed` :475 (public, reused by the route). `Refusal` :511. `Answer` :572. `Failed` :583 logs `Redact.Text(GetErrorText(sc))`, so it is not used for wallet or Config Store errors.
  - Seams :602-631: `OnlineDemo`, `AdminSessions`, `Notice`, `Restart`, `WriteAudit`.
  - 22.2's spec planned this edit as "one call ... in add ... in remove" (`spec-22-2` :91).
- `src/ocutalon/cls/OcuTalon/Msg/Command/AddMcpServer.cls` -- the class doc (line 1) says the secret reaches the wallet through `SettingsOps.SaveMcpEntry`. Add `Property Handoff As %String(MAXLEN = 128)` (sibling: `CreateWebhook.Handoff` :10, storage :23), and update the storage and the doc.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`:
  - The stubs `SaveMcpEntry`/`RemoveMcpEntry` :2146-2158 (docs included) are deleted. `NotImplemented` :2161 stays: `Save` uses it at :1141 and :1210.
  - Dispatch is in `Carry` :173-193, called by `OnMessage` :163. It gets `ListMcpServers` beside `MailSignIn` :185.
  - The class doc's webhook paragraph :93-98 is the sibling of the new paragraph.
  - `WebhookFieldText(key, value)` :2330-2337 renders a catalog key for the web. `HookSettings` uses it for its 409, and it is reused for T1 and `settings.refusedExpansion`.
  - `OnlineDemo` :696, `Result` :802. `RestartRunners` :2126 is unchanged.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `XData Routes` :325-369 (MCP rows :356-360, `MailSignIn` :343) gets `{"verb":"ListMcpServers","owner":"SettingsOps","origins":"web_admin"}`. Doc :24-25 (step 4) and :322-324. `TOOLVERBS` :62 and the refusal :109-111 are unchanged.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `AdminSessions` :826-849 is the sibling: a cross-owner read with the privilege check, run in production jobs and tests (doc :36-37). New: `PendingToolCalls`.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` (read only; 22.4, merged) -- `CancelPending(source, sinkClass, channel, irisUser, sessionRef, .count)` :449-472. It cancels every row matched by `SELECT Ref FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Kind = 'tool_call' AND State = 'pending' AND ToolSource = ?` (:453), under the column's default SQLUPPER collation (doc :445-448).
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` (read only) -- `Kind` :16, `State` :25, `ToolSource` :79, `ToolFingerprint` :85.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` (read only; 22.4) -- `Hold` :256-290 raises the real `tool_call` rows, with `ToolSource` set to the runner's toolref at :285.
- `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` (read only):
  - `Servers` :31-44 gives names and `config`, and no server on the online demo (`Mcp.Proxy.OnlineDemo`).
  - `Toolref(server)` :79-83 (22.4, merged) gives exactly `mcp:remote:@{config:AI.MCP.OcuTalon_<name>}` (`TOOLREFSTART` :27, `ENTRYPREFIX` :24), or "" for a name outside `NAMEPATTERN`.
  - `Mcp/Server.cls`: `NAMEPATTERN` :12, `AttachStatus` :21, `NameIndex` :32 (unique, default collation). `Mcp/ToolClassification.cls`: `CLASSIFICATIONS` :17.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- `settings.webhooksOffOnDemo` :731-735 is the sibling of T1's key `settings.mcpOffOnDemo`. The class doc :3 lists the webhook field texts. `Test/Msg/Catalog.cls`: Core count :80-83 (144), key list :1161, `XData` texts :1748.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - UrlMap :251-297: add `<Map Prefix="/v1/settings/mcp" Forward="OcuTalon.Web.McpSettings"/>` after the webhooks map :296.
  - `IsSettingsUrl` :354 already covers it.
  - The class doc's webhook-routes bullet :111-112 is the sibling of the new bullet.
  - `MESSAGESERVERERROR` :185, `MESSAGENOTFOUND` :175, `IsAdmin` :348, `ServerError` :389, `SettingsBody` :1126, `EnvelopeError` :1499, `Fail` :1511.
- `src/ocutalon/cls/OcuTalon/Web/HookSettings.cls` -- the sibling of the new class: class doc :1-12, `OnlineDemo` seam :35, `Refusal` :41-46, `Hand` :117-138 (put, submit, discard), `Submit` :141, `Answer` :148.
- `src/ocutalon/cls/OcuTalon/Core/SecretHandoff.cls` -- `Put` :25, `Take(uri, .secret, timeoutSec=5)` :51, `Discard` :76; unchanged by 21.4.
- IRIS (read only; verified in plan):
  - `%Wallet.Collection.Create(name, {EditResource, UseResource})` needs `%Admin_Wallet:USE` (`irislib/%Wallet/Collection.cls:10`, `%wallet.inc:25`).
  - `%Wallet.KeyValue.Create("<coll>.Key", {"Secret":{"token":v},"RequireTLS":0,"Usage":"CUSTOM"})`, `Delete`, and `%Wallet.Secret.Exists`.
  - `%ConfigStore.Configuration.Create(area,type,subtype,name,details,display,description,readResource,editResource,enabled,validateDetails)` needs `%Admin_ConfigStore:USE` for create and delete (`irislib/%SYS/ConfigStore/Configuration.cls:127-148, 338-347, 1209-1219`). Before a `Create`, `%ConfigStore.DescriptorManager.RebuildRegistry()`, as the fixtures do.
  - `GetDetails(fqn,.d,0,0)` :413 reads without resolving secrets (evidence 35-1 (2)).
  - `%AI.ConfigStore.MCPDescriptor` :95-155 requires `auth` (bearer `token`, basic, or header `name`/`value`) for remote transport when `validateDetails` is 1.
  - Sibling writer: `Install/Step/Provider.cls:179-181` (`ENTRYRESOURCE` `%Admin_ConfigStore` :53).
- Tests to change:
  - `Test/Core/CommandsStep4.cls`: `TestContracts` :70 and `XData Contracts` :581-593; `TestOrigins` :81; `TestMcpVerbsFromATool` :118; `TestToolVerbs` :303; `TestMcpEntryStubs` :334-365 with its helpers `WalletIds` :464 and `DropStubFixtures` :478 (property `StubServer`); `TestNoMcpSettingsRoute` :422-440.
  - `Test/Msg/Contracts.cls`: the verb list :42 and the `AddMcpServer` contract :544-554.
  - `Test/Contract/Ac.cls` :388-389: the two stub rows go. The doc :18 names them and "85 signatures". The floor `count >= 85` :165 still holds with 87 rows (89 today).
  - `Test/Web/SettingsApi.cls`: `TestNonAdminIs403Everywhere` :110-121 (the URL list and its count 11 :120).
  - `Test/Msg/Catalog.cls` (T1's key).
  - `Test/Core/Routing.cls` and `Test/Web/Api.cls` need no edit: neither lists CommandsIn's routes or `Map` rows (`Test/Web/Api.cls` `TestRoutes` :998 lists `Route` rows only). Each is run once.
- Siblings for new tests:
  - `Test/Web/HookSettingsApi.cls` + `HookSettingsProbe.cls`, `Test/Core/SettingsWebhooks.cls`, `Test/Core/SettingsOpsProbe.cls`.
  - `Test/Mcp/OpsProbe.cls`: `Shadow("CommandsIn")` :14 and its seams; no edit.
  - `Test/Mcp/Mock.cls`: `Start(.port, extra, header, expected)` :64, `Stop` :87, `Forget` :162, `Requests` :168, `Calls` :181.
  - `Test/Bridge/ApprovalRows.cls`: `NewRow(kind, name, arguments, source, runner)` :13 and `Save(row, state, expiresIn, answerer, .ref)` :47. These are the fixture `tool_call` rows; `Test/Mcp/Approval.cls` `TestCancellingTwiceIsANoOp` :581 builds one for an MCP toolref.
  - `Test/Core/SecretHandoff.cls`: `Leaks(text)` (committed :177), and `TraceLeaks(text)`, added by 21.14 (in flight).
- Lane A (ruled DW-1041 exception; test fallout of the Ops edit; committed-tree lines):
  - `Test/Mcp/Ops.cls` `Clean` :972-985 deletes rows and revokes, so the new entry and collection would leak.
  - `Test/Mcp/Attach.cls`:
    - `TestCommands` :342-417 makes a fixture entry `..Entry(, 1)` :349 before it submits `AddMcpServer` :352. McpOps now writes its own entry. At :404, `Leftovers()` is expected to still list "the Config Store entry, the wallet secret, the wallet collection, a mock node or job" after the remove; McpOps now drops the entry.
    - `Entry` :1670-1682, `Remove` :1685-1698, `Leftovers` :1701-1713 (it checks the fixture collection `Collection()` :1716 `OcuTalonZzMcp<n>` only).
    - `TestRemovedServer` :669 with `RemoveThroughItem` :1561: the removal now also drops the fixture's entry in the middle of the turn.
  - `Test/Mcp/Classification.cls`: `Make` :216 adds through the item, so an entry is now written. Its cleanup `Clean` :304 and `Leftovers` :320.
  - `Test/Mcp/Approval.cls` (22.4) `RemoveServer` :776, used by `TestRemovedWhilePending` :292, `TestRemovedWhileApproved` :324 and `TestCancellingTwiceIsANoOp` :581. McpOps now also drops the `JobFixture` entry `AI.MCP.OcuTalon_zzmcp`. `JobFixture.Remove` :193-205 guards each delete with `Exists`, and its collection `OcuTalonZzMcpJob` (:182) is not McpOps' name. Expected: no edit, and the runs confirm it.
- Web:
  - `web/src/app/settings/settings-view.ts`: `SETTINGS_TEXTS.sections` :33-41, `SETTINGS_SECTIONS` :129-137, doc :10 ("the seven sections").
  - `settings-page.ts`: imports :8-21, the `@switch (active())` :60-103.
  - Siblings: `webhooks-section.ts` (states loading/ready/off/denied/failed, field errors, announcer), `webhooks-view.ts`, `unsaved-dialog.ts` (CDK `DialogRef`, a sentence-named modal: the dialog sibling), `email-section.ts:119` (a `role="radiogroup"`) and `refusal.ts`.
  - `web/src/app/api/api-client.ts`, `api-types.ts` (webhook types :316-337 are the siblings).
  - Tokens `web/src/styles/tokens.css:555-560` (`--classification-*`, with the dark sets :778-783 and :1001-1006). `Icon` `check`.
- Web tests:
  - `web/e2e/api/webhooks.spec.ts` (W1: LIVE 403 + README admin). Helpers: `signInOverHttp`, `envelope` (`../sign-in/helpers`), `irisScript` and `fixtureUser` (`../support/iris`). `web/e2e/api/` is in project `chromium` (`live:sign-in`).
  - `web/e2e/settings/webhooks.spec.ts`. `settings/` is in project `sign-in-2` (`web/playwright.config.ts:52` `SIGN_IN_2_DIRS`).
  - `web/e2e/settings/settings.spec.ts:16` (`SECTIONS`, seven).
  - `web/scripts/ux-strings.test.mjs` (SOURCES: `ux`/`ac`/`ruled`) and `web/scripts/webhooks-view.test.mjs` (reads catalog texts with `catalogText`).
- Docs: `GUIDE.md` "## New since 1.0.0" :3 (0.30 is in, so T9 goes here, under "#### Your integrations", after "Your own mailbox."). EXPERIENCE `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` "### Settings and requests (step 4)" :973 (the webhook row :1003 is the sibling of T1's row).
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`:
  - AD-1: the step-4 `CreateWebhook` sub-bullet :128 (S6 goes after it).
  - AD-19 :673: the last sentences of "Step 4 details" name `SettingsOps.SaveMcpEntry` and the routes. AD-19 :675: "Until then the routes are stubs".
  - AD-21 :849: the online demo "preconfigures only the servers on the demo's allow-list", which the 2026-11-11 ruling replaced. AD-21 :856 (Names): "`OcuTalon.Core.SettingsOps` writes ... `McpOps` writes only the `Mcp.Server` row".
  - The Seed row :1516. The REST rows :1708-1710.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure on lane-C warm `e21s4iw` before the McpOps code is final; scratch only in the session scratch folder and `zz` names; record the results under Design Notes "Measured"):
  - (a) An entry of type `bearer` with `token` `secret://OcuTalon_MCP_zz.Key#token` attaches through `@{config:}` (bare `%AI.ToolMgr`, as in evidence 35-1 (2)), and `Test.Mcp.Mock` with header `Authorization`, expected `Bearer <value>`, records `matched`. If it does not attach, use type `header`, name `Authorization`, with the wallet value `Bearer <secret>`.
  - (b) A no-secret entry: first try no `auth` member with `validateDetails` 0 and check that the attach works. If it does not, use header `X-OcuTalon-Client` value `OcuTalon`.
  - (c) McpOps' production job creates the collection, with `EditResource` `%Admin_Wallet:USE` and `UseResource` `OcuTalon_MCP_<server>:USE`, and a runner build resolves the reference. If either fails, use `%Admin_Wallet:USE` for both and record it.
  - (d) Record the user and roles of McpOps' and SettingsOps' production jobs, and whether they hold `%Admin_Wallet:USE` and `%Admin_ConfigStore:USE` (expected: `_Ensemble` with `%All`, as 21.3 measured). Stop for a ruling if a grant is needed.
  - (e) Record which runner's first request attaches a newly added server on the `live:sign-in` stack (expected: the chat runner on a chat message; inference).
  - (f) Confirm that 21.14 is committed on this branch and that `Test.Core.SecretHandoff.TraceLeaks` exists. If not, stop: the lead orders the two stories (Decided 14).
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` -- add the entry write and drop as two private class methods, `SaveEntry(server, url, handoff) As %Status` and `DropEntry(server) As %Status`. -- DW-1041: the write runs in McpOps' job, never in the REST process.
  - `SaveEntry` takes the secret with `SecretHandoff.Take` (only when `handoff` is not empty) and refuses a secret holding `@{`.
  - It removes any leftover entry, key or collection of that name: the row is the truth.
  - It creates the collection `OcuTalon_MCP_<server>` and its `.Key` (Task 0 c). Then it creates the entry `AI.MCP.OcuTalon_<server>`: Read/Edit `%Admin_ConfigStore`, description "Written by McpOps for an MCP server an admin added; do not edit.", auth per Task 0 a/b.
  - It clears its local copy of the secret on every path, and removes what it made when a later step fails.
  - `DropEntry` removes the entry, key and collection where they exist.
  - Each method catches its own exceptions and returns a status; neither ever throws, like `CancelPending` :209-215 (Decided 13).
  - Call sites in `Register`:
    - `SaveEntry(server, request.Url, request.Handoff)` goes after `Grant`'s undo block :152-155 and before `WriteAudit` :156. On a failure: `Revoke`, delete the row, one `$$$LOGWARNING` with a fixed text (not `Failed`), and the answer `failed` with `CommandsIn` `MESSAGEFAILED`.
    - The audit-failure block :157-161 calls `DropEntry(server)` first, then its `Revoke` and row delete as today.
  - Call site in `Unregister`: after 22.4's `Do ..CancelPending(server, request)` :198 and before `Set restart = 1` :199 (Design Notes "Contended edits"), so that it runs only after the commit and after the cancel. A failure is one `$$$LOGWARNING` with a fixed text (never `GetErrorText`), and the answer stays `removed`.
  - Update the class doc: the add order :7, the remove order :8-11 (add "then the drop of the entry and the wallet secret (a failure is one warning)" after the cancel), and :12-14 (the address and the credential are stored only in the entry and the wallet key that McpOps writes, and are never logged, audited or put in a notice).
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Command/AddMcpServer.cls` -- `Handoff` property, storage, doc. New `src/ocutalon/cls/OcuTalon/Msg/Command/ListMcpServers.cls` (extends `Msg.Command`; `ActingUser`; doc: read-only, from `web_admin` only, owner SettingsOps).
- [ ] `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- the `ListMcpServers` route row and a doc line.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `PendingToolCalls(server As %String, Output sc As %Status) As %Integer`.
  - It counts the rows of `OcuTalon_Bridge_Data.ApprovalRequest` across owners, with a checked prepare, under exactly `CancelPending`'s predicate: `SELECT COUNT(*) ... WHERE Kind = 'tool_call' AND State = 'pending' AND ToolSource = ?`, bound to `##class(OcuTalon.Mcp.Attach).Toolref(server)`.
  - Default collation; no `%EXACT` on `ToolSource`. This keeps the count equal to what the removal cancels (Clarification C3).
  - A name that `Toolref` refuses gives 0 and an error in `sc`, as `CancelPending` refuses an empty source.
  - It runs only in production jobs and tests (doc line beside :36-37).
- [ ] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- delete the two stubs (keep `NotImplemented`).
  - Add `ListMcp(command)`, dispatched from `Carry` beside `MailSignIn` :185. On the online demo it answers `not_available` with T1 (`WebhookFieldText("settings.mcpOffOnDemo")`). Otherwise it answers `Ok` 1, outcome `listed`, and `Data` the GET body (Matrix "List"):
    - servers from `Mcp.Attach.Servers`;
    - `status` from the row's `AttachStatus`;
    - `address` from `GetDetails(fqn,.d,0,0)` `.url` (empty when the entry is missing);
    - `tools` and `unclassified` from `Mcp.Ops.Tools(server)`;
    - `pending` from `PendingToolCalls`;
    - and the tools array.
  - A failed read is `failed`.
  - Update the class doc (a paragraph after :98) and `WebhookFieldText`'s doc :2330 (it also renders the MCP settings keys).
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- add `settings.mcpOffOnDemo` after `settings.webhooksOffOnDemo` :735. Text T1 verbatim, no slots, source "EXPERIENCE Message Catalog / Settings and requests (step 4) / MCP servers off on the online demo". Update the class doc :3. `Test/Msg/Catalog.cls`: Core count 144 -> 145 with its comment line, the key in the list (:1161) and the text (:1748) (Decided 11).
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- the map row after :296. Lift `HookSettings.Hand`'s put, submit and discard core into a private `Web.Api` method that both subclasses use (Rule 2). Place it after `SettingsBody` :1126, away from 21.14's `SaveChannels` hunk. Add a class-doc bullet after :111-112.
- [ ] `src/ocutalon/cls/OcuTalon/Web/HookSettings.cls` -- call the lifted method; its behaviour is unchanged.
- [ ] New `src/ocutalon/cls/OcuTalon/Web/McpSettings.cls` (extends `Web.Api`; UrlMap `""` GET `List`, `/servers` POST `Add`, `/servers/:server` DELETE `Remove`, `/classify` POST `Classify`). Doc: the class description as the contract.
  - `Refusal`: 403 first, then 409 + T1 (`SettingsOps.WebhookFieldText("settings.mcpOffOnDemo")`) before the body.
  - Shapes: add takes exactly `{name, address}` plus an optional string `secret`; classify takes exactly `{server, tool, classification}`.
  - It runs the route checks of Always, then hands off and submits. T6 is the parameter `MESSAGESECRET` of this class.
  - Answers:
    - `listed` -> 200 with the Data;
    - `added`/`removed`/`saved` -> 200 with the result and McpOps' message;
    - `bad_name`/`bad_address`/`exists` -> 400 `bad_mcp_server` with the field;
    - `bad_classification` -> 400;
    - `not_found` -> 404;
    - `not_available` -> 409;
    - `not_allowed` and anything else -> 500 `server_error`.
  - The secret is in no answer.
- [ ] `web/src/app/api/api-types.ts`, `api-client.ts` -- `McpSettings`, `McpServerRow`, `McpToolRow`; `mcpSettings()`, `addMcpServer`, `removeMcpServer`, `classifyMcpTool`.
- [ ] Web section:
  - New `web/src/app/settings/mcp-view.ts`: `MCP_TEXTS`, `removeQuestion(server, n, m)` (T7's forms), `statusText`, `toolStatusText`, `visibleTools(tools, unclassifiedOnly)`, `addBody`.
  - New `mcp-section.ts` (sibling: `webhooks-section.ts`), with the states loading/ready/off/denied/failed:
    - The "Servers" table (T3/T4), with a "Remove" button per row (`aria-label` T11).
    - The "Add server" form: Name, Address, Secret (`type="password"`, `autocomplete="off"`), T5. A field error shows under each field, and the first is focused. On success: MESSAGEADDED, cleared fields, the list reloaded.
    - The remove dialog: CDK, in `unsaved-dialog.ts`'s shape, named and first-focused by its sentence (UX-DR38), with Cancel and Remove.
    - The "Tools" table: an "Unclassified only" checkbox and, per row, a `role="radiogroup"` named T10 with three radios (labels as the AC; D `classification-*`; the checked one shows `Icon check`). A pick saves at once and shows "Saved" for that row (announced). A failure puts the old value back and shows `MESSAGESERVERERROR`.
    - Any 500 on add or remove shows `MESSAGESERVERERROR` and reloads the list.
  - `settings-view.ts` gets the eighth section `{ slug: 'mcp', label: 'Tools and MCP servers' }` and the doc line :10. `settings-page.ts` gets `@case ('mcp')` in the switch :60-103.
- [ ] Tests (ObjectScript):
  - `Test/Core/CommandsStep4.cls`:
    - `TestContracts` (with `Handoff`; `ListMcpServers`).
    - `TestMcpVerbsFromATool` and `TestOrigins` also cover `ListMcpServers` (to SettingsOps from `web_admin` only). `TestToolVerbs` reads the real Routes.
    - `TestMcpEntryStubs` becomes `TestMcpEntryWrite`, reusing `WalletIds`/`DropStubFixtures`. Through `Test.Mcp.OpsProbe` `Shadow("CommandsIn")` it covers the Matrix rows "Add with secret", "Add without secret", "Add write fails" (a taken handoff) and "Remove". For "Remove", one fixture pending `tool_call` row made with `Test.Bridge.ApprovalRows` and `Mcp.Attach.Toolref`: `PendingToolCalls` is 1 before, the row is `cancelled` after (22.4's merged cancel, through the probe), and the count is then 0.
    - It checks the entry with `GetDetails(...,0,0)` and the wallet value. It checks that the secret is in no message body, `Ens.Util.Log` row, audit entry or `^OcuTalon*` global (`Test.Core.SecretHandoff` `Leaks` and `TraceLeaks`), and that the test's objects (rows, entries, collections, approval rows) are gone afterwards.
    - `TestNoMcpSettingsRoute` becomes `TestMcpSettingsRoutes` (the map row).
  - New `Test/Core/SettingsMcp.cls`: `ListMcp` over fixture rows, an entry and `ApprovalRows` fixture rows (Matrix "List"). It covers the pending count by toolref; a `pending` `tool_call` row whose `ToolSource` is the toolref in another case is counted, as `CancelPending` would cancel it; `approved`, `fix` and another server's rows are not counted. Also the online demo and a missing entry.
  - New `Test/Web/McpSettingsApi.cls` + `McpSettingsProbe.cls` (sibling: HookSettings'): every Matrix route row, including field errors before the handoff, the discard on every path, demo 409 before the body, and the 403.
  - Shared-surface updates: `Test/Msg/Contracts.cls` (:42, the contract), `Test/Contract/Ac.cls` (the two rows, doc :18), `Test/Web/SettingsApi.cls` (`TestNonAdminIs403Everywhere`: the four MCP calls, count 11 -> 15), `Test/Msg/Catalog.cls` (T1).
  - Lane A:
    - `Test/Mcp/Ops.cls` `Clean`, and `Test/Mcp/Classification.cls` `Clean`, each also drop `AI.MCP.OcuTalon_<name>`, `OcuTalon_MCP_<name>.Key` and the collection.
    - `Test/Mcp/Attach.cls`: `TestCommands` submits `Handoff` for its secret instead of making a fixture entry (`SecretHandoff.Put`, discarded afterwards). The assertion at :404 expects only "a mock node or job". `Leftovers` and `Remove` also check and drop McpOps' collection `OcuTalon_MCP_<server>` and its key.
    - `TestRemovedServer`: run it. If the UNREGISTERED denial no longer holds once the entry is dropped mid-turn, stop and report (a product finding, not a test edit).
    - `Test/Mcp/Approval.cls`: no edit expected; run the three removal tests.
- [ ] Tests (web):
  - New `web/e2e/api/mcp.spec.ts` (real HTTP; the `webhooks.spec.ts` shape):
    - M1: the LIVE user gets 403 on all four routes, and the README admin gets 200 on GET.
    - M2: the admin adds `zz<run>` at `Test.Mcp.Mock` (started with `irisScript`, header `Authorization`) with a random secret and gets 200. One chat message lets a runner build (Task 0 e). The GET then lists the mock's two tools `unclassified`, and the mock's log says `matched`.
    - M3: classify gets 200 `Saved`, and GET shows it.
    - M4: remove gets 200; GET lists it no more, and the entry and collection are gone.
    - M5: each "Add refused" case is 400 with nothing made.
    - M6: the leak scan of 35.3's W9 for the secret.
  - New `web/e2e/settings/mcp.spec.ts` (browser, `sign-in-2`):
    - B1: the section lists a fixture server and its tools, and "Unclassified only" filters them.
    - B2: an add through the form, with its field errors.
    - B3: a radiogroup pick shows "Saved" and the check icon and survives a reload.
    - B4: the `Jira` dialog wording (12 fixture tool rows and 1 pending fixture `tool_call` row with `ToolSource` the server's toolref, made and removed with `irisScript`). Cancel keeps the server. Remove takes it off the lists and leaves the fixture row `cancelled`.
    - B5: GET answered 409 (`page.route`) shows T1 in place of the content.
  - `web/e2e/settings/settings.spec.ts:16` gets the eighth section.
  - New `web/scripts/mcp-view.test.mjs` (T7's forms, the filter, the bodies, and T1 equal to `catalogText('settings.mcpOffOnDemo')`). `web/scripts/ux-strings.test.mjs` gets the new entries.
- [ ] Docs and spine (markers `[AMENDED 2026-11-12, Story 21.4, DW-1041 ruling]`, each keeping what it read):
  - S1-S6 of Design Notes. A memlog line; `lint_spine.py`.
  - T1-T11 are accepted (ruling B), so their rows go into EXPERIENCE "Settings and requests (step 4)" :973 in this story.
  - T9 goes into `GUIDE.md` "New since 1.0.0" (:3, "#### Your integrations", after "Your own mailbox."), as the ruling says now that 0.30 is merged.

**Acceptance Criteria:**
- Given an admin opens Settings > Tools and MCP servers, when it loads, then the navigation shows eight sections with the new one last, and the section lists each server's name, address, status, tool count and unclassified count, and a tools table whose rows come from `Mcp.Ops.Tools(server)` through `ListMcpServers`, filterable with "Unclassified only" (B1, M1).
- Given an admin adds a server with an `https://` or loopback address and a secret, when they save, then the route submits `AddMcpServer` (origin `web_admin`, `Handoff` only), McpOps' job writes the entry and the wallet secret, the secret appears in no answer, message, log, audit entry, global or test output, and after a runner build the tools arrive Unclassified (M2, M6, `TestMcpEntryWrite`).
- Given each of the five MCP verbs and `ListMcpServers`, when submitted with origin `tool` or inside a bridge context, then each is refused and nothing is sent (`TestMcpVerbsFromATool`).
- Given a server with n tools and m pending `tool_call` requests, when Remove is pressed, then the dialog shows T7's sentence for n and m, and confirming removes the server, its tools, entry and secret from the lists and the instance (B4, M4).
- Given a tool's radiogroup, when the admin picks an option, then it saves at once through `ClassifyTool`, shows "Saved" with the check icon, and McpOps audits it (B3, M3).
- Given the online demo, when an admin of that install opens the section or calls any MCP settings route, then T1 shows (409 `not_available`), nothing is offered, submitted or written, and the demo account (no admin role) sees no settings (B5, `McpSettingsApi`, `SettingsMcp`).
- Given the spine after this story, when AD-19, AD-21, the Seed and the REST rows are read, then none says that `SettingsOps` or a route writes the MCP entry, and each names McpOps' job and `ListMcpServers`.

- [ ] (Planner condition B) Given an add with a secret at a non-loopback `http://` address, when it is submitted (route and McpOps), then it is refused with `MESSAGEADDRESS` and no wallet key, Config Store entry or row is written; a test pins it (mutation: the address check skipped when a secret is present -> red).


### Review Findings

Code review 2 (2026-11-13; the story's diff `git diff 96bbbcd8` with QA's uncommitted tests, bookkeeping and this spec left out; four layers: Blind Hunter 8, Edge Case Hunter 8, Verification Gap 5, Acceptance Auditor 7; 28 findings in 23 entries: high 1, medium 4, low 17, false 1). Every patch below was applied in this pass.

- [x] [Review][Patch] [high] A Lane A file outside the grant: `Test/Mcp/OpsProbe.cls` had gained a `DropEntry` seam (Code Map: "no edit"; the spec's Never and AD-33's Rule). Auditor. Fixed: `OpsProbe.cls` is byte-identical to `96bbbcd8` again, and the seam lives in the new Lane B subclass `Test/Core/McpOpsProbe.cls`, which `Test.Core.CommandsStep4` `RunThrough` uses [src/ocutalon/cls/OcuTalon/Test/Core/McpOpsProbe.cls]
- [x] [Review][Patch] [medium] A removal that names the server in other letters leaves the wallet key (the secret) and the entry behind: `Unregister` finds the row through the case-blind `NameIndex` but dropped by the typed name, and wallet and Config Store names are exact. Blind + Edge. Fixed: `DropEntry` runs on the row's stored name (`NameGetStored`), and `TestMcpEntryWrite` removes an upper-case name and asserts nothing is left [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:196]
- [x] [Review][Patch] [medium] The tool radiogroups were named by row position (`'mcp-class-' + index`): turning "Unclassified only" off put a row in front, the new row's checked radio unchecked the old row's radio of the same name, and Angular never set it again (observed: B1 red under the old naming). Blind. Fixed: each group is named by its server and tool; B1 asserts each row's checked radio after the filter is turned off [web/src/app/settings/mcp-section.ts:205]
- [x] [Review][Patch] [medium] AC 1's address cell had no browser pin. Verification Gap. Fixed: B2 asserts the listed server's address cell [web/e2e/settings/mcp.spec.ts:128]
- [x] [Review][Patch] [medium] The Contest Planner's ~21:30Z ruling ("cancelled") was not applied to T7 and its pins. Auditor. Fixed: `MCP_TEXTS.remove`, the EXPERIENCE rows (and the reused example), `mcp-view.test.mjs`, `ux-strings.test.mjs`, e2e B4, and `## Public text` T7 (Spec Change Log) [web/src/app/settings/mcp-view.ts:46]
- [x] [Review][Patch] [low] AD-21's verb property list still gave `AddMcpServer` (`Server`, `Url`, `ActingUser`) and no `ListMcpServers`, against the S3 Names bullet. Blind + Auditor. Fixed with a marker [ARCHITECTURE-SPINE.md:858]
- [x] [Review][Patch] [low] AD-33's Rule lists every one-time cross-lane exception, but not 21.4's ruled DW-1041 exception. Auditor. Fixed: a bullet with a marker; `lint_spine.py` shows the 10 baseline findings only; no `.memlog.md` exists in the spine folder, so no memlog line was written [ARCHITECTURE-SPINE.md:1222]
- [x] [Review][Patch] [low] The `Mcp.Ops` class doc claimed the address is "never stored elsewhere" and that "a key never sits in the entry's address"; the command, the list answer and IRIS's own audit entry hold the address, and B2 refuses only a query string. Blind + VG + Edge. Fixed: the doc says what this class writes and never logs [src/ocutalon/cls/OcuTalon/Mcp/Ops.cls:14]
- [x] [Review][Patch] [low] Test headers behind their tests: `CommandsStep4`'s class doc and `TestMcpEntryWrite`'s doc left out the audit-failure undo (and the header the `@{` refusal and the failed drop); `api-types.ts` said the tools are sorted by name. Blind. Fixed [src/ocutalon/cls/OcuTalon/Test/Core/CommandsStep4.cls:25]
- [x] [Review][Patch] [low] Rule 19: the `mutation:` records of condition B, the filter, AC 3 and AC 5 sat only in `## Auto Run Result`; AC 7 had no manual-only note. VG. Fixed in `## Verification` (code review 2)
- [x] [Review][Patch] [low] `Test.Mcp.Attach:TestCommands` started the mock with the expected bearer value but never read it. VG. Fixed: it asserts that every request of AI Hub's client carried the handed-over secret (a wrong secret turned it red) [src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls]
- [x] [Review][Patch] [low] `Test.Core.SettingsMcp` `Leftovers` did not check the tool rows its fixtures make. VG. Fixed [src/ocutalon/cls/OcuTalon/Test/Core/SettingsMcp.cls:228]

Rejected (each with its reason; ledger rows `by=cr` where filed):
- [low] An add or removal whose runner restart fails answers 500 although the change is kept, and the Remove dialog then stays open (Edge, two sightings): the spec maps every outcome but added/removed/saved to 500, the restart-failure contract is 22.2's, and the section reloads the list. DW-1291 `by-design`.
- [low] A 403 in the section shows the section's denied text, not the page's denied view (Blind): the spec gives the section its own denied state. DW-1292 `by-design`.
- [low] McpOps checks only `@{` and emptiness of the secret (Blind): `AddMcpServer` comes from `web_admin` only, and its one submitter is the route that checks the shape. DW-1293 `wontfix-theoretical`.
- [low] An exception after `SaveEntry` in `Register` would leave the entry without undo (Edge): only `WriteAudit` follows, which returns a status; `SaveEntry`/`DropEntry` never throw. DW-1294 `wontfix-theoretical`.
- [low] The e2e cleanup never revokes the server's resource (Blind): only a failed DELETE leaves one, on a throwaway stack. DW-1295 `wontfix-accepted`, reopen_if=a live run reports a leftover `OcuTalon_MCP_zz*` resource or grant.
- [low] AC 7 holds only when the amended texts are read together (Auditor): S1 and S5 are applied word for word as ruled (V9); more AD text is a spine amendment, not a code fix.
- [low] Accepted texts reused but not named in the spec's reuse list (Auditor): no new public text; the fix would edit the spec only.
- [low] `ListMcp` fails the whole list for a server removed between two reads; overlapping picks; the lazy import's rejection (Edge): closed in review pass 1 with reasons; no new evidence.
- [false] `TestRemovedServer` does not assert "exactly one audit entry for the refused call" (Auditor, focus 9): the gate denies `UNREGISTERED` before any audit step (`Gate.cls:212`, `Denial` :537 returns a status only; spine :390), so no such entry exists by 22.x's design. The test asserts the ruling's intent: the server's one MCP entry is the removal, and the denied calls add no MCP or Tool entry. `Gate` and `Attach` are unchanged.

## Spec Change Log

- 2026-11-13 (code review 2, Contest Planner ruling ~21:30Z "spelling of cancelled", binding): T7's dialog sentences say "cancelled" (`mcp-view.ts`, the three EXPERIENCE rows and the reused EXPERIENCE example, their pins in `mcp-view.test.mjs`, `ux-strings.test.mjs` and e2e B4). Catalog keys and code states are unchanged. The frozen Matrix row "Remove dialog" keeps its old spelling as written; `## Public text` T7 carries the amendment.
- 2026-11-13 (lead, implement pass 4, the final pass; scope from the dispatch, binding for the implement handoff; it supersedes pass 3's B1 (c) lines):
  - **(a) B1, option (i).** `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` stays UNCHANGED. Edit only `Test.Mcp.Attach:TestRemovedServer` (Lane A test, granted): the mid-turn part keeps `UNREGISTERED` with exactly one audit entry for the refused call; the new-turn part asserts that the tool list of a turn started after the removal holds none of the server's tools. Extra proof, only if the class's mock model can script a tool call by name: the new turn calls a removed tool anyway, gets `ToolNotFound`, nothing runs, and `Test.Mcp.Mock`'s request log shows no request; if it cannot, write that under `## Review Triage Log` or the Auto Run Result (it does not block). Mutation: skip the V3 `DropEntry` in `McpOps.Unregister`, the new-turn assertion must turn red; revert byte-identical and record the `mutation:` line (a mutation of production-run code needs `ci/warm.sh down` then `up`).
  - **(b) Runs.** ALL of `Test.Mcp.Attach`, `Test.Mcp.Approval`, `Test.Mcp.Proxy`, `Test.Mcp.ProxyJob`, `Test.Mcp.Ops`, `Test.Mcp.Client` and `Test.Bridge.Gate`, one class per call (a long class split by method); `live sign-in --part 2/16` (`api/mcp.spec.ts`, M1-M5 with the two new M5 cases); `npm run build` with the initial bundle at or below the budget. A 22.x regression is a STOP.
  - **(c)** The step-04 follow-up recommendation is `true` only if a `high` was patched. **(d)** Rule 19: every pin has its `mutation:` line; Rule 14: `## Auto Run Result` states the final status (earlier passes' records may stay below it). **(e)** DW-1285 is filed (the runtime gap of B2): do not refile it.
  - **(f) Before finalize**, on a FRESH lane-C stack: `TestRemovedServer`, `Test.Web.McpSettingsApi`, `Test.Core.SettingsMcp`; then `test-boundaries.sh`, `test-class-rules.sh`, `test-ci-config.sh` and `node --test web/scripts/`.
  - Runtime tags for pass 4: warm `e21s4iw4`, fresh `e21s4i4`.
- 2026-11-13 (lead, Planner rulings `prompts/epic-21-rulings-20261113-1800.md`, binding; pass 3 scope):
  - **B1 (c), granted.** This is a cross-lane grant for this one change only: Lane A's `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` and `Test/Mcp/Attach.cls` `TestRemovedServer`. When Attach re-attaches recorded specs, it skips the spec of a server that has no `Mcp.Server` row. The gate then refuses the call with `UNREGISTERED` and writes its audit entry. `TestRemovedServer` asserts three things: `UNREGISTERED`, exactly one audit entry for the refused call, and no `ToolNotFound` anywhere in what it checks. The V3 drop of the entry and the wallet collection at removal stays. A contradiction with 22.x behaviour is a STOP.
  - **B2, accepted.** `Test.Mcp.Ops:TestNoAddressOrSecretInAnyText` keeps its audit assertion narrowed to source `OcuTalon`. IRIS's own audit entries are outside our control.
  - **B2, added refusal.** Both McpOps' address check and the route's refuse an address that holds `?` or `#` (a query string or a fragment). It is a 400 `bad_mcp_server` with the field `address`, the McpOps refusal mapped to its field like the others, and nothing written or audited. The new field text is T12, word for word: "An MCP server's address can't hold a query string (the part after ?). Put a key in Secret instead. Nothing was changed." Add one test that refuses such an address at the route and at McpOps, with its mutation: the check skipped -> red. No doc note. If Task 0's measured attach address, or the Jira example's address (`docs/mcp-jira-example.md` and the guide, if present), needs a query string, STOP and report.
  - The address rules stay EXACTLY as ruled. Lane D's 22.6 review checks its claims against them at its merge.
  - Keep new web code in lazily loaded chunks. The initial bundle has about 1.9 kB of headroom.
- 2026-11-13 ~19:50Z (lead). Pass 3 stopped before changing any code, on a STOP condition the lead had added himself: existing Lane A fixtures use `?`. The ruling's own STOP triggers are not met: Task 0's measured attach has no `?`/`#`, and `docs/mcp-jira-example.md` does not exist yet. Decided within ruling B2:
  - **Where the check lives:** in McpOps' ADD path, beside the existing address check of `OnAdd`/`Register`, and in the route. It is NOT in `Mcp.Ops.AddressAllowed`, because `Mcp.Proxy:84` calls that at call time (pinned by `Test/Bridge/CodeRules.cls:768`), and putting it there would change 22.x's runtime behaviour for an existing entry. `Mcp.Proxy` and `Mcp.Client` are unchanged.
  - **Lane A fixtures follow the ruling** (they are inside B2's scope in `Test/Mcp/Ops.cls`):
    - `TestBadAddress` (:148): `https://example.com:8443/a?b=c` moves from the allowed list to the refused list, refused with T12.
    - `TestNoAddressOrSecretInAnyText` (:503): the ADDED case uses a query-free address that still carries the secret probe (for example `https://<address>.example.invalid/mcp/<secret>`), so the scan still has a value to look for. The old `?token=<secret>` address becomes a REFUSED case, and it too must leave neither the address nor the secret in any text.
    - :512 keeps its own refusal reason (plain http to a non-loopback host).
    - `Test/Mcp/Client.cls` is unchanged.
  - Reported to the coordinator for veto.
- 2026-11-13 ~20:25Z (lead, Planner "21.4 RE-RULINGS", binding; these supersede B1 (c)):
  - **B1: option (i).** `Mcp/Attach.cls` stays unchanged. The grant is a Lane A edit to `Test.Mcp.Attach:TestRemovedServer` only:
    - The mid-turn part keeps `UNREGISTERED`, with exactly one audit entry.
    - The new-turn part asserts that the tool list of a turn started after the removal holds none of the server's tools.
    - Extra proof, if the mock model can script a tool call by name: the new turn calls a removed tool anyway, gets `ToolNotFound`, nothing runs, and the mock MCP server's request log shows no request. If the mock model can't script that, say so in the review notes; it does not block.
    - Mutation: skip the V3 drop, and the new-turn assertion goes red.
  - **B2: the placement is accepted** (add path and route only; `AddressAllowed` is unchanged). The fixture moves are approved. The runtime gap (an entry already saved with a query string) is ledgered LOW to burndown.

- 2026-11-13 (pass 3 scope, from the lead's dispatch; binding for the implement handoff):
  - **B1 (c).** Make the smallest change in `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` so the re-attach of recorded specs skips the spec of a server that has no `Mcp.Server` row, with no other Attach change. Never weaken `TestRemovedServer` (UNREGISTERED, exactly one audit entry for the refused call, no `ToolNotFound` anywhere it checks). Keep the V3 `DropEntry` in `Unregister`. Run ALL of `Test.Mcp.Attach`, `Test.Mcp.Approval`, `Test.Mcp.Proxy`, `Test.Mcp.ProxyJob`, `Test.Mcp.Ops`, `Test.Mcp.Client` and `Test.Bridge.Gate`, one class per call (a long class by method). A 22.x regression or contradiction is a STOP: set `blocked`, name it, halt.
  - **B2 refusal.** The check goes in McpOps' ADD path, beside `OnAdd`/`Register`'s address check, and in the route; NOT in `Mcp.Ops.AddressAllowed`. An address holding `?` or `#` is refused as 400 `bad_mcp_server` with field `address`; nothing is written or audited. T12's text goes where the other address messages live, registered the way they are, with the apostrophes authored as the neighbours do. Change the `Test/Mcp/Ops.cls` fixtures exactly as the ~19:50Z entry says. Add ONE test of the refusal covering both the route and McpOps, with its `mutation:` line (check skipped -> red). Keep the narrowing in `TestNoAddressOrSecretInAnyText`. No doc note. The address rules stay exactly as ruled; nothing more.
  - **STOP only if** Task 0's attach address or the Jira example's address needs `?` or `#` (`docs/mcp-jira-example.md` does not exist, so this does not fire). Fixtures do not trigger a STOP.
  - **Web.** Any new web code stays in the lazily loaded MCP chunk; check the initial bundle with `npm run build` (about 1.9 kB of headroom). If the web shows the server's refusal text, no web text is needed.
  - **Rule 19.** Every new pin gets its `mutation:` line. **Rule 14.** `## Auto Run Result` states the story's final status; pass 2's record stays below it.
  - **Verification for this pass.** On a fresh lane-C stack run `TestRemovedServer`, the new refusal test, `Test.Web.McpSettingsApi` and `Test.Core.SettingsMcp`; then `ci/iris.sh build` and `live sign-in-2 --part 10/12`; then `test-boundaries.sh`, `test-class-rules.sh` and `node --test web/scripts/`.
  - **Runtime tags for pass 3.** Warm `e21s4iw3`, fresh `e21s4i3`; a mutation of production-run code needs `ci/warm.sh down` then `up`.

- 2026-11-12 (lead, spec gate): Planner rulings B applied (V1-V12 approved; the plain-HTTP-with-secret condition added as an AC; 21.9 split written into epics.md; T1-T11 verbatim; implement after 22.4 merges).
- 2026-11-13 (plan, spec refresh): refresh after 22.4 merged. Epic 22 (22.9, 22.3, 22.4) is merged into this branch (`3d94a219`). These changes need no new ruling; every ruled item (V1-V12, T1-T11, condition B, the 21.9 split) is unchanged.
  - Every Code Map and Task line was re-verified against the tree.
  - `Mcp/Ops.cls`: `Unregister` now calls 22.4's `CancelPending` at :198. The drop goes right after it (Contended edits), and the class doc's remove order already names the cancel.
  - `PendingToolCalls` now uses `Mcp.Attach.Toolref` and `CancelPending`'s exact predicate. C3 is resolved: real rows exist, and the count matches.
  - Tests use `Test.Bridge.ApprovalRows` and assert the cancel at removal.
  - New Lane A run-only items: `Test.Mcp.Approval`'s three removal tests and `Test.Mcp.Attach` `TestRemovedServer`. `Attach` `TestCommands` :404 and `Leftovers` change.
  - T1 gets its catalog home (Decided 11). T9 goes to GUIDE.md (0.30 is in). The S6 anchor is corrected: AD-1 has no MCP-verbs sub-bullet, so S6 goes after the step-4 `CreateWebhook` sub-bullet.
  - Contended edits are re-listed for 21.10 and 21.14 (in flight).

### Review Findings ([CI] rework 1, 2026-11-14)
- [ ] [Review][CI] `web/e2e/api/mcp.spec.ts` M2 posts a chat message as the README admin (`/ocutalon/api/v1/messages`, "zz hello", about l.145) so that a runner builds, and never removes that turn. In CI run 43541569138 (`iris (shards-10)`, live:sign-in, head 435c5cc8) the next specs for the same account went red: `chat/chat.spec.ts` C1 (the empty chat headline was not found) and `frame/frame.spec.ts` F1 ("Recent decisions, 1" where 0 was expected). Fix: clean M2's chat turn and its AI session and decision records in the spec's own clean-up, following the existing pattern (`persona-approval.spec.ts`: `RunnerFixture.SessionMark()` before, then `DropSince(mark)` and `WaitRecords()` after; or `cleanFixtureRows` / the support helper that removes the posted turn). Prove it by running M2 and then chat.spec C1 and frame.spec F1 in ONE live run on the same stack, in that order; both must be green. Do not weaken C1 or F1.

## Review Triage Log

### 2026-11-13 - Review pass 1 (pass 4 of the implement; the whole story's diff `96bbbcd8..`, the 21.14 commits excluded, bookkeeping files left out)
- verdicts: 32 findings - high 0, medium 7, low 22, false 3, maybe-false 0. Layers: Blind Hunter 11, Edge Case Hunter 11, Verification Gap 10 (5 gaps, 5 others), Intent Alignment 0 (descriptive; its divergences are the ruled ones: the `?`/`#` check in McpOps' add path and the route (B2), the `SaveEntry` pre-drop (Design Notes), the status words, the shared `Api.HandOff`).
- patched here (the layer's single bounded pass; every patch is a test, a probe seam, a spec text or a doc sentence, none is production code): the five gaps of verification-gap, its hermeticity finding, the missing `mutation:` lines, the test coverage finding of Blind Hunter and the spine's secret-handoff sentence.
- findings:
  - `[low]` `[reject]` Blind: `ListMcp` fails the whole list when one server's read fails - a failed read of one server is not reachable in everyday use and its fix adds a skip-or-flag branch; reopen_if=a list that fails in the field.
  - `[low]` `[reject]` Blind: a failed drop at removal still answers `removed` - by design: the spec says "a failed drop is one warning, and the answer stays removed" (the pass now pins it).
  - `[low]` `[reject]` Blind: `SaveEntry` drops a leftover entry, key or collection of the name without an audit entry - by design (Design Notes: the row is the truth; the name does not exist at that point).
  - `[low]` `[reject]` Blind: the lazy `import('./mcp-section')` has no error state or loading text - a failed chunk load needs a new public text (a veto item beyond T1-T12) and the chunk is 19.88 kB.
  - `[low]` `[reject]` Blind: overlapping picks on one tool can restore a stale value - two clicks before the first answer; the fix adds in-flight bookkeeping.
  - `[low]` `[reject]` Blind: the Remove dialog's pending count is the one the list loaded - T7's sentence is specified on that list; by design.
  - `[low]` `[reject]` Blind: the last header cell of the servers table is empty - each Remove button has its own accessible name (T11).
  - `[false]` `[reject]` Blind: an empty secret is accepted - the matrix row "Add without secret" says "no `secret`, or `""`".
  - `[low]` `[patch]` Blind: the spine's secret-handoff sentence omits 21.4 - one clause added (the MCP credential: `Web.McpSettings` offers it, `McpOps`' own job takes it); `lint_spine.py` shows the 10 baseline findings and no new one. The MCP-writes bullet's "Until then the routes are stubs" is a history clause with its `[done in Story 21.4 ...]` marker, as the spine's convention keeps it.
  - `[medium]` `[patch]` Blind: no tests for the partial-failure and drop-failure paths - patched through the gap rows below (the `@{` refusal, the failed write's drop, the failed drop at removal, the route mapping); `ListMcp` with a failing read is the low row above.
  - `[low]` `[reject]` Blind: `Test.Contract.Ac`'s signature comment and floor are stale - pre-existing (the floor was 85 under 89 signatures before this story); reopen_if=the floor hides a removed signature.
  - `[low]` `[reject]` Edge: a leftover collection with another key makes `Collection.Delete` fail, so the name can never be added - needs a key added by hand to an `OcuTalon_MCP_<name>` collection.
  - `[low]` `[reject]` Edge: a server removed between `Servers()` and `Tools()` fails the whole list - a race of two admin clicks; the next list answers.
  - `[low]` `[reject]` Edge: `ListMcp` returns a stored url that holds a key in its query - an admin-only read of the admin's own entry; the runtime gap of B2 is DW-1285.
  - `[low]` `[reject]` Edge: overlapping picks (same as Blind's) - see above.
  - `[low]` `[reject]` Edge: a stale reload can restore a removed server or an older pick until the next reload - the next reload corrects it.
  - `[low]` `[reject]` Edge: the lazy import's rejection leaves a blank section (same as Blind's).
  - `[low]` `[reject]` Edge: no loading state while the chunk loads - an empty panel for the length of a 19.88 kB fetch.
  - `[false]` `[reject]` Edge: an empty secret is accepted (same as Blind's; the matrix allows it).
  - `[low]` `[reject]` Edge: `ListMcp` does not re-check the origin or the acting user - no `SettingsOps` verb does (CommandsIn is the one gate, pinned by `TestMcpVerbsFromATool`), and the read changes nothing.
  - `[low]` `[reject]` Edge: a key in an address's path is not refused - by design: ruling B2 refuses `?` and `#` only, and the address rules stay exactly as ruled.
  - `[false]` `[reject]` Edge: T12 claims "a key never sits in the address" - its words say a query string "can't" be held and to put a key in Secret; they claim nothing about the path.
  - `[medium]` `[patch]` VG1: `SaveEntry`'s final `DropEntry` after a failed write is not pinned - `TestMcpEntryWrite` now counts the drops of an add that fails after the secret was taken (two: before the write and again after it), through `OpsProbe.DropEntry`; mutation below.
  - `[medium]` `[patch]` VG2: McpOps' own refusal of a secret that holds `@{` is not pinned - `TestMcpEntryWrite` offers `zzEntry@{env:ZZ}` straight to McpOps: failed, one fixed warning, nothing left; mutation below.
  - `[medium]` `[patch]` VG3: the failed drop at removal is not pinned - `TestMcpEntryWrite` fails the drop through the probe (`^||ZzOps("dropError")`): answer `removed`, one fixed warning, no error text of the drop in the log; mutation below.
  - `[medium]` `[patch]` VG4: the routes' 500 and 409 mapping of `failed`, `not_audited`, `not_allowed` and `not_available` is not pinned - new `Test.Web.McpSettingsApi:TestFailedAnswers` (the probe's `outcome:<word>` mode) on all four routes; mutation below.
  - `[medium]` `[patch]` VG5: the section's failure states are not exercised - new e2e case B6 (a 500 on classify puts the old value back, shows the message, no Saved, the count back); mutation below. The denied, load-error, Retry and add-500 states stay without a browser case: `[low]` closed `wontfix-accepted`, reopen_if=a regression in those states reaches a user.
  - `[medium]` `[patch]` VG hermeticity: `TestMcpEntryWrite` expected the wallet text to equal the old text plus its two ids, true only on an empty wallet - now it asserts two more ids and that they are the collection and the key.
  - `[low]` `[reject]` VG hermeticity: `TestMcpEntryWrite` quits without an assertion when its counter name already exists - the name is a fresh counter value; reopen_if=a stale name is ever seen.
  - `[low]` `[reject]` VG hermeticity: `TestNotAdmin` skips its production-backed part without the production - its first part runs everywhere and the rest is named in the class header as throwaway-only (the other tests there use `Guard`).
  - `[low]` `[reject]` VG hermeticity: M5 compares the whole list before and after - an unrelated server row written between the two reads would break it; the stack has none.
  - `[low]` `[patch]` VG: ACs with a pin and no `mutation:` line (the eighth section, the leak scans, the Remove dialog, the online-demo state, the route map row) - the mutations were applied, observed red and reverted; the lines are in `## Verification`.

## Design Notes

**Governing ADs (Rule 6):**
- AD-1: commands from `web_admin`; REST writes nothing; the handoff clause.
- AD-13: admin-checked `/v1/settings` routes, the envelope.
- AD-17: McpOps' audit entries, no secret.
- AD-19: "MCP settings writes"; write-only secret; `@{`.
- AD-21: MCP servers: entry, Names, `Tools(server)`; "removal cancels pending requests for its tools" (22.4).
- AD-24: no new grant; jobs run as the Interoperability system user.
- AD-25: online demo: off.
- AD-29/AD-33: lanes; McpOps the one writer of a server's records.
- AD-11: only a pending request is cancelled (22.4's merged rule; read only here).

No AC contradicts an AD Rule. S1-S6 below correct wording that the DW-1041 ruling already overrode (AD-19 :675 says "Story 21.4 moves that write into McpOps").

**ACs already met on this branch (evidence):**
- "CommandsIn refuses every MCP verb from origin tool, and a test submits each": `CommandsIn` `TOOLVERBS` :62 holds no MCP verb and :109 refuses. `Test.Core.CommandsStep4` `TestMcpVerbsFromATool` :118 submits all five with `tool` and inside a bridge context (Story 35.2). This story only adds `ListMcpServers` to it.
- "Tested against Story 35.1's stub until 22.2 merges": 22.2 is merged, so the real `Tools(server)` is used.
- "The demo account sees no settings": demo visitors hold `OcuTalonUser` only, and `OnPreDispatch` answers 403 (`Test.Web.SettingsApi`).
- The MCP runtime is off on the demo: McpOps `Refusal` :511, `Install.Step.Mcp.Grants` :18 (none on the demo), and `Mcp.Attach.Servers` :34 (no server on the demo).
- "Removal cancels pending requests": 22.4's `Unregister` -> `CancelPending` :198 -> `Approval.CancelPending` :449. It is pinned by `Test.Mcp.Approval` `TestRemovedWhilePending` :292.

**Proposed split (doctrine U5; the lead rules):** epics AC 5 (the changed-tool banner) moves verbatim to a new sibling, **21.9 "Show the changed-tool banner in Settings"**, after 21.4.
- Why: no delivered data tells a tool that McpOps cleared after a fingerprint change from a newly discovered tool. Both rows are `unclassified` with a fresh `ChangedAt` (`Ops.ClearRow` :339, `KeepRow` :409), and `Tools(server)` gives name, classification and status only.
- A banner from those rows would claim "changed its description or inputs" about new tools (non-negotiable 3). The data needs a Lane A addition (Clarification C1).
- Moving an AC is a veto item (V10).

**Decided in-stage (reversible inside this story):**
- (1) The write lives in `Ops.cls`, not in Lane B helpers that McpOps calls. The ruling says "into McpOps", and this makes McpOps the one writer of a server's row, resource, entry and secret (AD-33). The stubs and their `Test.Contract.Ac` rows go.
- (2) The read is a command answered in SettingsOps' job, which removes all three blockers below without widening any resource:
  - The REST process cannot run `Tools(server)` or `Attach.Servers`: both prepare with the privilege check, and the README admin holds the three OcuTalon roles and no SQL grant (`Install/Step/Users.cls:5-6`, AD-13 :458; inference, high confidence).
  - It cannot read an entry whose ReadResource is `%Admin_ConfigStore` either.
  - `PendingToolCalls` crosses owners, which runs only in jobs.
- (3) Leftovers: an entry, key or collection with no row is replaced at the next add of that name. A failed drop is a warning, never a failed remove.
- (4) One tools table for all servers, with a Server column.
- (5) Status words: `attached` "Connected", `unavailable` "Unavailable", `""` "Not checked yet". Tool `refused` and `unavailable` have their own words (T8).
- (6) Secret shape: 1 to 4,096 printable ASCII characters (0x21-0x7E), no `@{`. Bearer tokens (JWTs included) fit.
- (7) `RequireTLS` 0 on the key. AI Hub's config lookup resolves it, not `%Net.HttpRequest.UseSecret`, and the address rule already allows `http://` only to this computer. This is a veto item (V3).
- (8) The audit entries keep McpOps' shape: no "secret set" member (it would be another Lane A edit).
- (9) No second-session case: MCP servers are instance settings, not owned data (standing rule (iii) covers owned data only).
- (10) The dialog's first focus is its sentence (UX-DR38's general rule).
- (11) T1's home is the Core catalog key `settings.mcpOffOnDemo`, the sibling of `settings.webhooksOffOnDemo`. The route, `ListMcp` and the web section all show it, and `SettingsOps.WebhookFieldText` renders it as it does the webhook 409. The text is T1 verbatim; nothing new.
- (12) `DropEntry` goes after 22.4's `CancelPending` line in `Unregister`, not before it. This leaves 22.4's line untouched, keeps the user-visible cancel first, and a drop failure cannot skip the cancel.
- (13) `SaveEntry` and `DropEntry` never throw. Each catches its own exceptions and returns a status, so nothing after the commit can turn a committed removal into `failed` through `OnRemove`'s catch. `OnAdd`'s catch is unchanged.
- (14) The leak scans call `Test.Core.SecretHandoff.TraceLeaks` (Story 21.14, implementing in this worktree now) beside `Leaks`, rather than writing their own trace scan (Rule 2). Both stories run on lane C in one worktree, so 21.4's implement starts after 21.14's commit (Task 0 f).
- (15) `Test.Watch.SettingSecret` `ROUTECLASSES` (a Lane A test that reads every GET route for a leak) is not extended to `Web.McpSettings`. That would be a Lane A edit outside the DW-1041 grant. `McpSettingsApi` and M6 pin that the GET holds no secret.
- (16) The fixture `tool_call` rows (`SettingsMcp`, `TestMcpEntryWrite`, B4) are built with `Test.Bridge.ApprovalRows` and `Mcp.Attach.Toolref`, as `Test.Mcp.Approval` `TestCancellingTwiceIsANoOp` does. Raising a real held call needs a model turn; 22.4's own tests cover that.

**Measured (Task 0, 2026-11-13, lane-C warm `e21s4iw`, build 154U; scratch objects `zzt0` only, all removed):**
- (a) An entry `{"transport":"remote","url":...,"auth":{"type":"bearer","token":"secret://OcuTalon_MCP_zzt0.Key#token"}}` made with `validateDetails` 1 attaches through `@{config:AI.MCP.OcuTalon_zzt0}` on a bare `%AI.ToolMgr` (`AddTool` OK), and `Test.Mcp.Mock` with header `Authorization` and expected `Bearer <value>` logged `matched` for `initialize` and `notifications/initialized`. The `header` fallback is not needed.
- (b) An entry with no `auth` member made with `validateDetails` 0 is accepted and attaches (`AddTool` OK; the mock saw `initialize` and the notification). IRIS marks such an entry `Valid` 0, `Enabled` 1 (a read with `checkValid` 1 fails; the attach and `GetDetails(fqn,.d,0,0)` do not need it). The `X-OcuTalon-Client` fallback is not needed.
- (c) `%Wallet.Collection.Create` with `EditResource` `%Admin_Wallet:USE` and `UseResource` `OcuTalon_MCP_<server>:USE` is accepted once the resource exists (after `Install.Step.Mcp.Grant`; before it, error #892). McpOps' production job (restarted warm stack) created it, and the key and entry, in `Test.Web.McpSettingsApi:TestAddListClassifyRemove` and `Test.Core.CommandsStep4:TestMcpEntryWrite`. A runner build that resolves the reference is M2's (`live:sign-in`), not measured here.
- (d) Every OCUTALON production job runs as `_Ensemble` with roles `%All` (`%SYS.ProcessQuery`: the jobs of `OCUTALON` and `OCUORDERS`; `Security.Users` `_Ensemble` Roles `%All`); `$SYSTEM.Security.Check` of `%Admin_Wallet:USE` and `%Admin_ConfigStore:USE` is 1 for them. No grant is needed.
- (e) Not measured yet: M2 records which runner's first request attaches a new server.
- (f) 21.14 is committed (`cc3c9df4`, `b479b0b2`) and `Test.Core.SecretHandoff.TraceLeaks` exists in the tree at HEAD.
- IRIS's own audit entry "Create Configuration: AI.MCP.OcuTalon_<server>" holds the entry's details, so the address (and any query string in it) shows in the instance audit log; the wallet audit entries and every other entry hold no secret value (`Test.Core.CommandsStep4:TestMcpEntryWrite` scans OcuTalon's entries; a scan of every source for a wallet secret found none).

**Contended edits (Rule 11):**

*Lane A, `Mcp/Ops.cls` (ruled order 22.4 -> 21.4 -> 22.5; 22.4 merged, so nothing is pending a union).* 21.4 builds on the merged file:
- `Register` :140-164: `SaveEntry` is inserted between `Grant`'s undo block (ends :155) and `WriteAudit` :156. `DropEntry` is inserted as the first line of the audit-failure block :157-161. 22.4 did not change `Register`.
- `Unregister` :168-201: the merged tail reads :197 error quit, :198 `Do ..CancelPending(server, request)`, :199 `Set restart = 1`, :200 answer.
  - The drop goes between :198 and :199, after the cancel. It sits outside the transaction and after the error quit, so it runs only once the removal has committed.
  - 22.4's line and its `CancelPending` method :203-216 are not edited, so the cancel still happens at every committed removal, before the drop.
  - 22.5 later adds its own post-commit call (remove the server's sources) in the same tail, after these two lines.
- Class doc: the add order :7, the remove order :8-11 (append the drop after the existing cancel clause) and :12-14 (replace the "not written here" sentence). 22.5 replaces only the sentence at :3.
- Two new private class methods (`SaveEntry`, `DropEntry`), appended after `CancelPending` :216.
- 22.5's `MessageMap` :61-74 `MapItem`s are not touched.

*Lane A tests (DW-1041 fallout, C2):*
- `Test/Mcp/Ops.cls` `Clean` :972-985.
- `Test/Mcp/Attach.cls` `TestCommands` :342-417, `Remove` :1685, `Leftovers` :1701.
- `Test/Mcp/Classification.cls` `Clean` :304.
- Run only: `Test/Mcp/Attach.cls` `TestRemovedServer`, and `Test/Mcp/Approval.cls` `TestRemovedWhilePending`, `TestRemovedWhileApproved`, `TestCancellingTwiceIsANoOp`.

*Read only:* `Mcp/Attach.cls` (`Servers`, `Toolref`), `Mcp/Server.cls`, `Mcp/ToolClassification.cls`, `Bridge/Approval.cls`, `Bridge/Data/ApprovalRequest.cls`, `Bridge/Policy/Gate.cls`, `Test/Mcp/OpsProbe.cls`, `Test/Mcp/Mock.cls`, `Test/Mcp/JobFixture.cls`, `Test/Bridge/ApprovalRows.cls`, `Install/Step/Mcp.cls`.

*Story 21.14 (lane C; implementing in this worktree now, uncommitted).* Files shared with 21.4:
- `Web/Api.cls`:
  - 21.14 changes `SaveChannels` (:948, its doc :940-947), `PASSWORDMAX` :199 and the class doc :45-52.
  - 21.4 changes the UrlMap (a new `Map` line after :296), the class doc (a new bullet after the webhook bullet :111-112) and a new private handoff method after `SettingsBody` :1126.
  - Different regions.
- `Core/SettingsOps.cls`:
  - 21.14 changes `SaveEmail` :1468 (plus one new private method next to it), `EmailShape` :1775 and the class doc :64-68.
  - 21.4 changes the class doc (a new paragraph after :98), `Carry` :184-192, the stubs :2146-2158 (deleted), a new `ListMcp` and `WebhookFieldText`'s doc :2330.
  - Different regions.
- `Test/Core/CommandsStep4.cls`:
  - 21.14 changes `SaveMailbox` :551.
  - 21.4 changes `TestContracts` :70, `TestOrigins` :81, `TestMcpVerbsFromATool` :118, `TestToolVerbs` :303, `TestMcpEntryStubs` :334-365, `TestNoMcpSettingsRoute` :422-440, the helpers :464-487 and `XData Contracts` :581+.
- `Test/Web/SettingsApi.cls`:
  - 21.14 changes `TestChannelsRoute` :544 and :626-628, `SaveSettingsHold` :717-745 and the header.
  - 21.4 changes `TestNonAdminIs403Everywhere` :110-121 and one header line.
- `Test/Mcp/Ops.cls`:
  - 21.14 adds a `TraceLeaks` assertion in `TestNoAddressOrSecretInAnyText` (after the event-log scan, committed :564).
  - 21.4 changes `Clean` :972-985 only.
- `Test/Mcp/Attach.cls`:
  - 21.14 adds "the trace" to `Leaks(adapter)` :1930.
  - 21.4 changes `TestCommands`, `Remove` and `Leftovers`.
- `Test/Mcp/Approval.cls`, `JobFixture.cls`, `ProxyJob.cls`, `Proxy.cls`: 21.14 adds trace-scan lines; 21.4 runs `Approval` only.
- `Test/Web/HookSettingsApi.cls`: 21.14 adds a `TraceLeaks` line in its per-secret loop; 21.4 runs it (the lift keeps `HookSettings`' behaviour) and does not edit it.
- `Test/Core/SecretHandoff.cls`: 21.14 adds `TraceLeaks`, `Holds` and `Swap`. 21.4 calls `Leaks` and `TraceLeaks` and does not edit it.
- `Core/SecretHandoff.cls`: 21.14 doc only; 21.4 none.

*Story 21.10 (lane C, ready-for-dev).* Files shared with 21.4:
- `Msg/Catalog/Core.cls`:
  - 21.10 changes `toolCall.request` :594, `toolCall.requestOnServer` :602 and `answered.canceled` :806.
  - 21.4 adds `settings.mcpOffOnDemo` after :735 and one class-doc clause at :3.
- `Test/Msg/Catalog.cls`:
  - 21.10 changes :1138-1139 and :1608-1609 and the `inputs` type tests.
  - 21.4 changes the Core count :80-83, the key list :1161 and the text :1748.
- No other file overlap. `Core/BridgeSink.cls`, `Msg/Catalog.cls`, the `Channel/*/Out.cls` cards, `Live/Payload/Approval.cls`, `web/scripts/catalog.mjs`, `payloads.mjs` and the approvals/rail/chat web files are 21.10's alone.
- Runtime link (not a file): 21.10's `answered.canceled` goes out when a removal deleted the `Mcp.Server` row. 21.4's DELETE route is the admin's way to trigger it, through McpOps' merged order (row deleted and committed, then `CancelPending`).

*Lane B files that 35.3 also changed (merged):* `Web/Api.cls`, `Web/HookSettings.cls`, `Core/SettingsOps.cls`, `Core/CommandsIn.cls`.

**Clarifications for the lead (non-blocking; the plan runs on the stated default):**
- C1 (Lane A, for 21.9): the banner needs `Tools(server)` to say which unclassified tools McpOps cleared after a fingerprint change. Suggested: a `ToolClassification` column set by `ClearRow` and reset by `Classify`/`KeepRow`, and a `changed` member in `Tools(server)`. Either Epic 22 adds it, or 21.9 gets a Lane A exception. Default: 21.9 waits for it.
- C2: the Lane A test files in "Contended edits" change only because McpOps now writes and drops an entry. The default reads the DW-1041 grant as covering them; otherwise Epic 22 makes the same cleanup edits.
- C3 (resolved by the refresh): the dialog promises "is canceled", and 22.4 does the cancelling. 22.4 is merged. The gate raises real `tool_call` rows with `ToolSource` = the runner's toolref (`Gate.Hold` :285), and `Unregister` cancels them after the commit through `Approval.CancelPending(Attach.Toolref(server), ...)` (`Ops.cls` :198, :211).
  - `CancelPending` selects `Kind = 'tool_call' AND State = 'pending' AND ToolSource = ?` (`Approval.cls` :453, default SQLUPPER collation).
  - `PendingToolCalls` now uses exactly that predicate and the same `Attach.Toolref(server)`. So the dialog's m is the number of requests the removal cancels: the same rows, at the moment of the read. A request answered between the read and the press is left alone by both.
  - `TestMcpEntryWrite` "Remove", `SettingsMcp` and B4 pin it: the count is 1 before, the row is `cancelled` after. No other change.

**Ledger inbox:** DW-1041 is addressed by Tasks "Ops.cls", "AddMcpServer" and "Web.McpSettings", by `TestMcpEntryWrite`, and by S1-S5 (AD-1 unchanged).

**Integration ACs (Rule 1):**
- The settings page (`mcp-section.ts`) reads `Web.McpSettings`, which reads `ListMcpServers`, and through it the real `Mcp.Ops.Tools(server)` and the real Config Store. It shows the mock's tools (M2, B1).
- McpOps' entry write is consumed by AI Hub's attach in a real runner build (M2: the mock sees the credential).
- `PendingToolCalls` is consumed by `ListMcp`, and so by the dialog (B4). Its count is checked against the rows that 22.4's merged `CancelPending` cancels at the same removal (`TestMcpEntryWrite`, B4).

**Consumes:** `McpOps` (`AddMcpServer` with `Handoff`, `RemoveMcpServer` with 22.4's merged cancel, `ClassifyTool`, `AddressAllowed`, messages), `Mcp.Ops.Tools`, `Mcp.Attach.Servers` and `Toolref`, `Mcp.Server`, `SecretHandoff`, `Commands.Submit`/`CommandsIn`, `Bridge.Data.ApprovalRequest`, `Bridge.Approval.CancelPending` (through McpOps), IRIS `%Wallet` and `%ConfigStore`, and `Test.Mcp.Mock`. All are real instances in M2-M4, B1-B4 and `TestMcpEntryWrite`.

**Consumed-by:** 21.5 (the source form reads the tools array's `classification`; its routes join `Web.McpSettings`), 21.9 (the banner reads GET), 21.10 (the cancelled card follows a removal), 22.5 (adds its post-commit call after 21.4's drop in `Unregister`).

**Extend, don't copy (Rule 2):**
- `Web.McpSettings` extends `Web.Api` the way `Web.HookSettings` does. HookSettings' put, submit and discard core is lifted into `Web.Api` and shared, not copied.
- `ListMcpServers` and `ListMcp` follow `TestModel`/`MailSignIn`'s command and handler shape.
- `PendingToolCalls` follows `Ownership.AdminSessions`, with `CancelPending`'s predicate.
- McpOps' writer follows `Install.Step.Provider`'s Config Store create and `Test.Mcp.Attach.Entry`'s wallet calls.
- `mcp-section.ts` follows `webhooks-section.ts` (states, field errors, announcer); the dialog follows `unsaved-dialog.ts` and the radiogroup `email-section.ts:119`.
- The tests follow `HookSettingsApi`/`HookSettingsProbe`, `webhooks.spec.ts` (both), `webhooks-view.test.mjs`, `Test.Bridge.ApprovalRows` and `Test.Core.SecretHandoff` (`Leaks`, `TraceLeaks`).

**Spine items (S1-S5 correct wording, and changing an AD's text is listed as V9):**
- S1 AD-19 :673: the sentence "For MCP servers, `SettingsOps.SaveMcpEntry(...)` and `RemoveMcpEntry(server)` (stubs in Story 35.2, built in Story 21.4) write ..., called by the MCP settings routes ..." becomes: "For MCP servers, `McpOps` writes the wallet secret (collection `OcuTalon_MCP_<server>`, key `.Key`) and the `AI.MCP.OcuTalon_<server>` entry in its own job when it handles `AddMcpServer`, and removes them after a removal commits. The route puts the secret into `SecretHandoff`, and the command carries only its `Handoff` uri. (Story 21.4; the `SettingsOps` stubs are removed.)"
- S2 AD-19 :675: append "[done in Story 21.4: the write is in `McpOps`; the routes are `Web.McpSettings`]".
- S3 AD-21 :856 (Names): "`OcuTalon.Core.SettingsOps` writes ... called from Story 35.2's MCP settings route; `McpOps` writes only the `Mcp.Server` row and calls `RestartRunners()`" becomes "`McpOps` writes the `Mcp.Server` row, the resource, the entry and the wallet secret, and calls `RestartRunners()`". In the same bullet: `AddMcpServer` carries `Server`, `Url`, `ActingUser` and `Handoff` (a `SecretHandoff` uri), and `ListMcpServers` (`ActingUser`) is a read-only command from `web_admin` to `SettingsOps`, which answers the settings page's GET in its job.
- S4 AD-21 :849: "and never at run time on the online demo, whose installer preconfigures only the servers on the demo's allow-list (FR-47)" becomes "and never on the online demo, where no MCP endpoint runs and every MCP settings route answers 409 [AMENDED 2026-11-11, Contest Planner ruling: the online-demo safety rule]".
- S5:
  - Seed :1516: replace the row with "`McpOps` writes an MCP server's entry and wallet secret (AD-19, AD-21); the `SettingsOps` stubs of Story 35.2 are removed | A | Story 21.4 (DW-1041 exception)".
  - Add a row "`ListMcpServers` (AD-1, AD-21), answered by `SettingsOps`; `Ownership.PendingToolCalls(server, *sc)` | B | Story 21.4".
  - REST :1708-1710: GET -> `ListMcpServers` in SettingsOps' job (body as the Matrix); POST servers -> `SecretHandoff`, then `AddMcpServer`; DELETE -> `RemoveMcpServer`; classify -> `ClassifyTool`. Each is 409 `not_available` on the online demo before the body.
- S6 AD-1, after the step-4 `CreateWebhook` sub-bullet :128 (AD-1 has no separate MCP-verbs sub-bullet; the MCP verbs live in AD-21 :856): "`ListMcpServers` comes from `web_admin` only, to `SettingsOps`; it changes nothing." [ADDED 2026-11-12, Story 21.4]

**Planner rulings at the spec gate (Contest Planner, owner's delegation, 2026-11-12 ~18:10Z, `prompts/gate-rulings-20261112-1810.md` B; binding):** V1-V12 APPROVED. V3 with `RequireTLS` 0 is fine (22.2's address rule allows `http://` only to this computer). CONDITION (now a Tasks & Acceptance item): one test pins that adding a server WITH a secret at a non-loopback `http://` address is refused with `MESSAGEADDRESS` (the secret never goes out over plain HTTP). V5: a needed grant stops the story, as written. V10: the 21.9 split approved (written into `epics.md`). Demo: every MCP route returns 409 with T1 before reading the body, with real-HTTP tests. PUBLIC TEXT: T1-T11 approved verbatim, T9 included; T9 lands in GUIDE.md's "New since 1.0.0" once 0.30 is merged (README until then). Order (orchestrator): implement only after Epic 22's 22.4 merges, integrating forward first (22.4 -> 21.4 -> 22.5).
- Status at the 2026-11-13 refresh: 22.4 is merged into this branch, so the order condition is met. 0.30 is in (`GUIDE.md` has "New since 1.0.0"), so T9 goes to GUIDE.md.

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| V1 | Lane A edit (DW-1041, ruled): `Mcp/Ops.cls` writes and drops the entry and the wallet secret (`SaveEntry`/`DropEntry`, two call sites, the doc), plus the three Lane A test files (C2) | approve | McpOps refuses first; nothing written |
| V2 | Secret handling: REST -> `SecretHandoff` -> McpOps -> wallet key only. `AddMcpServer.Handoff`. The route checks and discards the handoff on every path. The secret is in no GET | approve | the route refuses before the body |
| V3 | Wallet objects: McpOps creates and deletes collection `OcuTalon_MCP_<server>` (Edit `%Admin_Wallet:USE`, Use `OcuTalon_MCP_<server>:USE`, or `%Admin_Wallet:USE` per Task 0 c) and key `.Key` (`RequireTLS` 0, Decided 7) | approve | none |
| V4 | Config Store entry `AI.MCP.OcuTalon_<server>` (Read/Edit `%Admin_ConfigStore`; bearer `secret://` reference, or Task 0's fallback; the no-secret form of Task 0 b) | approve | none |
| V5 | Privileges: McpOps' job needs `%Admin_Wallet:USE` and `%Admin_ConfigStore:USE` (Task 0 d: held by `_Ensemble`'s `%All` on the measured install). No new grant; a needed grant stops the story | approve | n/a |
| V6 | New routes: `GET /api/v1/settings/mcp`, `POST .../mcp/servers`, `DELETE .../mcp/servers/<server>`, `POST .../mcp/classify` (`Web.McpSettings`; admin-checked; real-HTTP tests) | approve | 409 + T1 before the body |
| V7 | New command `ListMcpServers` (`web_admin` -> SettingsOps, read-only, refused from `tool`) | approve | refused `not_available` |
| V8 | Cross-owner count `Ownership.PendingToolCalls` (a number only, in SettingsOps' job, for the dialog) | approve | not called |
| V9 | Spine amendments S1-S6 (AD-1, AD-19, AD-21 wording, Seed and REST rows) | approve | -- |
| V10 | Split: epics AC 5 (the banner) moves to new Story 21.9 | approve | -- |
| V11 | Removed contract: `SettingsOps.SaveMcpEntry`/`RemoveMcpEntry` and their `Test.Contract.Ac` rows (Story 35.2's stubs) | approve | -- |
| V12 | Outward calls: none new. An add restarts the runners, as 22.2 built, and a runner build reaches only the admin's server | approve | none |

## Public text

Reused (accepted): "Tools and MCP servers", "Add server", "Remove", "Unclassified only", the dialog sentence for n > 1 and m = 1, "Cancel" (EXPERIENCE). "Unclassified (counts as risky)", "Read-only", "Risky", "Saved" (epics AC; 22.2). McpOps `MESSAGEADDED`, `MESSAGEREMOVED`, `MESSAGEADDRESS`, `MESSAGENAME`, `MESSAGEEXISTS` (approved at 22.2). `settings.refusedExpansion`. `Web.Api` `MESSAGESERVERERROR`. `SETTINGS_TEXTS.denied`. `LOAD_FAILED`, Retry.

New, for the Planner (Settings > Tools and MCP servers unless said; online demo: only T1 shows there):
- T1 `settings.mcpOffOnDemo` (the section's line in place of its content, and the 409 message of every MCP settings route and of `ListMcpServers`): "MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install."
- T2 group headings: "Servers", "Tools".
- T3 server table headers: "Server", "Address", "Status", "Tools", "Unclassified". Empty: "No MCP servers yet."
- T4 status words: "Connected", "Unavailable", "Not checked yet". The group's help line: "A new server's tools show here once OcuTalon next uses its agents. They count as risky until you classify them."
- T5 add form labels: "Name", "Address", "Secret (optional)". The secret's help: "Sent to the server with every request. It is kept in the IRIS Wallet and never shown again."
- T6 secret field error: "Use a secret of up to 4,096 letters, digits and punctuation, with no spaces. Nothing was changed."
- T7 dialog sentences. With n > 1 tools: "Remove {server}? Its {n} tools go at once." (m = 0); "... and 1 pending approval request for them is cancelled." (m = 1, accepted); "Remove {server}? Its {n} tools go at once, and {m} pending approval requests for them are cancelled." (m > 1). With n = 1: "Remove {server}? Its 1 tool goes at once." (m = 0); "Remove {server}? Its 1 tool goes at once, and 1 pending approval request for it is cancelled." (m = 1); "Remove {server}? Its 1 tool goes at once, and {m} pending approval requests for it are cancelled." (m > 1). With n = 0: "Remove {server}? It has no tools." (m = 0); "Remove {server}? 1 pending approval request for its tools is cancelled." (m = 1); "Remove {server}? {m} pending approval requests for its tools are cancelled." (m > 1). [AMENDED 2026-11-13, code review: "cancelled", Contest Planner ruling ~21:30Z (epic-21 rulings); it read "canceled" in each sentence]
- T8 tools table headers: "Tool", "Server", "Status", "Classification". Statuses: "Available", "Unavailable", "Refused: a built-in tool has this name". Empty: "No tools yet." With the filter on: "No unclassified tools."
- T9 "New since 1.0.0" bullet: "- **MCP servers in Settings.** On your own install, an admin adds an MCP server in Settings > Tools and MCP servers, with an optional secret kept in the IRIS Wallet, and classifies each of its tools as Read-only or Risky; until then a tool counts as risky. MCP servers are off on the online demo."
- T12 address field error (ruling B2, approved verbatim): "An MCP server's address can't hold a query string (the part after ?). Put a key in Secret instead. Nothing was changed."
- T10 radiogroup name: "Classification of {tool} on {server}". T11 remove button name: "Remove {server}".

## Verification

**How to run:**
- Run every command from the worktree root after `git rev-parse --show-toplevel` matches it.
- `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Tags: warm `e21s4iw`, fresh `e21s4i` (QA `e21s4qw`/`e21s4q`, review `e21s4rw`/`e21s4r`).
- Run one command per foreground call with `timeout: 600000`, each sized to about 150 s (the harness backgrounds a call at about 170-180 s). For a large class, run it one method per call (`class <Class>:<Method>`).
- Never two test runs in one message, and one `iris_execute_tests` per message with `server` and `namespace`.
- If `ci/warm.sh up` is backgrounded, wait in bounded foreground polls and never restart it.
- McpOps and SettingsOps run in the production, so a mutation of either needs `ci/warm.sh down` then `up` before the class run.
- Tear down only the tags this stage started. Never a slot, `ocutalon-aihub-test` or another lane's stack.

**Shared surfaces:**
- `SETTINGS_SECTIONS` (7 -> 8: `settings.spec.ts:16`, settings-view tests).
- `Web.Api` UrlMap (`TestMcpSettingsRoutes`; `Test/Web/Api.cls` lists `Route` rows only).
- CommandsIn routes (`CommandsStep4` `TestToolVerbs`/`TestOrigins`).
- Message contracts (`Test.Msg.Contracts`, `CommandsStep4` `XData Contracts`).
- `Test.Contract.Ac`'s list. The Core catalog count (`Test.Msg.Catalog`). The `ux-strings.test.mjs` inventory. `api-types.ts`.
- The entry, wallet and resource of every `zz` server: McpOps' add now writes them, and its remove drops them. So `Test.Mcp.Ops`, `Attach` and `Classification` clean them, and the `JobFixture` entry of `Test.Mcp.Approval` is dropped by its removal tests.
- `ApprovalRequest` fixture rows (B4, `SettingsMcp`, `TestMcpEntryWrite`); the removal cancels them, so each test deletes them by Ref whatever their state.
- Criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- `<vars> OCUTALON_RUN_TAG=e21s4iw ci/warm.sh up` (once) -- ready.
- `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s4iw ci/iris.sh class OcuTalon.Test.Core.CommandsStep4` (loop) -- pass. Mutations:
  - `SaveEntry`'s call removed from `Register` -> `TestMcpEntryWrite` red.
  - The undo `DropEntry` dropped from the audit-failure path -> red.
  - The `DropEntry` call removed from `Unregister` -> red.
  - `ListMcpServers` origins `web_admin,tool` -> `TestMcpVerbsFromATool` red.
- `... class OcuTalon.Test.Web.McpSettingsApi` (loop) -- pass. Mutations:
  - The secret check after `Put` -> the "nothing offered" case red.
  - `Discard` skipped on an error path -> red.
  - The demo check after the body read -> red.
- `... class OcuTalon.Test.Core.SettingsMcp` (loop) -- pass. Mutations:
  - `unclassified` counted over every tool -> red (AC 1).
  - `PendingToolCalls` without the `State` filter -> red (AC 4's count).
  - `ToolSource` compared with `%EXACT` -> the other-case row red (C3 parity with `CancelPending`).
  - The demo refusal removed -> red (AC 6).
- `... class` for `OcuTalon.Test.Mcp.Ops`, `OcuTalon.Test.Mcp.Classification`, `OcuTalon.Test.Mcp.Tools`, `OcuTalon.Test.Msg.Contracts`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Contract.Ac`, `OcuTalon.Test.Core.Routing`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Web.SettingsApi`, `OcuTalon.Test.Web.HookSettingsApi`, `OcuTalon.Test.Core.SettingsWebhooks` (once each, one per call) -- pass.
- `... class OcuTalon.Test.Mcp.Attach:TestCommands`, then `...:TestRemovedServer` (once each, one per call) -- pass.
- `... class OcuTalon.Test.Mcp.Approval:TestRemovedWhilePending`, `...:TestRemovedWhileApproved`, `...:TestCancellingTwiceIsANoOp` (once each, one per call; throwaway only, Rule 21) -- pass, with the `JobFixture` `Leftovers` empty.
- `node --test web/scripts/` (once) -- pass. Mutation: `removeQuestion` with m = 1 and the plural verb -> red. Then `cd web && npx tsc -p tsconfig.e2e.json --noEmit` and `cd web && npm run build` (once each) -- clean.
- `<vars> OCUTALON_RUN_TAG=e21s4i ci/iris.sh build` (once).
- `<vars> OCUTALON_RUN_TAG=e21s4i ci/iris.sh live sign-in-2 --part k/n` (once; the part whose PART line lists `settings/mcp.spec.ts`, with n large enough for about 150 s) -- pass. Mutation: the radiogroup's save on change removed -> B3 red.
- `ci/iris.sh live sign-in --part k/n` (once; the part listing `api/mcp.spec.ts`) -- pass. Mutation: the route submitting without `Handoff` -> M2 red (the mock says `absent`).
- `<vars> OCUTALON_RUN_TAG=e21s4iw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s4i ci/iris.sh teardown` (once each, also after a failure).
- `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh` (once each) -- pass.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once, after S1-S6) -- no finding beyond the baseline.

**Manual checks:**
- (AC 7, once) `grep -n 'SaveMcpEntry\|RemoveMcpEntry' _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md src` -- every hit in the spine is inside an "it read" history clause, and `src` has none.
- (C3, once) `grep -n "Kind = 'tool_call' AND State = 'pending' AND ToolSource = ?" src/bridge/cls/OcuTalon/Bridge/Approval.cls src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- one hit in each, with the same predicate.

**Pass 4 review mutations (Rule 19; each applied, observed red, reverted byte-identical, and the class or unit green again on the same stack):**
- mutation: `SaveEntry`'s final `DropEntry` after a failed write removed -> `TestMcpEntryWrite` red ("the entry is dropped before the write and once more after the failed write") -> reverted (warm stack down and up)
- mutation: the `(secret [ "@{")` refusal removed from `SaveEntry` -> `TestMcpEntryWrite` red ("an add of a secret that holds @{ is answered failed") -> reverted
- mutation: the error text of the failed drop logged by `Unregister` -> `TestMcpEntryWrite` red ("that holds no error text of the drop") -> reverted
- mutation: `SaveEntry` logs the secret (AC 2, the leak scans) -> `TestMcpEntryWrite` red ("no event log row holds it after the add", "no trace global holds it ...") -> reverted
- mutation: `Web.McpSettings` `Answer` answers OK with no body for an unknown outcome -> `TestFailedAnswers` red -> reverted
- mutation: Web.Api's `/v1/settings/mcp` prefix changed -> `TestMcpSettingsRoutes` red -> reverted
- mutation: the Tools and MCP servers row removed from `SETTINGS_SECTIONS` -> `settings-view.test.mjs` red (AC 1's eighth section) -> reverted
- mutation: the Remove dialog's `act` removes another name -> B4 red (AC 4's Remove) -> reverted
- mutation: `stateOf` maps `off` to `failed` -> B5 red (AC 6's section) -> reverted
- mutation: the pick's error handler without the old value put back -> B6 red -> reverted (the three web mutations in one `live sign-in-2 --part 10/12` run: 3 failed, 18 passed; the same run after the revert: 21 passed)

**QA stage (2026-11-13; branch `wip/21-4-impl1`; warm `e21s4qw`, fresh `e21s4q`, both torn down).** The gaps only; every row below was already pinned and needed no test: "Add refused" at the route and at McpOps (`TestAddRefusals`, `TestAddressWithQuery`, `TestMcpEntryWrite`, `Test.Mcp.Ops`), the demo's 409 before the body on every route (`TestOnlineDemo`), the 403 on every route (`TestNotAdmin`, M1, `SettingsApi`), the pending count against `CancelPending` (`SettingsMcp:TestPendingByToolref`, `TestMcpEntryWrite`, B4), the filter (`mcp-view.test.mjs`, B1), the view rules of the section's states (`mcpOutcome`).
Gaps closed (each a test that failed under its mutation and passed unmutated):
- the limits of an add and the verbatim secret (`TestAddAcceptsTheLimits`: a 40-character name, a 2,000-character address and a 4,096-character secret of every printable ASCII character, stored byte for byte; no existing case added anything at a limit or with a non-alphanumeric secret);
- the matrix row "Add without secret" at the route (`TestAddWithoutSecret`: an absent secret and `""`; no handoff, no auth member, no wallet collection, the list shows the address);
- the admin check before the demo's 409 and before the body, on all four routes (`TestNotAdminComesFirst`);
- the secret of a refused or failed add in no answer, log row, audit entry, trace global (`TraceLeaks`), stored command or global: a bad name, a name that exists (real McpOps), and a submit that fails, throws or is answered `failed` or `not_audited` (`TestRefusedAddsLeakNoSecret`);
- classification changes through the route (`TestClassifyEveryWord`: each of the three words saved on the named server and tool only, the list's tool and unclassified counts, one Tool audit entry per change, the 128-character tool name and the 404 for 129 characters or another case; the existing cases saved only `read-only`, so a route that always sent `read-only` was green);
- the section's denied, load-error and Retry states, and the 500 of an add and of a removal (B7 to B10 in `web/e2e/settings/mcp.spec.ts`, every answer fulfilled by the test, no fixture).
Not a gap: B10's 404 branch (the dialog closes and the server leaves the lists) is also covered by B4's 200 path and the shared `ConfirmDialog`; skipping `gone()` turned only B4 red, so no `mutation:` line is claimed for it.
- mutation: `SECRETMAX` compared with `>=` in `Web.McpSettings.AddFields` -> `TestAddAcceptsTheLimits` red -> reverted byte-identical
- mutation: the secret pattern narrowed to `^[A-Za-z0-9]+\z` -> `TestAddAcceptsTheLimits` red -> reverted byte-identical
- mutation: `ADDRESSMAX` compared with `>=` -> `TestAddAcceptsTheLimits` red -> reverted byte-identical
- mutation: a name longer than 39 characters refused by the route -> `TestAddAcceptsTheLimits` red -> reverted byte-identical
- mutation: the secret check refuses an empty string -> `TestAddWithoutSecret` red -> reverted byte-identical
- mutation: `Add` hands off with `optional` 0 (a handoff for an empty secret) -> `TestAddWithoutSecret` red -> reverted byte-identical
- mutation: the online-demo check before the admin check in `Refusal` -> `TestNotAdminComesFirst` red -> reverted byte-identical
- mutation: `Add` reads the body before `Refusal` -> `TestNotAdminComesFirst` red -> reverted byte-identical
- mutation: `Add` logs the secret of a refused add -> `TestRefusedAddsLeakNoSecret` red (event log row, trace global) -> reverted byte-identical
- mutation: `Classify` sends `read-only` in place of the pick -> `TestClassifyEveryWord` red -> reverted byte-identical
- mutation: `TOOLMAX` compared with `>=` -> `TestClassifyEveryWord` red -> reverted byte-identical
- mutation: `McpSection.stateOf` maps denied to failed -> B7 red -> reverted byte-identical
- mutation: Retry does not ask for the list again -> B8 red -> reverted byte-identical
- mutation: a refused add (500) does not reload the list -> B9 red -> reverted byte-identical
- mutation: the removal's failure text emptied -> B10 red -> reverted byte-identical (the four web mutations in one `live sign-in-2 --part 10/12` run: 4 failed, 12 passed; the run before them and with the web source unmutated: 16 passed)
Runs: warm `e21s4qw`: `Test.Web.McpSettingsApi` whole class green (15 s) after the new methods were run one by one; fresh `e21s4q`: `ci/iris.sh build` and `live sign-in-2 --part 10/12` 16 of 16 (B1 to B10 and the six others of the part). `web/src` is byte-identical to HEAD (`cmp` against the copy taken before the web mutations), so the initial bundle is unchanged (998.08 kB).
Test files touched by QA: `src/ocutalon/cls/OcuTalon/Test/Web/McpSettingsApi.cls` (QA), `web/e2e/settings/mcp.spec.ts` (QA).

**Code review 2 (2026-11-13; warm `e21s4cw`, fresh `e21s4cr`, both torn down).** Each mutation applied, observed red, reverted byte-identical (`cmp` against a saved copy), and the class or unit green again on the same stack:
- mutation: `Unregister` drops by the typed name (`DropEntry(server)` in place of `DropEntry(stored)`) -> `Test.Core.CommandsStep4:TestMcpEntryWrite` red ("and the row, the tool rows, the resource, the entry, the wallet key and the collection are gone", the upper-case remove) -> reverted; `CommandsStep4` whole class green
- mutation: the tool radiogroups named by row position (`'mcp-class-' + index`) -> B1 red ("the unclassified tool is still checked as such") -> reverted
- mutation: the servers table's address cell bound to `server.name` -> B2 red ("with its address") -> reverted (AC 1's address)
- mutation: T7's n > 1, m = 1 sentence back to "canceled" -> B4 red ("the dialog is named by its sentence"), and `mcp-view.test.mjs`/`ux-strings.test.mjs` 3 red -> reverted (the three web mutations in one `ci/iris.sh build` + `live sign-in-2 --part 10/12` run: 3 failed, 13 passed; after the revert and a rebuild: 16 passed)
- (test, not an AC pin) `Test.Mcp.Attach:TestCommands` handed a wrong secret over -> red ("AI Hub's client sent the handed-over secret as the bearer token with every request") -> reverted, green
- Records moved here from `## Auto Run Result` (implement pass 2; each was applied and observed red there):
  - mutation: (Planner condition B) the McpOps address check skipped when a handoff is present -> `TestMcpEntryWrite` red; the `Web.McpSettings.AddFields` address check skipped when a secret is present -> `McpSettingsApi:TestAddRefusals` red
  - mutation: (AC 1, the filter) `visibleTools` keeps every tool with the filter on -> `mcp-view.test.mjs` red
  - mutation: (AC 3) `ListMcpServers` origins `web_admin,tool` -> `CommandsStep4:TestOrigins` and `TestToolVerbs` red
  - mutation: (AC 5) the radiogroup's `(change)` handler removed -> B3 red
- AC 7 (the spine's wording) is pinned by the manual grep under "Manual checks" only: it is static document text, so it has no test and no `mutation:` line.
Runs, all green: warm `CommandsStep4` (whole), `SettingsMcp`, `Mcp.Attach:TestCommands`, `Mcp.Attach:TestRemovedServer`, `Mcp.Ops`, `Web.McpSettingsApi`, `Mcp.Approval:TestRemovedWhilePending`; fresh `live sign-in-2 --part 10/12` 16 of 16 and `live sign-in --part 2/16` 20 of 20 (`api/mcp.spec.ts` M1-M5); `node --test web/scripts/` 1993 pass; `tsc -p tsconfig.e2e.json` clean; `npm run build` initial 998.08 kB (unchanged), `mcp-section` lazy chunk 19.76 kB; `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh` pass; `lint_spine.py` the 10 baseline findings.

## Auto Run Result

Status: done
Blocking condition: none

**Summary (final, pass 4 and its review).** Story 21.4 is implemented: the four admin-checked MCP settings routes (`Web.McpSettings`), the secret handoff to McpOps' own job (entry and wallet write and drop), `ListMcpServers`, the eighth Settings section (lazy chunk), T1-T12, the spine S1-S6 and the docs. Pass 4 closed B1 by option (i): `Test.Mcp.Attach:TestRemovedServer` now pins `UNREGISTERED` mid-turn and, for a turn started after the removal, that none of the server's tools is listed and that a scripted call by name is `ToolNotFound` with no request at the mock. `Mcp/Attach.cls` is unchanged. "Exactly one audit entry for the refused call": the gate refuses an `UNREGISTERED` call before any audit step (`Gate.cls` "denied at once"), so the test asserts the removal's one MCP audit entry and that the denied calls add none.

**Files changed (whole story, `96bbbcd8..`):** the routes and handlers (`Web/McpSettings.cls`, `Web/Api.cls`, `Web/HookSettings.cls`, `Core/SettingsOps.cls`, `Core/CommandsIn.cls`, `Mcp/Ops.cls`, `Data/Ownership.cls`, `Msg/Catalog/Core.cls`, `Msg/Command/*`), the web section (`settings/mcp-section.ts`, `mcp-view.ts`, `settings-view.ts`, `settings-page.ts`, `api-client.ts`, `api-types.ts`), the tests (`Test/Core/CommandsStep4.cls`, `SettingsMcp.cls`, `Test/Web/McpSettingsApi.cls`, `McpSettingsProbe.cls`, `Test/Mcp/Ops.cls`, `Attach.cls`, `OpsProbe.cls`, `web/e2e/**/mcp*.ts`, `web/scripts/*.test.mjs`), `GUIDE.md`, EXPERIENCE and the spine.

**Review (pass 1 of the story; 32 findings, none high):** 7 patched (tests, a probe seam, e2e B6, a spine clause, mutation lines), 22 low rejected with reasons, 3 false; the table is in `## Review Triage Log`. No finding was deferred (`deferred: []`). Follow-up review recommended: false (no `high` was patched).

**Verification (pass 4 and the review patches):** warm `e21s4iw4`: `Test.Mcp.Attach` (whole class), `Approval`, `Proxy`, `ProxyJob`, `Ops`, `Client`, `Test.Bridge.Gate` and `Test.Core.CommandsStep4` green. Fresh `e21s4i4`: `Test.Mcp.Attach:TestRemovedServer`, `Test.Web.McpSettingsApi`, `Test.Core.SettingsMcp` and `Test.Core.CommandsStep4` green; `live sign-in --part 2/16` (`api/mcp.spec.ts`, M1-M5 with the two new M5 cases) 20 of 20; `live sign-in-2 --part 10/12` 21 of 21 (B1-B6). `npm run build` clean, initial bundle 998.08 kB (the 1 MB error budget; unchanged); `node --test web/scripts/` 1993 pass; `tsc -p tsconfig.e2e.json` clean; `test-boundaries.sh`, `test-class-rules.sh`, `test-ci-config.sh` pass; `lint_spine.py` the 10 baseline findings. No 22.x regression.

**Residual risks:** the add path has no refusal of a key in an address path (ruling B2); an entry saved by hand with a query string is not refused at runtime (DW-1285); the section's denied, load-error and Retry states have no browser case.

Earlier record (pass 3's stop, resolved by the 20:25Z re-rulings above): B1 (c) could not be implemented as ruled, because the V3 drop and `UNREGISTERED` for a turn composed after the removal contradict each other; the re-ruling chose option (i).

**Implement pass 4 (2026-11-13; branch `wip/21-4-impl1`; B1 option (i)).**
- Changed: only `Test.Mcp.Attach:TestRemovedServer` (and its class-doc line); `Mcp/Attach.cls` and every other production file are unchanged. The mid-turn part (a user's turn whose map was built before the removal) keeps `UNREGISTERED` for both tools, no taint and no approval request, and now also asserts that the removal is the one MCP audit entry of the server (`removed`) and that the denied calls add no MCP or Tool entry. The new-turn part (an untrusted turn started after the removal) asserts that its manager lists none of the server's tools and no `call_mcp_tool`, and, through the adapter's `CallTool` (the test's scripted call by name), that a call of each removed tool is `ToolNotFound`, runs nothing, taints nothing and raises no approval request. Finally the mock's request log shows no `tools/call` from any client.
- Review note (mock model): the class has no model; its adapter (`Test.Bridge.ZzTurnAdapter.CallTool`) runs `ExecuteTool(name, arguments)` on the turn's manager, so a tool call by name can be scripted, and the extra proof is in. A scripted call by name is not a model turn: the CI model mock's own tool-call scripting is not used here.
- Green on warm `e21s4iw4`: `Test.Mcp.Attach` (whole class, 151 s), `Test.Mcp.Approval`, `Test.Mcp.Proxy`, `Test.Mcp.ProxyJob`, `Test.Mcp.Ops`, `Test.Mcp.Client` and `Test.Bridge.Gate`. Green on fresh `e21s4i4`: `Test.Mcp.Attach:TestRemovedServer`, `Test.Web.McpSettingsApi`, `Test.Core.SettingsMcp`; `live sign-in --part 2/16` (`api/mcp.spec.ts`, M1-M5 with the two M5 cases) 20 of 20. `npm run build` clean, initial bundle 998.08 kB (the 1 MB error budget; unchanged). `test-boundaries.sh`, `test-class-rules.sh`, `test-ci-config.sh` pass; `node --test web/scripts/` 1993 pass.
- mutation: the `DropEntry` call skipped in `Mcp.Ops.Unregister` (warm stack taken down and up for it) -> `Test.Mcp.Attach:TestRemovedServer` red (the new turn's manager lists `zz_lookup`, `zz_delete_ticket` and `call_mcp_tool`, and a scripted call by name is `ToolAccessDenied`, not `ToolNotFound`) -> reverted byte-identical (`cmp` against the saved copy; `git status --short` lists only the spec and `Test/Mcp/Attach.cls`)
- Warm `e21s4iw4` and fresh `e21s4i4` torn down; nothing of this pass is left running.

**Implement pass 3 (2026-11-13; branch `wip/21-4-impl1`; B2 done, B1 blocked).**
- B2 refusal: `Mcp.Ops` `MESSAGEQUERY` (T12, word for word) and the check in `OnAdd` after the `AddressAllowed` check (`bad_address`, nothing written or audited); `Web.McpSettings` `AddFields` refuses `?`/`#` as the `address` field text; `Mcp.Ops.AddressAllowed`, `Mcp.Proxy` and `Mcp.Client` unchanged. Lane A fixtures in `Test/Mcp/Ops.cls` as the ~19:50Z entry says (`TestBadAddress`: the `?b=c` address moves to the refused list; `TestNoAddressOrSecretInAnyText`: the added address is query-free and carries the secret probe, the `?token=` address is a refused case with its own scan, the plain-http case is unchanged). New test `Test.Web.McpSettingsApi:TestAddressWithQuery` (route and McpOps); two M5 cases in `web/e2e/api/mcp.spec.ts`. No web code, no doc note.
- Green on warm `e21s4iw3`: `Web.McpSettingsApi`, `Mcp.Ops`, `Core.SettingsMcp`, `Core.CommandsStep4`, `Mcp.Attach:TestCommands`. `ci/iris.sh build` and `live sign-in-2 --part 10/12` passed on `e21s4i3`; `node --test web/scripts/` 1993 pass; `tsc -p tsconfig.e2e.json` clean; `test-boundaries.sh` and `test-class-rules.sh` pass. Red: `Mcp.Attach:TestRemovedServer` (B1, as above). Not run: the 22.x classes (no Attach change), `npm run build` (no web change), the live `api/mcp.spec.ts` part (the two new M5 cases are not run live).
- mutation: the `?`/`#` check skipped in `Web.McpSettings.AddFields` -> `TestAddressWithQuery` red (route cases) -> reverted
- mutation: the `?`/`#` check skipped in `Mcp.Ops.OnAdd` -> `TestAddressWithQuery` red (McpOps cases) -> reverted
- Warm and fresh stacks (`e21s4iw3`, `e21s4i3`) torn down. No review layers were run (the story is blocked).

**Implement pass 2 (2026-11-13; worktree `epic-21`, branch `wip/21-4-impl1`, HEAD `ea830d21`, everything below is UNCOMMITTED).**

Still open (the two rulings; nothing in this pass decides them):
- B1: `Test.Mcp.Attach:TestRemovedServer` sees `ERROR <%AICore>ToolNotFound: Tool not found: zz_lookup` instead of `UNREGISTERED` after McpOps drops the entry in `Unregister`. The `DropEntry` call in `Unregister` is kept as it is; the test is untouched. Confirmed red again in this pass (two asserts: "denied with UNREGISTERED" and "so is the call to its other tool").
- B2: IRIS's own audit entry "Create Configuration: AI.MCP.OcuTalon_<server>" holds the entry URL; `Test.Mcp.Ops` `TestNoAddressOrSecretInAnyText` keeps pass 1's narrowing to source `OcuTalon` (not extended). `Test.Mcp.Ops` is green with it. The e2e M6 scan reads the audit table without that narrowing for the secret only: no entry of any source holds the secret (an address in IRIS's own entry is B2's question and is not asserted here).
- Nothing else is gated by B1/B2.

Done in pass 2:
- Web section: `web/src/app/settings/mcp-view.ts` (MCP_TEXTS, `removeQuestion` with T7's nine forms, `statusText`, `toolStatusText`, `visibleTools`, `addBody`, `mcpOutcome`, `withClassification`), `mcp-section.ts` (states loading/ready/off/denied/failed; Servers table with Remove per row, T11 names; Add server form with Name, Address, Secret (`type="password"`, `autocomplete="off"`), field errors under each field with the first focused; the Remove dialog is the shared `ConfirmDialog` (Rule 2: its heading is the sentence, first-focused and naming the dialog); Tools table with "Unclassified only" and a three-radio `role="radiogroup"` per row named T10, `classification-*` chips, `Icon check` on the checked one, save at once, "Saved" per row, old value back on failure). `settings-view.ts` has the eighth section `mcp` ("Tools and MCP servers", last); `settings-page.ts` opens it (`@case ('mcp')`). `api-types.ts` and `api-client.ts` have `McpSettings`, `McpServerRow`, `McpToolRow`, `McpChanged`, `McpError` and `mcpSettings()`, `addMcpServer`, `removeMcpServer`, `classifyMcpTool`.
- Web tests: new `web/scripts/mcp-view.test.mjs` (T7's forms, filter, body, outcome, T1 equal to `catalogText('settings.mcpOffOnDemo')`); `ux-strings.test.mjs` imports `MCP_TEXTS` and has the new entries (every T-text is a `ux` source from the new EXPERIENCE rows; "Unclassified (counts as risky)" and "Risky" are `ac`); `settings-view.test.mjs` is eight sections; the source guards `announce-focus-sources.test.mjs` (speakers, focus calls, render waits, ConfirmDialog users) and `floor-sources.test.mjs` (dialog openers, scrollers) name `mcp-section.ts`; new `web/e2e/api/mcp.spec.ts` (M1, M2-M4 and M6 as one case, M5), `web/e2e/settings/mcp.spec.ts` (B1-B5), `web/e2e/support/mcp.ts`; `settings.spec.ts` has the eighth section (S1, S1f, the POST list).
- Docs: EXPERIENCE "Settings and requests (step 4)" has T1-T8, T10 and T11 as 17 rows (marker `[ADDED 2026-11-12, Story 21.4, Contest Planner ruling B]`; T6 is `Web.McpSettings` `MESSAGESECRET`); GUIDE.md "New since 1.0.0" has T9 under "Your integrations" after "Your own mailbox.". All verbatim.
- Spine S1-S6 with markers (AD-19 two places, AD-21 two places, Seed (a row replaced and a row added), three REST rows, AD-1 sub-bullet); `lint_spine.py`: 10 low placeholder findings, the baseline, none new. `grep SaveMcpEntry|RemoveMcpEntry`: every hit in the spine is inside an "it read" clause, `src` has none. A `spine_updated` line is in `cycle-log-epic-21.md`.
- Checks: `node --test web/scripts/` 1993 pass, 0 fail; `tsc -p tsconfig.e2e.json` clean; `npm run build` clean (initial bundle 998.08 kB against the 1 MB error budget, see Decided 17); `test-boundaries.sh`, `test-class-rules.sh`, `test-ci-config.sh` pass.
- Live: `ci/iris.sh live sign-in-2 --part 10/12` (session, email, mcp: B1-B5) 20 of 20; `live sign-in --part 2/16` (api/mcp.spec.ts M1-M5 with the mock and a real runner build) 20 of 20; `live sign-in-2 --part 11/12` (settings.spec.ts) once failed on my own missed count (S1f `toHaveCount(7)`), fixed, and the re-run passed (26 of 26).
- Warm ObjectScript classes (tag `e21s4iw2`, one class per call), all green: Core.CommandsStep4, Web.McpSettingsApi, Core.SettingsMcp, Mcp.Ops, Mcp.Classification, Mcp.Tools, Msg.Contracts, Msg.Catalog, Contract.Ac, Core.Routing, Web.Api, Web.SettingsApi, Web.HookSettingsApi, Core.SettingsWebhooks, Mcp.Attach:TestCommands, Mcp.Approval:TestRemovedWhilePending, :TestRemovedWhileApproved, :TestCancellingTwiceIsANoOp.
- Task 0 (e): in M2 one chat message after the add let a runner build and attach the mock's two tools within 13.5 s of the whole case; which runner built was not recorded (the test asserts the result, not the runner).

Red tests and why:
- `Test.Mcp.Attach:TestRemovedServer` (2 asserts): B1 only.
- No other red test remains.

Mutations (Rule 19; each applied, observed red, reverted byte-identical and equal to HEAD):
- mutation: removeQuestion m = 1 with the plural verb -> `mcp-view.test.mjs` red (and `ux-strings.test.mjs`) -> reverted
- mutation: `visibleTools` keeps every tool with the filter on -> `mcp-view.test.mjs` red (2) -> reverted
- mutation: `removeQuestion` treats one tool as many -> red -> reverted
- mutation: `withClassification` counts unclassified over every server -> red (2) -> reverted
- mutation: radiogroup `(change)` handler removed -> B3 red (`live sign-in-2 --part 10/12`) -> reverted
- mutation: `Web.Api.HandOff` without `Set command.Handoff = uri` -> M2 red (`live sign-in --part 2/16`: no wallet key or collection made) -> reverted
- mutation: `SaveEntry` call removed from `Ops.Register` -> `CommandsStep4` `TestMcpEntryWrite` red -> reverted
- mutation: `DropEntry` removed from Register's audit-failure path -> NOT red at first (no test pinned it, in `CommandsStep4` or `Test.Mcp.Ops`); pin added (the audit-failure case in `TestMcpEntryWrite`), then red -> reverted
- mutation: `DropEntry` call removed from `Ops.Unregister` (applied for the run and reverted; the call is as pass 1 left it) -> `TestMcpEntryWrite` red -> reverted
- mutation: `ListMcpServers` origins `web_admin,tool` -> `TestOrigins` and `TestToolVerbs` red -> reverted
- mutation: the secret checks of `Web.McpSettings.AddFields` skipped -> `McpSettingsApi` `TestAddRefusals` red -> reverted
- mutation: `Discard` skipped in `Web.Api.HandOff` -> `McpSettingsApi` red (`TestAddRefusals`, `TestHandoffDiscardedOnFailure`) -> reverted
- mutation: demo check after the body read in `Web.McpSettings.Add` -> `TestOnlineDemo` red -> reverted
- mutation: `unclassified` counted over every tool in `ListMcp` -> `SettingsMcp` `TestList` red -> reverted
- mutation: `PendingToolCalls` without the State filter -> `TestPendingByToolref` red -> reverted
- mutation: `ToolSource` compared with `%EXACT` -> `TestPendingByToolref` red -> reverted
- mutation: the demo refusal removed from `ListMcp` -> `TestOnlineDemo` red -> reverted
- mutation: condition B, `Ops` address check skipped when a handoff is present -> `TestMcpEntryWrite` red -> reverted
- mutation: condition B, `Web.McpSettings.AddFields` address check skipped when a secret is present -> `McpSettingsApi` `TestAddRefusals` red -> reverted
(19 mutations, all observed red; none left in the tree.)

Added beyond the task list, in this pass:
- The audit-failure pin in `TestMcpEntryWrite` (`Test/Core/CommandsStep4.cls`): an add whose audit fails is `not_audited` and leaves no row, resource, entry, key or collection. It was the only mutation of the spec's list that no test caught.
- Guard tests of the web source updated for the new file (`announce-focus-sources`, `floor-sources`): each lists the files that may announce, move focus, wait for a render, open a dialog or scroll; `mcp-section.ts` is added to each with its reason.

Decided in this pass (reversible inside the story; Design Notes numbering continues):
- (17) `mcp-section.ts` is loaded on demand (`import('./mcp-section')` through `NgComponentOutlet`, set when the section first opens). With it in the initial bundle the build was 1,011,990 bytes against the 1 MB error budget (the baseline was 992,400); on demand the initial bundle is 998.08 kB and the section is a 19.88 kB lazy chunk. The headroom is now about 1.9 kB: the next story that adds to the initial bundle will meet the budget. Flag for the lead (not a story decision).
- (18) The Remove dialog is the shared `ConfirmDialog` with `ConfirmRequest` (Rule 2), not a new dialog in `unsaved-dialog.ts`'s shape: its heading is the sentence, which names the dialog and takes the first focus (UX-DR38). The failure line in the dialog, and under the form, the tool row and the add button, is the server's own `error.message` (for a 500 that is `MESSAGESERVERERROR`), and "Couldn't save. Nothing was changed." (`SETTINGS_TEXTS.failed`, accepted) when the server sent none: the page holds no copy of `MESSAGESERVERERROR`.
- (19) A tool row that was classified while "Unclassified only" is on stays in the table until the section is opened again, so its "Saved" line can be read.
- (20) M2, M3, M4 and M6 are one e2e case (one runner build for the four), titled "M2 to M4 and M6".
- No sentence of the spec was left out for lack of an accepted text.

Veto items from this pass: none. No new public text beyond T1-T11 (the reused texts are "Cancel", "Add server", "Remove", "Unclassified only", "Saved", "Retry" and the accepted settings texts), no stored-data shape, no security-posture change. One note for the record: the M2 spec starts the mock with the expected header value on an `irisScript` command line (a random throwaway secret in a throwaway stack, as the spec says "a random secret"), so it is visible to `ps` inside the CI host for the length of the call; no real credential is ever used.

Stacks: warm `e21s4iw2` torn down (`ci/warm.sh down`); the throwaway tag `e21s4i` torn down with `ci/iris.sh teardown`.
