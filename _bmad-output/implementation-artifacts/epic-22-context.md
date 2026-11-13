# Epic 22 Context: Extend OcuTalon with MCP servers, governed like built-in tools (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make an admin-added MCP server's tools into OcuTalon tools under the same governance as built-in ones: one gate, admin classification by (server, tool name) checked against the tool's fingerprint at every call, approval for anything risky or unclassified, and an audit entry and agent step for every call. A read-only MCP tool can be polled as a source on the digest's coverage list. It also ships a worked Jira example, the security overview update, and an email tool that sends freely only to the user's own address. For the contest AD-21 stays (AI Hub lists, OcuTalon calls); a server stalling mid-request is a documented, measured known limit.

## Stories

- Story 22.2: Classify MCP tools by server and name (done)
- Story 22.8: Classify MCP calls by fingerprint in the gate (done)
- Story 22.9: Bound MCP attach and listing with a timeout (done, CI pending)
- Story 22.3: Call MCP tools only through the governed proxy (done, CI pending)
- Story 22.4: Hold risky and unclassified MCP calls for approval (done, CI pending)
- Story 22.5: Poll a read-only MCP tool as a source (Part A: the row, the verbs, coverage, the digest)
- Story 22.11: Run source polls through the governed proxy (Part B of 22.5; not yet in the epics file)
- Story 22.6: Document a worked Jira example and MCP governance
- Story 22.7: Send email from the chat, safe to you and approved for anyone else
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client (DEFERRED: the owner decides after the contest; do not build)

## Requirements & Constraints

- **Online demo (standing rule, every gate):** MCP is fully off, pinned by a test: `McpOps` refuses every verb (`not_allowed`), `Mcp.Attach.Servers()` lists none, the proxy refuses `MCPDEMO` before any outbound request, no source row can exist.
- Only admins add, remove or classify servers and tools, or set source polls, from the settings page (origin `web_admin`); nothing from chat, agents, items, models or tool results can. Every change is audited.
- Every MCP call, polls included, gets the permission check, the pinned AI Hub policies, classification at the live fingerprint, an audit entry and an agent step ("Running {tool} on {server}", never the arguments).
- MCP results are untrusted: they taint the turn, quarantine the next, and can never approve, classify, change settings or add servers. A Read-only MCP tool still sends its arguments to its server, even in tainted turns; the docs must say so plainly.
- All tool results of one model step stay within 10,000 tokens, cut and marked as cut. Servers only over verified `https://` (loopback for development); credentials only as `secret://` references, never in any message, trace, log, test output, audit entry or record.
- **Coverage:** a source counts as checked only if its runs in the window all passed; otherwise "not checked" with its reason and no all-clear. Fixture: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed."
- **Docs (22.6):** the worked example and the security overview use the same words to say an MCP tool that runs OS commands or arbitrary code must be classified risky. They document the mid-request residual (a server that stops answering after its probe passed holds that runner) and the measured known limit: a slow server can hold a request about 31 s past the 2 s bound. No text claims a hard MCP deadline. Until Story 21.10 merges, no release notes, guide or More-to-try text describes the changed-tool replay path.

## Technical Decisions

- **In place (22.2, 22.8, 22.9):** `McpOps` alone writes `Mcp.Server` and `Mcp.ToolClassification`. `Bridge.Context.ToolFingerprint` (SHA-256 over a sorted-keys form) is the one form everywhere. The gate classifies `mcp:` toolrefs only through `ClassifyMcp(source, name, fingerprint)`, denies an unregistered server `UNREGISTERED`, and fails closed. The agent's own manager holds no MCP server; each request's manager adds only servers whose 2 s `initialize` probe answered.
- **Built by 22.3:** `Mcp.Client` does `tools/list` (2 s) and `tools/call` (20 s) and verifies the peer. `Mcp.Proxy` / `call_mcp_tool` is offered only via `McpServersClass.ProxyToolSet()`. It re-lists before calling, refuses a changed fingerprint without running it, cuts through `Tools.Result`, and writes one `MCP` audit entry (server, tool, outcome). The gate rewrites the allowed call in place (AI Hub then sends only `tools/list`, never `tools/call`); no `MCPUSEPROXY` fallback. Permission is the service user's `U` on the resource `ClassifyMcp` returns. `Mcp.Client` has no total per-request deadline (per-read timeout): the recorded known limit, not to be fixed here.
- **Built by 22.4:** `Approval.Raise` kind `tool_call` holds the exact call with a required `ToolFingerprint`, no dry run. Replay: `Decide` to the calling runner, one-use grant, `call_mcp_tool` on a proxy-only manager (`Agent.ProxyManager`), agent manager restored on every path; a changed tool ends `changed` (`mcp.replayToolChanged`). `McpOps` calls `Approval.CancelPending` after a server's removal commits. An unknown toolref is DENIED, never held: `UNREGISTERED` when classification does not know the server, `FAILED` when the turn map holds no fingerprint (no request raised).
- **Source polls (22.5 Part A):** `SetSourcePoll`/`RemoveSourcePoll` in `McpOps`, refusing tools that aren't read-only; a `BackgroundCheck` row of `Kind` `source` (server, tool, arguments JSON, interval, `DisplayName`) through `Watch.Ops` row methods, then `CheckChanged`. Limits: interval 5–1,440 minutes, arguments a JSON object up to 4,000 characters with no `secret://` or `@{`. Removing a server removes its sources. `Checks.Coverage` lists sources and the mailbox (from `StatusMark.Get("emailPoll")`); the digest leads with not-checked lines when nothing failed. The `check` payload gains `intervalMinutes`.
- **Source polls (22.11, Part B):** `Checks` sends each due source an asynchronous `tool` request through `Decide`, provenance `untrusted`, carrying only the source's Ref, on TriageAgent, with no model and no Decision row. The bridge's new `Poll` class runs one `call_mcp_tool` on a proxy-only manager, the call map seeded from a live listing by OcuTalon's own client (`McpServersClass.PollCall`). Only a read-only tool runs; anything else is denied `UNTRUSTED`, never held. The whole text answer is one result, de-duplicated by SHA-256; the first successful run is a baseline. New results become untrusted Items sent to `Intake`. A tool no longer Read-only stops the source (Reason `stopped`, one `mcp.sourceStopped` to admins) until it is Read-only again. "Due", "seen" and "stopped" live on the row.
- **Name collisions (22.6, DW-1228):** a test confirms that a server tool named `call_mcp_tool`, or any built-in tool name, is refused under the current design ("Refused: a built-in tool has this name"); fix narrowly if it is not.
- **Email tool (22.7, approved with conditions):** `send_email`'s `Classify(arguments)` makes it safe only when every recipient is the session user's own `email.address` (case and spaces ignored). Extends the spine's classification convention; the forced copy of the own-address check is approved (DW-1256 unifies later). `send_email` is not read-only: in any turn with untrusted content it is refused `UNTRUSTED`, self-addressed included (injection case pinned), and described as an offer, never raised. Safe path: `SendEmail` via `Commands.Submit`, origin `tool`, idempotency key. Risky path: fix kind `OcuTalon.Fix.Kind.Email` (dry run: to, subject, text; no `IncidentRef`), approval `FixKind` `email` with `FixParameters.recipients`; `FixExecutor` sends once, origin `system`, with `ApprovalRef` (DW-1164). The audit holds no address, subject or text; the card shows the exact recipients, subject and text. Limits: 1–20 recipients, subject 1–200 characters, text 1–100,000. Google/Microsoft 365 mailboxes fail to send until 21.8 (DW-1179).
- **Audit, notices, ownership:** `Bridge.Audit` is the only audit writer. Producers send catalog keys, never text (`Msg.Catalog.Watch`, to `Ownership.AdminSessions()`). Lane A owns `OcuTalon.Mcp`, `.Tools`, `.Watch`, `.Fix`, `.Checks`, `.Digest`, the bridge, and the security overview. Tests use the loopback mock MCP server. Add new tool names to `OcuTalon.Tools.Names` and the CI mock's scripts.

## UX & Interaction Patterns

- Settings › Tools and MCP servers (Lane B) classifies each tool Unclassified (risky), Read-only or Risky; a changed tool reverts to Unclassified with a banner and a chat notice. Only Read-only tools can be sources ("Use as a source" form; the rail's "Polled every {n} minutes" is proposed for 21.5).
- A tool-call approval card reads "Run {tool} on {server}", with exact inputs and the no-dry-run sentence. A removed server's requests show "Canceled at {time}: the MCP server {server} was removed. Nothing was changed."
- Email results use `EmailOut`'s fixed sentences ("The email was sent.").

## Cross-Story Dependencies

- **Order:** 22.5 → 22.11 → 22.6 (planned against the current AD-21; documents 22.2–22.5, 22.8, 22.9, 22.11) → 22.7 (independent, shares the gate). 22.10 is not built. The orchestrator ruled contended `Mcp/Ops.cls` edits in the order 22.4 → 21.4 → 22.5.
- **22.7's merge waits for Lane C's Story 21.13**, which fixes DW-1244 (`EmailOut` ignores the idempotency key); 22.7 does not edit `Channel/Email/**`. Its no-incident notifications come from Lane B's `BridgeSink` (Story 21.11); until 21.11 merges, tests check only no `IncidentRef` and no `IncidentManager` send.
- Lane B: 21.4 owns the MCP settings routes; 21.5 the Settings source form and the rail's schedule line; 21.2/21.6 own `EmailIn`, `EmailOut` and `email.address`; 21.10 renders `mcp.replayToolChanged` on web and phone cards (DW-1232).
- Docs: the README's detail sections, "New since 1.0.0" and "For admins and developers" included, live in GUIDE.md. 22.6 supplies the worked example's path under `docs/`; Lane B's 36.2 adds the link and copies the classification sentence into GUIDE.md's admin section. Any "New since" line for MCP goes in GUIDE.md, only as the Planner rules.
