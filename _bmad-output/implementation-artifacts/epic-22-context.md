# Epic 22 Context: Extend OcuTalon with MCP servers, governed like built-in tools (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

An admin adds an MCP server and its tools become OcuTalon tools under the same gate, classification, approval and audit as the built-in ones. Tools arrive unclassified (counted as risky), a changed tool loses its classification, and every call is audited. A read-only MCP tool can also be polled as a source: its new results become items, and its health shows on the daily digest's coverage list, with a worked Jira example. The epic also updates the security overview for MCP and adds a chat email tool that sends freely only to the user's own address. Judges and security reviewers check exactly two things here: adding a server never opens a path around approval or audit, and a source that was not checked never yields an all-clear.

## Stories

- Story 22.2: Classify MCP tools by server and name (done)
- Story 22.8: Classify MCP calls by fingerprint in the gate (done)
- Story 22.9: Bound MCP attach and listing with a timeout (done)
- Story 22.3: Call MCP tools only through the governed proxy (done)
- Story 22.4: Hold risky and unclassified MCP calls for approval (done)
- Story 22.7: Send email from the chat, safe to you and approved for anyone else (done)
- Story 22.5: Poll a read-only MCP tool as a source, Part A: row, verbs, coverage (done)
- Story 22.6: Document a worked Jira example and MCP governance, tools half (done)
- Story 22.13: Keep source names, staleness and repoints honest on the coverage list (done)
- Story 22.11: Run source polls through the governed proxy: the poll run only (the bridge, `Checks` and the stop notice) (next)
- Story 22.12: Document polling a Jira MCP tool as a source
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client (declined for the contest; do not build)

## Requirements & Constraints

- **Admin-only changes.** Servers, classifications and source polls change only from the settings page (origin `web_admin`). They never change from chat, an agent tool, an item, model output or a tool result, and every change is audited. On the online demo every MCP verb is refused, and no MCP endpoint, probe or poll runs.
- **Every MCP call is governed, polls included.** Each one gets the IRIS permission check, the pinned AI Hub policies, classification, approval when needed, one audit entry and an agent step. The step's label names the server and tool, never the arguments. MCP results are untrusted: they taint, and they can never approve, classify, change settings or add servers.
- **Poll runs.** Only a Read-only tool is polled. Each new result becomes an untrusted Item that gets its own attention decision, and a result seen before never becomes an item again. A run's time, last result and trace header id are recorded and published, so the page shows the source's schedule, last run and last result.
- **Baseline (ruled).** The first good run since the row's `CreatedAt` is a baseline: it records what it saw and sends no Item. Later runs send only what is new. A repoint moves `CreatedAt` (22.13), so the next good run is a fresh baseline.
- **Stop.** A source whose tool became unclassified or risky stops at its next due time. It shows as not checked with reason `stopped`, and admins are told once, in the accepted wording.
- **Coverage (built).** A source counts as checked when its latest run at or after `CreatedAt` falls within max(digest window, interval + 180 s) of the window's end. Otherwise it is not checked, with its reason (unreachable, error, timeout, stopped). Any not-checked entry leads the digest and blocks the all-clear.
- **Secrets and transport.** Only `https://` (plain `http://` only to this computer). Credentials exist only as `secret://` Wallet references read at call time, never in a message body, trace, log, test output, audit entry or record. Poll arguments refuse `secret://` and `@{`.
- **Docs (22.12).** Every sentence of public text must be true of the code at merge and goes to the Contest Planner as PUBLIC TEXT. No text may claim a hard MCP deadline: a trickling server can hold a request about 31 s past its 2 s bound.

## Technical Decisions

- **AI Hub lists, OcuTalon calls.** Servers attach through the Config Store entry `AI.MCP.OcuTalon_<server>`. Each request's manager adds only the servers whose 2 s `initialize` probe answered. `call_mcp_tool(server, tool, arguments)` uses the client bounds 2 s for initialize and list and 20 s for the call. It re-lists the tool and refuses a changed fingerprint without running it, cuts the result through `OcuTalon.Tools.Result`, and writes one `MCP` audit entry (server, tool and outcome only). `Bridge.Context.ToolFingerprint` is the only fingerprint form. The gate classifies `mcp:` toolrefs and direct proxy calls by (server, tool) and denies unregistered servers.
- **Source-poll row (built).** A source poll is a `OcuTalon.Data.BackgroundCheck` row with `Kind` `source`, owned by the admin's session. It holds `Server`, `Tool`, `Arguments` (JSON), `IntervalMinutes` (5 to 1,440), `DisplayName` and `CreatedAt`. Its natural key is (session, `source`, name), and it is removed with its server. Only `McpOps` creates or removes it, through `OcuTalon.Watch.Ops`, and then sends `CheckChanged`. The name "Mailbox" is reserved (`reserved_name`).
- **The poll run (22.11).** On the heartbeat `Tick`, `Checks` runs each due source row as a `tool` request (no model) through `Decide`, which calls `call_mcp_tool`, so the gate, the audit policy and the agent step apply. Only `Checks` writes the run fields (`LastRunAt`, `Result`, `Finding`, `LastRunHeaderId`, `NextDueAt`, and `Reported`, the JSON of what was already sent as Items). It writes them with one SQL `UPDATE` keyed by `Ref`, so a poll removed in the meantime is never re-created. A check that missed several runs runs once. A source is scheduled at its own interval; the 60 s step belongs to production watches. A run's trace is its `Tick`'s session in OcuTalon's namespace, and the `check` payload's trace target is `LastRunHeaderId`.
- **Run records.** `OcuTalon.Digest.Data.CheckRun` rows come from the `BackgroundCheck` update trigger (`Checks.Coverage.RecordRun`, one per `LastRunAt` change), and the reason is derived from the run's finding. A `stopped` reason reads as not checked. Findings are built from class-parameter phrases with counts as the only slots, never error or tool-result text.
- **Items.** New results go to `Intake` as `OcuTalon.Msg.Item`, with `SessionRef` set to the row's owner, `Provenance` `untrusted`, and the result as content.
- **Conventions.** Producers send catalog keys plus `Slots` (`OcuTalon.Msg.Catalog.Watch`), never text. Admin notices go to `Ownership.AdminSessions()`. `Bridge.Audit` is the only audit writer. Coverage rows come only from `Checks.Coverage.Build`, and the all-clear key only from `Checks.Render`. Tests use the loopback mock MCP server, and new tool names go into `OcuTalon.Tools.Names` and the CI mock's scripts.

## UX & Interaction Patterns

- **Background check row:** shows the source's name, schedule, last run and last result, with a trace link, all driven by `check` events.
- **Stop notice** `mcp.sourceStopped` (admins' chat): "The source {source} stopped polling at {time}, because its tool {tool} on {server} is no longer Read-only. Your digest lists it as not checked."
- **Digest line** `digest.notCheckedStopped`: "Not checked: {entry} (stopped polling at {time}: its tool is no longer Read-only)." A not-checked source leads the digest, and "What I checked" starts expanded.

## Cross-Story Dependencies

- **Order.** 22.5 and 22.13 (done) come first, then 22.11, then 22.12. Story 22.12 adds the source half of `docs/mcp-jira-example.md` ("new tickets assigned to me" as a source poll, plus its coverage entry and the release check's source half). It needs 22.11 and Lane B's 21.5 merged. Do not build 22.10.
- **Lane B.** 35.2 supplies the MCP verbs and `RestartRunners()`. 21.5 owns the source form and the rail's schedule line. 21.10 renders `mcp.replayToolChanged`, so until it merges, no public text describes the changed-tool replay path. 36.3 links the worked example once Epic 22 merges.
- **Merged prerequisites.** Epic 35 (attach, the mock server, `McpOps` names), Epic 30 (the `tool` request path and `Checks`' send to `Intake`), Epic 17 (the coverage list and digest) and Epic 14 (the security overview).
