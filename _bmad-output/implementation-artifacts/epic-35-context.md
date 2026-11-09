# Epic 35 Context: Step 4's contracts: MCP servers attach, and webhooks bring events in (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 4's contract epic. It fixes step 4's names in the spine, and in code as stubs, so that the feature epics can build in parallel: Epic 21 (Lane B: email, webhook, MCP settings) and Epic 22 (Lane A: MCP and source polls). It also ships two working features. The MCP servers an admin registers attach to OcuTalon's agents, and every new tool starts unclassified (done in 35.1). Webhooks, each with its own secret, turn any JSON event into an untrusted item. Each story keeps its home lane's files. Where a story says "this epic", it means Epics 21 and 22 plus its partner story here.

## Stories

- Story 35.1: Fix step 4's contracts and register MCP servers (Lane A; done)
- Story 35.2: Fix Lane B's step 4 contracts (Lane B; the title still says "and send events to OcuTalon through a webhook" to keep its tracker key, but the webhook moved to 35.3)
- Story 35.3: Send events to OcuTalon through a webhook (Lane B; new, split from 35.2, follows it)

## Requirements & Constraints

- **35.2 spine update** (one change, ownership tables included):
  - a Lane B webhook table: ref, name, owning session, salted secret hash;
  - `/ocutalon/hook`, created by `OcuTalon.Install.Step.Web`: a dispatch class only, no session, and a minimal webhook role whose grants come from `Grants()`;
  - the secret header name and the body-size cap;
  - the email and MCP settings routes;
  - the record where `EmailIn` keeps each poll's outcome (Story 22.5 reads it).
- **35.2 verbs** go in `OcuTalon.Msg.Command`, routed by `CommandsIn`:
  - The five MCP verbs `AddMcpServer`, `RemoveMcpServer`, `ClassifyTool`, `SetSourcePoll` and `RemoveSourcePoll` go to `McpOps`. They come from `web_admin` only and are refused from `tool`.
  - `SendEmail` goes to `EmailOut`. From `tool`, it is accepted only when every recipient is the session user's own address; add it to AD-1's list of verbs taken from `tool`. From `system`, it carries `FixExecutor`'s approved email fix.
- **35.2 `SettingsOps.RestartRunners()`:** restarts the runner items through `Ens.Director` while the production keeps running, so each runner rebuilds its agent with the servers registered at that moment. A test checks it.
- **35.2 ruling additions (Planner, approved):**
  - A read API returns the sessions whose user held `OcuTalonAdmin` at their latest sign-in. This needs a new `Session` property (`AdminAtSignIn`); the stored-data change is approved. Story 22.2's admin notices use the API.
  - `SettingsOps` writes an MCP server's Config Store entry `AI.MCP.OcuTalon_<server>` and its IRIS Wallet secret, and the MCP settings route calls it. `McpOps` writes only the `Mcp.Server` row and calls `RestartRunners()`.
  - No command, log, test output or record ever carries a secret value, only a `secret://` reference.
- **35.3 webhook behaviour:**
  - An admin creates a webhook in Settings > Channels. The secret is stored only as a salted hash, in a write-only field that never shows it again. A value containing `@{` is refused. The webhook's events belong to the admin's session, and the change is audited without the secret.
  - A valid `POST` under the cap gets 202 within 1 s, before any decision. `WebhookIn` then sends an untrusted Item to `Intake`, which makes the attention decision. The event and its decision show in Visual Trace in the event's own trace session.
  - An unknown webhook and a missing or wrong secret get the same 401. The secret is compared as a salted hash in constant time, nothing becomes an item, and rejections are audited at a capped rate.
  - A body over the cap, or one that isn't JSON, is refused and never becomes an item.
  - A test calls `/ocutalon/hook` and every other OcuTalon path without signing in, and finds that only a webhook `POST` with its secret is accepted.
- **Texts:** 35.2 proposes the step 4 texts in `EXPERIENCE.md`, with keys in `OcuTalon.Msg.Catalog.Core`: email and webhook settings, the changed-tool banner, the source-poll form, and an approval's cancelled status. The Planner accepted its 30 keys with two edits (ruling planner-2026-11-09-35.2-text). 35.3 ships the webhook texts that 35.2 adds. No story ships a text the author hasn't accepted (UX-DR117, UX-DR145).
- Release checks (demo-host MCP allow-list; the proxy blocking the webhook path) belong to the Contest Planner, not these stories.

## Technical Decisions

- **Spine:** `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`. ADs the stories name: AD-1, AD-13, AD-14, AD-17, AD-19, AD-21, AD-23, AD-25, AD-26, AD-29, AD-30, AD-33.
- **Already in the spine (35.1 added it; extend it, don't duplicate it):**
  - AD-21's MCP **Names** bullet: the five verbs, the `SettingsOps` and `McpOps` split for config and secret writes, and the `Mcp.Server` columns.
  - `Tools(server)`, `McpServersClass` (`Servers`, `OnAttach`), the source-poll row type and the email fix kind (`OcuTalon.Fix.Kind.Email`).
  - Cross-area rows for `RestartRunners()` and for "Lane B contracts fixed by Story 35.2".
  - AD-13 already has the `/ocutalon/hook` bullet: dispatch class, minimal role, no session, header secret, constant-time salted hash, body cap, the same 401. AD-19 stores webhook secrets as salted hashes and refuses `@{`. AD-17 has the capped-rate audit of rejected webhook requests.
  - Production items `EmailIn`, `EmailOut` and `WebhookIn` (`OcuTalon.Channel.Email.In`, `.Out`, `OcuTalon.Channel.Webhook.In`, Lane B).
  - The REST surface already lists `POST /api/v1/settings/channels`.
- **Not yet in the spine (35.2 adds it):** the webhook table (in the Lane B table list and the ERD), the header name and cap value, the email and MCP settings routes, `EmailIn`'s poll-outcome record, `SendEmail` in AD-1's tool list, and the admin-session read API with its `Session` property.
- **Webhook payloads:** each source's payload mapping is deferred; every payload becomes an untrusted Item first.

### Already delivered: build on it

- **Story 35.1:**
  - `OcuTalon.Mcp.Ops`: the `Tools` stub, and `RecordAttach`.
  - `OcuTalon.Mcp.Server` (the row with its attach report).
  - `OcuTalon.Mcp.Attach`.
  - `OcuTalon.Bridge.Ext.McpServers`, with the attach in `Bridge/Adapter/Agent.cls`.
  - `OcuTalon.Msg.Catalog.Watch`'s `mcp.*` keys.
  - The loopback mock MCP server in `OcuTalon.Test.Mcp`.
  - `McpOps` is not in the production yet (Story 22.2 adds it).
- **CommandsIn** (`Core/CommandsIn.cls`): routes in `XData Routes` (verb, owner, origins), the tool verbs in `Parameter TOOLVERBS`, refusal texts in `MESSAGE*` parameters. None of the step 4 verbs is there yet.
- **SettingsOps** (`Core/SettingsOps.cls`): `XData Sections`, `ALLOWLIST`, `Save`, `Field` (it refuses `@{`), `WriteAudit` and `AuditData`. There is no `RestartRunners` yet. For `Ens.Director` restart patterns, see `Install.Step.Production` and the tests' `TempStopConfigItem` and `EnableConfigItem` calls.
- **Web.Api:**
  - `POST /v1/settings/channels` still answers 501 (`NotBuilt`), and `Test/Web/SettingsApi.cls` `TestBridgeRoutesAre501` covers it.
  - `OnPreDispatch` checks admins through `IsAdmin()` (`OcuTalonAdmin` by its whole name in `$Roles`).
- **Web page:** `web/src/app/settings/` holds `channels-section.ts` (Telegram, read-only), `settings-view.ts` (`SETTINGS_TEXTS`) and `refusal.ts`.
- **Install.Step.Web:** `Definitions`, `Apply`, `Common` and `Grants()`. `/ocutalon/hook` is added here.
- **`OcuTalon.Data.Pairing.HashCode`** is SHA-256 and base64url, unsalted. The webhook needs a salted hash.
- **`OcuTalon.Data.Session`** has no admin flag yet.
- **Not in code yet:** `OcuTalon.Channel.Email` and `.Webhook`, `SendEmail`, the MCP verbs, `RestartRunners`.

## UX & Interaction Patterns

- Settings > Channels holds the webhook form: a name and a write-only secret that never shows its value again.
- All texts follow Voice and Tone: plain English, short sentences, no class names or codes. Telegram and the simulated phone share each text exactly.

## Cross-Story Dependencies

- Story 35.1 is done and merged into the epic branch: its names, verbs and `Mcp.Server` columns are fixed.
- Story 35.2 must land before 35.3. 35.3 uses 35.2's spine entries (webhook table, header, cap, `/ocutalon/hook` application and role) and the webhook settings texts 35.2 adds.
- Outside this epic:
  - Story 22.2 (`McpOps`) calls 35.2's `RestartRunners()`, its admin-session read API, and `SettingsOps`' MCP entry writer.
  - Story 21.4 calls 35.1's `Tools(server)` stub.
  - Story 22.5 reads `EmailIn`'s poll-outcome record.
  - Story 22.7 sends through `SendEmail` from `system`.
- Epics 21 and 22 wait for this epic. Epic 36 extends the `BackgroundCheck` row types.
