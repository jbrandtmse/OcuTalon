# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 makes the signed-in page release 1's main page. The user chats with OcuTalon and sees each reply's decision, cost and trace link beside a live status rail, with no reload. The two remaining stories finish it. Story 2.11 tells the user plainly when the page loses contact, then fills in what they missed. Story 2.12 proves the whole page meets the accessibility and responsive floor in every supported browser.

## Stories

- Stories 2.1 to 2.10 and 2.13: frame, session and snapshot, commands, turn pipeline, chat, decisions, outcome routing, status rail, Visual Trace, status banners, trace links (done)
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor

## Requirements & Constraints

- **Lost contact.**
  - After 10 s with no answer from any live path (in release 1, polling only), the closable info banner "Reconnecting… New messages may be delayed." appears.
  - At 30 s, the unclosable danger banner "Can't reach OcuTalon. Retrying every 10 seconds." replaces it.
  - On recovery, missed content loads into place, the snapshot reloads if a stream's `seq` skipped, and both banners clear.
  - Not lost contact: a 401 (sign-out: polling stops, and the page returns to sign-in, or to the splash on the online demo), the online demo's idle stop, and an API 503 (the busy state).
- **Floor.**
  - Keyboard alone, every control labelled.
  - WCAG 2.1 AA in both themes: 4.5:1 for text, 3:1 for interactive boundaries. Decorative borders and the inactive Break the feed outline are exempt.
  - Text resizes to 200%. Colour is never the only signal, and links are underlined.
  - Under `prefers-reduced-motion`, nothing rotates, pulses, shimmers or smooth-scrolls.
  - Banned: modal notification interruptions, toast-only copy, sounds, tabs that switch by themselves, hover-only controls, drag-only actions, model-progress bars, celebrations, and infinite scroll in counted lists.
  - Browsers: current desktop Chrome, Edge, Firefox and Safari, at 1280×720 and up.
- **Strings.** Fixed strings are verbatim from the UX, with a single "…" character. A string test checks every fixed string this epic added.

## Technical Decisions

- **Lane B** owns `web/`, `Web` and `Live`. Both stories are mostly `web/` work.
- **Live path.**
  - One live-event service polls `/events` with session and instance cursors every 1 to 2 s (updates arrive within 2 s), applies full-view events idempotently, and reloads `/state` on a `seq` skip. Add no second poller.
  - The WebSocket comes later, in Story 31.1, and for local installs only. The online demo never opens one.
- **Tests.**
  - Playwright 1.64.x under `web/e2e/`. An unbuilt part is a `notBuilt(title, 'N.M')` call. A test that is turned on and must never skip again carries `@floor`.
  - The connection tests make the server unreachable and control the page's clock.
  - Story 2.12 runs the main page in Chromium, Firefox and WebKit at 1280×720 and 1280×600, with an automated scan for unlabelled controls and contrast failures in both themes. The scanner is pinned in `web/` and recorded as a Stack row.
  - IRIS jobs target about 10 minutes each, so watch the `browser` group's time.

## UX & Interaction Patterns

- **One polite announcer** announces each event once, wherever it shows:
  - "OcuTalon replied:" or "Tell now:" plus the first sentence;
  - a reminder's text or a banner's text;
  - "Message not sent", or the busy-and-failure notice.
  - The user's own messages and timers stay silent. More than three announcements in 2 s become "{n} new updates".
  - The chat, rail, turn indicator and timers are not live regions, and none uses `role="log"`.
- **Focus** moves only when an update removes or replaces the focused element, whatever the update's source. It goes to the replacement, to the section heading when a row leaves its list, or else to the nearest container.
- **Keyboard.**
  - The first tab stops are "Skip to chat" and "Skip to status".
  - Enter sends and Shift+Enter adds a line. Esc closes the topmost popover or dialog, and collapses a disclosure only from inside it. There are no single-character shortcuts.
  - The focus ring is never clipped, because every scroller keeps `scroll-gutter`.
- **Labels.**
  - Icon buttons name their action and object. State is text, and icons are hidden from assistive technology.
  - A control that can't act stays focusable with `aria-disabled`, and `aria-describedby` links it to its visible reason.
  - Errors are text beside their cause.
- **Layout.**
  - From 1440px wide, the rail is `rail-width-wide`. From 1280 to 1439px it is `rail-width`, and UJ-1 needs no page scroll, because each region scrolls on its own.
  - From 1024 to 1279px, the rail becomes a drawer opened from a "Status" header button that shows the approval count.
  - Below 1024px or at 200% zoom, the page is one column: header, banners, chat at `min(70vh, content)`, then status. Only a compact header is sticky.
  - In the stacked layout, the notice "This page is designed for a wider window. Everything still works." shows once per session. Its close is remembered per browser, and a storage failure is tolerated.

## Cross-Story Dependencies

- **Story 2.11** builds on Story 2.2's live-event service and Story 2.10's banner stack, which already orders "unreachable" third and "reconnecting" last.
- **Story 2.12** tests the whole page, including the banners, Retry, and Story 2.13's trace links, menu and popover. It also owns three ledger items:
  - DW-89: the chat and rail scrollers each get a tab stop and a name (for example `tabindex="0"` labelled by the heading), checked in WebKit.
  - DW-145: in Safari and macOS Firefox, the Visual Trace button must close its own open menu. Story 2.1's popover service counts the trigger's press as inside.
  - DW-153: every banner that appears in the same update must be heard. Verify with VoiceOver and NVDA, or announce that update's new banners as one message.
- **Trace tabs.** Story 2.13's link specs stub their trace tabs, because each real tab holds a licence connection (DW-146, with the burn-down). Keep them stubbed in the extra browsers.
- **Later.** Story 4.5 inserts "Skip to simulated devices" between the two skip links. The guide, the devices and the Telegram card join the drawer and stacked layouts with their own epics.
