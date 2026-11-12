# Epic 21 Context: Email, webhooks and MCP settings (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Lane B's step 4 feature epic. An admin connects a real mailbox (POP3 read, SMTP send, or Gmail and Microsoft 365 through OAuth2), so each new email becomes an untrusted item with its own attention decision and OcuTalon can email the user, including the daily digest. Admins also add, remove and classify MCP servers and their tools in Settings, set read-only tools up as source polls, and answer tool-call approval requests on every channel. The epic builds on contracts Epic 35 fixed (Story 21.1 became Story 35.2). Webhooks moved to Story 35.3 (parked until after voting), so this epic ships no webhook work despite its title. Story 21.2 was split at its spec gate: 21.2 the POP3 read (done), 21.6 the SMTP send (done), 21.7 the digest by email.

## Stories

- Story 21.2: Read a mailbox over POP3 (done)
- Story 21.3: Sign in to Gmail and Microsoft 365 with OAuth2 (next)
- Story 21.4: Add, remove and classify MCP servers and tools in Settings
- Story 21.5: Set up source polls and answer tool-call approval requests
- Story 21.6: Send email over SMTP (done)
- Story 21.7: Send the daily digest by email

## Requirements & Constraints

- **Online demo safety (standing rule, overrides any text about "preconfigured" or "allow-listed" demo servers):** real mail, OAuth and MCP endpoints never run on the online demo. The simulated mailbox stays; `EmailIn`/`EmailOut` stay disabled (`EmailOut` answers `not_available` whatever the rows say); email, OAuth, MCP and source-poll settings are off; the demo account sees no settings; nobody can add or remove a server, and the demo says so in a plain line (public text settled at 21.4's spec gate).
- **Secrets:** every secret field is write-only; any admin value containing `@{` is refused; no command, message, log, trace, audit entry, global, GET or test output holds a secret, only a reference. Homes: mail credentials in Interoperability credential `OcuTalonMail` (shared by `EmailIn` and `EmailOut`); OAuth2 tokens and client secrets only inside IRIS's OAuth2 client; MCP secrets in the IRIS Wallet, referenced from Config Store entry `AI.MCP.OcuTalon_<server>`.
- **Outbound email:** origin `tool` only to exactly the session user's own address; origin `system` only for an executing email-fix approval (below). The digest goes only to the own address as plain catalog-rendered text, recorded as a `Delivery`; email is offered as a digest channel only once a mailbox is connected.
- **Settings changes** apply within a minute and are audited without secrets (OAuth connect/remove entries hold no client secret or token).
- **OAuth2 (21.3):** tokens refresh without the admin; a revoked grant fails the poll with a plain reason and the mailbox counts as not checked. The README must explain creating the OAuth2 client with Google and Microsoft, the redirect address to register with each, and connecting in Settings.
- **Only accepted text ships:** texts come from the keys accepted for Story 35.2 (`settings.*`, `answered.canceled`, in `OcuTalon.Msg.Catalog.Core`). New public text (21.3's README and redirect guidance, 21.4's demo line) goes to the author first.
- **CI:** the CI-only mock serves a POP3 stub (21.2) and an SMTP stub (21.6); no real email is ever sent.

## Technical Decisions

- **Lanes:** Lane B owns `Core/**`, `Web/**`, `Channel/**`, `Data/**` (Lane B tables), `Msg/Command/**`, `Msg/Catalog/Core.cls`, `web/`, and items `EmailIn`/`EmailOut`. Lane A owns `Mcp/**`, `src/bridge/**`, `Install/**`, `Msg/Catalog/Watch.cls` and `Digest.Process`.
- **Commands (AD-1):** every change is a production message submitted with origin `web_admin` from admin-checked routes; REST code never writes the wallet, the Config Store or credentials. Secrets reach the operation through `OcuTalon.Core.SecretHandoff` (in-memory, single take; the command carries `secret://handoff/<name>`); reuse it for the OAuth2 client secret and the MCP secret.
- **Email in (21.2):** `EmailIn` with its own POP3 adapter, `Data.MailSeen` for no-repeats, `SettingsOps.SaveEmail` (sole writer of `email.address`/`email.owner`), route `POST /api/v1/settings/channels`; poll outcome in status mark `emailPoll` (`at`, `ok`, `reason`, `lastOkAt`; never server text, an address or a credential).
- **Email out (21.6):** `OcuTalon.Channel.Email.Out` (item `EmailOut`) with adapter `Channel.Email.Sender` (subclass of `EnsLib.EMail.OutboundAdapter`): one plain-text UTF-8 part from `email.address`, TLS only (`OcuTalonClient` implicit on 465, `OcuTalonClient*` STARTTLS otherwise), server identity always checked, one try. Plain SMTP only with CI-only `OCUTALON_TEST_PLAIN_SMTP=1` and host `mock`. Outcomes: `sent`, `already_sent`, `refused`, `not_connected`, `failed`, `not_available`. A system send needs `SendEmail.ApprovalRef` of an executing `fix` approval with `FixKind` `email` whose `FixParameters.recipients` equals the recipients (lower-cased set); a `Data.Delivery` claim row (channel `email`) makes one approval send at most once. Logs counts and outcomes only.
- **CommandsIn (21.6, AD-10):** refuses a tool `SendEmail` in a bridge context whose provenance isn't `user` or whose turn is tainted (an approved replay's context is clean), and answers `not_connected` when `EmailOut` has no alive job. Story 22.7's own-address tool must declare `TRUSTEDOUTPUT` 1 or every ordinary turn refuses it (DW-1164).
- **SettingsOps (21.6):** writes `EmailOut`'s System Default Settings rows (`SMTPServer`, `SMTPPort`, `Credentials` `OcuTalonMail`, `SSLConfig`, `SSLCheckServerIdentity` 1, `Enabled`); an empty server writes `Enabled` 0. Every successful email save runs the detached production update, even when no row changed (DW-1139 settled).
- **OAuth2 (21.3):** one new class switches to `%SYS` (in one `New $NAMESPACE` method) to register the IRIS OAuth2 client and must be added to AD-3's namespace-switching list in the same change; `EmailIn`/`EmailOut` take tokens through the adapters' OAuth2 settings for POP3 and SMTP.
- **Digest by email (21.7):** routed through Notify, which gains the email channel; `Digest.Process` gets no email knowledge (DW-820). Add the `email` channel to `OcuTalon.Msg.Catalog.Render` as plain text under the `phone` rules, testing every key `EmailOut` sends. DW-1167: `EmailIn` takes in OcuTalon's own mail to the polled address as a new item; mark `EmailOut`'s mail and skip it in `EmailIn`, or rule it harmless.
- **MCP (21.4):** `McpOps` (Lane A) handles add/remove/classify and the real `Tools(server)`. DW-1041 (ruled): the Config Store and wallet write moves into `McpOps`, never the REST process. 21.4 replaces the `SettingsOps.SaveMcpEntry`/`RemoveMcpEntry` stubs and their pins in `Test.Core.CommandsStep4` on purpose.
- **REST rows, each with real-HTTP route tests:** `GET /api/v1/settings/mcp`, `POST .../mcp/servers`, `DELETE .../mcp/servers/<server>`, `POST .../mcp/classify` (21.4); `POST .../mcp/sources`, `DELETE .../mcp/sources/<ref>` (21.5).
- **Approvals with no incident (21.5):** for `tool_call` requests and standalone email fixes, `OcuTalon.Core.BridgeSink` sends `approval`, `answered` and `result` through `NoticesIn`; `IncidentManager` covers only an incident's fix requests.
- **Catalog quirk:** `settings.refusedExpansion` takes `@{` as the slot `marker`.

## UX & Interaction Patterns

- **Settings › Channels › Email:** address, POP3 server, Outgoing mail server (SMTP), user, write-only password; OAuth2 adds Client ID, Client secret and "Sign in with {provider}" (consent opens in a new tab). Secret fields show `settings.secretSet`/`settings.secretNotSet`; a save shows "Saved. Applies within a minute. Recorded in the audit log."
- **Settings › Tools and MCP servers:** server list (name, address, status, tool count, unclassified count); Add server (name, `https://` or loopback, optional write-only secret; tools arrive Unclassified); Remove asks first ("Remove Jira? Its 12 tools go at once, and 1 pending approval request for them is canceled."); tools table with "Unclassified only" filter and a `role="radiogroup"` per tool ("Unclassified (counts as risky)", "Read-only", "Risky") that saves at once with "Saved"; a changed tool gets `settings.toolChangedBanner`.
- **Source-poll form:** `settings.source*` keys; a non-Read-only tool can't be chosen, with the reason beside it.
- **Tool-call card:** "Approval needed", "Why:", "Run {tool} on {server}", inputs as labelled lines, the no-dry-run line, Approve, Reject, expiry; rail, phone and Telegram carry the same as plain text; first answer wins; a cancelled request shows `answered.canceled`, its buttons stop everywhere and it leaves the rail within one live update. Standalone fixes show "Why:" and a dry run with exact text and every recipient.

## Cross-Story Dependencies

- **Order:** 21.2 and 21.6 done; then 21.3 (reuses `EmailIn`/`EmailOut`), 21.7 (needs `EmailOut`), 21.4, 21.5 (sources only tools 21.4 classified).
- **Lane A:** 22.2 is done (`McpOps`, real `Tools`). 22.8 (MCP classification by fingerprint in the gate) is merged on feature but not yet on this branch; merge feature before 21.4. Not yet built: 22.4 (raises/cancels `tool_call` requests), 22.5 (runs source polls), 22.7 (email tool and email fix kind; until then only seeded rows test `EmailOut`'s system path, DW-1164). Test against fixture requests and a `McpOps` test double meanwhile.
- **Downstream:** Story 24.3 pages by email through `EmailOut` and the `email` renderer from 21.7.
- **DW-1041 contention:** the wallet/Config Store write lands in `Mcp/Ops.cls`, a Lane A file contended with Epic 22; 21.4 must also reconcile spine passages that still say routes call `SettingsOps.SaveMcpEntry`.
- **Open for 21.3:** the AD-3 amendment (the `%SYS`-switching OAuth2 class) and the README text, both needing a ruling or author acceptance.
