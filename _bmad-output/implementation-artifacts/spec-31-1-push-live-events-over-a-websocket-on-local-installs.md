---
title: 'Push live events over a WebSocket on local installs'
type: 'feature'
created: '2026-10-30'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md']
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The page gets live events only by polling `GET /api/v1/events` (1 s after each answer). On a local or IPM install an update can wait a whole poll cycle. AD-12 plans a WebSocket as the second live path, built after polling and never replacing it (FR-12, NFR-9).

**Approach:** Add a new `%CSP.WebSocket` class, `OcuTalon.Web.Live`. It is reached through a new `GET /v1/live` route entry of `/ocutalon/api`, which was measured working on build 154U. The AC's `/ocutalon/OcuTalon.Web.Live.cls` is served by the contended Shell and never reaches the class. The socket sends each committed event after the client's cursors, in `/events`' own body `{epoch, events}`. The page's live service opens it after the first snapshot on a non-demo install and feeds every frame to the same `applyEvents` path. Polling keeps running, unchanged, beside it.

## Boundaries & Constraints

**Always:**
- **Polling stays the contract.**
  - `poll`, `schedulePoll`, `applyPoll`, `fetchSnapshot`, `POLL_DELAY_MS`, `POLL_TIMEOUT_MS`, the `ContactWatch` and the `answers` signal behave exactly as before.
  - Contact and the reconnecting banners (Story 2.11) are fed only by polling.
  - The socket delivers sooner, and applies nothing that polling would not.
- **The online demo never gets a socket.** With the online-demo flag set:
  - Client side (`snapshot.onlineDemo === true`), the page never constructs a WebSocket.
  - Server side (`Data.Setting.Get("onlineDemo") = 1`), the socket refuses before `Server()` runs (S13: an open socket keeps its CSP session and a licence connection alive with no timeout).
- **Every check runs in `OcuTalon.Web.Live.OnPreServer`, before `Server()`, so a refused socket never gets a frame.** The class guards itself whichever application reaches it. The checks are:
  - the user role (`Web.Public.Shell.HasRole()`);
  - not the online demo;
  - a non-empty `Origin` equal to the request's own scheme and Host (the same rule as `Api.EnvelopeError`'s `wrong_origin`);
  - the session from `Data.Ownership.SessionRef` (the CSP session, never request input; AD-4);
  - the cursors `after` and `afterInstance`, which must be 1 to 15 digits.

  Sign-in itself comes first: `ApiBase.Login` answers 401 without a session.
- **Every frame is the polling body.** A frame is `##class(OcuTalon.Web.Api).EventsBody(session, sessionCursor, instanceCursor).%ToJSON()`. That gives one envelope `{seq, stream, ts, type, payload}`, streams labelled `session` or `instance`, trace URLs added by `Web.TraceLink`, and no row ids.
- **The socket writes no table and no global** (AD-12/AD-13 web write rule). Waking uses `$SYSTEM.Event` named resources only. `Live.Publish` stays the only writer of events (AD-33).
- No key or token in IRIS, a log, a commit, the trace or the bundle.
- The socket path makes no announcement, moves no focus and shows no banner or message.

**Never:**
- **No edit to a contended path.** That covers:
  - `src/ocutalon/cls/OcuTalon/Web/Public/**` (the Shell included), `Web/SessionEvents.cls`, `Data/{Ownership,Session,Setting}.cls`, `Install/**`;
  - `web/e2e/banners/banners.spec.ts`, `web/e2e/support/floor.ts`, `web/e2e-online/**`;
  - `web/playwright.config.ts`, `web/package.json`, `web/scripts/playwright-projects.test.mjs`;
  - `docker/tests/lib-live.sh`, `ci/units.sh`;
  - `web/src/app/api/api-client.ts` (changed on unmerged `OCT-epic29`).
- No new web application, role, grant, CSP or gateway setting. No change to how anyone signs in or out.
- No new production item, message class, table or event type.
- No unit added to any CI group. No socket on the online demo. No change to approvals.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Session event while open | Signed-in local page, socket open, polls answered with their events stripped; `Publish(<session ref>, "reminder", p)` | The reminder shows on the page. A frame holds its envelope with `seq` = cursor + 1. No reload. | No error expected |
| Instance event | `Publish("instance", …)` while the socket is open | A frame holds it with `stream: "instance"` and it is applied (only the unit test's own stream is used; nothing publishes on the real instance stream) | No error expected |
| Cursors on connect | Upgrade `?after=s&afterInstance=i` | The first frame holds only events after `s` and `i`. Nothing the page holds is re-sent. | No error expected |
| Burst | More than `Live.Event.MAXEVENTS` (200) new events on a stream | Successive frames in `Seq` order until caught up | No error expected |
| Seq skip | A frame whose first session event is cursor + 2 | One snapshot reload through `fetchSnapshot`, cursors from the snapshot. Polling's schedule is unchanged. | No error expected |
| Repeat | The same event by poll and by socket | Applied once (`applyEvents` skips `seq` ≤ cursor) | No error expected |
| Socket blocked | `page.routeWebSocket` closes it | Polling delivers within 2 s. No banner and no message. | Reconnect backoff in background |
| Socket ends | Server lifetime reached, or network drop | The page reconnects in the background with its current cursors: 1 s after a socket that delivered a frame, otherwise backoff 1 s doubling to 30 s | Silent |
| Online demo | `onlineDemo` on | The page constructs no WebSocket. A hand-made upgrade gets no frame. | Refused in `OnPreServer` |
| Wrong or empty Origin | Upgrade with `Origin: http://evil.example`, or none | No frame; the connection closes | Refused in `OnPreServer` |
| Signed out / no role | No CSP session / user without `OcuTalonUser` | No frame (401 / 403 path) | Refused before `Server()` |
| Bad cursor | `after=x` or 16 digits | No frame | Refused in `OnPreServer` |
| Page stops | 401, Sign out, idle cap, epoch change, reset | The socket is closed and never reopened | n/a |
| Client closes | Close frame | The server loop ends within 0.5 s | `OnPostServer` runs |
| Quiet socket | No events for 25 s | Heartbeat frame `{epoch, events: []}`; nothing is applied | n/a |

</intent-contract>

## Code Map

**Server**

- `src/ocutalon/cls/OcuTalon/Live/Publish.cls` -- the only event writer.
  - `Publish` :62 unlocks at :101; signal the stream's resource after a successful commit and unlock.
  - `LastSeq` :42 is the committed head of a stream, read under a shared lock that waits for an open publish. The socket compares it with its cursors.
  - `RefreshGuide` :119 publishes `guide.state` through `Publish`, so it is covered.
- `src/ocutalon/cls/OcuTalon/Live/Event.cls` -- `Since` :37 (the allow-listed unchecked prepare; call it, never copy it), `MAXEVENTS` 200.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `/ocutalon/api`, shared by entry.
  - Routes and methods:
    - UrlMap :127-138;
    - `OnPreDispatch` :144 (role → 403 `no_role`; `EnvelopeError` exempts GET);
    - `Events` :191;
    - `CurrentSession` :900 (Private: `Ownership.SessionRef` + `Session.RefIndexOpen`);
    - `EventsBody` :934 (public; the frame builder, with `instanceStream` as a test seam);
    - `EnvelopeError` :954 (public; the one Origin rule);
    - `Fail` :966 (public);
    - `IsCursor` :1017 (Private, `?1.15N`).
  - The class doc comment lists the routes.
- `src/ocutalon/cls/OcuTalon/Web/Public/ApiBase.cls` -- `Login` answers 401 without a session (read only, contended).
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` -- `HasRole()` (public, reuse); `/(.*)` GET → `File`, which is why the AC URL never reaches a socket class (read only, contended).
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `SessionRef(.sc)` :139. Call it in `OnPreServer`, before `%CSP.WebSocket.Page` unlocks the session, because it may write `%session.Data` on a local install (read only, contended).
- `src/ocutalon/cls/OcuTalon/Web/TraceLink.cls` -- `Viewer`/`Add`; they use no `%request`, so they work in the socket process (inside `EventsBody`).
- Platform (gitignored reference source, read only):
  - `irislib/%CSP/WebSocket.cls`: `Page` :399 reads `HTTP_WEBSOCKET_ID` and HALTs without it; it calls `OnPreServer` before `InitializeServer`. In synchronous mode it unlocks the session and HALTs at the end. Asynchronous mode derives the class from the URL's last segment, so it is unusable behind a route.
  - `irislib/%SYSTEM/Event.cls`: one wakeup per signal, wakes ONE waiter; a process waits on one resource at a time; `Create` / `Clear` / `Signal` (returns 0 for a missing resource).
- `src/ocutalon/cls/OcuTalon/Test/Web/StubRequest.cls` -- `MakeCall(application, method, contentType, header, origin, host, secure)` :35.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- `TestRoutes` :905 pins exactly 12 routes; it is a shared surface. Session stubbing: `%session = ##class(%CSP.Session).%New("ZzX", 0)` plus `.Data("OcuTalon.SessionRef")` (:635-664). Own-stream `EventsBody` tests are at :756-825.
- `src/ocutalon/cls/OcuTalon/Test/Live/Publish.cls` -- fresh streams from `Bridge.Ids.NewRef()`, cleanup, and the `Job` patterns at :167 and :274 (pattern to mirror; not edited).

**Client**

- `web/src/app/live/live-state.ts` -- `LiveState`, the one live service.
  - `stop()` :149 (permanent).
  - `fetchSnapshot` :164.
  - `accept` :200 starts polling once.
  - `schedulePoll` :229, `poll` :244, `applyPoll` :267 (do not change these three).
  - `otherEpoch` / `changeEpoch` (pinned by `scripts/leave-sources.test.mjs`).
- `web/src/app/live/live-store.ts` -- `applyEvents(store, response)` :201 is the idempotent apply: a repeat is skipped, a skip gives `reload`, an epoch change gives `epochChanged`. `fromSnapshot` :114.
- `web/src/app/live/contact-watch.ts` -- polling's contact; the socket never calls `answered()`.
- `web/src/app/api/api-types.ts` -- `EventsResponse` :64, `StateSnapshot.onlineDemo` :50.
- `web/scripts/contact-watch.test.mjs` and `web/scripts/fake-clock.mjs` -- the pattern for a framework-free module test (`npm test` = `node --test scripts/*.test.mjs`).
- `web/scripts/announce-focus-sources.test.mjs` and `web/scripts/leave-sources.test.mjs` -- source pins. A new file must not announce or register `pagehide`, `visibilitychange` and the like.

**E2E**

- `web/e2e/support/iris.ts` -- `fixtureUser('LIVE')` :66 and `publishReminder(user)` :137 (through `docker exec … iris session`).
- `web/e2e/live/live.spec.ts` -- L1-L13, the LIVE fixture user; publishes only on that user's stream (api.spec pins the README session's and the instance stream's counts).
- Specs that steer delivery through routed polls. Each loses control once a socket also delivers:
  - `web/e2e/live/live.spec.ts` L10 :403 (tampers with the poll that carries a real publish);
  - `web/e2e/chat/chat.spec.ts` (:103 slices events, :111 `holdEvents`, :718 C8 filters `done`);
  - `web/e2e/chat/decision.spec.ts` D10 :448 (waits for a poll whose body carries the event);
  - `web/e2e/floor/guide.spec.ts` :470-478 (holds polls);
  - `web/e2e/support/api.ts` :98 (`POLLS` handler).
- `web/playwright.config.ts` :32-50 (read only) -- `workers: 1`. Project `chromium` = `e2e/**` except demo-path, demo-switch, floor, answers and cards, so a new `e2e/live/socket.spec.ts` joins the `sign-in` unit (browser group) with no config edit. `floor/guide.spec.ts` runs in `live:floor` (shards group).

## Tasks & Acceptance

**Execution:**

- [ ] `src/ocutalon/cls/OcuTalon/Live/Publish.cls` -- add the wake path and call it after each commit.
  - Add `WakeName(stream)`, which returns `$Name(^OcuTalonP.LiveWake(stream))`: a named resource only, never set as a global.
  - Add `Wake(stream)`: `$SYSTEM.Event.Signal(..WakeName(stream))`, which ignores a missing resource.
  - Call `Wake(stream)` in `Publish` after the commit and the unlock, only when `sc` is OK.
  - Update the class doc.
  - Why: AD-12 says "`Live.Publish` signals after each commit".
- [ ] `src/ocutalon/cls/OcuTalon/Web/Live.cls` (new, extends `%CSP.WebSocket`, synchronous mode) -- the socket.
  - `Accept()` class method:
    - with an empty `HTTP_WEBSOCKET_ID`, answer `Api.Fail(400, "not_websocket", …)`, because `Page` HALTs without one;
    - otherwise `Do ##class(%Library.Device).ReDirectIO(0)` then `Quit ..Page()`.
  - `OnPreServer()` runs every check in the Always list. `OriginError(origin, host, secure)` delegates to `Api.EnvelopeError("POST", "application/json", 1, origin, host, secure)` so the Origin rule stays in one place. It keeps `SessionRef`, both cursors and `InstanceStream` (default `Publish.#INSTANCE`; a test seam), creates both wake resources, and `Clear`s queued wakeups.
  - `Server()` loop:
    1. Send batches while either `LastSeq` is above its cursor, advancing each cursor to the highest `seq` sent on that stream.
    2. `Wait` 0.25 s on the session's resource, then 0.25 s on the instance resource. Each wakes one waiter; the `LastSeq` check makes every socket correct either way.
    3. `Read(, .sc, 0)`, then end on code 7951 (closed) or any error but 7950 (timeout).
    4. Send a heartbeat frame every `HEARTBEAT` = 25 s.
    5. `EndServer()` after `LIFETIME` = 60 s (Q1, pending).
    6. A `LastSeq` that throws is retried next loop.
  - Why: AC 1.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- add the route entry `<Route Url="/v1/live" Method="GET" Call="Live"/>` and `ClassMethod Live()` (`Quit ##class(OcuTalon.Web.Live).Accept()`). Add one class-doc line for `GET /v1/live`. Why: the routing decision (measured M2).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- `TestRoutes`: 13 routes, adding `"GET /v1/live Live"`; update the header's "12 routes". Why: Rule 19 shared surface.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Live.cls` (new) -- `%UnitTest`, each test with its own streams and cleanup.
  - Covers: `OnPreServer` with a stub request and session (role, online demo, Origin wrong/empty/right, cursors bad/good, no session); `OriginError`; and the batch builder (cursor advance, more than `MAXEVENTS`, envelope labels, `traceUrl` present, epoch).
  - Unit-test every matrix row that does not need a gateway.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Live/PublishWake.cls` (new) -- a `Job`'d waiter on `WakeName(<fresh ref>)` wakes within 1 s of a `Publish` on that stream. No wake for a failed publish, and none for another stream.
- [ ] `web/src/app/live/live-socket.ts` (new, framework-free, erasable syntax) -- `LiveSocket`.
  - Injected: the WebSocket factory, timers, `location {protocol, host}`, `cursors()` and `onEvents(EventsResponse)`.
  - `start(snapshot)` returns at once when `snapshot.onlineDemo === true`. Otherwise it opens `ws(s)://<host>/ocutalon/api/v1/live?after=<s>&afterInstance=<i>` with the current cursors.
  - It parses each text frame as `EventsResponse` and ignores a malformed frame.
  - On close or error it reconnects after 1 s when the socket delivered a frame, otherwise with a 1 s backoff doubling to 30 s.
  - `stop()` closes and never reopens. No announcement, no focus, no banner.
- [ ] `web/src/app/live/live-state.ts` -- wire the socket.
  - In `accept()`, after polling starts the first time, call `socket.start(snapshot)`.
  - New `applyPushed(response)`: `applyEvents` → `otherEpoch`/`changeEpoch` → on `reload` `fetchSnapshot(() => undefined, undefined, POLL_TIMEOUT_MS)` → `store.set`. No `watch.answered()`, no `answers`, no `schedulePoll`.
  - `stop()` also calls `socket.stop()`.
  - Update the class doc. Leave `poll`/`schedulePoll`/`applyPoll`/`fetchSnapshot` byte-identical.
- [ ] `web/scripts/live-socket.test.mjs` (new) -- node tests with `fake-clock.mjs` and a fake WebSocket. Cases: the URL and cursors, frames to `onEvents`, a malformed frame, reconnect timing both ways, `stop()`, and online demo with no socket constructed.
- [ ] `web/e2e/support/socket.ts` (new) -- the socket helpers for the specs.
  - `LIVE_SOCKET` (`/\/ocutalon\/api\/v1\/live/`).
  - `blockLiveSocket(page)`: `page.routeWebSocket(LIVE_SOCKET, ws => ws.close())`.
  - `socketFrames(page)`: records frames through `page.on('websocket')`.
  - `rawUpgrade({port, path, origin, cookie})`: a Node `net` handshake that returns the status line and whether any data frame arrived within 3 s.
- [ ] `web/e2e/live/socket.spec.ts` (new; LIVE fixture user; publishes only on that user's stream) -- these cases, with W1 to W4 also asserting no banner and no new live-region text:
  - W1: with polls answered event-free (`route.fetch` then `events: []`), a `publishReminder` shows on the page within 2 s and its `seq` is in a received frame. Log the ms, labelled (inference).
  - W2: with `blockLiveSocket`, polling delivers it within 2 s.
  - W3: the socket's URL carries the page's `data-session-seq` and `data-instance-seq`.
  - W4: after the socket closes it is reopened, and an event still arrives through it.
  - W5: `rawUpgrade` with a wrong Origin gets no frame.
  - W6: `rawUpgrade` without a cookie gets no frame.
  - W7: after `stop()` (sign out), no socket is reopened.
- [ ] Existing specs that steer delivery through polls (Q2, pending) -- add `blockLiveSocket(page)` to each test that routes `/events` while publishing, or waits for a poll's body. Assertions stay unchanged.
  - Files: `web/e2e/live/live.spec.ts` (L10), `web/e2e/chat/chat.spec.ts` (`holdEvents`, the `:103` helper's users, C8), `web/e2e/chat/decision.spec.ts` (D10), `web/e2e/floor/guide.spec.ts` (held polls), `web/e2e/support/api.ts` (`POLLS` handler).
  - First grep `web/e2e` for `v1/events` and `EVENTS` to find every other one. `banners.spec.ts` needs none, because contact stays polling's.
- [ ] `_bmad-output/implementation-artifacts/spec-31-1-…md` `## Verification` -- record the measured minutes of `socket.spec.ts` and of both `sign-in` parts before and after, the `live:floor` change, and one `mutation:` line per AC.

**Acceptance Criteria:**
- **AC 1 (the server).**
  - Given a signed-in session with the user role on a local or IPM install,
  - when the page opens the WebSocket `/ocutalon/api/v1/live?after=<s>&afterInstance=<i>` (AC URL amendment candidate A1),
  - then `OcuTalon.Web.Live` has checked the role, the online-demo flag, `Origin`, the session (from the CSP session) and the cursors before `Server()` runs, and a refused socket gets no frame. It waits on the session's `$SYSTEM.Event` resource and one instance resource, which `Live.Publish` signals after each commit, and sends each new event after the client's cursors in the envelope `{seq, stream, ts, type, payload}` inside `{epoch, events}`, with trace URLs (AD-12, AD-13).
- **AC 2 (the client).**
  - Given the page's live-event service,
  - when it starts,
  - then on a local or IPM install it receives events over the WebSocket and applies them through `applyEvents`, the same idempotent path as polling. A `Seq` skip reloads the snapshot. With `onlineDemo` set it never constructs a WebSocket and only polls. If the socket closes or fails, delivery continues by polling with no message, and the socket reconnects in the background. Polling's cadence, contact and banners are unchanged (FR-12, AD-12, UX-DR91, UX-DR149).
- **AC 3 (CI).**
  - Given the CI demo-path environment (the browser group's throwaway stack with the model mock),
  - when `web/e2e/live/socket.spec.ts` runs in the `sign-in` unit,
  - then an event published while the socket is open reaches the page through it (W1), and with the socket blocked polling still delivers it (W2). The 2-second bound is checked against the mock and measured over real networks only in the rehearsal (NFR-9).
- **AC 4 (integration).**
  - Given a fresh throwaway stack,
  - when the consumer `LiveState` reads from the socket,
  - then the published reminder appears on the page with no poll carrying it (W1, a real instance, no mock socket).
- **AC 5 (regression).**
  - Given the existing L, B, S, C, D and guide specs,
  - when they run with this change,
  - then all pass with their assertions unchanged.

## Spec Change Log

- 2026-10-30, lead (runner B): the plan HALTed `blocked` on Q1 and Q2 (with A1/A2). Rulings written under ## Design Notes: Q1 → U-174 (orchestrator, veto: checks before `Server()`, page close in `stop()`, 60 s lifetime; conditions (a)–(d) as tests; DW-457 for the server-side sign-out check), A2 → U-175 (orchestrator, veto: no AD-13 amendment; the shell forwards the socket at the AC's URL; A1 withdrawn; the story waits on Epic 29), Q2 → U-173 (runner, veto: polling unchanged beside the socket; specs block it with a helper that never edits `web/e2e/support/floor.ts` or `web/e2e/banners/banners.spec.ts`). Status reset to `draft`, so the spec is re-planned for the shell route once Epic 29 merges (re-measure M2 in the shell application). Ledger inbox at the re-plan: DW-457.

## Review Triage Log

## Design Notes

**Rulings on this plan's questions (2026-10-30, policy 6df0676; these govern the re-plan and override the "Decided in-stage" items and recommendations below wherever they differ):**
- **Q1 → U-174 (orchestrator ruling, veto): recommendation 1–3 kept.**
  - `OnPreServer` checks the role, the online-demo flag (the server refuses too), `Origin` and the session before `Server()`; a refusal sends no frame.
  - The page closes its socket in `LiveState.stop()`.
  - The server ends each socket after a fixed 60-second lifetime and the page reconnects silently, so every reconnect re-runs the checks.
  - Conditions, each one a test: (a) every refusal case (no session, missing role, wrong or missing `Origin`, the online-demo flag) sends no frame; (b) after sign-out, the page's socket closes within one poll; (c) the server closes the socket at the lifetime, and the page reconnects with the checks re-run (the lifetime may be shortened in tests); (d) no session id, cookie or token appears in any frame or log.
  - **Known cost:** a client that ignores the page's close keeps reading its own session's events for up to 60 s after sign-out (M5). The server-side sign-out check (a mark set at sign-out and read on each socket loop) needs `Data/Session.cls`, contended with Epic 29: ledger DW-457, routed to this story, for after Epic 29 merges.
- **A2 → U-175 (orchestrator ruling, veto): no AD-13 amendment; comply first (U7 step 1).**
  - AD-13 already allows "forwarded by the shell", at the AC's own URL `/ocutalon/OcuTalon.Web.Live.cls`, so U7 step 2 does not apply; U14 also bars an amendment while other in-flight epics' specs cite AD-13 (Epic 29's do).
  - So the socket is forwarded by the shell: a `Web/Public/Shell.cls` route for `/OcuTalon.Web.Live.cls`, placed before `/(.*)`, that hands the request to `OcuTalon.Web.Live.Page()` in synchronous mode (M2's handoff mechanism). `Web/Public/Shell.cls` is Epic 29's contended path, so this story waits on Epic 29's merge (`story_waiting … on=29`).
  - **A1 is withdrawn:** AC 1's URL stays as written. Route (c), `/ocutalon/api/v1/live`, is NOT planned; "Decided in-stage" item 1 is superseded.
  - **The re-plan after Epic 29 merges must re-measure M2's handoff inside the shell application** (`/ocutalon`, `OcuTalon.Web.Public.Shell`): the role, `%session` and SessionRef, the headers, the cursors, a concurrent `/state`, `Api.EventsBody`/`TraceLink` and the `$SYSTEM.Event` wake. It also re-reads Epic 29's merged Shell, Session and banner changes.
  - If the owner's delegate reverses U-175 to route (c), this spec as first planned applies.
- **Q2 → U-173 (runner ruling, veto): polling keeps running unchanged beside the socket.** Contact and the banners stay polling's; the socket only delivers sooner, through the same idempotent apply path. The routed-poll specs block the socket for their tests with one shared helper (`page.routeWebSocket`), their assertions unchanged. Orchestrator guards: the helper must not edit `web/e2e/support/floor.ts` or `web/e2e/banners/banners.spec.ts` (both changed on Epic 29's unmerged branch), and every spec file it touches is reported under `footprint_extensions:`. (The lead's earlier wording "polling's tests stay as they are" was a gloss, not owner-fixed; the owner-fixed rule is "polling is the release-1 contract".)

**Governing ADs (Rule 6):**
- **AD-12:** polling first and the contract; the socket second; never on the online demo; one envelope and one idempotent apply; skip → reload; trace URLs on the socket; the session and instance resources signalled by `Publish`.
- **AD-13:** the API application and its 401/403; the `Origin` check before accept; no CORS allow-list; the web write rule; "forwarded by the shell or moved to its own application, as its story decides" (see A2).
- **AD-4:** the session from the CSP session.
- **AD-33** and AD-1: `Publish` is the only event writer; the socket writes nothing.
- **AD-3:** `Web.Live` sits in the code database, not the public package.
- **AD-22:** tests on throwaways.

**Task 0, measured in this plan stage** (throwaway warm stack `e31s1planw` on build 154U, lane B, torn down). The probe classes and client stayed outside the tree.
- **M1.** A signed-in upgrade to `/ocutalon/OcuTalon.Web.Live.cls` never reaches the class (no `OnPreServer` call). The Shell's `File` route takes it, so (a) would need a Shell edit (Epic 29, contended).
- **M2.** A route entry in `OcuTalon.Web.Api` whose method calls `OcuTalon.Web.Live.Page()` works in synchronous mode:
  - The handshake and frames work both ways.
  - The socket process runs as the signed-in user with `OcuTalonUser` and the application roles in `$Roles`, and has `%session.SessionId`, `%session.Data("OcuTalon.SessionRef")`, `HTTP_ORIGIN`, `HTTP_HOST` and the query cursors.
  - A concurrent `GET /state` on the same session answered in 0.01 to 0.49 s (the session is unlocked).
  - `Api.EventsBody` and `TraceLink` work in it, and a `$SYSTEM.Event.Signal` reached the waiting socket with no measurable delay.
  - It works with `ReDirectIO` left on and with it turned off; the plan turns it off, the raw-device form the class writes.
- **M3.** The built-in web server answers every upgrade with `101` before any IRIS code runs. Every refusal therefore shows as `101` then an immediate close with no frame:
  - no session (ApiBase 401);
  - an `OnPreServer` error (wrong Origin);
  - a frame-less open on the M1 URL.

  This holds for any WebSocket on this gateway; no config file exists to change it.
- **M4.** `Read(, .sc, 0)` returns at once with error 7950 when no data waits, returns client data, and returns 7951 on a client close. The loop saw a close within one 0.25 s slice. `EndServer()` gives the client a clean close 1000.
- **M5.** While a synchronous socket is open, signing out does not reach it. This was tried both through `POST /v1/session/end` (204) and through `?IRISLogout=end`:
  - The next HTTP `/state` is 401.
  - The socket's `%CSP.Session` (`%ExistsId`, `%OpenId`: user, security context, `SessionRef`) stays unchanged for at least 10 s.
  - The socket keeps reading and writing.

  See Q1.
- **M6.** `%SYSTEM.Event` (documented in `irislib/%SYSTEM/Event.cls`): a signal wakes one waiter or queues one wakeup, and a process waits on one resource at a time. That is why the loop alternates the two resources and re-checks `LastSeq`. The AC and AD-12 mechanism is kept literally, and every socket stays correct with two tabs or many sessions.

**Decided in-stage:**
1. **Route (c), `/ocutalon/api/v1/live`.** M1 and M2 measured it; it stays inside the footprint; (a) and (b) touch contended paths. A1 and A2 record the amendments.
2. **The literal AD-12 resources.** Alternating 0.25 s waits plus a `LastSeq` check. This avoids both an AD amendment and a socket registry, which would be a web-layer write. Latency is at most about 0.5 s for a socket the signal did not wake (inference until W1's log).
3. **Synchronous mode**, because asynchronous mode needs the URL to name the class.
4. **All checks inside `Web.Live`**, defence in depth: a namespace-default CSP application could name a `%CSP.Page` class directly (inference).
5. **The server refuses on the online demo too**, not only the client: S13, and a visitor could hand-open sockets.
6. **The socket spec reuses the LIVE fixture user** (`workers: 1`; each L test reads its cursor fresh), so `test-sign-in.sh` and `FixtureKind` stay unedited.
7. **The socket URL constant lives in `live-socket.ts`**, because `api-client.ts`'s `BASE` is not exported and the file is changed on `OCT-epic29`.
8. **Named resources are never deleted.** `Clear` at socket start drops stale queued wakeups. That leaves one resource per session that ever opened a socket, plus one instance resource (inference: negligible locally).
9. **"CI demo-path environment"** means the browser group's throwaway stack with the mock; the spec runs in the `sign-in` unit. `e2e/demo-path/` stays the UJ-1 test alone.

**Extend, don't copy (Rule 2):**
- The frame is `Api.EventsBody` and the Origin rule is `Api.EnvelopeError`, both called rather than copied.
- `applyPushed` reuses `applyEvents`, `otherEpoch`, `changeEpoch` and `fetchSnapshot`. It is not a copy of `applyPoll`: it leaves out contact and scheduling, which are polling's by the owner rule.
- **Copy:** the `?1.15N` cursor check copies `Api.IsCursor`. Reason: that method is Private in an Api entry this story does not own, and `Web.Live` must check for itself (decision 4).
- **Copy:** the 2-line `SessionRef` + `RefIndexOpen` copies `Api.CurrentSession`, which is Private, for the same reason.
- `LiveSocket` follows `ContactWatch`'s injected-timer shape.

**Integration:** consumer `LiveState`, on the page, reads from the socket and the event shows (W1, AC 4).
- Consumes: `Live.Publish` (Story 0.5), `Live.Event.Since` and `Api.EventsBody` (2.2), `Web.TraceLink` (2.9), `Data.Ownership.SessionRef` (2.2), `LiveState` and `live-store` (2.2, 2.11, 16.3, 16.4).
- Consumed-by: the page (this story). Every later publisher (for example Story 31.2's approval results) reaches the socket through `Live.Publish` with no change.

**Ledger inbox:** none owned. **Footprint extensions:**
- Existing e2e specs (only if Q2 is answered as recommended): `web/e2e/live/live.spec.ts`, `web/e2e/chat/chat.spec.ts`, `web/e2e/chat/decision.spec.ts`, `web/e2e/floor/guide.spec.ts`, `web/e2e/support/api.ts`. None is contended or changed on another unmerged branch (checked with `git diff` against each `OCT-epic*` branch's merge base).
- `Test/Web/Api.cls` `TestRoutes`, a shared-surface edit.

**Amendment candidates for the lead (Rule 5 / Rule 20):**
- **A1.** AC 1's URL `/ocutalon/OcuTalon.Web.Live.cls` becomes `/ocutalon/api/v1/live`. Evidence: M1/M2; this corrects an AC-cited name. The spine's REST surface row (`WebSocket /ocutalon/OcuTalon.Web.Live.cls`) changes with it.
- **A2.** AD-13's "forwarded by the shell or moved to its own application, as its story decides" gains "or served by a route of `/ocutalon/api`", which is neither listed option. The lead classifies this: a name correction, or an AD amendment (veto window 9).

**Clarification Needed (this stage HALTs on Q1 and Q2):**
- **Q1 (security posture, veto window).** M5 shows that the server cannot see a sign-out while a socket is open. M3 shows that refusals arrive as `101` then close. How must "serves only a signed-in session" hold after accept?
  - Recommendation:
    - every check before `Server()`, with no frame on refusal;
    - the page closes its socket in `LiveState.stop()`, which a 401, Sign out, the idle cap and an epoch change all reach;
    - the server ends each socket after a fixed 60 s lifetime and the page reconnects silently, so every reconnect re-runs sign-in, role and Origin.
  - The exposure after sign-out is then at most 60 s, for a client that ignores the page's close.
- **Q2 (owner-fixed "polling's code path, cadence and tests stay as they are").** As worded it can't hold, because Playwright's `page.route` does not intercept WebSockets. The specs listed in the Code Map steer delivery through routed polls, and with any socket open they lose control and fail. Pausing polling while the socket is open would also break L1, L8, L12, L13 and the contended B13-B19.
  - Recommendation:
    - polling runs unchanged beside the socket, and contact and banners stay polling's;
    - those specs call `blockLiveSocket(page)` for their tests, with their assertions unchanged;
    - no contended file is edited.

## Verification

Lane variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=31 stage=implement'`. Use tags `e31s1i` (fresh) and `e31s1iw` (warm). Pass `timeout: 600000` on every call, and make one test-runner call per message.

**Commands:**
- (loop) `npm --prefix web test` -- expected: every `scripts/*.test.mjs` passes, `live-socket.test.mjs`, `announce-focus-sources` and `leave-sources` included.
- (loop) `npm --prefix web run lint` -- expected: exit 0.
- (loop) `OCUTALON_RUN_TAG=e31s1iw ci/warm.sh up` once, then one call each:
  - `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s1iw ci/iris.sh class OcuTalon.Test.Web.Live`
  - `… class OcuTalon.Test.Live.PublishWake`
  - `… class OcuTalon.Test.Web.Api`
  - `… class OcuTalon.Test.Live.Publish`

  Expected: `CLASS … passed`. Then `OCUTALON_RUN_TAG=e31s1iw ci/warm.sh down`.
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh build` -- expected: the bundle is rebuilt with the client change.
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh live sign-in --part 1/2`, then `… --part 2/2` -- expected: both pass (W1 to W7 and every existing L, S, C and D spec). Record each part's seconds.
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh live floor` -- expected: passes (`guide.spec.ts`).
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh live demo-path` -- expected: passes (the demo path stays green).
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh shard lane-b`, then `… shard lane-b --reverse` -- expected: every class passes on fresh stacks in both orders (Rule 19).
- (once) `bash ci/checks.sh` and `bash docker/tests/test-ci-config.sh` -- expected: all pass (class rules: no unchecked prepare outside the allow-list; boundaries: ASCII, no local paths).
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh teardown`.

**Shared surfaces:**
- `OcuTalon.Web.Api`'s route list (`Test.Web.Api.TestRoutes`, 12 → 13).
- The `chromium` project's spec list (a new file; derived from disk, so no pinned count).
- No stream counts: tests publish only on their own fresh streams or the LIVE user's stream, never the README session's or the instance stream.

Every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to apply (the implement stage records `mutation: … → …` here):**
- **AC 1.** Remove the `Wake(stream)` call in `Publish` → `Test.Live.PublishWake` goes red. Drop the Origin check in `OnPreServer` → `Test.Web.Live`'s wrong-Origin test and W5 go red.
- **AC 2.** Remove the `onlineDemo` return in `LiveSocket.start` → `live-socket.test.mjs`'s online-demo case goes red.
- **AC 3.** Make `LiveState.accept` skip `socket.start` → W1 goes red. Make the socket start pause polling → W2 or L1 goes red.
- **AC 4.** Same as W1.

**Manual checks:**
- In `git diff`, `poll`, `schedulePoll`, `applyPoll` and `fetchSnapshot` in `live-state.ts` are unchanged.
- No contended path appears in `git status --short`.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: (Q1, security posture, veto window) Measured on a throwaway (build 154U): while a WebSocket is open, signing out (`POST /v1/session/end`, and `?IRISLogout=end`) makes the next HTTP request 401 but leaves the socket's CSP session object unchanged (same user, security context and SessionRef) for at least 10 s, so the server cannot see the sign-out and the socket keeps serving; and the built-in web server answers every upgrade with 101 before IRIS code runs, so each refusal (no session, no role, wrong Origin, online demo) shows as 101 then an immediate close with no frame. How must "serves only a signed-in session" hold after accept? Recommendation: every check before Server() (no frame on refusal); the page closes its socket in LiveState.stop() (401, Sign out, idle cap, epoch change); and the server ends each socket after a fixed 60 s lifetime with a silent reconnect, so each reconnect re-runs the sign-in, role and Origin checks (exposure after sign-out at most 60 s for a client that ignores the page's close). (Q2, owner-fixed "polling's code path, cadence and tests stay as they are") Unreachable as worded: Playwright's page.route does not intercept WebSockets, and existing specs steer delivery through routed polls (live.spec.ts L10, chat.spec.ts holdEvents/the :103 helper/C8, decision.spec.ts D10, floor/guide.spec.ts held polls, support/api.ts POLLS), so with a socket open they lose control and fail; pausing polling while the socket is open would also break L1/L8/L12/L13 and the contended banners.spec.ts B13-B19. Recommendation: polling keeps running unchanged beside the socket (contact and banners stay polling's; the socket only delivers sooner), and those specs block the socket for their tests with one shared helper (page.routeWebSocket), assertions unchanged; no contended file is edited. Also for the lead, not blocking: amendment candidates A1 (AC 1's URL becomes /ocutalon/api/v1/live; /ocutalon/OcuTalon.Web.Live.cls was measured to land in the contended Shell) and A2 (AD-13's "forwarded by the shell or moved to its own application" and the spine's REST-surface row).
