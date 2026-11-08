---
title: 'Keep each online-demo session''s documents and memories to itself'
type: 'feature'
created: '2026-11-08'
status: 'done'
baseline_revision: '40de1ed28461d54451cec43b6621a61deef33cf5'
baseline_commit: '40de1ed28461d54451cec43b6621a61deef33cf5'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-19-4-answer-from-documents-with-citations.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-34-1-settle-step-3-ownership-and-fix-its-contracts.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: ['oversized', 'multiple-goals']
deferred:
  - summary: >-
      The upgrade harness reads an empty answer of an IRIS call as success: `document_found` maps no output to "found", and `built_class` / `seed_memory` / `seed_document` read it as "not built".
    evidence: |-
      release/upgrade-harness.sh `document_found` ends with `session_value ... | sed 's/^ok$//'`, so a failed call, a missing class or a missing CHK line prints nothing and `document_check` passes ("a search of its knowledge base finds the document") with no search run; `built_class` prints an empty string when it cannot say and the seeds take `${built:-0}` and skip the family with a note. The fix is to treat an empty answer as a failure in both places and to add that case to `t_memory_document`. Both are lines of the approved hunks H5 and H6 and of H9, and the release tool is frozen, so it needs a ruling on the exact lines (the Planner).
    location: >-
      release/upgrade-harness.sh:1027 (document_found) and :1042-1060 (seed_memory, seed_document); docker/tests/test-upgrade-harness.sh t_memory_document
    severity: medium
---

<intent-contract>

## Intent

**Problem:** On the online demo `DocumentOps` answers `AddDocument` with `not_built`, the Chat agent attaches one knowledge base (`OcuTalonKB.Docs`) once per runner job in its own `%OnInit` (DW-893), `OcuTalon.Docs.DropSession` and `OcuTalon.Memory.DropSession` are Story 34.1's do-nothing stubs, and evaluation documents share the persons' table (DW-900, DW-901). So a visitor cannot add documents, and if they could, one visitor would search another's.

**Approach:** Give every online-demo session its own knowledge-base tables (`OcuTalonKB.S<id>`, `_Config`), created by `OcuTalon.Docs` on the session's first document. Add the fourth bridge extension class `TurnToolsClass`: `OcuTalon.Docs.TurnTools` returns the turn owner's knowledge base, and when it does, the adapter composes a fresh tool manager for that request in `SessionConfigFor`, before the session opens, and puts the agent's own manager back when the request ends. Build both `DropSession` bodies, move evaluation documents into their own table with a start-of-run sweep, and prove isolation, sign-out and the reset with two real demo visitors. The upgrade harness half is planned as exact hunks for the release-tool ruling.

## Boundaries & Constraints

**Always:**
- One owner rule, in `OcuTalon.Docs.Store` (Rule 2: every caller uses it): a document's owner is the session on the online demo (`onlineDemo` 1), `instance` on a local install, and `eval` for an evaluation run; the table of owner `instance` is `OcuTalonKB.Docs` (suffix `Docs`), of `eval` `OcuTalonKB.Eval` (suffix `Eval`), and of a session `OcuTalonKB.S<id>` (suffix `S<id>`, `<id>` the `OcuTalon.Data.Session` row id whose `Ref` equals the SessionRef exactly). A suffix that is not `Docs`, `Eval` or `S` plus digits is refused before any SQL.
- Only `OcuTalon.Docs` (the package and the class) creates and drops knowledge-base tables, by SQL, with AI Hub's exact columns and `DEFAULTGLOBAL` `^OcuTalonP.KB<suffix>` / `^OcuTalonP.KB<suffix>Config` on the `CREATE TABLE` line (`kb-ddl`); every global resolves to OCUTALON_PRIVATE (AD-3, AD-33). A table is created only by `DocumentOps` (local `OnInit`, a session's first `AddDocument`) and `AddEval`; no code builds an AI Hub vector store over a table that does not exist, so a gone table is never reopened or rebuilt (AD-21).
- `DocumentOps` stays the only writer of document rows and knowledge-base rows during a session's life and the only publisher of `document` (AD-33); every knowledge-base operation on a row uses that row's own `KnowledgeBase`. The session-end deletion runs in `SessionOps`' job through the two `DropSession` methods, as AD-4 and AD-21 name them (spine union for the Tables line).
- `TurnToolsClass` follows AD-31: base `OcuTalon.Bridge.Ext.TurnTools` with `ClassMethod Tools(ownerRef As %String, kind As %String, Output tools As %ListOfObjects) As %Status` returning an empty list by default; a `Decide` setting (category Extensions) read in the runner's job through `Ext.Accessor.ClassFor`, whose `BASES` gains the pair; a named class that is missing or does not extend the base fails the request with that error, never a silent fallback. The bridge names no OcuTalon class (`bridge_refs`).
- Each object `Tools` returns answers `AddToManager(manager As %AI.ToolMgr) As %Status` (as `%AI.RAG.KnowledgeBase` does) and stays referenced by the adapter until the request ends.
- The composition runs in `SessionConfigFor` (AD-6's one composing method), in the runner's job, outside every callback, before `CreateSession`/`ResumeSession`; it composes at most once per request and always sets the gate and the step audit policy on the composed manager (AD-6, AD-10).
- Every test added or changed creates and removes its own state (`zz-` refs and names, Session fixture rows, tables, KB rows, memories, `^OcuTalonTest` nodes, the `onlineDemo` setting and Decide rows snapshot and restored) and passes on a fresh environment, in either order (Rule 19).

**Never:**
- No edit of a frozen release tool (`release/*.sh`, `release/upgrade-harness.sh`, `release/demo-host-check.sh`, `eval/run.sh`, the IPM artifact or check scripts) before the Planner's ruling on the hunks under Design Notes; no install from the public IPM registry.
- No edit of a Lane B file (`Core/**`, `Web/**`, `web/**`, `Data/Session.cls`, `Data/Upload.cls`, `Data/Ownership.cls`, `Demo/**`, `Msg/Command/**`, `Test/{Core,Web}/**`, `docker/Dockerfile`); `SessionOps.End` already calls both drops, and the two `DropSession` signatures stay exactly as Story 34.1 fixed them.
- No `%AI` reference in the class `OcuTalon.Docs` (package `OcuTalon`); no `%AI` native call or Python in a callback; no `%SYS.Python` in `DocumentOps`, the runner job or `TurnTools`.
- No new `AD-n`, no change to an AD's Rule, Binds or Prevents line: spine edits are plain unions marked `[AMENDED 2026-11-08, Story 19.5, ...]`.
- No PDF or Word routing (Story 19.7), no chip rendering (Story 20.2), no MCP attach (Story 35.1), no new CI group or job.
- No user-facing text beyond the ACs, `EXPERIENCE.md` and `epics.md`; the developer guide lines are PUBLIC TEXT (Design Notes).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First demo document | `onlineDemo` 1; visitor K (Session row id n) has no table; `POST /v1/documents` `{name:"Results runbook.md", content}` | 200 `{"result":"done","ref"}`; `OcuTalonKB.Sn` and `OcuTalonKB.Sn_Config` exist with AI Hub's columns and `DEFAULTGLOBAL` `^OcuTalonP.KBSn[Config]` in OCUTALON_PRIVATE, made before any `Build()`; the row has `OwnerRef` K and `KnowledgeBase` `OcuTalonKB.Sn`; `document` events go to K's stream; it reaches `ready` in K's `GET /v1/documents` only | indexing error: `failed`, the source's rows removed from `OcuTalonKB.Sn` |
| Demo remove | K's `DELETE /v1/documents/<ref>`; then C's `DELETE` of K's ref | K: 200, rows of the source gone from `OcuTalonKB.Sn`, last event `removed` on K's stream; C: 404 (Ownership) and `DocumentOps` would answer `not_found` | none |
| Per-turn tools, demo | A `turn` with `OwnerRef` K, K's table exists | `Docs.TurnTools` returns one holder over `OcuTalonKB.Sn`; the model request offers `documents`; its results hold only K's sources | KB build failure: one redacted warning, no tool, the turn goes on |
| No table yet / gone | A `turn` for a demo session whose table does not exist (no document yet, dropped, or no Session row after a reset) | No tool, the agent's own manager; no class, table or `^OcuTalonP.KBS*` global is created, nothing in OCUTALON_DATA | none |
| Local install | `onlineDemo` 0, a person's `turn` | The holder over `OcuTalonKB.Docs`; the 16 offered tools of 19.4 unchanged | as above |
| Other kinds | `decide`, `diagnose`, `tool` (Replay) | `Tools` returns none; the request uses the agent's own manager | none |
| Missing extension | `TurnToolsClass` names a class that does not exist or does not extend the base | The request ends with that error status (Decide's fallback route); no turn runs without its tools silently | error status |
| Fixture toolset (AC) | A test adapter that attaches a fixture toolset in `OnAfterAgentInit` through `Attach`, and a fixture `TurnToolsClass` that returns a fixture tool | The turn's model request offers the agent's tools, the fixture toolset's tool and the fixture turn tool; the next request without turn tools offers the first two only, same job | none |
| Skills | An agent class that declares `SKILLS` gets turn tools | The request fails with an error naming the agent (the composed manager cannot carry skills) | error status |
| Two concurrent sessions (AC) | K and C each add the runbook text (`Results runbook.md`, `Partner runbook.md`) and save "the Results partner's contact is Lee" (`memory-save`), then both send `documents-runbook` and `memory-recall-meaning` turns at the same moment | Each turn's `documents` results and `HostData.citations` hold only its own document's `source`; each `search_memories` result and `HostData.memories` only its own `memoryRef` | the unit fails |
| DW-893 | Local turn, then `onlineDemo` 1 with a session that has no table, then `onlineDemo` 0, one runner job | `documents` offered, not offered, offered again; same job id | none |
| Sign-out (AC) | K signs out (`POST /v1/session/end`) while C stays | 200; K's tables, classes, globals, Document rows and memories gone; C's intact and C's next turn still cites C's document; a second `Docs.DropSession(K)` and `Memory.DropSession(K)` return OK and change nothing; a K turn creates nothing | a held lock past 5 s: error status, End answers `failed`, the session stays resumable |
| Drop while indexing | `DropSession` while `DocumentOps` indexes the session's document | The drop waits for the batch (owner lock), then the next batch finds no row and stops; no table is re-created | lock timeout as above |
| Reset (AC) | A fresh online-demo install, ready, before any visitor (what the golden copy is captured from) | No `OcuTalonKB.S*` table or class, no `^OcuTalonP.KBS*` global, no `Data.Memory` and no `Data.Document` row | none |
| DW-892 | `Demo.Features` on the demo | Its documents entry is now true: the demo route answers 200 and the document reaches `ready` (no `Features.cls` change) | none |
| DW-901 | An evaluation run's documents and a person's document with the same text on one local install | The eval rows are in `OcuTalonKB.Eval`; the person's turn finds only the person's source, the eval turn (`OwnerRef` `eval`) only the eval sources | none |
| DW-900 | Eval rows left by a crash (in `OcuTalonKB.Eval`, or in `OcuTalonKB.Docs` from 19.4's code) | `Eval.In.Start` removes every `OwnerRef` `eval` row and its passages (`RemoveEval`) before its first case | a failed removal: one warning, the run goes on |
| Integration: consumer ChatAgent (Rule 1) | A real `turn` through `Decide` -> `ChatAgent` with the CI mock, on a demo document added through `Commands.Submit` -> `CommandsIn` -> `DocumentOps` | The adapter reads `TurnToolsClass`, the model request offers `documents`, `HostData.citations` names the session's own document | the test fails |
| Integration: consumer SessionOps.End (Rule 1) | Lane B's `SessionOps.End` from `POST /v1/session/end` | The two drops run in its job and the visitor's data is gone (live unit) | the unit fails |
| Upgrade harness (AC, after the ruling) | `release/upgrade-harness.sh run` | A memory (and a document, when the previous build indexes documents) made before the upgrade are present and searchable after the upgrade and after the restart; otherwise they are made on the candidate and checked after the restart, with the row's note | the row fails |

</intent-contract>

## Code Map

Line numbers are those of `OCT-epic19` at `11997361`. Contended now (checked 2026-11-08 after `git fetch`): Epic 11's diff is empty, Epic 31 is merged and its branch is gone, Epic 17's open diff (17.10) touches no file of this story. The feature has moved ahead of this branch in `ci/units.sh` (shards-5 gains `live:sign-in-3`), `Core/SessionOps.cls` (same drop calls), `Test/Agent/Runners.cls` (Epic 11's lines 149-228) and `docker/tests/test-class-rules.sh`: this story's edits there are plain unions at the next integrate-forward.

Bridge (Lane A, `paths_hint` `Bridge/{Ext,Adapter}/**`):
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- `BuildAgent` (197-217; built once per job, kept in AI Hub's `Agent`); `OnAfterAgentInit(ByRef agent)` (222-229: `##super`, then `agent.ToolManager.SetAuthPolicy(Gate.%New())`, `SetAuditPolicy(StepAudit.%New())`; no MCP attach yet); `SessionConfigFor(Output config)` (288-291: `Quit ..Compose(...)`, no request argument; callers `NewSession` 308-314 -> `..Agent.CreateSession(config)`, `OpenSession` 328-340 -> `..Agent.ResumeSession(opened, config)`; a compaction composes two or three times in one request: 672, 763); `Answer(request, superSession, Output reply)` (366-406: kind check 369, `BuildAgent` 380, `Context.Begin` 383, `AnswerLinked`/`AnswerRetried`/`NewSession`, `Converse` 553 with `..Agent.Chat(session, input, StepRenderer)` at 564, `SaveLinked` 602, `ReleaseSession` 840); `request.OwnerRef`/`Kind` are in scope from 369; `BaseChars` (882) and `Inventory` (1021-1042) read `..Agent.ToolManager`.
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls:57-65` -- `adapter.NewSession` before `Context.Begin`, then `adapter.Agent.ToolManager.ExecuteTool`; unchanged (kind `tool` composes nothing).
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls:1-6,11,19-35,60-95` -- doc "three extension classes"; `Parameter BASES = "HostSinkClass=...HostSink,ReplyFilterClass=...ReplyFilter,ClassificationClass=...Classification"`; `ValueFor` (`Ens.Director.GetItemSettingValue`), `ClassFor(setting, production, item = "Decide", Output sc)`, `Check` (empty, uncompiled or non-extending class is an error), `BaseOf`.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls` -- the shape to follow for the new base (doc header "(AD-31) ... default does nothing, so the bridge runs alone (FR-5). A host extends this class and names the subclass in the ...Class setting of the Decide item.").
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:139,210-216,1740-1753` -- `SETTINGS` (`HostSinkClass:Extensions,ReplyFilterClass:Extensions,ClassificationClass:Extensions,...`), the three properties `Property XClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.X" ];`, storage `DecideDefaultData` Values 1-3 (a new property appends a Value; AD-5).
- AI Hub (read in `irislib/`): `%AI/Agent.cls:144` `Property ToolManager As %AI.ToolMgr [ Transient ]` (plain settable, made in `%OnNew` 180); `%Init` 197-232 (`%LoadToolSets` from `ToolSets`/`#TOOLSETS` 404-420 via `UseToolSet` -> `RegisterToolSet`, `%LoadSkills` 553, `%OnInit`); `UseToolSet` doc 423-427: "every live session consults it fresh on each turn"; `CreateSession` passes `..ToolManager.%Discover()` (649); `ResumeSession` passes the manager token, ignored by `%AttachToAgent` (700; Session.cls 147-148); `Chat` passes `..ToolManager.%token` on every call (754-760); `UseSkill` loads a skill's tools into `..ToolManager` and keeps the catalog entry on the agent (470-552). `%AI/ToolMgr.cls` -- public `%New()`, `SetAuthPolicy`/`SetAuditPolicy` per manager (207-239; a fresh manager is unrestricted: `Agent.cls:938-955`), `AddTool(spec or instance)` (279), `RegisterToolSet` (441), `%OnClose` frees the native manager (676-693). `%AI/RAG/KnowledgeBase.cls:69-92,158-172` -- `Build(embedding, store)` keeps only native tokens, so the holder keeps the three objects; `AddToManager(toolManager)`.
- `src/bridge/cls/OcuTalon/BridgeExample/**` -- the standalone example (its agent's `TOOLSETS` 16); proved by CI workflow `lane-a.yml` job `standalone-bridge` (`bash release/standalone-bridge.sh`, frozen, run only) and `docker/tests/test-bridge-example.sh`.
- `docker/tests/lib-scan.sh:87-96` (`bridge_refs`) -- the bridge may name `OcuTalon.Docs.TurnTools` only in a `///` comment.

Docs and Memory (Lane A):
- `src/ocutalon/cls/OcuTalon/Docs.cls:8-11` -- `ClassMethod DropSession(sessionRef As %String) As %Status { Quit $$$OK }`; class in package `OcuTalon`, so SQL only, no `%AI` (`docker/tests/test-class-rules.sh:5-7,63-64,106`, case `kb_bad5` 411).
- `src/ocutalon/cls/OcuTalon/Memory.cls:22-47,52,128,163-166` -- `TABLE "OcuTalon_Data.Memory"`, `NEARESTSQL`/`KEYWORDSQL` (`WHERE SessionRef = ?`), `Search(sessionRef, query, limit, Output rows)` rows `{memoryRef, text, savedAt, origin}`, `List`, the `DropSession` stub (163-166).
- `src/ocutalon/cls/OcuTalon/Memory/Ops.cls:71,103,154` -- `row.SessionRef = request.SessionRef`; forget checks the owner; `Lock +^OcuTalon.Memory(sessionRef):5`. Memories are already per session on the demo (`Tools/CommandCall.cls:43,66-73`, `Tools/MemoryTools.cls:93,108` use `context.OwnerRef`).
- `src/ocutalon/cls/OcuTalon/Docs/Store.cls:23-26,37-41,45-69,78-117,125-158,161,174` -- `TABLE "OcuTalonKB.Docs"`, `SUFFIX "Docs"`, `TOPK`, `DESCRIPTION`, `LOGATTACH`; holder properties `Embedding`, `VectorStore`, `KnowledgeBase`; `EnsureTable()` with the literal DDL (51, 54), Private `Exists(table)`/`Create(table, statement)`; `Write(ref, name, passages, from, count)`, `Remove(ref)`, `Count(ref = "")` (-1 on a failed read), all on `..#TABLE`; `Attach(agent, Output holder)` (onlineDemo check 130, `EnsureTable`, `Docs.Embedding.Register`, `VectorStore.IRIS` `Schema`/`TableName` from `#TABLE`, `Build`, `KnowledgeBase(Names.#DOCUMENTS, DESCRIPTION)`, `TopK`, `Build`, `AddToAgent`; failure is one warning); `DocumentName`; Private `ToText`.
- `src/ocutalon/cls/OcuTalon/Docs/Ops.cls:34-62,81-89,92-125,128-207,212-271,274-302,341,347-372,382,399-413` -- `BATCH 8`, `OWNER "instance"`, `EVALOWNER "eval"`, `MESSAGENOTBUILT`; `OnInit` (local `EnsureTable`); `OnAdd` (95 `no_session`, 96 demo `not_built`, 99 `Upload.Take(UploadRef, SessionRef)`, 107 `Text` seam, 112-118 save, answer, `Index(Ref, 0)`); `OnIndex`/`IndexBatch(ref, from, Output state, Output row)` (182 `Store.Remove`, 185 `Store.Write`, 199); `AddEval` (215 demo `not_built`, 220 `EnsureTable`, 222 `NewRow(eval, eval, ...)`), `RemoveEval` (refuses another owner); `OnRemove` (281 `OwnerRef '= ..#OWNER` -> `not_found`); Private `OnlineDemo()` (341); `Save` -> `NewRow(..#OWNER, ...)` (347), `NewRow` sets `KnowledgeBase = Store.#TABLE` (367); `Fail` (382) on the fixed table; `Publish`/`PublishPayload` always `Live.Publish.#INSTANCE` (409). The session stream is the SessionRef itself (`Live/Publish.cls:73` `IsStream`).
- `src/ocutalon/cls/OcuTalon/Data/Document.cls:49,51` -- `RefIndex`, `OwnerRefAddedAtIndex`; `KnowledgeBase` MAXLEN 128 (its doc names `OcuTalonKB.S<rowid>`). No storage change in this story.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls:83,87-94` -- `Property Documents As OcuTalon.Docs.Store [ Transient ]` and `%OnInit` (`##super`, `Docs.Store.Attach($this, .holder)`): both go. Lane A, outside the `paths_hint` (footprint extension, as in 19.4).
- `src/ocutalon/cls/OcuTalon/Production.cls:15-66,20-23` -- Lane A's region; `Decide` with `HostSinkClass` (21) and `ReplyFilterClass` (22) item settings: the precedent for `TurnToolsClass`.
- `src/ocutalon/cls/OcuTalon/Eval/In.cls:204-229,245-264,671-691,739-806` -- `Start` (the sweep goes before the case loop, about 212), `Finish`, `TurnRequest` (`OwnerRef` `Ownership.#EVAL` 685, `Kind` `turn`), `DocumentsUp`/`AddOne`/`DocumentsDown` (`AddEval`/`RemoveEval`). Lane A, outside the `paths_hint` (footprint extension). Callers of `Start`: `Eval/Report.cls:327`, `Eval/Sweep.cls:83`.
- `src/ocutalon/cls/OcuTalon/Install/Step/PrivateData.cls:31-54,95` -- covers every compiled `OcuTalonKB.*` class's globals and scans OCUTALON_DATA: per-session and eval tables are covered with no edit.
- `docker/tests/test-class-rules.sh:100-115` (`kb-ddl`) -- one line: `CREATE TABLE` with `DEFAULTGLOBAL` and the literal `^OcuTalonP.`; a line built as `"CREATE TABLE "_table_" (...) WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KB"_suffix_"'"` passes (`Test/Memory/Fixture.cls:95` has that shape). No edit.

Lane B, read-only (no edit needed):
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:239-257,492-535` -- `End`: `EndDocumentsAndMemories` first (documents, memories, uploads, each in its own Try; a failure counts and keeps the resume hash); `DropDocuments` -> `Docs.DropSession` (520-523), `DropMemories` -> `Memory.DropSession` (526-529), `DropUploads` (532-535). The feature's copy has the same calls (571-613).
- `src/ocutalon/cls/OcuTalon/Data/Session.cls:26,67,152,249-251` -- `Ref` (MAXLEN 22, default collation), `RefIndex` unique (case-insensitive open: compare `row.Ref = sessionRef` exactly), `NewVisitor`, integer row id.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:341-366,756,970,974` -- `Documents`/`Document`: `OwnerRef = ? OR (local AND OwnerRef = 'instance')`, so the demo already lists only the session's rows.
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls:117,126-129,142,153-160` -- 501 only from a `not_built` answer or a stopped owner; `DELETE` filters through `Ownership.Document` first.
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls:20,26-34,56-60` (DW-892) -- `documents` = `Built("OcuTalon.Docs.Ops")`; true once the demo path works.
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOpsDocuments.cls:11-12,115-124` -- `TestRealStubsEnd` stays green when a real drop returns OK for a fixture session with nothing to drop; only its doc comment goes stale (Lane B's).

Tests that pin today's shape (Lane A):
- `Test/Docs/Chat.cls:73-81` (`TestAttach`: Chat's `%OnInit`, `TABLE|SUFFIX` = `OcuTalonKB.Docs|Docs`), `Test/Docs/Store.cls:13,262` (`TestAttach`, no holder on the demo), `Test/Docs/Ops.cls:18` (`TestOnlineDemo` asserts `not_built`), `Test/Docs/Live.cls:14-57` (`TestFound` builds an agent and calls `Attach`; `TestGone`), `Test/Docs/Turns.cls` (`TestEvalDocuments`).
- `Test/Bridge/Ext.cls:3,55,149` (three extension classes), `Test/Bridge/Runner.cls:645,698` (`TestStepsRedacted` chains a second audit policy onto the built agent's manager), `Test/Bridge/Gate.cls:867`, `Test/Bridge/Decide.cls:4017`, `Test/Bridge/Conversation.cls:1115` (read the agent's manager outside a turn: the agent's own manager, unchanged).
- `Test/Agent/Runners.cls:26,76-77,320-383,528-529` -- `TestToolInventory` expects `documents` in ChatAgent's inventory (`REMINDERTOOLS`, 325, 365-378, 383); 528-529 add it to a Chat turn's offered tools (stays).
- `Test/Install/SecurityOverview.cls:37,58,65,169,473-505` (`TestToolsMatchRunners` compares the rows with each runner's inventory), `Test/Install/Production.cls:13,654,676` (Decide's settings row).
- `Test/Contract/Step3.cls:65-82` (`TestDropSession` asserts the stubs keep the data), `Test/Contract/Ac.cls:381-382` (the two signatures: keep).
- `Test/Eval/Documents.cls` (19.4's AD-22 isolation test of the eval path), `Test/Memory/Fixture.cls:91-109` (`CreateTable`/`DropTable`), `Test/Memory/Search.cls` (`TestOwnerIsolation`).
- Offered-tool pins, local, unchanged (16 names with `documents`): `Test/Watch/Turns.cls:63`, `Test/Tools/Reminders.cls:275`, `Test/Tools/Persona.cls:296`.

CI, live and release:
- `ci/units.sh:89-109` -- `shards-2` is `shard:lane-a@rest` (Docs and Memory areas); `shards-5` is `shard:lane-a@Bridge,Agent`. `docker/tests/test-ci-config.sh` needs a new script in exactly one group; `group_input_pattern` picks it up; not in `BROWSER_UNITS` (curl only) nor `NO_WEB_BUNDLE_UNITS`; `.github/workflows/ci.yml` needs no edit.
- `docker/tests/test-online-session.sh:34-67,128-131,157-163,435` -- the online-demo start (`live_start`, `live_web_port`, `online_values`, `online_override`, `dc up -d --build`, `wait_started_ready 400`), two jars (`online_signin`), `session_row`, sign-out `POST /ocutalon/api/v1/session/end`. `docker/tests/test-documents.sh:40-127` -- `api_send`, `upload_body`, `doc_state`/`doc_is`, `run_class`/`check_live` (`CHK|` parse), `mark`, `chat_turn`. Mock scenarios reused: `ci/mock/scenarios/A/documents-runbook.json`, `memory-save.json`, `memory-recall-meaning.json`.
- `_bmad-output/implementation-artifacts/evidence/34-3-upload-reset.md` -- the golden-copy restore recipe (stop, copy `${P}_durable` to `${P}_golden`, add data, restore, start, CHK).
- `release/upgrade-harness.sh` (frozen; 1,829 lines): constants 59-80, `api_post` 600-603, `run_turn` 658-676, the pairing family 799-957 (the pattern), `phase_seed` 1169-1222 (family calls 1207-1211), `phase_upgrade` 1469-1536 (1527-1534), `phase_restart` 1540-1623 (1621). Its self-test `docker/tests/test-upgrade-harness.sh:442,486,505,774-903` hard-codes the rows. `release/rehearse.sh:72-75,1144-1209,1221` (memory-offline step and the sign-in step) and `docker/tests/test-rehearsal.sh:230-275,937-1001` (stub hosts).

Footprint (every file this story creates or edits; `[19.7]` = Story 19.7 likely edits it too):
- `src/bridge/cls/OcuTalon/Bridge/Ext/TurnTools.cls` (new)
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls` (edit)
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` (edit; footprint extension)
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` (edit)
- `src/ocutalon/cls/OcuTalon/Docs/TurnTools.cls` (new)
- `src/ocutalon/cls/OcuTalon/Docs/Store.cls` (edit) [19.7]
- `src/ocutalon/cls/OcuTalon/Docs/Ops.cls` (edit) [19.7]
- `src/ocutalon/cls/OcuTalon/Docs.cls` (edit; footprint extension)
- `src/ocutalon/cls/OcuTalon/Memory.cls` (edit; footprint extension)
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` (edit; footprint extension)
- `src/ocutalon/cls/OcuTalon/Production.cls` (edit, Lane A region)
- `src/ocutalon/cls/OcuTalon/Eval/In.cls` (edit; footprint extension)
- `src/ocutalon/cls/OcuTalon/Test/Bridge/TurnTools.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTurnAdapter.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTurnTools.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTurnToolset.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Docs/TurnTools.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Docs/Sessions.cls` (new) [19.7]
- `src/ocutalon/cls/OcuTalon/Test/Docs/SessionTurns.cls` (new) [19.7]
- `src/ocutalon/cls/OcuTalon/Test/Docs/SessionLive.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Memory/Drop.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Docs/Store.cls` (edit) [19.7]
- `src/ocutalon/cls/OcuTalon/Test/Docs/Ops.cls` (edit) [19.7]
- `src/ocutalon/cls/OcuTalon/Test/Docs/Chat.cls` (edit)
- `src/ocutalon/cls/OcuTalon/Test/Docs/Live.cls` (edit) [19.7]
- `src/ocutalon/cls/OcuTalon/Test/Docs/Turns.cls` (edit) [19.7]
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls` (edit)
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls` (edit)
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls` (edit; footprint extension, 19.4's own lines)
- `src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls` (edit)
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` (edit)
- `src/ocutalon/cls/OcuTalon/Test/Contract/Step3.cls` (edit; footprint extension)
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls` (edit; footprint extension)
- `src/ocutalon/cls/OcuTalon/Test/Eval/Documents.cls` (edit; footprint extension)
- `ci/mock/scenarios/A/turn-tools-probe.json` (new)
- `docker/tests/test-session-data.sh` (new)
- `ci/units.sh` (edit, Lane A entry) [19.7]
- `docs/bridge-guide.md` (edit; PUBLIC TEXT)
- `docker/tests/test-bridge-guide.sh` (edit)
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` (edit) [19.7]
- `_bmad-output/implementation-artifacts/evidence/19-5-task0-turn-tools.md` (new)
- `_bmad-output/implementation-artifacts/evidence/19-5-session-reset.md` (new)
- `_bmad-output/implementation-artifacts/evidence/19-5-dw783-rehearse-dry-run.md` (new)
- `release/upgrade-harness.sh` (edit; FROZEN: only after the Planner's ruling)
- `docker/tests/test-upgrade-harness.sh` (edit; with the same ruling)

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first; product default 5) -- one lane-C throwaway (`OCUTALON_RUN_TAG=e19s5i0`, the lane's variables, `OCUTALON_LOCK_OWNER='epic=19 stage=implement'`) with a scratch adapter subclass and scratch tables `OcuTalonKB.S9001`/`S9002` made through `Test/Memory/Fixture.CreateTable`; record in `evidence/19-5-task0-turn-tools.md`, then tear down.
  - M1: in a real ChatAgent turn on the CI mock, a fresh `%AI.ToolMgr` (Chat's toolsets registered, `Gate` and `StepAudit` set, a knowledge base over `S9001` added) assigned to `..Agent.ToolManager` before `CreateSession`, and on a second turn before `ResumeSession` of the linked session: the logged request offers `documents`, a `documents` call searches `S9001`, the gate decides it (a step is recorded, `Tainted` 1), and after the build-time manager is put back the next turn offers no `documents`; the job id is unchanged; no crash or deadlock within 120 s.
  - M2: the time to compose that manager (median of 10) and the `%OnClose` of the dropped manager (no error).
  - M3: turns for owners A (`S9001`) and B (`S9002`) as A, B, A on one job: each search returns only its own table's sources.
  - M4: `DROP TABLE` of `S9001_Config` and `S9001` after a knowledge base was built over it leaves no class, no `^OcuTalonP.KBS9001*` global and nothing in OCUTALON_DATA; a search through the knowledge base built before the drop does not re-create the table.
  - **Stop rule:** HALT `blocked` / `intent gap` with the measurement when M1 shows the session keeps the build-time manager's tools or the gate does not decide the call (name AD-21 "Attaching per turn" and AD-6; recommend a ruling on composing a new agent per request instead), or when M4 shows a re-created table (name AD-21 "a dropped table is never reopened").
- `src/bridge/cls/OcuTalon/Bridge/Ext/TurnTools.cls` (new) -- the base: `ClassMethod Tools(ownerRef As %String, kind As %String, Output tools As %ListOfObjects) As %Status` sets `tools` to an empty `%ListOfObjects` and returns OK; the doc states the element contract (`AddToManager(manager As %AI.ToolMgr) As %Status`, kept referenced until the request ends) in Classification's doc style. Rule 2: modelled on `Ext.Classification`.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls` -- `BASES` appends `,TurnToolsClass=OcuTalon.Bridge.Ext.TurnTools`; the doc says four extension classes.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- `SETTINGS` gains `TurnToolsClass:Extensions` after `ClassificationClass:Extensions`; `Property TurnToolsClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.TurnTools" ];` with one doc line; the storage Value is appended by the compiler and committed (AD-5). Nothing else.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- (a) `Method Attach(agent As %AI.Agent, spec As %String) As %Status`: `agent.ToolManager.AddTool(spec)` and, on success, records the spec (transient list), the one way `OnAfterAgentInit` adds a tool (Story 35.1's MCP servers); (b) one Private method sets `Gate` and `StepAudit` on a manager, used by `OnAfterAgentInit` and the composer; (c) `Answer` records the request's `OwnerRef` and `Kind` before its first session call; (d) `SessionConfigFor` composes the config as today and, once per request, reads `TurnToolsClass` through `Ext.Accessor.ClassFor` (an error status ends the composition with it), calls `Tools(ownerRef, kind, .tools)`; with no tool it keeps the agent's own manager; otherwise it refuses an agent with skills (error naming the class), makes `%AI.ToolMgr.%New()`, registers each entry of `..Agent.ToolSets` (else `#TOOLSETS`), re-adds every recorded spec, calls each tool's `AddToManager`, governs it (b), keeps the build-time manager and the tools in transient properties and assigns the new manager to `..Agent.ToolManager`; (e) when `Answer` ends, on every exit path, it puts the build-time manager back and releases the per-turn manager and tools. The class doc states the per-turn contract (Rule 14). No `OcuTalon` name outside comments (`bridge_refs`).
- `src/ocutalon/cls/OcuTalon/Docs/Store.cls` -- (a) `TableFor(ownerRef, Output suffix) As %String` and the owner rule `OwnerFor(sessionRef) As %String` (demo: the SessionRef; local: `instance`) with the one online-demo read moved here from `Docs.Ops` (Rule 2); the suffix check; (b) `EnsureTable`, `Write`, `Remove`, `Count` take an optional last argument `table` (default `..#TABLE`) and its suffix where the DDL needs it; (c) `Drop(table) As %Status`: `DROP TABLE IF EXISTS` of `<table>_Config`, then `<table>` (Task 0 M4 decides whether a leftover `^OcuTalonP.KB<suffix>*` global is killed too); (d) `Knowledge(table, Output holder) As %Status`: under the owner lock, nothing when the table does not exist, otherwise `Docs.Embedding` (`Register`), the vector store (`Schema`, `TableName`, `Build`) and the knowledge base (`Names.#DOCUMENTS`, `DESCRIPTION`, `TopK` 5, `Build`) in a new holder, a failure is one redacted warning and no holder; (e) `Method AddToManager(manager As %AI.ToolMgr) As %Status` delegates to `KnowledgeBase`; (f) `Attach` is removed. Locks: `^OcuTalon.Docs(<owner>)` shared (`#"S"`, 5 s) for `EnsureTable`+write paths and `Knowledge`, exclusive for `Drop` callers.
- `src/ocutalon/cls/OcuTalon/Docs/TurnTools.cls` (new; extends `OcuTalon.Bridge.Ext.TurnTools`) -- for kind `turn` only: the owner is `eval` for `ownerRef` `eval`, else `Store.OwnerFor(ownerRef)`; `TableFor`; `Knowledge` and one holder in `tools`, or an empty list; it never creates a table and never fails the turn over a missing or broken knowledge base.
- `src/ocutalon/cls/OcuTalon/Docs/Ops.cls` -- `OnAdd`: the demo `not_built` branch goes; the owner is `Store.OwnerFor(request.SessionRef)`, the table `TableFor(owner)`, `EnsureTable(table)` before the row is saved (a failure: a failed row, as today's failures); `NewRow` takes the owner and the table; `IndexBatch`, `Fail`, `OnRemove` and `RemoveEval` use `row.KnowledgeBase`, and `IndexBatch` holds the owner's shared lock for its writes; `OnRemove` answers `not_found` unless `row.OwnerRef` is `OwnerFor(request.SessionRef)`; `AddEval` writes owner `eval` into `OcuTalonKB.Eval`; `Publish` goes to the row's `OwnerRef` stream (`Live.Publish.#INSTANCE` for `instance`); `OnInit` unchanged (local `EnsureTable` of `OcuTalonKB.Docs`). The class doc states the per-owner tables (Rule 14).
- `src/ocutalon/cls/OcuTalon/Docs.cls` -- `DropSession(sessionRef)`: under the owner's exclusive lock (5 s; a timeout is an error status), delete every `Data.Document` row whose `OwnerRef` equals the SessionRef exactly, then `Store.Drop(TableFor(sessionRef))` when it maps to a table; OK when there is nothing; no event, no `%AI` name, independent of the `onlineDemo` setting; the signature and its doc's contract unchanged.
- `src/ocutalon/cls/OcuTalon/Memory.cls` -- `DropSession(sessionRef)`: under `MemoryOps`' lock `^OcuTalon.Memory(sessionRef)` (5 s; a timeout is an error status), `DELETE FROM OcuTalon_Data.Memory WHERE SessionRef = ?`; OK for an empty or unknown ref; signature unchanged.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- remove the `Documents` property and `%OnInit`; one doc clause: the documents tool reaches each turn through `TurnToolsClass` (Story 19.5).
- `src/ocutalon/cls/OcuTalon/Production.cls` (Lane A region) -- `Decide` gains `<Setting Target="Host" Name="TurnToolsClass">OcuTalon.Docs.TurnTools</Setting>` beside `HostSinkClass` and `ReplyFilterClass`.
- `src/ocutalon/cls/OcuTalon/Eval/In.cls` -- `Start`, before its case loop: every `Data.Document` row with `OwnerRef` `eval` is removed through `Docs.Ops.RemoveEval` (a failure is one warning); the doc says a run starts by sweeping what an earlier run left (DW-900) and that runs do not overlap.
- Tests (new):
  - `Test/Bridge/TurnTools.cls` with fixtures `ZzTurnAdapter` (an adapter subclass whose `OnAfterAgentInit` calls `##super` and then `..Attach(agent, <ZzTurnToolset>)`), `ZzTurnTools` (a `TurnToolsClass` that returns one holder whose `AddToManager` registers a fixture tool, or none, by a `^OcuTalonTest` node) and `ZzTurnToolset` (one read-only tool); through a runner on the CI mock (`turn-tools-probe`): the base returns none; `ClassFor("TurnToolsClass")` resolves the fixture, and a missing class fails the request; a turn with turn tools offers the agent's tools, the fixture toolset's tool and the fixture turn tool, the gate decides the fixture call and a step is recorded; the next request without turn tools offers the first two only; same job; an agent class with `SKILLS` and turn tools fails naming it; `Inventory` lists no turn tool.
  - `Test/Docs/TurnTools.cls` -- the owner and table rule (local person -> `Docs`, `eval` -> `Eval`, demo session -> `S<id>`, an unknown or case-different Ref -> none, a bad suffix refused), the kinds, a missing table -> no tool and no class, table or global made, a built holder searched through a bare `%AI.ToolMgr` finds only its own source.
  - `Test/Docs/Sessions.cls` -- `onlineDemo` 1 with two `zz-` visitor Session rows, through `Commands.Submit` as `web_user` -> `DocumentOps`: the first add makes `S<id>` and `_Config` (columns, `GetGlobalDest` OCUTALON_PRIVATE, no OCUTALON_DATA entry, `^IRIS.KNNIndex` empty), the row's owner and table, events on the session's stream; another session's remove is `not_found`; `Docs.DropSession` of one visitor drops its tables, classes and rows and leaves the other's; a second drop is OK and changes nothing; a drop during indexing leaves no table; a held owner lock makes the drop return an error.
  - `Test/Docs/SessionTurns.cls` -- live turns through `Decide` -> `ChatAgent` (the `Test.Memory.Turns` template, `[[mock:...]]`): A, B, A for two demo visitors with the same runbook text and the same memory text: citations, `documents` results (`RunnerFixture.ToolResults`) and memories are each session's own; DW-893 (local, demo without a table, local: `documents` offered, not, again; same job); a dropped session's turn creates nothing.
  - `Test/Docs/SessionLive.cls` -- skips unless `^OcuTalonTest("Docs","sessions")` names two SessionRefs; `ClassMethod Facts(sessionRef) As %String` ("tables|classes|globals|documents|memories" for one session, or for all `S*` with ""); the in-stack checks the live unit runs.
  - `Test/Memory/Drop.cls` -- `Memory.DropSession` removes only the session's memories (search and list find none of them, the other session's stay), is OK twice and for an unknown ref, and returns an error while `MemoryOps`' lock is held elsewhere.
- Tests (changed): `Test/Docs/Store.cls` (`TestAttach` becomes `Knowledge` tests; the table argument; `Drop`), `Test/Docs/Ops.cls` (`TestOnlineDemo`: the demo add, owner, table, stream; eval rows in `OcuTalonKB.Eval`), `Test/Docs/Chat.cls` (`TestAttach`: no `%OnInit` attach, `TABLE|SUFFIX` unchanged), `Test/Docs/Live.cls` (`TestFound` through `Store.Knowledge` and a bare `%AI.ToolMgr`; a new `ClassMethod Found(ref, query) As %String` returning "" or the reason, for the live units and the harness), `Test/Docs/Turns.cls` (`TestEvalDocuments` over `OcuTalonKB.Eval`; DW-901: a person's turn beside an eval run finds no eval source), `Test/Bridge/Ext.cls` (four classes, `TurnToolsClass` read in another job), `Test/Bridge/Runner.cls` (`TestStepsRedacted` puts its second audit policy on every manager through a test adapter subclass that extends the governing method, never through a product setting), `Test/Agent/Runners.cls` (ChatAgent's inventory no longer lists `documents`: `REMINDERTOOLS`, 325, 365-378, 383; 528-529 stay), `Test/Install/SecurityOverview.cls` (the `documents` row is checked against a local Chat turn's offered tools, not the inventory), `Test/Install/Production.cls` (Decide's `TurnToolsClass`), `Test/Contract/Step3.cls` (`TestDropSession`: the drops now remove the session's data and only that), `Test/Contract/Ac.cls` (the `TurnTools.Tools` contract pin beside the two `DropSession` pins), `Test/Eval/Documents.cls` (DW-900: crash-left `eval` rows in both tables are gone after `Start`).
- `ci/mock/scenarios/A/turn-tools-probe.json` (new) -- calls the fixture turn tool once, then answers with a fixed text.
- `docker/tests/test-session-data.sh` (new live unit `live:session-data`, curl only) -- online-demo throwaway (test-online-session's start, Rule 2 copy with reason: `lib-online.sh` is shared), `keys_point`; fresh check before any visitor (`SessionLive.Facts("")`: no `S*` table, class or global, no memory, no document); visitors K and C sign in; each posts the runbook text (`Results runbook.md`, `Partner runbook.md`) and waits for `ready`; each list shows only its own; each sends a `memory-save` turn; then both send `documents-runbook` and then `memory-recall-meaning` turns at the same moment (two background curls, both awaited); the mock log's tool results of each turn hold only its own `source` and `memoryRef`; K signs out (200); `Facts(K)` all zero, `Facts(C)` intact, C's `documents-runbook` turn still holds C's source; `Docs.DropSession(K)` again is OK; `SessionLive` passes; teardown. Prints one `SESSION-DATA` line with the seconds.
- `ci/units.sh` (orchestrator ruling 2026-11-08, item 6) -- rebalance `shards-2` before the push: move whole areas out of `shard:lane-a@rest` into existing pieces of other groups (rest is computed from the pieces the groups name, so every area stays in exactly one piece), and put `live:session-data` and every new class's area into the shortest group with room, so that each group's projection stays under 2,100 s; never `production`, `browser`, `install-fresh` or `install-upgrade`; no group added or renamed; no deadline raised. Measured (green runs; group seconds): this branch at 881ac467 (ci 42445320545): shards-2 1,766 (READY 280; areas Fix 738, Docs 225, Memory 197, Eval 170, Tools 93, Digest 40), shards 1,763, shards-3 1,976, shards-4 about 1,940, image about 1,790, shards-5 about 1,270 (Bridge,Agent only); the feature at 550bf9b8 (ci 42425689094, jobs): shards-5 1,901 (Bridge,Agent 1,222 + Story 32.5's live:sign-in-3 678), shards 1,868, image 1,895, shards-3 1,831, shards-4 1,917, browser 1,765. Project with the feature's shards-5 (the integrate-forward brings it). Write the measured inputs and the projection in one comment block; `bash docker/tests/test-ci-config.sh` passes. Report each move and each new unit's group in the Auto Run Result.
- `docs/bridge-guide.md` and `docker/tests/test-bridge-guide.sh` -- the settings table row, the "read each time" list and the extension classes section (PUBLIC TEXT under Design Notes), and the pins of the changed lines.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- plain unions marked `[AMENDED 2026-11-08, Story 19.5, ...]` (list under Design Notes); lint afterwards, no new finding.
- DW-783 (once, no edit of a frozen tool) -- the rehearsal dry run on a lane-C throwaway: `bash release/rehearse.sh install --dry-run --rc 1`, then `report`, then `down`, with the lane's variables and `OCUTALON_RUN_TAG=e19s5ir` (bounded polls when backgrounded); the evidence shows `MEMOFF-RECONNECTED`, the `sign-in` step passing on the published web port right after it, and `docker port` of the container after the reconnect. A failure there is an `intent gap` naming `release/rehearse.sh:1159`.
- Reset evidence (once) -- the 34.3 golden-copy recipe on an online-demo throwaway (`e19s5ig`, a scratch script in the stage scratchpad, never committed): golden copy after ready, one visitor adds a document and a memory, restore, start; `Facts("")` all zero and a turn for the old SessionRef creates nothing; `evidence/19-5-session-reset.md`, with one mutation run (a fixture `S` table left in the golden copy turns the check red).
- `release/upgrade-harness.sh` and `docker/tests/test-upgrade-harness.sh` -- RULED 2026-11-08 (Contest Planner under the owner's delegation, relayed by the orchestrator: option (a)): apply the hunks H1 to H9 under Design Notes "Frozen release tools" EXACTLY as written there and change no other line of any release tool; `bash docker/tests/test-upgrade-harness.sh` passes with them; the memory part runs on the 1.0.3 -> 1.0.4 upgrade (1.0.3 saves memories, so the seed's `built_class` check finds MemoryOps built on the previous build); the document part waits for the next release, as `DOCUMENT_UPGRADE_NOTE` says. Then one `release/upgrade-harness.sh run` on a lane-C throwaway (`e19s5ih`, bounded foreground polls when it is moved to the background) or, if it cannot run locally, a note for the Planner's record. List the applied hunks (file, lines) in the Auto Run Result as `release_tool_hunks:`.

- [x] [Ruling] DW-940 (RULED 2026-11-08, Contest Planner under the owner's delegation, relayed by the orchestrator: option (a)) -- a MINIMAL fix inside the approved hunks H5/H6 of `release/upgrade-harness.sh`: an EMPTY answer of the IRIS call counts as a FAILURE, never as success -- `document_found` (H5, :1027) returns a reason (not "") when the call prints nothing, and `built_class` / `seed_memory` / `seed_document` (H5) treat an empty answer as a failure of the family, never as "not built". The change is limited to that check; no other harness line changes. A test in `docker/tests/test-upgrade-harness.sh` (`t_memory_document`, H9) pins both cases: an empty answer fails and a real answer passes. The exact hunk goes into `## Auto Run Result` under `release_tool_hunks:`. Rides in 19.5's review (or rework); it does not re-open 19.4.

**Acceptance Criteria:**
- Given the online demo (P6 decided), when a session adds its first document through `POST /v1/documents`, then `OcuTalon.Docs` has created `OcuTalonKB.S<id>` and `OcuTalonKB.S<id>_Config` with AI Hub's exact columns and `DEFAULTGLOBAL` under `^OcuTalonP.` (resolving to OCUTALON_PRIVATE) before any vector store is built, and the document reaches `ready` in that session's list only (FR-15, AD-3, AD-21).
- Given a turn, when the runner prepares it, then `Decide`'s `TurnToolsClass` returns the owner's knowledge base or none; when it returns one, the adapter composes a fresh tool manager (the agent's tools, the tools attached in `OnAfterAgentInit`, that knowledge base, the gate and the audit policy) and assigns it before the session opens, in `SessionConfigFor`, and the turn's model request offers `documents` over that owner's table only; when it returns none, the request keeps the agent's own manager, to which no turn adds a tool; no knowledge base stays bound after the request, and a fixture toolset attached in `OnAfterAgentInit` is offered in that turn (AD-6, AD-21, AD-31).
- Given the bridge alone with the do-nothing default, when the standalone bridge job runs `OcuTalon.BridgeExample`, then it passes as before (FR-5, AD-2, AD-31).
- Given two concurrent online-demo sessions with different documents and memories, when each asks at the same time a question both could match, then each turn's tool results and `HostData` hold only its own passages and memories (FR-15, FR-41, FR-42, AD-4).
- Given a fresh online-demo install ready before any visitor (the golden copy's source), when its data is read, then no session table, class or global and no memory or document exists; and given a session whose table is gone, when a turn or a drop names it, then no table is created and no knowledge base is built over it (FR-15, FR-59, AD-21, AD-25).
- Given an online-demo session with documents and memories, when it signs out and Lane B's `SessionOps.End` calls `OcuTalon.Docs.DropSession` and `OcuTalon.Memory.DropSession`, then that session's tables, documents and memories are gone, another session's are untouched, each drop is idempotent, and the dropped table is never reopened (FR-14, FR-15, FR-41, FR-42, AD-4, AD-21).
- Given an evaluation run, when it starts and while it runs, then documents an earlier run left are removed first (DW-900), and its documents are in `OcuTalonKB.Eval`, which no person's turn searches (DW-901); pinned (U-305 kept, with the orchestrator's pin): a person's chat turn that runs while an eval run's documents are indexed in `OcuTalonKB.Eval` gets `documents` results and citations with no eval source (a test with its own mutation: the person's turn searching `OcuTalonKB.Eval` turns it red).
- Given the upgrade-in-place harness, when it runs from this release on, then it creates a memory and a document before the upgrade when the previous release can save or index them (otherwise on the upgraded candidate, checked after the restart, with the row's note), and both are present and searchable after it (FR-60, NFR-16, NFR-17, REL-6; epics.md amended 2026-11-08, Rule 5 tier-1; on the 1.0.3 -> 1.0.4 upgrade the memory is made before the upgrade and the document on the candidate).

### Review Findings

Code review 2026-11-08 (four layers, full-opus tier; 34 raw findings; 14 root-cause entries kept after grouping, high 0, medium 5, low 9; 10 rejected). Every patch below was applied in the review pass and verified on the lane-C warm stack (tag e19s5cw) or by `bash docker/tests/test-upgrade-harness.sh`; mutation lines are under `## Verification`.

- [x] [Review][Patch] (medium, hermeticity) `Test.Eval.Documents` TestEmbedFailure, TestSecondFileFails and TestRefusals compared whole-table counts: on a stack without `OcuTalonKB.Eval` (a fresh CI stack of the `shards` piece, where `TestEmbedFailure` runs first) the count is -1 before and 0 after `AddEval` makes the table, and any DocumentOps work of another class moves the totals; QA's one-time red after `Docs.Sessions` was this (its reruns found the table made). Now the helper `Left()` counts only the `Zz eval` rows and passages, a missing table as 0 [src/ocutalon/cls/OcuTalon/Test/Eval/Documents.cls:237]
- [x] [Review][Patch] (medium, regression gap) No test failed a request after its manager was composed, so putting the agent's own manager back on the error path (no knowledge base stays bound, AC2) was unpinned: new `Test.Bridge.TurnTools` TestFailureRestores with the `ZzTurnAdapter` fail node [src/ocutalon/cls/OcuTalon/Test/Bridge/TurnTools.cls:175]
- [x] [Review][Patch] (medium, regression gap) The owner lock and the drop-mark exit of `Docs.Ops.IndexBatch` (matrix row "Drop while indexing") were pinned by no test that can fail: new `Test.Docs.Sessions` TestBatchYieldsToDrop (a marked owner, an exclusive lock held by another job, then the control batch); `Hold` takes an exclusive flag [src/ocutalon/cls/OcuTalon/Test/Docs/Sessions.cls:359]
- [x] [Review][Patch] (medium, ruled task DW-940) The upgrade harness read an empty IRIS answer as success: `document_found` now returns a reason when the call prints nothing, and `seed_memory`/`seed_document` fail on an empty `built_class` answer; `t_memory_document` pins both cases [release/upgrade-harness.sh:1027]
- [x] [Review][Patch] (low) `Docs.Ops.Fail` skipped the passage removal for a row with an empty `KnowledgeBase` (a Story 19.4 row), which `IndexBatch` and `OnRemove` map to `OcuTalonKB.Docs`: it now removes from that table too [src/ocutalon/cls/OcuTalon/Docs/Ops.cls:434]
- [x] [Review][Patch] (low) The one-writer sentences of `Docs.Ops` and `Memory` did not name the sign-out deletion in SessionOps' job [src/ocutalon/cls/OcuTalon/Docs/Ops.cls:5] [src/ocutalon/cls/OcuTalon/Memory.cls:3]
- [x] [Review][Patch] (low) `Test.Docs.SessionTurns` TestTwoVisitors skipped the `search_memories` isolation check when the result held no memory list: the list is now asserted first [src/ocutalon/cls/OcuTalon/Test/Docs/SessionTurns.cls:286]
- [x] [Review][Patch] (low) `Test.Docs.TurnTools` TestKinds asserted a constant 0 (`%IsA` of the base on its subclass) beside the `%Extends` check; the constant half is gone [src/ocutalon/cls/OcuTalon/Test/Docs/TurnTools.cls:188]
- [x] [Review][Patch] (low) The document half of the harness AC had no `mutation:` line: recorded under `## Verification` [docker/tests/test-upgrade-harness.sh:1015]
- [x] [Review][Defer] (medium) An approved call of a tool that only a `TurnToolsClass` manager offers cannot be replayed (`Replay.Run` runs `ExecuteTool` on the agent's own manager) [src/bridge/cls/OcuTalon/Bridge/Replay.cls:65] -- deferred: DW-950 decision-pending owner=burndown (a product call; the spec's matrix row "Other kinds" composes nothing for `tool`, `Replay.cls` is outside the paths_hint, and OcuTalon's `documents` is held only when Decide's ToolClassification row cannot be read)
- [x] [Review][Defer] (low) `api_get` polls `GET /v1/documents` with no unique `probe` query [release/upgrade-harness.sh:618] -- deferred: DW-951 wontfix-accepted (frozen hunk H4; the document check also needs the IRIS-side search)
- [x] [Review][Defer] (low) A request with turn tools rebuilds its manager from TOOLSETS and `Attach` only, so a tool an agent adds in `%OnInit` is absent from it [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:370] -- deferred: DW-952 wontfix-accepted (no agent does it; the guide names TOOLSETS)
- [x] [Review][Defer] (low) A drop that times out leaves a document stopped by the drop mark in `indexing` until a later drop [src/ocutalon/cls/OcuTalon/Docs.cls:22] -- deferred: DW-953 wontfix-accepted (decided (g))
- [x] [Review][Defer] (low) `docs/security-overview.md` is not brought up to date with this story (inventory statement, online-demo isolation line) [src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls:16] -- deferred: DW-954 wontfix-accepted (PUBLIC TEXT)

Rejected:
- low: `TurnToolsClass` read fails every request when no production names an item Decide (ValueFor reads the production definition, the defaults and the property's initial value; AD-30 fixes the item name, the gate reads ClassificationClass the same way, and the standalone job passed) -- theoretical.
- low: the drop mark stays in `^IRIS.Temp` when SessionOps' job dies between `Drain(1)` and `Drain(0)` -- theoretical: real only for a job killed mid-sign-out, and the next sign-out of the session clears it.
- low: `AddDocument` reads the online-demo flag twice (`OnAdd`, `Save`) -- theoretical: `onlineDemo` is an install setting that does not flip during an add.
- low: the spine's AD-31 line "reads the three settings" -- its first bullet already names the fourth, `TurnToolsClass`'s own bullet says it is read through `ClassFor`, and rewording an AD's Rule is not a stage's spine edit.
- low: Task 0 M1 used a scratch agent, not ChatAgent -- `Test.Docs.SessionTurns` covers ChatAgent with the real gate; redoing the measurement is more than a correction.
- low: `Test.Bridge.TurnTools` asserts no gate decision record and resolves the class through `ValueFor` -- the composed manager's authorization policy is asserted to be the Gate, and `TestMissingClass` drives `ClassFor`.
- low: `OcuTalonKB.Eval` is left after the tests -- it is a product table that `AddEval` makes and the product never drops (like `OcuTalonKB.Docs`).
- low: `Test.Docs.SessionLive` TestSignedOut cannot be turned red by the AC5 mutation -- `Test.Docs.TurnTools` TestNoTable and `Test.Docs.SessionTurns` TestDroppedSession pin AC5.
- spec edit: the footprint and Auto Run Result lists miss `Test/Bridge/Conversation.cls` and seven fixtures; the matrix row says 200 where the route answers 204; the stub-only 1.0.3 path -- each fix edits the spec under review (decided (f) and the residual risks record them).
- spec edit: `status: done` while DW-940 was open -- delivered in this pass.

## Spec Change Log

- 2026-11-08T10:32Z (lead, runner respawn): DW-940 ruled option (a) by the Contest Planner under the owner's delegation (orchestrator relay): minimal H5/H6 fix, empty answer = failure, test pins both cases, no other harness line; added as an open `[Ruling]` task, delivered in the review pass.
- 2026-11-08 (lead, spec gate after the rulings; orchestrator RESUME of about 05:25Z, Contest Planner under the owner's delegation): (1) release-tool freeze: option (a), apply H1-H9 exactly, with the conditions now in the harness task; (2) PUBLIC TEXT approved as written (the bridge-guide `TurnToolsClass` row, line 153's "and `TurnToolsClass`", the line 309 lead-in "...four classes, ..." and its fourth bullet, the two harness notes); (3) veto U-305 (`OcuTalonKB.Eval`) KEPT, with the pin added to the DW-901 AC; veto U-304 (19.4's AD-5 seed) KEPT; (4) Story 19.4 rides with this story (no part merge of 19.4 alone: the demo needs the per-session knowledge bases); (5) Story 19.7 is built by a second runner on `OCT-epic19b` and merged into `OCT-epic19` later, so this story keeps 19.4's `Docs.Ops` and `Test.Docs.Ops` structure where it can (19.7 edits only the Text seam and `TestNotBuilt`); (6) CI: rebalance `shards-2` before the push and put the new units into the shortest group with room (the `ci/units.sh` task). The upgrade-harness AC carries the epics.md tier-1 amendment's wording. Status set to `ready-for-dev`.

## Review Triage Log

### 2026-11-08 -- Review pass
- verdicts: 51 findings -- high 0, medium 4, low 46, false 1, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: `Attached` never reset when `BuildAgent` builds again after a failed build (Adapter/Agent.cls) -- real: OnAfterAgentInit runs again and Attach appends the spec twice; fixed by clearing `Attached` at the start of `BuildAgent`; pinned by TestComposesOnce (rebuild leaves one recorded spec).
  - `[low]` `[reject]` Blind: composed manager drops a tool added without `Attach` -- the adapter class doc names Attach as the one way OnAfterAgentInit adds a tool, and a skills agent fails loudly; no unmarked path in the product adds one; a catalog check would be new surface for a case nothing reaches.
  - `[medium]` `[patch]` Blind: "composed at most once per request" untested -- added `Test.Bridge.TurnTools` TestComposesOnce (two session configs of one request ask the class once and give one manager; the agent manager is put back) with the fixture `ZzTurnAdapter.TwoConfigs`; mutation recorded.
  - `[low]` `[patch]` Blind: `AssertTurnTool` states a negative it does not check -- the doc sentence now states only what is checked and the test asserts that at least one runner was asked.
  - `[low]` `[patch]` Blind: timing-dependent assertions -- `TestDropWhileIndexing` now asserts the document is `indexing` before the drop, and `TestDrain` pins the drain mark without a sleep; the `^IRIS.KNNIndex` empty check is the AC text (a throwaway-only class), so it stays.
  - `[low]` `[reject]` Blind: data written after a drop, unconditional `Drain(owner,0)`, rejected row with an empty KnowledgeBase -- needs an `AddDocument` or save that is in flight at the moment of sign-out, whose session cookie is already ended; the host reset empties the rest; theoretical for the demo.
  - `[low]` `[reject]` Blind: empty `KnowledgeBase` falls back to the install table -- every session row is saved with its table (Ops OnAdd sets it before the first save); the fallback serves 19.4 rows that have none; a rejected row has no passages to index or remove.
  - `[medium]` `[defer]` Blind: the harness reads an empty answer of the IRIS call as "not built" (`built_class`) and as "found" (`document_found`) -- real false-pass in a release gate, but the fix is an edit of H5 and H6 of the approved hunks of `release/upgrade-harness.sh`; deferred for a ruling on the exact lines.
  - `[low]` `[reject]` Blind: the 1.0.3 -> 1.0.4 upgrade path was not run for real -- the spec's matrix names the "otherwise" branch for a previous build that cannot save or index; the stubs cover the other branch; stated under residual risks.
  - `[low]` `[reject]` Blind: the evaluation sweep assumes no overlapping run -- the DW-900 text says evaluation runs do not overlap; a lock would be new scope.
  - `[low]` `[patch]` Blind: stale text -- the `Docs.Ops` class doc said a document is shared by every user of the install; now says it belongs to its owner. The Auto Run Result is rewritten at finalize; the `ci/units.sh` margin figures are labelled inference and the first CI run replaces them.
  - `[low]` `[reject]` Edge: AddDocument or save_memory racing the sign-out drop re-makes data -- same root as the Blind row on data written after a drop.
  - `[low]` `[patch]` Edge: `Attached` duplicated on rebuild -- same root and fix as the first Blind row.
  - `[low]` `[reject]` Edge: an `AddToManager` error fails the turn -- registering a knowledge base on a bare manager is local and does not fail on a built holder; a build failure (the case the matrix names) is handled in `Tools`; the class doc claim is corrected.
  - `[low]` `[reject]` Edge: a turn still searching after the sign-out drop gets a tool error -- measured in Task 0 (M4: no table is re-made); the visitor has signed out.
  - `[low]` `[reject]` Edge: `DropSession` has no onlineDemo check, so a local End drops that session's memories -- by design: the spec makes the drops independent of the setting and Lane B's `SessionOps.End` decides when they run.
  - `[low]` `[reject]` Edge: overlapping drops of one owner share one drain mark -- a retry of a failed sign-out runs after the first call returned; no concurrent callers exist.
  - `[false]` `[reject]` Edge: `Fail` after the row is gone leaves passages -- the row goes only through RemoveDocument or DropSession, and both remove the passages or the table first; no path leaves passages without a row.
  - `[low]` `[patch]` Edge: `EnsureTable` doc says the caller holds the owner lock -- only the session path of DocumentOps does; the doc now says so.
  - `[low]` `[reject]` Edge: a missing install table gives no documents tool until the next upload -- the spec says the tool never creates a table; OnInit makes it at start and logs a warning when it cannot.
  - `[medium]` `[defer]` Edge: `document_found` reads an empty answer as found -- same root and route as the harness row of the Blind Hunter (H5).
  - `[low]` `[reject]` Edge: `test-session-data.sh` places an empty mark in `Seen(...)` -- the script then fails with a syntax error, a loud failure of the unit and not a false pass.
  - `[low]` `[reject]` Edge: the sweep warning is not redacted -- the sibling warnings of Eval.In are not either, and the text is an internal status.
  - `[low]` `[patch]` Edge claim: Docs.TurnTools "never fails a turn over a knowledge base" -- the doc now says its `Tools` never returns an error over one.
  - `[low]` `[patch]` Edge claim: owner lock for EnsureTable on every path -- same doc fix as the `EnsureTable` row.
  - `[low]` `[reject]` Edge claim: a dropped table is never reopened -- true for searches and drops; a late AddDocument is the Blind row on data written after a drop.
  - `[medium]` `[defer]` VG: the harness helpers are verified through stubs only, and `document_found` maps an empty answer to found -- same root and route as the harness rows above (H5); the real run is the DW-783 rehearsal.
  - `[low]` `[patch]` VG: the "not offered" assertions pass when no model request was logged -- both sites in SessionTurns now assert a request was sent first (positive controls already precede them).
  - `[low]` `[patch]` VG: `TestDropWhileIndexing` does not show the drop met an indexing document -- precondition added.
  - `[low]` `[patch]` VG: `AssertEquals(job, $Job)` in TestTurnTools cannot fail (a shadow runner in the test's process) -- removed, with its header text.
  - `[low]` `[reject]` VG: the "at the same moment" live turns serialise at a pool of 1 -- the unit sends two requests at once and pins that neither result holds the other's source; it claims no parallel execution.
  - `[low]` `[patch]` VG: `AssertTurnTool` skips unlisted runners and asserts no runner ran -- the checked count is asserted and the doc states only what is checked.
  - `[low]` `[reject]` VG: TestNoTable's last check names only S0 -- the Facts-based checks of Sessions and SessionTurns cover a made table for any suffix.
  - `[low]` `[patch]` VG: `TestOtherKinds` skips its assertions when no request was logged -- an assertion of the request count was added.
  - `[low]` `[patch]` VG mutation line: upgrade-harness AC -- mutation applied and recorded.
  - `[low]` `[patch]` VG mutation line: fresh install before any visitor -- recorded from the reset evidence (the golden copy with a fixture table).
  - `[low]` `[patch]` VG mutation line: live half of the two-session AC -- mutation applied in `live:session-data` and recorded.
  - `[low]` `[patch]` VG mutation line: memory half of the two-session AC -- mutation applied in `live:session-data` and recorded.
  - `[low]` `[patch]` VG mutation line: drain mark -- TestDrain added with a mutation recorded.
  - `[low]` `[reject]` VG not self-contained: `TestKinds` over the install table -- other tests remove their documents; the class cleans its own refs.
  - `[low]` `[reject]` VG not self-contained: `AssertTurnTool` relies on onlineDemo off -- the default of every stack and a local-turn test by definition.
  - `[low]` `[reject]` VG not self-contained: live step 5 acts after the 204 -- `SessionOps.End` is synchronous within the request; two green runs.
  - `[low]` `[reject]` VG not self-contained: fixed table names S9096-S9099 -- they collide only at Session ids that high, and the cleanup is exact.
  - `[low]` `[reject]` VG: the Example AC is pinned by `release/standalone-bridge.sh` only -- `Test.Bridge.Example` skips off a throwaway by design; the standalone job is the pin and ran green.
  - `[low]` `[reject]` VG: `Docs.TurnTools.Tools` error path has no test that makes `Knowledge` throw -- `Test.Docs.Store` TestKnowledge pins the build-failure warning where it arises.
  - `[low]` `[reject]` Intent: sign-out answers 204 where the matrix says 200 -- decided in-stage (f) from the route as it is (Lane B); the unit pins 204.
  - `[low]` `[reject]` Intent: End with a held lock is pinned at the drop and not through `SessionOps.End` -- the drop returns the error status End turns into `failed`; Lane B's `Test.Core.SessionOpsDocuments` stays green.
  - `[low]` `[reject]` Intent: the drop uses a drain mark besides the owner lock -- decided in-stage (g), measured on a loaded stack.
  - `[low]` `[reject]` Intent: concurrency is two simultaneous requests, one runner job -- see the VG row on pool size.
  - `[low]` `[reject]` Intent: the reset is emulated from a golden copy, not the host's scripts -- they live outside the repository; the evidence says so.
  - `[low]` `[reject]` Intent: no direct assertion on the `Demo.Features` documents entry -- the live unit pins the route (200, ready) that the entry stands for.

## Design Notes

**Architecture decisions:** AD-2 (the bridge stays separable: a do-nothing base, named as a string, `bridge_refs`; the class `OcuTalon.Docs` is SQL only), AD-3 (every KB global private), AD-4 (session ownership; sign-out drops documents and memories), AD-5 (the new Decide property appends its storage Value; tables and rows survive a restart), AD-6 (one composing method, gate and audit always, no `%AI` in callbacks), AD-10 (every composed manager is governed), AD-21 (Documents: Creating, Attaching per turn, Removal, Tables, Names), AD-22 (tests, mock under `A/`, the eval kind), AD-25 (the golden copy holds no session data), AD-29 (Lane A files; Lane B read-only), AD-31 (`TurnToolsClass`), AD-33 (`OcuTalon.Docs` creates and drops KB tables; `kb-ddl`; one publisher). Conventions: "Settings", "Citations and memories", "Tests", "Python".

**Integration ACs:** the matrix rows "Integration: consumer ChatAgent" (`Test.Docs.SessionTurns`, real runner, gate, AI Hub tool, `CommandsIn` and `DocumentOps`) and "Integration: consumer SessionOps.End" (`live:session-data` through the real sign-out route).

**Consumed-by:**
- 19.7: `Store.OwnerFor`/`TableFor` and the `KnowledgeBase`-driven `IndexBatch`, so PDF and Word documents join the session's own knowledge base on the demo.
- 35.1: `Adapter.Attach` in `OnAfterAgentInit`, whose specs every composed manager re-adds (the MCP servers).
- 20.2, 25.3, 26.2: citations and the per-session knowledge base as they stand.

**Consumes:** 34.1 (stubs, names, table naming, the `TurnToolsClass` contract), 19.4 (`Docs.Store`, `Docs.Ops` `IndexBatch`/`AddEval`/`RemoveEval`, `Bridge.Citations`, the seeded `ToolClassification` row), 19.3 (`Memory`, `MemoryOps`' lock), 16.4 (`SessionOps.End`, Lane B), 34.2/34.3 (routes, `Upload.Take`), Epic 13 (the standalone bridge job), 17.2/17.3 (`SessionConfigFor`).

**Extend, don't copy:** `Ext.TurnTools` follows `Ext.Classification`; `Docs.TurnTools` extends it as `Checks.ReplyGuard` extends `Ext.ReplyFilter`; `Docs.Store` gains the table argument instead of a second store class; `Store.Drop` is the product twin of `Test/Memory/Fixture.DropTable` (the fixture may call it later); `DocumentOps` keeps one `IndexBatch` for every owner; `Memory.DropSession` takes `MemoryOps`' own lock; the composer reuses the governing method of `OnAfterAgentInit`; `test-session-data.sh` copies test-online-session's start and two jars and test-documents' helpers, because `lib-live.sh` and `lib-online.sh` are shared (19.4's reason).

**Decided in-stage:**
- A request whose `TurnToolsClass` returns no tool keeps the agent's own manager: no turn ever adds a tool to it, so nothing stays bound, the standalone bridge runs exactly as before, and an agent's `SKILLS` (which the bridge guide supports and a composed manager cannot carry, because `UseSkill` keeps its catalog on the agent) keep working. A request that does get turn tools on an agent with skills fails with an error naming the agent. The composition happens once per request (a compaction composes two or three configs); `Replay` records no request, so it composes nothing.
- The knowledge base reaches the adapter as the `Docs.Store` holder, which keeps the embedding, the vector store and the knowledge base referenced (each frees its native handle on close) and answers `AddToManager`.
- `TurnTools` never creates a table: `DocumentOps` does (local `OnInit`, a session's first add, `AddEval`). The online-demo flag and `OwnerFor` live in `Docs.Store`, read once per call.
- "Never reopened or rebuilt" means no code builds an AI Hub vector store over a table that does not exist (AI Hub's `Build()` would re-create it in the data database); a later add from a session whose End failed and stayed resumable creates a fresh table through `OcuTalon.Docs`' DDL, which is the AD-21 path.
- Owner locks `^OcuTalon.Docs(<owner>)`: shared for `EnsureTable`, `IndexBatch` writes and `Knowledge`, exclusive for `DropSession`, 5 s, as `MemoryOps`' lock; a timeout gives no tool (a warning) or a drop error (End answers `failed`; the visitor can sign out again).
- `DropSession` publishes no `document` event: the session is ending.
- ChatAgent's `ToolInventory` reports the agent's own manager, so `documents` leaves it; a local Chat turn still offers it (the 16-name pins stay). The security overview's `documents` row keeps the toolset `OcuTalon.Docs.Store` (it builds the knowledge base), so `docs/security-overview.md` is not regenerated.
- `TurnToolsClass` is an item setting of `Decide` in `Production.cls`, as `HostSinkClass` and `ReplyFilterClass` are (wiring, not an admin value; AD-5).
- Memories need no product change beyond `Memory.DropSession`: every read and write already filters on the turn's SessionRef; the story adds the two-session tests.
- DW-892 needs no `Demo/Features.cls` change (Lane B): once the demo route answers 200, its listing is true.
- The start-of-run sweep assumes evaluation runs do not overlap (one release gate or one test class at a time), and says so in `Start`'s doc.
- The reset AC's committed pin is the fresh-stack check of `live:session-data` (the state the golden copy is captured from); the restore itself runs once as evidence (34.3's recipe), because the host's reset is outside the repository and a committed restore would cost about 150 s more in CI.
- `live:session-data` joins `shards-2`: 1,520 s clean on ci run 42384900368 (before 19.4's classes; 1,803 s on the loaded run 42425571857), plus 19.4's and this story's shard classes (about 100 + 60 s, inference) and the unit (about 300 s in CI, inference from `live:documents`' 315 s with a restart), about 1,980 s (33 min). `image` (1,786 s + 300) and `shards-3` (about 2,040 s with `live:documents`) have less room, `shards-5` is about 1,950 s on the feature with `live:sign-in-3`. The lead reports the first measured time; over 35 minutes stops before any rerun. New shard classes: `Test.Docs.{TurnTools,Sessions,SessionTurns,SessionLive}` and `Test.Memory.Drop` in `shard:lane-a@rest` (`shards-2`); `Test.Bridge.TurnTools` in `shard:lane-a@Bridge,Agent` (`shards-5`, a few seconds).
- Developer-facing error and log texts (the skills refusal, the drop lock timeout, the KB warning) follow `MemoryOps`' style and are not user-facing.
- Implement-stage decisions (2026-11-08): (a) Task 0 ran on the lane-C warm stack (tag e19s5iw) with scratch classes, not on a fresh `e19s5i0` stack (the platform facts do not depend on it); evidence in `evidence/19-5-task0-turn-tools.md`, whose M4 reading was redone with a corrected global scan. (b) The owner lock key is the SessionRef for a session (`Store.OwnerOf(table)`), `instance` and `eval`; `LockOwner`/`UnlockOwner` are public on `Docs.Store`. (c) `AddEval` keeps its online-demo `not_built` answer (only `OnAdd` lost it), and `Ops.#OWNER`, `#EVALOWNER` and `#MESSAGENOTBUILT` are gone (`Docs.Store` owns the owner constants). (d) `Store.Remove` of a table that does not exist is OK (SQLCODE -30), so a gone table is never an error and never re-created. (e) `Eval.In.Start` sweeps first, before it creates `EvalIn` (a disabled `EvalIn` still sweeps). (f) `POST /v1/session/end` answers 204, not 200; the live unit pins 204. (g) `DropSession` marks the owner as being dropped (`^IRIS.Temp.OcuTalonDocsDrop`) before it asks for the exclusive lock and `Store.Write` stops between passages while it is set, because a batch of eight passages takes about 4 s on the Embedder worker and the 5 s lock then timed out in `TestDropWhileIndexing` on a loaded stack; a batch that stops this way leaves the document `indexing` until the drop (or a retry of it) deletes the row. (h) The step tests of `Test.Bridge.Runner` run on `ZzStepsAdapter` (a `Govern` override) because a local `turn` now gets `documents` on any agent; `Test.Bridge.Conversation.TestFirstStepCountsHistory` sets `TurnToolsClass` to the base class for its run (`NoTurnTools`), `Test.Install.SecurityOverview` checks the `documents` row against a local turn's offered tools, and `Test.Agent.Runners` no longer lists `documents` in the inventory. (i) The harness self-test's record count pins (`eleven` to `thirteen` rows, 13 to 15 table lines) changed with H9, as its rows are hard-coded. (j) The `ci/units.sh` rebalance moved the `Eval` area into the `shards` piece and put `live:session-data` in `shards-2`. (k) `docker/tests/test-bridge-guide.sh` pins the three new guide lines in its own rule `turntools`, not in `livetext`.

**Spine unions (marker `[AMENDED 2026-11-08, Story 19.5, ...]`):** AD-21 "Attaching per turn" (the composition as built: once per request, the agent's own manager when there is no turn tool, toolsets, `Attach` specs, `AddToManager` tools, gate and audit, the manager put back; Task 0's measurements replace the inference), "Removal" (what the two drops do, the locks), "Tables" (`OcuTalonKB.Eval`, `Docs.Store.TableFor`), "Names" (eval documents in `OcuTalonKB.Eval`, the start-of-run sweep), "Indexing and search" (the `%OnInit` attach replaced by `OcuTalon.Docs.TurnTools`); AD-31 `TurnToolsClass` (the element contract, the Decide property's default, a missing class fails the request); AD-6 (the gate and the audit are also set on every composed manager); the Structural Seed Tables line (the session-end deletion runs in `SessionOps`' job through the two drops). Lint must show no new finding.

**PUBLIC TEXT needed** (the plan does not depend on the wording; the implementer uses the proposal until the lead rules):
- `docs/bridge-guide.md` settings table, after `ClassificationClass`: "| `TurnToolsClass` | `OcuTalon.Bridge.Ext.TurnTools` | The class that gives one request tools of its own, such as a knowledge base of the person's documents. See "The extension classes". |"
- `docs/bridge-guide.md:153`: the "read each time" list becomes "... `ToolClassification`, `ClassificationClass` and `TurnToolsClass` of `Decide`, ..." (pinned at `docker/tests/test-bridge-guide.sh:590`).
- `docs/bridge-guide.md:309`: "The bridge reaches your code only through four classes, ..." and a fourth bullet: "- `OcuTalon.Bridge.Ext.TurnTools` (`TurnToolsClass`): `Tools(ownerRef, kind, tools)` returns the tools to add to one request, each an object with `AddToManager(manager)`, such as an AI Hub knowledge base. When it returns any, the runner gives that request a new tool manager with the agent's own tools, the tools attached when the agent was built, these tools, the gate and the step audit, and puts the agent's own manager back afterwards; an agent that declares skills cannot take tools of its own this way. It returns none by default."
- The harness record notes (only with the ruling): `MEMORY_UPGRADE_NOTE` "the upgrade part joins from the release after the first one that saves memories" and `DOCUMENT_UPGRADE_NOTE` "the upgrade part joins from the release after the first one that indexes documents".

**Ledger inbox:**
- DW-783: addressed by the DW-783 task (the rehearsal dry run on a real lane-C stack, evidence; no frozen edit needed; see the release-tool block).
- DW-892: addressed (matrix row "DW-892"; `live:session-data` proves the demo route reaches `ready`).
- DW-893: addressed by the per-turn composition (matrix row "DW-893", `Test.Docs.SessionTurns`).
- DW-900: addressed by `Eval.In.Start`'s sweep (matrix row "DW-900", `Test.Eval.Documents`).
- DW-901: addressed by `OcuTalonKB.Eval` and the per-turn attach by owner (matrix row "DW-901", `Test.Docs.Turns`).

**Lane B FYI (no edit needed, for the orchestrator):** stale comments at `Test/Core/SessionOpsDocuments.cls:11-12` (the stubs), `Demo/Features.cls:8` and `Web/Documents.cls`' `OWNER` parameter doc (19.4's DW note).

**Frozen release tools: the exact hunks (for the Contest Planner's ruling; nothing here is applied before it).**

H1 `release/upgrade-harness.sh` header, after line 38 (before `# Merge retries`), add:
```
# The memory and document families (Story 19.5; FR-60, NFR-16, NFR-17, REL-6): the records project saves a memory through a chat turn and
# the CI mock (scenario memory-save) and adds the Results runbook through POST /v1/documents. A record passes when, after the upgrade or
# the restart, OcuTalon.Memory.Search for its session still returns the memory, and the document is still listed ready and found by a
# search of its knowledge base (OcuTalon.Test.Docs.Live Found). The seed makes them on the previous build only when its MemoryOps or
# DocumentOps is built (no STUB); otherwise the upgrade phase makes them on the candidate, the restart phase checks them, and the row
# carries the note that its upgrade part joins later.
```
H2 constants, lines 63-69: `HARNESS_ON="conversation reminder approval watch settings pairing memory document"`; `HARNESS_ROWS="previous-build upgrade conversation reminder approval watch settings restart storage private-globals pairing memory document"`; after `PAIRING_UPGRADE_NOTE` add:
```
# The memory and document rows' notes while the previous build cannot save a memory or index a document.
MEMORY_UPGRADE_NOTE="the upgrade part joins from the release after the first one that saves memories"
DOCUMENT_UPGRADE_NOTE="the upgrade part joins from the release after the first one that indexes documents"
```
H3 seed texts, after line 80 (`MOCK_LOG=...`), add:
```
REPLY_MEMORY="The CI mock will remember that."
TEXT_MEMORY="the Results partner's contact is Lee"
DOC_FILE=eval/documents-runbook-rotate/results-runbook.md
DOC_NAME="Zz upgrade runbook.md"
DOC_QUERY="how do I rotate the Results certificate?"
```
H4 after `api_post` (line 603), add:
```
api_get() { # api_get <path>: prints the status; the body is in $tmp/get.body
  curl -s --max-time 30 -b "$jar" -c "$jar" -o "$tmp/get.body" -w '%{http_code}' "$base/ocutalon/api/v1/$1"
}
```
H5 after line 957 (the end of `check_pairing_restart`, before `seed_watch`), add the family block:
```
# The memory and document families (Story 19.5). See the header.

# built_class <class>: 1 when the running build has the class compiled and without STUB, 0 when not, "" when it cannot say.
built_class() {
  printf '%s\n' \
    "Try { Write !,\"CHK|built|\",(##class(%Dictionary.CompiledClass).%ExistsId(\"$1\")&&'+\$Parameter(\"$1\",\"STUB\")) } Catch e { Write !,\"CHK|built|\" }" \
    'Halt' | session_value OCUTALON built
}

# memory_make <label> <clientId>: saves the memory through a chat turn and sets mem_ref and mem_session from the newest row with its text.
memory_make() {
  local line
  mem_ref="" mem_session=""
  run_turn "$2" memory-save "Remember that $TEXT_MEMORY." "$REPLY_MEMORY" "$1" || return 1
  line=$(printf '%s\n' \
    "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT TOP 1 Ref,SessionRef FROM OcuTalon_Data.Memory WHERE Text = ? ORDER BY ID DESC\",\"$TEXT_MEMORY\")" \
    'Write !,"CHK|mem|",$Select(rs.%Next():rs.%GetData(1)_"|"_rs.%GetData(2),1:"")' \
    'Halt' | session_value OCUTALON mem)
  mem_ref=${line%%|*} mem_session=${line#*|}
  if [ -z "$mem_ref" ]; then fail "$1: the turn saved no memory with the scenario's text"; return 1; fi
  pass "$1: the memory $mem_ref is saved for session $mem_session"
}

# memory_found <ref> <session>: 1 when OcuTalon.Memory.Search for the session returns the memory, else 0.
memory_found() {
  printf '%s\n' \
    "Set f=0,sc=##class(OcuTalon.Memory).Search(\"$2\",\"Results partner contact\",5,.rows) If \$System.Status.IsOK(sc) { For i=0:1:rows.%Size()-1 { If rows.%Get(i).memoryRef=\"$1\" Set f=1 } }" \
    'Write !,"CHK|found|",f' \
    'Halt' | session_value OCUTALON found
}

memory_check() { # memory_check <label> <ref> <session>
  if [ "$(memory_found "$2" "$3")" = 1 ]; then pass "$1: the memory is still there and found by a search of its session"; else fail "$1: a search of session $3 does not find the memory $2"; fi
}

# document_ready <ref>: the document is listed ready in GET /v1/documents.
document_ready() { [ "$(api_get documents)" = 200 ] && [ "$(jq -r --arg r "$1" '[.documents[]? | select(.ref == $r) | .state][0] // ""' "$tmp/get.body")" = ready ]; }

# document_make <label>: adds the runbook through POST /v1/documents, waits up to 120 s for it to be ready and sets doc_ref.
document_make() {
  local code
  doc_ref=""
  { printf '{"name":"%s","content":"' "$DOC_NAME"; base64 < "$harness_root/$DOC_FILE" | tr -d '\n'; printf '"}'; } > "$tmp/doc.json"
  code=$(api_post documents "@$tmp/doc.json")
  if [ "$code" != 200 ]; then fail "$1: POST /v1/documents answered $code"; return 1; fi
  doc_ref=$(jq -r '.ref // ""' "$tmp/post.body")
  if [ -z "$doc_ref" ] || ! wait_until 120 document_ready "$doc_ref"; then fail "$1: the document '$doc_ref' was not ready within 120 s"; return 1; fi
  pass "$1: the document $doc_ref is added and ready"
}

# document_found <ref>: "" when a search of the document's knowledge base returns one of its passages, else the reason.
document_found() {
  printf '%s\n' \
    "Set r=##class(OcuTalon.Test.Docs.Live).Found(\"$1\",\"$DOC_QUERY\")" \
    'Write !,"CHK|found|",$Select(r="":"ok",1:r)' \
    'Halt' | session_value OCUTALON found | sed 's/^ok$//'
}

document_check() { # document_check <label> <ref>
  local why
  if ! document_ready "$2"; then fail "$1: the document $2 is not listed ready"; return; fi
  pass "$1: the document is still listed ready"
  why=$(document_found "$2")
  if [ -z "$why" ]; then pass "$1: a search of its knowledge base finds the document"; else fail "$1: a search does not find the document ($why)"; fi
}

seed_memory() {
  row memory
  local built
  built=$(built_class OcuTalon.Memory.Ops)
  env_set "$state/seed.env" prev_memory "${built:-0}"
  if [ "$built" != 1 ]; then echo "INFO memory: the previous build's MemoryOps is not built, so no memory is saved in the seed"; return; fi
  if memory_make "memory: the previous build" "up-$key-7"; then
    env_set "$state/seed.env" mem_ref "$mem_ref"
    env_set "$state/seed.env" mem_session "$mem_session"
  fi
}

seed_document() {
  row document
  local built
  built=$(built_class OcuTalon.Docs.Ops)
  env_set "$state/seed.env" prev_document "${built:-0}"
  if [ "$built" != 1 ]; then echo "INFO document: the previous build's DocumentOps is not built, so no document is added in the seed"; return; fi
  if document_make "document: the previous build"; then env_set "$state/seed.env" doc_ref "$doc_ref"; fi
}

check_memory_upgrade() {
  row memory
  if [ "$(env_get "$state/seed.env" prev_memory)" != 1 ]; then note_row "$MEMORY_UPGRADE_NOTE"; return; fi
  if [ -z "$(env_get "$state/seed.env" mem_ref)" ]; then fail "memory: the previous build saves memories, but the seed saved none"; return; fi
  memory_check "memory after the upgrade" "$(env_get "$state/seed.env" mem_ref)" "$(env_get "$state/seed.env" mem_session)"
}

check_document_upgrade() {
  row document
  if [ "$(env_get "$state/seed.env" prev_document)" != 1 ]; then note_row "$DOCUMENT_UPGRADE_NOTE"; return; fi
  if [ -z "$(env_get "$state/seed.env" doc_ref)" ]; then fail "document: the previous build indexes documents, but the seed added none"; return; fi
  document_check "document after the upgrade" "$(env_get "$state/seed.env" doc_ref)"
}

# memory_candidate, document_candidate: when the seed could not make the record, make it on the candidate for the restart.
memory_candidate() {
  row memory
  if [ "$(env_get "$state/seed.env" prev_memory)" = 1 ]; then return; fi
  if memory_make "memory: the candidate" "up-$key-8"; then
    env_set "$state/upgrade.env" mem_ref "$mem_ref"
    env_set "$state/upgrade.env" mem_session "$mem_session"
  fi
}

document_candidate() {
  row document
  if [ "$(env_get "$state/seed.env" prev_document)" = 1 ]; then return; fi
  if document_make "document: the candidate"; then env_set "$state/upgrade.env" doc_ref "$doc_ref"; fi
}

check_memory_restart() {
  row memory
  local ref session
  ref=$(env_get "$state/upgrade.env" mem_ref) session=$(env_get "$state/upgrade.env" mem_session)
  if [ -z "$ref" ]; then ref=$(env_get "$state/seed.env" mem_ref) session=$(env_get "$state/seed.env" mem_session); fi
  if [ -z "$ref" ]; then fail "memory: no memory was saved to check after the restart"; return; fi
  memory_check "memory after the restart" "$ref" "$session"
}

check_document_restart() {
  row document
  local ref
  ref=$(env_get "$state/upgrade.env" doc_ref)
  if [ -z "$ref" ]; then ref=$(env_get "$state/seed.env" doc_ref); fi
  if [ -z "$ref" ]; then fail "document: no document was added to check after the restart"; return; fi
  document_check "document after the restart" "$ref"
}
```
H6 `phase_seed`, after line 1211 (`if family_on pairing; then seed_pairing; fi`), add:
```
  if family_on memory; then seed_memory; fi
  if family_on document; then seed_document; fi
```
H7 `phase_upgrade`, after line 1534 (the closing `fi` of the pairing block), add:
```
  if family_on memory; then
    check_memory_upgrade
    memory_candidate
  fi
  if family_on document; then
    check_document_upgrade
    document_candidate
  fi
```
H8 `phase_restart`, after line 1621 (`if family_on pairing; then check_pairing_restart; fi`), add:
```
  if family_on memory; then check_memory_restart; fi
  if family_on document; then check_document_restart; fi
```
H9 `docker/tests/test-upgrade-harness.sh` (the harness's self-test, which hard-codes the rows): line 442 the loop list appends `memory document`; line 486 the expected order ends `...,private globals,pairing,memory,document,`; line 505 `11` becomes `13`; and a `t_memory_document` rule over stubs of `built_class`, `run_turn`, `session_value` and `api_post`/`api_get` (the pattern of `pairing_stubs`/`t_pairing`, 779-903): built 0 writes no seed and the upgrade row carries the note; built 1 seeds and checks; a search that misses is a fail line; the candidate record is checked after the restart.

`release/rehearse.sh` (DW-783): no hunk is needed; the dry run task is the proof. Optional, only if the Planner wants a sharper failure: at line 1159, after `echo MEMOFF-RECONNECTED`, add `; docker port "$cid" 52773 > /dev/null 2>&1 && echo MEMOFF-PORT || echo MEMOFF-PORT-MISSING`, and in `step_memoryoffline` (1157-1188) fail the step on `MEMOFF-PORT-MISSING`, with the stub line in `docker/tests/test-rehearsal.sh:268`. Recommended: no hunk.

Recommended non-frozen alternative for the harness AC (proves less): the same memory and document seed and checks in `docker/tests/test-install-upgrade.sh` (`live:install-upgrade`, CI on every push), through ObjectScript, beside `orders_probe` (80-108). It proves the records survive an in-place re-run of every install step on this build, not an upgrade from the previous release, and it is not the harness the AC names, so it is a companion, not a replacement.

## Verification

Lane-C variables, written `LC` below: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=19 stage=implement'`. Every call runs in the foreground with `timeout: 600000`, sized to about 150 s; a call moved to the background is polled in bounded foreground loops. IRIS MCP calls name `server` `ocutalon-slot-c` and namespace `OCUTALON` (compile checks only; `iris_server_info` first); one `iris_execute_tests` per message. On the warm stack, after `Docs/Ops.cls` or `Bridge/Adapter/Agent.cls` reloads, restart `DocumentOps` and every agent runner item (`Ens.Director.EnableConfigItem` off and on) before the next class run, or the run is a false green.

**Commands:**
- `LC OCUTALON_RUN_TAG=e19s5iw ci/warm.sh up` (once) -- `WARM up`; `ci/warm.sh down` with the same tag at the stage's end, also after a failure.
- `LC OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s5iw ci/iris.sh class OcuTalon.Test.<Class>` (loop), one class per call, for `Bridge.TurnTools`, `Bridge.Ext`, `Bridge.Runner`, `Bridge.Example`, `Bridge.ExampleTools`, `Bridge.CodeRules`, `Bridge.SessionConfig`, `Bridge.Gate`, `Bridge.Decide`, `Bridge.Conversation`, `Docs.TurnTools`, `Docs.Sessions`, `Docs.SessionTurns`, `Docs.SessionLive`, `Docs.Store`, `Docs.Ops`, `Docs.Chat`, `Docs.Live`, `Docs.Turns`, `Memory.Drop`, `Memory.Search`, `Memory.Ops`, `Agent.Runners`, `Install.SecurityOverview`, `Install.Production`, `Install.PrivateData`, `Contract.Step3`, `Contract.Ac`, `Eval.Documents`, `Eval.In`, `Tools.Persona`, `Tools.Reminders`, `Watch.Turns`, and Lane B's `Core.SessionOpsDocuments` (read-only, must stay green) -- each `CLASS ... passed`.
- `LC OCUTALON_RUN_TAG=e19s5i ci/iris.sh live session-data` (once per change set) -- `SESSION-DATA ... ok`, exit 0.
- `LC OCUTALON_RUN_TAG=e19s5i ci/iris.sh live documents` (once) -- 19.4's unit still passes with `Test.Docs.Live` changed.
- `LC OCUTALON_RUN_TAG=e19s5i bash release/standalone-bridge.sh` (once; run, never edited) -- the bridge alone with `BridgeExample` passes.
- `LC OCUTALON_RUN_TAG=e19s5i ci/iris.sh shard lane-a@Bridge,Agent --part k/n` and `shard lane-a@rest --part k/n` (once each part, forward then `--reverse`; parts sized to about 150 s) -- every class passed (Rule 19 fresh check).
- `bash docker/tests/test-class-rules.sh`, `test-storage.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-boundaries.sh`, `test-bridge-guide.sh`, `test-mock.sh` (once each, one per call) -- PASS.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once, after the spine edit) -- no new finding.
- Teardown: `LC OCUTALON_RUN_TAG=<tag> ci/iris.sh teardown` for `e19s5i0`, `e19s5i`, `e19s5ir`, `e19s5ig` (and `e19s5ih` after the ruling); `git status --short` shows only the story's files.

**Planned mutations (one per AC; record `mutation: <change> -> <red test>` here when run):**
- AC1: `Store.EnsureTable` without `DEFAULTGLOBAL` on the per-session line -> `Test.Docs.Sessions` (private-database assertion) and `kb-ddl`.
- AC2: `SessionConfigFor` skips the composition (the agent's own manager always) -> `Test.Docs.SessionTurns` (demo turn offers no `documents`) and `Test.Bridge.TurnTools` (fixture turn tool missing); the attached spec not re-added -> the fixture toolset missing.
- AC3: `Ext.TurnTools.Tools` returns one bogus tool by default -> `release/standalone-bridge.sh` and `Test.Bridge.Example`.
- AC4: `TurnTools` maps every demo session to `OcuTalonKB.Docs` -> `Test.Docs.SessionTurns` and `live:session-data` (the other session's source appears).
- AC5: `TurnTools` calls `EnsureTable` before `Knowledge` -> `Test.Docs.TurnTools` (a table is created for a session without one).
- AC6: `Docs.DropSession` deletes rows but drops no table -> `Test.Docs.Sessions`, `Test.Contract.Step3`, `live:session-data`; `Memory.DropSession` without the SessionRef filter -> `Test.Memory.Drop` (the other session's memory is gone).
- AC7: `Start` without the sweep -> `Test.Eval.Documents`; `AddEval` back on `OcuTalonKB.Docs` -> `Test.Docs.Turns` (DW-901).

**Mutations run (implement stage, 2026-11-08; each applied to the file, observed red, reverted from a backup in the stage scratchpad, tree byte-identical afterwards):**
- AC1: mutation: `Store.EnsureTable` without `DEFAULTGLOBAL` on the table's `CREATE TABLE` line -> `test-class-rules.sh` rule kb-ddl red, and `Test.Docs.Sessions` TestFirstAdd red ("their DEFAULTGLOBAL is under ^OcuTalonP.").
- AC2: mutation: `SessionConfigFor` returns after `Compose` without the composition (`Quit $$$OK` for `Quit ..ComposeTurnTools()`) -> `Test.Bridge.TurnTools` red (TestTurnTools, TestOtherKinds, TestSkills, TestMissingClass) and `Test.Docs.SessionTurns` red (TestTwoVisitors, TestOfferedByOwner, TestDroppedSession: documents not offered); mutation: the attached specs not re-added (`While $ListNext("", position, spec)` for `..Attached`) -> `Test.Bridge.TurnTools` red (TestTurnTools: the fixture toolset's tool is missing from the composed manager's offer).
- AC3: mutation: `Ext.TurnTools.Tools` also inserts one bogus tool object into the list -> `Test.Bridge.TurnTools` red (TestBaseGivesNone and the request tests) and `release/standalone-bridge.sh` red (the guide's send block gets no decision); `Test.Bridge.Example` stays green (it skips off a throwaway), so the standalone job is the pin.
- AC4: mutation: `Docs.TurnTools` names `OcuTalonKB.Docs` (`Store.#TABLE`) for every owner instead of `TableFor(owner)` -> `Test.Docs.TurnTools` red (TestKinds, TestNoTable, TestOwnSourceOnly) and `Test.Docs.SessionTurns` red (the demo visitors' turns search the install's table). The live unit was not rerun for this mutation.
- AC5: mutation: `Docs.TurnTools` calls `Store.EnsureTable(table)` before `Store.Knowledge` -> `Test.Docs.TurnTools` red (TestNoTable: a table is made for a session that has none).
- AC6: mutation: `Docs.DropSession` deletes the rows and drops no table -> `Test.Docs.Sessions` red (TestDropSession, TestDropLockHeld; `Test.Contract.Step3` stays green, because its fixture sessions have no Session row and so no table; the live unit's Facts check is the pin for the tables); mutation: `Memory.DropSession` deletes `WHERE SessionRef <> ?` (not the session's own) -> `Test.Memory.Drop` red (TestDropsOnlyTheSession: A's memories stay, B's go).
- AC7: mutation: `Eval.In.Start` without `Do ..SweepDocuments()` -> `Test.Eval.Documents` red (TestSweep: both leftover documents stay); mutation: `AddEval` writes to `OcuTalonKB.Docs` (`Store.#TABLE`) -> `Test.Docs.Turns` red (TestEvalDocuments and TestEvalNotSearched); mutation (U-305 pin): `Docs.TurnTools` gives every owner the table `OcuTalonKB.Eval` -> `Test.Docs.Turns` TestEvalNotSearched red (the person's turn reads no passage of the person's own document).

**Mutations run (review pass, 2026-11-08; each applied, observed red, reverted from a backup in the stage scratchpad, files byte-identical afterwards):**
- Once per request (Rule 19, the composition guard): mutation: `ComposeTurnTools` without `If ..TurnComposed Quit ..TurnStatus` -> `Test.Bridge.TurnTools` red (TestComposesOnce: the class was asked twice and the agent's own manager is not put back).
- Rebuild (the attached specs): mutation: `BuildAgent` without `Set ..Attached = ""` -> `Test.Bridge.TurnTools` red (TestComposesOnce: the attached spec is recorded twice).
- Drain mark (AC6, "drop while indexing"): mutation: `Store.Write` without the `Draining(owner)` stop -> `Test.Docs.Store` red (TestDrain: Write writes passages while the owner is marked as being dropped).
- Upgrade harness (the harness AC): mutation: `memory_check` passes without the search (`if true` for the `memory_found` comparison) -> `docker/tests/test-upgrade-harness.sh` red (rule `memory-document`: "a search that misses the memory is a fail line").
- AC4, live half: mutation: `Docs.TurnTools` names `OcuTalonKB.Docs` for every owner -> `live:session-data` red (4 checks: neither visitor's documents turn reaches the model with its own source, and SessionLive fails after K's sign-out).
- Two sessions, memory half: mutation: `Memory` NEARESTSQL and KEYWORDSQL with `SessionRef <>` instead of `=` -> `live:session-data` red (K's memory turn holds C's memoryRef and C's holds K's).
- Fresh install before any visitor (reset): mutation: a fixture table `OcuTalonKB.S9001` left in the golden copy -> the check `Facts("") = 0|0|0|0|0` of `live:session-data` reads `2|2|5|0|0` and fails (`evidence/19-5-session-reset.md`, measured by the implement stage).

**Mutations run (QA, 2026-11-08; each applied to the file, observed red on the warm stack, reverted from a backup in the stage scratchpad, tree byte-identical afterwards):**
- AC1/I-O row "indexing error" (a failed batch of a session's document takes its rows out of the session's own table): mutation: `Docs.Ops.Fail` calls `Store.Remove(ref)` (the install's table) instead of `Store.Remove(ref, row.KnowledgeBase)` -> `Test.Docs.Sessions` TestIndexingError red ("the rows its first batch wrote are deleted from the session's table").
- I-O row DW-892 (the demo's documents feature is listed): mutation: `Parameter STUB = 1` on `Docs.Ops` -> `Test.Docs.Sessions` TestDocumentsFeature red (documents not listed; "DocumentOps is no stub").
- AC7 / I-O row DW-900 ("a failed removal: one warning, the run goes on"): mutation: `Eval.In.SweepDocuments` without the `$$$LOGWARNING` for a removal that fails -> `Test.Eval.Documents` TestSweepFails red ("the failed removal is one warning that names the document").

**Mutations run (code review, 2026-11-08; each applied, observed red, reverted from a backup in the stage scratchpad, files byte-identical afterwards; IRIS classes on the lane-C warm stack e19s5cw):**
- DW-940 (the harness AC, an empty IRIS answer): mutation: `release/upgrade-harness.sh` put back as at HEAD (`document_found` ending `| sed 's/^ok$//'`, the seeds without the empty-answer check) -> `docker/tests/test-upgrade-harness.sh` red (rule `memory-document`: "an empty answer of built_class fails both seeds and is never 'not built'" got `00|00`, and "the search's answer '': an empty one is a fail line" got `20`; the real answer `ok` stays green).
- Harness AC, document half: mutation: `document_check` passes without the search (`if true` for `if [ -z "$why" ]`) -> `docker/tests/test-upgrade-harness.sh` red (rule `memory-document`: "a search that misses the document is a fail line" and the empty-answer pin).
- Hermeticity (Rule 19): `Test.Eval.Documents` as at HEAD, on a stack where `OcuTalonKB.Eval` was dropped -> red (TestEmbedFailure "and leaves no row and no passage"); the patched class passed on the same new stack before any run had made the table.
- AC2, the error path ("no knowledge base stays bound after the request"): mutation: `Answer` puts the agent's own manager back only on success (`If $$$ISOK(sc) Do ..EndTurnTools()`) -> `Test.Bridge.TurnTools` red (TestFailureRestores: "the agent's own manager is put back on the error path" and "which offers no tool of the failed request").
- Matrix row "Drop while indexing" (AC6), the drop mark: mutation: `IndexBatch` without its `If ##class(OcuTalon.Docs.Store).Draining(owner)` exit -> `Test.Docs.Sessions` red (TestBatchYieldsToDrop: "it stops as gone, writes no passage and leaves the row to the drop").
- Matrix row "Drop while indexing" (AC6), the owner lock: mutation: `IndexBatch` without `LockOwner` -> `Test.Docs.Sessions` red (TestBatchYieldsToDrop: "a batch under a drop's lock returns an error status" and "and writes no passage").

**Tests added or changed (QA):**
- `src/ocutalon/cls/OcuTalon/Test/Docs/Sessions.cls` (QA): new `TestIndexingError` (a failed batch of a demo session's document: failed, session table rows gone, event on the session's stream only) and `TestDocumentsFeature` (DW-892); the class doc lists both.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Documents.cls` (QA): new `TestSweepFails` (a leftover whose removal fails is one warning and the sweep goes on), the `BAD` parameter and its row's clean-up.

**Shared surfaces:** `Ext.Accessor.BASES` and `Decide`'s `SETTINGS` Extensions list (`Test.Bridge.Ext`, `Test.Install.Production`), ChatAgent's `ToolInventory` (`Test.Agent.Runners`, `Test.Install.SecurityOverview`), the `OcuTalonKB` table set (new `OcuTalonKB.Eval` and per-session tables; `Test.Install.PrivateData`, `Test.Docs.Store` `Count`), `Docs.Store`'s methods (`Test.Docs.{Store,Chat,Live}`), the stubs' contract (`Test.Contract.Step3`, `Test.Contract.Ac`), the `shards-2` unit list (`test-ci-config.sh`), the bridge guide's pinned lines (`test-bridge-guide.sh`); the local offered-tool lists (16 names) are unchanged. Every test added or changed passes on a fresh environment, in either order; the two-concurrent-sessions AC and every destructive check run on throwaways only.

## Auto Run Result

Status: done
Blocking condition: none

release_tool_hunks: `release/upgrade-harness.sh` H1 lines 39-44 (header comment after the pairing paragraph); H2 lines 70, 73 and 76-78 (`HARNESS_ON`, `HARNESS_ROWS`, `MEMORY_UPGRADE_NOTE`, `DOCUMENT_UPGRADE_NOTE`); H3 lines 90-94 (the seed texts after `MOCK_LOG`); H4 lines 618-620 (`api_get` after `api_post`); H5 lines 976-1110 (the family block after `check_pairing_restart`); H6 lines 1364-1365 (`phase_seed`); H7 lines 1689-1696 (`phase_upgrade`); H8 lines 1784-1785 (`phase_restart`). `docker/tests/test-upgrade-harness.sh` H9: lines 23-26 (the loop list and the expected order), 446, 489-490, 509 and 770 (the consequent pins: table lines 15, "thirteen records", the not-run count 13), 909-1069 (`t_memory_document`, `b_memory_document`, the stubs) and 1334 (`rule memory-document`). Applied exactly as written; no other release tool changed (`git diff --stat` shows only these two files under `release/` and `docker/tests/`). DW-940 fix: `release/upgrade-harness.sh` lines 1028-1029 and 1032-1033 (`document_found`: the answer is kept in `why`, and an empty one is the reason "the IRIS call gave no answer"), 1048 (`seed_memory`) and 1061 (`seed_document`: an empty `built_class` answer fails the family); `docker/tests/test-upgrade-harness.sh` lines 981-985 (an empty `built_class` answer fails both seeds) and 1015-1021 (the search answers "" and `ok`: a fail line, two passes).

Footprint extensions (files outside the story's own paths_hint): `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` (the `TurnToolsClass` setting, named by the spec); `src/ocutalon/cls/OcuTalon/{Docs.cls,Memory.cls}` (the two `DropSession` bodies, the stubs of Story 34.1), `Agent/Chat.cls` (the `%OnInit` attach removed), `Eval/In.cls` (the sweep); `Test/Agent/Runners.cls` (outside Epic 11's lines 149-228: ChatAgent's inventory no longer lists `documents`), `Test/Contract/{Ac,Step3}.cls`, `Test/Eval/Documents.cls`; `docker/tests/{test-bridge-guide.sh,test-session-data.sh,test-upgrade-harness.sh}`, `docs/bridge-guide.md` (PUBLIC TEXT approved), `release/upgrade-harness.sh` (the ruled hunks only); the spine `ARCHITECTURE-SPINE.md` (plain unions marked `[AMENDED 2026-11-08, Story 19.5, ...]`); `src/ocutalon/cls/OcuTalon/Production.cls` (Lane A's region) and `ci/mock/scenarios/A/turn-tools-probe.json` and `ci/units.sh` (Lane A's entries). Contended files touched (stage prompt list): `ci/units.sh` (two unit-list entries, plain union) and `Test/Agent/Runners.cls` (lines outside 149-228). No Lane B file was edited.

new_units: the live unit `live:session-data` (`docker/tests/test-session-data.sh`, in `shards-2`); the test classes `Test.Docs.{TurnTools,Sessions,SessionTurns,SessionLive}` and `Test.Memory.Drop` (area pieces of `shard:lane-a@rest`, group `shards-2`) and `Test.Bridge.TurnTools` (piece `Bridge,Agent`, group `shards-5`); the fixtures `Test.Bridge.Zz{TurnAdapter,TurnAgent,TurnProbeTools,TurnRunner,TurnSkillAgent,TurnTool,TurnTools,TurnToolset,StepsAdapter,StepsRunner}`. No group added, renamed or given a longer deadline.

ci/units.sh moves with projections: `live:session-data` joins `shards-2` (about 300 s on CI, inference from `live:documents`; 155-177 s and 339 s on a lane-C throwaway); the `Eval` area (170 s) moves from `shard:lane-a@rest` to the piece of `shards` (`shard:lane-a@Checks,Install,Watch,Eval`). Projection from the larger measured figure of each group (ci runs 42445320545 and 42425689094): `shards-2` about 1,996 s (1,766 + 100 + 300 - 170), `shards` about 2,038 s (1,868 + 170), `shards-5` about 1,911 s (1,901 + 10), every other group unchanged; the 2,100 s line holds in each. The first measured CI run replaces these (inference until then).

Summary: every online-demo session has its own knowledge-base tables (`OcuTalonKB.S<id>` and `_Config`), made by DocumentOps on its first document and dropped by `Docs.DropSession` at sign-out; `Memory.DropSession` deletes the session's memories; evaluation documents live in `OcuTalonKB.Eval` with a start-of-run sweep (DW-900, DW-901); the fourth bridge extension `TurnToolsClass` (`Ext.TurnTools`, `Docs.TurnTools`) gives a turn its owner's knowledge base, composed in `SessionConfigFor` once per request and put back at the request's end (DW-893); the Chat agent no longer attaches a knowledge base in `%OnInit`. Task 0 measured the platform facts first (`evidence/19-5-task0-turn-tools.md`; no stop rule tripped). Decisions in-stage are under Design Notes (a)-(k).

Files changed: the bridge (`Ext/TurnTools`, `Ext/Accessor`, `Process/Decide`, `Adapter/Agent` with `Attach`, `Govern` and the per-request composition); `Docs.cls`, `Docs/Store`, `Docs/Ops`, `Docs/TurnTools`, `Memory.cls`, `Agent/Chat`, `Eval/In`, `Production`; new and changed tests under `Test/{Bridge,Docs,Memory,Contract,Eval,Install,Agent}`; the mock scenario `turn-tools-probe`; the live unit `test-session-data.sh`; the harness hunks; the bridge guide and its pin test; the spine unions; three evidence files (`19-5-task0-turn-tools.md`, `19-5-session-reset.md`, `19-5-dw783-rehearse-dry-run.md`).

Review (first pass, four layers, 51 findings): patched 19 rows (medium 1, low 18): `Attached` is cleared in `BuildAgent`; TestComposesOnce (the once-per-request guard and the rebuild); TestDrain (the drain mark); a request-sent assertion before each "not offered" assertion and in TestOtherKinds; a precondition in TestDropWhileIndexing; the vacuous `$Job` assertion removed; AssertTurnTool's claim and checked count; five missing `mutation:` lines written (six mutations run in this pass, the reset one recorded from the implement stage's evidence); four doc sentences corrected. Deferred: 1 item (the harness reads an empty answer as success), which needs a ruling on the frozen release tool (see the frontmatter). Rejected rows carry their reasons in the Review Triage Log (theoretical windows at sign-out, spec-bound decisions (f) and (g), by-design drops independent of `onlineDemo`, test hygiene that has controls, stub-only coverage that the DW-783 rehearsal replaces).

followup_review_recommended: false -- the first pass patched one medium (a test) and no high; the patches are tests, doc text and one line (`Attached` cleared), each verified red-then-green.

Verification performed (lane C; warm tag e19s5iw, fresh tag e19s5i; every call in the foreground): all 34 classes of the Commands list passed on the warm stack after the patches, `lane-a@Bridge,Agent` parts 1-6 and `lane-a@rest` parts 1-8 passed forward on the warm stack (the reverse order is the lead's fresh check; the implement pass ran the new and changed Docs and Memory classes in reverse and green); `live:session-data` passed once on a fresh throwaway after the last code patch (177 s), `live:documents` (187 s) and `release/standalone-bridge.sh` passed; `test-class-rules`, `test-storage`, `test-ci-config`, `test-ci-changes`, `test-boundaries`, `test-bridge-guide`, `test-mock` and `test-upgrade-harness` pass; the spine lint shows no new finding. Warm stack down and tag e19s5i torn down.

Residual risks: the 1.0.3 -> 1.0.4 upgrade path of the memory and document rows runs only through the self-test stubs (this branch's highest merged tag is v1.0.1, so the real run made both records on the candidate); the harness empty-answer gap above; CI group seconds are projections until the first CI run; the `Hold`/lock tests wait 5 s each; a document whose indexing batch the drain stops and whose drop then times out stays `indexing` until a later drop; Story 19.7's edits of `Docs/Ops.cls` and `Test/Docs/Ops.cls` need a textual merge with this story's (separate hunks).
