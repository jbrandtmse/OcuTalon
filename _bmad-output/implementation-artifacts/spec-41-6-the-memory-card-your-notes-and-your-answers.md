---
title: 'Story 41.6: The Memory card: your notes and your answers'
type: 'feature'
created: '2026-11-08'
status: 'done'
baseline_revision: 'c0e3b6d01d7ec443f23d6c6ba56115d1444bcc17'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      Story 41.5's NZ1 and NZ2 (web/e2e/memory-noise.spec.ts) fail when the instance's UTC hour is below 10.
    evidence: |-
      The page renders the mark time as "1:10" and the cases expect "01:10". They went red in this story's runs of `ci/iris.sh live sign-in-3 --part 6/6` after 00:00 UTC and green before it. Not caused by this story; the part holding memory-card.spec.ts shares the unit, so CI's shards-5 group is red in those hours.
    location: >-
      web/e2e/memory-noise.spec.ts:116 and :147
    severity: medium
---

<intent-contract>

## Intent

**Problem:** A person can't see what OcuTalon remembers about them. The daily notes (41.3) and the precedents (41.2, written by 41.5) reach the model (41.4), but no page shows them, and the person can't forget an answer.

**Approach:** Add a Memory card to the status rail, in its own component under `web/src/app/rail/memory-card/` and with one slot in `rail-view.ts`, placed after the Heartbeat checklist and before Persona. The card has two ARIA tabs:
- **Notes** shows today's and yesterday's lines from `GET /api/v1/memory/notes`, as the route serves them.
- **Your answers** lists `GET /api/v1/memory/precedents`. Each row has a Forget button. Forget asks first in a modal dialog, then sends `DELETE /api/v1/memory/precedents/:ref` and removes the row at once.

The card reads only through `ApiClient`, the page's one HTTP client, and shows only what the session's own routes return.

## Boundaries & Constraints

**Always:**
- Every visible string and accessible name is EXPERIENCE.md's (Later Steps › Personality, the Memory card, lines 1049-1053), the epics AC's (Story 41.6), or a string the Contest Planner rules from `## Design Notes` › PUBLIC TEXT needed. Each string is used exactly as written. The note lines are 41.3's approved formats, shown as served, one line per list item.
- The card shows only what the routes answer for the CSP session's own session (AD-4). It never filters, sorts or rewrites rows, keeps no copy across page loads, and holds no SessionRef.
- An empty text shows only after a successful read with nothing in it. While a read is pending or after it fails, that panel shows its intro line and nothing else, so a failure never reads as "nothing" (AD-28; the sibling is the Persona card's heading-only rule). A failed read is tried again the next time its tab is selected.
- Forget sends only the delete route. A 200 or a 404 (gone either way) closes the dialog and removes the row at once, with no re-read. Any other answer leaves the dialog open, shows its failure notice, and keeps the row.
- Labels and keyboard (NFR-25):
  - The tabs follow the device panel's ARIA tabs pattern: `role="tablist"` labelled by the Memory heading; two `role="tab"` buttons with `aria-selected` and roving `tabindex`. ArrowLeft and ArrowRight move focus to the other tab, wrap, and select it. Each tab panel is `role="tabpanel"`, labelled by its tab.
  - Forget is a native button. Its visible text is "Forget" and its accessible name includes the row's summary.
  - The dialog follows `documents/remove-dialog.ts`: it is named by its heading (the question), and focus starts on that heading. Esc and Cancel close it and return focus to Forget. After a confirmed Forget, focus goes to the Memory heading (`#rail-heading-memory`).
- The rail's existing sections keep their order and their tests: Telegram, the four lists, Heartbeat checklist, then Memory, then Persona, which stays last.
- The card adds no element with class `empty` or `hint` to the rail, no h3 other than its section heading, no count, and no live region. `demo-path/01-page.spec.ts` reads `rail.locator('.empty')`, `.hint`, `h3 > [aria-hidden]` and the rail's live regions.
- Source text is ASCII. Non-ASCII characters are written as escapes (Rule 14). Comments state the contract, never the history.

**Never:**
- Edit a Lane A class or test (`Agent/**`, `Eval/**`, `Test/Agent/**`, `Test/Eval/**`), `ci/mock/**`, `ci/units.sh`, `release/**`, `eval/run.sh`, IPM artifact or check scripts, the spine, EXPERIENCE.md or DESIGN.md. Reading Lane A classes through `irisScript` in a test (`$Parameter`, `Test.Contract.Mock.LogSince`, `RunnerFixture`) is fine.
- Edit `web/src/app/api/api-types.ts`, `web/e2e/support/*` files that exist today, `src/ocutalon/cls/OcuTalon/Web/Api.cls` or `Test/Web/Api.cls` (contended). A NEW file under `web/e2e/support/` is fine.
- Create `web/src/app/api/memory-types.ts` or touch 41.5's files (`chat/noise-*`, `notice-card.ts`, `phone/*`). Depend on any 41.5 code.
- Add a second HTTP client. `inject(HttpClient)` stays in `api-client.ts` only (`api-client-sources.test.mjs:83-91`).
- Change any demo-path spec beyond the one ruled edit in Clarification 1.
- Show, link or rewrite anything of another session's rows or of eval-seeded rows. Write a precedent from product code, or add a precedent writer outside `PrecedentOps`. Test fixtures may save and delete rows directly, as `api/memory.spec.ts` does.
- Add an icon, chip, count or animation that DESIGN.md does not give.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Rail | Signed in, any install | One more h3 section than today, in order: Telegram (when included), the four lists, Heartbeat checklist, Memory, Persona (eight with Telegram). Memory has no count. Its card shows the tabs "Notes" (selected) and "Your answers" | none |
| Notes, both days | Notes routes answer lines for today and yesterday | The Notes panel shows the intro line, then the label "Today" with today's lines in served order, then "Yesterday" with yesterday's lines | none |
| Notes, today empty | Today's route answers `lines: []` | Under "Today": "Nothing recorded yet today." | none |
| Notes, yesterday empty | Yesterday's route answers `lines: []` | Under "Yesterday": the ruled yesterday empty text (PUBLIC TEXT) | none |
| Notes, cut | A served line `(more not shown)` | Shown as a line, as served | none |
| Notes read fails | 500, a network error, or not yet answered | The intro line only. No day label, no empty text | Tried again when Notes is next selected |
| Answers listed | The list route answers rows | The intro line, then one row per served row, in served order. Title: `summary`. Meta: when (`pageWhen` of `answeredAt`), channel (omitted when ""), answer word, joined by the rail separator. Then Forget | none |
| Answers empty | `precedents: []` | The intro line, then the ruled answers empty text (PUBLIC TEXT) | none |
| Answers read fails | 500, a network error, or not yet answered | The intro line only | Tried again when Your answers is next selected |
| Tool row | A row with `channel` "" (keyed `tool:<ToolName>`, never read in this release, DW-922) | Listed and forgettable. Its detail line is the ruled tool note (PUBLIC TEXT) | none |
| Unknown answer value | `answer` not `noise`, `approved` or `rejected` | The value shown as served | none |
| Forget, confirmed | The delete route answers 200 | The dialog closes, the row leaves, and focus goes to the Memory heading. The table row is gone, and the next decide request for that sender carries no precedent | none |
| Forget, already gone | The delete route answers 404 | As 200: the dialog closes and the row leaves | none |
| Forget fails | 500, 501, or a network error | The dialog stays open with the ruled failure notice (PUBLIC TEXT). The row stays | The person may retry or Cancel |
| Forget cancelled | Esc, Cancel, or a backdrop press | The dialog closes, nothing is sent, and focus returns to that row's Forget | none |
| Keyboard | Tab to the selected tab, then ArrowRight or ArrowLeft | Focus and selection move to the other tab and wrap. The panel changes and the newly selected tab is read again | none |
| Drawer band (1024-1279px) | The rail is open as a drawer when Forget opens the dialog | The dialog opens over the page. Esc or Cancel returns focus to Forget in the still-open drawer (inference: Layout's drawer handling is unmeasured; the test decides) | none |
| Isolation | Another session has a precedent row and a turn today. An eval-seeded row exists | The README account's card shows neither the other session's row nor its note line, and no eval row (AD-4, AD-21 as amended) | none |

</intent-contract>

## Code Map

Paths are under `web/` unless given in full. Line numbers are at `630efe7d`.

**New files**
- `src/app/rail/memory-card/memory-card-view.ts`: framework-free, like `persona-card-view.ts` (its header form at 1-16). It holds:
  - `MEMORY_TEXTS`, the card's fixed strings;
  - `MEMORY_HEADING_ID = 'rail-heading-memory'` (the id that `status-rail.ts:37` gives the section);
  - `answerWord(answer)`, the ruled word or the value as served;
  - `isToolRow(row)`, which is `row.channel === ''` (`Data/Precedent.cls:44`: only a tool call has no channel);
  - `metaParts(row, when)`, the meta parts that the component joins with the rail separator;
  - `forgetName(summary)`;
  - `nextTab(tab)`.

  Nothing in it builds a request.
- `src/app/rail/memory-card/memory-card.ts`: the component, `app-memory-card`.
  - It injects `ApiClient`, `Dialogs`, `ElementRef` and `Injector`.
  - On creation it reads notes for today and yesterday, and the precedents. Selecting a tab reads that tab again.
  - Its tabs follow `devices/device-panel.ts:60-80` and the key handler at `:303-313`.
  - Its rows use the rail's row pattern (`status-rail.ts` `.row` styles, which the implementer may copy into the card's own styles because component styles are scoped).
  - Forget opens `ForgetDialog` through `Dialogs.open(ForgetDialog, { labelledBy: FORGET_TITLE_ID, restoreFocus: <the pressed button> })`, the same call as `documents/documents-page.ts:222-238`.
  - On `FORGOTTEN`, it removes the row and calls `globalThis.setTimeout(() => <the Memory heading>.focus(), 0)`, as `documents-page.ts:236` does. The heading is found under the rail host by `#rail-heading-memory`.
- `src/app/rail/memory-card/forget-dialog.ts`: `ForgetDialog` and `ForgetTarget`, following `documents/remove-dialog.ts`. The heading `<h2 [id]="titleId" tabindex="-1">` holds the question. It has Cancel (`button-secondary`) and the confirm (`app-server-button variant="primary"`). The confirm calls `api.forgetPrecedent(ref)`, closes with `FORGOTTEN` on 200 or 404, and otherwise shows `app-inline-notice variant="warning"` with the failure text.
- `src/app/api/memory-card-types.ts`: type-only, following `persona-types.ts`:
  - `MemoryDay = 'today' | 'yesterday'`;
  - `MemoryNotes { day: string; date: string; lines: string[] }`;
  - `PrecedentRow { ref, answeredAt, channel, answeredChannel, summary, outcome, answer }`, all strings, in the order `Web/Api.cls:1588-1602` writes them through `Precedent.View`;
  - `PrecedentList { precedents: PrecedentRow[] }`;
  - `PrecedentForgotten { result: 'done' }`.
- `scripts/memory-card-view.test.mjs`: node tests of the view module, following `scripts/persona-card-view.test.mjs`.
- `e2e/memory-card.spec.ts`: Playwright (Task 10).
- `e2e/support/memory.ts`, the shared fixtures, moved out of `e2e/api/memory.spec.ts:27-111`:
  - `seedPrecedent(owner, fields)` and `removePrecedent(ref)`;
  - `precedentExists(ref)`;
  - `seedNoteTurn(session, text, createdAtUtc)` and `removeNoteRows(...)`.

**Files to change**
- `src/app/rail/rail-view.ts`:
  - add `memory: 'Memory'` to `RAIL_TEXTS` after `heartbeat` (57);
  - add `'memory'` to `SectionId` (86);
  - push the section `{ id: 'memory', label, heading, spoken: RAIL_TEXTS.memory, rows: [], empty: '', hint: '' }` between the heartbeat push (366) and the persona push (367);
  - in the header comment (7-9), add Memory (Story 41.6) before Persona.
- `src/app/rail/status-rail.ts`:
  - import `MemoryCard` (after 15);
  - add it to `imports` (85);
  - add `} @else if (section.id === 'memory') { <app-memory-card />` between the heartbeat branch (100-101) and the persona branch (102);
  - in the comment (66-71), name the Memory section.
- `src/app/api/api-client.ts` (contended, Epic 18 at about 10, 21 and 59-82): three methods appended at the end of the class, after `runHeartbeat` (206-208) and before the closing `}` (209). They use inline `import('./memory-card-types').X` type queries, which is 41.5's convention, so no import line changes:
  - `memoryNotes(day)`: `` this.http.get<...MemoryNotes>(`${BASE}/memory/notes`, { params: { day } }) ``;
  - `precedents()`: `` this.http.get<...PrecedentList>(`${BASE}/memory/precedents`) ``;
  - `forgetPrecedent(ref)`: `` this.http.delete<...PrecedentForgotten>(`${BASE}/memory/precedents/${encodeURIComponent(ref)}`, { body: {} }) ``, as `removeDocument` (155-157) does.
- `e2e/api/memory.spec.ts`: import the moved helpers from `support/memory.ts`. Its assertions do not change.
- `playwright.config.ts:61`: add `'memory-card.spec.ts'` to `SIGN_IN_3_FILES`. Also update its comment (55-59) and the header (15-18).
- `scripts/playwright-projects.test.mjs`: the same list (86) and the case title (119).
- The rail's shared surfaces, each a count or order edit only:
  - `e2e/rail/rail.spec.ts`:
    - the `headings` filter at 73 adds `Memory`;
    - the counts at 103 and 477 become 8;
    - the spoken list at 105 gets `'Memory'` before `'Persona'`;
    - the focusable heading count at 130 becomes 8;
    - the comments at 70-72 follow.
  - `e2e/frame/frame.spec.ts`:
    - the count at 82 becomes `RAIL_LABELS.length + 4`, with its message;
    - 87 keeps Heartbeat checklist at `nth(RAIL_LABELS.length + 1)` but loses "second to last";
    - add `nth(RAIL_LABELS.length + 2)` = Memory;
    - 88 keeps Persona last.
  - `scripts/rail-view.test.mjs`:
    - the two order cases (144-157) gain `memory`/`Memory` before `persona`;
    - the Heartbeat case (172-182) asserts that Memory, not Persona, follows it, and that it is third to last;
    - add a Memory case (no count, no rows, between Heartbeat checklist and Persona);
    - the `RAIL_TEXTS` pin near 122 gains `memory`.
  - `scripts/floor-sources.test.mjs`:
    - the key map (106) gets `'app/rail/memory-card/memory-card.ts': 'ArrowLeft and ArrowRight move between the Memory card\'s two tabs, as the ARIA tabs pattern asks (EXPERIENCE L321)'`;
    - the Arrow files (146) add the card;
    - the bindings (157) add `'app/rail/memory-card/memory-card.ts down'`;
    - the describe title (94) may name the card's tabs.
  - `e2e/floor/layout.spec.ts:508` (G4, viewport 1000x2100): raise the height only if the case goes red, because the rail has grown. Story 40.4 did the same.
  - `e2e/demo-path/01-page.spec.ts:103`: Clarification 1 only.
- Contended test inventories, edited only as Clarification 2 rules:
  - `scripts/announce-focus-sources.test.mjs` (`FOCUS_CALLS`, 124-142);
  - `scripts/ux-strings.test.mjs` (`IMPORTED` 68, `SOURCES.ux` 555, `ac` 566-586, `ruled` 587-691).

**Consumed as built (read only)**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `Precedents` (1590-1603): newest first, at most `PRECEDENTSMAX` 100, never a seeded row;
  - `ForgetPrecedent` (1609-1632): 404 `not_found` for a row the session can't see, otherwise `ForgetPrecedent` with origin `web_user`, 200 `{"result":"done"}`;
  - `Notes` (1637-1661): a missing day means today, any other day is 404, and `lines` come from `DailyNote.Build`.
- `Data/Precedent.cls`:
  - `ANSWERS` (21) is `noise,approved,rejected`;
  - `Channel` (44-45) is a `Msg.Enum CHANNEL` value or "" for a tool call;
  - `Summary` (48) is at most 80 characters;
  - `Similar` (149) is the decide-time reader.
- `Core/SessionOps.cls:427-441`: `EndPrecedents`, the sign-out drop.
- `shared/dialogs.ts` (`Dialogs.open`), `shared/server-button.ts`, `shared/inline-notice.ts`, `chat/page-time.ts:183` `pageWhen`, and the rail's `RailFormat.separator`, which `status-rail.ts` `formatAt` builds.
- `ci/mock/scenarios/A/memory-precedent.json` (41.4): the Triage reply is a tellnow JSON, matched by the marker `memory-precedent`.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` `LogMark` and `LogSince`, and `Test/Agent/RunnerFixture.cls` `ToolNames`, as `e2e/chat/try-it.spec.ts:498-517` uses them.
- `e2e/support/iris.ts`: `irisScript`, `chk`, `quoted`, `sendItem` (601), `seedOtherSession` (776), `cleanFixtureRows`. Also `e2e/support/devices.ts:188-200` (`pointKeys`, `restoreKeys`, `dropPhone`), `e2e/support/persona.ts` (`sessionRef`), `e2e/sign-in/helpers` (`README_ACCOUNT`) and `e2e/support/floor.ts` (`signInReadmeLoaded`).

**Patterns to follow**
- `e2e/heartbeat-card.spec.ts:673-701`, the HC4 integration describe: `pointKeys` in `beforeAll` with the ready check, and `restoreKeys`, `WaitRecords` and the monitor settle in `afterAll`. This spec runs in the same unit.
- `e2e/persona-card.spec.ts` PC6 and `heartbeat-card.spec.ts` `rewriteGet`: a case may rewrite one field of the real GET answer through `page.route`.

## Tasks & Acceptance

**Execution:**
1. `web/src/app/api/memory-card-types.ts`, and the three appended `ApiClient` methods. These are the card's only calls.
2. `web/src/app/rail/memory-card/memory-card-view.ts`: `MEMORY_TEXTS` with the sourced strings below, and the ruled strings once the Planner rules them. Until then, the proposals stand in, flagged in the test. Also the pure helpers.
   - Sourced strings: `notes` "Notes" and `answers` "Your answers" (EXPERIENCE 1050).
   - `notesIntro` "Built by OcuTalon from today's decisions, incidents, approvals and reminders. No model writes these notes." and `notesEmpty` "Nothing recorded yet today." (1051).
   - `answersIntro` "OcuTalon looks at these when it decides on similar items. Only your own answers are kept here." (1052).
   - `forget` "Forget" and `question` "Forget this answer? OcuTalon will stop using it." (1053).
   - `today` "Today" and `yesterday` "Yesterday" (epics.md, Story 41.6, AC 1).
3. `web/src/app/rail/memory-card/forget-dialog.ts`.
4. `web/src/app/rail/memory-card/memory-card.ts`. Template:
   - the tablist;
   - the Notes panel: intro, then for each day the label (an `h4`), and then either a `ul` of lines or the empty text;
   - the Your answers panel: intro, then a `ul` of rows (title, meta, the tool note as the detail line, Forget) or the empty text.

   Reading and failure rules are in Boundaries. The panel that is not selected is `hidden`.
5. `web/src/app/rail/rail-view.ts` and `status-rail.ts`: the slot.
6. `web/e2e/support/memory.ts`, and `web/e2e/api/memory.spec.ts` switched to it.
7. `web/playwright.config.ts` and `web/scripts/playwright-projects.test.mjs`: the sign-in-3 file.
8. The rail's shared surfaces listed in the Code Map. Then search `web/e2e`, `web/e2e-online` and `web/scripts` for any other pin that the eighth section or the new component trips (heading counts, `app-*-card` lists, source scans), and update it.
9. **Waits for the Clarification rulings:** `demo-path/01-page.spec.ts:103` (Clarification 1), and the `announce-focus-sources` and `ux-strings` edits (Clarification 2). Until they are ruled, those tests stay red on the story's head, and nothing is pushed.
10. `web/scripts/memory-card-view.test.mjs` and `web/e2e/memory-card.spec.ts`. Each case creates and removes its own rows by Ref in `finally`, and asserts only on its own rows and marked lines. The cases:
    - **MC1** (AC 1): the README account loads. The rail's eight headings are in order, with Memory between Heartbeat checklist and Persona. The tabs are `Notes` (selected) and `Your answers`, with roles, `aria-selected` and the tablist named "Memory". The Notes intro is verbatim.
    - **MC2** (AC 1): a seeded done turn today and one yesterday, each with a unique `Zz` text (created at the instance-zone noon of each day, through `Data.Time.FromLocal`). Under "Today", a line `hh:mm message (web): <today text>` shows. Under "Yesterday", the yesterday line shows. The lines of both days are each in served order, compared with the route's own answer read in the same case.
    - **MC3** (AC 1, Matrix empty rows): `page.route` rewrites the real notes answers to `lines: []` and the precedents to `[]`. The empty texts show. A route that answers 500 shows the intro only, with no empty text.
    - **MC4** (AC 2): three seeded rows of the session:
      - a noise row (`mailbox`, outcome tellnow);
      - an approval row (channel `system`, outcome "", answer approved);
      - a tool row (channel "", answer rejected).

      Your answers lists each, with its title, meta parts and answer word, and the tool row's note. Forget opens the dialog named by the verbatim question, with focus on its heading. Esc closes it with focus back on Forget, and nothing is sent. Forget, then confirm: one DELETE to the row's address, the row leaves with no re-read, focus is on the Memory heading, `precedentExists(ref)` is 0, and a reload no longer lists it.
    - **MC5** (Matrix): a confirm that `page.route` answers 500 keeps the dialog open with the failure notice, and the row stays. A confirm answered 404 removes the row.
    - **MC6** (NFR-25): by keyboard alone. Tab reaches the selected tab, ArrowRight selects and focuses Your answers, and ArrowLeft wraps back. Tab reaches Forget, Enter opens the dialog, Tab reaches Cancel and the confirm, and Enter on the confirm forgets.
    - **MC7** (Matrix, drawer): at 1100x800, with the drawer open, Forget's dialog opens, and Cancel returns focus to Forget in the open drawer.
    - **MC8** (AC 3, the demo variant): `seedOtherSession` gives another session with a precedent row and a done turn today, and an eval-seeded row (owner `eval`, a run Ref) shares the README row's key. The README card lists its own row and none of the other two. Its Notes show its own line and not the other session's. After the README row and turn are removed (as the online demo's sign-out drop does) and the page is reloaded, neither shows: the card keeps nothing across loads.
    - **MC9** (AC 4, Integration). In a describe with HC4's `beforeAll` and `afterAll`:
      1. Seed a noise row for the README session with `Channel` mailbox, `MatchKey` `zz.memcard.<n>@example.com` and a unique Summary.
      2. `LogMark`, then `sendItem` from `Zz Card <zz.memcard.<n>@example.com>` with Text `[[mock:memory-precedent:<n>a]] Zz card a`. Wait (bounded, 90 s) for its decide Decision.
      3. The Triage request that holds the marker contains `$Parameter("OcuTalon.Agent.Input","PRECEDENTSOPENING")` and the row's Summary. This is the control.
      4. Forget the row in the card.
      5. A second item `...:<n>b` from the same sender gets a Triage request without `PRECEDENTSOPENING`.
      6. Clean up: both Decisions and their Delivery rows (`dropPhone` from the case's start), and the row if it is still there.

**Acceptance Criteria:**
1. **The card and Notes.** Given a signed-in person, when the page loads, then the status rail shows the "Memory" section, after Heartbeat checklist and before Persona, with the `app-memory-card` component and its tabs "Notes" and "Your answers". Notes shows Today and Yesterday from the notes route as served, with the intro line verbatim. An empty day shows its empty text only after a successful read (FR-71; MC1, MC2, MC3).
2. **Your answers and Forget.** Given the Your answers tab, when it lists precedents, then each row shows its date, channel, summary and answer, with Forget. Forget asks "Forget this answer? OcuTalon will stop using it.", sends only the delete route, and the row leaves at once. Cancel and Esc change nothing (FR-72; MC4, MC5).
3. **The demo variant.** Given the card, when it reads, then it lists only the session's own notes and answers, never another session's or an eval-seeded row. It holds nothing across page loads, so the online demo's sign-out drop (`SessionOps.End`) and the reset leave it empty (FR-15, AD-4, AD-21 as amended; MC8).
4. **Integration (consumers: the card over the real routes, and the real Decide over the precedent table).** Given a precedent that reaches a decide request, when the person forgets it in the card, then the next decide request for the same sender no longer carries it (FR-72, Rule 1, Rule 2, Rule 3; MC9).
5. **Labels and keyboard.** Given the card, when it is used by keyboard alone, then the tabs, Forget and the dialog work as Boundaries says, and every control has a label (NFR-25; MC6, MC7).
6. **No regression.** Given the changes, when the rail, frame, floor, demo-path and source tests run, then each passes, with only the edits listed in the Code Map and the ruled Clarification edits. The demo-path suite stays green (REL-2).

## Spec Change Log

- 2026-11-08 (rulings relayed by the orchestrator; Contest Planner under the owner's delegation):
  - **PUBLIC TEXT APPROVED as written, all nine items; pin them all with fixed strings:** `yesterdayEmpty` "Nothing recorded yesterday."; `answersEmpty` "No answers yet."; `forgetName` "Forget {summary}"; the dialog's `cancel` "Cancel" and `confirm` "Forget"; `forgetFailed` "Couldn't forget it. Nothing was changed."; the answer words "This was noise", "Approved", "Rejected"; the meta line `{when} · {channel} · {answer}`; `toolNote` "OcuTalon keeps this answer but does not use it when it decides." **The channel is shown AS THE SERVER SENDS IT** (`mailbox`, `webhook`, ..., as in the daily-note lines). `RAIL_TEXTS.memory` "Memory" is EXPERIENCE 1050.
  - **Demo-path edit APPROVED:** `web/e2e/demo-path/01-page.spec.ts:103` count 7 -> 8, plus the Memory-before-Persona assertion, and NOTHING else in the demo-path specs.
  - **Epic 18 test-list edits** (`announce-focus-sources.test.mjs` `FOCUS_CALLS` after line 131; `ux-strings.test.mjs` `SOURCES.ux`/`ac`/`ruled` appends) are plain unions (orchestrator, decide). The `IMPORTED` one-name append and the `ApiClient` end-of-class methods are within the standing precedent and are reported.
  - **`shards-5` time:** approved CI-only change (one area of `shard:lane-a@Bridge,Agent` into the `production` group) is made by the lead as a separate commit in the next story push, not by this story.
  - `## Clarification Needed` is cleared.

## Review Triage Log

### 2026-11-09 - Review pass
- verdicts: 38 findings - high 0, medium 1, low 22, false 15, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: MC8's header says "demo variant" but runs as the README account - Design Notes "Decided in-stage" rules MC8 on the local sign-in-3 stack, and the header says so.
  - `[low]` `[reject]` Blind: MC3/MC8 route gates are not released if an assertion fails first - the page closes at test end; no later case shares the page.
  - `[low]` `[reject]` Blind: `monitorSettled` returns silently on timeout - its doc says none comes when the reading did not change (HC4's documented behaviour).
  - `[false]` `[reject]` Blind: a forgotten row can reappear after a re-read - every read sets its signal to undefined before sending, so no Forget button exists while a read is in flight, and the next read starts after the DELETE.
  - `[low]` `[reject]` Blind: failed and pending reads look alike - the Boundaries rule ("intro only", tried again at the next selection); a failure line would be new text.
  - `[low]` `[reject]` Blind: no case for 501/network on Forget - `ForgetDialog.confirm` has one non-404 branch, which MC5's 500 case drives.
  - `[false]` `[reject]` Blind: a seeded "today" turn at noon may be in the future - MC2 passed in a run at 01:10 UTC with turns at noon today.
  - `[low]` `[reject]` Blind: mutation record leaves behaviours unchecked - Rule 19 asks one mutation per AC; all six are recorded.
  - `[low]` `[reject]` Blind: layout G4 not re-run - the spec leaves `live:floor` to CI; R17's loop is task 8's shared-surface edit.
  - `[low]` `[reject]` Blind: inconsistent EXPERIENCE citations in the allow-lists - the strings are the spec's own (L321 for the key map).
  - `[low]` `[reject]` Blind: relative times freeze at the last read - the rail's rows read `now` at render too; a long-open page re-reads on tab selection.
  - `[low]` `[reject]` Edge: Esc during an in-flight DELETE then 200 leaves the row listed - same shape as documents/remove-dialog.ts; a second Forget answers 404 and removes the row; the fix adds state.
  - `[false]` `[reject]` Edge: a click on the selected tab does not retry - the spec says a tab is read again when it is next selected (Matrix: Tried again when Notes is next selected).
  - `[low]` `[reject]` Edge: Alt/Cmd+Arrow is swallowed - the same handler shape as devices/device-panel.ts, which the spec says to follow.
  - `[false]` `[reject]` Edge: row removal when the list is undefined (re-read pending) - no Forget exists while a read is pending (same root as the Blind re-read claim).
  - `[false]` `[reject]` Edge: heading() may be null after Forget - the card sits inside the section whose h3 carries the id; MC4/MC5/MC6 assert focus on it.
  - `[low]` `[reject]` Edge: dialog `closed` subscription outlives a destroyed card - the dialog is modal and completes on close.
  - `[low]` `[reject]` Edge: Today/Yesterday labels stale across midnight - re-read at the next tab selection or load.
  - `[false]` `[reject]` Edge: `entry.request.tools.%Size()` may throw - MC9's control request is counted (count > 0), so the field exists in the mock log.
  - `[low]` `[reject]` Edge: `monitorSettled` timeout is silent - same as the Blind row.
  - `[low]` `[reject]` Edge: seedThree cleanup error masks the seed error - fixture-only, cleanup helper does not throw on a missing row.
  - `[low]` `[reject]` Edge: MC8 seed step may lose a Ref - fixture-only; `cleanFixtureRows` removes the other session.
  - `[low]` `[reject]` Edge: the doc claim "a click reads it again" - a click on the selected tab does not; wording only, no behaviour.
  - `[medium]` `[patch]` VG: MC2's served-order assertion cannot fail with one line a day - patched: MC2 seeds two turns per day latest first, asserts time order, and the mutation (reversed Today list) went red.
  - `[low]` `[reject]` VG: MC9's Triage-request assertions have no mutation that reaches them - the control (count > 0, opening present before Forget) shows they are not vacuous; every realistic fault deletes no row, so `precedentExists` fires first.
  - `[low]` `[reject]` VG: Rule 19 attribution of combined mutation runs - each AC has its own recorded line.
  - `[low]` `[reject]` VG: MC6 relies on no newer row for the session - workers 1, and the other cases remove their rows in `finally`.
  - `[false]` `[reject]` VG: MC3 depends on `signInReadmeLoaded` not waiting on notes - it does not (MC3 passes).
  - `[low]` `[patch]` VG: memory-card-view.test.mjs greps a doc comment of Precedent.cls - patched: the case is deleted (the channel contract is pinned by Test.Data.Precedent).
  - `[low]` `[reject]` VG: confirmed Forget not exercised in the drawer band - MC7 requires Cancel and Esc there.
  - `[false]` `[reject]` VG: browser coverage only in sign-in-3 - the repo's convention (Rule 3 evidence is that project).
  - `[false]` `[reject]` Intent: re-read on every selection versus a lazier reading - the Code Map says "Selecting a tab reads that tab again".
  - `[false]` `[reject]` Intent: both tabs read at construction - the spec's "Decided in-stage: Reading".
  - `[false]` `[reject]` Intent: Notes failure is all-or-nothing - the Matrix: intro only, no day label.
  - `[false]` `[reject]` Intent: h4 day labels and `p` empties - Design Notes "Today/Yesterday are h4 labels".
  - `[false]` `[reject]` Intent: edit to the 41.2 spec api/memory.spec.ts - the Code Map lists it (helpers moved, assertions unchanged).
  - `[low]` `[reject]` Intent: R10 and R17 rewritten beyond counts - task 8; the card reads on creation and tab select, and the taller rail needs a stepped wheel.
  - `[false]` `[reject]` Intent: root-scoped `ForgetTarget` carries the ref - holds a precedent Ref (not a SessionRef), set before each open; Dialogs.open takes no data.
- triage-added (not counted above): `[medium]` `[patch]` Rule 2: `instanceSeq`, `monitorSettled` and HC4's ready/records steps were copied from heartbeat-card.spec.ts into support/memory.ts with no stated reason - patched: moved to the new support/runners.ts, imported by both specs; HC4 and MC9 passed after.

## Design Notes

**Architecture decisions:**
- AD-1: `ForgetPrecedent` reaches `PrecedentOps` only through the route, with origin `web_user`. The card builds no command.
- AD-4: owner-scoped reads through `Ownership`, and online-demo sessions.
- AD-13: the one client and the envelope interceptor. A DELETE carries the body `{}`.
- AD-21 as amended 2026-11-08: no eval row on the card; precedents reach decide only.
- AD-28: no false empty state.
- AD-29 and U-177: Lane B.
- AD-22: the CI mock in MC9.
- AD-33: `PrecedentOps` is the one writer. Test fixtures write directly, as in 41.2.

No AC contradicts an AD's Rule.

**Integration ACs:** AC 4 (MC9).
- The card consumes the real list, delete and notes routes (41.2/41.3).
- The real Intake → `Agent.Input.PrecedentPart` → `Precedent.Similar` path (41.4) consumes the table after the card's Forget.

**Consumes:**
- 41.2: `GET /api/v1/memory/precedents`, `DELETE /api/v1/memory/precedents/:ref` and `ForgetPrecedent`;
- 41.3: `GET /api/v1/memory/notes` and `DailyNote.Build`'s approved lines;
- 41.4: the precedent block and the `memory-precedent` scenario;
- 41.5's rows when it lands. The card shows whatever rows exist and needs none of 41.5's code.

**Consumed-by:** 41.13 adds the Pinned and All memories tabs to this card. 41.7 reads nothing of it.

**Extend, don't copy:**
- The card extends the Persona card's shape: a section card in `rail/<name>-card/` with a framework-free view module, a heading-only failure rule and `status-rail.ts`'s branch. Its tabs follow `device-panel.ts`.
- `ForgetDialog` is a copy of `documents/remove-dialog.ts`'s shape. That dialog binds Documents' target, texts and call, and a shared confirm dialog would change Story 34.2's component and its tests. The lead routes the unification (one `ConfirmDialog` for both) to Epic 41's burn-down.
- The e2e fixtures move from `api/memory.spec.ts` into `support/memory.ts`, so both specs share them.

**PUBLIC TEXT needed** (veto window 5; the lead sends the list to the Planner before implement). All of these are in `web/src/app/rail/memory-card/memory-card-view.ts` `MEMORY_TEXTS` unless noted:
1. `yesterdayEmpty`: "Nothing recorded yesterday." (EXPERIENCE gives only today's empty text.)
2. `answersEmpty`: "No answers yet." (This follows the rail's "No decisions yet.".)
3. `forgetName`, the accessible name of a row's Forget: "Forget {summary}". The visible text "Forget" starts the name (WCAG 2.5.3). This follows the ruled "Remove {name}" of 34.2.
4. The dialog's buttons:
   - `cancel` "Cancel" (EXPERIENCE 206 gives it to the sign-out dialog; `DOCUMENTS_TEXTS.cancel`);
   - `confirm` "Forget" (EXPERIENCE 1053 gives "Forget" as the row's control).

   The question is verbatim (1053).
5. `forgetFailed`: "Couldn't forget it. Nothing was changed." This follows 34.2's ruled "Couldn't remove it. Nothing was changed.".
6. The answer words: noise "This was noise" (EXPERIENCE 1057, the control's own name), approved "Approved" and rejected "Rejected" (the words of EXPERIENCE 702-703's answered statuses).
7. The channel is shown as served (`mailbox`, `email`, `webhook`, `slack`, `system`, `heartbeat`), as 41.3's approved note lines show it. It is left out for a tool row. The alternative is a word per code, for example "the simulated mailbox"; the Planner chooses.
8. The row's meta line: `{when} · {channel} · {answer}`, where `when` is `pageWhen` of `answeredAt` (EXPERIENCE: Formats) and the separator is the rail's " · " (U+00B7). An example: "Monday at 14:13 · mailbox · This was noise".
9. `toolNote`, the detail line of a `tool:` row: "OcuTalon keeps this answer but does not use it when it decides." Product default (3): `tool:` rows are listed and forgettable but never read in this release (DW-922), so without a note the intro "OcuTalon looks at these when it decides on similar items." would claim more than the product does. Hiding the rows would hide a stored answer, against the story's "never hidden". If the Planner prefers the rows hidden, MC4's tool row drops.
10. Accessible names that need no new text: the tablist is labelled by the Memory heading (`aria-labelledby`), each tab panel by its tab, and the dialog by its question.
11. `RAIL_TEXTS.memory` "Memory" (EXPERIENCE 1050). No loading or error text: a pending or failed read shows the intro only (Decided in-stage).

**Decided in-stage:**
- **Place:** after Heartbeat checklist and before Persona, so that Persona stays last (`rail-view.ts` comment, `rail-view.test.mjs:162`, `01-page.spec.ts:110`) and every existing card keeps its order. EXPERIENCE does not place the card.
- **Reading:** the card reads all three answers at creation, and reads a tab again each time it is selected. There is no live refresh: the notes are built on read, and a live key would add requests per event on the online demo (default 6). It can be reversed by a read key in the view module.
- **Failure:** heading-only, as the Persona card does, with no new text (AD-28: a missing panel claims nothing).
- **Focus after Forget:** the Memory heading. `documents-page.ts:236` uses the same `setTimeout` focus, so `memory-card.ts` has two `.focus(` calls: the arrow key's tab and this one.
- **Today/Yesterday** are `h4` labels inside the tab panel. They are not h3, so the rail's heading counts see one new heading only.
- **Types file:** `memory-card-types.ts`, not 41.5's `memory-types.ts`, so that neither story depends on or collides with the other. The epic may hold two small type files.
- **The empty states** are pinned by rewriting the real GET answers (PC6's pattern), because the README session holds other specs' records today.
- **The demo variant** (MC8) is pinned on the local `sign-in-3` stack. Owner scoping is the same code on both installs (AD-4, `Ownership`). The online demo's sign-out drop is already pinned server-side: `Test.Core.SessionOpsPrecedents` (End deletes the rows), `e2e-online/session/sign-out.spec.ts` O2 (the next sign-in is a new session, so `DailyNote.Build` reads a new owner), and `e2e-online/reset.spec.ts`. MC8 adds the card's side: it keeps nothing across loads. A flag-on case would join `live:online-session` (group `shards`) or `live:online-demo` (`install-fresh`), both near the 35-minute line. The lead can ask for it.
- **"Later decisions no longer get it"** is pinned at the decide request through the mock log (MC9), with a control before the Forget (Rule 19), not by a table read alone.
- **No Task 0:** the platform behaviour in use is measured by existing specs: CDK dialog focus restore and `setTimeout` focus (Story 34.2), the mock log (`try-it.spec.ts`) and `pointKeys` (HC4). The drawer row is labelled (inference); MC7 decides it.

**Shared files with 41.5 (sequential in this branch; whichever lands second keeps the other's lines):**
- `api-client.ts`: both append at the class end. The second appends after the first.
- `playwright.config.ts:61` and `playwright-projects.test.mjs:86`: both add a name to `SIGN_IN_3_FILES`.
- `ux-strings.test.mjs`: both append to `IMPORTED` (after 68) and to `SOURCES.ux` (after 555).
- `announce-focus-sources.test.mjs`: 41.5 inserts into the speakers list, and this story into `FOCUS_CALLS`.

**Contended edits (standing precedent):**
- Allowed and reported:
  - the appended `ApiClient` block (Epic 18 edits at about 10, 21 and 59-82; no import line here);
  - the `IMPORTED` one-name append in `ux-strings.test.mjs` after line 68: `['rail/memory-card/memory-card-view.ts', ['MEMORY_TEXTS']],`.
- The other inventory edits are Clarification 2.

**Footprint beyond the lead's lane list** (Lane B, not contended; reported under `footprint_extensions:`): `web/src/app/rail/status-rail.ts`, `web/playwright.config.ts`, `web/scripts/playwright-projects.test.mjs`, `web/scripts/rail-view.test.mjs`, `web/scripts/floor-sources.test.mjs`, `web/scripts/memory-card-view.test.mjs` (new), `web/e2e/support/memory.ts` (new), `web/e2e/api/memory.spec.ts`, `web/e2e/rail/rail.spec.ts`, `web/e2e/frame/frame.spec.ts` and, only if G4 goes red, `web/e2e/floor/layout.spec.ts`. None is in Epics 17, 18 or 32's diffs (checked with `git diff --stat HEAD...origin/OCT-epic<M>`).

**Ledger:** this story owns no ledger entries.

## Clarification Needed

**Cleared 2026-11-08 (Contest Planner / orchestrator rulings): see `## Spec Change Log`.**

1. **The demo-path spec's rail count (REL-2; the 39.5 precedent, U-295).**
   - The Memory section adds the rail's eighth h3. `web/e2e/demo-path/01-page.spec.ts:103` asserts `toHaveCount(7)` ("seven sections in order, Telegram first and Persona last"), so the demo-path suite goes red with any rail card. No form of the AC's "the status rail shows the Memory card ... one slot in rail-view.ts" avoids that.
   - **Recommended (as U-295 ruled for 39.5):** the only demo-path edit is line 103. It becomes `toHaveCount(8)` with the message "eight sections in order, Telegram first and Persona last". After line 109, one assertion is added: `await expect(headings.nth(names.length + 2), 'the Memory heading comes before Persona, with no count').toHaveAccessibleName('Memory');`.
   - Every other line (96-102 and 104-124) is unchanged. The `.empty`, `.hint`, count-span and live-region checks keep holding, because the card adds none of them.
   - No other demo-path spec line changes, and the full demo-path suite stays green on the story's head.
   - Alternative: none that keeps the AC.
2. **Contended test inventories (Epic 18; standing precedent).** Proposed as plain unions, done by whichever epic merges second:
   - (a) `web/scripts/announce-focus-sources.test.mjs` `FOCUS_CALLS`: insert one entry after line 131 (`'app/rail/persona-card/persona-card.ts'`). Epic 18's insertions are at about 139-146, so the two hunks don't touch. The entry: `'app/rail/memory-card/memory-card.ts': [2, 'the tab that the user\'s arrow key moved to, and the Memory heading after the user\'s own confirmed Forget, when the dialog has given focus back and the row is gone (Story 41.6)'],`.
   - (b) `web/scripts/ux-strings.test.mjs` `SOURCES.ux`: append, after `'Checklist',` (555), the EXPERIENCE strings that are not already in the inventory: "Memory", "Notes", "Your answers", the Notes intro, "Nothing recorded yet today.", the Your answers intro, "Forget", and "Forget this answer? OcuTalon will stop using it.". Each string sits under the first source the test accepts. A word that EXPERIENCE holds incidentally ("Today", "Yesterday", "Cancel", "Approved", "Rejected", "This was noise") sits under `ux`, as 39.5's "To" did.
   - (c) the same file, `SOURCES.ac`: only if a string is not in EXPERIENCE, a new entry `'Story 41.6: The Memory card: your notes and your answers (the day labels of the Notes tab)'` appended before the `ac` block's closing `},` (586).
   - (d) the same file, `SOURCES.ruled`: one new entry for the Planner's ruling of the PUBLIC TEXT list, appended before the `ruled` block's closing `},` (691). Epic 18's `ruled` hunks are at about 595-640.
3. **CI time (REL-4, owner-fixed value 9: 35 minutes).** These are measured figures, not a request to change `ci/units.sh` in this story.
   - **The measurement:** `ci` run 42485902344 is this branch's head `6aa10fd5` (41.3), before 41.4's `MemoryTurns` and before the integrate-forward of Epic 19 part 2. In it, `shards-5` was 2,070 s of units (`shard:lane-a@Bridge,Agent` 1,294 s, `live:sign-in-3` 776 s), and its job ran 35 min 8 s.
   - **The other groups:** `shards-4` 2,064, `install-upgrade` 2,018, `image` 1,978, `install-fresh` 1,942, `shards-3` 1,938, `browser` 1,935, `shards` 1,886, `shards-2` 1,638 (before `live:session-data`) and `production` 1,546 (no web bundle).
   - **The effect:** 41.4 (60-150 s in `shards-5`), 41.5's `memory-noise.spec.ts` and this story's spec (about 60-120 s with MC9's `pointKeys`, inference) all land in `shards-5`.
   - **Recommendation:** the spec joins `live:sign-in-3`, as the lead asked. The lead takes the group's time to the Planner before this story's push. The figures suggest moving one area of `shard:lane-a@Bridge,Agent` (no web bundle) to `production`, after measuring the area's seconds; that is the Planner's rebalance, not this story's edit.

## Verification

Run every command from the worktree root, one per call, with `timeout: 600000`, each sized to about 150 s.
- **IRIS:** this story changes no class. If a stage reads the slot, it uses `server` `ocutalon-slot-a` and `namespace` `OCUTALON` on every MCP call, after `iris_server_info` shows build 154, with one `iris_execute_tests` per message.
- **Throwaways:** prefix each `ci/` call with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=implement'` and `OCUTALON_RUN_TAG=e41s6impl`. Tear down after.

**Commands:**
- (loop) `node --test web/scripts/memory-card-view.test.mjs web/scripts/rail-view.test.mjs web/scripts/floor-sources.test.mjs`. Expected: all pass.
- (loop) `npm --prefix web run lint`. Expected: exit 0 (type-checks the e2e specs and `support/memory.ts`).
- (once) Each in its own call:
  - `node --test web/scripts/announce-focus-sources.test.mjs web/scripts/ux-strings.test.mjs web/scripts/api-client-sources.test.mjs`. Expected: pass after the Clarification 2 edits.
  - `node --test web/scripts/playwright-projects.test.mjs`. Expected: `memory-card.spec.ts` is listed by `sign-in-3` only.
  - `npm --prefix web test`. Expected: every web script test passes.
- (once) `npm --prefix web run build`. Expected: the token, payload and catalog `--check` steps and `ng build` pass.
- (once) `bash ci/checks.sh`. Expected: every block passes.
- **Left to CI**, because each takes over 150 s locally:
  - `live:sign-in-3` in `shards-5`: `web/e2e/memory-card.spec.ts`, Rule 3;
  - `live:sign-in` in `browser`: `rail/rail.spec.ts`, `frame/frame.spec.ts` and `api/memory.spec.ts`;
  - `live:demo-path` in `browser`: REL-2, with Clarification 1's edit;
  - `live:floor` in `shards-3`: `floor/layout.spec.ts`;
  - the fresh-environment check, forward and reversed.

  A stage that can hold a lane-A fresh stack may run `ci/iris.sh build`, then `OCUTALON_LIVE_DEADLINE=900 ci/iris.sh live sign-in-3` (over 150 s, so if it is moved to the background, wait in bounded foreground polls), then `ci/iris.sh teardown`.

**Mutations (Rule 19), one per AC; record each as `mutation: <change> -> <test red>`:**
- AC 1: the notes panel shows `notesEmpty` while a read is pending (the failure rule dropped) -> MC3's 500 case, and `memory-card-view.test.mjs` if the rule is in the view.
- AC 2: `forgetPrecedent` sends `DELETE .../precedents/` with no ref encoded -> MC4. Also the row removed only after a re-read -> MC4's "no re-read" request count.
- AC 3: the card keeps the last list in `sessionStorage` and shows it before the read answers -> MC8's after-reload check. The owner scoping itself is the routes' and is pinned by 41.2 (`Test.Web.MemoryApi`, `api/memory.spec.ts`).
- AC 4: `forgetPrecedent`'s confirm closes the dialog without calling the route -> MC9's second Triage request still carries `PRECEDENTSOPENING`.
- AC 5: the `(keydown)` handler removed -> MC6.
- AC 6: `RAIL_TEXTS.memory` put after `persona` -> `rail-view.test.mjs` and `rail.spec.ts` R1.

Recorded by the implement stage (browser cases on a fresh `ci/iris.sh live sign-in-3 --part 6/6` stack, each mutation reverted byte-identically; the other reds in a run are the same fault reaching other cases):
- mutation: AC 1, the Notes panel shows `notesEmpty` while its read is pending (an `@else` on the days) -> MC3 red (also MC6 and MC8 in that run, which carried AC 5's and AC 3's mutations).
- mutation: AC 2, `forgetPrecedent` sends `DELETE .../precedents/` with no ref -> MC4 red (the DELETE address; MC5, MC6 and MC9 red too).
- mutation: AC 2, the row removed only after a re-read (`gone` calls `readAnswers`) -> MC4 red (the "one DELETE and no re-read" request list; MC5 red too).
- mutation: AC 3, the last list kept in `sessionStorage` and shown before the read answers -> MC8 red (the held-read check after the reload).
- mutation: AC 4, the dialog's confirm closes it without calling the route -> MC9 red (the row stays in the table; MC4, MC5 and MC6 red too).
- mutation: AC 5, the `(keydown)` binding removed -> MC6 red, and `floor-sources.test.mjs` red (the key-binding and key-handler inventories).
- mutation: AC 6, the Memory section pushed after Persona in `railView` -> `rail-view.test.mjs` red (five cases). `rail.spec.ts` R1 not run against it.
- mutation: AC 1 (served order), the Today list rendered reversed (`shown.today.slice().reverse()`) -> MC2 red (review pass; MC2 seeds two turns a day, latest first; the tree was restored byte-identically and MC1 to MC9 passed again on a fresh `ci/iris.sh live sign-in-3 --part 6/6`, with Story 41.5's NZ1 and NZ2 red as deferred).

**Shared surfaces:**
- the rail's sections and heading counts: `rail-view.test.mjs`, `rail/rail.spec.ts` R1 and R11, `frame/frame.spec.ts` F1, `demo-path/01-page.spec.ts:103`;
- the rail's height: `floor/layout.spec.ts` G4;
- the key and focus inventories: `floor-sources.test.mjs`, `announce-focus-sources.test.mjs`;
- the UX inventory: `ux-strings.test.mjs`;
- the sign-in projects' file lists: `playwright.config.ts`, `playwright-projects.test.mjs`;
- the README session's Precedent, Turn and Decision rows: `api/memory.spec.ts`, which shares the moved helpers;
- the runners' keys: MC9's `pointKeys`, restored in `afterAll` as HC4 does; the shared steps are in `web/e2e/support/runners.ts`, which `heartbeat-card.spec.ts` HC4 imports too (`ci/iris.sh live sign-in-3 --part 5/6` passed, 23 tests).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

- **Summary:** the Memory card is in the status rail between the Heartbeat checklist and Persona. It has two ARIA tabs: Notes (today and yesterday from `GET /api/v1/memory/notes`, as served) and Your answers (`GET /api/v1/memory/precedents`, each row with Forget, which asks in a modal dialog, then sends only `DELETE /api/v1/memory/precedents/:ref` and removes the row with no re-read). It reads only through `ApiClient`, shows the intro line alone while a read is pending or failed, and holds nothing across loads. All nine ruled strings are pinned with fixed strings.
- **Files changed:**
  - New: `web/src/app/rail/memory-card/{memory-card-view,memory-card,forget-dialog}.ts`, `web/src/app/api/memory-card-types.ts`, `web/scripts/memory-card-view.test.mjs`, `web/e2e/memory-card.spec.ts` (MC1-MC9), `web/e2e/support/memory.ts` (moved fixtures), `web/e2e/support/runners.ts` (shared runner/monitor steps).
  - Changed: `rail-view.ts`, `status-rail.ts` (the slot), `api-client.ts` (three methods at the class end), `playwright.config.ts` and `playwright-projects.test.mjs` (`sign-in-3` list), `rail-view.test.mjs`, `floor-sources.test.mjs`, `announce-focus-sources.test.mjs`, `ux-strings.test.mjs` (plain unions and the one-name `IMPORTED` append), `e2e/api/memory.spec.ts` (helpers moved), `e2e/rail/rail.spec.ts`, `e2e/frame/frame.spec.ts`, `e2e/heartbeat-card.spec.ts`, `e2e/demo-path/01-page.spec.ts` (count 8 plus the Memory-before-Persona assertion only).
- **Review:** 38 findings, 1 patched medium (MC2 order pin) and 1 patched low (a doc-comment grep), 1 triage-added medium patched (copied runner helpers moved to `support/runners.ts`), 1 item deferred (Story 41.5's NZ1/NZ2 under UTC hour 10), 35 rejected with their reasons in the Review Triage Log. Follow-up review recommended: false (one medium patched).
- **Verification performed:**
  - `node --test` memory-card-view, rail-view, floor-sources, announce-focus-sources, ux-strings, api-client-sources, playwright-projects: pass. `npm --prefix web test` 1610 pass. `npm --prefix web run lint` exit 0. `npm --prefix web run build` passes. `bash ci/checks.sh` all scripts passed (before the review patches, which touch only e2e files). `bash docker/tests/test-boundaries.sh` passes.
  - `ci/iris.sh live sign-in-3 --part 6/6`: MC1-MC9 pass (NZ1 and NZ2 of Story 41.5 red, deferred); `--part 5/6`: 23 pass (HC4 included); sign-in parts 3/19, 12/19, 14/19 and sign-in-2 part 11/15 passed in the implement pass. Mutations are recorded under `## Verification`.
  - Throwaways torn down; no lock left.
- **Residual risks:**
  - `floor/layout.spec.ts` G4 (viewport 1000x2100) and the demo-path unit were not run locally (over 150 s); G4 may need a taller viewport, as Story 40.4 did. Left to CI.
  - Story 41.5's NZ1/NZ2 are red in sign-in-3 part 6/6 while the UTC hour is below 10 (deferred above).
  - The group time of `shards-5` is the lead's rebalance (Clarification 3).
- **footprint_extensions:** `web/src/app/rail/status-rail.ts`, `web/playwright.config.ts`, `web/scripts/{playwright-projects,rail-view,floor-sources,memory-card-view}.test.mjs`, `web/e2e/support/{memory,runners}.ts`, `web/e2e/{api/memory,rail/rail,frame/frame,heartbeat-card}.spec.ts`.
- **Contended edits made (standing precedent):** the `ApiClient` end-of-class block, the `IMPORTED` one-name append, and the Clarification 2 test-list unions (`announce-focus-sources.test.mjs`, `ux-strings.test.mjs`).
