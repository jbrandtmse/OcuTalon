# Epic 19 Context: OcuTalon remembers, and answers from your documents (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

OcuTalon answers from added Markdown, plain-text, PDF and Word documents, cites the document and section, and says so when nothing is relevant; every vector is computed on the instance. Part 1 is merged (memory: `OcuTalon.Memory.*`, `Tools.MemoryTools`, `Tools.HostData`, the `Memory.Worker` base; extraction: `Docs.Extract`/`Extractor`). Part 2 builds documents on it and on Epic 17's merged bridge. The order is 19.4, then 19.5 (including `Memory.DropSession`), then 19.7's documents side. 19.7 may run on a second runner after 19.4, but only if the 19.5 and 19.7 specs share no files: list the footprints.

## Stories

- Story 19.1: moved to Story 34.1
- Story 19.2: Compute embeddings offline in a worker (done)
- Story 19.3: Remember, recall, list and forget in the chat (done)
- Story 19.4: Answer from documents with citations (part 2; spec `blocked`, rulings recorded)
- Story 19.5: Keep each online-demo session's documents and memories to itself (part 2)
- Story 19.6: Extract text from PDF and Word files with Embedded Python (done)
- Story 19.7: Answer from PDF and Word documents (part 2)
- Story 19.8: Epic 19 burn-down (done)

## Requirements & Constraints

- **Citations.** A reply cites each document and section it used. When nothing is relevant it says exactly "None of your documents cover that." and cites nothing. A reply with citations never contains that sentence. Code decides both from the same turn's `documents` results, and tests cover both directions.
- **Limits.** A `documents` call returns at most 5 passages (the gate clamps `top_k`) and a reply carries at most 5 citations. All tool results of one model step stay within 10,000 tokens, `documents` results included.
- **Ownership.** A local-install document has owner `instance` and is shared, with `AddedBy` set to the adding session. On the online demo each session has its own knowledge base. A removed document leaves search at once, and no later reply cites it.
- **Isolation.** Concurrent demo sessions see only their own passages and memories. Sign-out drops are idempotent and session-scoped; a reset restores the golden copy and runs no code; a dropped table is never reopened.
- **Durability.** Documents and memories survive a restart and an in-place upgrade. From 19.5 on, the `release/` upgrade harness creates a memory and a document before the upgrade, and both are present and searchable after it.
- **Data stays home.** Every knowledge-base global resolves to OCUTALON_PRIVATE, and `^IRIS.KNNIndex` stays empty.
- **Taint.** Document results are never trusted output. The turn is tainted, the next turn is quarantined, and a later `save_memory` in the same turn is denied.
- **Tests.** Each test owns its state and passes fresh, in either order; mock scenarios go under `ci/mock/scenarios/A/`; 19.7 runs 19.6's tests on the real image with no test-setup install. The real-model release eval is the owner's gate, never run by a runner.

## Technical Decisions

- **19.4's re-dispatch.** Epic 17 has merged: reset `status` to `ready-for-dev` if the plan stands with the rulings, else `draft`, then the lead's spec gate. Its Code Map line numbers predate Epic 17 (`Converse` and the session-config method moved).
- **Indexing.** `DocumentOps` writes the passages itself. No `KnowledgeBase.AddDocument`, `AddDocuments` or `ReindexDocument`, measured as follows: a repeated add replaces every chunk of a `source`, and AI Hub's chunker neither sections nor bounds passages.
  - `Passages.Split` splits on `##` headings. `MAXPASSAGE` is 1,000 characters, and indexing proceeds in self-queued batches of 32.
  - Each row has id `ref:n` and metadata `{source, chunk_index, document, section}`. `Data.Document` appends the section map, and its storage may only grow.
  - `OcuTalon.Docs.Store` alone holds the DDL and names `%AI.RAG.VectorStore.IRIS`.
- **Embedder (approved).** `OcuTalon.Docs.Embedding` is an `%AI.RAG.Embedding` over `Memory.Embedding.Embed` in the 19.2 worker. AI Hub's `FastEmbed.Create()` is not used, and no `%SYS.Python` runs in `DocumentOps` or the ChatAgent job. Conditions:
  - The `CITEFLOOR` value and the measurement behind it go in the spec and an evidence file.
  - Tests cover both sides of the floor.
  - Adding X a second time replaces only X's passages.
- **19.4 Task 0** measures the in-turn query path, the gate's inputs, the `top_k` rewrite and the floor; its stop rule halts on a crash or recycled job, a missing `origin_class`, an ineffective rewrite, or overlapping scores.
- **Attach (19.4, local only).** The Chat agent's `%OnInit` calls `Docs.Store.Attach`, because `TOOLSETS` entries must be `OcuTalon.Tools.*`. The holder must stay referenced, because `%OnClose` frees the native handle. On the demo, nothing is attached until 19.5.
- **Gate source fallback (ruled, narrow).**
  - The fallback applies only when `origin_class` is absent and the pair is exactly `%AI.RAG.KnowledgeBase:documents`. Such a call is safe and read-only, and its output is not trusted.
  - `top_k` is clamped to 5, and an invalid value is removed. A room check (`RAGRESULTMAX`) runs against the step's 40,000 characters.
  - Tests: clamp, room check, other unknown sources and near-misses still hold, no escape from the untrusted-content outcomes.
  - Decide's `ToolClassification` in `Production.cls` gains the entry. The security-overview sentence naming the fallback is PUBLIC TEXT for the spec gate.
- **Citations.** `OcuTalon.Bridge.Citations.Collect` is called once from `StepAudit.%LogExecution`, the only place that sees a knowledge-base result. It also adds the result's length to `ToolResultChars`. It applies the floor and keeps citations distinct by (source, chunk_index), in order, at most 5. `Tools.HostData`'s bodies move to a new `OcuTalon.Bridge.HostData`, because the bridge cannot name a host class, and `Tools.HostData` delegates to it.
- **ReplyFilter (additive AD-31 amendment).** It becomes `Filter(text, hostData)`: `Decide` (`Conclude`) hands over the reply's HostData. `ReplyGuard` applies `OcuTalon.Docs.Reply.Apply`, which strips the sentence, with the run of `.!?` after it, when `citations` is non-empty. Tests:
  - the sentence is stripped from a reply with citations;
  - a reply that is only the sentence, with no citations, is unchanged;
  - citations are never stripped.

  The do-nothing default must still let the bridge run alone.
- **Chat bullets (approved PUBLIC TEXT).** Pin each with a fixed-strings test. They go after 19.3's memory bullets and before "Everything that comes from a tool...", with the PersonaBlock pins still last.
  1. "When the user asks about something their documents may cover, such as a runbook, call documents with the question, and answer only from the passages it returns, naming the document and section of each step you give."
  2. "If no passage that documents returns answers the question, reply with exactly this sentence and nothing else: None of your documents cover that."
- **Other 19.4 rulings.**
  - The `documents` eval kind is a plain add; web e2e D8/D10 move only their network setup to `page.route` (assertions verbatim), and one e2e covers the real path.
  - `documents` joins `Tools.Names` and the offered-tool pins; its `top_k` schema changes the `Runners` checks.
  - Spine edits: plain unions marked `[AMENDED 2026-11-06, Story 19.4, owner ruling via the Contest Planner]`, no new AD id, then lint.
- **Per-session tables (19.5).** Each demo session gets `OcuTalonKB.S<rowid>` and its `_Config`, where `<rowid>` is the `Data.Session` row id. The globals are `^OcuTalonP.KB<suffix>` and `^OcuTalonP.KB<suffix>Config`. The tables are created before `Build()`.
- **Per-turn tools (19.5).**
  - Base `OcuTalon.Bridge.Ext.TurnTools` has `ClassMethod Tools(ownerRef, kind, Output tools As %ListOfObjects)`, which returns an empty list by default.
  - The `TurnToolsClass` setting goes on `Decide` (category Extensions). `Ext.Accessor`'s `BASES` gains the pair.
  - `OcuTalon.Docs.TurnTools` returns the owner's knowledge base for a `turn` request.
- **Session config (19.5).** The adapter builds a fresh tool manager every turn: agent tools, the knowledge base, gate, audit policy and the MCP toolsets attached in `OnAfterAgentInit`. It assigns the manager before `OpenSession`, in the session-config method. After Epic 17 that method is `SessionConfigFor`: `NewSession` and `OpenSession` both call it, and it carries the retry timer. It replaces 19.4's `%OnInit` attach.
  - A fixture toolset attached in `OnAfterAgentInit` is found in the turn's manager.
  - The standalone `OcuTalon.BridgeExample` job still passes.
- **Sign-out drops (19.5).** `Docs.DropSession` and `Memory.DropSession` replace the stubs in `Docs.cls` and `Memory.cls`. Lane B's `SessionOps.End` calls them beside `Upload.DropSession`.
- **19.7.** `OnAdd` sends `pdf`/`docx` through `Extract.Read`, not `not_built`, and maps its codes to `Document.Reason`. The `## Page n` and heading markers feed `Passages.Split`. The file's own `## ` lines are escaped (DW-832). Three gaps to close:
  - Serialise extractor reads, or amend the "one worker" wording (DW-827).
  - Bound a single long C call before it runs (DW-828).
  - Read Word content controls and nested tables (DW-831).
- **Lanes.** Lane B's `Core/**`, `Web/**`, `web/**`, `Data/Upload.cls`, `Data/Ownership.cls` and `Msg/Command/**` are read-only, except the U-177 grants (`CommandsStep3` flip, D8/D10). Contended files take plain unions.
- **CI.** `shards-2` was split into `shards-5` to fit its 35-minute cap. Place new units, such as `live:documents`, so that no group exceeds the cap. Never raise a timeout.

## UX & Interaction Patterns

- Answers end with citation chips like "Results runbook § Rotating the certificate". `document` is the name without its extension, and the chip joins it to the section; chips render in Story 20.2. Labels state provenance ("Sources", "From memory"), never "used" or "based on".
- On the Documents page:
  - The list shows "Indexing…", "Ready" or "Couldn't read it: {reason}".
  - Removing asks "Remove 'Results runbook'? Answers will stop citing it."
  - 19.7 updates "Adding" to accept "Markdown, plain text, PDF and Word (.docx) files." (DW-719).

## Cross-Story Dependencies

- **19.4 → 19.5.** 19.5 builds on 19.4's `Docs.Store` (per-session tables, `Remove` for `DropSession`). 19.4 also carries these ledger items:
  - DW-739: test the real `Web.Documents` → `CommandsIn` path.
  - DW-747: an empty `Take` gives a failed row.
  - DW-833: the knowledge-base half of `TestNothingStored`.
- **19.4 → 19.7.** 19.7 uses `Passages.Split` and the eval kind.
- **19.5.** It needs `SessionOps.End` from Story 16.4 and the standalone bridge job from Epic 13. DW-783 needs a real-stack dry run of `rehearse.sh`'s memory-offline step.
- **Downstream.** Story 20.2 carries `citations` and `memories` onto `chat.message` and keeps the "None" consistency at display. Story 26.2 reuses `Failure(code)`. Story 35.1 attaches MCP servers through the per-turn manager.
