---
title: 'Answer from documents with citations'
type: 'feature'
created: '2026-11-06'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-19-3-remember-recall-list-and-forget-in-the-chat.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-34-2-add-and-remove-documents-on-a-documents-page.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Step 3's documents have a table, verbs, a disabled `DocumentOps` stub, an upload store and a Documents page, but nothing indexes a document, the Chat agent has no `documents` tool, and no reply carries citations. While `DocumentOps` is disabled, the documents routes answer 501.

**Approach:** Build `DocumentOps`. It takes the upload, keeps the text in `Data.Document`, and splits it into passages, each under its `##` section. It embeds them through the 19.2 worker and writes them into AI Hub's vector-store table `OcuTalonKB.Docs`, with `source` set to the document's `Ref` and `chunk_index` set. It publishes `document` events. The Chat agent attaches that table as AI Hub's knowledge-base tool `documents` (TopK 5). The gate classifies the tool as safe and read-only, never trusted output, and clamps `top_k`. The runner side builds `HostData.citations` by code from the turn's `documents` results, with a measured score floor. A reply never shows both citations and "None of your documents cover that." This is local-install only. The per-session tables and the per-turn attach are Story 19.5's.

## Boundaries & Constraints

**Always:**
- `DocumentOps` is the only writer of `OcuTalon.Data.Document` and of the rows of `OcuTalonKB.Docs`, and the only publisher of the `document` event (AD-33). It answers `AddDocument`/`RemoveDocument` synchronously with a `CommandResult` and indexes asynchronously (AD-1, AD-21).
- A local-install document has `OwnerRef` `instance` and is shared by every user of the install. `AddedBy` is the adding session (AD-4).
- Only the `OcuTalon.Docs` package creates `OcuTalonKB.Docs` and `OcuTalonKB.Docs_Config`, with AI Hub's exact columns. `DEFAULTGLOBAL` is `^OcuTalonP.KBDocs` and `^OcuTalonP.KBDocsConfig`, written on the same line as `CREATE TABLE` (`kb-ddl`). The table is created before any AI Hub `Build()`. Every global it writes resolves to OCUTALON_PRIVATE.
- Each passage is one row with `source` = the document's `Ref`. Its `metadata` is `{"source","chunk_index","document","section"}`, and `chunk_index` is the passage's position, 0-based. `Data.Document` keeps the same section per `chunk_index` (the passage-to-section map).
- The tool is AI Hub's knowledge base, whose `Name` is `OcuTalon.Tools.Names` `DOCUMENTS` (`documents`), with `TopK` 5. It is attached in the Chat agent's own `%OnInit`, in the runner's job and outside every callback. No OcuTalon callback class (tool, policy, renderer, embedder callback, collector) makes a `%AI` call or runs Python. The query is embedded only through `OcuTalon.Memory.Embedding.Embed` in the 19.2 worker (AD-6, Decided in-stage).
- Document results are never trusted output, so the turn is tainted (AD-10). The gate clamps `top_k` to at most 5 (AD-10).
- `HostData.citations` holds `{documentRef, document, section, passage, chunkIndex}`, one entry per distinct (`source`, `chunk_index`) that the turn's `documents` calls returned at or above the floor. Entries are in order, at most 5, and the member is absent when empty. Code builds it from tool results, never from model text (Conventions "Citations and memories").
- The tool results of one model step stay within NFR-3's 10,000 tokens, `documents` results included.
- Every test added or changed creates and removes its own state (`zz-doc-*` refs and names, rows, KB rows, `^OcuTalonTest` nodes, item swaps) and passes on a fresh environment, in either order.

**Never:**
- No `%AI.RAG.KnowledgeBase.AddDocument`/`AddDocuments`/`ReindexDocument` in product code: a repeated add replaces every chunk of a `source`, and AI Hub's chunker does not bound or section passages (measured, Design Notes).
- No AI Hub `FastEmbed.Create()` and no `%SYS.Python` in `DocumentOps` or in the Chat agent's job.
- No per-session `OcuTalonKB.S<id>` tables, no `TurnToolsClass`, no per-turn tool manager, and no `Docs.DropSession` body (all Story 19.5). No PDF or Word extraction (Stories 19.6 and 19.7). No chip rendering (Story 20.2, Lane B).
- No edit of a Lane B file (`Core/**`, `Web/**`, `web/**`, `Data/Upload.cls`, `Data/Ownership.cls`, `Msg/Command/**`, `Test/{Core,Web}/**`), except the pre-granted U-177 flip and the items under Design Notes "Needs a ruling" once ruled.
- No new `AD-n` id. Spine edits are plain unions with `[AMENDED 2026-11-06, Story 19.4, ...]` markers.
- No user-facing text beyond "None of your documents cover that." (UX-DR144) and the model-facing texts under Design Notes.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Add Markdown | Local install. `AddDocument` (`web_user`, `Name` "Results runbook.md", `markdown`, a live `UploadRef`) | The upload is taken once with the command's `SessionRef`. A row is written with `State` `indexing`, `OwnerRef` `instance`, `Text` and `KnowledgeBase` `OcuTalonKB.Docs`, and a `document` event goes to the instance stream. The answer is Ok 1 `added` with the `Ref`. Later the rows are written, `State` becomes `ready`, and a second event is sent. | indexing error: `failed`/`failed`, the source's rows deleted, an event |
| Sections | Text `# T`, an intro, `## Rotating the certificate` with 3 steps, `## Clearing the queue` with 1 paragraph | The intro has section "". The steps' passage has "Rotating the certificate", and the last passage has "Clearing the queue". No passage is over `MAXPASSAGE` characters, and no heading line is inside a passage. | none |
| Plain text | `text`, 5,000 characters with no blank line | Passages of at most `MAXPASSAGE` characters, cut at line, then sentence, then word boundaries. Every section is "". | none |
| Unreadable | `markdown`/`text` bytes that are not UTF-8, hold a NUL, or are blank after a BOM is stripped | A row `failed` / `unreadable` and its event. The answer is Ok 1 with the `Ref`. No KB row is written. | none |
| PDF/Word (until 19.6) | `pdf` or `docx` | A row `failed` / `not_built` and its event. The answer is Ok 1. No KB row is written. | none |
| Upload gone (DW-747) | The `UploadRef` is already taken or dropped, for example after the route's 120 s timeout | A row `failed` / `failed` and its event. The answer is Ok 0 `failed` with that row's `Ref`. | none |
| No session | An unknown `SessionRef`, either verb | Ok 0 `no_session`. No row is written and nothing is taken. | none |
| Online demo (until 19.5) | Setting `onlineDemo` = 1, `AddDocument` | Ok 0 `not_built`. No row is written and nothing is taken. The route answers 501 as today. The Chat agent attaches no knowledge base. | none |
| Remove | `RemoveDocument` for a ready row, then a search | The KB rows of its `source` are deleted, then the row. A last event is sent with `removed` true. The answer is Ok 1 `removed`. The next `documents` call returns none of its passages. | `not_found` for an unknown `Ref` |
| Remove while indexing | `RemoveDocument` queued behind an indexing batch | The remaining batches find no row and stop. No KB row of the source is left. | none |
| Covered question | The runbook is ready. The model calls `documents {"query":"how do I rotate the Results certificate?"}` | At most 5 passages come back through AI Hub. `HostData.citations` holds the passages at or above the floor, the first being `{documentRef, document:"Results runbook", section:"Rotating the certificate", passage, chunkIndex}`. `Tainted` is 1. | none |
| Clamp | `documents {"query":..., "top_k": 9}` on a document of 8 or more passages | At most 5 passages are returned. | none |
| Not covered (DW-720 a) | The model calls `documents` with an unrelated question, and every score is below the floor; or the table is empty | No `citations` member. The reply may say "None of your documents cover that." | none |
| Covered but model says none (DW-720 b) | Citations exist and the model's text contains "None of your documents cover that." | The reply that leaves `Decide` does not contain the sentence, and the citations stay (mechanism: Design Notes, ruling). | none |
| Taint | `documents`, then `save_memory` in the same turn | `save_memory` is denied with the gate's sentence, and nothing is stored. | gate denial |
| Integration: consumer ChatAgent (Rule 1) | A real `turn` through `Decide` -> `ChatAgent` with the mock scenario, on a document added through `Commands.Submit` -> `CommandsIn` -> `DocumentOps` | The `Reply`'s `HostData.citations` names the document and section. The ChatAgent job is the same live job across this turn, the next one and a `search_memories` turn. | the test fails on a dead or recycled runner job |
| Real route (DW-739) | `POST /v1/documents` and then `DELETE` through the signed-in web API | 200 `{"result":"done","ref"}`, then the list shows `ready`. The `DELETE` answers 200, and the list and the KB no longer hold it. | `live:documents` fails |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Docs/Ops.cls` -- the stub (`STUB = 1`, `OnMessage` answers 5003). It becomes the real operation. Delete `STUB` and `OnMessage`, and add an `XData MessageMap`: `AddDocument`->`OnAdd`, `RemoveDocument`->`OnRemove`, `OcuTalon.Docs.Msg.Index`->`OnIndex`.
- `src/ocutalon/cls/OcuTalon/Memory/Ops.cls` -- the sibling to follow, as 19.3 built it: the MessageMap, `no_session` through `Data.Session.RefIndexOpen`, the `Answer(.response, ok, outcome, message, ref)` builder, `MESSAGE*` parameters and the `Failed` warning. `Watch/Ops.cls:58-68,247-273` is its own model.
- `src/ocutalon/cls/OcuTalon/Data/Upload.cls:55-67` (Lane B, read-only) -- `Take(ref, sessionRef)` returns a `%Stream.TmpBinary` or "", through `Ownership.Upload`. 34.3 delivered the session check and the purge, so only DW-747's timeout case is this story's.
- `src/ocutalon/cls/OcuTalon/Data/Document.cls` -- append `Sections As %String(MAXLEN = "")`, a JSON array with the section of each `chunk_index`. The Storage block may only grow (`docker/tests/test-storage.sh`).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Document.cls:28-38` -- `FromRow` leaves `Removed` 0. The publisher sets `Removed = 1` on the last event. `Live/Publish.cls:82` `Publish(stream, type, payload, .seq)`: the stream is `"instance"`, the type is `document` (already in `TYPES`), and it refuses inside an open transaction. The example caller is `Checks/Process.cls:532-538`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:693-696` (Lane B, read-only) -- `LocalFlag` is `Data.Setting.Get("onlineDemo") '= 1`, and it is Private. Read the same setting directly.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:39,77-95,193-194` (Lane B, read-only) -- the document verbs are `web_user` only and routed to `DocumentOps`, with `TIMEOUT` 120. A stub answers `not_built`.
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls:93-119,153-177,196-199` (Lane B, read-only) -- Ok gives 200 `{"result":"done","ref"}`. Ok 0 `not_built` gives 501, and any other Ok 0 gives 500. The upload row is dropped on any non-Ok answer. `OwnerRunning` is the 501 guard that turns itself off once the item is enabled.
- `src/ocutalon/cls/OcuTalon/Test/Memory/Fixture.cls:87-105,150-170` -- `CreateTable`/`DropTable`, the DDL to copy (both statements with `DEFAULTGLOBAL`), and `HubFill`, which builds a vector store and a knowledge base.
- `irislib/%AI/RAG/KnowledgeBase.cls:41-92,158-169` -- `Name` (the tool's name, measured), `Description`, `TopK`, `Build(embedding, store)`, `AddToAgent`/`AddToManager`. `%OnClose` releases the native handle, so the holder must stay referenced. `irislib/%AI/RAG/VectorStore/IRIS.cls:58-117` -- `Build()` runs `CREATE TABLE IF NOT EXISTS`, and does nothing once our table exists. `irislib/%AI/RAG/Embedding.cls:18-62` -- `EmbedBatch(texts) As %DynamicArray` (abstract). `Dimensions` and `ModelName` are ReadOnly (set through `i%`), and `Register()` must be called explicitly (`Build` does not call it).
- `irislib/%AI/Agent.cls:197-234` -- `%Init` ends with `Return ..%OnInit()`, after the toolsets load and before the adapter's `OnAfterAgentInit` installs the gate and audit (`src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:155-183`). That is where the Chat agent attaches the knowledge base.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls:18,26-72` -- `TOOLSETS` stays as it is. Its entries must be `OcuTalon.Tools.*` (`Test/Bridge/CodeRules.cls:720-727`), so the knowledge base cannot be added there. `INSTRUCTIONS`: the new bullets go before "Everything that comes from a tool...", after 19.3's memory bullets. `Test/Agent/PersonaBlock.cls:217-225` pins the end.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls:141-152,186-199,213-215,292-299` -- rule 3 and the taint. `Source()` is `mcp:`, else `metadata.origin_class`, else "", and "" means unclassified at 199. Next come the `ToolClassification` setting and then the extension, which forces `readOnly` 0. There is no `top_k` code yet, and lines 41/56 say the gate "never modifies the call". The replay `TakeGrant` check is at 143-147.
- `src/bridge/cls/OcuTalon/Bridge/Policy/StepAudit.cls:18-31` -- `%LogExecution(call, metadata, result, ...)` receives `result.result_json` for every tool and hands it to `StepBuffer.Tool`. That is where the citations collector hooks in.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:459-460` (`Converse`) -- `reply.HostData = context.HostData`, `reply.Tainted = context.Tainted`. `Adapter/StepRenderer.cls:36` resets `Context.ToolResultChars` at each model response.
- `src/ocutalon/cls/OcuTalon/Tools/Result.cls:22,35-71` -- `STEPTOKENS` 10000 x 4 characters, against `Context.ToolResultChars`. A knowledge-base result is neither cut nor counted today.
- `src/ocutalon/cls/OcuTalon/Tools/HostData.cls:14-34` -- 19.3's `Put/Get/Remove` merge rule (Rule 2 sibling). The bridge cannot name it (bridge-refs), so its body moves into a new bridge class, and `Tools.HostData` delegates to it.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:367,614-621`, `src/bridge/cls/OcuTalon/Bridge/Ext/ReplyFilter.cls`, `src/ocutalon/cls/OcuTalon/Checks/ReplyGuard.cls` -- the reply filter runs once in `Decide` on text only. `ReplyGuard` is AD-28's precedent for removing a sentence that only code may make true. `Checks/Render.cls` with `Core/Conversation.cls:461-483` is the precedent for a code-rendered sentence.
- `src/ocutalon/cls/OcuTalon/Production.cls:20-23,63` -- `Decide` holds its host settings, and `DocumentOps` is `Enabled="false"`. Lane A's region is 15-64.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsStep3.cls:122-143`, `CommandsStep3Probe.cls:16-24` -- `TestRealStubOwners`. Story 19.3's flip of `MemoryOps` (commit `a41d8141`) is the pattern: a `$Select` per verb, the STUB assert set to "", and a probe branch that calls the handlers.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls:13,676` -- the `DocumentOps` oracle row, `enabled 0, stub 1` today.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`, `Test/Memory/Turns.cls`, `ci/mock/scenarios/A/memory-*.json` -- the turn-test template (`Send`, `NewRequest`, `ReadyReason`, `Run`, the `[[mock:<name>]]` marker, `StepProblems`, the job-id check).
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls:27-28,515,526-528` -- every offered tool must be an OcuTalon tool, ChatAgent offers exactly its list, and no logged request holds `"top_k"`. The knowledge-base tool's schema has a `top_k` property, so these change.
- `src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls:275` -- the sorted names that the second ChatAgent request offers.
- `src/ocutalon/cls/OcuTalon/Install/Step/PrivateData.cls:31-66` -- it covers every `OcuTalonKB.` class's storage and index locations. `Test/Install/PrivateData.cls` is read-only here.
- `docker/tests/test-demo-switch.sh:56-68` -- `sign_in`, `api_get`, `api_post` (curl with the cookie jar). `docker/tests/test-memory-offline.sh` -- the `CHK|` class step and the restart wait. `ci/units.sh:80-92` -- `group_units`.
- `src/ocutalon/cls/OcuTalon/Eval/{In,Report}.cls`, `Eval/Msg/TurnResult.cls`, `docker/tests/test-eval-set.sh` (Epic 39 contended) -- no case kind today can assert that a tool ran or that a citation exists, and nothing can seed a document. `watch` (`Eval/In.cls:38-43`) is the setup pattern.
- `web/e2e/documents/documents.spec.ts:11-14,194-205,240-275` (Lane B) -- D8 posts a real 10 MB PDF and would leave an `instance` row behind. D10 expects the real `DELETE` to fail, and goes red once the item is built.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first; product default 5). Use one fresh lane-C throwaway (`OCUTALON_RUN_TAG=e19s4i0`, the lane's variables, `OCUTALON_LOCK_OWNER='epic=19 stage=implement'`) with `OcuTalon.Docs.Embedding`, `OcuTalon.Docs.Store` and a scratch Chat override compiled. Record the results in `_bmad-output/implementation-artifacts/evidence/19-4-task0-documents.md`, then tear down.
  - M1: the query path inside a real ChatAgent turn on the CI mock. The knowledge base is built with `OcuTalon.Docs.Embedding`, so `EmbedBatch` calls `Memory.Embedding.Embed` from inside AI Hub's tool execution. Over three turns with `documents` calls and one turn with `search_memories`, check:
    - that results come back;
    - that the embedding ran in the Embedder worker's job;
    - that the runner job id is unchanged;
    - that no S11 crash or deadlock occurs (wait up to 120 s).
  - M2: what the real adapter's gate receives for the call (`toolref`, `metadata`; the plan stage saw `documents` and `{"requires_auth":false}` on a bare manager), and that toolset calls still carry `origin_class`.
  - M3: a gate rewrite of `call.arguments.top_k` from 9 to 5 takes effect, on a document of 8 or more passages.
  - M4: the floor. Use the real embedder and the UJ-2 runbook fixture (`eval/documents-runbook-rotate/results-runbook.md`). Score these queries:
    - 3 relevant: rotating the certificate, by different wordings;
    - 2 near-miss: other sections;
    - 5 unrelated: for example the capital of France, resetting a password.

    Set `CITEFLOOR` midway between the highest unrelated top score and the lowest relevant top score.
  - M5: `SendRequestAsync(..%ConfigName, index, 0)` from `DocumentOps` to itself is handled after the current message, in FIFO order with commands.

  **Stop rule:** HALT `blocked` / `intent gap` with the measurement, naming AD-6/AD-21 ("Documents (step 3)"), if any of these holds:
  - M1 crashes, deadlocks or recycles the job. The recommended amendment is then AI Hub's FastEmbed with the image's `FASTEMBED_CACHE_DIR`, and a ruling on IPM installs, which need `os.putenv` through `%SYS.Python` in two non-worker jobs.
  - M2 shows that some non-knowledge-base tool lacks `origin_class`.
  - M3 shows a rewrite has no effect.
  - In M4, the relevant and unrelated scores overlap (no floor separates them). Then name DW-720 and FR-42 and recommend a coverage rule.
- `src/ocutalon/cls/OcuTalon/Docs/Passages.cls` (new) -- `Split(text, contentType, Output passages As %DynamicArray)`. Each passage is `{text, section}`. Markdown rules:
  - A line `## <heading>` starts a section, and its text is trimmed, with trailing `#` removed.
  - Text before the first `##` has section "".
  - `#` and `###`+ lines stay as passage lines.
  - Heading lines of `##` are not passage text.

  Plain text has one section "". Within a section, paragraphs separated by blank lines are packed into passages of at most `MAXPASSAGE` = 1,000 characters. A longer paragraph is cut at line, then sentence (". "), then word boundaries, else hard. Blank passages are dropped. It is a pure function with no SQL.
- `src/ocutalon/cls/OcuTalon/Docs/Embedding.cls` (new; extends `%AI.RAG.Embedding`) -- `%OnNew` sets `i%Dimensions` 384 and `i%ModelName` "AllMiniLML6V2". `EmbedBatch` calls `OcuTalon.Memory.Embedding.Embed` for each text and returns `[[...384 floats]]`, throwing on an error status. It has no `%AI` call and no Python (it is a callback class: `CALLBACKHELPERS`).
- `src/ocutalon/cls/OcuTalon/Docs/Store.cls` (new) -- the local knowledge base. It is the only class that names `%AI.RAG.VectorStore.IRIS` and holds the DDL.
  - `TABLE` "OcuTalonKB.Docs" and `SUFFIX` "Docs".
  - `EnsureTable()` makes both tables, as `Test/Memory/Fixture.cls:87-105` does, when they are missing, and does nothing otherwise.
  - `Write(ref, name, passages, from, count)` embeds each passage (the text is `section _ $C(10) _ text` when the section is not empty), and inserts `id` `ref_":"_n`, `text`, `TO_VECTOR(...)`, `metadata` and `source`.
  - `Remove(ref)` runs `DELETE ... WHERE source = ?`.
  - `Attach(agent, Output holder)` returns no holder on the online demo. Otherwise it runs `EnsureTable`, then `Docs.Embedding` with `Register()`, the vector store (`Build`) and the `KnowledgeBase` (`Names.#DOCUMENTS`, `DESCRIPTION`, TopK 5, `Build`, `AddToAgent`). It returns a holder object with the three in its properties. A failure is one Type 3 warning and no holder; the agent still builds.
  - `DocumentName(name)` is the `Name` without a final `.md`, `.markdown`, `.txt`, `.pdf` or `.docx`, in any case.
- `src/ocutalon/cls/OcuTalon/Docs/Msg/Index.cls` (new; `Ens.Request`) -- `Ref` and `Next`.
- `src/ocutalon/cls/OcuTalon/Docs/Ops.cls` -- the real `DocumentOps` (pool 1); `OnInit` runs `Store.EnsureTable()`.
  - `OnAdd`:
    1. `no_session` when the session is unknown.
    2. Online demo: `not_built`.
    3. `Take(UploadRef, SessionRef)`. An empty answer gives a failed row (`failed`) and Ok 0 `failed`.
    4. `pdf`/`docx` give a failed row (`not_built`).
    5. Decode UTF-8 and strip the BOM. A NUL, a decode failure or blank text gives a failed row (`unreadable`).
    6. Otherwise save the row (`indexing`, `OwnerRef` `instance`, `AddedBy`, `Name`, `ContentType`, `Size`, `AddedAt` `NowUtc`, `Text`, `KnowledgeBase`) and publish.
    7. Send `Index(Ref, 0)` to itself, and answer Ok 1 `added` with the `Ref`.

    Every failed row is published, and answered Ok 1 with its `Ref` except the empty-take case.
  - `OnIndex`:
    1. Do nothing when the row is gone or not `indexing`.
    2. `Passages.Split`. On `Next` 0, store `Sections` and run `Store.Remove(ref)`.
    3. `Store.Write` at most `BATCH` = 32 passages from `Next`.
    4. Re-queue `Index(Ref, Next+32)` while passages remain. Otherwise set `ready` and publish.
    5. Any error runs `Store.Remove`, sets `failed` / `failed`, publishes, and logs one redacted warning.
  - `OnRemove`: `no_session`. Then `not_found` unless the row exists with `OwnerRef` `instance`. Then `Store.Remove(ref)`, `%DeleteId`, publish `FromRow` with `Removed` 1, and Ok 1 `removed`.

  Publish happens outside any transaction. A publish failure is a warning and never changes the answer. The model-facing `MESSAGE*` parameters follow MemoryOps. The doc comment states the contract (Rule 14).
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- append one self-contained block at the end of the class:
  - a `[ Transient ]` property `Documents`;
  - `%OnInit`, which calls `##super()` and then `##class(OcuTalon.Docs.Store).Attach($this, .holder)`, keeps the holder, and returns OK;
  - plus the INSTRUCTIONS bullets of Design Notes (PUBLIC TEXT) and one doc clause.
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- `Parameter DOCUMENTS = "documents";` (a plain line, so the mock reads it) and `Parameter DOCUMENTSTOOLS = {..#DOCUMENTS}` (the expression form, which the mock skips), both outside `RELEASE1`.
- `src/bridge/cls/OcuTalon/Bridge/HostData.cls` (new) -- `Put(member, value)`, `Get(member)` and `Remove(member)`, moved from `Tools.HostData`'s bodies. `src/ocutalon/cls/OcuTalon/Tools/HostData.cls` -- each method becomes a one-line delegation (Rule 2).
- `src/bridge/cls/OcuTalon/Bridge/Citations.cls` (new) -- `Collect(call, metadata, result)`. Only when `metadata` has no `origin_class` and `result.result_json` parses as an array of `{text, score, metadata{source, chunk_index}}` does it run. It adds `$Length(result_json)` to `Context.ToolResultChars`. Then, for each item with `score` >= `CITEFLOOR` (Task 0 M4), it merges `{documentRef: source, document, section, passage: text, chunkIndex}` into `HostData.citations` through `Bridge.HostData`: distinct by (source, chunkIndex), in order, at most 5. It names no host package, makes no `%AI` call and runs no Python.
- Ruling-gated (bridge, Epic 17 footprint): `src/bridge/cls/OcuTalon/Bridge/Policy/StepAudit.cls` -- one call of `Citations.Collect` in `%LogExecution`.
- Ruling-gated (bridge, Epic 17 footprint): `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - (a) `Source()`: a call with no `mcp:` `toolref` and no `origin_class` has source `%AI.RAG.KnowledgeBase`.
  - (b) For that source, after the `TakeGrant` check and before `ReportStep`, a numeric `top_k` above `MAXTOPK` = 5 becomes 5, and a value below 1 or not a number is removed.
  - (c) It denies such a call, with a plain sentence, when `Context.ToolResultChars + RAGRESULTMAX` exceeds the step's 40,000 characters. `RAGRESULTMAX` = 8,000, which a host test pins at `>= 5 * (Passages.MAXPASSAGE + 400)`.
  - Lines 41 and 56 name the two rewrites.
- Ruling-gated: `src/ocutalon/cls/OcuTalon/Production.cls`:
  - `DocumentOps` `Enabled="true"` (an allowed union).
  - `Decide` gains `<Setting Target="Host" Name="ToolClassification">[{"class":"%AI.RAG.KnowledgeBase","tool":"documents","classification":"safe","readOnly":1,"trustedOutput":0}]</Setting>` (needs a ruling).
- Ruling-gated (DW-720 b; mechanism under Design Notes): the code that keeps "None of your documents cover that." out of a reply that has citations, with `OcuTalon.Docs.Reply.Apply(text, hostData)` (new, pure, Lane A) as the rule. It removes the sentence, with the run of `.!?` that follows it, when `hostData.citations` is a non-empty array, and leaves the text unchanged otherwise.
- Ruling-gated pins (shared surfaces):
  - `Test/Install/Production.cls:13,676` -- an allowed union: enabled 1, stub 0, and the sentence.
  - `Test/Agent/Runners.cls` -- the list at :515 gains `documents` (an allowed union). :27-28 exempt the `documents` tool, and :526-528 assert no top-level `top_k` (needs a ruling).
  - `Test/Agent/{Instructions,Constants}.cls` -- the bullets and the `DOCUMENTS` name (an allowed union).
  - `Test/Bridge/Decide.cls` `TestEstimateTokens` -- the tool's definition length (an allowed union).
  - `Test/Install/SecurityOverview.cls:37` -- `released` appends `_ $ListFromString($Parameter("OcuTalon.Tools.Names", "DOCUMENTSTOOLS"))` (one term, an allowed union).
  - `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` -- renders the `documents` row from Decide's `ToolClassification` entry. `docs/security-overview.md` is regenerated with `live:security-overview --write`.
- The U-177 pre-granted flip: `src/ocutalon/cls/OcuTalon/Test/Core/CommandsStep3.cls:134-141` and `CommandsStep3Probe.cls:16-24`. `TestRealStubOwners` moves `DocumentOps` from `not_built` to "built": both verbs answer `0|no_session` for the test's unknown session, `STUB` is "", and the probe calls `OnAdd`/`OnRemove`. No other line changes.
- Uncontended pins:
  - `Test/Tools/Reminders.cls:275`, `Test/Tools/Persona.cls`, `Test/Watch/{Tools,Turns}.cls` -- the offered-tool lists gain `documents`. Search the tool lists for `propose_persona,recent_activity`.
  - `Test/Bridge/CodeRules.cls:82` -- `CALLBACKHELPERS` appends `OcuTalon.Docs.Embedding,OcuTalon.Bridge.Citations,OcuTalon.Bridge.HostData`.
  - `Test/Bridge/Gate.cls` -- new methods for (a) to (c) and for the taint. `TRUSTEDTOOLS` and `READONLYTOOLS` are unchanged.
  - `ci/mock/test/constants.test.mjs` -- `DOCUMENTS` is read and called by a scenario.
  - `Test/Contract/Step3.cls` -- `Data.Document`'s new property, if pinned.
- `ci/mock/scenarios/A/documents-{runbook,none,topk,none-conflict,removed,then-save}.json` (new) -- scripted turns. The queries and `top_k` are fixed. `none-conflict` answers "None of your documents cover that." after a covered search.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Passages.cls` (new) -- the section and size rules of the matrix, the cut order, blanks, plain text and `DocumentName`.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Store.cls` (new) -- `EnsureTable` is idempotent. The globals resolve to OCUTALON_PRIVATE by `GetGlobalDest`, with no data-database directory entry and `^IRIS.KNNIndex` still empty. Through a bare `%AI.ToolMgr` in the test job: `Write` rows and their metadata, search, a removal visible to the next search, and the empty table. `Attach` on the demo gives no holder.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Ops.cls` (new; throwaway/CI) -- through the production and through `Commands.Submit` with origin `web_user` (DW-739): every add and remove row of the matrix and its events, read back from the instance stream. Also: origin `tool` refused, remove during indexing, `no_session`, and the answer time under 10 s.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Turns.cls` (new; throwaway/CI) -- live turns through `Decide` -> `ChatAgent` with the scenarios: covered (citations, `Tainted` 1), clamp, not covered, none-conflict (once ruled), removed, then-save denied, and the job id unchanged. `StepProblems` runs for each turn.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Citations.cls` (new) -- the floor, distinctness, order, the cap of 5, non-knowledge-base results ignored, the characters counted, and malformed JSON ignored. `src/ocutalon/cls/OcuTalon/Test/Docs/Reply.cls` (new) -- `Reply.Apply` both ways.
- `docker/tests/test-documents.sh` (new live unit `live:documents`; registered like `live:memory-offline`, in group `shards-2`).
  - It signs in (the `test-demo-switch.sh` helpers), posts the runbook, waits up to 120 s for `ready`, and runs a class step that searches the table.
  - It then runs `docker restart`, waits for ready, and checks that the list and the search still hold the document (AD-5).
  - Finally it posts a `.pdf` (giving `not_built`) and a NUL `.txt` (giving `unreadable`), deletes all three, and checks that the list and the KB are empty.
- `ci/units.sh` -- the area `Docs` joins `lane-a`'s area list (a one-name append), and `live:documents` joins `shards-2`.
- Ruling-gated (Epic 39 contended `Eval/**`): kind `documents` in `Eval/In.cls`, `Eval/Report.cls` and `Eval/Msg/TurnResult.cls` (`Citations`), and in `docker/tests/test-eval-set.sh`. Its setup is `documents` (files added through `DocumentOps` before the turn and removed in `Finish`). Its expectations are `citations` (`[{document, section}]`) or `none` (the reply holds the sentence and has no citations).
  - `eval/documents-none-cover/case.json`, `eval/documents-runbook-rotate/{case.json,results-runbook.md}` (new, ours), with mock scenarios.
  - The real-model run is the owner's release gate.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- plain unions with `[AMENDED 2026-11-06, Story 19.4, ...]`:
  - an AD-21 "Indexing and search (Story 19.4)" bullet: the measurements, the passages, the metadata keys, `Docs.Embedding`, `CITEFLOOR` and the attach in `%OnInit`;
  - one sentence on the `%AI.RAG.KnowledgeBase` source in the Conventions "Tool classification" row;
  - the ownership tables: `OcuTalon.Docs.Msg.Index` and `OcuTalonKB.Docs`.

  Lint afterwards.

**Acceptance Criteria:**
- Given a Markdown or plain-text document sent to `DocumentOps`, when it is indexed, then `OcuTalonKB.Docs` (created by `OcuTalon.Docs`, globals in OCUTALON_PRIVATE) holds its passages with `source` = `Ref`, `chunk_index` and section. `Data.Document` keeps the text and the section of each passage. `document` events go from `indexing` to `ready`, or to `failed` with `unreadable`/`not_built`/`failed`.
- Given a question the documents cover, when the Chat agent searches, then the tool is named `documents` and returns at most 5 passages (the gate clamps `top_k`), the `Reply`'s `HostData.citations` names each cited passage's document and section from `source` and `chunk_index`, and the turn is tainted. `documents` is in `OcuTalon.Tools.Names` and in the mock's scenarios.
- Given a question no document covers, when the agent answers, then no citation is carried and the reply may say "None of your documents cover that.". Given citations, the reply that leaves `Decide` never says it (DW-720, both directions tested).
- Given a removed document, when the remove command is handled, then its passages leave search at once and no later reply cites it.
- Given the real route, when a person adds and removes a document through `/v1/documents`, then it reaches `ready` through `CommandsIn` -> `DocumentOps` and then leaves the list and the knowledge base (DW-739). After an iris container restart, the document is still listed and found.

## Spec Change Log

- 2026-11-07 (lead, part 2 re-open): Epic 17 is merged (feature 5b47f052); status reset to `draft` to re-plan around the merged bridge files; the Design Notes "Rulings (2026-11-06 ...)" block stays binding and verbatim.

- 2026-11-06 (lead): the Planner's rulings on the blocking question and the "Needs a ruling" items recorded under Design Notes "Rulings"; the story waits for Epic 17's merge, then status reset and spec gate.

## Review Triage Log

## Design Notes

**Architecture decisions:**
- AD-1: commands through `CommandsIn` from `web_user`, answered synchronously.
- AD-4: `instance` owner locally, and `AddedBy`.
- AD-5: rows survive a restart.
- AD-6: knowledge-base attach outside callbacks, query embedding in the worker, no `%AI` or Python in callbacks.
- AD-10: taint, the `top_k` clamp, NFR-3.
- AD-12: the event.
- AD-21: Documents (step 3).
- AD-22: tests, mock scenarios, eval.
- AD-29: Lane A.
- AD-31: no new extension class.
- AD-33: one writer and one publisher.
- Conventions: "Citations and memories", "Tool results", "Tool classification", "Python".

**Plan-stage measurement (slot C `ocutalon-slot-c`, build 154U ARM64; a scratch `%AI.RAG.Embedding` subclass with synthetic vectors, scratch policies and table `OcuTalonKB.ZzE19s4`; all deleted after, slot left clean):**
- The tool's name is exactly the knowledge base's `Name`. Its schema is `query` (required) and `top_k` (integer, optional), and its catalog entry is `source:"rag"` with `metadata:{}`.
- A result is `{"timing","value":[{id, score, text, metadata:{chunk_index, source, <caller keys>}}]}`.
- The authorization policy received `toolref` `documents` and metadata `{"requires_auth":false}` (no `origin_class`). The audit received `result_json`.
- Chunking: AI Hub splits only after a heading line, and glues the heading to the END of the previous chunk. Blank-line paragraphs stayed together, and a 20,783-character text stayed one chunk.
- A second `AddDocument` (or an `AddDocuments` entry) for a `source` replaces all its chunks. `ReindexDocument(source, "")` leaves 0.
- Rows inserted, updated or deleted by SQL show in the very next search. An unrelated query still returns every passage with scores near 0, and an empty table returns `[]`.
- The `EmbedBatch` callback ran in the calling job.

These force `DocumentOps` to write passages itself and code to apply a floor. AI Hub's FastEmbed was not run (the slot has no model).

**Integration ACs:** the matrix row "Integration: consumer ChatAgent" (`Test.Docs.Turns`: the real runner, gate, AI Hub tool, `CommandsIn` and `DocumentOps`, with no double), and "Real route" (`live:documents`).

**Consumed-by:**
- 19.5: `Docs.Store` per-session tables, `Attach` replaced by `TurnToolsClass`, `Docs.DropSession` over `Store.Remove`.
- 19.6: the extracted text enters `OnAdd`.
- 19.7: `Passages.Split` with page and heading markers, and the eval kind.
- 20.2 (Lane B): `HostData.citations` and the "None" consistency at display.

**Consumes:**
- 34.1: names, table, stubs.
- 34.2: verbs, routes, `Live.Payload.Document.FromRow`, reason codes.
- 34.3: `Upload.Take(ref, sessionRef)`.
- 19.2: `Memory.Embedding.Embed`.
- 19.3: `Tools.HostData`.

**Extend, don't copy:**
- `DocumentOps` follows `Memory.Ops`/`Watch.Ops`.
- `Docs.Store`'s DDL is `Test/Memory/Fixture.CreateTable`'s (product twin; the fixture may later call it).
- `Bridge.HostData` takes `Tools.HostData`'s bodies and `Tools.HostData` delegates, so there is no copy.
- `Docs.Embedding` wraps `Memory.Embedding.Embed`.
- `Docs.Reply` follows `Checks.ReplyGuard`'s matching rule.
- The live unit copies `test-demo-switch.sh`'s two sign-in lines, as `test-bundle-folder.sh` did, because `lib-live.sh` is shared.

**Decided in-stage:**
- Query and passage vectors come from `OcuTalon.Docs.Embedding` (the 19.2 worker's fastembed 0.9.0, the AllMiniLM-L6-v2 that AD-21 pins, equal to AI Hub's FastEmbed within 1.3e-7, with `ModelName` "AllMiniLML6V2"), not AI Hub's `FastEmbed.Create()`. So no FastEmbed and no Python run in `DocumentOps`, in the ChatAgent job or in a callback. IPM installs need no `FASTEMBED_CACHE_DIR` in those jobs, and one model is loaded per worker rather than per runner. This replaces the line "DocumentOps sets `FASTEMBED_CACHE_DIR` ... before `FastEmbed.Create()`" (confirmation requested; Task 0 M1 decides, with the stop rule as the fallback).
- "At most 5 passages per model request" is read as per `documents` call, as the AC's parenthetical defines it. NFR-3's step bound covers several calls in one step (gate (c)).
- `MAXPASSAGE` 1,000 characters (about 250 word pieces in English, under the 256 that the model embeds) and `BATCH` 32.
- A section's heading is embedded with its passage but not stored in its text.
- `document` in a citation is the name without its file extension, so the AC's "Results runbook (section sign, U+00A7) Rotating the certificate" comes from `document` + `section`. The section-sign join is the chip's (Lane B).
- An empty `Take` writes a failed row (spine Lane B contract: "an empty answer is a failed row") and answers Ok 0. The route has already answered when it timed out.
- The knowledge base's `DESCRIPTION` (model-facing): "Searches the documents added to OcuTalon, such as runbooks, and returns the passages that best match the query, each with its document and section."
- `live:documents` joins `shards-2`, whose only unit is `shard:lane-a@rest`. A unit over 1,000 s on a clean run is split; a group only above 35 minutes on two clean runs.

**Needs a ruling** (the rest of the plan does not depend on these):
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` (Epic 17's bridge footprint; Epic 19's paths_hint does not include `Policy/`) -- (a) the source fallback for a call with no `origin_class` (AI Hub sends none for a knowledge base, measured), (b) AD-10's `top_k` clamp, (c) NFR-3's room check for knowledge-base results. Without them, `documents` is unclassified and held for approval in every user turn.
- `src/bridge/cls/OcuTalon/Bridge/Policy/StepAudit.cls` (same footprint) -- one call of `OcuTalon.Bridge.Citations.Collect` in `%LogExecution`, the only place that sees a knowledge-base result (no host hook receives tool results).
- `src/ocutalon/cls/OcuTalon/Production.cls` (Epic 17 contended) -- `Decide`'s `ToolClassification` setting entry for `%AI.RAG.KnowledgeBase:documents` (safe, readOnly 1, trustedOutput 0), beside the allowed `DocumentOps` `Enabled="true"`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls` (Epic 17 contended) -- beyond the list append: `:27-28` exempt the knowledge-base tool from "every tool is an OcuTalon tool", and `:526-528` assert no top-level `top_k` (the tool's schema has the property).
- `web/e2e/documents/documents.spec.ts` (Lane B, U-177; DW-735) -- D8 fulfils its POST with `page.route` (today it would leave a real `instance` row), D10 fulfils the failing `DELETE` with `page.route` (it goes red once the item is built), and the header lines 11-14. If declined, route it to Lane B Story 20.2, but `live:sign-in`/`browser` are then red from this story's merge.
- `src/ocutalon/cls/OcuTalon/Eval/{In,Report}.cls`, `Eval/Msg/TurnResult.cls`, `docker/tests/test-eval-set.sh` (Epic 39 contended) -- the `documents` case kind and setup. No existing kind can assert a tool call or a citation.
- The DW-720 b mechanism (contended `Decide.cls`, `Ext/ReplyFilter.cls`, `Checks/ReplyGuard.cls`; see the blocking question).

**PUBLIC TEXT needed:**
- `Agent/Chat.cls` INSTRUCTIONS, inserted after Story 19.3's memory bullets and before "Everything that comes from a tool...", with the PersonaBlock pins still last. Proposed:
  1. "When the user asks about something their documents may cover, such as a runbook, call documents with the question, and answer only from the passages it returns, naming the document and section of each step you give."
  2. "If no passage that documents returns answers the question, reply with exactly this sentence and nothing else: None of your documents cover that."

**Ledger inbox:**
- DW-720 is addressed by `Citations.Collect` with the floor (direction a) and the ruling-gated reply rule (direction b), with tests both ways in `Test.Docs.Turns` and `Test.Docs.Reply`.
- DW-735 is ruling-gated (above).
- DW-739 is addressed by `Test.Docs.Ops` (`Commands.Submit` -> `CommandsIn` -> `DocumentOps` for real) and `live:documents` (the real `Web.Documents` route over HTTP). What remains is `Test.Web.DocumentsApi`'s stale comment at :537 (Lane B).
- DW-747 is addressed by `OnAdd`'s single `Take` with the command's `SessionRef` and its empty-take failed row (matrix "Upload gone"). 34.3 delivered the sweep and the session check.

**Rulings (2026-11-06; the Contest Planner under the owner's delegation, relayed by the orchestrator). They answer the blocking question and every "Needs a ruling" / "PUBLIC TEXT needed" item above. Every spine amendment below carries the marker `[AMENDED 2026-11-06, Story 19.4, owner ruling via the Contest Planner]`.**
- ORDER: this story waits for Epic 17's merge (as 19.5 does). At that merge: integrate forward, then reset `status` per the re-dispatch protocol (`ready-for-dev` if the plan stands with these rulings, `draft` if it must be re-planned around Epic 17's merged bridge files), and only then the lead's spec gate. Until then nothing here is implemented and none of the contended files is touched.
- Q1 (the "None of your documents cover that." half of DW-720 / U-280): option A. AD-31 gets an ADDITIVE amendment: `OcuTalon.Bridge.Ext.ReplyFilter.Filter(text, hostData)` (Decide hands the reply's HostData to the reply filter). Tests: (a) the sentence is stripped from any reply whose HostData holds citations; (b) a reply that is only that sentence, with no citations, is shown unchanged; (c) citations are never stripped.
- Q2 (the embedder): APPROVED. AD-21 clarification amendment: documents use "the FastEmbed model, run through the embedding worker" (`OcuTalon.Docs.Embedding` via Story 19.2's worker). Conditions: (a) the score floor's value and the measurement behind it go in the story record (this spec and an evidence file); (b) tests on both sides of the floor: an unrelated question gets no passages, and a question a passage answers still gets it; (c) a second add of document X replaces only X's passages, never Y's, with a test.
- Q3 (`Bridge/Policy/Gate.cls` source fallback): APPROVED, narrow and exact. The fallback applies only when `origin_class` is absent AND the pair is exactly `%AI.RAG.KnowledgeBase:documents`. It classifies the call as safe and read-only, and NOT trusted output (passages are untrusted content). `top_k` is clamped to 5, plus NFR-3's room check. Tests: the clamp; the room check; another unknown source still holds; a near-miss still holds (another tool on the same provider, or the same tool name on another provider); a documents result cannot lead past the untrusted-content outcomes. The generated `docs/security-overview.md` lists this fallback in plain words: that sentence goes to the orchestrator as `## Clarification Needed` beginning `PUBLIC TEXT:` at this story's spec gate. (`Bridge/Policy/StepAudit.cls`' one citations call and the `Production.cls` ToolClassification entry follow with Q3.)
- Q4 (DW-735, U-177 GRANTED, scoped to D8 and D10 in `web/e2e/documents/documents.spec.ts`): their page-visible assertions stay word for word; only the network setup moves to `page.route`. This story's own e2e must cover the real, unrouted documents path once.
- Q5 (Eval): the `documents` case kind in the Eval files (`Eval/{In,Report}.cls`, `Eval/Msg/TurnResult.cls`, `docker/tests/test-eval-set.sh`) is fine as a plain add after Epic 39 merges. The real-model run stays the Planner's release gate (never run by a runner).
- Q6 (PUBLIC TEXT, APPROVED as written), placed after Story 19.3's memory bullets and before "Everything that comes from a tool...", PersonaBlock pins still last; pin both with fixed-strings tests:
  1. "When the user asks about something their documents may cover, such as a runbook, call documents with the question, and answer only from the passages it returns, naming the document and section of each step you give."
  2. "If no passage that documents returns answers the question, reply with exactly this sentence and nothing else: None of your documents cover that."

## Verification

Lane variables go on every `ci/iris.sh` / `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=19 stage=implement'`. Every call runs in the foreground with `timeout: 600000`.

Runtime targets:
- lane C warm `e19s4iw` (`ci/warm.sh up` once, `down` at the end and after a failure);
- fresh `e19s4i` (live, shards, destructive);
- fresh `e19s4i0` (Task 0);
- `ocutalon-slot-c` / `OCUTALON` only for `iris_doc_load` compile checks.

**Commands:**
- `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s4iw ci/iris.sh class <C>` (loop), one call each, for C in:
  - `OcuTalon.Test.Docs.`: `Passages`, `Store`, `Ops`, `Turns`, `Reply`;
  - `OcuTalon.Test.Bridge.`: `Citations`, `Gate`, `CodeRules`, `Decide`;
  - `OcuTalon.Test.Tools.`: `HostData`, `Memory`, `Reminders`, `Persona`;
  - `OcuTalon.Test.Watch.`: `Tools`, `Turns`;
  - `OcuTalon.Test.Agent.`: `Instructions`, `Constants`, `Runners`, `PersonaBlock`;
  - `OcuTalon.Test.Install.`: `Production`, `SecurityOverview`, `PrivateData`;
  - `OcuTalon.Test.Core.CommandsStep3`, `OcuTalon.Test.Contract.Step3`, `OcuTalon.Test.Memory.Turns`.

  Expected: CLASS passed, no SKIP.
- `OCUTALON_LIVE_DEADLINE=1200 OCUTALON_RUN_TAG=e19s4i ci/iris.sh live documents` (loop; destructive: a container restart), then `ci/iris.sh teardown` with that tag -- expected: every PASS.
- `OCUTALON_RUN_TAG=e19s4i ci/iris.sh live security-overview` (once) -- expected: no `DRIFT`.
- `OCUTALON_RUN_TAG=e19s4i ci/iris.sh live sign-in --part 1/2`, then `--part 2/2`, one each (once, after the DW-735 ruling and a `ci/iris.sh build`) -- expected: every test passed.
- `OCUTALON_LIVE_DEADLINE=1200 OCUTALON_RUN_TAG=e19s4i ci/iris.sh live memory-offline` (once) -- expected: `MEMORY-OFFLINE engine=aarch64 ok=1`.
- `OCUTALON_RUN_TAG=e19s4i ci/iris.sh shard lane-a --part k/12` for k = 1..12, one call each (once) -- expected: every class passed.
- `OCUTALON_RUN_TAG=e19s4i ci/iris.sh shard lane-b --part k/4` for k = 1..4, one call each (once) -- expected: every class passed.
- `bash docker/tests/test-<n>.sh` for n = `ci-config`, `class-rules`, `storage`, `boundaries`, `ci-changes`, `mock`, `eval-set`, one call each (once) -- expected: PASS.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once) -- expected: no new finding.
- CI: `iris (shards-2)` runs `Test.Docs.*` and `live:documents`. Record its seconds.

**Shared surfaces:**
- ChatAgent's offered tools: `Test.Tools.{Reminders,Persona}`, `Test.Watch.{Tools,Turns}`, `Test.Agent.Runners`, `Test.Bridge.Decide`.
- `Tools.Names` (`Test.Agent.Constants`, `ci/mock/test/constants.test.mjs`).
- The security overview's tools region (`docs/security-overview.md`, `Test.Install.SecurityOverview`, `live:security-overview`).
- `CodeRules.CALLBACKHELPERS`.
- Gate classification and rewrites (`Test.Bridge.Gate`).
- The production oracle (`Test.Install.Production`) and `Test.Core.CommandsStep3`.
- `Data.Document`'s schema (`test-storage.sh`, `Test.Contract.Step3`, `Test.Install.PrivateData`).
- The Chat INSTRUCTIONS order (`Test.Agent.PersonaBlock`).
- `web/e2e/documents` D8/D10.
- `ci/units.sh` areas and groups (`test-ci-config.sh`).

Every test added or changed passes on a fresh environment, in either order.

**Mutations (one per AC; the implement stage records each result):**
- AC1: `mutation:` drop the `section` from the inserted metadata -> `Test.Docs.Store` red. `mutation:` drop `DEFAULTGLOBAL` from the DDL -> `Test.Docs.Store` globals check red.
- AC2: `mutation:` skip `Citations.Collect` -> `Test.Docs.Turns` covered case red. `mutation:` drop the clamp -> `Test.Bridge.Gate` and `Test.Docs.Turns` clamp red. `mutation:` set the setting's `trustedOutput` to 1 -> the taint case red.
- AC3: `mutation:` `CITEFLOOR` 0 -> the not-covered case red. `mutation:` `Docs.Reply.Apply` returns the text unchanged -> `Test.Docs.Reply` and the none-conflict turn red.
- AC4: `mutation:` skip `Store.Remove` in `OnRemove` -> `Test.Docs.Ops` remove red.
- AC5: `mutation:` keep `DocumentOps` `Enabled="false"` -> `live:documents` red.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: DW-720 / owner ruling U-280 condition (1) ("both are decided by code from the same turn's tool results") has two defensible readings that give different replies, and each needs a change this story cannot decide alone. (A, recommended) The model writes "None of your documents cover that." (PUBLIC TEXT bullet 2), code decides the citations from the turn's documents results with a measured score floor (CITEFLOOR, Task 0 M4), and the reply filter removes the sentence from any reply whose HostData holds citations: this needs Decide to hand the reply's HostData to the ReplyFilterClass (OcuTalon.Bridge.Ext.ReplyFilter.Filter(text, hostData), an AD-31 extension-contract change in Epic 17-contended Decide.cls and Ext/ReplyFilter.cls) and OcuTalon.Checks.ReplyGuard (Epic 17/39-contended Checks/**) to apply OcuTalon.Docs.Reply.Apply. (B) AD-28's pattern, code alone writes the sentence: ReplyGuard always removes the model's copy, the runner side records in HostData that the documents tool ran and nothing reached the floor, and Conversation (Lane B, Story 20.2) renders the sentence from it as it renders Checks.Render's; then AC3's sentence first appears with Story 20.2 (part of an AC moved to a not-yet-planned Lane B story). Please also confirm the Decided in-stage embedder: query and passage vectors from OcuTalon.Docs.Embedding (the Story 19.2 worker's fastembed 0.9.0, the same model as AI Hub's FastEmbed within 1.3e-7) instead of AI Hub's FastEmbed.Create() with FASTEMBED_CACHE_DIR set in DocumentOps' job, because an IPM install would then need %SYS.Python os.putenv in DocumentOps' and the ChatAgent's non-worker jobs. Evidence: the plan-stage measurement and the AD-28 precedent under Design Notes. Everything else is planned; the contended-file edits are under Design Notes "Needs a ruling" and do not block on this question.
