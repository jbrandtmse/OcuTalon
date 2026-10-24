---
title: 'Story 2.12: Meet the accessibility and responsive floor'
type: 'feature'
created: '2026-10-24'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:**
- **Most events are silent.** The page has one polite announcer, Story 2.1's `Announcer`, a thin wrapper over the CDK `LiveAnnouncer`. Only three things use it: the load failure, the busy notice and new banners. A reply, a tell-now card, a reminder card and a failed send say nothing, so a screen-reader user does not hear them.
- **Banners can be lost (DW-153).** Banners that appear in one update are announced 150 ms apart. Each later `announce()` clears the earlier text about 50 ms after it landed, and nothing combines a burst.
- **Focus falls to the page body.** Only the banner stack and the rail follow the focus rule (UX-DR131), each with its own copy of the code. When an update removes any other focused control, focus drops to `body`. Three cases:
  - **Retry sending** when it is pressed;
  - the load error's Retry when the page loads;
  - a rail row's trace-help popover when the row leaves.
- **The story is too large for one implement pass** (Decided 1). This spec keeps its two announcement and focus criteria and DW-153. It splits the other four criteria, with DW-89 and DW-145, word for word into Stories 2.14 to 2.16.

**Approach:**
- **A framework-free queue behind `Announcer`**, `shared/announce-queue.ts`:
  - the messages of one update become one text;
  - texts land at least 1 s apart;
  - no more than three announcements are spoken in any 2 s;
  - beyond that, two or more waiting messages become "{n} new updates", so four or more at once always do.
- **The chat announces its own entries, once each.** A framework-free diff, `chat/chat-announcements.ts`, gives:
  - "OcuTalon replied:" plus the reply's first sentence;
  - "Tell now:" plus the card's first sentence;
  - a reminder card's text.
- **Failures are announced where they happen.** `ChatOutbox` announces "Message not sent". The rail never announces, so an event heard from the chat is not heard again from the rail.
- **One shared focus helper**, `shared/focus-rule.ts`. It replaces the banner stack's and the rail's copies, and it serves the chat and the load error. It acts only when an update removed the element that held focus.
- **Tests:**
  - browser cases A1 to A7 and P1 to P4 under `web/e2e/floor/`, in the chromium project of `live:sign-in`, with a new fixture user;
  - Node tests that pin the queue's timing and the diff.

## Boundaries & Constraints

**Always:**
- **The queue: `web/src/app/shared/announce-queue.ts` (new).**
  - It is framework-free, like `shared/busy-state.ts` and `live/contact-watch.ts`. It imports nothing, uses only erasable TypeScript syntax, and has its timers and clock injected: `setTimeout`, `clearTimeout`, `now` and `speak`.
  - **Its exports:**
    - `ANNOUNCE_MERGE_ABOVE = 3`;
    - `ANNOUNCE_WINDOW_MS = 2000`;
    - `ANNOUNCE_MIN_GAP_MS = 1000` (a new name, so it is not confused with the banner stack's `ANNOUNCE_GAP_MS`, which goes);
    - `NEW_UPDATES = '{n} new updates'`;
    - the class `AnnounceQueue`, with `push(message)` and `dispose()`, and its options type.
  - **The rule (Decided 2 and 3):**
    - `push` trims the message, ignores an empty one, and adds it to the waiting list.
    - The flush runs at the later of now and the last text's time plus `ANNOUNCE_MIN_GAP_MS`. At the soonest that is a 0 ms timer, so everything pushed in one turn of the event loop (one update) flushes together.
    - A flush counts `recent`, the messages spoken in the last `ANNOUNCE_WINDOW_MS`. A text counts as the number of messages it carries.
      - **`recent` + waiting ≤ 3:** the waiting messages are spoken as one text, in push order, joined by a space. A message that does not end in ".", "!", "?" or "…" gets a full stop first.
      - **Otherwise, with two or more waiting:** the text is `NEW_UPDATES`, with n the number waiting.
      - **Otherwise** (one waiting, `recent` ≥ 3): the queue waits until `ANNOUNCE_WINDOW_MS` after the newest spoken message, then flushes again.
    - Every pushed message is spoken once, alone, joined or counted. Nothing is spoken twice, and nothing is dropped.
- **`Announcer` (`web/src/app/shared/announcer.ts`)** stays the page's one root service.
  - It owns one `AnnounceQueue`, built with `globalThis.setTimeout`, `globalThis.clearTimeout` and `performance.now()`.
  - Its `speak` is `LiveAnnouncer.announce(text, 'polite')`.
  - `announce(message)` keeps its signature, and its class doc states the rule.
  - The CDK sets the region's text as text, never as HTML (AD-13).
- **Where each event is announced (one place each).**
  - **`BannerStack`.** Its rule stays: a banner announced is one that appears after the first snapshot. It now passes each new banner's text to `Announcer` at once, in stack order. `ANNOUNCE_GAP_MS`, `waiting`, `gap` and `drain()` go, so one update's banners become one text (DW-153).
  - **`ChatPanel`** runs `chatAnnouncements` over its entries.
    - The first run records the entries and announces nothing.
    - Each later run announces:
      - a turn whose reply has landed (text or fallback) and had not landed at the last run, whether the turn is new or known: `CHAT_TEXTS.announceReplied`, a space, and `firstSentence` of the reply as the page shows it;
      - a tell-now card that is new: `CHAT_TEXTS.announceTellNow`, a space, and `firstSentence` of the card's text;
      - a reminder card that is new: the card's text.
    - Nothing else in the chat is announced: user messages (the page's own, stored, from Telegram or from the guide), Deciding and Working, the seconds, a card updated in place, and a reply that had already landed.
  - **`ChatOutbox`** announces `CHAT_TEXTS.messageNotSent` once for each post that fails. A failure is any answer but 202 or 401, or no answer within `BUSY_TIMEOUT_MS`. A retry that fails is a new failure.
  - **`ServerButton` and `LiveState`** keep their calls, `BUSY_NOTICE` and `LOAD_FAILED`, which now go through the queue.
  - **Silent:** the rail, the header, the turn indicator and every timer announce nothing.
- **The diff: `web/src/app/chat/chat-announcements.ts` (new).**
  - It is framework-free and imports only types.
  - **Its exports:**
    - `firstSentence(text)`;
    - `ChatAnnounceFormat`, which is `{ replyText(replyText): string; fallbackText(catalogKey, fallbackReason): string }`;
    - `chatAnnouncements(heard, entries, format)`, which returns `{ texts, heard }`. `heard` is undefined on the first run. Its record holds the current entries, by view key, with whether each one has landed.
  - **`firstSentence`** (Decided 7):
    - it takes the text up to its first line break;
    - in that, the sentence ends at the first ".", "!", "?" or "…" followed by white space or the end, and keeps that mark;
    - it trims the result;
    - text with no such mark is returned whole, trimmed.
  - **The format's sources, from the real modules.**
    - `replyText` is `plainText(parseReply(text))`. `plainText` is new in `reply-text.ts`: the text of the first block, a paragraph's runs or a list's first item, with each link as its label.
    - `fallbackText` is `replyFallbackText`. This is the fallback-sentence logic of `ocutalon-reply.ts:193-200`, moved into an exported function that the component also calls.
- **Texts.** These are the UX's (E:426-440), each written once:
  - `CHAT_TEXTS.announceReplied: 'OcuTalon replied:'`;
  - `CHAT_TEXTS.announceTellNow: 'Tell now:'`;
  - `CHAT_TEXTS.messageNotSent: 'Message not sent'`;
  - `NEW_UPDATES`.
- **Live regions.**
  - The CDK announcer's element is the page's only `aria-live` element.
  - No element anywhere has `role="log"`, `"status"`, `"alert"`, `"timer"` or `"marquee"`.
  - The chat list, the rail, the turn indicator and the timers stay as they are: none is a live region.
- **The focus rule: `web/src/app/shared/focus-rule.ts` (new).**
  - **The call.** `keepFocus(host, injector, popovers, rule)` is called from a host's effect before the host renders again. It is the pattern of `banner-stack.ts:241` and `status-rail.ts:240`, and it replaces both.
  - **Before the render.**
    - The focused element is `document.activeElement`. When that is inside an open popover's pane, it is the popover's trigger instead (`Popovers.triggerOf`).
    - If that element is not inside the host, or not inside `rule.within` (a selector under the host) when the rule gives one, the call does nothing.
    - Otherwise it records the item: the closest element that matches `rule.item` (a selector), with `rule.keyOf(item)` as its key. It also records the keys of every item in DOM order, and the item element. A rule with no `item` records none.
  - **After the render** (`afterNextRender`), it acts only when focus was lost, that is, `document.activeElement` is null or `body`. Then:
    - the item's key is still there: focus goes to that item element, which is the replacement in place or the nearest container;
    - the key is gone: focus goes to `rule.whenGone(lost)`;
    - when that is null, or there was no item: focus goes to `main.main`.
    - Every move is `focus({ preventScroll: true })`.
  - **The hosts:**
    - **`BannerStack`:** items `[data-banner]`, keyed by that attribute. When the banner is gone: its `REPLACED_BY` replacement, else the next banner, else the previous one. This is Story 2.10's and 2.11's rule, unchanged.
    - **`StatusRail`:** items `[data-row-key]`, keyed by that attribute. When the row is gone: the heading of its `data-section`.
    - **`ChatPanel`:** items `[data-part][data-key]`, keyed `part:key`. When the item is gone: null. So **Retry sending** leaves focus on its message.
    - **`MainPage`:** `within` is `.load-error`, with no item. Focus inside the load error when it leaves goes to `main.main`.
  - **`Popovers.triggerOf(element)` (new)** gives the trigger of the open popover whose pane contains the element, else undefined. `PopoverRef.close()` still does not refocus a trigger that is no longer in the page.
  - **Nothing else moves focus.** An update that leaves the focused element in the page, or that lands somewhere else, changes nothing.
- **Tests.**
  - The browser specs are `web/e2e/floor/announcements.spec.ts` (A1 to A7) and `web/e2e/floor/focus.spec.ts` (P1 to P4).
  - They are chromium project specs, run by `live:sign-in`, signed in as the new fixture user `FLOOR` (`OCUTALON_FLOOR_USER`), over real HTTP.
  - **"One update":** the case holds the in-flight `/events` request with `page.route` while it seeds, then lets it continue (`holdPoll`), all within 8 s.
  - `recordAnnouncements` also records when each text landed, on the page's clock.

**Never:**
- **No server change.** No ObjectScript, REST route, payload, event type, stored property or global; no role or grant; no dependency.
- **No new live region and no new noise.**
  - No component gets an `aria-live` attribute or a log, status, alert or timer role.
  - No toast, modal or sound.
  - No new public text beyond the UX's announcement texts. A joined text adds only a full stop.
- **Nothing else is announced:** the first snapshot, the user's own messages, guide sends, Deciding and Working, the seconds, countdowns, a clear, a card updated in place, or anything from the rail.
- **No focus move** while the focused element is still in the page.
- **Not this story (the split, Decided 1):**
  - Story 2.14: the skip links, the Esc and keyboard rules, labels, the visible reasons for `aria-disabled` controls, colour, 200% text, motion and the banned patterns;
  - Story 2.15: the drawer, the stacked layout and the narrow-window note;
  - Story 2.16: the Firefox and WebKit projects, the scan, the string test, DW-89 and DW-145.
- **Tests:**
  - never stop IRIS or its web server;
  - never hold a poll for 8 s or longer, because Reconnecting shows at 10 s;
  - never run the `Test.Core.*Production`, `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry` or `Test.Demo.Production` classes on slot B.
- **Contended paths are read-only:**
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Install,Schedule,Checks,Eval,Watch}/**`;
  - `Data/Public/**` and `Data/{StatusMark,Time,Reminder}.cls`;
  - `Core/Commands*.cls` and `Msg/Tick.cls`;
  - `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts` and `release/**`;
  - `.github/workflows/lane-a.yml`, `ci/iris.sh` and `ci/warm.sh`;
  - `docker/tests/test-pinned-sources.sh`, `test-production.sh`, `test-ci-warm.sh` and `test-ci-config.sh`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reply | A turn's reply lands, as text or as a fallback | One announcement: "OcuTalon replied: " plus the first sentence the page shows; the user's message and Deciding/Working are silent | A reply already landed at the first snapshot: silent |
| Tell now | A tell-now card and its decision row in the rail | One announcement: "Tell now: " plus the card's first sentence; the rail row adds none | A card updated in place: silent |
| Reminder | A reminder card arrives and its rail row leaves | One announcement: the card's text ("Reminder: stretch.") | — |
| One update, two banners (DW-153) | One poll brings two new banners | One text: both banner texts in stack order, joined by a space | — |
| Burst | Four or more messages waiting at a flush, or two or more when they would pass three in 2 s | One text: "{n} new updates", n the number waiting | n is never below 2 |
| Straggler | One message waiting, three heard in the last 2 s | It waits until 2 s after them, then is spoken alone | Never "1 new updates" |
| Spacing | A second update 200 ms after a text | Its text lands 1 s after the previous one | — |
| Failed send | A post fails, then a retry fails | "Message not sent" each time | A 401 announces nothing (the session gate's) |
| Reload | A skipped `seq` reloads the snapshot | Only entries or replies new since the last view are announced | — |
| Retry sending | Retry pressed (keyboard), the button leaves while the post is out | Focus on its message (`[data-part="user"]`); it stays there when the post fails again, and when the stored turn takes the message over under the same key | — |
| Row leaves with its help open | A rail row's trace-help popover holds focus; the row leaves | Focus on the section heading | — |
| Banner leaves | 2.10/2.11 cases through the shared helper | Replacement, next, previous, else `main.main`, as before | — |
| Load error Retry | Retry loads the page | Focus on `main.main` | A failed Retry keeps focus on Retry |
| Anything else | Focus on the composer or on a row updated in place, while a reply, a card, a row change and a banner arrive | Focus stays where it is | — |

</intent-contract>

## Code Map

**Page (Lane B, edit or new)**
- `web/src/app/shared/announcer.ts:1-13`: the wrapper over the CDK `LiveAnnouncer` that gains the queue.
  - CDK 22.2.3's `announce()` clears the region, cancels a pending message, and sets the text 100 ms later.
  - The region is one `.cdk-live-announcer-element` in `body`, with `aria-live="polite"` and `aria-atomic="true"`.
  - The source is `node_modules/@angular/cdk/fesm2022/_a11y-module-chunk.mjs`.
- `web/src/app/shared/busy-state.ts` and `web/src/app/live/contact-watch.ts`: the sibling pattern for the queue (framework-free, injected timers, callbacks).
- `web/src/app/banners/banner-stack.ts`:
  - `ANNOUNCE_GAP_MS` `:27-30` (goes);
  - the class doc `:32-45`;
  - the effects `:176-194`;
  - `announce` `:202-217` and `drain` `:220-233`;
  - `keepFocus` `:241-266`, which becomes a call of the shared helper.
- `web/src/app/rail/status-rail.ts`:
  - `ROW_KEY` and `ROW_SECTION` `:23-27`;
  - the class doc `:45-54`;
  - the effect `:230-233`;
  - `keepFocus` `:240-261`, which becomes a call of the shared helper.
- `web/src/app/chat/chat-panel.ts`:
  - the class doc `:38-52`, which says "nothing moves focus except the New messages button";
  - the template `:60-90`, with entries tracked by `entry.key`;
  - `since` `:159` and `entries` `:183-198`;
  - the constructor's effects `:201-230`;
  - `showNew` `:254-265`, which is the user's own move and stays.
- `web/src/app/chat/chat-outbox.ts`: `post` `:71-83`, where the failure branch is `:77-80`.
- `web/src/app/chat/user-message.ts:18-28`:
  - the message element (`data-part="user"`, `data-key`, `tabindex="-1"`);
  - "Not sent" and the Retry button, which an `@if` removes.
- `web/src/app/chat/ocutalon-reply.ts`:
  - `FALLBACK_KEY` `:12`;
  - the fallback computed `:193-200`, which moves to the exported `replyFallbackText`;
  - the reply element `:31` (`data-part="reply"`).
- `web/src/app/chat/notice-card.ts:26`: the card element (`data-part="notice"`).
- `web/src/app/chat/reply-text.ts`: `parseReply` `:99`, its block types `:17-23`, and the place for `plainText`.
- `web/src/app/chat/chat-view.ts`:
  - `CHAT_TEXTS` `:25-57`;
  - `noticeOf` `:178-207` (text without "Why now:", and kind);
  - `replyOf` `:225-255`;
  - `chatView` `:269-351`;
  - the view types `:80-144`.
- `web/src/app/live/live-state.ts`: `fail()` `:196-203` (announces `LOAD_FAILED`; unchanged).
- `web/src/app/shared/server-button.ts`: `BUSY_NOTICE` `:10`, announced at `:69` (unchanged).
- `web/src/app/shared/popover.ts`:
  - `PopoverRef` `:18-50` (`close()` skips a disconnected trigger at `:44`);
  - `show` `:64-108`;
  - the `open` set `:61`.
- `web/src/app/shared/trace-link.ts`: the destroy close `:160` and `press` `:164`. `web/src/app/shared/trace-help.ts:26-38`: the help is needed on a local install until it is seen in this tab's session.
- `web/src/app/main-page/main-page.ts:54-79`: `main.main` (`tabindex="-1"`) and `.load-error` with Retry.
- `web/src/app/msg/catalog.ts`: `PAGE_TEXTS` and `renderPageText` `:97`. The file is generated; do not edit it.

**Page tests**
- `web/scripts/fake-clock.mjs:5-33`: gains a `now` getter (Rule 2).
- `web/scripts/busy-state.test.mjs`: the loader `:13-15`, `setup()` `:17-30` and the source guard `:113-118`, which are the pattern for the new Node tests.
- `web/scripts/chat-view.test.mjs:401-455`: the `CHAT_TEXTS` `deepEqual` gains the three keys.
- `web/scripts/` has a test of `reply-text.ts` (`reply-text.test.mjs`), which gains `plainText` cases.
- `web/e2e/support/page.ts:47-72`: `recordAnnouncements`, `announcements` and `announcementCount`.
- `web/e2e/support/api.ts`: `EVENTS` `:12` and `MESSAGES` `:13`, and the place for `holdPoll`.
- `web/e2e/support/iris.ts`:
  - `FixtureKind` `:15` and `fixtureUser` `:18`;
  - `seedTurns` `:306` and `finishTurn` `:389`;
  - `seedDecision` `:442`;
  - `sendItemDecision` `:530` and `sendNotification` `:556`;
  - `cleanFixtureRows` `:575`;
  - `seedReminder` `:760` and `publishReminder` `:89`;
  - `publishStatus` `:723`;
  - `seedApproval` `:613` and `setApprovalState` `:634`.
- Patterns to follow:
  - `web/e2e/chat/notice.spec.ts`: how a tell-now card and its decision are produced; `countFocusins`.
  - `web/e2e/rail/rail.spec.ts`: R7 `:276-298` (a reminder fires: its row leaves and its card arrives), R9 `:391-409`, R14 `:562` and R15 `:589` (row focus).
  - `web/e2e/trace/links.spec.ts`: how a row's trace link opens the sign-in help.
  - `web/e2e/live/live.spec.ts`: L6 `:271` and L7 `:321`, the load error and Retry.
  - `web/e2e/chat/chat.spec.ts`: C4 `:331-480`, the failed post and Retry sending.
- `web/e2e/banners/banners.spec.ts`:
  - the announcement assertions `:197-239`, `:362-375`, `:459-469`, `:514-546`, `:632-636` and `:811-909`;
  - the focus cases B5 `:366-391`, B10 `:557`, B13 `:812-832`, B14 `:871` and B18 `:1120`.
- `docker/tests/test-sign-in.sh`:
  - the header `:2-46`;
  - the fixture loop `:152`;
  - `show_log` `:199`;
  - the variables `:200-236`;
  - the PASS and FAIL labels `:241` and `:247`.
- **Read only:**
  - `web/playwright.config.ts:30-33`: the chromium project runs every spec outside `e2e/demo-path/`, so `e2e/floor/` joins it with no config change.
  - `web/scripts/playwright-projects.test.mjs`: it lists the specs on disk, so the new folder needs no edit.
  - `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md:409-440`: the focus table and the announcement table.

## Tasks & Acceptance

**Execution:** No Task 0. Nothing on the server changes. The CDK's announcer behaviour is read from its installed source (Code Map), and the browser specs follow the existing patterns.

1. `web/src/app/shared/announce-queue.ts` (new): the constants, `AnnounceQueue` and its options, as Boundaries says, each documented. This is the queue.
2. `web/src/app/shared/announcer.ts`: own the queue, speak through `LiveAnnouncer` politely, and replace the class doc. All announcements now share one queue.
3. `web/src/app/banners/banner-stack.ts`: drop `ANNOUNCE_GAP_MS`, `waiting`, `gap` and `drain()`, and announce each new banner's text at once, in stack order. Update the class doc's announcement lines. This fixes DW-153. Its focus code moves in Task 7.
4. `web/src/app/chat/chat-view.ts`: add `announceReplied`, `announceTellNow` and `messageNotSent` to `CHAT_TEXTS`, with the module doc. `web/src/app/chat/reply-text.ts`: add `plainText(blocks)`. `web/src/app/chat/ocutalon-reply.ts`: export `replyFallbackText(catalogKey, fallbackReason)` and use it in the component. These are the texts and their sources, written once.
5. `web/src/app/chat/chat-announcements.ts` (new): `firstSentence`, `ChatAnnounceFormat` and `chatAnnouncements`, documented. This is the chat's announcement policy.
6. `web/src/app/chat/chat-panel.ts`: an effect over `entries()` that runs `chatAnnouncements` with the real format and announces each text, and the class doc's announcement lines. `web/src/app/chat/chat-outbox.ts`: announce `messageNotSent` in the failure branch. These are the chat's announcements.
7. **The one focus rule.**
   - `web/src/app/shared/focus-rule.ts` (new): `keepFocus`, `FocusRule` and `LostFocus`, documented.
   - `web/src/app/shared/popover.ts`: add `triggerOf(element)`, documented.
   - Then the hosts call it:
     - `web/src/app/banners/banner-stack.ts`: `keepFocus` with the banner rule;
     - `web/src/app/rail/status-rail.ts`: `keepFocus` with the heading rule;
     - `web/src/app/chat/chat-panel.ts`: an effect that calls it with the chat rule;
     - `web/src/app/main-page/main-page.ts`: an effect on `live.status()` that calls it for the load error.
   - Each host's class doc follows, and the chat panel's no longer says that only the New messages button moves focus.
8. `web/scripts/fake-clock.mjs`: add `now`. `web/scripts/announce-queue.test.mjs` (new) covers:
   - one message is spoken at 0 ms, once;
   - messages pushed together become one text, in order, with the full stop added only when joined;
   - four pushed together are "4 new updates" and no message text;
   - a second text waits until 1 s after the first;
   - with 2 heard, 2 more within 2 s are "2 new updates";
   - with 1 heard, 2 more are one joined text;
   - with 3 heard, 1 more waits until 2 s after them and is spoken alone, and more that arrive meanwhile join it at that flush;
   - nothing is spoken twice and nothing is dropped over a random sequence (a fixed seed);
   - `dispose()` leaves no timer;
   - the module imports nothing and uses no non-erasable syntax.
9. `web/scripts/chat-announcements.test.mjs` (new) covers:
   - the first run is silent;
   - a reply that lands as text, and as a fallback (with a fake format);
   - a new tell-now card and a new reminder card;
   - a card updated in place, a reply that had already landed, an outbox entry, Deciding, Working and the seconds are all silent;
   - a reload with old and new entries announces only the new;
   - the texts follow the chat's order;
   - `firstSentence` with ".", "!", "?", "…", the end, a line break, an address with dots, and no mark at all;
   - the source guard.

   `web/scripts/reply-text.test.mjs`: `plainText` of a paragraph with a link, and of a list. `web/scripts/chat-view.test.mjs`: the three new `CHAT_TEXTS`.
10. `web/e2e/support/page.ts`: `recordAnnouncements` also records `announcedAt` (`performance.now()` when the text landed), and a new `announcedTexts(page)` returns every text in order. `web/e2e/support/api.ts`: add `holdPoll(page)`, which holds the next `/events` request and returns `release()`, which continues it and unroutes. `web/e2e/support/iris.ts`: add `FLOOR` to `FixtureKind`.
11. `web/e2e/floor/announcements.spec.ts` (new): one header that says what the file pins and needs, and these cases, each signing in as `FLOOR` and recording announcements before it signs in.
    - **A1: a reply.** A running turn is seeded and published. Then `finishTurn` with "zz A1 First sentence here. Second sentence." gives exactly one announcement, "OcuTalon replied: zz A1 First sentence here." Nothing holds the turn's own text, "Deciding" or "Working". With the reply on the page, 3 s more add nothing.
    - **A2: a tell now.** In one held update, a tell-now card arrives with its decision row in the rail. The card is an item decision with outcome tellnow and summary "zz A2 Orders are failing. More.", sent as the N-cases send one. Its decision is published as a `decision` event, as the R-cases publish one. The rail row shows, and exactly one announcement is heard, "Tell now: zz A2 Orders are failing."
    - **A3: a reminder.** A pending reminder row with "zz A3 stretch" shows. In one held update its row leaves (fired) and its card arrives. There is exactly one announcement: the card's text, "Reminder: zz A3 stretch."
    - **A4: two banners in one update (DW-153).** Two conditions that show banners are published in one held update. There is exactly one announcement, the two banner texts in stack order joined by a space. Neither text is heard alone.
    - **A5: a burst.** Two banners and two done turns are published in one held update. There is exactly one announcement, "4 new updates", and none of the four texts.
    - **A6: a failed send.**
      - `/messages` answers 500. Typing a message and pressing Enter gives one "Message not sent".
      - Retry, with the route still answering 500, gives a second one.
      - No announcement holds the typed text, though the message shows in the chat.
      - The route never lets a post through. A post that reached the server would start a turn whose fallback reply lands up to 20 s later (C2), inside a later case's window.
    - **A7: one region, a silent first snapshot, and silent timers.** Before sign-in, the case seeds what the first snapshot will show:
      - a running turn, so its indicator shows;
      - a pending reminder due within a minute, so its countdown ticks every second;
      - a done turn with a reply, and a notice card;
      - the no-key banner, which every page of the stack shows.

      Then:
      - the page has exactly one `[aria-live]` element, the CDK's, with `aria-live="polite"`;
      - it has no `[role=log]`, `[role=status]`, `[role=alert]`, `[role=timer]` or `[role=marquee]`;
      - the chat list, the rail, the indicator and the countdown carry no `aria-live`, `aria-atomic` or `aria-relevant`;
      - after 3 s of ticking, nothing at all has been announced since sign-in.

    Each case clears its conditions and calls `cleanFixtureRows` in `finally`.
12. `web/e2e/floor/focus.spec.ts` (new): one header, and these cases:
    - **P1: Retry sending.**
      - `/messages` answers 500, a message is sent, and Retry sending is focused.
      - The route now holds the next post, and Enter is pressed. While the post is out, the button is gone and focus is on that message's `[data-part="user"]` element, not `body`.
      - The held post is then answered 500. "Not sent" and Retry sending return, and focus stays on the message: nothing moves it back.
      - No post reaches the server, so no turn outlives the case. A turn's fallback reply could land up to 20 s later (C2). The stored turn that takes a message over keeps its key (`chat-view.ts:287-341`), so the same element stays.
    - **P2: a row leaves while its help holds focus.** A rail row with a trace link is seeded. Pressing its Trace link opens the sign-in help with focus inside it. The row then leaves, in its own update, and focus is on that section's heading.
    - **P3: the load error's Retry.** The first `/state` answers 500, so the load error and Retry show. Retry is focused, the route is lifted, and Enter is pressed. Once the page has loaded, focus is on `main.main`.
    - **P4: nothing else moves focus.**
      - With the composer focused, a reply lands, a tell-now card arrives, a rail reminder row leaves and a banner appears. Focus is still on the composer, and a `focusin` counter reads 0.
      - Then, with a check row focused, the check is republished with a new result in place. Focus is still on that row.
13. `docker/tests/test-sign-in.sh`: the floor fixture user `ZzFloor` (user role), its random password, its two variables, its redaction in `show_log`, a header line for Story 2.12's A1 to A7 and P1 to P4, and the PASS and FAIL labels, which end "… and Story 2.12's A1-A7 and P1-P4".
14. **The sweep (shared surfaces).**
    - Search `web/e2e/` for every `announcements(`, `announcementCount(` and `window.announced` reading. Update each case where:
      - two announced texts now arrive in one update and become one text;
      - two texts now come within 1 s, so the second lands later than the case waits;
      - a reply or a card now adds an announcement inside a counted window.

      Check `banners.spec.ts:234-239`, `:464-469` and `:883-895` first.
    - Search `web/src/app/` for every remaining `.focus(` and `afterNextRender`, and record that the shared helper or a user action covers each one.

**Acceptance Criteria:**
- **One announcer (NFR-25, UX-DR132; AD-12, AD-32; DW-153).**
  - **Given** the page receives updates,
  - **when** they are announced,
  - **then:**
    - one polite live region announces each event once, even when it shows in several places:
      - a reply as "OcuTalon replied:" plus its first sentence;
      - a tell-now notice as "Tell now:" plus its first sentence;
      - a reminder as its text ("Reminder: stretch.");
      - a banner as its text;
      - a failure as "Message not sent" or the busy-and-failure notice;
    - my own messages and ticking timers are silent;
    - more than three announcements within 2 seconds are combined into "{n} new updates".

  Tests: A1 to A6, `announce-queue.test.mjs`, `chat-announcements.test.mjs`, and L6 (the busy notice, unchanged).
- **No other live region (UX-DR58, UX-DR132).**
  - **Given** the page shows a reply, a notice card, a running turn's indicator, a ticking countdown and a banner,
  - **when** its live regions are inspected,
  - **then** the chat, the rail, the turn indicator and every timer are not live regions, and none uses `role="log"`.

  Tests: A7, and the per-component checks of C1, N1, D1, R18 and B1 (unchanged).
- **One update is heard whole (DW-153).**
  - **Given** two banners appear in one update,
  - **when** the page announces them,
  - **then** one text carries both, in stack order, and every later text lands at least 1 s after the one before it.

  Tests: A4 and `announce-queue.test.mjs`. The screen-reader check is human-only (Design Notes).
- **The focus rule (NFR-25, UX-DR126, UX-DR131).**
  - **Given** an update removes or replaces the element that has focus,
  - **when** the page applies it, whether it came from me or from another channel,
  - **then** focus moves to its replacement, to the section heading when a row leaves its list, or otherwise to the nearest container; live content never moves focus in any other case.

  Tests: P1 to P4, and B5, B10, B13, B14, B18, R9, R14 and R15 through the shared helper.
- **Integration (Rule 1).**
  - **Given** the real page on a real stack,
  - **when** one poll brings two banners, a reply lands, and updates remove focused controls in the banner stack, the rail, the chat and the load error,
  - **then:**
    - the consumers `BannerStack` and `ChatPanel` speak through `Announcer`'s queue, and the live region receives the texts that A1, A4 and A5 name;
    - `BannerStack`, `StatusRail`, `ChatPanel` and `MainPage` move focus through `focus-rule.ts` as their rules say.

  Tests: A1, A4, A5, P1 to P3, B13 and R9.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-12:** one live path (polling), events applied idempotently, and a reload when a `seq` skips. An announcement is a diff of what the page shows, so a reload announces only what is new. No second poller.
- **AD-13:** untrusted and model text renders as text. The announcer's region takes `textContent`. The CSP stays `script-src 'self'`.
- **AD-32:** the page renders only from `catalog.ts`. A fallback reply's announcement uses the catalog sentence the reply shows.
- **AD-22:** Playwright specs on a throwaway stack, and Node tests in `web/scripts/`.
- **AD-29:** `web/` is Lane B's.
- **AD-33:** no new event type and no new publisher.
- **Conventions:** Angular (one typed API client and one live-event service; standalone components and signals), Text OcuTalon sends, and Tests.

No AC contradicts an AD's Rule.

**Rule 5:** no NFR is unmeasurable. NFR-25's announcement and focus parts are DOM facts and timer values, pinned in the browser and in Node.

**Decided in-stage** (small, reversible, within the intent):

1. **The split.**
   - **Why.** The story holds six criteria and three ledger entries. Its announcement and focus half alone is larger than Story 2.11, which made a 63 KB spec with 14 mutations. Each other criterion is a story's worth of work:
     - the keyboard and labels: skip links, the visible reasons for `aria-disabled`, and the banner and About Close buttons that do not name their object;
     - colour, 200% text and motion: fixed chip heights, the composer's stale height, the About dialog with no scroll, button-styled links, the spinner;
     - the drawer and the stacked layout: none exists, and the UX leaves the drawer's heading, close and count format open;
     - the cross-browser runs with a scan and a string test.
   - **What it does.** This story keeps the first two criteria and DW-153. Three siblings, planned next in this epic, take the rest word for word. No criterion leaves the release, and Epic 2 then has four split children of six.
   - **Story 2.14: Work the whole page by keyboard, with labels and words.** Its criteria are the story's third and fourth, word for word:
     - "**Given** I use only the keyboard **When** I work through the page **Then** every function works: the first tab stops are "Skip to chat" and "Skip to status"; Enter sends and Shift+Enter adds a line; Esc closes the topmost popover or dialog and collapses a disclosure only when focus is inside it; there are no single-character shortcuts; and the focus ring is always visible and never clipped, because every scrolling region keeps `scroll-gutter` (NFR-25, UX-DR11, UX-DR33, UX-DR125) **And** every control has a visible or programmatic label, icon buttons name their action and object, state is text with icons hidden from assistive technology, and a control that can't act stays focusable with `aria-disabled`, its visible reason linked by `aria-describedby` (NFR-25, UX-DR130, UX-DR133)"
     - "**Given** any state on the page **When** it is shown **Then** it never relies on colour alone (every state has a word and every link is underlined), text resizes to 200% without loss because heights are minimums, errors are text beside their cause linked to their field, and under `prefers-reduced-motion` nothing rotates, pulses, shimmers or scrolls smoothly (NFR-25, UX-DR14, UX-DR134, UX-DR135) **And** none of the banned patterns appears: modal notification interruptions, toasts as the only copy, sounds, tabs that switch by themselves, hover-only controls, drag-and-drop as the only way, model-progress bars, celebration effects, or infinite scroll in counted lists (UX-DR129)"
   - **Story 2.15: Lay the page out at every supported width.** Its criterion is the story's fifth, word for word:
     - "**Given** the browser window's size **When** the page lays out **Then** from 1440px wide the rail is `rail-width-wide`; from 1280 to 1439px it is `rail-width` and every UJ-1 control is reachable without scrolling the page, because each region scrolls on its own; from 1024 to 1279px the rail becomes a drawer opened from a "Status" header button that shows the approval request count; below 1024px or at 200% zoom the page becomes one scrolling column (header, banners, the chat scrolling on its own at `min(70vh, content)`, then the status sections) with only a compact header sticky (FR-12, UX-DR20, UX-DR137) **And** in the stacked layout, the info inline notice "This page is designed for a wider window. Everything still works." shows once per session, and its close is remembered per browser (UX-DR35, UX-DR128, UX-DR138)"
   - **Story 2.16: Prove the floor in Chromium, Firefox and WebKit.** It is planned after 2.14 and 2.15, because its scan and its string test cover their surfaces. Its criterion is the story's sixth, word for word, with the two ledger bullets:
     - "**Given** the CI demo-path environment **When** the page tests run **Then** Playwright runs the main page in Chromium, Firefox and WebKit at 1280×720 and 1280×600, an automated accessibility scan finds no unlabelled control and no contrast failure in the light and dark themes, and a string test checks every fixed interface string this epic introduced against the UX, including the single "…" character in "Deciding…", "Working…" and "Reconnecting…" (FR-12, NFR-25, UX-DR8, UX-DR117, UX-DR138)"
     - "- DW-89: The chat list (Story 2.5's `chat-panel`) and the rail scroll on their own with no tab stop, so a keyboard user in WebKit cannot scroll them; each scroller gets a tab stop and a name (for example `tabindex="0"` labelled by its heading), and the WebKit run checks it (ledger; routed by cr 2026-10-22)"
     - "- DW-145: In Safari and macOS Firefox the Visual Trace menu button closes its own open menu, as it does in Chromium: Story 2.1's popover service treats the trigger's own press as the close, and this story's WebKit and Firefox runs check it (ledger; routed by cr 2026-10-24)"
   - **What the siblings' plans start from** (this plan's findings, file:line in the Code Map's files):
     - **2.14:**
       - no skip link exists; the first tab stop is `a.home` (`header.ts:54`), which F3 and F7 pin;
       - Esc and Enter are built and tested;
       - the banner Close and About Close are named only "Close";
       - the conversation link (`header.ts:109-111`) and the busy `ServerButton` are `aria-disabled` with no visible reason;
       - the chip and fallback flag are 22 px fixed heights;
       - the composer's pixel height goes stale on a text resize;
       - the About dialog cannot scroll at 200%;
       - button-styled links and `a.home` are not underlined;
       - the rail uses `--space-3` padding, not its `--status-rail-padding-inline` token;
       - the spinner is covered only by the global reduced-motion rule.
       - Any new label or reason text is a veto-window item unless the UX gives it.
     - **2.15:**
       - the only width rule is `main-page.ts:98`;
       - the UX names the drawer's button ("Status", with the approval count) but not its heading, its close control, its count format or whether it is modal. It does not say what the compact header holds, or the name of the note's Close. Each choice that adds words is a veto-window item.
     - **2.16:**
       - **The CI hosts.** They were set up with Chromium's system packages only (`cloud-init.yaml`: `install-deps chromium`; this is an inference for `ocutalon-ci-b` and `-c`), and the runner user has no sudo. Firefox and WebKit need their packages, which needs an owner action (For the lead).
       - **The scan.** `axe-core` and `@axe-core/playwright` are MPL-2.0, outside `licences_allowed`, so the scan is the project's own:
         - unlabelled controls, from Playwright's own accessible names (`toHaveAccessibleName` or `ariaSnapshot`; Apache-2.0, already a dependency);
         - contrast, from computed styles in `page.evaluate`, against WCAG's formula in both themes, with DESIGN.md's exemptions.
         - Whether `page.evaluate` runs under the page's CSP in Firefox and WebKit is a Task 0 measurement there (inference: it does, since it is not a page script).
       - **The string test** compares the epic's text constants (`CHAT_TEXTS`, `NOTICE_TEXTS`, `DECISION_TEXTS`, `RAIL_TEXTS`, `TRACE_TEXTS`, `BANNER_TEXTS`, `BUSY_NOTICE`, `LOAD_FAILED`, `NEW_UPDATES`, the header's inline strings, and the skip, drawer and note texts of 2.14 and 2.15) with EXPERIENCE.md's quoted texts. Note that the turn indicator shows "Deciding" with animated dots and speaks "Deciding…".
       - **Where the runs go.** A unit of its own (for example `live:floor`, with its own throwaway and deadline), in the shortest group by the balance rule, not inside `live:sign-in`. After this story the local deadline of `live:sign-in` has about 60 to 90 s left (inference).
       - **The subset.** A lean one: about six cases at 1280×720 and 1280×600 in Firefox and WebKit, while Chromium keeps the full suite:
         - the load;
         - the skip links;
         - the Visual Trace menu's toggle (DW-145);
         - the scrollers' tab stops (DW-89);
         - the scan in both themes;
         - one announcement.
       - **The time (inference).**
         - Locally, about 24 runs of 5 to 8 s, plus a stack start and a first browser download that is then cached: about 4 to 5 minutes in all.
         - On the runner, about 2.5 times that: 9 to 12 minutes added to its group.
         - REL-4's 35 minutes holds if the unit joins `shards` (about 9 to 10 minutes on the measured runs) and not `browser` (about 16 minutes). No Rule 5 finding.
       - Also: check in WebKit that an IME-confirming Enter does not send (Story 2.5's residual), and keep trace tabs stubbed in the added browsers (DW-146).
2. **"More than three announcements within 2 seconds"** is read as a rate:
   - the page never speaks more than three announcements in any 2 s;
   - when a flush would pass three and two or more messages wait, they are spoken as "{n} new updates";
   - a single waiting message waits for the window instead, so the page never says "1 new updates", which would be new text.

   The UX gives only the plural form.
3. **The messages of one update are one text, and texts land at least 1 s apart** (DW-153's fix). The CDK replaces its region's text on every `announce()`, so this is the queue's job, not each caller's. With one 0 ms flush, the banner stack, the chat and any failure of the same update join into one text.
4. **One place per event.** Replies and cards are announced from the chat's entries. Banners are announced from the stack, and failures from the control that failed. The rail and the header never announce. That is how "once, even when it shows in several places" holds: the reply's rail decision row, the tell now's rail row and the reminder's leaving row are silent by construction.
5. **The first snapshot is silent, and a reload announces only what is new,** as the banner stack already does (B11). The chat's record holds the current entries, so an entry that a reload drops and brings back would be announced again. The chat cap of 100 never brings an entry back.
6. **A fallback reply is a reply.** Its announcement is "OcuTalon replied:" plus the first sentence of the catalog sentence the reply shows, for example "OcuTalon replied: I couldn't answer that: the model's reply was empty."
7. **First sentence.** This is the text the page shows: the first block, with links as their labels. It runs up to the first line break, and within that up to the first ".", "!", "?" or "…" followed by white space or the end. So "e.g. this" splits after "e.g.", and an address such as "https://a.b/c" does not split.
8. **"Message not sent" is announced by `ChatOutbox` at each failed post,** because each one is an event: the user pressed Send or Retry, and it failed. A 401 stays the session gate's.
9. **The focus rule is one helper, and it acts only on lost focus.** Banners and rail rows keep their own targets. The helper checks `document.activeElement` after the render: a focused element that is still in the page is never moved, which is "live content never moves focus in any other case". Focus inside a popover counts as focus on its trigger, so a row that leaves with its help open is a row that leaves.
10. **Retry sending's replacement is its message.** The button has no replacement, and the message element (`tabindex="-1"`, the New messages button's target) is its nearest container. The stored turn keeps the message's key, so focus stays when the store takes it over.
11. **The load error's Retry goes to `main.main`.** It is the nearest container, and the chat panel that replaces the error holds no single replacement.
12. **The floor specs live in `web/e2e/floor/`,** run by the chromium project in `live:sign-in` with a fixture user of their own. The sign-in unit already holds every Epic 2 case and its fixtures. A unit of their own costs a stack start, and Story 2.16 plans one for the browsers it adds.
13. **"One update" in a test is a held poll.** The case holds the in-flight `/events` request, seeds with synchronous publishes, and then lets it continue, so every event arrives in one answer. Production sends such as a tell-now card wait for the card's event in the server's stream (`sessionEvents`) before the release.
14. **The ids.** The announcement cases are A1 to A7 and the focus cases P1 to P4. Story 2.14's and 2.15's floor cases take letters of their own.

**For the lead (your calls).**
- **Apply the split** to `epics.md` (Decided 1): insert Stories 2.14, 2.15 and 2.16 with the criteria above, word for word, and the sprint keys.
  - This story keeps its title and key.
  - Re-own DW-89 and DW-145 to Story 2.16's key once the tracker has it.
- **An owner item before Story 2.16's implement** (raise it now, so it is ready). The CI hosts need Firefox's and WebKit's system packages, for example `sudo npx -y playwright@1.64.1 install-deps firefox webkit` on `ocutalon-ci-b` and `ocutalon-ci-c`.
  - The other way is to run those browsers in a digest-pinned `mcr.microsoft.com/playwright:v1.64.1-noble` image. That is a new dependency (Apache-2.0), so a veto item. It costs about 2 GB per host and moves the specs' `docker exec` helpers out of reach.
  - Both are inference from the hosts' setup notes. The runner user has no sudo.
- **A human-only check (DW-153):** with VoiceOver (Safari, macOS) and NVDA (Firefox or Chrome, Windows), check that each text is heard once:
  - two banners in one update;
  - a reply;
  - a burst of four.

  File it as `decision-pending note=human=screen-reader check of the announcer`.
- **Rule 20 (your call).** Decided 2 to 4 and 9 constrain Stories 4.4, 4.6, 6.1, 6.4, 8.2, 12.4 and 16.8, which add announcements and focus moves. A Consistency Conventions row would keep them from drifting:

  > "Announcements and focus: the page speaks only through `Announcer` (one polite region): one update's messages as one text, texts at least 1 s apart, at most three announcements in 2 s, two or more waiting beyond that as "{n} new updates"; each event is announced from one place; the first snapshot is silent. Focus moves only when an update removed the focused element, through `shared/focus-rule.ts`."

  No AD amendment is needed.

**Lead's rulings at the spec gate (2026-10-24).** The split is applied in `epics.md` (U5 decide; Stories 2.14, 2.15 and 2.16 added word for word; DW-89 and DW-145 re-owned to 2.16). The Conventions row "Announcements and focus" is written as worded above. DW-153's screen-reader check is filed as a human-only `decision-pending` entry.

**Veto-window items:** none. There is no stored data, role, grant, dependency or new public text. The announcement texts are the UX's, and the joined form adds only a full stop.

**Integration ACs (Rule 1).**
- **`AnnounceQueue` (new):** its consumer is `Announcer`, which `BannerStack`, `ChatPanel`, `ChatOutbox`, `ServerButton` and `LiveState` call.
- **`focus-rule.ts` (new):** its consumers are `BannerStack`, `StatusRail`, `ChatPanel` and `MainPage`.
- **Tests:** A1, A4, A5 and P1 to P3 exercise the real stack, with real polling and the real components.

**Consumed-by:**
- **2.14:** its explained-disabled reasons and field errors may be announced through `Announcer`, and its skip-link targets take focus.
- **2.15:** the drawer's rail keeps the row-heading rule through the helper, and the note's Close returns focus by it.
- **2.16:** checks the announcer and the focus rule in Firefox and WebKit; its string test reads `CHAT_TEXTS` and `NEW_UPDATES`.
- **4.4:** "Step {n} of 5: {step}" and the prompt bar's focus.
- **4.6:** the email decided announcement, and the row focus.
- **6.1 and 6.4:** incident and result announcements, and the answered status's focus (6.2 and 6.3).
- **8.2:** the heartbeat banner, announced once.
- **12.4:** "Telegram paired".
- **16.8:** Reset soon, announced once.

**Consumes:**
- 2.1: `Announcer`, `Popovers` and `main.main`;
- 2.5: the chat panel, the outbox and `CHAT_TEXTS`;
- 2.7: the notice cards;
- 2.8: the rail's focus rule;
- 2.10 and 2.11: the banner stack, its announcements and `REPLACED_BY`;
- 2.13: the trace links and the sign-in help.

**Extend, don't copy (Rule 2).**
- **`focus-rule.ts`** replaces the two copies in `banner-stack.ts` and `status-rail.ts`, and serves the chat and the main page instead of adding two more.
- **`AnnounceQueue`** follows `BusyState`'s and `ContactWatch`'s pattern (framework-free, injected timers) and does not extend either. Each holds a different machine.
- **The banner stack's `drain()` goes into the queue.** It is not kept beside it.
- **`replyFallbackText`** is moved out of `OcutalonReply`, and **`plainText`** extends `reply-text.ts`. Neither is copied.
- **`fake-clock.mjs`** gains `now` for the queue's tests. It is not copied.
- **`holdPoll`** is new. The inline routes of L3, L13 and B19 refuse, fail or delay polls, so none of them does what it does.

**Ledger (Rule 17).**
- DW-153 is addressed by Task 3, the "One update is heard whole" AC and A4. Its screen-reader check is human-only (For the lead).
- **Declined DW-89:** it moves with the cross-browser criterion to Story 2.16 by this plan's split (Decided 1); the lead re-owns it there.
- **Declined DW-145:** it moves with the cross-browser criterion to Story 2.16 by this plan's split (Decided 1); the lead re-owns it there.

## Verification

**IRIS.** This story changes no ObjectScript, so no slot call is needed. If a stage makes one:
- every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`;
- the first call is `iris_server_info` (build 154, port 1991);
- there is one `iris_execute_tests` call per message.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s212i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`.
- `<main checkout>` is the main checkout's absolute path. It is typed only at the prompt, never in a tracked file.
- Run one piece per call with `timeout: 600000`, and end with `teardown` on the same tag and variables.
- `LOCK busy` (exit 75) means contention: wait and run it again.
- QA uses the tag `e2s212q` (stage `qa`), and review uses `e2s212r` (stage `review`).

**Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) Each in its own call: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `bash docker/tests/test-web-build.sh`, `bash docker/tests/test-boundaries.sh`. Expected: exit 0. The new `announce-queue.test.mjs` and `chat-announcements.test.mjs` cases pass, and so do the changed `reply-text.test.mjs` and `chat-view.test.mjs`.
- (loop) Throwaway, one piece per call: `build`; `live sign-in`; `teardown`. Expected:
  - A1 to A7 and P1 to P4 pass, with every other chromium spec (B1 to B19, R1 to R19, L1 to L13 and C1 to C15 among them);
  - B6 and the demo-path "not built" case skip, as before;
  - teardown leaves nothing.
  - **The time budget.** Before this story the unit took about 398 s of the local 540 s deadline. The eleven cases add about 50 to 90 s (inference).
    - CI's 1200 s holds.
    - If a full local run passes 500 s, record the figure here: Story 2.16 then moves `web/e2e/floor/` into its own unit.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway, one piece per call: `build`; `live demo-path`; `live bundle-folder`; `teardown`. Expected: both pass, with the demo path's floor unchanged. Together with `live sign-in`, these are the `browser` group.

**Planned mutations (Rule 19).** For each one: apply it, observe red, restore a byte-identical tree (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| One announcer | `ANNOUNCE_MERGE_ABOVE` = `Infinity` (never merge) | `announce-queue.test.mjs`; A5 |
| One announcer | `chatAnnouncements` announces on its first run | `chat-announcements.test.mjs`; A7 (an announcement at sign-in) |
| One announcer | the reply's whole text instead of `firstSentence` | `chat-announcements.test.mjs`; A1 |
| One announcer | the rail announces a new decision row (one `Announcer` call in `StatusRail`) | A2 (two announcements) |
| One announcer | `ChatOutbox` does not announce the failure | A6 |
| One announcer | the chat announces the user's own message | `chat-announcements.test.mjs`; A6 (the typed text heard) |
| No other live region | `aria-live="polite"` on the chat list | A7 |
| One update is heard whole | the queue flushes each push on its own timer (no batching) | `announce-queue.test.mjs`; A4 (two texts) |
| One update is heard whole | `ANNOUNCE_MIN_GAP_MS` = 0 | `announce-queue.test.mjs` (the second text at once) |
| One update is heard whole | `banner-stack.ts` keeps its 150 ms `drain()` | A4 |
| Focus rule | the helper does not focus the item that is still there | P1 (focus on `body`) |
| Focus rule | `Popovers.triggerOf` returns undefined | P2 |
| Focus rule | `MainPage` does not call the helper | P3 |
| Focus rule | the helper acts whenever focus is in the host, not only when it was lost | P4 (focus leaves the composer) |
| Focus rule | the banner rule drops `REPLACED_BY` | B13 (through the helper) |

**Shared surfaces:**
- **The announcer's output.** One update's messages are now one text, texts land at least 1 s apart, and bursts are "{n} new updates". Every spec that counts announcements (`banners.spec.ts`, and L6, L7 and L11 of `live.spec.ts`) is swept by Task 14.
  - Replies and cards now announce, which can add to a counted window.
  - `recordAnnouncements` gains `announcedAt`; the existing helpers keep their results.
- **`CHAT_TEXTS`** gains three keys (the `deepEqual` in `chat-view.test.mjs`).
- **`fake-clock.mjs`** gains `now`.
- **The focus code of `banner-stack.ts` and `status-rail.ts`** moves to `focus-rule.ts`. B5, B10, B13, B14, B18, R9, R14 and R15 pin it. `Popovers` gains `triggerOf`.
- **`reply-text.ts`** gains `plainText`, and `ocutalon-reply.ts`'s fallback sentence becomes an exported function.
- **`test-sign-in.sh`** gains a fixture user with its variables, redaction, header and labels; `FixtureKind` gains `FLOOR`.
- **The chromium project's spec list** gains `e2e/floor/`. `playwright-projects.test.mjs` reads it from disk.
- **No server surface changes.**

**Every test added or changed passes on a fresh environment, in either order:**
- each case signs in the floor user;
- each holds or routes only its own requests, and `afterEach` unroutes them;
- each publishes only on the floor user's own session stream, clears every condition it turns on in `finally`, and removes its rows with `cleanFixtureRows`;
- no case lets a chat post reach the server (A6 and P1 answer or hold `/messages` in the browser), so no turn of one case replies inside another's window, in either order;
- P2 starts a fresh browser context, so the sign-in help is needed;
- the Node tests use the fake clock only.

**Manual checks (human-only):** DW-153's screen-reader check (For the lead). No agent can run VoiceOver or NVDA.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-24).** The plan halted after planning, as the dispatch asked.
- It reused the committed `epic-2-context.md` (b1116ec) without recompiling it.
- It took Story 2.11 as the continuity context.
- It ran no runtime measurement and started no throwaway. No server code changes.
- **It splits the story (Decided 1).** This spec keeps the announcement and focus criteria and DW-153. Stories 2.14, 2.15 and 2.16 take the other four criteria word for word, and DW-89 and DW-145 move with the cross-browser criterion to 2.16.
- **For the lead:**
  - apply the split to `epics.md`, and re-own DW-89 and DW-145;
  - raise the owner item for the CI hosts' Firefox and WebKit packages before Story 2.16;
  - file DW-153's human-only screen-reader check;
  - optionally, the Conventions row under "For the lead".
