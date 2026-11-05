# Epic 34 Context: Step 3's contracts, and a Documents page (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic fixes step 3 (memory and documents) in the spine and in code as stubs, and gives users a Documents page where they add and remove Markdown, plain-text, PDF and Word documents, so that Epics 19 (Lane A: memory, retrieval, extraction) and 20 (Lane B: citations and memory chips in the chat) can build in parallel. It exists only so step 3's two contract stories merge together, which breaks the whole-epic pairing deadlock; each story keeps its home lane's files (34.1 Lane A, 34.2 Lane B). It also confirms the ownership decision for step 3 data and checks that the FastEmbed model is found offline on an IPM install before any document code is written.

## Stories

- Story 34.1: Settle step 3 ownership and fix its contracts
- Story 34.2: Add and remove documents on a Documents page

## Requirements & Constraints

- **Who owns step 3 data (already decided; confirm it everywhere).** Online demo: documents and memories belong to the session and are gone at the reset. Local install: memories per IRIS user (the user's durable session), documents shared by every user (`OcuTalonKB.Docs`). The PRD, the UX open items/assumptions and the spine must all say this.
- **Isolation.** On the online demo a session sees only its own documents, never another's. No endpoint accepts a `SessionRef` from the client; reads and commands go through the ownership API.
- **Sign-out.** On the online demo, `SessionOps.End` also calls `OcuTalon.Docs.DropSession(sessionRef)` and `OcuTalon.Memory.DropSession(sessionRef)`. The reset itself runs nothing: restoring the golden copy removes every session's tables and memories, so no code drops them at the reset.
- **Files.** Accepted types: Markdown, plain text, PDF, Word (.docx). Any other type, or a PDF/Word file over 10 MB, is refused and its row shows "Couldn't read it: {reason}". Until Lane A's extraction (Story 19.6) merges, PDF/Word rows also show that status.
- **Offline embeddings.** On an IPM install with outbound network blocked after install, AI Hub's FastEmbed (documents) must find the model on first use. If it can't by the path below, Story 34.1 stops and puts the gap to the author before any document code.
- **Private data.** Every start's private-data check covers the memory, document and knowledge-base globals and `^IRIS.IF.*`, and fails if any lands in the data database.
- **Accessibility.** Keyboard-only use works for every control; the file picker is always present (drag-and-drop is never the only way); labels and WCAG 2.1 AA contrast.

## Technical Decisions

- **Spine additions (34.1, Lane A), each added to the ownership tables in the same change:** the memory and document operations; the embedding worker category `OcuTalon.Memory.Embedder`; tables `OcuTalon.Data.Memory` and `OcuTalon.Data.Document` (Lane A) plus the knowledge-base tables `OcuTalon.Docs` creates; the `document` live event and its single publisher; the memory and document tool names; the hybrid-ranking parameters; the fourth bridge extension class `TurnToolsClass`; how a reply marks the passages and memories it used; the PDF/Word extraction class in `OcuTalon.Docs` with its own `%SYSTEM.WorkMgr` category and its Python resource under `src/ocutalon/python/`. Record that 34.2 fixes Lane B's verbs, routes and Dockerfile lines, and Story 20.2 carries memories and citations onto `chat.message`.
- **Stubs (34.1).** New production items go in Lane A's region of the single `ProductionDefinition` block, disabled until their story enables them. New persistent tables commit their storage blocks and set `DEFAULTGLOBAL` under `^OcuTalonP.` (register short names). The two `DropSession` methods exist as signatures with stub bodies. A CI check fails any knowledge-base `CREATE TABLE` without the `DEFAULTGLOBAL` rule.
- **Documents design (AD-21).** `%AI.RAG.KnowledgeBase` over `%AI.RAG.VectorStore.IRIS` with FastEmbed; citations from `source` and `chunk_index`. One knowledge base and table per demo session (`OcuTalonKB.S<session>` and its `_Config`), `OcuTalonKB.Docs` locally. `OcuTalon.Docs` creates each table itself with AI Hub's exact columns and private globals, then builds the vector store; never reopen a dropped table. Per turn, `TurnToolsClass` returns the session's knowledge base and the adapter builds a fresh tool manager. The search tool is named `documents`, `TopK` ≤ 5.
- **Memory design.** `OcuTalon.Data.Memory`: `VECTOR(DOUBLE,384)` with HNSW index plus `%iFind` index; reciprocal-rank fusion. Vectors from the Python `fastembed` 0.9.0 package wrapped as `OcuTalon.Memory.Embedding` (`%Embedding.Interface`), always run in the `Embedder` WorkMgr worker, never in the calling process.
- **Model path.** Docker: AllMiniLM-L6-v2 baked into a root-owned, read-only folder named by `FASTEMBED_CACHE_DIR`. IPM: downloaded once into `<mgr>/fastembed/` at install; OcuTalon passes that folder explicitly as `fastembed`'s `cache_dir` and sets `FASTEMBED_CACHE_DIR` inside its own worker before first use (a package can't set the IRIS process environment). Story 34.1 records the check's result in the spine.
- **Lane B contracts (34.2).** Memory and document command verbs in `OcuTalon.Msg`, routed by `CommandsIn` to Lane A's operations under 34.1's names; origin `tool` is accepted only for saving and forgetting a memory. Adding from the page submits with origin `web_user` through `Commands.Submit`. Documents REST routes under `/ocutalon/api/v1/`, added to the spine's REST table; state-changing calls keep the browser envelope (`Content-Type: application/json`, `X-OcuTalon-Request: 1`, matching `Origin`); errors as `{"error": {"code", "message"}}`. The spine doesn't fix how file content travels in the request, so the story decides and records it.
- **Dockerfile (34.2).** Pinned installs with the existing `pip install --target /usr/irissys/mgr/python --only-binary=:all:` pattern: `fastembed==0.9.0`, `pdfplumber==0.11.10`, `python-docx==1.1.2`; licence notices kept; model baked as above. Stack rows for all three already exist.
- **Conventions.** Python only as `.py` resources imported with `%SYS.Python.Import`, never `[Language = python]`. Times in UTC ISO 8601, rendered only through `OcuTalon.Data.Time`. Catalog keys in your own lane's catalog class (`Catalog.Core` for Lane B). Live payloads are full public views keyed by `Ref`, written only through `Live.Publish` after commit. Storage is append-only.

## UX & Interaction Patterns

- Header navigation adds **Documents** (`header-nav-item`, `aria-current="page"`) after Chat and admin-only Settings; page title "Documents · OcuTalon".
- List rows: name, date added, size, status "Indexing…", "Ready" or "Couldn't read it: {reason}", updated live from `document` events (polling on the online demo).
- Empty state: "No documents yet. Add a runbook to get cited answers."
- **Add documents**: file picker, with drag-and-drop on the page as a second way. New rows appear as "Indexing…". The UX text still says "PDF, Word from S6"; the owner moved them to step 3, and Story 34.1 puts that UX change to the author.
- Removal: a modal dialog (focus trapped, first focus on its heading, Esc closes and returns focus) asking "Remove '{name}'? Answers will stop citing it." (fixture: "Remove 'Results runbook'? Answers will stop citing it."); confirming submits the remove command and the row leaves the list.

## Cross-Story Dependencies

- Story 34.2 follows 34.1: it routes to the names 34.1 fixes and calls 34.1's `DropSession` stubs; its tests check both are called with the session's `SessionRef` until Story 19.5 builds them. Online-demo isolation is tested on fixture rows of two sessions until 19.5 merges.
- Story 34.1 needs Epic 15 (IPM install for the model-path check); Story 34.2 needs Epic 33 (header navigation) and Epic 16 (`SessionOps.End`, Story 16.4). All three are merged.
- Downstream: Epic 19 uses 34.1's names, tables and stubs and 34.2's verbs and Dockerfile lines (19.2 the model, 19.3/19.4 the verbs, 19.5 `DropSession`, 19.6/19.7 PDF/Word extraction); Epic 20's Story 20.2 carries 34.1's reply citation/memory shape and links "Open document" to this page.
- Merge gate: Epic 34 merges into the feature branch only once `release/1.0.0-rc1` exists, so no step 3 work enters 1.0.0.
