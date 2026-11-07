# Epic 34 Context: Step 3's contracts, and a Documents page (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic fixes step 3 (memory and documents) in the spine and in code as stubs, and gives users a Documents page where they add and remove Markdown, plain-text, PDF and Word documents, so that Epics 19 (Lane A) and 20 (Lane B) can build in parallel. Stories 34.1 to 34.3 are done and merged. The epic is re-opened as a fix-forward for Story 34.4, a test-only story in Lane B's files. The Documents page's keyboard browser test (D5) times out now and then waiting for the file chooser. The story finds the cause and makes D5 fail only when the page is really wrong, so that a red browser job means a real defect. It must land before the 1.0.3 cut, within a 90-minute timebox.

## Stories

- Story 34.1: Settle step 3 ownership and fix its contracts (done)
- Story 34.2: Add and remove documents on a Documents page (done)
- Story 34.3: Epic 34 burn-down (done)
- Story 34.4: The keyboard add-documents test is stable (DW-825)

## Requirements & Constraints

- **What D5 must still prove (34.4).** The test is D5 in `web/e2e/documents/documents.spec.ts`, "Add documents works by keyboard, and a .png is refused with its reason". It must still show that:
  - Tab reaches **Add documents**;
  - Enter on it opens the file chooser;
  - a .png sent through the real documents route comes back refused with its reason, shown on its row ("Couldn't read it: {reason}") and announced exactly once.
  No assertion may be deleted or weakened, and a longer timeout on its own does not count as a fix.
- **Find the cause first.** Record the root cause of the missed `filechooser` event, with evidence. The fix is test-only. If the cause turns out to be in the Add documents control itself (a product defect), stop and get the Planner's ruling before you change product code.
- **Proof of the fix.**
  - D5 passes 20 of 20 with `--repeat-each=20` under the browser job's load, or under an equivalent load that you document.
  - The old D5 fails at least once under the same repeat and load.
  - Full CI is green on every workflow.
- **Keyboard parity and the file picker.** Every function works with the keyboard alone. The Add documents file picker is always there, so drag-and-drop is never the only way to add a file.
- **One announcer.** A single polite live region carries every announcement, and each event is announced once. Live content never moves keyboard focus.
- **Refusals.**
  - A file that isn't Markdown, plain text, PDF or Word, or a PDF or Word file over 10 MB, is refused. The route answers 400 `bad_document` with a reason code such as `wrong_type`, `too_large` or `empty`, or 413 `body_too_large` for a body over the route's bound.
  - Refusals are enforced before any `OcuTalon.Data.Upload` row is written.
- **Isolation.** A session sees only its own documents and uploads. No endpoint accepts a `SessionRef` from the client.

## Technical Decisions

- **Documents REST.** `/ocutalon/api/v1/documents` is forwarded to `OcuTalon.Web.Documents`.
  - `GET` returns `{"documents": [...]}`, newest first.
  - `POST` takes `{name, content}` with `content` in base64. The extension decides the `ContentType`.
  - `DELETE /:ref` answers 404 for a ref the caller can't see.
  - Errors are `{"error": {"code", "message"}}`. State-changing calls keep the browser envelope.
- **Body bounds.** Every API route has a 256 KB body limit. The documents upload declares its larger bound (about 14 MB) in `XData BodyBounds` in both `Web.Api` and `Web.Documents`.
- **Live status.** Document rows update live from `document` events, which `DocumentOps` alone publishes. A row's status reads "Indexing…", "Ready" or "Couldn't read it: {reason}".
- **Browser test conventions.**
  - Playwright 1.64.x. Specs live under `web/e2e/`.
  - A test for an unbuilt part is written as a `notBuilt(title, 'N.M')` call naming the story that turns it on. A turned-on test that must never skip again carries `@floor`.
  - The accessibility floor's specs (`web/e2e/floor/`) run only in their own unit `live:floor`, never in `live:sign-in`.
- **Lane ownership.** Lane B owns `.github/workflows/ci.yml` (builds, `%UnitTest` shards, checks, the `web` job and the demo path), the web app, its Playwright runner configuration and fixtures, `Data.Upload` and `Data.Ownership`. Story 34.4 stays in Lane B's files, as Story 34.2 did. Only the owning lane edits a class.
- **Conventions.** Persistent classes commit their `Storage` block, and storage is append-only. Times are rendered only through `OcuTalon.Data.Time`.

## UX & Interaction Patterns

- The page is titled "Documents · OcuTalon" and is reached from "Documents" in the header. Each row shows the document's name, date added, size and status. With no documents the page reads "No documents yet. Add a runbook to get cited answers."
- **Add documents** is a button that opens a file picker, with drag-and-drop as a second way. Focus handling, overlays and announcements use the Angular CDK.
- Removing a document asks "Remove '{name}'? Answers will stop citing it." Confirming removes the row.

## Cross-Story Dependencies

- Story 34.4 tests the Documents page and route that Story 34.2 built and Story 34.3 hardened. It changes no contract, so Epics 19 and 20 are unaffected.
- The fix ships in the 1.0.3 release, so it must merge before that cut.
