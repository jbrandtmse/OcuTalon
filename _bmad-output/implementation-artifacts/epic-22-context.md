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
- Story 22.11: Run source polls through the governed proxy (done)
- Story 22.14: SourceSet TestUpdate asserts the repoint RESET without clock dependence (done)
- Story 22.15: The tool list reports which tools changed, the `changed` flag (done)
- Story 22.12: Document polling a Jira MCP tool as a source (next)
- Story 22.10: List and offer MCP tools through OcuTalon's own bounded client (deferred; declined for the contest, do not build)

## Requirements & Constraints

- **Docs story (22.12).** The worked example `docs/mcp-jira-example.md` gains its source half: "new tickets assigned to me" set up as a source poll of a Read-only Jira search tool, the source's entry on the digest's coverage list (checked, or not checked with its reason), and the source half of the release check. Every sentence of new public text must be true of the code at merge and goes to the Contest Planner as PUBLIC TEXT. No text may claim a hard MCP deadline: a trickling server can hold a request about 31 s past its 2 s bound (the measured known limit already documented).
- **Release check (step 4, source half).** On a clean local install with a real Jira MCP server, new tickets assigned to the user become items with decisions in Visual Trace. The Contest Planner runs it in the hands-on pass; the doc must describe it so it can be followed.
- **Admin-only changes.** Servers, classifications and source polls change only from Settings (origin `web_admin`), never from chat, an agent tool, an item, model output or a tool result, and every change is audited. On the online demo every MCP verb is refused and no MCP endpoint, probe or poll runs.
- **Every MCP call is governed, polls included.** IRIS permission check, pinned AI Hub policies, classification, approval when needed, one audit entry and an agent step whose label names server and tool, never arguments. MCP results are untrusted: they taint and can never approve, classify, change settings or add servers. A Read-only tool still sends its arguments to its server.
- **Poll behaviour (built).** Only a Read-only tool is polled, at its own interval (5 to 1,440 minutes). Each new result becomes an untrusted Item with its own attention decision; a result seen before never becomes an item again. The first good run since the row's `CreatedAt` is a baseline that sends no Item. A repoint (server, tool or arguments) moves `CreatedAt`, so the next good run is a fresh baseline; changing only the interval or the name's case does not.
- **Stop (built).** A source whose tool became unclassified or risky stops at its next due time, shows as not checked with reason `stopped`, and admins are told once.
- **Coverage (built).** A source counts as checked when its latest run at or after `CreatedAt` falls within max(digest window, interval + 180 s) of the window's end; otherwise it is not checked with its reason (unreachable, error, timeout, stopped). Any not-checked entry leads the digest and blocks the all-clear. The name "Mailbox" is reserved for the connected mailbox.
- **Secrets and transport.** Only `https://` (plain `http://` only to this computer). Credentials exist only as `secret://` IRIS Wallet references read at call time, never in a body, trace, log, test output, audit entry or record. Poll arguments refuse `secret://` and `@{`.

## Technical Decisions

- **AI Hub lists, OcuTalon calls.** Servers attach through Config Store entry `AI.MCP.OcuTalon_<server>`; each request adds only servers whose 2 s `initialize` probe answered. `call_mcp_tool(server, tool, arguments)` bounds initialize and list at 2 s and the call at 20 s, re-lists and refuses a changed fingerprint, cuts the result through `OcuTalon.Tools.Result`, and writes one `MCP` audit entry. The gate classifies `mcp:` toolrefs and direct proxy calls by (server, tool) and denies unregistered servers.
- **Source-poll row.** An `OcuTalon.Data.BackgroundCheck` row with `Kind` `source`, owned by the admin's session (`Server`, `Tool`, `Arguments`, `IntervalMinutes`, `DisplayName`, `CreatedAt`), removed with its server. Only `McpOps` creates or removes it, through `OcuTalon.Watch.Ops`.
- **The poll run.** On the heartbeat `Tick`, `Checks` runs each due source as a `tool` request (no model) through `Decide`, which calls `call_mcp_tool`. Only `Checks` writes the run fields, with one SQL `UPDATE` keyed by `Ref`. New results go to `Intake` as `OcuTalon.Msg.Item` (`Provenance` `untrusted`, `SessionRef` the row's owner). A run's trace is its `Tick`'s session; the `check` payload's trace target is `LastRunHeaderId`.
- **Changed tools.** A tool McpOps cleared after a fingerprint change has `Changed` = 1 and `Tools(server)` reports `changed: true` until an admin classifies it again.
- **All-clear from code only.** Coverage rows come only from `Checks.Coverage.Build` and the all-clear key only from `Checks.Render`; model text can never produce or alter them. Docs must not paraphrase the reserved sentences into something the code does not emit.

## UX & Interaction Patterns

- **Settings › Tools and MCP servers:** server list, tools table with classification controls and "Unclassified only" filter; a read-only tool can be set as a source poll, after which it joins the digest's coverage list. The source-poll form's texts come from the Message Catalog block "Settings and requests (step 4)".
- **Background check row:** the source's name, schedule, last run and last result, with a trace link.
- **Digest failure wording (Jira unreachable):** "Not checked: Jira (unreachable since 02:10). Everything else I checked passed." No all-clear, and "What I checked" starts expanded with the Jira row marked "Not checked". Inside digest sentences the mailbox reads "the mailbox"; as a label it reads "Mailbox".
- **Stop notice** `mcp.sourceStopped`: "The source {source} stopped polling at {time}, because its tool {tool} on {server} is no longer Read-only. Your digest lists it as not checked." Digest line `digest.notCheckedStopped`: "Not checked: {entry} (stopped polling at {time}: its tool is no longer Read-only)."

## Cross-Story Dependencies

- **22.12's prerequisites are met:** 22.5, 22.11 and 22.13 are done, and Lane B's 21.5 (the source form and the rail's schedule line) is done. Describe the source setup as 21.5's form actually presents it.
- **Keep the example's path and shared sentences stable.** Lane B's 36.3 (done) links `docs/mcp-jira-example.md` from GUIDE.md "For admins and developers" and copies its sentence that an MCP tool running operating-system commands or arbitrary code must be classified risky; do not move the file or reword that sentence.
- **Changed-tool replay.** 21.10 (done) renders `mcp.replayToolChanged`; describe that path only if the text is true of the merged code.
- **Merged prerequisites.** Epic 35 (attach, the mock server, `McpOps` names and verbs), Epic 30 (the `tool` request path and `Checks`' send to `Intake`), Epic 17 (the coverage list and digest) and Epic 14 (the security overview).
