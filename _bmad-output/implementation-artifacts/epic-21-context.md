# Epic 21 Context: Email, webhooks and MCP settings (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Lane B's step 4 feature epic. An admin connects a real mailbox (POP3 read, SMTP send, or Gmail and Microsoft 365 through OAuth2), so each new email becomes an untrusted item with its own attention decision, and OcuTalon can email the user, including the daily digest. Admins also add, remove and classify MCP servers and their tools in Settings, set read-only tools up as source polls, and answer tool-call approval requests on every channel. The epic builds on contracts Epic 35 fixed. Story 21.1 became Story 35.2. Webhooks moved to Story 35.3 (parked until after voting), so this epic ships no webhook work despite its title. Story 21.2 was split at its spec gate: 21.2 is the POP3 read (done), 21.6 the SMTP send, 21.7 the digest by email.

## Stories

- Story 21.2: Read a mailbox over POP3 (done)
- Story 21.3: Sign in to Gmail and Microsoft 365 with OAuth2
- Story 21.4: Add, remove and classify MCP servers and tools in Settings
- Story 21.5: Set up source polls and answer tool-call approval requests
- Story 21.6: Send email over SMTP
- Story 21.7: Send the daily digest by email

## Requirements & Constraints

- **Online demo safety (standing rule, overrides any AC or spine text about "preconfigured" or "allow-listed" demo servers):** real mail, OAuth and MCP endpoints never run on the online demo. The simulated mailbox stays; `EmailIn`/`EmailOut` stay disabled; the email, OAuth, MCP and source-poll settings are off; the demo account sees no settings; nobody can add or remove a server, and the demo says so in a plain line (public text settled at 21.4's spec gate).
- **Secrets:** every secret field is write-only; any admin value containing `@{` is refused; no command, message, log, trace, audit entry, global or test output holds a secret, only a reference. Homes: mail passwords in Interoperability credentials; OAuth2 tokens and client secrets only inside IRIS's OAuth2 client; MCP secrets in the IRIS Wallet, referenced from Config Store entry `AI.MCP.OcuTalon_<server>`.
- **Outbound email (21.6, 21.7):** only to the session user's own address. A `SendEmail` from origin `tool` reaches `EmailOut` only when every recipient is that address (Lane A's email tool, 22.7, relies on this). The digest goes as plain catalog-rendered text, recorded as a `Delivery`; email is offered as a digest channel only once a mailbox is connected.
- **Settings changes** apply within a minute and are audited without secrets (OAuth connect/remove entries hold no client secret or token).
- **OAuth2 (21.3):** a revoked grant gives a failed poll with a plain reason and the mailbox counts as not checked; fresh tokens come without admin help.
- **Only accepted text ships:** texts come from the keys accepted for Story 35.2 (`settings.*`, `answered.canceled`, in `OcuTalon.Msg.Catalog.Core`). New public text (21.3's README and redirect-address guidance, 21.4's demo line) goes to the author first.
- **CI:** stubs in the CI-only override (`ci/mock`): the POP3 stub exists (21.2); 21.6 adds an SMTP stub that receives mail, and no real email is ever sent.

## Technical Decisions

- **Lanes:** Lane B owns `Core/**`, `Web/**`, `Channel/**`, `Data/**` (Lane B tables), `Msg/Command/**`, `Msg/Catalog/Core.cls`, `web/`, and items `EmailIn`/`EmailOut`. Lane A owns `Mcp/**`, `src/bridge/**`, `Install/**`, `Msg/Catalog/Watch.cls` and `Digest.Process`.
- **Commands (AD-1):** every change is a production message submitted with origin `web_admin` from admin-checked routes. REST code never writes the wallet, the Config Store or credentials.
- **Secret path (settled by 21.2):** the REST process hands a secret to the operation through `OcuTalon.Core.SecretHandoff` (in-memory, single take); the command carries only `secret://handoff/<name>`. Reuse it for the SMTP password, the OAuth2 client secret and the MCP secret.
- **Email (21.2 delivered):** `EmailIn` with its own POP3 adapter, `Data.MailSeen` for no-repeats, `SettingsOps.SaveEmail` (sole writer of `email.address`/`email.owner`; the mailbox moves to the last saving admin), route `POST /api/v1/settings/channels`. Poll outcome lives in status mark `emailPoll` (`at`, `ok`, `reason`, `lastOkAt`; reason never holds server text, an address or a credential). `EmailOut` is not yet a production item; 21.6 adds it and validates recipients and CR/LF in `Subject`.
- **DW-1139 (21.6):** `SaveEmail` starts the production update only when a row changed, so an identical re-save after a failed update leaves the item unapplied; fix it on the shared apply path.
- **Digest by email (21.7, Contest Planner ruling):** route through Notify, which gains the email channel; `Digest.Process` keeps building content and gets no email knowledge (DW-820). Add the `email` channel to `OcuTalon.Msg.Catalog.Render` as plain text under the `phone` channel's rules, and test every key `EmailOut` sends.
- **OAuth2 (21.3):** one class switches to `%SYS` to register the IRIS OAuth2 client and joins AD-3's namespace-switching list in the same change; `EmailIn`/`EmailOut` use the adapters' OAuth2 settings.
- **MCP (21.4):** `OcuTalon.Mcp.Ops` (item `McpOps`, Lane A, from 22.2) now handles `AddMcpServer`/`RemoveMcpServer`/`ClassifyTool` (rows, grant, audit, `RestartRunners`) and `Tools(server)` is real. It does **not** yet write the Config Store entry or wallet secret. **DW-1041 (ruled, owned by 21.4):** that write moves into `McpOps`, never the REST process; AD-1 unchanged. 21.4 replaces the `SettingsOps.SaveMcpEntry`/`RemoveMcpEntry` stubs (error 5003) and the pins in `Test.Core.CommandsStep4` (`TestMcpEntryStubs`, `TestNoMcpSettingsRoute`) on purpose.
- **REST rows to build, each with real-HTTP route tests:** `GET /api/v1/settings/mcp`, `POST /api/v1/settings/mcp/servers`, `DELETE /api/v1/settings/mcp/servers/<server>`, `POST /api/v1/settings/mcp/classify` (21.4); `POST /api/v1/settings/mcp/sources`, `DELETE /api/v1/settings/mcp/sources/<ref>` (21.5).
- **Approvals with no incident (21.5, AD-31/32):** for `tool_call` requests and standalone email fixes, `OcuTalon.Core.BridgeSink` sends `approval`, `answered` and `result` through `NoticesIn`; `IncidentManager` covers only an incident's fix requests.
- **Catalog quirk:** `settings.refusedExpansion` takes `@{` as the slot `marker`.

## UX & Interaction Patterns

- **Settings > Channels > Email:** address, POP3 server, SMTP server, user, write-only password; OAuth2 adds Client ID, Client secret and "Sign in with {provider}" (consent opens in a new tab). Secret fields show `settings.secretSet`/`settings.secretNotSet`; a save shows "Saved. Applies within a minute. Recorded in the audit log."
- **Settings > Tools and MCP servers:** server list (name, address, status, tool count, unclassified count); Add server (name, `https://` or loopback address, optional write-only secret; tools arrive Unclassified); Remove asks first ("Remove Jira? Its 12 tools go at once, and 1 pending approval request for them is canceled."); tools table filterable "Unclassified only", each with a `role="radiogroup"` ("Unclassified (counts as risky)", "Read-only", "Risky"; check icon on selection) that saves at once and confirms "Saved"; a changed tool gets the `settings.toolChangedBanner`.
- **Source-poll form:** `settings.source*` keys; a non-Read-only tool can't be chosen, with the reason beside it.
- **Tool-call card:** "Approval needed", "Why:", "Run {tool} on {server}", inputs as labelled lines, "No dry run is available for this tool. Approving runs exactly this call once.", Approve, Reject, expiry. Rail, phone and Telegram carry the same as plain text; first answer wins; a cancelled request shows `answered.canceled`, its buttons stop everywhere and it leaves the rail within one live update. Standalone fixes show "Why:" and a dry run with exact text and every recipient.

## Cross-Story Dependencies

- **Order:** 21.2 (done), 21.6, 21.3, 21.7, 21.4, 21.5. 21.3 reuses `EmailIn`/`EmailOut`; 21.7 needs `EmailOut` from 21.6; 21.5 sources only tools 21.4 classified.
- **Lane A:** 22.2 is merged (`McpOps`, `Mcp.ToolClassification`, `Mcp.Attach`, real `Tools`). Not merged: 22.4 (raises/cancels `tool_call` requests), 22.5 (runs source polls; `McpOps` has no `SetSourcePoll` handler yet, reads `emailPoll`), 22.7 (email tool and email fix kind). Until then, test against fixture requests and a `McpOps` test double.
- **DW-1041 contention:** the wallet/Config Store write lands in `Mcp/Ops.cls`, a Lane A file contended with Epic 22; 21.4 must also reconcile spine passages that still say routes call `SettingsOps.SaveMcpEntry`.
- **Open rulings:** 21.3's AD-3 amendment and README text.
