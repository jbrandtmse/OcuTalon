---
title: 'Story 24.3: Deliver pages on the on-call channel and stop escalation on acknowledgement'
type: 'feature'
created: '2026-11-15'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-4-decide-when-to-page-the-on-call-person-and-when-to-escalate.md'
warnings: [oversized, multiple-goals]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 23.4 pages the on-call person, but a page still takes Notify's generic route, so it reaches only the paired Telegram chat. The web chat records a bare row with no card, `EmailOut` refuses every kind but `digest`, the web Got it route accepts tell-now notices only, and `ReminderOps` answers every escalation timer `not_built`. As a result, nothing ever pages the backup, and the Settings On call line has to say so.

**Approach:** Lane B builds the rest of AD-14/AD-18's page contract:
- a `page` route in `Notify` (the web chat card, Telegram when chosen, email when chosen);
- `EmailOut`'s fourth path, the page email;
- the web chat page card, whose Got it submits `AckPage` through the existing got-it route;
- the escalation timer in `ReminderOps`/`Schedule.Reminder` (`Data.Reminder` gains `Kind`, `IncidentRef`, `PageRef`; the waiter sends `Msg.Escalation`; it is re-armed at start, cancelled from `system`, and purged).

The On call line is then replaced with one that is true of the code.

## Boundaries & Constraints

**Always:**
- Pages follow the DW-1251 reading under Design Notes (P1, recommended option A). A user's page has a web chat card in the page's session. It goes to Telegram only when `telegram` is in the page row's `Channels` and the session is paired at send time, and to `EmailOut` only when `email` is in `Channels`. A person who chose one channel gets only that one, plus the chat card. An address-only page (`SessionRef` `instance`) goes to email only. The simulated phone never gets a page.
- `EmailOut` sends a page only to the on-call key of the page row's `Role` (`oncall.primary.email` / `oncall.backup.email`), read from its row at send time. It sends at most one email per page row, claimed by a `Delivery` row of channel `email` with the page's Ref. Its subject is the catalog key `page.subject`, and its body is `Watch.Paging.Text(n, "email")`. It logs counts and outcomes only.
- An acknowledgement reaches `IncidentManager` only as `AckPage` through `Commands.Submit` (AD-1). The web route never decides; `Watch.Paging.Acknowledge` does.
- An escalation `Reminder` row has `SessionRef` `instance`, `Kind` `escalation` and both Refs. It is created and cancelled from origin `system` only, and it never shows in `ListReminders`, a live event or a session's lists. Each page has at most one row (a repeat ask answers the same Ref). Due, it sends `Msg.Escalation` (`IncidentRef`, `PageRef`) asynchronously to `IncidentManager`, never a Notification.
- On the online demo nothing is paged:
  - `Watch.Paging` already refuses;
  - `ReminderOps` refuses an escalation, `EmailOut` sends no page, and the Notify functions are false;
  - the got-it route answers 404 for a page Ref.
- No on-call value, Telegram chat id or display name appears in any message body or header OcuTalon writes, any log line, audit entry, trace or payload (AD-19, NFR-11). The rendered channel text and its Delivery row are the approved exception (23.4 deviation 1).
- Text comes only from the catalog and approved strings (Public text). Storage is append-only, with committed storage blocks (AD-5).

**Never:**
- Edit `Watch/IncidentManager.cls`, `Watch/Paging.cls`, `Data/Page.cls`, `Msg/Catalog/Watch.cls`, `Core/SessionOps.cls` or `Channel/Telegram/In.cls`. Lane A edits are only the two listed under Veto items (V5).
- Add a route, a verb, a table, a catalog key, a production item or a web dependency.
- Let a reply to a page email acknowledge anything (ruling V5: email is untrusted content).
- Make a timer outside `ReminderTimer` (AD-5), or create a Session row for a page.
- Fall back from an unreachable Telegram to email, or from email to anything else. A chosen channel that cannot be reached is reported, not replaced.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| User, both channels, paired | page Notification (SessionRef S, DecisionRef P, Channels `telegram,email`) | 1 web chat card (Delivery kind `page`, text = `Paging.Text(n,"web")`, Got it); 1 Telegram `sendMessage` (23.4's); 1 email to the role's key address, subject `page.subject`, header `X-OcuTalon-Ref` | none |
| One channel chosen | Channels `telegram` (or `email`) | the chat card plus only that channel | none |
| Telegram chosen, not paired | Channels `telegram`, S unpaired | the chat card; no `sendMessage`; one TelegramOut Delivery row (channel telegram, kind page, DecisionRef P, FallbackReason `not_paired`, no text) that the paging owner reads with `Delivery.FindByRef` | no error status, no warning with an identity |
| Address-only person | SessionRef `instance`, Channels `email` | email only; no chat card, no Telegram | none |
| Email cannot go | `email` chosen, role address empty or not an address, or no mailbox (`email.address`) | no email; one Delivery claim row for P with FallbackReason `no_address` / `no_mailbox` | one count-only warning |
| Same page again | the same Notification delivered twice to EmailOut | no second email | none |
| Online demo | `onlineDemo` 1 | EmailOut sends nothing; `PageEmail` is false; ReminderOps refuses escalation (`not_allowed`); got-it for a page Ref answers 404 | refusal by code |
| Web Got it on a page | POST `/v1/decisions/P/got-it` from S (body `{}`) | `AckPage` {P, web} from `web_user`; 200 `{"result":"done","handledAt"}` (`Page.Marked(P)`); the card and the Telegram copy show "Marked as handled at {time}"; the escalation is cancelled (23.4) | another session, an unknown Ref, or a Ref that is neither tell-now nor a page copy of S: 404 `not_found`, nothing submitted |
| Second press, any channel | P already acknowledged | 200, same handledAt; nothing changes | none |
| Escalation set | SetReminder {Kind escalation, IncidentRef, PageRef, DelaySeconds 900} from `system` | row (SessionRef `instance`, pending, Kind, Refs, DueAt now+900 s, Text ""), one live waiter, Ok 1 `set` with Ref and DueAt; no live event | from any other origin: `not_allowed`; bad Refs or delay: `refused` `bad_time`; a failed start deletes the row and answers `failed` |
| Escalation asked again | the same PageRef | the first row's Ref and DueAt, no new row or waiter | none |
| Escalation due | waiter wakes at DueAt, row pending | row `fired` (Late as for reminders); one `Msg.Escalation` to `IncidentManager`; no Notification, no publish | a failed send is logged with the Ref, not retried |
| Escalation cancelled | CancelReminder {ReminderRef} from `system` on a pending escalation row | `cancelled`; the waiter interrupted; Ok 1 | from a session origin: `no_reminder`, nothing changed |
| Restart | a pending escalation row, its waiter gone (one due during downtime) | Reconcile re-arms it; one due in the past fires about 1 s after the start | none |
| Lists | a session lists reminders, or reads `/state` or its reminder notes | no escalation row appears | none |
| Purge | fired or cancelled escalation rows created before the cutoff | deleted; pending and newer rows stay | as the other parts |

</intent-contract>

## Code Map

All paths are under `src/ocutalon/cls/OcuTalon/` unless they start with a top-level folder.

**Routing (Lane B)**
- `Core/Rule/Notify.cls`:
  - `page` takes the generic branches at 71-82 today.
  - The `Notification` rule (35-83) is first-match. The second rule `DigestEmail` (84-89) adds EmailOut and is the pattern for `PageEmail`.
- `Core/Rule/Functions.cls`: `IsSession` 8, `TelegramOn` 30, `TelegramPaired` 36. `DigestEmail` 73 is the model for `PageEmail`, including the EmailOut alive-job check and the online-demo check.
- `Test/Core/Routing.cls` evaluates rules on a shadow router. `TestNotifyTargets` 224 enumerates every kind, so it is a shared surface; `TestNotifyDigestEmail` 317 is the sibling.

**Email (Lane B; outside epic-24's paths_hint)**
- `Channel/Email/Out.cls`:
  - `OnNotification` 289-299 calls `SendDigest`, which warns at 304-306 for any other kind.
  - `SendDigest`/`SendDigestLocked` 301-365 are the page path's sibling (from-address check, render, `CheckValues`, lock, `Transmit` 277 with `REFHEADER` 96).
  - The one-send claim pattern is `Claimed` 542 / `SendClaimed` 194.
  - `MESSAGEUNAVAILABLE` 135.
- `Data/Delivery.cls`: `Record` 69 (fallbackReason, digestKey), `FindByRef` 176.
- Tests: `Test/Channel/EmailLive.cls` (running production, CI SMTP mock `ci/mock/smtp.mjs`, `OCUTALON_TEST_PLAIN_SMTP` with host `mock`); `Test/Channel/EmailOut.cls`.

**Web chat card and Got it (Lane B; `Channel/WebChat`, `Live/Payload/Notification.cls` and `web/src/app/chat/**` are outside epic-24's paths_hint)**
- `Channel/WebChat/Out.cls`:
  - `CARDKINDS` 51 has no `page`, so 82-83 record a bare row.
  - The render branches are at 85-92, with `summary` → `Watch.Summary.Text` as the pattern.
  - `OnHandled` 102-110 republishes `tellnow` cards only.
- `Live/Payload/Notification.cls:63`: `handledAt` is set for `tellnow` only (`Handled.Marked`).
- `Web/Api.cls`:
  - route 278;
  - `GotIt` 898-922 (tell-now Decision only, 404 otherwise), `GotItChannel` 925.
  - The sibling verb switch is `Channel/Telegram/In.cls:442` (AckPage chosen by the Delivery row's Kind).
- `Data/Ownership.cls`: `DeliveryByRef` 659, `SessionRef`.
- Web:
  - `web/src/app/chat/chat-view.ts`: `NoticeKind` 158, `noticeOf` 247 (drops `page`), `strip` 272.
  - `web/src/app/chat/notice-card.ts:76`: Got it for `tellnow` only.
  - `web/src/app/chat/got-it.ts` and `api-client.ts:267` stay unchanged.
  - The web catalog already has `handled.marked` (`web/src/app/msg/catalog.ts:70`).
- Tests: `Test/Web/GotItApi.cls` (`TestPressUpdatesEveryCopy` 83 is the pattern); `Test/Core/WebChatOut.cls` (pins CARDKINDS); `web/scripts/chat-view.test.mjs`, `chat-announcements.test.mjs`; `web/e2e/chat/notice.spec.ts` (the chromium project, `live:sign-in`).

**Escalation timer (Lane B, Schedule/**)**
- `Schedule/ReminderOps.cls`:
  - `Set` 101-138: line 103 answers `not_built`.
  - `Cancel` 175-212 and `IsPending` 215 (`Ownership.Reminders`, by session).
  - `EndWaiter` 246-265 and `StartWaiter` 276-287 need the session's TraceRef.
  - `SendIn` 292. `Refuse`/`Done`/`Result` 318-340.
- `Schedule/Reminder.cls`:
  - `Wake` 123-160 sends a `reminder` Notification and publishes.
  - `StartFrom` 192-210 errors with no session.
  - `Reconcile` 217-246 skips a row whose SessionRef names no Session (238-240).
  - `LiveWaiter` 164.
- `Data/Reminder.cls` 1-88 has no Kind, IncidentRef or PageRef; its storage is Values 1-11.
- `Msg/Command/SetReminder.cls` (Kind 18, IncidentRef 21, PageRef 24), `Msg/Escalation.cls`, `Core/CommandsIn.cls:344-346` (origins include `system`), `MESSAGENOTALLOWED` 87.
- Production items: `IncidentManager` (Production.cls:57), `ReminderOps`/`ReminderTimer` 100-101 (pool 1).
- `Data/Purge.cls`: session-scoped Reminder delete at 104, `Keeps` pending check at 133. No part reaches `instance` rows.
- Readers that must keep excluding instance rows (all `WHERE SessionRef = ?`): `Data/Ownership.cls:1236, 1361, 1442`.
- Tests:
  - `Test/Schedule/Reminders.cls`: `TestEscalationNotBuilt` 674 and `TestEscalationGuardComesFirst` 730 are replaced.
  - Probes `ReminderOpsProbe`, `ReminderOpsSendProbe`, `ReminderOpsStartedProbe`, `ReminderTimerDouble`, `ReminderFixture`.
  - `docker/tests/test-production-restart.sh` (append a phase).

**Paging owner, already built (Lane A; read only except V5)**
- `Watch/IncidentManager.cls`:
  - `Arm` 2082-2097 asks SetReminder escalation from `system`, with DelaySeconds = minutes x 60 and no SessionRef or key, and records `result.Ref` through `Paging.Armed`.
  - `SendCommand` 2101 is the probe seam.
  - `Escalated` 2104 handles `Msg.Escalation`.
  - `Cancel` 2173-2181 is the CancelReminder from `system`, which warns unless Ok.
- `Watch/Paging.cls`:
  - `Notice` 150 (Channels from the role's key, SessionRef = `SessionOf` 130: the paired session, else the first, else `instance`);
  - `Escalate` 171, `Acknowledge` 251 (channels web, phone, telegram; the session must be `SessionOf(Person)`);
  - `Handled` 267 (one `handled` Notification to the page's session);
  - `Text` 329 (the `email` variant at 372), `KEYSUBJECT` 58, `OnlineDemo` 90.
- `Data/Page.cls`: Channels 34, `Marked` 67, `RefIndexOpen`.
- `Channel/Telegram/Out.cls`:
  - `KINDS` 112, `GOTITKINDS` 126;
  - the page branch 213-214; `Target` returns no chat for an unpaired session at 207-208 (V5 hooks here);
  - `EditHandled` falls back to `Page.Marked`.
- Tests: `Test/Watch/PagingLive.cls:327` `TestEscalationAsk` asserts `not_built` (DW-1384); `Test/Watch/IncidentProbe.cls` (`SendCommand` fixture); `Test/Channel/TelegramPageFixture.cls`, `LiveCase.cls`.

**Settings line (Lane B section, Lane C pins)**
- `web/src/app/settings/settings-view.ts:102` `telegramOnly`, and `byEmailHelp` 108, which stays.
- `web/src/app/settings/on-call-section.ts:64-68` (`@if (!pagesBuilt())` / `oncall-telegram-only`) and its doc 43-44.
- Pins:
  - `web/scripts/ux-strings.test.mjs:1142`;
  - `web/scripts/on-call-view.test.mjs:41`;
  - `web/e2e/settings/on-call.spec.ts:44` (O1, the sign-in-2 project).
- `pagesBuilt`: `Core/SettingsOps.cls:2811`, which stays.

## Tasks & Acceptance

**Execution (Part A: delivery and the web acknowledgement):**
- [ ] Task 0 (measure first; record under Design Notes › Measured; label anything unmeasured "(inference)"). On a fresh lane-D throwaway, measure:
  - (a) how long `IncidentManager`'s `Arm` takes with the real waiter start (the sync chain IM → CommandsIn → ReminderOps → ReminderTimer), and that nothing deadlocks;
  - (b) that a page Notification sent to Notify with `email` chosen reaches the SMTP mock through the enabled EmailOut, and the mail's headers;
  - (c) what TelegramOut does today for a page to an unpaired session (no call, no warning, no row expected).
- [ ] `Core/Rule/Functions.cls`:
  - add `PageChannel(decisionRef, channel)`: 1 when the `Data.Page` row of the Ref exists and its `Channels` lists the channel. It reads by object access and is never true on the online demo.
  - add `PageEmail(decisionRef)`: `PageChannel(…,"email")`, and EmailOut has an alive job (as `DigestEmail`).
  - Both are pure reads (AD-14).
- [ ] `Core/Rule/Notify.cls`:
  - In the `Notification` rule, after the digest branches and before the generic ones:
    - `Kind="page" && 'IsSession(SessionRef)`: no target;
    - `Kind="page" && TelegramOn() && PageChannel(DecisionRef,"telegram")`: `WebChatOut,TelegramOut`;
    - `Kind="page"`: `WebChatOut`.
  - Add the rule `PageEmail`: `Kind="page" && PageEmail(DecisionRef)` → `EmailOut`.
  - Update the class doc. -- AD-14 as amended (P1).
- [ ] `Channel/Email/Out.cls`:
  - `OnNotification` dispatches on Kind: `digest` → `SendDigest`, `page` → a new `SendPage`. The class doc lists the fourth path.
  - `SendPage` steps:
    - check the online demo first;
    - read the page row (absent, or `email` not in `Channels`: a warning, nothing sent);
    - the to-address is the role's key, `Fresh`; the from-address is `email.address`;
    - the subject is `Catalog.Render("page.subject", {production}, "email")` (production from the Notification's Slots);
    - the body is `Paging.Text(n, "email")`, checked with `CheckValues`;
    - claim one `Delivery` row (channel email, kind page, DecisionRef P, `DigestKey` P) under a lock, so a second Notification for P sends nothing;
    - one `Transmit` with `X-OcuTalon-Ref`;
    - no address or no mailbox marks the claim row with FallbackReason `no_address` / `no_mailbox` and sends nothing.
  - No daily cap. -- AD-14 fourth send.
- [ ] `Channel/WebChat/Out.cls`:
  - `page` joins `CARDKINDS`; its text is `Watch.Paging.Text(request, ..#TEXTCHANNEL, .sc)`, beside `summary`.
  - `OnHandled` republishes a card of kind `tellnow` or `page`.
- [ ] `Live/Payload/Notification.cls` -- `handledAt` for a `page` row is `Data.Page.Marked(DecisionRef)`.
- [ ] `Web/Api.cls` `GotIt`:
  - when the Ref is not the session's tell-now Decision, look for the session's own web copy of a page (`Ownership.DeliveryByRef(ref, "web", session)` of kind `page`);
  - for a page copy, submit `AckPage` {Ref, SessionRef, Channel `GotItChannel()`} from `web_user`;
  - answer 200 `{"result":"done","handledAt": Page.Marked(ref)}` on Ok, 404 on `not_found`, and as today otherwise;
  - anything else stays 404 before any submit;
  - update the route doc. -- AD-1, AD-14.
- [ ] `web/src/app/chat/chat-view.ts`, `notice-card.ts` -- `page` joins `NoticeKind` and `noticeOf`. A page card shows Got it (channel web) until `handledAt`, then the `handled.marked` line, exactly as a tell-now card does. It has the tell-now icon and no strip.
- [ ] `Channel/Telegram/Out.cls` (V5, Lane A, about 5 lines) -- in `OnNotification`, for kind `page` with no chat target: record one Delivery row (session, channel telegram, kind page, DecisionRef, FallbackReason `not_paired`, no text) and return OK. This is the undelivered report (P2).

**Execution (Part B: the escalation timer):**
- [ ] `Data/Reminder.cls` -- append `Kind` (32), `IncidentRef` (22), `PageRef` (22); let the compiler append the storage slots (12-14). -- AD-5, AD-18.
- [ ] `Schedule/ReminderOps.cls`:
  - `Set` for Kind `escalation`:
    - refuse `not_allowed` (`CommandsIn.MESSAGENOTALLOWED`) unless the Origin is `system` and it is not the online demo;
    - refuse `bad_time` unless IncidentRef and PageRef are Refs and DelaySeconds is a whole number > 0;
    - an existing row for the PageRef answers `set` with its Ref and DueAt;
    - otherwise save the row, start the waiter with an empty SuperSession, publish nothing, and answer `set`.
  - `Cancel`: from `system`, a pending row of Kind `escalation` named by ReminderRef is cancelled without a session check, the waiter is ended, and nothing is published. Any other origin keeps today's session path, so an escalation row is `no_reminder` there.
  - `StartWaiter`/`EndWaiter` use an empty SuperSession for an `instance` row.
  - Update the class doc.
- [ ] `Schedule/Reminder.cls`:
  - `Wake`: a pending escalation row is marked fired (with Late) and sends one `Msg.Escalation` (IncidentRef, PageRef) asynchronously to `IncidentManager`; no Notification and no publish.
  - `StartFrom`: an `instance` escalation row starts with an empty SuperSession.
  - `Reconcile`: an `instance` escalation row is re-armed, not skipped.
  - Update the class doc.
- [ ] `Data/Purge.cls` -- a new part deletes Reminder rows with `SessionRef = 'instance'`, a state of fired or cancelled, and `CreatedAt` before the cutoff. The class doc is updated. -- AD-27 (V1).

**Execution (Part C: the line, the spine and the tests):**
- [ ] `web/src/app/settings/settings-view.ts`, `on-call-section.ts` -- replace `telegramOnly` with `pages`, whose text is the NEW On call line verbatim (Public text). The template id becomes `oncall-pages`, shown while `pagesBuilt`; the doc comment is updated. `notYet` and `byEmailHelp` are unchanged.
- [ ] Spine (the lead, Rule 20, once the Planner rules): amend AD-14's page bullets as P1 rules; add to AD-18 the as-built escalation (empty SuperSession, one row per PageRef, purge); add to AD-27 the `instance` reminder rows. Recompile `epic-24-context.md`.
- [ ] `GUIDE.md` -- the On-call pages bullet (Public text), only if the Planner approves P4.
- [ ] Tests (each with the mutation under Verification):
  - `Test/Core/Routing.cls`:
    - new `TestNotifyPageTargets`: a page Notification, a session with Telegram chosen, paired or not and Telegram on or off; email only; an `instance` session; demo mode on (no SimPhoneOut); and the rule `PageEmail` with no alive EmailOut;
    - `TestNotifyTargets` updated for the kind `page`;
    - `TestFunctions` gains `PageChannel` and `PageEmail`.
  - `Test/Channel/PageRoute.cls` (NEW; running production, the CI Telegram and SMTP mocks, the `TelegramPageFixture`/`EmailLive` set-up) covers Matrix rows 1-6 end to end through Notify:
    - the mail's To is the role's key address, and the subject and body equal the catalog renderings;
    - one email per page;
    - the backup role's address;
    - no identity in the messages, the logs or the audit.
  - `Test/Schedule/Escalation.cls` (NEW, warm; ReminderOps probes) covers Matrix rows 9-15. The Reminders tests at 674 and 730 are replaced by it.
  - `Test/Schedule/EscalationLive.cls` (NEW; running production, real `IncidentManager`, a fixture `Data.Page` on-call row with a backup configured):
    - an escalation asked from `system` with DelaySeconds 3 makes exactly one backup page row;
    - one cancelled before it falls due makes none.
  - `Test/Web/GotItApi.cls` -- real HTTP:
    - a page press gives 200 with handledAt, the row is acknowledged with channel web, and the Telegram copy is edited (mock `editMessageText`);
    - a second press gives 200 with no change;
    - another session gets 404 and nothing is submitted;
    - the online demo gives 404.
  - `Test/Watch/PagingLive.cls:327` (V5, DW-1384) -- `TestEscalationAsk` asserts Ok 1, `set`, a Ref recorded as the page's `EscalationRef`, and one pending `instance` row.
  - `Test/Data/Tables.cls` (Reminder contract) and `Test/Data/Purge.cls` (the instance-row part).
  - `docker/tests/test-production-restart.sh` -- append one self-contained phase. Before the kill, seed a fixture page with a pending escalation row due in about 5 s and one due in 1 h. After the start:
    - the first fires exactly once (one backup row);
    - the second has a live waiter.
  - `web/scripts/chat-view.test.mjs` (the page notice view), `ux-strings.test.mjs:1142`, `on-call-view.test.mjs:41`, `web/e2e/settings/on-call.spec.ts:44` O1 (the new line, the old one absent).
  - `web/e2e/chat/page-card.spec.ts` (NEW, Rule 3): as the LIVE user with a seeded page:
    - the chat shows the page card with the page text and Got it;
    - pressing it shows "Marked as handled at {time}";
    - a reload keeps it.

**Acceptance Criteria:**
- AC1: Given a page with each Channels value and pairing state, when Notify routes it, then exactly the targets of Matrix rows 1-4 receive it. A chosen channel that is unreachable sends nothing there. An unpaired Telegram leaves one `not_paired` row that `Delivery.FindByRef(P,"telegram",S)` returns (`Test.Core.Routing`, `Test.Channel.PageRoute`).
- AC2: Given `email` chosen and a mailbox configured, when the page is delivered, then the SMTP mock receives one mail:
  - To: exactly the role's key address;
  - Subject: the `page.subject` rendering;
  - body: the `page.*Email*` rendering, with an `X-OcuTalon-Ref` header.
  A second delivery of the same Notification sends none. The online demo sends none (`PageRoute`).
- AC3: Given a user's page, when the LIVE user opens the chat and presses Got it, then:
  - `AckPage` reaches `IncidentManager` once with channel web;
  - the web card and the Telegram copy show "Marked as handled at {time}";
  - a second press changes nothing;
  - another session's press is 404 (`GotItApi`, `page-card.spec.ts`).
- AC4: Given IncidentManager's escalation ask, when it is set, then one pending `instance` row with the Kind and both Refs and one live waiter exist. It appears in no session's `ListReminders`, `/state` or reminder notes. A repeat ask, or an ask from any origin but `system`, creates nothing (`Escalation`, `PagingLive` `TestEscalationAsk`).
- AC5 (Integration, Rule 1): Given a pending escalation of an unacknowledged on-call page, when it falls due, then the real `IncidentManager` records exactly one backup page. When it is cancelled first (an acknowledgement or a close), no backup page is recorded (`EscalationLive`).
- AC6: Given pending escalation rows and a real restart, when the production starts, then a row due during the downtime fires once within about 2 s of the reconcile, and a future one is re-armed (`live:production-restart`).
- AC7: Given `pagesBuilt` true, when the On call section renders, then it shows the NEW On call line verbatim and not the 23.4 line (unit pins and O1).
- AC8: Given every test above, when it runs with a distinctive fixture name and address, then no message, log line, trace, audit entry or payload holds a chat id, a display name, `oncall.*.user` or `oncall.*.email`. Each surface is checked against a distinctive fixture name or address, with a positive control.

## Spec Change Log

## Review Triage Log

## Design Notes

### For the Planner's gate (CHOICES, each with a recommendation)

**P1. DW-1251: AD-14's page route.**

The contradiction has three parts:
- AD-14 lists "the web chat of that user's session" among the chosen channels, although `oncall.*.channels` holds only `telegram,email` (`Core/SettingsOps.cls:936-943`).
- It says "a person with no paired chat ... gets email only", which contradicts that web copy.
- It says every `*Out` updates its copy, although an email cannot be edited.

The choice:
- **(A, recommended)**:
  - A user's page always has a web chat card in the page's session (it is not a "channel"). Telegram and email follow `Channels` exactly, with no fallback.
  - "Email only" applies to an address-only person.
  - On acknowledgement, the chat card and the Telegram copy show `handled.marked`. An email copy is never changed (it carries no acknowledgement, as ruled in V5).
  - Why: the approved texts `page.onCallEmail`/`page.backupEmail` say "press Got it on your OcuTalon page", and AD-15 and the 36.1 rulings name "the page card's Got it" as the web acknowledgement. Only (A) gives a user who chose email-only a place to press it.
- **(B)**: a web card only when no Telegram copy goes. A user paged by Telegram then has a single acknowledgement place, and an email-only user still gets a card. This contradicts nothing approved but adds a rule users can't see.

This spec is planned on (A). Under (B), the Notify branch changes, and the On call line takes its option-B form.

**P2. "Reported back to the paging owner as undelivered with a plain reason".**

No contract defines the report.
- **(a, recommended)**: the page is routed to `TelegramOut` whenever `telegram` is chosen (with Telegram on). `TelegramOut` then records a Delivery row with the code `not_paired` when there is no chat, which the paging owner reads with `Delivery.FindByRef`. It is a row, as AD-5's "rows are the truth" expects, with no new message. Cost: a cross-lane edit of about 5 lines (V5).
- **(b)**: a new message to `IncidentManager` with a handler. That is a new contract and a Lane A handler, so it is not recommended now.

Displaying the report (on the incident card, for example) is not in this story.

**P3. The On call line (DW-1400 replacement; orchestrator line binding).** The NEW text is under Public text. It is true of the code at merge, DW-1409 included:
- "for failures it finds in the productions it watches" holds for the edge where a production is unwatched between the poll and the notice, because the failure was found while it was watched.
- "while its user stays signed in" holds for the edge where the session row is gone. `Data/Purge.cls` `Keeps` never deletes a session that a live CSP session holds, so `FailurePoller.Scope` (`Watch/FailurePoller.cls:134-141`) scopes that user's Break the feed to the session, and `Paging.Notice` refuses it (OwnerRef is not `instance`, `Watch/Paging.cls:155`).
- "Email pages go out from the mailbox set up under Channels" holds because `PageEmail` requires an alive EmailOut and `email.address`.

Recommendation: approve. The alternative, closing DW-1409 in Lane A code (`FailurePoller`/`Paging`), is larger and contended.

**P4. Findability (23.4's accepted deviation 3: "24.3 carries them").**
- Recommendation: one GUIDE.md bullet (Public text) and NO More to try item. The online demo never pages, so a try-it item would lead a judge to nothing visible.
- Alternative: neither.

**P5. Rule 5 split, recommended YES.** The story has three goals (delivery, acknowledgement paths, escalation timers) and about 25 files.
- 24.3a: "Deliver pages on the chosen channels and acknowledge them on the web" (Part A, the routing and web tests, the P1 spine amendment).
- 24.3b: "Page the backup when nobody acknowledges: the escalation timer" (Part B, the restart phase, DW-1384, the On call line and GUIDE).

The On call line must ship with 24.3b, because it promises email and escalation. Without a split the spec stands as written; the parts are already ordered for it.

### Already built (evidence on the feature; not re-planned)
- The paging owner and its decisions: `Watch/Paging.cls` (Notice 150, Escalate 171, Acknowledge 251, Handled 267, Closing 280, Armed 293, Text 329 with the email variant 372, Audit 376) and `IncidentManager` (Arm 2082, Escalated 2104, Cancel 2173).
- The page row: `Data/Page.cls`.
- The catalog keys, all approved:
  - `Msg/Catalog/Watch.cls` 1277-1374: `page.onCall`, `page.onCallEmail`, `page.backup`, `page.backupEmail`, `page.subject`, `page.onCallAlone`, `page.onCallEmailAlone`, `page.causeUnknown`;
  - `button.gotIt` 426 and `handled.marked` 431.
- Telegram delivery and Telegram Got it (23.4): `Channel/Telegram/Out.cls` 38-41, 112, 126, 213-214 and `EditHandled`; `Channel/Telegram/In.cls:52,442`.
- `AckPage` routing: `Core/CommandsIn.cls:383`. `system` origins for the reminder verbs: 344-346.
- What 23.4 sends: the escalation ask, its cancel on acknowledgement and close, and the probe fixture `Test/Watch/IncidentProbe.cls`. Until now `ReminderOps.cls:103` answers `not_built`, so `EscalationRef` stays empty.
- `pagesBuilt`: `SettingsOps.cls:2811`.
- Break the feed never pages: 23.4's `Test/Watch/PagingLive.cls:700` `TestSessionBreakNeverPages`.

### Governing ADs (Rule 6)
AD-1 (AckPage and the timer verbs through Submit), AD-4 (session-scoped copies and lists), AD-5 (row truth, append-only storage, the reconciler), AD-13 (object-access reads), AD-14 (the route, EmailOut's fourth send, Got it, no chat id), AD-15 (the paging rules), AD-17 (no identity in the audit), AD-18 (escalation timers), AD-19 (the on-call keys, read at send time), AD-22 (mocks, throwaways), AD-25 (the online demo), AD-26 (waiter trace sessions), AD-27 (purge), AD-29/33 (lanes, one writer), AD-32 (catalog only). The spine edits are listed in Part C.

### Decided in-stage
1. An escalation row's waiter has an empty SuperSession: no Session TraceRef exists for `instance`. Its trace session starts at its own start header.
2. Repeat detection for escalations is by PageRef, not by IdempotencyKey. `Arm` sends none, and IncidentManager is not edited. No index is added; the read is SQL over few rows.
3. Page emails have no daily cap. There is at most one per page row, and pages are at most two per incident.
4. A page card uses the tell-now card's look and Got it. No new web text.
5. A user with several sessions gets the card in the page's session only (`Paging.SessionOf`), the one whose Got it `Acknowledge` accepts.
6. The simulated phone gets no page, following AD-14's list. Demo mode does not add it.
7. With Telegram not included (`TelegramOn` false), a Telegram choice routes nowhere and leaves no `not_paired` row.

### Integration ACs (Rule 1) and linkage (Rule 2)
- **Integration:** AC5 (the real IncidentManager consumes the waiter's `Msg.Escalation`), AC3 (IncidentManager consumes the web route's `AckPage`; TelegramOut consumes the `handled`), AC1/AC2 (WebChatOut, TelegramOut, EmailOut and the SMTP mock consume Notify's route).
- **Consumes:** 23.4's `Watch.Paging` (Text, Acknowledge, Marked), `Data.Page`, IncidentManager's `Arm`/`Cancel`/`Escalated`; 36.2's `AckPage`, `Msg.Escalation`, `SetReminder` fields; 21.6/21.7's EmailOut claim and transmit; 18.4's got-it route and card.
- **Consumed-by:** 24.4a/b's cards (the `page` payload, unchanged); the burn-down for any undelivered-report display (P2).

### Extend, don't copy (Rule 2)
- `SendPage` extends EmailOut's digest path and claim pattern.
- `PageEmail` mirrors `DigestEmail`.
- The page card reuses the tell-now card and `GotIt`.
- The got-it route switches verb as `TelegramIn` does.
- The escalation reuses ReminderOps' row, waiter, reconcile and purge.
- The tests reuse `EmailLive`, `TelegramPageFixture`, `LiveCase`, the ReminderOps probes and `Fixture`.

### Ledger (Rule 17; `LEDGER slice 24-3-…`)
- DW-1251: addressed by P1 (choice A) and the AD-14 amendment (Part C).
- DW-1384: addressed by the `TestEscalationAsk` task (V5).

### CI
- No new unit. `Test.Schedule.*` and `Test.Channel.PageRoute` join their areas' shards.
- `page-card.spec.ts` runs in the chromium project (`live:sign-in`), O1 in sign-in-2.
- The restart phase adds about 10-20 s to `production` (inference).

## Public text

1. **NEW — the On call line** (`web/src/app/settings/settings-view.ts` `onCall.pages`; replaces DW-1400's line), verbatim, option A:
   "OcuTalon pages the on-call person for failures it finds in the productions it watches: in their OcuTalon chat if they're an OcuTalon user, and by Telegram or email as chosen below. Email pages go out from the mailbox set up under Channels. If nobody presses Got it within the minutes below, OcuTalon pages the backup. A practice Break the feed pages nobody while its user stays signed in."
   - Option-B form (only if P1 = B): the same text with "in their OcuTalon chat if they're an OcuTalon user, and by Telegram or email as chosen below" replaced by "by Telegram or email as chosen below, and in their OcuTalon chat when no Telegram message goes".
2. **NEW — the GUIDE.md bullet** (only if P4 is approved):
   "- **On-call pages.** On your own install, choose an on-call person and a backup in Settings > On call. When OcuTalon finds failures in a production it watches, it pages the on-call person in their OcuTalon chat and by Telegram or email, and pages the backup if nobody presses Got it in time. The online demo never pages anyone."
3. Existing approved text, used unchanged:
   - `page.onCall`, `page.onCallEmail`, `page.backup`, `page.backupEmail`, `page.subject` "OcuTalon page: {production} incident" (36.1 gate, 2026-11-12);
   - `page.onCallAlone`, `page.onCallEmailAlone`, `page.causeUnknown` (23.4 Planner ruling, 2026-11-15);
   - `button.gotIt` "Got it";
   - `handled.marked` "Marked as handled at {time}" (UX-DR143; `Msg/Catalog/Watch.cls:431`, `web/src/app/msg/catalog.ts:70`): existing, not new;
   - `onCall.notYet` and `onCall.byEmailHelp` (36.4);
   - the got-it 404 `MESSAGENOTFOUND`;
   - `CommandsIn.MESSAGENOTALLOWED`, model-facing and never shown.

## Veto items

- **V1 (NEW) Stored data.**
  - `Data.Reminder` appends `Kind`, `IncidentRef` and `PageRef` (names fixed by AD-18 at 36.2).
  - Escalation rows are owned by `instance`.
  - Retention: `Data.Purge` deletes finished `instance` reminder rows older than `daysToKeep`. This is a new purge part (AD-27).
  - Online demo: no row is ever written (ReminderOps refuses; Paging never asks).
- **V2 (NEW) Outward action: page emails** through EmailOut to the on-call key's address, at most one per page row, with no approval (FR-28; AD-14's fourth send, ruled V5 at 36.2).
  - Online demo: never. Paging refuses, `PageEmail` is false and EmailOut refuses, each by code.
  - Tests reach only the CI SMTP mock.
- **V3 (NEW) Changed route:** `POST /v1/decisions/:ref/got-it` also accepts the session's own page copy and submits `AckPage` (origin `web_user`). No new route or grant.
  - Online demo: 404, since no page exists and `Acknowledge` answers `not_found`.
- **V4 (NEW) AD amendment:** AD-14's page bullets per P1. AD-18 and AD-27 get as-built additions (Part C).
- **V5 (NEW) Cross-lane edits (Lane A):**
  - `Channel/Telegram/Out.cls`: the `not_paired` row, about 5 lines (P2);
  - `Test/Watch/PagingLive.cls` `TestEscalationAsk`: DW-1384;
  - no `IncidentManager`, `Paging` or `Data.Page` edit.
- **V6 (NEW) Footprint extensions** (Lane B files outside epic-24's paths_hint):
  - `Channel/Email/Out.cls`, `Channel/WebChat/Out.cls`;
  - `Core/Rule/Functions.cls`, `Live/Payload/Notification.cls`, `Data/Purge.cls`;
  - `web/src/app/chat/{chat-view,notice-card}.ts`, `web/scripts/chat-view.test.mjs`;
  - `docker/tests/test-production-restart.sh`, `GUIDE.md` (P4).
  - `Watch/**` is untouched.
- **V7 (NEW) Public text:** the On call line and the GUIDE bullet.
- None: a new verb, table, catalog key, production item, privilege or web dependency.

## Verification

Every IRIS call runs from the worktree root with:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'
```

- The warm tag is `e24s3iw` and the fresh tag is `e24s3i`. IRIS MCP lookups run only on `ocutalon-slot-d`/`OCUTALON`.
- Each line is one foreground call (`timeout: 600000`) that ends inside about 150 s. Run one class or one `Class:Method` per call, and never two test calls in one message.
- After a `web/` change, `ci/iris.sh build` comes before a browser part.

**Shared surfaces:**
- Notify's targets for every kind (`Test.Core.Routing` `TestNotifyTargets`, `TestFunctions`, `TestRuleTargetsAreProductionItems`; `Test.Core.RoutingProduction`).
- WebChatOut `CARDKINDS` (`Test.Core.WebChatOut`) and the chat's notice kinds (`chat-view.test.mjs`, `chat-announcements.test.mjs`, `web/e2e/chat/notice.spec.ts`).
- The Reminder contract and its readers: `Test.Data.Tables`, `Test.Data.Ownership`, `Test.Data.Purge`, `Test.Schedule.Reminders` 674/730, the storage check `docker/tests/test-storage.sh`.
- `Test.Watch.PagingLive` `TestEscalationAsk`.
- The On call texts (`ux-strings`, `on-call-view`, O1).
- The got-it route (`Test.Web.GotItApi` `TestDigestDecisionIs404` stays 404).
- The mock call logs: the Telegram chat ids and the SMTP mailboxes used are new to this story.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `npm --prefix web test` -- passes.
- (once) `npm --prefix web run lint` and `npm --prefix web run build` -- pass, with no budget error.
- (once) `... OCUTALON_RUN_TAG=e24s3iw ci/warm.sh up` -- ready.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s3iw ci/iris.sh class <Class>`, one call each:
  - `OcuTalon.Test.Core.Routing`, `OcuTalon.Test.Schedule.Escalation`, `OcuTalon.Test.Schedule.Reminders`;
  - `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Data.Purge`, `OcuTalon.Test.Core.WebChatOut`;
  - `OcuTalon.Test.Channel.EmailOut`, `OcuTalon.Test.Web.GotItApi`.
  - Each gives `CLASS ... passed`.
- (once) `... OCUTALON_RUN_TAG=e24s3iw ci/warm.sh down`.
- (once, each its own call) `... OCUTALON_RUN_TAG=e24s3i ci/iris.sh class` for `OcuTalon.Test.Channel.PageRoute`, `OcuTalon.Test.Schedule.EscalationLive`, `OcuTalon.Test.Watch.PagingLive` -- passes on a fresh stack. Split by `Class:Method` if over 150 s.
- (once) `... OCUTALON_RUN_TAG=e24s3i ci/iris.sh live production-restart` -- passes (split if needed; at most once locally).
- (once) `... OCUTALON_RUN_TAG=e24s3i ci/iris.sh build`, then (loop) `... ci/iris.sh live sign-in --part k/N` for the part holding `chat/page-card.spec.ts`, and `live sign-in-2 --part k/N` for O1. Choose N so each part ends inside about 150 s.
- (once) `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-storage.sh` -- pass.

**Mutations (Rule 19, planned; the implement stage records the observed red):**
- AC1: drop `TelegramOut` from the page branch → `TestNotifyPageTargets` (and `PageRoute` sendMessage count).
- AC2: send to `email.address` instead of the role key → `PageRoute` To assertion. Remove the claim → the "one email per page" case.
- AC3: submit `GotIt` instead of `AckPage` → `GotItApi` page press (row not acknowledged). Remove `page` from the card's Got it condition → `page-card.spec.ts`.
- AC4: drop the origin check → the `Escalation` non-system case. Publish the reminder event → the no-live-event case.
- AC5: send a Notification instead of `Msg.Escalation` in `Wake` → `EscalationLive` (no backup row).
- AC6: skip `instance` rows in `Reconcile` → the restart phase.
- AC7: restore the 23.4 line → `ux-strings`/`on-call-view`/O1.
- AC8: put the role address in the EmailOut warning → the `PageRoute` log check.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
