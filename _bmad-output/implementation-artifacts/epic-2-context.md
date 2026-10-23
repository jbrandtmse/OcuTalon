# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 turns the signed-in page into release 1's main page on a local or IPM install. A user chats with OcuTalon and sees each reply with its decision, cost and trace link, next to a live status rail of approval requests, background checks, reminders and recent decisions, all without a reload. Stories 2.1 to 2.6 built the frame, the session snapshot and polling, command routing, the turn pipeline, the chat and the decision strip. The remaining stories add four things:

- the rest of Lane B's production core: untrusted intake, outcome routing and notification fan-out;
- the status rail and Visual Trace links on every turn, decision, check, reminder and approval request;
- the status and lost-contact banners;
- the accessibility and responsive floor the whole page must meet.

## Stories

- Story 2.1: Lay out the main page frame (done)
- Story 2.2: Keep the session and load its snapshot with live updates (done)
- Story 2.3: Route every command by verb, with origin checks (done)
- Story 2.4: Answer every chat message through the turn pipeline (done)
- Story 2.5: Chat with OcuTalon in the page (done)
- Story 2.6: Show every decision with its reasons and cost (done)
- Story 2.7: Route untrusted items and notifications by outcome
- Story 2.8: Show the status rail
- Story 2.9: Open anything in Visual Trace
- Story 2.10: Show status banners for a missing key or a stalled heartbeat
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor

## Requirements & Constraints

- **Outcomes.**
  - Only Tell now and Act notify. Ignore only records the decision, and Digest forwards the item to `DigestStore` without notifying anyone.
  - A message the user writes is always answered, never ignored or digested.
- **Untrusted content.** Mail, webhooks and check findings never enter the user's conversation. On `act`, such an item gets a read-only turn with provenance `untrusted` in a `fresh` session. Anything more is offered to the user, never done.
- **Evaluation.** An item owned by `eval` goes only to `EvalSink`. It creates no `Notification`, no `Delivery` row and no live event.
- **Timing.** CI checks these against the mock on every run:
  - live content reaches the page within 2 s;
  - a tell-now notice reaches the web chat within 5 s of its decision.

  The 19-of-20 figures over real networks are measured in the rehearsal, not in CI.
- **Text.**
  - Plain English, with no class names or error codes.
  - Fixed strings match the UX catalog exactly, including the single "…" character.
- **Times.**
  - UTC ISO 8601 in storage, slots and the API.
  - Message text uses the instance's zone through `Data.Time`, adding " ET" only on the online demo.
  - The page uses the browser's zone with no suffix. A page time beside message text adds the browser's zone abbreviation when it differs from the instance's.
  - Banner times are page times. Story 2.10 decides how (DW-29): pass a web-formatted time, or format the time in the browser.
- **Security.**
  - Arriving text and model text render only as text. Nothing writes HTML or calls `bypassSecurityTrust*`, and the CSP is `script-src 'self'`.
  - No endpoint accepts a `SessionRef`. Every REST read goes through `Data.Ownership`, and an unseen `Ref` answers 404.
  - The signed-in user holds no SQL grant, so unchecked prepares are allowed only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows`.
  - No key, pairing code or Telegram identity appears in any message, log or event.
- **Accessibility floor.** Full keyboard use, a label on every control, and WCAG 2.1 AA contrast in both themes, in Chromium, Firefox and WebKit at 1280×720 and 1280×600.

## Technical Decisions

- **Lanes.** Lane B owns:
  - the packages `OcuTalon.Web`, `.Channel` (except `.Channel.Telegram` from Epic 12), `.Core`, `.Schedule`, `.Live`, `.Msg` and `.Data.{Time,Setting,Ownership,Public}`;
  - the tables `Session`, `Turn`, `Delivery`, `Reminder`, `StatusMark`, `Pairing` and `Live.Event`;
  - the folders `web/`, `docker/` and `ci/`.

  Lane A's `Bridge`, `Checks`, `Watch`, `Decision`, `ApprovalRequest` and `BackgroundCheck` are read-only to this epic:
  - Read bridge rows through Ownership and keep no copies.
  - Ask for a missing property instead of adding it.
  - Edit only Lane B's region of the production XData, and keep `Test.Contract.Ac` green.
- **Routing.** `OutcomeRouter` and `Notify` are routing-rule items that route only on named properties. Producers never render text: a `Notification` carries a catalog key and slots, never finished wording.
- **Delivery.**
  - Only `*Out` operations render, and only through `Msg.Catalog.Render(key, slots, channel)`.
  - Each operation records one `Delivery` row per session's copy through `Delivery.Record`. `FindByApproval(approvalRef, channel, ownerRef)` finds the copy to edit in place.
  - Story 2.7 implements both methods, and `WebChatOut` is their first writer. For a reply, `WebChatOut` only records the row, because the page shows replies from `chat.message`.
- **Live events.**
  - Write events only through `Live.Publish`, after the commit and never inside a transaction.
  - Each payload is the entity's full view, keyed by its `Ref` in camelCase, never a delta.
  - Each type has one publisher:

    | Type | Publisher |
    | --- | --- |
    | `notification` | `WebChatOut` |
    | `decision`, `approval`, `turn.step` | `BridgeSink` |
    | `check` | Lane A's `Checks` |
    | `reminder` | `ReminderOps`, `ReminderTimer` |
    | `status` | `StatusMonitor`, on the instance stream |

  - The snapshot's `chat` is the newest 100 entries, oldest first, with notice cards merged in by time.
  - Polling is release 1's only live path: one cursor per stream, every 1 to 2 s. The page reloads the snapshot when a stream's `seq` skips.
- **BridgeSink and approvals.**
  - `BridgeSink` publishes each `approval.*` event to the owning session's stream. For an `instance` incident it publishes to each session that `Session.Recipients` returns.
  - It never fails its caller and waits at most 1 s on any lock.
  - `Recipients` must read the watchers in a production job, not in the REST request. A failed read is loud, never treated as "nobody watches" (DW-68).
- **Status conditions** come from a closed catalog: `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused` and `resetSoon`.
  - `/state` computes them on read, and `StatusMonitor` publishes each change every 15 s.
  - Key state comes only from `Bridge.Keys.Status(agent)` and cap state only from `Bridge.Budget.State()`.
  - The last heartbeat tick is kept in `StatusMark`. The heartbeat counts as stalled when that tick is more than 3 minutes old.
- **Visual Trace.**
  - Each session has one thread per day, from `Core.Trace.Join`, which only channel services call.
  - Work inside a turn, commands included, joins the turn's thread through the bridge context's `ThreadSessionId`. It never calls `Trace.Join` again.
  - `Web.TraceLink` is the only builder of trace URLs. Each row a link targets stores the header id it needs: the turn, `Decision.TraceSessionId`, a check's latest run, or a reminder's waiter. An approval request row links to its incident's trace.
  - The page size comes from the viewer's own Visual Trace settings, read through one helper. The installer pins the public accounts to 100.
- **Telegram in release 1.** `Telegram.In.Included()` returns 0, and tests turn it on with `^OcuTalonTest("TelegramIncluded")`.
- **Links.**
  - Every README link uses `README_URL` from `web/src/app/links.ts`. A section link replaces `#readme` with the section's anchor.
  - Trace links go to OcuTalon's own trace applications: `/ocutalon/trace/ocutalon/` and, with demo mode on, `/ocutalon/trace/ocuorders/`.
- **Tests.**
  - ObjectScript tests go in `OcuTalon.Test.<Area>`, in shard `lane-b`. Mock scenarios go under `ci/mock/scenarios/B/`.
  - Demo-path specs are `web/e2e/demo-path/0<n>-<id>.spec.ts`. An unbuilt part is a `notBuilt(title, 'N.M')` call, and a test that must never skip again is tagged `@floor`.
  - Destructive tests run only on throwaway stacks.

## UX & Interaction Patterns

These cross-cutting rules apply to every story, not only Story 2.12, which tests them:

- **One announcer.** A single polite live region speaks each event once, even when the event shows in several places. The chat, the rail, the turn indicator and the timers are not live regions, and none uses `role="log"`.
- **Focus moves only when the focused element is removed or replaced.** It goes to the replacement, to the section heading when a row leaves its list, or else to the nearest container.
- **Trace links.**
  - A trace link sits beside a row's button, never inside it. It opens a new tab and says "(opens in a new tab)" in its name.
  - On a local install, the first press shows the "Sign in to Visual Trace" popover. Whether it has been seen is kept per browser session, and "Don't show this again" is kept per browser.
  - Popovers are non-modal, close on Esc, an outside press or focus leaving, and return focus to their trigger.
- **States and controls.**
  - Every state has a word and an icon; colour is never the only signal.
  - Every link is underlined.
  - A control that can't act stays focusable with `aria-disabled`, and its visible reason is linked by `aria-describedby`.
  - Server buttons go `aria-busy` while they wait.
  - Under `prefers-reduced-motion`, nothing moves.
- **Layout.** Each region scrolls on its own and keeps `scroll-gutter`. The rail has a fixed section order, and it never collapses by itself.
- **Persistence.** Per-browser state lives in local storage, with failures tolerated.
- **Banned:** modal notifications, toast-only copy, sounds, tabs that switch by themselves, hover-only controls, drag-only actions, model-progress bars, celebrations, and infinite scroll in counted lists.

## Cross-Story Dependencies

- **Built so far (Stories 2.1 to 2.6; read the code).**
  - The frame, its popover service and the banner slot.
  - `Ownership` and `Session.Recipients`.
  - `/state`, polling and `live-store`.
  - `CommandsIn`.
  - `WebChatIn`, which deduplicates on `clientId`, applies the allowance and sends to `Conversation`. `Conversation` publishes `chat.message` and sends an `Outbound`, carrying its `DecisionRef`, to `Notify`.
  - The chat and its decision strip.
  - `BridgeSink`, which publishes `decision` and `turn.step` events and does nothing yet for `approval.*`.
  - Test helpers: `DecideDouble`, `ConversationProbe` and the `InProduction` base.
- **Inside the epic.**
  - **Story 2.7:**
    - its notice cards join the chat list and the capped snapshot (DW-62);
    - it puts `DecideDouble` in a throwaway production to prove `Busy` end to end through the real `Ens.Alarm` (DW-81).
  - **Story 2.8:** its decision rows consume the `decision` events from Story 2.6 and show only the 20 newest.
  - **Story 2.9:**
    - `TraceLink` serves every row that Stories 2.6 and 2.8 render;
    - its Visual Trace menu gives the popover service its first browser test (DW-58);
    - it settles whether `Commands.Submit` loses the calling job's `SessionId` (DW-74).
  - **Story 2.10:** its banner mechanism carries Story 2.11's two banners and the "(late)" marks on Story 2.8's check rows.
  - **Story 2.12:** it covers the whole page: the announcer, focus replacement, the drawer and stacked layouts, the Firefox and WebKit runs, scroller tab stops (DW-89), the accessibility scan and the string test.
- **Lane A has not merged.** Test against fixtures or Epic 0's stubs. The real paths turn on with these Lane A stories:

  | Lane A path | Turns on with |
  | --- | --- |
  | Real decisions | Story 1.3 |
  | Agent steps and threads | Story 1.5 |
  | `Keys.Status`, and with it the no-key CI test | Story 1.6 |
  | `Budget.State` | Story 1.4 |
  | Approvals | Stories 3.4 and 3.5 |
  | A replayed tool call's `approval.result` | Story 30.3 |
  | `check` events | Epic 5 |
  | `Included()` | Story 12.7 |

- **Later Lane B work.**
  - Story 4.5: `SimPhoneOut`, which turns on the phone half of the 5 s check.
  - Story 8.2: the real heartbeat condition.
  - Epic 8: reminders firing.
  - Epic 6: incident and approval cards.
  - Epic 16: the online demo's allowance and daily-cap flows.
  - Story 10.3: the Telegram session side, including the `pairing` route.
  - Story 31.1: the WebSocket.
