# Epic 22 Context: Extend OcuTalon with MCP servers, governed like built-in tools (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make an admin-added MCP server's tools into OcuTalon tools under the same governance as built-in ones: one gate, admin classification by (server, tool name) checked against the tool's fingerprint at every call, approval for anything risky or unclassified, and an audit entry and agent step for every call. A hung server must never hold a runner, so OcuTalon ends up listing and calling MCP tools through its own bounded client. A read-only MCP tool can be polled as a source on the digest's coverage list. The epic also ships a worked Jira example, the security overview update, and an email tool that sends freely only to the user's own address.

## Stories

- Story 22.2: Classify MCP tools by server and name (done)
- Story 22.8: Classify MCP calls by fingerprint in the gate (done)
- Story 22.9: Bound MCP attach and listing with a timeout (done)
- Story 22.3: Call MCP tools only through the governed proxy (done)
- Story 22.4: Hold risky and unclassified MCP calls for approval (done)
- Story 22.5: Poll a read-only MCP tool as a source (Part A: the row, the verbs, coverage, the digest)
- Story 22.11: Run source polls through the governed proxy (Part B of 22.5; not yet in the epics file)
- Story 22.6: Document a worked Jira example and MCP governance
- Story 22.7: Send email from the chat, safe to you and approved for anyone else
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client

## Requirements & Constraints

- **Online demo (standing rule for every Epic 22 gate):** MCP is fully off there, pinned by a test. `McpOps` refuses every MCP verb (`not_allowed`), `Mcp.Attach.Servers()` lists no server, the proxy refuses with `MCPDEMO` before any outbound request, and no source row can exist.
- Only admins add, remove or classify servers and tools, or set source polls, from the settings page (origin `web_admin`); no chat request, agent tool, item content, model output or tool result can. Every change is audited.
- Every MCP call, polls included, gets the permission check, the pinned AI Hub policies, classification at the live fingerprint, an audit entry and an agent step ("Running {tool} on {server}", never the arguments).
- MCP results are untrusted: they taint the turn, quarantine the next, and can never approve, classify, change settings or add servers. A Read-only MCP tool still sends its arguments to its server, even in tainted turns; the docs must say so plainly.
- All tool results of one model step stay within 10,000 tokens, cut and marked as cut. Servers only over verified `https://` (loopback for development); credentials only as `secret://` references, never in any message, trace, log, test output, audit entry or record.
- **Coverage:** a source counts as checked only if its runs in the window all passed; otherwise "not checked" with its reason and no all-clear. Fixture: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed."
- **Docs:** the worked example and the security overview use the same words to say an MCP tool that runs OS commands or arbitrary code must be classified risky, and document the mid-request residual until 22.10 lands.

## Technical Decisions

- **In place (22.2, 22.8, 22.9):** `McpOps` alone writes `Mcp.Server` and `Mcp.ToolClassification`. `Bridge.Context.ToolFingerprint` (SHA-256 over a sorted-keys form) is the one form everywhere. The gate classifies `mcp:` toolrefs only through `ClassifyMcp(source, name, fingerprint)`, denies an unregistered server `UNREGISTERED`, and fails closed. The agent's own manager holds no MCP server; each request's manager adds only servers whose 2 s `initialize` probe answered.
- **Built by 22.3:** `Mcp.Client` does `tools/list` (2 s) and `tools/call` (20 s), verifies the peer. `Mcp.Proxy` / `call_mcp_tool` is offered only via `McpServersClass.ProxyToolSet()`, re-lists before calling and refuses a changed fingerprint unrun, cuts through `Tools.Result`, and writes one `MCP` audit entry (server, tool, outcome). The gate rewrites the allowed call in place (measured: AI Hub then sends only its own `tools/list`, never `tools/call`); no `MCPUSEPROXY` fallback. Permission is the service user's `U` on the resource `ClassifyMcp` returns.
- **Built by 22.4:** `Approval.Raise` kind `tool_call` holds the exact call with a required `ToolFingerprint`, no dry run. Replay goes through `Decide` to the calling runner, one-use grant, then `call_mcp_tool` on a proxy-only manager (`Agent.ProxyManager`), agent manager restored on every path; a changed tool ends `changed` (`mcp.replayToolChanged`). `McpOps` calls `Approval.CancelPending` after a server's removal commits. An MCP call with no fingerprint in the turn map is denied `FAILED` and raises no request; an unknown toolref is `UNREGISTERED` (whether that satisfies "held" is pending with the Planner, DW-1240).
- **Source polls (22.5 Part A):** `SetSourcePoll`/`RemoveSourcePoll` in `McpOps`, refusing non-read-only tools; a `BackgroundCheck` row of `Kind` `source` (server, tool, arguments JSON, interval, `DisplayName`) through `Watch.Ops` row methods, then `CheckChanged`. Limits: interval 5–1,440 minutes, arguments a JSON object up to 4,000 characters with no `secret://` or `@{`. Removing a server removes its sources. `Checks.Coverage` lists sources and the mailbox (from `StatusMark.Get("emailPoll")`); the digest leads with not-checked lines when nothing failed. The `check` payload gains `intervalMinutes`.
- **Source polls (22.11, Part B):** `Checks` sends each due source an asynchronous `tool` request through `Decide`, provenance `untrusted`, carrying only the source's Ref, on TriageAgent, with no model and no Decision row. The bridge's new `Poll` class runs one `call_mcp_tool` on a proxy-only manager, the call map seeded from a live listing by OcuTalon's own client (`McpServersClass.PollCall`). Only a read-only tool runs; anything else is denied `UNTRUSTED`, never held. The whole text answer is one result, de-duplicated by SHA-256; the first successful run is a baseline. New results become untrusted Items to `Intake`. A tool no longer Read-only stops the source (runs recorded with Reason `stopped`, one `mcp.sourceStopped` to admins); it resumes once Read-only again. "Due", "seen" and "stopped" live on the row.
- **Email tool (22.7):** `Classify(arguments)`: safe only when every recipient is the session user's own `email.address` (case and spaces ignored); extends the spine's classification convention. Declares `TRUSTEDOUTPUT` 1. In a tainted turn any non-read-only suggestion, email included, is an offer, never a raised request. Safe path: `SendEmail` via `Commands.Submit`, origin `tool`, idempotency key. Risky path: fix kind `OcuTalon.Fix.Kind.Email` (dry run: to, subject, text; no `IncidentRef`), approval `FixKind` `email` with `FixParameters.recipients`; `FixExecutor` sends once, origin `system`, with `ApprovalRef` (DW-1164). Limits: 1–20 recipients, subject 1–200, text 1–100,000 characters. Google/Microsoft 365 mailboxes fail to send until 21.8 (DW-1179).
- **Own client (22.10):** OcuTalon's client lists and calls; AI Hub's MCP client is no longer used; amend AD-21's "AI Hub lists, OcuTalon calls". Carries DW-1210, DW-1211 and DW-1221 (no total per-request deadline; a trickling server can outlast the call bound). Keep `PollCall`'s listing on OcuTalon's client.
- **Audit, notices, ownership:** `Bridge.Audit` is the only audit writer. Producers send catalog keys, never text (`Msg.Catalog.Watch`, to `Ownership.AdminSessions()`). Lane A owns `OcuTalon.Mcp`, `.Tools`, `.Watch`, `.Fix`, `.Checks`, `.Digest`, the bridge, and the security overview. Tests use the loopback mock MCP server. Add new tool names to `OcuTalon.Tools.Names` and the CI mock's scripts.

## UX & Interaction Patterns

- Settings › Tools and MCP servers (Lane B) classifies each tool Unclassified (risky), Read-only or Risky; a changed tool reverts to Unclassified with a banner and a chat notice. Only Read-only tools can be sources ("Use as a source" form; the rail's "Polled every {n} minutes" is proposed for 21.5).
- A tool-call approval card reads "Run {tool} on {server}", with exact inputs and the no-dry-run sentence. A removed server's requests show "Canceled at {time}: the MCP server {server} was removed. Nothing was changed."
- Email results use `EmailOut`'s fixed sentences ("The email was sent."); an email fix's dry run shows the exact text and every recipient.

## Cross-Story Dependencies

- **Order:** 22.5 → 22.11 → 22.6 (documents 22.2–22.5, 22.8, 22.9, 22.11, the Read-only arguments sentence and the residual) → 22.7 (independent, shares the gate) → 22.10. The orchestrator ruled contended `Mcp/Ops.cls` edits in the order 22.4 → 21.4 → 22.5.
- Lane B: 21.4 owns the MCP settings routes; 21.5 the Settings source form, the rail's schedule line and `BridgeSink`'s email-fix notices (until it merges, 22.7 checks only no `IncidentRef` and no `IncidentManager` send); 21.2/21.6 own `EmailIn`, `EmailOut` and `email.address`. DW-1232 (`mcp.replayToolChanged` renders no text on web and phone cards) awaits a ruling.
- Docs: 0.30 moved the README's detail sections, "New since 1.0.0" and "For admins and developers" included, into GUIDE.md. 22.6 supplies the worked example's path under `docs/`; Lane B's 36.2 adds the link and copies the classification sentence into the admin section, now GUIDE.md's. Any "New since" line for MCP goes in GUIDE.md, only as the Planner rules.
