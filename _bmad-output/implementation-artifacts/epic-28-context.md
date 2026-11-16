# Epic 28 Context: Transform drafts, memory fading and OcuTalon as an MCP server

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 7's Lane A work, brought forward by the owner on 2026-11-16 ("Epics 27 and 28 START NOW"). OcuTalon keeps recall relevant as memory grows (unused memories rank lower; done in 28.2), lets a developer call its read-only tools from their own MCP client under their own IRIS sign-in without opening any new way to act (28.3, next), and drafts the transform change that would stop a data-format failure as a text proposal that is never compiled, saved or applied (28.1, waits for Epic 27). The nightly duplicate merge was split out to Story 28.4, which is held for an owner decision on its duplicate rule and is not next work. The 1.0.12 release has merged back into this branch.

## Stories

- Story 28.2: Fade unused memories (done; fading only)
- Story 28.3: Offer OcuTalon's read-only tools to MCP clients (next)
- Story 28.1: Draft a transform change as a proposal that is never applied (after 28.3; waits for Epic 27)
- Story 28.4: Merge duplicate memories nightly (HELD for an owner decision on its duplicate rule; do not start)

## Requirements & Constraints

- **Spine first, per story.** Each story records its share of step 7 in the architecture spine in its own change, with new items, tables and roles in the ownership tables: 28.3 `OcuTalon.Mcp.Service` with its web application, resource, role and installer step; 28.1 the transform draft's storage and the `DraftTransform` verb.
- **MCP server (28.3):** offers only read-only toolsets; refuses anonymous clients, wrong passwords and users without `OcuTalonMCPClient`; tools run as the calling IRIS user and return only that user's session's records; no offered tool can resend, fix or change a setting (risky actions only through an approved approval request in OcuTalon's own channels); every call, read-only included, is audited with the calling IRIS user. Off on the online demo (`/mcp` is outside the proxy's allow-list; a release check, not a story gate).
- **Tests (28.3):** IRIS-runner tests with a minimal MCP client covering each refusal and one successful read-only call; the security overview lists the service's tools from its specification and the `OcuTalonMCPClient` role.
- **Transform draft (28.1):** for an incident whose cause is a data format a transform rejects, read the transform's source through `OcuTalon.Watch.Reader`, ask the diagnosis agent through `Decide` with the sample failure, everything cut to size limits, and attach the draft (transform name, time) to the incident. It shows as text in chat, the incident summary and Visual Trace, never as runnable code. `OcuTalon.Test.Fix` with mock scenarios under `ci/mock/scenarios/A/` proves the class dictionary, routines and watched production are unchanged, and the tool inventory test still finds no tool that compiles or saves code.
- **Texts:** step 7 texts the UX doesn't give (draft presentation and never-applied note) are proposed to the author as `EXPERIENCE.md` Message Catalog additions, keys in `OcuTalon.Msg.Catalog.Watch`; nothing ships a text the author hasn't accepted.
- Release checks are the Contest Planner's hands-on pass, not story gates.

## Technical Decisions

- **Every command is a production message.** State changes go through `CommandsIn` with an origin set by code; tools never write domain tables. A read-only MCP tool therefore changes nothing and submits no state-changing command.
- **MCP server shape:** `OcuTalon.Mcp.Service` extends `%AI.MCP.Service` with `Parameter RESOURCE = "OcuTalon_MCPServer"` (the platform class checks Use on every listed resource for each REST and WebSocket request; empty means CSP authentication alone, so it must be set). Its `SPECIFICATION` is a comma list of toolset classes, each of which must exist and compile. Web application `/mcp/ocutalon`: password authentication only, namespace OCUTALON, no application roles. Role `OcuTalonMCPClient`: Use on the resource, read on the databases its tools read, SQL `SELECT` on exactly the tables they query; the role bounds the tools because they run as the client's user.
- **`iris-mcp-server`:** no endpoint credentials (they admit anonymous clients whatever `allow_anonymous` says), `allow_anonymous = false` (never copied from AI Hub's dev template), status tool off; its own login is a role-less user whose password comes from the environment. Spike S10 confirmed this configuration.
- **Security boundary:** only `Install.*` reaches `%SYS`; the installer creates roles, resources and web applications. The new web application, role and resource are a veto item.
- **Audit:** `OcuTalon.Bridge.Audit` is the only audit writer; type `MCP` exists, but its shapes today cover the step-4 client side only (`change,server` and `change,server,tool,outcome`). Entries name the acting IRIS user, never secrets, arguments or results.
- **Storage is append-only (AD-5)**; new persistent classes use `DEFAULTGLOBAL` under `^OcuTalonP.` and commit their `Storage` block.
- **Fading (delivered in 28.2):** `Data.Memory.LastUsedAt`; `Agent.Content.Accepted` (which now gets the reply's `HostData` as `replyHostData`) sends `OcuTalon.Memory.Msg.Used` through the adapterless `MemoryIn` to `MemoryOps`; `Memory.Fuse` halves the score of an unpinned memory last used (else saved) more than `memory.fadeDays` days ago (seed 90); fading never drops a memory, pins never fade. `MemoryIn`'s internal messages are not command verbs. `MemoryOps` stays the memory table's only writer.
- **Fixes (28.1):** a drafted transform change is stored as a proposal, never compiled or deployed; no fix kind, tool or approval can apply it. `IncidentManager` is the one writer of the incident row.
- **Ownership:** Lane A owns `.Memory`, `.Mcp`, `.Watch`, `.Fix`, the installer core and Lane A tests.

## Delivered code these stories build on

- **MCP client side (step 4):** `src/ocutalon/cls/OcuTalon/Mcp/` holds `Ops.cls` (business operation for MCP verbs), `Attach.cls` (`Bridge.Ext.McpServers`), `Classification.cls` (`Bridge.Ext.Classification`), `Client.cls`, `Proxy.cls`, `Server.cls` and `ToolClassification.cls` (persistent rows). No `Mcp/Service*.cls` exists yet. Tests in `Test/Mcp/`.
- **`Install/Step/Mcp.cls`:** today only per-server resources `OcuTalon_MCP_<server>` and their `U` grant to `OcuTalonServiceRole` (`Grants()`, `Grant`, `Revoke`, `RESOURCEPREFIX`); it refuses any other resource name. Web applications are created in `Install/Step/Web.cls`, roles in `Install/Step/Roles.cls`.
- **How tool classification is declared:** each tool's provider class (extends `OcuTalon.Tools.Result`) carries class parameters `CLASSIFICATION<NAME>` (`safe`/`risky`), `READONLY<NAME>` and `TRUSTEDOUTPUT<NAME>` (1/0), with `STEPLABEL<NAME>`; the gate (`Bridge/Policy/Gate.cls`) and `Install/SecurityOverview.cls` read them. Toolsets (`%AI.ToolSet` XData) hold no `Requirement`, except `Tools/Watch.cls` (`OcuTalonWatch`), which also declares `<Requirement Name="ReadOnly" Value="1"/>` per tool.
- **Read-only tools today:** `read_failed_messages`, `read_event_log`, `read_item_settings` (`Tools/WatchReads.cls`, the Diagnosis agent's `OcuTalon.Tools.Watch`; they read the bridge context's incident); `recent_activity` and the incident summary (`Tools/RecentActivity.cls`); `list_productions`, `check_status` (`Tools/WatchTools.cls`); `search_memories`, `list_memories` (`Tools/MemoryTools.cls`); `list_reminders` (`Tools/ReminderTools.cls`). The Chat toolsets (`Tools/Watching.cls`, `Memory.cls`, `Reminders.cls`) mix read-only and state-changing tools, and every session tool finds its owner through `Tools/CommandCall.cls` `Session()`, which needs an active `OcuTalon.Bridge.Context` (a turn) and otherwise answers `NOSESSION`.
- **Security overview:** `docs/security-overview.md`, whose Built-in tools, Fix kinds and Privileges sections are generated by `OcuTalon.Install.SecurityOverview` between `BEGIN/END GENERATED` markers (do not hand-edit them); the hand-written "MCP tools" section covers only the client side.
- **Platform reference:** `%AI.MCP.Service` (`%CSP.REST` + `%CSP.WebSocket`; endpoints `GET /v1/services`, `GET /v1/health`, `POST /v1/tool_call`, `WS /v1/ws`; overridable `OnAuthenticate`, `GetSpecification`; `LOGINPAGE` gives a JSON 401) lives only in the main checkout's gitignored `irislib/%AI/MCP/Service.cls`; read it there, read-only, never load it.
- **Memory and fading:** `Data/Memory.cls`, `Memory.cls` (`Search`, `Fuse`, `Faded`, `FadeDays`), `Memory/Ops.cls`, `Memory/In.cls`, `Memory/Msg/Used.cls`, `Install/Step/Memory.cls`; tests `Test/Memory/Fade.cls`, `LastUsed.cls`.
- **Watch and incidents (28.1):** `Watch/Reader.cls` (no transform-source read yet), `Watch/IncidentManager.cls`, `Watch/Summary.cls`, `Fix/Kind*.cls`.

## Cross-Story Dependencies

- 28.3 needs the step-4 Mcp area and installer step (merged). It runs in parallel with Epic 27 (Lane B: Slack, `CommandsIn`, `Core/Conversation.cls`, `Core/SettingsOps.cls`, `Msg.Catalog.Core`, `Msg/Command/*`); avoid editing those.
- 28.1 needs Epic 27's Story 27.1 (backlog), which creates `DraftTransform` in `OcuTalon.Msg` (carrying `IncidentRef`; accepted from origin `tool` only for one of the session's own incidents; routed by `CommandsIn` to `IncidentManager`). Its chat path waits for Epic 27 to merge.
- 28.4 waits for the owner's ruling on the duplicate rule (R-28.2-3: zero false merges on 28.2's Task 0 set); its spine entries (`OcuTalon.Memory.Task`, `Memory.Data.Merge`, `Consolidate`) are planned, not built.
- 28.2's Volume item is closed: `Test.Memory.Volume` (plan guard on `NEARESTSQL`, which now selects `LastUsedAt`) passed in the memory-offline live unit (DW-1436, resolved-by 28.2).
