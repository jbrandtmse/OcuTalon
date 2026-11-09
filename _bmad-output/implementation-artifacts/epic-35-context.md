# Epic 35 Context: Step 4's contracts: MCP servers attach, and webhooks bring events in (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 4's contract epic. It sets step 4's names in the spine, and in code as stubs, so that the feature epics, Epic 21 (Lane B: email, webhook, the MCP settings) and Epic 22 (Lane A: MCP and source polls), can be built in parallel. It also ships two working features. The MCP servers an admin registers are attached to OcuTalon's agents, and every new tool starts unclassified. Webhooks, each with its own secret, turn JSON events into untrusted items. In stories, "this epic" means Epics 21 and 22 plus the partner story here. Each story keeps its home lane's files.

## Stories

- Story 35.1: Fix step 4's contracts and register MCP servers (Lane A)
- Story 35.2: Fix Lane B's step 4 contracts and send events to OcuTalon through a webhook (Lane B; follows 35.1)

## Requirements & Constraints

- **35.1 spine update** (one change, with the ownership tables): `McpOps` (`OcuTalon.Mcp.Ops`, Lane A) owns `OcuTalon.Mcp.Server` and `OcuTalon.Mcp.ToolClassification`. It takes these commands: add or remove a server, classify a tool, set or remove a source poll. Add the source-poll row type in `OcuTalon.Data.BackgroundCheck`. `Tools(server)` returns name, classification and status for every discovered tool, and each one has a row, unclassified included. It ships as a stub that Story 21.4 calls until Story 22.2 builds it. Also add the email fix kind, with its approval path to `FixExecutor` and its send through `EmailOut`. Record in AD-31 that a fix request with no incident gets its `approval`, `answered` and `result` notifications from `OcuTalon.Core.BridgeSink`, as tool calls do; `IncidentManager` sends them only for a kind `fix` request of an incident.
- **35.1 attach:** in `OnAfterAgentInit`, after the agent's own toolsets, attach each server as `mcp:remote:@{config:AI.MCP.OcuTalon_<server>}`. Check the attach status and the tool statuses. Report a server that is unavailable. Refuse a tool whose name shadows a built-in, and tell the admins. The tests use a fixture `Mcp.Server` row and a Config Store entry. A loopback mock MCP server in `OcuTalon.Test.Mcp` offers one read-only tool and one risky tool, and Epic 22 reuses it.
- **35.2 spine update:** the webhook table holds each webhook's ref, name, owning session and salted secret hash. Add `/ocutalon/hook`, created by `OcuTalon.Install.Step.Web`: a dispatch class only, no session, and a minimal webhook role declared through `Grants()`. Also add the secret header name, the body-size cap, the email and MCP settings routes, and the record where `EmailIn` keeps each poll's outcome (Story 22.5 reads it).
- **35.2 verbs** go in `OcuTalon.Msg.Command`, routed by `CommandsIn`. The MCP verbs go to `McpOps` under 35.1's names and are refused from origin `tool`. `SendEmail` goes to `EmailOut`. It is accepted from `tool` only when every recipient is the session user's own address, so add it to AD-1's list of verbs taken from `tool`.
- **35.2 `SettingsOps.RestartRunners()`:** restarts the runner items through `Ens.Director` while the production keeps running, so each runner rebuilds its agent with the servers registered at that moment. A test checks it.
- **Webhook behaviour:**
  - Created in Settings › Channels.
  - The secret is stored only as a salted hash, in a write-only field. A value containing `@{` is refused. The change is audited without the secret.
  - A valid `POST` gets 202 within 1 s, before any decision. `WebhookIn` then sends an untrusted Item to `Intake`, in the event's own trace session.
  - An unknown webhook and a wrong or missing secret get the same 401. The secret is compared in constant time, and rejections are audited at a capped rate.
  - A body over the cap, or one that isn't JSON, is refused.
  - A test calls every OcuTalon path without signing in and finds that only the webhook `POST` with its secret is accepted.
- **Texts:** both stories propose their new wording for `EXPERIENCE.md` (35.1: keys in `OcuTalon.Msg.Catalog.Watch`; 35.2: keys in `Catalog.Core`). Nothing ships until the author accepts it (UX-DR117, UX-DR145).
- Release checks (demo-host MCP allow-list, proxy blocks the webhook path) belong to the Contest Planner, not these stories.

## Technical Decisions

- **Spine:** `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`. ADs the stories name: AD-1, AD-6, AD-13, AD-14, AD-16, AD-17, AD-19, AD-21, AD-22, AD-23, AD-25, AD-26, AD-29, AD-30, AD-31, AD-32, AD-33.
- **Already in the spine** (extend these, don't add them twice):
  - `OcuTalon.Mcp.Ops.Tools(server)`, as a dependency-graph node and a cross-area row: Lane A, stub in 35.1, built in 22.2.
  - `OcuTalon.Core.SettingsOps.RestartRunners()`, also as a graph node and a row: Lane B, Story 35.2.
  - `McpOps (Lane A)`, named only in AD-21's Changes bullet.
  - `OcuTalon.Mcp.Server`, named in AD-10 and AD-21.
  - `Mcp.Server` and `Mcp.ToolClassification` in Lane A's table list, and an ERD edge `McpServer ||--o{ ToolClassification`.
  - `/ocutalon/hook`, in AD-13.
  - Production items `EmailIn`, `EmailOut` and `WebhookIn` (`OcuTalon.Channel.Email.In`, `.Out`, `OcuTalon.Channel.Webhook.In`, Lane B).
  - Webhook secrets as salted hashes, and MCP secrets as `secret://` wallet references (AD-19).
  - Capped-rate audit of rejected webhook requests, and an audit of every MCP call (AD-17).
  - Source polls as a `tool` request to `Decide` through `call_mcp_tool` (AD-6, AD-21).
- **Not yet in the spine:**
  - the `SendEmail` verb and the MCP command verbs;
  - the webhook table (in the Lane B table list and the ERD);
  - a production-item row for `McpOps`;
  - the source-poll row type;
  - the email fix kind;
  - the header name and the cap value;
  - the email and MCP settings routes in the REST surface;
  - `EmailIn`'s poll-outcome record;
  - the AD-31 note on `BridgeSink` (AD-32 already gives kind `approval` to a fix request with no incident).
- **MCP rules (S9, partial pass):** AI Hub lists a server's tools and OcuTalon calls them. The gate rewrites every allowed MCP call into the governed proxy `call_mcp_tool(server, tool, arguments)`, which cuts results through `OcuTalon.Tools.Result`. The gate classifies an MCP tool by (toolref, name) only through `ClassificationClass`, and ignores MCP annotations. A tool with a changed fingerprint (description plus input schema) is unclassified. Each server has an IRIS resource `OcuTalon_MCP_<server>`. URLs must be `https://` with a trusted certificate, or loopback.

### Already delivered (Epics 17, 18, 19, 33): build on it, don't duplicate it

- **Adapter** `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` (Story 19.5):
  - `OnAfterAgentInit` currently calls `##super` and then `Govern`.
  - `Attach(agent, spec)` is the one way to add a tool, and it records the spec in `Attached` so that every per-turn manager adds it again. MCP attach goes through it.
  - Also there: `Govern`, `SessionConfigFor`, `ComposeTurnTools`, `BuildTurnManager` and `EndTurnTools`.
  - Specs: `spec-19-5-keep-each-online-demo-session-s-documents-and-memories-to-it.md`, `evidence/19-5-task0-turn-tools.md`.
- **Per-turn tools:** `OcuTalon.Bridge.Ext.TurnTools`, `OcuTalon.Docs.TurnTools`, and the `TurnToolsClass` setting in `OcuTalon.Production`.
- **Gate** `OcuTalon.Bridge.Policy.Gate`:
  - `MCPPREFIX "mcp:"`; for an MCP call the source is the toolref.
  - It reads no read-only or trusted-output flag from MCP.
  - The base `OcuTalon.Bridge.Ext.Classification.Classify(source, name, arguments)` exists, but OcuTalon has no subclass yet: `ClassificationClass` is unset in `OcuTalon.Production`.
  - Name clash: Decide's `ToolClassification` *setting* (a JSON array for developer tools, seeded by `Install.Step.Production.SeedClassification`) is not the `OcuTalon.Mcp.ToolClassification` *table*.
- **CommandsIn** (`Core/CommandsIn.cls`): routes live in `XData Routes` (verb, owner, origins), the tool verbs in `Parameter TOOLVERBS`, and the refusal texts in `MESSAGE*` parameters.
- **SettingsOps** (`Core/SettingsOps.cls`, Stories 33.2, 18.2 and 18.3):
  - `XData Sections` has no `channels` row ("no save yet").
  - Also there: `ALLOWLIST`, `Values()`, `Save`, `Field` (refuses `@{`), `WriteAudit` and `AuditData`.
  - No `RestartRunners` yet. For `Ens.Director` restart patterns, see `Install.Step.Production` and the tests' `TempStopConfigItem` and `EnableConfigItem` calls.
- **Web.Api** (Story 33.2):
  - `POST /v1/settings/channels` is routed to `NotBuilt` (501).
  - The admin check `IsAdmin()` in `OnPreDispatch` looks for `OcuTalonAdmin` by its whole name in `$Roles`.
  - The test `Test/Web/SettingsApi.cls` `TestBridgeRoutesAre501` now covers only channels.
  - Specs: `spec-33-1-fix-the-step-2-contracts-in-the-spine.md`, `spec-33-2-open-the-settings-page-as-an-admin.md`, `spec-18-2-*`, `spec-18-3-*`, `spec-18-4-*`.
- **Web page:** `web/src/app/settings/` holds `channels-section.ts` (the read-only Telegram state, Story 18.2), `settings-page.ts`, `settings-view.ts` (`SETTINGS_TEXTS`) and `refusal.ts` (meant for the later sections).
- **Install.Step.Web:** `Definitions`, `Apply`, `Common` and `Grants()`. `/ocutalon/hook` is added here.
- **`OcuTalon.Data.Pairing.HashCode`:** SHA-256 and base64url, unsalted. The webhook needs a salted hash.
- **`Data.BackgroundCheck.Kind`:** today only `production`.
- **Not in code yet:** packages `OcuTalon.Mcp` and `OcuTalon.Test.Mcp`, `OcuTalon.Channel.Email` and `.Webhook`, `SendEmail`, `RestartRunners`, and the catalog key `digest.notChecked.unreachable`.

## UX & Interaction Patterns

- **Settings › Tools and MCP servers** (built in Epic 21):
  - a server list with status, a tool count and an unclassified count;
  - removing a server asks first and cancels its pending requests;
  - a tool table with one radio group per tool that saves at once, shows "Saved" and is audited, plus an "Unclassified only" filter;
  - a changed tool shows a banner in Settings and a notice card in the chat.
- A tool-call approval card shows "Run {tool} on {server}" and the exact inputs, with the UX's "no dry run" sentence.
- All texts follow Voice and Tone: plain English, no class names or codes.

## Cross-Story Dependencies

- Story 35.2 follows 35.1: its verbs route to `McpOps` under 35.1's names. Story 22.2 (`McpOps`) calls 35.2's `RestartRunners()`, and Story 21.4 calls 35.1's `Tools(server)` stub.
- Epics 17, 18, 19 and 33 have merged. Epics 21 and 22 wait for this epic, and Epic 36 extends 35.1's `BackgroundCheck` row types.
