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
- Story 22.5: Poll a read-only MCP tool as a source, Part A: row, verbs, coverage (done)
- Story 22.6: Document a worked Jira example and MCP governance, tools half (done)
- Story 22.11: Run source polls through the governed proxy, Part B: the run, Items, stop (next)
- Story 22.12: Document polling a Jira MCP tool as a source
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client (declined for the contest; do not build)

## Requirements & Constraints

- **Admin-only changes.** Servers, classifications and source polls change only from the settings page (origin `web_admin`), never from chat, an agent tool, an item, model output or a tool result; every change is audited. On the online demo every MCP verb is refused and no MCP endpoint or poll runs.
- **Every MCP call is governed, polls included:** IRIS permission check, pinned AI Hub policies, classification, approval when needed, one audit entry and an agent step (label names server and tool, never arguments). MCP results are untrusted: they taint, and can never approve, classify, change settings or add servers.
- **Source runs.** Only a Read-only tool is polled. Each new result becomes an untrusted Item with its own attention decision; a result seen before never becomes an item again. A poll whose tool became unclassified or risky stops at its next due time, shows as not checked with reason `stopped`, and admins are told once. Repointing a source (server, tool or arguments) must reset its seen-results state and run history (DW-1328).
- **Coverage.** A source counts as checked only if its poll ran successfully within its interval plus 180 s; otherwise not checked with its reason (unreachable, error, timeout, stopped). Any not-checked entry leads the digest and blocks the all-clear.
- **Secrets and transport.** `https://` only (plain `http://` only to this computer); credentials only as `secret://` Wallet references read at call time, never in a message body, trace, log, test output, audit entry or record. Poll arguments refuse `secret://` and `@{`.
- **Docs.** Public text is every sentence true of the code at merge, brought to the Contest Planner as PUBLIC TEXT; no text claims a hard MCP deadline (a slow server can hold a request about 31 s past its 2 s bound).

## Technical Decisions

- **AI Hub lists, OcuTalon calls.** Servers attach via Config Store `AI.MCP.OcuTalon_<server>`; each request's manager adds only servers whose 2 s `initialize` probe answered. `call_mcp_tool(server, tool, arguments)` (client bounds 2 s initialize/list, 20 s call) re-lists and refuses a changed fingerprint unrun, cuts the result through `OcuTalon.Tools.Result`, and writes one `MCP` audit entry (server, tool, outcome only). `Bridge.Context.ToolFingerprint` is the only fingerprint form; the gate classifies `mcp:` toolrefs via `ClassifyMcp` and denies unregistered servers.
- **Source-poll row (built in 22.5).** `OcuTalon.Data.BackgroundCheck` `Kind` `source`, owned by the admin's session, with `Server`, `Tool`, `Arguments` (JSON), `IntervalMinutes` (5 to 1,440), `DisplayName`; natural key (session, `source`, name); removed with its server. Created/removed only by `McpOps` (`SetSourcePoll`, `RemoveSourcePoll`) through `OcuTalon.Watch.Ops`, which then sends `CheckChanged`.
- **Poll run (22.11).** On the heartbeat `Tick`, `Checks` runs each due source row as a `tool` request (no model) through `OcuTalon.Bridge.Process.Decide` calling `call_mcp_tool`, so the gate, audit policy and agent step apply. `Checks` alone writes run fields (`LastRunAt`, `Result`, `Finding`, `LastRunHeaderId`, `NextDueAt`, `Reported` = JSON of what was already sent as Items) with one SQL `UPDATE` keyed by `Ref`, so a poll removed meanwhile is never re-created. A run's trace is its `Tick`'s session; each run writes one `OcuTalon.Digest.Data.CheckRun` row (`Result`, `Reason` when not checked) and publishes `check` events carrying run time, last result and trace header id. The planning docs do not fix whether a source's first run is a baseline (production watch) or reports (queue row); settle it at the spec gate.
- **Items.** New results go to `Intake` as `OcuTalon.Msg.Item` with `SessionRef` the row's owner, `Provenance` `untrusted` and content; code-fixed notice text travels as `CatalogKey` plus `Slots`.
- **Coverage and all-clear.** Coverage rows come only from `OcuTalon.Checks.Coverage.Build`, the all-clear key only from `OcuTalon.Checks.Render`; lines are `{key, slots}` (e.g. `digest.notCheckedUnreachable`, `digest.notCheckedStopped`).
- **Conventions.** Producers send catalog keys (`OcuTalon.Msg.Catalog.Watch`), never text. Admin notices go to `Ownership.AdminSessions()`. `Bridge.Audit` is the only audit writer. Tests use the loopback mock MCP server; new tool names go into `OcuTalon.Tools.Names` and the CI mock's scripts.

## UX & Interaction Patterns

- **Background check row** shows the source's name, schedule, last run and last result with a trace link (driven by the `check` events).
- **Digest:** a not-checked source leads, "What I checked" starts expanded, the row is marked "Not checked". Stopped line: "Not checked: {entry} (stopped polling at {time}: its tool is no longer Read-only)."
- **Stop notice** `mcp.sourceStopped`: "The source {source} stopped polling at {time}, because its tool {tool} on {server} is no longer Read-only. Your digest lists it as not checked." Copy follows the accepted catalog wording.

## Cross-Story Dependencies

- **Order.** 22.5 (done) → 22.11 (poll run, Items, stop) → 22.12 (source half of `docs/mcp-jira-example.md`: "new tickets assigned to me" as a source poll and its digest entry; needs 22.5, 22.11 and Lane B's 21.5). Do not build 22.10.
- **Lane B.** 35.2 supplies the MCP verbs and `RestartRunners()`; 21.5 owns the source form and the rail's schedule line; 21.2 owns `EmailIn` poll outcomes; 21.10 renders `mcp.replayToolChanged` (until it merges, no public text describes the changed-tool replay path); 36.2 adds the README link to the worked example.
- **Other epics.** Epic 35 (attach, mock server, `McpOps` names), Epic 30 (the `tool` request path), Epic 17 (coverage list and digest) and Epic 14 (security overview) are merged prerequisites.
