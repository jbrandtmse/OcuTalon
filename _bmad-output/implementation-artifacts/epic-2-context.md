# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 turns Epic 0's empty signed-in page into release 1's working main page on a local or IPM install. The user chats with OcuTalon, and every message they write gets exactly one reply, in order, with a plain-English fallback when the model fails. Each reply shows its attention decision with reasons, confidence, cost, details and a Visual Trace link. A status rail lists pending approval requests, background checks, pending reminders and the 20 newest decisions. Polling keeps all of it current without a reload, and it is all still there after a restart. Behind the page, the epic builds Lane B's core of the production: command routing with origin checks, the turn pipeline, untrusted intake, outcome and notification routing, the bridge event sink, status banners and the one trace-link builder. This is UJ-1's page step, and Epics 4, 6 and 16 build on it. The demo-mode regions (guide, simulated devices, Break the feed) are not part of this epic.

## Stories

- Story 2.1: Lay out the main page frame
- Story 2.2: Keep the session and load its snapshot with live updates
- Story 2.3: Route every command by verb, with origin checks
- Story 2.4: Answer every chat message through the turn pipeline
- Story 2.5: Chat with OcuTalon in the page
- Story 2.6: Show every decision with its reasons and cost
- Story 2.7: Route untrusted items and notifications by outcome
- Story 2.8: Show the status rail
- Story 2.9: Open anything in Visual Trace
- Story 2.10: Show status banners for a missing key or a stalled heartbeat
- Story 2.11: Say plainly when the page loses contact
- Story 2.12: Meet the accessibility and responsive floor

## Requirements & Constraints

- **Where to run.** This is Lane B. The only IRIS target is the dev slot `ocutalon-slot-b` (IRIS MCP profile `ocutalon-slot-b`, namespace `OCUTALON`, ports 1991/52791). Pass the server and namespace on every IRIS MCP call, and make at most one `iris_execute_tests` call per message. Code is loaded and compiled with the MCP tools, and installer steps are run explicitly. Destructive, after-start and IPM tests run only in throwaway stacks and CI.
- **Every message is answered.** Each message the user writes gets exactly one reply, whatever its attention decision says: it is never ignored or held for the digest. A message sent while a turn runs becomes its own turn and reaches the model as the user's own message, never inside a tool result. Every reply is generated live; nothing is canned.
- **Fallback replies.** A fallback reads "I couldn't answer that: {reason}. Nothing was changed." The reason uses the UX's wording for each `FallbackReason`. `invalid`, `unusable` and an error status all share the generic reason. Tests force every reason through a `Decide` test double.
- **Timing.** Live content reaches the page within 2 s, and a tell-now notice reaches the web chat within 5 s of its decision. CI checks both against the mock on every run. CI also asserts that the decision lands before its reply. The 19-of-20 figures over real networks and the 10-second decision bound on Claude Haiku 5.5 are measured in the rehearsal, not in this epic.
- **Survives a restart.** The conversation, background checks, pending reminders, pending approvals and queued turns all survive a restart of IRIS or its container. A turn left `running` runs again.
- **Plain English and times.** User-facing text never shows class names or error codes. Times are stored and sent as UTC ISO 8601. Message text uses the instance zone, with " ET" added on the online demo. The page uses the browser's zone and adds the zone abbreviation beside message text when it differs from the instance zone. A banner's `{time}` is a page time (DW-29).
- **Cost.** Cost is per turn and per decision, never per step. Formats: "<$0.0001" below that, four decimals under $0.01, three under $1, otherwise two. Tokens get thousands separators, confidence two decimals, and figures are tabular.
- **No false all-clear.** The reserved all-clear sentences come only from `Checks.Render`'s catalog key. Check rows are never model-written.
- **Security.** Model and arriving text render as text only: nothing calls `bypassSecurityTrust*`, and the page sends `Content-Security-Policy: script-src 'self'`. No key, token or pairing code appears in IRIS, a log, the trace or a live event. Owner `eval` produces no live event, `Notification` or `Delivery`.
- **Accessibility and browsers.** The page meets WCAG 2.1 AA, works by keyboard alone and has a label on every control. It runs in Chromium, Firefox and WebKit at 1280×720 and 1280×600.
- **OpenClaw.** The About dialog's tagline and the not-affiliated note share one block. OpenClaw is never part of a product name.

## Technical Decisions

- **Commands.** Every state change enters through `OcuTalon.Core.Commands.Submit` (Epic 0). It sets `Origin` from the authenticated context, and sets `tool` whenever a bridge context is active.
  - `CommandsIn` is adapterless and is called through `Ens.Director.CreateBusinessService` and `ProcessInput`.
  - It routes each verb to its one owner: `ReminderOps`, `WatchOps`, `SettingsOps`, `SessionOps`, or `IncidentManager` (as an `IncidentCommand` `dismiss`).
  - It returns the owner's synchronous `CommandResult` and passes the `IdempotencyKey` through unchanged.
  - Origin `tool` may only set or cancel a reminder, start or stop a watch, save or forget a memory (from step 3), and dismiss one of the session's own incidents.
  - Settings and demo-mode verbs are accepted only from `system` or `web_admin`, and pairing only from `telegram`.
  - A stub owner yields a plain-English failure `CommandResult`, never an exception.
- **Chat intake.** `POST /api/v1/messages` (`clientId`, `text`, `fromGuide`) answers 202. Then `WebChatIn`:
  - deduplicates on `clientId` within the session;
  - calls `OcuTalon.Core.Allowance.TryConsume(SessionRef, Channel, Text)` synchronously before queueing. It allows everything unless the online-demo flag is set, and records a refused message as a `Turn` with no decision;
  - calls `OcuTalon.Core.Trace.Join`, and sets `..%SessionId` and `..%SuperSession` inside `OnProcessInput`, after the base class clears them and before the first send;
  - sends `Conversation` an `OcuTalon.Msg.Item` with a new `ItemId`, channel `web` and provenance `user`.
- **The turn pipeline.** `Conversation` alone owns the `Turn` queue. A turn moves through `queued`, `running` and `done`, and stores its `Channel`, `FromGuide` and both `DecisionRef`s, never a total. For each turn, `Conversation`:
  - renders the input with `Agent.Input`;
  - calls `Decide` with kind `decide`, then with kind `turn`, passing its own trace session id as `ThreadSessionId`;
  - publishes `chat.message` when the turn is queued, when the decision lands and when the reply lands;
  - sends the reply to `Notify` as an `Outbound` with `OriginChannel`.

  When `Decide`'s answer needs handling:
  - `Busy`: re-queue after 3 s, at most 5 times, then fall back with `rate_limited`.
  - An error status: fall back at once.
  - `SessionBroken`: retry once with `SessionMode` `fresh` and a code-written recap.
  - `Tainted`: send the next turn `fresh`, with a `SeedText` recap built from `Turn` rows, never from tool results.
  - Check results in `HostData`: call `Checks.Render` after the reply filter, and put its key and rows on the reply and on `chat.message`.
- **Untrusted items.** `Intake` renders the item and calls `Decide` with kind `decide`. On `act`, it runs a read-only turn with provenance `untrusted` and `SessionMode` `fresh`, never in the user's conversation. It then builds an `ItemDecision` and sends it to `OutcomeRouter` (owner a session or `instance`) or to `EvalSink` (owner `eval`).
- **Outcome routing.** `OutcomeRouter` (`OcuTalon.Core.Rule.Outcome`, a routing engine):
  - Ignore records the decision only.
  - Digest forwards the `ItemDecision` to `DigestStore`.
  - Tell now and Act produce a `Notification` of kind `tellnow`. It uses the item's `CatalogKey` and `Slots` when present. Otherwise it uses the tell-now key with the `Summary` and the first reason line, read from the `Decision` row through Ownership.
- **Notification routing.** `Notify` (`OcuTalon.Core.Rule.Notify`) routes only on named properties:
  - a reply goes to its turn's channel and the web chat;
  - a notification goes to `WebChatOut`, to `SimPhoneOut` in demo mode, and to `TelegramOut` when paired;
  - `allowance` goes to the web chat and the paired chat only.
- **Rendering and delivery.** Producers never render text. Only the `*Out` operations do, through `OcuTalon.Msg.Catalog.Render(key, slots, channel)` (Epic 0, already implemented; `RenderAt` for tests) and `OcuTalon.Data.Time`.
  - For a reply, `WebChatOut` records only its `Delivery` row.
  - For a notification, it renders the text, records the row and publishes `notification`.
  - This epic implements `Delivery.Record(ownerRef, channel, channelMessageId, approvalRef)` and `FindByApproval(approvalRef, channel, ownerRef)`.
- **`OcuTalon.Core.BridgeSink`** extends `OcuTalon.Bridge.Ext.HostSink` and is named by `Decide`'s `HostSinkClass` setting. It is the only place that turns bridge events into `Live.Publish` calls.
  - `decision.recorded` becomes a `decision` event. Its trace target is `Decision.TraceSessionId`, and it carries `ItemSummary`.
  - `turn.step` (`{decisionRef, label}`) publishes only the label, to the owning session's running turn.
  - Each `approval.*` event goes to the owning session, or to each session `Session.Recipients` returns.
  - It reads bridge rows read-only through Ownership and keeps no copies. It never fails its caller, waits on no lock for more than 1 s, and publishes nothing for `eval`.
- **Status conditions.** `StatusMonitor` (`CallInterval` 15 s) computes the closed catalog of status conditions:
  - `noModelKey` from `Bridge.Keys.Status(agent)` for each of the three agents;
  - `dailyCap` from `Bridge.Budget.State()`;
  - `heartbeatStalled` when the last tick in `StatusMark` is more than 3 minutes old.

  On any change it publishes `status` on the instance stream. `/state` computes the same conditions on read.
- **Session and ownership.**
  - `OcuTalon.Web.SessionEvents.OnLogin` creates each IRIS user's one durable `Session` row (`SessionRef`, `TraceRef`, epoch) at the first sign-in and reuses it afterwards.
  - Sign-out ends only the CSP session and its sign-in group.
  - `OcuTalon.Data.Ownership` serves every REST read and command handler. It takes the `SessionRef` from the CSP session, never from the client, and re-checks the target's owner or scope. A `Ref` the session can't see answers 404.
  - Incident reads include only incidents whose `NoticedAt` is set.
  - `/state` and `/events` switch from Epic 0's `Session.ForUser` to Ownership, through one resolution method that Story 16.3 later extends (DW-15).
  - `TurnCost` and `RunCost` sum `Usage` rows, excluding `eval`.
  - `Session.Recipients` returns the owning session, or every session watching the production for an `instance` incident, or none for `eval`.
- **REST.** Paths are `/ocutalon/api/v1/...`. Errors are `{"error": {"code", "message"}}`. A state-changing call needs `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`, and the `ApiClient` interceptor adds them (DW-14). Unchecked SQL prepares are allowed only in CI-allow-listed methods.
- **Live events.**
  - Events are written only through `OcuTalon.Live.Publish`, after the publisher's own commit and never inside a transaction.
  - Each payload is the full current public view keyed by its `Ref`, never a delta, with camelCase keys.
  - The envelope is `{seq, stream, ts, type, payload}`, with the stream labelled `session` or `instance`.
  - Payload classes are `OcuTalon.Live.Payload.<Type>`, and their TypeScript interfaces are generated by `web/scripts/payloads.mjs` (`--check` runs in the build).
  - Each event type has exactly one publisher.
  - Events older than 24 h are deleted through `OcuTalon.Live`'s `Purge(daysToKeep)`. The purge task arrives with Story 30.2, so until then tests call the declaration directly.
- **Polling is release 1's only live path.** The page reads the `GET /state` snapshot, which carries each stream's last `seq` and the epoch, then polls `GET /events?after=&afterInstance=` every 1 to 2 s. It applies each event idempotently by `Ref` and reloads the snapshot when a `seq` skips. The WebSocket moved to Story 31.1.
- **Trace.**
  - `Trace.Join` returns the session's daily thread: an id kept on the `Session` row and allocated under a lock, with a new thread from the first turn after midnight in the instance zone. Only channel services call it.
  - Work inside a turn reuses the bridge context's `ThreadSessionId`.
  - No other header id is ever used as a session id.
  - `OcuTalon.Web.TraceLink` is the only builder of trace URLs:
    - the app is `/ocutalon/trace/ocutalon/` or `/ocutalon/trace/ocuorders/`;
    - `SESSIONID` is the target's header id;
    - `PAGE` = ceil(item index ÷ page size). The item index counts the thread's headers plus its event-log, rule-log and I/O-log rows up to the target. The page size and "Show events" come from the viewer's own settings (defaults 40 and on), read through one helper.
  - Payloads carry `TraceHeaderId` and `TraceNamespace`, and the web layer adds the URL.
- **Telegram in release 1.** `/state`'s Telegram block reads `OcuTalon.Channel.Telegram.In.Included()`, which returns 0 in release 1. Tests turn it on with `^OcuTalonTest("TelegramIncluded")`. The rail's Telegram card is its own component under `web/src/app/rail/telegram-card/`, which Lane A owns from Epic 12.
- **Angular.** Standalone components and signals, hash routing, one typed API client and one live-event service. Styling uses the Angular CDK plus custom components from the `DESIGN.md` tokens, which a Stack row already records. Icons and fonts are vendored, never loaded from a CDN.
- **Conventions.**
  - Tests are `%UnitTest` classes `OcuTalon.Test.<Area>.<Subject>` in shard `lane-b`. Test doubles and owners go in `OcuTalon.Test.Core`.
  - Demo-path specs are `web/e2e/demo-path/0<n>-<id>.spec.ts`. An unbuilt part is `notBuilt(title, 'N.M')`, and a test that must never skip again is tagged `@floor`.
  - Mock scenarios go under `ci/mock/scenarios/B/` and are picked by a `[[mock:<name>]]` marker, a guide prompt or `MOCKKEY`.
  - Storage is append-only, with committed `Storage` blocks and `DEFAULTGLOBAL` `^OcuTalonP.<Short>` registered in `src/short-names.tsv`.
  - Edit only the production class's lane B region.
  - Enumerations come from `OcuTalon.Msg.Enum`, and refs from `OcuTalon.Bridge.Ids.NewRef()`. Row ids never leave the server.

## UX & Interaction Patterns

- **Page order.** The landmark and tab order is: app header, banner slot, region "Status" (the rail), then `main` (the chat). With demo mode off, the chat takes the guide's and devices' space. The page has one visually hidden `h1`, an `h2` per region and an `h3` per rail section. Release 1 has one page plus the About dialog, with no header navigation.
- **The rail.** Sections run Telegram, Approval requests, Background checks, Reminders, Recent decisions, with live counts in the headings. Rows are read-only, with hints such as To stop, ask: "Stop watching Orders." A row that leaves its list passes focus to its section heading.
- **The decision strip** sits under each reply:
  - an unfocusable outcome chip (Ignore, Digest, Tell now, Act) that is distinct without colour;
  - the amber "Fallback" flag with `life-buoy` (a fallback's outcome is Tell now);
  - "Confidence {0.00} · {cost}";
  - "Decision details", an inline `aria-expanded` disclosure, never a dialog.
- **The turn indicator** shows "Deciding…", then "Working…" (with the elapsed time after 10 s), or the current step's label from `turn.step`. It is never a live region.
- **Server buttons** go busy on press: a spinner, `aria-disabled` and `aria-busy` (never `disabled`), with repeat presses ignored. After 10 s without an answer they restore themselves with the announced "Couldn't reach OcuTalon. Try again. Nothing was changed.", and a late answer still shows.
- **Banners** come from a closed catalog in a fixed order, at least 44px tall. Only "Reset soon" and "Reconnecting" can be closed. When polling gets no answer:
  - after 10 s, "Reconnecting… New messages may be delayed.";
  - after 30 s, "Can't reach OcuTalon. Retrying every 10 seconds.";
  - on recovery, the missed content loads into place and the banners clear.
- **Trace links** sit beside a row's button, never inside it, and open in a new tab. On a local install the first press shows the "Sign in to Visual Trace" popover, once per browser session. On the online demo, links open directly.
- **Announcements and focus.** One polite live region announces each event once and combines more than three in 2 s into "{n} new updates". Live content never moves focus, except to replace an element that had focus.
- **Persistence.** The theme, the narrow-window note's close and the popover's "Don't show this again" are saved per browser, tolerating storage failures. Whether the popover was seen is saved per browser session.
- **Banned patterns:** modal notification interruptions, toast-only information, sounds, tabs that switch by themselves, hover-only controls, drag-and-drop as the only way, model-progress bars, celebration effects, and infinite scroll in counted lists.
- **Exact strings.** Every fixed interface string must match the UX exactly, and a string test checks them, including the single "…" character.
- **Layout by width.**
  - From 1440px: `rail-width-wide`.
  - 1280 to 1439px: `rail-width`, with every UJ-1 control reachable without scrolling the page.
  - 1024 to 1279px: the rail becomes a drawer.
  - Below 1024px or at 200% zoom: one scrolling column.

## Cross-Story Dependencies

- **Inside the epic.**
  - Story 2.1's frame and shared controls (busy buttons, popovers, focus ring) serve every page story.
  - Story 2.2's `Session`, `Ownership`, `Recipients`, snapshot and live-event service underpin Stories 2.5 to 2.12.
  - Story 2.3's `CommandsIn` comes before anything that submits commands.
  - Story 2.4's pipeline, `Allowance` and `Decide` test double come before Stories 2.5 and 2.6, and Stories 2.7 and 2.9 reuse the double.
  - Story 2.6's `BridgeSink` feeds Story 2.8's Recent decisions, and Story 2.8 extends it to `approval.*`.
  - Story 2.9's `Trace.Join` runs in Story 2.4's `WebChatIn`, and its `TraceLink` serves the rows of Stories 2.6 and 2.8.
  - Story 2.11 uses Story 2.10's banner slot.
- **Lane A, through test doubles until each story merges.**
  - `Decide` (Story 1.3), `OcuTalon.Agent.Input`, `Checks.Render`, `Bridge.Keys.Status` (Story 1.6) and `Bridge.Budget.State` (Story 1.4).
  - The real trace path waits for Stories 1.3 and 1.5, and the no-key CI test turns on when Story 1.6 merges.
  - The real approval-event path waits for Stories 3.4 and 3.5, and for Story 30.3 for a replay's `approval.result`.
- **Contracts.** Cross-lane signatures stay as Epic 0 fixed them, and the `OcuTalon.Test.Contract.Ac` signature oracle must stay green.
- **Later epics that depend on this one.**
  - Epic 5 needs `Session.Recipients`, and Epic 9 needs `Intake`'s `EvalSink` path.
  - Story 4.5 adds `SimPhoneOut`, which turns on the phone half of the 5 s check.
  - Story 12.7 turns on `Included()` and the README Telegram link.
  - Story 16.3 extends Ownership's one resolution method, and Story 16.9 builds the allowance refusal.
  - Story 30.2 adds the purge task, and Story 31.1 the WebSocket.
  - Story 31.3 adds the About dialog's bridge-guide and security-overview links.
