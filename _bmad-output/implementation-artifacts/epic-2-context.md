# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 turns the empty signed-in page into release 1's main page on a local or IPM install. Every message gets exactly one reply, in order, with a plain-English fallback when the model fails, and each reply shows its attention decision with reasons, confidence, cost and a Visual Trace link. A status rail lists approvals, checks, reminders and recent decisions, kept current without a reload, and everything survives a restart. Behind the page the epic builds Lane B's production core: command routing, the turn pipeline, untrusted intake, outcome and notification routing, the bridge event sink, status conditions and the trace-link builder.

## Stories

- Story 2.1: Lay out the main page frame (done)
- Story 2.2: Keep the session and load its snapshot with live updates (done)
- Story 2.3: Route every command by verb, with origin checks (done)
- Story 2.4: Answer every chat message through the turn pipeline (done)
- Story 2.5: Chat with OcuTalon in the page
- Story 2.6: Show every decision with its reasons and cost
- Story 2.7: Route untrusted items and notifications by outcome
- Story 2.8: Show the status rail
- Story 2.9: Open anything in Visual Trace
- Story 2.10: Show status banners for a missing key or a stalled heartbeat
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor

## Requirements & Constraints

- **Replies.** Each message gets exactly one live reply, whatever its outcome. A message sent mid-turn becomes its own turn, as the user's message, never inside a tool result.
- **Fallbacks.** A fallback reads "I couldn't answer that: {reason}. Nothing was changed." in the UX's words, with Tell now, the Fallback flag and no confidence. Tests force every `FallbackReason` and the error status through a `Decide` double.
- **Timing.** CI checks these against the mock: live content on the page within 2 s, a tell-now notice in the chat within 5 s, and every decision landing before its reply.
- **Restarts.** The conversation, checks, reminders, pending approvals and queued turns survive. A running turn runs again.
- **Text and times.**
  - Fixed strings match the UX exactly. A string test checks them, including "…".
  - Times are UTC ISO 8601 in storage and the API. Message text uses the instance zone through `Data.Time`. The page uses the browser zone, and banner times are page times.
- **Cost** is kept per turn and per decision, never per step. A reply shows `Ownership.TurnCost`; a rail row shows the decision's own cost.
- **All-clear.** All-clear sentences and check rows come only from `Checks.Render`.
- **Security.**
  - Model-written and arriving text renders as text: no `bypassSecurityTrust*`, and CSP is `script-src 'self'`.
  - No endpoint takes a `SessionRef`.
  - Untrusted content never reaches a governance command or the conversation.
  - No key, pairing code or Telegram identity is logged or published.
  - `eval` yields no live event, `Notification` or `Delivery`.
- **Accessibility.** WCAG 2.1 AA in both themes and full keyboard use, on Chromium, Firefox and WebKit at 1280×720 and 1280×600.

## Technical Decisions

- **Lanes.** Lane B owns `OcuTalon.Web`, `.Channel`, `.Core`, `.Schedule`, `.Demo`, `.Live`, `.Msg` and `.Data.{Time,Setting,Ownership,Public}`, the tables `Session`, `Turn`, `Delivery`, `Reminder` and `Live.Event`, and `web/`, `docker/` and `ci/`.
  - Lane A's classes and tables are read-only: Bridge, Agent, Checks, Watch, `Incident`, `BackgroundCheck`, `Decision`, `ApprovalRequest` and `Usage`. Ask for a property rather than adding it.
  - Edit only lane B's production region, and keep `Test.Contract.Ac` green.
- **Entry points.** Components talk only by messages to item names. Outside Core, call only `Commands.Submit`; channel services may also call `Allowance.TryConsume` and `Trace.Join`.
- **Commands.** `CommandsIn` is the one command gate: a fixed verb→owner table matched by exact class name, plus origin rules. It passes the command through unchanged, `IdempotencyKey` included.
  - Every answer is a plain-English `CommandResult` with status OK: a refusal sends nothing, and a stub owner gives `not_built`.
  - `tool` may only set, list or cancel reminders, start or stop watches, and `Dismiss` an incident its own session (the bridge context's `OwnerRef`) can see.
  - Settings and demo mode come only from `system` or `web_admin`, and pairing only from `telegram`.
  - REST handlers never write domain tables; they submit commands.
- **Pipelines.**
  - `WebChatIn` deduplicates on `clientId`, applies the allowance and joins the trace thread.
  - `Conversation` alone owns the `Turn` queue. It calls `Decide` (`decide`, then `turn`), stores both `DecisionRef`s and publishes `chat.message` at each stage.
  - `Intake` calls `decide`; on `act` it runs a read-only turn in a fresh session. It sends each `ItemDecision` to `OutcomeRouter`, or to `EvalSink` for `eval`.
  - Rules route only on named properties, and only Tell now and Act notify.
- **Rendering.** Only `*Out` operations render, through `Msg.Catalog.Render`. Each records its row with `Delivery.Record`, which Story 2.7 implements.
- **`BridgeSink`** alone turns bridge events into live events.
  - It reads bridge rows through Ownership and keeps no copies.
  - It never fails its caller, and waits under 1 s on any lock.
- **Ownership and SQL (AD-13, amended 2026-10-22).**
  - Every REST read and handler goes through `Data.Ownership`. An unseen `Ref` answers 404 `not_found`.
  - Incidents show only once `NoticedAt` is set. On a local install, watchers also see `instance` incidents.
  - Unchecked prepares are allowed only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows`. `Rows` takes the owner `Ref` as a required argument (never from request input), uses fixed SQL per row kind with the owner in every `WHERE`, and proves for each row kind that a second session gets none of the first session's rows.
  - CI forbids embedded SQL and every other unchecked path.
- **Live events.**
  - Write them only through `Live.Publish`, after the commit and never inside a transaction.
  - Each payload is the entity's full view, keyed by its `Ref`, never a delta.
  - Each type has one publisher: `chat.message` (`Conversation`), `notification` (`WebChatOut`), `decision`, `approval` and `turn.step` (`BridgeSink`), `reminder` (`ReminderOps`, `ReminderTimer`) and `status` (`StatusMonitor`).
  - Polling is release 1's only live path.
- **Status conditions** come from a closed catalog: `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused` and `resetSoon`. `/state` computes them, and `StatusMonitor` publishes their changes every 15 s. Key and cap state come only from `Bridge.Keys.Status` and `Bridge.Budget.State`.
- **Visual Trace.** Each session has one thread per day, from `Trace.Join`, which only channel services call. Work inside a turn, commands included, joins the turn's thread through the bridge context's `ThreadSessionId`; a command outside a turn takes the session's `TraceRef` as its `SuperSession`. `Web.TraceLink` is the only trace-URL builder.
- **Telegram.** `Included()` is 0 in release 1, and tests set `^OcuTalonTest("TelegramIncluded")`.
- **README links.** `README_URL` is defined in `links.ts`. A section link swaps `#readme` for that section's anchor.
- **Conventions.**
  - REST errors are `{"error": {"code", "message"}}` in plain English. The 400 codes are `bad_cursor` and `bad_message` (no `clientId` or no text).
  - Tests are `OcuTalon.Test.<Area>` in shard `lane-b`, and mock scenarios go under `ci/mock/scenarios/B/`.
  - Destructive tests, such as the purge, run only on throwaways.

## UX & Interaction Patterns

- **Colour.** Teal marks action, orange needs a person, red is failure and amber is a fallback. Every state also has a word and an icon. Replies have no greetings, emoji or exclamation marks.
- **Live updates.**
  - Focus moves only when the focused element is removed.
  - The chat, rail and timers are not live regions.
  - One announcer speaks each event once.
- **Controls.** Reuse Story 2.1's buttons, server button, popovers, dialogs and tooltips. Disclosures open inline. Trace links sit beside rows and open in a new tab.
- **Banned.** Modal notifications, toast-only copy, sounds, hover-only controls, progress bars, celebrations and infinite scroll.
- **Widths.** The rail is wide from 1440px, standard from 1280px and a drawer from 1024px. Below that the page is one column.

## Cross-Story Dependencies

- **Built so far (Stories 2.1 to 2.4).**
  - **Frame:** `MainPage`, `.banner-slot` and the shared controls.
  - **Server:**
    - `SessionEvents` attaches the durable `Session` at sign-in;
    - `Ownership` provides `SessionRef`, `Rows`, `Watchers` and `Incident`, and `Session.Recipients` is built;
    - `/state` holds `epoch`, `streams`, `chat`, `rail`, `telegram` and `status` (empty until Story 2.10), built by the `Live.Payload.*.FromRow` builders;
    - `CommandsIn` routes every verb; its owners stay stubs until their own epics;
    - `POST /api/v1/messages` (202 `{clientId}`, a repeat dropped, 400 `bad_message`) → `WebChatIn` → `Conversation`, which handles Busy, SessionBroken and Tainted, maps every failure to `conversation.turnFallback` with a reason, publishes `chat.message` at `queued`, `running` and `done`, and sends an `Outbound` to `Notify`;
    - a `Turn` keeps the text, the reply as sent, the `clientId` and the trace target (`ChatMessage.FromRow` maps them); `Install.Step.Web.Reconcile` resumes turns after a restart.
  - **Page:** the envelope interceptor, `SessionGate` (stops every call on a 401), the `live-store` keyed by `ref`, `LiveState` polling, skeletons with **Retry**, and sign-out through the API.
  - **Test helpers:** `DecideDouble` (a scripted `Decide` stand-in that can also run in a throwaway production), `ConversationProbe`, and the `InProduction` base for throwaway production tests.
- **Inside the epic.**
  - Story 2.5 posts with a `clientId` (a resend reuses it) and renders `catalogKey` and `fallbackReason`. Story 2.6 adds decision fields to `Outbound` and `chat.message`. Story 2.7's `Notify` routes the `Outbound`, and its `Intake` tests reuse `DecideDouble`.
  - Story 2.6's `BridgeSink` feeds Stories 2.5 and 2.8, and Story 2.8 adds the `approval.*` events.
  - Story 2.9's `Trace.Join` goes in `WebChatIn` before its send. Its `TraceLink` serves Stories 2.6 and 2.8, and its menu tests the popover (DW-58).
  - Story 2.11 uses Story 2.10's banner slot.
- **Routed ledger items.**
  - **Story 2.5 (DW-65):** `ChatItems` loads the whole chat. Choose a cap or paging within the snapshot's shape, and test it on a long session.
  - **Story 2.7 (DW-62):** keep web notice cards where the snapshot can read them, merged into the chat in time order.
  - **Story 2.7 (DW-81):** with `DecideDouble` in a throwaway production, test `Busy` end to end: a 3 s wait through the real `Ens.Alarm`, then a resend on the reopened instance, at most 5 times before the fallback.
  - **Story 2.8 (DW-68):** `Recipients` reads watchers in a production job, not in the REST request (or the story asks to amend AD-13). A failed read is loud, and a test shows two watchers both get the `approval` event.
  - **Story 2.9 (DW-74):** a throwaway check settles whether `Commands.Submit` loses the calling job's job-local `SessionId`. If it does, `Trace.Join` or the runner restores it, so a tool's later steps stay in the turn's thread.
- **Lane A.** Real decisions arrive with Story 1.3 and threads with Story 1.5. The key status comes from Story 1.6 and the cap from Story 1.4. Approvals arrive with Stories 3.4 and 3.5.
- **Later.** Epic 5 uses `Recipients`, Story 16.3 extends `SessionRef`, Story 30.2 adds the purge task and Story 31.1 the WebSocket.
