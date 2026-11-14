# Epic 22 Context: Extend OcuTalon with MCP servers, governed like built-in tools (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

An admin adds an MCP server and its tools become OcuTalon tools under the same gate, classification, approval and audit as built-in ones: tools arrive unclassified (counted as risky), a changed tool loses its classification, and every call is audited. A read-only MCP tool can also be polled as a source whose new results become items and whose health appears on the daily digest's coverage list, shown in a worked Jira example. The epic also updates the security overview for MCP and adds a chat email tool that sends freely only to the user's own address. Judges and security reviewers check exactly this: adding a server must never open a path around approval or audit, and a source that was not checked must never yield an all-clear.

## Stories

- Story 22.2: Classify MCP tools by server and name (done)
- Story 22.8: Classify MCP calls by fingerprint in the gate (done)
- Story 22.9: Bound MCP attach and listing with a timeout (done)
- Story 22.3: Call MCP tools only through the governed proxy (done)
- Story 22.4: Hold risky and unclassified MCP calls for approval (done)
- Story 22.7: Send email from the chat, safe to you and approved for anyone else (done)
- Story 22.5: Poll a read-only MCP tool as a source (Part A: row, verbs, coverage)
- Story 22.11: Run source polls through the governed proxy (Part B: the run, Items, stop)
- Story 22.6: Document a worked Jira example and MCP governance (tools half)
- Story 22.12: Document polling a Jira MCP tool as a source
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client (declined for the contest; do not build)

## Requirements & Constraints

- **Admin-only changes.** Servers, classifications and source polls change only from the settings page (origin `web_admin`), never from chat, an agent tool, an item, model output or a tool result; every change is audited. On the online demo every MCP verb is refused and no MCP endpoint runs.
- **Unclassified counts as risky.** A tool whose description or inputs change becomes Unclassified and admins are told. Annotations such as `readOnlyHint` are ignored; an MCP tool never takes a built-in's classification, and a server tool named like a built-in (including `call_mcp_tool`) is refused.
- **Every MCP call is governed**, polls included: IRIS permission check, pinned AI Hub policies, classification, approval when needed, audit entry and agent step (label names server and tool, never arguments). MCP results are untrusted: they taint the turn and can never approve, classify, change settings or add servers.
- **Sources.** Only a Read-only tool can be a source. New results become untrusted items with attention decisions; a result seen before is never an item again. A source whose tool becomes unclassified or risky stops polling, shows as not checked with that reason, and admins are notified.
- **Coverage.** Each source poll, and the connected mailbox (from `EmailIn`'s poll outcomes; fixture outcomes until Lane B's 21.2 merges), is a coverage entry that counts as checked only if its poll ran successfully in the window; otherwise not checked with its reason (unreachable, error, timeout, stopped). Any not-checked entry is named first and blocks the all-clear. Step 4 fixture: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed."
- **Secrets and transport.** `https://` only (loopback for development); credentials only as `secret://` IRIS Wallet references, never in a command, log, trace, test output, audit entry or record.
- **Docs.** The worked example and the security overview share one sentence: an MCP tool that runs operating-system commands or arbitrary code must be classified risky. They say plainly that a Read-only MCP tool still sends its arguments to its server, even in turns reading untrusted content. They document the measured limit (a slow server can hold a request about 31 s past its 2 s bound); no public text claims a hard MCP deadline. Until Story 21.10 merges, no release note, guide or More-to-try text describes the changed-tool replay path. Public text goes to the Contest Planner as PUBLIC TEXT, every sentence true of the code at merge.

## Technical Decisions

- **AI Hub lists, OcuTalon calls.** Servers attach via Config Store entry `AI.MCP.OcuTalon_<server>`; the agent's own manager holds none, and each request's manager adds only servers whose 2 s `initialize` probe answered. The mid-request stall is an accepted, documented residual.
- **Write ownership.** `McpOps` (Lane A) writes `OcuTalon.Mcp.Server` and `OcuTalon.Mcp.ToolClassification` rows and calls `OcuTalon.Core.SettingsOps.RestartRunners()`; `SettingsOps` (Lane B) writes the Config Store entry and Wallet secret; the per-server resource `OcuTalon_MCP_<server>` goes only through `Install.Step.Mcp.Grant`/`Revoke`; `Bridge.Audit` is the only audit writer.
- **Gate and proxy.** `Bridge.Context.ToolFingerprint` (SHA-256 over sorted-keys server, name, description, input schema) is the only fingerprint form. The gate recognises `toolref` `mcp:` first and classifies via `ClassificationClass.ClassifyMcp`; unregistered servers are denied (`UNREGISTERED`). Allowed calls are rewritten to `call_mcp_tool(server, tool, arguments)`, which re-lists and refuses a changed fingerprint, cuts the result through `OcuTalon.Tools.Result` (10,000 tokens per model step) and writes one `MCP` audit entry. Risky calls raise `Approval.Raise` kind `tool_call` with fingerprint and no dry run; replay runs exactly once.
- **Source-poll row.** `OcuTalon.Data.BackgroundCheck` with `Kind` `source`, owned by the admin's session, holding server, tool, arguments (JSON), interval (`IntervalMinutes`) and `DisplayName`. Created and removed only through `OcuTalon.Watch.Ops` row methods, which `McpOps` calls after refusing a non-read-only tool, then sends `CheckChanged`. Story 22.5 appends the columns; readers filtering `Kind` `production` stay unchanged. `Checks` alone writes run fields. Verbs: `SetSourcePoll` (`Server`, `Tool`, `Name`, `Arguments`, `IntervalMinutes`, `ActingUser`) and `RemoveSourcePoll` (`SourceRef`, `ActingUser`).
- **Poll run.** On the heartbeat tick, `Checks` sends each due poll as a `tool` request through `Decide` that calls `call_mcp_tool` with no model, so gate, audit policy and agent step apply. Each run writes one `OcuTalon.Digest.Data.CheckRun` row (`Result`, `Reason` for not-checked) and publishes run time, last result and trace header id as `check` events; new results go to `Intake`.
- **Coverage and all-clear.** Coverage rows come only from `OcuTalon.Checks.Coverage.Build` (whose sources section is empty until step 4); the all-clear key comes only from `OcuTalon.Checks.Render`. Rows use `{result, entry, finding, checkedAt}`; lines are `{key, slots}` with keys such as `digest.notCheckedUnreachable`, `digest.notCheckedStopped`.
- **Conventions.** Producers send catalog keys (`OcuTalon.Msg.Catalog.Watch`), never text. Admin notices go to `Ownership.AdminSessions()`. Tests use the loopback mock MCP server. New tool names go into `OcuTalon.Tools.Names` and the CI mock's scripts.

## UX & Interaction Patterns

- **Settings › Tools and MCP servers** (Lane B): the "Use as a source" form (Source name, Arguments (JSON), Check every) is offered only for Read-only tools ("Only a Read-only tool can be a source."); invalid JSON reads "Enter the arguments as a JSON object. Nothing was changed."
- **Background check row** shows the source's name, schedule, last run and last result with a trace link.
- **Digest:** a not-checked source leads, the "What I checked" section starts expanded, and the row is marked "Not checked". Stopped line: "Not checked: {entry} (stopped polling at {time}: its tool is no longer Read-only)."
- **Notice keys:** `mcp.sourceStopped` ("The source {source} stopped polling at {time}, because its tool {tool} on {server} is no longer Read-only. Your digest lists it as not checked."), plus the built `mcp.serverUnavailable`, `mcp.toolShadowsBuiltIn`, `mcp.toolChanged`, `mcp.replayToolChanged`. Copy follows the accepted catalog wording.

## Cross-Story Dependencies

- **Order.** 22.5 (row, verbs, coverage, digest lead) → 22.11 (poll run, Items, stop) → 22.6 (tools half of the docs, at `docs/mcp-jira-example.md`, plus the security overview regeneration: drop "can't connect to MCP servers", add `call_mcp_tool` and `OcuTalon_MCP_<server>`, name MCP calls as live data flows) → 22.12 (source half, after 22.5, 22.11 and Lane B's 21.5). Do not build 22.10.
- **Lane B.** 35.2 supplies the MCP verbs and `RestartRunners()`; 21.4 owns the MCP settings routes; 21.5 owns the source form and the rail's schedule line; 21.2 owns `EmailIn` poll outcomes; 21.10 renders `mcp.replayToolChanged`; 36.2 adds the README link to the worked example and copies the classification sentence into the admin section.
- **Other epics.** Epic 35 (attach, mock server, `McpOps` names), Epic 30 (the `tool` request path), Epic 17 (coverage list and digest, Stories 17.5–17.6) and Epic 14 (the security overview) are merged prerequisites.
