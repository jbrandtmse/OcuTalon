# Epic 21 Context: Email, webhooks and MCP settings (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This is Lane B's step 4 feature epic. The email half is done. An admin connects a real mailbox over POP3 and SMTP, using a password or a Gmail or Microsoft 365 OAuth2 sign-in. Each new email becomes an untrusted item with its own decision, and OcuTalon emails the user, including the daily digest. What remains is the MCP half. Admins add, remove and classify MCP servers and tools in Settings. They see which changed tool was made Unclassified, and they set Read-only tools up as source polls. Held tool calls and standalone fix requests show exactly what will run, on every channel. Webhooks shipped in Story 35.3 (21.1 became 35.2), so no webhook work is left here. One test-only story guards the README's anchors.

## Stories

- Story 21.2: Read a mailbox over POP3 (done)
- Story 21.6: Send email over SMTP (done)
- Story 21.7: Send the daily digest by email (done)
- Story 21.3: Register the mail OAuth2 client and sign in (done)
- Story 21.8: Read and send mail with the OAuth2 sign-in (done, with security rework 1)
- Story 21.4: Add, remove and classify MCP servers and tools in Settings (ready-for-dev)
- Story 21.9: Show the changed-tool banner in Settings (backlog)
- Story 21.5: Set up source polls (ready-for-dev)
- Story 21.10: Answer tool-call approval requests on every channel (ready-for-dev, Planner-ruled)
- Story 21.11: Show standalone fix requests with their reason and dry run on every channel (backlog)
- Story 21.12: A check fails on a link to a README anchor that README.md does not have (backlog; next to plan)

## Requirements & Constraints

- **Online demo safety:** no real mail, OAuth or MCP endpoint ever runs on the demo. Every MCP settings route answers 409 `not_available` with the accepted line "MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install." before it reads the body.
- **Secrets:** fields are write-only, and any value containing `@{` is refused. A secret never appears in a log, trace, audit entry, global, GET or test output. MCP secrets live in the IRIS Wallet. A secret sent to a non-loopback `http://` address is refused with `MESSAGEADDRESS`.
- **Mail tokens (21.8 rework, DW-1230):** in OAuth2 mode the bearer token goes out only over TLS. Plain POP3 or SMTP is allowed only with the CI-only switch on and the host exactly `mock` (the shared `Sender.PlainFor` rule). Any other setting refuses before a token is fetched. The CI-only switches never appear in a compose file or an image. No text may claim least privilege (DW-1180).
- **Approvals:** the first answer wins on every channel. A cancelled request stops its buttons everywhere. **Telegram condition (21.10 V4):** when the full request would go over 4,096 characters, Telegram shows the head of the request, no Approve button, and the line "The inputs are too long to show here. See them on your OcuTalon page before you approve." The web card shows everything (collapsible is fine). A test pins both channels.
- **Only accepted text ships.** Text that is already accepted:
  - 21.4's T1-T11 and the rail line "Polled every {n} minutes";
  - for 21.10, T1 "Why: {tool} counts as risky, so it runs only after an approval." and T2 (the "Inputs:" line, then "{name}: {value}" lines with JSON values, or "{}");
  - the full `toolCall.requestOnServer` text and `answered.canceled`.
- **Guide placement:** since Story 0.30, the install, admin and how-to text lives in `GUIDE.md`, including 21.8's T3 bullet and T4 section "Gmail and Microsoft 365". README.md keeps the pointers. New how-to text goes in GUIDE.md.
- **CI** uses only the CI mock: POP3 and SMTP stubs with XOAUTH2, a fake OAuth2 server, and `Test.Mcp.Mock`. It never reaches a real provider.

## Technical Decisions

- **Lanes:** Lane B owns `Core/**`, `Web/**`, `Channel/**` except `Channel/Telegram/**`, `Data/**`, `Msg/Command/**`, `Msg/Catalog/Core.cls` and `web/`. Lane A owns `Mcp/**`, `Fix/**`, `Watch/**`, `Digest/**`, `src/bridge/**`, `Install/**` and `release/**`.
- **Commands (AD-1):** every change is a production message. Admin-checked `/v1/settings` routes submit commands with origin `web_admin`, and the REST process writes nothing. `CommandsIn` refuses MCP verbs from origin `tool`.
- **MCP writes:** `McpOps` (Lane A) is the only writer of a server's row, its wallet secret, its Config Store entry `AI.MCP.OcuTalon_<server>` and its resource.
  - 21.4 replaces the `SettingsOps` stubs and adds `Web.McpSettings` (GET `/api/v1/settings/mcp`, POST servers, DELETE `servers/<server>`, POST classify).
  - 21.5 adds the sources routes.
  - Tools and counts come from `Mcp.Ops.Tools(server)`.
- **Notices (AD-31, AD-32):** producers never render text. `BridgeSink` provides the slots, and `Msg.Catalog.Render` writes the text for every channel. `BridgeSink` stays asynchronous and waits on no lock for more than 1 s.
- **21.10's plan:**
  - Extend `BridgeSink.ToolNoticeOf` with a new `inputs` slot type: exact, uncut, one JSON value per line, still masked by `Bridge.Redact`.
  - The approval payload gains `server` and `cancelledAt`.
  - Send `answered.canceled` only when the server's `Mcp.Server` row is gone. A session end also cancels requests, and those send nothing.
  - The reason line is written by code, never by the model.
- **21.11:** builds the `approval`, `answered` and `result` notices for a fix request that has no incident, plus its web card and rail title. It reuses 21.10's branches. `IncidentManager` keeps an incident's fix requests.
- **21.12 (DW-1207, test-only):** `docker/tests/test-readme.sh` already has the `readme-links` rule, but it checks only README.md and GUIDE.md. The new check covers every other tracked Markdown file (`docs/*.md` included). It catches `README.md#x` links, relative or by the repository URL, whose anchor is not a GitHub heading slug of README.md. It reports the file, line and anchor, and proves it can fail with a planted dead link. No product change.

## UX & Interaction Patterns

- **Settings › Tools and MCP servers:** a server list and a tools table with an "Unclassified only" filter. Each tool has a `role="radiogroup"` control (Unclassified (counts as risky), Read-only, Risky) that saves at once and shows "Saved". Remove asks for confirmation first. 21.9 adds the changed-tool banner.
- **Sources (21.5):** "Use as a source" on a Read-only tool opens a form with name, arguments as JSON, and an interval (6 choices, 15 minutes by default). Other tools show "Only a Read-only tool can be a source."
- **Tool-call card (21.10):** "Approval needed", "Why:", "Run {tool} on {server}", the labelled inputs, the no-dry-run sentence, Approve, Reject and the expiry. Rail rows have no answer buttons (UX-DR52). A cancelled card shows "Canceled at HH:MM: the MCP server {server} was removed. Nothing was changed." and leaves the rail within one live update.

## Cross-Story Dependencies

- **Order:** 22.4 → 21.4 → 22.5 → 21.5.
  - 21.9 follows 21.4 and needs `Tools(server)` to report the tools that were cleared.
  - 21.10 implements after 22.4 merges. Integrate forward first, and use fixture requests for 22.4 until it merges.
  - 21.11 follows 22.7, which fixes the email request row's shape.
  - 21.12 depends on nothing and can run in idle time.
- **Lane A status:** 22.2 and 22.8 are done. 22.3, 22.4 and 22.9 are ready-for-dev. 22.5, 22.7 and 22.10 are in the backlog.
- **Contention:**
  - `Mcp/Ops.cls`.
  - `Core/BridgeSink.cls`: 22.4 may add one branch (`mcp.replayToolChanged`) and one `Test.Core.ToolCallNotices` row, merged as a union.
  - `Core/SettingsOps.cls`.
  - README.md, GUIDE.md and `test-readme.sh`, which every story's findability lines touch: placed edits only.
- **Downstream:** 24.3 sends email through `EmailOut`. 22.6 documents the MCP settings.
