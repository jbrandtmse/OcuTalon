---
title: 'Story 4.5: Get notifications on the simulated phone'
type: 'feature'
created: '2026-10-26'
status: 'done'
baseline_revision: 'd32e2e986649640457c02851a18170b3880a4e55'
baseline_commit: 'd32e2e986649640457c02851a18170b3880a4e55'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** In demo mode `Notify` already routes every notification to `SimPhoneOut` (except kind `allowance`), but the operation is a stub that answers "not implemented". The page also has no device column. A judge without Telegram sees no phone, and Story 2.7's 5-second check has no phone half.

**Approach:**
- **The server side.**
  - `SimPhoneOut` becomes a real channel. It renders the paired chat's catalog text for the card kinds, records a `SimMessage` row (with the new `Text` column) and its phone `Delivery` row, and publishes `phone`.
  - `/state` gains `phone`: the session's phone messages, in demo mode only.
- **The page.** A "Simulated devices" region sits right of the chat, with ARIA tabs and a skip link. The phone tab shows those messages, with the chat's "New messages" pattern. The mailbox tab is a header-only shell that Story 4.6 fills.

## Boundaries & Constraints

**Always:**
- **One renderer (AD-32).** The phone text is `Msg.Catalog.Render(CatalogKey, Slots, "phone")`, which gives exactly the `telegram` text: plain, with " ET" on the online demo. The page never renders or edits it.
- **Card kinds only.** Kinds `tellnow` and `reminder` get a `SimMessage`, a phone `Delivery` row and a `phone` event, in that order of writes. Both rows are saved in one transaction, and the event is published after the commit.
  - Any other kind records only its phone `Delivery` row (kind, approval and decision Refs; no message id, no text), and no event. This mirrors WebChatOut's non-card kinds, until Stories 6.3 and 6.4 add Approve and Reject (AD-32 Prevents: "notices on the phone or in Telegram without Approve and Reject").
- **Sessions only (AD-4).**
  - `SimPhoneOut` acts only when `Session.Recipients(SessionRef)` is exactly that Ref. Any other owner (`instance`, `eval`, a non-session) logs one warning, writes nothing and returns OK.
  - The owner check comes before rendering, because `test-demo-switch.sh`'s control Notification has an unrenderable `{}` slot set.
- **Writes.** `Data.Delivery` is written only through `Delivery.Record(...)` (contended, Epic 10).
- **Reads.** The snapshot reads `SimMessage` only through a new `Ownership` reader, with the caller's `SessionRef`.
- **The `phone` key.** `/state` carries `phone` only while `demoMode` is true: the newest 100 messages, oldest first, each a `Live.Payload.Phone`. It sits after `status` and before `guide`, so `guide` stays the last key.
- **The page decides nothing (AD-12).** The phone list is the snapshot's `phone` (in its order), then `store.phones` refs that are not in it, in arrival order. A ref present in both takes the store's payload.
  - The region shows only while `snapshot.demoMode` is true, even if a `phone` key is present.
  - `web/src/app/api/**` is not edited: `phone` is read through a phone-owned type `StateSnapshot & { phone?: PhonePayload[] }`, as `GuideSnapshot` does.
- **Exact texts.**
  - "Simulated devices", "Simulated phone", "Simulated mailbox", "Simulated", "OcuTalon", "Skip to simulated devices", "New messages", the badge name "{tab}, {n} new" (EXPERIENCE L296) and the empty phone text (EXPERIENCE L335, verbatim).
  - No other public text. Straight ASCII quotes and apostrophes.
- **Silent, no live region (EXPERIENCE L422, UX-DR132).** The phone and the devices region announce nothing (the chat card already announces the event once) and add no `aria-live`, live role or `aria-atomic`.
- **Focus.** Focus moves only on the user's own action (arrow keys, New messages, the skip link), or through `shared/focus-rule.ts` when an update removed the focused element.
- **Styling.**
  - Styles use DESIGN.md tokens only (`--simulated-*`, `--device-tab-*`, `--tab-badge-*`, `--phone-notification-*`, `--space-device-width[-wide]`, `--space-phone-screen-*`, `--rounded-*`).
  - Descriptive token strings (`--device-tab-indicator-selected`) are rebuilt from `--action` as a 3px bottom border.
- **Floor rules.** No `transition`, fixed heights, `sticky` or `IntersectionObserver`. Every scroller declares `scroll-padding: var(--space-scroll-gutter)`. Width media queries use only `LAYOUT_QUERIES`.

**Never:**
- No change to `Notify`, `Data.Delivery`, `docker/**`, `web/src/app/api/**`, `Test/Contract/Ac.cls`, `Test/Install/**` or `Test/Bridge/**`. Calling or reading them is fine.
- **Not in this story:**
  - Approve and Reject on the phone, in-place edits through `Delivery.FindByApproval`, and the incident, approval, answered and result kinds (Stories 6.3 and 6.4);
  - the mailbox's content: chips, form, rows, empty text and endpoints (Story 4.6);
  - the guide's Show me (Story 4.7, which uses `DeviceTabs.select`);
  - the Telegram card's move to the device column in the 1024-1279 band (Telegram epics);
  - `01-page`'s `notBuilt(..., '4.7')` part.
- No canned phone content: every message on the phone is a delivered `Notification`, or in a test a fixture event that the test names as such.

## I/O & Edge-Case Matrix

Conventions:
- T = `{whatHappened:"Disk almost full", reason:"you asked to hear about disk space"}` with key `notice.tellNow`, which renders "Disk almost full\nWhy now: you asked to hear about disk space".
- R = `reminder.due` with `{text:"stretch", dueAt}`, which renders "Reminder: stretch.".
- "Phone list" = the page's merged list.

| # | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| 1. Tell now | `Notification` kind `tellnow`, owner a session, demo on, via Notify | One `SimMessage` {Kind `phone`, Direction `out`, SessionRef, CreatedAt, Text = `Render(key,slots,"telegram")`}. One `Delivery` {Channel `phone`, ChannelMessageId = the SimMessage's Ref, Kind, ApprovalRef, DecisionRef, Text ""}. One `phone` event on the session stream, `{ref, direction:"out", text, createdAt}` | render error: the error status; no row, no event |
| 2. Reminder | R, and `reminder.late` with the online-demo flag on | Same as row 1. The late text ends its time with " ET" when `onlineDemo` is set, and has no suffix otherwise | none |
| 3. Other kind | kind `incident` with `ApprovalRef` | Only the phone `Delivery` row (kind and Refs). No `SimMessage`, no event | none |
| 4. Not a session | owner `instance`, `eval`, `zzswitch` | One warning logged; no rows, no event; OK | none |
| 5. Publish fails | publish refused (open transaction) | Both rows stay. A warning is logged; OK | none |
| 6. Snapshot | demo on; the session has phone rows; another session has some too | `/state.phone` = this session's newest 100, oldest first, `Phone` payloads. It is absent with demo off. Key order `...,telegram,status,phone,guide` | reader error: `..Check(sc)` throws, as the chat's readers do, so `/state` answers its existing 500 |
| 7. Region | demo on, any width of 1024 or more | Region "Simulated devices" right of the chat: 384px at 1440 and wider, 352px from 1024 to 1439. A tablist holds "Simulated phone" (selected by default, `aria-selected="true"`, tabindex 0) and "Simulated mailbox" (tabindex -1). Each tab controls its tabpanel, which is labelled by the tab. The skip links are "Skip to chat", "Skip to simulated devices", "Skip to status"; the middle one focuses the region | demo off: no region, no middle skip link, and main reaches the right edge |
| 8. Arrows | focus on a tab; ArrowRight or ArrowLeft | The other tab is focused and selected (automatic activation, wrapping); its panel shows. The choice is stored under `ocutalon.devices.tab` and restored after a reload | storage throws: works for the page's life, with no console error |
| 9. Badge | mailbox selected; 1 phone message arrives (live) | The mailbox stays selected. The phone tab shows the badge "1" and is named "Simulated phone, 1 new". Selecting it clears the badge. Two `mailbox` events with the phone selected give "Simulated mailbox, 2 new" | snapshot content and the first load: no badge |
| 10. Phone look | the phone tab | Frame in `--simulated-phone-frame` with `--rounded-xl` corners and the device shadow; screen on `surface`. The top bar reads exactly "OcuTalon" plus the amber outlined "Simulated" label, which is not focusable. No other top-bar text, no composer, no textbox | none |
| 11. Messages | phone list of 3 | Newest at the bottom. Each is a `sunken` notification whose text keeps its line breaks (Angular text binding, no HTML), with a caption time `pageTimeBeside(createdAt, instanceZone)` | empty list: "Notifications, reminders and approval requests appear here. The simulated phone is a real channel in the production; you'll see it in the trace." |
| 12. Follow | at the bottom (24px slack), no pending approval in the list; a message arrives | The feed scrolls the new message into view, with no New messages button | none |
| 13. Hold | scrolled up, or a message whose `approvalRef` names a `pending` approval in `store.approvals`; a message arrives | The feed does not move, and "New messages" (`chevron-down`) shows. Pressing it scrolls to the bottom and focuses the first new notification (`tabindex="-1"`) | none |
| 14. Stacked | width under 1024 | DOM and tab order: main, devices, rail. The phone is centred; the screen is at least `--space-phone-screen-min-height` and its feed scrolls | none |
| 15. Short | 1280x600 | The page does not scroll; the device panel scrolls on its own | none |
| 16. Five seconds | the live sign-in stack (demo on, mock); N10's untrusted item | Its tell-now text is on the phone within 5000 ms of the send, counted from before the send | none |
| 17. Real switch | the demo-switch stack, README; a fixture tell now and reminder through Notify | Mode 1: both texts on the phone (and as chat cards), still there after a reload, with SimMessage rows +2. Mode 0: both chat cards, no region, no `phone` key, SimMessage rows +0 | none |

</intent-contract>

## Code Map

**Server (Lane B):**
- `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls` -- the stub: `STUB = 1`, and `OnMessage` returns `NotImplemented`. Delete both.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- the sibling:
  - `:17-28` the parameters `CHANNEL`, `CARDKINDS`, `TEXTCHANNEL`, `LOGNOTASESSION`, `LOGPUBLISH`;
  - `:30-40` its MessageMap;
  - `:43-56` `OnNotification`;
  - `:67-73` `IsSession` (private) and `:76-84` `Announce`, the parts the new base takes.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls:42-47` -- already sends to `SimPhoneOut` when `DemoOn()`. Unchanged.
- `src/ocutalon/cls/OcuTalon/Production.cls:50` -- the `SimPhoneOut` item, enabled, pool 1. Unchanged.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls`:
  - `:101` only `web` picks a different text, so `phone` = `telegram`;
  - `:55` Render reads `Data.Public.Settings.Get("onlineDemo")`;
  - `:63-64` `RenderAt(key, slots, channel, now, onlineDemo, .sc)` for tests.

  The keys are in `Msg/Catalog/Core.cls`: `notice.tellNow` `:236`, `notice.tellNowFallback` `:244`, `reminder.due` `:252` and `reminder.late` `:259`.
- `src/ocutalon/cls/OcuTalon/Data/SimMessage.cls` -- Ref, SessionRef, Kind (`phone`|`mailbox`), Direction, ItemId and CreatedAt, with indexes Ref (unique), SessionRef and ItemId. Storage `:32-63`; `Text` is appended as Value 8 (V1).
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls:48` -- `Record(ownerRef, channel, channelMessageId, approvalRef, kind, text, decisionRef, dueAt, fallbackReason, .row)`. CONTENDED: call only. Its `Text` doc limits text to web cards, so the phone row passes "".
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `:5-29` the reader list in the header;
  - `:263-268` `RecentNotices`;
  - `:460-492` the `Rows` binds (`o` = owner, `a` = argument);
  - `:516-632` `Statement` (`:595-597` the `recentNotices` SQL). Add the `recentPhone` kind there.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Phone.cls` -- ref, direction, text, approvalRef, createdAt, all pinned. Add `FromRow(row As Data.SimMessage)`, modelled on `Live/Payload/Notification.cls:44-63`.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls:62` -- `Publish(stream, type, payload, .seq)`. It refuses inside a transaction. `TYPES` (`:15`) already has `phone:Phone`; `phone` is not in `GUIDETRIGGERS` (`:21`).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `StateBody` `:355`:
  - keys are added at `:367-391`;
  - `demoMode` `:377`;
  - `guide` `:391` (`If body.demoMode ...`), with `phone` going just before it;
  - `TraceLink.Add` `:393`.

**Server tests and fixtures:**
- `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls` -- the pattern to follow:
  - the shadow instance `Ens.Host.GetShadowInstance("class||...")` `:279-284`;
  - `Notification(...)` `:287-295`;
  - `Observe.Events(session, type)`, `DeliveryRows` and `Warnings` `:305-346`;
  - the publish failure inside `TSTART` `:253-266`;
  - onlineDemo set and restored `:36,:43`.
- `src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls` -- the production-path pattern (sends through the running items, waits on rows). `:189` asserts no header to SimPhoneOut for an eval item, which stays true.
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:22` -- the SimPhoneOut row `"stub": 1` → 0. `Test/Install/Production.cls:150,171` (contended, read-only) compares `STUB` with this oracle, and `test-production.sh:162-171` derives its stub list from it.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`:
  - `:315-341` `Clean` (for a Session: `DropStream`, `DropDeliveries`, `DropGuide`);
  - `:460-465` `DropDeliveries`.

  Nothing drops `SimMessage` rows yet.
- `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls:393-407` -- SimMessage's exact contract.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls:359,408` -- the kind lists (isolation; refused owners).
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`:
  - `:95-124` `TestStateBody` (exact keys `:124`, demo on);
  - `:163-187` `TestStateFlags` (`guide` present exactly when `demoMode`).
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls:768-777` -- pins Phone's props. Adding a method changes nothing.
- `ci/units.sh:17` -- lane-b holds `Contract Core Data Demo Live Msg Web`.
- `docker/tests/test-demo-switch.sh` (contended):
  - `:119-135` counts header existence only;
  - `:128` the control owner `zzswitch` with `Slots="{}"`;
  - `:156-168` runs `npm run e2e:demo-switch`, the whole `web/e2e/demo-switch/` folder, at mode 0 (61 s after the switch) and at mode 1.

**Page (Lane B):**
- `web/src/app/main-page/main-page.ts`:
  - `:65-121` `section.rail` and `main.main`;
  - `:124-128` the host is a flex row;
  - `:154-175` the drawer and stacked styles;
  - `:309-326` `place(stacked)`, which needs `:scope > .rail` and `.main` and only puts the rail before or after main.
- `web/src/app/header/skip-links.ts:15-18` -- `SKIP_LINKS` (two entries, rendered by `@for`). `:64-67` `skip` → `Layout.focusRegion(target)` (`shared/layout.ts:62`), a no-op without the region.
- `web/src/app/shared/layout-view.ts:15-24` -- `LAYOUT_QUERIES` stacked `(width < 1024px)`, framed, drawer `(1024px <= width < 1280px)`, wide `(width >= 1440px)`.
- `web/src/app/guide/demo-guide.ts:138-143,320-324` -- the guide's right column is `--space-device-width` (`-wide` from 1440), which the device column lines up under.
- `web/src/app/guide/guide-view.ts:19,53-58` -- `GuideSnapshot` and `guideOf`, the snapshot-plus-store pattern for `phoneOf`.
- `web/src/app/live/live-store.ts`:
  - `:47` `phone` → `phones`, keyed by ref;
  - `:75,118` empty from the snapshot;
  - `:166-167` events put by key, with insertion order kept;
  - `:44,72,115` `approvals`.
- `web/src/app/live/live-state.ts:79,85,177-190` -- the `snapshot` and `store` signals. `accept()` rebuilds the store.
- `web/src/app/live/payloads.ts:135-141` -- `PhonePayload` (generated; never edit).
- `web/src/app/chat/chat-panel.ts`:
  - `:98-133` the list (`tabindex="0"`, `role="region"`, `aria-labelledby`) and the New messages button;
  - `:34` `BOTTOM_SLACK_PX`;
  - `:299-308` ResizeObserver follow;
  - `:326-337` `onScroll`;
  - `:347-358` `showNew`;
  - `:361-377` `noteArrivals`.

  This is the inline pattern the phone mirrors.
- `web/src/app/chat/chat-view.ts:43` -- `newMessages: 'New messages'`. `web/src/app/chat/page-time.ts:64` -- `pageTimeBeside(iso, instanceZone)`. `web/src/app/shared/stored-flag.ts:2,11` -- `readFlag(open, key, value)` and `writeFlag`.
- `web/src/app/header/header.ts:96-99,262-271` -- the Status count pill: hidden "Status, {spoken}", with `--tab-badge-*`. It is the badge-name precedent.
- `web/src/styles/tokens.css`:
  - `:120-124` device and phone-screen spacing;
  - `:444-487` the `--simulated-device-panel-*`, `--device-tab-*`, `--tab-badge-*`, `--simulated-label-*`, `--simulated-phone-*`, `--phone-notification-*` and `--simulated-mailbox-*` tokens;
  - `:103` `--rounded-xl` (28px).

  The file is generated: never edit it.
- **UX.** The UX folder is `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/`.
  - EXPERIENCE.md:
    - L64-73 regions and order;
    - L265 the New-messages button;
    - L296-301 the device panel, the label and the phone;
    - L335 the empty phone;
    - L376 the skip links;
    - L386 persistence;
    - L404 and L408 names and `aria-selected`;
    - L422 one announcer;
    - L458-463 the width bands;
    - L706 Telegram and the phone share text.
  - DESIGN.md:
    - L472-510 the tokens;
    - L694 the phone's height;
    - L797 New messages;
    - L830-840 the tabs, the label, the phone, the notification and the mailbox header.
  - `mockups/main-page.html:255-272,502-531` gives the markup (`section.devices`, `.dev-tabs`, `.pbar`, `.pfeed`, `.pn`, `.pn-time`). EXPERIENCE and the AC win where they differ.

**Source-scanning unit tests** (`web/scripts/`, `node --test`):
- `floor-sources.test.mjs`:
  - `:362` the tab ban (`allowed: {}`);
  - `:94-163` the keys rule (literal set `:141`, template bindings `:147-153`, `KEY_HANDLERS` `:103-110`);
  - `:298` scrollers;
  - `:454-463` the media-query files;
  - `:214-219` `FIXED_HEIGHTS`;
  - `:321-331` transitions and animations.
- `announce-focus-sources.test.mjs`:
  - `:43-50` the live-attribute ban;
  - `:95-106` speakers (the phone adds none);
  - `:112-119` `FOCUS_CALLS`;
  - `:131` `afterNextRender` allow-list;
  - `:135-142` `keepFocus` hosts.
- `ux-strings.test.mjs`:
  - `:41-53` `IMPORTED`;
  - `:83` the skip-link grab (exactly 2);
  - `:145+` `SOURCES` (`ux`, `design`, `ac`, `ruled`, `format`);
  - `:156` 'New messages';
  - `:255-256` the skip texts.
- `playwright-projects.test.mjs:184-191` -- the floor `@browsers` ids.

**E2E:**
- `web/e2e/chat/notice.spec.ts`:
  - `:36` `FIVE_SECONDS_MS`;
  - `:288-313` N10 (`started` before `sendItem(... '[[mock:refusal]]')`, then attached within the remaining budget);
  - `:467` N11 `notBuilt(..., '4.5')`.

  NOTICE user, `live sign-in`.
- `web/e2e/support/iris.ts`:
  - `:591-607` `sendNotification(user, {kind, catalogKey, slots, ...})`, which goes to Notify from NoticesIn and works for README (`ocutalon`) on any stack;
  - `:405` `sinkEvent` (BridgeSink only; it cannot publish `phone`);
  - `:610` `cleanFixtureRows`.
- `web/e2e/support/guide.ts:16-29` -- `publishWatchProgress`, a fixture publish through `Live.Publish`. Generalize it for the `mailbox` fixture events.
- `web/e2e/support/floor.ts:56-58` -- `SKIP_CHAT`, `SKIP_STATUS` and `skipLink`.
- `web/e2e/support/api.ts:27` -- `changeSnapshot`. `web/e2e/support/page.ts:17,29,37,53` -- `tokenColor`, `fromBottom`, `scrollListTo` and `recordAnnouncements`.
- `web/e2e/demo-switch/badge.spec.ts` -- `stackMode()` and `signInReadme`, the mode-following pattern.
- **Shared e2e pins:**
  - `web/e2e/api/api.spec.ts:116` and `web/e2e/frame/frame.spec.ts:502` (F9) pin the exact `/state` keys;
  - F1 `:71,:91-96` gives h2s `['Status','Chat']`, the DOM order and tabindex values; F2 `:100-117` covers demo off.
  - `web/e2e/sign-in/shell.spec.ts:38` -- `main > *` is 2.
  - `web/e2e/floor/layout.spec.ts`:
    - `placeOfFocus` `:95-105`;
    - G3 `:352-354`, which presses Tab twice to reach Skip to status;
    - G4 and G6 `:425,:504,:547,:684`, `main.main + section.rail` when stacked;
    - G5 `:552-576`, a walk `/main(,main)*,rail/`;
    - G5b `:623-624`;
    - G1 `:169`, the page doesn't scroll at 1280x600.
  - `web/e2e/floor/keyboard.spec.ts`:
    - K1 `:81-145`: Tab 2 is Skip to status, Tab 3 the home link, at three places;
    - K4 `:408-413`: Tab, Tab, Enter reaches the rail.
  - `web/e2e/floor/announcements.spec.ts:344-351` -- A7 `places`. `web/e2e/floor/words.spec.ts:159` -- W2 selectors.

## Tasks & Acceptance

**Execution** (in dependency order):
- [x] `src/ocutalon/cls/OcuTalon/Data/SimMessage.cls` -- add `Property Text As %String(MAXLEN = "")` ("the message's text as the device shows it"), appended to storage as Value 8 (V1). Update the class doc.
- [x] `src/ocutalon/cls/OcuTalon/Channel/Operation.cls` (new, abstract, `Extends Ens.BusinessOperation`) -- holds what both channel operations share:
  - `IsSession(ownerRef)`: `Session.Recipients`, plus one warning from the parameter `LOGNOTASESSION`;
  - `Announce(ownerRef, type, payload)`: `Live.Publish.Publish`, where a status error or an exception logs `LOGPUBLISH` and goes no further.

  Rule 2.
- [x] `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- extend `OcuTalon.Channel.Operation`. Drop its own `IsSession` and the try block of `Announce`, which now calls the base with `"notification"`. Behaviour is unchanged, and `Test.Core.WebChatOut` stays green as written.
- [x] `src/ocutalon/cls/OcuTalon/Live/Payload/Phone.cls` -- `ClassMethod FromRow(row As OcuTalon.Data.SimMessage) As OcuTalon.Live.Payload.Phone`: ref, direction, text and createdAt from the row, and `ApprovalRef` "" (Story 6.3 sets it).
- [x] `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls` -- the real operation (rows 1-5). It extends `Channel.Operation`:
  - parameters `CHANNEL = "phone"`, `TEXTCHANNEL = "phone"` and `CARDKINDS = "tellnow,reminder"`;
  - a MessageMap with `OcuTalon.Msg.Notification` → `OnNotification` only;
  - the steps: owner check → kind filter → `Render` → `TSTART`, save the SimMessage (new Ref, `Data.Time.NowUtc()`), `Delivery.Record(session,"phone",ref,ApprovalRef,Kind,"",DecisionRef)`, `TCOMMIT` (`TROLLBACK 1` and return the error on a failure) → `Announce(session,"phone",Phone.FromRow(row))`.
  - The response is "". Remove `STUB` and update the class doc.
- [x] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add the `recentPhone` statement: `SELECT TOP ? ID FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'phone' ORDER BY CreatedAt DESC, ID DESC` (class SimMessage, binds `ao`). Add the public `RecentPhone(sessionRef, max = 100, .sc)` and the header line.
- [x] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `PHONEMAX = 100`. Just before the `guide` line, when `body.demoMode`: `body.phone` = `RecentPhone` reversed to oldest first, each `PayloadObject(Phone.FromRow(row))`. The reader's status goes through `..Check(sc)` (`:511`), as `ChatItems`' readers do (`:405-418`; row 6). Update `StateBody`'s doc.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `DropSimMessages(sessionRef)` (SQL delete by SessionRef), called from `Clean` beside `DropDeliveries`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls` (new; lane-b `Demo`; shadow instance + `Test.Core.Observe` + `Test.Data.Fixture`):
  - `TestTellNow` and `TestReminder` (row 1 exactly, Text = `RenderAt(...,"telegram",...)` and the same with `"phone"`);
  - `TestOnlineDemoTimesNameTheZone` (row 2);
  - `TestOtherKindsRecordOnly` (row 3);
  - `TestNotASession` (instance, eval, a non-session; row 4);
  - `TestRenderError`;
  - `TestPublishFailure` (row 5);
  - `TestThroughNotify`: in the running production with demo on, a Notification from a `CreateBusinessService` host to Notify for a fixture session gives its SimMessage within 5 s. The `Ens.MessageHeader`s from Notify to WebChatOut and to SimPhoneOut have the same `MessageBodyClassName` (`OcuTalon.Msg.Notification`), `MessageBodyId` and `SessionId`, both are completed with no error, and neither has a response header. Only `TargetConfigName` differs (AC3, the Visual Trace clause).

  Clean in `OnAfterAllTests` on every path.
- [x] Server pins:
  - `Test/Data/Tables.cls` -- SimMessage gains `"Text": "%String(MAXLEN=)"`;
  - `Test/Data/Ownership.cls` -- `recentPhone` joins both kind lists, plus a reader case: oldest/newest order, cap, and another session's rows absent;
  - `Test/Web/Api.cls` -- `TestStateBody`'s keys gain `phone` before `guide`; `TestStateFlags` asserts `phone` exactly when `demoMode`; a new `TestStatePhone` covers row 6's content and order;
  - `Test/Core/ProductionItems.cls:22` -- `"stub": 0`.
- [x] `web/src/app/shared/follow-bottom.ts` (new) -- `BOTTOM_SLACK_PX` and `atBottom(el, slack)`, moved from `chat-panel.ts`. `chat-panel.ts` imports them, with no change in behaviour (Rule 2: the phone's follow rule is the chat's).
- [x] `web/src/app/devices/device-view.ts` (new; framework-free, erasable TS):
  - `DEVICE_TEXTS`: region, the two tab names, `'Simulated'`, the badge pattern, the skip text;
  - `type DeviceTab`, `TAB_KEY = 'ocutalon.devices.tab'`, `tabName(tab, count)`, `otherTab(tab)`;
  - `newRefs(seen, refs)` for the badge counts (row 9).
- [x] `web/src/app/devices/device-tabs.ts` (new; `@Injectable({providedIn:'root'})`) -- the `selected` signal, read from and written with `stored-flag` (value `'mailbox'`; anything else is phone), and `select(tab)`. Story 4.7's Show me calls `select('phone')`.
- [x] `web/src/app/devices/simulated-label.ts` (new component) -- the static amber outlined pill "Simulated" (`--simulated-label-*`), with no tabindex. The phone and Story 4.6's mailbox header both use it.
- [x] `web/src/app/phone/phone-view.ts` (new; framework-free) -- holds:
  - `PHONE_TEXTS`: "OcuTalon", the empty text;
  - `type PhoneSnapshot`, and `phoneOf(snapshot, store)`, which returns `undefined` unless `demoMode` (merge rule above);
  - `pendingApproval(list, approvals)`.
- [x] `web/src/app/phone/simulated-phone.ts` (new component `app-simulated-phone`) -- rows 10-13:
  - the frame, the top bar and `app-simulated-label`;
  - the feed: a scroller with `tabindex="0"`, `role="region"` and `aria-labelledby` its tab's id (input);
  - notifications as `[data-key]` with `tabindex="-1"`, `white-space: pre-line`, and the caption from `pageTimeBeside`;
  - the empty text;
  - follow / hold / New messages, mirroring `chat-panel.ts` with `follow-bottom.ts` plus the pending-approval hold. The New messages button is placed after the feed in tab order.
- [x] `web/src/app/devices/device-panel.ts` (new component `app-device-panel`) -- rows 7-9, 14, 15:
  - The host shows only in demo mode; otherwise it is `display:none` with no region.
  - `section` region "Simulated devices" with `tabindex="-1"` (the skip target).
  - A tablist of two `button role="tab"` with roving tabindex, `aria-selected`, `aria-controls` and a `(keydown)` that handles only ArrowLeft and ArrowRight, focusing and selecting the other tab.
  - Tabpanels with `role="tabpanel"`, `aria-labelledby` and `hidden` when unselected. The phone panel holds `app-simulated-phone`. The mailbox panel holds only its header, "Simulated mailbox" plus the label, with `tabindex="0"` (Decided 6).
  - Badge counts with `newRefs` (the badge `aria-hidden`, and the count inside the tab's name).
  - Width `--space-device-width`, `-wide` from 1440, auto when stacked. The panel body scrolls (`overflow-y:auto`, gutter).
  - `keepFocus` with the default fallback.
- [x] `web/src/app/main-page/main-page.ts` -- `<app-device-panel />` as the host's third child, after `main`. `place()` puts the rail after the device panel when stacked (main, devices, rail) and before main when framed. Update the doc.
- [x] `web/src/app/header/skip-links.ts` -- three entries; the middle one is `{text:'Skip to simulated devices', target:'app-device-panel section', demo:true}`, shown only while `snapshot.demoMode`. Update the doc.
- [x] `web/scripts/device-view.test.mjs` and `phone-view.test.mjs` (new) -- cover:
  - tab names with and without counts;
  - `otherTab` wrapping;
  - `newRefs` (no count for refs seen at load);
  - `phoneOf`: demo off is `undefined`, the merge order, and a ref in both;
  - `pendingApproval` (pending, approved, absent).
- [x] Shared-surface unit tests, each edited with its reason:
  - `floor-sources.test.mjs`:
    - the tab ban allows `app/devices/device-panel.ts` ("ARIA tabs of the simulated device panel; content never switches them (EXPERIENCE L296)"). The pattern is case-insensitive, so no other file may contain `tablist` or `tabpanel`, identifiers included;
    - the keys literal set gains `ArrowLeft` and `ArrowRight`, and the device panel's `(keydown)` joins the binding list;
    - scrollers gain the panel and the phone;
    - the media files gain the device panel;
  - `announce-focus-sources.test.mjs`: `FOCUS_CALLS` gains the device panel (1) and the phone (1); the `keepFocus` hosts gain the device panel;
  - `ux-strings.test.mjs`:
    - `SOURCES` for every new string. The badge pattern `'{tab}, {n} new'` is a `ux` entry: `holds()` (`:395-401`) matches each slot against a run of EXPERIENCE L296's "Simulated mailbox, 2 new";
    - `IMPORTED` gains `DEVICE_TEXTS` and `PHONE_TEXTS`;
    - the skip-link grab (`:83`, which matches `{ text: '...', target: '...' }` exactly) allows the optional `demo` field, and its count becomes 3;
  - `playwright-projects.test.mjs`: D1 is `@browsers`.
- [x] `web/e2e/support/devices.ts` (new) -- three helpers:
  - `publishFixtureEvent(user, type, payloadClass, fields)`, generalized from `publishWatchProgress`, which then calls it;
  - `publishMailbox(user, ref)`, a fixture `mailbox` event on the user's stream (nothing publishes one before Story 4.6);
  - `dropPhone(user, sinceUtc)`, which deletes the session's `SimMessage` rows and its phone and web `Delivery` rows from that time on, for FLOOR and README, which are not fixture sessions.
- [x] `web/e2e/phone/phone.spec.ts` (new; chromium, `live sign-in`, README with `changeSnapshot`, no server writes):
  - P1, region and tabs (row 7): names, `aria-selected`, roving tabindex, the arrows (row 8), reload memory, storage that throws, and the middle skip link focusing the region;
  - P2, look (row 10): the top bar text exactly, the label unfocusable with its token colours, the frame radius 28px, a shadow, no textbox;
  - P3, the empty text (`phone: []`) and the messages (row 11): order, line break, caption time in a browser zone unlike the instance's;
  - P4: `demoMode` false with a `phone` key gives no region and no middle skip link.
- [x] `web/e2e/chat/notice.spec.ts` -- N11 replaces the `notBuilt`. It uses N10's path and budget: `started` is taken before `sendItem`, and the unique tell-now text must be on the phone feed in under 5000 ms (row 16). Update the header comment.
- [x] `web/e2e/demo-switch/phone.spec.ts` (new; the demo-switch project, README, `stackMode()`; row 17, AC4):
  - `sendNotification('ocutalon', T with a unique stamp)` and R;
  - mode 1: both texts on the phone in order, both after a reload, and the SimMessage count of README's session +2 (`irisScript`);
  - mode 0: both chat cards visible, no region, `/state` without `phone`, and the SimMessage count +0.

  All assertions are relative.
- [x] `web/e2e/floor/devices.spec.ts` (new; the floor stack, FLOOR):
  - D1 `@browsers`: tab order (skip links, tabs, the feed), the arrows, rings inside the viewport and the panel at 1280x720 and 1280x600 (row 8);
  - D2, layout: 1440 (384px), 1280 (352px, under the Break the feed box's left edge), 1100 (352px, drawer), 1000 (stacked order and tab order main, devices, rail), and 1280x600 with no page scroll (rows 7, 14, 15);
  - D3, real arrivals with `sendNotification(FLOOR)`: follow at the bottom (row 12), hold when scrolled up and New messages focusing the first new notification (row 13), mailbox selected giving the phone badge with no switch and clearing on select, then two `publishMailbox` giving "Simulated mailbox, 2 new" (row 9);
  - D4, the pending-approval hold: `changeSnapshot` adds a pending approval to `rail.approvals` and a `phone` entry naming it, then a real arrival does not move the feed and shows New messages (row 13).

  No live attributes anywhere in the region. Each case's `finally` calls `dropPhone(FLOOR, start)`.
- [x] Existing e2e, edited for the region and the skip link:
  - `frame/frame.spec.ts` F1: the device panel after main in the DOM order, once; F9: the keys gain `phone`;
  - `api/api.spec.ts:116`: the keys gain `phone`;
  - `floor/keyboard.spec.ts` K1 (Tab 2 is Skip to simulated devices, Tab 3 Skip to status, Tab 4 the home link, at all three places) and K4 (three Tabs);
  - `floor/layout.spec.ts`: G3 three Tabs; G4 and G6 stacked `main.main + app-device-panel + section.rail`; G5's walk allows device stops between main and rail; `placeOfFocus` gains `'devices'`; G5b also drives the middle link;
  - `floor/announcements.spec.ts` A7: `app-device-panel` joins `places`;
  - `floor/words.spec.ts` W2: the tab buttons join the selectors;
  - `support/floor.ts`: `SKIP_DEVICES`.

**Acceptance Criteria:**
- **AC1.** Given demo mode on, when the main page renders, then rows 7, 8 and 14 hold. The region "Simulated devices" sits right of the chat at `device-width` (wide from 1440px). Its ARIA tabs are "Simulated phone" (selected by default) and "Simulated mailbox", moved between with the arrow keys and marked with `aria-selected`. The skip links read "Skip to chat", "Skip to simulated devices", "Skip to status". With demo mode off there is no region and no middle link.
- **AC2.** Given an unselected tab, when new content arrives, then row 9 holds: a badge count also in its name, and no switch. The selected tab is remembered per browser.
- **AC3.** Given a notification for a session while demo mode is on, when `Notify` routes it to `SimPhoneOut`, then rows 1-5 hold. The text equals the paired chat's (`telegram`) render: plain text, " ET" on the online demo. The SimMessage and Delivery rows and the `phone` event are written. Its Notify-to-SimPhoneOut message is the same production message as the web chat's, with only the target differing (Visual Trace).
- **AC4.** Given the demo-switch stack, when fixture notifications of kinds `tellnow` and `reminder` are sent, then with demo mode on they are on the phone (also after a reload), and with demo mode off they are nowhere on the phone: no region, no `phone` key, no SimMessage row (row 17; Integration).
- **AC5.** Given the live sign-in stack with the mock, when N10's untrusted item gets its tell-now decision, then the notification is on the simulated phone within 5 seconds (row 16; Integration; Story 2.7's phone half).
- **AC6.** Given the Simulated phone tab, when it renders, then rows 10 and 11 hold: the generic frame, "OcuTalon" plus the unfocusable "Simulated" label, no clock, brand or composer, the session's notifications newest at the bottom with caption times, and the exact empty text.
- **AC7.** Given a new phone notification, when I have scrolled up or an approval request is pending in the phone, then the phone does not scroll and "New messages" applies; otherwise the notification scrolls into view. The region is never a live region (rows 12-13).
- **AC8.** Given the floor stack, when the floor suite runs, then D1-D4 and the edited floor cases pass, with D1 in Chromium, Firefox and WebKit (rows 14-15).

### Review Findings

Code review 2026-10-26 (stage `e4s5cr`, full mode; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). 33 rows: 9 entries survive (high 0, medium 2, low 7), all `patch`, all applied; 0 decision-needed. One more entry came from the review's own verification run (DW-274, routed). Each entry: severity, fix-risk, footprint, spec-status.
- [x] [Review][Patch] At 1280x600 the phone screen keeps its 360px minimum in a shorter column, so New messages lies below the panel body's view; apply the lead's ruling (the screen yields to the body's height beside the chat), drop D5b's `test.fail()` and D1's 85% ring branch, and make D2's short-window clauses pin the ruling (medium; fix-risk low, CSS only, the stacked rule kept; in-story; clear, Design Notes ruling) [web/src/app/devices/device-panel.ts:173]
- [x] [Review][Patch] `TestThroughNotify` pins the SimMessage but not the production path's phone Delivery row and `phone` event that the Integration AC names (medium; fix-risk low, assertions only; in-story; clear) [src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls:301]
- [x] [Review][Patch] `TestNotASession` and `TestOtherKindsRecordOnly` assert "no phone message, no event" only for inputs that can never reach `Save`, and read the instance stream from its oldest event; add a card that renders and read the instance stream from a mark (low; fix-risk low; in-story; clear) [src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls:210]
- [x] [Review][Patch] `TestTextIsTheTelegramWording` checks its event only `If events.%Size() = 1`, with no count assertion (low; fix-risk low; in-story; clear) [src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls:139]
- [x] [Review][Patch] `TestReminder`'s doc claims a no-due-slot case that it never sends (low; fix-risk low, a comment; in-story; clear) [src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls:103]
- [x] [Review][Patch] `devices.spec.ts`'s header names D1 to D4 only; D5 and D5b are undescribed (low; fix-risk low, a comment; in-story; clear) [web/e2e/floor/devices.spec.ts:24]
- [x] [Review][Patch] The Simulated label's `min-height: 20px` is a raw value, and the phone caption takes the tab badge's typography instead of DESIGN's caption (low; fix-risk low, value-identical tokens; in-story; clear) [web/src/app/devices/simulated-label.ts:22]
- [x] [Review][Patch] An arrow key on a focused tab that is not the selected one moves from the selected tab, not the focused one (reachable by a press dragged off a tab); the arrows now move from the focused tab, and P1 pins it (low; fix-risk low; in-story; clear) [web/src/app/devices/device-panel.ts:278]
- [x] [Review][Patch] `phoneRows` reads an empty CHK value as 0, so a failed count would pass the demo-off "+0" check (low; fix-risk low; in-story; clear) [web/e2e/support/devices.ts:75]
- [x] [Review][Defer] The CDK live announcer's element has no visually-hidden style until a dialog's focus trap loads it, so its last text lies below a framed page and the page scrolls by a line (D2's probe at 1280x480: the element is static at 480-501px after the narrow-window note) [web/src/app/shared/announcer.ts:18] — deferred: pre-existing (Story 2.12), in-epic MED, fix-risk low; DW-274 `routed owner=burndown`. D2's short-window loop therefore checks that nothing of `app-root` reaches below the window; G1 and D2's 600px document check are unchanged.

Applied: the device panel's phone panel is the body's height beside the chat (`flex: 1 1 0`, `--phone-screen-min: 0px`), and the stacked rule keeps `min(360px, 70vh)` with the panel as tall as the phone; D1 uses the strict ring check at both heights; D2's 600px and 480px clauses pin the yield (screen under 360px, nothing hidden in the body, the screen inside it, the feed scrolling); D5b runs without `test.fail()`. Runs (fresh lane-B throwaways, tag `e4s5cr`, after `ci/iris.sh build`): `live floor` 88 passed in the three projects; `live sign-in` 217 passed; `class OcuTalon.Test.Demo.SimPhoneOut` passed with no skip; `npm --prefix web test` 640 of 640; lint exit 0.

**Rejected** (verdict, then why):
- `low` The badge counts reset when LiveState reloads the snapshot (new epoch or skipped Seq), so an existing badge clears without a selection (blind-hunter, edge-case-hunter, verification-gap) - reloads come only from an epoch change or a lost event, the reset is the documented contract ("a reload records what is there"), and a fix adds branches that a demo-mode change would make miscount.
- `low` ArrowLeft and ArrowRight act with Alt, Ctrl, Meta or Shift held (blind-hunter, edge-case-hunter) - Back from the page while focus is on a device tab is rare; the fix adds a guard that the ARIA pattern does not ask for.
- `low` `IsSession` passes a Ref that differs only in case, through the SQLUPPER unique index (edge-case-hunter) - no caller produces such a Ref; the code moved unchanged from WebChatOut, and the fix is in Epic 16's contended `Data/Session.cls`.
- `low` `TestThroughNotify`'s `$ZHorolog + WAIT` deadline never ends across midnight (edge-case-hunter) - only a run that already fails, within 5 s of midnight; the same deadline form is used in 71 places across the tree.
- `maybe-false` (would be low) The feed's scroll position resets when its tab is hidden and shown again (edge-case-hunter) - settle by toggling the tabs with the feed scrolled up in the three engines; low either way, and the fix adds saved state.
- `false` New messages loses focus when its target message is gone (edge-case-hunter) - the target is a ref of the list, and the list only loses refs when demo mode goes off, which removes the panel too.
- `low` Row 6's phone reader error has no test of its own (verification-gap) - no AC lists row 6; a failing phone read alone needs a fault seam the chat's readers do not have either.
- `false` AC clauses without their own `mutation:` line (widths, storage that throws, caption time, Visual Trace) (verification-gap) - Rule 19 asks one demonstrated mutation per AC, and every AC has one.
- `false` `newRefs(new Set(), [])` deep-equals `[]` cannot fail (verification-gap) - a supporting edge assertion that a non-array or a list with `''` fails; the case's first assertion pins it.
- `false` `TestThroughNotify` relies on demo mode that it did not set (verification-gap) - every docker stack starts in demo mode (Decided 13), and the test asserts it first, like the running production.
- `low` In the stacked layout the screen minimum is `min(360px, 70vh)`, a raw 70vh, under 360px in short windows (acceptance-auditor) - the fix would edit row 14 or put the feed's ring outside the window again; it follows the lead's yield-to-the-room ruling, residual risk (1), and the chat list's stacked 70vh.
- `false` `DEVICE_TEXTS` has no skip text (acceptance-auditor) - the text has one source, `SKIP_LINKS`, which `ux-strings` reads; no harm.
- `false` D1 does not walk the skip links with Tab (acceptance-auditor) - K1 walks the three links in all three engines.
- `false` While the snapshot loads only two skip links show (acceptance-auditor) - the middle link is shown only while `snapshot.demoMode`, which is unknown before the snapshot (residual risk (2), judged by QA).

## Spec Change Log

- 2026-10-26, spec gate (runner): V1 kept as a veto item (U-89); spine conventions row updated.

## Review Triage Log

### 2026-10-26 - Review pass
- verdicts: 20 findings - high 0, medium 1, low 14, false 5, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: card kinds, the Delivery branch and the render skeleton repeat WebChatOut's - the lists agree today and the two skeletons differ (Save versus Delivery.Record with text, due time and reason); folding them is more than a direct correction -> reject (a copy of two lines of constant; the sibling's own Delivery call cannot be shared)
  - `[low]` `[patch]` Blind: `tabOf` is exported and tested but the app never calls it - removed it, and the unit test now pins `readFlag` against the stored values (Mailbox, empty, null, other), which is what `DeviceTabs` calls
  - `[low]` `[reject]` Blind: `dropPhone` depends on the host and instance clocks (2 s margin) - same machine and one worker; a test-only helper; no failing case shown
  - `[low]` `[patch]` Blind: `playwright.config.ts` comment names the demo-switch specs as badge and guide only - now names the phone spec
  - `[low]` `[reject]` Blind: the `docker/tests/test-demo-switch.sh` comment says only WebChatOut drops the control Notification - contended path; a comment only
  - `[low]` `[reject]` Blind: the DeviceTabs comment lists a guide's Show me - Story 4.7 uses `select` per the spec; the comment states the contract
  - `[false]` `[reject]` Blind: the empty phone text promises approval requests - the text is EXPERIENCE's verbatim string, fixed by the spec's exact-text rule
  - `[false]` `[reject]` Blind: the feed region repeats its tabpanel's name - the feed is the scroller and tab stop, a region named by its tab, by spec Design Note 11 (a tabpanel is not a region landmark)
  - `[low]` `[reject]` Blind: IsSession and Announce are public on the base - callable by subclasses either way; no harm
  - `[medium]` `[patch]` Blind (verification gap): `Save` has no failure test - added `TestSaveFailureKeepsNothing` (an ApprovalRef over its 22 characters fails the Delivery row: error status, no message, no row, no event, no open transaction); mutation line added
  - `[low]` `[patch]` Edge: `FromRow` was evaluated outside Announce's Try, a change from WebChatOut's behaviour - `Announce` now takes the payload class and the row and builds the payload inside its Try; both callers updated
  - `[low]` `[reject]` Edge: `TROLLBACK 1` inside an already open transaction - the operation runs as a production host, never inside a caller's transaction; the one test that opens one (TestPublishFailure) commits it
  - `[low]` `[reject]` Edge: same claim as the FromRow finding for WebChat/Out.cls:54 - carried, patched once
  - `[low]` `[reject]` Edge: same claim as the dropPhone clock finding - carried
  - `[low]` `[patch]` Verification gap: `TestPublishFailure` leaves a transaction open if `OnNotification` throws - the call is now in a Try with the status taken from the exception
  - `[low]` `[patch]` Verification gap: mutation lines missing for the online-demo " ET", rollback, ordering/PHONEMAX, reload and persistence clauses - lines added after demonstrating each; the Visual Trace line is recorded with its limit (see the mutation list)
  - `[false]` `[reject]` Verification gap: `TestNotASession`'s "no event" line may be vacuous - `Observe.Phones` reads each owner's own stream, so a published event for `instance` or the unknown Ref would be seen
  - `[low]` `[reject]` Verification gap: the dispatch cases need a fresh stack - recorded in Verification (fresh only); not a defect
  - `[false]` `[reject]` Intent: readings A-D, the diff implements A end to end; no divergence in the surface (the 5-second check N11 runs on the live stack)
  - `[false]` `[reject]` Intent: tab persistence and mailbox badges go beyond the intent - matrix rows 8 and 9 name both

## Design Notes

**Lead ruling on QA's clarification (runner, 2026-10-26; decide):** at 1280x600 the device column is shorter than the phone screen's 360 px minimum, so the phone's "New messages" button floats below the visible panel body (QA's D5b, marked `test.fail()`). AC7's New-messages pattern must hold at every supported size, so the button must be visible inside the panel body. Ruling: when the column is shorter than the phone's minimum, the phone screen yields to the available height (its minimum becomes the smaller of 360 px and the space the panel body gives it), so the feed scrolls inside the screen and the button sits at the screen's visible bottom; at normal heights nothing changes. Use DESIGN's tokens and no height queries, sticky positioning or observers (floor rules, Decided 11); if that cannot work, place the button at the panel body's visible bottom instead. The code review applies it as an in-story patch, removes D5b's `test.fail()`, and runs `live floor` and `live sign-in` clean after `ci/iris.sh build`.

**Lead rulings at the spec gate (runner, 2026-10-26; policy 9e90866):**
- **V1 (veto, kept; inbox U-89):** `Data.SimMessage.Text`, appended to storage, as recommended.
- **Spine:** the "Live events" conventions row now names the snapshot's demo-only `phone` and `guide` keys (Rule 20, a conventions row; no AD change).
- **Footprint:** the Lane B home-area extensions the plan lists are accepted; `Data/Delivery.cls` and `web/src/app/api/**` stay untouched (contended).


**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- **AD-14** (L390-401):
  - SimPhone is out only;
  - `Notify` is the one routing rule (unchanged);
  - each `*Out` records its `Delivery` row through `Delivery.Record`;
  - `FindByApproval` serves in-place edits. Its first phone consumer is Story 6.3, not this story; Story 2.7's spec named 4.5, but the edit is 6.3's AC (epics L2763).
- **AD-32** (L840-851):
  - only `*Out` operations render, through `Render(key, slots, channel)`, with times through `Data.Time` and " ET" online;
  - Approve and Reject come only with kinds `incident` and `approval`. So this story shows no such notice without them (Prevents).
- **AD-12** (L330-343): a full view keyed by `Ref`, published after commit; the snapshot plus events; the page decides nothing. `phone` is not a guide trigger.
- **AD-33** (L852-862; event table L1105): `SimPhoneOut` is the only `phone` publisher; `SimMessage` and `Delivery` are Lane B's.
- **AD-4** (L155-178): only a session owner gets rows; the snapshot reads with the caller's `SessionRef`; no client-supplied Ref.
- **AD-3 and AD-5:** SimMessage keeps its private global; the new property is appended to storage, so existing rows read `Text` as "".
- **AD-13:** text binding only, no `bypassSecurityTrust*`. No new REST call.
- **AD-26:** the phone's message is in the turn's or decision's trace session like the web chat's.
- **AD-22** (L579-604): the mock stack; N10's path.
- **AD-29** (L765-799): Lane B.
- **Conventions:**
  - L907 Times;
  - L913 "Announcements and focus";
  - L914 "Text OcuTalon sends";
  - L926 Angular ("one typed API client": no new client; `phone` comes through `LiveState`);
  - L930 Tests (floor cases only in `live:floor`);
  - L911 "Notice cards" (WebChatOut unchanged).

**Decided in-stage:**
1. **Kinds.** `tellnow` and `reminder` reach the phone screen, the web chat's card kinds and the AC's test kinds. Others record their phone `Delivery` row only, as WebChatOut does. Approve and Reject and the incident, approval, answered and result kinds are Stories 6.3 and 6.4's ACs (epics L2753-2755, L2793, L2810, L2814), and AD-32 forbids such a notice without buttons. No AC moves.
2. **The Delivery row carries no text.** Delivery's `Text` is documented for web cards only, and the class is contended, so the phone's text lives on `SimMessage` (V1). `ChannelMessageId` = the SimMessage's `Ref`, so Story 6.3's `FindByApproval` finds the message to edit.
3. **The snapshot.** `phone` appears in demo mode only, like `guide`, and sits before it so `guide` stays last. It holds the newest 100, oldest first (the chat's cap). A reader error fails `/state` as the chat's readers do.
4. **N11 follows N10.** On the keyless sign-in stack the untrusted item's decision is the no-key fallback tell now. The clock starts before the send, a stricter bound than "from its decision", as Story 2.7's accepted N10 does.
5. **The real switch carries AC4.** `Notify`'s `DemoOn()` reads a 60 s per-process cache, so a unit test cannot switch it in time. The demo-switch stack switches for real and runs its specs 61 s after each switch. A spec in `web/e2e/demo-switch/` joins without a script edit.
6. **The mailbox panel** holds only its header ("Simulated mailbox" plus the label, DESIGN L840), as plain text with no heading.
   - The empty text names controls that Story 4.6 adds, so it waits for them.
   - The panel has `tabindex="0"` (APG: a tabpanel without focusable content).
   - The phone panel has none, because its feed is a tab stop.
7. **Tabs.** Activation is automatic. ArrowLeft and ArrowRight wrap; Home and End are not handled (two tabs; optional in APG).
   - The badge counts live arrivals while the tab is unselected and clears on selection. Content present at load is never "new".
   - The badge is visual and `aria-hidden`; the count is in the tab's name, as the header's Status pill does.
8. **No heading for the region.** It is named by `aria-label`, as the mockup and Story 4.4's guide do, so F1's, B's and Q's h2 lists hold.
9. **"Pending on screen"** means a phone message whose `approvalRef` names a `pending` approval in the store. That is the conservative reading of EXPERIENCE L301's purpose: a late arrival never moves Approve and Reject. In this story only a fixture produces one (D4).
10. **The caption time** is `pageTimeBeside(createdAt, instanceZone)`, the notice card's rule for a page time beside message text (Story 2.7's AC). The mockups' bare "14:12" is the same time in the instance's zone.
11. **The feed is the scroller and tab stop** (`role="region"`, named by its tab), as the chat list is. The device panel body also scrolls when the column is shorter than the phone's minimum. No height query is needed.
12. **The drawer band (1024-1279) keeps `--space-device-width`.** EXPERIENCE L462 names no device width there; the guide's column above keeps it (`demo-guide.ts:315-319`), so the box stays aligned over the device column.
13. **Every docker stack runs in demo mode.** From this story, every notification test session also gets SimMessage and phone `Delivery` rows and a `phone` event. `Test.Data.Fixture.Clean` drops them for fixture sessions. No test found at planning asserts a stream's exact event list or counts deliveries across channels where a notification is sent (`Observe.Events` filters by type; RoutingProduction's all-channel counts send no Notification). The implement stage re-greps.

**Veto-window item (with the recommendation):**
- **V1 (a change to how stored data is kept: a schema addition).** `OcuTalon.Data.SimMessage` gains `Text As %String(MAXLEN = "")`, appended to its storage. Existing rows read it as "".
  - **Recommendation: keep.** SimMessage is "a message on the simulated phone or mailbox". Its text must survive a reload (the snapshot), and Story 6.3's in-place edit changes what the phone shows, while the `Delivery` row stays the record of what was sent. Story 4.6 can keep an email's body in the same column.
  - **Alternative:** the phone text on its `Delivery` row through `Record`'s existing `text` argument. That needs no schema change, but it contradicts Delivery's documented contract ("empty for any other row"). Delivery is contended (Epic 10), so the doc fix and 6.3's edits there would be a clarification. Reversal before implement costs nothing; after, it means moving one column's reads.

**Rule 2 (extend, don't copy):**
- `SimPhoneOut` and `WebChatOut` share a new abstract `Channel.Operation` (the owner check and the publish-and-warn). Each keeps its own steps, because they write different rows and events. Story 4.6's `SimMailboxOut` can extend it too.
- `Phone.FromRow` follows `Notification.FromRow`, and `Ownership.RecentPhone` is a `Rows` kind like `RecentNotices`.
- `Test.Demo.SimPhoneOut` follows `Test.Core.WebChatOut`'s shadow-instance pattern and its `Observe` helpers.
- The phone's follow and New messages logic mirrors `chat-panel.ts` and shares `follow-bottom.ts` with it. The rest of the chat's version is bound to turns, replies and composer sends, so the phone keeps its own few lines for arrivals and the approval hold.
- The tab memory uses `stored-flag`, the caption uses `pageTimeBeside`, and the button text is the chat's `newMessages`. `publishFixtureEvent` generalizes `publishWatchProgress`.

**Integration ACs (Rule 1):**
- The page (`app-device-panel`, `app-simulated-phone`) reads the real `/state.phone` and real `phone` events from the real `SimPhoneOut` behind the real `Notify` (AC4 on the demo-switch stack; AC5 N11; D3).
- `Notify` → `SimPhoneOut` in the running production writes the rows and the event (`TestThroughNotify`).

**Consumes:**
- Story 2.7: `Notify`'s demo route, `Delivery.Record`, N10's path and budget;
- Story 0.9: `Msg.Catalog.Render`;
- Epic 2: `LiveState`, `live-store`'s `phones` and `approvals`, `focus-rule`, `stored-flag`, `page-time`, the chat's New messages, skip links, `Layout`;
- Story 4.1: the demo-switch stack;
- Story 4.4: the guide's device-width column.

**Consumed-by:**
- **Story 4.6:** the mailbox tabpanel, its badge (`store.mailboxes`), `app-simulated-label`, `Channel.Operation`, and possibly `SimMessage.Text` for the body.
- **Story 4.7:** Show me calls `DeviceTabs.select('phone')` and focuses the pending notification (`[data-key]`).
- **Story 6.3:** Approve and Reject on the phone; `FindByApproval(approvalRef, "phone", owner)` → the SimMessage `Ref`, an in-place edit of `Text` and a `phone` republish with the same ref; `ApprovalRef` in `Phone.FromRow`.
- **Story 6.4:** the result, fallback and no-fix kinds (extend `CARDKINDS` or their own path).
- **Story 8.3:** real reminders on the phone.
- **Stories 11.1 and 11.3:** the demo path and the 5 s measure on the phone.
- **Story 12.6:** Telegram's text equals the phone's, key by key.

**Ledger:** the inbox for this story is empty; no DW entry is owned.

**For the lead:**
- **Footprint.** Outside Epic 4's listed footprint, all Lane B home areas and none contended:
  - `Channel/Operation.cls` (new) and `Channel/WebChat/Out.cls`;
  - `Data/{SimMessage,Ownership}.cls` and `Live/Payload/Phone.cls`;
  - `Test/Data/{Tables,Ownership,Fixture}.cls`, `Test/Web/Api.cls`, and `Test/Core/ProductionItems.cls`'s SimPhoneOut row;
  - `web/src/app/{devices/*, main-page/main-page.ts, header/skip-links.ts, shared/follow-bottom.ts, chat/chat-panel.ts}`;
  - `web/scripts/*.test.mjs`;
  - `web/e2e/{phone,frame,api,chat,floor,support}/**`.

  In the footprint: `Channel/SimPhone/**`, `Web/Api.cls`, `Test/Demo/**`, `web/src/app/phone/**` and `web/e2e/demo-switch/**`.
- **Spine.** No AD changes. The snapshot's `phone` key (demo only, newest 100, oldest first) could join the "Live events" conventions row beside the chat's cap. V1 needs no spine edit (the code owns the attributes).
- **Mockup differences.** The mockups show no skip links and no phone New messages button, and `states.html` keeps only the label in the mailbox header. EXPERIENCE, DESIGN and the AC win.

## Verification

`<B>` means: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=implement'`.
- The fresh tag is `e4s5i` and the warm tag `e4s5iw` (`ci/warm.sh up` once; `ci/warm.sh down` at the end, also after a failure).
- One command per foreground call (`timeout: 600000`); one `iris_execute_tests` per message.
- **Slot B** (`ocutalon-slot-b`, `OCUTALON`) is for loading and compiling only (`iris_doc_load`, `baseDir` `src/ocutalon/cls`).
- **Fresh stacks only.** The live units, the demo switch, and `TestThroughNotify` (the running `SimPhoneOut` job must hold the new class) run on fresh throwaways.
- **No Task 0.** Every platform behaviour this story uses is already exercised in this tree:
  - shadow-instance operation tests;
  - `Live.Publish` after a commit, and its refusal inside a transaction;
  - `CreateBusinessService` sends to Notify;
  - `Ens.MessageHeader` reads.

  The abstract `Ens.BusinessOperation` base is standard Interoperability practice (inference). `Test.Core.WebChatOut`, `Test.Demo.SimPhoneOut`, both shards and `live production` prove it.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes, the new view tests and the edited source, string and project tests included.
- `npm --prefix web run lint` -- expected: exit 0.
- `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh class OcuTalon.Test.Demo.SimPhoneOut` -- expected: `CLASS ... passed` with no skip (fresh: its production case).
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s5iw ci/iris.sh class OcuTalon.Test.Core.WebChatOut` -- expected: passed (the refactor changes nothing).
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s5iw ci/iris.sh class OcuTalon.Test.Data.Ownership` -- expected: passed.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s5iw ci/iris.sh class OcuTalon.Test.Data.Tables` -- expected: passed.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s5iw ci/iris.sh class OcuTalon.Test.Web.Api` -- expected: passed.
- `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh live sign-in` -- expected: PASS (chromium: P1-P4, N10-N12, F1, F2, F9, api, chat C6 and C9).
- `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh live floor` -- expected: PASS in all three projects (D1-D4, K1, K4, G1-G6, A7, W2, the guide's M cases).
- `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh live demo-switch` -- expected: all PASS (the phone spec in modes 0 and 1).

Rebuild the web bundle with `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh build` before a browser run that should see changed web code.

`(once)`:
- `bash docker/tests/test-web-build.sh` -- expected: the build passes (the payload and catalog checks, budgets under the error level).
- `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh shard lane-b` -- expected: every class passed.
- `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh shard lane-a` -- expected: every class passed (`Test.Install.Production`'s stub check reads the oracle).
- `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh live production` -- expected: PASS (the pool's stub list no longer holds SimPhoneOut).
- `<B> OCUTALON_RUN_TAG=e4s5i ci/iris.sh live demo-path` -- expected: PASS (the region shows on that stack; 01-page's `4.7` part stays skipped).
- `bash ci/checks.sh` -- expected: exit 0.

**Planned mutations (Rule 19).** Apply each, observe red, revert, confirm `git status --short` and `git diff --stat` are unchanged, and record it as `mutation: ... -> ...`.

| AC | Mutation | Expected red |
| --- | --- | --- |
| 1 | `phoneOf` and the panel ignore `demoMode` | `phone-view.test`; P4 |
| 1 | the skip link's `demo` flag ignored | P4 (no middle link with demo off) |
| 1 | ArrowRight focuses without selecting | P1; D1 |
| 2 | the badge counts snapshot content | `device-view.test`; D3 (no badge at load) |
| 2 | content switches the tab | D3 (mailbox stays selected) |
| 3 | `TEXTCHANNEL` `"web"` | `TestTellNow` (text ≠ the telegram render) |
| 3 | the owner check after `Render` | `TestNotASession` (a render error for `{}`) |
| 3 | no `Delivery.Record` for the phone | `TestTellNow`; `TestThroughNotify` |
| 4 | `Web.Api` adds `phone` whatever `demoMode` | `TestStateFlags`; demo-switch phone spec mode 0 |
| 5 | the phone feed drops live `phone` events (snapshot only) | N11 red (no text in 5 s) |
| 6 | `white-space: pre-line` removed | P3 (the line break) |
| 6 | the label gets `tabindex="0"` | P2; D1 |
| 7 | the follow ignores the pending-approval hold | D4 |
| 7 | the follow scrolls when scrolled up | D3 |
| 8 | `place()` keeps rail after main when stacked | D2; G4 |

**Mutations run (Rule 19).** Each was applied, observed red, and reverted (files byte-identical to the backups).
- mutation: AC1 `phoneOf` ignores `demoMode` -> `phone-view.test.mjs` red (the demo-off case)
- mutation: AC1 the panel's `demo()` ignores `demoMode` -> `F2` and `P4` red (region count)
- mutation: AC1 the skip link's `demo` flag ignored -> `P4` red (a middle skip link with demo off)
- mutation: AC1 ArrowRight focuses without selecting -> `D1` red in Chromium, Firefox and WebKit (`aria-selected`)
- mutation: AC2 `newRefs` counts what was seen -> `device-view.test.mjs` red (two cases); the badge of the snapshot's content
- mutation: AC2 content selects the unselected tab -> `D3` red (the phone tab with the count is not found; the mailbox no longer stays selected)
- mutation: AC3 `TEXTCHANNEL` `"web"` -> `TestTextIsTheTelegramWording` red (the web render of `answered.approved` differs from the telegram one). `TestTellNow` stays green: `notice.tellNow` and `reminder.*` have no web wording, so a key that words the web differently is needed (added test)
- mutation: AC3 the owner check after `Render` -> `TestNotASession` red (render error for the `{}` slot set)
- mutation: AC3 no `Delivery.Record` for the phone -> `TestTellNow`, `TestReminder`, `TestPublishFailure` red
- mutation: AC4 `Web.Api` adds `phone` whatever `demoMode` -> `TestStateFlags` red and the demo-switch phone spec red in mode 0 (`/state` has no phone key)
- mutation: AC5 the phone feed drops live `phone` events -> `N11` red
- mutation: AC6 `white-space: pre-line` removed -> `P3` red
- mutation: AC6 the label gets `tabindex="0"` -> `P2` red
- mutation: AC7 the follow ignores the pending-approval hold -> `D4` red
- mutation: AC7 the follow scrolls when scrolled up (the ResizeObserver always scrolls) -> `D3` and `D4` red
- mutation: AC8 `place()` keeps the rail after main when stacked -> `D2`, `G4` (three cases), `G5` and `G6` red
- mutation: AC3 `Save` ends with `TCOMMIT` instead of `TROLLBACK 1` (a failed Delivery row keeps the message) -> `TestSaveFailureKeepsNothing` red (the phone message is kept)
- mutation: AC3 the text is rendered with the online-demo flag forced off (`RenderAt(..., "", 0)`) -> `TestOnlineDemoTimesNameTheZone` red (no " ET")
- mutation: AC3 the operation returns an `Ens.Response` -> `TestTellNow` red (with no response). `TestThroughNotify`'s "neither has a response header" stays green under this mutation: the clause guards Notify's routing, which this story does not change (inference: an asynchronous send records no response header for a response nobody asked for)
- mutation: AC4 `Ownership.RecentPhone` orders ascending -> `TestRecentPhone` red (newest first, and the newest max)
- mutation: AC4 `/state` drops one phone row (the loop stops one short) -> `TestStatePhone` red (the three messages, oldest first, at most PHONEMAX)
- mutation: AC4 `/state.phone` is always empty -> the demo-switch phone spec red on the reload (the texts are not there after it)
- mutation: AC1 `DeviceTabs.select` does not store the tab -> `P1` red (the choice is not remembered after a reload)

**QA additions (QA)** (stage `e4s5qa`; the tests close three gaps the implement stage left, and one defect they found):
- `web/e2e/phone/phone.spec.ts` (QA): P3's messages case gains the clause that the empty text is gone once the phone holds a message (row 11).
- `web/e2e/floor/devices.spec.ts` (QA): D3 gains the clause that the selected phone tab takes no count and no badge from what arrives on it (row 9), and D5 and D5b (row 13 and row 15 together, short window): New messages is the tab stop after the feed, its ring is inside the viewport, Enter focuses the first new message (D5); at 1280x600 the button is in view of the panel body (D5b; QA marked it `test.fail()` for the known defect, and the code review removed the marker when it applied the lead's ruling).
- Judged and left as they are: the loading-time skip link is pinned by K1 (`keyboard.spec.ts`, the page still loading: Skip to chat, then Skip to status); D1's 85% clause at 1280x600 is the engine-neutral reading of a ring that cannot be wholly in view, and D5 and D5b now pin what it left open (the New messages stop and its place).
- mutation: AC6 the empty text is shown beside messages -> `P3` (messages case) red
- mutation: AC7 the New messages button placed before the feed in the template -> `D5` red (the stop after the feed is not New messages)
- mutation: AC2 the badge counts arrivals on the selected tab -> `D3` red (the selected phone tab has a count in its name)
- mutation: AC7 `aria-live="polite"` on the phone feed -> `announce-focus-sources.test.mjs` red (the live-attribute ban; node test only, no browser run)

**Code review mutations** (stage `e4s5cr`; each applied, observed red on a fresh throwaway, and reverted from a backup with `git status --short` and `git diff --stat` unchanged):
- mutation: AC7 (row 15) beside the chat the phone keeps its 360px minimum (the device panel's `--phone-screen-min` set to `var(--space-phone-screen-min-height)`) -> `D5b` red (New messages at 615-647px under a panel body view ending at 600px), and `D2` and `D1` red (`D1` in Chromium, Firefox and WebKit)
- mutation: AC3 `Save` records no phone Delivery row -> `TestThroughNotify` red ("one phone Delivery row, for the message"), with `TestTellNow`, `TestReminder`, `TestPublishFailure` and `TestSaveFailureKeepsNothing`

**Shared surfaces:**
- `/state`'s keys (`Test.Web.Api`, `api.spec.ts:116`, F9);
- SimMessage's contract (`Test.Data.Tables`);
- `Ownership`'s kind lists;
- the production oracle's SimPhoneOut stub flag (`Test.Install.Production`, `test-production.sh`);
- the skip links and first tab stops (K1, K4, G3, G5b, the `ux-strings` skip grab, `support/floor.ts`);
- the region and stacked order (F1, G4, G5, G6, `place()`);
- the source-scan lists (tabs, keys, scrollers, media files, `FOCUS_CALLS`, `keepFocus` hosts, `SOURCES`, `IMPORTED`, `@browsers` ids);
- A7's places and W2's selectors;
- the chat's bottom tracking (C6, C9, N12, K4);
- WebChatOut's code (`Test.Core.WebChatOut`);
- every notification test session's streams and rows in demo mode (a `phone` event, SimMessage and phone `Delivery` rows; `Fixture.Clean` drops them);
- the FLOOR session (D3 and D4 add, then `dropPhone` removes) and README on the demo-switch stack (gains two cards and two phone rows per run; relative assertions).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented.** `SimPhoneOut` is a real channel: for the card kinds (`tellnow`, `reminder`) it renders the telegram text, saves a `SimMessage` (new `Text` column) and its phone `Delivery` row in one transaction, then publishes `phone`; other kinds record only their Delivery row; non-session owners are dropped with one warning. `/state.phone` (demo mode only, newest 100, oldest first) is read through `Ownership.RecentPhone`. The page has the "Simulated devices" region (ARIA tabs, skip link, phone feed with the "New messages" pattern, a header-only mailbox shell). `Channel.Operation` is the new abstract base (`IsSession`, `Announce`) that `WebChat.Out` now shares.

**Files changed** (one line each): server - `Channel/Operation.cls` (new base), `Channel/SimPhone/Out.cls` (real channel), `Channel/WebChat/Out.cls` (extends the base), `Data/SimMessage.cls` (`Text`), `Data/Ownership.cls` (`RecentPhone`), `Live/Payload/Phone.cls` (`FromRow`), `Web/Api.cls` (`phone` in `/state`); tests - `Test/Demo/SimPhoneOut.cls` (new), `Test/Data/{Tables,Ownership,Fixture}.cls`, `Test/Web/Api.cls`, `Test/Core/ProductionItems.cls`; web - `src/app/devices/**`, `src/app/phone/**`, `shared/follow-bottom.ts` (new), `chat/chat-panel.ts`, `main-page/main-page.ts`, `header/skip-links.ts`; e2e and node tests - `e2e/phone/phone.spec.ts`, `e2e/floor/devices.spec.ts`, `e2e/demo-switch/phone.spec.ts`, `e2e/support/devices.ts`, edits to the frame, api, chat, notice (N11 real), floor and support specs, and the source-scan tests under `web/scripts/`. Outside the stated footprint: `web/e2e/chat/chat.spec.ts` (C5 and the empty-chat G4 case open larger windows because the device column narrows main), `web/playwright.config.ts` (a comment only).

**Review.** 20 findings: patches applied 5 (the `TestSaveFailureKeepsNothing` test, `Announce` builds the payload inside its Try, the dead `tabOf` removed with its test now pinning `readFlag`, `TestPublishFailure` kept hermetic, the config comment), nothing deferred, 15 rejected with reasons in the triage log (spec-mandated texts and region, theoretical or test-only clock and transaction claims, a comment in a contended script, descriptive intent findings). Patched by verdict: medium 1, low 4. Follow-up review not recommended.

**Verification.** `npm --prefix web test` 640 of 640, `npm --prefix web run lint` exit 0, `bash ci/checks.sh` and `bash docker/tests/test-web-build.sh` pass; `class` runs of `Test.Demo.SimPhoneOut` (fresh), `Test.Core.WebChatOut`, `Test.Data.Ownership`, `Test.Data.Tables` and `Test.Web.Api` (warm) pass; `live sign-in` (217 passed), `live floor` (86 passed in the three projects), `live demo-switch`, `live production` and `live demo-path` pass; `shard lane-b` (55 classes) and `shard lane-a` (47 classes) pass. Every mutation in the list was applied, observed red and reverted. No stack with the tags `e4s5i` is left.

**Residual risks / deviations.** (1) D1 at 1280x600 accepts at least 85% of the phone feed in view when the column is shorter than the feed (the Break the feed box leaves it under about 330 px); the stacked screen minimum is `min(360px, 70vh)`. (2) While the snapshot loads the "Skip to simulated devices" link is absent (demo mode unknown), so the loading page keeps the order chat, status, home link. (3) The demo-switch phone spec removes its own chat cards and phone rows in `finally` (the stack's S0 hash comparison would fail otherwise), so the note that README gains two cards per run does not hold. (4) `/state.phone` payloads omit an empty `approvalRef` (the JSON adapter drops it); `TestStatePhone` pins four keys. (5) The initial bundle is 576 kB, over the 500 kB warning budget, under the error level (`test-web-build.sh` passes). (6) The "neither has a response header" clause of `TestThroughNotify` guards Notify's routing and no SimPhoneOut mutation turns it red.
