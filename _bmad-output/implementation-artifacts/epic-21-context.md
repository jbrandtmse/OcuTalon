# Epic 21 Context: Email, webhooks and MCP settings (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This is Lane B's step 4 feature epic. The email half is built: an admin connects a real mailbox over POP3 and SMTP, with a password or a Gmail or Microsoft 365 OAuth2 sign-in. Each new email becomes an untrusted item with its own decision, and OcuTalon emails the user, daily digest included. The next item is one email fix (21.13), so that a re-sent chat turn never emails anyone twice. After that comes the MCP half. Admins add, remove and classify MCP servers and tools in Settings, see which changed tool was made Unclassified, and set Read-only tools up as source polls. Held tool calls and standalone fix requests show exactly what will run, on every channel. Webhooks shipped in Story 35.3 (21.1 became 35.2), so no webhook work is left here.

## Stories

- Story 21.2: Read a mailbox over POP3 (done)
- Story 21.6: Send email over SMTP (done)
- Story 21.7: Send the daily digest by email (done)
- Story 21.3: Register the mail OAuth2 client and sign in (done)
- Story 21.8: Read and send mail with the OAuth2 sign-in (done; pushed, CI pending)
- Story 21.12: A check fails on a link to a README anchor that README.md does not have (done; pushed, CI pending)
- Story 21.13: A re-sent turn sends its email once (backlog; next to plan)
- Story 21.4: Add, remove and classify MCP servers and tools in Settings (ready-for-dev)
- Story 21.9: Show the changed-tool banner in Settings (backlog)
- Story 21.5: Set up source polls (ready-for-dev)
- Story 21.10: Answer tool-call approval requests on every channel (ready-for-dev, Planner-ruled)
- Story 21.11: Show standalone fix requests with their reason and dry run on every channel (backlog)

## Requirements & Constraints

- **21.13 (DW-1244, ledger DW-1253):** `EmailOut` (`Channel/Email/Out.cls`) currently de-duplicates on `ApprovalRef` only. A `SendEmail` from origin `tool` carries an `IdempotencyKey`. When a command arrives again with a key that was already sent (a re-sent turn, a replay, or after a restart), it sends nothing and answers as it did the first time, so exactly one mail reaches the SMTP stub. A different key sends normally. The system path's approval-keyed de-duplication (21.6 ruling (f)) stays unchanged. A test pins one send per key.
- **Online demo safety:** no real mail, OAuth or MCP endpoint ever runs on the demo. Every MCP settings route answers 409 `not_available` with the accepted line "MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install." It answers before it reads the body.
- **Secrets:** fields are write-only, and any value containing `@{` is refused. A secret never appears in a log, trace, audit entry, global, GET or test output. MCP secrets live in the IRIS Wallet. A secret sent to a non-loopback `http://` address is refused with `MESSAGEADDRESS`.
- **Plain mail (Planner ruling G):** in OAuth2 mode the bearer token goes out only over TLS. The CI-only switch `OCUTALON_TEST_PLAIN_SMTP` (`Sender.PlainFor`) allows plain POP3 and SMTP, and only for host `mock`. It is ratified, documented where it is defined and in the credential rule, and set only in `ci/compose.ci.yml`, never in a shipped compose file or image. Any other setting is refused before a token is fetched. No text may claim least privilege.
- **Approvals:** the first answer wins on every channel, and a cancelled request stops its buttons everywhere. When a request would go over 4,096 characters, Telegram shows its head, no Approve button, and "The inputs are too long to show here. See them on your OcuTalon page before you approve." The web card shows everything (it may collapse). A test pins both channels.
- **Only accepted text ships:**
  - 21.4's T1-T11 and the rail line "Polled every {n} minutes";
  - 21.10's T1 "Why: {tool} counts as risky, so it runs only after an approval." and T2 (the "Inputs:" line, then "{name}: {value}" lines with JSON values, or "{}");
  - `toolCall.requestOnServer` and `answered.canceled`.
- **Docs:** install, admin and how-to text goes in `GUIDE.md`, and README.md keeps the pointers.
- **CI** uses only the CI mock: POP3 and SMTP stubs with XOAUTH2, a fake OAuth2 server, and `Test.Mcp.Mock`. It never reaches a real provider.

## Technical Decisions

- **Lanes:** Lane B (this epic) owns `Core/**`, `Web/**`, `Channel/**` (except `Channel/Telegram/**`), `Data/**`, `Msg/Command/**`, `Msg/Catalog/Core.cls` and `web/`. Lane A owns `Mcp/**`, `Fix/**`, `Watch/**`, `Digest/**`, `src/bridge/**`, `Install/**` and `release/**`.
- **Commands (AD-1, AD-8):** every change is a production message. A tool's command carries `IdempotencyKey` (the turn's `ItemId` plus the command's position in the turn, the same on every approved replay), and its owner ignores a repeat. `ReminderOps.SetReminder` shows the existing keyed-repeat pattern. The admin `/v1/settings` routes submit commands with origin `web_admin`, and the REST process writes nothing. `CommandsIn` refuses MCP verbs from origin `tool`.
- **MCP writes:** `McpOps` (Lane A) is the only writer of a server's row, wallet secret, Config Store entry `AI.MCP.OcuTalon_<server>` and resource. 21.4 replaces the `SettingsOps` stubs and adds `Web.McpSettings` (GET `/api/v1/settings/mcp`, POST servers, DELETE `servers/<server>`, POST classify). 21.5 adds the sources routes. Tools and counts come from `Mcp.Ops.Tools(server)`.
- **Notices (AD-31, AD-32):** producers never render text. `BridgeSink` fills the slots and `Msg.Catalog.Render` writes the text for each channel. `BridgeSink` stays asynchronous and never waits more than 1 s on a lock.
- **21.10:** add a new `inputs` slot type to `BridgeSink.ToolNoticeOf`: exact, uncut, one JSON value per line, still masked by `Bridge.Redact`. The approval payload gains `server` and `cancelledAt`. `answered.canceled` goes out only when the `Mcp.Server` row is gone; a session end cancels quietly. The reason line is written by code, never by the model.
- **21.11:** builds the approval, answered and result notices for a fix request that has no incident, plus its web card and rail title. It reuses 21.10's branches.

## UX & Interaction Patterns

- **Settings › Tools and MCP servers:** a server list and a tools table with an "Unclassified only" filter. Each tool has a `role="radiogroup"` with Unclassified (counts as risky), Read-only and Risky. A choice saves at once and shows "Saved". Remove asks for confirmation.
- **Sources (21.5):** "Use as a source" on a Read-only tool opens a form: name, arguments as JSON, and an interval (6 choices, 15 minutes by default). Other tools show "Only a Read-only tool can be a source."
- **Tool-call card (21.10):** "Approval needed", "Why:", "Run {tool} on {server}", the labelled inputs, the no-dry-run sentence, Approve, Reject and the expiry. Rail rows have no answer buttons. A cancelled card shows "Canceled at HH:MM: the MCP server {server} was removed. Nothing was changed." and leaves the rail within one live update.

## Cross-Story Dependencies

- **21.13 first:** Story 22.7 (Lane A, chat email) can't merge until 21.13 lands. The orchestrator reconciles DW-1244 and DW-1253 after the merge.
- **MCP order:** 22.4 → 21.4 → 22.5 → 21.5. 21.9 follows 21.4 and needs `Tools(server)` to report the tools that were cleared. 21.10 is built after 22.4 merges: integrate forward first, and use fixture requests until then. 21.11 follows 22.7.
- **Lane A status:** 22.2 and 22.8 are done. 22.3, 22.4 and 22.9 are ready-for-dev. 22.5, 22.6, 22.7 and 22.10 are in the backlog.
- **Contention:**
  - `Mcp/Ops.cls`, `Core/SettingsOps.cls`.
  - `Core/BridgeSink.cls`: 22.4 may add one branch (`mcp.replayToolChanged`) and one `Test.Core.ToolCallNotices` row, merged as a union.
  - README.md, GUIDE.md and `test-readme.sh`: placed edits only.
- **Downstream:** 24.3 sends email through `EmailOut`. 22.6 documents the MCP settings.
