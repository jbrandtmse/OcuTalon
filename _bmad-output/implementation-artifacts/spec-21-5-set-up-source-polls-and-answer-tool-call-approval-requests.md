---
title: 'Story 21.5: Set up source polls in Settings'
type: 'feature'
created: '2026-11-12'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-4-add-remove-and-classify-mcp-servers-and-tools-in-settings.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** An admin can classify an MCP tool Read-only, but cannot make it a source: the page has no source-poll form, `Web.McpSettings` (Story 21.4) has no `/sources` route, and the settings GET lists no sources. `SetSourcePoll`/`RemoveSourcePoll` exist as commands, but nothing on the page sends them. The rail shows no schedule for a `source` check.

**Approach:** Extend 21.4's section and routes. In the tools table, each Read-only tool gets "Use as a source", which opens a form (Source name, Arguments (JSON), Check every). A tool that is not Read-only can't be chosen, and the accepted reason shows beside it. Two admin-checked routes in `Web.McpSettings` submit `SetSourcePoll` and `RemoveSourcePoll` (origin `web_admin`, the admin's `SessionRef`) to Lane A's `McpOps`, which Story 22.5 builds. 21.4's `ListMcpServers` answer gains `sources`: the caller's own session's source rows. The rail's check row for a `source` reads "Polled every {duration}" (ruling C/D, V7). All of it is off on the online demo, where 21.4's T1 line shows. **Split (ruled, V5):** epics ACs 2-4 (the approval requests on every channel) are Story 21.10.

## Boundaries & Constraints

**Always:**
- Each change is a command with origin `web_admin`, sent through the `HandOff`/`Submit` seam of `Web.Api` that `Web.McpSettings` uses (no secret: `HandOff(command, , .result, 1)`). `Context` sets `SessionRef` from `Ownership.SessionRef`; the route sets `ActingUser` `$USERNAME`. The REST process writes nothing. The GET reads sources only inside `ListMcpServers` (SettingsOps' job), and the DELETE's owner check reads only `Ownership.Checks(sessionRef)`.
- **The route checks, before any submit:**
  - the body has exactly `{server, tool, name, arguments, intervalMinutes}`: four strings and one whole number;
  - neither `name` nor `arguments` holds `@{`;
  - `arguments` is `""` or the text of a JSON object.

  McpOps (22.5) judges the rest: Read-only, the name, the interval, the size and `secret://`. Its messages are relayed unchanged.
- **Sources belong to the session that set them (AD-4, AD-18).** The GET lists only the caller's own. A DELETE whose Ref is not a `source` row of the caller's session gets 404, and nothing is submitted.
- **Online demo:** both new routes answer 409 `not_available` with 21.4's T1, before the body is read. The section shows T1 in place of its content. No source can be saved, and none is polled.
- **Initial bundle (DW-1282, standing rule: new web code goes into lazy chunks; the initial bundle is 998.08 kB of its 1 MB cap):** every new web line goes into the lazy MCP chunk (`mcp-section.ts`, `mcp-view.ts`, loaded by `settings-page.ts` :278-279), except two pieces that cannot live there: `ApiClient`'s two one-line methods (DW-231: `inject(HttpClient)` only in `api-client.ts`, pinned by `api-client-sources.test.mjs`) and the rail's source line with `intervalText` (V7; `rail-view.ts` is in the initial bundle). Types in `api-types.ts` are erased (0 bytes). `npm run build` must show the initial bundle at most 0.7 kB above 998.08 kB and under the cap; anything more stops the story and goes to the Planner (veto item V8).
- Only accepted or listed text ships (Public text). Every test added or changed creates and removes its own `zz` servers, tool rows, source rows and sessions' fixtures, and passes on a fresh environment, in either order.

**Never:**
- The approval-request ACs (epics ACs 2-4; Story 21.10).
- Any Lane A edit: `Mcp/**`, `Watch/**`, `Checks/**`, `Data/BackgroundCheck.cls`, `Live/Payload/Check.cls`, the bridge (`StepBuffer.cls` included).
- A hand edit of the generated `web/src/app/live/payloads.ts` (regenerate it: `npm --prefix web run payloads`).
- A second writer of a source row.
- A new command, grant, role, privilege, table or column.
- Showing a source's arguments in any GET or list.
- An edit control (saving the same name again updates; 22.5's natural key).
- A More to try item.
- A real MCP server or credential.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Set | README admin, POST `/v1/settings/mcp/sources` `{"server":"zzS","tool":"zz_lookup","name":"Jira","arguments":"{\"q\":\"mine\"}","intervalMinutes":15}`; `zz_lookup` is Read-only | One `SetSourcePoll` with exactly those values, `ActingUser`, the caller's `SessionRef` and origin `web_admin`. 200 `{"result":"saved","message":<McpOps' message>,"ref":<Ref>}`. GET `sources` lists `{ref,name:"Jira",server:"zzS",tool:"zz_lookup",intervalMinutes:15}` | -- |
| Update | The same name again, with new arguments or interval | 200 `saved`, the same Ref. GET shows the new interval | -- |
| Route refusal | An extra or missing member, or a wrong type; `@{` in name or arguments; arguments `[1]`, `"x"` or `not json` | 400 `bad_source` with `MESSAGEBADSETTINGS`. A shape error has `fields` {} (as 21.4's `BadServer({})`); `@{` gives `fields` {member: `settings.refusedExpansion`}; arguments not a JSON object give `{arguments: settings.sourceBadArguments}` | Nothing submitted |
| McpOps refusal | A risky, unclassified or unknown tool; an unknown server; a blank name or one over 100 characters; an interval outside 5-1,440; arguments over 4,000 characters or holding `secret://` | `not_read_only` -> 400 `bad_source` `{tool}`. `bad_name` -> `{name}`. `bad_interval` -> `{intervalMinutes}`. `bad_arguments` -> `{arguments}`. Each carries McpOps' message. `not_found` -> 404 `not_found` with `MESSAGENOTFOUND` (21.4's mapping) | No row |
| McpOps failure | `failed`, `not_audited`, `not_allowed` or any other word | 500 `server_error` | The page shows `MESSAGESERVERERROR` |
| Remove | DELETE `/v1/settings/mcp/sources/<own Ref>` | One `RemoveSourcePoll` (`SourceRef`, `ActingUser`, `SessionRef`). 200 `{"result":"removed","message":<McpOps' message>}`. GET lists it no more | McpOps `not_found`: 404 |
| Not yours | DELETE of another session's `source` Ref, a non-source check's Ref, or an unknown Ref | 404 `not_found`; nothing submitted; the row stays | -- |
| List | The caller's session holds a `source` row and a `production` row; another session holds a `source` row | `sources` holds only the caller's `source` row, sorted by name, with no `arguments` member | -- |
| Rail | A `check` payload of kind `source` with `intervalMinutes` 15, 360 or 1440 | The row's detail reads "Polled every 15 minutes", "Polled every 6 hours", "Polled every 1 day" | No `intervalMinutes`: no detail line |
| Not an admin | LIVE `OcuTalonUser`, either route | 403 `not_admin`; nothing submitted | -- |
| Online demo | `onlineDemo` 1, either route, any body | 409 `not_available` + T1, before the body is read | Nothing submitted |

</intent-contract>

## Code Map

**Built by Story 21.4 (done, LOCAL READY on this branch at `598919da`; 21.5 extends each, Rule 2):**
- `src/ocutalon/cls/OcuTalon/Web/McpSettings.cls` (198 lines):
  - class doc :1-18; UrlMap :33-41 (four routes: `List`, `Add`, `Remove` `/servers/:server`, `Classify`); `OnlineDemo` :44-47;
  - `Refusal` :50-55: 403 `not_admin` first, then 409 with `SettingsOps.WebhookFieldText("settings.mcpOffOnDemo")`, before any body read;
  - `List` :58-68 calls `Context` :64, so `ListMcpServers` already carries the caller's `SessionRef` (the old Task 0 (c) question is settled);
  - `Remove` :93-105 (the `:server` route argument pattern); `Classify` :108-126 (a body checked with `SettingsBody` and `%GetTypeOf`, then submit);
  - `Context` :129-133 sets `command.SessionRef = Ownership.SessionRef(.sc)`;
  - `AddFields` :138-162 renders `@{` as `WebhookFieldText("settings.refusedExpansion", "@{")` :142;
  - `Answer(result, kind)` :167-190, the one table of words. `saved` gives `{"result","message"}` with no `ref` :176-179. `bad_name`, `bad_address` and `exists` go to `BadServer` (400 `bad_mcp_server`) for EVERY kind :181-185, so 21.5's `set` branch must come before it. `not_found` -> 404 `MESSAGENOTFOUND` :187; `not_available` -> 409 :188; anything else 500 :189;
  - `BadServer(fields)` :193-196 (400, `MESSAGEBADSETTINGS`, `{"fields"}`).
- `Web/Api.cls`: the forward `<Map Prefix="/v1/settings/mcp" Forward="OcuTalon.Web.McpSettings"/>` :301; the class doc's MCP bullet :114-116; `HandOff` :1147-1162 (with `optional` 1 and no secret it only calls `Submit`); `Submit` :1166-1169 (`Commands.Submit(command, "web_admin")`, the test seam).
- `Core/SettingsOps.cls`: dispatch :189; `ListMcp` :2347-2377 (demo check :2349; the answer `{"servers","tools"}` :2376; a failed read answers `failed` :2375); `WebhookFieldText` :2382-2387.
- `Msg/Command/ListMcpServers.cls` :1-22 (only `ActingUser`; `SessionRef` comes from the base `Msg/Command.cls` :15).
- Tests:
  - `Test/Web/McpSettingsProbe.cls` :1-45. `Submit` :28-43 counts submits and records only an `AddMcpServer`'s handoff uri; it does NOT record the command's fields. Mode `outcome:<word>` answers `Ok` 0 with that word, so it cannot fake a 200 `saved`.
  - `Test/Web/McpSettingsApi.cls` (runs the real production, real McpOps and SettingsOps; Rule 21, throwaways and CI only): fixtures :51-92; `TestNotAdmin` :365; `TestOnlineDemo` :391-417 (loops the four routes); `TestFailedAnswers` :438-462 (loops the four routes over `outcome:` words); `TestNotAdminComesFirst` :532; helpers `Call` :698-717 (passes the route argument only for `"Remove"`), `PreDispatch` :719, `Clean` :764, `Leftovers` :779.
  - `Test/Core/SettingsMcp.cls` (a shadow `SettingsOpsProbe`, safe on a slot): `TestList` :50-84; `List()` :180-191 sets NO `SessionRef`; `Clean` :205, `Leftovers` :221.
- Web (the lazy chunk: `settings-page.ts` :90-91, :236, :278-279 `import('./mcp-section')`):
  - `web/src/app/settings/mcp-view.ts` (framework-free, types-only imports): `MCP_TEXTS` :26-69 (already has `removeButton` "Remove", `cancel` "Cancel", `saved` "Saved", `toolColumns.tool` "Tool"); `fieldText` :134-140 (keys `name`/`address`/`secret`); `mcpOutcome` :143-160 (`denied`, `off`, `fields` for `bad_mcp_server`, `form`); `withClassification` :163-167 returns `{servers, tools}` only, so it would DROP `sources`.
  - `web/src/app/settings/mcp-section.ts` (643 lines): `NONE` :39 `{servers:[], tools:[]}`; the states :60-75 (`off`, `failed`, `denied`, `ready`); the tools table :186-228 (four columns, a `radiogroup` per row); `state` :385, `settings` :386; `load` :421-440, `reload` :443-457; `pick` :571-600 (updates `settings` at once through `withClassification`); `messageOf` :607-610, `stateOf` :612-618, `refusedAdd` :620-637 (the field-error pattern: set, announce, focus the first); `moveFocusTo` :640-642.
  - `web/src/app/api/api-client.ts` `mcpSettings` :98-100, `addMcpServer` :106-108, `removeMcpServer` :111-113 (`{ body: {} }`), `classifyMcpTool` :116-118; `api-types.ts` `McpSettings` :367-370, `McpChanged` :373-376, `McpError` :379-382.
  - `web/e2e/api/mcp.spec.ts`: M1 :90 (LIVE 403 on the four routes), M2-M4/M6 :117, M5 :208; helpers `admin` :43, `list` :49, `cleanup` :56, `startMock` :70.
  - `web/e2e/settings/mcp.spec.ts`: B1-B10 (:53-364; B5 :205 is the 409 view). `web/e2e/support/mcp.ts`: `seedMcpServer(name, tools, pending)` :18 (fixture `Mcp.Server` and `ToolClassification` rows with a classification), `dropMcpServer` :39, `leftovers` :64.
  - `web/scripts/mcp-view.test.mjs` (`catalogText(key)` :20 reads the Core catalog); `web/scripts/ux-strings.test.mjs` registers `settings/mcp-view.ts` `MCP_TEXTS` :70 and `rail/rail-view.ts` `RAIL_TEXTS` :45, 21.4's entries :257-; `web/scripts/announce-focus-sources.test.mjs` :172 counts two `.focus(` calls in `mcp-section.ts` (both through `moveFocusTo` or the heading).
- 21.4's T1 (`settings.mcpOffOnDemo`, `Msg/Catalog/Core.cls` :736) is the demo line. Its T9 is `GUIDE.md` :16.

**Built by Story 22.5 (Lane A, ready-for-dev, not merged; read only):**
- `Mcp/Ops.cls` `OnSetSource`/`OnRemoveSource`:
  - outcomes `saved` (with `Ref`), `removed`, `not_read_only`, `not_found`, `bad_name`, `bad_arguments`, `bad_interval`, `not_allowed` and `not_audited`;
  - the `MESSAGE*` texts at 22.5's gate.
- `Data/BackgroundCheck.cls`: `Server`, `Tool`, `Arguments` and `IntervalMinutes` (storage 16-19), Kind `source`, owned by the command's `SessionRef`.
- `Live/Payload/Check.cls` `IntervalMinutes` (`intervalMinutes`) on the `check` event and `/v1/state`.

**Existing (verified on this branch, HEAD `598919da`):**
- `Msg/Command/SetSourcePoll.cls` :6-21 (`Server` 40, `Tool` 128, `Name` 100, `Arguments`, `IntervalMinutes`, `ActingUser`). `RemoveSourcePoll.cls` :6-9 (`SourceRef` 22, `ActingUser`). `Msg/Command.cls`: `Origin` :9, `SessionRef` :15. `Msg/CommandResult.cls`: `Ok` :6, `Message` :9, `Outcome` :12, `Ref` :15, `Data` :21.
- `Core/CommandsIn.cls`:
  - routes :362-363 (both to McpOps, `web_admin` only);
  - origin refusals :110-113;
  - the send and answer :132-139. Until 22.5, McpOps has no `MapItem` for them (`Mcp/Ops.cls` :3, `MessageMap` :73-86), so the answer is `failed` (DW-1137, by-design until 22.5).
- `Web/Api.cls`: `OnPreDispatch` :318-340 and `IsSettingsUrl` :359-363 (gates `/v1/settings/mcp/...`); `SettingsBody` :1131-1142; `MESSAGENOTFOUND` :179, `MESSAGESERVERERROR` :189, `MESSAGENOTADMIN` :194, `MESSAGEBADSETTINGS` :197; `ServerError` :394; `Fail` :1543; `RailBody` :1450-1466 (`Ownership.Checks` + `Live.Payload.Check.FromRow`). `Web/BodyLimit.cls` `MAXBYTES` 256 KB :26 (no `BodyBounds` needed).
- `Web/HookSettings.cls` :93-96: the owner check -> 404 (the sibling for the DELETE's check).
- `Data/Ownership.cls`: `Checks(sessionRef, *sc)` :439-442, owner-filtered, in the REST process and in jobs (`Rows` :1155; the statement :1238-1241 filters by `SessionRef` only, ordered by ID: the Kind filter is the caller's). `SessionRef` :297. `Data/Session.cls` :1-2: one durable session per IRIS user on a local install.
- `Data/BackgroundCheck.cls` (Lane A, read only): `Ref` :11, `SessionRef` :14, `Kind` :17, `DisplayName` :26.
- `Mcp/Ops.cls` (read only): `MESSAGESAVED` "Saved" :65, `MESSAGENOSERVER` :59, `MESSAGENOTOOL` :61.
- `Msg/Catalog/Core.cls`: `settings.mcpOffOnDemo` :736, `settings.refusedExpansion` :761 and `settings.sourceHeading`/`Help`/`Name`/`Arguments`/`Interval`/`NotReadOnly`/`BadArguments` :776-810 (accepted; EXPERIENCE.md :1010-1016).
- `Test/Data/Fixture.cls` `Session(user)` :22.
- Web:
  - `web/src/app/settings/settings-view.ts` `SETTINGS_TEXTS.save` "Save changes" :43;
  - `webhooks-section.ts` `moveFocusTo` :410-412, the field-error sibling;
  - the rail (initial bundle): `web/src/app/rail/rail-view.ts` (framework-free) `RAIL_TEXTS.checkSchedule` :55 and `checkScheduleQueues` :56, `checkTitle` :212-215, `checkRow` :244-264 (the kind branches :259-263); `web/src/app/live/payloads.ts` (GENERATED by `web/scripts/payloads.mjs`; `payloads.test.mjs` checks the real tree) `CheckPayload` :345-359, no `intervalMinutes` yet; `web/scripts/rail-view.test.mjs` fixed strings :89-125, background checks :384-; `web/e2e/rail/rail.spec.ts` R5 :218 (a check's schedule).
- Docs: `GUIDE.md` "New since 1.0.0" :3, "#### Your integrations" :7, 21.4's MCP servers bullet :16. `README.md` :62-64 now only links there. EXPERIENCE.md "Settings and requests (step 4)" :973 (21.4's rows end :1033) and the rail's "Background check row" :276.
- Spine (`ARCHITECTURE-SPINE.md`): the REST row for the source routes :1784; the GET row :1781.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement, before code; source reads only; results go under Design Notes "Read at implement"):
  - (a) Confirm 22.5 is merged into this branch (21.4 is: `598919da`). If 22.5 is missing, stop with `## Clarification Needed` (C1).
  - (b) From the merged `Mcp/Ops.cls`, record the exact outcome words, the `Ref` on `saved`, and the `MESSAGE*` names. From the merged `Data/BackgroundCheck.cls`, record the column names. Adjust the Matrix mapping only where a name differs. Also record: whether `web/src/app/live/payloads.ts` has `intervalMinutes` (if not, regenerate it); the signature of `Checks.Coverage.Build`; whether a 22.5 test saves a source through the verb and finds it in the coverage list (T7 condition (a)); whether 22.11 (the run) is merged and pins the unchanged-result skip (T7 condition (b)).
  - (c) Run `npm run build` once before any web edit and record the initial bundle (expected 998.08 kB).
- [ ] `src/ocutalon/cls/OcuTalon/Web/McpSettings.cls`:
  - UrlMap :33-41 gains `/sources` POST `SetSource` and `/sources/:ref` DELETE `RemoveSource`.
  - `SetSource` follows the Always order: `Refusal`, `SettingsBody` and the shape (as `Classify` :112), `@{` (`WebhookFieldText("settings.refusedExpansion", "@{")`, as `AddFields` :142), the arguments (a private `%FromJSON` check, `""` allowed), then `Context` and `HandOff(command, , .result, 1)`.
  - `RemoveSource(ref)`: `Refusal`, then the Ref must be a `source` row in `Ownership.Checks(Ownership.SessionRef())` (else 404 `MESSAGENOTFOUND`, as `HookSettings` :96), then `Context` and submit.
  - `Answer` :167-190 gains kinds `set` and `removeSource` in the same table: `saved` for `set` adds `ref` (`result.Ref`); for `set`, `not_read_only`/`bad_name`/`bad_interval`/`bad_arguments` go to a `BadSource(fields)` sibling of `BadServer` :193 (400 `bad_source`, `MESSAGEBADSETTINGS`, `{"fields"}` with McpOps' message), placed BEFORE the `bad_name` -> `BadServer` branch :181. Do not copy the table.
  - Update the class doc :1-18 and `Web/Api.cls`' MCP bullet :114-116.
- [ ] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `ListMcp` :2347-2377: the answer :2376 gains `sources`. It reads `Ownership.Checks(command.SessionRef)` inside the existing Try, keeps Kind `source`, and maps each row to `{ref, name: DisplayName, server, tool, intervalMinutes}`, sorted by name. A failed read answers `failed`, as :2375 does. Update the doc :2341-2346 and the class doc :94-95.
- [ ] `web/src/app/api/api-types.ts` -- `McpSourceRow`; `McpSettings.sources` :367-370; `McpChanged` :373 gains optional `ref`; `McpError.fields` :381 gains `tool`, `name`, `arguments`, `intervalMinutes`. `api-client.ts` -- `setMcpSource(body)` and `removeMcpSource(ref)` beside `classifyMcpTool` :116, as one-line siblings of `addMcpServer`/`removeMcpServer` (the only initial-bundle client code; Boundaries).
- [ ] `web/src/app/rail/rail-view.ts` (initial bundle; V7):
  - `RAIL_TEXTS` gains `checkScheduleSource: 'Polled every {duration}'` beside `checkScheduleQueues` :56, and the T4 duration words;
  - export `intervalText(n)` (T4: the six choices' words; any other value "{n} minutes", or "{h} hours" for a whole number of hours);
  - `checkRow` :259-263 gains a `source` branch: `fill(RAIL_TEXTS.checkScheduleSource, { duration: intervalText(n) })` when `intervalMinutes` is a number, no detail otherwise. Update the doc.
- [ ] `web/src/app/live/payloads.ts` -- regenerated (`npm --prefix web run payloads`) only if 22.5's merge left it without `intervalMinutes` (Task 0 (b)).
- [ ] `web/src/app/settings/mcp-view.ts` (lazy) -- extend `MCP_TEXTS` with T1-T6 and the `settings.source*` texts (Public text), and add:
  - `INTERVAL_CHOICES` (5, 15, 30, 60, 360, 1440; default 15), labelled by `intervalText` imported from `../rail/rail-view` (one definition; the rail is already in the initial bundle, so the chunk adds nothing);
  - `canBeSource(tool)` (`read-only` and status not `refused`);
  - `sourceBody(...)`, `toolText(tool, server)` (T3), `sourceName(tool, server)` (T5), `removeSourceName(source)` (T6);
  - `sourceOutcome(status, body)`: a `bad_source` with fields gives `{kind: 'fields', tool, name, arguments, intervalMinutes}`; everything else is `mcpOutcome` :143 (widen `fieldText` :134's keys, do not copy it);
  - `withClassification` :163-167 keeps `sources` (`{...settings, servers, tools}`).
  - Update the doc :1-15 (one value import now).
- [ ] `web/src/app/settings/mcp-section.ts` (lazy):
  - `NONE` :39 gains `sources: []`.
  - **Tools table** :186-228 gains a "Source" column:
    - a Read-only tool gets the "Use as a source" button (accessible name T5);
    - any other non-refused tool gets the button with `aria-disabled="true"`, `settings.sourceNotReadOnly` beside it, linked by `aria-describedby`; a press does nothing;
    - a refused tool gets no control.
    - A classification change updates the control at once (it reads `tool.classification`, which `pick` :571 updates).
  - **The form.** The button opens a form panel below the table: heading `settings.sourceHeading`, the line T3, help `settings.sourceHelp`, then Source name (maxlength 100), Arguments (JSON) (a textarea) and Check every (a select of `INTERVAL_CHOICES`), with Save changes (`SETTINGS_TEXTS.save`) and Cancel (`MCP_TEXTS.cancel`).
    - Focus starts on Source name.
    - Field errors appear under their fields, and focus moves to the first one (a `refusedSource` built like `refusedAdd` :620-637). A `tool` error and a 500 are form-level (`messageOf` :607).
    - On success, McpOps' message ("Saved") is announced, the panel closes, focus returns to the row's button, and the list reloads (`reload` :443).
    - Every focus move goes through `moveFocusTo` :640, so `announce-focus-sources.test.mjs` :172 keeps its count; extend its reason text (or its count, if a call is added).
  - **"Your sources" group (T1-T3).** A table with Source, Tool and Check every, plus a Remove button per row (accessible name T6, no dialog). A success announces McpOps' message and reloads; a failure shows `MESSAGESERVERERROR`.
  - A 409 shows T1, and a 403 the denied state (`stateOf` :612, 21.4's states).
- [ ] **Tests (ObjectScript):**
  - `Test/Web/McpSettingsProbe.cls` -- `Submit` :28-43 also records the submitted command's class and every field (`^OcuTalonTest("McpSettingsProbe", "command")`, as JSON; never a secret), and mode `outcome:<word>` answers `Ok` 1 with Ref "zzref" for `saved` and `removed`. This is the AC's McpOps test double. Update its doc.
  - `Test/Web/McpSettingsApi.cls` -- `Call` :698 passes the route argument for `RemoveSource` too. Every Matrix route row:
    - the recorded command's every field;
    - nothing submitted on each route refusal, on a 404 or on the demo;
    - the 409 comes before the body (`TestOnlineDemo` :391's route loop gains both routes); the 403 (`TestNotAdmin` :365, `TestNotAdminComesFirst` :532);
    - each outcome word maps to its HTTP answer (`TestFailedAnswers` :438's loop gains both routes, plus the `set` field words);
    - the real `saved`/`removed` through the real McpOps (22.5), with `Clean`/`Leftovers` :764-795 extended to `source` rows;
    - T7 condition (a), only if Task 0 (b) finds no 22.5 test for it: `TestSavedSourceInCoverage` -- a source saved through the route is an entry of `Checks.Coverage.Build` for the session (read only).
  - `Test/Core/SettingsMcp.cls` -- `List()` :180 sets a fixture session's `SessionRef`; a new `TestListSources`: own `source` rows only, sorted, no `arguments`; other kinds and other sessions left out. It uses fixture `BackgroundCheck` rows and removes them (`Clean`/`Leftovers`).
- [ ] **Tests (web):**
  - `web/scripts/mcp-view.test.mjs` -- `INTERVAL_CHOICES`, `canBeSource` for each classification and status, `sourceBody`, `sourceOutcome`, T3/T5/T6, `withClassification` keeping `sources`, and the `settings.source*` constants equal to `catalogText(key)`.
  - `web/scripts/rail-view.test.mjs` -- the fixed strings :89-125 gain the new entries; background checks :384 gains the `source` row (15, 360, 1440 and none) and `intervalText` (each choice; 120 gives "2 hours"; 45 gives "45 minutes"). Mutation: no `source` branch -> red.
  - `web/scripts/ux-strings.test.mjs` -- the new entries; `api-client-sources.test.mjs` -- the two methods' verbs, addresses and bodies.
  - `web/e2e/api/mcp.spec.ts` (real HTTP):
    - **M1** :90 extended: the LIVE user gets 403 on both new routes too.
    - **M7:** the README admin seeds `zz<run>` with `zz_lookup` Read-only and `zz_delete` Risky (`seedMcpServer`). Then:
      - POST returns 200 `saved` with a Ref;
      - GET lists the source;
      - an `irisScript` fixture `source` row of another session is not listed, and its DELETE gets 404 and the row stays;
      - the admin's DELETE returns 200, and GET no longer lists it.
    - **M8:** the risky tool gives 400 `{tool}`; `"arguments":"x"` gives 400 `{arguments}` with `settings.sourceBadArguments`; `@{` gives `settings.refusedExpansion`. Each time GET lists nothing new.
    - `support/mcp.ts` `dropMcpServer` :39 and `leftovers` :64 also cover the server's `source` rows.
  - `web/e2e/settings/mcp.spec.ts` (browser):
    - **B11:** with a fixture server with a Read-only and a Risky tool, the Read-only row's control opens the form and the Risky row's is `aria-disabled` with the reason beside it. Saving shows "Saved" and a "Your sources" row "Jira | zz_lookup on zzS | 15 minutes". Remove takes the row off.
    - **B12:** arguments `[1]` shows `settings.sourceBadArguments` under Arguments (JSON), with focus moved there.
  - `web/e2e/rail/rail.spec.ts` -- R5 :218 gains a `source` check row: "Polled every 15 minutes".
- [ ] **Docs and spine** (ruled; marker `[ADDED 2026-MM-DD, Story 21.5, Contest Planner ruling D]` with the day the lead writes it):
  - T1-T6 and the rail line go into EXPERIENCE "Settings and requests (step 4)" (after :1033) and the "Background check row" :276.
  - S1 and S2 of Design Notes.
  - T7 goes into `GUIDE.md` "#### Your integrations", after :16, only when 22.11 (the run) is merged, with its two conditions applied (Design Notes, Decided 12). Otherwise the lead files it on 22.11/22.12 and 21.5 ships without it.

**Acceptance Criteria:**
- Given a Read-only tool in Settings > Tools and MCP servers, when an admin presses "Use as a source", enters a name, arguments and an interval, and saves, then the form uses the accepted `settings.source*` wording and the route submits `SetSourcePoll` to `McpOps` (origin `web_admin`, the admin's `SessionRef`, exactly the entered values). "Saved" shows, and the source is listed under "Your sources" with its tool and interval (B11, M7, `McpSettingsApi`).
- Given a tool that isn't Read-only, when the tools table shows it, then its source control can't be chosen and "Only a Read-only tool can be a source." shows beside it; a crafted POST for it gets 400 with McpOps' `not_read_only` message, and no row is created (B11, M8).
- Given arguments that are not a JSON object, or `@{` in the name or the arguments, when the admin saves, then the field error (`settings.sourceBadArguments` or `settings.refusedExpansion`) shows under its field and takes focus, and nothing is submitted (B12, M8, `McpSettingsApi`).
- Given the admin's own source, when they press Remove, then `RemoveSourcePoll` is submitted and the source leaves the list. A source of another session is never listed, and its DELETE gets 404 with nothing submitted (M7, `McpSettingsApi`, `SettingsMcp`).
- Given the route tests, when they run, then a `McpOps` test double (the route probe's submit seam) records every submitted source command, and the real-HTTP tests (M1, M7, M8) reach the real `McpOps` of Story 22.5 (epics AC 1's test-double clause, Rule 2).
- Given the online demo, when anyone calls either route or opens the section, then 409 `not_available` with T1 comes before the body is read, the section shows T1 in place of its content, and nothing is submitted (`McpSettingsApi`; 21.4's B5).
- Given a `source` check row whose payload carries `intervalMinutes`, when the rail shows it, then its detail line reads "Polled every {duration}" in T4's duration words (for example "Polled every 15 minutes", "Polled every 6 hours", "Polled every 1 day"), like the production and queue schedule lines; with no `intervalMinutes` there is no line (`rail-view.test.mjs`, R5; ruling C/D, V7).

## Spec Change Log

- 2026-11-14 (lead): 22.5 is now merged (feature 23fafe59b), so Task 0 (a)'s wait is met. Veto V8 is APPROVED by the Planner (~02:00Z Nov 14): the 0.5 kB (ApiClient methods and the rail line) goes in the initial bundle; 21.5 merges only once 36.5 is on feature (it is) and must pass the budget (`web/scripts/initial-bundle.test.mjs`, 921 kB cap). The implement stage re-reads 22.5's merged McpOps handlers, columns and MESSAGE texts first and records them under Design Notes. A material difference from the contract planned here is a STOP.

- 2026-11-12 (lead, spec gate): split ruled (21.10); 22.5 item 9 routed here by the Planner, so the rail line is in scope.
- 2026-11-14 (planner, refresh after 21.4 (LOCAL READY on OCT-epic21); 22.5 still unmerged): every Code Map and Task reference re-verified at `598919da`, and each "21.4 will..." assumption replaced by 21.4's committed code. Findings that changed the plan: `List` already sets `SessionRef` (Task 0 (c) dropped); `Answer` maps `bad_name` to `bad_mcp_server` for every kind, and `saved` carries no `ref`; the probe records no command fields and its `outcome:` mode is `Ok` 0; `withClassification` drops extra members; `SettingsMcp.List()` sets no `SessionRef`; 21.4 used B1-B10 and M1-M6, so the cases are now M1 (extended), M7, M8, B11, B12 and R5 (extended); `payloads.ts` is generated; T7 goes to GUIDE.md :16. Ruling D applied: the rail line is IN SCOPE as "Polled every {duration}" (task, AC, Matrix row), V7 approved, T7's two conditions and its 22.11 timing. Added: the initial-bundle Boundaries line (DW-1282) and V8; the contended files (Rule 11); "Read at refresh". The 21.10 evidence moved to 21.10's own spec. No public text added.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-1: commands from `web_admin`; the REST process writes nothing.
- AD-4: session ownership.
- AD-12: the rail renders the live payload.
- AD-13: admin-checked `/v1/settings` routes and the envelope.
- AD-18: the source row type; `McpOps` creates rows through `Watch.Ops`; Lane B only reads.
- AD-19: `@{` refused; no secret in the arguments.
- AD-21: the verbs; source polls run through a `tool` request.
- AD-25: the online demo: off.
- AD-29 and AD-33: lanes; one creator of a source row.

No AC contradicts an AD's Rule. The approval ADs (AD-10, AD-11, AD-16, AD-31, AD-32) govern Story 21.10.

**Split (ruled, V5):** 21.5 keeps epics AC 1 (the source-poll form and its routes, with the test-double clause) and the rail line; epics ACs 2-4 are Story 21.10 (`spec-21-10-*.md`, which holds the evidence this spec used to list).

**Order and dependencies (said plainly):**
- **From 21.4 (in, `598919da`):** every piece 21.5 extends (Code Map).
- **From 22.5 (Lane A, not merged):** the `McpOps` handlers and their outcomes, the `BackgroundCheck` source columns, the `MESSAGE*` texts and the payload's `intervalMinutes`. 21.5 implements only after 22.5 merges into this branch (V6; Task 0 (a)).
- **From 22.11 (Lane A, ruled at gate C, Part B of 22.5):** only T7's timing and wording (Decided 12). Nothing in 21.5's code waits on it.

**Decided in-stage (reversible inside this story):**
1. **The list shows the caller's own sources only.** A session is one IRIS user on a local install (`Data/Session.cls` :1). The list is read through the existing `Ownership.Checks` in SettingsOps' job; there is no new Ownership method.
2. **The DELETE route removes only the caller's own source (404 otherwise).** This is narrower than 22.5's "any admin may remove any source", which still holds for McpOps (V3).
3. **One judge.** The route checks only shape, `@{` and that the arguments are a JSON object (accepted texts); McpOps judges the rest, and its messages are relayed.
4. **Check every** is a select of six choices, with 15 minutes as the default, so a bad interval can come only from a crafted request.
5. **A refused tool gets no source control.** Its status already says why.
6. **No edit control and no arguments in the GET.** Saving the same name updates the source (22.5's natural key).
7. **Removing a source asks nothing.** It is undone by setting it again, and nothing pending is lost.
8. **The isolation case uses a fixture `source` row of another session**, made and removed with `irisScript`. No second admin user is needed (standing rule (iii)).
9. **"Use as a source"** (the accepted heading text) is also the button text. Save reuses `SETTINGS_TEXTS.save`; Cancel and Remove reuse `MCP_TEXTS.cancel`/`removeButton`.
10. **(refresh) A shape error has `fields` {}** and a `not_found` from McpOps is 404 with `MESSAGENOTFOUND`, as 21.4's `Answer` already does; one table, no second mapping.
11. **(refresh) The real-HTTP and browser cases seed fixture server and tool rows (`seedMcpServer`)** instead of attaching the mock: 22.5 validates against the rows only, and no outward call is needed. Each case removes its source rows in `finally`.
12. **(refresh) T7's timing and conditions.** T7 claims that OcuTalon calls the tool on its schedule, which is 22.11's run. So T7 lands only if 22.11 is merged at 21.5's docs step. Then (a) "and the source joins the digest's coverage list" stays only if a 22.5 test or 21.5's `TestSavedSourceInCoverage` proves it; else the sentence ends "...makes an attention decision on each new result." (b) "each new result" stays only if 22.11 skips an unchanged result (its `seen` check, `TestSeenBefore`); else "on each result".
13. **(refresh) `intervalText` lives in `rail-view.ts`.** The rail needs the words in the initial bundle; `mcp-view.ts` imports it, so it is defined once and the chunk adds nothing.
14. **(refresh) The e2e names follow 21.4's series** (M7, M8, B11, B12; M1 and R5 extended), so the spine items S1 and S2 keep their names.

**Clarifications for the lead (non-blocking; the plan runs on the stated default):**
- **C1 (order; ruled V6):** 21.5 implements only after 21.4 AND 22.5 have merged into this branch. 21.4 is in; Task 0 (a) stops the implement stage until 22.5 is.
- **C2:** the route relays McpOps' (22.5) source messages verbatim. Their wording is decided at 22.5's gate, and a change there needs no 21.5 change.
- **C3 (observation):** the accepted `settings.sourceHelp` (EXPERIENCE :1011) says "OcuTalon calls this tool on a schedule and decides on each new result. The source joins your digest's coverage list." The form shows it as accepted. If 21.5 ships in a release without 22.11, that line is ahead of the code, as T7 would be. Default: no change here; the release check covers it (22.12 depends on 22.5, 22.11 and 21.5 in the same release).

**Read at refresh (22.5 planned, not merged; its spec in Lane D's tree, read only):**
- Outcomes: `saved` (Ok, `MESSAGESAVED`, `Ref` set), `removed`, `not_read_only`, `not_found` (unknown server or tool: `MESSAGENOSERVER`/`MESSAGENOTOOL`; a Ref that is no `source` row: `MESSAGENOSOURCE`), `bad_name`, `bad_arguments`, `bad_interval`, `not_allowed` (origin, tool, context and the online demo), `not_audited`. Same words as this spec.
- New messages: `MESSAGENOTREADONLY`, `MESSAGESOURCENAME`, `MESSAGESOURCEARGUMENTS`, `MESSAGESOURCEINTERVAL`, `MESSAGENOSOURCE`, `MESSAGESOURCEREMOVED` (approved at gate C). `MESSAGENOTREADONLY` reads "Only a Read-only tool can be a source. Nothing was changed.", the catalog's `settings.sourceNotReadOnly` plus "Nothing was changed."; the route relays it and the page shows the catalog text beside the control. No conflict.
- Columns: `Server` (40), `Tool` (128), `Arguments` (canonical JSON; empty means `{}`), `IntervalMinutes`, storage 16-19; the natural key (SessionRef, `source`, DisplayName). Same as this spec. Limits: name 1-100, interval 5-1,440, arguments at most 4,000, no `secret://` or `@{` (`NAMEMAX`, `INTERVALMIN`, `INTERVALMAX`, `ARGUMENTSMAX`).
- Drift:
  - 22.5's Public text still lists the rail's `checkScheduleSource` as "Polled every {n} minutes"; ruling D replaced it with "Polled every {duration}", owned by 21.5. 22.5 ships no web text, so nothing collides.
  - The split (22.5 Part A + 22.11 Part B) is ruled at gate C, but 22.5's spec and Lane D's `epics.md` do not yet record 22.11 (Story 22.12 already depends on it). 21.5 needs only Part A.
  - 22.5 cites `CommandsIn` L359-360 and `Mcp/Ops.cls` `MessageMap` L60-72; on this branch they are :362-363 and :73-86 (21.4 changed both). Lane D re-reads them when it integrates forward.
  - 22.5 adds `IntervalMinutes` to `Live/Payload/Check.cls`, but `web/**` is outside its lane, so the generated `payloads.ts` may be stale after its merge (`payloads.test.mjs` checks the real tree). Task 0 (b) covers it.
  - 22.5 removes a server's sources with the server (`RemoveMcpServer`); the section's reload after a server Remove shows that with no 21.5 change.

**Ledger:**
- Inbox: none.
- Cited: DW-1137 (by-design until 22.5; this story's UI is the first sender, hence C1); DW-1045 (`wontfix-accepted`, `reopen_if` a step 4 text is edited without the other). 21.5 edits neither `Catalog.Core` nor any existing EXPERIENCE row; its new texts are page constants with new rows. So DW-1045 does not reopen. DW-1282 (the initial bundle; Boundaries, V8). DW-231 (one API client).

**Integration ACs (Rule 1):** the settings page (`mcp-section.ts`) reads `sources` from the GET and posts to the two routes. These submit to the real `McpOps` (22.5), whose row then appears in the GET (M7, B11), and is removed by the DELETE (M7). The rail renders the real payload's `intervalMinutes` (R5).
**Consumes:**
- 21.4: `Web.McpSettings`, `ListMcpServers`/`ListMcp`, `mcp-section`/`mcp-view`, the API client, T1, the fixture helpers.
- 22.5: the `SetSourcePoll`/`RemoveSourcePoll` handlers, the source columns and the payload's `intervalMinutes`.
- Also: `Ownership.Checks`, `Commands.Submit`/`CommandsIn`, `Msg.Command.SetSourcePoll`/`RemoveSourcePoll`.

All are real instances in M1, M7, M8, B11, B12 and R5.
**Consumed-by:** no later story calls these routes. 22.6 (docs) describes the form, and 22.12 shows a source on the coverage list.

**Extend, don't copy (Rule 2):**
- The routes join 21.4's `Web.McpSettings` and its `Refusal`, `Context`, `HandOff`/`Submit` seam and `Answer` table.
- The DELETE's owner check follows `HookSettings` :96.
- `sources` extends 21.4's `ListMcp`, read through the existing `Ownership.Checks`.
- The form and the list extend 21.4's `mcp-section.ts`/`mcp-view.ts` (`mcpOutcome`, `fieldText`, `moveFocusTo`, `messageOf`, `stateOf`, the `refusedAdd` pattern).
- The rail line extends `checkRow`'s kind branches; `intervalText` is defined once.
- The tests extend `McpSettingsApi`/`Probe`, `SettingsMcp`, `mcp.spec.ts` (both), `support/mcp.ts`, `mcp-view.test.mjs`, `rail-view.test.mjs` and R5.

**Contended files (Rule 11; whoever lands second integrates forward and keeps both rules):**
- **Story 21.10** (`BridgeSink`, the channel cards, the catalog `toolCall.*`): 21.5 edits none of those three. Shared files:
  - `web/src/app/rail/rail-view.ts`: 21.10 adds `RAIL_TEXTS.runToolOn` and changes `approvalTitle` :186-209; 21.5 adds `checkScheduleSource` and the duration words after `checkScheduleQueues` :56, `intervalText`, and the `source` branch in `checkRow` :259-263. Adjacent `RAIL_TEXTS` entries; a plain union.
  - `web/scripts/rail-view.test.mjs`: both add to the fixed-strings `deepEqual` :89-125 (union of the entries); 21.10 in "approval requests" :248, 21.5 in "background checks" :384.
  - `web/src/app/live/payloads.ts` (generated): 21.10's `ApprovalPayload` :227 and 22.5's `CheckPayload` :345. The second lander reruns `npm --prefix web run payloads`; never a hand merge.
  - `web/e2e/rail/rail.spec.ts`: 21.10's R3 :166-175 and X14; 21.5's R5 :218.
  - `web/scripts/ux-strings.test.mjs`: both add entries.
- **Lane D, Stories 22.5, 22.6 and 22.7** (`Mcp/Ops.cls`, `StepBuffer.cls`): 21.5 edits neither (Never). It depends on these `Mcp/Ops.cls` regions: `MessageMap` :73-86 (22.5's two `MapItem`s), the `MESSAGE*` parameters :47-65 (plus 22.5's six), and the new `OnSetSource`/`OnRemoveSource`. If 22.6 or 22.7 change them after 22.5, 21.5's integrate-forward repeats Task 0 (b). `StepBuffer.cls` has no 21.5 tie. `Data/BackgroundCheck.cls` and `Live/Payload/Check.cls` are read only.
- **Story 21.9** (same lane, being planned now; the changed-tool banner): `mcp-section.ts` (its banner vs 21.5's Source column, form and group), `mcp-view.ts` `MCP_TEXTS` and `withClassification`, `SettingsOps.ListMcp` :2347-2377 (its tool member vs 21.5's `sources`), `McpSettingsApi`/`SettingsMcp`, `settings/mcp.spec.ts` and `ux-strings.test.mjs`. The Epic 21 runner orders them; the second integrates forward.

**Spine items (ruled; additive):**
- **S1, REST row :1784:** append: "POST body `{server, tool, name, arguments, intervalMinutes}`; the route refuses a shape error, `@{` and arguments that are not a JSON object, and McpOps judges the rest; DELETE removes only a `source` row of the caller's session (else 404); both 409 `not_available` on the online demo before the body [ADDED, Story 21.5]".
- **S2, the GET row :1781 (21.4's `ListMcpServers` body):** append: "the answer also lists the caller's session's source rows in `sources` (`ref`, `name`, `server`, `tool`, `intervalMinutes`; never the arguments) [ADDED, Story 21.5]".

**Rulings so far:** the split into 21.5 + 21.10 is ruled by the Epic 21 runner (decide, doctrine U5; `epics.md` written). The Contest Planner ruled 22.5's item 9 YES (`prompts/gate-rulings-20261112-1810.md` C). Ruling D (~18:40Z): the split, the cross-epic wait (21.5 implements only after 21.4 AND 22.5 merge), and V1-V6 APPROVED (V3's narrower web DELETE is right); demo: both routes 409 with 21.4's T1 before the body, real-HTTP tests. V7 APPROVED with one change: "Polled every {duration}" in T4's duration words, never "Polled every 1440 minutes"; this replaces the "{n} minutes" form approved for 22.5, and 21.5 owns it. PUBLIC TEXT: T1-T6 verbatim; T7 approved with two conditions (Decided 12); T7 goes in GUIDE.md's "New since 1.0.0"; no More to try item. Open: V8 (refresh).

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| V1 | New routes: `POST /api/v1/settings/mcp/sources` and `DELETE /api/v1/settings/mcp/sources/<ref>` (`Web.McpSettings`; admin-checked; real-HTTP tests S1-S3 with the LIVE user, the README admin and an isolation case) | approve | 409 + T1 before the body |
| V2 | The GET `/v1/settings/mcp` body gains `sources` (the caller's own; no arguments) | approve | the GET answers 409 (21.4) |
| V3 | Access rule: the web DELETE removes only the caller's own source; McpOps' any-admin rule (22.5 V5) is unchanged | approve | refused |
| V4 | Outward calls: a saved source makes Lane A's `Checks` poll the admin's MCP server at its interval (22.5's V3; this story adds the control that starts it) | approve | none (no source can be saved; 22.5 skips `source` rows) |
| V5 | Split: epics ACs 2-4 move verbatim to new Story 21.10 | approve | -- |
| V6 | Order C1: 21.5 implements after 22.5 merges (a cross-epic story wait) | approve | -- |
| V7 | The rail line in Lane B's `rail-view.ts` (22.5's veto item 9): "Polled every {duration}" | APPROVED (ruling D, with the "{duration}" change) | never shows |
| V8 | (refresh) Initial-bundle exception to DW-1282's standing rule: `ApiClient.setMcpSource`/`removeMcpSource` (DW-231's one client) and V7's rail line with `intervalText` go into the initial bundle, about 0.5 kB, capped at 0.7 kB over 998.08 kB and under 1 MB (else STOP to the Planner); every other new web line is in the lazy MCP chunk. If vetoed: the rail line waits for DW-1282's burndown, and DW-231's guard is amended to allow a client inside the lazy chunk | approve | -- |

V1's "S1-S3" are now M1, M7 and M8 (Decided 14). There is no new command, grant, role, privilege, table, column, retention or web dependency.

## Public text

**Reused (accepted):**
- `settings.sourceHeading` "Use as a source", `settings.sourceHelp`, `settings.sourceName` "Source name", `settings.sourceArguments` "Arguments (JSON)", `settings.sourceInterval` "Check every", `settings.sourceNotReadOnly` "Only a Read-only tool can be a source.", `settings.sourceBadArguments` and `settings.refusedExpansion`.
- `SETTINGS_TEXTS.save` "Save changes"; `MCP_TEXTS.cancel` "Cancel" and `removeButton` "Remove".
- `Web.Api` `MESSAGEBADSETTINGS`, `MESSAGENOTFOUND` and `MESSAGESERVERERROR`.
- 21.4's T1 (the demo line) and its states.
- McpOps' `MESSAGESAVED` "Saved". McpOps' 22.5 source messages are relayed (approved at gate C).

**Ruled (ruling D; all in Settings > Tools and MCP servers unless said; online demo: none shows there, since T1 replaces the section):**
- T1 group heading: "Your sources".
- T2 table headers: "Source", "Tool", "Check every" (accepted). Empty: "No sources yet." "Source" is also the tools table's new column header.
- T3 tool cell: "{tool} on {server}".
- T4 interval choices: "5 minutes", "15 minutes", "30 minutes", "1 hour", "6 hours", "1 day". Any other value: "{n} minutes", or "{h} hours" for a whole number of hours.
- T5 the source button's accessible name: "Use {tool} on {server} as a source".
- T6 the Remove button's accessible name: "Remove the source {source}".
- T7 "New since 1.0.0" bullet (README "Your integrations" today; GUIDE.md once 0.30 is in): "- **MCP tools as sources.** On your own install, an admin sets a Read-only MCP tool up as a source in Settings > Tools and MCP servers, with its arguments and how often to check it. OcuTalon calls it on that schedule and makes an attention decision on each new result, and the source joins the digest's coverage list. Sources are off on the online demo."
  - Ruled conditions: (a) "and the source joins the digest's coverage list" stays only if a test in 22.5 or 21.5 proves a saved source shows in the digest's coverage list; else cut it so the sentence ends "...makes an attention decision on each new result." (b) "each new result" stays only if the code skips a result unchanged from the last poll (22.11's results-as-items); if every poll's result becomes an item, write "on each result". "Sources are off on the online demo." stays. T7 goes in GUIDE.md's "New since 1.0.0" (0.30 is in: `GUIDE.md` :7, after :16).
- The rail's source schedule (`RAIL_TEXTS.checkScheduleSource`, owned by 21.5; it replaces 22.5's "{n} minutes" form): "Polled every {duration}", with {duration} in T4's words (for example "Polled every 15 minutes", "Polled every 6 hours", "Polled every 1 day"; never "Polled every 1440 minutes"). Online demo: no source rows, so it never shows.

**New:** none.

**Findability:** no More to try item, because the section is not visible on the online demo.

## Verification

Run every command from the worktree root, after `git rev-parse --show-toplevel` matches it.
- `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Tags: warm `e21s5iw` and fresh `e21s5i`; QA `e21s5qw`/`e21s5q`; review `e21s5rw`/`e21s5r`. The production-changing checks (the live units) run only on the lane-C fresh throwaway `e21s5i`.
- One command per foreground call, with `timeout: 600000`, each sized to about 150 s (the harness backgrounds a call at about 170-180 s). One class per call.
- Never two test runs in one message. One `iris_execute_tests` per message, with `server` and `namespace`.
- If `ci/warm.sh up` is backgrounded, wait in bounded foreground polls and never restart it.
- McpOps and SettingsOps run in the production, so a mutation of `SettingsOps` needs `ci/warm.sh down` then `up` before the class run (`Web.McpSettings` runs in the test process through the probe).
- Tear down only this stage's tags. Never a slot, `ocutalon-aihub-test` or another lane's stack.

**Shared surfaces:**
- the GET `/v1/settings/mcp` body (new `sources`: 21.4's `SettingsMcp` body assertions, `mcp-view.test.mjs`, `api-types.ts`, `withClassification`);
- the tools table's columns and DOM (21.4's B1-B10 locators);
- `Web.McpSettings`' UrlMap and `Answer` table (21.4's `TestFailedAnswers`, `TestOnlineDemo`, `TestNotAdmin` route loops);
- the `ux-strings.test.mjs` inventory, `RAIL_TEXTS`' fixed strings, `announce-focus-sources.test.mjs`' focus count for `mcp-section.ts`;
- the initial bundle (998.08 kB of 1 MB);
- a session's `BackgroundCheck` rows: M7 and B11 create `source` rows through the real route and remove them; check-counting tests (rail specs, `Test.Digest.*`) must not see them, so each test removes its rows in `finally`.

Criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `<vars> OCUTALON_RUN_TAG=e21s5iw ci/warm.sh up` -- expected: ready.
- (loop) `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s5iw ci/iris.sh class OcuTalon.Test.Web.McpSettingsApi` -- expected: passed (21.4's whole class took about 15 s). Mutations:
  - the `@{` check after the submit -> the "nothing submitted" case goes red;
  - the DELETE owner check removed -> the "Not yours" case goes red;
  - `Context` not called on `SetSourcePoll` -> the recorded-command case goes red;
  - the demo check moved after the body read -> the "Online demo" case goes red (AC 6);
  - the `set` branch placed after `bad_name` -> `BadServer` -> the `bad_name` case is `bad_mcp_server` (red).
- (loop) `... class OcuTalon.Test.Core.SettingsMcp` -- expected: passed. Mutations (warm down and up after each SettingsOps change):
  - the Kind filter removed -> `TestListSources` goes red;
  - `arguments` added to a row -> red.
- (once each, one per call) `... class OcuTalon.Test.Core.CommandsStep4`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Web.HookSettingsApi` -- expected: passed (unchanged).
- (once) `node --test web/scripts/` -- expected: passed. Mutations: `canBeSource` true for `unclassified` -> red; no `source` branch in `checkRow` -> red; `withClassification` without `sources` -> red.
- (once each) `cd web && npx tsc -p tsconfig.e2e.json --noEmit` and `cd web && npm run build` -- expected: clean; the initial total at most 0.7 kB above Task 0 (c)'s number and under 1 MB (else STOP, V8).
- (once) `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh build`.
- (once) `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh live sign-in --part k/n` (the part whose PART line lists `api/mcp.spec.ts`; 21.4 used `--part 2/16`) -- expected: passed. Mutation: the route submits without `SessionRef` -> M7's GET lists no source (red).
- (once) `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh live sign-in-2 --part k/n` (the part listing `settings/mcp.spec.ts`; 21.4 used `--part 10/12`) -- expected: passed. Mutation: the source control is enabled for a risky tool -> B11 red.
- (once) `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh live <project> --part k/n` (the project and part whose PART line lists `rail/rail.spec.ts`) -- expected: passed (R5).
- (once each, also after a failure) `<vars> OCUTALON_RUN_TAG=e21s5iw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh teardown`.
- (once each) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh` -- expected: pass.
- (once, after S1 and S2) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: no finding beyond the baseline.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
