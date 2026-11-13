---
title: 'Story 21.4: Add, remove and classify MCP servers and tools in Settings'
type: 'feature'
created: '2026-11-12'
status: 'in-progress'
baseline_revision: '96bbbcd8ecb47dfd42eafb0b83cf1785d8099cd1'
review_loop_iteration: 0
followup_review_recommended: false
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

## Spec Change Log

- 2026-11-13 (lead, Planner rulings `prompts/epic-21-rulings-20261113-1800.md`, binding; pass 3 scope):
  - **B1 (c), granted.** This is a cross-lane grant for this one change only: Lane A's `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` and `Test/Mcp/Attach.cls` `TestRemovedServer`. When Attach re-attaches recorded specs, it skips the spec of a server that has no `Mcp.Server` row. The gate then refuses the call with `UNREGISTERED` and writes its audit entry. `TestRemovedServer` asserts three things: `UNREGISTERED`, exactly one audit entry for the refused call, and no `ToolNotFound` anywhere in what it checks. The V3 drop of the entry and the wallet collection at removal stays. A contradiction with 22.x behaviour is a STOP.
  - **B2, accepted.** `Test.Mcp.Ops:TestNoAddressOrSecretInAnyText` keeps its audit assertion narrowed to source `OcuTalon`. IRIS's own audit entries are outside our control.
  - **B2, added refusal.** Both McpOps' address check and the route's refuse an address that holds `?` or `#` (a query string or a fragment). It is a 400 `bad_mcp_server` with the field `address`, the McpOps refusal mapped to its field like the others, and nothing written or audited. The new field text is T12, word for word: "An MCP server's address can't hold a query string (the part after ?). Put a key in Secret instead. Nothing was changed." Add one test that refuses such an address at the route and at McpOps, with its mutation: the check skipped -> red. No doc note. If Task 0's measured attach address, or the Jira example's address (`docs/mcp-jira-example.md` and the guide, if present), needs a query string, STOP and report.
  - The address rules stay EXACTLY as ruled. Lane D's 22.6 review checks its claims against them at its merge.
  - Keep new web code in lazily loaded chunks. The initial bundle has about 1.9 kB of headroom.
- 2026-11-13 ~19:50Z (lead, after pass 3 stopped on the lead's own extra STOP condition; the ruling's STOP triggers are not met: Task 0's measured attach has no `?`/`#`, and `docs/mcp-jira-example.md` does not exist yet). Decided within ruling B2:
  - **Where the check lives:** in McpOps' ADD path, beside the existing address check of `OnAdd`/`Register`, and in the route. It is NOT in `Mcp.Ops.AddressAllowed`, because `Mcp.Proxy:84` calls that at call time (pinned by `Test/Bridge/CodeRules.cls:768`), and putting it there would change 22.x's runtime behaviour for an existing entry. `Mcp.Proxy` and `Mcp.Client` are unchanged.
  - **Lane A fixtures follow the ruling** (they are inside B2's scope in `Test/Mcp/Ops.cls`):
    - `TestBadAddress` (:148): `https://example.com:8443/a?b=c` moves from the allowed list to the refused list, refused with T12.
    - `TestNoAddressOrSecretInAnyText` (:503): the ADDED case uses a query-free address that still carries the secret probe (for example `https://<address>.example.invalid/mcp/<secret>`), so the scan still has a value to look for. The old `?token=<secret>` address becomes a REFUSED case, and it too must leave neither the address nor the secret in any text.
    - :512 keeps its own refusal reason (plain http to a non-loopback host).
    - `Test/Mcp/Client.cls` is unchanged.
  - Reported to the coordinator for veto.
  - **Pass 3 scope (lead overrides, binding).**
    - B1 (c): in `Mcp/Attach.cls`, make the smallest change that makes the re-attach of recorded specs skip the spec of a server with no `Mcp.Server` row; no other Attach change. `TestRemovedServer` is never weakened. Keep the V3 `DropEntry` in `Unregister`. Run ALL of `Test.Mcp.Attach`, `Test.Mcp.Approval`, `Test.Mcp.Proxy`, `Test.Mcp.ProxyJob`, `Test.Mcp.Ops` and `Test.Bridge.Gate`, one class per call. Any 22.x regression or contradiction is a STOP: set `blocked`, name it, and halt.
    - B2 refusal: McpOps' address check (`Mcp/Ops.cls`) and the route's (`Web.McpSettings`) both refuse an address holding `?` or `#`: 400 `bad_mcp_server`, field `address`, text T12 verbatim. Put T12 where the other address messages live, registered the way they are, apostrophes authored the way the neighbours do. Nothing is written or audited. Add ONE test covering both the route and McpOps, with its `mutation:` line (the check skipped -> red). The narrowing in `Test.Mcp.Ops` stays. No doc note. Keep the address rules exactly as ruled, nothing more.
    - STOP with `blocked` if Task 0's measured attach address, any existing test fixture address, or the Jira example's address (`docs/mcp-jira-example.md`, the GUIDE, the README, `Test.Mcp.Mock` addresses) needs `?` or `#`; report where.
    - Web: any new web code stays inside the lazily loaded MCP chunk; check the initial bundle with `npm run build`. If the web shows the server's refusal text, no web text is needed.
    - Rule 19: every new pin gets its `mutation:` line. Rule 14: `## Auto Run Result

Status: in-progress
Blocking condition: none (pass 3 re-dispatched with the lead's decisions)
