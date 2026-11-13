# Epic 22 Context: Extend OcuTalon with MCP servers, governed like built-in tools (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

An admin adds an MCP server and its tools become OcuTalon tools under the same governance as built-in ones. One gate decides every call. The admin classifies each tool by (server, tool name), and the classification holds only while the tool's fingerprint matches. Anything risky or unclassified needs an approval, and every call gets an audit entry and an agent step. A read-only MCP tool can also be polled as a source on the daily digest's coverage list, with a worked Jira example. The epic also ships the security overview's MCP update and a chat email tool that sends freely only to the user's own address. This is the extension story judges and security reviewers check: adding a server must never open a path around approval or audit.

## Stories

- Story 22.2: Classify MCP tools by server and name
- Story 22.8: Classify MCP calls by fingerprint in the gate
- Story 22.9: Bound MCP attach and listing with a timeout
- Story 22.3: Call MCP tools only through the governed proxy
- Story 22.4: Hold risky and unclassified MCP calls for approval
- Story 22.5: Poll a read-only MCP tool as a source
- Story 22.11: Run source polls through the governed proxy (split from 22.5; not yet in the epics file)
- Story 22.6: Document a worked Jira example and MCP governance
- Story 22.12: Document polling a Jira MCP tool as a source
- Story 22.7: Send email from the chat, safe to you and approved for anyone else
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client (deferred: not built in this release)

## Requirements & Constraints

- **Admin-only changes.** Servers are added and removed, tools classified and source polls set only from the settings page (origin `web_admin`). No chat request, agent tool, item, model output or tool result can do any of it, and every change is audited. On the online demo nobody adds a server: `McpOps` refuses every MCP verb and only the installer's allow-listed servers exist.
- **Unclassified counts as risky.** New tools arrive Unclassified. A tool whose description or inputs change loses its classification, and admins are told. MCP annotations such as `readOnlyHint` are ignored. An MCP tool never takes a built-in tool's classification, and a server tool that shares a built-in's name (including `call_mcp_tool`) is refused.
- **Every MCP call is governed.** Polls included, each call gets the IRIS permission check, the pinned AI Hub policies, the classification check, an approval when needed, an audit entry and an agent step. The step's label names the server and tool, never the arguments. A test shows that a risky MCP tool does not run without approval even when no platform policy covers it.
- **MCP results are untrusted.** They taint the turn: only read-only tools run for the rest of it, the next turn is quarantined, and a result can never approve, classify, change settings or add servers. A Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, and the docs must say so plainly.
- **Size and transport.** All tool results of one model step stay within 10,000 tokens, cut and marked as cut. Servers are reached only over `https://` with a trusted certificate (loopback for development). Credentials exist only as `secret://` IRIS Wallet references, never in a command, log, trace, test output, audit entry or record.
- **Coverage.** A source is "checked" only if its poll ran successfully in the digest window; otherwise it is "not checked" with its reason (unreachable, error, timeout, stopped) and there is no all-clear. Step 4 test fixture: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed."
- **Email.** Email to the session user's own address is safe; email to anyone else is risky and needs approval, sent exactly once after it.
- **Docs.** The worked example and the security overview use the same sentence: an MCP tool that runs OS commands or arbitrary code must be classified risky. They also document the known limit: a slow server can hold a request about 31 s past its 2 s bound. No public text claims a hard MCP deadline. Until Story 21.10 merges, no release note, guide or More-to-try text describes the changed-tool replay path.

## Technical Decisions

- **AI Hub lists, OcuTalon calls.** The runner attaches each server through its Config Store entry `AI.MCP.OcuTalon_<server>`. The agent's own manager holds no MCP server. Each request's manager adds only the servers whose 2 s `initialize` probe answered, and a failed probe reports the server `unavailable`. This rule stays for the contest because the re-architecture in 22.10 was declined, so a server that stalls mid-request is the accepted, documented residual.
- **Ownership of writes.** `McpOps` (Lane A) writes the `OcuTalon.Mcp.Server` and `OcuTalon.Mcp.ToolClassification` rows and calls `OcuTalon.Core.SettingsOps.RestartRunners()` after an add or remove. `SettingsOps` (Lane B) writes the Config Store entry and the Wallet secret. The per-server resource `OcuTalon_MCP_<server>` and its `U` grant go only through `Install.Step.Mcp.Grant`/`Revoke`. `Bridge.Audit` is the only audit writer.
- **Fingerprint.** `Bridge.Context.ToolFingerprint` is SHA-256 hex over a sorted-keys form of server id, tool name, description and input schema, and it is the only fingerprint form. The gate recognises MCP calls first, by a `toolref` starting `mcp:`, before `metadata.origin_class`, and classifies them through `ClassificationClass.ClassifyMcp(source, name, fingerprint)`. A missing, unclassified or mismatched tool counts as risky, and an unregistered server is denied (`UNREGISTERED`). The gate fails closed.
- **Governed proxy.** Every allowed MCP call is rewritten in place into `call_mcp_tool(server, tool, arguments)`. It uses OcuTalon's own Streamable HTTP client (`Mcp.Client`), re-lists the tool just before `tools/call` and refuses a changed fingerprint without running it. It cuts the result through `OcuTalon.Tools.Result` and writes one `MCP` audit entry (server, tool and outcome only). It is offered only through `McpServersClass.ProxyToolSet()` and refused on the demo (`MCPDEMO`).
- **Approvals.** A risky or unclassified MCP call raises `Approval.Raise` kind `tool_call` with the exact call and fingerprint and no dry run. The replay goes `Decide` → the calling runner → a one-use grant → `call_mcp_tool` at the stored fingerprint, so it runs exactly once. Removing a server cancels its pending requests.
- **Source polls.** A `BackgroundCheck` row with `Kind` `source`, owned by the admin's session, created through `Watch.Ops` row methods after `McpOps` refuses non-read-only tools, then `CheckChanged`. `Checks` sends due polls as asynchronous `tool` requests through `Decide` with no model, so the gate, audit and agent step apply. New results become untrusted Items sent to `Intake`, and a result seen before is never an item again. Run time, last result and trace header id are published as `check` events. A tool that stops being Read-only stops its source with the `mcp.sourceStopped` notice. Coverage rows come only from `Checks.Coverage` and the all-clear only from `Checks.Render`.
- **Email tool.** `Classify(arguments)` extends the tool-classification convention for argument-dependent tools. `send_email` is not read-only, so it is refused in any turn holding untrusted content, self-addressed mail included. The safe path is `SendEmail` via `Commands.Submit` (origin `tool`, idempotency key). The risky path is a fix of kind `email` with a dry run of the exact recipients, subject and text, sent once by `FixExecutor`. The audit holds no address, subject or text.
- **Conventions.** Producers send catalog keys (`OcuTalon.Msg.Catalog.Watch`), never text. Admin notices go to `Ownership.AdminSessions()`. Tests use the loopback mock MCP server. New tool names go into `OcuTalon.Tools.Names` and the CI mock's scripts.

## UX & Interaction Patterns

- **Settings › Tools and MCP servers** (Lane B) has a server list and **Add server** (tools arrive Unclassified). Remove is confirmed. The tools table filters to "Unclassified only", and each tool has a radio group (Unclassified (risky), Read-only, Risky) that saves at once. A changed tool reverts to Unclassified with a banner and a chat notice.
- **Sources.** Only a Read-only tool can be a source, set from the "Use as a source" form (name, Arguments (JSON), Check every).
- **Tool-call approval card.** It reads "Run {tool} on {server}" with the exact inputs and "No dry run is available for this tool. Approving runs exactly this call once." A removed server's requests read "Canceled at {time}: the MCP server {server} was removed. Nothing was changed."
- **Notice keys:** `mcp.serverUnavailable`, `mcp.toolShadowsBuiltIn`, `mcp.toolChanged`, `mcp.replayToolChanged`, `mcp.sourceStopped`, `digest.notCheckedStopped`. Copy follows the accepted catalog wording.

## Cross-Story Dependencies

- **Status and order.** 22.2, 22.8, 22.9, 22.3, 22.4 and 22.7 are built. Remaining work is 22.5 (row, verbs, coverage, digest lead), then 22.11 (the poll run, Items and stop), then 22.6 (the tools half of the docs, against the current listing design), then 22.12 (the source half, after 22.5, 22.11 and Lane B's 21.5). Do not build 22.10.
- **Lane B.** 35.2 provides the MCP command verbs and `RestartRunners()`. 21.4 owns the MCP settings routes. 21.5 owns the source form and the rail's schedule line. 21.2/21.6 own `EmailIn`, `EmailOut` and `email.address`. 21.10 renders `mcp.replayToolChanged` on cards. 21.11's `BridgeSink` sends the email request's notifications. 36.2 adds the README/GUIDE link to the worked example and copies the classification sentence into the admin section.
- **Other epics.** Epic 35 (attach, mock server, `McpOps` names), Epic 30 (approved tool-call replay, the `tool` request path), Epic 17 (coverage list and digest) and Epic 14 (the security overview 22.6 regenerates) are prerequisites.
