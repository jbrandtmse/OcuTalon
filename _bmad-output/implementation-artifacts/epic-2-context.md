# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 makes the signed-in page release 1's main page: chat with OcuTalon, each reply's decision, cost and trace link, a live status rail, and banners, all without a reload. Only Story 2.12 is left. It proves the whole built page works by keyboard and screen reader, meets AA contrast, and lays out at every supported size in every supported browser.

## Stories

- Story 2.1: Lay out the main page frame (done)
- Story 2.2: Keep the session and load its snapshot with live updates (done)
- Story 2.3: Route every command by verb, with origin checks (done)
- Story 2.4: Answer every chat message through the turn pipeline (done)
- Story 2.5: Chat with OcuTalon in the page (done)
- Story 2.6: Show every decision with its reasons and cost (done)
- Story 2.7: Route untrusted items and notifications by outcome (done)
- Story 2.8: Show the status rail (done)
- Story 2.9: Open anything in Visual Trace (done)
- Story 2.10: Show status banners for a missing key or a stalled heartbeat (done)
- Story 2.11: Say plainly when the page loses contact (done)
- Story 2.12: Meet the accessibility and responsive floor
- Story 2.13: Open Visual Trace from the page (done)

## Requirements & Constraints

- **The floor:** keyboard alone, a label on every control, WCAG 2.1 AA contrast. Not a full audit.
- **Contrast, both themes:** 4.5:1 for load-bearing text; 3:1 for interactive boundaries (inputs, composer, secondary buttons, actionable chips). Decorative `border` and the inactive Break the feed outline are exempt.
- **Browsers:** current desktop Chrome, Edge, Firefox and Safari, at 1280×720 and up. In CI, Playwright runs the main page in Chromium, Firefox and WebKit at 1280×720 and 1280×600, and an automated scan finds no unlabelled control and no contrast failure in either theme.
- **Text** resizes to 200% without loss (heights are minimums). Targets are at least 32px. Every page sets `lang="en"`.
- **Fixed strings** match the UX word for word, with the single "…" character ("Deciding…", "Working…", "Reconnecting…"). A string test checks every fixed string this epic added.

## Technical Decisions

- **Lane B owns `web/`.** Standalone Angular components with signals, the Angular CDK plus custom components (no kit), `DESIGN.md` tokens, and one live-event service (add no second poller).
- **A new library** in `web/`, such as the accessibility scanner, is pinned there and recorded as a Stack row, as the component and QR libraries were.
- **The page's CSP is `script-src 'self'`,** and untrusted text renders as text. An injected scanner has to work under that CSP.
- **Tests:**
  - Playwright 1.64.x specs go under `web/e2e/`.
  - An unbuilt part is a `notBuilt(title, 'N.M')` call. A test that must never skip again carries `@floor`, and a skip never counts as a pass.
  - `web/e2e/demo-path/` holds only UJ-1's step specs, and its summary fails on any other file, so floor specs go elsewhere.
- **"The CI demo-path environment"** is the `browser` group's throwaway stack (`live:demo-path`, `live:sign-in`) with the CI override and the model mock. Story 2.12 adds its Firefox and WebKit projects.
- **CI time:** no IRIS job runs more than about 25% over the mean of the six, and units move between groups whole. A slowest job over about 10 minutes goes to the owner. Extra browsers add time to `browser`.

## UX & Interaction Patterns

- **One polite announcer** announces each event once, wherever it shows:
  - "OcuTalon replied:" or "Tell now:" plus the first sentence;
  - a reminder's text or a banner's text;
  - "Message not sent", or the busy-and-failure notice.

  The user's own messages and timers are silent. More than three announcements in 2 s become "{n} new updates". The chat, rail, turn indicator and timers are not live regions, and none uses `role="log"`.
- **Focus** moves only when an update, from any source, removes or replaces the focused element. It goes to the replacement, or to the section heading when a row leaves its list, or else to the nearest container.
- **Keyboard:**
  - The first tab stops are "Skip to chat" and "Skip to status".
  - Enter sends and Shift+Enter adds a line.
  - Esc closes the topmost popover or dialog, and collapses a disclosure only from inside it.
  - There are no single-character shortcuts.
- **Focus ring:** 2px solid `focus`, a 2px offset and a `surface` halo. It is never clipped, because every scroller keeps `scroll-gutter`. No selected marker uses a ring in the focus colour.
- **Labels:**
  - Landmarks: banner, `main` (the chat), and the region "Status".
  - Icon buttons name their action and object. State is text, and icons are hidden from assistive technology.
  - A control that can't act stays focusable with `aria-disabled`. `aria-describedby` links it to its visible reason.
  - Disclosures are inline `aria-expanded` buttons. Only Visual Trace and README links open new tabs, and they say so.
  - Errors are text beside their field.
- **Never colour alone:** every state has a word, and links are underlined.
- **Reduced motion:** under `prefers-reduced-motion`, nothing rotates, pulses, shimmers or smooth-scrolls.
- **Banned:** modal notification interruptions, toast-only copy, sounds, tabs that switch by themselves, hover-only controls, drag-only actions, model-progress bars, celebrations, and infinite scroll in counted lists.
- **Layout:**
  - From 1440px wide, the rail is `rail-width-wide`.
  - From 1280 to 1439px it is `rail-width`, and UJ-1 needs no page scroll, because each region scrolls on its own.
  - From 1024 to 1279px, the rail becomes a drawer opened from a "Status" header button that shows the approval count.
  - Below 1024px or at 200% zoom, the page is one column: header, banners, chat at `min(70vh, content)`, then status. Only a compact header is sticky.
  - That stacked layout shows the notice "This page is designed for a wider window. Everything still works." once per session. Its close is remembered per browser, and a storage failure is tolerated.

## Cross-Story Dependencies

- **What Story 2.12 builds on:**
  - Story 2.1's announcer, a wrapper over the CDK `LiveAnnouncer`. Story 2.12 adds de-duplication and batching.
  - Story 2.1's skip links, focus ring, drawer button and popover service.
  - Story 2.5's chat: the focus move when **Retry sending** goes, and the `CHAT_TEXTS` strings, which the string test extends. In WebKit, check that an IME-confirming Enter doesn't send.
  - Story 2.8's rail.
  - The banner stack from Stories 2.10 and 2.11. Unreachable replacing Reconnecting is the only banner replacement.
  - Story 2.13's trace links, the Visual Trace menu and the sign-in popover.
- **Ledger items Story 2.12 owns:**
  - DW-89: the chat list and the rail each get a tab stop and a name, for example `tabindex="0"` labelled by the heading. Checked in WebKit.
  - DW-145: in Safari and macOS Firefox, the Visual Trace button must close its own open menu. The popover service must count the trigger's press as inside. Checked in WebKit and Firefox.
  - DW-153: every banner that appears in the same update must be heard. Verify with VoiceOver and NVDA, or announce that update's new banners as one message.
- **Trace tabs stay stubbed in the added browsers.** Real tabs appear to hold licence connections and starve later cases (DW-146, with the burn-down).
- **Later:** Story 4.5 inserts "Skip to simulated devices" between the skip links. Epic 4's guide and devices, and Lane A's Telegram card, join the drawer and stacked layouts in their own epics.
