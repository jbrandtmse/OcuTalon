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

**Problem:** An admin can classify an MCP tool Read-only, but cannot make it a source: the page has no source-poll form, `Web.McpSettings` (Story 21.4) has no `/sources` route, and the settings GET lists no sources. `SetSourcePoll`/`RemoveSourcePoll` exist as commands, but nothing on the page sends them.

**Approach:** Extend 21.4's section and routes. In the tools table, each Read-only tool gets "Use as a source", which opens a form (Source name, Arguments (JSON), Check every). A tool that is not Read-only can't be chosen, and the accepted reason shows beside it. Two admin-checked routes in `Web.McpSettings` submit `SetSourcePoll` and `RemoveSourcePoll` (origin `web_admin`, the admin's `SessionRef`) to Lane A's `McpOps`, which Story 22.5 builds. 21.4's `ListMcpServers` answer gains `sources`: the caller's own session's source rows. All of it is off on the online demo, where 21.4's T1 line shows. **Proposed split:** epics ACs 2-4 (the approval requests on every channel) move to a new sibling, 21.10 (Design Notes).

## Boundaries & Constraints

**Always:**
- Each change is a command with origin `web_admin`, sent through the `Submit` seam of `Web.McpSettings`. That seam carries `ActingUser` `$USERNAME` and `SessionRef` from `Ownership.SessionRef`. The REST process writes nothing. The GET reads sources only inside `ListMcpServers` (SettingsOps' job), and the DELETE's owner check reads only `Ownership.Checks(sessionRef)`.
- **The route checks, before any submit:**
  - the body has exactly `{server, tool, name, arguments, intervalMinutes}`: four strings and one whole number;
  - neither `name` nor `arguments` holds `@{`;
  - `arguments` is `""` or the text of a JSON object.

  McpOps (22.5) judges the rest: Read-only, the name, the interval, the size and `secret://`. Its messages are relayed unchanged.
- **Sources belong to the session that set them (AD-4, AD-18).** The GET lists only the caller's own. A DELETE whose Ref is not a `source` row of the caller's session gets 404, and nothing is submitted.
- **Online demo:** both new routes answer 409 `not_available` with 21.4's T1, before the body is read. The section shows T1 in place of its content. No source can be saved, and none is polled.
- Only accepted or listed text ships (Public text). Every test added or changed creates and removes its own `zz` servers, tool rows, source rows and sessions' fixtures, and passes on a fresh environment, in either order.

**Never:**
- The approval-request ACs (epics ACs 2-4; proposed 21.10).
- Any Lane A edit: `Mcp/**`, `Watch/**`, `Checks/**`, `Data/BackgroundCheck.cls`, `Live/Payload/Check.cls`, the bridge.
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
| Route refusal | An extra or missing member, or a wrong type; `@{` in name or arguments; arguments `[1]`, `"x"` or `not json` | 400 `bad_source`, `fields` {member: text}: `MESSAGEBADSETTINGS` for a shape error; `settings.refusedExpansion`; `settings.sourceBadArguments` | Nothing submitted |
| McpOps refusal | A risky, unclassified or unknown tool; an unknown server; a blank name or one over 100 characters; an interval outside 5-1,440; arguments over 4,000 characters or holding `secret://` | `not_read_only` -> 400 `bad_source` `{tool}`. `bad_name` -> `{name}`. `bad_interval` -> `{intervalMinutes}`. `bad_arguments` -> `{arguments}`. `not_found` -> 404. Each carries McpOps' message | No row |
| McpOps failure | `failed`, `not_audited`, `not_allowed` or any other word | 500 `server_error` | The page shows `MESSAGESERVERERROR` |
| Remove | DELETE `/v1/settings/mcp/sources/<own Ref>` | One `RemoveSourcePoll` (`SourceRef`, `ActingUser`, `SessionRef`). 200 `{"result":"removed","message":<McpOps' message>}`. GET lists it no more | McpOps `not_found`: 404 |
| Not yours | DELETE of another session's `source` Ref, a non-source check's Ref, or an unknown Ref | 404 `not_found`; nothing submitted; the row stays | -- |
| List | The caller's session holds a `source` row and a `production` row; another session holds a `source` row | `sources` holds only the caller's `source` row, sorted by name, with no `arguments` member | -- |
| Not an admin | LIVE `OcuTalonUser`, either route | 403 `not_admin`; nothing submitted | -- |
| Online demo | `onlineDemo` 1, either route, any body | 409 `not_available` + T1, before the body is read | Nothing submitted |

</intent-contract>

## Code Map

**Built by Story 21.4 (ready-for-dev, not yet implemented; 21.5 extends each, Rule 2):**
- `src/ocutalon/cls/OcuTalon/Web/McpSettings.cls`: UrlMap, `Refusal` (403, then 409 + T1 before the body), the `Submit` seam, the answer mapping, and the `settings.refusedExpansion` field error.
- `Core/SettingsOps.cls` `ListMcp` and `Msg/Command/ListMcpServers.cls`: the GET body.
- `Test/Web/McpSettingsApi.cls` + `McpSettingsProbe.cls` (its submit double records the command) and `Test/Core/SettingsMcp.cls`.
- Web:
  - `web/src/app/settings/mcp-section.ts` and `mcp-view.ts` (`MCP_TEXTS`, the tools table with a `role="radiogroup"` per row);
  - `api-client.ts` `mcpSettings()` and `api-types.ts` `McpSettings`/`McpToolRow`;
  - `web/e2e/api/mcp.spec.ts` (M1-M6, the mock helpers) and `web/e2e/settings/mcp.spec.ts` (B1-B5);
  - `web/scripts/mcp-view.test.mjs`.
- 21.4's T1 (`settings.mcpOffOnDemo`) is the demo line.

**Built by Story 22.5 (Lane A, ready-for-dev; read only):**
- `Mcp/Ops.cls` `OnSetSource`/`OnRemoveSource`:
  - outcomes `saved` (with `Ref`), `removed`, `not_read_only`, `not_found`, `bad_name`, `bad_arguments`, `bad_interval`, `not_allowed` and `not_audited`;
  - the `MESSAGE*` texts at 22.5's gate.
- `Data/BackgroundCheck.cls`: `Server`, `Tool`, `Arguments` and `IntervalMinutes` (storage 16-19), Kind `source`, owned by the command's `SessionRef`.

**Existing (verified on this branch, HEAD 8ea041a8):**
- `Msg/Command/SetSourcePoll.cls` :6-21 (`Server` 40, `Tool` 128, `Name` 100, `Arguments`, `IntervalMinutes`, `ActingUser`). `RemoveSourcePoll.cls` :6-9 (`SourceRef` 22, `ActingUser`). The base `Msg/Command.cls` has `Origin` :9 and `SessionRef` :15. `Msg/CommandResult.cls`: `Ok`, `Message`, `Outcome`, `Ref` :15, `Data`.
- `Core/CommandsIn.cls`:
  - routes :359-360 (both to McpOps, `web_admin` only);
  - refusals :109-111;
  - the answer :132-139. With no McpOps handler the answer is `failed` (DW-1137, by-design until 22.5).
- `Web/Api.cls`:
  - `OnPreDispatch` :307-322 and `IsSettingsUrl` :348, which already gates `/v1/settings/mcp/...`;
  - `SettingsBody` :1103, `MESSAGEBADSETTINGS` :189, `MESSAGENOTFOUND` :171, `MESSAGESERVERERROR` :181, `Fail` :1486;
  - `RailBody` :1393-1401, which uses `Ownership.Checks` + `Live.Payload.Check.FromRow` for the rail.
- `Web/HookSettings.cls` :96: the owner check -> 404 (the sibling for the DELETE's check).
- `Data/Ownership.cls` `Checks(sessionRef, *sc)` :435. It is owner-filtered and runs in the REST process and in jobs (`Rows` :1109, statement :1192-1194). `SessionRef` :293. `Data/Session.cls` :1: one durable session per IRIS user on a local install.
- `Data/BackgroundCheck.cls` (Lane A, read only): `Ref` :11, `SessionRef` :14, `Kind` :17, `DisplayName` :26.
- `Mcp/Ops.cls` (read only): `MESSAGESAVED` "Saved" :58, `MESSAGENOSERVER` :52, `MESSAGENOTOOL` :54.
- `Msg/Catalog/Core.cls`: `settings.refusedExpansion` :756 and `settings.sourceHeading`/`Help`/`Name`/`Arguments`/`Interval`/`NotReadOnly`/`BadArguments` :771-801 (accepted; EXPERIENCE.md :1010-1016, :1078-1079).
- Web:
  - `web/src/app/settings/settings-view.ts` (`SETTINGS_TEXTS.save` "Save changes" :42; Cancel);
  - `webhooks-section.ts`, the field-error sibling (focus on the first error, the announcer);
  - `web/scripts/ux-strings.test.mjs`;
  - the rail (conditional item only): `web/src/app/rail/rail-view.ts` titles :211-215, check rows :244-265 and schedules :55-56; `web/src/app/live/payloads.ts` `CheckPayload` :344; `web/scripts/rail-view.test.mjs` :379-412.
- `README.md` :62 "New since 1.0.0" ("Your integrations" :66-76). `GUIDE.md` is not on this branch.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement, before code; source reads only; results go under Design Notes "Read at implement"):
  - (a) Confirm 21.4 and 22.5 are merged into this branch. If either is missing, stop with `## Clarification Needed` (C1).
  - (b) From the merged `Mcp/Ops.cls`, record the exact outcome words, the `Ref` on `saved`, and the `MESSAGE*` names. From the merged `Data/BackgroundCheck.cls`, record the column names. Adjust the Matrix mapping only where a name differs.
  - (c) From the merged `Web.McpSettings`, record its `Submit`, `Answer` and field-error helpers. Record also whether `List` sets `SessionRef` on `ListMcpServers`; set it if not.
- [ ] `src/ocutalon/cls/OcuTalon/Web/McpSettings.cls`:
  - UrlMap rows `/sources` POST `SetSource` and `/sources/:ref` DELETE `RemoveSource`.
  - `SetSource` follows the Always order: `Refusal`, the shape, `@{`, the arguments, then submit through the seam. `RemoveSource`: `Refusal`, then the Ref must be a `source` row in `Ownership.Checks(SessionRef)` (else 404), then submit.
  - The answers follow the Matrix. Extend the existing answer mapping (one table of words), do not copy it.
  - Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `ListMcp`'s `Data` gains `sources`. It reads `Ownership.Checks(command.SessionRef)`, keeps Kind `source`, and maps each row to `{ref, name: DisplayName, server, tool, intervalMinutes}`, sorted by name. A failed read answers `failed`, as 21.4's do. Update the doc.
- [ ] `web/src/app/api/api-types.ts`, `api-client.ts` -- `McpSourceRow` and `McpSettings.sources`; `setMcpSource(body)` and `removeMcpSource(ref)`.
- [ ] `web/src/app/settings/mcp-view.ts` -- extend `MCP_TEXTS` with T1-T6 (Public text), and add:
  - `INTERVAL_CHOICES` (5, 15, 30, 60, 360, 1440; default 15) and `intervalText(n)`;
  - `canBeSource(tool)` (`read-only` and status not `refused`);
  - `sourceBody(...)`, `sourceOutcome(...)` and `toolText(tool, server)`.
- [ ] `web/src/app/settings/mcp-section.ts`:
  - **Tools table.** It gains a "Source" column:
    - a Read-only tool gets the "Use as a source" button (accessible name T5);
    - any other non-refused tool gets the button with `aria-disabled="true"`, `settings.sourceNotReadOnly` beside it, linked by `aria-describedby`; a press does nothing;
    - a refused tool gets no control.
    - A classification change updates the control at once.
  - **The form.** The button opens a form panel below the table: heading `settings.sourceHeading`, the line "{tool} on {server}", help `settings.sourceHelp`, then Source name (maxlength 100), Arguments (JSON) (a textarea) and Check every (a select), with Save changes and Cancel.
    - Focus starts on Source name.
    - Field errors appear under their fields, and focus moves to the first one. A `tool` error and a 500 are form-level.
    - On success, "Saved" (McpOps' message) is announced, the panel closes, focus returns to the row's button, and the list reloads.
  - **"Your sources" group (T1-T3).** A table with Source, Tool and Check every, plus a Remove button per row (accessible name T6, no dialog). A success announces McpOps' message and reloads; a failure shows `MESSAGESERVERERROR`.
  - A 409 shows T1, and a 403 the denied state (21.4's states).
- [ ] **Tests (ObjectScript):**
  - `Test/Web/McpSettingsApi.cls` + `McpSettingsProbe.cls` -- every Matrix route row through the probe's submit double, which is the AC's McpOps test double:
    - the recorded command's every field;
    - nothing submitted on each route refusal, on a 404 or on the demo;
    - the 409 comes before the body;
    - the 403;
    - each outcome word maps to its HTTP answer.
  - `Test/Core/SettingsMcp.cls` -- the "List" row: own `source` rows only, sorted, no `arguments`; other kinds and other sessions left out. It uses fixture `BackgroundCheck` rows and removes them.
- [ ] **Tests (web):**
  - `web/scripts/mcp-view.test.mjs` -- `intervalText` (each choice; 120 gives "2 hours"; 45 gives "45 minutes"), `canBeSource` for each classification and status, `sourceBody`, `sourceOutcome`.
  - `web/scripts/ux-strings.test.mjs` -- the new entries.
  - `web/e2e/api/mcp.spec.ts` (real HTTP):
    - **S1:** the LIVE user gets 403 on both routes.
    - **S2:** the README admin adds `zz<run>` at the mock (21.4's M2 helpers) and classifies `zz_lookup` Read-only. Then:
      - POST returns 200 `saved` with a Ref;
      - GET lists the source;
      - an `irisScript` fixture `source` row of another session is not listed, and its DELETE gets 404 and the row stays;
      - the admin's DELETE returns 200, and GET no longer lists it.
    - **S3:** a risky tool gives 400 `{tool}`; `"arguments":"x"` gives 400 `{arguments}` with `settings.sourceBadArguments`; `@{` gives `settings.refusedExpansion`. Each time GET lists nothing new.
  - `web/e2e/settings/mcp.spec.ts` (browser):
    - **B6:** with a fixture server with a Read-only and a Risky tool, the Read-only row's control opens the form and the Risky row's is `aria-disabled` with the reason beside it. Saving shows "Saved" and a "Your sources" row "Jira | zz_lookup on zzS | 15 minutes". Remove takes the row off.
    - **B7:** arguments `[1]` shows `settings.sourceBadArguments` under Arguments (JSON), with focus moved there.
- [ ] **Docs and spine** (after the gate; marker `[ADDED 2026-MM-DD, Story 21.5]` with the day the lead writes it) -- S1 and S2 of Design Notes. After acceptance, T7 goes wherever "New since 1.0.0" lives at merge (README.md :62 today, GUIDE.md once 0.30 is in), and T1-T6 go into EXPERIENCE "Settings and requests (step 4)".

**Acceptance Criteria:**
- Given a Read-only tool in Settings > Tools and MCP servers, when an admin presses "Use as a source", enters a name, arguments and an interval, and saves, then the form uses the accepted `settings.source*` wording and the route submits `SetSourcePoll` to `McpOps` (origin `web_admin`, the admin's `SessionRef`, exactly the entered values). "Saved" shows, and the source is listed under "Your sources" with its tool and interval (B6, S2, `McpSettingsApi`).
- Given a tool that isn't Read-only, when the tools table shows it, then its source control can't be chosen and "Only a Read-only tool can be a source." shows beside it; a crafted POST for it gets 400 with McpOps' `not_read_only` message, and no row is created (B6, S3).
- Given arguments that are not a JSON object, or `@{` in the name or the arguments, when the admin saves, then the field error (`settings.sourceBadArguments` or `settings.refusedExpansion`) shows under its field and takes focus, and nothing is submitted (B7, S3, `McpSettingsApi`).
- Given the admin's own source, when they press Remove, then `RemoveSourcePoll` is submitted and the source leaves the list. A source of another session is never listed, and its DELETE gets 404 with nothing submitted (S2, `McpSettingsApi`, `SettingsMcp`).
- Given the route tests, when they run, then a `McpOps` test double (the route probe's submit seam) records every submitted source command, and the real-HTTP tests (S1-S3) reach the real `McpOps` of Story 22.5 (epics AC 1's test-double clause, Rule 2).
- Given the online demo, when anyone calls either route or opens the section, then 409 `not_available` with T1 comes before the body is read, the section shows T1 in place of its content, and nothing is submitted (`McpSettingsApi`; 21.4's B5).

## Spec Change Log

- 2026-11-12 (lead, spec gate): split ruled (21.10); 22.5 item 9 routed here by the Planner, so the rail line is in scope.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-1: commands from `web_admin`; the REST process writes nothing.
- AD-4: session ownership.
- AD-13: admin-checked `/v1/settings` routes and the envelope.
- AD-18: the source row type; `McpOps` creates rows through `Watch.Ops`; Lane B only reads.
- AD-19: `@{` refused; no secret in the arguments.
- AD-21: the verbs; source polls run through a `tool` request.
- AD-25: the online demo: off.
- AD-29 and AD-33: lanes; one creator of a source row.

No AC contradicts an AD's Rule. The approval ADs (AD-10, AD-11, AD-16, AD-31, AD-32) govern the proposed 21.10.

**Proposed split (doctrine U5; the lead rules; this spec plans only 21.5's child):**
- **21.5 (this spec):** epics AC 1, the source-poll form and its routes, with the test-double clause.
- **21.10 (new, proposed): "Answer tool-call and standalone approval requests on every channel".** Epics ACs 2, 3 and 4 move to it verbatim: the tool-call card and its plain-text copies; the standalone fix with "Why:", its dry run and the `BridgeSink` notices; the cancelled request on every channel.
  - Order: after 22.4 merges, with fixture rows for 22.4 and 22.7. It does not depend on 21.4.
  - Moving the ACs is veto item V5.
- **Why split:** the two halves share no file and no dependency (sources need 21.4 and 22.5; approvals need 22.4 and 22.7), and together they touch about 20 files. The approval half alone changes the web card, the payload, the catalog renderer's plain-text inputs, `BridgeSink` (beside 22.4's ruled R1 branch) and the Telegram and phone edits.
- **Read for 21.10** (evidence on this branch, so its plan starts from facts):
  - Already met:
    - the tool-call notices on the phone, Telegram and web chat: `BridgeSink.ToolNoticeOf` :233-254 and `toolCall.requestOnServer` (`Catalog/Core.cls` :602), pinned by `Test.Core.ToolCallNotices`;
    - first answer wins (`Approval.AnswerLocked` :357-362; Telegram `EditAnswered` :283);
    - the card shows "Approval needed", Approve, Reject and the expiry (`approval-view.ts` :49-52, :82);
    - a cancelled request leaves the rail on its live update (`rail-view.ts` :340-345; `rail.spec.ts` R3).
  - Gaps:
    - "Why:" (no reason column; `payload.reason` is unread);
    - the inputs as labelled lines (today one line, "Inputs: {...}", cut at 200);
    - no `server` member in the payload;
    - no notice for `approval.cancelled` (`BridgeSink.cls` :253), so Telegram and phone keep their buttons;
    - `answered.canceled` (:806) is used by no product code;
    - a cancelled chat card shows no status;
    - no `BridgeSink` notice or web card for a fix with no incident (`Replayable` :226-230; `requestsOf` drops it);
    - no `email` fix kind yet (22.7);
    - the rail has no buttons by design (`answers.spec.ts` X6 :551).
  - Ledger: DW-592 (an answered tool-call card after a reload) is related.

**Order and dependencies (said plainly):**
- **From 21.4 (not yet built):** every piece 21.5 extends -- `Web.McpSettings` and its `Refusal`/`Submit`/answer mapping, `ListMcpServers`/`ListMcp`, `mcp-section.ts`/`mcp-view.ts` and the tools table, the API client and types, T1, the test classes and both e2e specs with the mock helpers. 21.5 implements after 21.4 is implemented and merged into this branch.
- **From 22.5 (Lane A):** the `McpOps` handlers and their outcomes, the `BackgroundCheck` source columns, and the `MESSAGE*` texts.

**Decided in-stage (reversible inside this story):**
1. **The list shows the caller's own sources only.** A session is one IRIS user on a local install (`Data/Session.cls` :1). The list is read through the existing `Ownership.Checks` in SettingsOps' job; there is no new Ownership method.
2. **The DELETE route removes only the caller's own source (404 otherwise).** This is narrower than 22.5's "any admin may remove any source", which still holds for McpOps (V3).
3. **One judge.** The route checks only shape, `@{` and that the arguments are a JSON object (accepted texts); McpOps judges the rest, and its messages are relayed.
4. **Check every** is a select of six choices, with 15 minutes as the default, so a bad interval can come only from a crafted request.
5. **A refused tool gets no source control.** Its status already says why.
6. **No edit control and no arguments in the GET.** Saving the same name updates the source (22.5's natural key).
7. **Removing a source asks nothing.** It is undone by setting it again, and nothing pending is lost.
8. **The isolation case uses a fixture `source` row of another session**, made and removed with `irisScript`. No second admin user is needed (standing rule (iii)).
9. **"Use as a source"** (the accepted heading text) is also the button text. Save and Cancel reuse `SETTINGS_TEXTS`.

**Clarifications for the lead (non-blocking; the plan runs on the stated default):**
- **C1 (order; for the orchestrator's graph):** 21.5 implements only after 21.4 AND 22.5 have merged into this branch.
  - Evidence:
    - DW-1137 is closed by-design on the grounds that "no UI sends them before 22.5";
    - the standing real-HTTP rule (ii) needs McpOps' real `saved`;
    - the list reads 22.5's columns.
  - If the orchestrator classes this as an epic-dependency change, it goes to the owner. Default: Task 0 (a) stops the implement stage until both have merged.
- **C2:** the route relays McpOps' (22.5) source messages verbatim. Their wording is decided at 22.5's gate, and a change there needs no 21.5 change.

**Pending routing (22.5 -> 21.5, Planner) -- CONDITIONAL, applied only if the Planner routes 22.5's veto item 9 here. The core plan does not depend on it:**
- AC (would add): "Given a `source` check row whose payload carries `intervalMinutes` n, when the rail shows it, then its detail line reads 'Polled every {n} minutes', like the production and queue schedule lines."
- Task (would add):
  - `web/src/app/live/payloads.ts` `CheckPayload` gains `intervalMinutes?: number`.
  - `web/src/app/rail/rail-view.ts` gains `checkScheduleSource` and, in the check-row detail :259-263, a `source` branch (no line when the member is absent).
  - Tests: `web/scripts/rail-view.test.mjs` adds the source row, with mutation "no `source` branch -> red"; `web/e2e/rail/rail.spec.ts` gets one source row case.
  - It reads 22.5's `intervalMinutes` (`Live/Payload/Check.cls`), unchanged.
- PUBLIC TEXT (22.5's proposal, for the Planner): `checkScheduleSource` = "Polled every {n} minutes". Online demo: no source rows, so it never shows.

**Contended edits needed:** none. 21.5 uses only Lane A's published contracts: 22.5's verbs, outcomes and columns (AD-18's row type), and `Mcp.Ops` messages. `Core.BridgeSink`, where 22.4's ruled R1 branch lands, is not touched by this child; that contention moves to 21.10.

**Ledger:**
- Inbox: none.
- Cited: DW-1137 (by-design until 22.5; this story's UI is the first sender, hence C1); DW-1045 (`wontfix-accepted`, `reopen_if` a step 4 text is edited without the other). 21.5 edits neither EXPERIENCE's catalog rows nor `Catalog.Core`; its new texts are page constants. So DW-1045 does not reopen.

**Integration ACs (Rule 1):** the settings page (`mcp-section.ts`) reads `sources` from the GET and posts to the two routes. These submit to the real `McpOps` (22.5), whose row then appears in the GET (S2, B6), and is removed by the DELETE (S2).
**Consumes:**
- 21.4: `Web.McpSettings`, `ListMcpServers`/`ListMcp`, `mcp-section`/`mcp-view`, the API client, T1, the mock helpers.
- 22.5: the `SetSourcePoll`/`RemoveSourcePoll` handlers and the source columns.
- Also: `Ownership.Checks`, `Commands.Submit`/`CommandsIn`, `Msg.Command.SetSourcePoll`/`RemoveSourcePoll`.

All are real instances in S1-S3 and B6-B7.
**Consumed-by:** no later story calls these routes. 22.6 (docs) describes the form (inference from 22.5's Consumed-by).

**Extend, don't copy (Rule 2):**
- The routes join 21.4's `Web.McpSettings` and its `Refusal`, `Submit` seam and answer mapping.
- The DELETE's owner check follows `HookSettings` :96.
- `sources` extends 21.4's `ListMcp`, read through the existing `Ownership.Checks`.
- The form and the list extend 21.4's `mcp-section.ts`/`mcp-view.ts` (states, field errors as in `webhooks-section.ts`).
- The tests extend `McpSettingsApi`/`Probe`, `SettingsMcp`, `mcp.spec.ts` (both) and `mcp-view.test.mjs`.

**Spine items (after the gate; additive):**
- **S1, REST row :1661:** append: "POST body `{server, tool, name, arguments, intervalMinutes}`; the route refuses a shape error, `@{` and arguments that are not a JSON object, and McpOps judges the rest; DELETE removes only a `source` row of the caller's session (else 404); both 409 `not_available` on the online demo before the body [ADDED, Story 21.5]".
- **S2, AD-21's `ListMcpServers` sentence (as 21.4's S3 writes it):** "its answer also lists the caller's session's source rows (`ref`, `name`, `server`, `tool`, `intervalMinutes`; never the arguments) [ADDED, Story 21.5]".

**Rulings so far:** the split into 21.5 + 21.10 is ruled by the Epic 21 runner (decide, doctrine U5; `epics.md` written; the orchestrator records the graph hash, reason=split). The Contest Planner ruled 22.5's item 9 YES (`prompts/gate-rulings-20261112-1810.md` C): "Polled every {n} minutes" comes to this story as a DW bullet and its text is approved, so the "Pending routing" section above is IN SCOPE (V7 applies). V1-V6 and T1-T7 await the Planner.

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| V1 | New routes: `POST /api/v1/settings/mcp/sources` and `DELETE /api/v1/settings/mcp/sources/<ref>` (`Web.McpSettings`; admin-checked; real-HTTP tests S1-S3 with the LIVE user, the README admin and an isolation case) | approve | 409 + T1 before the body |
| V2 | The GET `/v1/settings/mcp` body gains `sources` (the caller's own; no arguments) | approve | the GET answers 409 (21.4) |
| V3 | Access rule: the web DELETE removes only the caller's own source; McpOps' any-admin rule (22.5 V5) is unchanged | approve | refused |
| V4 | Outward calls: a saved source makes Lane A's `Checks` poll the admin's MCP server at its interval (22.5's V3; this story adds the control that starts it) | approve | none (no source can be saved; 22.5 skips `source` rows) |
| V5 | Split: epics ACs 2-4 move verbatim to new Story 21.10 | approve | -- |
| V6 | Order C1: 21.5 implements after 22.5 merges (a cross-epic story wait) | approve | -- |
| V7 | Conditional: the rail line in Lane B's `rail-view.ts` (22.5's veto item 9), only if the Planner routes it | Planner | never shows |

There is no new command, grant, role, privilege, table, column, retention or web dependency.

## Public text

**Reused (accepted):**
- `settings.sourceHeading` "Use as a source", `settings.sourceHelp`, `settings.sourceName` "Source name", `settings.sourceArguments` "Arguments (JSON)", `settings.sourceInterval` "Check every", `settings.sourceNotReadOnly` "Only a Read-only tool can be a source.", `settings.sourceBadArguments` and `settings.refusedExpansion`.
- `SETTINGS_TEXTS.save` "Save changes" and "Cancel"; "Remove".
- `Web.Api` `MESSAGEBADSETTINGS`, `MESSAGENOTFOUND` and `MESSAGESERVERERROR`.
- 21.4's T1 (the demo line) and its states.
- McpOps' `MESSAGESAVED` "Saved". McpOps' 22.5 source messages are relayed (their gate).

**New, for the Planner** (all in Settings > Tools and MCP servers; online demo: none shows there, since T1 replaces the section):
- T1 group heading: "Your sources".
- T2 table headers: "Source", "Tool", "Check every" (accepted). Empty: "No sources yet." "Source" is also the tools table's new column header.
- T3 tool cell: "{tool} on {server}".
- T4 interval choices: "5 minutes", "15 minutes", "30 minutes", "1 hour", "6 hours", "1 day". Any other value: "{n} minutes", or "{h} hours" for a whole number of hours.
- T5 the source button's accessible name: "Use {tool} on {server} as a source".
- T6 the Remove button's accessible name: "Remove the source {source}".
- T7 "New since 1.0.0" bullet (README "Your integrations" today; GUIDE.md once 0.30 is in): "- **MCP tools as sources.** On your own install, an admin sets a Read-only MCP tool up as a source in Settings > Tools and MCP servers, with its arguments and how often to check it. OcuTalon calls it on that schedule and makes an attention decision on each new result, and the source joins the digest's coverage list. Sources are off on the online demo."

**Findability:** no More to try item, because the section is not visible on the online demo.

## Verification

Run every command from `/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/epic-21`, after `git rev-parse --show-toplevel` matches it.
- `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Tags: warm `e21s5iw` and fresh `e21s5i`; QA `e21s5qw`/`e21s5q`; review `e21s5rw`/`e21s5r`. The production-changing checks (the live units) run only on the lane-C fresh throwaway `e21s5i`.
- One command per foreground call, with `timeout: 600000`, each sized to about 150 s (the harness backgrounds a call at about 170-180 s).
- Never two test runs in one message. One `iris_execute_tests` per message, with `server` and `namespace`.
- If `ci/warm.sh up` is backgrounded, wait in bounded foreground polls and never restart it.
- Tear down only this stage's tags. Never a slot, `ocutalon-aihub-test` or another lane's stack.

**Shared surfaces:**
- the GET `/v1/settings/mcp` body (new `sources`: 21.4's `SettingsMcp` body assertions, `mcp-view.test.mjs`, `api-types.ts`);
- the tools table's columns and DOM (21.4's B1-B5 locators);
- `Web.McpSettings`' UrlMap (21.4's `TestMcpSettingsRoutes`);
- the `ux-strings.test.mjs` inventory;
- a session's `BackgroundCheck` rows: S2 and B6 create `source` rows through the real route and remove them; check-counting tests (rail specs, `Test.Digest.*`) must not see them, so each test removes its rows in `finally`.

Criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `<vars> OCUTALON_RUN_TAG=e21s5iw ci/warm.sh up` -- expected: ready.
- (loop) `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s5iw ci/iris.sh class OcuTalon.Test.Web.McpSettingsApi` -- expected: passed. Mutations:
  - the `@{` check after the submit -> the "nothing submitted" case goes red;
  - the DELETE owner check removed -> the "Not yours" case goes red;
  - `SessionRef` not set on `SetSourcePoll` -> the recorded-command case goes red;
  - the demo check moved after the body read -> the "Online demo" case goes red (AC 6).
- (loop) `... class OcuTalon.Test.Core.SettingsMcp` -- expected: passed. Mutations:
  - the Kind filter removed -> the "List" case goes red;
  - `arguments` added to a row -> red.
- (once each, one per call) `... class OcuTalon.Test.Core.CommandsStep4`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Web.HookSettingsApi` -- expected: passed (unchanged).
- (once) `node --test web/scripts/` -- expected: passed. Mutation: `canBeSource` true for `unclassified` -> red. Then (once each) `cd web && npx tsc -p tsconfig.e2e.json --noEmit` and `cd web && npm run build` -- expected: clean.
- (once) `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh build`.
- (once) `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh live sign-in --part k/n` (the part whose PART line lists `api/mcp.spec.ts`, with n large enough for about 150 s) -- expected: passed. Mutation: the route submits without `SessionRef` -> S2's GET lists no source (red).
- (once) `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh live sign-in-2 --part k/n` (the part listing `settings/mcp.spec.ts`) -- expected: passed. Mutation: the source control is enabled for a risky tool -> B6 red.
- (once each, also after a failure) `<vars> OCUTALON_RUN_TAG=e21s5iw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s5i ci/iris.sh teardown`.
- (once each) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh` -- expected: pass.
- (once, after S1 and S2) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: no finding beyond the baseline.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
