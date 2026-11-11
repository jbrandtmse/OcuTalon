# Epic 21 Context: Email, webhooks and MCP settings (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Lane B's step 4 feature epic, reopened 2026-11-11. An admin connects a real mailbox (POP3/SMTP, or Gmail and Microsoft 365 through OAuth2), so each new email becomes an untrusted item with its own attention decision and OcuTalon can email the user, including the daily digest. Admins also add, remove and classify MCP servers and their tools in Settings, set read-only tools up as source polls, and answer tool-call approval requests on every channel. The epic builds on the contracts that Epic 35 fixed (35.1 and 35.2 are merged). Story 21.1 became Story 35.2. The webhook work moved to Story 35.3, which is parked until after voting, so this epic ships no webhook work despite its title.

## Stories

- Story 21.2: Read a mailbox and send email over POP3 and SMTP
- Story 21.3: Sign in to Gmail and Microsoft 365 with OAuth2
- Story 21.4: Add, remove and classify MCP servers and tools in Settings
- Story 21.5: Set up source polls and answer tool-call approval requests

## Requirements & Constraints

- **Online demo safety (standing rule):** real mail servers, OAuth and real MCP servers never run on the online demo. The simulated mailbox (`SimMailbox`) stays. The new Settings sections (email, OAuth, Tools and MCP servers, source polls) are off on a demo install, `EmailIn` and `EmailOut` stay disabled, the demo account sees no settings, and nobody can add or remove a server. Where an AC or the spine mentions demo servers that are "preconfigured" or "allow-listed", this rule overrides it.
- **Secrets:**
  - Every secret field is write-only.
  - Any admin value containing `@{` is refused.
  - No command, message, log line, audit entry, test output or record ever holds a secret value. Only a `secret://` reference is allowed.
  - Audit entries never hold a password, client secret or token.
- **Homes for credentials:**
  - Mail passwords go in Interoperability credentials.
  - OAuth2 tokens and client secrets stay inside IRIS's OAuth2 client. OcuTalon keeps no copy.
  - MCP secrets go in the IRIS Wallet, referenced from the Config Store entry `AI.MCP.OcuTalon_<server>`.
- **Email intake:**
  - Only mail that arrives after the mailbox was connected becomes an item: one untrusted Item per email, sent to `Intake`.
  - Mail stays on the server (`DeleteMessage` off).
  - An email that was already seen never becomes an item again, even after a restart.
  - The mailbox belongs to the admin's session.
- **Outbound email:** email goes only to the session user's own address. The digest goes out as plain text rendered from the catalog and is recorded as a `Delivery`.
- **Only accepted text ships.** The texts come from the 30 keys accepted for Story 35.2 (EXPERIENCE.md > Message Catalog > "Settings and requests (step 4)", in `OcuTalon.Msg.Catalog.Core`, with the `settings.*` keys and `answered.canceled`). Any text not in that set (for example, 21.3's README and the redirect-address guidance) must go to the author first.
- **CI:** a POP3/SMTP stub in the CI-only override serves fixture mail. The tests cover:
  - one item per new email;
  - no repeats after a restart;
  - untrusted provenance;
  - mail left on the server;
  - a failed poll recorded with its reason.

## Technical Decisions

- **Lanes:** this is Lane B. Lane B files are `Core/**`, `Web/**`, `Channel/**`, `Data/**` (Lane B tables), `Msg/Command/**`, `Msg/Catalog/Core.cls` and `web/`. `Mcp/**`, `src/bridge/**`, `Install/**` and `Msg/Catalog/Watch.cls` belong to Lane A. Production items `EmailIn` and `EmailOut` (`OcuTalon.Channel.Email.In` and `.Out`) are Lane B.
- **Commands (AD-1):** every change is a production message, and the web layer submits it with origin `web_admin` from routes that check for an admin first. REST code may write only the Session row, counters, pairing hashes and UI markers. It never writes the wallet, the Config Store or credentials.
- **Contracts fixed by Story 35.2 (already in code, so build on them):**
  - **`SendEmail`** (`Recipients` as a comma list, `Subject`, `Text`) goes to `EmailOut`.
    - From origin `tool`, it is accepted only when every recipient equals `email.address`, ignoring case and spaces. `email.owner` must be the command's SessionRef, and inside a bridge context the SessionRef must be the context's OwnerRef. An empty list, a missing address or any other recipient is refused (`not_allowed`) and nothing is sent.
    - From origin `system`, it carries `FixExecutor`'s approved email fix.
    - Story 21.2 makes `SettingsOps` the only writer of the product keys `email.address` and `email.owner`. `EmailOut` validates the values, including CR/LF in `Subject`.
  - **The MCP verbs in `CommandsIn`** are `AddMcpServer(Server, Url, ActingUser)`, `RemoveMcpServer(Server, ActingUser)`, `ClassifyTool(Server, Tool, Classification = unclassified|read-only|risky, ActingUser)`, `SetSourcePoll(Server, Tool, Name, Arguments as JSON text, IntervalMinutes, ActingUser)` and `RemoveSourcePoll(SourceRef, ActingUser)`.
    - They go to `McpOps` and are accepted from `web_admin` only. From `tool` the refusal uses the chat text; from any other origin it uses the admin-only text.
    - No verb carries a secret.
    - `McpOps` is not a production item yet, so an accepted verb answers `failed` until Story 22.2 adds it. Tests use the `CommandsInProbe` and `CommandsOwner` stand-ins.
  - **MCP settings path, now stubs:** `SettingsOps.SaveMcpEntry` and `RemoveMcpEntry` return error 5003 and write nothing. `Web.Api` has no `/v1/settings/mcp` route. `Test.Core.CommandsStep4` pins both (`TestMcpEntryStubs` checks the wallet and the Config Store; `TestNoMcpSettingsRoute`), so Story 21.4 must replace those pins on purpose. `POST /v1/settings/channels` still answers 501 (`NotBuilt`).
  - **Poll outcome:** the status mark `emailPoll` (`StatusMark.Record`) holds a JSON object with `at` (UTC), `ok` (1 or 0), `reason` and `lastOkAt`.
    - `reason` is plain English and never holds server text, an address or a credential.
    - There is one mark, holding the latest outcome.
    - Lane A's `Checks.Coverage` (Story 22.5) reads it.
  - **Also delivered:** `SettingsOps.RestartRunners()`, `Ownership.AdminSessions()` with `Session.AdminAtSignIn`, `Core.Admin.Held()` (whole-name `OcuTalonAdmin`, never `%All`), and the `Tools(server)` stub on `OcuTalon.Mcp.Ops` (35.1), which returns OK with an empty array.
- **Spine REST rows to build:**
  - `POST /api/v1/settings/channels`: the mailbox (21.2).
  - `GET /api/v1/settings/mcp`: servers with their attach reports, plus `Tools(server)` (21.4).
  - `POST /api/v1/settings/mcp/servers` and `DELETE /api/v1/settings/mcp/servers/<server>` (21.4).
  - `POST /api/v1/settings/mcp/classify` (21.4).
  - `POST /api/v1/settings/mcp/sources` and `DELETE /api/v1/settings/mcp/sources/<ref>` (21.5).
  - Each route needs the standing real-HTTP route tests.
- **DW-1041 (ruled, owned by 21.4):** the MCP settings write (wallet secret and the `AI.MCP.OcuTalon_<server>` entry) moves into `McpOps`, an operation. It never runs in the REST process, and AD-1 stays unchanged. `McpOps` then calls `RestartRunners()`.
- **OAuth2 (21.3):** the IRIS OAuth2 client is registered by one class that switches to `%SYS`. That class joins AD-3's list of namespace-switching classes in the same change. The adapters' OAuth2 settings fetch fresh tokens. A revoked grant gives a failed poll with a plain reason, and the mailbox counts as not checked.
- **Approval notices with no incident (21.5, AD-31/32):** for `tool_call` requests and the standalone email fix, `OcuTalon.Core.BridgeSink` sends the `approval`, `answered` and `result` Notifications through `NoticesIn`. `IncidentManager` covers only an incident's fix requests. A cancelled request (its server was removed) stops its buttons on every channel and leaves the rail within one live update.
- **Rendering (21.2):** add the `email` channel to `OcuTalon.Msg.Catalog.Render` as plain text under the `phone` channel's rules, and test every key `EmailOut` sends.
- **Catalog quirk:** `settings.refusedExpansion` stores the two characters `@{` as a text slot named `marker`, so a producer passes them as the slot value.

## UX & Interaction Patterns

- **Settings > Channels > Email:** the fields are the address, the POP3 server, the SMTP server, a user name and a write-only password. For OAuth2 the fields are Client ID, Client secret and "Sign in with {provider}" (Google or Microsoft 365), which opens the consent page in a new tab.
  - A field holding a secret shows `settings.secretSet`; an empty one shows `settings.secretNotSet`.
  - A save shows "Saved. Applies within a minute. Recorded in the audit log."
- **Daily digest:** email is offered as a channel only once a mailbox is connected.
- **Settings > Tools and MCP servers:**
  - **The server list:** name, address, status, tool count and count of unclassified tools.
  - **Add server:** a name, an `https://` address (or loopback in development) and an optional write-only secret. Tools arrive Unclassified.
  - **Remove:** a dialog asks first, using the fixture text "Remove Jira? Its 12 tools go at once, and 1 pending approval request for them is canceled."
  - **The tools table:** filterable with "Unclassified only". Each tool has a `role="radiogroup"` control ("Unclassified (counts as risky)", "Read-only", "Risky"; D `classification-*`; a check icon on the selected option). It saves at once and confirms with "Saved".
  - **Changed tool:** the banner `settings.toolChangedBanner` names it.
- **Source-poll form:** the `settings.source*` keys. A tool that isn't Read-only can't be chosen, and the reason shows beside it.
- **Tool-call card:**
  - It shows "Approval needed", "Why:", "Run {tool} on {server}", the inputs as labelled lines, and "No dry run is available for this tool. Approving runs exactly this call once."
  - It has **Approve** and **Reject** and shows the expiry.
  - The rail, the phone and Telegram carry the same content as plain text, and the first answer wins.
  - The canceled status is `answered.canceled`.

## Cross-Story Dependencies

- **Lane A dependencies, none merged yet (Epic 22 is in backlog):**
  - 22.2 builds `McpOps` and the real `Tools(server)`.
  - 22.4 raises and cancels `tool_call` requests.
  - 22.5 runs source polls and reads `emailPoll`.
  - 22.7 adds the email tool and the email fix kind.
  - Until those merge, Epic 21 tests against stubs, fixture requests and a `McpOps` test double.
- **Order inside the epic:** 21.2 comes before 21.3, because OAuth reuses `EmailIn` and `EmailOut`. 21.4 comes before 21.5, because 21.5 sources only Read-only tools that 21.4 classified.
- **Open points that each spec must settle:**
  - **DW-1041 crosses lanes.** It puts the wallet and Config Store write inside `McpOps` (`Mcp/Ops.cls`, a Lane A file that is contended with Epic 22). Three spine passages still say `SettingsOps.SaveMcpEntry` is called from the routes: AD-21 Names, the cross-area row and the REST rows. 21.4 must reconcile them.
  - **Mail passwords and the OAuth2 client secret** face the same REST-write limit as DW-1041. "Story 21.2 fixes how" is still open.
  - **21.3's AD-3 amendment** and its README text each need a ruling.
  - **DW-1042 reopens** if 21.2 lets the mailbox move between sessions.
