# Epic 34 Context: Step 3's contracts, and a Documents page (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic fixes step 3 (memory and documents) in the spine and in code as stubs, and gives users a Documents page where they add and remove Markdown, plain-text, PDF and Word documents, so that Epics 19 (Lane A: memory, retrieval, extraction) and 20 (Lane B: citations and memory chips) can build in parallel. Stories 34.1 (Lane A) and 34.2 (Lane B) are done. Story 34.3, a burn-down in Lane B's files, makes the upload holding table that 34.2 introduced safe: an upload that is never indexed leaves nothing behind, a refused file never writes a row, and no one but its owner ever sees it.

## Stories

- Story 34.1: Settle step 3 ownership and fix its contracts (done)
- Story 34.2: Add and remove documents on a Documents page (done)
- Story 34.3: Epic 34 burn-down

## Requirements & Constraints

- **Who owns step 3 data.** On the online demo, documents, memories and uploads belong to the session and are gone at the reset. On a local install, memories and uploads belong to the IRIS user's durable session, and documents are shared by every user (`OcuTalonKB.Docs`, `OwnerRef` `instance`).
- **Isolation.** A session never sees another session's documents or uploads. No endpoint accepts a `SessionRef` from the client. Every REST read and command handler goes through the ownership API (`OcuTalon.Data.Ownership`, Lane B), which applies the caller's `SessionRef` and checks the target's owner again.
- **Orphaned uploads (34.3).** An `OcuTalon.Data.Upload` row older than 1 hour that was never taken must be deleted, either by an existing purge task or by the documents route's next call. A crash between storing an upload and its `Take` must leave nothing behind. A test pins this.
- **Refuse before storing (34.3).** The 10 MB file limit (10,485,760 bytes, all four file types) and the route's body bound (13,985,112 bytes, the 10 MB limit in base64 plus the JSON around it) are enforced before any `Upload` row is written. Tests assert that no row exists after a refused add (400 `bad_document` with `wrong_type`, `too_large` or `empty`, and 413 `body_too_large`).
- **Owner scope and the reset (34.3).** `Upload` rows are scoped to their owner like other session data, and the online demo's reset clears them. Check this once on a throwaway reset and record the evidence. The demo host's deployment and reset scripts live outside this repository.
- **Private data.** Every start's private-data check covers the memory, document and knowledge-base globals and `^IRIS.IF.*`, and fails if any of them lands in the data database.

## Technical Decisions

- **The `Upload` table (Lane B, U-287).** It lives in `^OcuTalonP.Upload` (the private database) with `Ref`, `SessionRef` (compared exactly), `Content` (a global binary stream) and `CreatedAt` (UTC ISO 8601 from `OcuTalon.Data.Time`). It exists because a message body can't hold a global stream, so `AddDocument` carries `UploadRef` and never the bytes.
  - `Web.Documents` stores the row only after its not-running guard has passed and just before it submits. It deletes the row if the submit fails or the owner doesn't answer Ok.
  - `Upload.Take(ref)` returns the bytes as a temporary stream and deletes the row. It returns nothing for an unknown or already-taken `Ref`. Its only consumer is `DocumentOps` (Story 19.4).
  - `Upload.DropSession(sessionRef)` deletes a session's uploads. `SessionOps.End` calls it at sign-out next to `Docs.DropSession` and `Memory.DropSession`.
  - Until Story 19.4 enables `DocumentOps`, both routes answer 501 `not_built` and submit nothing. A valid add therefore never stores a row today.
- **Retention (AD-27).** Retention never uses a hand-written message purge. The OcuTalon task `OcuTalon.Install.Task.Purge` (Lane A, daily at 03:00 instance time, `DaysToKeep` 90) calls each area's `Purge(daysToKeep)` through the install registry. Lane B's web area (`OcuTalon.Install.Step.Web`) already purges `Live.Event` rows after 24 hours and `AddressCounter` rows after one hour, whatever `daysToKeep` says. A fixed-age purge of `Upload` rows fits that pattern. Day counts are task properties, so no purge reads `OcuTalon.Data.Setting`. Because the task runs daily, an orphan can outlive 1 hour by up to a day unless the route also sweeps.
- **The online demo's reset (AD-25).** A reset restores a golden copy of the durable volume, which holds no visitor data: no sessions, pairings, approval requests, live events or CSP sessions. The first golden copy comes from a fresh install, and each release's update captures a new one after an in-place upgrade with no visitor data. Nothing runs at the reset, so per-session knowledge-base tables, memories and uploads are gone because the restore replaced the volume, not because code dropped them.
- **Body bounds (Story 11.22, DW-687).** Every route has a body limit of 262,144 bytes unless the dispatch class's `XData BodyBounds` (a JSON array of `{"method", "url", "bytes"}`) declares a larger one. `Web.BodyLimit` checks it in `OnPreDispatch` before routing and answers 413 `body_too_large`. The documents bound is declared twice, both at `Web.Documents`' `BODYMAX`: in `Web.Api` for `POST /v1/documents` and in `Web.Documents` for `POST ""` (the forwarded dispatch). `Test.Web.DocumentsApi` pins both values.
- **Documents REST (`/ocutalon/api/v1/documents`, forwarded by a `<Map>` to `OcuTalon.Web.Documents`).**
  - `GET` returns `{"documents": [...]}`, read through `Ownership.Documents` as `Live.Payload.Document`, newest first.
  - `POST` takes `{name, content}`, where `content` is base64, read from the request stream and never through a string. The extension is mapped to a `ContentType`. It answers 200 `{"result": "done", "ref"}`, 400 `bad_document`, 413 or 501.
  - `DELETE /:ref` calls `Ownership.Document` first (404 for a ref the caller can't see) and answers 200 `{"result": "done"}`.
  - State-changing calls keep the browser envelope. Errors are `{"error": {"code", "message"}}`.
- **Step 3 names (34.1).** `DocumentOps` (`OcuTalon.Docs.Ops`) and `MemoryOps` (`OcuTalon.Memory.Ops`) are disabled stubs until Stories 19.3 and 19.4. Lane A owns `OcuTalon.Data.Document` (`Ref`, `OwnerRef`, `Name`, `ContentType`, `Size`, `AddedAt`, `State` `indexing`, `ready` or `failed`, `Reason`, `KnowledgeBase`, `Text`) and `OcuTalon.Data.Memory`. A failed document row carries the code `unreadable`, `not_built` or `failed`. `DocumentOps` is the single publisher of the `document` event. `OcuTalon.Docs` alone creates the knowledge-base tables with `DEFAULTGLOBAL` under `^OcuTalonP.`, enforced by the CI rule `kb-ddl`.
- **Citations and memories (U-280).** Code builds a reply's `citations` and `memories` from the turn's tool results, never from model text. A reply that says "None of your documents cover that." carries no citations, and a reply with citations never says it. Labels state provenance ("Sources", "From memory"), never "used" or "based on".
- **Ownership tables (AD-33).** A new table, item or event type goes into the spine's ownership tables in the same change. Only the owning lane edits a class. `Data.Upload` and `Data.Ownership` are Lane B's, so 34.3 stays in Lane B's files.
- **Conventions.** Persistent classes commit their compiler-generated `Storage` block, and storage is append-only. Times are rendered only through `OcuTalon.Data.Time`. Python is used only through `.py` resources.

## Cross-Story Dependencies

- Story 34.3 follows 34.2 and works on the merged route, `Upload` and `SessionOps.End` drop. 34.2's tests check the `DropSession` calls, and Story 19.5 builds the Lane A `DropSession` bodies.
- Story 19.4 (Lane A) is the only caller of `Upload.Take`. Until it lands, tests drive `Take` directly or through the route probe. An orphan sweep must not delete a row that a running `AddDocument` is about to take.
- Downstream:
  - Epic 19 uses 34.1's names, tables and stubs and 34.2's verbs and Dockerfile lines.
  - Story 20.2 carries the citation and memory shape, and its "Open document" link goes to `#/documents`.
- Merge gate: Epic 34 merges into the feature branch only once `release/1.0.0-rc1` exists, so no step 3 work enters 1.0.0. The epic ships in the first daily release after it merges.
