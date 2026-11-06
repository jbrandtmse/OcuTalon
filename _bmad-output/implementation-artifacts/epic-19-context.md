# Epic 19 Context: OcuTalon remembers, and answers from your documents (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic builds step 3's Lane A behaviour on the names, tables and stubs Epic 34 fixed. A user tells OcuTalon to remember something and gets it back later by meaning or keyword, offline, from OcuTalon's own database. OcuTalon answers from added Markdown, plain-text, PDF and Word documents, cites the document and section used, and says so when nothing is relevant. On the online demo each session's documents and memories stay its own and go at sign-out or reset. Every vector is computed on the instance and nothing leaves IRIS. The epic ships in the first daily release after it merges (after 1.0.0).

## Stories

- Story 19.2: Compute embeddings offline in a worker
- Story 19.3: Remember, recall, list and forget in the chat
- Story 19.4: Answer from documents with citations
- Story 19.5: Keep each online-demo session's documents and memories to itself
- Story 19.6: Extract text from PDF and Word files with Embedded Python
- Story 19.7: Answer from PDF and Word documents

## Requirements & Constraints

- **Offline.** On a fresh Docker install with outbound network blocked, storing and recalling a memory works on first use; the model ships in the image. An IPM install downloads it once at install; later starts and upgrades never do. The release candidate's clean-machine rehearsal checks this.
- **Memory.** A memory belongs to its owner (on the demo, the session); no one else lists, searches, recalls or forgets it. Forgetting removes it from search at once and the reply confirms "Forgotten." An answer from memory says so.
- **Documents.** Answers cite each document and section used. With nothing relevant the reply says exactly "None of your documents cover that." and cites nothing. Local-install documents are shared by all users; demo documents are per session. A removed document leaves search at once.
- **Limits.** At most 5 passages per model request and 5 memories per recall; no request over 100,000 input tokens; no tool result over about 10,000 tokens. PDF and Word files at most 10 MB; extracted text is cut at a fixed size and says when cut.
- **Extraction failures.** Encrypted, damaged, text-less PDF, legacy `.doc` or timed-out files fail with a plain reason fitting "I couldn't read that file: {reason}.", and nothing is stored. The reason texts are not yet specified.
- **Data stays home.** Memory, document and knowledge-base globals, and `^IRIS.IF.*`, must be in the private database; the start-up private-data check fails otherwise.
- **Durability.** Memories and documents survive IRIS/container restart and in-place upgrade; from this release the upgrade harness creates one of each before upgrading and checks both are searchable after.
- **Evaluation.** The real model is checked on the no-coverage answer and on the runbook question whose answer cites "Results runbook § Rotating the certificate".

## Technical Decisions

- **Embedding.** `OcuTalon.Memory.Embedding` is an `%Embedding.Interface` class over Python `fastembed` 0.9.0 (AllMiniLM-L6-v2, 384 dims), vectors identical to AI Hub's so `EMBEDDING()` and embedding columns work. AI Hub's `FastEmbed.EmbedBatch` throws on build 154; `%Embedding.SentenceTransformers` is rejected (needs torch).
- **Model path.** The image bakes the model into a root-owned read-only folder named by `FASTEMBED_CACHE_DIR`; an IPM install's Memory-area step downloads it into `<mgr>/fastembed/`. A package can't set the IRIS process environment, so the embedder passes that folder as `cache_dir` and sets `FASTEMBED_CACHE_DIR` inside its own worker before first use. Only measured for AI Hub's FastEmbed on ARM64; the Python package reading the same folder, and x64, are unproven until Story 19.2 measures them.
- **Image hardening gap.** `/usr/irissys/mgr/python` is owned by irisowner (mode 555) in the base image, so the IRIS user could chmod it and replace installed packages (the packages themselves are root-owned and read-only). Story 19.2 carries this.
- **Workers only.** Python runs only in `%SYSTEM.WorkMgr` workers: `OcuTalon.Memory.Embedder` (one or two, ~220 MB each) and `OcuTalon.Docs.Extractor` (one, for `OcuTalon.Docs.Extract` using `src/ocutalon/python/ocutalon_extract.py`, pdfplumber 0.11.10, python-docx 1.1.2). Area install steps create the categories via `Config.WorkQueues`. Python comes only from `.py` resources imported with `%SYS.Python.Import`, never `[Language = python]`; CI fails any Python or `%SYS.Python` reference in a tool, policy or renderer class.
- **Memory store.** `OcuTalon.Data.Memory` (`Ref`, `SessionRef`, `Text` ≤ 2,000 chars, `SavedAt`, saving turn's `ItemId` and `Origin`, `Embedding VECTOR(DOUBLE,384)`), append-only. Story 19.3 adds an HNSW (cosine) and an `%iFind` index and checks where their globals land. Ranking: reciprocal-rank fusion, k = 60, over the 20 nearest by cosine and 20 best keyword hits, equal weights, top 5, ties to newer `SavedAt`. HNSW plan verified at 10,000 memories of one owner.
- **Operations.** `MemoryOps` (`OcuTalon.Memory.Ops`) answers `SaveMemory`/`ForgetMemory` from origin `tool` only, with the bridge-context owner check; it must refuse a `ForgetMemory` whose `MemoryRef` belongs to another `SessionRef` (nothing upstream checks this). `DocumentOps` (`OcuTalon.Docs.Ops`) answers `AddDocument` (`Name`, `ContentType`, `UploadRef`) and `RemoveDocument` from origin `web_user` only, synchronously with a `CommandResult`, and indexes asynchronously. Both start as disabled stubs their stories enable. Reads use `OcuTalon.Memory.Search(sessionRef, query, limit, *rows)` and `.List(sessionRef, *rows)`. Tools submit through `Commands.Submit` with an idempotency key.
- **Disabled-owner wait.** Until MemoryOps is enabled, `CommandsIn` waits its full 120 s timeout on a send to the disabled item; the general fix is a `CommandsIn` `not_built` answer for a disabled owner.
- **Documents.** Knowledge base is `%AI.RAG.KnowledgeBase` over `%AI.RAG.VectorStore.IRIS` with FastEmbed; a chunk's `source` is the document `Ref`, citations come from `source` and `chunk_index`. `DocumentOps` takes bytes with `OcuTalon.Data.Upload.Take(ref, sessionRef)` (empty answer means a failed row). `OcuTalon.Data.Document` stores the text; Story 19.4 adds the passage-to-section map (section = the `##` heading above it). Failed rows carry `unreadable`, `not_built` (PDF/Word until 19.6) or `failed`. `DocumentOps` is the single publisher of the `document` live event (`OcuTalon.Live.Payload.Document.FromRow`, `removed` true on a removed document's last event).
- **Upload lifecycle gaps.** `Data.Upload` has no lifecycle beyond `Take`, the route's delete and sign-out: nothing sweeps abandoned rows on a local install, a `CommandsIn` timeout drops the row while the `AddDocument` may still reach DocumentOps, and `Take` is at-most-once with no session check.
- **Knowledge-base tables.** Only `OcuTalon.Docs` creates them, with AI Hub's exact columns and `DEFAULTGLOBAL` under `^OcuTalonP.`, before AI Hub's `Build()`: `OcuTalonKB.Docs` (local) or `OcuTalonKB.S<id>` (per demo session, `Data.Session` row id), each with `_Config`; globals `^OcuTalonP.KB<suffix>`. AI Hub's DDL, or building on a missing table, would put globals in the data database, so a dropped table is never reopened. CI rule `kb-ddl` enforces this.
- **Tools and gate.** Names `save_memory`, `search_memories`, `list_memories`, `forget_memory`, `documents` (knowledge base `Name`, `TopK` ≤ 5) go into `OcuTalon.Tools.Names` and the CI mock scripts. Results go through `OcuTalon.Tools.Result` as dynamic objects or text, never pre-encoded JSON. The gate clamps `top_k` to 5; saving is refused in an untrusted or tainted turn; document results always taint the turn; a recall is trusted only when every memory returned was saved in a user's untainted turn.
- **Reply data.** Lane A's runner puts `citations` and `memories` on the bridge `Reply`'s `HostData` beside `checks`, built from the turn's tool results (never model text), omitted when empty. `citations`: one `{documentRef, document, section, passage, chunkIndex}` per distinct passage, ≤ 5. `memories`: one `{memoryRef, text, savedAt}`, ≤ 5. Code decides both the "None of your documents cover that." reply and citations from the same turn's documents-tool results: a reply with citations never says it, and that reply carries none; tests cover both directions.
- **Per-turn tools (19.5).** Bridge extension `TurnToolsClass` (base `OcuTalon.Bridge.Ext.TurnTools`, `Tools(ownerRef, kind, Output tools As %ListOfObjects)`, empty by default) is a `Decide` setting read via `Ext.Accessor.ClassFor` (add the pair to `BASES`). `OcuTalon.Docs.TurnTools` returns the owner's knowledge base for a `turn`. The adapter builds a fresh tool manager every turn, before `OpenSession`, in the method composing the session config: agent tools, knowledge base, gate, audit policy and the MCP toolsets attached in `OnAfterAgentInit`. A long-lived manager would leak one visitor's documents to another. The standalone bridge still runs on the default.
- **Removal.** The demo reset restores a golden copy with no session data; no code runs. Sign-out runs Lane B's `SessionOps.End`, calling `OcuTalon.Docs.DropSession(sessionRef)` and `OcuTalon.Memory.DropSession(sessionRef)`, whose stub bodies 19.5 replaces; both idempotent and touching no other session.
- **Ownership.** New tables, items and events go into the spine's ownership tables in the same change. Lane A edits only Lane A classes; `Data.Upload`, `Data.Ownership`, `Web.Documents` and `Conversation` are Lane B's.

## UX & Interaction Patterns

- Memory lives in the chat: an answer from memory carries a "From memory" chip (popover: text, date). Provenance labels ("Sources", "From memory"), never "used", "relied on" or "based on".
- Document answers end with citation chips like "Results runbook § Rotating the certificate"; Lane B (Story 20.2) renders them, this epic supplies the data.
- Documents-page status ("Indexing…", "Ready", "Couldn't read it: {reason}") is driven by this epic's `document` events.
- Story 19.7 updates the UX text (Epic 40 has merged): the Documents "Adding" line and UX-DR144 accept "Markdown, plain text, PDF and Word (.docx) files." in place of "then PDF and Word from step 6", with the local-install ownership line in the UX assumptions.

## Cross-Story Dependencies

- **Epic 34 (done)** supplies names, tables, stubs, command verbs, `CommandsIn` routing, documents routes, `Data.Upload` and the Dockerfile pins (`fastembed`, baked model, `pdfplumber`, `python-docx`).
- **19.2** precedes 19.3 and 19.4 (they need vectors); its IPM download relies on Epic 15 (done).
- **19.3** enabling MemoryOps ends the 120 s disabled-owner wait.
- **19.4** enabling DocumentOps turns web e2e D8 and D10 (`web/e2e/documents/documents.spec.ts`) red, since they expect an error from the real routes; switch them to fulfilled `page.route` answers. No test yet runs the real `Web.Documents` route → `Commands.Submit` → `CommandsIn` path (the OwnerRunning guard answers 501 while DocumentOps is disabled).
- **19.5** needs Epics 13, 16 (done) and 17 (backlog): the `OcuTalon.BridgeExample` standalone job, `SessionOps.End`, and Story 17.3's change to the session-config method; it waits on Epic 17. Story 35.1 later relies on its per-turn manager for MCP servers.
- **19.6** needs Epic 15; until the image pins exist its tests install `pdfplumber` and `python-docx` with the same `pip install --target` line.
- **19.7** follows 19.6, indexes what it extracts, reruns 19.6's tests on the real image without test-setup installs; CI mock scenarios live under `ci/mock/scenarios/A/`.
- **Downstream.** Epic 20 (Story 20.2) carries `citations` and `memories` onto `chat.message`; Epic 41 extends `Data.Memory` and `MemoryOps`.
