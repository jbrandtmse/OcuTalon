---
title: 'Story 24.3a: Deliver pages on the on-call channels and take the web acknowledgement'
type: 'feature'
created: '2026-11-15'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-4-decide-when-to-page-the-on-call-person-and-when-to-escalate.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 23.4 pages the on-call person, but a page still takes Notify's generic route. It reaches only a paired Telegram chat, the web chat keeps a bare row with no card, `EmailOut` refuses every kind but `digest`, and the web Got it route accepts tell-now notices only. So an email-only person is never paged, and nobody can acknowledge a page on the web.

**Approach:** Lane B builds the delivery half of AD-14's page contract, on the Contest Planner's P1 Option A and P2 rulings:
- a `page` route in `Notify`;
- `EmailOut`'s fourth path, the page email;
- the web chat page card, whose Got it submits `AckPage` through the existing got-it route;
- the undelivered report: a `not_paired` Delivery row written by Lane A's `TelegramOut`, about 5 lines.

The escalation timer, the On call line, DW-1384 and the GUIDE bullet are Story 24.3b's.

## Boundaries & Constraints

**Always:**
- **Routing (P1 Option A).** A page is routed by its `Data.Page` row, the one the Notification's `DecisionRef` names:
  - A user's page (its `SessionRef` names a session) always gets a web chat card in that session. The card is not counted as a channel.
  - Telegram and email follow the row's `Channels` exactly, with no fallback either way.
  - `TelegramOut` gets the page when `telegram` is chosen and Telegram is included. A session that is not paired at send time gets no message: `TelegramOut` writes one `not_paired` Delivery row instead, which the paging owner reads with `Ownership.DeliveryByRef(pageRef, "telegram", sessionRef)` (P2).
  - A person given only as an address (`SessionRef` `instance`) gets email only.
  - The simulated phone never gets a page.
  - Notify routes no `page` on the online demo, and no `handled` to `EmailOut`. An email copy is never marked handled.
- **Page email (V2).**
  - It goes only to the on-call key of the row's `Role` (`oncall.primary.email` or `oncall.backup.email`), which an admin set in Settings › On call, read from its row at send time. Never to an address from the Notification, an item, the model or a message.
  - It is sent from `email.address`.
  - Subject: `Catalog.Render("page.subject", {production}, "email")`. Body: `Watch.Paging.Text(n, "email")`, the approved page email keys, and nothing else. No item, message or Notification text goes in verbatim.
  - At most one email per page row, claimed by a `Delivery` row (channel `email`, kind `page`, `DecisionRef` = the page's Ref) under a lock, whatever the Notification's `SessionRef` is. Each email is tried once.
  - Trace, logs and audit carry Refs and counts only: never an address, subject or body.
  - It is refused on the online demo in both `Notify` (`PageWeb`, `PageEmail`) and `EmailOut` (checked first, before anything is read or written).
- **Got it (V3).** `POST /v1/decisions/:ref/got-it` accepts a page Ref only when the signed-in session holds its own web copy of the page (`Ownership.DeliveryByRef(ref, "web", session)` of kind `page`).
  - In every other case it answers exactly as for a missing Ref (404 `not_found`, the same body) before anything is submitted: another session's page, an unknown Ref, and any page Ref on the online demo.
  - An accepted press submits `AckPage` {Ref, SessionRef, Channel `web`} from `web_user` through `Commands.Submit` (AD-1). `Watch.Paging.Acknowledge` decides; the route never does.
- No on-call value, Telegram chat id or display name appears in any Ens message body or header that 24.3a writes, nor in any log line, audit entry, trace or payload (AD-19, NFR-11). The exceptions are the rendered channel text and its web/Telegram Delivery row (23.4 deviation 1).
- Text comes from the catalog and approved strings only (Public text). No storage change.

**Never:**
- Edit `Watch/**`, `Data/Page.cls`, `Msg/Catalog/**`, `Core/SessionOps.cls` or `Channel/Telegram/In.cls`. The only Lane A edit is the `Channel/Telegram/Out.cls` one named in V5.
- Add a route, verb, table, column, catalog key, production item or web dependency, or change any Settings text.
- Let a reply to a page email acknowledge anything (36.2 ruling V5; the approved texts say "Replying to this email doesn't count").
- Touch `Schedule/**`, `Data/Reminder.cls`, `Data/Purge.cls` or the On call line (24.3b).
- Send a page email with no page row, or more than once per row.
- Fall back from Telegram to email or the other way round.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| User, both channels, paired | page Notification (SessionRef S, DecisionRef P, row Channels `telegram,email`) | 1 web card (Delivery kind `page`, text `Paging.Text(n,"web")`, Got it); 1 Telegram `sendMessage` (23.4's, Got it); 1 email to the role key's address, subject `page.subject`, body `Paging.Text(n,"email")`, header `X-OcuTalon-Ref` | none |
| One channel | Channels `telegram`, or `email` | the card plus that channel only | none |
| Telegram chosen, unpaired | Channels `telegram`, S not paired | the card; no `sendMessage`; one Delivery row (S, telegram, kind page, DecisionRef P, FallbackReason `not_paired`, no text, no message id) | Target's existing count-only warning; no error status |
| Telegram not included | Channels `telegram`, `TelegramOn()` 0 | the card only; no Telegram row | none |
| Address only | SessionRef `instance`, Channels `email` | email only; no card, no Telegram | none |
| Email cannot go | `email` chosen, role key empty or not an address (`no_address`), or `email.address` not an address (`no_mailbox`) | no email; the claim row for P marked with that FallbackReason | one count-only warning |
| Same page again | the same page delivered to EmailOut twice, or with another SessionRef | no second email, no second row | none |
| No page row / not chosen | DecisionRef names no `Data.Page`, or `email` not in Channels | Notify routes nothing to EmailOut; EmailOut, if reached directly, sends nothing and writes nothing | one count-only warning |
| Online demo | `onlineDemo` 1, with a page row and every key set | Notify routes the page nowhere; EmailOut reached directly writes no row and sends nothing; got-it on a page Ref is 404 with nothing submitted | refusal by code |
| Web Got it | POST `/v1/decisions/P/got-it` from S (body `{}`) | `AckPage` {P, S, web} from `web_user`; 200 `{"result":"done","handledAt": Page.Marked(P)}`; the card and the Telegram copy show "Marked as handled at {time}"; no email | none |
| Second press | P already acknowledged, from any channel | 200, the same handledAt; nothing changes | none |
| Not own copy | another session's P, an unknown Ref, a Ref that is neither the session's tell-now Decision nor its own page copy | 404 `not_found`, byte-identical to the unknown-Ref answer; no `AckPage` submitted | none |
| Handled | `handled` Notification for P | the web card is republished with handledAt; Telegram edits its copy (23.4); EmailOut gets nothing | none |

</intent-contract>

## Code Map

All paths are under `src/ocutalon/cls/OcuTalon/` unless they start with a top-level folder. Line numbers are from `da7526b34`.

**Routing (Lane B)**
- `Core/Rule/Notify.cls`:
  - The `Notification` rule is first-match. Today `page` falls to the generic branches at the rule's end (`DemoOn`/`TelegramPaired`).
  - The rule `DigestEmail` is the pattern for the new rule `PageEmail`.
  - The class doc lists every branch.
- `Core/Rule/Functions.cls`:
  - `IsSession` 8 (0 for `instance`), `TelegramOn` 30.
  - `DigestEmail` 73 is the model for `PageEmail`: it reads `onlineDemo` with `Data.Setting.Get` and checks the alive job with `CommandsIn.ItemRunning("EmailOut")`.
  - Function names must be unique across function sets.
- `Test/Core/Routing.cls` evaluates rules on a shadow router:
  - `TestNotifyTargets` 224 enumerates the kinds (a shared surface);
  - `TestNotifyDigestEmail` 317 is the sibling;
  - `TestFunctions` 369; `TestRuleTargetsAreProductionItems` 432.

**Email (Lane B)**
- `Channel/Email/Out.cls`:
  - The class doc enumerates three paths; it gets the fourth.
  - `OnNotification` 289 calls `SendDigest` 301, whose kind check (303-306) warns for any other kind.
  - `SendDigest`/`SendDigestLocked` 301-364 are the sibling: online-demo check, `Fresh(email.address)`, `IsAddress`, render, `CheckValues` 487, lock, `Transmit` 277 with `REFHEADER`, `Delivery.Record`.
  - The claim pattern is `Claimed` 542 (approval or owner+key modes), with `CLAIMPENDING`/`CLAIMFAILED`.
- `Watch/Paging.cls` (read only):
  - `Text` 329 (channel `email` picks the Email key and refuses on the online demo);
  - `KEYSUBJECT`, `ONCALL`/`BACKUP`, `KEYPRIMARYEMAIL`/`KEYBACKUPEMAIL`, `KIND` (parameters, read them, never copy them);
  - `SessionOf` 130, `Acknowledge` 251, `Handled` 267.
- `Data/Page.cls` (read only): `RefIndexOpen`, `Role` (SQL `PageRole`), `Person`, `Channels`, `Marked` 68.
- `Data/Delivery.cls`: `Record` 69; `FindByRef` 176 returns only the message id, so the `not_paired` report is read with `Ownership.DeliveryByRef`.
- Tests: `Test/Channel/EmailLive.cls` (running production, the CI SMTP mock `ci/mock/smtp.mjs`, `OCUTALON_TEST_PLAIN_SMTP` with host `mock`; `TestDigestReachesTheStub` 1119 and `TestNotifyRoutesDigestToEmailOut` 1205 are the patterns); `Test/Channel/EmailOut.cls` (onlineDemo save and restore 89/109).

**Web card and Got it (Lane B)**
- `Channel/WebChat/Out.cls`:
  - `CARDKINDS` 51 has no `page`, so 82-83 record a bare row.
  - The render branches at 85-92 (`summary` → `Watch.Summary.Text`) are the pattern.
  - `OnHandled` 102-110 republishes `tellnow` cards only.
- `Live/Payload/Notification.cls` `FromRow`:
  - `handledAt` is set for `tellnow` only (`Handled.Marked`).
  - The text/whyNow split by the last line applies to `tellnow` only.
- `Web/Api.cls`:
  - route 278; route doc 33-34;
  - `GotIt` 890-922 (tell-now Decision only, else 404 before submit), `GotItChannel` 925.
  - The verb switch to copy in spirit is `Channel/Telegram/In.cls:442` (AckPage chosen by the Delivery row's Kind).
- `Data/Ownership.cls`: `DeliveryByRef` (owner-exact, Ref-exact), `SessionRef`, `Decision`.
- `Core/CommandsIn.cls:383`: `AckPage` is owned by `IncidentManager`, from `web_user,web_admin,telegram`.
- Web:
  - `web/src/app/chat/chat-view.ts`: `NoticeKind` 158; `noticeOf` 240-275 (the 247 filter drops `page`; the `strip` at 272).
  - `web/src/app/chat/notice-card.ts`: Got it at 76 for `tellnow` only; the icon at 211; the class bindings at 48.
  - `got-it.ts`, `api-client.ts` and the web catalog's `handled.marked` stay unchanged.
- Tests:
  - `Test/Web/GotItApi.cls` (real HTTP: `TestPressUpdatesEveryCopy` 83, `TestOtherSessionIs404` 169, `TestDigestDecisionIs404` 192);
  - `Test/Core/WebChatOut.cls` (pins the card kinds, `TestTellNowCard` 83);
  - `web/scripts/chat-view.test.mjs`, `chat-announcements.test.mjs`;
  - `web/e2e/chat/notice.spec.ts` with `web/e2e/support/iris.ts` (`irisScript` 108, `seedIncident` 1145, `sendNotification` 684, `cleanFixtureRows` 735, `fixtureUser`).

**Telegram (Lane A; V5)**
- `Channel/Telegram/Out.cls`:
  - `OnNotification` 201; at 206-207 `Target` gives `chatId` "" for an unpaired session (it logs `LOGNOCHAT`, count-only) and the method returns OK.
  - `KINDS` 112 and `GOTITKINDS` 126 already include `page`.
  - `EditHandled` 365 falls back to `Page.Marked`.
- Test fixtures (read only): `Test/Channel/TelegramPageFixture.cls` (`Start` 76), `Test/Channel/LiveCase.cls`.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure first; record under Design Notes › Measured, and label anything unmeasured "(inference)"). On a lane-D throwaway, measure:
  - (a) that a page Notification sent to Notify with `email` chosen reaches the SMTP mock through an enabled EmailOut, and the mail's headers;
  - (b) that `Commands.Submit` of `AckPage` from `web_user` answers synchronously with IncidentManager's result.
- [ ] `Core/Rule/Functions.cls` -- add three pure reads (AD-14). Each is 0 on any error and on the online demo, and reads the row by object access:
  - `PageWeb(decisionRef, sessionRef)`: 1 when the `Data.Page` row of the Ref exists (Ref exact) and `IsSession(sessionRef)`;
  - `PageChannel(decisionRef, channel)`: 1 when that row exists and its `Channels` names the channel;
  - `PageEmail(decisionRef)`: `PageChannel(…,"email")` and EmailOut has an alive job (as `DigestEmail`).
- [ ] `Core/Rule/Notify.cls` -- AD-14 as amended:
  - In the `Notification` rule, after the digest branches and before the generic ones:
    - `Kind="page" && 'PageWeb(DecisionRef,SessionRef)` → no target;
    - `Kind="page" && TelegramOn() && PageChannel(DecisionRef,"telegram")` → `WebChatOut,TelegramOut`;
    - `Kind="page"` → `WebChatOut`.
  - New rule `PageEmail`: `Kind="page" && PageEmail(DecisionRef)` → `EmailOut`.
  - Update the class doc.
- [ ] `Channel/Email/Out.cls` -- AD-14's fourth send:
  - `OnNotification` dispatches `digest` → `SendDigest` and `page` → a new `SendPage`; any other kind gives one warning. Move the kind check out of `SendDigest`.
  - `SendPage` steps, in order:
    - the online demo: return before anything is read or written;
    - open the page row by `DecisionRef`. If it is absent, its Ref differs, or `email` is not in `Channels`: one warning, nothing written;
    - under `Lock +^OcuTalon.EmailOut.Page(ref):CLAIMWAIT`, an existing email row of kind page with this DecisionRef means nothing more is done. Extend `Claimed` with a DecisionRef mode; do not copy it;
    - otherwise write the claim row: owner = the Notification's SessionRef, or `instance`; channel email; kind page; the DecisionRef; a new Ref as ChannelMessageId; FallbackReason `pending`;
    - the to-address is `Fresh` of the role's key. Not an address: mark the row `no_address`, one warning, stop. The from-address is `Fresh(email.address)`. Not an address: mark the row `no_mailbox`, one warning, stop;
    - subject `page.subject` with the Slots' `production`; body `Paging.Text(request,"email")`; `CheckValues`. A failure marks the row `failed` with one warning;
    - one `Transmit` with the claim's Ref. Success clears the mark, with one info line "sent one page email". Failure marks the row `failed`, with one warning by `Sender.Classify`.
  - No daily cap. Update the class doc (four paths).
- [ ] `Channel/WebChat/Out.cls`:
  - `page` joins `CARDKINDS`; its text is `Watch.Paging.Text(request, ..#TEXTCHANNEL, .sc)`, beside `summary`.
  - `OnHandled` republishes a card of kind `tellnow` or `page`.
  - Update the class doc.
- [ ] `Live/Payload/Notification.cls` `FromRow` -- for a `page` row, `handledAt` is `Data.Page.Marked(DecisionRef)`, and its text is split into text and whyNow by the last line, as for `tellnow`.
- [ ] `Web/Api.cls` `GotIt` -- AD-1, AD-14, V3:
  - When the Ref is not the session's tell-now Decision:
    - unless it is the online demo, look up `Ownership.DeliveryByRef(ref,"web",session)`;
    - a row of kind `page` submits `AckPage` {Ref, SessionRef, Channel `web`} from `web_user`;
    - anything else stays the existing 404 before any submit.
  - For a page: Ok → 200 `{"result":"done","handledAt": Page.Marked(ref)}`; `not_found` → the same 404; anything else as today.
  - Update the route doc (33-34 and 890-897).
- [ ] `web/src/app/chat/chat-view.ts`, `notice-card.ts` -- `page` joins `NoticeKind` and `noticeOf`. A page card has:
  - the tell-now look and icon, and its whyNow line;
  - no decision strip;
  - Got it (channel web) until `handledAt`, then the `handled.marked` line.
- [ ] `Channel/Telegram/Out.cls` (V5, Lane A, about 5 lines) -- in `OnNotification`, when `Target` gives no chat for a kind `page` with a session SessionRef: record one Delivery row (SessionRef, `telegram`, no message id, no approval, kind `page`, no text, DecisionRef, no dueAt, FallbackReason `not_paired`) and return OK. This is the undelivered report (P2).
- [ ] Spine (the lead, Rule 20) -- apply the AD-14 amendment under Design Notes › Spine updates (V4), with memlog and lint_spine, and report its OLD and NEW text at merge. The implement stage does not edit the spine.
- [ ] Tests (each pinned under Verification):
  - `Test/Core/Routing.cls`:
    - new `TestNotifyPageTargets` covers every page row of the Matrix: online demo, `instance`, no row, Telegram on or off, paired or not, `handled` for a page → no EmailOut, and the rule `PageEmail` with no alive EmailOut;
    - `TestNotifyTargets` updated for `page`;
    - `TestFunctions` gains `PageWeb`, `PageChannel`, `PageEmail`.
  - `Test/Core/WebChatOut.cls` -- a page card (text, kind, Delivery row), and `OnHandled` republishing it.
  - `Test/Channel/PageRoute.cls` (NEW; running production, the CI Telegram and SMTP mocks, `TelegramPageFixture`/`EmailLive` set-up; one fixture `Data.Page` row and incident per method, removed after) -- Matrix rows 1-9 end to end, through Notify and EmailOut, with the V2 pins.
  - `Test/Web/GotItApi.cls` -- real HTTP, with the V3 pins:
    - a page press: 200 with handledAt; the row is acknowledged with channel web; the Telegram copy is edited (mock `editMessageText`); no mail;
    - a second press: 200, unchanged;
    - another session's page Ref: 404 byte-identical to an unknown Ref, and no `AckPage` header;
    - the online demo: 404, and no `AckPage` header.
  - `web/scripts/chat-view.test.mjs` -- the page notice view; `chat-announcements.test.mjs` only if it enumerates kinds.
  - `web/e2e/chat/page-card.spec.ts` (NEW, Rule 3; chromium project), with a new `seedPage(user, fields)` in `web/e2e/support/iris.ts`. `seedPage` makes an incident, a page row whose `Person` is the fixture user, and the page Notification through WebChatOut, and asserts that `Paging.SessionOf(user)` is the signed-in session. As the fixture user, the spec checks that:
    - the chat shows the page card with the page text and Got it;
    - pressing it shows "Marked as handled at {time}";
    - a reload keeps that line.

**Acceptance Criteria:**
- AC1 (routing, P1): Given a page with each `Channels` value, pairing state and Telegram inclusion, when Notify routes it, then exactly the targets of Matrix rows 1-5 receive it, with no fallback. An unpaired Telegram leaves one `not_paired` row that `Ownership.DeliveryByRef(P,"telegram",S)` returns (`Routing`, `PageRoute`).
- AC2 (page email, V2): Given `email` chosen and a mailbox, when the page is delivered, then the SMTP mock receives exactly one mail:
  - To: exactly the role key's address, never the row's `Person` or any address in the Notification;
  - Subject: the `page.subject` rendering;
  - body: exactly `Paging.Text(n,"email")`;
  - header: `X-OcuTalon-Ref` equal to the claim row's message id.
  A backup row mails `oncall.backup.email`. A second delivery, from any session, sends nothing (`PageRoute`).
- AC3 (online demo, V2): Given `onlineDemo` 1 with a page row and every key set, when the page is routed and when it is sent straight to EmailOut, then Notify gives no target, and EmailOut writes no Delivery row and sends no mail (`Routing`, `PageRoute`).
- AC4 (no identity, V2/NFR-11): Given distinctive fixture addresses, user name and chat id, when AC1-AC3 run, then none of them appears in any Ens message body or header of the test window, any `Ens.Util.Log` line or any audit entry. The subject and body are absent too. Positive control: the mock received them (`PageRoute`).
- AC5 (web Got it, V3; Integration, Rule 1): Given a user's page card, when the session that holds it presses Got it, then:
  - `IncidentManager` records the acknowledgement once, with channel web;
  - the web card and the Telegram copy show "Marked as handled at {time}", and no second mail goes;
  - a second press changes nothing;
  - another session's press, and any press on the online demo, answers byte-identically to an unknown Ref with no `AckPage` submitted (`GotItApi`, `page-card.spec.ts`).
- AC6: Given a page card, when the chat loads, is pressed and is reloaded, then it shows the page text, Got it, and then the handled line (`chat-view.test.mjs`, `page-card.spec.ts`).

## Spec Change Log

- 2026-11-16 (lead). **24.3a Q1 and Q2 rulings, Contest Planner ~12:30Z Nov 16 (BINDING)**, quoted in full:

  > ## 24.3a Q1 and Q2 (Contest Planner, ~12:30Z Nov 16). BINDING.
  > 
  > ### Q1, the page email: ACCEPTED
  > Use the approved catalog texts as they are, with no link. Conditions:
  > - **Cause:** the diagnosed cause in the email is EXACTLY the sentence shown on the web card and in Telegram, after Bridge.Redact.Text and the same length cap. It is never raw item or message text.
  > - **Name:** the on-call or backup person's name exactly as an admin set it in Settings.
  > - **Pin it:** no item or message text reaches the email body. Add a mutation.
  > 
  > ### Q2: hold 24.3a until 24.3b is green
  > - 24.3a's merge is HELD until 24.3b is green.
  > - The two merge back to back, with no release cut between them.
  > - DW-1400's On call line stays true until then.

  Applied: the email body uses the approved `page.*Email*` texts with no link; its cause slot is exactly the card and Telegram cause sentence after `OcuTalon.Bridge.Redact.Text` and the same length cap; its name slot is the Settings name as set; a mutation pins that no item or message text reaches the body. Q2 needs nothing in this story: the lead pushes 24.3a when ready and goes straight on to 24.3b; the merge is held until 24.3b is green. Lane B's 23.15 changes `chat-view`/`notice-card` (the partner card and the may-have-sent lines): union at integrate.

- 2026-11-16 (lead). **24.3 gate rulings, Contest Planner ~08:30Z Nov 16 (BINDING)**, quoted in full:

  > ## 24.3: NOT in 1.0.12
  > Merge 24.3a only AFTER the 1.0.12 cut. The gate is approved as follows.
  > 
  > ### P5: the split is APPROVED
  > - 24.3a: delivery and the web acknowledgement.
  > - 24.3b: the escalation timer, the On call line, DW-1384 and the GUIDE bullet.
  > - The On call line ships with 24.3b. Until then, DW-1400's line stands.
  > 
  > ### P1: Option A is APPROVED
  > - A page always gets a web chat card, and that card is not counted as a channel.
  > - Telegram and email follow the person's chosen channels exactly, with no fallback.
  > - A person given only as an address gets email only.
  > - An email copy is never marked handled.
  > 
  > Option B is refused.
  > 
  > ### P2: APPROVED
  > A not_paired delivery row that Paging reads.
  > 
  > ### P4: the GUIDE bullet is APPROVED as written
  > - No More-to-try item.
  > - Use the Settings separator GUIDE already uses elsewhere (› or >). Do not introduce a new one.
  > 
  > ### New text 1, the On call line: APPROVED verbatim (Option A version)
  > Keep its pins in ux-strings, on-call-view and O1.
  > 
  > ### Vetoes V1 to V6: APPROVED, with conditions
  > Pin each condition with a mutation.
  > 
  > - (a) V2, page email:
  >   - It goes ONLY to an address an admin set in Settings › On call. Never take an address from an item, the model or a message.
  >   - The body is built only from the fixed page keys: production, failure count, time and the OcuTalon link. No untrusted item or message text goes in verbatim.
  >   - At most one email per page row, and at most one escalation to the backup per page.
  >   - Trace, logs and audit carry ids only.
  >   - It is refused on the online demo in BOTH Notify and EmailOut.
  > - (b) V3, got-it:
  >   - It accepts only the session's OWN page copy.
  >   - Another user's page ref answers 404, exactly like a missing ref, so nothing reveals that it exists.
  >   - It answers 404 on the online demo.
  > - (c) V1, escalation timers:
  >   - They survive a restart and are re-armed exactly once, so a restart never pages twice.
  >   - The Data.Purge part removes only finished escalation rows, and purging the data removes them with it.
  >   - Nothing is written on the online demo.
  > - (d) V4: at merge, send the AD-14, AD-18 and AD-27 amendments as old text and new text.
  > - (e) V5 and V6: the orchestrator coordinates the Lane A and Lane B file overlaps.
  > 
  > ## Lane D order
  > 1. DW-1426 (small; can make 1.0.12).
  > 2. 24.3a: push it, but it merges after the cut.
  > 3. 24.3b.
  > 
  > Any 1.0.12 cut item that is still open comes first.

  Applied by the lead: `epics.md` replaces Story 24.3 with a split note and charters **24.3a** (this spec, renamed from `spec-24-3-...`; delivery and the web acknowledgement; merges after the 1.0.12 cut) and **24.3b** (the escalation timer, the On call line, DW-1384 and the GUIDE bullet). Status reset to `draft` for a re-plan narrowed to 24.3a with the V1-V3 conditions pinned.

- 2026-11-16 (plan stage, re-plan). **The intent was amended to 24.3a's scope.**
  - Removed from the intent: the escalation timer (Part B), the On call line and the GUIDE bullet, the V1 storage and purge, the restart phase and DW-1384. Each is listed under Design Notes › Moved to Story 24.3b.
  - Kept: delivery per P1 Option A and P2, the page email (now carrying the V2 conditions), and the web Got it (now carrying the V3 conditions).
  - Changed from the 24.3 plan:
    - Notify routes no page on the online demo (`PageWeb`), so V2's "refused in BOTH Notify and EmailOut" is literal;
    - EmailOut claims before it renders, so its own demo refusal is observable (no claim row);
    - a page press is always channel web;
    - the `not_paired` report is read with `Ownership.DeliveryByRef`, because `Delivery.FindByRef` returns only a message id.
  - The 24.3 plan is kept at the scratch path `e24s3plan/spec-24-3-parent.md` and in git history (`da7526b34`).
  - KEEP for any re-derivation: the Never list's Lane A boundary, the claim-before-render order, and the byte-identical 404.

## Review Triage Log

## Design Notes

### Rulings applied (P1, P2, V2, V3)
- P1 Option A: the Notify branches and the AD-14 amendment below. The email copy is never marked handled: Notify sends no `handled` to EmailOut, and EmailOut has no handled path.
- 24.3a's "every copy shows Marked as handled" is read under P1 as every copy that can be edited: the web card and the Telegram copy.
- 24.3a's example "a reply to the page email" is not built. 36.2's ruling V5 and the approved texts ("Replying to this email doesn't count") exclude it.
- P2: the row is written by TelegramOut. The paging owner reads it with `Ownership.DeliveryByRef`. Showing it, on the incident card for example, is not in this story.

### Decided in-stage
1. **V2's body condition is read as the approved page email keys.** The 24.3a acceptance criterion says the text is "rendered by the `*Out` operation from the catalog key the author accepted from Story 36.1's proposal".
   - Those keys (`page.onCallEmail`, `page.onCallEmailAlone`, `page.backupEmail`; Planner-approved 2026-11-12 and 2026-11-15) hold the production, the failure count and item noun, the time, the cause, the escalation minutes, the backup's or person's name, and "press Got it on your OcuTalon page". They hold no URL.
   - So the body is exactly `Paging.Text(n,"email")`, and no link is added: a link would be new public text.
   - `{cause}` is the diagnosed cause, a model-written sentence cleaned by the catalog's `sentence` rules, or the setting-change cause. It is the same sentence that the web card and the Telegram copy carry. No item or message text is ever a slot. (Flagged to the orchestrator as new beyond the rulings.)
2. The claim is per page row (DecisionRef, channel email, kind page), not per session, so a page goes once whatever the Notification's SessionRef is.
3. An email that cannot go (`no_address`, `no_mailbox`, `failed`) keeps its claim row and is never retried (one try, as the digest). The row is the undelivered report for email.
4. Page emails have no daily cap: at most one per page row, and at most two pages per incident.
5. A page press on the web is always channel `web`. No page copy exists on the simulated phone.
6. With Telegram not included, a Telegram choice routes nowhere and leaves no row (the same as 24.3's decision 7).
7. A page card uses the tell-now card's look, icon, whyNow line and Got it, with no strip and no new web text.
8. An address-only person can only have `email`: `SettingsOps` refuses `telegram` for an address (Telegram is reachable only for a user with a paired session). So "email only" and "Channels exactly" agree.

### Moved to Story 24.3b
- `Schedule/ReminderOps.cls` -- Moved to Story 24.3b: the escalation `Set`/`Cancel` (it answers `not_built` until then).
- `Schedule/Reminder.cls` (`ReminderTimer`'s `Wake`/`StartFrom`) -- Moved to Story 24.3b: the waiter that sends `Msg.Escalation`.
- The reconciler re-arm of `instance` escalation rows -- Moved to Story 24.3b.
- V1's `Data.Reminder` columns (`Kind`, `IncidentRef`, `PageRef`) -- Moved to Story 24.3b.
- V1's `Data.Purge` part (finished `instance` rows) -- Moved to Story 24.3b.
- V1's conditions -- Moved to Story 24.3b: re-armed exactly once, so a restart never pages twice; the purge removes only finished escalation rows; nothing is written on the demo; at most one escalation to the backup per page.
- The On call line (new text 1, approved verbatim, Option A) and its pins in `ux-strings`, `on-call-view` and O1 -- Moved to Story 24.3b.
- DW-1384 (`Test/Watch/PagingLive.cls` `TestEscalationAsk`) -- Moved to Story 24.3b.
- The GUIDE.md On-call pages bullet (P4) -- Moved to Story 24.3b.
- The `live:production-restart` phase -- Moved to Story 24.3b.
- The AD-18 and AD-27 amendments (V4) -- Moved to Story 24.3b, with the timer they describe.

### Spine updates (V4; Rule 20; the lead applies them and reports OLD and NEW at merge)
AD-14, in `ARCHITECTURE-SPINE.md` under Rule › Outbound routing.

**OLD (1), verbatim:**
> - **The `page` kind (step 5)** [ADDED 2026-11-12, Story 36.2, Contest Planner rulings V1-V7]. From Story 24.3, kind `page` goes only to the paged person's chosen channels:
>   - the web chat of that user's session;
>   - the paired Telegram chat of that session (`telegram` chosen and paired at send time; `TelegramOut`'s delivery is Story 23.4);
>   - `EmailOut` (`email` chosen).
> - A person with no paired chat, or one given only as an address, gets email only. Until Story 24.3, a `page` takes the generic route and `Notify` is unchanged.

**NEW (1):**
> - **The `page` kind (step 5)** [ADDED 2026-11-12, Story 36.2, Contest Planner rulings V1-V7] [AMENDED 2026-11-16, Story 24.3a, Contest Planner 24.3 rulings P1 (Option A) and P2, DW-1251]. Notify routes kind `page` by its `Data.Page` row (the Notification's `DecisionRef`), and routes none on the online demo (`Functions.PageWeb`, `PageChannel`, `PageEmail`):
>   - a user's page (its `SessionRef` a session, `Watch.Paging.SessionOf`'s) always gets a web chat card in that session; the card is not counted as a channel;
>   - `TelegramOut` when `telegram` is in the row's `Channels` and Telegram is included. A session not paired at send time gets no message; `TelegramOut` records one `Delivery` row (channel `telegram`, kind `page`, the page's Ref, FallbackReason `not_paired`, no text), the undelivered report the paging owner reads with `Ownership.DeliveryByRef(pageRef, "telegram", sessionRef)`;
>   - `EmailOut` (rule `PageEmail`) when `email` is in `Channels` and `EmailOut` has an alive job.
> - Telegram and email follow `Channels` exactly, with no fallback from one to the other. A person given only as an address (`SessionRef` `instance`) gets email only. The simulated phone never gets a page.

**OLD (2), verbatim:**
> - On acknowledgement, the paging owner sends one `handled` Notification (`DecisionRef` = the page's `Ref`) per session holding a copy, and each `*Out` updates its copy to `handled.marked`.

**NEW (2):**
> - On acknowledgement, the paging owner sends one `handled` Notification (`DecisionRef` = the page's `Ref`) per session holding a copy. The web chat card and the Telegram copy show `handled.marked`. An email copy is never changed, and Notify sends `EmailOut` no `handled` [AMENDED 2026-11-16, Story 24.3a, P1].

**OLD (3), verbatim (end of the fourth-send bullet):**
> The email carries no acknowledgement. Story 36.2 sends nothing.

**NEW (3):**
> The email carries no acknowledgement. Story 36.2 sends nothing. As built in Story 24.3a [AMENDED 2026-11-16, Contest Planner 24.3 ruling V2]:
> - the subject is `page.subject` and the body is exactly `Watch.Paging.Text(n, "email")`, the approved page email keys;
> - the online demo is checked before anything is read or written;
> - the claim is the page's Ref (`DecisionRef`, kind `page`), whatever the session, under a lock, and is written before the render. A send that cannot go keeps its claim, marked `no_address`, `no_mailbox` or `failed`, and is never retried;
> - there is no daily cap;
> - logs carry counts and outcomes only.

**OLD (4), verbatim (the end of the Got it bullet's 18.4 sentence):**
> the web chat's and the Simulated phone's **Got it** submit `GotIt` through `POST /api/v1/decisions/:ref/got-it` (origin `web_user`, 404 unless the Decision is the session's own tell-now one);

**NEW (4):**
> the web chat's and the Simulated phone's **Got it** submit `GotIt` through `POST /api/v1/decisions/:ref/got-it` (origin `web_user`, 404 unless the Decision is the session's own tell-now one). As built in Story 24.3a, the route also takes the session's own web copy of a page (`Ownership.DeliveryByRef(ref, "web", session)` of kind `page`) and submits `AckPage` (channel `web`) instead. Any other page Ref, and every page Ref on the online demo, answers 404 exactly as a missing Ref does, before anything is submitted [AMENDED 2026-11-16, Story 24.3a, Contest Planner 24.3 ruling V3];

Memlog: `AD-14 amended (24.3a, P1/P2/V2/V3): page route by the Page row, web card always, channels exactly, no fallback, not_paired report, page email claim/body, got-it accepts own page copy; prevents email-only users having no Got it and a page reaching a channel nobody chose`.

### Governing ADs (Rule 6)
- AD-1: `AckPage` through Submit.
- AD-4: session-scoped copies.
- AD-5: rows are the truth; the Delivery report.
- AD-13: object-access reads.
- AD-14: the route, EmailOut's fourth send, Got it, no chat id.
- AD-15: the paging rules.
- AD-17: no identity in the audit.
- AD-19: the on-call keys, read at send time.
- AD-22: mocks and throwaways.
- AD-25: the online demo.
- AD-29 and AD-33: lanes, one writer.
- AD-32: catalog only.

### Integration ACs (Rule 1) and linkage (Rule 2)
- **Integration:**
  - AC5: the real `IncidentManager` consumes the web route's `AckPage` and sends `handled`, which WebChatOut and TelegramOut consume.
  - AC1/AC2: WebChatOut, TelegramOut, EmailOut and the SMTP mock consume Notify's route.
  - The `not_paired` row has no consumer code in this story. Its reader is `Ownership.DeliveryByRef`, pinned in `PageRoute`. Its first display is not chartered (P2: display is out of scope).
- **Consumes:** 23.4's `Watch.Paging` (`Text`, `Acknowledge`, `SessionOf`, `Handled`), `Data.Page`, and IncidentManager's AckPage handling; 36.2's `AckPage`; 21.6/21.7's EmailOut claim and transmit; 18.4's got-it route and card.
- **Consumed-by:**
  - 24.3b: the escalation is cancelled by any acknowledgement, the web one included, and its On call line describes this route.
  - 24.4a/b: the cards (the `page` payload, unchanged).

### Extend, don't copy (Rule 2)
- `SendPage` extends the digest path's steps and `Claimed`, which gains a DecisionRef mode.
- `PageEmail` mirrors `DigestEmail`.
- The page card reuses the tell-now card and `got-it.ts`.
- The route's verb switch follows `TelegramIn`'s.
- The tests reuse `EmailLive`, `TelegramPageFixture`, `LiveCase` and `e2e/support/iris.ts`.

### Ledger (Rule 17; `LEDGER slice 24-3a-deliver-pages-on-the-on-call-channels-and-take-the-web-ackno`)
- DW-1251 (the only entry): addressed. P1 Option A settles the reading; the AD-14 amendment above (OLD/NEW 1 and 2) writes it, and AC1 pins it.

### Files (V5/V6; the orchestrator coordinates overlaps)
- **Lane A** (cross-lane, V5): `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` only.
- **Lane B, source:**
  - `Core/Rule/Functions.cls`, `Core/Rule/Notify.cls`;
  - `Channel/Email/Out.cls`, `Channel/WebChat/Out.cls`;
  - `Live/Payload/Notification.cls`, `Web/Api.cls`;
  - `web/src/app/chat/chat-view.ts`, `web/src/app/chat/notice-card.ts`.
- **Lane B, tests:**
  - `Test/Core/Routing.cls`, `Test/Core/WebChatOut.cls`;
  - `Test/Channel/PageRoute.cls` (NEW);
  - `Test/Web/GotItApi.cls`;
  - `web/scripts/chat-view.test.mjs` (and `chat-announcements.test.mjs` if it enumerates kinds);
  - `web/e2e/chat/page-card.spec.ts` (NEW), `web/e2e/support/iris.ts`.
- **Spine:** `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` and `.memlog.md` (the lead).
- Outside epic-24's `paths_hint` (footprint extensions to report): `Core/Rule/Functions.cls`, `Channel/Email/Out.cls`, `Channel/WebChat/Out.cls`, `Live/Payload/Notification.cls`, `web/src/app/chat/{chat-view,notice-card}.ts`, `web/scripts/chat-view.test.mjs` (and `chat-announcements.test.mjs`), plus the Lane A `Channel/Telegram/Out.cls`. `web/src/app/chat/**` is also in epic-25's `paths_hint`.

### CI
- No new unit. `Test.Channel.PageRoute` joins `Test.Channel`'s shard.
- `page-card.spec.ts` runs in the chromium project (`live:sign-in`).

## Public text
No new text. Used unchanged:
- `page.onCall`, `page.onCallAlone`, `page.backup` (web and Telegram);
- `page.onCallEmail`, `page.onCallEmailAlone`, `page.backupEmail`, `page.subject` (email);
- `page.causeUnknown`;
- `button.gotIt`;
- `handled.marked`;
- the got-it 404 `MESSAGENOTFOUND`.

Each was approved at the 36.1 gate (2026-11-12) or by the 23.4 Planner ruling (2026-11-15). The Settings On call line is unchanged; DW-1400's line stands until 24.3b (P5).

## Veto items
All were approved at the 24.3 gate with the conditions pinned below.
- **V2. Outward action: page emails**, through EmailOut, under the conditions (a). Tests reach only the CI SMTP mock.
- **V3. Changed route:** got-it also takes the session's own page copy, under the conditions (b). No new route or grant.
- **V4. AD-14 amendment:** OLD/NEW above.
- **V5. Cross-lane edit:** the `not_paired` row in `Channel/Telegram/Out.cls`, about 5 lines.
- **V6. Footprint extensions:** the Lane B files above.
- None: a new verb, table, column, catalog key, production item, privilege, web dependency or stored-data change.

## Verification

Every `ci/iris.sh`/`ci/warm.sh` call runs from the worktree root with:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'
```

- The warm tag is `e24s3aiw` and the fresh tag is `e24s3ai`. IRIS MCP calls go to `ocutalon-slot-d`/`OCUTALON` only.
- Each line is one foreground call (`timeout: 600000`) that ends inside about 150 s. Run one class, or one `Class:Method`, per call, and never two test calls in one message.
- After a `web/` change, run `ci/iris.sh build` before a browser part.

**Shared surfaces:**
- Notify's targets for every kind: `Test.Core.Routing` (`TestNotifyTargets`, `TestFunctions`, `TestRuleTargetsAreProductionItems`) and `Test.Core.RoutingProduction`.
- WebChatOut's card kinds (`Test.Core.WebChatOut`) and the chat's notice kinds (`chat-view.test.mjs`, `chat-announcements.test.mjs`, `web/e2e/chat/notice.spec.ts`).
- The got-it route: `Test.Web.GotItApi` (`TestDigestDecisionIs404` and `TestOtherSessionIs404` stay 404).
- EmailOut's paths: `Test.Channel.EmailOut` and `EmailLive`. The digest kind check moves to `OnNotification`.
- Readers of telegram Delivery rows: grep for `"telegram"` with `Delivery`/`DeliveryByRef`, so that a `not_paired` row, which has no message id, breaks none of them.
- The mock call logs: the Telegram chat ids and the SMTP mailboxes this story uses are its own.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `npm --prefix web test` -- passes.
- (once) `npm --prefix web run lint` and `npm --prefix web run build` -- pass, with no budget error.
- (once) `… OCUTALON_RUN_TAG=e24s3aiw ci/warm.sh up` -- ready.
- (loop) `… OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s3aiw ci/iris.sh class <Class>`, one call each:
  - `OcuTalon.Test.Core.Routing`, `OcuTalon.Test.Core.WebChatOut`;
  - `OcuTalon.Test.Channel.PageRoute`, `OcuTalon.Test.Channel.EmailOut`;
  - `OcuTalon.Test.Web.GotItApi`.
  - Each gives `CLASS … passed`.
- (once) `… OCUTALON_RUN_TAG=e24s3aiw ci/warm.sh down`.
- (once, each its own call) `… OCUTALON_RUN_TAG=e24s3ai ci/iris.sh class OcuTalon.Test.Channel.PageRoute`, then `OcuTalon.Test.Channel.EmailLive` and `OcuTalon.Test.Web.GotItApi` -- pass on a fresh stack. Split by `Class:Method` if a call nears 150 s.
- (once) `… OCUTALON_RUN_TAG=e24s3ai ci/iris.sh build`. Then (loop) `… ci/iris.sh live sign-in --project chromium --part k/N` for the part holding `chat/page-card.spec.ts` and `chat/notice.spec.ts` (`web/scripts/e2e-part.mjs` lists the parts). Choose N so each part ends inside about 150 s.
- (once) `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-ci-config.sh` -- pass.

**Mutations (Rule 19; one per AC and per ruled condition; the implement stage records each observed red):**
- AC1 (P1, channels exactly): route a paired session's page to TelegramOut by `TelegramPaired` instead of `PageChannel` → `TestNotifyPageTargets` (the email-only, paired case).
- AC1 (P2): drop the `not_paired` Record in TelegramOut → `PageRoute` (no row from `DeliveryByRef`).
- AC2 / V2 (only the admin-set address): send to the page row's `Person` instead of the role key → `PageRoute` To assertion (the row's Person is a distinctive other address).
- V2 (the backup's key): always read `oncall.primary.email` → `PageRoute` backup case.
- V2 (body from the fixed page keys only): append the fixture incident's first item text (a distinctive marker) to the body → `PageRoute` body equality and item-marker absence check. The positive control is that the marker is in the incident's item.
- V2 (at most one per page row): remove the claim check → `PageRoute` "same page again" (two mails).
- V2 (refused in Notify on the online demo): drop the online-demo check from `PageEmail` → `TestNotifyPageTargets` demo case (EmailOut target). Drop it from `PageWeb` → the same case (WebChatOut target).
- V2 (refused in EmailOut on the online demo): remove `SendPage`'s demo check → `PageRoute` demo case (a claim row is written).
- AC4 / V2 (ids only): put the to-address in `SendPage`'s sent info line → `PageRoute` log check.
- AC5 (Integration): submit `GotIt` instead of `AckPage` for a page copy → `GotItApi` page press (the row is not acknowledged).
- V3 (own copy only): look the copy up as any owner's row of that Ref, not `DeliveryByRef(…, session)` → `GotItApi` other-session case (an `AckPage` header appears).
- V3 (byte-identical 404): answer 403 `forbidden` for another session's page → the same case (status and body compare).
- V3 (online demo): remove the route's demo check → `GotItApi` demo case (an `AckPage` header appears).
- AC6: remove `page` from the card's Got it condition → `page-card.spec.ts` (no Got it) and `chat-view.test.mjs`.
- P1 (email never marked handled): drop `Kind="page"` from the rule `PageEmail` → `TestNotifyPageTargets` `handled` case (EmailOut target).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
