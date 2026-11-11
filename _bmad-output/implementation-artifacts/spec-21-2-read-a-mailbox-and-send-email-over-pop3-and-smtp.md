---
title: 'Story 21.2: Connect a mailbox and read it over POP3 (first child of 21.2)'
type: 'feature'
created: '2026-11-11'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-35-2-fix-lane-b-s-step-4-contracts-and-send-events-to-ocutalon-th.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** An admin cannot connect a real mailbox: `POST /api/v1/settings/channels` answers 501, there is no `EmailIn` item, no home for the mail password that keeps it out of every command and message (AD-19 leaves "how" to this story), and nothing writes `email.address`/`email.owner` (Story 35.2's own-address rule) or the `emailPoll` mark.

**Approach:** Settings > Channels gains an Email form (address, POP3 server, user name, write-only password). The route hands the password to `SettingsOps` through a new in-memory hand-off (`OcuTalon.Core.SecretHandoff`, `$SYSTEM.Event`), never a command; `SettingsOps` writes the Interoperability credential `OcuTalonMail`, the product keys and `EmailIn`'s System Default Settings, and starts the item. `EmailIn` polls with its own adapter (a subclass of `EnsLib.EMail.InboundAdapter`): never deletes mail, remembers seen UIDLs in a new Lane B table, makes one untrusted Item per new email for `Intake`, and records each poll in `emailPoll`. Sending (SMTP, `EmailOut`) and the digest by email are proposed siblings (Design Notes, "Proposed split").

## Boundaries & Constraints

**Always:** Lane B files and the Epic 21 footprint only; a NEW file in a contended folder or one self-contained append to a contended file, each reported (Design Notes, "Contended files"). The password never enters a command, message, global outside the credential store, log line, audit entry, test output or the trace; commands carry only `secret://handoff/<ref>`. `SettingsOps` is the only writer of the credential, the `email.*` keys and `EmailIn`'s System Default Settings; REST writes none of them (AD-1, AD-19). Every value holding `@{` is refused and nothing changes. TLS always (`OcuTalonClient`, server identity checked); mail is never deleted. On the online demo the email section is absent, the route refuses before anything is offered or submitted, and `EmailIn` stays disabled. Ship only accepted wording (the 35.2 `settings.*` keys, existing page strings, and this spec's Public text rows once accepted). ASCII-only source (Rule 14); comments state the contract.

**Never:** a Lane A file (`Install/**`, `Digest/**`, `Mcp/**`, `src/bridge/**`, `Msg/Catalog/Watch.cls`, Lane A tests); `EmailOut`, SMTP, the `settings.emailOutgoing` field, the digest by email or the `email` render channel (proposed siblings); OAuth2 (21.3); `Ens.Director.EnableConfigItem` or any save of the production definition (it rewrites `Production.cls` without the lane markers); a plain-text POP3 option in the product; a real mail server or real credentials in any test or CI run; a new role, grant or web application; a new `ci/units.sh` unit or group.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First save | admin, local install; `{address, incoming, user, password}` all valid, no mailbox yet | 200 `{"result":"done","sections"}`; credential `OcuTalonMail` (user, password); `email.address`, `email.owner` = admin's SessionRef; `EmailIn` SDS rows `POP3Server`, `POP3Port`, `Credentials`, `SSLConfig` (`OcuTalonClient`, or `OcuTalonClient*` for port 110), `Enabled` 1; `EmailIn` runs within 60 s; one Settings audit entry per changed field, password entry `to` "set", address and user `to` "set"/"changed" (no value) | -- |
| Save, password omitted or "" | credential exists | password kept, other changes applied | no credential yet: 400 `bad_settings` `["password"]`, nothing changed |
| Refused value | any field holding `@{`; bad address; server not `host` or `host:port` (1-65535); empty user; password with a control character or over 256 chars; unknown or missing field; body not an object | 400 `bad_settings` naming every refused field; nothing written, offered secret withdrawn, nothing audited | -- |
| Non-admin | LIVE fixture user (OcuTalonUser only) | 403 `not_admin` before the body is read; nothing offered or submitted | -- |
| Online demo | `onlineDemo` 1, any body | 409 `not_available` (Public text P2); nothing offered, submitted, written; `EmailIn` SDS untouched; GET has no `channels` section | `SettingsOps` also refuses `not_available` |
| Other admin saves | mailbox owned by session A; admin B saves | `email.owner` = B; audited | -- |
| Hand-off lost | the reference names no offered secret (expired, taken, wrong) | `refused` naming `password`; nothing written | -- |
| First poll | mailbox new to `EmailIn` (identity = hash of server, port, user) | every listed UIDL recorded seen (baseline row), no Item; `emailPoll` `ok` 1 | -- |
| New mail | 3 new UIDLs | 3 Items to `Intake`: `Channel` email, `Provenance` untrusted, `SessionRef` = `email.owner`, Sender/Subject/Text from the mail, own trace session under the owner's `TraceRef`; nothing deleted on the server | at most 10 per poll; rest next poll |
| Seen mail | UIDLs already recorded, also after an item or production restart | no Item | -- |
| Large or HTML mail | over 1,048,576 bytes; HTML-only body | headers only: Sender, Subject, empty Text; HTML tags removed, Text cut to 10,000 chars | -- |
| Failed poll | unreachable or TLS failure; PASS refused; other error | `emailPoll` `{at, ok:0, reason, lastOkAt}` with reason P1a, P1b or P1c; no server text, address or credential anywhere | seen rows of Items already sent stay |
| Gone mail | a seen UIDL no longer listed | its row deleted after the successful poll | -- |
| Tool email after save | owner session; `SendEmail` to the saved address from origin `tool` | `CommandsIn` routes it to `EmailOut` (stand-in records it) | other session or address: `not_allowed` |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- UrlMap `/v1/settings/channels` -> `NotBuilt` :261; `OnPreDispatch` admin gate :283-305, `IsSettingsUrl` :326; `SaveSection` :900 (pattern for the new route); `Answer` :936 (outcome -> status map; add `not_available` -> 409); `SettingsBody`; `NotBuilt` :984.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- class doc 1-66; `ALLOWLIST` :71; `Carry` :143; `AuditData` :190, `Stored` :204, `WriteAudit` :211, `Apply` :218; `OnlineDemo` :660; `XData Sections` :801 (doc: "A section without a row here (Channels) has no save yet"); `Values` :848; `Save` :914 (kind branch, like `models` -> `SaveModels` :1108); `Field` :956; `SaveProduct` :1000 (audit-then-row transaction pattern).
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:134-147` -- `OwnAddressOnly` reads `email.address`/`email.owner` through `Setting.Get`'s 60 s cache (DW-1042).
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls:39` -- `Get` (cached); uncached read = `KeyIndexOpen(key)` as `SettingsOps.Stored` does.
- `src/ocutalon/cls/OcuTalon/Channel/SimMailbox/In.cls` -- sibling: untrusted Item to `Intake`, `%SuperSession` = session `TraceRef`, private `Send` seam, `BODYMAX` 10000.
- `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls:21,39` -- `Record(mark, value)`, `Get(mark)`; `emailPoll` contract: spine AD-14 "Email (step 4)".
- `src/ocutalon/cls/OcuTalon/Production.cls` -- lane B region (between its markers): `EmailIn` is added there, `Enabled="false"`, `CallInterval` 60.
- `src/ocutalon/cls/OcuTalon/Install/Step/SSL.cls:12` -- `OcuTalonClient` (VerifyPeer 1, OS CA store). `Install/Step/Production.cls:186` -- an `Enabled` SDS overrides the definition's flag (read-only reference).
- `src/ocutalon/cls/OcuTalon/Data/Handled.cls` -- Lane B table sibling (storage `^OcuTalonP.HandledD` naming).
- IRIS (read, never load): `irislib/EnsLib/EMail/InboundAdapter.cls` -- `DeleteMessage` default 1 :50; `OnTask` :84-190 re-reads every message each poll, logs From/To/Subject :171, has no seen tracking ("Service code responsibility", :49) -- why a subclass replaces `OnTask`; OAuth2 token block :101-112 (keep for 21.3). `irislib/%Net/POP3.cls` -- `ConnectPort` :61 (TLS :74-79, STLS :92-100, USER/PASS :126-142), `GetSizeOfMessages` :194, `GetMessageUIDArray` :230, `Fetch` :291, `FetchMessageHeaders` :614. `irislib/Ens/Config/Credentials.cls:72` `SetCredential(name, user, password, overwrite)` (password to the secondary store). `irislib/%SYSTEM/Event.cls` -- Create, Signal(name, message), WaitMsg, Delete.
- Web: `web/src/app/settings/channels-section.ts` (Telegram block; contended with 35.3); `settings-view.ts` `SETTINGS_TEXTS` (`save`, `saved`, `failed`), `refusalKind`; `refusal.ts`; `check-thresholds-section.ts` (field-error pattern); `web/src/app/api/api-types.ts:228` `SettingsSections`; `api-client.ts:61` section save; `web/scripts/ux-strings.test.mjs:42-61` view-module list + SOURCES.
- Mock: `ci/mock/server.mjs` (entry, arg parsing), `ci/mock/mock.mjs:305,630` (`/_mock/telegram/` control pattern); `ci/compose.ci.yml` (no change: the stub port stays inside the compose network).
- Test pins: `Test/Web/Api.cls:999` (route list: `POST /v1/settings/channels NotBuilt`); `Test/Core/SettingsSave.cls` `TestAllowList` :392, `TestValues` :414; `Test/Web/SettingsApi.cls` `TestNonAdminIs403Everywhere` :107, `TestGetShape` :150; `Test/Data/Tables.cls` (table contracts); `Test/Core/SettingsOpsProbe.cls` (audit seam), `Test/Core/PrecedentOpsProbe.cls:38` (online-demo seam pattern); `Test/Core/InProduction.cls` (base, throwaway/CI only); `web/e2e/settings/settings.spec.ts:16,82` (section list, unchanged).

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first, record under Design Notes "Measured", label anything unmeasured (inference)) on the lane-C warm stack: (a) a secret offered by a CSP request of an admin without `%All` reaches `SettingsOps`' job through `SecretHandoff` and `Delete` discards it; (b) an `Enabled` SDS row of 1 plus `Ens.Director.UpdateProduction()` starts the definition-disabled `EmailIn` in the running production, and changed adapter SDS apply on its restart (else the restart pattern of `Bridge.Timeouts.Restart`; never `EnableConfigItem`); (c) the `%Net.POP3` error codes for a refused connection, a TLS failure and a `-ERR` after `PASS` (stub-driven) to classify P1a-P1c; (d) Subject/From decoding and part selection of `%Net.MailMessage`; (e) implicit TLS and STARTTLS (`*`) of `%Net.POP3` against a scratch-only TLS wrapper of the stub with a scratch certificate and a scratch SSL configuration (files only in the session scratch folder, never committed); if STARTTLS fails, port 110 is refused at save instead.
- `src/ocutalon/cls/OcuTalon/Core/SecretHandoff.cls` -- new: `Offer(secret, Output reference) As %Status` (random Ref, named resource, `Signal` with the secret; returns `secret://handoff/<ref>`), `Take(reference, Output secret, seconds=2) As %Status` (`WaitMsg`, then `Delete`), `Withdraw(reference)` (`Delete`). Never logs or stores the secret; refuses any other reference form.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `/v1/settings/channels` -> new `SaveChannels`: online demo -> 409 `not_available` before reading the body; body object check; a non-empty string password over 256 chars -> 400 `["password"]` without an offer; otherwise `Offer` it and put the reference in `Changes.password`; submit `SaveSettings` (slug `channels`, origin `web_admin`, `$USERNAME`, CSP SessionRef); `Withdraw` always; `Answer` maps `not_available` -> 409. Class doc updated.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `XData Sections` row `{"slug":"channels","kind":"email","fields":[address,incoming,user,password]}`; `ALLOWLIST` += `email.address,email.owner`; `Save` branches kind `email` to `SaveEmail`: online demo -> `not_available` (P2); validate every field (matrix row 3), `Take` the password; audit-then-write in one transaction as `SaveProduct` (address/user forms "set"/"changed", password "set", incoming host:port as is, `email.owner` from/to Refs); then `SetCredential("OcuTalonMail", user, password, 1)`, the `EmailIn` SDS rows and the start/restart of Task 0 (b). A failure after the transaction puts the old keys back and audits that (as `PutBack`). `Values` adds `channels` `{address, incoming, user, passwordSet}` (never on the online demo; user from the credential). Class doc: one paragraph.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `OwnAddressOnly` reads both keys from their rows (uncached), closing DW-1042's stale pair.
- `src/ocutalon/cls/OcuTalon/Data/MailSeen.cls` -- new Lane B table: `Mailbox` (SHA-256 hex of server, port, user), `Uidl` (MAXLEN 70), `Baseline` %Boolean, `SeenAt`; unique (Mailbox, Uidl); written only by `EmailIn`; storage `^OcuTalonP.MailSeen*`.
- `src/ocutalon/cls/OcuTalon/Channel/Email/Adapter.cls` -- new, `Extends EnsLib.EMail.InboundAdapter`; `DeleteMessage` forced 0; `OnTask`: credentials (+ parent's OAuth2 token lines), connect, `GetMessageUIDArray`, baseline or new UIDLs (oldest first, at most `NEWMAX` 10), size check (`MAXBYTES` 1048576), fetch, `BusinessHost.ProcessInput(mail)` per email, `QuitAndCommit` (no delete); seen bookkeeping in `Data.MailSeen`; `emailPoll` after every poll; logs counts only.
- `src/ocutalon/cls/OcuTalon/Channel/Email/In.cls` -- new `Ens.BusinessService` (`ADAPTER` above); builds the Item as `SimMailbox.In` does (owner from the `email.owner` row, `%SuperSession` = owner's `TraceRef`, private `Send` seam to `Intake`); `Channel/Email/Mail.cls` -- new carrier (UIDL, From, Subject, Text).
- `src/ocutalon/cls/OcuTalon/Production.cls` -- lane B region: `<Item Name="EmailIn" ClassName="OcuTalon.Channel.Email.In" PoolSize="1" Enabled="false">` with `CallInterval` 60 (one self-contained append).
- `web/src/app/settings/email-view.ts` (new: `EMAIL_TEXTS` from the 35.2 keys `settings.emailHeading`, `emailHelp`, `emailAddress`, `emailAddressHelp`, `emailIncoming`, `emailUser`, `emailPassword`, `secretSet`, `secretNotSet`, `refusedExpansion`; body and dirty rules) and `email-section.ts` (new: the form; write-only password never pre-filled; a refused field shows `refusedExpansion` when its typed value holds `@{`, else `SETTINGS_TEXTS.failed`; saved shows `SETTINGS_TEXTS.saved`; hidden when the snapshot's `onlineDemo` is true); `channels-section.ts` -- one appended `<app-email-section />` block and its import; `web/src/app/api/api-types.ts` -- `SettingsSections.channels?`; `web/scripts/ux-strings.test.mjs` -- one view-module entry and `ux` SOURCES rows.
- `ci/mock/mail.mjs` (new POP3 stub: USER, PASS, STAT, LIST, UIDL, TOP, RETR, DELE counted but never applied, QUIT; fixture mailbox and failure modes set through `/_mock/mail/...` on 8080, state read back incl. delete count), one self-contained start block in `ci/mock/server.mjs` (`--pop3-port`, default 1110), `ci/mock/test/mail.test.mjs` (new).
- `src/ocutalon/cls/OcuTalon/Test/Core/SecretHandoff.cls`, `Test/Core/SettingsEmail.cls` (probe-driven save rows 1-7, audit content, online demo, all-or-nothing), `Test/Channel/EmailIn.cls` (adapter and service against a stand-in `%Net.POP3` subclass: rows 8-12), `Test/Channel/EmailLive.cls` (Extends `InProduction`, throwaway/CI only: real save through `Commands.Submit` with a hand-off, the stub, items reach `Intake` and a Decision with `OwnerRef` the owner, `EmailIn` restart, no repeats, mail left (stub delete count 0), failed poll reasons, the dummy password found only in the credential: not in any `SaveSettings` body, `Ens.Util.Log` row, recorded audit data or `^OcuTalon*` global; restores everything); `Test/Core/CommandsStep4.cls` -- add the row-13 integration case with keys written by the real save; pins updated: `Test/Web/Api.cls`, `Test/Core/SettingsSave.cls`, `Test/Web/SettingsApi.cls` (channels 403 and online-demo 409), `Test/Data/Tables.cls`.
- `web/e2e/settings/email.spec.ts` -- new (project `sign-in-2`): real HTTP over signed-in sessions: LIVE fixture user 403; README admin 200 and the form's saved text, GET shows `passwordSet` true and no password; a second session's GET of `/v1/state` and chat hold no email item of the first owner's mailbox (isolation); restores the mailbox.
- Spine (`ARCHITECTURE-SPINE.md`, after the spec gate's rulings): S1-S5 of Design Notes with `[ADDED 2026-11-11, Story 21.2]` markers, memlog line, lint (no new finding). `README.md` -- the P3 bullet appended under "New since 1.0.0" once accepted. `EXPERIENCE.md` -- the accepted P1/P2 rows appended to "Settings and requests (step 4)".

**Acceptance Criteria:**
- Given an admin on a local install in Settings > Channels, when they enter the address, POP3 server, user name and password and save, then the page shows "Saved. Applies within a minute. Recorded in the audit log.", `EmailIn` runs and has polled within 60 s, and every matrix row 1-3 and 6-7 holds, observed on the HTTP answer, the credential, the SDS rows, the `email.*` rows and the recorded audit data.
- Given a saved mailbox, when the page reloads, then the password field shows "Saved, and never shown again. Type a new value to replace it." and no response, page or log ever contains the password.
- Given the dummy password of `EmailLive`, when the save and three polls have run, then `Ens.Config.Credentials.GetValue("OcuTalonMail", "Password")` returns it and no `SaveSettings` body, `Ens.Util.Log` row, recorded audit data, `emailPoll` value or `^OcuTalon*` global holds it.
- Given the LIVE fixture user, when it POSTs `/api/v1/settings/channels`, then it gets 403 and nothing is offered, submitted or written; given the online demo, every route call gets 409, `EmailIn` stays disabled and no Email section shows.
- Given a connected mailbox on the stub, when `EmailIn` polls, then matrix rows 8-13 hold, including after an `EmailIn` restart, and the stub reports 0 deletions.
- Given the saved mailbox, when a tool turn of the owner session submits `SendEmail` to the saved address, then `CommandsIn` routes it to `EmailOut` (stand-in), and a second session's identical command is refused (integration with the real keys).
- Given the finished diff, when its paths are listed, then no Lane A path or Never-list item appears, and each contended-file touch is the one Design Notes names.

## Spec Change Log

## Review Triage Log

## Design Notes

**Ledger (Rule 17, lead spec gate 2026-11-11):** DW-1042 re-opened (its reopen_if is met: this story moves the mailbox to the last saving admin) and routed to this story; addressed by the `CommandsIn.cls` task (both keys read uncached) and AC 6 / matrix row 13.

**Spec gate (lead, 2026-11-11):** the proposed split is ruled (decide, doctrine U5): Stories 21.6 (SMTP) and 21.7 (digest by email) are inserted into epics.md with the moved criteria verbatim; order 21.2, 21.6, 21.3, 21.7, 21.4, 21.5. V1-V11, P1-P3 and S1-S5 go to the Contest Planner through the orchestrator before the implement spawn; their rulings are recorded here when they arrive.

**Governing ADs (Rule 6):** AD-1 (commands, origins, REST write list), AD-4 (session ownership), AD-5 (SDS hold changing values), AD-13 (admin-checked settings routes), AD-14 (EmailIn, Items, `emailPoll`), AD-17 (audit without secrets or identities), AD-19 (credential homes, `@{`, `SettingsOps` the only writer, B4 "Story 21.2 fixes how"), AD-22 (CI mock, Lane B mock behaviour), AD-25 (online demo), AD-26 (own trace session), AD-28 (an honest poll outcome), AD-29 (lanes), AD-30 (untrusted Items via `Intake`), AD-33 (one owner per item and table). No AC contradicts an AD Rule; S1-S5 below are extensions (veto items).

**Already met (evidence, not re-done):** `SendEmail` own-address rule and refusal (`CommandsIn.cls:115,134-147`; `Msg/Command/SendEmail.cls`; `Test/Core/CommandsStep4` `TestSendEmailOwnAddress`); the 30 texts incl. the email keys (`Msg/Catalog/Core.cls`, EXPERIENCE "Settings and requests (step 4)"); `email` in `Msg.Enum` CHANNEL (`Msg/Enum.cls:36`); the `emailPoll` shape (spine AD-14) and `StatusMark.Record`; `EmailIn`/`EmailOut` names (spine production items table); the REST row `POST /api/v1/settings/channels`.

**Measured in plan (slot C, OCUTALON, build 154U, read-only apart from a named event resource created and deleted):** a `Signal(name, message)` with no waiter queues the message; a later `WaitMsg` gets `1|<message>`; `Delete` with a message queued discards it (re-created resource: count 0, `WaitMsg` `0|`); a JOBbed process consumed a queued wakeup (count 1 -> 0); the resource name `$Name(^OcuTalonHandoffProbe(...))` created no global. Unmeasured (Task 0 a): the message content across processes and the privilege of a caller without `%All` (inference: no privilege needed).

**Spine edits (after the spec gate; plain unions):** S1 AD-19 sub-bullet: the mail password reaches the credential through `SecretHandoff` (in memory, deleted on take or withdraw, never stored); `OcuTalonMail` holds user and password; server, port, SSL config and `Enabled` are `EmailIn` SDS rows written by `SettingsOps`; the mailbox moves to the last saving admin's session. S2 AD-1 sub-bullet: REST code may offer a secret it received to `SecretHandoff` (no stored state). S3 AD-14 sub-bullet: `EmailIn`'s adapter (no delete, baseline, seen UIDLs, 10 per poll, the size rule). S4 Tables paragraph: Lane B owns `MailSeen` (writer `EmailIn`). S5 AD-22 sub-bullet: the mock's POP3 side and `/_mock/mail/`.

**Decided in-stage:** (1) split (below); (2) "connected" = `EmailIn`'s first successful poll of a mailbox identity: mail present then is baseline, so mail arriving in the seconds before that first poll is not an Item (inference: under 5 s); (3) TLS rule: port 110 -> STARTTLS, any other port implicit TLS, default 995; no plain option; (4) the CI stub is plain TCP; `EmailLive` asserts the save wrote `SSLConfig` `OcuTalonClient` (the first poll then fails, giving the P1a case), then sets the SDS `SSLConfig` to "" and `CallInterval` to 2 as a test-only fixture and restores both; TLS itself is Task 0 (e) (a committed private key would trip `docker/tests/lib-keys.sh`); (5) "no repeats after a restart" uses an `EmailIn` restart in `EmailLive` (persistence is the table's), no production restart; (6) at most 10 new emails per poll, poll every 60 s; (7) audit forms: address and user "set"/"changed" (identities, AD-17), password "set", server host:port as is; (8) no disconnect in this story (proposed for 21.6); (9) DW-1042 resolved here by uncached reads (the mailbox can move); (10) no More-to-try item: the panel is the demo guide's and the online demo (where judges try it) keeps the simulated mailbox; the README line names "on your own install"; (11) page texts are literals in `email-view.ts` equal to the accepted wording (source `ux`); (12) passwords up to 256 characters; (13) EmailIn's tests live in `Test/Channel` (shard piece `lane-a@Channel`, group `production`); `SettingsEmail`/`SecretHandoff` in `Test/Core` (piece `lane-b@Contract,Core,Data,Live`, group `image`); the e2e spec in `live:sign-in-2` (group `shards-4`). No new unit.

**Proposed split (lead rules; plan only this child):**
- **21.2 (this spec): Connect a mailbox and read it over POP3.** Epics criteria 1 (POP3 parts: credentials, address, `EmailIn` host settings, within a minute, audit, ownership), 2 and its And (`emailPoll`), 4 (for `EmailIn` and the settings), 5 (POP3 parts). Criterion 1's And is already met (35.2) except "reaches `EmailOut`", which needs the item.
- **21.6 (new): Send email over SMTP.** Criterion 1's SMTP parts (`settings.emailOutgoing`, `EmailOut` SDS, same credential and TLS rule), its And (`SendEmail` reaches `EmailOut`, sent, `Delivery`; CR/LF in `Subject` refused), 4 for `EmailOut`, 5's SMTP stub (no real email); a Disconnect.
- **21.7 (new): Send the daily digest by email.** Criterion 3 and its And (`email` in `Msg.Catalog` CHANNELS, Daily digest offers email once connected). Open point: `Digest.Process` (Lane A) knows only web, phone, telegram (`CHANNELS`, `ITEMS`, `Own`), so the digest cannot reach `EmailOut` without a Lane A change or DW-820's routing through Notify -- a ruling is needed.
- 21.3 (OAuth) then follows 21.6, since it reuses `EmailIn` and `EmailOut`. Moving criteria to 21.6/21.7 is a veto item (same release).

**Integration ACs (Rule 1):** `Intake` (real) takes `EmailIn`'s Item and records a Decision whose `OwnerRef` is the mailbox owner (`EmailLive`); `CommandsIn` (real) accepts the owner's tool `SendEmail` to the saved address from keys the real save wrote (`CommandsStep4`, AC 6). `emailPoll`: first consumer Story 22.5 (`Checks.Coverage`). `SecretHandoff`: consumer `SettingsOps` here; next Story 21.4.
**Consumed-by:** 21.6 (credential, owner, address, TLS rule, the form), 21.7 (connected state, address), 21.3 (the adapter's OAuth2 settings, the form), 21.4 (`SecretHandoff` for MCP secrets, DW-1041), 22.5 (`emailPoll`), 22.7 (`email.address`/`email.owner`).
**Consumes:** `SettingsOps` save pattern, `Commands.Submit`, `CommandsIn`, `Intake`, `StatusMark.Record`, `Data.Setting`, `Ownership.SessionRef`, `Session.TraceRef`, `Bridge.Ids.NewRef`, `Ens.Config.Credentials`, `EnsLib.EMail.InboundAdapter`, `%Net.POP3`, `$SYSTEM.Event` -- real instances in `EmailLive` and the e2e spec.

**Extend, don't copy (Rule 2):** the adapter extends `EnsLib.EMail.InboundAdapter` (keeps its settings and OAuth2 for 21.3) and replaces `OnTask` -- the parent's re-reads every message each poll and logs addresses; its OAuth2 token lines (~8) are copied for that reason. `EmailIn`'s Item build copies `SimMailbox.In.Accept`'s 9 lines: the sources differ (no allowance, no `SimMessage` row, no live event) and a shared helper would change a class other stories pin. `SaveEmail` reuses `AuditData`, `WriteAudit`, `Apply`, `Stored` and mirrors `SaveProduct`'s transaction; `SaveChannels` extends `SaveSection`'s shape; the form follows `check-thresholds-section.ts`; the stub follows the mock's Telegram control routes; `EmailLive` extends `InProduction`.

**Contended files (reported):** `Web/Api.cls` (one route row changed, one method added; 35.3 adds `/channels/webhooks` beside it), `Test/Web/Api.cls:999` (one list entry renamed), `channels-section.ts` (one block appended), `api-types.ts` (one optional member), `Production.cls` (lane B region, one item), `ci/mock/server.mjs` (one start block), `README.md` (one bullet), `ux-strings.test.mjs` (one list entry, rows). New files in contended folders: `web/src/app/settings/email-*.ts`, `web/e2e/settings/email.spec.ts`, `ci/mock/mail.mjs`. **Footprint extensions:** `web/scripts/ux-strings.test.mjs`, `Channel/Email/**` (listed as `Email*`), `Data/MailSeen.cls` (AD-33 table).

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| V1 | How the mail password is handled: `SecretHandoff` over `$SYSTEM.Event` (memory only), AD-1 and AD-19 sub-bullets S1-S2 | approve | route refuses before any offer |
| V2 | Credential store: Interoperability credential `OcuTalonMail`, written only by `SettingsOps` | approve | never written |
| V3 | New table `Data.MailSeen` (hashed mailbox id, UIDL, flag, time); rows of gone mail and of other mailboxes deleted | approve | never written (`EmailIn` disabled) |
| V4 | Keys `email.address`, `email.owner` on the allow-list; ownership moves to the last saving admin | approve | refused |
| V5 | Run-time SDS rows for `EmailIn` (`POP3Server`, `POP3Port`, `Credentials`, `SSLConfig`, `Enabled`) by `SettingsOps` | approve | none |
| V6 | Route `POST /api/v1/settings/channels` 501 -> save (admin-only, existing gate) | approve | 409 `not_available` |
| V7 | Outward action: `EmailIn` connects over TLS to the admin's POP3 server, reads, never deletes | approve | never |
| V8 | Email sender, subject and body go to the model provider for each decision (as simulated mail does) | approve; README says it | n/a |
| V9 | Audit content: identities as "set"/"changed", password "set", host:port kept | approve | none |
| V10 | No plain POP3; CI's plain stub is a test-only fixture change (Decided 4) | approve | n/a |
| V11 | Moving criteria to new 21.6/21.7 (split) | approve | n/a |

## Public text

Not in UX or PRD; send to the Planner before implementation:
- P1a `emailPoll.reason` (Channel/Email/Adapter, shown wherever 22.5 lists the mailbox as not checked): "OcuTalon couldn't reach the mail server."
- P1b same place: "The mail server refused the user name or password."
- P1c same place: "OcuTalon couldn't read the mailbox."
- P2 `SettingsOps`/`Web.Api` 409 message (API body; the page hides the section): "Email can't be connected on the online demo. Nothing was changed."
- P3 README "New since 1.0.0" bullet: "- **Your own mailbox.** On your own install, an admin connects a POP3 mailbox in Settings > Channels > Email. OcuTalon makes an attention decision on each email that arrives after that, sends the email to the model for it, and leaves your mail on the server. The online demo keeps its simulated mailbox."

All other strings: the accepted 35.2 keys and existing `SETTINGS_TEXTS` (`save`, `saved`, `failed`, `channels`).

## Verification

Lane C variables on every `ci/` call (worktree root): `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=implement'`; warm tag `e21s2iw`, fresh tag `e21s2i`. One command per foreground call, each about 150 s at most, `timeout: 600000`; never two test runs in one message; one `iris_execute_tests` per message with `server` and `namespace` named.

**Commands:**
- `<vars> OCUTALON_RUN_TAG=e21s2iw ci/warm.sh up` (once) -- warm stack up.
- `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s2iw ci/iris.sh class OcuTalon.Test.Core.SecretHandoff` (loop) -- pass. mutation: `Take` skips `Delete` -> red.
- `... class OcuTalon.Test.Core.SettingsEmail` (loop) -- pass. mutation: `SaveEmail` writes the credential before validating -> red; online-demo check removed -> red.
- `... class OcuTalon.Test.Channel.EmailIn` (loop) -- pass. mutation: `DeleteMessage` honoured -> red; seen check skipped -> red; baseline skipped -> red.
- `... class OcuTalon.Test.Channel.EmailLive` (loop) -- pass. mutation: seen rows not written -> "no repeats after a restart" red; password put in `Changes` -> leak check red.
- `... class OcuTalon.Test.Core.CommandsStep4` (loop) -- pass. mutation: `OwnAddressOnly` back to `Setting.Get` with a moved owner -> the new case red.
- `... class` for `Test.Core.SettingsSave`, `Test.Web.SettingsApi`, `Test.Web.Api`, `Test.Data.Tables`, `Test.Core.CommandsRouting` (once each, one per call) -- pass (shared surfaces).
- `node --test ci/mock/test/` (once) and `node --test web/scripts/` (once) -- pass.
- `cd web && npx tsc -p tsconfig.e2e.json --noEmit` and `npm run build` (once each) -- clean.
- `<vars> OCUTALON_RUN_TAG=e21s2i ci/iris.sh build` (once), then `<vars> OCUTALON_RUN_TAG=e21s2i ci/iris.sh live sign-in-2 --part k/8` for the part whose PART line lists `settings/email.spec.ts` (once; raise n if the call nears 150 s) -- pass. mutation: the route's online-demo or admin gate removed -> the 403 case red.
- `<vars> OCUTALON_RUN_TAG=e21s2iw ci/warm.sh down` (once, also after a failure); `ci/iris.sh teardown` with `e21s2i` (once).
- `bash docker/tests/test-storage.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-readme.sh` (once each) -- pass.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once) -- no new finding.

**Shared surfaces:** `SettingsOps.Values()` sections and `XData Sections` (`Test.Core.SettingsSave` `TestValues`, `Test.Web.SettingsApi` `TestGetShape`, `api-types.ts`); `ALLOWLIST` (`TestAllowList`); `Web.Api` UrlMap route list (`Test/Web/Api.cls:999`); the production's lane B items (`EmailIn` disabled, so "every enabled item runs" checks are unchanged); the tables list (`Test.Data.Tables`, `test-storage.sh`, spine Tables); the mock's routes and ports (`ci/mock/test/server.test.mjs`); `ux-strings.test.mjs` inventory; README "New since 1.0.0" (`test-readme.sh`); the spine lint baseline; Settings > Channels content (`web/e2e/settings/settings.spec.ts` checks section names only). Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
