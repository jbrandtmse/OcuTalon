# Epic 21 Context: Email, webhooks and MCP settings (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Lane B's step 4 feature epic. The email half is built: a real mailbox over POP3 and SMTP, with a password or a Gmail or Microsoft 365 OAuth2 sign-in. Each email becomes an untrusted item with its own decision, OcuTalon emails the user (daily digest included), and a re-sent turn emails nobody twice. One email fix is left: 21.14 (DW-1255) keeps the mailbox address and user name out of the trace. Then comes the MCP half: admins add, remove and classify MCP servers and tools, see changed tools made Unclassified, set Read-only tools up as source polls, and see exactly what a held tool call or standalone fix will run, on every channel. Webhooks shipped in Epic 35.

## Stories

- Story 21.2: Read a mailbox over POP3 (done)
- Story 21.6: Send email over SMTP (done)
- Story 21.7: Send the daily digest by email (done)
- Story 21.3: Register the mail OAuth2 client and sign in (done)
- Story 21.8: Read and send mail with the OAuth2 sign-in (done; pushed, CI pending)
- Story 21.12: A check fails on a link to a README anchor that README.md does not have (done; pushed, CI pending)
- Story 21.13: A re-sent turn sends its email once (done; pushed, CI pending)
- Story 21.14: The mailbox address and user name stay out of the trace (backlog; next to plan, implements after 21.8 merges)
- Story 21.4: Add, remove and classify MCP servers and tools in Settings (ready-for-dev)
- Story 21.9: Show the changed-tool banner in Settings (backlog)
- Story 21.5: Set up source polls (ready-for-dev)
- Story 21.10: Answer tool-call approval requests on every channel (ready-for-dev, Planner-ruled)
- Story 21.11: Show standalone fix requests with their reason and dry run on every channel (backlog)

## Requirements & Constraints

- **21.14 (DW-1255):** saving Settings > Channels > Email sends `address` and `user` through the same `SecretHandoff` swap `Web/Api.cls` uses for `password` and `clientSecret`. `SaveSettings.Changes` holds only handoff references, and the values reach only `SettingsOps` and IRIS's own audit entry. `incoming`, `outgoing`, `signIn`, `clientId` and `origin` are unchanged. A leak-scan test finds neither value in any traced message, log row, trace or `^OcuTalon*` global after a save. `docs/security-overview.md` says plainly that the trace role sees each item's content, including an email's sender (`Msg.Item.Sender` stays).
- **Personal data:** `SecretHandoff` is for synchronous saves only. Data that must persist (22.7's recipients) goes in a stored private row, and the traced message carries only its reference. `EmailOut` de-duplicates a `tool` `SendEmail` on its `IdempotencyKey` (21.13).
- **Online demo safety:** no real mail, OAuth or MCP endpoint ever runs on the demo. Every MCP settings route answers 409 `not_available` with the accepted line "MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install." It answers before it reads the body.
- **Secrets:** fields are write-only, and any value containing `@{` is refused. A secret never appears in a log, trace, audit entry, global, GET or test output. MCP secrets live in the IRIS Wallet. A secret sent to a non-loopback `http://` address is refused with `MESSAGEADDRESS`.
- **Plain mail:** OAuth2 bearer tokens go out only over TLS. The CI-only `OCUTALON_TEST_PLAIN_SMTP` (`Sender.PlainFor`) allows plain POP3/SMTP for host `mock` only, set only in `ci/compose.ci.yml`. No text may claim least privilege.
- **Approvals:** the first answer wins on every channel, and a cancelled request stops its buttons everywhere. Over 4,096 characters, Telegram shows the head, no Approve button, and "The inputs are too long to show here. See them on your OcuTalon page before you approve."; the web card shows everything.
- **Only accepted text ships:** 21.4's T1-T11 and "Polled every {n} minutes"; 21.10's T1 "Why: {tool} counts as risky, so it runs only after an approval." and T2 ("Inputs:" then "{name}: {value}" JSON lines, or "{}"); `toolCall.requestOnServer` and `answered.canceled`.
- **Docs:** install, admin and how-to text goes in `GUIDE.md`, and README.md keeps the pointers.
- **CI** uses only the CI mock: POP3 and SMTP stubs with XOAUTH2, a fake OAuth2 server, and `Test.Mcp.Mock`. It never reaches a real provider.

## Technical Decisions

- **Lanes:** Lane B (this epic) owns `Core/**`, `Web/**`, `Channel/**` (except `Channel/Telegram/**`), `Data/**`, `Msg/Command/**`, `Msg/Catalog/Core.cls` and `web/`. Lane A owns `Mcp/**`, `Fix/**`, `Watch/**`, `Digest/**`, `src/bridge/**`, `Install/**` and `release/**`.
- **Commands (AD-1, AD-8):** every change is a production message, and its owner ignores a repeated `IdempotencyKey`. The `/v1/settings` routes submit with origin `web_admin`, and the REST process writes nothing. `CommandsIn` refuses MCP verbs from origin `tool`.
- **MCP writes:** `McpOps` (Lane A) is the only writer of a server's row, wallet secret, Config Store entry `AI.MCP.OcuTalon_<server>` and resource. 21.4 replaces the `SettingsOps` stubs and adds `Web.McpSettings` (GET `/api/v1/settings/mcp`, POST servers, DELETE `servers/<server>`, POST classify). 21.5 adds the sources routes. Tools and counts come from `Mcp.Ops.Tools(server)`.
- **Notices (AD-31, AD-32):** producers never render text. `BridgeSink` fills the slots and `Msg.Catalog.Render` writes the text for each channel. `BridgeSink` stays asynchronous and never waits more than 1 s on a lock.
- **21.10:** add a new `inputs` slot type to `BridgeSink.ToolNoticeOf`: exact, uncut, one JSON value per line, still masked by `Bridge.Redact`. The approval payload gains `server` and `cancelledAt`. `answered.canceled` goes out only when the `Mcp.Server` row is gone; a session end cancels quietly. The reason line is written by code, never by the model.
- **21.11:** notices, web card and rail title for a fix request with no incident, reusing 21.10's branches.

## UX & Interaction Patterns

- **Settings › Tools and MCP servers:** a server list and a tools table with an "Unclassified only" filter. Each tool has a `role="radiogroup"` with Unclassified (counts as risky), Read-only and Risky. A choice saves at once and shows "Saved". Remove asks for confirmation.
- **Sources (21.5):** "Use as a source" on a Read-only tool opens a form: name, arguments as JSON, and an interval (6 choices, 15 minutes by default). Other tools show "Only a Read-only tool can be a source."
- **Tool-call card (21.10):** "Approval needed", "Why:", "Run {tool} on {server}", the labelled inputs, the no-dry-run sentence, Approve, Reject and the expiry. Rail rows have no answer buttons. A cancelled card shows "Canceled at HH:MM: the MCP server {server} was removed. Nothing was changed." and leaves the rail within one live update.

## Cross-Story Dependencies

- **Email fixes:** 21.14 implements after 21.8 merges and touches `Web/Api.cls`, `Core/SettingsOps.cls`, `Test.Core.SettingsEmail`, `Test.Web.SettingsApi` and `docs/security-overview.md`. Story 22.7 (Lane A, chat email) merges only after 21.13 lands, and only once it carries recipients by private-row reference.
- **MCP order:** 22.4 → 21.4 → 22.5 → 21.5. 21.9 follows 21.4 and needs `Tools(server)` to report the tools that were cleared. 21.10 is built after 22.4 merges: integrate forward first, and use fixture requests until then. 21.11 follows 22.7.
- **Contention:**
  - `Mcp/Ops.cls`, `Core/SettingsOps.cls` (21.14 and 21.4 both edit it).
  - `Core/BridgeSink.cls`: 22.4 may add one branch (`mcp.replayToolChanged`) and one `Test.Core.ToolCallNotices` row, merged as a union.
  - README.md, GUIDE.md and `test-readme.sh`: placed edits only.
- **Downstream:** 24.3 sends email through `EmailOut`. 22.6 documents the MCP settings.
