# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 makes the signed-in page release 1's main page on a local or IPM install: the user chats with OcuTalon and sees each reply with its decision, cost and trace link beside a live status rail, without a reload, and the conversation survives a restart. Stories 2.1 to 2.8 built the frame, snapshot, commands, turn pipeline, chat, decisions, outcome routing and rail. The rest threads each conversation in Visual Trace and links every row to it, adds the status and lost-contact banners, and proves the whole page meets the accessibility and responsive floor.

## Stories

- Story 2.1: Lay out the main page frame (done)
- Story 2.2: Keep the session and load its snapshot with live updates (done)
- Story 2.3: Route every command by verb, with origin checks (done)
- Story 2.4: Answer every chat message through the turn pipeline (done)
- Story 2.5: Chat with OcuTalon in the page (done)
- Story 2.6: Show every decision with its reasons and cost (done)
- Story 2.7: Route untrusted items and notifications by outcome (done)
- Story 2.8: Show the status rail (done)
- Story 2.9: Open anything in Visual Trace
- Story 2.10: Show status banners for a missing key or a stalled heartbeat
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor

## Requirements & Constraints

- **Traceable.** A read-only reviewer follows any turn end to end in Visual Trace alone. Link targets: a turn, its user message, decision, agent steps and reply; a decision, the session holding its decision message; a check, its latest run; a reminder, its waiting process; an approval request row, its incident's diagnosis; "Open my conversation", today's thread.
- **Live.** Banners appear and clear within one live update (2 s). Release 1 is snapshot plus polling only (WebSocket: Story 31.1).
- **Banners** come only from the closed catalog (`allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused`, `resetSoon`) and the page's reconnecting (10 s) and unreachable (30 s) states. Stack order: allowance used up, daily cap, unreachable, no model key, daily cost cap, heartbeat stalled, bot in use, reset soon, reconnecting. Only "Reset soon" and "Reconnecting" close; a closed one returns if its condition worsens. `{time}` is page time in the browser's zone, never `Catalog.Render`'s instance-zone time (DW-29).
- **No key, caps.** With no model key OcuTalon starts, every decision falls back, nothing in the production fails, and the banner says how to set a key. A local cost cap shows its banner, sends no chat message, and gets its "Budgets" action only with the step-2 settings page. The composer stays usable. A starting install or the pre-launch demo gets no page state.
- **Text.** Fixed strings exactly as the UX gives them (single "…" character), checked by a string test; plain English, no class names or codes.
- **Accessibility floor.** Keyboard-only use, every control labelled, WCAG 2.1 AA contrast, text to 200% without loss; Playwright in Chromium, Firefox and WebKit at 1280×720 and 1280×600, with an automated scan in both themes.

## Technical Decisions

- **Lanes.** Lane B. Lane A's bridge, `Checks`, `Decision`, `ApprovalRequest` and `BackgroundCheck` are read-only: read through Ownership, ask for missing properties. Edit only Lane B's production XData region; keep `Test.Contract.Ac` green.
- **Threads.** `OcuTalon.Core.Trace.Join` returns the session's thread for the day: its own trace session id, kept on the `Session` row, allocated under a lock on it; a new one at the first turn after midnight in the instance zone. Only channel services call it. `WebChatIn` sets `..%SessionId` and `..%SuperSession` (the session's `TraceRef`) in `OnProcessInput`, after the base clears them, before its first send. Work inside a turn (commands, approvals, notices) joins through the bridge context's `ThreadSessionId`, never `Join`; waiters and incidents clear `..%SessionId`, keeping `SuperSession`. No other header id is ever a session id (its messages vanish from trace views).
  - **DW-74:** a throwaway check settles whether `Commands.Submit` loses the job's `SessionId`; if so, `Join` or the runner restores it.
  - **DW-112:** `Conversation.Rebuild` retries a `SessionBroken` turn as a new `Decide` call under a new `ItemId` derived from the turn's (one decision per item and kind); the broken attempt keeps its `error` fallback row, and the Turn keeps its `ItemId` and links to the retry's decision.
- **Links.** `OcuTalon.Web.TraceLink` alone builds trace URLs, added when `/state` and polling serve payloads carrying `TraceHeaderId` and `TraceNamespace`. Targets: `/ocutalon/trace/ocutalon/`, or `/ocutalon/trace/ocuorders/` (demo mode only). `SESSIONID` = target header id; `PAGE` = ceil(item index ÷ page size), the index counting the thread's headers up to the target plus its event-, rule- and I/O-log rows logged up to the target's creation. Page size and "Show events" are the viewer's own settings, read through one helper per request (defaults 40 and on; public accounts pinned to 100). A decision targets its `TraceSessionId`.
- **Status.** `StatusMonitor` (15 s) publishes a `status` event on the instance stream when a condition changes; `/state` computes the same on read. Key state only from `Bridge.Keys.Status(agent)` for the three agents; cap state only from `Bridge.Budget.State()`. Heartbeat stalled: `StatusMark`'s last tick over 3 minutes old. With the online-demo flag, the daily-cap banner is the danger one and trace links open directly.
- **Recovery.** Events come only from `Live.Publish`, after commit, as full camelCase views keyed by `Ref`; the page applies them idempotently and reloads the snapshot when a stream's `seq` skips.
- **README links** use `README_URL` from `web/src/app/links.ts`, with a section's anchor replacing `#readme`.
- **Bundle.** The initial bundle is just over the 500 kB warning budget; past 550 kB, split or lazy-load (DW-121).
- **Tests.** ObjectScript in `OcuTalon.Test.<Area>` (shard `lane-b`); demo-path specs `web/e2e/demo-path/0<n>-<id>.spec.ts`, an unbuilt part as `notBuilt(title, 'N.M')`, a never-skip test tagged `@floor`. Drive banners with fixture `status` payloads through `Live.Publish` and fixture stub returns; connection tests control the page clock; destructive tests only on throwaway stacks.

## UX & Interaction Patterns

- **Trace links:** an `external-link` icon and underlined "Trace" in `action-ink` caption, beside (never inside) the row's button, opening a new tab with "(opens in a new tab)" in the name. The header's ghost Visual Trace menu holds "Open my conversation in Visual Trace".
- **Sign-in popover (local, IPM).** Until seen this browser session, links are named "Open in Visual Trace (shows sign-in help first)" with `aria-haspopup="dialog"`; the first press or the menu shows "Sign in to Visual Trace" with the UX text, "Don't show this again" (per browser) and an optional "Open Visual Trace". Popovers are non-modal `dialog`s named by their heading, no `aria-modal`, focus on the first control; Esc, an outside press or focus leaving trigger and panel closes and refocuses the trigger (DW-58: the popover service's first browser test).
- **One announcer.** One polite live region announces each event once: "OcuTalon replied:" or "Tell now:" plus the first sentence, a reminder's or banner's text, "Message not sent" or the busy-and-failure notice. Own messages and timers are silent; more than three in 2 s become "{n} new updates". Chat, rail, turn indicator and timers are not live regions; no `role="log"`.
- **Focus** moves only when the focused element is removed or replaced: to its replacement, to the section heading when a row leaves, else to the nearest container.
- **Keyboard.** First tab stops "Skip to chat", "Skip to status"; Enter sends, Shift+Enter adds a line; Esc closes the topmost popover or dialog and collapses a disclosure only from inside; no single-character shortcuts; focus ring never clipped (`scroll-gutter`). Chat and rail scrollers each get a tab stop named by their heading (DW-89).
- **Labels and state.** Icon buttons name action and object; state is text, icons hidden from assistive technology; a control that can't act stays focusable with `aria-disabled` and `aria-describedby` to its visible reason. Never colour alone, links underlined, errors beside their cause, nothing moves under reduced motion.
- **Responsive.** ≥ 1440px: `rail-width-wide`. 1280–1439px: `rail-width`, every UJ-1 control reachable without page scroll. 1024–1279px: the rail is a drawer from a "Status" header button showing the approval request count. Below 1024px or at 200% zoom: one scrolling column (header, banners, chat at `min(70vh, content)`, status), compact sticky header, and once per session "This page is designed for a wider window. Everything still works." (close remembered per browser).
- **Banned:** modal notification interruptions, toast-only copy, sounds, self-switching tabs, hover-only controls, drag-only actions, model-progress bars, celebrations, infinite scroll in counted lists.

## Cross-Story Dependencies

- **Inside the epic.** Story 2.9's links attach to Story 2.6's strips and Story 2.8's rows. Story 2.10's banner mechanism carries Story 2.11's banners and the "(late)" marks on Story 2.8's check rows. Story 2.12 tests the whole page. DW-81 (busy wait and resend end to end) belongs to the Epic 2 burn-down.
- **Lane A not merged.** Use fixtures or Epic 0's stubs: a `Decide` test double sends fixture decision and `AgentStep` messages in the turn's thread until Stories 1.3 and 1.5 merge; `Budget.State` comes in Story 1.4; `Keys.Status` and the no-key CI test in Story 1.6 (turned on by Epic 11).
- **Later:** the real heartbeat condition (Story 8.2); `TelegramIn` calling `Join` (Story 12.6); the online demo's allowance, daily-cap and reset banners and busy check before opening a trace window (Epic 16); "Budgets" (step 2); the WebSocket (Story 31.1).
