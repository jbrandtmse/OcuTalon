# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 makes the signed-in page release 1's main page: the user chats with OcuTalon, with each reply's decision, cost and trace link beside a live status rail, and never needs a reload. The remaining stories tell the user plainly why decisions use fixed rules, why checks are late or why the page has lost contact. They also prove that the whole built page meets the accessibility and responsive floor.

## Stories

- Stories 2.1 to 2.9 and 2.13: frame, session and snapshot, commands, turn pipeline, chat, decisions, outcome routing, status rail, Visual Trace (done)
- Story 2.10: Show status banners for a missing key or a stalled heartbeat
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor

## Requirements & Constraints

- **Banners.**
  - The server conditions are a closed set: `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused`, `resetSoon`. Reconnecting and Unreachable are the page's own.
  - Fixed stack order: allowance used up (session), daily cap (online demo), unreachable, no model key, daily cost cap (local), heartbeat stalled, bot in use, reset soon, reconnecting.
  - Only "Reset soon" and "Reconnecting" can be closed. A closed banner returns if its condition gets worse.
  - A banner appears and clears within one live update (2 s) and is announced. The page renders every condition, even one with no producer yet.
  - Text is verbatim from the UX. `{time}` is a page time (the browser's zone and hour format, unsuffixed), never the renderer's instance time. Story 2.10 picks how: the server passes a web-formatted time, or the browser formats the UTC slot (DW-29).
- **No model key.** OcuTalon starts, nothing in the production fails, and decisions fall back with "no model key is set". The no-key CI test stays `notBuilt` until Story 1.6.
- **Cost cap.** On the online demo it is a danger banner with "Install it yourself". Locally it is a warning naming `{cap}`, with no "Budgets" action yet and no chat message. The composer stays usable either way.
- **Heartbeat stalled** (no tick for more than 3 minutes). While it holds, check rows read "Last run {time} (late)".
- **Lost contact.**
  - With no poll answer for 10 s, the closable info "Reconnecting…" banner shows. At 30 s, the unclosable danger banner "Can't reach OcuTalon. Retrying every 10 seconds." replaces it.
  - On recovery, missed content loads in place (the snapshot reloads if a `seq` skipped) and the banners clear.
  - Polling is release 1's only live path. A 401 is Story 2.2's sign-out path, not lost contact.
- **Floor.**
  - Keyboard alone, every control labelled, WCAG 2.1 AA in both themes (4.5:1 for text, 3:1 for interactive boundaries).
  - Text resizes to 200%, colour is never the only signal, nothing animates under `prefers-reduced-motion`, and none of the UX's banned patterns appears.
  - Current desktop Chrome, Edge, Firefox and Safari at 1280×720 and up. A string test checks fixed strings, including the single "…" character.

## Technical Decisions

- **Lane B** owns `Web`, `Core` (`StatusMonitor` is still an Epic 0 stub), `Live`, `Data.StatusMark` and `web/`.
  - Read Lane A only through `Bridge.Keys.Status(agent)` (three agents) and `Bridge.Budget.State()` (spent, cap, capped, resets at; UTC).
  - Edit only Lane B's region of the production XData, and keep the `Test.Contract.Ac` oracle green.
- **One status computation.** `OcuTalon.Live.Payload.Status.Active(sessionRef)` sits outside Core, because Web may not call Core. `/state` calls it on read, and `StatusMonitor` calls it every 15 s.
  - `StatusMonitor` alone publishes `status`, on the instance stream, when a condition changes.
  - The last tick and the Telegram pause come from `StatusMark.Get`.
  - Story 2.2's tests pin `status: []`, and Story 2.10 rewrites them.
- **Events.**
  - Events are written only through `Live.Publish`, after commit, as full views. The page applies them idempotently, polling `/events` every 1 to 2 s, and reloads the snapshot on a `seq` skip.
  - Story 2.11 hooks into Story 2.2's poll-failure path (on a 5xx or network error, the next poll waits the same delay).
  - Tests publish fixture `status` payloads through `Live.Publish`. Connection tests control the page's clock.
- **Text.** Producers never render. The page renders from the generated `catalog.ts` and payload types, which the build checks. README actions use `README_URL` with the section's anchor in place of `#readme`.
- **Tests.**
  - An unbuilt part is a `notBuilt(title, 'N.M')` call. A test that is turned on and must never skip again carries `@floor`.
  - Story 2.12 adds Firefox and WebKit to Playwright 1.64.x.
  - A new library, such as an accessibility scanner, is pinned in `web/` and recorded as a Stack row.
  - IRIS jobs target about 10 minutes each (Epic 32), so watch the `browser` group's time.

## UX & Interaction Patterns

- **Banner:** full width under the header, at least 44px tall. It has a 4px accent and a variant icon (`triangle-alert`, `circle-alert` or `info`), at most one underlined action and an optional close.
- **One polite announcer:** Story 2.1's wrapper over the CDK `LiveAnnouncer`. Story 2.12 adds de-duplication and batching.
  - Each event is announced once, wherever it shows: "OcuTalon replied:" or "Tell now:" plus the first sentence, a reminder's text, a banner's text, or "Message not sent".
  - The user's own messages and timers are silent. More than three announcements in 2 s become "{n} new updates".
  - The chat, rail, turn indicator and timers are not live regions, and none uses `role="log"`.
- **Focus:** only when an update removes the focused element. It moves to the element's replacement, to the section heading when a row leaves its list, or else to the nearest container.
- **Keyboard:**
  - The first tab stops are "Skip to chat" and "Skip to status". Story 4.5 later inserts "Skip to simulated devices" between them.
  - Enter sends and Shift+Enter adds a line. Esc closes the topmost popover or dialog. There are no single-character shortcuts.
  - The focus ring (2px `focus` at a 2px offset, `surface` halo) is never clipped, because every scroller keeps `scroll-gutter`.
  - A control that can't act stays focusable with `aria-disabled`, and its visible reason is linked by `aria-describedby`.
- **Layout:**
  - From 1440px wide, the rail is `rail-width-wide`. From 1280 to 1439px it is `rail-width`, and UJ-1 needs no page scroll.
  - From 1024 to 1279px, the rail becomes a drawer opened from a "Status" header button that shows the approval count.
  - Below 1024px or at 200% zoom, the page is one column: header, banners, chat at `min(70vh, content)`, then status. Only a compact header is sticky.
  - The narrow-window notice shows once per session, and its close is remembered per browser.

## Cross-Story Dependencies

- **Stories 2.10 and 2.11.** Story 2.10's banner stack, in Story 2.1's `.banner-slot`, hosts Story 2.11's banners. Story 2.10 also adds the "(late)" marks to Story 2.8's check rows.
- **Story 2.12** runs last and tests the whole page, including the banners and Story 2.13's trace links, menu and popover. It also owns two ledger items:
  - DW-89: the chat and rail scrollers get a tab stop and a name, checked in WebKit.
  - DW-145: the Visual Trace button closes its own popover in Safari and macOS Firefox. Story 2.1's popover service counts the trigger's press as inside.
- **Lane A.** `Budget.State` arrives in Story 1.4 and `Keys.Status` in Story 1.6; use stub fixtures until then. Story 8.2 computes `heartbeatStalled` from `StatusMark`'s last tick.
- **Later.** Epic 16 produces the allowance, online-cap and reset-soon conditions, and Epic 12 bot-in-use. Step 2 adds "Budgets" and its no-key text, and Story 31.1 the WebSocket. The guide, devices and Telegram card join the stacked layout with their own epics.
