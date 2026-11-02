---
title: 'Push live events over a WebSocket on local installs'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: '1c972cc8e3619d3cb727b8bcb1a7b4d7f7fd67c4'
baseline_commit: '1c972cc8e3619d3cb727b8bcb1a7b4d7f7fd67c4'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md']
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The page gets live events only by polling `GET /api/v1/events` (1 s after each answer). On a local or IPM install an update can wait a whole poll cycle. AD-12 plans a WebSocket as the second live path, built after polling and never replacing it (FR-12, NFR-9).

**Approach:** Add a new `%CSP.WebSocket` class, `OcuTalon.Web.Live`. It is reached at the AC's own URL, `/ocutalon/OcuTalon.Web.Live.cls`, forwarded by the shell (AD-13: "forwarded by the shell"): a `Web/Public/Shell.cls` route for `/OcuTalon.Web.Live.cls`, placed before `/(.*)`, hands the request to `OcuTalon.Web.Live.Page()` in synchronous mode (U-175; route (c) `/ocutalon/api/v1/live` is not planned, and M2's handoff is re-measured inside the shell application). The sign-out sets a server-side mark in `Data/Session.cls` that the socket reads on each loop, so an open socket sends no further frame within one loop after sign-out; a fixed 60-second socket lifetime stays as a backstop (U-174). The socket sends each committed event after the client's cursors, in `/events`' own body `{epoch, events}`. The page's live service opens it after the first snapshot on a non-demo install and feeds every frame to the same `applyEvents` path. Polling keeps running, unchanged, beside it (U-173). [AMENDED 2026-11-01, lead (runner C) at the re-plan, applying rulings U-173/U-174/U-175 and the owner's answers already recorded under ## Design Notes; it read: "It is reached through a new `GET /v1/live` route entry of `/ocutalon/api` … The AC's `/ocutalon/OcuTalon.Web.Live.cls` is served by the contended Shell and never reaches the class."]

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

  Sign-in itself comes first: without a session the shell (`Shell.Login()`) answers with the sign-in page, and the socket gets no frame. [AMENDED 2026-11-01, lead (runner C), wording only, after the shell route: it read "`ApiBase.Login` answers 401 without a session".]
- **Every frame is the polling body.** A frame is `##class(OcuTalon.Web.Api).EventsBody(session, sessionCursor, instanceCursor).%ToJSON()`. That gives one envelope `{seq, stream, ts, type, payload}`, streams labelled `session` or `instance`, trace URLs added by `Web.TraceLink`, and no row ids.
- **The socket writes no table and no global** (AD-12/AD-13 web write rule). Waking uses `$SYSTEM.Event` named resources only. `Live.Publish` stays the only writer of events (AD-33).
- No key or token in IRIS, a log, a commit, the trace or the bundle.
- The socket path makes no announcement, moves no focus and shows no banner or message.

**Never:**
- **No edit to a contended path** (open epics' paths as of 2026-11-01; re-check with `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` before editing an existing file). That covers:
  - Epic 11's: `src/ocutalon/cls/OcuTalon/Web/Api.cls` (read `EventsBody` only, never edit), `Data/Pairing.cls`, `web/src/app/api/api-types.ts`, `web/src/app/live/live-store.ts`, `web/e2e/support/{approvals,demo-path,devices,iris,navigate,rehearsal,trace}.ts`, `ci/units.sh`, `release/**`, `Test/Live/Payloads.cls`;
  - Epic 4's: `web/src/app/**` except one self-contained block in `web/src/app/live/live-state.ts` and new files (`live/live-socket.ts`); in `web/e2e/floor/guide.spec.ts` only this story's held-poll lines; `web/scripts/*.test.mjs`;
  - Epic 12's: `docker/tests/lib-live.sh`, Telegram; Epic 30's: the bridge, Checks, Fix, Tasks, `Install/Step/{Retention,Watch}`;
  - standing: `web/e2e/banners/banners.spec.ts`, `web/e2e/support/floor.ts`, `web/e2e-online/**` (U-173), `web/playwright.config.ts`, `web/package.json`, `Install/**`.
  - Free since Epic 29 merged, and this story's to edit: `Web/Public/Shell.cls` (the forwarding route only) and `Data/Session.cls` (the sign-out mark only). [AMENDED 2026-11-01, lead (runner C): the contended list re-computed after Epic 29 merged; it listed `Web/Public/**`, `Web/SessionEvents.cls`, `Data/{Ownership,Session,Setting}.cls`, `Install/**`, `web/e2e/banners/banners.spec.ts`, `web/e2e/support/floor.ts`, `web/e2e-online/**`, `web/playwright.config.ts`, `web/package.json`, `web/scripts/playwright-projects.test.mjs`, `docker/tests/lib-live.sh`, `ci/units.sh`, `web/src/app/api/api-client.ts`.]
- No new web application, role, grant, CSP or gateway setting. No change to how anyone signs in, or to what a sign-out does beyond also setting the server-side mark (U-174).
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

Line numbers are at the worktree head (feature 416b0f64) unless marked "feature": those are at feature `02e91b21`, which holds Epic 4's merge (`374f958e`, after this worktree's base). The implement stage starts on a head that includes that merge (see Design Notes, "For the lead").

**Server**

- `src/ocutalon/cls/OcuTalon/Live/Publish.cls` -- the only event writer (AD-12, AD-33).
  - `Publish` :62 commits, then unlocks at :101. The wake goes after that unlock, only when `sc` is OK, for every stream (the instance stream included).
  - `LastSeq` :42 is the committed head of a stream (a shared lock that waits for an open publish; it throws after `LOCKWAIT`). The socket compares it with its cursors.
  - `RefreshGuide` :119 publishes `guide.state` through `Publish`, so it is woken too.
  - `^OcuTalonP.LiveEventC(stream)` :6, :80 is the precedent for a counter global kept beside a class's storage (the sign-out mark follows it).
- `src/ocutalon/cls/OcuTalon/Live/Event.cls` -- `Since` :34 and `MAXEVENTS` :11 (200). Reached only through `Api.EventsBody`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- READ ONLY (Epic 11 changes it; its hunks are at :27, :555, :579, :819, :836).
  - Call: `EventsBody` :934 (public; the frame; `instanceStream` is the test seam), `EnvelopeError` :954 (public; the one Origin rule, applied for a non-GET method).
  - Do not call or copy beyond the two copies named in Design Notes: `CurrentSession` :900 and `IsCursor` :1017 are Private.
  - `EndSession` :215 signs out with `%session.Logout(1)` :230, which runs the event class's `OnLogout` (measured T3).
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` -- the `/ocutalon` dispatch class (public package, AD-3).
  - UrlMap :40-47: the new route goes between `/` :43 and `/(.*)` GET :44.
  - `OnPreDispatch` :73 already ends a no-role session and shows the sign-in page; `Login()` :58 answers a request without a session (measured T6: no frame).
  - `HasRole()` :142 (public; reuse).
  - Class doc :1-16 gains one bullet for the route.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls` -- `/ocutalon`'s session events (Lane B; not contended).
  - `OnLogin` :43 / `AttachFor` :50 are the shape to follow: always answer OK, catch everything, log without the user name (`Log` :142).
  - The class doc :26-27 says it has no `OnLogout`. That line is rewritten.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls` -- Lane B's session row. DEFAULTGLOBAL `^OcuTalonP.Session` :16 (`D`, `I`, `S` in use; `M` is free). The mark adds two class methods and no property, so the storage block :185-234 and `Test.Data.Tables`'s Session contract are unchanged.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `SessionRef(.sc)` :139. Call it in `OnPreServer`: `Page` runs `OnPreServer` before it unlocks the session, and on a local install `SessionRef` may write `%session.Data` (Attach). READ ONLY.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- `Get("onlineDemo")` :39.
- `src/ocutalon/cls/OcuTalon/Web/TraceLink.cls` -- used inside `EventsBody`; it needs no `%request` (measured in the earlier plan).
- Platform (gitignored reference source, read only):
  - `irislib/%CSP/WebSocket.cls` `Page` :399. It HALTs without `HTTP_WEBSOCKET_ID`. It calls `OnPreServer` before `InitializeServer`. In synchronous mode it takes a shared lock on the CSP session id, unlocks the session, runs `Server()` and `OnPostServer()`, then HALTs. Asynchronous mode takes the class from the URL's last segment, so it is not used.
  - `irislib/%CSP/Session.cls` `Logout` :1170: it calls each event class's `OnLogout` first, and an error status stops a non-forced logout. So `OnLogout` must always answer OK.
  - `irislib/%SYSTEM/Event.cls`: a signal wakes one waiter or queues one wakeup; a process waits on one resource at a time; `Signal` on a missing resource returns 0.
- Tests to extend (lane-b areas): `Test/Live/Publish.cls` (fresh streams from `Bridge.Ids.NewRef()`; the `Job` patterns at :163 and :270); `Test/Web/SessionEvents.cls` (stand-in `%session` and settings save/restore, for example `TestFlagOff` :497); `Test/Data/Session.cls`; `Test/Web/Shell.cls` (stub request pattern :42); `Test/Web/LeavingThePage.cls` `TestNoProductClassEndsASessionOnTimeout` :74 (pins "no product class defines OnLogout"; see Q2).
- `src/ocutalon/cls/OcuTalon/Test/Web/StubRequest.cls` -- `MakeCall(application, method, contentType, header, origin, host, secure)` :35.
- `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls` -- `TestReferencesOnlyThePublicAllowList` :337, AD-3's scan of the public classes. It reads `##class(`, `$SYSTEM.` and the dynamic-dispatch functions in the class text, the superclasses and the member types. A UrlMap `Call="Class:Method"` target is none of these. Unchanged.

**Client**

- `web/src/app/live/live-state.ts` -- `LiveState`, the one live service.
  - The imports :2 gain `effect` and `untracked`.
  - Leave byte-identical: `stop` :149, `fetchSnapshot` :164, `accept` :200, `schedulePoll` :229, `poll` :244, `applyPoll` :267, `otherEpoch` :294 (pinned by `web/scripts/leave-sources.test.mjs` :135), `changeEpoch` :300.
  - Reuse: `contact` :99, `halted` :102, `snapshot` :87, `store` :93, `stopped` :63.
  - The wiring is one new block inside the class (fields plus one method), for example after `instanceSeq` :111.
- `web/src/app/live/live-store.ts` -- `applyEvents` :201 is the idempotent apply (skips `seq <= cursor`, a skip gives `reload`, another epoch gives `epochChanged`). Every collection is keyed (`COLLECTIONS` :41), so a repeat can only show as a stale overwrite. READ ONLY (Epic 11).
- `web/src/app/live/contact-watch.ts` -- `ContactState` :16. The socket never calls `answered()`.
- `web/src/app/api/api-types.ts` -- `EventsResponse` :64, `StateSnapshot.onlineDemo` :50. READ ONLY.
- `web/src/app/main-page/main-page.ts` :104 -- `data-session-seq` / `data-instance-seq` on the page (read by W3 and W9).
- `web/scripts/contact-watch.test.mjs` + `web/scripts/fake-clock.mjs` -- the pattern for a framework-free module test. The module is imported as it is, so it imports only types and keeps to erasable syntax. `announce-focus-sources.test.mjs` and `leave-sources.test.mjs` scan every source: the new file must not announce, move focus or register `pagehide`, `visibilitychange`, `beforeunload` or `unload`.

**E2E** (impact map against feature `02e91b21`; `workers: 1`)

- `web/e2e/support/iris.ts` -- `fixtureUser('LIVE')` :66 and `publishReminder(user, fields)` :137 (`fields.ref` re-publishes the same entity). READ ONLY (Epic 11).
- `web/playwright.config.ts` :48-61 -- project `chromium` is `e2e/**` except demo-path, demo-switch, floor, answers and cards. So `e2e/live/socket.spec.ts` joins the `sign-in` unit (browser group) with no edit. `web/scripts/playwright-projects.test.mjs` derives the spec lists from disk.
- Tests that steer delivery through polls and break once a socket also delivers. Each one needs `blockLiveSocket(page)` before its page loads:
  - `web/e2e/live/live.spec.ts`: L10 (:404-441, drops seq cursor+1 from a poll);
  - `web/e2e/chat/chat.spec.ts`: C2 (:212, `oneEventPerPoll`), C3 (:275, `holdEvents`), C4 "the post reached the server but its answer was 503" (:377), C4 "a failed post whose turn then arrives by poll" (:474), C7 (:693), C8 (:717, strips `done`), C9 (:761);
  - `web/e2e/chat/decision.spec.ts`: D10 (:449, waits for a poll body that holds the event);
  - `web/e2e/chat/try-it.spec.ts` (feature): `keepRoutedFinish` :210, which strips `guide.state` from polls and is used by Y5 :417 (with `holdPoll` :430), Y9 :548 and Y10 :577. Put the call inside `keepRoutedFinish`, which already runs before the page loads;
  - `web/e2e/floor/announcements.spec.ts`: A2 :162, A3 :187, A4 :214 and A5 :232 (`holdPoll` makes "one update"). The call goes in each test before `open()` :69;
  - `web/e2e/floor/guide.spec.ts` (feature): M10 :618, M14 :685 and M13 :804 (`holdPolls` :490, "only the 200 answer"). These are the held-poll lines: one call per test before `seedFinishingRun`, plus the import line.
- Need nothing: `support/api.ts` (`holdPoll` :83, used by the callers above), `support/clock.ts` (timing only), `support/floor.ts` (no events routing), `chat/notice.spec.ts`, `guide/guide.spec.ts` (synthetic events), `demo-path/**` (arrivals only; `01-page.spec.ts` :23-46 reads the first poll's cursors, safe unless the README session publishes during load), `rail`, `api`, `session`, `demo-switch`, `answers`, `cards`, `trace`, `phone`, `reminder`.
- `web/e2e/banners/banners.spec.ts` B14 :858-920 (NEVER edited) publishes `heartbeatStalled` while `refuseApi` holds the API down, and asserts the page has not heard it until the first answer after the outage. It stays green because the page applies no socket frame while `contact` is not `ok` (Design Notes, D3).
- The LIVE user: only `live.spec.ts` publishes on its stream (L2, L4, L10). `session/session.spec.ts` S8 uses it without publishing. A socket spec on LIVE is safe under `workers: 1` if each test reads its cursor fresh.

## Tasks & Acceptance

**Execution:**

- [ ] (lead, before implement) Integrate the feature forward so that the epic branch holds Epic 4's merge `374f958e`. The e2e anchors above marked "feature" assume it.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Session.cls` -- the sign-out mark (U-174, DW-457).
  - `Parameter MARKGLOBAL` names `^OcuTalonP.SessionM`.
  - `ClassMethod MarkSignedOut(ref) As %Status`: `$Increment(^OcuTalonP.SessionM(ref))` for a non-empty ref. It is atomic and takes no row lock, so it never waits on `Core.Trace`'s row lock.
  - `ClassMethod SignOuts(ref) As %Integer`: `+$Get(...)`, 0 for an empty or unknown ref.
  - The class doc gains one paragraph: what the mark is, who writes it and who reads it.
  - No property, index or storage change.
- [ ] `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls` -- `ClassMethod OnLogout() As %Status`.
  - Only when `Data.Setting.Get("onlineDemo") '= 1` and `%session.Data(Ownership.#SESSIONKEY)` names a session: call `Session.MarkSignedOut(ref)`, then `Publish.Wake(ref)` so that its socket wakes at once.
  - It always answers OK (an error would stop a non-forced logout) and catches everything. A failure goes through `Log` without the user name (measured T7: the console write may not land from this callback, so nothing depends on it).
  - Rewrite the class-doc line "The class has no OnLogout…" to say what `OnLogout` does and that a CSP session's end still ends nothing else.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Publish.cls` -- the wake (AD-12: "`Live.Publish` signals after each commit").
  - `ClassMethod WakeName(stream) As %String` returns `$Name(^OcuTalonP.LiveWake(stream))`, a resource name only (never set as a global).
  - `ClassMethod Wake(stream)` calls `$SYSTEM.Event.Signal(..WakeName(stream))`, which ignores a missing resource.
  - In `Publish`, call `..Wake(stream)` after the unlock at :101 when `sc` is OK, before `RefreshGuide`.
  - Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Live.cls` (new; extends `%CSP.WebSocket`; synchronous mode; code database, AD-3) -- the socket (AC 1).
  - Parameters: `HEARTBEAT` 25, `LIFETIME` 60, `SLICE` 0.25.
  - Properties: `SessionRef`, `After`, `AfterInstance`, `InstanceStream` (default `Publish.#INSTANCE`, a test seam), `Mark`, `StartedAt`, `SentAt`, `Lifetime` (default `LIFETIME`, a test seam).
  - `ClassMethod Accept() As %Status`, the shell's route target. With an empty `HTTP_WEBSOCKET_ID` it sets `%response.Status` 404 and answers OK: no body and no new text, as the shell answers a path it doesn't serve, because `Page` would HALT. Otherwise `Do ##class(%Library.Device).ReDirectIO(0)` and `Quit ..Page()`.
  - `ClassMethod Refusal(hasRole, onlineDemo, origin, host, secure, sessionRef, after, afterInstance) As %String`: "" or the first code of `no_role`, `online_demo`, `wrong_origin`, `no_session`, `bad_cursor`.
    - Origin: `Api.EnvelopeError("POST", "application/json", 1, origin, host, secure) '= ""` means `wrong_origin`.
    - Cursors: `?1.15N`.
    - The codes are internal and never sent.
  - `Method OnPreServer()`:
    - reads `Shell.HasRole()`, `Setting.Get("onlineDemo")`, `HTTP_ORIGIN`, `HTTP_HOST`, `%request.Secure`, `Ownership.SessionRef(.sc)` and the two query cursors;
    - calls `Refusal`; a refusal returns an error status (no frame; measured T6), and the class logs nothing;
    - otherwise it keeps the cursors, `SessionRef`, `Mark = Session.SignOuts(ref)` and the times, creates both wake resources (`WakeName(ref)`, `WakeName(InstanceStream)`) and `Clear`s queued wakeups.
  - `ClassMethod Next(markAtOpen, markNow, startedAt, now, sentAt, ahead, lifetime) As %String`: the loop's decision, in this order:
    1. `end` when the mark changed;
    2. `end` at the lifetime;
    3. `send` when either stream is ahead;
    4. `heartbeat` when `HEARTBEAT` s passed since the last frame;
    5. otherwise `wait`.
  - `Method Server()` loops:
    - read `Session.SignOuts(SessionRef)` and `LastSeq` of both streams (a `LastSeq` that throws counts as not ahead, retried next loop);
    - `send` writes `Api.EventsBody(session, After, AfterInstance, InstanceStream).%ToJSON()`, advances each cursor to the highest `seq` of its stream in the frame, and repeats until caught up;
    - `heartbeat` writes the same body with no events;
    - `end` calls `EndServer()`;
    - then `Wait SLICE` on the session's resource and `SLICE` on the instance resource, and `Read(, .sc, 0)`: end on 7951 or any error but 7950.
    - It writes no table and no global.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` -- the forwarding route only (U-175).
  - Add `<Route Url="/OcuTalon.Web.Live.cls" Method="GET" Call="OcuTalon.Web.Live:Accept"/>` after `/` and before `/(.*)`.
  - Add one class-doc bullet: "a GET of /OcuTalon.Web.Live.cls is forwarded to the live-events WebSocket (AD-12, AD-13)".
  - No `##class` and no new parameter, so `Test.Web.Status` and `Test.Web.PublicTexts` are unchanged.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Live.cls` (new; lane-b area Web) -- each test makes its own streams and session rows and removes them.
  - `TestRefusals` covers every `Refusal` case (U-174 (a)): no role; online demo; Origin wrong, empty, other scheme, other host and right; session empty; cursors `x`, empty, 16 digits, `0` and 15 digits.
  - `TestOnPreServer` uses a stub request (`StubRequest.MakeCall`) and a stand-in `%session` holding a fixture `SessionRef`. It checks that a good upgrade keeps the cursors, the ref and the mark, that a wrong Origin returns an error status, and that the onlineDemo flag (saved and restored) refuses.
  - `TestNext` drives `Next` with a shortened lifetime (U-174 (c)): mark changed → end before send; lifetime → end; ahead → send; 25 s quiet → heartbeat.
  - `TestFrames` uses `EventsBody` on its own fresh session stream and an `InstanceStream` seam stream: more than `MAXEVENTS` events give successive frames in `Seq` order; the envelope labels are `session`/`instance`; `traceUrl` is present; the epoch is the session's. No frame holds the stored `SessionRef` or a row id (U-174 (d)).
  - `TestAccept`: no `HTTP_WEBSOCKET_ID` gives 404 with no body.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Live/Publish.cls` -- `TestWake`.
  - A `Job`'d waiter on `WakeName(<fresh ref>)` wakes within 1 s of a `Publish` on that stream.
  - It does not wake for a refused publish (bad type), nor for a publish on another fresh stream.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls` -- `TestSignOutMark` (DW-457).
  - With a stand-in `%session` holding a fixture ref, `OnLogout` answers OK and `SignOuts(ref)` goes up by exactly 1.
  - The row's `Epoch`, `CspSessionId` and the other fields are unchanged.
  - With onlineDemo on (saved and restored), nothing changes.
  - With no ref, it answers OK and nothing changes.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Session.cls` -- `TestSignOutMark`: 0 for an unknown ref; two calls give +2; one ref's mark leaves another's alone.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Shell.cls` -- `TestForwardsTheSocket` reads the UrlMap XData. It checks that GET `/OcuTalon.Web.Live.cls` calls `OcuTalon.Web.Live:Accept`, that the route comes before `/(.*)`, and that it is the only route naming a class outside the two public packages (Q3).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/LeavingThePage.cls` -- `TestNoProductClassEndsASessionOnTimeout`.
  - No product class defines `OnTimeout` or `OnEndSession`.
  - `OnLogout` is defined by `OcuTalon.Web.SessionEvents` alone.
  - Update the header bullet to match.
- [ ] `web/src/app/live/live-socket.ts` (new; framework-free; imports types only; erasable syntax) -- `LiveSocket`, following `ContactWatch`'s injected shape.
  - Constants: `SOCKET_PATH = '/ocutalon/OcuTalon.Web.Live.cls'`, `RECONNECT_MS = 1000`, `MAX_BACKOFF_MS = 30_000`, `SILENT_MS = 60_000`.
  - Injected: `open(url)` (the WebSocket factory), `setTimeout`/`clearTimeout`, `location {protocol, host}`, `cursors()`, `accepting()` and `onEvents(EventsResponse)`.
  - `start(snapshot)` opens once. It returns at once and constructs nothing when `snapshot.onlineDemo === true`. Otherwise it opens `ws:` or `wss:` (by `location.protocol`) `//<host>` + `SOCKET_PATH` + `?after=<s>&afterInstance=<i>` from `cursors()` at that moment.
  - Each text frame is parsed as `EventsResponse` and handed to `onEvents` only when `accepting()` is true. A malformed frame is ignored.
  - On close or error, it reconnects with the cursors of that moment: `RECONNECT_MS` after a socket that delivered a frame, otherwise a backoff from `RECONNECT_MS` doubling to `MAX_BACKOFF_MS`.
  - No frame for `SILENT_MS` closes the socket, which then reconnects. A refused upgrade can stay open with no frame (measured T6).
  - `stop()` closes, clears every timer and never reopens.
  - No announcement, no focus, no banner, no page-lifecycle handler.
- [ ] `web/src/app/live/live-state.ts` -- the import line plus ONE self-contained block (AC 2).
  - `private readonly socket = new LiveSocket({ open: (url) => new WebSocket(url), …, cursors: () => this.store()?.cursors, accepting: () => this.contact() === 'ok', onEvents: (response) => this.applyPushed(response) })`.
  - One `effect` field: with the latest `snapshot()` and `halted()`, `untracked`, it calls `socket.stop()` when halted, else `socket.start(snapshot)` once a snapshot exists.
  - `private applyPushed(response)`. When stopped or with no store it does nothing. Otherwise it runs `applyEvents`. Another online-demo epoch goes to `changeEpoch()`. `reload` calls `fetchSnapshot(() => undefined, undefined, POLL_TIMEOUT_MS)`. Otherwise it sets the store if it changed.
  - It never touches the watch, `answers` or the poll schedule.
  - The block's doc comment says that the socket only delivers sooner, beside polling.
- [ ] `web/scripts/live-socket.test.mjs` (new; `fake-clock.mjs` and a fake WebSocket). Cases:
  - the URL with both cursors, `ws:` and `wss:`;
  - frames reach `onEvents`;
  - a malformed frame is ignored;
  - frames are dropped while `accepting()` is false (the B14 rule, D3);
  - reconnect 1 s after a delivered frame;
  - the backoff 1, 2, 4 … 30 s;
  - the silence watchdog;
  - `stop()` closes, cancels a pending reconnect and never reopens;
  - a second `start` opens nothing;
  - `onlineDemo` constructs no WebSocket.
- [ ] `web/e2e/support/socket.ts` (new) -- the shared helper (U-173).
  - `LIVE_SOCKET` (`/\/ocutalon\/OcuTalon\.Web\.Live\.cls/`).
  - `blockLiveSocket(page)` is `page.routeWebSocket(LIVE_SOCKET, (ws) => ws.close())`. Call it before the page loads.
  - `proxyLiveSocket(page)`: routes that `connectToServer()` and are kept for the test to close.
  - `socketFrames(page)` records frames through `page.on('websocket')`.
  - `rawUpgrade({baseURL, path, origin, cookie})`: a Node `net` handshake. It returns the status line, the data frames with their times, a close frame, and `close()`.
- [ ] `web/e2e/live/socket.spec.ts` (new; LIVE user; publishes only on its own stream; cursors read fresh) -- W1 to W9.
  - W1 (AC 3, AC 4, U-174 (d)): with polls answered event-free (`route.fetch`, then `events: []`), a `publishReminder` shows on the page within 2 s, and its `seq` is in a received frame. No banner. No frame holds the CSP session cookie's value or the session's `Ref`. Log the ms, labelled (inference).
  - W2 (AC 3): with `blockLiveSocket`, polling delivers it within 2 s. No banner.
  - W3: the socket URL is `SOCKET_PATH`, with the page's `data-session-seq` and `data-instance-seq`.
  - W4 (U-174 (c), page side): with `proxyLiveSocket`, the test closes the first socket. The page opens a second upgrade with its current cursors, and a publish arrives through it while polls are event-free. No banner and no new live-region text.
  - W5 (U-174 (a)): `rawUpgrade` with the LIVE cookie and Origin `http://evil.example`, then with no Origin: no data frame within 3 s.
  - W6 (U-174 (a)): `rawUpgrade` with no cookie: no data frame within 3 s.
  - W7 (U-174 (b)): Sign out from the account menu. The page's socket closes within one poll (2 s) and no new socket opens.
  - W8 (U-174 sign-out mark, DW-457): open a `rawUpgrade` with a signed-in context's cookie. `POST /ocutalon/api/v1/session/end` with the same cookie and the envelope answers 204. A `publishReminder` after that reaches no data frame, and a close frame arrives within 1 s. Then the same with `GET /ocutalon/?IRISLogout=end`.
  - W9 (U-173, dual delivery): hold the page's next poll, which was issued with `after=s`. Publish R "first" (s+1) and `route.fetch()` the held poll now, so that its answer holds s+1 only. Wait until "first" shows by the socket. Publish R "second" (s+2, same ref) and wait until it shows. Then fulfil the held poll with its answer. The page still shows "second", `data-session-seq` is s+2, and no `/state` request was made.
- [ ] Existing specs: add `blockLiveSocket(page)` before the page loads in every test the Code Map lists. Assertions stay unchanged.
  - Files: `web/e2e/live/live.spec.ts`, `web/e2e/chat/chat.spec.ts`, `web/e2e/chat/decision.spec.ts`, `web/e2e/chat/try-it.spec.ts`, `web/e2e/floor/announcements.spec.ts`, `web/e2e/floor/guide.spec.ts`.
  - Grep `web/e2e` (not `e2e-online`) once more for `v1/events`, `holdPoll`, `holdEvents` and `keepRoutedFinish` on the implement head, and give any new caller the same call.
  - Never edit `banners.spec.ts`, `support/floor.ts`, `e2e-online/**` or Epic 11's `support/*` files.
- [ ] `## Verification` of this spec -- record each command's seconds, socket.spec's own duration, W1's ms (inference), and one `mutation:` line per pinning test.

**Acceptance Criteria:**

- **AC 1 (the server, AD-12, AD-13).**
  - Given a signed-in session with the user role on a local or IPM install,
  - when the page opens the WebSocket `/ocutalon/OcuTalon.Web.Live.cls?after=<s>&afterInstance=<i>` (forwarded by the shell),
  - then `OcuTalon.Web.Live` has checked the role, the online-demo flag, `Origin`, the session (from the CSP session) and the cursors before `Server()` runs, and a refused socket gets no frame.
  - It waits on the session's `$SYSTEM.Event` resource and one instance resource, which `Live.Publish` signals after each commit. It sends each new event after the client's cursors in `{epoch, events}`, in the envelope `{seq, stream, ts, type, payload}` with trace URLs.
- **AC 2 (the client; FR-12, UX-DR91, UX-DR149).**
  - Given the page's live-event service,
  - when it starts,
  - then on a local or IPM install it receives events over the WebSocket and applies them through `applyEvents`. A `Seq` skip reloads the snapshot.
  - With `onlineDemo` set it never constructs a WebSocket and only polls.
  - If the socket closes or fails, delivery continues by polling with no message, and the socket reconnects in the background.
  - Polling's cadence, contact and banners are unchanged, and no socket frame is applied while contact is not `ok`.
- **AC 3 (CI; NFR-9).**
  - Given the CI throwaway stack with the model mock,
  - when `web/e2e/live/socket.spec.ts` runs in the `sign-in` unit,
  - then an event published while the socket is open reaches the page through it (W1), and with the socket blocked polling still delivers it (W2).
  - The 2-second bound is checked against the mock and measured over real networks only in the rehearsal.
- **AC 4 (integration, Rule 1).**
  - Given a fresh throwaway stack,
  - when the consumer `LiveState` reads from the socket,
  - then the published reminder appears on the page with no poll carrying it (W1, a real instance, no mock socket).
- **AC 5 (sign-out; U-174, DW-457).**
  - Given an open socket of a signed-in session on a local install,
  - when that session signs out (`POST /v1/session/end`, or `?IRISLogout=end`),
  - then the socket sends no further frame and closes within one loop (W8). Every refusal sends no frame (W5, W6, `TestRefusals`). The page closes its own socket at Sign out (W7). The server ends every socket at its lifetime, and the page reconnects through the checks (`TestNext`, W4). No frame carries a session id, cookie or ref (W1, `TestFrames`).
- **AC 6 (one event, two paths; U-173).**
  - Given an event that reaches the page over the socket and again in a late poll,
  - then it is applied exactly once, by `seq`: a stale repeat never overwrites a newer view (W9).
- **AC 7 (regression).**
  - Given the existing L, C, D, Y, A, M, B and S specs and the demo path,
  - when they run with this change,
  - then all pass with their assertions unchanged.

### Review Findings

Epic-cycle code review, 2026-11-01 (layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; full-opus tier). 31 raw findings, 8 entries after grouping (high 0, medium 4, low 4); every patch applied, re-run green; 15 rejected (below).

- [x] [Review][Patch] (medium) `TestServer`'s quiet case could not fail: `Served()` created no wake resources, so the loop ended on `Wait`'s ERUNDEF inside `Server`'s catch, and the `"0|0"` cursors read the same whether a heartbeat was written or not -- `Served` now creates and clears both resources as `Admit` does, and the quiet case asserts `SentAt` unchanged and an end within 5 s [src/ocutalon/cls/OcuTalon/Test/Web/Live.cls:208]
- [x] [Review][Patch] (medium) W5 checked the refused sockets about 150 ms in, as soon as the control had a frame, and never checked that they close (matrix row "the connection closes") -- it now waits until both refused upgrades are closed (close frame or ended) before asserting no frame [web/e2e/live/socket.spec.ts:192]
- [x] [Review][Patch] (medium) W6 had no positive control, so a broken upgrade path or route also passed -- the same upgrade with the live user's cookie must get a frame [web/e2e/live/socket.spec.ts:214]
- [x] [Review][Patch] (medium) W12 relied on the real instance stream (StatusMonitor publishes there) staying quiet for 60 s (Rule 19 hermeticity) -- only frames with no events count as heartbeats, the quiet time counts from the previous frame, and an event frame is allowed [web/e2e/live/socket.spec.ts:448]
- [x] [Review][Patch] (low) The Client-closes branch (`Pause` on Read's 7951) had no falsifiable pin, and W11's doc said the opposite of the recorded mutation run -- pinned by `TestServer`'s quiet case (mutation below); W11's doc corrected [web/e2e/live/socket.spec.ts:415]
- [x] [Review][Patch] (low) Stale test docs: `TestOnPreServer` claimed a missing-session case it does not run, `Test.Web.Live`'s header omitted `TestServer`, `socket.spec.ts`'s header said W1 to W9 and "W5 to W8" use `rawUpgrade` -- corrected [src/ocutalon/cls/OcuTalon/Test/Web/Live.cls:65]
- [x] [Review][Patch] (low) AC 1's role and cursor clauses of `Refusal` had no `mutation:` line -- both applied, observed red, reverted; lines added under ## Verification [src/ocutalon/cls/OcuTalon/Web/Live.cls:70]
- [x] [Review][Defer] (low) Rule 2: `Web.Live` repeats `Api.IsCursor` and `Api.CurrentSession`'s pair, both Private in the contended `Web/Api.cls` [src/ocutalon/cls/OcuTalon/Web/Live.cls:74] -- deferred: DW-556 `wontfix-accepted` (spec-forced copy, out-of-footprint fix; reopen_if a change to either Api method)

Rejected:
- `low` blind + edge: frames dropped while contact is not `ok` leave the server's cursors ahead, so a later frame can trigger one extra, idempotent snapshot reload; the proposed fix (close on every dropped frame) adds reconnect churn during an outage.
- `low` edge + auditor: `Admit` calls `SessionRef` (which may attach) before `Refusal`; unreachable through the shell, which ends a no-role session and answers a no-session request first; adjudicated in the build's triage.
- `low` blind + edge: `Wait` throws ERUNDEF on a resource deleted before the wait; no product code deletes a WakeName resource, and the socket would simply end and reconnect (real only if product code ever calls `$SYSTEM.Event.Delete` on one).
- `low` edge: `Read(, , 0)` may drop a partial frame header; the page never sends data frames, and a close frame is a few bytes.
- `low` edge: a frame of 2 x MAXEVENTS large events could exceed the string limit; polling carries the same bodies, and the page reconnects with current cursors.
- `low` edge: several skipping frames can start parallel reloads; `fetchSnapshot` orders answers by request number (adjudicated in the build's triage).
- `low` edge: `rawUpgrade` would parse a non-101 body as frames; T6 measured 101 for every refusal, and the effect would be a false red, never a false green.
- `low` edge: `rawUpgrade` is plain TCP, so an https baseURL breaks it; the e2e stack is http.
- `by-design` verification-gap: the client-side online-demo rule is pinned on `LiveSocket` (node) and not through `LiveState` in a browser; D8 places the online-demo cases in a node test and a unit test.
- `false` verification-gap: "planned mutations not run" for W4 and W8; the planned list is a plan, and the recorded results state what went red (the Refusal clauses part is the patch row above).
- `low` verification-gap: `applyPushed`'s `stopped` guard is untested; a one-turn window, and there is no node host for `LiveState`.
- `low` verification-gap + auditor: W8's close bound starts after the publish returns and accepts an ended connection; adjudicated in the build's triage (W8 pins the mark by its recorded mutation).
- `low` verification-gap: the route's `Url` is a regex with unescaped dots; harmless (a non-upgrade gets 404 and every check still runs).
- `low` auditor: the "Page stops" row is tested for Sign out only; every cause goes through the one `halted()` effect that W7 pins.
- `low` auditor: a socket-triggered reload runs `accept()`, which feeds the watch; the spec prescribes that call, and a real answered snapshot is contact (adjudicated in the build's triage).

## Spec Change Log

- 2026-10-30, lead (runner B): the plan HALTed `blocked` on Q1 and Q2 (with A1/A2). Rulings written under ## Design Notes: Q1 → U-174 (orchestrator, veto: checks before `Server()`, page close in `stop()`, 60 s lifetime; conditions (a)–(d) as tests; DW-457 for the server-side sign-out check), A2 → U-175 (orchestrator, veto: no AD-13 amendment; the shell forwards the socket at the AC's URL; A1 withdrawn; the story waits on Epic 29), Q2 → U-173 (runner, veto: polling unchanged beside the socket; specs block it with a helper that never edits `web/e2e/support/floor.ts` or `web/e2e/banners/banners.spec.ts`). Status reset to `draft`, so the spec is re-planned for the shell route once Epic 29 merges (re-measure M2 in the shell application). Ledger inbox at the re-plan: DW-457.
- 2026-10-30, lead (runner B): owner answers applied (the Contest Planner, the owner's delegate, through the inbox), quoted under ## Design Notes. U-173 at=2026-10-30T22:43:15Z#526: accepted, plus a required test that one event arriving over both the socket and a poll is applied exactly once (by `seq`), and the dev note that polling stays on beside the socket against the user story's "polling only as the fallback". U-174 at=2026-10-30T22:43:15Z#527: accepted with one change: the server-side sign-out mark (set at sign-out, read on each socket loop) is built in this story, with a test that an open socket sends no further frame within one loop after sign-out; the 60 s lifetime stays as a backstop; the server's own online-demo refusal stays (the demo gate passes upgrades, AD-24); only if another open epic holds `Data/Session.cls` at the re-plan does DW-457 stay a ledger entry, due before 1.0.0. U-175 kept (route (c) declined) and resolved. Status stays `draft`.

- 2026-11-01, lead (runner C): re-dispatched after Epic 29 merged. Intent block brought in line with U-173/U-174/U-175 (Approach: shell-forwarded route at the AC's URL and the sign-out mark; Never: contended paths re-computed, Shell and Session freed for this story's two edits; sign-out sentence). Re-dispatch rulings added at the top of ## Design Notes. Ledger inbox: DW-457, DW-397. Status stays `draft` for the re-plan.

- 2026-11-01, lead (runner C): the re-plan halted on Q1-Q3; ruled under ## Design Notes (Q1 decide, Q2 veto U-209, Q3 decide), `pending` markers removed, the intent's sign-in sentence reworded for the shell route, status `ready-for-dev`.

## Review Triage Log

### 2026-11-01 — Review pass
- verdicts: 32 findings reported (blind 11, edge 12, verification-gap 8, intent 1; a row below groups findings with one root cause) — high 0, medium 1 (the heartbeat and lifetime gap), the rest low or false, maybe-false 0; the intent report is descriptive; the lead's own Matrix Test Audit adds the rows for W10 and W11
- findings:
  - `[low]` `patch` blind: W2 allows one announcement though its message says none -- message reworded to "beyond the event's own"; bound unchanged (the reminder's own announcement is the one allowed).
  - `[low]` `patch` blind: `within` doc says half-second looks, polls every 100 ms -- comment corrected.
  - `[low]` `patch` blind + edge: `Pause` compares `GetErrorCodes` with 7950, fragile for a multi-code status -- now `'$SYSTEM.Status.Equals(sc, 7950)`.
  - `[medium]` `patch` verification-gap: the 25 s heartbeat and the 60 s server lifetime were pinned only through `Next` -- W12 added (raw upgrade held to the lifetime: heartbeat frame `{epoch, events: []}`, close frame at 60 s); mutation line written.
  - `[low]` `patch` verification-gap: two node cases could not fail (the handlers were nulled before the second event) -- they now call handlers captured beforehand; mutation line written.
  - `[medium]` `patch` Matrix Test Audit (lead): the rows "Seq skip" and "Client closes" had no test -- W10 and W11 added; W10 mutation line written, W11 noted.
  - `[low]` `reject` blind: `MARKGLOBAL` parameter unused beside the literal global -- the parameter names the global as the spec requires; `Publish` keeps its counter global the same way; not worth indirection.
  - `[low]` `reject` blind + edge: `SessionM` nodes and per-session wake resources never removed, not in short-names -- one integer per signed-out session and one resource per user (T5: a user has one durable row), no registry rule found in checks; accepted.
  - `[low]` `reject` blind: `Server` swallows exceptions silently -- the page falls back to polling and the spec says the class logs nothing on a refusal; no logging seam is specified.
  - `[false]` `reject` blind: multi-socket wake behaviour untested -- D4 designs for it (each socket also checks `LastSeq` every loop, so a missed wake costs at most 0.5 s).
  - `[false]` `reject` blind: spec results stop at W9, status text stale -- results and Auto Run Result updated by the lead.
  - `[low]` `reject` blind: `blockLiveSocket` added by hand per test -- U-173's ruling (one shared helper, assertions unchanged); the Code Map lists every affected test and the full sign-in and floor units passed.
  - `[low]` `reject` blind + edge: `applyPushed` has no in-flight guard and ignores a failed reload -- `fetchSnapshot` orders answers by request number, a repeat reload is idempotent and the next skipping frame or poll repairs a failed one.
  - `[low]` `reject` blind + edge: `rawUpgrade` is plain TCP and drops fragmented frames -- the CI stack is http and every frame is a single small text frame.
  - `[low]` `reject` blind: W5/W6 never assert a refused upgrade is not 101 -- T6 measured that a refused upgrade answers 101 and sends no frame, so the status cannot be asserted.
  - `[low]` `reject` edge: `Admit` calls `SessionRef` before `Refusal` -- the shell ends a no-role session and answers a no-session request before the route, and the attach is the write a sign-in or `/state` makes anyway.
  - `[low]` `reject` edge: a local epoch reset would leave server cursors ahead of the heads -- the epoch changes only on the online demo, which has no socket; the 60 s lifetime ends any socket.
  - `[low]` `reject` edge: a CSP timeout without `OnLogout` leaves frames flowing up to 60 s -- the lifetime backstop is U-174's ruling.
  - `[low]` `reject` edge: `live-socket.ts` `connect` with no `location` -- the page injects `globalThis.location`.
  - `[low]` `reject` edge: two claims (a socket-triggered reload goes through `fetchSnapshot`'s `accept`, the 0.5 s close bound) -- true and consistent with the spec: contact is fed by the answered snapshot request, as for any reload; tests assert one second.
  - `[low]` `reject` verification-gap: `OnPreServer` forwarding `HasRole()` is never run -- the shell enforces the role first and `Admit(0)`/`Refusal` are unit-tested; no realistic user-reachable failure.
  - `[low]` `reject` verification-gap: sub-behaviours without their own mutation line, W8's conditional close-frame timing, `TestWake`'s 1 s bound, `TestSignOutMark`'s whole-global count, the dead `changeEpoch` branch -- one mutation per AC is the bar; the bounds and the branch are the spec's (Code Map, AC 5); the count compares a test's own before and after on a test stack.
  - `[none]` `reject` intent-alignment (descriptive report): descriptive; the diff implements the whole-path reading and the divergences (role/session checks unreachable through the shell, `blockLiveSocket` closes the socket browser-side) are the spec's own design.

## Design Notes

**Rulings that govern this plan (read first).**

- **Re-dispatch, 2026-11-01 (runner C, policy ff1bd1a):**
  - Epic 29 has merged (fe1d81e2), so `Web/Public/Shell.cls` and `Data/Session.cls` are free, and the sign-out mark is built here (U-174's main case). This plan re-checked that no open branch (Epics 11, 12, 13, 15, 30) changes either file.
  - Owner-fixed (3) now reads "Polling is the online demo's contract; local installs get the WebSocket with Epic 31 in 1.0.0." This changes nothing in the intent.
  - Epic 11 changes `Web/Api.cls`, `live-store.ts` and `Test/Web/Api.cls`: they are read only here.
  - Epic 4 (`web/src/app/**`, `floor/guide.spec.ts`): the ruling is one self-contained block in `live-state.ts` and only the held-poll lines in `guide.spec.ts`. Epic 4 merged while this plan ran (`374f958e`), so that ruling now only limits the size of the edits.
  - CI: add no unit to a group over 30 minutes; new IRIS test classes go into `shards`; rename no job and add, rename or remove no iris group (see Q1).
- **U-174 (orchestrator, veto; owner answer at=2026-10-30T22:43:15Z#527):** every check before `Server()`, with no frame on refusal; the page closes its socket in `LiveState.stop()`; a 60 s server lifetime as a backstop; conditions (a)–(d) are tests. The owner: "Accepted with your conditions and one change. U-175 makes 31.1 wait for Epic 29's merge, so Data/Session.cls will be free when 31.1 runs. Build the server-side sign-out check (a mark the sign-out sets, read on each socket loop) in 31.1 itself, with a test that an open socket sends no further frame within one loop after sign-out, and keep the 60 s lifetime as a backstop. That removes the known 60 s cost instead of ledgering it. Only if another open epic holds Data/Session.cls when 31.1 resumes: keep the ledger entry instead, due before 1.0.0, not open-ended. Keep the server's own online-demo refusal: the demo gate passes WebSocket upgrades (AD-24), so on the public host the server's refusal is the real guard. I will check it on the host at the 1.0.0 update." So there is no known 60 s cost any more.
- **U-175 (orchestrator, veto; kept by the owner's delegate):** no AD-13 amendment. The socket is forwarded by the shell at the AC's URL `/ocutalon/OcuTalon.Web.Live.cls`. Route (c) `/ocutalon/api/v1/live` is not planned, and the earlier amendment candidate A1 is withdrawn.
- **U-173 (runner, veto; owner answer at=2026-10-30T22:43:15Z#526):** polling keeps running unchanged beside the socket. The routed-poll specs block the socket with one shared `page.routeWebSocket` helper, assertions unchanged, and `support/floor.ts` and `banners.spec.ts` are never edited. The owner: "Accepted. Polling keeps running unchanged beside the socket; the socket only delivers sooner, through the same idempotent apply path; one shared page.routeWebSocket helper blocks the socket in the existing specs, assertions unchanged. Condition: add a test where one event arrives over both the socket and a poll and is applied exactly once (by seq). Record in the story's dev notes that polling stays on beside the socket, against the user story's wording 'polling only as the fallback'. The user-facing promise (updates arrive at once) holds, and on a single-user local install the extra polls cost nothing that matters."
  - **Dev note (owner-recorded deviation):** polling stays on beside the socket, against the user story's wording "polling only as the fallback".

**Governing ADs (Rule 6):**
- **AD-12:** polling first and the contract, the socket second, and never on the online demo. One envelope and one idempotent apply; a skip reloads. Trace URLs on the socket. The session and instance `$SYSTEM.Event` resources, signalled by `Publish`.
- **AD-13:** the `/ocutalon` shell. "The WebSocket … is forwarded by the shell or moved to its own application, as its story decides." The WebSocket checks `Origin` before it accepts. No CORS allow-list.
- **AD-1's web write rule** (spine :112): "REST and WebSocket code may read tables, and may write only: … a sign-out, which submits `SessionOps.End` through `CommandsIn` on the online demo, …". See D1.
- **AD-3:** `Web.Live` sits in the code database. The public package's allow-list is held by `Test.Web.Status` (see Q3).
- **AD-4:** the session comes from the CSP session. On a local install, signing out ends only the CSP session.
- **AD-24:** the demo gate passes upgrades, so the server's own online-demo refusal is the guard.
- **AD-33** and **AD-29:** `Publish` is the only event writer; Lane B's files.
- **AD-5:** the mark is a global that survives a restart and an upgrade, with no storage change.
- **AD-22:** tests on throwaways.

**Task 0, measured in this plan stage** (2026-11-01, one fresh lane-C throwaway `ocutalon-t0probe-e31s1plan-*`, build 154, through `lib-live.sh`, port 52803, torn down; probe classes loaded from the scratch folder only: a copy of Shell with the route, a probe `Web.Live`, and copies of Session and SessionEvents with an `OnLogout` that bumps a row counter):
- **T1 (M2 re-measured inside the shell application).** `<Route Url="/OcuTalon.Web.Live.cls" Method="GET" Call="OcuTalon.Web.Live:Accept"/>` before `/(.*)` reaches the class: a plain GET arrives with no `HTTP_WEBSOCKET_ID`, and an upgrade answers 101. `OnPreServer` saw:
  - `$Username` = the user, with `%DB_OCUTALON_CODE`, `%DB_OCUTALON_DATA`, `%DB_OCUTALON_PRIVATE` and `OcuTalonUser` in `$Roles`;
  - namespace OCUTALON, `%request.Application` `/ocutalon/`;
  - `%session.SessionId`, and `Ownership.SessionRef` OK;
  - `HTTP_ORIGIN`, `HTTP_HOST` and the cursors;
  - `Shell.HasRole()` = 1 and `Setting.Get("onlineDemo")` = 0.

  A concurrent `GET /state` on the same session answered 200 in 22 to 58 ms.
- **T2.** `Api.EventsBody` frames were delivered. A `Publish` followed by `$SYSTEM.Event.Signal` from another process woke the socket at once (the frame came 0 ms after the publish call returned). The first upgrade's IRIS process started about 2 s after the client saw 101, and its first frame still held the event published in between (cursor-based) (cause: inference).
- **T3.** `POST /ocutalon/api/v1/session/end` (204, 8 to 14 ms) ran `OnLogout` of `/ocutalon`'s event class, and its `Data.Session` write in the private database succeeded. The open socket read the change on its next 0.25 s slice and sent a close frame 148 ms after the POST. `/state` was then 401.
- **T4.** `GET /ocutalon/?IRISLogout=end` (200, 9 to 19 ms) ran `OnLogout` too, and the socket closed about 85 ms later.
- **T5.** Two CSP sessions of the same user share the row. One's sign-out ended the other's socket while the other's `/state` stayed 200, so that page simply reconnects.
- **T6.** Refusals:
  - an upgrade with no cookie: 101, no frame, and the connection stayed open after 3 s (the shell's `Login()` answered and `Accept` never ran);
  - an `OnPreServer` error status: 101, no frame, closed in 2 ms;
  - a client close: `Read` returned 7951, `OnPostServer` ran, and TCP closed 1 ms after the close frame.
- **T7.** `%SYS.System.WriteToConsoleLog` from `OnLogout` wrote nothing, while the write in the same call succeeded (cause unknown).
- From the earlier plan (lane B, build 154U): `Read(, .sc, 0)` returns 7950 at once with nothing waiting; `EndServer()` gives a clean close 1000; while a socket is open, the socket's own `%CSP.Session` does not see a sign-out for at least 10 s (hence the mark).
- **(inference, not measured):**
  - the `$Increment` global write from `OnLogout`: T3 measured a row write in the same database under the same context, and W8 and `TestSignOutMark` prove it;
  - a sign-out started from a trace application (group-wide): the 60 s lifetime backstops it;
  - whether a CSP timeout runs `OnLogout`: a timed-out session has no open page socket.

**Decided in-stage:**
1. **D1, the sign-out mark (U-174; storage shape owner-approved, decided here).** `Data.Session` keeps `^OcuTalonP.SessionM(SessionRef)`, a sign-out count raised by `$Increment` in `MarkSignedOut`, beside its own storage, as `Publish` keeps `^OcuTalonP.LiveEventC`. Reasons for a global and not a row property:
   - atomic, with no row lock (`Core.Trace.Join` can hold the row's lock across a send);
   - no storage-block, `Test.Data.Tables` or storage-roundtrip change (`Test/Data/Tables.cls` is changed on `OCT-epic30`);
   - an old row reads as 0.

   It is set by `Web.SessionEvents.OnLogout`, the one hook that both sign-out paths reach (T3, T4), and only off the online demo. This fits the write rule exactly: on a local install a sign-out is web code's permitted write and submits nothing, and AD-4's "signing out ends only the CSP session" holds because the mark ends no OcuTalon state. On the online demo the sign-out keeps its one write, `SessionOps.End` through `CommandsIn`, and sockets are refused there anyway. The socket reads the mark at the top of every loop, before any send, so an event published after the sign-out's answer is never sent. The sign-out also signals the session's resource so that the read comes at once. The mark is per session row, so every socket of that IRIS user ends, and a page still signed in elsewhere reconnects through the checks (T5).
2. **D2, the forward.** The shell's route names its target as `Call="OcuTalon.Web.Live:Accept"` (%CSP.REST's own cross-class call), so the shell's code holds no `##class` reference. `Accept` answers a non-upgrade GET 404 with no body: no new text, as the shell answers a path it doesn't serve. Synchronous mode is used, because asynchronous mode needs the URL to name the class.
3. **D3, no frame applied while contact is not `ok`.** `LiveSocket` hands a frame on only while `contact() === 'ok'`, and drops it otherwise. The next answered poll brings it, because cursors are per stream. This keeps "Contact and the reconnecting banners are fed only by polling" and "applies nothing that polling would not". It also keeps the never-edited `banners.spec.ts` B14 green, where the page must not hear an event published during an outage until the first answer after it.
4. **D4, the alternating waits.** 0.25 s on the session's resource, then 0.25 s on the instance resource, with a `LastSeq` check every loop. This is AD-12's mechanism, kept literally: a signal wakes one waiter, so an unwoken socket catches up within about 0.5 s (inference), with two tabs or many sessions.
5. **D5, all checks in `Web.Live`,** as defence in depth behind the shell's own role check: `Refusal` is a pure method, so every refusal case is a unit test. The server refuses on the online demo too (S13, AD-24).
6. **D6, the client watchdog (`SILENT_MS` 60 s, more than two heartbeats).** T6 shows that a refused upgrade can stay open with no frame. The page closes such a socket and reconnects instead of keeping it.
7. **D7, the wiring in one block.** One `effect` field drives `start`/`stop` from `snapshot()` and `halted()`, so `accept()` and `stop()` stay byte-identical. A frame that lands between `stop()` and the effect is dropped by `applyPushed`'s `stopped` guard.
8. **D8, the test placement.** The socket spec reuses the LIVE user (`workers: 1`; cursors read fresh), so `test-sign-in.sh` and `FixtureKind` stay unedited. AC 3's "CI demo-path environment" means a throwaway stack with the mock, and the spec runs in the `sign-in` unit; `e2e/demo-path/` stays UJ-1's test alone. The online-demo cases are a node test (client) and a unit test (server), because setting the flag on a shared e2e stack would disturb other specs.
9. **D9, a dual-delivery observable.** Every store collection is keyed by ref, so a repeat by itself is invisible in the DOM. W9 therefore re-delivers an older view of the same entity late: it can only show if a path applied it out of `seq`.

**Extend, don't copy (Rule 2):**
- These are called, not copied: the frame is `Api.EventsBody`, the Origin rule is `Api.EnvelopeError`, the session is `Ownership.SessionRef`, and the apply is `applyEvents` with `otherEpoch`, `changeEpoch` and `fetchSnapshot`.
- `applyPushed` is not a copy of `applyPoll`: it leaves out contact, `answers` and scheduling, which are polling's.
- **Copy:** the `?1.15N` check copies `Api.IsCursor`, and the `SessionRef` + `RefIndexOpen` pair copies `Api.CurrentSession`. Reason: both are Private in `Api`, which this story may not edit (Epic 11), and `Web.Live` checks for itself (D5).
- `LiveSocket` follows `ContactWatch`'s injected-timer shape. `OnLogout` follows `OnLogin`/`AttachFor` (always OK, all caught). The mark follows `Publish`'s counter global.
- The new tests extend their siblings (`Test.Live.Publish`, `Test.Web.SessionEvents`, `Test.Data.Session`, `Test.Web.Shell`); only `Test.Web.Live` is a new class.

**Integration (Rule 1):** the consumer `LiveState`, on the page, reads from the socket and the event shows with no poll carrying it (W1, AC 4).
- Consumes: `Live.Publish` (Story 0.5), `Api.EventsBody` and `Ownership.SessionRef` (2.2), `Web.TraceLink` (2.9), `LiveState`, `live-store` and `ContactWatch` (2.2, 2.11, 16.3, 16.4), `Web.SessionEvents` (16.3), `Shell` (0.3, 29.7).
- Consumed-by: the page (this story). Every later publisher (for example Story 31.2's approval results) reaches the socket through `Live.Publish` with no change.

**Ledger inbox (Rule 17):**
- DW-457 is addressed by the mark tasks, AC 5, W8 and `TestSignOutMark`. It is resolved by this story at adjudication.
- Declined DW-397: its fix edits `Install/Step/Demo.cls`, which this story's Never list forbids (`Install/**`), and it has nothing to do with live delivery; the lead re-owns it.

**Footprint extensions (report in the completion contract):**
- `Web/SessionEvents.cls`.
- The tests `Test/Web/Live.cls` (new), `Test/Web/SessionEvents.cls`, `Test/Data/Session.cls`, `Test/Web/Shell.cls`, `Test/Web/LeavingThePage.cls` and `Test/Live/Publish.cls`.
- The specs `web/e2e/live/live.spec.ts`, `web/e2e/chat/chat.spec.ts`, `web/e2e/chat/decision.spec.ts`, `web/e2e/chat/try-it.spec.ts`, `web/e2e/floor/announcements.spec.ts` and `web/e2e/floor/guide.spec.ts`. None is changed on an open branch (checked against Epics 11, 12, 13, 15 and 30 at feature `02e91b21`).

**For the lead (not questions):**
- The intent's sentence "Sign-in itself comes first: `ApiBase.Login` answers 401 without a session" is left over from route (c). Under the shell, `Shell.Login()` answers with the sign-in page, and the socket still gets no frame (T6). The matrix row "Signed out / no role … (401 / 403 path)" holds in the same sense. A wording touch-up only.
- Epic 4's merge brought in `chat/try-it.spec.ts` and three new held-poll tests in `guide.spec.ts`. They are in the Code Map, so integrate forward before implement.

**Rulings on the re-plan's questions (2026-11-01, lead (runner C), policy ff1bd1a):**
- **Q1 → decide (CI detail; no unit added, no group or job changed):** recommendation kept. `Test.Web.Live` and the extended lane-b classes run in `shard:lane-b` (the `image` group) by area, and `socket.spec.ts` in the `browser` group's existing `sign-in` unit, with no edit to `ci/units.sh`. The dispatch's "new test units go into `shards`" concerns new units, and this story adds none. Condition: the implement stage measures the added seconds per class and per spec locally, and the lead records the CI step times of `image` and `browser` on the story's head under `ci_groups:`. If either group then crosses 35 minutes, the Contest Planner's CI trigger applies (split the heaviest group into a new iris group, which is a branch-protection change: raised as a clarification before any push that adds a group).
- **Q2 → veto U-209 (a guarantee's wording, veto window 4):** recommendation kept. The mark is set in `OcuTalon.Web.SessionEvents.OnLogout`, and Story 16.4's pin is narrowed exactly as recommended: no product class defines `OnTimeout` or `OnEndSession`; `OnLogout` is defined by `Web.SessionEvents` alone and changes nothing but the local install's sign-out mark (`TestSignOutMark` checks that the epoch and every `Session` row field are unchanged, and that the online demo sets no mark). AD-4 holds: `OnLogout` does not run on a closed page, the idle cap or a timeout, and on a local install signing out still ends only the CSP session. Rejected: the mark in `Api.EndSession` (Epic 11's contended `Web/Api.cls`; the story would wait on Epic 11, and `?IRISLogout=end` would rely on the 60 s backstop). Reversal: move the mark to `Api.EndSession` after Epic 11 merges and restore the full pin.
- **Q3 → decide (confirmed):** the shell's single forward to `OcuTalon.Web.Live:Accept` is AD-13's "forwarded by the shell", as U-175 already ruled; no AD-3 amendment. `Test.Web.Shell` pins it as the only route naming a class outside the two public packages.
- Epic 4 has merged (374f958e): `web/src/app/**` (outside Epic 11's `api-types.ts` and `live-store.ts`) and `web/e2e/floor/guide.spec.ts` are no longer contended. The lead integrates forward before the implement stage. The self-contained-block rule for `live-state.ts` still stands (smaller diff, easy union); edits to `web/e2e/**` specs outside this story's paths_hint are reported under `footprint_extensions:`.

## Verification

Use these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=31 stage=implement'`, with tags `e31s1i` (fresh) and `e31s1iw` (warm).
- Pass `timeout: 600000` on every call.
- Make one test-runner call per message, and never re-submit a call after a client-side timeout.
- Before any browser unit, run `ci/iris.sh build`, because the bundle is not rebuilt by itself (Rule 21).

**Commands:**
- (loop) `npm --prefix web test` -- expected: every `scripts/*.test.mjs` passes, including `live-socket.test.mjs`, `announce-focus-sources`, `leave-sources` and `playwright-projects`.
- (loop) `npm --prefix web run lint` -- expected: exit 0.
- (loop) `OCUTALON_RUN_TAG=e31s1iw ci/warm.sh up` once, then one call each, each expected to print `CLASS … passed`:
  - `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s1iw ci/iris.sh class OcuTalon.Test.Web.Live`
  - `… class OcuTalon.Test.Live.Publish`
  - `… class OcuTalon.Test.Web.SessionEvents`
  - `… class OcuTalon.Test.Data.Session`
  - `… class OcuTalon.Test.Web.Shell`
  - `… class OcuTalon.Test.Web.LeavingThePage`
  - `… class OcuTalon.Test.Web.Status`
  - `… class OcuTalon.Test.Web.SessionEndApi`
  - `… class OcuTalon.Test.Web.Api`

  At the stage's end, also after a failure: `OCUTALON_RUN_TAG=e31s1iw ci/warm.sh down`.
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh build` -- expected: the bundle is rebuilt with the client change.
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh live sign-in --part 1/3`, then `--part 2/3`, then `--part 3/3`, one per call -- expected: every part passes (W1 to W9, and every L, S, C, D, Y and B spec, B14 included). Record each part's seconds and socket.spec's own duration. Three parts keep each under 8 minutes now that `try-it.spec.ts` has joined the unit.
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh live floor` -- expected: passes (announcements A2–A5, guide M10, M13 and M14).
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh live demo-path` -- expected: passes, so UJ-1 stays green with the socket on.
- (once) Fresh lane-b in both orders (Rule 19), one per call: `OCUTALON_RUN_TAG=e31s1i ci/iris.sh shard lane-b --part 1/2`, `… --part 2/2`, `… --reverse --part 1/2`, `… --reverse --part 2/2` -- expected: every class passes, with each part about 4 to 5 minutes for 86 classes.
- (once) `bash ci/checks.sh`, then `bash docker/tests/test-ci-config.sh` -- expected: all pass. That covers the class rules (the unchecked-prepare allow-list, the public-global rule), the boundaries (ASCII, no local paths) and the shard coverage.
- (once) `OCUTALON_RUN_TAG=e31s1i ci/iris.sh teardown`.

**Shared surfaces:**
- The shell's UrlMap: the new route, pinned by `Test.Web.Shell`; `Test.Web.Status`'s scan is unchanged.
- The product's CSP-session callbacks: pinned by `Test.Web.LeavingThePage` (Q2).
- The sign-out mark global `^OcuTalonP.SessionM`: new, and asserted only as a change since a test's own start.
- The `chromium` spec list: a new file, derived from disk with no pinned count.
- The LIVE user's stream: every test reads its cursor fresh.
- Poll control in the listed specs: the block helper, assertions unchanged.
- No stream counts: tests publish only on their own fresh streams or the LIVE user's, never the README session's or the real instance stream.

Every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to apply** (the implement stage writes `mutation: <change> → <red test>` next to each):
- AC 1, the wake: remove the `Wake(stream)` call in `Publish` → `Test.Live.Publish` `TestWake` goes red.
- AC 1, the Origin: drop the Origin clause from `Refusal` → `TestRefusals` and W5 go red.
- AC 1, the online demo, server side: drop the online-demo clause → `TestRefusals` goes red.
- AC 2, the online demo, client side: remove the `onlineDemo` return in `LiveSocket.start` → the node online-demo case goes red.
- AC 2, the contact gate (D3): pass every frame regardless of `accepting()` → the node case goes red, and so does B14.
- AC 3 and AC 4: make the `effect` skip `socket.start` → W1 goes red. Make a socket start pause polling → W2 or L1 goes red.
- AC 5, the mark: move the mark check after the send in `Next`/`Server`, or drop `MarkSignedOut` from `OnLogout` → W8 goes red (a frame after the 204, or no close), and so do `TestNext` and `TestSignOutMark`.
- AC 5 (b): drop `socket.stop()` from the halted branch → W7 goes red.
- AC 5 (c): give `Next` no lifetime → `TestNext` goes red. Drop the reconnect → W4 and the node reconnect case go red.
- AC 5 (d): add the stored `SessionRef` to the frame → `TestFrames` and W1's no-ids assertion go red.
- AC 6: make `applyPushed` apply a frame's events without advancing the shared cursors (each event spoofed as cursor + 1, then the old cursors restored) → W9 goes red (the page shows "first").
- AC 7: remove `blockLiveSocket` from C8 → C8 goes red. That shows the helper is load-bearing.

**Manual checks:**
- In `git diff`, `poll`, `schedulePoll`, `applyPoll`, `fetchSnapshot`, `accept` and `stop` in `live-state.ts` are unchanged.
- No contended path appears in `git status --short`, and neither do `banners.spec.ts`, `support/floor.ts`, `e2e-online/**` or Epic 11's `support/*` files.
- `Shell.cls` changes only the route and its doc bullet, and `Data/Session.cls` only the mark.

**Implement-stage results** (lane-c throwaways, tags e31s1i and e31s1iw):
- `npm --prefix web test`: 1177 tests pass (live-socket.test.mjs: 19). `npm --prefix web run lint`: exit 0.
- Warm IRIS classes, each `passed`, measured seconds of the class: `Test.Web.Live` (new) 0.28 to 0.36, `Test.Live.Publish` 3.5 (TestWake included; it waits 2 s for its quiet check), `Test.Web.SessionEvents` 5.6, `Test.Data.Session` 0.1, `Test.Web.Shell` 0.1, `Test.Web.LeavingThePage` 0.04, `Test.Web.Status` 0.22, `Test.Web.SessionEndApi` 22.6, `Test.Web.Api` 1.2.
- Final tree (lead's `(once)` pass): `ci/iris.sh live sign-in --part 1/3`: 89 passed, 219 s. `--part 2/3`: 76 passed, 310 s (it holds live.spec.ts and socket.spec.ts; W12's 60 s included). `--part 3/3`: 81 passed, 195 s. `live floor`: 106 passed, 283 s (M10, M13, M14 and A2 to A5 included). `live demo-path`: passed, 128 s (9 skipped as before). Fresh `shard lane-b`, forward then `--reverse`, two parts each: 86 classes all passed, 291 s and 573 s forward, 556 s and 298 s reversed (the long ones hold `Schedule.Heartbeat`, 177 to 215 s, real Task Manager runs). One forward run of `Test.Schedule.Heartbeat` failed `TestTaskDeclared` ("the Task Manager ran the task within 75 s") on a loaded machine and passed alone on a fresh stack (177 s): wall-clock, not this story's code.
- `socket.spec.ts` own duration (sum of its tests, run in part 2/3, final tree): about 82 s, of which W12 (a quiet socket held to its 60 s lifetime) is 60 s: W1 0.32, W2 1.3, W3 0.20, W4 2.4, W5 0.15, W6 3.0, W7 4.4, W8 3.1 + 3.1, W9 1.3, W10 1.8, W11 1.2, W12 60 s. Without W12 it is about 22 s.
- W1: the frame was seen 30 ms after the publish began, and the reminder showed 2 ms after `publishReminder` returned (inference: the frame and the page update both land inside the publish call's own docker-exec time, so the true publish-to-page latency is below the call's duration and is not separable here).
- `bash ci/checks.sh`: all scripts passed (9 min 14 s, near the 10-minute cap on this machine; not this story's growth). `bash docker/tests/test-ci-config.sh`: all rules passed (31 s).

**Mutations** (each applied, observed red, reverted; the tree was checked byte-identical by md5 after each batch):
- mutation: remove the `Wake(stream)` call in `Publish` -> `Test.Live.Publish` `TestWake` red ("it was woken, not timed out").
- mutation: drop the Origin clause from `Refusal` -> `Test.Web.Live` `TestRefusals` (and `TestOnPreServer`) red; and W5 red in the browser.
- mutation: drop the online-demo clause from `Refusal` -> `TestRefusals` and `TestOnPreServer` red.
- mutation: remove the `onlineDemo` return in `LiveSocket.start` -> `live-socket.test.mjs` "constructs no WebSocket on the online demo" red.
- mutation: pass every frame regardless of `accepting()` -> `live-socket.test.mjs` "are dropped while the page is not accepting them" red, and B14 red (part 1/3).
- mutation: make the effect skip `socket.start` -> W1, W3, W4, W7 and W9 red.
- mutation: make a socket start pause the polling (`clearTimers()` after `socket.start`) -> L1 and W2 red (20 tests in all, the polling ones).
- mutation: move the mark check after the lifetime and the send in `Next` -> `TestNext` red ("a changed mark ends before a send").
- mutation: drop `MarkSignedOut` from `OnLogout` -> `Test.Web.SessionEvents` `TestSignOutMark` red, and W8 (both sign-out paths) red.
- mutation: `MarkSignedOut` does nothing -> `Test.Data.Session` `TestSignOutMark` red.
- mutation: drop `socket.stop()` from the halted branch -> W7 red.
- mutation: give `Next` no lifetime -> `TestNext` red.
- mutation: drop the reconnect (`scheduleReconnect` arms no timer) -> `live-socket.test.mjs` reconnect and backoff cases red. (W4 was not run with this mutation; its reconnect is covered by the node cases.)
- mutation: remove the `this.current !== socket` guard in `ended` and the `this.current === mine` guard in `connect` -> `live-socket.test.mjs` "counts the error and the close of one socket as one ending" and "ignores a socket that was replaced or closed by the page" red (both call the handlers they captured before the socket was released).
- mutation: `applyPushed` ignores `result.reload` (a Seq skip does nothing) -> W10 red (the page's cursor stays where it was).
- mutation: the server never writes the heartbeat (`Server` only notes the time) -> W12 red (no frame within 35 s).
- W11 (the Client-closes row) has no mutation line: with `Pause` ignoring a client close, the loop still ends within two seconds, because the platform's read-error path halts the process when the gateway drops the connection; W11 therefore pins the observable (the connection and the socket's process end), not the graceful path.
- mutation: add the stored `SessionRef` to the frame -> `TestFrames` red, and W1 red (its no-ids assertion).
- mutation: make `applyPushed` apply events without advancing the shared cursors -> W9 (and W1, W4) red.
- mutation: remove `blockLiveSocket` from C8 -> C8 red.
- mutation: remove the shell's `/OcuTalon.Web.Live.cls` route -> `Test.Web.Shell` `TestForwardsTheSocket` red.
- mutation: rename `OnLogout` in `SessionEvents` -> `Test.Web.LeavingThePage` `TestNoProductClassEndsASessionOnTimeout` red.

**QA-stage additions (QA)** (warm throwaway, tag e31s1qw; no browser or node test added, so the `browser` group's time is unchanged):
- (QA) `src/ocutalon/cls/OcuTalon/Test/Web/Live.cls` `TestServer` (new method, 0.08 s): runs `Server()` in process on a socket object with a shared connection to a dead gateway address, so its first `Write` or `Read` fails and the loop ends; the cursors show what the loop did. It pins the matrix's "Instance event" row at the loop (an event on the instance stream alone is sent and moves only the instance cursor; the session's alone moves only the session cursor; a quiet socket sends nothing) and the sign-out mark read by `Server` itself before a send. Before this, only `Frame` and `Next` were tested apart, and nothing failed if `Server` ignored the instance stream.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls` `TestSignOutWakesTheSocket` (new method, about 0.5 s): after `OnLogout` the session's wake resource is signalled; it is not for another session, on the online demo, or with no ref. Before this, W8's "closes within 1 s" passed without the wake, because the loop reads the mark every 0.25 s.
- mutation: `Server` compares only the session stream's head (`ahead` drops `instanceHead`) -> `Test.Web.Live` `TestServer` red ("an event on the instance stream only is sent"). (QA)
- mutation: `Server` passes its open-time mark as the current mark to `Next` (`Next(..Mark, ..Mark, ...)`) -> `TestServer` red ("a sign-out since the open ends the socket before it sends what is ahead"). (QA)
- mutation: drop `Publish.Wake(ref)` from `OnLogout` -> `Test.Web.SessionEvents` `TestSignOutWakesTheSocket` red ("its socket's wake resource is signalled"); `TestSignOutMark` and W8 stay green, which is why the test was added. (QA)
- Each was applied from a backup in the scratch folder and restored from it; `git diff | md5` was identical before and after (e29ef3ec...). `Test.Web.Live` and `Test.Web.SessionEvents` pass on the restored tree.
- mutation: `Pause` ignores the client's close (`Quit 0` for every Read status) -> `Test.Web.Live` `TestServer` red ("and writes no frame, not even a heartbeat", "a client that is gone (Read's 7951) ends the quiet loop at once"; the loop ran to the 25 s heartbeat). (CR)
- mutation: `Server` writes a heartbeat on a `wait` -> `TestServer` red ("and writes no frame, not even a heartbeat"). (CR)
- mutation: drop the `no_role` clause from `Refusal` -> `TestRefusals` ("no role", "with every check failing, the role is first") and `TestOnPreServer` red. (CR)
- mutation: drop the `bad_cursor` clause from `Refusal` -> `TestRefusals` (every bad cursor case) and `TestOnPreServer` red. (CR)
- Code-review results (CR; lane-c throwaways e31s1cw warm, e31s1c fresh): `Test.Web.Live` passed 0.62 to 0.91 s with the patches; each mutation above was applied to `Web/Live.cls`, observed red and restored from a scratch backup (`git diff --quiet 3010f5a7` on the file after each). `npm --prefix web run lint`: exit 0. `ci/iris.sh live sign-in --part 9/14` (socket.spec.ts alone, 13 tests): passed, 245 s in all, W5 0.17 s, W6 3.2 s, W12 60 s.
- Not added, with the reason: the heartbeat and lifetime of the loop (W12 and `TestNext` pin them; an in-process loop cannot wait without a gateway), the page-stop rows for 401, idle cap and reset (the one `halted()` effect that W7 pins covers them; a browser test per row would cost CI minutes), and an epoch change from a frame (the socket never runs on the online demo, the only place the epoch changes).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Web.Live` (a `%CSP.WebSocket`, synchronous) pushes each committed event after the client's cursors in `/events`' own body, reached at `/ocutalon/OcuTalon.Web.Live.cls` through one forwarding route in `Web/Public/Shell.cls`. Every check runs in `OnPreServer`. `Live.Publish` signals a per-stream `$SYSTEM.Event` resource after each commit. `Web.SessionEvents.OnLogout` raises a sign-out mark (`Data.Session.MarkSignedOut`, global `^OcuTalonP.SessionM`) that the socket reads on each loop; a 60 s lifetime stays as the backstop. The page's `LiveSocket` (`live-socket.ts`) opens it after the first snapshot on a non-demo install, reconnects in the background, and `live-state.ts` feeds each frame to `applyEvents` in one self-contained block; polling is unchanged beside it.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Web/Live.cls` (new): the socket, its refusals, `Next` and the loop.
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`: the forwarding route and one doc bullet.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`: `OnLogout`.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls`: `MarkSignedOut`, `SignOuts`, `MARKGLOBAL`.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls`: `WakeName`, `Wake`, and the wake after each commit.
- `web/src/app/live/live-socket.ts` (new) and `web/src/app/live/live-state.ts` (one block): the client.
- Tests: `Test/Web/Live.cls` (new), and extended `Test/Live/Publish.cls`, `Test/Web/SessionEvents.cls`, `Test/Data/Session.cls`, `Test/Web/Shell.cls`, `Test/Web/LeavingThePage.cls`; `web/scripts/live-socket.test.mjs`, `web/e2e/support/socket.ts`, `web/e2e/live/socket.spec.ts` (W1 to W12); `blockLiveSocket(page)` added to the polled-delivery tests of `live.spec.ts`, `chat.spec.ts`, `decision.spec.ts`, `try-it.spec.ts`, `announcements.spec.ts` and `guide.spec.ts`.

**Review.** Patches applied: six (W2 message, `within` comment, `Status.Equals` for 7950, W12 for the heartbeat and lifetime, two node cases made falsifiable, W10 and W11 for the Seq-skip and Client-closes matrix rows). Deferred: none. Every other finding was rejected with its reason in the Review Triage Log. Follow-up review recommended: false (no HIGH, one MEDIUM patched with its own test and mutation run).

**Verification.** See the results under `## Verification`: node tests 1177 pass, lint exit 0, nine warm IRIS classes pass, `live sign-in` parts 1/3, 2/3 and 3/3 pass (89, 76, 81), `live floor` 106, `live demo-path`, fresh `shard lane-b` both orders (86 classes), `ci/checks.sh` and `test-ci-config.sh`. Mutations were applied and reverted with the tree byte-identical.

**Residual risks.** W12 holds a socket for 60 s, so `sign-in` part 2/3 is about 310 s (about 5 s of stack start included); the unit's CI time rises by about 70 s. `ci/checks.sh` takes 9 min 14 s on this machine, near the 10-minute cap. `Test.Schedule.Heartbeat` is a wall-clock test that failed once under load. W11 pins the observable close, not the graceful-path branch (see its note under Verification). The socket path is inference-only for latency over real networks (W1's 30 ms is the local stack).
