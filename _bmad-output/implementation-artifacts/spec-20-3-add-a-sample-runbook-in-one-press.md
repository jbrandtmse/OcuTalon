---
title: 'Story 20.3: Add a sample runbook in one press'
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

**Problem:** A demo visitor with no file to hand cannot see a cited answer (Story 20.2's chips) without bringing a document of their own, so the "cited answers" promise is hard to find in voting week.

**Approach:** The Documents page gets an **Add the sample runbook** button that gives a short runbook bundled in the web app to the page's existing add path (`POST /api/v1/documents`, `AddDocument`, `DocumentOps`), with no server change. While the visitor has no documents, More to try items 6 and 8 show the same control, which opens the Documents page and presses that button. Item 6's look-for suggests one question the runbook answers, measured to cite one section.

## Boundaries & Constraints

**Always:**
- The sample takes the normal path, byte for byte the same as a picked file: the page builds a `File` from the bundled text and hands it to its own `addFile` (FileReader base64, `api.addDocument`, the pending/refused rows, the refusal announcement). The request is `{name, content}` to the existing `POST /api/v1/documents`. Ownership follows the install (session on the online demo, `instance` locally) because the route already decides it. No network fetch: the text is a constant in the web bundle.
- "Has no documents" is the visitor's own list: `GET /api/v1/documents` overlaid with the live store's `document` events (`documents-view.rows`), any state. Unknown (not loaded, or the GET failed) means the existing link. `Demo.Features` only says the feature is built. The sample control shows only when the panel's items include the `documents` id.
- The More to try control does what the control it names does (EXPERIENCE "A control does what the control it names does"): it opens the Documents page and puts focus on that page's **Add the sample runbook**, then presses it. The panel itself never posts.
- The page button is a `ServerButton` (`shared/server-button.ts`): it keeps its label, gains a spinner, and is `aria-busy` and `aria-disabled` (never `disabled`), and repeat presses are ignored while it is busy. A refusal or failure shows the page's existing row texts ("Couldn't read it: {reason}") and is announced once, as for any file.
- Runbook text is ASCII only. Every passage is under 1,000 characters, and the facts are the demo's own (see Design Notes, "Facts").
- Labels state provenance only (U-280). No new public string is committed before the Planner rules it (`## Public Text`). Non-ASCII in code is written as escapes (Rule 14).
- Changes to contended files are additive (Design Notes lists them). More to try's count stays eight.

**Never:**
- No server class change. No new or changed route, role, grant, table, column or stored setting. No seeding on the server or in the golden copy (AD-25).
- No Lane A edit (U-177): `src/bridge/**`, `Docs/**`, `Memory/**`, `Tools/**`, `Agent/**`, `Checks/**`, `Watch/**`, `Fix/**`, `Eval/**` and their tests.
- `ApiClient`/`HttpClient` is never used in `guide/more-to-try.ts`. Its template keeps one `<button>`, one `<a>` and two `(click)`, and nothing runs at creation (`more-to-try-sources.test.mjs`).
- No new More to try item. No change to `ci/units.sh`, `.github/**` or `release/**`, and no new CI unit.
- No canned product reply. The only scripted text is the CI mock's own reply in its scenario file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Press on the Documents page | The list is loaded and holds no sample | Busy (spinner, aria-busy, aria-disabled, same label). One POST `{name:"Sample runbook.md", content: base64(text)}`. The row reads "Indexing…", then "Ready" live. The button leaves and focus goes to the list region | none |
| Repeat press while busy | A second Enter or click | No second POST | none |
| Sample already listed | A server or live row named "Sample runbook.md" (any state), or the page's own pending add | The button is absent (no duplicate). After that row is removed, the button shows again | none |
| Refused or failed add | 400 `bad_document`, 413, 501, 500 or a network error | The page's own refused row "Couldn't read it: {reason}" (existing texts), announced once. The button stays, with focus, and can be pressed again | the existing `reasonOf` |
| Guide: no documents | `documents` in features, list `[]` and no live rows | Items 6 and 8: a native button "Add the sample runbook" | none |
| Guide: has documents | One or more rows (any state) | Items 6 and 8: the existing link "Open the Documents page" | none |
| Guide: list unknown | GET pending or failed | The existing links | GET error ignored |
| Guide: live change | A `document` event adds a row, or a `removed` event empties the list | The control switches without a reload | none |
| Guide press | The sample control | Navigates to `#/documents`. Once the list loads, focus is on the page's sample button and it is pressed (one POST). If the sample is already listed by then, focus goes to the list region and nothing is posted | none |
| Suggested question | Ask the question in item 6's look-for | The reply ends with a chip "Sample runbook § When orders fail with a date error" (named "Sample runbook, section When orders fail with a date error") | the model may not search (online, inference) |

</intent-contract>

## Code Map

- `web/src/app/documents/documents-page.ts` -- the add path to extend: `addFiles` :342, `addFile(file)` :348-360 (pending row, `encode` :395, `api.addDocument`, `own`, `patch`, `fetch`; catch -> `refuse` :363, announced once), `reasonOf` :374; `.bar` with **Add documents** :52-55; `items`/`shown` :216-225; `loaded` :203; `focusList` :284; snapshot-driven `fetch` effect :228-231 (sibling for the presence fetch); focus pin `announce-focus-sources.test.mjs:145` (2 calls).
- `web/src/app/documents/documents-view.ts` -- framework-free, imports nothing. `DOCUMENTS_TEXTS` :20-35 (add `sample`); `rows(server, live, local)` :178-201 (reuse for `hasDocuments` and `sampleListed`); `DocumentRow` :113-131 (`local`, `state`).
- `web/src/app/shared/server-button.ts` -- the busy button (`action` returns a Promise/Observable; BUSY_NOTICE after 10 s is an existing string). Sibling usage in other components: `<app-server-button variant="secondary" [action]=...>`.
- `web/src/app/api/api-client.ts:174-185` -- `documents()` and `addDocument(name, content)`, reused unchanged.
- `web/src/app/live/live-store.ts:51,82,144,194` -- `documents` collection, empty from a snapshot and filled by `document` events only (so the GET is needed).
- `web/src/app/guide/more-to-try.ts` -- template :63-82 (`@if (item.action === 'documents')` link, else the one button); `press(item)` :206-235 (`default` no-op today); injects `LiveState` :173. Contended (23.6). Pinned by `web/scripts/more-to-try-sources.test.mjs:31-51` (no ApiClient, 1 button, 1 link, 2 clicks, 1 `.focus(`, nothing at creation), :177.
- `web/src/app/guide/more-to-try-view.ts` -- `MORE_TO_TRY_TEXTS.items.documents.lookFor` :58-59 (changes), `sources` :68-73 (unchanged), registry :93-102 (unchanged). Contended (23.6).
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls:1-24` (read-only evidence) -- the route's ownership, refusals, 501 `not_built`, sweep, and that GET works whether or not DocumentOps runs.
- `src/ocutalon/cls/OcuTalon/Docs/Passages.cls:1-12` and `Docs/Store.cls:231-235,324-334` (Lane A, read-only) -- a `## ` line opens a section, passages are at most 1,000 characters, the embedded input is `section\ntext`, and the `document` name is the file name without `.md`. `src/bridge/cls/OcuTalon/Bridge/Citations.cls:20,23` (read-only) -- CITEFLOOR 0.4, at most 5.
- `ci/mock/scenarios/A/documents-runbook.json` -- sibling scenario shape (toolUse `documents` with a fixed `query`, then text). `ci/mock/scenarios.mjs:12-21` -- format and marker rules; B/ is Lane B's folder. `ci/mock/test/constants.test.mjs:153-158` lists A's documents scenarios (unchanged).
- `docker/tests/test-documents.sh:232-290` -- how the real cited path is proven (real upload, real Ready, the mock calls `documents`, real search, real citations); `web/e2e/chat/sources.spec.ts:486-560` -- S7: `pointKeys`/`restoreKeys` (`e2e/support/devices.ts:188,195`), `SessionMark`/`DropSince`, wipe, `send()`, `replyOf`/`sourcesOf`/`dialogOf`.
- `web/e2e/documents/documents.spec.ts` -- the Documents page specs (README account, instance fixtures, `cleanFixtureRows`, `publish`, `posted`, `rowsOf`, `listRegion`); D2 asserts the empty text, so any instance document a new case adds must be removed after it.
- `web/e2e/guide/more-to-try.spec.ts` -- `ITEMS` oracle :95-111 (item 6 look-for), `controlOf` :119, K3 :274-284 (items 6 and 8 are links). Contended (23.6).
- Tests to update: `web/scripts/more-to-try-view.test.mjs:64-68` (oracle) and `has()` checks :150-185; `web/scripts/sources-docs.test.mjs:94-108` (EXPERIENCE item 6 and the controls sentence); `web/scripts/ux-strings.test.mjs` `IMPORTED` :41-71, `SOURCES` :173+; `web/scripts/announce-focus-sources.test.mjs:145`; `web/scripts/documents-view.test.mjs`.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- Item 6 :251; the controls sentence and the hand-off rule :254-255; Step 3 Documents :978-983 (do not edit the Adding line :980, which `test-documents.sh` pins). `README.md` "New since 1.0.0" :32-41.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure, record as "Task 0 results (implement)" under Design Notes). (a) On the fresh sign-in stack, the e2e's real turn shows the citation on the target section, and the popover passage starts with "OrdersFromPartner accepts". (b) The fixture user the new e2e uses holds exactly `OcuTalonUser` (`Security.Users`, like sources.spec S0). (c) The time from the press to "Ready" on the developer machine.
- [ ] `web/src/app/documents/sample-runbook-view.ts` (new, framework-free, imports nothing) -- `SAMPLE_RUNBOOK_TEXTS = {name, text, question}`, verbatim from `## Public Text`. The bundled runbook.
- [ ] `web/src/app/documents/documents-view.ts` -- add `DOCUMENTS_TEXTS.sample`. Add `hasDocuments(server, live)` (`rows(server, live, []).length > 0`). Add `sampleListed(rows, name)`: true when a row has that name and is not the page's own refused row. Both extend `rows`. Update the header comment.
- [ ] `web/src/app/documents/sample-runbook.ts` (new, `@Injectable({providedIn:'root'})`) -- `none: Signal<boolean>`: true only once the GET answered and `hasDocuments` is false over the GET and `live.store().documents`. The GET runs on creation and again on every snapshot reload, the same effect as `DocumentsPage`'s; an error leaves it unknown (false). Also `ask()` and `take()`, a one-shot request from the guide.
- [ ] `web/src/app/documents/documents-page.ts` -- in `.bar` after **Add documents**, add `<app-server-button variant="secondary" [action]="addSample">` with the text `texts.sample`, shown while `loaded() && !sampleListed(shown(), name)`. `addSample` builds `new File([text], name, {type: 'text/markdown'})` and awaits `addFile`, which now returns success. On success, focus goes to the list region. On a refusal nothing moves. Hand-off: if `inject(SampleRunbook).take()` was set at construction, then once `loaded()` and after render, focus the sample button's native button and click it. If the sample is already listed, focus the list region instead. Update the class doc.
- [ ] `web/src/app/guide/more-to-try.ts` -- inject `SampleRunbook` and `Router`. `sampleFirst = computed(() => sample.none() && items().some(i => i.id === 'documents'))`. Template: the link branch becomes `item.action === 'documents' && !sampleFirst()`. The one button shows `sampleFirst() && item.action === 'documents' ? DOCUMENTS_TEXTS.sample : item.button`. `press` case `'documents'`: `sample.ask(); void router.navigate(['/documents'])`. Keep the counts the source test pins, and update the component doc (items 6 and 8).
- [ ] `web/src/app/guide/more-to-try-view.ts` -- item 6 `lookFor` as in `## Public Text` (one string changed, nothing else).
- [ ] `ci/mock/scenarios/B/sample-runbook.json` (new) -- marker `sample-runbook`. Replies: toolUse `documents` with `input.query` equal to `SAMPLE_RUNBOOK_TEXTS.question`, then text "The CI mock answered from the sample runbook." (a CI fixture, not shipped).
- [ ] `web/scripts/sample-runbook-view.test.mjs` (new) -- ASCII only. Ends with one newline. Has a `## When orders fail with a date error` section. Each `## ` section's paragraphs fit in 1,000 characters. The name ends `.md`. The `B/sample-runbook.json` documents query equals the question. Item 6's look-for holds `"<question>"`.
- [ ] `web/scripts/documents-view.test.mjs` -- `hasDocuments` (empty, a server row, a live add, a live `removed`) and `sampleListed` (a server row in each state, an own pending add, an own refused row only, another name).
- [ ] `web/scripts/more-to-try-view.test.mjs`, `more-to-try-sources.test.mjs`, `sources-docs.test.mjs`, `ux-strings.test.mjs`, `announce-focus-sources.test.mjs` -- item 6 oracle and `has()` checks (`press ${DOCUMENTS_TEXTS.sample}`, `"${question}"`, `reads ${DOCUMENTS_TEXTS.ready}`). Source rules: still no ApiClient or `addDocument` in `more-to-try.ts`, the documents press only `ask()`s and `navigate`s, and counts unchanged. Sources-docs: the EXPERIENCE item 6 line and the new controls sentence. Ux-strings: `IMPORTED` += `['documents/sample-runbook-view.ts', ['SAMPLE_RUNBOOK_TEXTS']]`, with each new string in `SOURCES` (`ux` once EXPERIENCE.md holds it verbatim, else `ruled` keyed by the 20.3 ruling id the lead records). Focus pin: `documents-page.ts` count and reason (the hand-off focus, for the user's own press in the guide).
- [ ] `web/e2e/documents/sample.spec.ts` (new, chromium project) -- as the CHAT fixture user (`OcuTalonUser` only). Each case removes what it adds, also on failure: the document through the real `DELETE`, turns, AI sessions since the mark, and the keys restored. E0 role check. E1 is the demo-visible path. The precondition is no row named the sample. Delay the POST (`page.route` -> `continue` after about 1.5 s) to assert busy, the unchanged label and one POST after a second press. Check the body (`name`, `content` decodes to the text). Wait for the real row "Indexing…" -> "Ready" (up to 120 s); the button is gone and focus is on the list region. Then `pointKeys`, open the chat, send `${question} [[mock:sample-runbook]]`, and expect the reply text, then a chip named exactly "Sample runbook, section When orders fail with a date error" showing "Sample runbook § When orders fail with a date error". Its popover holds the passage. E2: a 501 (fulfilled) -> "Couldn't read it: this part of OcuTalon isn't built yet." on the page's row, announced once, button kept, with focus. E3: a seeded instance row named "Sample runbook.md" -> no button; after its `removed` event the button shows. E4: Tab reaches the button after **Add documents** and Enter presses it.
- [ ] `web/e2e/guide/more-to-try-sample.spec.ts` (new, sign-in-3 project, the K3 setup) -- G1: with GET `/v1/documents` fulfilled `[]`, items 6 and 8 are buttons "Add the sample runbook". With one document, they are links (href `#/documents`). A published `document` event flips the buttons to links without a reload. G2: pressing item 6's button lands on `#/documents` with focus on the page's sample button and makes exactly one POST named "Sample runbook.md" (fulfilled 200), and the panel posts nothing itself. G3: Tab plus Enter does the same.
- [ ] `web/e2e/guide/more-to-try.spec.ts` -- `ITEMS.documents.lookFor` oracle text. K3 fulfils GET `/v1/documents` with one document, so items 6 and 8 stay links (additive lines).
- [ ] `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- Item 6 look-for, the controls sentence, the hand-off rule and the Step 3 sample bullet, as in `## Public Text`. Each gets `[AMENDED <commit date>, Story 20.3, Planner ruling <id>. It read: "...">]` where it changes existing text.
- [ ] `README.md` -- only if the Planner rules Public Text 9 in: append it LAST under "New since 1.0.0", with L30's count unchanged.

**Acceptance Criteria:**
- Given the Documents page with no sample listed, when the user presses **Add the sample runbook**, then the bundled runbook goes through `POST /api/v1/documents` exactly like a picked file (the same `addFile`), its row reaches Ready live, the button leaves, and no server class changed (FR-42, AD-21).
- Given an upload in flight, when the user presses again, then the button stays busy with its label, a spinner, `aria-busy` and `aria-disabled`, and no second request is made. A refusal shows the existing "Couldn't read it: {reason}" text, announced once (NFR-25, UX-DR130).
- Given the sample is listed (any state, or pending), when the page shows, then there is no sample button. After the user removes it, the button returns.
- Given More to try with `documents` listed, when the visitor's own list is empty, then items 6 and 8's control is **Add the sample runbook**, and pressing it opens the Documents page and presses that page's button. Once they have any document, the control is the existing link (Integration AC: More to try consumes `SampleRunbook.none()` and the Documents page consumes its request).
- Given the sample is Ready, when the visitor asks item 6's suggested question through the composer (CI mock), then the reply ends with a citation chip "Sample runbook § When orders fail with a date error" from the real search of the real indexed runbook (Story 20.2).
- Given keyboard use, when the user Tabs to either control, then it is a native button with a visible label, it works with Enter or Space, and nothing relies on colour alone.
- Given the fixed-strings test, when it runs, then every new string is in `SOURCES` with its ruling, the runbook module is in `IMPORTED`, item 6's look-for in EXPERIENCE.md equals the registry's, and the count stays eight (UX-DR117).

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):**
- AD-21: documents go through `DocumentOps`, with `Passages`/`Citations`, ownership by install and the `document` event.
- AD-4: ownership comes from the session, never from the client.
- AD-12: the page decides from the server's list and events, and guide progress is untouched.
- AD-13: no route change.
- AD-25: no network fetch, nothing seeded, and the golden copy stays document-free.
- AD-22: CI mock only, with the scenario in B/.
- AD-29 and AD-33: Lane B files only, and `DocumentOps` stays the one publisher.
- AD-31: chips are built by code.

No AC contradicts an AD. AD-12's "Prevents" covers guide progress and Break the feed only, and choosing a control from the visitor's own list is not either of those.

**Already met by delivered code (judged against it):**
- Upload, ownership and refusals: `Web/Documents.cls:3-15` (34.2/34.3, 19.5). The session's own on the demo, `instance` locally, 400/413/501/500, nothing stored on a refusal.
- Row states, live: `documents-page.ts` rows plus `document` events (34.2).
- Chips naming document and section: `answer-sources-view.ts` (20.2) over `Citations` (19.4).
- The busy button: `ServerButton`.
- The open-document panel: 20.2.

This story adds only the bundled text, the button, the guide control, the look-for, the mock scenario, tests and docs.

**Consumes:** `POST`/`GET /api/v1/documents` (34.2); `DocumentOps`, `Passages`, `Citations` and the embedding worker (19.4, Lane A); `answer-sources` chips (20.2); `ServerButton`; `LiveState` `documents`; the CI mock.

**Consumed-by:** this story's More to try control and the Documents page hand-off (both consume `SampleRunbook`). No later story is planned.

**Integration ACs:** the guide-control AC (G1/G2, the real page) and the cited-answer AC (E1: real route, real index, real search, real chip) are the consumer ACs.

**Extend, don't copy (Rule 2):**
- The sample reuses `addFile` (a `File` built from the text), so there is no second upload path, and it reuses `api.addDocument`.
- `hasDocuments` and `sampleListed` wrap `rows()`.
- The button is `ServerButton`.
- The guide control reuses the panel's one button and the hand-off rule.
- The scenario copies `documents-runbook.json`'s shape.
- One small copy: `SampleRunbook`'s GET-on-snapshot effect repeats `DocumentsPage`'s five-line fetch. It is kept because the page owns its list (it refetches after each add, and has local rows) while the service is a read-only presence probe that lives outside the page. Unifying them would move the page's list into a service, which is a refactor outside this story.

**Spec gate (lead, 2026-11-09):** passed (Integration ACs G1/G2 and E1; AD ids mapped; ledger inbox empty; no route, privilege or stored-data change; lane-B throwaways only). Sent to the Planner before any implement: the 9 rows of `## Public Text` (PUBLIC TEXT). Implement waits for the ruling and for Story 20.2's CI on 6c6f00a7; each ruling is recorded here when it arrives.

**Decided in-stage:**
1. The guide control hands off: navigate, then press the page's button. This keeps "A control does what the control it names does", and refusals show where they always do.
2. "Has no documents" is any row of the visitor's list (GET plus events). Unknown or error keeps the link. The control is gated on the `documents` id, so an install with memory only never offers it.
3. Second press: the page hides the button while the list holds the sample (a server row in any state, or the page's own pending add), so there is never a duplicate upload. After a refusal the button stays. After success, focus goes to the list region (the remove flow's target).
4. Only item 6's look-for changes; item 8 stays as ruled in 20.2.
5. The name is "Sample runbook.md", so the chip reads "Sample runbook § …". The question is the measured variant v2.
6. The scenario goes in `B/`, which is Lane B's.
7. The 10 s ServerButton notice is the existing BUSY_NOTICE.
8. The README line is optional, for the Planner.

**Facts (only what the demo has):**
- The Orders production runs in OCUORDERS. Its items are PartnerOrdersIn, OrdersFromPartner (the transform accepts only YYYY-MM-DD) and OrdersToWarehouse (`Demo/Orders/Production.cls:1-19`, `Transform.cls:1-16`).
- Orders are PO-<4 digits> with a SKU and a quantity (`Partner.cls:12-28`). The partner's formats are YYYY-MM-DD and MM/DD/YYYY.
- Break the feed sends 50 orders (README :108).
- The repair-and-resend fix is `Fix/Reformat.cls`.
- The Results partner's certificate notice is the Simulated mailbox's sample (EXPERIENCE :656).

The runbook makes no claim about OcuTalon.

**Task 0 results (plan stage, 2026-11-09, lane-B warm throwaway `e20s3pw`, started and torn down by this stage; stack ready in 259 s):**
- `Docs.Passages.Split` of the text in `## Public Text` (1,263 characters, markdown) gives 4 passages: 0 intro "" 199 chars; 1 "How orders flow" 221; 2 "When orders fail with a date error" 557; 3 "When the Results partner changes its certificate" 166.
- Each was embedded as `section\ntext` through `Memory.Embedding.Embed` (as `Docs.Store.Write` does). Each question was embedded the same way. The table gives the cosine similarity of each question with passages 0/1/2/3. (inference: AI Hub's knowledge-base score is this cosine; 19.4's M4 values are of the same scale, and E1 confirms it end to end.)

| Question | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| **According to the runbook, what should I do when partner orders fail with a date error?** (chosen) | 0.3361 | 0.3672 | **0.7505** | 0.2295 |
| What should I do when partner orders fail with a date error? | 0.2040 | 0.3423 | 0.7584 | 0.2283 |
| What does the runbook say to do when orders fail with a date error? | 0.3515 | 0.2220 | 0.6380 | 0.0914 |
| What does the sample runbook say to do when orders fail with a date error? | 0.4026 | 0.2405 | 0.6130 | 0.1463 |
| Who do I call about Results? (item 5) | 0.2183 | 0.1648 | 0.0877 | 0.3768 |
| Which productions are running? (Try it) | 0.3104 | 0.1233 | 0.1995 | 0.0528 |
| Is anything wrong right now? (Try it) | -0.0869 | -0.0651 | 0.0627 | -0.0635 |

So at CITEFLOOR 0.4 the chosen question cites only passage 2. The other demo prompts cite nothing from the sample. "Sample runbook" in a question lifts the intro over the floor, which is why the chosen wording says "the runbook". Naming the runbook also invites the real model to call `documents` (inference; release hands-on pass).

**Contended files (all additive or one-string):**
- `guide/more-to-try.ts` (23.6): one computed, two injections, one template condition and one `press` case.
- `guide/more-to-try-view.ts` (23.6): the item 6 `lookFor` string only.
- `e2e/guide/more-to-try.spec.ts`: the oracle string and K3's added route lines.
- EXPERIENCE.md More to try block (23.6, Epic 35): item 6, one added sentence and one added clause.
- `README.md` (23.6): one bullet appended last, if ruled in.

If 23.6 prepends an item, "Items 6 and 8" renumber at the second merge. Code refers to ids, never numbers.

Not touched: any `.cls`, `Web/Api.cls`, `Core/**`, `Data/**`, `Msg/**`, `chat/chat-view.ts`, `chat/notice-card.ts`.

**Veto-window / escalation items (for the lead at the spec gate):**
- Public text: every row of `## Public Text` is new and needs the Planner's ruling before implement.
- Security, privileges, stored data and routes: none changed. The sample is an ordinary user upload under the visitor's session or `instance`, and the existing sign-out and reset drops apply.
- The demo path: the cited answer online depends on Haiku calling `documents` (inference). This is the Planner's hands-on pass.

**Ledger inbox (Rule 17):** none.

## Public Text

All rows are new and need a Planner ruling. Use them verbatim once ruled. Each one passes the U-280 check: provenance only, never "used", "relied on" or "based on".

| # | Text (verbatim) | Target | Source |
|---|---|---|---|
| 1 | `Add the sample runbook` (Documents page button, and items 6 and 8's control while the visitor has no documents; the busy state keeps this label, with no busy text) | `documents-view.ts` `DOCUMENTS_TEXTS.sample` | new -- needs Planner ruling |
| 2 | `Sample runbook.md` (the file name; the list shows it, and chips show "Sample runbook") | `sample-runbook-view.ts` `name` | new -- needs Planner ruling |
| 3 | The runbook text, below, exactly, ending with one newline | `sample-runbook-view.ts` `text` | new -- needs Planner ruling |
| 4 | `According to the runbook, what should I do when partner orders fail with a date error?` | `sample-runbook-view.ts` `question` | new -- needs Planner ruling |
| 5 | Item 6 look-for: `On the Documents page, press Add the sample runbook, or add a short file of your own (nothing personal: Visual Trace on the demo is shared). When it reads Ready, ask in the chat "According to the runbook, what should I do when partner orders fail with a date error?", or ask about your own file, and look for the chip under the answer that names the document and its section.` | `more-to-try-view.ts` `documents.lookFor`, its pins, EXPERIENCE.md Item 6 | new -- needs Planner ruling (replaces 20.2's text 9) |
| 6 | EXPERIENCE.md controls sentence, appended after `Items 6 and 8's controls are links to the Documents page.`: `While the visitor has no documents, each is instead an "Add the sample runbook" button, which opens the Documents page and presses that page's Add the sample runbook.` | EXPERIENCE.md :254 | new -- needs Planner ruling |
| 7 | EXPERIENCE.md hand-off rule, clause added after "item 4 turns the Demo view switch off and leaves focus on it;": ` items 6 and 8, while the visitor has no documents, open the Documents page and press its Add the sample runbook, with focus on it;` | EXPERIENCE.md :255 | new -- needs Planner ruling |
| 8 | EXPERIENCE.md Step 3 bullet after the Adding line: `- **Sample:** an **Add the sample runbook** button beside Add documents adds a short runbook about the demo's Orders feed, which ships with the page, through the same upload. It shows only while the list holds no "Sample runbook.md".` | EXPERIENCE.md after :980 | new -- needs Planner ruling |
| 9 | (optional; the Planner decides whether it lands) README bullet, appended LAST under "New since 1.0.0": `- **A sample runbook in one press.** No file to hand? On the Documents page, press Add the sample runbook: a short runbook about the demo's Orders feed is added through the same upload as any file. When it reads Ready, ask "According to the runbook, what should I do when partner orders fail with a date error?" and look for the chip under the answer that names the runbook and its section. Try it: More to try, *Ask about a document*.` | `README.md` after L41 | new -- needs Planner ruling |
| -- | Shown but not new: the chip "Sample runbook § When orders fail with a date error" and its name "Sample runbook, section When orders fail with a date error" (20.2's ruled formats); "Indexing…", "Ready", "Couldn't read it: {reason}", BUSY_NOTICE | -- | existing |

Runbook text (row 3), verbatim:

```markdown
# Sample runbook: the demo's Orders feed

This sample comes with OcuTalon's web app. It covers the Orders production that the demo runs in namespace OCUORDERS, where a simulated partner sends orders.

## How orders flow

The partner's orders arrive at PartnerOrdersIn. OrdersFromPartner turns each order into a warehouse order, and OrdersToWarehouse takes the orders that pass. Each order has a number such as PO-0001, an item and a quantity.

## When orders fail with a date error

OrdersFromPartner accepts an order date written YYYY-MM-DD and nothing else. When the partner sends dates in another format, such as MM/DD/YYYY, each of those orders fails with "The order date was not in the expected format." Break the feed plays this out with 50 orders.

1. Read the error of one failed order to see the format the partner sent.
2. Rewrite each failed order's date as YYYY-MM-DD and resend it.
3. Check how many orders went through to OrdersToWarehouse.

Then ask the partner to go back to YYYY-MM-DD, so that the next batch does not fail.

## When the Results partner changes its certificate

The Results partner gives notice before the TLS certificate on its results endpoint changes. Load the new certificate before the change, so that results keep flowing.
```

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` / `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=20 stage=implement'`. The fresh tag is `e20s3i`. No IRIS class changes, so no warm stack is needed.

Run one command per tool call, sized to about 150 s. A fresh stack started in 259 s in this stage under load, so a `live` call can pass that. If it is moved to the background, wait in bounded foreground polls before doing anything else. IRIS runs only on lane-B throwaways.

**Commands:**
- (loop) `node --test web/scripts/sample-runbook-view.test.mjs web/scripts/documents-view.test.mjs web/scripts/more-to-try-view.test.mjs web/scripts/more-to-try-sources.test.mjs web/scripts/sources-docs.test.mjs web/scripts/ux-strings.test.mjs web/scripts/announce-focus-sources.test.mjs` -- all pass.
- (loop) `node --test ci/mock/test/` -- passes (the new scenario loads with no problem line).
- (loop) e2e:
  - Build once after web changes: `$LANE OCUTALON_RUN_TAG=e20s3i ci/iris.sh build`.
  - Pick the part: `npm --silent --prefix web run e2e -- --list --reporter=json > "$SCRATCH/chromium.json"` and `node web/scripts/e2e-part.mjs k/n "$SCRATCH/chromium.json"`. `$SCRATCH` is a folder of the session scratchpad. Pick n (e.g. 20) and the k that holds `e2e/documents/sample.spec.ts`.
  - Run it: `$LANE OCUTALON_RUN_TAG=e20s3i ci/iris.sh live sign-in --part k/n` -- the part passes.
  - Repeat for `e2e/guide/more-to-try-sample.spec.ts` and `more-to-try.spec.ts` with `npm --silent --prefix web run e2e:sign-in-3 -- --list --reporter=json` and `ci/iris.sh live sign-in-3 --part k/n`.
  - Teardown: `$LANE OCUTALON_RUN_TAG=e20s3i ci/iris.sh teardown`.
- (once) `npm --prefix web test`; `npm --prefix web run lint`; `npm --prefix web run build` -- each passes.
- (once) `bash ci/checks.sh` (in batches of its CHECK_SCRIPTS if one call cannot hold it) -- every block passes, `test-boundaries.sh` (Rule 14) included.
- (once) `bash docker/tests/test-mock.sh` -- passes.

**Mutations to record (Rule 19), one per AC, each observed red and reverted byte-identical:**
- The sample `File` built from `''` -> E1 red (body/refused `empty`).
- `sampleListed` ignoring server rows -> `documents-view.test.mjs` and E3 red.
- `sampleFirst` forced false -> G1 red. `SampleRunbook.none` ignoring live events -> G1's flip red.
- The guide press without `ask()` -> G2 red.
- The scenario query changed to "How do I reset my password?" -> E1's chip red. The question and query differing -> `sample-runbook-view.test.mjs` red.
- `ServerButton` swapped for a plain `<button>` -> E1's busy and one-POST assertions red.
- `addSample` swallowing the error without `refuse` -> E2 red.
- A ruled string changed by one word -> `ux-strings.test.mjs` / `sources-docs.test.mjs` red.

**Shared surfaces:**
- The More to try controls of items 6 and 8 and item 6's look-for: `more-to-try-view.test.mjs`, `more-to-try-sources.test.mjs` counts, `more-to-try.spec.ts` ITEMS oracle and K3, `sources-docs.test.mjs`, EXPERIENCE.md.
- `DOCUMENTS_TEXTS` and `IMPORTED`/`SOURCES`: `ux-strings.test.mjs`.
- The focus-call counts: `announce-focus-sources.test.mjs`.
- The Documents page's `.bar` Tab order: `documents.spec.ts` D5.
- The instance document list on the sign-in stacks: `documents.spec.ts` D2's empty text and `sources.spec.ts` S5. Every case removes its own documents.
- The mock's scenario set: `ci/mock/test`. A warm stack refuses after a `ci/mock` change: `warm down`/`up`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
