# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 makes the signed-in page release 1's main page. The user chats with OcuTalon, sees each reply with its decision, cost and trace link beside a live status rail, and never needs a reload; the conversation survives a restart. Stories 2.1 to 2.9 built the frame, snapshot and polling, commands, the turn pipeline, the chat, decisions, outcome routing, the rail, and Visual Trace's server half (daily thread, item positions, `traceUrl`). What remains: trace links and the Visual Trace menu on the page, the status and lost-contact banners, and the accessibility and responsive floor.

## Stories

- Story 2.1 to 2.8: frame, session and snapshot, commands, turn pipeline, chat, decisions, outcome routing, status rail (done)
- Story 2.9: Open anything in Visual Trace, the server half (done)
- Story 2.10: Show status banners for a missing key or a stalled heartbeat
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor
- Story 2.13: Open Visual Trace from the page (next)

## Requirements & Constraints

- **Trace targets.** A turn opens at its user message, decision, agent steps and reply. A decision opens at its decision message's session, a check at its latest run, a reminder at its waiting process, and an approval row at its incident's trace. "Open my conversation" opens the current day's thread.
- **Sign-in help (local and IPM installs).** Until the popover has been seen in this browser session, trace links are named "Open in Visual Trace (shows sign-in help first)" with `aria-haspopup="dialog"`, and the first press shows "Sign in to Visual Trace". Its "Don't show this again" is remembered per browser, with storage failures tolerated. With the online-demo flag set, links open directly and the popover never shows.
- **Banners.**
  - Server conditions (closed set): `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused`, `resetSoon`.
  - Page-side: Reconnecting (info) after 10 s with no poll answer, replaced at 30 s by Unreachable (danger).
  - A banner appears and clears within one live update (2 s), is announced, and stacks in the UX order. Only "Reset soon" and "Reconnecting" can be closed, and a closed banner returns if its condition worsens.
  - The page renders every condition even before its producer exists.
  - `{time}` is a page time in the browser's zone, never the catalog renderer's instance time. Story 2.10 decides how (DW-29).
- **States.**
  - With no key, OcuTalon starts, every decision falls back with "no model key is set", and nothing in the production fails.
  - With the heartbeat stalled for more than 3 minutes, check rows read "Last run {time} (late)".
  - The daily cap is danger with "Install it yourself" on the online demo. Locally it is a warning naming `{cap}`, with no "Budgets" action yet and no chat message. The composer stays usable either way.
  - On recovery, missed content loads in place.
- **Text.** Fixed strings match the UX exactly, including the single "…" character, and are checked by a string test. Text is plain English with no class names or codes.
- **Floor.** The page works by keyboard alone and every control is labelled. It meets WCAG 2.1 AA in both themes (4.5:1 for text, 3:1 for boundaries) and handles text at 200%. Playwright runs in Chromium, Firefox and WebKit at 1280×720 and 1280×600, with an accessibility scan in both themes.

## Technical Decisions

- **Lane B** owns `Web`, `Core` (including `StatusMonitor`, still an Epic 0 stub), `Live`, `Data.StatusMark` and `web/`.
  - Read Lane A only through `Bridge.Keys.Status(agent)` (three agents) and `Bridge.Budget.State()` (spent, cap, capped, resets-at; UTC).
  - Edit only Lane B's region of the production XData, and keep the `Test.Contract.Ac` signature oracle green.
- **Status.** `StatusMonitor` (every 15 s) alone publishes `status`, on the instance stream when a condition changes. `/state` computes the same conditions on read. The last tick and the Telegram pause come from `StatusMark`.
- **Events.** Events are written only through `Live.Publish`, after commit, and each payload is the entity's full view keyed by `Ref`. The page applies them idempotently, reloads the snapshot when `seq` skips, and never moves focus because of an event. Tests publish fixture payloads, and connection tests control the page's clock.
- **Trace URLs.**
  - `Web.TraceLink` is the only builder; the page never assembles a URL. `/state` and `/events` add `traceUrl` to every payload object with `traceHeaderId` and `traceNamespace`, and leave it out when no trace application serves the namespace. Show a link only where a `traceUrl` exists.
  - `PAGE` divides an index, computed by `Core.Trace.Position` in the production job, by the viewer's own page size. REST code may add no unchecked `Ens` reads.
  - `traceUrl` is added at serve time, so the generated `payloads.ts` lacks it and the client must type it.
- **Trace applications.** `/ocutalon/trace/ocutalon/` and `/ocutalon/trace/ocuorders/` (demo mode only) share the page's sign-in group.
- **Web app.**
  - README links use `README_URL` (`web/src/app/links.ts`) plus the section anchor.
  - The initial bundle is about 503 kB. Split it once it passes 550 kB.

## UX & Interaction Patterns

- **Trace link:** an `external-link` icon plus an underlined "Trace" in `action-ink` caption text. It sits beside the row's button, never inside it, and opens a new tab, with "(opens in a new tab)" in its name.
- **Visual Trace menu:** a ghost header menu button with `external-link`. Its popover holds "Open my conversation in Visual Trace".
  - Popovers are non-modal: `role="dialog"`, named by their heading, with no `aria-modal`. Focus goes to the first control. Esc, an outside press or focus leaving closes the popover and returns focus to the trigger (DW-58).
- **Banners:** full width under the header, at least 44px tall, with a 4px accent, a variant icon, at most one underlined action and an optional close.
- **Announcing and focus:** one polite announcer, and the chat, rail and timers are not live regions. Focus moves only when the focused element goes, to its replacement or to the section heading.
- **Layout:** from 1024 to 1279px the rail is a "Status" drawer. Below that, or at 200% zoom, the page is one column.

## Cross-Story Dependencies

- **Story 2.13** consumes Story 2.9's `traceUrl`, and must:
  - fill the approval and reminder payloads' targets (the incident's trace and the waiter) where the row has one;
  - add today's thread to `/state` for "Open my conversation";
  - settle DW-129: a decision's link opens page 1 of the day's thread, because its `TraceSessionId` is the thread and has no index. A turn's `chat.message` URL is already exact.
- **Stories 2.10 and 2.11.** Story 2.10's banner stack hosts Story 2.11's banners and the "(late)" marks on Story 2.8's rows.
- **Story 2.12** runs last and tests the built page, including Story 2.13's links. It also owns DW-89: tab stops for the chat and rail scrollers in WebKit.
- **Lane A.**
  - `Budget.State` arrives in Story 1.4 and `Keys.Status` in Story 1.6; use stub fixtures until then. The no-key CI test turns on with Story 1.6.
  - Story 8.2 makes the stall real.
  - Until Stories 1.3 and 1.5 merge, tests use `DecideDouble`.
- **Later.**
  - Story 16.1 adds the menu's credential rows, and Story 16.5 the busy check before a trace window.
  - Epic 16 adds the allowance, online cap and reset-soon producers, and Epic 12 the bot-in-use producer.
  - Story 4.7 adds the guide's trace step, step 2 adds "Budgets", and Story 31.1 the WebSocket.
- **The Epic 2 burn-down** owns DW-74, DW-81, DW-126 and DW-128.
