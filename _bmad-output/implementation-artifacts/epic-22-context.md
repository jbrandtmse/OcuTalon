# Epic 22 Context: Extend OcuTalon with MCP servers, governed like built-in tools (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make the tools of an admin-added MCP server into OcuTalon tools under the same governance as built-in ones: one gate, admin classification keyed by (server, tool name) and checked against the tool's fingerprint at every call, approval for anything risky or unclassified, and an audit entry and agent step for every call. Unclassified counts as risky, and a tool whose description or inputs change loses its classification. A hung server must never hold a runner: attach and listing are bounded first, and in the end OcuTalon lists and calls MCP tools through its own bounded client instead of AI Hub's. A read-only MCP tool can be polled as a source, so new results become items and the source appears on the digest's coverage list. The epic also ships a worked Jira example, an updated security overview, and a built-in email tool that sends to the user's own address without approval and holds every other recipient for approval. Adding an MCP server must never open a path around OcuTalon's governance.

## Stories

- Story 22.2: Classify MCP tools by server and name (done)
- Story 22.8: Classify MCP calls by fingerprint in the gate (done)
- Story 22.9: Bound MCP attach and listing with a timeout
- Story 22.3: Call MCP tools only through the governed proxy
- Story 22.4: Hold risky and unclassified MCP calls for approval
- Story 22.5: Poll a read-only MCP tool as a source
- Story 22.6: Document a worked Jira example and MCP governance
- Story 22.7: Send email from the chat, safe to you and approved for anyone else
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client

## Requirements & Constraints

- **Online demo:** real MCP servers never run there. Only the installer's allow-listed servers exist; every MCP admin surface is off and refused with a plain reason, and nothing is added at run time.
- Only admins add, remove or classify servers and tools, and only from the settings page (origin `web_admin`). No chat request, agent tool, item content, model output or tool result can do any of these. `McpOps` re-checks the origin behind `CommandsIn`'s refusal of origin `tool`.
- New tools arrive Unclassified. Removing a server removes its tools at once and cancels its pending approval requests. Every add, remove and classification change is audited.
- Every MCP call, read-only ones included, gets the IRIS permission check, the pinned AI Hub policies, classification, approval when needed, an audit entry and an agent step. An automated test shows that a risky MCP tool does not run without approval even when no platform policy covers it.
- A classification holds only for the fingerprint it was given for, and the gate checks it at every call. Tests show a rug-pull (same name, changed description or schema) is caught, including a change between the turn's listing and the call.
- MCP results are untrusted. They taint the turn, after which only read-only tools run, they quarantine the next turn, and they can never approve, classify, change settings or add servers. A Read-only MCP tool may run in an untrusted or tainted turn but still sends its arguments to its server. The governance docs must say so plainly; the sentence goes to the Contest Planner at Story 22.6's spec gate.
- An approved call runs exactly once, as approved. A replay whose fingerprint changed is refused, never run, and reported.
- All tool results of one model step together stay within 10,000 tokens, cut and marked as cut.
- MCP servers are reached only over `https://`, or loopback for development, with the server certificate verified. A credential is stored only as a `secret://` IRIS Wallet reference. No command, message body, Visual Trace, log, test output, audit entry or record ever carries a secret value.
- **Coverage:** a source counts as checked only if its poll succeeded in the window. Otherwise it shows as not checked with its reason (unreachable, error or timeout), and the digest gives no all-clear. Fixture wording: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed."
- **Docs:** the worked example and the security overview must use the same words to say that an MCP tool that runs operating-system commands or arbitrary code must be classified risky. They must also document the mid-request residual until Story 22.10 lands.

## Technical Decisions

- **Fingerprint:** `OcuTalon.Bridge.Context.ToolFingerprint(server, name, description, parameters)` is SHA-256 hex over a canonical, sorted-keys form of the server id (its `tool_ref`), the tool name, the description and the input schema. The same form is used at attach, in the turn map, by the proxy's call-time re-list and on approval rows.
- **Already in place (Epic 35, Stories 22.2 and 22.8):**
  - The five verbs `AddMcpServer`, `RemoveMcpServer`, `ClassifyTool`, `SetSourcePoll` and `RemoveSourcePoll` route to `McpOps` (`OcuTalon.Mcp.Ops`, a production item). `McpOps` is the only writer of `Mcp.Server` and `Mcp.ToolClassification` and calls `SettingsOps.RestartRunners()` after adds and removes.
  - The per-server resource `OcuTalon_MCP_<server>` and its `U` grant to `OcuTalonServiceRole` change only through `OcuTalon.Install.Step.Mcp.Grant/Revoke(server)`.
  - `McpOps.ClearChanged` clears and audits a changed tool's classification. Admin notices use the catalog keys `mcp.serverUnavailable`, `mcp.toolShadowsBuiltIn` and `mcp.toolChanged`.
  - The gate recognises an MCP call first by a `toolref` starting `mcp:` and ignores annotations such as `readOnlyHint`. Before `Chat`, the runner builds the turn's fingerprint map (`ComposeTurnTools`, bridge context node `mcp`).
  - The gate classifies an MCP call only through `ClassificationClass.ClassifyMcp(source, name, fingerprint)`. A tool missing from the map, with no row, unclassified or with a mismatched fingerprint is risky. An admin's read-only gives readOnly 1, and the result still taints, since an `mcp:` source never carries trusted output.
  - An unregistered server's toolref is denied with `UNREGISTERED` before every other step, replays included. The gate fails closed. `McpServersClass.ToolsReadOnly(server)` feeds `Decide.ToolsReadOnly`.
- **Bounded attach and listing (22.9):**
  - Measured: AI Hub gives no deadline against a server that accepts and never answers. `AddTool`, `%Discover()` and `ExecuteTool` all block for minutes, and `MCPDescriptor` takes no timeout.
  - So the agent's own manager holds no MCP server. `McpServersClass.Probe` (OcuTalon: `OcuTalon.Mcp.Client.Probe`) sends an unauthenticated JSON-RPC `initialize` with a 2 s limit, to admin-registered servers only. A request's manager adds only the servers whose probe answered.
  - A failed probe reports the server `unavailable` (reason `unreachable`) and rests it for 60 s per runner job.
  - The error text of a failed attach can hold the credential, so it only picks a reason word and is never logged or stored.
- **Mid-request residual:** a server that stops answering within one request, after its probe passed, holds that runner job until it closes the connection. This is accepted for now. Story 22.10 removes it by amending AD-21's "AI Hub lists, OcuTalon calls", so that OcuTalon's own client does both the listing and the calling. The gate, fingerprint classification, approval and audit stay unchanged.
- **Governed proxy (22.3):**
  - The gate rewrites every allowed MCP call into `call_mcp_tool(server, tool, arguments)`. The proxy is offered only by a request's composed manager that holds an MCP server, through `McpServersClass.ProxyToolSet()`, and is in no agent's `TOOLSETS`.
  - The proxy's client extends `OcuTalon.Mcp.Client`, with 2 s `initialize`, 2 s `tools/list` and 20 s `tools/call`, and verifies the peer. It re-lists the tool just before `tools/call` and refuses a changed fingerprint without running the call.
  - Results pass through `OcuTalon.Tools.Result`. Each run writes one `MCP` audit entry, `called` or `refused`, with server, tool and outcome only. The proxy never writes a classification row.
  - Permission is the service user's `U` on the `resource` that `ClassifyMcp` answers, checked with `$SYSTEM.Security.CheckUserPermission`.
  - If the gate cannot reroute a native call, it denies it with `MCPUSEPROXY` and the model calls `call_mcp_tool` itself.
- **Approval and replay (22.4):**
  - `Approval.Raise` uses kind `tool_call` and holds the exact call (server, tool, canonical arguments) with no dry run. An `mcp:` row requires `ToolFingerprint`.
  - On approval, the request goes as a `tool` request through `Decide` to the calling runner: `StartExecution`, a one-use grant, then a replay as `call_mcp_tool` on a governed manager holding only `ProxyToolSet()`. The agent's own manager is restored on every path.
  - The grant takes its toolref only when `McpServersClass.ServerOf(toolref)` equals the call's server.
  - A fingerprint changed since the request was raised ends with result `changed`, which `Core.BridgeSink` maps to `mcp.replayToolChanged`.
  - With no grant, or on a second replay, the call gets `ToolAccessDenied`.
  - The conversation gets a code-written note on its next turn, never the tool's result text.
  - `McpOps` cancels the pending requests of a removed server after the removal commits.
- **Source polls (22.5):**
  - A poll is a `BackgroundCheck` row of `Kind` `source`, owned by the admin's session, holding server, tool, arguments JSON, interval and `DisplayName`. It is created and removed only through `OcuTalon.Watch.Ops`'s row methods, which `McpOps` calls after refusing any tool that is not read-only; `McpOps` then sends `CheckChanged`.
  - `Checks` runs the poll as a `tool` request through `Decide` with no model. It writes the run fields and publishes `check` events. New results become de-duplicated untrusted Items sent to `Intake`.
  - A tool that turns unclassified or risky stops polling.
  - The mailbox's poll outcomes come from `EmailIn`'s `emailPoll.reason`.
- **Email tool (22.7):**
  - The tool declares `Classify(arguments)`: safe only when every recipient is the session user's own `email.address`, compared without case or surrounding spaces. Story 22.7 also extends the spine's tool-classification convention with this form.
  - The tool must declare `TRUSTEDOUTPUT` 1. `CommandsIn` refuses a `SendEmail` of origin `tool` in a tainted or non-`user` context, so without the flag it fails in every ordinary turn.
  - Safe path: `SendEmail` (`Recipients`, `Subject`, `Text`) goes through `Commands.Submit` with origin `tool` and an idempotency key. `CommandsIn` answers `not_connected` when `EmailOut` is not running.
  - Risky path: fix kind `OcuTalon.Fix.Kind.Email` (dry run shows `to`, `subject` and `text`; no `IncidentRef`). The approval row has `FixKind` `email` and `FixParameters.recipients`, an array that must equal the send's recipients as a lower-cased set. `FixExecutor` sends once with origin `system` and `SendEmail.ApprovalRef`.
  - `EmailOut` enforces both paths itself and claims a system send by its approval, so one approval sends at most once. Its limits: 1 to 20 recipients, a subject of 1 to 200 characters, a text of 1 to 100,000. Its outcomes: `sent`, `already_sent`, `refused`, `not_connected`, `failed`, `not_available` (DW-1164).
- **Audit and notices:** `OcuTalon.Bridge.Audit` is the only audit writer, and entries pass the redactor. Producers never render text: catalog keys live in `OcuTalon.Msg.Catalog.Watch` and reach `Ownership.AdminSessions()`. Tool-call and email-fix approval notices come from `OcuTalon.Core.BridgeSink`, not from `IncidentManager`.
- **Ownership and tests:** Lane A owns `OcuTalon.Mcp`, `.Tools`, `.Watch`, `.Fix`, `.Checks`, `.Digest`, the bridge, `ci/mock/scenarios/A/` and the security overview. Tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`, run against the loopback mock MCP server. The mock also serves an SMTP stub for email tests. Add `call_mcp_tool` and the email tool to `OcuTalon.Tools.Names` and to the CI mock's scripts.
- **Open risk DW-174:** measure a real MCP tool's toolref and metadata in `%CanExecute`.

## UX & Interaction Patterns

- Settings › Tools and MCP servers (Lane B) shows each tool as Unclassified (risky), Read-only or Risky. A change is saved at once and audited. A changed tool reverts to Unclassified with an admin notice card. Only read-only tools can be source polls.
- A tool-call approval card reads "Run {tool} on {server}", with the exact inputs and the no-dry-run sentence. An email fix's dry run shows the exact text and every recipient.
- In an untrusted or tainted turn, any suggestion that is not read-only, email included, is described as an offer and never raised as a request.
- The agent step label names the server and tool, never the arguments.
- Email results use `EmailOut`'s fixed sentences, such as "The email was sent." and "No outgoing mail server is connected, so the email wasn't sent." The mailbox's not-checked reasons on the coverage list use the fixed mail-poll sentences, such as "OcuTalon couldn't reach the mail server."

## Cross-Story Dependencies

- Epic 35 is merged and supplies the contracts. Epics 14, 17 and 30 supply the security overview, the digest's coverage list, and the `tool` request and replay path. Stories 22.2 and 22.8 are done.
- Lane B:
  - Story 21.4 owns the MCP settings routes and moves the Wallet and Config Store writes into `McpOps`; until then the routes are stubs.
  - Stories 21.2 and 21.6 own `EmailIn`, `EmailOut` and `email.address`.
  - Story 21.5 owns `BridgeSink`'s email-fix notices. Until it merges, 22.7 checks only that the request has no `IncidentRef` and that `IncidentManager` sends nothing for it.
  - Story 22.4 adds one `BridgeSink` branch (`changed` to `mcp.replayToolChanged`).
- **Order:**
  1. 22.9.
  2. 22.3: the proxy, the call-time re-list and `ProxyToolSet`.
  3. 22.4: replay through the proxy, `ServerOf` and the cancellation of pending requests.
  4. 22.5: needs read-only classification and the proxy.
  5. 22.6: documents 22.2 to 22.5, 22.8, 22.9, the Read-only arguments sentence and the residual.
  6. 22.7: independent, but shares the gate.
  7. 22.10: builds on 22.3's client and 22.9's bounds, and amends AD-21.
- Story 22.6 supplies the worked example's path under `docs/`. Lane B's Story 36.2 adds the README link and copies the classification sentence.
