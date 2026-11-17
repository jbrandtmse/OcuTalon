---
title: 'Story 0.38: Telegram and email turns check the person''s role at use time, as web chat does'
type: 'bugfix'
created: '2026-11-17'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized', 'release-blocker-for-any-epic-27-release']
deferred: []
---

<intent-contract>

## Intent

**Problem:** DW-1284. A Telegram or email message starts a turn on the strength of the pairing (Telegram) or the saved mailbox (email), not of the sender holding a role that may chat at USE time. A viewer, or a person whose OcuTalonUser role was removed after pairing, can start turns that web chat refuses.

**Approach:** extend Story 27.3's use-time check point (the production job in `OcuTalon.Core.Conversation`, when a turn Item arrives) from channel slack to telegram and email, with the SAME role read and the ONE shared predicate (web chat's exact rule) that 27.3 defines; refuse at pair or link time where such a step exists, with existing texts only. The plan stage derives the rest from epics.md Story 0.38, the rulings quoted below, and Story 27.3's in-progress work in `.worktrees/epic-27` (read only).

</intent-contract>

## Boundaries & Constraints

**Always:**
- ONE predicate, in Core (DW-1466): `OcuTalon.Core.Access` (new, Lane B). `RolesMayChat(roles)` is web chat's rule on a comma list of roles (it holds `OcuTalonUser` by its whole name; a viewer without it, `OcuTalonAdmin` alone, `%All` alone and no role may not chat). `MayChat(irisUser)` is the one call of every channel: `Bridge.Approval.RolesOf` (the one role read, unchanged), then `RolesMayChat`, then the account state (DW-1465): the IRIS account is `Enabled` and not past its `ExpirationDate` (the last day it may be used), read from `Security.Users` in `%SYS` in the calling job. Every caller passes the **session row's own `IrisUser`**, never `SessionOps.IrisUser` (it falls back to `$Username`).
- Fail closed: no row, no user, an unknown account, roles or account that cannot be read, or an exception, answers 0.
- A refused message: no Turn, no Decision, no model call, no tool call, no reply SENT, no live event, no Conversation or turn row; exactly one content-free `OcuTalon.Channel.Refused` {Channel, Reason `not_user`} to Intake, which drops it silently. A failed send of it is one fixed warning that names nothing of the message; the message is still not taken.
- `Channel.Refused` (new, Lane B) is the not_user record of Slack, Telegram and email; `Channel.Slack.Ignored` keeps only its own reasons (not_user leaves its REASONS).
- Texts: only existing ones, plus the ONE approved sentence (item 4), verbatim, under Save in Settings > Channels > Email: "This mailbox would be yours, but you can't use the chat, so its email would never be read. An admin who can use the chat must connect it. Nothing was changed."

**Never:**
- No NEW reference from Core or Channel to `OcuTalon.Web.*` (this story removes Conversation's); no reference from `OcuTalon.Web.Public.*` to anything but its AD-3 allow-list.
- No change to channel `web` or `mailbox` (the demo's simulated mailbox, UJ-1); no new role, grant or resource; no change to which jobs hold `%Admin_Secure:USE`; no copy of the role read or of the predicate.
- No telegram file content fetched or stored for a person who may not chat; never read.
- No new `MESSAGE*` parameter in SessionOps (an outcome without one answers an empty Message); no new catalog key.

## I/O & Edge-Case Matrix

| # | Scenario | Input / State | Expected | Pinning test |
|---|---|---|---|---|
| A1 | The rule agrees with web chat | the 10 role sets of `TestMayChatIsTheRuleOfWebChat` | `Core.Access.RolesMayChat(roles)` = 1 exactly when POST /v1/messages passes `Web.Api.OnPreDispatch` | Test.Web.ViewerApi TestMayChatIsTheRuleOfWebChat (now against Core.Access) |
| A2 | Account state | real fixture accounts: OcuTalonUser enabled (control 1); `Enabled` 0; `ExpirationDate` 2 days ago; `ExpirationDate` 30 days ahead (control 1); no account; "" | 1, 0, 0, 1, 0, 0 (an exception inside the read is caught and answers 0) | Test.Core.Access TestAccountState, TestNoWebReference |
| S1 | Slack, disabled / expired | Slack Item of an OcuTalonUser account that is disabled, then one that is expired | refused as Always; the record is `Channel.Refused` channel slack | Test.Core.ConversationNotUser TestDisabledRefused, TestExpiredRefused (slack case); live:slack-hook phase 7 |
| S2 | Slack record moved | every slack refusal of 27.3's tests | one `Channel.Refused` {slack, not_user}; no `Slack.Ignored` | ConversationNotUser AssertRefused (updated) |
| T1 | Telegram viewer | telegram Item, user OcuTalonViewer only | refused as Always, record {telegram, not_user} | ConversationNotUser TestTelegramViewerRefused |
| T2 | Telegram role removed after pairing | first Item makes a Turn; OcuTalonUser removed | next Item refused, one record, no second Turn | TestTelegramRoleRemovedAfterPairing |
| T3 | Telegram admin + user | OcuTalonAdmin,OcuTalonUser | Turn and its Decide request, no record | TestTelegramAdminWithUserAllowed |
| T4 | Telegram admin-only | OcuTalonAdmin; Admin+Viewer | both refused; control `RolesMayChat` 0 on the same roles | TestTelegramAdminOnlyFollowsWebChat |
| T5 | Telegram disabled / expired | OcuTalonUser account, Enabled 0; another past its expiry | refused, one record each | TestDisabledRefused, TestExpiredRefused (telegram case) |
| T6 | Telegram file, refused | paired chat's document or photo, session user may not chat | TelegramIn: no getFile, no download, nothing stored, no allowance entry, no reply, no Item; one `Channel.Refused` {telegram, not_user} to Intake | Test.Channel.TelegramFile TestRefusedSenderFileNotFetched |
| T7 | Telegram file, race | a file Item reaches Conversation and its user may no longer chat | refused as Always and the stored file is discarded at once (`Core.Files.Discard`; never read: no ReadFile call) | ConversationNotUser TestRefusedFileIsDiscarded |
| P1 | Pair, may not chat | valid unused code; session user viewer-only, then disabled, then a session with no user | `not_user`, Ok 0, empty Message; chat not linked; code not used; one `rejected` audit entry reason not_user; no pairing event; TelegramIn answers the existing `pairing.badCode` | Test.Core.SessionOps TestPairRefusesWhoMayNotChat; Test.Channel.TelegramPair TestNotUserIsBadCode |
| P2 | Pair, user | same, OcuTalonUser | `paired` as before | TestPairRefusesWhoMayNotChat (control) |
| E1 | Email viewer owner | email.owner = session of a viewer-only account; new Mail | no Item; one `Channel.Refused` {email, not_user} to Intake; status OK | Test.Channel.EmailIn TestNotUserOwnerRefused |
| E2 | Email role removed after the save | owner held OcuTalonUser (first Mail gives an Item); role removed | next Mail: no Item, one record | TestNotUserRoleRemovedAfterSave |
| E3 | Email admin + user | OcuTalonAdmin,OcuTalonUser | one Item as before, no record | TestNotUserAdminWithUserAllowed |
| E4 | Email admin-only | OcuTalonAdmin alone | no Item, one record; control `RolesMayChat` 0 | TestNotUserAdminOnlyFollowsWebChat |
| E5 | Email disabled / expired | owner account Enabled 0; another past its expiry | no Item, one record each | TestNotUserDisabledOrExpired |
| E6 | Refused email is seen | adapter run with the probe, refused owner | the Uidl is recorded seen (Data.MailSeen); the next poll hands it on no more | TestNotUserMailIsSeen |
| E7 | Email record send fails | FailSend 1, viewer owner | no Item, status OK, one warning, the fixed text, no address, user, Ref or mail text | TestNotUserRecordFailureIsOneWarning |
| M1 | Mailbox save refused | SaveEmail by a session whose user may not chat (admin-only; also disabled) | Ok 0, outcome `not_user`, Message the sentence VERBATIM; nothing written: email.* keys, the credential, EmailIn/EmailOut rows, OAuth client, audit entries unchanged, no hand-off taken; Web.Api answers 409 `not_user` with that message | Test.Core.SettingsEmail TestSaveRefusesWhoMayNotChat; Test.Web.SettingsApi TestChannelsNotUser |
| M2 | Mailbox save shown | the browser's Save answered 409 not_user | the sentence, exactly, in `#email-error` under Save, announced; no field marked | web/scripts/email-view.test.mjs; web/e2e/settings/email.spec.ts, a new not_user case |
| R1 | Record and Intake | a `Channel.Refused` of each channel | Intake answers OK at once: no warning, join, decision or send; the class has exactly Channel and Reason | Test.Core.Intake TestRefusedIsDropped |
| W1 | Web unchanged | Item channel web of a viewer-only user | taken as before, no record | ConversationNotUser TestOtherChannelsUnchecked (web only) |

## Code Map

Base: `OCT-epic0-dw1284` at `be0aa2133be8eeda7f951af4c357f87d14f1baf3` (feature `720467ed5`, Story 27.3 included). Lines are on that base. Lane per AD-29 footprints (`_bmad/custom/epic-dependencies.yaml`).
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` (B) -- class doc L7-10 (slack check); `CHECKEDCHANNEL = "slack"` L165-166; `INTAKE` L168-169; `LOGNOTUSER` L171-172; `Take` L233-236 (`If ..NotUser(item) Quit ..RecordNotUser()`, after `Untrusted`, so a file Item is checked after `UntrustedFile`'s Describe, before any read); `NotUser` L266-279 (opens the row, `..MayChat(session.IrisUser)`, fail closed); `RecordNotUser` L281-291 (a `Slack.Ignored` Kind message.im); public `MayChat(irisUser)` L293-300 (RolesOf, then `Web.Public.Shell.MayChat`: the Core-to-Web edge of DW-1466).
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` (B) -- `ROLE` L27, `VIEWERROLE` L30, `HasRole` L148, `ViewerOnly` L154, `MayChat(roles)` L159-166 (callers: Conversation L299 and Test.Web.ViewerApi L179 only). Shell is in the public package: `Test.Web.Status` TestReferencesOnlyThePublicAllowList (L332-) fails on any reference outside %CSP, dynamic objects, `$SYSTEM.License`/`Status` and the two public packages (AD-3).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` (A) -- `RolesOf(irisUser, Output roles)` L414-430, the one role read; its doc names "Core.Conversation MayChat". It reads roles of a disabled or expired account normally (DW-1465 occurrence, measured on a 27.3 throwaway), so the account state is a read of its own.
- `irissys/Security/Users.cls` (read only) -- `Get(Username, .Properties)` L482: `Properties("Enabled")` 0/1, `Properties("ExpirationDate")` ODBC date or "" (none), error #838 for no account; `ExpirationDate` is "Last date an account can be used" (L74-76). `Security.Users` exists only in `%SYS` (measured on `ocutalon-slot-d`: `%Dictionary.CompiledClass` `Security.Users` is 0 in OCUTALON); `%SYSTEM.Security` has no account-state call. Production jobs run as `_Ensemble` with `%All` (27.3 Task 0 record).
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` (B, shared_by_entry) -- Slack list `ListSlack` L3156-3180 (`Conversation.MayChat(name)` L3179), link L3219 (same); `MESSAGEUNAVAILABLE` L891 (the parameter block); `SaveEmail` L1544-1560 doc and L1560-1562 (online demo first; `TakeMailbox` next, the first read of the hand-off); `email.owner` is set to `command.SessionRef` L1607.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` (B, shared_by_entry) -- class doc L6-12 (Pair outcomes); `Pair` L156-193: session-row check L170, then Unlink/audit/Link; `Reject` L519-526 (audit `rejected` + `$Parameter(MESSAGE<OUTCOME>)`, "" when absent: measured on slot D, `$Parameter` of an undefined parameter is ""); `IrisUser` L556-560 (`$Username` fallback: never for the check).
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls` (A) -- class doc L54-75 (turn and file steps, DW-1340 order); `TARGET` L160; `Pair` L603-614 (`pairing.badCode` for every outcome but paired); `File` L678-704; `Stored` L707-732 (Fetch, then Store); `Turn` L798-861 (row, then `Allowed` L895, then `Stored`, then the Item); `SendTurn` L877.
- `src/ocutalon/cls/OcuTalon/Channel/Email/In.cls` (B) -- `OnProcessInput` L39-63 (row of the owner L42-44, `IsOwnMail` L46, then the Item to Intake); `Send(target, request)` seam L96-99. A status OK makes the adapter record the email seen (`Channel/Email/Adapter.cls` doc ~L23).
- `src/ocutalon/cls/OcuTalon/Channel/Slack/Ignored.cls` (B) -- doc L1-4, `REASONS` L12 (has `not_user`).
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls` (B) -- doc L23-24, `OnRequest` L77 drops a `Slack.Ignored` silently.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (B, shared_by_entry) -- class doc L47-55 (channels answers); `SaveChannels` L1059-1100; `Answer` L1202-1228 (`not_available` 409 at L1225; anything unknown is 500); `Fail(status, code, message)` L1654.
- `web/src/app/settings/email-section.ts` (B) -- template `#email-error` under the Save button L219-224; `refused()` L475-489 (non-field refusal shows `SETTINGS_TEXTS.failed`); `web/src/app/settings/email-view.ts` (pure helpers, tested by `web/scripts/email-view.test.mjs`); pattern to extend: `slack-view.ts` `slackOutcome` L51-70 (reads `error.code` and `error.message` of the body).
- Tests to extend (reuse, no copied helpers): `Test/Core/ConversationNotUser.cls` (B; `Session(name, roles, .user)`, `RemoveRole`, `DropUser`, `NewProbe`, `Item`, `AssertRefused` L215-229, `TestOtherChannelsUnchecked` L185-194 pins telegram unchecked); `Test/Core/ConversationProbe.cls` (B; `Send` records `Slack.Ignored` fields L51-55, `MayChat` throw seam L71-76); `Test/Install/RolesAssign.cls` (A, read only: `CreateUser`, `RemoveRole`, `EnsureRoles`, `DropRoles`); `Test/Channel/EmailIn.cls` + `EmailInServiceProbe.cls`; `Test/Channel/TelegramFile.cls` + `TelegramInProbe.cls` (A); `Test/Channel/TelegramPair.cls` (A); `Test/Core/SessionOps.cls` + `SessionOpsProbe`; `Test/Core/SettingsEmail.cls` + `SettingsEmailProbe`; `Test/Core/Intake.cls` (L373-); `Test/Web/ViewerApi.cls` L168-182; `Test/Web/SettingsApi.cls` TestChannelsRoute L546-; `docker/tests/test-slack-hook.sh` phase 7 L440-565 (`not_user_count` L454 and the check at L545-551 read `OcuTalon_Channel_Slack.Ignored`); `web/e2e/settings/email.spec.ts` (README admin, real stack).

## Tasks & Acceptance

**Execution** (in order; (A) = a Lane A file, (B) = Lane B):
- Task 0 (first; a lane-D throwaway, never a slot; record under `## Verification` > "Task 0 record"): (a) on a fixture account holding OcuTalonUser, `Security.Users.Get` from a `New $Namespace` switch to `%SYS` answers `Enabled` and `ExpirationDate` as Code Map says, after `Modify` sets `Enabled` 0, and an `ExpirationDate` 2 days ago; `RolesOf` still answers the roles for both. (b) A signed-in README-admin CSP session whose account is then expired (and, separately, disabled) by `Security.Users.Modify`: does its next `POST /v1/settings/channels` pass `OnPreDispatch` and reach SaveEmail? Yes: M2's browser pin is the new `email.spec.ts` not_user case as planned. No: the sentence is unreachable from the browser; M2 keeps its `email-view.test.mjs` and `SettingsApi` pins, the browser case is dropped, and the stage records it (no other change). Any need for a new grant, role or resource: STOP with `## Clarification Needed`.
- `src/ocutalon/cls/OcuTalon/Core/Access.cls` (B, NEW) -- `Parameter USERROLE = "OcuTalonUser"`; `ClassMethod RolesMayChat(roles As %String) As %Boolean` (web chat's rule, whole name, as Shell compares); `ClassMethod MayChat(irisUser As %String) As %Boolean` (RolesOf, RolesMayChat, then `Usable`); `ClassMethod Usable(irisUser As %String) As %Boolean [ Private ]`: the class's one method that switches namespace (`New $Namespace`, `%SYS`), `Security.Users.Get`, 1 only when `Enabled` is 1 and `ExpirationDate` is "" or not before today (`$ZDateH(..., 3)` against `+$Horolog`); any error or exception 0. Class doc: who calls it, that it runs in the caller's job (production jobs: `_Ensemble`, `%All`) and fails closed where `%SYS` cannot be read.
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` (B) -- delete `MayChat` (no product caller remains); `HasRole`/`ViewerOnly` unchanged; HasRole's doc names Core.Access RolesMayChat as the Core rule the agreement test keeps equal to web chat's gate.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` (B) -- `CHECKEDCHANNEL = "slack,telegram"`; `NotUser` tests `$ListFind($ListFromString(..#CHECKEDCHANNEL), item.Channel)`; `MayChat(irisUser)` becomes `[ Private ]`, the test seam, and only calls `Core.Access.MayChat`; `RecordNotUser(item)` sends one `Channel.Refused` {Channel item.Channel, Reason not_user} and, when `item.FileRef '= ""`, first calls `Core.Files.Discard(item.FileRef, item.SessionRef)` (T7; a failed discard is one fixed warning); docs updated (email is checked at EmailIn: no email Item reaches Conversation).
- `src/ocutalon/cls/OcuTalon/Channel/Refused.cls` (B, NEW) -- `Extends Ens.Request`; `Parameter CHANNELS = "slack,telegram,email"`, `Parameter REASONS = "not_user"`; `Property Channel As %String(MAXLEN = 16)`, `Property Reason As %String(MAXLEN = 32)`; nothing else; generated storage committed; doc: the content-free trace record of a refused message (AD-26), sent to Intake, which drops it.
- `src/ocutalon/cls/OcuTalon/Channel/Slack/Ignored.cls` (B) -- REASONS without `not_user`; doc no longer names Conversation.
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls` (B) -- OnRequest also answers OK at once for a `Channel.Refused` (the same silent drop); doc.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` (B) -- L3179 and L3219 call `Core.Access.MayChat` (doc L3160 too); `Parameter MESSAGEEMAILNOTUSER` = the approved sentence verbatim; in `SaveEmail` right after the online-demo line: open `command.SessionRef`'s row; no row or `'Core.Access.MayChat(row.IrisUser)` -> `Quit ..Result(0, "not_user", ..#MESSAGEEMAILNOTUSER)` before `TakeMailbox` (nothing read from the hand-off, nothing written, no audit entry); SaveEmail's doc lists it.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` (B) -- in `Pair`, replace the L170 row check by opening the row once: no row -> `unknown_code` as now; `'Core.Access.MayChat(row.IrisUser)` -> `Quit ..Reject("not_user", "not_user", session, channel)`. No MESSAGE parameter; class doc lists `not_user`. The used-code repeat (L165, links nothing) is unchanged.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls` (A) -- in `Turn`, after the row check and before `Allowed`: when `upload` is an object and `'..MayChat(session.IrisUser)`, call `..Refused()` and do nothing else (no allowance call, no Fetch, no Store, no reply, no Item). New private seams `MayChat(irisUser)` (calls Core.Access) and `SendRefused(record)` (`SendRequestAsync` to new `Parameter INTAKE = "Intake"`); `Refused()` clears `%SessionId`/`%SuperSession` as SlackIn's Ignore does and sends one `Channel.Refused` {telegram, not_user}; a failed send is one fixed warning (`LOGREFUSED`). Text turns are unchanged (Conversation checks them). Class doc step (4) of the file list.
- `src/ocutalon/cls/OcuTalon/Channel/Email/In.cls` (B) -- after `IsOwnMail`: `If '##class(OcuTalon.Core.Access).MayChat(session.IrisUser)`: send one `Channel.Refused` {email, not_user} to TARGET through `Send`, log the fixed `LOGNOTUSER` warning when it fails, `Quit $$$OK` (the adapter records it seen), no Item. Class doc.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (B) -- `Answer`: `If outcome = "not_user" Quit ..Fail(409, "not_user", result.Message)`; class doc L55.
- `web/src/app/settings/email-view.ts` (B) -- `export function notUserText(status: number, body: unknown): string` (the body's `error.message` when status 409 and `error.code` is `not_user` and the message is a non-empty string, else ""), the slack-view pattern; `email-section.ts` (B) -- `refused()`: when `notUserText` is non-empty, show it in `#email-error` instead of `failed` and announce it; no field marked.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` (A) -- doc of `RolesOf` only: its caller is Core.Access MayChat (no code change).
- Tests (each with its header updated): `Test/Core/Access.cls` (B, NEW: A2 and TestNoWebReference); `Test/Core/ConversationNotUser.cls` (B: S1, S2, T1-T5, T7, W1; disabled/expired via a `Security.Users.Modify` helper in `%SYS` beside `DropUser`); `Test/Core/ConversationProbe.cls` (B: record `channel` and `reason` of a `Channel.Refused`; MayChat seam `[ Private ]`); `Test/Channel/TelegramFile.cls` + `TelegramInProbe.cls` (A: T6, probe records `SendRefused`); `Test/Channel/TelegramPair.cls` (A: P1's reply); `Test/Core/SessionOps.cls` (B: P1, P2); `Test/Channel/EmailIn.cls` + `EmailInServiceProbe.cls` (B: E1-E7, probe records `channel`/`reason`); `Test/Core/SettingsEmail.cls` (B: M1); `Test/Web/SettingsApi.cls` (B: M1's 409); `Test/Web/ViewerApi.cls` (B: A1 against `Core.Access.RolesMayChat`); `Test/Core/Intake.cls` (B: R1); `web/scripts/email-view.test.mjs` (B: M2); `web/e2e/settings/email.spec.ts` (B: M2, a new not_user case: a spec-made admin+user account, signed in, then expired, Save -> the sentence, account removed after); `docker/tests/test-slack-hook.sh` (B: phase 7 reads `OcuTalon_Channel.Refused` channel slack, and two more linked OcuTalonUser accounts, one disabled and one expired after linking, are refused with one record each). Plus `Test/Data/Fixture.cls` (B: `ChatSession`), `Test/Channel/LiveCase.cls` (A) and every existing test of `## Verification` > Shared surfaces that needs a real account.

**Acceptance Criteria:**
- Given any channel's caller, when it asks whether a person may chat, then it calls `Core.Access.MayChat` with the session row's IrisUser, and `RolesMayChat` agrees with `Web.Api.OnPreDispatch` on A1's 10 role sets. mutation: `RolesMayChat` also accepts `OcuTalonAdmin` -> ViewerApi TestMayChatIsTheRuleOfWebChat red. And no Core-to-Web edge (DW-1466): Test.Core.Access TestNoWebReference reads the source of `Core.Access`, `Core.Conversation`, `Channel.Email.In` and `Channel.Telegram.In` from the class dictionary and finds no `OcuTalon.Web.`; mutation: `RolesMayChat` calls `Shell.HasRole` -> TestNoWebReference red.
- Given an OcuTalonUser account that is disabled or past its expiry, when `MayChat` reads it, then it answers 0 (A2) and its Slack, Telegram and email messages are refused (S1, T5, E5; live:slack-hook phase 7). mutation: `Usable` returns 1 -> Test.Core.Access TestAccountState red (and phase 7's disabled check).
- Given a Telegram Item of a person who may not chat, when Conversation takes it, then T1-T4 and W1 hold. mutation: `CHECKEDCHANNEL` back to `"slack"` -> TestTelegramViewerRefused red.
- Given a paired chat's file from a person who may not chat, when TelegramIn handles it, then T6 holds (nothing fetched or stored); and when such a file Item still reaches Conversation, T7 holds. mutations: delete TelegramIn's MayChat line -> TelegramFile TestRefusedSenderFileNotFetched red; delete the Discard call -> TestRefusedFileIsDiscarded red.
- Given a valid pairing code whose session's user may not chat, when the chat sends `/start <code>`, then P1 holds with the existing `pairing.badCode`, and P2 for a user. mutation: delete the MayChat line in `SessionOps.Pair` -> TestPairRefusesWhoMayNotChat red.
- Given the saved mailbox's owner may not chat, when EmailIn takes a new email, then E1-E7 hold. mutations: delete the MayChat line in `EmailIn.OnProcessInput` -> TestNotUserOwnerRefused red; the refusal answers an error status instead of OK -> TestNotUserMailIsSeen red (it would be re-read).
- Given an admin whose session user may not chat, when they save Settings > Channels > Email, then M1 and M2 hold: the exact sentence, nothing written. mutations: delete the SaveEmail check -> SettingsEmail TestSaveRefusesWhoMayNotChat red; change one word of `MESSAGEEMAILNOTUSER` -> the same test and the email.spec.ts not_user case red; move the check after the keys' transaction -> TestSaveRefusesWhoMayNotChat's nothing-written assertions red.
- Given any refusal of S1-E7, when it is recorded, then it is one `Channel.Refused` of its channel that Intake drops silently, and no `Slack.Ignored` carries `not_user` (S2, R1). mutation: Conversation sends `Slack.Ignored` again -> ConversationNotUser AssertRefused red.
- Integration (Rule 1/2): Conversation, TelegramIn, EmailIn, SessionOps.Pair and SettingsOps (SaveEmail, the Slack list and link) call the real `Core.Access.MayChat` on real IRIS accounts holding real roles and real account state, and produce the records above; no mock of the role or account read in any pin (only ConversationProbe's existing throw seam).
- Given CI on this story's head, when it finishes, then every workflow is green.

## Spec Change Log

- 2026-11-17 (lead). **Re-plan gate: all four points APPROVED (Contest Planner, BINDING)**, quoted in full; the build applies them:

  > ## 0.38 re-plan rulings (Contest Planner, ~07:20Z Nov 17). BINDING. All APPROVED. Start NOW.
  > 
  > ### (i) Where the rule lives
  > - The rule lives ONLY in OcuTalon.Core.Access. Shell.MayChat is deleted.
  > - Web.Api.OnPreDispatch stays unchanged.
  > - The agreement test compares Core.Access with it over 10 role sets. The sets INCLUDE a %All-only set and an admin-only set, and both must give the SAME answer as the web check.
  > 
  > ### (ii) Method names
  > RolesMayChat(roles) and MayChat(irisUser).
  > 
  > ### (iii) AD-3 amendment, with conditions
  > - ONE read-only method in Core.Access switches to %SYS and reads only Security.Users' Enabled and expiry, for one user.
  > - It switches back, restored in a FINALLY block, even on error.
  > - It returns booleans only. It returns no other user data and writes nothing.
  > - Any error is "may not chat" (fail closed). No new grant.
  > - Pins:
  >   - the namespace is restored after the call, including on the error path;
  >   - a disabled user is refused;
  >   - an expired user is refused;
  >   - an enabled, unexpired user with OcuTalonUser is allowed.
  > 
  > ### (iv) AD-33 exception
  > Approved for Channel/Telegram/In.cls (the check before download) and its 3 lane-A tests only. The Approval.cls comment is fine.
  > 
  > ### Test fixture
  > - Test.Data.Fixture.ChatSession creates a real OcuTalonUser account and cleans it up afterwards.
  > - LiveCase gives each live Telegram test one.
  > - NO role is granted to irisowner.
  > - The cleanup runs EVEN WHEN A TEST FAILS. Pin this: an orphaned IRIS user left behind by a test is a security smell.
  > 
  > ### Task 0
  > Approved: measure whether a disabled or expired admin's open browser session can still reach Save. Drop that browser test ONLY if the measurement shows it can't be reached.
  > 
  > ### Spine
  > AD-14, AD-26, AD-3, AD-33 and the dependency diagram are approved, and written at the merge.
  > 
  > ### Release note (verbatim)
  > "A user without the chat role, or whose IRIS account is disabled or expired, could still start conversations through Telegram or email; that is now refused, as it is in the web chat."

- 2026-11-17 (plan stage, re-plan on `be0aa2133be8eeda7f951af4c357f87d14f1baf3`, Story 27.3 merged in). The plan is re-derived on the current code and applies every BINDING ruling below. **Rule 5 amendment (apply and report), done:** `_bmad-output/planning-artifacts/epics.md` Story 0.38 AC1. Original: "**Given** a turn Item of channel telegram or email reaching `OcuTalon.Core.Conversation` in the production job / **When** its session's IRIS user may not chat by web chat's exact rule (the ONE shared predicate that Story 27.3 introduces in Core.Conversation, reading roles the way Bridge/Approval.cls HoldsRole does)". Amended: "**Given** a message of channel telegram or email in the production job: Telegram turns are checked where they reach Core.Conversation; email is checked in EmailIn before an Item is made / **When** its session's IRIS user may not chat by web chat's exact rule (the ONE shared predicate, Core.Access MayChat (DW-1466), reading roles the way Bridge/Approval.cls HoldsRole does)", each line marked `[AMENDED 2026-11-17 — see the story change log]`. Rationale: the 01:10Z ruling, item 1 (no email Item reaches Conversation), and the 02:05Z ruling, item 2 (the predicate moves into Core). Four deviations for the lead and the Planner are under `## Design Notes` (Shell cannot call Core under AD-3; two method names; an AD-3 `%SYS` switch; Lane A's TelegramIn). KEEP: the matrix's pin names and the one-record shape of a refusal.

- 2026-11-17 (lead). **RELEASE BLOCKER and scope additions, Contest Planner ~02:05Z Nov 17 (BINDING)**, quoted in full; applied at the re-plan after 27.3 merges (27.3 is accepted with MayChat in Core.Conversation and Web.Public.Shell, and Bridge.Approval.RolesOf new):

  > ## Additions from the 27.3 rework (Contest Planner, ~02:05Z Nov 17). BINDING.
  > 
  > ### 1. DW-1465 is in 0.38's scope
  > - Extend MayChat to refuse a DISABLED account and one PAST ITS EXPIRY. Read Enabled and the expiry in the production job.
  > - Pin it for each channel, including live:slack-hook.
  > 
  > **RELEASE BLOCKER:** 0.38 blocks the next release that contains ANY Epic 27 story. No release ships Slack without it. Record this on the tracker and in 0.38's spec.
  > 
  > **Release note**, stating it plainly as a fix: "a disabled or expired IRIS account, or a user without the chat role, could still start conversations through Telegram or email; now refused."
  > 
  > ### 2. DW-1466: MOVE the predicate into Core
  > - Do NOT add a Core-to-Web edge.
  > - Move it into Core, for example Core.Access.MayChat(roles) plus MayChat(irisUser).
  > - Web.Public.Shell then calls Core. Web depending on Core is the existing direction.
  > - Keep the agreement test against Web/Api that covers 10 role sets.
  > 
  > ### 3. Channel.Refused
  > It moves in 0.38, as already ruled. 27.3 still writes not_user into Slack.Ignored.

- 2026-11-17 (lead). **Story 0.38 spec-gate rulings and the item-4 text, Contest Planner ~01:10Z Nov 17 (BINDING)**, quoted in full; to be applied in the build after 27.3 merges and feature is green:

  > # Story 0.38 (DW-1284) spec-gate rulings (Contest Planner, ~01:10Z Nov 17). BINDING.
  > 
  > APPROVED. It is built AFTER 27.3 lands.
  > 
  > - **The predicate:** MayChat(irisUser) is RolesOf followed by Web.Public.Shell MayChat(roles). It is approved as the one shared rule.
  > 
  > 1. **Email check point: APPROVED.** The check is in Channel/Email/In.cls, BEFORE any Item is made.
  >    - Correct AC1 to: "Telegram turns are checked where they reach Core.Conversation; email is checked in EmailIn before an Item is made".
  > 2. **The not_user record: make ONE small channel-neutral class**, for example Channel.Refused, with reason and channel.
  >    - All three channels (Slack, Telegram, email) use it for not_user.
  >    - Slack's Ignored keeps its other reasons.
  >    - Do NOT reuse a Slack-named class for Telegram and email.
  > 3. **Pairing: badCode for not_user is APPROVED,** with no new text. The audit entry gives admins the real reason.
  > 4. **Email mailbox save:** an admin-only user (one who fails MayChat) must NOT be able to save a mailbox whose email would then be refused.
  >    - REFUSE the save at save time.
  >    - This needs one new sentence. Send its text to the Planner FIRST.
  >    - The Planner's suggestion: "This mailbox would belong to an OcuTalon user who can't use the chat, so its email would never be read. Nothing was changed."
  > 5. **Smaller choices.** OK: a refused email is marked seen and not re-read; a refused pairing does not use up the code; the Telegram allowance entry is used.
  >    - **A REFUSED TELEGRAM FILE: NOT OK to download first.**
  >      - Check BEFORE downloading, so no content from a refused user is fetched or stored.
  >      - If the check order makes that impossible: delete the file at once, never store or read it, and pin both behaviours.
  > 
  > **Release note (for later):** state it plainly as a fix: "a user without the chat role could start conversations through Telegram; now refused."
  > 
  > ## Item 4 text: APPROVED verbatim (Contest Planner, ~01:20Z Nov 17). BINDING.
  > "This mailbox would be yours, but you can't use the chat, so its email would never be read. An admin who can use the chat must connect it. Nothing was changed."
  > - It goes under Save in Settings › Channels › Email, as outcome not_user, refused before anything is written.
  > - Pin the exact text.
  > - Pin that nothing is written.

  Orchestrator relay of item 4: the approved text, VERBATIM: "This mailbox would be yours, but you can't use the chat, so its email would never be read. An admin who can use the chat must connect it. Nothing was changed." It shows under Save in Settings › Channels › Email, outcome not_user, refused before anything is written; pin the exact text and pin that nothing is written. Item 2: whichever of 27.3 and 0.38 lands second moves Slack's not_user onto Channel.Refused.

- 2026-11-17 (lead). Chartered by the orchestrator's Planner dispatch (~00:30Z Nov 17). The BINDING rulings, quoted from `<coordination>/prompts/story-273-rulings-20261116.md` (the 26.4 / DW-1284 section and the 27.3 Task 0 ruling):

  > ## 26.4 / DW-1284: Telegram and email get the same USE-TIME check. RAISED IN PRIORITY.
  > - This is an existing gap in released versions: a viewer paired on Telegram can start turns that web chat refuses.
  > - Schedule it right AFTER the Triage confidence A/B, ahead of the LOW items.
  > - Make it a small story with the same shared predicate and the same pins for each channel.
  > - Its release note says plainly that it is a fix.
  > 
  > ## 27.3 viewer fix, Task 0 outcome (Contest Planner, ~00:05Z Nov 17). BINDING.
  > - **OPTION (a) APPROVED.**
  > - **(c) is REFUSED outright:** no %Admin_Secure on an unauthenticated application, ever.
  > - **(b) is not needed.**
  > 
  > Conditions for (a):
  > 1. **Where and how the check runs**
  >    - In the production job, in Core.Conversation, when a turn Item arrives.
  >    - It uses the SAME role read as Bridge/Approval, and the ONE shared predicate: the web chat's exact rule.
  >    - For now it applies to channel `slack` only. The DW-1284 story extends the same check point to Telegram and email.
  > 2. **A refused turn**
  >    - No turn, no reply, no tool call and no model call.
  >    - One content-free record, with reason `not_user`.
  >    - The inbound Item's text goes no further than its message body, and follows normal retention.
  >    - Pin that no reply is SENT, and that no Conversation or turn row is written for it.
  > 3. **All the pins**
  >    - A viewer's DM is refused.
  >    - A role removed after linking is refused on the next DM.
  >    - An admin who is also a user is allowed.
  >    - An admin-only user follows the web chat's rule.
  >    - Linking a viewer is refused at link time. Task 0 confirms that the admin web process can read roles.
  > 4. **The README fix** goes in the same push.
  > 5. **Conversation.cls** is lane B's file, and no running branch touches it.

  Dispatch additions: the predicate is defined ONCE (lane B is introducing it in Core.Conversation in `.worktrees/epic-27`, branch OCT-epic27; use the exact class, method name and signature; whichever lands first defines it and the other merges to identical text); the pins per channel are a viewer's message refused, a role removed after pairing refused on the next message, admin plus user allowed, an admin-only user following web chat's rule, no reply SENT and no Conversation or turn row written, and pairing or linking a viewer refused at pair or link time where a pairing step exists (existing texts only; any NEW text goes to the Planner first). Branch OCT-epic0-dw1284 from feature b2768afeb.


## Review Triage Log

## Design Notes

**RELEASE BLOCKER (ruled).** Story 0.38 blocks the next release that contains ANY Epic 27 story; no release ships Slack without it. **Release note** (rulings), stated plainly as a fix: "a disabled or expired IRIS account, or a user without the chat role, could still start conversations through Telegram or email; now refused."

**Governing ADs:** AD-3 (namespace switches; the public packages' allow-list), AD-4 (SessionOps is the only linker), AD-14 (channels, the not_user rule), AD-24 (roles), AD-26 (the record in Visual Trace), AD-29/AD-33 (lanes, owners), AD-19 (Settings saves write nothing on a refusal).

**Consumes / Consumed-by / Extend (Rule 1/2).** Consumes Story 27.3's `Bridge.Approval.RolesOf`, its use-time check point in Conversation and its tests' fixture. `Core.Access` is a new shared module; its consumers in this story are Conversation (slack, telegram), TelegramIn (files), EmailIn, SessionOps.Pair and SettingsOps (SaveEmail, the Slack list and link), each pinned above against real accounts. Consumed-by: every later channel check. Extend, don't copy: the predicate MOVES (Conversation and Shell lose theirs; no copy stays); the record MOVES (Slack.Ignored loses not_user); the tests extend 27.3's class and `Test.Install.RolesAssign`'s fixture.

**Deviations for the lead and the Planner (decide before implement):**
1. *DW-1466 "Web.Public.Shell then calls Core" cannot hold.* Shell is in `OcuTalon.Web.Public`, the public database's package, which runs with no roles before sign-in; AD-3 and `Test.Web.Status` TestReferencesOnlyThePublicAllowList forbid any reference outside %CSP, dynamic objects, `$SYSTEM.License`/`Status` and the two public packages. Plan: the rule lives only in `Core.Access`; `Shell.MayChat` (whose only callers were Conversation and a test) is deleted; web chat's own gate stays `Web.Api.OnPreDispatch` with `Shell.HasRole`/`ViewerOnly`, and the 10-role-set agreement test pins `Core.Access.RolesMayChat` to that gate. No Core-to-Web edge remains. Observable behaviour is the same either way.
2. *Two method names, not two `MayChat`s.* ObjectScript has no overloading, so the ruling's "MayChat(roles) plus MayChat(irisUser)" becomes `RolesMayChat(roles)` and `MayChat(irisUser)`.
3. *A new `%SYS` switch (AD-3 amendment; veto window, items 1 and 9).* DW-1465 needs `Enabled` and `ExpirationDate`, which only `Security.Users` in `%SYS` holds (no `%SYSTEM` call answers them; measured). `Core.Access.Usable` is one method, read only, `New $Namespace`; it joins AD-3's list of namespace-switching classes. No grant: production jobs are `_Ensemble` with `%All`.
4. *A Lane A file (AD-33).* The ruled "check BEFORE downloading" is only possible in TelegramIn (`Channel/Telegram/In.cls`, Lane A from Epic 12) and its tests (`Test/Channel/TelegramFile`, `TelegramInProbe`, `TelegramPair`); `Bridge/Approval.cls` gets a doc line. The lead records an AD-33 exception line like Story 21.7's.

**Decided in-stage (new beyond the rulings):**
- TelegramIn checks only file turns, before the allowance (a refused file costs no entry, no fetch); text turns keep the ruled check in Conversation (their allowance entry is used, as ruled).
- The race (role removed between TelegramIn's check and Conversation's): Conversation's refusal discards the stored file at once (`Core.Files.Discard`); nothing reads it (Begin never runs).
- TelegramIn's record goes in a trace session of its own (SlackIn's Ignore pattern); Conversation's and EmailIn's in the message's own trace session.
- SaveEmail's check reads the saving session row's IrisUser (the row that becomes `email.owner`), before the hand-off is read; a missing row is refused the same way.
- Web.Api answers `not_user` as 409 `not_user` with the result's message; the form shows that message (the approved sentence) in its existing `#email-error` line under Save. No web-side copy of the text.
- Reach (Task 0 (b)): an admin who fails the role rule is 403 at `OnPreDispatch` before SaveEmail, so through the browser only an admin+user whose account was disabled or expired during a live session reaches it.
- Expiry: refused from the day after `ExpirationDate` (IRIS: "last date an account can be used"); the tests use 2 days ago and 30 days ahead, away from the boundary. The inactivity limit (`AccountNeverExpires`, `InactiveLimit`) is not read.
- A refused pairing does not use up the code; a refused email is seen and never re-read (it does not come back if the role returns) (both ruled OK).
- Conversation keeps a private `MayChat` seam only so that ConversationProbe's existing throw seam stays.

**Spine updates for the lead (Rule 20, same bookkeeping commit as the rulings):** AD-14 (`Web.Public.Shell.MayChat` -> `Core.Access.MayChat`, telegram at Conversation and TelegramIn's files, email at EmailIn, pairing and the mailbox save refuse, disabled and expired accounts, `Channel.Refused`), AD-26 (`Channel.Refused` beside `Slack.Ignored`), AD-3 (deviation 3), AD-33 (deviation 4; the new message table `Channel.Refused`, Lane B), the dependency diagram (Channel --> `OcuTalon.Core.Access`). DW-1466's diagram question closes with no Core-to-Web edge.

**Ledger inbox (Rule 17).** `LEDGER slice 0-38-telegram-and-email-turns-check-the-person-s-role-at-use-time`: owned_ledger=1, DW-1284 (routed, med), addressed in full (T1-T7, P1-P2, E1-E7). DW-1465 and DW-1466 are in this branch's ledger as `escalated owner=burndown` (both from 27.3); the 02:05Z ruling put them in 0.38's scope: the lead re-owns both to this story's key (`routed`, `note=ruled_into_0.38`), and this plan addresses them (A2, S1, T5, E5, phase 7; deviation 1). Adjudicate all three `resolved-by` with the diff.

**AC1 correction (Rule 5, apply and report; done by this plan):** epics.md Story 0.38 AC1's Given now reads the ruled wording ("Telegram turns are checked where they reach Core.Conversation; email is checked in EmailIn before an Item is made") and names the predicate `Core.Access MayChat` (DW-1466), with an `[AMENDED 2026-11-17 — see the story change log]` marker.

**Known, not changed:** `Bridge.Approval` approval answers still check roles only (HoldsRole), not account state; a session row whose user is renamed is not followed.

## Verification

**Shared surfaces:** who may pair, have a telegram turn, have an email Item and save the mailbox (every test that expects success there now needs a session whose IrisUser is a real, enabled, unexpired account holding OcuTalonUser); the not_user record's class and table (`Slack.Ignored` -> `Channel.Refused`); `Slack.Ignored.#REASONS`; `ConversationNotUser.TestOtherChannelsUnchecked`; `Shell.MayChat` (deleted); the Web.Api settings answers (a new 409 `not_user`). Unit tests run as `irisowner`, which holds `%All` only and so may NOT chat (`ci/iris.sh` class_script, `lib-live.sh` L492), so sessions of `$Username` are refused too.

The fixture (Rule 2, extend): `Test/Data/Fixture.cls` (B) gains `ChatSession(name, roles = "OcuTalonUser")`: a real account made through `Test.Install.RolesAssign.CreateUser` (no copy), recorded under `^OcuTalonTest("Fixture", "users")`, plus the session row (Keep); `Clean` also drops the recorded accounts of the rows it removes. `Test/Channel/LiveCase.cls` (A) `FixtureSession` makes its `zztg...` session through `ChatSession`, and `DropSessions` drops those accounts. Never grant a role to `irisowner` or any slot account.

Existing tests to move to `ChatSession` (found by a sweep of `src/.../Test`, `docker/tests`, `web/e2e`; the implement stage re-greps for `Fixture.Session(`, `ForUser(` and `$Username` sessions on the paths below):
- Pair: `Test/Core/SessionOps.cls` (the `zzsessops` session, every test that expects paired or unpairs: TestPairValidCode, TestPairUsedCode, TestPairRepeatChangesNothing, TestPairUsedCodeAfterItsExpiry, TestPairChatMoves, TestPairSecondChat, TestPairSameChatNewCode, TestPairMoveOntoASessionWithAChat, TestNotifyReadsTheNotice, TestPairAuditFails, TestPairAuditFailsAfterADrop, TestUnpairStop, TestPageUnpair, TestUnpairOriginsAuditTheirChannel, TestCrossSessionUnpair, TestUnlinkApi, TestUnlinkStandsWhenTheSideEffectsFail, TestEndUnlinksWithoutNotice; the expired, gone-session and unknown-chat refusals keep their outcomes, the check comes after them); `Test/Core/SessionOpsProduction.cls` (3 tests); `Test/Core/AnswersTelegramProduction.cls` TestAnswerFollowsThePairingSessionOpsWrites; `Test/Web/PairingApi.cls` TestCodeRoute, TestPageUnpair; the live Telegram classes through LiveCase: `TelegramPair`, `TelegramChat` (also its file turns), `TelegramDigest`, `TelegramApproval` (its `Paired()` default of `$Username`), `Test/Core/PersonaAnswers.cls` (6 tests on `$Username`). Where a route ties the code to `$Username`'s own session, the test pairs a `ChatSession` instead (re-own the code row before `/start`) and keeps its subject.
- Telegram Item to Conversation: `Test/Core/ConversationTurns.cls` TestTurnKeepsItsChannel; `Test/Core/ConversationFiles.cls` TestFileItemBecomesTurn and TestNoReaderReply (telegram half); `ConversationNotUser` TestOtherChannelsUnchecked (now web only). `Test/Channel/TelegramInTurn.cls` stays as is (text turns are not checked in TelegramIn).
- Telegram files: `Test/Channel/TelegramFile.cls` TestDocument, TestPhoto, TestStreamTooLarge, TestOtherTypeAndEmpty, TestFetchFails, TestFetchBadPath, TestNotSent (the `zztgfile` session); TestReportedTooLarge, TestOnlineDemo and TestNoReader are unchanged (they stop in File, before Turn).
- Email Item: `Test/Channel/EmailIn.cls` TestServiceItem; `Test/Channel/EmailLive.cls` (owner `zzprod...`: every save and poll test).
- Mailbox save: `Test/Core/SettingsEmail.cls` (its `zzsession...` Refs have no row: every test, the refusal tests included, since the check comes first); `Test/Core/CommandsStep4.cls` TestSendEmailAfterSave; `Test/Channel/PageRoute.cls` `Connect()`; `Test/Fix/Email.cls` and `web/e2e/settings/email.spec.ts` save as the README account (holds OcuTalonUser): unchanged.
- Records: `ConversationNotUser` L106/L210 and `AssertRefused`; `ConversationProbe` L51; `Test/Core/Intake.cls` TestIgnoredIsSilent (REASONS without not_user; plus R1); `Test/Channel/SlackIn.cls` L433 (Ignored's properties: unchanged); `docker/tests/test-slack-hook.sh` L112 `ignored_headers` (phase 7's not_user records leave that count), L454, L539-550.

Standing criterion (Rule 19): every test added or changed passes on a fresh environment, in either order, and creates and removes its accounts and rows itself.

**Commands** (from the worktree root; lane D: `LANE="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d"`; every `ci/iris.sh` call carries `OCUTALON_LOCK_DIR="$LANE" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`; one call per tool call, `timeout: 600000`; class runs about 150 s fresh):
- `ci/iris.sh build` once (web changes), then warm: `OCUTALON_RUN_TAG=e038iw ci/warm.sh up`; per class `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e038iw ci/iris.sh class <Class>` for `OcuTalon.Test.Core.Access`, `.Core.ConversationNotUser`, `.Core.SessionOps`, `.Core.SettingsEmail`, `.Core.SettingsSlack`, `.Core.Intake`, `.Channel.EmailIn`, `.Channel.TelegramFile`, `.Channel.TelegramPair`, `.Web.ViewerApi`, `.Web.SettingsApi`, `.Web.Status`, then every class of the Shared surfaces list -- expected: `CLASS ... passed`; `ci/warm.sh down` at the end, also after a failure. Mutations are observed on the warm stack and count only when the class is green again after the revert.
- `OCUTALON_RUN_TAG=e038i ci/iris.sh live slack-hook` (about 375 s) -- expected: every check PASS, phase 7's disabled and expired cases included.
- `OCUTALON_RUN_TAG=e038i ci/iris.sh live sign-in-2 --part k/8`, the part that holds `settings/email.spec.ts` -- expected: passed (with Task 0 (b) yes).
- `node --test web/scripts/email-view.test.mjs` and `bash ci/checks.sh` -- expected: pass.
- Fresh environment (Rule 19, Rule 21): `OCUTALON_RUN_TAG=e038i ci/iris.sh shard lane-b --part k/n` and `shard lane-a --part k/n` (pieces of about 8 minutes, `lane-a@Channel` among them), forward, then each with `--reverse`, one per call -- expected: every class passed; then `ci/iris.sh teardown` with `e038i` and with `e038iw`.

**Mutations:** one per AC as written in Tasks & Acceptance; record each here as `mutation: <change> -> <test> red`, with `git status --short` and `git diff --stat` unchanged after the revert.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning), re-derived on `be0aa2133be8eeda7f951af4c357f87d14f1baf3` with Story 27.3 merged in. For the lead before implement: four deviations under `## Design Notes` (deviation 1 departs from the 02:05Z ruling's literal "Web.Public.Shell then calls Core", which AD-3 forbids; deviation 3 is an AD-3 amendment, a veto-window item); the spine updates (Rule 20); re-own DW-1465 and DW-1466 to this story's key; the epics.md AC1 amendment is applied (Spec Change Log).
