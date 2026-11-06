# Epic 19 Context: OcuTalon remembers, and answers from your documents (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic builds step 3's Lane A behaviour on the names, tables and stubs Epic 34 fixed. A user tells OcuTalon to remember something, and it recalls it later by meaning or by keyword, offline, from OcuTalon's own database. OcuTalon also answers from added Markdown, plain-text, PDF and Word documents, cites the document and section it used, and says so when no document is relevant. On the online demo each session's documents and memories stay its own and go at sign-out or the reset. This turns OcuTalon from a stateless assistant into one that knows the user's systems and runbooks, with every vector computed on the instance and nothing leaving IRIS. The epic ships in the first daily release after it merges, which is after 1.0.0.

## Stories

- Story 19.2: Compute embeddings offline in a worker
- Story 19.3: Remember, recall, list and forget in the chat
- Story 19.4: Answer from documents with citations
- Story 19.5: Keep each online-demo session's documents and memories to itself
- Story 19.6: Extract text from PDF and Word files with Embedded Python
- Story 19.7: Answer from PDF and Word documents

## Requirements & Constraints

- **Offline embeddings.** On a fresh Docker install with all outbound network access blocked, storing and recalling a memory works on first use. The model ships in the image. An IPM install downloads it once, during the install, and later starts and upgrades don't download it again. The release candidate's clean-machine rehearsal checks this.
- **Memory.** A memory belongs to the user who stored it (on the online demo, to the session). No one else recalls it. Users list, search and forget memories in the chat. A forgotten memory is gone from search at once, and the reply confirms "Forgotten." An answer drawn from memory says so.
- **Documents.** An answer from documents cites each document and section used. With no relevant document the reply says exactly "None of your documents cover that." and cites nothing. On a local install documents are shared by every user; on the online demo each session's are its own. A removed document leaves search at once and is cited no more.
- **Size limits.** At most 5 passages per model request and at most 5 memories per recall. No model request may exceed 100,000 input tokens, and no single tool result may pass more than about 10,000 tokens. PDF and Word files are limited to 10 MB. Extracted text is cut at a fixed size, and the result says when it was cut.
- **Extraction failures.** Encrypted, damaged, text-less PDF, legacy `.doc` or timed-out files fail with a plain reason that fits "I couldn't read that file: {reason}.", and nothing is stored from them. The reason texts are not yet specified (a planning warning).
- **Data stays home.** Memory, document and knowledge-base globals, and `^IRIS.IF.*`, must live in the private database. Every start's private-data check fails otherwise.
- **Durability.** Memories and documents survive an IRIS or container restart and an in-place upgrade. From this release on, the upgrade harness creates a memory and a document before the upgrade and checks that both are searchable after it.
- **Evaluation.** The real model is checked on the no-coverage answer and on the runbook question about rotating the Results certificate, whose answer cites "Results runbook § Rotating the certificate".

## Technical Decisions

- **Embedding.** `OcuTalon.Memory.Embedding` is an `%Embedding.Interface` class over the Python `fastembed` 0.9.0 package (AllMiniLM-L6-v2, 384 dimensions). Its vectors are identical to AI Hub's for the same text, so `EMBEDDING()` and embedding columns work. AI Hub's `FastEmbed.EmbedBatch` throws on build 154, and `%Embedding.SentenceTransformers` is rejected because it needs torch.
- **Model path.** The image bakes the model into a root-owned, read-only folder named by `FASTEMBED_CACHE_DIR`. On an IPM install, the Memory area's installer step downloads it into `<mgr>/fastembed/`. A package can't set the IRIS process environment, so OcuTalon passes that folder as `cache_dir` and also sets `FASTEMBED_CACHE_DIR` inside its own worker before `FastEmbed.Create()`. This was measured for AI Hub's FastEmbed on ARM64 only. That the Python package reads the same folder, and that it works on x64, are both unproven until Story 19.2 measures them.
- **Workers, never the caller.** Python runs only in `%SYSTEM.WorkMgr` workers:
  - `OcuTalon.Memory.Embedder` runs one or two workers of about 220 MB each.
  - `OcuTalon.Docs.Extractor` runs one worker for `OcuTalon.Docs.Extract`, which uses `src/ocutalon/python/ocutalon_extract.py` (pdfplumber 0.11.10, python-docx 1.1.2).
  - The area install step creates both categories through `Config.WorkQueues`.
  - Python comes only from `.py` resources imported with `%SYS.Python.Import`, never `[Language = python]` methods. A CI check fails any Python or `%SYS.Python` reference in a tool, policy or renderer class.
- **Memory store.** `OcuTalon.Data.Memory` holds `Ref`, `SessionRef`, `Text` (at most 2,000 characters), `SavedAt`, and the `ItemId` and `Origin` of the saving turn, plus `Embedding VECTOR(DOUBLE,384)`. Story 19.3 appends an HNSW (cosine) index and an `%iFind` index and checks where their globals land. Ranking is reciprocal-rank fusion with k = 60 over the 20 nearest by cosine and the 20 best keyword hits, equal weights, top 5, ties going to the newer `SavedAt`. The HNSW plan is verified at 10,000 memories of one owner. Storage is append-only.
- **Operations and commands.**
  - `MemoryOps` (`OcuTalon.Memory.Ops`) answers `SaveMemory` and `ForgetMemory`, both accepted from origin `tool` only, with the bridge-context owner check.
  - `DocumentOps` (`OcuTalon.Docs.Ops`) answers `AddDocument` (`Name`, `ContentType`, `UploadRef`) and `RemoveDocument`, both from origin `web_user` only, synchronously with a `CommandResult`. It indexes asynchronously.
  - Both are disabled stubs that their stories enable.
  - Reads go through `OcuTalon.Memory.Search(sessionRef, query, limit, *rows)` and `.List(sessionRef, *rows)`.
  - Tools submit through `Commands.Submit` with an idempotency key.
- **Documents.**
  - The knowledge base is `%AI.RAG.KnowledgeBase` over `%AI.RAG.VectorStore.IRIS` with FastEmbed. A chunk's `source` is the document's `Ref`, and citations come from `source` and `chunk_index`.
  - `DocumentOps` takes the bytes with `OcuTalon.Data.Upload.Take(ref, sessionRef)` (Lane B). An empty answer means a failed row.
  - `OcuTalon.Data.Document` stores the text, and Story 19.4 appends the passage-to-section map, where a section is the `##` heading a passage falls under.
  - Failed rows carry the code `unreadable`, `not_built` (PDF and Word until Story 19.6) or `failed`.
  - `DocumentOps` is the single publisher of the `document` live event (`OcuTalon.Live.Payload.Document`, built by `FromRow`, with `removed` true on the last event of a removed document).
- **Knowledge-base tables.** `OcuTalon.Docs` alone creates them, with AI Hub's exact columns and `DEFAULTGLOBAL` under `^OcuTalonP.`, before AI Hub's `Build()`. The tables are `OcuTalonKB.Docs` (local) or `OcuTalonKB.S<id>` (per demo session, where `<id>` is the `Data.Session` row id), each with its `_Config`. The globals are `^OcuTalonP.KB<suffix>` and `...Config`. AI Hub's own DDL, or a build on a missing table, would put the globals in the data database, so a dropped table is never reopened. The CI rule `kb-ddl` enforces this.
- **Tools and the gate.**
  - Tool names are `save_memory`, `search_memories`, `list_memories`, `forget_memory` and `documents` (the knowledge base's `Name`, `TopK` at most 5). Each goes into `OcuTalon.Tools.Names` and the CI mock's scripts.
  - Results go through `OcuTalon.Tools.Result` as dynamic objects or plain text, never pre-encoded JSON.
  - The gate clamps `top_k` to 5 on document search.
  - Saving is refused in an untrusted or tainted turn.
  - Document results are never trusted output, so they taint the turn.
  - A recall is trusted output only when every memory it returns was saved in a user's untainted turn.
- **Citations and memories on the reply.** Lane A's runner side puts `citations` and `memories` on the bridge `Reply`'s `HostData`, beside `checks`. Code builds them from the turn's tool results, never from model text, and leaves them out when empty.
  - `citations` holds one `{documentRef, document, section, passage, chunkIndex}` per distinct passage, in order, at most 5.
  - `memories` holds one `{memoryRef, text, savedAt}` per memory, at most 5.
  - A reply with citations never says "None of your documents cover that.", and that reply carries no citations. Tests cover both directions.
- **Per-turn tools (Story 19.5).** The bridge extension `TurnToolsClass` has base `OcuTalon.Bridge.Ext.TurnTools` and method `Tools(ownerRef, kind, Output tools As %ListOfObjects)`, which returns an empty list by default. It is a setting on `Decide` read through `Ext.Accessor.ClassFor`, whose `BASES` gains the pair. `OcuTalon.Docs.TurnTools` returns the owner's knowledge base for a `turn` request. The adapter builds a fresh tool manager every turn, in the method that composes the session config, before `OpenSession`. The manager holds the agent's tools, the knowledge base, the gate, the audit policy and the MCP toolsets attached in `OnAfterAgentInit`. A long-lived manager would leak one visitor's documents to another. With the default, the standalone bridge still runs.
- **Removal.** The demo reset restores a golden copy that holds no session data, and no code runs at the reset. Sign-out runs Lane B's `SessionOps.End`, which calls `OcuTalon.Docs.DropSession(sessionRef)` and `OcuTalon.Memory.DropSession(sessionRef)`. Story 19.5 replaces their stub bodies. Both must be idempotent and must touch no other session's data.
- **Ownership.** A new table, item or event goes into the spine's ownership tables in the same change. Lane A edits only Lane A classes. `Data.Upload`, `Data.Ownership`, `Web.Documents` and `Conversation` are Lane B's.

## UX & Interaction Patterns

- Memory lives in the chat. An answer from memory carries a "From memory" chip, whose popover shows the text and date. Labels state provenance ("Sources", "From memory"), never "used", "relied on" or "based on".
- Answers from documents end with citation chips such as "Results runbook § Rotating the certificate". Lane B (Story 20.2) renders the chips; this epic only supplies the data.
- Document status on the Documents page ("Indexing…", "Ready", "Couldn't read it: {reason}") is driven live by the `document` events this epic publishes.

## Cross-Story Dependencies

- **Epic 34 (merged).** This epic builds on its names, tables and stubs; on its command verbs, `CommandsIn` routing and documents routes; on `Data.Upload`; and on its Dockerfile pins (`fastembed`, the baked model, `pdfplumber`, `python-docx`).
- **Story 19.2** comes before 19.3 and 19.4, which need vectors. Its IPM download relies on Epic 15 (done).
- **Story 19.5** needs Epics 13, 16 and 17 merged: the `OcuTalon.BridgeExample` standalone job, `SessionOps.End`, and Story 17.3's change to the adapter method that composes the session config. Epic 17 is still in backlog, so 19.5 waits on it. Story 35.1 later depends on 19.5's per-turn tool manager to carry its MCP servers.
- **Story 19.6** needs Epic 15 (done). Until the image pins are present, its tests install `pdfplumber` and `python-docx` with the same `pip install --target` line.
- **Story 19.7** follows 19.6 and indexes what it extracts. It reruns 19.6's tests on the real image with no test-setup install, and its CI mock scenarios live under `ci/mock/scenarios/A/`.
- **Downstream.** Epic 20 (Story 20.2) carries `citations` and `memories` onto `chat.message`, and Epic 41 extends `Data.Memory` and `MemoryOps`.
