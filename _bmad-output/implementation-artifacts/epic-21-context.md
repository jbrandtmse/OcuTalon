# Epic 21 Context: Email, webhooks and MCP settings (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Lane B's step 4 feature epic. An admin connects a real mailbox (POP3 read, SMTP send, or Gmail and Microsoft 365 through OAuth2), so each new email becomes an untrusted item with its own attention decision and OcuTalon can email the user, including the daily digest. Admins also add, remove and classify MCP servers and their tools in Settings, set read-only tools up as source polls, and answer tool-call approval requests on every channel. It builds on the contracts Epic 35 fixed (Story 21.1 became Story 35.2). Webhooks shipped in Story 35.3 (Epic 35), so this epic has no webhook work despite its title. Spec-gate splits: 21.2 became 21.2 (POP3 read), 21.6 (SMTP send) and 21.7 (digest by email); 21.3 became 21.3 (register the mail OAuth2 client and sign in) and 21.8 (use that sign-in to read and send).

## Stories

- Story 21.2: Read a mailbox over POP3 (done)
- Story 21.6: Send email over SMTP (done)
- Story 21.7: Send the daily digest by email (done)
- Story 21.3: Register the mail OAuth2 client and sign in (done)
- Story 21.8: Read and send mail with the OAuth2 sign-in (next)
- Story 21.4: Add, remove and classify MCP servers and tools in Settings
- Story 21.5: Set up source polls and answer tool-call approval requests

## Requirements & Constraints

- **Online demo safety (standing rule; it overrides any text about "preconfigured" or "allow-listed" demo servers):** real mail, OAuth and MCP endpoints never run on the online demo. Only the simulated mailbox exists. `EmailIn`/`EmailOut` stay disabled, `/csp/sys/oauth2` is never enabled there, and email, OAuth, MCP and source-poll settings are off. The demo account sees no settings, nobody can add or remove a server, and the demo says so in a plain line (public text settled at 21.4's spec gate).
- **Secrets:** every secret field is write-only, and any admin value containing `@{` is refused. No command, message, log, trace, audit entry, global, GET or test output holds a secret, only a reference. Mail credentials live in Interoperability credential `OcuTalonMail`, OAuth2 tokens and the client secret only inside IRIS's OAuth2 client `OcuTalonMail`, and MCP secrets in the IRIS Wallet, referenced from Config Store entry `AI.MCP.OcuTalon_<server>`.
- **Outbound email:** origin `tool` sends only to exactly the session user's own address. Origin `system` sends only for an executing email-fix approval. The digest goes only to the own address.
- **Settings changes** apply within a minute and are audited without secrets.
- **21.8 (OAuth2 token use):** `EmailIn` and `EmailOut` use the tokens through the adapters' OAuth2 settings for POP3 and SMTP (XOAUTH2). An expired token is refreshed without the admin. A revoked grant fails the poll with a plain reason, and the mailbox counts as not checked (`emailPoll` ok 0). The README explains creating the client with Google and with Microsoft, the redirect address to register with each, and connecting the mailbox in Settings. It names `_Ensemble` as the measured production user. The live run lists each privilege that registering needs for a production user narrower than `_Ensemble`, each with a check that registering is refused without it. No text claims least privilege (DW-1180). It settles DW-1179: a provider-mode mailbox still polls with the empty stored password, so it fails with the refused-login sentence.
- **Only accepted text ships:** texts come from the accepted catalog keys (`settings.*`, `answered.canceled`, `mcp.*`). New public text (the OAuth README and redirect guidance, 21.4's demo line) goes to the author first.
- **CI:** the CI-only mock serves POP3 and SMTP stubs and a fake OAuth2 server (`ci/mock/oauth.mjs`; 21.8 adds XOAUTH2 to the stubs and refresh and revoke to the fake server). No real email is ever sent and no real provider is reached.

## Technical Decisions

- **Lanes:** Lane B owns `Core/**`, `Web/**`, `Channel/**`, `Data/**` (Lane B tables), `Msg/Command/**`, `Msg/Catalog/Core.cls`, `web/`, and the items `EmailIn`/`EmailOut`. Lane A owns `Mcp/**`, `Fix/**`, `Digest/**`, `Tools/Email*`, `src/bridge/**`, `Install/**` and `Msg/Catalog/Watch.cls`.
- **Commands (AD-1):** every change is a production message that an admin-checked route submits with origin `web_admin`. REST code never writes the wallet, the Config Store, credentials or `%SYS`. Secrets reach their writer through `OcuTalon.Core.SecretHandoff` (single take; the command carries `secret://handoff/<name>`).
- **The email that exists:** `SettingsOps` is the only writer of the `email.*` keys, `OcuTalonMail` and both items' System Default Settings rows, and a detached job updates the production. The poll outcome is in status mark `emailPoll`. `EmailOut` (adapter `Channel.Email.Sender`) is TLS only with the server identity checked. Every mail it sends carries `X-OcuTalon-Ref`, and `EmailIn` skips its own echoes by that Ref (DW-1167 closed). Notify routes the digest to email (rule `DigestEmail`), and the renderer has the `email` channel.
- **OAuth2 as built (21.3):** `OcuTalon.Channel.Email.OAuth` (one `Sys` method; it is the AD-3 namespace-switching class) registers client `OcuTalonMail` with fixed `https://` provider endpoints (no discovery, PKCE S256, minimum POP3 and SMTP scopes). Application and session id are both `OcuTalonMail`. OcuTalon reads only the signed-in state and never a token value. The keys are `email.signIn`, `email.clientId` and `email.oauthOwned`, plus status mark `emailSignIn`. The redirect is `/csp/sys/oauth2/OAuth2.Response.cls` on the request's origin. `/csp/sys/oauth2` is enabled only during an admin's register or sign-in. Route: `POST /api/v1/settings/channels/sign-in` (`start`/`check`, verb `MailSignIn`, `web_admin` only). CI plain HTTP is allowed only with `OCUTALON_TEST_OAUTH_MOCK=1`.
- **21.8 plan direction (from 21.3's split proposal):** the System Default Settings rows `OAuth2ApplicationName`/`OAuth2SessionId` `OcuTalonMail`, `OAuth2Scope` and `OAuth2AuthProperties`, plus an `Ens.Util.OAuth2.Handler` subclass as `OAuth2CallBackHandler` that never raises a Workflow request. IRIS refreshes the token inside `%SYS.OAuth2.AccessToken.GetAccessToken`. The adapters' OAuth2 hooks are in `Channel/Email/Adapter.cls` and `Sender.cls`.
- **MCP (21.4):** `McpOps` (Lane A, built in 22.2) handles add, remove and classify, and the real `Tools(server)`. DW-1041 was ruled: the wallet and Config Store write moves into `McpOps`, never the REST process. 21.4 replaces the `SettingsOps.SaveMcpEntry`/`RemoveMcpEntry` stubs and the `TestMcpEntryStubs` pins on purpose, and reconciles the spine passages that still say the routes or `SettingsOps` write the entry. `CommandsIn` refuses every MCP verb from `tool`, and a test proves it for each verb.
- **REST rows, each with real-HTTP route tests:** `GET /api/v1/settings/mcp`, `POST .../mcp/servers`, `DELETE .../mcp/servers/<server>` and `POST .../mcp/classify` (21.4); `POST .../mcp/sources` and `DELETE .../mcp/sources/<ref>` (21.5).
- **Approvals with no incident (21.5):** for `tool_call` requests and standalone email fixes, `OcuTalon.Core.BridgeSink` sends the `approval`, `answered` and `result` notifications through `NoticesIn`. `IncidentManager` covers only an incident's fix requests. `BridgeSink` maps the `FinishExecution` result `changed` to `mcp.replayToolChanged`. `Approval.CancelPending` cancels a removed server's pending `tool_call` rows.

## UX & Interaction Patterns

- **Settings › Channels › Email:** a Sign-in method (Password, Google, Microsoft 365). OAuth2 adds Client ID, Client secret, the redirect address and "Sign in with {provider}", and consent opens in a new tab. A save shows "Saved. Applies within a minute. Recorded in the audit log."
- **Settings › Tools and MCP servers:** the server list (name, address, status, tool count, unclassified count). **Add server** takes a name, an `https://` or loopback address and an optional write-only secret, and its tools arrive Unclassified. **Remove** asks first ("Remove Jira? Its 12 tools go at once, and 1 pending approval request for them is canceled."). The tools table has an "Unclassified only" filter and a `role="radiogroup"` per tool ("Unclassified (counts as risky)", "Read-only", "Risky"; the selected option shows a check icon) that saves at once with "Saved". A changed tool gets `settings.toolChangedBanner`.
- **Source-poll form:** the `settings.source*` keys ("Use as a source", "Source name", "Arguments (JSON)", "Check every"). A tool that isn't Read-only can't be chosen, and "Only a Read-only tool can be a source." shows beside it.
- **Tool-call card:** "Approval needed", "Why:", "Run {tool} on {server}", the inputs as labelled lines, "No dry run is available for this tool. Approving runs exactly this call once.", Approve, Reject and the expiry. The rail, phone and Telegram carry the same content as plain text, and the first answer wins. A cancelled request shows `answered.canceled`, its buttons stop everywhere, and it leaves the rail within one live update. A standalone fix shows "Why:" and a dry run with the exact text and every recipient.

## Cross-Story Dependencies

- **Order:** 21.8 is next (it extends 21.3's client and the `EmailIn`/`EmailOut` adapters), then 21.4, then 21.5 (sources use only tools 21.4 classified).
- **Lane A:** 22.2 and 22.8 are done, and 22.3, 22.4 and 22.9 are ready-for-dev. Not built yet: 22.4 (raises and cancels `tool_call` requests), 22.5 (runs source polls) and 22.7 (the email tool and the email fix kind). Test against fixture requests and a `McpOps` test double until they merge.
- **Contention:** the DW-1041 write lands in `Mcp/Ops.cls`, a Lane A file Epic 22 is also changing.
- **Downstream:** Story 24.3 sends pages by email through `EmailOut` and the `email` renderer, and Story 23.5 now sends through the SimMailbox channel instead.
