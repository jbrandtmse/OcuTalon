# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 turns Epic 0's empty signed-in page into release 1's working main page on a local or IPM install. A signed-in user chats with OcuTalon, and each message they write gets exactly one reply, in order, with a plain-English fallback when the model fails. Each reply shows its attention decision with reasons, confidence, cost, details and a Visual Trace link. A status rail lists pending approval requests, background checks, pending reminders and the 20 newest decisions. Polling keeps everything current without a reload, and all of it survives a restart. Behind the page, the epic builds Lane B's core of the production: command routing with origin checks, the turn pipeline, untrusted intake, outcome and notification routing, the bridge event sink, status conditions and the one trace-link builder. This is UJ-1's page step, the part every release must keep working. Lane B's demo-mode regions (Epic 4), incident cards (Epic 6) and online demo (Epic 16) build on it.

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

- **Every message is answered.** Each message the user writes gets exactly one reply, whatever its attention decision says, and is never ignored or held for the digest. A message sent while a turn runs becomes its own turn and reaches the model as the user's own message, never inside a tool result. Replies are generated live, never canned.
- **Fallbacks.** A failed chat turn replies in plain English, saying why and that nothing was changed, using the UX's wording for each fallback reason. A fallback's outcome is Tell now, it carries the fallback flag, and it shows no confidence. Tests force every fallback reason, and the error status, through a test double.
- **Timing.** Live content reaches the page within 2 s, a tell-now notice reaches the web chat within 5 s of its decision, and a decision always lands before its reply. CI checks each against the mock on every run. The 19-of-20 figures over real networks and the 10-second decision bound on Claude Haiku 5.5 are measured in the rehearsal, not in this epic.
- **Restarts.** The conversation, background checks, pending reminders, pending approval requests and queued turns survive a restart of IRIS or its container. A turn left running is run again.
- **Plain English, exact strings.** User-facing text has no class names, error codes or stack traces. Every fixed interface string matches the UX, which a string test checks, including the single "…" character.
- **Times.** Times are stored and sent as UTC ISO 8601. Message text uses the instance's zone through `OcuTalon.Data.Time`, with " ET" added on the online demo. The page uses the browser's zone, and adds the zone abbreviation beside message text when it differs from the instance's. Banner times are page times.
- **Cost** is recorded per turn and per decision, never per step. A reply shows the turn's cost, while a rail row or notice shows the decision's own cost.
- **No false all-clear.** The reserved all-clear sentences and the check rows come only from code (`Checks.Render`), never from the model.
- **Security.**
  - Model-written and arriving text renders as text only: nothing calls `bypassSecurityTrust*`, and the page sends `Content-Security-Policy: script-src 'self'`.
  - No endpoint accepts a `SessionRef` from the client.
  - Content that didn't come from the user can't reach a governance command or the user's conversation.
  - Keys, pairing codes and Telegram identities never appear in a message, log, live event or audit entry.
  - Owner `eval` produces no live event, `Notification` or `Delivery`.
- **Sessions.** A local session lasts at least 8 hours of idle time. Any 401 stops all calls and shows the sign-in page.
- **Accessibility and browsers.** WCAG 2.1 AA contrast in light and dark themes, full keyboard use, and a label on every control. Chromium, Firefox and WebKit at 1280×720 and 1280×600.

## Technical Decisions

- **Lane B's footprint.** Lane B owns:
  - `OcuTalon.Web` (with `.Web.Public`), `.Channel`, `.Core`, `.Schedule`, `.Demo`, `.Live`, `.Msg`, `.Data.Time`, `.Data.Setting`, `.Data.Ownership` and `.Data.Public`;
  - the tables `Session`, `StatusMark`, `Pairing`, `Turn`, `Delivery`, `Reminder`, `Setting` and `Live.Event`;
  - `web/`, `docker/`, and `ci/` except `ci/mock/scenarios/A/`.

  Lane A's classes and tables (`Bridge`, `Agent`, `Tools`, `Watch`, `Checks`, `BackgroundCheck`, `Incident`, `Decision`, `ApprovalRequest`, `Usage`) are read-only to this epic; ask for a property rather than adding it. Edit only the lane B region of the production class. Cross-lane signatures stay as Epic 0 fixed them, and the `OcuTalon.Test.Contract.Ac` signature oracle must stay green. Unmerged Lane A work is tested through its Epic 0 stubs, fixtures and test doubles.
- **Dependency direction.** Components talk only through messages addressed by production item name. Outside `OcuTalon.Core`, the only Core entry points are `Commands.Submit`, plus `Allowance.TryConsume` and `Trace.Join`, which channel services may call. The web layer may also call `OcuTalon.Channel.Telegram.In.Included()`.
- **Commands.** Every state change is a production message submitted through `OcuTalon.Core.Commands.Submit`. It sets `Origin` from the authenticated context, and sets `tool` whenever a bridge context is active. `CommandsIn` is adapterless and is called with `Ens.Director.CreateBusinessService` and `ProcessInput`. It routes each verb to its one owner and returns that owner's synchronous `CommandResult`, passing the `IdempotencyKey` through unchanged. Origin rules:
  - `tool` may only set, list or cancel reminders, start or stop a watch, and dismiss one of the session's own incidents (from step 3, also save or forget a memory);
  - settings and demo-mode verbs come only from `system` or `web_admin`;
  - pairing comes only from `telegram`.

  REST code may read tables, but may write only the `Session` row at sign-in, a sign-out, a pairing code's hash and UI-only markers.
- **Pipelines.**
  - **A user's message:** `WebChatIn` deduplicates on `clientId`, applies the allowance and joins the trace thread, then hands the turn to `Conversation`. `Conversation` alone owns the `Turn` queue. It calls `Decide` twice (first `decide`, then `turn`), stores both `DecisionRef`s on the turn (never a total), publishes `chat.message` at each stage, and sends the reply through `Notify`.
  - **An untrusted item:** `Intake` calls `Decide`. On `act` it runs a read-only turn with provenance `untrusted` in a fresh session. It then sends an `ItemDecision` to `OutcomeRouter`, or to `EvalSink` for owner `eval`.
  - **Routing:** `OutcomeRouter` and `Notify` are routing rules that route only on named properties. Only Tell now and Act notify.
- **Rendering.** Producers never render text. Only the `*Out` operations render, through `OcuTalon.Msg.Catalog.Render(key, slots, channel)`, Epic 0's one renderer (`RenderAt` fixes the clock in tests). Every `*Out` records its `Delivery` row through `Delivery.Record`, which this epic implements together with `FindByApproval`.
- **`OcuTalon.Core.BridgeSink`** extends `OcuTalon.Bridge.Ext.HostSink`, and `Decide`'s `HostSinkClass` setting names it. It is the only place that turns bridge events into live events. It reads bridge rows read-only through the ownership API and keeps no copies. It never fails its caller and waits on no lock for more than 1 s.
- **Session and ownership.**
  - Each IRIS user has one durable `Session` row (`SessionRef`, `TraceRef`, epoch), created in `OcuTalon.Web.SessionEvents` at the first sign-in. Signing out ends only the CSP session and the rest of the sign-in group.
  - Every REST read and command handler goes through `OcuTalon.Data.Ownership`, which takes the session from the CSP session and re-checks the target's owner or scope. A record the session can't see answers 404. Session resolution stays one method, because the online demo later extends it.
  - Unchecked SQL prepares are allowed only in CI-allow-listed methods.
- **Live events.**
  - Events are written only through `OcuTalon.Live.Publish`, after the publisher's own commit and never inside a transaction.
  - Each payload is the entity's full current public view, keyed by its `Ref` with camelCase keys, never a delta. The envelope is `{seq, stream, ts, type, payload}`, with the stream labelled `session` or `instance`.
  - Each event type has exactly one publisher. Lane B's are `chat.message` (`Conversation`), `notification` (`WebChatOut`), `decision`, `approval` and `turn.step` (`BridgeSink`), `reminder` (`ReminderOps` and `ReminderTimer`) and `status` (`StatusMonitor`). `incident` and `check` are Lane A's.
  - Payload classes are `OcuTalon.Live.Payload.<Type>`. Their TypeScript interfaces are generated by `web/scripts/payloads.mjs`, whose `--check` runs in the build. Payloads carry trace targets as `TraceHeaderId` and `TraceNamespace`, and the web layer adds the URL.
- **Polling is release 1's only live path.** The page loads the `/state` snapshot, then polls `/events` every 1 to 2 s with one cursor per stream. It applies events idempotently and reloads the snapshot when a stream's `seq` skips. The WebSocket belongs to Epic 31.
- **Status conditions** are a closed catalog: `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused` and `resetSoon`. `/state` computes them on read, and `StatusMonitor` publishes changes on the instance stream every 15 s. Key and cost-cap state are read only through `Bridge.Keys.Status` and `Bridge.Budget.State`.
- **Visual Trace.**
  - Each session has one trace thread per day, started at the first turn after midnight in the instance zone and returned by `Core.Trace.Join`. Only channel services call it; work inside a turn reuses the bridge context's `ThreadSessionId`, and no other header id is ever used as a session id.
  - `OcuTalon.Web.TraceLink` is the only builder of trace URLs. It targets OcuTalon's own trace applications, and computes the link's page from the viewer's own Visual Trace settings.
- **REST.** Paths sit under `/ocutalon/api/v1/` and use plural nouns.
  - Errors take the shape `{"error": {"code", "message"}}` in plain English, with the fixed codes, among them 401 `signed_out`, 403 `not_json`, `no_request_header` and `wrong_origin`, 404 `not_found`, 429 with `retryAt`, and 501 `not_built`.
  - A state-changing call needs `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`, which an `ApiClient` interceptor adds.
- **Angular.**
  - Standalone components and signals, hash-based routing, one typed API client and one live-event service.
  - The Angular CDK plus custom components styled from the `DESIGN.md` tokens, with no component kit (Story 2.1 recorded this as a Stack row).
  - Lucide icons and the fonts are vendored, never loaded from a CDN.
  - Pinned versions: Angular and CDK 22.2.x, TypeScript ~6.0.3, Playwright 1.64.x.
- **README link.** There is one address, `https://github.com/jbrandtmse/OcuTalon#readme`, defined once as `README_URL` in `web/src/app/links.ts`.
  - A link to a README section replaces `#readme` with the section's anchor and never appends a second fragment.
  - Server-side text that names the README uses the same address.
  - A README section link appears only once its section exists. The Telegram link waits for `Included()` to return 1.
- **Telegram in release 1.** `Included()` returns 0. Tests turn it on through `^OcuTalonTest("TelegramIncluded")`. The rail's Telegram card is its own component under `web/src/app/rail/telegram-card/`, which Lane A owns from Epic 12.
- **The public package** (the login page and shell in `OcuTalon.Web.Public`) references only `%CSP`, dynamic objects and its two own packages. It keeps its own copies of the UX texts it renders, and a test compares them with the catalog.
- **Conventions.**
  - Enumerations come from `OcuTalon.Msg.Enum`, and public refs from `OcuTalon.Bridge.Ids.NewRef()` (22-character base64url). Row ids never leave the server.
  - Storage is append-only, with committed `Storage` blocks. A private table sets `DEFAULTGLOBAL` `^OcuTalonP.<Short>`, registered in `src/short-names.tsv`.
  - Tests are `%UnitTest` classes `OcuTalon.Test.<Area>.<Subject>` in shard `lane-b`, with test doubles and owners in `OcuTalon.Test.Core`.
  - Demo-path specs are `web/e2e/demo-path/0<n>-<id>.spec.ts`. An unbuilt part is `notBuilt(title, 'N.M')`, and a test that must never skip again is tagged `@floor`.
  - Mock scenarios go under `ci/mock/scenarios/B/`, chosen by a `[[mock:<name>]]` marker, a guide prompt or the agent's `MOCKKEY`.
- **Where code runs.** Lane B's developer instance (slot B) loads and compiles code with the IRIS MCP tools and runs installer steps explicitly. After-start, IPM and destructive tests run only in throwaway compose stacks and CI.

## UX & Interaction Patterns

- **Posture.** The page is a calm, dense operations console whose job is to show its work.
  - Teal marks actions, links, focus and the Act outcome.
  - Orange marks what needs a person: Tell now and pending approvals.
  - Red means failure, and amber marks fallback and warnings.
  - Color is never the only signal: every state has a word and an icon, and every link is underlined.
  - Surfaces are flat, with no sparkle "AI" imagery. Replies have no greetings, emoji or exclamation marks.
- **Page structure.** The landmark and tab order is header, banner slot, region "Status", then `main` (the chat). The page has one visually hidden `h1`, an `h2` per region and an `h3` per rail section. With demo mode off, the guide and devices are absent and the chat widens. There is no header navigation in release 1, and dialogs stack at most one deep.
- **Shared controls (built in Story 2.1).**
  - Button variants, never pill-shaped.
  - Busy server buttons: `aria-busy` and `aria-disabled`, never `disabled`, with repeat presses ignored. After 10 s without an answer they restore themselves and show the announced "couldn't reach" notice; an answer that arrives later still shows.
  - The double focus ring, used for nothing else.
  - Non-modal popovers, modal dialogs and pointer-only tooltips.
  - One polite announcer.
- **Live, not jumpy.** Live content never moves focus, except to the replacement (or the section heading, or the nearest container) when the focused element is removed. The chat, rail, turn indicator and timers are not live regions and never use `role="log"`. Each event is announced once, and more than three within 2 s are combined.
- **Disclosures** ("Decision details", decision rows) open inline with `aria-expanded`, never in a dialog. Trace links sit beside a row's button, never inside it, and open in a new tab, saying so. On a local install the first trace press shows the sign-in popover, once per browser session.
- **Loading.** Skeletons are static `sunken` blocks. After 10 s with no data they give way to a load error with **Retry**.
- **Persistence.** The theme, dismissed notes and the popover's "Don't show this again" are saved per browser, and storage failures are tolerated.
- **Formats.** Costs use the UX's tiered decimals. Tokens get thousands separators and confidence two decimals. Counts agree with their plurals, and figures are tabular.
- **Banned:** modal notification interruptions, toasts as the only copy, sounds, tabs that switch by themselves, hover-only controls, drag-and-drop as the only way, model-progress bars, celebration effects, and infinite scroll in counted lists.
- **Widths.**
  - From 1440px, the wide rail.
  - From 1280 to 1439px, the standard rail, with every UJ-1 control reachable without page scroll because each region scrolls on its own.
  - From 1024 to 1279px, the rail becomes a drawer.
  - Below 1024px or at 200% zoom, one scrolling column.

## Cross-Story Dependencies

- **Inside the epic.**
  - Story 2.1's frame and shared controls serve every page story. Story 2.2's **Retry** gives the server button, inline notice and announcer their first browser test (DW-57). Story 2.9's Visual Trace menu gives the popover service its first browser test (DW-58).
  - Story 2.2's `Session`, `Ownership`, `Recipients`, snapshot and live-event service underpin Stories 2.5 to 2.12.
  - Story 2.3's `CommandsIn` comes before anything that submits commands.
  - Story 2.4's pipeline, `Allowance` and `Decide` test double come before Stories 2.5 and 2.6. Stories 2.7 and 2.9 reuse the double.
  - Story 2.6's `BridgeSink` and decision events feed Story 2.5's decision-before-reply order and Story 2.8's Recent decisions. Story 2.7 reads the tell-now reason the same way `BridgeSink` does. Story 2.8 extends `BridgeSink` to `approval.*` events.
  - Story 2.9's `Trace.Join` runs inside Story 2.4's `WebChatIn`, and its `TraceLink` serves the rows of Stories 2.6 and 2.8.
  - Story 2.11's banners use Story 2.10's banner slot and catalog order.
- **Lane A, through stubs and test doubles until each story merges.**
  - The real decision path turns on with `Decide` (Story 1.3); until then, tests use Story 2.4's double and fixture rows.
  - The real thread path waits for Stories 1.3 and 1.5. The no-key CI test turns on with Story 1.6, and the cost-cap state comes from Story 1.4.
  - `Agent.Input` and `Checks.Render` run against their Epic 0 stubs.
  - The real approval-event path waits for Stories 3.4 and 3.5, and for Story 30.3 in the case of a replay's `approval.result`.
- **Later epics that build on this one.**
  - Epic 5 needs `Session.Recipients`, and Epic 9 needs `Intake`'s `EvalSink` path.
  - Story 4.5's `SimPhoneOut` turns on the phone half of the 5 s check. Story 4.6 reuses the `Decide` double.
  - Story 10.2 checks the README links the page shows.
  - Story 12.7 turns on `Included()` and the README's Telegram link. Epic 12 calls `Delivery`, `Allowance` and `Trace.Join` directly.
  - Story 16.3 extends Ownership's session resolution, and Story 16.9 builds the allowance refusal.
  - Story 30.2 adds the purge task that calls `Live`'s `Purge` (until then, tests call the declaration directly). Story 31.1 adds the WebSocket, and Story 31.3 adds the About dialog's bridge-guide and security-overview links.
  - Story 11.1 turns on every check still waiting on a "turns on when … merges" clause.
