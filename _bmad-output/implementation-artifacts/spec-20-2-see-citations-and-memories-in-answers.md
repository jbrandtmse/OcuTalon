---
title: 'Story 20.2: See citations and memories in answers'
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-20-context.md'
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Lane A already puts code-built `citations` and `memories` on the bridge `Reply`'s `HostData` (Stories 34.1, 19.3, 19.4), but `Conversation` drops them, so the web chat cannot show where an answer came from, and the "cited answers" the Documents page and README promise are invisible to a visitor or a judge.

**Approach:** `Conversation` keeps both arrays on the `Turn` (beside `CheckKey`/`CheckRows`) and carries them onto the `Outbound` and `chat.message` (and so `/v1/state`); the web reply ends with citation chips and "From memory" chips whose popovers show the passage or memory, and "Open document" shows that document's text on the Documents page through a new read-only `GET /v1/documents/:ref`. An eighth More to try item and a README line lead visitors to it.

## Boundaries & Constraints

**Always:**
- Carry only what Lane A's `HostData` holds, after Decide's reply filter: `citations` `{documentRef, document, section, passage, chunkIndex}` and `memories` `{memoryRef, text, savedAt}`, at most 5 each, absent when empty. Chips are built by code from these arrays, never from reply text (DW-721, U-280).
- Only a usable reply (the `Replied` path that reaches `Checked`) is read; Busy, SessionBroken, fallback and unusable answers carry nothing. Bad JSON or a wrong shape adds nothing and never fails the turn.
- `Conversation.Checked` and `RenderChecks` stay byte-identical (DW-383: `Eval.In.Render` mirrors `Checked`).
- Passage, memory and document text render as plain text (interpolation, `white-space: pre-wrap`), never `innerHTML`; a passage shows at most 6 lines (CSS line clamp, not a fixed height: `floor-sources.test.mjs`).
- Chips are native buttons with `aria-haspopup="dialog"`; each chip's accessible name includes its document or memory; popovers use `shared/popover.ts` (`Popovers.show`), named by their heading; nothing relies on colour alone; text resizes to 200%.
- Labels state provenance only: never "used", "relied on" or "based on" (U-280). No new public string is committed before the Planner rules it (see `## Public Text`).
- Live-event keys camelCase; nested shapes are `OcuTalon.Live.Payload.Part` classes and `web/src/app/live/payloads.ts` is regenerated, never hand-edited (AD-12).
- `GET /v1/documents/:ref` reads through `Ownership.Document(ref, sessionRef)` (the check DELETE uses): a document the session cannot see answers 404 `not_found` exactly like a missing one. It submits nothing and publishes nothing; it inherits `Web.Api`'s role check and browser envelope. No new role, grant or privilege.
- Non-ASCII in code via escapes (`'§'`, `'…'`), Rule 14. Every change to a contended file is an additive block (Design Notes lists them).

**Never:**
- Never edit a Lane A class or test (U-177): `src/bridge/**`, `Tools/**`, `Agent/**`, `Docs/**`, `Memory/**`, `Checks/**`, `Eval/**` and their tests. Never duplicate `Docs.Reply.Apply`'s none-line logic in Lane B or the page.
- No Telegram or Simulated phone rendering of citations or memories; no change to `Channel/**/Out.cls`.
- No memory REST route, no new memory lookup; the "From memory" popover shows only what the chat message carries (it does not duplicate the Memory card).
- No new CI unit, group or shard area; no change to `ci/units.sh`.
- No seeded/sample document on the online demo (out of scope; see Design Notes, escalation).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Cited answer | usable Reply, `HostData.citations` 2 entries (same doc, sections A and B) | Turn.Citations holds both; Outbound and `chat.message`/`/v1/state` carry `citations`; page shows 2 chips "{document} § {section}" after the text and check rows | none |
| Same section twice | two citations, same `documentRef` and `section`, different `chunkIndex` | one chip; its popover shows both passages in order, each clamped to 6 lines | none |
| Section-less passage | citation with `section` "" | chip label is the document name alone | none |
| Memory recall | `HostData.memories` 1 entry | one "From memory" chip; accessible name "From memory: {text, cut to 80 chars}"; popover heading "From memory", the text, "Saved {when}" (`pageWhen`) | none |
| Both kinds | citations and memories | citation chips first, then memory chips, in one `role="group"` named "Sources" | none |
| None-line, no citations (DW-721 a) | reply text "None of your documents cover that.", no `citations` | text shown as sent, no chip | none |
| Citations with none-line in model text (DW-721 b) | model text holds the sentence + citations, through the real `ReplyGuard.Filter` | stored/shown reply lacks the sentence; chips shown | guard is Lane A's, carried unchanged |
| Bad HostData | not JSON, not an object, `citations` not an array, entries missing fields, 7 entries | malformed entries dropped (non-string text fields), at most 5 kept, nothing stored when none valid; checks unaffected | `$$$LOGWARNING`, turn ends normally |
| Not a usable reply | Busy, SessionBroken, Fallback, error | no citations/memories on the turn | none |
| Old turn rows | rows saved before this story | `citations`/`memories` absent; page renders as today | none |
| Open document | press "Open document" | navigates to `#/documents?doc=<documentRef>`; the page shows a panel with the document's name as heading and its text; focus on the panel heading | none |
| Document gone / other owner | `GET /v1/documents/<ref>` for a removed ref or another session's document (online-demo owner) | 404 `not_found`; page shows "Couldn't open that document. It may have been removed." | no text leaks |
| Route failure | read error | 500 `server_error`; page shows the same failure line | logged |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` -- `Replied` :493-507 (calls `Checked` at :506, then `Conclude`); `Checked` :513-527 and `RenderChecks` :530-533 (DO NOT CHANGE, DW-383); `Conclude` :602-616; `Announce` :620-628 (`ChatMessage.FromRow`); `Tell` :632-650 (copies CheckKey/CheckRows at :640-641); class doc bullets :26-31. Contended (Epic 41): additive only.
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls` -- `%Persistent`, explicit `Storage Default`, values 1-23 (:93-172, last `SessionRotated` = 23 at :162); `CheckKey` :71, `CheckRows` :75 (`MAXLEN=""`); pattern for "rows saved before hold no value" :63-65. Lane B (spine Tables :1338).
- `src/ocutalon/cls/OcuTalon/Msg/Outbound.cls` -- `CheckRows` :25 (storage value 7), `CheckKey` :31 (value 9); new properties take value 10+. Read by `Channel/Telegram/Out.cls:158` (checks only); WebChat Out records a Delivery only (`Channel/WebChat/Out.cls:31-32`).
- `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls` -- properties :6-58 (`CheckKey` :55, `Checks` :58 `list Of Part.CheckRow`); `FromRow` :66-90 (checks at :86-88). Reused by `/v1/state` `ChatItems` (`Web/Api.cls:1163-1170`), so reload shows the same.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/CheckRow.cls` -- sibling to extend in shape: properties with `%JSONFIELDNAME`, `ListFromJSON(json)` :19, private `Text` :43.
- `src/bridge/cls/OcuTalon/Bridge/Citations.cls` (read-only, Lane A) -- citation shape :8-10,20-26; CITEFLOOR 0.4 :20, MAXCITATIONS 5 :23. `src/ocutalon/cls/OcuTalon/Tools/MemoryTools.cls:153-162` (read-only) -- memory shape, `savedAt` = `Data.Memory.SavedAt` (UTC to the second, same format as `Turn.CreatedAt`).
- `src/ocutalon/cls/OcuTalon/Checks/ReplyGuard.cls:30-40` and `Docs/Reply.cls:16-41` (read-only) -- the filter that strips the none-line when citations exist; called from `Bridge/Process/Decide.cls:1371`; HostData passes through unchanged (:1405).
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls` -- URL map :55-58; `Remove` :122-150 (pattern: `Ownership.SessionRef`, `Ownership.Document`, 404 `not_found` with `MESSAGENOTFOUND`); `List` :72-90 (`ServerError`, `CONTENTTYPE`). Not contended (Epic 35 edits `Web/Api.cls`, which this story does not touch).
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:366-374` -- `Document(ref, sessionRef)`: own, or on a local install owner `instance`. `Data/Document.cls:43` `Text` stream; `:47` `Sections` ("" for a passage under no heading).
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- `Present` / `Ids` :26-45 (feature ids of the More to try panel); `Test/Demo/Features.cls:52-60` pins the mapping.
- `web/src/app/chat/ocutalon-reply.ts` -- template: text :57-81, `app-check-rows` :82-84, `app-decision-strip` :86-95; input `turn` :193. Silent file (`announce-focus-sources.test.mjs:94`).
- `web/src/app/chat/chat-view.ts` -- `TurnView` :110-137 (checkKey/checks :132-134); `chatView` copies at :392-397. Contended (23.6): additive only.
- `web/src/app/shared/popover.ts` -- `Popovers.show({trigger, content, viewContainerRef, labelledBy})` :7-15,:73; role dialog :89-90; Esc :100, outside :107, focus-out :167; `focusFirst` :217 (selector includes `[tabindex]:not([tabindex="-1"])`). Usage pattern: `web/src/app/shared/trace-link.ts:126-134,183-215`.
- `web/src/app/chat/page-time.ts` -- `pageWhen` :183 (the Memory card's date format, `rail/memory-card/memory-card.ts:255`).
- `web/src/app/icon/icon.ts` -- `IconName` union :4-29, `@switch` of Lucide paths :49+; no `file-text` yet.
- `web/src/styles/tokens.css` (generated, do not edit) -- `--citation-chip-*` :547-554 (dark :775-777, :998-1000).
- `web/src/app/documents/documents-page.ts` (315 lines) and `documents-view.ts` (`DOCUMENTS_TEXTS` :16-29, `empty` :21); `web/src/app/api/api-client.ts:172-191` (documents calls); route `#/documents` (`app.config.ts:22`).
- `web/src/app/guide/more-to-try-view.ts` -- `MORE_TO_TRY_TEXTS` :21-69 (documents :56-61), `MoreToTryAction` :75, `MORE_TO_TRY_ITEMS` :87-95, header count :2-3 and :86; `more-to-try.ts:36-39` (item-number comment), :68-69 (`documents` action is a `routerLink="/documents"` link). Contended (23.6): additive.
- Count/text pins: `web/scripts/more-to-try-view.test.mjs:64-66,77,87,89,95,180,198,202-211`; `web/e2e/guide/more-to-try.spec.ts:61-62 (FOUR/SEVEN), 64-103 (ITEMS oracle, documents :95-97), K3 :267-273`; `web/scripts/ux-strings.test.mjs:181,441-443`, `IMPORTED` :41-71, `SOURCES` :172, char allow-list :956 (U+00A7 not allowed yet).
- `web/e2e/support/iris.ts` -- `SeedTurn` :277-293, `seedTurns` :397 (`CheckRows` at :426), `fixtureUser` :71, `irisScript`; `web/e2e/chat/decision.spec.ts` D7-D9 :308-436 (seeded check rows pattern); composer marker pattern `web/e2e/reminder/chat.spec.ts:116`.
- `ci/mock/scenarios/A/memory-save.json`, `memory-recall-keyword.json` -- real memory save and recall through the mock; `docker/tests/test-session-data.sh:123-136,260` drops saved AI sessions between marker turns (`RunnerFixture.DropSince`).
- Tests to extend: `Test/Core/ConversationTurns.cls` (`TestCheckRowsFromRender` :1591, `TestOutboundCarriesTheDecision` :1558, `TestBusyAndBrokenRepliesAreNotChecked` :1682; `DecideDouble`), `Test/Live/Payloads.cls` (`TestFromRowBuilders` :608), `Test/Web/Api.cls` (`TestStateBody` :103), `Test/Web/DocumentsApi.cls` (`TestDispatch` :80, `TestRemove` :589), `Test/Data/Tables.cls` (Turn columns :395-404), `Test/Msg/Contracts.cls` (Outbound :210), `Test/Demo/Features.cls`; web `chat-view.test.mjs:314-327`, `documents-view.test.mjs`.
- `README.md` -- L30 "seven more things to try"; "### New since 1.0.0" L32, bullets L36-41 (L37 documents). `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- More to try block :242-255 (count :248, item 6 :251, controls :253); citation chip :348; memory :977; answers :982; Documents empty :391.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure on the lane-B warm stack, record each result as a "Task 0 results" bullet under `## Design Notes`): (a) `Data.Document.Text` holds the text for a ready Markdown, PDF and Word document (one `iris_sql_query`/class call on the warm stack); (b) through the composer and the CI mock, `[[mock:memory-save]]` then `[[mock:memory-recall-keyword]]` gives a Reply whose `HostData.memories` is non-empty; if the mock does not read the second marker on a continued AI session, the e2e drops the saved AI sessions between the turns as `test-session-data.sh:123-136` does; (c) the two chromium fixture users the e2e uses each hold exactly `OcuTalonUser`.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Turn.cls` -- add `Citations` and `Memories` `%String(MAXLEN = "")` (JSON arrays as `HostData` carries them; rows saved before hold no value); storage values 24 and 25 appended -- the turn is the record `chat.message` and `/v1/state` render from.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Outbound.cls` -- add `Citations` and `Memories` `%String(MAXLEN = "")` (next storage values) -- AC "on the outbound reply"; visible in Visual Trace's message body.
- [ ] `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` -- in `Replied`, after `Do ..Checked(...)`, add `Do ..Sourced(turn, answer.HostData)`; add private `Sourced` (parse HostData; for `citations` keep entries with string `documentRef`, `document`, `passage`, string `section` ("" allowed) and numeric `chunkIndex`; for `memories` entries with string `memoryRef`, `text`, `savedAt`; at most 5 each; set the Turn field only when at least one entry is kept; Try/Catch -> `$$$LOGWARNING`); in `Tell` copy both to the Outbound; add one class-doc bullet. Leave `Checked`/`RenderChecks` byte-identical.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Part/Citation.cls`, `Part/Memory.cls` (new) -- `{documentRef, document, section, passage, chunkIndex}` and `{memoryRef, text, savedAt}`, each with `ListFromJSON` in `Part.CheckRow`'s shape.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls` -- `Citations` (`citations`) and `Memories` (`memories`) lists filled in `FromRow` from the row; then `npm --prefix web run payloads` regenerates `web/src/app/live/payloads.ts`.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Documents.cls` -- route `<Route Url="/:ref" Method="GET" Call="Text"/>`; `Text(ref)`: sweep as the others do, `Ownership.SessionRef`, `Ownership.Document`; no row -> 404 `not_found`; else 200 `{"ref","name","text"}` (text read from the stream); a failed read -> 500. Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- new id `sources`, listed last when memory or documents is built; update the doc comment.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls` -- add `TestSourcesCarried` (turn fields, `chat.message` payload, the Outbound sent to Notify), `TestSourcesShape` (bad JSON, non-array, malformed entries dropped, 7 -> 5, checks still rendered), `TestSourcesNotOnFallbacks` (Busy, Broken, Fallback, error), `TestNeverBoth` (DW-721: text run through the real `ReplyGuard.Filter(text, hostData)` before the double delivers it: with citations the stored ReplyText lacks the none-line and citations are carried; without citations the sentence stays and nothing is carried).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`, `Test/Web/Api.cls`, `Test/Data/Tables.cls`, `Test/Msg/Contracts.cls`, `Test/Demo/Features.cls` -- update shape pins for the new payload keys, columns, Outbound properties and the `sources` id; add a `/v1/state` assertion that a turn with sources lists them.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls` -- `TestText`: own, instance-owned (local), another session's (404), unknown (404), empty ref, read failure (500), nothing submitted; `TestDispatch` gains GET `/:ref`.
- [ ] Planner conditions (2026-11-09): (a) the citation chip's accessible name is `{document}, section {section}` (`{document}` alone when the section is ""), never containing U+00A7, while the visible label stays `{document} § {section}`; pin it in `answer-sources-view.test.mjs` AND in `web/e2e/chat/sources.spec.ts` (getByRole button name). (b) The document text on the Documents page (and passage/memory text in popovers) renders as PLAIN, ESCAPED text (Angular interpolation, never `innerHTML`/`[innerHTML]`, never a Markdown renderer); add one test with markup in a document: a document whose text holds `<b>bold</b> <script>window.__x=1</script> **md** # Heading` shows those characters literally on the Documents page (e2e: `textContent` equals the raw text, no `b`/`script`/`h1` element created, `window.__x` undefined) and in a citation passage popover (view or e2e).
- [ ] `web/src/app/icon/icon.ts` -- add `file-text` (Lucide paths).
- [ ] `web/src/app/chat/answer-sources-view.ts` (new, framework-free) -- `ANSWER_SOURCES_TEXTS` and pure helpers: citation chips grouped by `documentRef`+`section` in first-seen order (label per `## Public Text`), memory chips (accessible name with the text cut to 80 chars + `…`), at most 5 of each kind.
- [ ] `web/src/app/chat/answer-sources.ts` (new) -- `role="group"` "Sources" row of citation then memory chip buttons (citation chip: `--citation-chip-*` tokens + `file-text` icon; memory chip: the same tokens, no icon); popovers via `Popovers` (citation: heading = chip label, passages clamped to 6 lines, `routerLink="/documents" [queryParams]="{doc: documentRef}"` "Open document"; memory: heading "From memory", text in a `tabindex="0"` block so focus enters, "Saved {when}" via `pageWhen`).
- [ ] `web/src/app/chat/chat-view.ts` -- `TurnView` gains optional `citations`/`memories`, copied in `chatView` when non-empty (additive lines beside `checks`).
- [ ] `web/src/app/chat/ocutalon-reply.ts` -- render `<app-answer-sources>` after `app-check-rows`, inside the reply branch, when the turn has either.
- [ ] `web/src/app/api/api-client.ts`, `web/src/app/documents/documents-page.ts`, `documents-view.ts` -- `documentText(ref)`; the page reads the `doc` query param, fetches the text and shows a region (heading = name, focus moved to it, text `pre-wrap`, "Close" removes the param); 404/500 show the failure line. `empty` string unchanged (DW-976).
- [ ] `web/src/app/guide/more-to-try-view.ts`, `more-to-try.ts` -- DW-975: `documents.lookFor` per `## Public Text`; append item `sources` LAST (`action: 'documents'`, existing button text); header comments say eight.
- [ ] `web/scripts/answer-sources-view.test.mjs` (new), `chat-view.test.mjs`, `documents-view.test.mjs`, `more-to-try-view.test.mjs`, `ux-strings.test.mjs` -- view tests incl. DW-721 both directions; replace literal count/order pins with registry-derived ones (keep the independent text oracle); register `answer-sources-view.ts` in `IMPORTED`, each new string in `SOURCES` (`ux` for UX-sourced texts, `ruled` keyed by the Planner ruling's id for the others), allow U+00A7 in the char rule.
- [ ] `web/e2e/support/iris.ts` -- `SeedTurn` gains `citations`/`memories` (written to the Turn's columns).
- [ ] `web/e2e/chat/sources.spec.ts` (new, chromium project) -- seeded cited, memory and none-line turns; chip names, popover rules (Esc/outside/Tab-away, focus return), 6-line clamp, "Open document" -> Documents page text; real-HTTP route checks as two `OcuTalonUser`-only fixture users; the memory chip through the real composer and mock.
- [ ] `web/e2e/guide/more-to-try.spec.ts` -- K3 expected ids from `MORE_TO_TRY_ITEMS` (imported), oracle gains the new item and the new item 6 lookFor.
- [ ] `README.md` -- L30 "seven" -> "eight"; append the new bullet LAST under "New since 1.0.0".
- [ ] `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- More to try block: "eight items", item 6 new look-for with an `[AMENDED ...]` marker that names the commit's date, Story 20.2 and the Planner ruling's id, new Item 8, controls line names items 6 and 8 as Documents links.

**Acceptance Criteria:**
- Given a usable Reply whose HostData carries citations and memories (Lane A's shape), when `Conversation` records the turn, then the Turn, the Outbound sent to Notify and `chat.message` (and `/v1/state`) carry them after the reply filter, with `Checked` unchanged and check rows still carried (AD-6, AD-28, AD-30).
- Given a reply with citations in the web chat, when it shows, then it ends with citation chips styled by the `citation-chip` tokens with the `file-text` icon and "{document} § {section}" (fixture "Results runbook § Rotating the certificate"), and pressing one opens a popover with the passage (at most 6 lines), the document, the section and "Open document" (FR-42, UX-DR144, UX-DR106, UX-DR38).
- Given the citation popover, when the user presses "Open document", then the Documents page shows that document's name and full text, through `GET /v1/documents/:ref` (FR-42).
- Given `GET /v1/documents/:ref` over real HTTP, when an `OcuTalonUser`-only fixture user (local install) asks for an instance document it gets 200 with the text; when user B asks for a document owned by user A's session it gets 404 `not_found` while A gets 200; an unknown ref is 404 (Planner standing rule (i) and (iii)).
- Given a reply that recalled a memory, when it shows, then it carries a "From memory" chip whose popover shows the remembered text and the date it was saved, and the chip appears on a real turn driven through the composer and the CI mock (FR-41, UX-DR144; Integration AC: the web chat consumes `chat.message`'s `memories`).
- Given keyboard and screen-reader use, when the user Tabs to a chip, then it is a button whose accessible name includes its document or memory, Enter opens its popover with focus inside, Esc / an outside press / Tab-away closes it and returns focus to the chip, state never relies on colour alone, and the fixed-strings test covers every new string (NFR-25, UX-DR38, UX-DR130, UX-DR134, UX-DR117).
- Given DW-721, when a reply says "None of your documents cover that.", then it shows no document chip, and when it has document chips, then its text never holds that sentence, with tests in both directions (Conversation through the real guard, the view, the e2e).
- Given the demo guide on an instance with documents or memory, when the visitor opens More to try, then the last item "See where an answer came from" links to the Documents page, item 6's look-for names the chip, every count (README L30, EXPERIENCE.md, the registry comment) says eight, and every count-pinning test reads the registry.
- Given README.md, when read, then "New since 1.0.0" ends with the Planner-ruled line about citation and memory chips.

## Spec Change Log

- 2026-11-09 (lead, spec gate): Planner rulings applied: `## Public Text` marked ruled (14 edited, 1a added); Tasks gain the two Planner conditions (accessible name without §; plain escaped document text with a markup test); Design Notes record the rulings and the spine rows.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):** AD-6 (HostData reaches `Conversation` on the Reply); AD-28 (check glue unchanged, carried after the guard); AD-30 (Conversation records the turn, publishes `chat.message`, sends the reply to Notify); AD-12 (publish through `Live.Publish`, Part classes, generated TS); AD-13 (route inherits role check and envelope; no CORS); AD-14 (reply goes to its channel and the web chat; Outbound only gains fields); AD-21 (documents/memories scoping: `Ownership.Document`; the "Citations and memories" convention row); AD-25 (proxy allows `/ocutalon/*`, so the new GET is reachable on the demo); AD-29/AD-33 (Lane B edits only Lane B classes; `Turn`, `chat.message`, `Conversation` are Lane B); AD-22 (CI mock only; tests in `OcuTalon.Test.<Area>`). No AC contradicts an AD.

**Consumes:** Lane A `Reply.HostData` `citations`/`memories` (Stories 34.1, 19.3, 19.4, 19.7); `Checks.ReplyGuard` + `Docs.Reply.Apply` (via Decide); `Ownership.Document`; `Data.Document.Text`; `shared/popover.ts`; `page-time.ts` `pageWhen`; the Documents page (34.2); the CI mock scenarios `memory-save`/`memory-recall-keyword`.
**Consumed-by:** the web chat (this story: `answer-sources.ts` reads `chat.message`/`/v1/state` `citations`/`memories`); the Documents page (this story: `GET /v1/documents/:ref`); Visual Trace (Outbound message body). No Telegram/phone consumer; the first would be a later Telegram story (none planned).
**Integration ACs:** the memory-chip AC (real turn through composer + mock -> Conversation -> `chat.message` -> chip) and the "Open document" AC (page -> real route -> text) are the consumer ACs (Rule 1).

**Extend, don't copy (Rule 2):** `Sourced` resembles `Checked` (parse HostData, guard, catch); a separate method is chosen so `Checked` stays identical to `Eval.In.Render` (DW-383). `Part.Citation`/`Part.Memory` follow `Part.CheckRow`'s `ListFromJSON`. `Web.Documents.Text` follows `Remove`'s ownership lookup. `answer-sources.ts` uses `Popovers` like `trace-link.ts`; dates use `pageWhen` like the Memory card.

**Ledger inbox (Rule 17):**
- Declined DW-383: 20.2 leaves `Conversation.Checked`/`RenderChecks` byte-identical (new carry is a separate method), so `Eval.In.Render`'s copy stays honest; unifying the glue into one helper is Lane A work (`Eval/**`, U-177) -- re-own to Lane A / burndown.
- DW-721: addressed (I/O rows "None-line" and "Citations with none-line", AC "Given DW-721", `TestNeverBoth`, view and e2e tests; labels per `## Public Text`; FR-41 met by "From memory").
- Declined DW-733: a hermeticity fix of `Test.Live.GuideRefresh`, unrelated to 20.2's surface; the voting-week scope admits only judge-visible work, and Epic 39 also edits the file -- re-own to burndown or Epic 39.
- DW-975: addressed (item 6 look-for restored with its three pins and EXPERIENCE.md item 6; text in `## Public Text`).
- DW-976: addressed without a string change: 20.2 makes "cited answers" true; the e2e adds a document and shows its chip and text.

**Contended files (all additive):** `Core/Conversation.cls` (one call line in `Replied`, two lines in `Tell`, one new method appended, one doc bullet; Epic 41); `web/src/app/chat/chat-view.ts` (two optional fields + copy lines; 23.6); `web/src/app/guide/more-to-try-view.ts` (one string changed for DW-975, one item appended LAST; 23.6 prepends FIRST); `more-to-try.ts` (comment only); `README.md` (L30 count + one bullet appended last; 23.6); EXPERIENCE.md More to try block (count, item 6, item 8 appended; 23.6, Epic 35). `Demo/Features.cls` may also gain 23.6's id: ours is appended last. Not touched: `Agent/Chat.cls`, `Channel/**/Out.cls`, `Msg/Catalog/*`, `Web/Api.cls`, `Web/SessionEvents.cls`, `Data/Session.cls`, `Core/CommandsIn.cls`, `Core/SessionOps.cls`, `Memory/**`.

**Count ruling:** this branch's registry has 7 items; with `sources` it has 8, so README L30, EXPERIENCE.md and the registry comment say eight. Whichever of 23.6/20.2 merges second sets the final count (nine if both). Placement proposal: `sources` LAST, after `heartbeat` (23.6 prepends, so the two hunks never overlap).

**Veto-window / escalation items (for the lead at the spec gate):**
1. Stored data (veto 3): `Data.Turn` gains `Citations` and `Memories` (copies of passage and memory text, kept with the turn under the existing turn retention and online-demo reset); `Msg.Outbound` gains the same two properties (message bodies under the Ens purge). Consequence: a memory forgotten or a document removed later stays visible in earlier answers' chips until the turn rows go. Recommended: accept (the reply text itself already persists; only the session's own chat shows them).
2. New route (no new privilege): `GET /api/v1/documents/:ref`, user route under the existing role check. Spine update for the lead (Rule 20): add its row to the routes table after `ARCHITECTURE-SPINE.md:1540`.
3. Public text: every string in `## Public Text` marked "new" needs a Planner ruling before implement.
4. Demo path (measured by reading, model behaviour inference): a visitor's online-demo session CAN produce both chips, but only by its own actions -- nothing is seeded (AD-25 golden copy; `test-session-data.sh` fresh state 0|0|0|0|0). (a) Citation: Documents page -> add a short .md/.txt -> wait for Ready -> ask about it; the chip appears only if Haiku calls `documents` and a passage scores >= 0.4 (inference). (b) From memory: More to try item 5 sends "Remember that ..."; asking "Who do I call about Results?" shows the chip only if Haiku calls `search_memories` (inference: the save taints the turn, so the next turn starts fresh with a code-written recap and must search). Neither is measurable without the real key; the Planner's release hands-on pass covers it. Not built here (smaller is better): a "sample runbook" button for visitors without a file -- the lead may raise it as a follow-up.

**Spec gate (lead, 2026-11-09):** passed (Integration ACs present; AD ids mapped; ledger inbox complete: DW-383 and DW-733 re-owned to `burndown` by=spec_gate; no decision dependency; destructive checks on lane-B throwaways only). Sent to the orchestrator before any implement: the `## Public Text` list (PUBLIC TEXT), veto-window items 1 (stored data) and 2 (new user route), the spine rows (REST surface row for `GET /api/v1/documents/:ref`; the Live events convention's `chat.message` sentence gains citations and memories), and item 4 (demo path). Implement waits for those rulings; each ruling is recorded here when it arrives. Spine rows: written 2026-11-09 by orchestrator ruling (decide) as two separate marked rows (Consistency Conventions `Citations and memories on the page`; REST surface `GET /api/v1/documents/:ref`), lint at baseline.

**Planner rulings (2026-11-09, relayed by the orchestrator, recorded):** A. Public text 1-13 and 15 approved as drafted; item 8 goes LAST; the count follows the registry; text 14 approved as edited (verbatim in `## Public Text`); accessibility condition on text 1: accessible name `{document}, section {section}` (no § sign), visible label unchanged, pinned in a test; `No documents yet. Add a runbook to get cited answers.` KEEP; README L37 "names the document and section it used" KEEP. B. Veto 1 (Citations/Memories on `Data.Turn` and `Msg.Outbound`) ACCEPTED, no scrub on forget; veto 2 (`GET /api/v1/documents/:ref`) ACCEPTED as specified with the real-HTTP route-rule tests, on condition the document text shows as plain, escaped text, never rendered HTML or Markdown, with one test with markup in a document. C. Spine rows: the orchestrator's plain-union ruling agreed (written e52f7e75). D. The Planner does the hands-on demo pass after deploy. A "sample runbook" button is a separate next story (20.3), NOT part of 20.2.

**Decided in-stage:** one memory chip per memory (DW-721 "at most 5 each" chips); citation chips grouped by document+section, passages listed in the popover; section-less label = document name; memory chip shares the citation-chip tokens without an icon (DESIGN.md has no memory-chip token); memory popover focus lands on its `tabindex="0"` text block; "Open document" uses `#/documents?doc=<ref>`; route body `{"ref","name","text"}`; feature id `sources` listed when memory or documents is built; U+00A7 added to `ux-strings.test.mjs`'s allowed characters (UX text uses it).

## Public Text

RULED by the Planner 2026-11-09 (see Design Notes, "Planner rulings"): 1-13 and 15 approved as drafted; 14 approved as edited below; 1a added. Use every text verbatim. Sources: UX = EXPERIENCE.md/DESIGN.md; ruled = owner ruling U-280.

| # | Text (verbatim) | Target | Source |
|---|---|---|---|
| 1 | `{document} § {section}` (chip label and citation popover heading; section "" gives `{document}` alone) | `web/src/app/chat/answer-sources-view.ts` | UX: DESIGN.md:863, EXPERIENCE.md:590 (section-less form: new, needs ruling) |
| 1a | `{document}, section {section}` (citation chip's ACCESSIBLE NAME; section "" gives `{document}`; no § sign) | `answer-sources-view.ts` | Planner ruling 2026-11-09 (accessibility condition on text 1) |
| 2 | `Sources` (accessible name of the chip group) | `answer-sources-view.ts` | ruled U-280 ("Sources" allowed); placement new, needs ruling |
| 3 | `Open document` | `answer-sources-view.ts` | UX: EXPERIENCE.md:348 |
| 4 | `From memory` (chip text, memory popover heading) | `answer-sources-view.ts` | UX: EXPERIENCE.md:977, UX-DR144 |
| 5 | `From memory: {memory}` (memory chip accessible name; text cut to 80 characters with "…") | `answer-sources-view.ts` | new, needs ruling |
| 6 | `Saved {when}` ({when} from `pageWhen`, e.g. "Saved Monday at 14:13") | `answer-sources-view.ts` | new, needs ruling |
| 7 | `Close` (closes the document text) | `web/src/app/documents/documents-view.ts` | new, needs ruling |
| 8 | `Couldn't open that document. It may have been removed.` | `documents-view.ts` | new, needs ruling |
| 9 | Item 6 look-for: `On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat, and look for the chip under the answer that names your file and its section.` | `web/src/app/guide/more-to-try-view.ts` (`documents.lookFor`), its pins, EXPERIENCE.md:251 | new (DW-975), needs ruling |
| 10 | Item 8 label: `See where an answer came from` | `more-to-try-view.ts` (`sources.label`), EXPERIENCE.md More to try | new, needs ruling |
| 11 | Item 8 look-for: `Under an answer from your documents, press the chip that names the document and section to read the passage, then Open document to see the whole file. Under an answer that recalls something you asked it to remember, press From memory to see what it remembered and when.` | `more-to-try-view.ts` (`sources.lookFor`), EXPERIENCE.md | new, needs ruling |
| 12 | Item 8 control: `Open the Documents page` | `more-to-try-view.ts` | UX (existing item 6 control, reused) |
| 13 | README L30: `seven more things to try` -> `eight more things to try` | `README.md:30` | count ruling (binding) |
| 14 | README bullet, appended last (Planner-edited, verbatim): `- **Where an answer came from.** An answer from your documents ends with a chip for each source that names the document and section: press it to read the passage, or open the whole document on the Documents page. An answer that recalls a memory carries a From memory chip that shows what was remembered and when. Try it: More to try, *See where an answer came from*.` | `README.md` "New since 1.0.0", after L41 | Planner ruling 2026-11-09 (edited) |
| 15 | EXPERIENCE.md: `There are eight items` (was seven); Item 8 entry with texts 10-12; controls line: `Items 6 and 8's controls are links to the Documents page.` | EXPERIENCE.md :248, :253 | count ruling + new, needs ruling |
| -- | Unchanged: `No documents yet. Add a runbook to get cited answers.` (DW-976, now true); README L37 "names the document and section it used" (U-280 binds chip labels; the Planner may rule it) | `documents-view.ts:21`, `README.md:37` | -- |

## Verification

Lane variables on every `ci/iris.sh` / `ci/warm.sh` call (written here as on the command line): `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=20 stage=implement'`, abbreviated `$LANE` below. Warm tag `e20s2iw`, fresh tag `e20s2i`. One command per tool call, each under about 150 s; IRIS only on lane-B throwaways (warm or fresh), never the dev slot for destructive checks.

**Commands:**
- `$LANE OCUTALON_RUN_TAG=e20s2iw ci/warm.sh up` -- once at stage start; `ci/warm.sh down` at stage end, also after a failure.
- (loop) `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e20s2iw ci/iris.sh class OcuTalon.Test.Core.ConversationTurns` -- passed; likewise one call each for `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Web.DocumentsApi`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Demo.Features`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Msg.Contracts`.
- (loop) `npm --prefix web run payloads` -- regenerates `payloads.ts` after any Payload class change.
- (loop) `node --test web/scripts/answer-sources-view.test.mjs web/scripts/chat-view.test.mjs web/scripts/documents-view.test.mjs web/scripts/more-to-try-view.test.mjs web/scripts/ux-strings.test.mjs` -- all pass.
- (loop) e2e: `$LANE OCUTALON_RUN_TAG=e20s2i ci/iris.sh build`; `npm --silent --prefix web run e2e -- --list --reporter=json > "$SCRATCH/chromium.json"` and `node web/scripts/e2e-part.mjs k/n "$SCRATCH/chromium.json"` (`$SCRATCH` = a folder of the session scratchpad, outside the repo) to pick n (e.g. 20) and the k that holds `e2e/chat/sources.spec.ts`; then `$LANE OCUTALON_RUN_TAG=e20s2i ci/iris.sh live sign-in --part k/n` -- the part passes. The same for `e2e/guide/more-to-try.spec.ts` with `npm --silent --prefix web run e2e:sign-in-3 -- --list --reporter=json` and `ci/iris.sh live sign-in-3 --part k/n`. Teardown: `$LANE OCUTALON_RUN_TAG=e20s2i ci/iris.sh teardown`.
- (once) `npm --prefix web test`; `npm --prefix web run lint`; `npm --prefix web run build` -- each passes.
- (once) `bash ci/checks.sh` -- every block passes (class rules, README public-text and links).
- (once) `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e20s2iw ci/iris.sh shard lane-b --part k/8`, k = 1..8, one per call -- all passed (the part holding `Test.Schedule.Heartbeat` can run past 150 s: if moved to the background, wait in bounded foreground polls).
- Mutations to record (Rule 19), one per AC, e.g.: drop the `Sourced` call -> `TestSourcesCarried` red; drop the `Tell` copy -> its Outbound assertion red; `FromRow` skips memories -> `Test.Live.Payloads` red; route skips `Ownership.Document` (reads by ref) -> `TestText` other-session case and the e2e isolation check red; chip label without section -> view test red; popover without focus return -> e2e red; reading the none-line in the view -> both-directions test red; registry item removed -> registry-derived count tests red.

**Shared surfaces:** `chat.message` and `/v1/state` chat item keys (`payloads.ts`, `Test.Live.Payloads`, `Test.Web.Api`); `Data.Turn` columns (`Test.Data.Tables`); `Msg.Outbound` properties (`Test.Msg.Contracts`); the Documents URL map (`Test.Web.DocumentsApi` `TestDispatch`); `Demo.Features` ids and `guide.features` (`Test.Demo.Features`, `more-to-try.spec.ts`); the More to try registry and its count (`more-to-try-view.test.mjs`, `more-to-try.spec.ts`, README L30, EXPERIENCE.md); `ux-strings.test.mjs` `IMPORTED`/`SOURCES`/allowed characters; `IconName`; `TurnView` (`chat-view.test.mjs`); `SeedTurn`. Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
