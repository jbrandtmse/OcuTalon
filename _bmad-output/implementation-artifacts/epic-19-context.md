# Epic 19 Context: OcuTalon remembers, and answers from your documents (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

OcuTalon keeps a user's memories and documents in its own IRIS and embeds them offline. It recalls memories by meaning or keyword. It answers from Markdown, plain-text, PDF and Word documents, cites the document and section, and says "None of your documents cover that." when nothing is relevant. Part 1 is merged: the embedding worker, the chat memory tools, PDF and Word extraction, and the install-accuracy burn-down. Story 19.4, documents with citations on a local install, is done on this branch. Two stories remain. Story 19.5 makes documents and memories safe on the online demo, where each session's data must stay its own. Story 19.7 lets PDF and Word files join the knowledge base with the same citations.

## Stories

- Story 19.1: moved to Story 34.1
- Story 19.2: Compute embeddings offline in a worker (merged)
- Story 19.3: Remember, recall, list and forget in the chat (merged)
- Story 19.4: Answer from documents with citations (done)
- Story 19.5: Keep each online-demo session's documents and memories to itself
- Story 19.6: Extract text from PDF and Word files with Embedded Python (merged)
- Story 19.7: Answer from PDF and Word documents
- Story 19.8: Epic 19 burn-down (merged)

## Requirements & Constraints

- **Ownership.**
  - On a local install, every user shares the documents (`OwnerRef` `instance`). Memories belong to each IRIS user's durable session.
  - On the online demo, each session's documents and memories are its own. When two concurrent sessions ask a question both could match, each gets only its own passages and memories.
- **Ending a session.**
  - Sign-out drops the session's knowledge-base tables, its documents and its memories. Each drop is idempotent, touches no other session, and never reopens or rebuilds a dropped table.
  - A reset restores a golden copy that holds no session tables or memories, and it runs no code.
- **Citations.**
  - A reply cites each document and section it used.
  - A model request retrieves at most 5 passages, and a reply carries at most 5 citations.
  - When nothing is relevant, the reply says exactly "None of your documents cover that." and cites nothing. It never has both the sentence and citations. Code decides this from the same turn's `documents` results, and tests cover both directions.
  - A removed document leaves search at once.
- **Size.** No tool result passes 10,000 tokens to the model, and no request exceeds 100,000 tokens.
- **Trust.** Document results are never trusted output. The turn is tainted, the next turn is quarantined, and a later `save_memory` in the same turn is denied.
- **Durability.** Memories and documents survive a restart and an in-place upgrade. From 19.5 on, the `release/` upgrade harness creates a memory and a document before the upgrade, and checks that both are present and searchable after it.
- **Data stays home.** Every knowledge-base and memory global resolves to the private database (`^OcuTalonP.`). Embedding works with outbound network blocked.
- **Evaluation documents.**
  - They must not be retrievable in a person's chat turn while a run is in flight (DW-901).
  - A crash must not leave them stranded: add a start-of-run sweep of the `eval` rows (DW-900).
- **Demo feature list.** `Demo.Features` lists documents on the demo, where `AddDocument` answers `not_built` until 19.5 builds per-session documents (DW-892).
- **PDF and Word.**
  - Files are limited to 10 MB.
  - A failure stores nothing and gives a reason that fits "I couldn't read that file: {reason}."
  - 19.7 runs 19.6's extraction tests on the real image, where `pdfplumber==0.11.10` and `python-docx==1.1.2` are pinned, with no test-setup install.

## Technical Decisions

**As built by 19.4: extend it, never copy it.**

- **DocumentOps** (`OcuTalon.Docs.Ops`) owns `Data.Document` and the knowledge-base tables, and is the only publisher of the `document` event.
  - It never calls `KnowledgeBase.AddDocument`, `AddDocuments` or `ReindexDocument`.
  - `Docs.Passages.Split` splits the text: a `## ` line opens a section, a passage holds at most 1,000 characters, and `\## ` is an escaped literal line.
  - `Docs.Embedding` embeds each passage. It is an `%AI.RAG.Embedding` over `Memory.Embedding.Embed` in the 19.2 worker.
  - Rows are inserted by SQL: id `<Ref>:<n>`, `source` the `Ref`, metadata `{source, chunk_index, document, section}`. A message carries eight passages, and DocumentOps sends itself `Docs.Msg.Index` for the next batch.
  - `Data.Document.Sections` maps each `chunk_index` to its section.
  - `IndexBatch` is the shared split, embed and write step.
- **Python and native calls.**
  - `FastEmbed.Create()` and `%SYS.Python` never run in DocumentOps, in the Chat agent's job or in any callback.
  - Callbacks never call AI Hub's native (`%AI`) methods.
  - Python runs only from `.py` resources under `src/ocutalon/python/`, imported with `%SYS.Python.Import`, inside a `%SYSTEM.WorkMgr` worker.
- **Evaluation documents.**
  - Their `OwnerRef` and `AddedBy` are the literal `eval`. `Docs.Ops.AddEval` writes them in `EvalIn`'s own process through `IndexBatch`, and `RemoveEval` removes them at `Finish` (it refuses any other owner).
  - The path uses no command, Session row, origin, upload, event or message, and no route lists these documents.
  - Today they sit in the shared `OcuTalonKB.Docs` table.
- **Classification.**
  - The `documents` call arrives with no `origin_class`. The gate recognises exactly `%AI.RAG.KnowledgeBase` with `documents`, and takes its classification (safe, read-only, not trusted output) from Decide's `ToolClassification`. A call with no entry is held.
  - That value is a System Default Settings row (`OcuTalon.Production` / `Decide` / `*` / `ToolClassification`). `Install.Step.Production.SeedClassification` merges it at every start:
    - it keeps the other entries;
    - it replaces a different entry for that exact pair;
    - it leaves a row that is not a JSON array alone, with a warning.
  - The production class holds structure only. Values an install or an admin may change belong in settings rows, never in item settings in `Production.cls`.
- **Citations.**
  - `OcuTalon.Bridge.Citations` builds `HostData.citations` by code from the turn's results: `{documentRef, document, section, passage, chunkIndex}`, distinct, in order, at most 5, with score floor `CITEFLOOR` 0.4.
  - The ReplyFilter contract is `Filter(text, hostData)`. `ReplyGuard` applies `Docs.Reply.Apply`, which removes the "None" sentence when citations exist.
- **Attaching the documents tool today.** The Chat agent's `%OnInit` calls `Docs.Store.Attach` on a local install only, and attaches nothing on the demo. 19.5 replaces this.

**Story 19.5**

- **Per-session tables.**
  - Each session has `OcuTalonKB.S<id>` and its `_Config`. `<id>` is the `Data.Session` row id, because a SessionRef's `-` is not a valid SQL identifier.
  - Their globals are `^OcuTalonP.KB<suffix>` and `^OcuTalonP.KB<suffix>Config`.
  - `OcuTalon.Docs` creates both tables by SQL, with AI Hub's exact columns and `DEFAULTGLOBAL`, before `Build()`. Building on a missing table re-creates it in the data database.
  - CI rule `kb-ddl`:
    - every product `CREATE TABLE` carries `DEFAULTGLOBAL` and `^OcuTalonP.`;
    - only the package `OcuTalon.Docs` names `%AI.RAG.VectorStore.IRIS`.
- **Per-turn tools.**
  - The base `OcuTalon.Bridge.Ext.TurnTools` declares `ClassMethod Tools(ownerRef, kind, Output tools As %ListOfObjects) As %Status`, and its default returns an empty list.
  - The setting `TurnToolsClass` goes on `Decide` (category Extensions) and is read through `Ext.Accessor.ClassFor`. `BASES` gains the pair, and a missing named class is an error, never a silent fallback.
  - `OcuTalon.Docs.TurnTools` returns the owner's knowledge base for a `turn` request, and nothing for any other kind.
  - The bridge never names an OcuTalon class.
- **Adapter.**
  - Every turn gets a fresh tool manager: the agent's tools, the knowledge base, the gate, the audit policy and the MCP toolsets attached in `OnAfterAgentInit`.
  - The manager is assigned before `OpenSession`, in the one method that composes the session config. A long-lived manager would keep the first knowledge base bound. This also fixes DW-893.
  - Tests:
    - a fixture toolset attached in `OnAfterAgentInit` appears in the turn's manager;
    - the standalone `OcuTalon.BridgeExample` job still passes.
- **Drops.** `Docs.DropSession` and `Memory.DropSession` replace Story 34.1's stubs. Lane B's `SessionOps.End` already calls both, beside `Upload.DropSession`.

**Story 19.7**

- **Routing PDF and Word.** Until this story, DocumentOps fails PDF and Word adds with `not_built`. 19.7 routes them through `Docs.Extract.Read`, which runs in the Extractor worker, never in DocumentOps' process.
  - `Read` returns `{ok:1, text, cut, markers}`, or `{ok:0, reason}` with a fixed code that `Failure(code)` words.
  - A PDF gets one `## Page n` line per page that has text.
  - A .docx maps Title to `#` and Heading n to n+1 `#` (at most 6), and joins table cells with ` | `. So `Split` sections a PDF by page and a Word file by Heading 1.
  - The file's own `## ` lines must be written as `\## ` (DW-832).
  - Limits: `MAXBYTES` 10,485,760, `MAXTEXT` 200,000 and `MAXUNPACKED` 104,857,600. The file's byte signature decides the parser.
- **Open items.**
  - DW-827: serialise extractor reads, or amend the "one worker" wording.
  - DW-828: bound a single long C call before it starts.
  - DW-831: read Word content controls and nested tables.
  - DW-894: batch or parallelise the embedding (about 0.33 s per passage).

**Lanes, CI and tests**

- Lane A's files only:
  - Lane B's `SessionOps`, `Web.Documents`, `Data.Upload`, `Data.Ownership` and `Msg.Command` are read-only.
  - New mock scenarios go only under `ci/mock/scenarios/A/`.
- In CI:
  - `live:documents` runs in group `shards-3`;
  - lane-a's Bridge and Agent areas run in `shards-5`;
  - its remaining areas run in `shards-2`.
- Each test owns its state:
  - in a shared table, assert only on the test's own `source`;
  - snapshot and restore any Decide settings row the test changes (`RunnerFixture.RememberDefault` and `RestoreDefaults`).

## UX & Interaction Patterns

- **Citation chips.**
  - A chip reads like "Results runbook § Rotating the certificate".
  - Its popover shows the passage (at most 6 lines), the document, the section and "Open document". Chips render in Story 20.2.
  - Labels state provenance ("Sources", "From memory"), never "used", "relied on" or "based on".
- **The Documents page.**
  - Each row shows the document's name, date added, size and status: "Indexing…", "Ready" or "Couldn't read it: {reason}".
  - Removing asks "Remove 'Results runbook'? Answers will stop citing it."
  - The empty page says "No documents yet. Add a runbook to get cited answers."
- **Adding (Story 19.7).** Once Epic 40 merges, Adding accepts "Markdown, plain text, PDF and Word (.docx) files." (DW-719).

## Cross-Story Dependencies

- **19.5 needs:**
  - Epic 13's standalone bridge job;
  - Story 16.4's `SessionOps.End`;
  - the session-config method that Story 17.3 changed (Epic 17 is merged).
- **19.5 builds on 19.4.** It uses `Docs.Store` for the per-session tables, and replaces the Chat agent's `%OnInit` attach. It closes DW-900 and DW-901, and DW-783 needs a real-stack dry run of `rehearse.sh`'s memory-offline step.
- **19.7 builds on 19.4 and 19.6.** It uses 19.4's add path and splitter, and 19.6's extraction. On the demo its files join the session's own knowledge base, so its demo behaviour depends on 19.5's per-session tables.
- **Downstream:**
  - Story 20.2 carries `citations` and `memories` onto `chat.message` and keeps the "None" consistency on display.
  - Story 25.3 adds **Add to documents** to a file reply.
  - Story 26.2 handles files sent from the chat and Telegram.
  - Story 35.1 attaches MCP servers through the per-turn manager.
