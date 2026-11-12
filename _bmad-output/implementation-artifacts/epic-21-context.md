# Epic 21 Context: Email, webhooks and MCP settings (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This is Lane B's step 4 feature epic. The email half is built. An admin connects a real mailbox (POP3 and SMTP, with a password or with a Gmail or Microsoft 365 OAuth2 sign-in), each new email becomes an untrusted item with its own attention decision, and OcuTalon emails the user, the daily digest included. What remains is the MCP half. Admins add, remove and classify MCP servers and their tools in Settings, see which changed tool was made Unclassified, set Read-only tools up as source polls, and answer held tool calls and standalone fix requests with full knowledge of what will run, on every channel. Webhooks shipped in Story 35.3 and Story 21.1 became Story 35.2, so the title's webhook part has no work here.

## Stories

- Story 21.2: Read a mailbox over POP3 (done)
- Story 21.6: Send email over SMTP (done)
- Story 21.7: Send the daily digest by email (done)
- Story 21.3: Register the mail OAuth2 client and sign in (done)
- Story 21.8: Read and send mail with the OAuth2 sign-in (done; local commit, not pushed while the Planner's CI hold lasts)
- Story 21.4: Add, remove and classify MCP servers and tools in Settings (ruled spec, ready-for-dev)
- Story 21.9: Show the changed-tool banner in Settings (split from 21.4)
- Story 21.5: Set up source polls (ruled spec, ready-for-dev; its approval criteria moved to 21.10)
- Story 21.10: Answer tool-call and standalone approval requests on every channel (next to plan)

## Requirements & Constraints

- **Online demo safety (standing rule, which overrides any "preconfigured" or "allow-listed" wording):** no real mail, OAuth or MCP endpoint ever runs on the demo. Every MCP settings route (and `ListMcpServers`) answers 409 `not_available` with the accepted line "MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install." before it reads the body. The section shows that line in place of its content, and real-HTTP tests pin all of this.
- **Secrets:** every secret field is write-only, and any admin value containing `@{` is refused. No secret ever appears in a command, log, trace, audit entry, global, GET or test output. Only references do. MCP secrets live in the IRIS Wallet, referenced from the Config Store entry `AI.MCP.OcuTalon_<server>`. A server added with a secret at a non-loopback `http://` address is refused with `MESSAGEADDRESS` (a Planner condition on 21.4).
- **Sources:** only a Read-only tool can be a source. A source belongs to the admin's session. The web DELETE removes only the caller's own source (404 for anyone else's), and the GET never returns a source's arguments.
- **Approvals:** first answer wins on every channel. A held tool call shows exactly what it will run. A standalone fix shows "Why:" and a dry run with the exact text and every recipient. A cancelled request stops its buttons everywhere.
- **Only accepted text ships.** New public text goes to the author first. 21.4's T1-T11 and 22.5's rail line "Polled every {n} minutes" (now in 21.5) are approved.
- **CI** uses only the CI mock: POP3/SMTP stubs with XOAUTH2, the fake OAuth2 server, and the MCP mock (`Test.Mcp.Mock`). It never reaches a real provider and never sends real email.

## Technical Decisions

- **Lanes:** Lane B owns `Core/**`, `Web/**`, `Channel/**`, `Data/**` (its own tables), `Msg/Command/**`, `Msg/Catalog/Core.cls` and `web/`. Lane A owns `Mcp/**`, `Fix/**`, `Digest/**`, `Tools/Email*`, `src/bridge/**` and `Install/**`.
- **Commands (AD-1):** every change is a production message. An admin-checked `/v1/settings` route submits it with origin `web_admin`, and the REST process writes nothing. Secrets reach their writer through `Core.SecretHandoff`. `CommandsIn` refuses every MCP verb from origin `tool`.
- **MCP writes (DW-1041 ruling):** `McpOps` (`Mcp/Ops.cls`, Lane A, built in 22.2) is the one writer of a server's row, its wallet secret, its Config Store entry and its resource (AD-33). 21.4 replaces the `SettingsOps.SaveMcpEntry`/`RemoveMcpEntry` stubs and their pins, and it corrects the spine passages that still say the routes or `SettingsOps` write the entry. `McpOps` audits each change without the secret. The tools and their counts come from `Mcp.Ops.Tools(server)`.
- **Routes:** 21.4 adds `Web.McpSettings` with `GET /api/v1/settings/mcp`, `POST .../mcp/servers`, `DELETE .../mcp/servers/<server>` and `POST .../mcp/classify`, plus the `Refusal` and `Submit` seams. 21.5 extends it with `POST .../mcp/sources` and `DELETE .../mcp/sources/<ref>`, and the GET gains `sources`. Every route has real-HTTP tests.
- **Approvals (AD-10, AD-11, AD-16, AD-31, AD-32):** the `Bridge.Approval` row is the truth, and `Cancel` fires `approval.cancelled`. `Core.BridgeSink` is the only place that turns bridge events into live events. It sends the `approval`, `answered` and `result` notifications through `NoticesIn` for `tool_call` requests and for a fix request with no incident. `IncidentManager` sends them only for an incident's fix requests. The spine still says Story 21.5 builds the no-incident part; 21.10 now does, so 21.10 should correct that wording. `BridgeSink` sends asynchronously and never waits on a lock for more than one second.
- **Starting point for 21.10 (from 21.5's read of this branch):**
  - Already met: the tool-call notices (`BridgeSink.ToolNoticeOf`, `toolCall.requestOnServer`, pinned by `Test.Core.ToolCallNotices`), the first-answer lock, the card's heading, buttons and expiry, and a cancelled request leaving the rail.
  - Gaps: no reason column or "Why:"; the inputs show as one truncated line; the payload has no `server` member; there is no notice for `approval.cancelled`, so the phone and Telegram keep their buttons; `answered.canceled` is unused; a cancelled card shows no status; a fix with no incident gets no notice and no web card; the `email` fix kind does not exist yet (22.7).
  - Related: DW-592 (an answered tool-call card after a page reload).

## UX & Interaction Patterns

- **Settings › Tools and MCP servers:** a server list and a tools table with an "Unclassified only" filter. Each tool has a `role="radiogroup"` ("Unclassified (counts as risky)", "Read-only", "Risky"; the selected option shows a check icon) that saves at once and confirms with "Saved". Remove asks first, with sentences for every count of tools and pending requests (21.4's T7). 21.9 adds a banner, in the accepted wording, that names a changed tool.
- **Sources (21.5):** a Read-only tool has "Use as a source", which opens a form with Source name, Arguments (JSON) and Check every (a select of six choices, 15 minutes by default). Sources are listed under "Your sources". A tool that is not Read-only shows "Only a Read-only tool can be a source." The rail's source row reads "Polled every {n} minutes".
- **Tool-call card (21.10):** "Approval needed", "Why:", "Run {tool} on {server}", the exact inputs as labelled lines, "No dry run is available for this tool. Approving runs exactly this call once.", Approve, Reject and the expiry. The rail row, the phone notification and Telegram carry the same content as plain text. A cancelled request shows `answered.canceled` and leaves the rail within one live update.

## Cross-Story Dependencies

- **Order (rulings):** 22.4 → 21.4 → 22.5. 21.4 implements only after Lane A's 22.4 merges and is integrated first. 21.9 follows 21.4 and needs `Tools(server)` to report which tools `McpOps` cleared after a fingerprint change (a cross-epic ask to Epic 22). 21.5 implements only after both 21.4 and 22.5 have merged. 21.10 follows the 22.4 merge, uses fixture requests for 22.4 and 22.7 until they merge, and needs nothing from 21.4 or 22.5.
- **Lane A status:** 22.2 and 22.8 are done; 22.3, 22.4 and 22.9 are ready-for-dev; 22.5 and 22.7 are in the backlog.
- **Contention:** `Mcp/Ops.cls` (21.4's write, beside 22.4's `CancelPending` and 22.5's message map). In `Core.BridgeSink`, ruling R1 allows 22.4 to add exactly one branch (result `changed` gives `mcp.replayToolChanged`) and one `Test.Core.ToolCallNotices` row, merged as a plain union with 21.10's changes.
- **Downstream:** Story 24.3 sends pages by email through `EmailOut` and the `email` renderer. 22.6 documents the MCP settings and the source form.
