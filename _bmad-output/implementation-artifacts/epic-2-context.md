# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 turns the signed-in page into release 1's main page on a local or IPM install: the user chats with OcuTalon and sees each reply with its decision, cost and trace link, beside a live status rail, without a reload. With the chat, turn pipeline and outcome routing done (Stories 2.1 to 2.7), the remaining stories finish the page: the status rail, Visual Trace threading and links, the status and lost-contact banners, and the accessibility and responsive floor the whole page must meet.

## Stories

- Story 2.1: Lay out the main page frame (done)
- Story 2.2: Keep the session and load its snapshot with live updates (done)
- Story 2.3: Route every command by verb, with origin checks (done)
- Story 2.4: Answer every chat message through the turn pipeline (done)
- Story 2.5: Chat with OcuTalon in the page (done)
- Story 2.6: Show every decision with its reasons and cost (done)
- Story 2.7: Route untrusted items and notifications by outcome (done)
- Story 2.8: Show the status rail
- Story 2.9: Open anything in Visual Trace
- Story 2.10: Show status banners for a missing key or a stalled heartbeat
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor

## Requirements & Constraints

- **Live.** Rows and banners change within one live update through the snapshot plus polling, release 1's only live path. CI checks the 2 s bound against the mock; the 19-of-20 figures over real networks belong to the rehearsal.
- **Rail.** Pending approval requests, background checks, pending reminders and the session's 20 newest decisions, plus a Telegram section only when the release includes Telegram. After live events the rail holds exactly what a reload would, so Recent decisions stays capped at 20.
- **Banners.** Only from the closed status catalog (`allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused`, `resetSoon`) and the page's own reconnecting and unreachable states. They stack in the UX catalog's order; only "Reset soon" and "Reconnecting" close, and a closed one returns if its condition worsens. A banner's `{time}` is a page time in the browser's zone, never `Catalog.Render`'s instance-zone time (DW-29).
- **Text.** Plain English, no class names or error codes. Fixed strings match the UX exactly, including the single "…", and a string test checks every fixed string this epic added.
- **Security.** Model and arriving text render only as text (no HTML, no `bypassSecurityTrust*`, CSP `script-src 'self'`). No endpoint accepts a `SessionRef`; REST reads go through `Data.Ownership`, and an unseen `Ref` answers 404. Unchecked prepares only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows`. No key, pairing code or Telegram identity in any message, log or event.
- **Accessibility floor.** Keyboard-only use, a label on every control, WCAG 2.1 AA contrast in both themes; verified in Chromium, Firefox and WebKit at 1280×720 and 1280×600 with an automated scan.

## Technical Decisions

- **Lanes.** This is Lane B. Lane A's `Bridge`, `Checks`, `Watch`, `Decision`, `ApprovalRequest` and `BackgroundCheck` are read-only: read through Ownership, keep no copies, ask for missing properties. Edit only Lane B's production XData region and keep `Test.Contract.Ac` green. The rail's Telegram card is its own component under `web/src/app/rail/telegram-card/` (Lane A's from Epic 12).
- **Live events.** Write only through `Live.Publish`, after commit, never in a transaction; each payload is the entity's full view keyed by `Ref` (camelCase), never a delta. One publisher per type: `BridgeSink` for `decision`, `approval` and `turn.step`; Lane A's `Checks` for `check`; `ReminderOps` and `ReminderTimer` for `reminder`; `StatusMonitor` for `status` (instance stream); `WebChatOut` for `notification`.
- **Approvals.** `BridgeSink` reads each `approval.*` event's `ApprovalRequest` through Ownership and publishes to the owning session, or for an `instance` incident to each session `Session.Recipients` returns. It never fails its caller and waits at most 1 s on a lock. `Recipients` reads watchers in a production job, not the REST request; a failed read is loud, never "nobody watches" (DW-68).
- **Status conditions.** `/state` computes them on read; `StatusMonitor` publishes each change every 15 s. Key state only from `Bridge.Keys.Status(agent)` for the three agents, cap state only from `Bridge.Budget.State()`. Heartbeat stalled means `StatusMark`'s last tick is over 3 minutes old.
- **Visual Trace.** One thread per session per day from `Core.Trace.Join`, which only channel services call. Work inside a turn, commands included, joins through the bridge context's `ThreadSessionId`, and no other header id is ever a session id (DW-74: does `Commands.Submit` lose the job's `SessionId`?). `Web.TraceLink` alone builds URLs, from payloads' `TraceHeaderId`/`TraceNamespace`, into OcuTalon's own trace apps (`/ocutalon/trace/ocutalon/`, `/ocutalon/trace/ocuorders/` in demo mode), reading the viewer's page size through one helper.
- **Telegram in release 1.** `Telegram.In.Included()` returns 0, so no Telegram section and no README Telegram link; tests turn it on with `^OcuTalonTest("TelegramIncluded")`.
- **README links.** Use `README_URL` from `web/src/app/links.ts`; a section link replaces `#readme` with its anchor.
- **Tests.** ObjectScript in `OcuTalon.Test.<Area>` (shard `lane-b`); demo-path specs `web/e2e/demo-path/0<n>-<id>.spec.ts`, an unbuilt part as `notBuilt(title, 'N.M')`, a never-skip test tagged `@floor`. Drive rows and banners with fixture rows and payloads sent through `Live.Publish`; destructive tests only on throwaway stacks.

## UX & Interaction Patterns

- **One announcer.** A single polite live region speaks each event once, wherever it shows. The chat, rail, turn indicator and timers are not live regions, and none uses `role="log"`.
- **Focus** moves only when the focused element is removed or replaced: to its replacement, to the section heading when a row leaves its list, else to the nearest container.
- **Trace links** sit beside a row's button, never inside it, open a new tab and say so. On a local install the first press shows the sign-in popover; popovers are non-modal and return focus to their trigger.
- **States.** Every state has a word and an icon, links are underlined, colour is never the only signal. A control that can't act stays focusable with `aria-disabled`, its visible reason linked by `aria-describedby`. Under `prefers-reduced-motion`, nothing moves.
- **Layout.** Each region scrolls on its own, keeps `scroll-gutter` and has a named tab stop (DW-89). The rail keeps a fixed section order and never collapses by itself; below 1280px it becomes a drawer, then part of one stacked column.
- **Persistence.** Per-browser state in local storage, failures tolerated.
- **Banned:** modal notifications, toast-only copy, sounds, self-switching tabs, hover-only controls, drag-only actions, model-progress bars, celebrations, infinite scroll in counted lists.

## Cross-Story Dependencies

- **Built:** Stories 2.1 to 2.7's work is in the code; reuse its popover service, banner slot, `live-store` and test helpers (`DecideDouble`, `ConversationProbe`, `InProduction`).
- **Inside the epic.** Story 2.8's decision rows consume Story 2.6's `decision` events. Story 2.9's `TraceLink` serves every row Stories 2.6 and 2.8 render, and its Visual Trace menu gives the popover service its first browser test (DW-58). Story 2.10's banner mechanism carries Story 2.11's two banners and the "(late)" marks on Story 2.8's check rows. Story 2.12 tests the whole page. DW-81 (`Busy` end to end) belongs to the Epic 2 burn-down.
- **Lane A has not merged.** Test against fixtures or Epic 0's stubs. Real paths turn on with: decisions, Story 1.3; agent steps and threads, Story 1.5; `Budget.State`, Story 1.4; `Keys.Status` and the no-key CI test, Story 1.6; approvals, Stories 3.4 and 3.5; a replayed tool call's `approval.result`, Story 30.3; `check` events, Epic 5; `Included()`, Story 12.7.
- **Later Lane B work:** the real heartbeat condition (Story 8.2), reminders firing (Epic 8), incident and approval cards (Epic 6), the online demo's allowance, daily-cap and reset flows (Epic 16), the Telegram session side (Story 10.3), and the WebSocket (Story 31.1).
