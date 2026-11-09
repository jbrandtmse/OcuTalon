# Epic 20 Context: Add documents in the web app (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user adds documents from the web app and can see which documents and memories an answer drew on. Story 20.2 is done. Web answers end with citation chips and "From memory" chips, "Open document" shows a document's text, and More to try has an eighth item. Story 20.3 is a voting-week findability follow-up. A demo visitor with no file to hand can add a short bundled sample runbook with one press, ask about it, and see a cited answer. Adding and removing documents (the former Story 20.1) moved to Story 34.2 and is merged.

## Stories

- Story 20.2: See citations and memories in answers (done)
- Story 20.3: Add a sample runbook in one press

## Requirements & Constraints

- **The sample takes the normal path, with no server special case.** The runbook ships with the web app, so nothing is fetched from the network. It is added through the same `POST /api/v1/documents` upload as any file a person picks. From there it goes through `AddDocument` to `DocumentOps` indexing. Its row appears in the list and reaches Ready like any other document. Ownership follows the install:
  - Online demo: the document belongs to the visitor's session.
  - Local install: it is an `instance` document, shared by every user of the install.
- **More to try items 6 and 8** ("Ask about a document", "See where an answer came from"):
  - When the visitor has no documents, the item's control is the sample-runbook button.
  - Once the visitor has a document, the control is the existing "Open the Documents page" link.
  - When the sample is Ready, the item's look-for suggests one question the runbook answers. The answer to that question must carry a citation chip that names the runbook and its section.
- **Accessibility:**
  - The button is a native button with a visible label.
  - It shows a busy state while the upload runs. The project rule for busy buttons: the button keeps its label, gains a spinner, and is set `aria-disabled` and `aria-busy`, never the `disabled` attribute, so it keeps focus. Repeat presses are ignored.
  - A refusal or failure shows the Documents page's existing texts ("Couldn't read it: {reason}" and the route's reason codes).
  - Keyboard use, nothing conveyed by colour alone, and 200% text resizing all apply.
- **Public text:** every new string is PUBLIC TEXT that the Contest Planner rules at the spec gate, verbatim. That covers the button label, the runbook's file name and body, the suggested question, and any changed look-for. Each ruled string goes into the fixed-strings test (`ux-strings.test.mjs` `SOURCES`, with `IMPORTED` covering any new view file). Owner ruling U-280 still binds: labels state provenance and never say "used", "relied on" or "based on".
- **Findability:** README "New since 1.0.0" and More to try change only as the Planner rules. EXPERIENCE.md currently says "Items 6 and 8's controls are links to the Documents page". That line and the items' look-fors need an `[AMENDED …]` marker naming the ruling. The More to try count stays eight unless a ruling adds an item.
- **Route tests:** any new or changed `/api/v1` route needs real-HTTP tests run as an `OcuTalonUser`-only fixture user, with a second-session isolation check. Story 20.3 needs no new route if it reuses the upload.
- **Release check:** the Planner's hands-on pass on the demo verifies the result. Whether a cited answer appears depends on the model calling the `documents` tool (inference).

## Technical Decisions

- **Upload contract (Stories 34.2 and 34.3, as built):**
  - Request body: `{name, content}`, with `content` the bytes in base64.
  - The file extension sets the type: `.md`/`.markdown` is Markdown, and `.txt` is plain text. The sample should be `.md`.
  - Success is 200 `{"result":"done","ref"}`.
  - A refused add returns 400 `bad_document` with a `reason` (`wrong_type`, `too_large`, `empty`) and writes no row.
  - A body over the bound returns 413 `body_too_large`.
  - While `DocumentOps` is not running, the route returns 501 `not_built`.
  - The upload passes through a Lane B `Data.Upload` row that `DocumentOps` takes. Rows nobody takes within an hour are purged.
  - Row status reaches the page through the `document` live event, whose single publisher is `DocumentOps`. Its fields: `ref`, `name`, `addedAt`, `size`, `state` (`indexing`/`ready`/`failed`), `reason` and `removed`.
- **How passages and sections are built (AD-21, Lane A, read-only):**
  - A Markdown `## ` line opens a section, and a passage holds at most 1,000 characters.
  - A passage counts as a citation only when its search score is at least 0.4 (`CITEFLOOR`), with at most 5 per turn.
  - To get chips that read "{runbook} § {section}", write the sample with `## ` sections. Each answerable fact should sit inside one section that the suggested question matches closely.
- **Delivered 20.2 surfaces to reuse:**
  - `Conversation.Sourced` carries `HostData.citations`/`memories` onto the Turn, the Outbound and `chat.message` (and so `/v1/state`).
  - `answer-sources.ts` and `answer-sources-view.ts` draw the chips:
    - Visible label: "{document} § {section}".
    - Accessible name: "{document}, section {section}", with no § sign.
  - `GET /api/v1/documents/:ref` returns `{ref,name,text}` through `Ownership.Document`. It answers 404 for a document the session cannot see.
  - The Documents page opens a document's text with `#/documents?doc=<ref>` and renders it as plain, escaped text.
  - The registry gates More to try items by instance feature ids from `Demo.Features`: `documents`, and `sources` (listed last when memory or documents is built). Those ids say a feature is built, not whether this visitor has documents. That per-session condition must come from the session's own document list or its `document` events, both owner-scoped.
- **Ownership (AD-4, AD-21):** the web layer reads documents only through `OcuTalon.Data.Ownership`. No endpoint accepts a `SessionRef` from the client. On the online demo, a session's knowledge-base table (`OcuTalonKB.S<id>`) is created by its first `AddDocument`. Sign-out drops the session's documents (`SessionOps.End` calls `Docs.DropSession`, `Memory.DropSession` and `Upload.DropSession`).
- **Online demo (AD-25):** the proxy allows only `/ocutalon/*`, so the existing routes are reachable. The IRIS container has no general internet access, which is why the sample is bundled. A reset restores a golden copy that holds no sessions or session tables, so nothing may be seeded server-side. The golden copy stays document-free.
- **Lanes:** Epic 20 works in Lane B's files: the web app, `Web.Documents`, `Conversation`, and Lane B tables. Never edit Lane A classes or tests (U-177): `Docs/**`, `Memory/**`, `Tools/**`, `Checks/**`, `Eval/**`, `src/bridge/**`.
- **Contended files:** `more-to-try-view.ts`, `more-to-try.ts`, `README.md` and the EXPERIENCE.md More to try block are shared with other stories (23.6, Epic 35). Changes to them are additive only.
- **Tests:**
  - New tests go under `OcuTalon.Test.<Area>`, use the CI mock only, and record a mutation for each (Rule 19).
  - The CI mock has documents scenarios (for example `ci/mock/scenarios/A/documents-runbook.json`) for a deterministic cited-answer e2e.
  - Every test must pass on a fresh environment.

## UX & Interaction Patterns

- The sample button is on the Documents page, and More to try items 6 and 8 also offer it. **Add documents**, its file picker and drag-and-drop stay as they are.
- The new row shows "Indexing…" and then "Ready", updated live like any upload. A refusal shows on its row as "Couldn't read it: {reason}".
- More to try rules: each control does exactly what the control it names does. Focus moves only on the user's own press, and the panel announces nothing. A control works by Tab with Enter or Space.
- Citation chip popovers show the passage (at most 6 lines), the document, the section, and "Open document".
- The demo guide's item 6 warns visitors to add "nothing personal: Visual Trace on the demo is shared". The bundled sample avoids that concern.

## Cross-Story Dependencies

- Merged dependencies:
  - Story 34.2/34.3: the Documents page, the upload route, and the `Data.Upload` lifecycle.
  - Stories 19.3 to 19.7: memory, document indexing, per-session knowledge bases, and PDF/Word.
  - Story 20.2: the chips, `GET /documents/:ref` and the `sources` item.
- Story 20.3 changes the controls that 20.2 set for items 6 and 8. 20.2's More to try tests pin those items, and 20.3 must update them: `more-to-try-view.test.mjs`, `e2e/guide/more-to-try.spec.ts` and `sources-docs.test.mjs`, the last of which ties EXPERIENCE.md items to the registry.
- Open question for 20.3's spec: no plan says whether a second press, after a sample already exists, adds another copy. The busy state only blocks presses while an upload runs.
- Ledger items DW-383 and DW-733 were re-owned to burn-down and are not this epic's.
