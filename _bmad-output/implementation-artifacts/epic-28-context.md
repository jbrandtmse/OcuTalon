# Epic 28 Context: Transform drafts, memory fading and OcuTalon as an MCP server

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 7's Lane A work, brought forward by the owner on 2026-11-16 ("Epics 27 and 28 START NOW"; the 2026-11-15 scope hold is lifted). OcuTalon keeps recall relevant as memory grows (unused memories rank lower, duplicates merge nightly with every source kept), lets a developer call its read-only tools from their own MCP client under their own IRIS sign-in without opening any new way to act, and drafts the transform change that would stop a data-format failure as a text proposal that is never compiled, saved or applied. Run order: 28.2, then 28.3 (in parallel with Epic 27), then 28.1, which waits for Epic 27.

## Stories

- Story 28.2: Fade unused memories and merge duplicates nightly (runs first)
- Story 28.3: Offer OcuTalon's read-only tools to MCP clients (second)
- Story 28.1: Draft a transform change as a proposal that is never applied (last; waits for Epic 27)

## Requirements & Constraints

- **Spine first, per story.** Each story updates the architecture spine in its own change with its share of step 7's additions: 28.2 the memory-fading setting (and its default), the merge record and the nightly consolidation task; 28.3 `OcuTalon.Mcp.Service` with its web application, resource, role and installer step; 28.1 the transform draft's storage and the `DraftTransform` verb. New items, tables and event types go into the ownership tables in the same change.
- **Fading:** a memory used in an answer gets its last-used time updated (a new property appended to `OcuTalon.Data.Memory`). Memories unused longer than the configured period rank below equally matching, more recently used ones, but still come back when nothing else matches. A forgotten memory never comes back.
- **Consolidation:** a nightly task enters through the production, calls no model, finds duplicates within one owner by vector similarity plus keyword match above a set threshold, keeps one memory per duplicate set carrying every source, keeps it marked untrusted if any merged memory was, and records each merge (kept memory, merged memories with texts and sources, time) where Visual Trace shows it. Never merges across sessions. A second run merges nothing new.
- **MCP server:** only read-only toolsets; refused for anonymous clients, wrong passwords and users without `OcuTalonMCPClient`; tools run as the calling IRIS user and return only that user's session's records; no offered tool can resend, fix or change settings (risky actions only via an approved approval request in OcuTalon's own channels); every call, read-only included, is audited with the calling IRIS user. Off on the online demo (`/mcp` is outside the proxy's allow-list).
- **Transform draft:** for an incident whose cause is a data format a transform rejects, read the transform's source through `OcuTalon.Watch.Reader`, ask the diagnosis agent through `Decide` with the sample failure, everything cut to size limits, and attach the draft (transform name, time) to the incident. It shows as text in chat, the incident summary and Visual Trace, never as runnable code. Tests must prove the class dictionary, routines and watched production are unchanged, and the tool inventory test still finds no tool that compiles or saves code.
- **Texts:** step 7 texts the UX doesn't give (draft presentation and never-applied note, a memory merge as the user sees it) are proposed to the author as `EXPERIENCE.md` Message Catalog additions, keys in `OcuTalon.Msg.Catalog.Watch`; nothing ships a text the author hasn't accepted.
- **Tests:** `OcuTalon.Test.Memory` (28.2); IRIS-runner tests with a minimal MCP client, plus the security overview listing the service's tools from its specification and the role (28.3); `OcuTalon.Test.Fix` with mock scenarios under `ci/mock/scenarios/A/` (28.1). Release checks are the Contest Planner's hands-on pass, not story gates.

## Technical Decisions

- **Every command is a production message.** State changes go through `OcuTalon.Core.Commands.Submit` and `CommandsIn` with an origin set by code; tools never write domain tables. `MemoryOps` (`OcuTalon.Memory.Ops`) is the memory table's only writer, so last-used updates and merges go through it (inference from the existing single-writer rule).
- **Storage is append-only (AD-5):** append properties to `OcuTalon.Data.Memory`, never rename or retype; commit the compiler-generated `Storage` block. New persistent classes use `DEFAULTGLOBAL` under `^OcuTalonP.`.
- **Memory ranking today:** reciprocal-rank fusion (k = 60) over the 20 nearest by cosine (HNSW `EmbeddingIdx`) and 20 best `%iFind` keyword hits, equal weights, top 5, ties to newer `SavedAt`. Fading adjusts this ordering. Embeddings come only from the `OcuTalon.Memory.Embedder` WorkMgr worker, never in the calling process.
- **Trust:** a recall is trusted only when every returned memory has `Origin` `tool`; otherwise the turn is tainted. A merged memory must not become trusted when any member wasn't. `Source` (`told`/`learned`) and pins also live on the row; forgetting deletes the row, vector, keyword entry and pin at once.
- **Scheduled tasks:** an area declares tasks in its install step's `Tasks()`; `OcuTalon.Install.Step.Tasks` creates each once (name prefixed `OcuTalon`, class extends `%SYS.Task.Definition`), and later runs keep Task Manager edits. A task enters the production by calling an adapterless business service via `Ens.Director.CreateBusinessService`/`ProcessInput`, and does nothing while the production is stopped. Purge tasks run daily at 03:00 instance time.
- **Product settings** live in `OcuTalon.Data.Setting` (Lane B's table); install-changeable values never go in the production class.
- **MCP server:** `OcuTalon.Mcp.Service` extends `%AI.MCP.Service`, `Parameter RESOURCE = "OcuTalon_MCPServer"`. Web application `/mcp/ocutalon`: password authentication only, namespace OCUTALON, no application roles. Role `OcuTalonMCPClient`: Use on the resource, read on the databases its tools read, SQL `SELECT` on exactly the tables they query. `iris-mcp-server`: no endpoint credentials (they would admit anonymous clients whatever `allow_anonymous` says), `allow_anonymous = false` (never copied from AI Hub's dev template), status tool off, its own login a role-less user whose password comes from the environment. Spike S10 passed this configuration on Oct 17.
- **Audit:** `OcuTalon.Bridge.Audit` is the only audit writer (type `MCP` exists); entries name the acting IRIS user, never secrets.
- **Fixes:** a drafted transform change is stored as a proposal and is never compiled or deployed; no fix kind, tool or approval can apply it. `IncidentManager` is the one writer of the incident row.
- **Ownership:** Lane A owns `.Memory`, `.Mcp`, `.Watch`, `.Fix`, the installer core and Lane A tests; catalog keys go in `Msg.Catalog.Watch`.

## Delivered code these stories build on

- Memory: `src/ocutalon/cls/OcuTalon/Data/Memory.cls` (properties through `Source`, `Pinned`, `PinnedAt`; HNSW and iFind indexes), `OcuTalon/Memory.cls` (`Search`, `Fuse`, `List`, `Pinned`, `CoreBlock`, `DropSession`), `Memory/Ops.cls` (`OnSave`, `OnForget`, `OnPin`, `OnUnpin`, `OnSearch`, `OnListPinned`), `Memory/Embedder.cls`, `Embedding.cls`, `Learned.cls`, `Worker.cls`, `Install/Step/Memory.cls`; tests in `Test/Memory/` (`Search`, `Ops`, `Pins`, `Volume`, `Turns`, `Fixture`, ...).
- Memories used in a reply: `Tools/MemoryTools.cls`, `Tools/HostData.cls` (`memories`), carried by Lane B's `Core/Conversation.cls`.
- Tasks: `Install/Step/Tasks.cls`, `Install/Step.cls` (`Tasks()`), `Install/Task/Purge.cls`, `Schedule/HeartbeatTask.cls` (pattern for entering the production).
- MCP (client side, step 4): `Mcp/Ops.cls`, `Attach.cls`, `Classification.cls`, `Client.cls`, `Proxy.cls`, `Server.cls`, `ToolClassification.cls`, `Install/Step/Mcp.cls` (per-server resources and grants); tests in `Test/Mcp/`. No `Mcp/Service*.cls` exists yet. Read-only tool classes include `Tools/Watch*.cls`, `RecentActivity.cls`. Platform reference: `irislib/%AI/MCP/Service.cls` (main checkout only).
- Watch and incidents: `Watch/Reader.cls` (no transform-source read yet), `Watch/IncidentManager.cls`, `Watch/Summary.cls` (Story 23.6 incident summary, which 28.1's draft joins), `Fix/Kind*.cls`.
- Security overview: `docs/security-overview.md`.

## Cross-Story Dependencies

- 28.2 needs Epic 19 (memory recall, `OcuTalon.Data.Memory`): merged.
- 28.3 needs the step-4 Mcp area names and installer step (Stories 35.1/35.2, Epics 14 and 22): merged. Its new web application, role and resource are a veto item.
- 28.1 needs Epic 23's incident summary (23.6, merged) and Epic 27's Story 27.1, which creates `DraftTransform` in `OcuTalon.Msg` (carrying `IncidentRef`; accepted from origin `tool` only for one of the session's own incidents; routed by `CommandsIn` to `IncidentManager`). 28.1's chat path waits for Epic 27 to merge.
- 28.2 and 28.3 run in parallel with Epic 27 (Lane B files: Slack, `CommandsIn`, `Msg.Catalog.Core`); avoid editing those.
