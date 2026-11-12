# Epic 22 Context: Extend OcuTalon with MCP servers, governed like built-in tools (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make an admin-added MCP server's tools into OcuTalon tools under the same governance as built-in ones: one gate, admin classification by (server, tool name) checked against the tool's fingerprint at every call, approval for anything risky or unclassified (the default), and an audit entry and agent step for every call. A hung server must never hold a runner, so in the end OcuTalon lists and calls MCP tools through its own bounded client. A read-only MCP tool can be polled as a source. The epic also ships a worked Jira example, an updated security overview, and an email tool that sends to the user's own address freely and holds every other recipient for approval. Adding an MCP server must never open a path around governance.

## Stories

- Story 22.2: Classify MCP tools by server and name (done)
- Story 22.8: Classify MCP calls by fingerprint in the gate (done)
- Story 22.9: Bound MCP attach and listing with a timeout (done)
- Story 22.3: Call MCP tools only through the governed proxy
- Story 22.4: Hold risky and unclassified MCP calls for approval
- Story 22.5: Poll a read-only MCP tool as a source
- Story 22.6: Document a worked Jira example and MCP governance
- Story 22.7: Send email from the chat, safe to you and approved for anyone else
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client

## Requirements & Constraints

- **Online demo:** no real MCP server runs there. Every MCP admin surface is off and refused with a plain reason; nothing is added at run time.
- Only admins add, remove or classify servers and tools, from the settings page (origin `web_admin`). No chat request, agent tool, item content, model output or tool result can. `McpOps` re-checks the origin behind `CommandsIn`. Removing a server removes its tools and cancels its pending approval requests; every change is audited.
- Every MCP call, read-only included, gets the IRIS permission check, the pinned AI Hub policies, classification, approval when needed, an audit entry and an agent step. A test shows a risky MCP tool does not run without approval even when no platform policy covers it.
- A rug-pull (same name, changed description or schema) is caught, including a change between the turn's listing and the call.
- MCP results are untrusted: they taint the turn (then only read-only tools run), quarantine the next turn, and can never approve, classify, change settings or add servers. A Read-only MCP tool may run in a tainted turn but still sends its arguments to its server; the docs must say so plainly (sentence to the Contest Planner at 22.6's spec gate).
- An approved call runs exactly once, as approved; a replay whose fingerprint changed is refused and reported.
- All tool results of one model step stay within 10,000 tokens, cut and marked as cut.
- MCP servers only over verified `https://`, or loopback for development. Credentials only as `secret://` Wallet references; no secret value in any command, message, trace, log, test output, audit entry or record.
- **Coverage:** a source counts as checked only if its poll succeeded in the window; otherwise "not checked" with its reason (unreachable, error, timeout) and no all-clear. Fixture: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed."
- **Docs:** the worked example and the security overview use the same words to say an MCP tool that runs OS commands or arbitrary code must be classified risky, and document the mid-request residual until 22.10 lands.

## Technical Decisions

- **Fingerprint:** `OcuTalon.Bridge.Context.ToolFingerprint(server, name, description, parameters)`, SHA-256 hex over a canonical sorted-keys form. The same form at attach, in the turn map, in the proxy's call-time re-list and on approval rows.
- **In place (Epic 35, 22.2, 22.8):** `McpOps` is the only writer of `Mcp.Server` and `Mcp.ToolClassification`. The gate classifies an `mcp:` toolref only through `ClassificationClass.ClassifyMcp(source, name, fingerprint)` (missing, unclassified or mismatched is risky; an `mcp:` source always taints), denies an unregistered server `UNREGISTERED` first, replays included, and fails closed.
- **Bounds (22.9, done):** AI Hub gives no deadline against a silent server, so the agent's own manager holds no MCP server. `OcuTalon.Mcp.Client.Probe` sends an unauthenticated `initialize` (2 s, no redirect, any HTTP status is an answer) to admin-registered servers only, before every `AddTool`; a request's manager adds only servers that answered. A failed probe reports `unavailable` (`unreachable`) and rests the server 60 s per runner job. Attach error text can hold the credential, so it only picks a reason word. Until 22.4, the replay of an approved MCP call fails `ToolNotFound` (fail closed).
- **Mid-request residual:** a server that stops answering after its probe passed holds that runner job until it closes the connection. Accepted for now; 22.10 removes it by amending AD-21 so OcuTalon's own client both lists and calls. Gate, classification, approval and audit stay unchanged. 22.10 is the suggested home for DW-1210 (a server down at the agent build is never retried before the next build) and DW-1211 (per-job reports against one shared `Mcp.Server` row).
- **Governed proxy (22.3):** the gate rewrites every allowed MCP call into `call_mcp_tool(server, tool, arguments)`, offered only by a request's composed manager that holds an MCP server (`McpServersClass.ProxyToolSet()`), in no agent's `TOOLSETS`. `Mcp.Client` gains `tools/list` (2 s) and `tools/call` (20 s), verifies the peer, and re-lists the tool just before the call, refusing a changed fingerprint without running it. Results pass `OcuTalon.Tools.Result`. Each run writes one `MCP` audit entry (`called`/`refused`, server, tool, outcome only); the proxy never writes classification. Permission: the service user's `U` on the resource `ClassifyMcp` answers (`$SYSTEM.Security.CheckUserPermission`). A native call the gate cannot reroute is denied `MCPUSEPROXY`.
- **Approval and replay (22.4):** `Approval.Raise` kind `tool_call` holds the exact call (server, tool, canonical arguments) with no dry run; an `mcp:` row requires `ToolFingerprint`. On approval: a `tool` request through `Decide` to the calling runner, `StartExecution`, a one-use grant (toolref only when `McpServersClass.ServerOf(toolref)` equals the call's server), then a replay as `call_mcp_tool` on a governed manager holding only `ProxyToolSet()`; the agent's own manager is restored on every path. Changed fingerprint ends `changed`, mapped by `Core.BridgeSink` to `mcp.replayToolChanged`. No grant or a second replay gets `ToolAccessDenied`. The conversation gets a code-written note next turn, never the tool's result text. `McpOps` cancels a removed server's pending requests after the removal commits.
- **Source polls (22.5):** a `BackgroundCheck` row of `Kind` `source` (server, tool, arguments JSON, interval, `DisplayName`), owned by the admin's session, created and removed only through `OcuTalon.Watch.Ops`, which `McpOps` calls after refusing any non-read-only tool, then sends `CheckChanged`. `Checks` runs it as a `tool` request through `Decide` with no model, so it never reaches AI Hub's MCP client; new results become de-duplicated untrusted Items to `Intake`. A tool that turns unclassified or risky stops polling. The mailbox's outcomes come from `EmailIn`'s `emailPoll.reason`.
- **Email tool (22.7):** declares `Classify(arguments)`: safe only when every recipient is the session user's own `email.address` (owner `email.owner`), compared without case or surrounding spaces; 22.7 extends the spine's classification convention with this form. It must declare `TRUSTEDOUTPUT` 1, or `CommandsIn` refuses its tool-origin `SendEmail` in every ordinary turn. Safe path: `SendEmail` (`Recipients`, `Subject`, `Text`) via `Commands.Submit`, origin `tool`, idempotency key; `not_connected` when `EmailOut` is not running. Risky path: fix kind `OcuTalon.Fix.Kind.Email` (dry run shows to, subject, text; no `IncidentRef`), approval `FixKind` `email` with `FixParameters.recipients` equal to the send's recipients as a lower-cased set; `FixExecutor` sends once, origin `system`, with `ApprovalRef`. `EmailOut` enforces both paths and claims a system send by its approval. Limits: 1–20 recipients, subject 1–200, text 1–100,000 characters. Outcomes: `sent`, `already_sent`, `refused`, `not_connected`, `failed`, `not_available`. A mailbox signed in with Google or Microsoft 365 has a password-less credential, so its sends fail until Story 21.8 adds OAuth2 token use (DW-1179).
- **Audit and notices:** `OcuTalon.Bridge.Audit` is the only audit writer (redacted). Producers never render text: catalog keys (`OcuTalon.Msg.Catalog.Watch`) reach `Ownership.AdminSessions()`; tool-call and email-fix approval notices come from `Core.BridgeSink`.
- **Ownership and tests:** Lane A owns `OcuTalon.Mcp`, `.Tools`, `.Watch`, `.Fix`, `.Checks`, `.Digest`, the bridge, `ci/mock/scenarios/A/` and the security overview. Tests run against the loopback mock MCP server. Add `call_mcp_tool` and the email tool to `OcuTalon.Tools.Names` and the CI mock's scripts.

## UX & Interaction Patterns

- Settings › Tools and MCP servers (Lane B) shows each tool as Unclassified (risky), Read-only or Risky, saved at once and audited. A changed tool reverts to Unclassified with an admin notice. Only read-only tools can be source polls.
- A tool-call approval card reads "Run {tool} on {server}", with the exact inputs and the no-dry-run sentence. An email fix's dry run shows the exact text and every recipient.
- In a tainted turn, any suggestion that is not read-only, email included, is an offer, never a raised request.
- The agent step label names server and tool, never the arguments.
- Email results use `EmailOut`'s fixed sentences ("The email was sent.", "No outgoing mail server is connected, so the email wasn't sent."); the mailbox's not-checked reasons use the fixed mail-poll sentences.

## Cross-Story Dependencies

- Epic 35 supplies the contracts; Epics 14, 17 and 30 the security overview, the coverage list, and the `tool` request and replay path. 22.2, 22.8 and 22.9 are done.
- Lane B: 21.4 owns the MCP settings routes (stubs until then) and moves Wallet and Config Store writes into `McpOps`. 21.2/21.6 own `EmailIn`, `EmailOut` and `email.address`; 21.8 owns OAuth2 token use for send. 21.5 owns `BridgeSink`'s email-fix notices; until it merges, 22.7 checks only that the request has no `IncidentRef` and `IncidentManager` sends nothing. 22.4 adds one `BridgeSink` branch.
- **Order:** 22.3 (proxy, `tools/call`, re-list, `ProxyToolSet`) → 22.4 (replay, `ServerOf`, cancellation) → 22.5 (needs read-only and the proxy) → 22.6 (documents 22.2–22.5, 22.8, 22.9, the Read-only arguments sentence and the residual) → 22.7 (independent, shares the gate) → 22.10 (builds on 22.3's client and 22.9's bounds; amends AD-21).
- 22.6 supplies the worked example's path under `docs/`; Lane B's 36.2 adds the README link and copies the classification sentence.
