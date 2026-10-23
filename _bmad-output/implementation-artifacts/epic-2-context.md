# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 makes the signed-in page the main page of release 1 on a local or IPM install. The user chats with OcuTalon and sees each reply with its decision, cost and trace link beside a live status rail, all without a reload, and the conversation survives a restart. Stories 2.1 to 2.8 built the frame, snapshot, commands, turn pipeline, chat, decisions, outcome routing and rail. The rest adds the status and lost-contact banners, proves the page meets the accessibility and responsive floor, and threads each conversation through Visual Trace with a link on every row.

## Stories

- Story 2.1: Lay out the main page frame (done)
- Story 2.2: Keep the session and load its snapshot with live updates (done)
- Story 2.3: Route every command by verb, with origin checks (done)
- Story 2.4: Answer every chat message through the turn pipeline (done)
- Story 2.5: Chat with OcuTalon in the page (done)
- Story 2.6: Show every decision with its reasons and cost (done)
- Story 2.7: Route untrusted items and notifications by outcome (done)
- Story 2.8: Show the status rail (done)
- Story 2.9: Open anything in Visual Trace (stopped: owner decision pending)
- Story 2.10: Show status banners for a missing key or a stalled heartbeat
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor
- Story 2.13: Open Visual Trace from the page (waits on 2.9)

## Requirements & Constraints

- **Live.** A banner appears and clears within one live update (2 s). In release 1 the page stays live through the snapshot plus polling; the WebSocket comes later and never runs on the online demo.
- **Banner catalog.** The set is closed.
  - Server conditions: `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused`, `resetSoon`.
  - Page-side states: "Reconnecting" (info) after 10 s with no poll answer; "Unreachable" (danger, "Retrying every 10 seconds.") replaces it at 30 s.
  - Stack order: allowance used up, daily cap, unreachable, no model key, daily cost cap, heartbeat stalled, bot in use, reset soon, reconnecting.
  - Only "Reset soon" and "Reconnecting" can be closed, and a closed banner returns if its condition gets worse.
  - The page renders every condition's banner, even when its producer comes later.
- **No model key.** OcuTalon starts, every decision falls back with "no model key is set", and nothing in the production fails. The banner uses the release-1 text, not the step-2 text.
- **Daily cap.**
  - On the online demo it is a danger banner with "Install it yourself".
  - On a local install it is a warning naming `{cap}`, with no "Budgets" action until the step-2 settings page, and it sends no chat message.
  - The composer stays usable either way.
- **Heartbeat stalled.** The last tick is more than 3 minutes old. While it holds, check rows read "Last run {time} (late)".
- **Recovery.** When contact returns, missed content loads into place (with a snapshot reload if a stream's `seq` skipped) and the banners clear. A starting install and the pre-launch demo get no page state.
- **Text.** Fixed strings match the UX exactly, including the single "…" character, and a string test checks them. All text is plain English with no class names or codes.
- **Banner times.** A banner's `{time}` is page time in the browser's zone, never the catalog renderer's instance-zone time. Story 2.10 decides whether the server passes a web-formatted time or the browser formats it.
- **Accessibility floor.**
  - The page works by keyboard alone, and every control has a label.
  - Contrast meets WCAG 2.1 AA in both themes: 4.5:1 for text, 3:1 for interactive boundaries.
  - Text resizes to 200% without loss.
  - CI runs Playwright in Chromium, Firefox and WebKit at 1280×720 and 1280×600, plus an automated accessibility scan in the light and dark themes.

## Technical Decisions

- **Lane B owns** `Web`, `Core` (including `StatusMonitor`), `Live`, `Data.StatusMark` and `web/`.
  - Lane A's bridge is read-only. Key presence comes only from `Bridge.Keys.Status(agent)` for the three agents, and cap state only from `Bridge.Budget.State()` (spent, cap, capped, resets-at; UTC).
  - Until Lane A builds those two, test against fixture returns of their Epic 0 stubs.
  - Edit only Lane B's region of the production XData, and keep the `Test.Contract.Ac` signature oracle green.
- **Status.** `StatusMonitor` (15 s) is the only publisher of `status` and `reset` events. It publishes `status` on the instance stream when a condition changes, and `/state` computes the same conditions on read. The last tick and the Telegram pause are read from `StatusMark`.
- **Events.**
  - Events are written only through `Live.Publish`, after commit. Each payload is the entity's full current view, keyed by `Ref`.
  - The page applies events idempotently, reloads the snapshot when `seq` skips, and never moves focus because of an event.
  - Tests drive banners with fixture `status` payloads published through `Live.Publish`. Connection tests control the page's clock.
- **README links** use `README_URL` from `web/src/app/links.ts`, with the section's anchor in place of `#readme`.
- **Bundle.** The initial bundle is just over the 500 kB warning budget. Split or lazy-load once it passes 550 kB or a build fails on the budget.
- **Visual Trace (Stories 2.9 and 2.13).**
  - **The daily thread.** `Core.Trace.Join`, called only by channel services, returns the session's daily thread. The thread id is kept on the `Session` row under a lock, and a new thread starts at the first turn after midnight in the instance zone.
  - **Joining.** `WebChatIn` sets `..%SessionId` and `..%SuperSession` in `OnProcessInput`, after the base clears them and before its first send.
  - **Inside a turn**, work joins through the bridge context's `ThreadSessionId`, never through `Join`. No other header id is ever used as a session id.
  - **Links.** `Web.TraceLink` builds every URL. `SESSIONID` is the target's header id, and `PAGE` is ceil(item index ÷ the viewer's own page size), with defaults 40 and "Show events" on.

## UX & Interaction Patterns

- **Banners** span the full width under the header and are at least 44px tall, with a 4px accent and an icon in the variant's ink (`triangle-alert`, `circle-alert` or `info`). Each has at most one underlined action and an optional close, and is announced.
- **One polite announcer** announces each event once:
  - a reply: "OcuTalon replied:" plus its first sentence;
  - a tell-now notice: "Tell now:" plus its first sentence;
  - a reminder or a banner: its text;
  - a failure: "Message not sent" or the busy notice.

  The user's own messages and timers are silent, and more than three announcements in 2 s become "{n} new updates". The chat, rail, turn indicator and timers are not live regions, and none uses `role="log"`.
- **Focus** moves only when the focused element is removed or replaced: to its replacement, to the section heading when a row leaves, otherwise to the nearest container.
- **Keyboard.**
  - The first tab stops are "Skip to chat" and "Skip to status". Enter sends; Shift+Enter adds a line.
  - Esc closes the topmost popover or dialog, and collapses a disclosure only when focus is inside it. There are no single-character shortcuts.
  - Every scroller keeps `scroll-gutter`, so the focus ring is never clipped.
  - The chat and rail scrollers each get a tab stop named by their heading (WebKit).
- **Labels and state.**
  - Icon buttons name their action and object.
  - State is text, and icons are hidden from assistive technology.
  - A control that can't act keeps focus with `aria-disabled`, and `aria-describedby` points to its visible reason.
  - Nothing relies on colour alone, and links are underlined.
  - Under reduced motion, nothing moves.
- **Responsive layout.**
  - From 1440px wide the rail is `rail-width-wide`.
  - From 1280 to 1439px it is `rail-width`, and every UJ-1 control is reachable without scrolling the page.
  - From 1024 to 1279px the rail becomes a drawer opened from a "Status" header button that shows the approval count.
  - Below 1024px or at 200% zoom the page is one scrolling column with the chat at `min(70vh, content)` and only a compact header sticky. The note "This page is designed for a wider window. Everything still works." shows once per session, and its close is remembered per browser (storage failures tolerated).
- **Banned:** modal notification interruptions, toast-only copy, sounds, tabs that switch by themselves, hover-only controls, drag-only actions, model-progress bars, celebrations, and infinite scroll in counted lists.

## Cross-Story Dependencies

- **Within the epic.**
  - Story 2.10's banner stack carries Story 2.11's banners and the "(late)" marks on Story 2.8's check rows.
  - Story 2.12 tests the page as built.
  - Story 2.9 is stopped until the owner rules on AD-26: whether `PAGE`'s item index counts rows Visual Trace doesn't draw.
  - Story 2.13 uses Story 2.9's `traceUrl` and follows it.
  - DW-74 and DW-81 belong to the Epic 2 burn-down.
- **From Lane A.**
  - `Budget.State` lands in Story 1.4 and `Keys.Status` in Story 1.6; the no-key CI test turns on when Story 1.6 merges.
  - Story 8.2 makes the stalled condition come from the real heartbeat.
  - Story 2.9 uses a `Decide` test double until Stories 1.3 and 1.5 merge.
- **Later.**
  - Epic 16 brings the allowance, online daily-cap and reset-soon producers, and the busy check before opening a trace window.
  - Epic 12 brings the bot-in-use producer.
  - Step 2 adds "Budgets".
  - Story 31.1 adds the WebSocket and its half of the connection test.
