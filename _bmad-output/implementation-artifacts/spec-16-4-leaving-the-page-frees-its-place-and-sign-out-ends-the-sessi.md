---
title: 'Story 16.4: Leaving the page frees its place, and Sign out ends the session'
type: 'feature'
created: '2026-10-29'
status: 'done'
baseline_revision: '25aab4984a05dc4b6daa879568c565689e7f9a4b'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-1, lines 99-111; AD-4, 155-178; AD-11, 314-329; AD-13, 345-395; AD-24, 657-684; AD-25, 685-736)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only About, lines 137-147; Frame and the dialog rule, 199-221; State Patterns, 328-347)'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md (read only Story 16.4, lines 4461-4503)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the online demo a CSP session lives 8 hours, so a visitor who closes the page, walks away or leaves a Visual Trace page holds a licence connection the 8-connection Community licence can't spare (NFR-23, DW-285). Sign out ends only the CSP session today: `POST /v1/session/end` logs out and `SessionOps` answers `EndSession` with `not_built`. The next sign-in therefore resumes the session, with its pairing, reminders, watches and approval requests still live. The page also has no idle cap, a 401 sends it to the local sign-in page, and it would render another session's snapshot after an epoch change.

**Approach:**
- With the online-demo flag set, the Web step gives the four sign-in-group applications a 120-second CSP timeout.
- The page frees its place after an idle cap (600 s, a product setting), on a 401 and on an epoch change, and returns to the splash. The splash then shows the place-freed notice whenever the browser still holds a resume cookie, except after an epoch change.
- On the online demo, Sign out opens a confirm dialog. Confirming calls `/session/end`, which submits the now-built `SessionOps.End` through `CommandsIn`, expires the resume cookie and signs the group out.
- The story also lands the owner's tagline change (DW-378) and three small ledger items (DW-290, DW-291, DW-333).

## Boundaries & Constraints

**Always:**
- **The flag decides.**
  - Every new branch runs only on the online demo: `Public.Settings.Get("onlineDemo") = "1"` server-side, and the loaded snapshot's `onlineDemo` in the page.
  - With the flag off, local and IPM installs behave exactly as today:
    - `Timeout` stays 28800 on every application;
    - Sign out has no dialog and posts `/session/end`, which only logs out;
    - a 401 goes to `/ocutalon/?signedOut=1` ("You were signed out.");
    - there is no idle cap, the epoch handling is unchanged, `/state` has no `idleSeconds` key, and no new setting row is written.
- **Timeouts (AC 1).**
  - With the flag on, `/ocutalon`, `/ocutalon/api`, `/ocutalon/trace/ocutalon/` and `/ocutalon/trace/ocuorders/` (the last only when it exists) get `Timeout` 120.
  - `/ocutalon/public` and every flag-off application keep 28800.
  - The step reads the flag through `OcuTalon.Data.Public.Settings`, through one helper that the seeds also use.
- **Polling, reload, pagehide (AC 1).**
  - The page keeps polling `/events` about once a second, as today.
  - Nothing signs out, ends a session or sends a beacon on `pagehide`, `beforeunload`, `unload` or `visibilitychange`.
- **Idle cap (AC 3).**
  - The cap is `/state`'s `idleSeconds` (online demo only). Its value is `Setting.Get(Setting.#IDLEKEY, Setting.#IDLESEED)`: the seed is 600, and any value that isn't a whole number above 0 also gives 600. The Web step seeds it only with the flag on.
  - Only these count as activity: a `keydown` or `click` anywhere in the document (capture phase), and a message the chat outbox sends (`ChatOutbox.sends`). Polls, snapshots, timers and pointer movement never count.
  - The cap runs only while the page polls. It stops at Sign out, a 401, an epoch change and the reset's resetting view (Story 16.8).
  - After a sleep, a timer that fires late leaves at once when the cap has passed (wall-clock arithmetic).
- **Leaving the page (online demo).** `SessionGate` handles every exit, once, in this order: stop `LiveState`, stop the idle cap, then (except after a 401) run the group sign-out, then `location.replace` to the splash.
  - **The group sign-out** is a same-origin GET of `/ocutalon/?IRISLogout=end&t=<unique>`. It is never a navigation to that URL, because the splash's form action (`Error:FullURL`) would carry `IRISLogout` into the next sign-in POST (inference).
    - The GET is awaited for at most 3 s, and the page leaves whatever it answers.
    - It requests a trace application's own `?IRISLogout=end` only if Task 0 (a) shows the main sign-out leaves that application's trace session or its licence unit alive. Even then, it requests only the trace applications this page opened a link to (recorded by `DemoBusyState.openTrace`).
    - It never sends a request after a 401: the CSP session is already gone, and AD-13 says nothing calls IRIS under a public account without a session.
  - **The splash address** is `splashAddress(PAGE_LOADED_AT_MS)` = `/ocutalon/?since=<load time>` after the idle cap and after a 401. After an epoch change it is `splashAddress(PAGE_LOADED_AT_MS, true)` = `/ocutalon/?since=<load time>&ended=1`.
  - **Reset first.** `SessionGate.onSignedOut`'s reset check (`ResetWatch.enterIfDue`) stays the first test.
- **Epoch (AC 4).**
  - On the online demo the page never applies a poll or a snapshot whose `epoch` differs from its first snapshot's. It applies none of that answer's events, does not reload, and leaves with `ended=1`. The local behaviour (a reload) is unchanged.
  - The epoch stays the `Session` row's own value (16.3), never `%session.SessionId`.
- **Place-freed notice.**
  - `Splash.InfoNotice` keeps 16.8's reset and restart notices first: they show when `since` is earlier than `lastReset`.
  - Otherwise it shows `PLACEFREED` ("You were away for a while, so your place was freed for other visitors. Sign in again to pick up where you left off.") in the same `notice notice-info` element above both cards, when the request carries the resume cookie and no `ended=1`.
  - Otherwise it shows nothing.
  - The splash reads the cookie with `%request.GetCookie`. Its name is defined once, in the public class `Web.Public.Shell` (`RESUMECOOKIE`). `SessionEvents.#RESUMECOOKIE` keeps answering it, as a COSEXPRESSION of Shell's.
  - `Shell.RedirectUrl` drops `ended` pairs as it drops `since`.
- **Sign out (AC 5).**
  - On the online demo the account menu's Sign out opens a modal dialog through `Dialogs.open`.
  - The dialog is named by its one sentence, "Signing out ends this demo session. Signing in again starts a fresh one.". It has **Cancel** (initial focus, overriding the heading rule) and **Sign out**, focus is trapped inside it, and focus returns to the account trigger when it closes.
  - Cancel, Esc or a press on the backdrop closes it, sends no request and changes nothing.
- **`POST /v1/session/end` on the online demo.** The envelope checks run as today, then:
  - The CSP session's `Ownership.SessionRef` gives the session, and an `EndSession` with that `SessionRef` is submitted through `Commands.Submit(command, "web_user", .result)`.
  - On `Ok`, the answer expires `OcuTalonResume` and signs out with `%session.Logout(1)` and `EndSession` = 1, then answers 204.
    - The expiry is the same `SetCookie` attribute list as 16.3's, through one `SessionEvents` setter that both use: value "", an RFC 1123 date in the past, path `/ocutalon/`, Secure, HttpOnly, Strict.
  - `not_built` gives 501. Any other failure gives 500 `server_error`, with no cookie change and no logout.
  - An unresolved session (16.3's attach failure) gives a logout only and 204, with no command.
  - REST writes nothing else (AD-1).
- **The page after `/session/end` (online demo).**
  - After a 204: the trace sign-outs only if Task 0 (b) needs them, then `location.replace('/ocutalon/')` (the plain splash).
  - After any other answer but a 401: the full group sign-out, then the plain splash. The session stays resumable.
- **`SessionOps.End` (Lane B's operation, AD-4, AD-33).**
  - Order of work, each step tried even when an earlier one failed:
    1. `..Unlink(sessionRef, "", "session_end", ChannelOf(origin), "", .changed)`: Story 10.3's unlink, unchanged, with no notice;
    2. one `CancelReminder` (its `ReminderRef` and the command's `Origin`) per pending reminder of `Ownership.Reminders`, sent synchronously to the `ReminderOps` item;
    3. one `StopWatch` (its `Namespace` and `Production`) per row of `Ownership.Checks` whose `Kind` is `Watch.Ops.#KIND`, sent synchronously to `WatchOps`;
    4. `OcuTalon.Bridge.Approval.Cancel(ref, "", channel, IrisUser(sessionRef), sessionRef)` for each pending request of `Ownership.Approvals` whose `OwnerRef` is the session;
    5. the row's `ResumeHash` is set to "".
  - It answers `Ok 1, "ended"`, or `Ok 0, "failed"` after trying every step. A session with no row answers `Ok 0, "no_session"`. A repeat changes nothing and answers `ended`.
  - It never edits `Unlink`, `Pairing.cls`, `ReminderOps`, `Watch.Ops` or `Bridge.Approval`.
- **Closed page (AC 2).** Nothing new runs when a CSP session ends: no `OnTimeout`, `OnEndSession` or `OnLogout` callback, and no task.
- **Real paths (DW-291, AD-29).** The tests cancel reminders through the real `ReminderOps`, stop watches through the real `WatchOps` (Story 5.1 has merged) and cancel approvals through the real `Approval.Cancel`. There is no test double. Telegram cases are `notBuilt(..., '31.3')`.
- **Test discipline (Stories 16.1 to 16.8):**
  - every context and curl jar ends with the group sign-out;
  - every page request carries a unique `probe=<n>`;
  - each case creates and removes its own rows;
  - assertions are scoped to the case's own sessions, never instance counts;
  - no password or resume reference is printed.
- **Runtime targets (Rule 21):**
  - stacks only through `ci/iris.sh` and `ci/warm.sh`, with lane C's three variables;
  - `ocutalon-slot-c`, namespace `OCUTALON`, only for optional `iris_doc_load` compiles, after `iris_server_info` shows build 154 on port 52792.

**Never:**
- **Never edit these files.** A need to edit one is a `## Clarification Needed` stop.
  - `Data/Pairing.cls`, `Schedule/ReminderOps.cls`, `Watch/Ops.cls`, `src/bridge/**` (call `Approval.Cancel`, never edit it), `Test/Bridge/**`, `Test/Watch/**`, `Fix/**`, `Install/**` other than `Install/Step/Web.cls`, `src/module.xml`, `docs/**`, `release/**`, `.github/**`, `docker/tests/test-readme.sh`.
  - `SessionOps.Unlink`'s body or signature.
- **Never sign out on `pagehide`.** No beacon either.
- **No new application role or grant.** `PermittedClasses` and `EventClass` of the trace applications stay unchanged (AD-24, AD-4).
- **No new public text** beyond the AC's two sentences and the tagline. A needed text that is in neither the AC nor the UX is a `## Clarification Needed` stop.
- **No new stored field or table.** `End` only changes existing rows' state, through their owners.
- **Out of scope:**
  - a per-tab sign-out of a trace page while the OcuTalon page stays open (declined, see Design Notes);
  - Telegram behaviour (31.3);
  - document and memory drops (19.5, 34.2);
  - the allowances (16.9);
  - voiding an unused pairing code at sign-out (Telegram is off in 0.1.0).

## I/O & Edge-Case Matrix

Where each row runs:
- **The new `online-session` live unit** (fresh flag-on throwaway): rows 1-live, 2 and 4 as curl and `iris_script` rows.
- **Its browser step:**
  - rows 3, 5, 7, 9 and 9b in `web/e2e-online/session/leave.spec.ts`;
  - rows 10 and 11 in `web/e2e-online/session/sign-out.spec.ts`.
- **In process on the warm stack:** rows 1, 6, 8 and 12 to 14.
- **The local stacks:** row 15.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Timeouts (AC 1) | In process: `Web.Definitions` with the flag on, then off. Live: the four applications after the flag-on start; a curl jar opens a Visual Trace page | On: 120 for `/ocutalon`, `/ocutalon/api` and the trace applications, 28800 for `/ocutalon/public`. Off: 28800 everywhere. Live: `Security.Applications` reads 120 for the four, and the jar's trace CSP session has `AppTimeout` 120 (Task 0 (c)) | -- |
| 2 | Polling keeps the session (AC 1) | Live: jar K signs in and GETs `/api/v1/events` with its cursors every 5 s through the browser step. Jar C signs in at the same moment and makes no request | At least 150 s after C's last request, K's `/state` answers 200 with K's epoch, and C's CSP session no longer exists | The row fails, naming the elapsed seconds, when the browser step was shorter than 150 s and the wait did not make up the rest |
| 3 | Reload (AC 1) | L1: sign in, then reload twice | The same `epoch` each time and the loaded main page, never the splash. No request to `IRISLogout` or `/session/end` (`recordTraffic`). The row's `CspSessionId` CSP session still exists | -- |
| 4 | Closed page (AC 2; Telegram part off) | Live: before the browser step, C (curl) signs in and opens a trace page. C's session gets a fixture turn, a fixture pairing, a real reminder due in 1 h (`ReminderFixture.Set`), a real Orders watch (`StartWatch` through `Commands.Submit`), a pending fixture approval and a `BreakFeedRun` row. Then C makes no request | After the browser step, C's main and trace CSP sessions are gone within 180 s of its last request (`MEASURED` delay, licence counts `MEASURED`). Every row is unchanged: the turn, the pairing (SessionRef C), the reminder pending, the watch row, the approval pending, the run row. Then, with no CSP session of C: a real reminder set for C due in 5 s fires (`State` fired, its delivery row); `Approval.Answer` on the approval answers done; the watch row's `LastRunAt` passes the moment C was seen gone (wait at most 90 s). The splash GET with C's jar shows `PLACEFREED` above both cards. A sign-in with C's jar resumes C's epoch with the rows still there. `notBuilt('Telegram keeps working with no CSP session open', '31.3')` | -- |
| 5 | Idle cap (AC 3) | L2, page clock installed before load: sign in, open a trace page in a second tab and close that tab, then `runFor` with no activity | 590 s: still on the page, with at least one `/events` answer in that time (polls don't count). A key press at 590 s, then 590 s more: still there. A click on the page, then 590 s more: still there. 600 s with no activity: the page lands on `/ocutalon/?since=<load>`, `#ocu-notice` reads `PLACEFREED` above `.splash-cards`, the context's `/api/v1/state` is 401, and a new tab's trace URL shows the trace sign-in form. Signing in from the splash gives the same `epoch` | -- |
| 6 | Idle setting (AC 3) | In process: `/state` with the flag on and the row absent, holding 300, or holding "x"; the flag off. `Web.SeedSettings` with the flag on (absent key; an existing "300"), then off | 600, 300 and 600; flag off: no `idleSeconds` key. The seed writes "600" when the key is absent and keeps "300"; with the flag off it writes no row | -- |
| 7 | 401 (AC 3) | L3: sign in; out of band, the context's own `request.get('/ocutalon/?IRISLogout=end&probe=<n>')` | The next poll's 401 takes the page to `/ocutalon/?since=<load>` with no `signedOut`. The splash shows `PLACEFREED`, and no "You were signed out." text anywhere. No API request follows the 401. Signing in gives the same `epoch` | -- |
| 8 | Notice rules | In process (`Test.Web.Splash`): the resume cookie with no `since`; the cookie and a `since` before `lastReset`; the cookie and `ended=1`; no cookie; the local page with the cookie | `PLACEFREED`; the reset notice (16.8, unchanged); no notice; no notice; the local page unchanged. The redirect after the sign-in POST drops `ended` and `since` (splash.spec S7 gains `ended=1`) | -- |
| 9 | Epoch change, injected (AC 4) | L4: a loaded page. Its next `/events` answer is route-fulfilled with another `epoch` and a `chat.message` event whose text is X; `/state` is routed to another epoch with X in its chat | The page never shows X and never re-requests `/state`. It sends the group sign-out and lands on `/ocutalon/?since=<load>&ended=1` with no notice | -- |
| 9b | Epoch change, real (AC 4) | L5: pages P1 and P2 in one context, session S1. P1's `/events` is aborted by a route while P2 signs out through the dialog and signs in again (S2, with a fixture turn Y). Then the route is removed | P1's next poll carries S2's epoch. P1 never shows Y (an exposed binding records any node holding Y). It signs the group out and lands on `?since=<load>&ended=1`. A sign-in from P1 gives an epoch other than S1's | -- |
| 10 | Dialog (AC 5) | O1: the account menu's Sign out on the online demo | A `role=dialog`, `aria-modal` dialog named by the sentence, with exactly the buttons Cancel and Sign out. Cancel is `document.activeElement`. Tab and Shift+Tab stay inside it. Esc closes it, and so does Cancel: no `/session/end` request, the same epoch, focus on the account trigger | -- |
| 11 | Sign out ends the session (AC 5, AC 6; DW-291, DW-285) | O2: sessions A and B (two contexts), each with a fixture pairing, a real reminder, a real Orders watch and a pending approval. A opens a trace page and closes it. A presses Sign out, then Sign out again in the dialog | `/session/end` answers 204, and its `Set-Cookie` expires `OcuTalonResume` (path `/ocutalon/`). The plain splash shows with no notice, and `resumeCookie(context)` is undefined. A's state: the reminder cancelled with its waiter ended (`ReminderFixture.WaitEnded`), the watch row gone, the approval cancelled with an Approval audit entry `cancelled`, the pairing unlinked with an audit entry `unlinked/session_end/web`, and `ResumeHash` "". A's trace URL shows the trace sign-in form. Every one of B's rows is unchanged. A's next sign-in gives a new epoch | -- |
| 12 | `End` in the production (AC 5) | `Test.Core.SessionOpsProduction`: session A with two real reminders, a real watch, two pending approvals and a fixture pairing; session B with one of each; End of A from web_user, then End of A again | A: both reminders cancelled with their waiters ended, the watch row deleted with a `CheckChanged` `Stopped` 1 to Checks, both approvals cancelled, one unlinked entry (session_end, web), one pairing event, no Notification to Notify, `ResumeHash` "", `Ok 1 ended`. B: untouched. The repeat: `ended`, nothing changes, nothing new is audited. With one of A's reminder rows held open by the test (concurrency 4), End still unlinks, stops and cancels the rest and answers `failed` | End of a missing session: `Ok 0 no_session` |
| 13 | `End` unit (AC 5) | `Test.Core.SessionOps` probe: a session with a fixture pairing only; an EndSession whose session has no row | `AuditSummary` = `unlinked/session_end/<ref>/web`, no notice, `ResumeHash` "", `ended`; then `no_session` | -- |
| 14 | The route (AC 5; integration: `Web.Api` consumes `SessionOps.End` through `CommandsIn`) | `Test.Web.SessionEndApi` over the production, flag on, a CSP session attached to a visitor row with a pending real reminder; then a session whose End fails (the test holds its pending reminder row open with concurrency 4, so `ReminderOps` answers failed); then no attached session | 204, `%response` holds the expired cookie with the exact attributes, `%session.EndSession` 1 and logged out, one EndSession request header from CommandsIn to SessionOps, and the reminder cancelled. The failing End: 500 `server_error`, no cookie, not logged out. No attached session: 204 and a logout, with no header to SessionOps. `TestEndSession` (flag off) is unchanged | -- |
| 15 | Local unchanged (AC 1, AC 5) | `live sign-in` (flag off) | Green unchanged: `session.spec` S1 (Sign out with no dialog), S3 (`?signedOut=1` and "You were signed out."), S7, and `frame.spec` F5 (menu items) | -- |

</intent-contract>

## Code Map

**Server**
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls`:
  - `Run` :53-71; `SeedSettings` :92-96 (flag read at :94 through `Setting.Get`);
  - `Definitions` :123-159; `TraceApp` :164-176;
  - `Common` :179-195, which sets `Timeout` 28800 at :187 for every application, `/ocutalon/public` included;
  - `Apply` :198-206 runs in %SYS;
  - there is no timeout constant today.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - the routes :115-128, with `/v1/session/end` → `EndSession` at :125;
  - `EndSession` :193-201 (`Logout(1)`, `EndSession` 1, 204);
  - `Unpair` :645-661, the submit shape to mirror (`Ownership.SessionRef`, `Commands.Submit(..., "web_user", .result)`, `not_built` → 501);
  - `StateBody` :676-729: `epoch` :691, `onlineDemo` :697, `traceAccount` and `AddReset` :724-725; `/events` epoch :872;
  - `CurrentSession` :830-840; `ServerError` :159-168; `OnPreDispatch` envelope :133-145.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls`:
  - class doc :1-23 (line 16 says EndSession stays not built);
  - `OnMessage` :48-65 (the stub at :53);
  - `Unlink` :77-118, which takes `reason` "session_end" and `noticeKey` "" (Epic 10's `TestUnlinkApi` already uses these);
  - `Unpair` :199-216; `Failed` :230; `Announce` :238; `ChannelOf` :250 (`CHANNELS` :31); `IrisUser` :256; `WriteAudit` :276; `SendNotice` :282 (the test seams); `Result` :288.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls`:
  - the `EndSession` route :175 (origins web_user, web_admin, telegram, timer, system; never tool);
  - `TIMEOUT` 120 :33; no change.
- `src/ocutalon/cls/OcuTalon/Msg/Command/EndSession.cls`: no properties of its own; `Msg/Command.cls` has `Origin`, `IdempotencyKey`, `SessionRef`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `SessionRef` :136-155 (the online-demo branch :148-151); `Reminders` :264 (pending only); `Checks` :270; `Approvals` :297 (also instance requests locally, so filter on `OwnerRef`); `Pairing` :303.
- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls`: `Cancel` :172-209, read only; it ends the waiter and publishes the event.
- `src/ocutalon/cls/OcuTalon/Watch/Ops.cls`: `KIND` "production" :21; `OnStart` :57-, which refuses all but the Orders production on the online demo through `Watch.Reader.Admits`; `OnStop` :103-135, read only; it deletes the row and sends `Changed`.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`: `Admits` and `OnlineDemo` :130. These give the Orders namespace and production that a test's real `StartWatch` must name.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`: `Cancel` :348-357; `Answer` :247; read only.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls`: `Epoch` :30, set in `NewRow` :100; `ResumeHash` :41 (unique; empty on local rows); `CspSessionId` :44.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`:
  - `RESUMECOOKIE` :26; `AttachVisitor` :58-94; the `SetCookie` :91; `CookieExpiry` :110-117;
  - it has no `OnLogout` and none must be added.
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`: `REFUSALKEY` :27, the precedent for a public key; `RedirectUrl` :142-152 drops `since`.
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`:
  - the class doc :1-18; `RESETNOTICE` and `RESTARTNOTICE` :57-62;
  - `OnLoginPage` writes `InfoNotice()` at :167, before `.splash-cards` at :168;
  - `InfoNotice` :213-227.
  - It may reference only `%CSP`, dynamic objects, the allowed `$SYSTEM` classes and the two public packages (AD-3, CI-checked).
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls`: `ADDRESSLIMITKEY` and `ADDRESSLIMITSEED` :12-15 are the pattern to mirror; `Get` :32; `Seed` :50.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`: `splash.resetNotice` and `splash.restartNotice` :474-483 show the entry shape and source form; the place-freed row's source is "EXPERIENCE State Patterns / Place freed (online demo)".

**Server tests**
- `Test/Web/Install.cls`: `TestDefinitions` :42-73; `Expected` :418-469 (`Timeout` 28800 :426).
- `Test/Web/Api.cls`:
  - class doc :1-23; the DW-290 clause is at :14-15 ("and a check in a namespace with no trace application carries none");
  - `TestEndSession` :649-663 (flag off, kept); `TestStateTraceAccount` :1447, the online-only key precedent.
- `Test/Web/PairingApi.cls`: the pattern for route tests over the production (`Guard` :277, `Call` :349; RUNS IN THROWAWAY STACKS AND CI ONLY).
- `Test/Web/Splash.cls`: `TestInfoNotice` :451; `PageWith(query)` :593, which gains a cookie argument; `Render` :609. `Test/Web/StubRequest.cls` builds requests with cookies (`%request.Cookies(name, 1)`, as 16.3's tests do).
- `Test/Web/PublicTexts.cls`: `Classified` :123-188; counts compared 40, notInUx 2, notText 29 (:39, :82-84).
- `Test/Msg/Catalog.cls`: core 93 :80, fixtures 115 :121, `Keys` :952, `Fixtures` :1184.
- `Test/Data/Setting.cls`: `TestAddressLimitSetting` :161, the pattern.
- `Test/Core/SessionOps.cls`: `TestUnlinkApi` :522-558; `TestEndSessionStaysNotBuilt` :592-602 is replaced; helpers `Probe` :616, `Session` :630, `AuditSummary` :703.
- `Test/Core/SessionOpsProduction.cls`: doc :16; `TestEndSessionStaysNotBuilt` :195-202 is replaced; `Submit` :244.
- `Test/Core/CommandsInProduction.cls`: doc :4-6 and :25-27; `TestStubOwnersAnswerPlainEnglish` :29-56 uses EndSession, the last stub owner. "Each owner's story rewrites its row here when it builds the owner."
- `Test/Schedule/ReminderFixture.cls`: `Set` :66, `Cancel` :51, `WaitEnded` :241, `RemoveAll` :163; already used from browser specs through `irisScript`.
- `Test/Data/Fixture.cls`: `Session` :19, `Turn` :32, `Approval` :102, `BreakFeedRun` :156, `Pairing` :230, `Clean` :331, `Headers` :427, `Between` :450.
  - If `Approval.Cancel` refuses a fixture row because it has no Workflow task, raise a real request the way Epic 6's tests do, reading `Test/Bridge/**` only.

**Web**
- `web/src/app/session/session-gate.ts`: `onSignedOut` :30-37, `signOut` :40-52, `HOME` :9.
- `web/src/app/session/splash-address.ts`: `PAGE_LOADED_AT_MS` :12, `splashAddress` :23-25.
- `web/src/app/live/live-state.ts`: `load` :100-112; `stop` :134-143; `fetchSnapshot` :155-180; `accept` :183-198 (where the epoch guard goes); `applyPoll` :248-262. The doc at :39-40 already names the idle stop.
- `web/src/app/live/live-store.ts`: `applyEvents` :195-214, which compares the epoch at :196.
- `web/src/app/live/reset-watch.ts`: `enterIfDue` :64-73, `enter` :107-125.
- `web/src/app/live/demo-busy-state.ts`: `openTrace` :44-53, the online demo's trace opener (`trace-link.ts` press :194-212, `header.ts` `pressConversation` :442-455).
- `web/src/app/header/header.ts`: the account menu :197-201; `signOut` :457-459; `openAbout` :461-463.
- `web/src/app/shared/dialogs.ts`: `open` :24-37 (`autoFocus: 'first-heading'`).
- `web/src/app/about/about-dialog.ts`: the dialog pattern; the tagline :26; the note :42.
- `web/src/app/chat/chat-outbox.ts`: `send` :56 bumps the `sends` signal.
- `web/src/app/api/api-types.ts`: `StateSnapshot` :37-59. `api-client.ts`: `endSession` :39-41.
- `web/src/app/live/contact-watch.ts` and `web/scripts/contact-watch.test.mjs` with `scripts/fake-clock.mjs`: the framework-free, fake-clock-tested pattern for the idle cap.
- `web/src/app/api/envelope.interceptor.ts` :21-49 handles only `/ocutalon/api/`; after a 401 every call fails at once.

**Web tests**
- `web/e2e-online/support.ts`: `SIGN_OUT` and `TRACE_SIGN_OUTS` :15-18; `signOutGroup` :24-34, whose doc says 28,800 s; `signInFromSplash` :45; `resumeCookie` :83; `sessionRow` :106; `removeSession` :130.
- `web/e2e-online/reset.spec.ts`: R6 :550-573 asserts `signedOut=1` for a pre-reset 401; `routeLivePath` :353-384 and the epoch hooks.
- `web/e2e-online/splash.spec.ts`: S7 :474-495, the redirect dropping `since`.
- `web/e2e/support/clock.ts` (`recordTraffic`, `traffic`, `runUntil`, `freeze`); `web/e2e/support/iris.ts` (`irisScript`, `chk`, `quoted`); `web/e2e/demo-path/not-built.ts:11`.
- `web/e2e/frame/frame.spec.ts`: the tagline at :252 and :262; the note at :257 and :263.
- `web/scripts/ux-strings.test.mjs`: the tagline at :280 in `SOURCES.ux`, which also holds 'Sign out' :289.
- `web/e2e/rail/rail.spec.ts`: `open()` :76-84 (DW-333). `signIn` (`e2e/sign-in/helpers.ts:60-63`) waits for no navigation.
- `web/playwright.config.ts`: the projects :41-57 (chromium's `testIgnore` is the precedent; `online-demo` :56). `web/package.json`: `e2e:online-demo` :20. `web/scripts/playwright-projects.test.mjs` pins the projects.

**Live units**
- `docker/tests/test-online-demo.sh`:
  - the header :2-80; passwords and the anchor :98-121; the override :124-146; build and start :149-170;
  - the helpers `logout_all` :291-297, `online_signin` :299-321 and `signin_outcome` :323-342; `run_e2e` :847-857.
- `docker/tests/lib-live.sh`: `live_start`, `iris_script` :307, `check_session` :479. `docker/tests/lib-scan.sh` is the precedent for a shared unit library.
- `ci/units.sh`:
  - `group_units` :27-37 (`install-fresh` = install-start, bundle-folder);
  - `BROWSER_UNITS` :41;
  - the measured CI job times (runs 40806153227 and 40803657925): install-fresh 827-847 s, install-upgrade 806-1108 s, browser 1449-1517 s, image 1635-1797 s, shards 1617-1877 s.

## Tasks & Acceptance

**Execution:**

**Task 0** (implement, first): write the new unit's start and its Task 0 rows first (`docker/tests/lib-online.sh` and `docker/tests/test-online-session.sh`, below), together with the server tasks that (b) needs. Run them on lane C's throwaway before the page's group sign-out is written. Print each result as a `MEASURED` line and record it under Verification. Any temporary diagnostic is reverted byte-identical and never committed.
- (a) A jar signs in and opens a Visual Trace page; then `GET /ocutalon/?IRISLogout=end` with that jar.
  - Measure whether the jar's trace CSP session is gone within 15 s, with `$SYSTEM.License` LU before and after.
  - If it is not gone, the page's group sign-out also requests the trace applications it opened (see Always).
- (b) The same, but with `POST /api/v1/session/end` on the online demo instead.
  - This decides whether the page requests the trace sign-outs after a 204.
- (c) The trace CSP session's `AppTimeout` on the flag-on stack (expected 120).
- (d) How many seconds after its last request a closed jar's main and trace sessions disappear.
- (e) How the unit names a jar's CSP sessions: the `Session` row's `CspSessionId` for the main session, and for the trace session the `%CSP.Session` row matching the jar's trace cookie (or whatever Task 0 finds).
- If (a) and (b) show that no request ends a trace session, stop with `## Clarification Needed`.

**Server**
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` (rows 1, 6):
  - add `Parameter ONLINETIMEOUT = 120;` and `Parameter LOCALTIMEOUT = 28800;`;
  - add a private `OnlineDemo()` that reads `Public.Settings.Get("onlineDemo") = "1"`; `SeedSettings` uses it too;
  - `Common` takes the timeout: 120 for the four sign-in-group applications on the online demo, 28800 otherwise and for `/ocutalon/public`;
  - `SeedSettings` also seeds `Setting.#IDLEKEY` with `IDLESEED`;
  - the class comment names both.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` (row 6): add `Parameter IDLEKEY = "onlineDemo.idleSeconds";` and `Parameter IDLESEED = 600;`, each with a doc line. No existing line changes.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (rows 6, 14):
  - `StateBody`: with the flag on, `idleSeconds`, a whole number from the setting, or 600 when the setting holds none above 0; placed with `traceAccount`;
  - `EndSession`: the online branch per Always; the flag-off branch unchanged;
  - both comments state it.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` (rows 12, 13):
  - `OnMessage` routes `EndSession` to a new private `End(command)` per Always;
  - add the outcome messages (`MESSAGEENDED`, `MESSAGENOSESSION`);
  - the class doc's EndSession line states the contract (replacing ":16");
  - `Unlink` is unchanged.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls` (rows 8, 14):
  - `RESUMECOOKIE` becomes `Parameter RESUMECOOKIE As COSEXPRESSION = "##class(OcuTalon.Web.Public.Shell).#RESUMECOOKIE";`. If a project check refuses a COSEXPRESSION parameter, drop the parameter and point its callers at Shell's;
  - add one `ResumeCookie(value, expiry)` setter with 16.3's attribute list; `AttachVisitor` and `Api.EndSession` (expired) use it.
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` (row 8):
  - add `Parameter RESUMECOOKIE = "OcuTalonResume";`;
  - `RedirectUrl` drops `ended` pairs too;
  - its comments say so.
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls` (rows 4, 5, 7, 8):
  - add the `PLACEFREED` parameter (the UX sentence);
  - `InfoNotice` applies the order in Always;
  - the class doc names the notice.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` (row 8): add `splash.placeFreed`: the text, no slots, the source above.

**Server tests**
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`: core 94, fixtures 116, `Keys`, a `Fixtures` entry.
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls`: `PLACEFREED` → compared (`splash.placeFreed`), `Shell.RESUMECOOKIE` → notText. The counts move by exactly one each: 41 and 30.
- `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls` (row 1): `TestOnlineDemoTimeout`. It saves and restores `onlineDemo` through `Public.Settings`; `Expected` (flag off) is unchanged.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` (rows 6, DW-290):
  - add `TestStateIdleSeconds`; the setting row and the flag are saved and restored;
  - the class doc's :14-15 clause becomes what the test asserts since Story 5.6: a check carries its latest run's traceUrl into its namespace's trace application (read the assertion near :251);
  - update any key-order assertion that the new online-only key moves.
- `src/ocutalon/cls/OcuTalon/Test/Web/SessionEndApi.cls` (new; row 14): mirrors `Test.Web.PairingApi` (Guard, Call, InProduction clean-up). The copied private helpers carry that reason in the commit, because they are private to another story's class.
- `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls` (row 8): add `TestPlaceFreedNotice`; `TestTexts` gains `PLACEFREED`; `PageWith` gains an optional cookie.
- `src/ocutalon/cls/OcuTalon/Test/Data/Setting.cls` (row 6): add `TestIdleSetting`. No existing method changes.
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls` (row 13): replace `TestEndSessionStaysNotBuilt` with `TestEndUnlinksWithoutNotice` and `TestEndNeedsTheSession`; update the header list.
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOpsProduction.cls` (row 12): replace `TestEndSessionStaysNotBuilt` with `TestEndThroughTheProduction` and `TestEndAgainChangesNothing`; update the doc.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls`:
  - with no stub owner left, `TestStubOwnersAnswerPlainEnglish` becomes `TestEndSessionReachesSessionOps`: Ok 1, `ended`, one response header to CommandsIn that is not an error;
  - the class doc drops "the stub owner";
  - `not_built` stays pinned by `Test.Core.CommandsRouting`'s probe (confirm it).

**Web**
- `web/src/app/session/splash-address.ts` and its node test (rows 5, 7, 9): `splashAddress(loadedAtMs, ended = false)` appends `&ended=1`. Update the doc's 16.4 line.
- `web/src/app/session/idle-cap.ts` (new, framework-free) and `web/scripts/idle-cap.test.mjs` (row 5):
  - `IdleCap` takes `start(seconds)`, `touch()` and `stop()`, with an injected clock, and calls its handler once;
  - tests: it fires at exactly the cap after the last touch; a touch resets it; `stop` silences it; a late timer fires at once; a second `start` replaces the first.
- `web/src/app/live/live-store.ts` (+ `scripts/live-store.test.mjs`) and `web/src/app/live/live-state.ts` (rows 9, 9b):
  - `applyEvents` reports an epoch change apart from a Seq gap;
  - on the online demo, `LiveState` never applies an answer or snapshot of another epoch, stops, and signals the change (a signal the gate reads; LiveState must not import SessionGate);
  - the local reload path is unchanged.
- `web/src/app/session/session-gate.ts` (rows 3, 5, 7, 9, 11): add `leave(ended)` per Always; `onSignedOut` takes the online branch; `signOut` gets the online after-call path; the idle cap is wired to the document listeners and `ChatOutbox.sends`; the class doc is updated.
- `web/src/app/live/demo-busy-state.ts`: only if Task 0 (a) needs it, record the trace application of each URL `openTrace` opens.
- `web/src/app/shared/dialogs.ts`: add an optional `autoFocus` to `DialogOptions`; the default stays `'first-heading'`.
- `web/src/app/header/sign-out-dialog.ts` (new, the `AboutDialog` pattern) and `web/src/app/header/header.ts` (row 10): on the online demo `signOut()` opens the dialog with `restoreFocus` the account trigger. Its Sign out closes the dialog and calls `gate.signOut()`. Button styles follow DESIGN.md's dialog.
- `web/src/app/api/api-types.ts`: add `idleSeconds?: number` to `StateSnapshot`.
- `web/src/app/about/about-dialog.ts` (DW-378): :26 becomes "An AI assistant for InterSystems IRIS."; :42 stays verbatim.

**Web tests and config**
- `web/scripts/ux-strings.test.mjs`:
  - the tagline at :280 becomes the new text;
  - the dialog sentence and 'Cancel' join `SOURCES.ux` (both verbatim in EXPERIENCE.md :206); 'Sign out' is shared;
  - a new `*_TEXTS` constant joins `IMPORTED`.
- `web/e2e/frame/frame.spec.ts` (DW-378): :252 and :262 use the new tagline; the note lines stay.
- `web/e2e/rail/rail.spec.ts` (DW-333): `open()` arms `page.waitForResponse` for the GET of `/ocutalon/api/v1/state` before `signIn`, awaits it (status 200), then keeps its two expects.
- `web/playwright.config.ts`, `web/package.json` and `web/scripts/playwright-projects.test.mjs`:
  - `online-demo` gains `testIgnore: ['**/e2e-online/session/**']`;
  - a new project `online-session` with `testDir: './e2e-online/session'`, Desktop Chrome;
  - a new script `"e2e:online-session": "playwright test --project=online-session"`;
  - the projects test covers both.
- `web/e2e-online/session/leave.spec.ts` (new; rows 3, 5, 7, 9, 9b): L1 to L5, plus `notBuilt('L6: a paired Telegram chat keeps working while no CSP session is open', '31.3')`. Every case signs out and removes its rows in `finally`.
- `web/e2e-online/session/sign-out.spec.ts` (new; rows 10, 11): O1 and O2. Server state is read through `irisScript`, and reminders are set and removed through `Test.Schedule.ReminderFixture`.
- `web/e2e-online/support.ts`:
  - fix the `signOutGroup` doc (120 s on the online demo);
  - if L4 needs 16.8's `routeLivePath` hooks, move them here from `reset.spec.ts` rather than copying them;
  - add any helper the two new specs share.
- `web/e2e-online/reset.spec.ts` (shared surface):
  - R6's pre-reset 401 now lands on `?since=…` with no `signedOut`;
  - cases whose page clock passes 600 s with no activity keep the page active (a key press between steps, or a `/state` route that raises `idleSeconds`).
- `web/e2e-online/splash.spec.ts`: S7's paths gain `ended=1`.

**Live units**
- `docker/tests/lib-online.sh` (new; Rule 2, extract): move the online-demo start into it, sourced by both units, with `test-online-demo.sh`'s PASS lines unchanged:
  - the password generation, `redact`, the anchor and the override writer;
  - `logout_all` and `online_signin`.
- `docker/tests/test-online-demo.sh`:
  - source `lib-online.sh`; the header notes the 120 s timeout;
  - any check that reused a jar after more than 120 s idle is fixed so the unit stays green (shared surface).
- `docker/tests/test-online-session.sh` (new; rows 1-live, 2 and 4, Task 0):
  - the start: flag-on start values from `lib-online.sh`; the header lists the checks;
  - row 1;
  - C's and K's setup, with K's poll loop as the script's child (stopped after the browser step and by the EXIT trap);
  - the browser step, `npm --prefix web run e2e:online-session`, with `OCUTALON_E2E_TIMEOUT_MS` from the deadline as `run_e2e` does;
  - rows 2 and 4's checks, then Task 0's (a), (b) and (e) rows, then the group sign-out of every jar.
- `ci/units.sh` (own entries):
  - add `live:online-session` at the end of `install-fresh`'s units (the shortest measured CI job), and to `BROWSER_UNITS`;
  - keep `test-ci-config.sh` and `test-ci-changes.sh` green, updating only expectations this unit adds.

**Acceptance Criteria:**
- Given the online-demo flag set before the Web step, when the step runs, then `/ocutalon`, `/ocutalon/api` and both trace applications get a 120-second CSP timeout and a local install keeps 8 hours; and the page's polling keeps its CSP session alive, a reload keeps it, and nothing signs out on `pagehide`. Rows 1 to 3 and 15 hold.
- Given a signed-in visitor who closes the page, when the CSP timeout passes, then the CSP session (and its trace session) ends while the OcuTalon session's conversation, pairing, reminders, watches, orders and approval requests stay untouched, a reminder fires, a watch runs and an approval can be answered with no CSP session open, the splash says the place was freed, and the same browser resumes the session. Row 4 holds.
- Given the 600-second idle cap (a product setting), when the page has had no key press, click or sent message for that long, then it stops polling, signs the group out and shows the splash's place-freed notice above both cards, and signing in resumes the session; and on the online demo a 401 returns to the same splash and notice, never the local sign-in page or "You were signed out.". Rows 5 to 8 hold.
- Given a page that loaded epoch E, when a poll or snapshot carries another epoch, then the page stops polling, shows nothing of the other session, signs the group out and returns to the splash with no place-freed notice. Rows 9 and 9b hold.
- Given the online demo's account menu, when the visitor chooses Sign out, then the dialog behaves as UX-DR30 says, and confirming ends the session through `SessionOps.End` (pairing unlinked and audited, reminders cancelled through the real `ReminderOps`, watches stopped through the real `WatchOps`, pending requests cancelled through `Approval.Cancel`), expires the resume cookie under the same name and path, ends the CSP session with every application of the sign-in group and shows the splash; the next sign-in starts a fresh session, and another session's rows are untouched. Rows 10 to 14 hold.
- Given the About dialog, when it opens, then its tagline reads "An AI assistant for InterSystems IRIS." and the not-affiliated note is unchanged; `frame.spec.ts` F6 and `ux-strings.test.mjs` pin both (DW-378).

## Spec Change Log

- 2026-10-29, lead spec gate: the `(once)` `shard lane-a` run is split into `--part 1/3` to `3/3` (70 classes; 40 lane-b classes took 587 s in one call, so one call cannot hold the whole shard).

## Review Triage Log

### 2026-10-29 — Review pass
- verdicts: 49 findings — high 0, medium 8, low 34, false 7, maybe-false 0
- findings:
  - `[medium]` `[patch]` BH: a failed Sign out is half-applied; End clears the resume hash after a failed step while the route and the page say the session stays resumable — SessionOps.End ran EndResume after a failed step, so a failed End left the chat unlinked and the cookie dead with a reminder still pending (a live session no cookie reaches). Patched: End clears the hash only when its other four steps succeeded; class doc, Api doc and the two End tests follow; mutation recorded.
  - `[low]` `[reject]` BH: the idle cap and the epoch exit work per tab, while the group sign-out ends the browser's one CSP session — Real only with two OcuTalon tabs of one browser (the demo flow is one tab; the trace pages have no cap); the visitor lands on the splash and signs in to resume. The fix is a cross-tab activity channel, which is more than a direct correction. reopen_if: a second OcuTalon tab shows up in demo sessions.
  - `[low]` `[reject]` BH: End does not stop work already running (a turn in flight can still create a reminder, a watch or a request after Sign out) — The intent lists End's steps and no stored field may be added (Never); stopping in-flight work needs an ended marker on the row. The late rows fire into a session no page reaches until the reset. reopen_if: Story 29.4's load run finds late rows after Sign out.
  - `[low]` `[patch]` BH: row 2 asserts C's CSP session gone at 150 s, while Task 0 (d) measured 152 to 153 s — The check ran at the very edge of the measured delay. Patched: row 2 waits up to 180 s (row 4's bound) for C's session to go, after the 150 s floor, then reads K's /state; the unit run read 152 s.
  - `[medium]` `[patch]` BH: the 'gone' checks of rows 2 and 4 can pass without the sessions ever having existed (empty csp_c, no trace cookie) — csp_exists '' answers 0 and csp_find '' answers none, so a harness fault read as success; trace_info_c was assigned and never used. Patched with a setup check that C holds a main and a trace CSP session; mutation (open_trace does nothing) stops the unit at it.
  - `[low]` `[patch]` BH: the header claim 'Every wait ends by the overall deadline' is false for the reminder, watch and trace_end loops — Patched: each of the three loops stops at the deadline.
  - `[low]` `[reject]` BH: only some of End's failure branches are pinned (EndWatches failing, EndApprovals, EndResume save failure, Carry non-CommandResult) — The not-failure branches that decide ended against failed on a repeat (a request or watch already gone) are pinned by TestEndAgainChangesNothing; the others are error paths that log and count. No realistic failure; more tests only. reopen_if: a failed End is reported in the demo.
  - `[low]` `[patch]` BH: sign-out.spec O1 asserts the length of a constant — expect(SIGN_OUT_SENTENCE.length).toBeGreaterThan(0) cannot fail; the dialog name is pinned by the signOutDialog locator. Patched: the line and the unused import are removed.
  - `[low]` `[reject]` BH: rail.spec open() leaves the waitForResponse promise unawaited if signIn throws — It rejects only after signIn has already failed the case, as report noise; the fix is a guard line on a helper that DW-333 just made reliable. reopen_if: a rail case reports an unhandled rejection.
  - `[medium]` `[patch]` ECH: End still clears ResumeHash when a step fails (SessionOps.cls:248) — Same root cause as the first Blind Hunter finding; patched together (one condition in End).
  - `[low]` `[reject]` ECH: after /session/end answers 500 or 501 the page signs the group out anyway (session-gate.ts) — Specified: 'After any other answer but a 401: the full group sign-out, then the plain splash. The session stays resumable.' With the patched End the session now is resumable, which the splash's notice and the sign-in then use. by-design.
  - `[low]` `[reject]` ECH: the idle cap counts only this document's key and click events while another tab stays active — Same root cause as the second Blind Hunter finding; rejected with the same reason.
  - `[low]` `[reject]` ECH: an epoch change seen in a stale tab runs the group sign-out with the shared cookies and ends the other tab's new session — Specified twice: matrix row 9b ('It signs the group out') and Design Notes 'The page signs out on an epoch change ... That other tab then returns to its own place-freed splash and resumes on sign-in'. by-design.
  - `[low]` `[reject]` ECH: each Carry waits CommandsIn.TIMEOUT (120 s) while the gate waits 120 s for all of End — Needs an owner item that does not answer for two minutes; the bound is the project's one command timeout, and a shared budget is a new mechanism. The gate then answers 500, the session stays resumable, and the repeat finishes the work. reopen_if: a Sign out reaches 500 on a stuck owner item.
  - `[low]` `[reject]` ECH: a Visual Trace tab idle for over 120 s loses its CSP session while the main page polls — The 120 s timeout of both trace applications is AC 1 and AD-25's backstop (the trace pages make no keep-alive request); a sign-in form after two idle minutes is the specified outcome. by-design.
  - `[false]` `[reject]` ECH: a splash left open past 120 s has an expired CSP session, so the sign-in may fail — Measured on the flag-on stack (temporary, reverted): a splash GET, 135 s of waiting, then the sign-in POST answered 303 and the next /state answered 200. The form carries no IRISSessionToken on this stack.
  - `[low]` `[reject]` ECH: the place-freed notice shows beside a refusal when the sign-in page re-renders with the cookie (wrong credentials, busy) — Specified: PLACEFREED shows when the request carries the resume cookie and no ended=1. The cookie means the session is resumable, so 'pick up where you left off' is true. by-design.
  - `[false]` `[reject]` ECH: a 200 answer without an epoch field compares unequal and the page leaves — The API always sends epoch (StateBody and Events set it from the row); a missing field would be a server defect, and leaving the page on it is a loud, safe failure.
  - `[low]` `[reject]` ECH: a stale page can send a chat message before its next poll sees the new epoch, and it lands in the other session — The window is the poll interval (about a second) and the session is the same visitor's own; closing it needs an epoch on every command, an API change outside this story. reopen_if: a message lands in the wrong session.
  - `[low]` `[reject]` ECH: signOut() runs while leave() is already signing out — Needs the dialog's Sign out pressed in the same second as the idle cap or a 401; both end in the splash. A guard line adds nothing a visitor meets.
  - `[medium]` `[patch]` ECH: test-online-session.sh csp_find/csp_exists with an empty value pass vacuously (lines 178, 245, 260) — Same root cause as the Blind Hunter finding on vacuous gone checks; patched together.
  - `[low]` `[patch]` ECH: the reminder and watch wait loops ignore the overall deadline — Same root cause as the Blind Hunter finding on the header claim; patched together.
  - `[low]` `[patch]` ECH: row 2 asserts C gone at 150 s, measured 152 to 153 s — Same root cause as the Blind Hunter finding on row 2; patched together.
  - `[low]` `[reject]` ECH: the production-level stub case (TestStubOwnersAnswerPlainEnglish) was deleted — The spec replaces it (Tasks: TestEndSessionReachesSessionOps) because EndSession was the last stub owner, and says Test.Core.CommandsRouting's probe keeps not_built pinned (it passes). by-design.
  - `[medium]` `[patch]` VG: the snapshot path of the epoch guard (LiveState.fetchSnapshot) has no test; AC 4 says 'a poll or snapshot' — L4 and L5 reach the poll guard first. Patched: L4b (a skipped Seq of the page's own epoch, then a snapshot of another epoch: never shown, group sign-out, ended=1, one snapshot request); mutation recorded.
  - `[medium]` `[patch]` VG: Sign out when POST /session/end fails has no client test — Only the server half was pinned. Patched: O3 (a routed 500: group sign-out as a request, plain address, CSP session gone, cookie kept, same epoch on the next sign-in); mutation recorded.
  - `[low]` `[patch]` VG: the 3 s bound of the group sign-out (SIGN_OUT_LIMIT_MS) is not pinned — An Always clause with no case. Patched: L4c (a sign-out request that is never answered; the page lands on ended=1); mutation recorded. The finding's 'defer' became a fix because the case was cheap beside L4b.
  - `[low]` `[patch]` VG: unit row 4's 'every row of C is as it was' includes a constant CHK|events|0 — The statement printed a literal, so the entry could not fail and the spec's row lists no events count. Patched: the entry is removed from the expectation and the script.
  - `[medium]` `[patch]` VG: the 'session gone' checks pass without proving the sessions existed — Same root cause as the Blind Hunter finding on vacuous gone checks; patched together, and Task 0 (a) and (b) now report 'unmeasured' when the jar held no trace session before the sign-out.
  - `[low]` `[patch]` VG: the pinning tests of AC 6 (F6) and DW-333 (R1) have no observed mutation — Closed in this pass: F6 went red in live sign-in part 1/2 with the old tagline, and R1's delay case (old open() red, new open() green) ran in part 2/2; both lines are in the Mutation record.
  - `[low]` `[patch]` VG, other: sign-out.spec O1 asserts the length of a constant — Same root cause as the Blind Hunter finding on O1; patched together.
  - `[low]` `[reject]` VG, other: the 501 not_built branch of the route is dead code with no test — Specified ('not_built gives 501') and kept as the contract of the route if the owner is withdrawn; Test.Web.SessionEndApi has the three cases of matrix row 14. by-design.
  - `[low]` `[reject]` VG, other: Test.Data.Setting's two seed tests leave the other key's row behind — The leftover rows hold the seeded defaults (600 and 5), TestIdleSetting and TestStateIdleSeconds remove or restore the row they assert on, and the spec forbids changing an existing method of that class. reopen_if: a test asserts the absence of the other key.
  - `[low]` `[reject]` VG, other: the online-demo unit's header claim (no jar or page idle for over 120 s) is a comment, not a check — The unit passed twice (371 s and 392 s, 173 PASS lines each) with the 120 s timeouts; a mechanical check would be a new feature of the unit. reopen_if: an online-demo row goes red on a session that timed out.
  - `[false]` `[reject]` IA: the problem is stated in licence connections and the tests assert CSP session existence — The matrix itself says 'licence counts MEASURED'; the unit prints the licence before and after as MEASURED lines. Nothing in the intent asks for a licence assertion.
  - `[false]` `[reject]` IA: the page wiring (SessionGate, LiveState, Header) has no node test — Specified: the Tasks give node tests to IdleCap, the store and splashAddress, and the wiring to the browser cases L1 to L5 and O1 to O3 on the live stack, where every case ran and its mutation went red.
  - `[low]` `[reject]` IA: a sent chat message counting as activity has no direct case — A message is sent by Enter or a click, which already count; the outbox effect adds nothing a visitor can observe. wontfix-theoretical.
  - `[low]` `[reject]` IA: the cap stopping in the reset's resetting view has no case — The halted effect stops the cap for every stop(); the resetting view shows a screen the page leaves at the reset anyway, and a case needs a 600 s clock run in reset.spec. reopen_if: a page leaves from the resetting view.
  - `[low]` `[patch]` IA: the 3 s limit on the group sign-out has no direct case — Same root cause as the Verification Gap finding on SIGN_OUT_LIMIT_MS; patched together (L4c).
  - `[low]` `[reject]` IA: the 501 not_built branch of the route has no case — Same root cause as the Verification Gap finding on the dead branch; rejected with the same reason.
  - `[medium]` `[patch]` IA: 'never sends a request after a 401' is not observed by L3, whose filter sees only /ocutalon/api/ — The group sign-out goes to /ocutalon/?IRISLogout=end. Patched: L3 records the context's requests and asserts none to IRISLogout or /session/end after the 401; mutation recorded.
  - `[false]` `[reject]` IA: the server tests call Api.EndSession as a class method, so the envelope is not on their path — Specified: Test.Web.SessionEndApi mirrors PairingApi (matrix row 14: 'in process on the warm stack'); the envelope and the real route run in O2 and O3 on the live stack.
  - `[false]` `[reject]` IA: the install step and the route compare the flag differently (Public.Settings.Get = '1' against Setting.Get = 1) — Setting.Get answers a public key from Public.Settings; Api.cls reads the flag the same way in StateBody and four other places, and the Public step writes 0 or 1.
  - `[low]` `[reject]` IA: before the first snapshot the page's online() is false, so a 401 or Sign out would take the local path — Specified ('the loaded snapshot's onlineDemo in the page'); the online demo's server renders the splash for a 401 before the first snapshot, and Design Notes records it. by-design.
  - `[low]` `[reject]` IA: the per-document cap and the per-browser sign-out diverge for two tabs — Same root cause as the Blind Hunter finding on tabs; rejected with the same reason.
  - `[low]` `[reject]` IA: after a failed End the cookie remains, so the splash says 'You were away' to a visitor who pressed Sign out — Follows the specified notice rule (cookie present, no ended=1); the finding is the auditor's own note that this is the contract's text. by-design.
  - `[false]` `[reject]` IA: Task 0's (a)/(b) check passes if either request ends the trace session — Specified: 'If (a) and (b) show that no request ends a trace session, stop'. Both ended it (0 s each); L2 and O2 assert the trace sign-in form for each path.
  - `[low]` `[patch]` IA: F6 and R1 (in live sign-in) were not run by the author, so their mutations are unobserved — Same root cause as the Verification Gap finding on the two mutation lines; closed in this pass.
  - `[low]` `[reject]` IA: test-side changes outside the contract's text (floor-sources, reset.spec, ci/units.sh) — Shared surfaces the spec's Verification names (the keydown allow-list, R6, the CI group); informational, no defect.

## Design Notes

**Architecture decisions:**
- **AD-1:** sign-out is the one REST write besides sign-in, and it submits `SessionOps.End` through `CommandsIn`. `End` reaches `ReminderOps` and `WatchOps` with production messages.
- **AD-4:** what ending an online-demo session does. A CSP session ending (closed page, idle cap, timeout) ends nothing else. The cookie is expired under the same name and path. The trace applications have no session-events class.
- **AD-11:** a pending request is cancelled only through `Approval.Cancel`, and the row stays the truth.
- **AD-12:** the epoch belongs to the snapshot, and each owner publishes its own events (reminder, pairing, check).
- **AD-13:** the 120 s timeout, polling, no sign-out on `pagehide`, the idle cap, the 401 and epoch returns with `?since=`, the group sign-out (`?IRISLogout=end`), and no sessionless calls.
- **AD-17:** the Pairing and Approval audit entries come from their one writers.
- **AD-18:** reminders and checks run without a CSP session.
- **AD-19:** the idle cap is a product setting in `Setting`, and the flag is read through `Public.Settings`.
- **AD-22:** throwaways only, and the CI groups.
- **AD-23:** the Public step runs before the Web step.
- **AD-24:** `PermittedClasses` and the roles are unchanged.
- **AD-25:** the 120 s backstop for trace units.
- **AD-29:** real paths, with Telegram off.
- **AD-33:** each table changes through its owner.
- **AD-3:** the cookie name lives in a public class for the splash.
- No AC contradicts an AD's Rule. The AD-25 tension below is reported, not planned around.

**Decided in-stage:**
- **Real paths.** The sign-out tests use the real `WatchOps` too, because Story 5.1 has merged; the AC's "until Story 5.1 merges" double no longer applies. Story 31.3 then only turns on the Telegram cases (story texts are not edited here).
- **A new live unit, `online-session`.**
  - Why: the `online-demo` unit already takes 364-422 s, and this story's checks would push it past one 10-minute call (Rule 18 (5)). "Split rather than stretch".
  - The specs stay under `web/e2e-online/` (in `session/`), as the epic context asks.
  - The unit joins CI group `install-fresh`, the shortest measured job: about 840 s, against shards' 1877 s.
- **Real timeout, not a shortened one.** The closed-page row uses the real 120 s, overlapped with the browser step, so it also pins the product value. The keep-alive row polls the same endpoint the page polls. The idle cap is fast-forwarded with Playwright's clock at its 600 s default, and its setting read is pinned in process. This satisfies AC 6's "shortened timeout and idle cap" at lower wall time.
- **When the notice shows.** The place-freed notice shows when the splash request carries the resume cookie, because the UX's State Patterns row also covers a page that was closed and opened again later.
  - The cookie expires at sign-out and at the reset, so its presence means the session is resumable. The splash can't read the row (AD-3).
  - `ended=1` suppresses the notice after an epoch change, where "You were away" would be untrue.
- **The page signs out on an epoch change.** Otherwise the shell would serve the browser's other, live session instead of the splash. That other tab then returns to its own place-freed splash and resumes on sign-in.
- **The group sign-out is a GET, then `location.replace`,** never a navigation to `?IRISLogout=end`.
- **The idle key.** `onlineDemo.idleSeconds`, seed 600, written only with the flag on (the 16.3 pattern). A non-positive value falls back to 600.
- **A failed End keeps the session.** It answers 500 with no cookie change and no logout; the page then does the group sign-out, and the session stays resumable. An orphaned live session, whose reminders would keep firing, would be worse.
- **End clears `ResumeHash`.** A lost expiry then can't resume an ended session.
- **Direct messages.** `End` sends its reminder and watch commands straight to their owner items rather than back through `CommandsIn`. They carry the EndSession's origin, which both owners accept.
- **A pending pairing code row is left alone.** That would need a `Pairing.cls` change, and Telegram is off in 0.1.0.
- **A 401 before the first snapshot keeps today's path.** The online demo's server renders the splash for it anyway.
- **The dialog has no heading.** The UX gives none, and a new heading would be new public text.
- **The Web step reads the flag through `Public.Settings`** (the AC), through one helper for the timeout and both seeds.

- **A failed End keeps the resume hash** (review pass, 2026-10-29). `End` clears `ResumeHash` only when its other four steps all succeeded. The Always list says every step runs after a failed one, and the same list says a failed End leaves the session resumable; the hash cleared after a failed End would orphan a session whose reminders still fire, the case this note's "A failed End keeps the session" rules out. So step 5 alone follows the resumable reading, and a repeat of `End` (the visitor presses Sign out again) clears it. Reversible inside this story: one condition in `SessionOps.End` and two assertions.
- **The splash after a failed End.** The cookie is kept, so the plain splash shows the place-freed notice; the notice rule (cookie present, no `ended=1`) stands as specified.
- **Footprint, beyond the lead-approved list.** The implement stage edited five paths that are in neither the approved extensions nor the paths_hint, all under `web/**` (Lane B's files, which Epic 16 keeps) and none claimed by a concurrent epic's footprint: `web/scripts/floor-sources.test.mjs` (its allow-lists name the one document `keydown` listener and the second `dialogs.open` caller), `web/scripts/online-demo-anchor.test.mjs` (the anchor moved to `docker/tests/lib-online.sh`), `web/scripts/reset-schedule.test.mjs` (the node test of `splash-address.ts`), `web/src/app/app.ts` (one line: `inject(SessionGate)`, so that the idle cap's listeners and effects exist before the first snapshot) and `web/e2e/support/clock.ts` (an optional `stepMs` for `runUntil`). `Test/Web/ResetSchedule.cls` and `web/scripts/live-store.test.mjs` are in the paths_hint and the Tasks. The lead reports them under `footprint_extensions:`.

**Rule 2 (extend, don't copy):**
- `Dialogs.open` gains `autoFocus`; `SignOutDialog` follows `AboutDialog`; `IdleCap` follows `ContactWatch`.
- `splashAddress`, `InfoNotice`, `RedirectUrl`, `SeedSettings` and `Common` are extended.
- `End` reuses `Unlink`, `ChannelOf`, `IrisUser`, `Result` and `Failed`, and the route mirrors `Unpair()`.
- The one cookie setter serves both writes, and the cookie name has one definition.
- `lib-online.sh` is extracted from `test-online-demo.sh`, not copied.
- The specs reuse `signInFromSplash`, `signOutGroup`, `resumeCookie`, `sessionRow`, `irisScript`, `Fixture`, `ReminderFixture`, `recordTraffic` and `notBuilt`.
- One copy, with its reason: `Test.Web.SessionEndApi` copies `PairingApi`'s private `Guard` and `Call`.

**Integration ACs:**
- `Web.Api.EndSession` consumes `SessionOps.End` through `CommandsIn`: the 204, the expired cookie, the group sign-out and the ended rows (rows 11, 14).
- The page's `SessionGate` and `IdleCap` consume `/state`'s `idleSeconds` and leave at the cap (row 5).
- `Splash` consumes the resume cookie that `SessionEvents` sets (rows 4, 5, 7).

**Consumes:**
- 10.3: `SessionOps.Unlink`, unchanged.
- 8.4: `ReminderOps` cancel and `ReminderFixture`.
- 5.1: `WatchOps` stop.
- Epic 6 and 7: `Approval.Cancel` and `Answer`.
- 16.3: the cookie, `Session.Epoch`, `CspSessionId` and `Ownership`.
- 16.8: `splashAddress`, `InfoNotice` and `ResetWatch`.
- 16.5: `DemoBusyState.openTrace`.
- 2.x: `Dialogs`, `LiveState` and `ChatOutbox`.

**Consumed-by:**
- 16.9 extends `/state` and the session row.
- 19.5 and 34.2 add drops to `SessionOps.End`.
- 31.1 extends the live client.
- 31.3 turns on the Telegram cases.
- 29.4 measures licence units per visitor.
- 12.x pairs real chats that `End` unlinks.

**Ledger inbox:**
- **DW-378:** addressed (the About task; AC 6). It ships in the first implement pass.
- **DW-290:** addressed (the `Test/Web/Api.cls` doc task).
- **DW-291:** addressed (rows 11 and 12 use the real `ReminderOps` cancel, with no double).
- **DW-333:** addressed (the `rail.spec.ts` `open()` task).
- **DW-285:** addressed in part:
  - every leave the page can see (idle cap, epoch change, Sign out) signs the group out at once, which ends the browser's trace sessions (Task 0 (a) and (b) measure their units);
  - a closed page or trace tab falls to the 120 s timeout on both trace applications (rows 1 and 4).
- **Declined DW-285 (the remainder):** signing out a single trace tab while the OcuTalon page stays open has no mechanism within the ADs as measured.
  - `?IRISLogout=end` ends the whole group (spec-0-3, spec-4-7).
  - Ending only the trace application's session would need an OcuTalon class in the trace applications' `PermittedClasses`, which amends AD-24, or a session-events class on them, which amends AD-4. Either is a veto-window item, and the platform behaviour is unmeasured.
  - It belongs with Story 29.4's measurement (DW-286).

**Footprint extensions:**
- `Core/SessionOps.cls`;
- `Test/Core/SessionOps.cls`, `Test/Core/SessionOpsProduction.cls` and `Test/Core/CommandsInProduction.cls`;
- `web/src/app/about/about-dialog.ts`, `web/e2e/frame/frame.spec.ts` and `web/e2e/rail/rail.spec.ts`;
- `docker/tests/test-online-demo.sh`, and the new `docker/tests/test-online-session.sh` and `docker/tests/lib-online.sh`;
- `docker/tests/test-ci-config.sh` and `test-ci-changes.sh`, expectations only, if needed.

Everything else is in the paths_hint or shared by entry. No contended path is touched.

**For the lead:**
- **AD-25.** Its Rule says "Leaving a trace page must sign its trace session out". This spec meets that for every leave the OcuTalon page can see, and relies on the 120 s backstop for a trace tab closed while the page stays open. Please route the remainder: Story 29.4, or an AD-24/AD-4 amendment, a veto-window item.
- **CI.** `live:online-session` joins `install-fresh`. Expected: about 330-450 s locally, and the job's CI time grows by about 10-15 minutes (inference), still below shards'.
- **Telegram.** A pending pairing code row survives a sign-out. This matters only for Telegram (0.1.1; Stories 31.3 and 12.x).
- **Stale text.** Story 16.4's text still says the `WatchOps` double applies until Story 5.1. Story 31.3's planner should know that the real path is already on.

## Verification

**Targets and variables:**
- Run every command from the worktree root, in the foreground, with `timeout: 600000`, one per call. Never put two test-runner calls in one message.
- Tags:
  - implement `e16s4i` (fresh) and `e16s4iw` (warm);
  - QA `e16s4q` and `e16s4qw`, with stage `qa`;
  - review `e16s4r` and `e16s4rw`, with stage `code-review`.
- Each stage tears down only its own tags. Flag-on checks run only in the units' throwaways, never on `ocutalon-slot-c`.

**Commands:**
- (loop) `npm --prefix web test` -- every node test passes (`idle-cap`, `live-store`, `playwright-projects`, `ux-strings`, `tokens` among them).
- (loop) `npm --prefix web run lint` -- `tsc` passes over `e2e/` and `e2e-online/`.
- (loop) `bash docker/tests/test-web-build.sh` -- the build passes and the tree stays clean.
- (loop) `bash ci/checks.sh` -- every block passes (`ci-config`, `ci-changes`, `boundaries`, `class-rules`, `readme`).
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4iw bash ci/warm.sh up` -- once at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e16s4iw bash ci/iris.sh class <Class>` -- one call per class, each printing `CLASS ... passed` after a `WARM reloaded` line:
  - `OcuTalon.Test.Web.Install`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Web.SessionEndApi`, `OcuTalon.Test.Web.Splash`, `OcuTalon.Test.Web.PublicTexts`, `OcuTalon.Test.Web.SessionEvents`;
  - `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Data.Setting`;
  - `OcuTalon.Test.Core.SessionOps`, `OcuTalon.Test.Core.SessionOpsProduction`, `OcuTalon.Test.Core.CommandsInProduction`, `OcuTalon.Test.Core.CommandsRouting`.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4iw bash ci/warm.sh down` -- at the stage's end, and after a failure.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh build` -- before the first live run and after every change under `web/`.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh live online-session` -- PASS for rows 1, 2 and 4, L1 to L5, O1 and O2, with Task 0's `MEASURED` lines. Record the time; expected 330-450 s inside the 540 s default deadline. If it passes 480 s, tell the lead.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh live online-demo` -- PASS with the 120 s timeout and the idle cap: R6's new landing, S7's `ended`, and every earlier row. Record the time (364-422 s before).
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_LIVE_DEADLINE=900 OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh live sign-in --part 1/2` -- PASS (row 15; `frame.spec` F6's tagline; `rail.spec`'s `open()`).
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_LIVE_DEADLINE=900 OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh live sign-in --part 2/2` -- PASS.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh shard lane-b --part 1/3` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh shard lane-b --part 2/3` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh shard lane-b --part 3/3` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh shard lane-a --part 1/3` -- every class passes (the Install area holds the Web step's neighbours; 70 classes, so three parts, each inside one call).
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh shard lane-a --part 2/3` -- every class passes (the Install area holds the Web step's neighbours; 70 classes, so three parts, each inside one call).
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh shard lane-a --part 3/3` -- every class passes (the Install area holds the Web step's neighbours; 70 classes, so three parts, each inside one call).
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s4i bash ci/iris.sh teardown` -- nothing tagged `e16s4i` is left.
- These units are left to CI: install-*, production, demo-path, floor, cards, answers, and image's other units.

**Shared surfaces:**
- **Applications.** The Web step's `Timeout` per application (`Test.Web.Install`). Every flag-on stack now has 120 s, so `docker/tests/test-online-demo.sh` and `web/e2e-online/` must not reuse a jar or page after more than 120 s without a request: check the busy rows, the probe rows and row 6's resume.
- **The snapshot.** The `/state` shape (`idleSeconds`; key-order assertions in `Test.Web.Api`; `StateSnapshot`).
- **Texts.**
  - The catalog's counts, `Keys` and `Fixtures`; `PublicTexts`' counts;
  - the ux-strings inventory;
  - the About dialog's lines (`frame.spec` F6).
- **The splash.** Its notice now also follows the resume cookie: search `web/e2e-online/` and the units for an assertion of no `#ocu-notice` made with a cookie present.
- **The online demo's 401 landing** (`reset.spec` R6, and any `signedOut=1` online assertion).
- **The idle cap.** It runs in every online page: search `web/e2e-online/` for `clock.` runs past 600 s.
- **Sign-out semantics.** `/session/end` now ends the session on the online demo: search for specs that sign out through it or the menu and then expect a resume.
- **EndSession is no longer a stub.** This affects `Test.Core.SessionOps`, `SessionOpsProduction` and `CommandsInProduction`.
- **Playwright and CI.** The projects (`playwright-projects.test.mjs`) and `ci/units.sh`' groups (`test-ci-config.sh`, `test-ci-changes.sh`).
- **Settings.** The `Setting` row `onlineDemo.idleSeconds`.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19). One per AC: each mutation is applied temporarily, observed red, then reverted byte-identical. A live mutation needs a fresh unit run, with `ci/iris.sh build` first for a web change.

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `Test.Web.Install.TestOnlineDemoTimeout` | `Common` ignores the flag (28800 always) |
| AC 1 | `leave.spec.ts` L1 | `SessionGate` sends `/ocutalon/?IRISLogout=end` on `pagehide` |
| AC 2 | the unit's row 4 | `SessionEvents` gains an `OnTimeout` that submits `EndSession` |
| AC 3 | `leave.spec.ts` L2 | `IdleCap` is touched by every poll answer |
| AC 3 | `leave.spec.ts` L3 | `onSignedOut` keeps `?signedOut=1` on the online demo |
| AC 3 | `Test.Web.Splash.TestPlaceFreedNotice` | `InfoNotice` ignores the cookie |
| AC 3 | `Test.Web.Api.TestStateIdleSeconds` | `StateBody` writes 600 whatever the setting |
| AC 4 | `leave.spec.ts` L4 | `LiveState` reloads and applies an online answer of another epoch |
| AC 5 | `sign-out.spec.ts` O1 | the dialog opens with `autoFocus` `'first-heading'` |
| AC 5 | `sign-out.spec.ts` O2 | `Api.EndSession`'s online branch skips the cookie expiry |
| AC 5 | `Test.Core.SessionOpsProduction.TestEndThroughTheProduction` | `End` skips `Approval.Cancel` |
| AC 5 | `Test.Web.SessionEndApi` | the online branch logs out after a failed End |
| AC 3 | `leave.spec.ts` L3 (no sign-out request after the 401) | `onSignedOut`'s online exit runs the group sign-out after a 401 |
| AC 4 | `leave.spec.ts` L4b | `LiveState.fetchSnapshot` applies a snapshot of another epoch |
| AC 4 | `leave.spec.ts` L4c | `groupSignOut` has no time limit |
| AC 5 | `sign-out.spec.ts` O3 | the online error branch of `signOut` navigates to `?IRISLogout=end` |
| AC 5 | `Test.Core.SessionOps.TestEndUnlinksWithoutNotice` | `End` clears the `ResumeHash` after a failed step |
| AC 6 | `frame.spec.ts` F6 | the old tagline is put back |
| DW-333 | `rail.spec.ts` R1 | a temporary route delays `/state` by 12 s: the old `open()` goes red, the new one stays green |

**Mutation record:**
- Each mutation was applied, observed red and reverted byte-identical (`cmp` against a saved copy; `git diff --stat` the same before and after). The five server mutations ran on the warm stack `e16s4iw` (a production item's mutated class needs the item restarted to load, which the SessionOps case did). The seven browser and live mutations were applied together in one `ci/iris.sh build` and one fresh `live online-session` run on `e16s4i`; each pinning test went red on its own mutation (the combined run also turned L5 red with L4's mutation and row 4 red with row 4's), and the bundle was rebuilt clean after the revert.
- mutation: AC 1, `Test.Web.Install.TestOnlineDemoTimeout`, `Common` ignores the flag (28800 always): red, 4 asserts (`flag on: /ocutalon`, `/ocutalon/api`, the OCUTALON trace application, the OCUORDERS trace application); reverted.
- mutation: AC 1, `leave.spec.ts` L1, `SessionGate` sends `/ocutalon/?IRISLogout=end` on `pagehide`: red (`reload 1: the main page loads its snapshot` failed: the reload landed on the splash); reverted.
- mutation: AC 2, the unit's row 4, `SessionEvents` gains an `OnTimeout` that submits `EndSession`: red (`C's CSP sessions were not both gone within 180 s` (310 s), `every row of C is as it was` 4 of 7 values differ, `Approval.Answer answered 'not_found'`, the watch did not run again, the sign-in gave another epoch); reverted.
- mutation: AC 3, `leave.spec.ts` L2, `IdleCap` touched by every poll answer: red (`page.waitForURL` timed out after 60 s: the page never left); reverted.
- mutation: AC 3, `leave.spec.ts` L3, `onSignedOut` keeps `?signedOut=1` on the online demo: red (`page.waitForURL` for `?since=` timed out); reverted.
- mutation: AC 3, `Test.Web.Splash.TestPlaceFreedNotice`, `InfoNotice` ignores the cookie: red (`TestPlaceFreedNotice` and `TestInfoNotice` failed); reverted.
- mutation: AC 3, `Test.Web.Api.TestStateIdleSeconds`, `StateBody` writes 600 whatever the setting: red (`the row holds 300: 300`); reverted.
- mutation: AC 4, `leave.spec.ts` L4, `LiveState` reloads and applies an online answer of another epoch: red (`page.waitForURL` for `ended=1` timed out; L5 red too); reverted.
- mutation: AC 5, `sign-out.spec.ts` O1, the dialog opens with `autoFocus` `'first-heading'`: red (`Cancel has the focus`); reverted.
- mutation: AC 5, `sign-out.spec.ts` O2, `Api.EndSession`'s online branch skips the cookie expiry: red (`it sets the resume cookie once`); reverted.
- mutation: AC 5, `Test.Core.SessionOpsProduction.TestEndThroughTheProduction`, `End` skips `Approval.Cancel`: red (`A's request 1 is cancelled`, `A's request 2 is cancelled`, `with one Approval entry`, and `TestEndAgainChangesNothing` and `TestEndWithAHeldReminderFails` too); reverted. A first attempt without restarting the SessionOps item stayed green (the production job still ran the old code); that is why the item is restarted.
- mutation: AC 5, `Test.Web.SessionEndApi`, the online branch logs out after a failed End: red (`500 server_error`, `no cookie is set`, `the CSP session is not logged out and does not end`); reverted.
- mutation: AC 6, `frame.spec.ts` F6, the old tagline put back in `about-dialog.ts`: red in `live sign-in --part 1/2` (`F6: the About dialog`, `the seven lines, in order`); the node pin `ux-strings.test.mjs` goes red too (`has an entry for every inventory string`); reverted, then rebuilt.
- mutation: DW-333, `rail.spec.ts` R1, the first `/state` delayed by 12 s (a temporary route): a temporary case with the old `open()` went red (`toHaveAttribute` on `main.main` timed out at 10000 ms), and R1 with the new `open()` and the same delay stayed green (`live sign-in --part 2/2`, 96 passed, 1 failed: the temporary case); reverted (`cmp`, `git status --short` and `git diff --stat` identical).
- Review pass (patches of the 2026-10-29 review), each applied temporarily, observed red, reverted byte-identical (`cmp` against a saved copy; `git status --short` and `git diff --stat` the same before and after):
- mutation: AC 5, `Test.Core.SessionOps.TestEndUnlinksWithoutNotice` (and, by the same assertion on a held reminder, `TestEndWithAHeldReminderFails`), `End` runs `EndResume` after a failed step: red on the warm stack (`the resume hash is kept: a failed End leaves the session resumable`); green again on the same stack after the revert.
- mutation: AC 3, `leave.spec.ts` L3, `leave('unauthorized')` runs the group sign-out: red (`and the page sent no sign-out after it`: one `IRISLogout=end&t=` request); reverted.
- mutation: AC 4, `leave.spec.ts` L4b, the snapshot guard in `LiveState.fetchSnapshot` removed: red (`it never showed the other session`); reverted. L4 and L5 stay green with it, because the poll guard fires first.
- mutation: AC 4, `leave.spec.ts` L4c, `groupSignOut` without its `AbortSignal.timeout`: red (`page.waitForURL` for `ended=1` timed out at 30 s); reverted.
- mutation: AC 5, `sign-out.spec.ts` O3, the online error branch of `signOut` replaced by `location.replace('/ocutalon/?IRISLogout=end')`: red (`at the plain address, not at a sign-out address`); reverted.
- mutation: rows 2 and 4, `docker/tests/test-online-session.sh`, `open_trace` does nothing: red (`FAIL setup: C's CSP sessions could not be named (main ..., trace 'none')`, and Task 0 (c) fails), and the unit stops before rows 2 and 4 wait for sessions that never existed; reverted.
- The four web mutations of L3, L4b, L4c and O3 ran together in one `ci/iris.sh build` and one fresh `live online-session` run (6 passed, 4 failed: exactly those four); the bundle was rebuilt clean after the revert.


**Task 0 results:**
- MEASURED (a): after `GET /ocutalon/?IRISLogout=end&t=<n>` with a jar that opened a Visual Trace page, the jar's trace CSP session was gone at the first check (0 s, inside the 15 s); licence (connections/units) 2/2 before, 1/1 after. The page's group sign-out is that one GET, and `DemoBusyState.openTrace` is unchanged (no trace sign-outs).
- MEASURED (b): the same with `POST /api/v1/session/end` on the online demo: the trace CSP session gone at 0 s; licence 2/2 before, 1/1 after. No trace sign-outs follow a 204.
- MEASURED (c): the jar's trace CSP session is an `/ocutalon/trace/ocutalon/` session (the application's name has the trailing slash) with `AppTimeout` 120.
- MEASURED (d): a closed jar's main and trace CSP sessions were both gone 152 to 153 s after its last request (two runs; the unit polls every 5 s and each check takes 1 to 3 s); licence (connections/units) 2/2 with the trace page open, 1/1 once gone.
- MEASURED (e): the jar holds a `CSPSESSIONID...` cookie at `/ocutalon/` and one at `/ocutalon/trace/ocutalon/`; the `%CSP.Session` row whose `CSPSessionCookie` equals the cookie names each session (`/ocutalon/|120` and `/ocutalon/trace/ocutalon/|120`). The main session is also the Session row's `CspSessionId` (`%CSP.Session.%ExistsId`).
- MEASURED times (final tree): `live online-session` 306 s (10 specs, the browser step 27 s; the first run 282 s with 7 specs, 4:42), `live online-demo` 392 s (173 PASS lines; 364 to 422 s before), `live sign-in` part 1/2 319 s (127 tests) and part 2/2 310 s (96 tests), `shard lane-b` 192, 193 and 417 s (82 classes) and `shard lane-a` 378, 149 and 418 s (70 classes), all on lane C.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** On the online demo the four sign-in-group applications get a 120-second CSP timeout; the page frees its place after the 600-second idle cap (a `Setting` row, `/state`'s `idleSeconds`), on a 401 and on an epoch change, runs the group sign-out as a bounded GET and lands on the splash, which shows the place-freed notice whenever the browser holds the resume cookie (not after `ended=1`); Sign out opens a confirm dialog and, once confirmed, `/session/end` submits `SessionOps.End` (unlink, reminders, watches, approval requests, then the resume hash), expires the cookie and logs the group out. DW-378 (the tagline), DW-290, DW-291 and DW-333 are in. Task 0 measured that a sign-out ends the trace CSP session at once (so the page needs no trace sign-outs), that a closed jar's sessions are gone 152 to 153 s after its last request, and that the trace session has `AppTimeout` 120.

**Files changed.**
- Server: `Install/Step/Web.cls` (timeouts, one flag helper, idle seed), `Data/Setting.cls` (idle key and seed), `Web/Api.cls` (`/state` idleSeconds, online `EndSession`), `Core/SessionOps.cls` (`End`), `Web/SessionEvents.cls` (one cookie setter, cookie name as Shell's), `Web/Public/Shell.cls` (cookie name, `ended` dropped), `Web/Public/Splash.cls` (place-freed notice), `Msg/Catalog/Core.cls` (`splash.placeFreed`).
- Server tests: new `Test/Web/SessionEndApi.cls`; changed `Test/Web/{Install,Api,Splash,PublicTexts,ResetSchedule}.cls`, `Test/Msg/Catalog.cls`, `Test/Data/Setting.cls`, `Test/Core/{SessionOps,SessionOpsProduction,CommandsInProduction}.cls`.
- Web: new `session/idle-cap.ts`, `header/sign-out-dialog.ts`, `header/sign-out-texts.ts`; changed `session/{session-gate,splash-address}.ts`, `live/{live-state,live-store}.ts`, `header/header.ts`, `shared/dialogs.ts`, `api/api-types.ts`, `about/about-dialog.ts`, `app.ts`.
- Web tests and config: new `e2e-online/session/{leave,sign-out}.spec.ts`, `scripts/idle-cap.test.mjs`; changed `e2e-online/{support.ts,reset.spec.ts,splash.spec.ts}`, `e2e/{frame/frame.spec.ts,rail/rail.spec.ts,support/clock.ts}`, `scripts/{ux-strings,live-store,reset-schedule,floor-sources,online-demo-anchor,playwright-projects}.test.mjs`, `playwright.config.ts`, `package.json`.
- Live units: new `docker/tests/lib-online.sh` (extracted from `test-online-demo.sh`) and `docker/tests/test-online-session.sh`; changed `docker/tests/test-online-demo.sh` and `ci/units.sh` (`live:online-session` in `install-fresh` and `BROWSER_UNITS`).

**Review.** One pass, four layers: 49 findings (medium 8, low 34, false 7). 19 patched (8 medium, 11 low), 30 rejected with a recorded reason, none deferred (`deferred:` stays empty). The patches:
- `SessionOps.End` clears `ResumeHash` only after a clean End (a failed End stays resumable, as the route and page already assume); class doc, Api doc and the two End tests follow.
- New cases L4b (the snapshot path of the epoch guard), L4c (the 3 s bound of the group sign-out), O3 (a failed `/session/end`); L3 now watches every request after the 401; O1's vacuous line is gone.
- `test-online-session.sh`: a setup check that C holds a main and a trace CSP session, row 2 waits up to 180 s for C to go, the constant `events` entry is gone, the three waits honour the deadline, and Task 0 reports `unmeasured` when the jar had no trace session.
- The F6 and R1 mutations the author had left for the lead were run and recorded.

**Rejected findings** (reasons are in the Review Triage Log): two OcuTalon tabs of one browser sharing one group sign-out (BH2/ECH3/IA: low, reopen_if a second tab shows up in demo sessions); End not stopping work already in flight; End failure branches beyond the pinned ones; a trace tab idle over 120 s (AD-25's backstop); the splash after a failed End and beside a refusal (the specified notice rule); the group sign-out after a failed `/session/end` and after an epoch change in a stale tab (specified); the 501 branch with no case; the cap in the resetting view and the outbox touch without cases; the commands' 120 s waits against the gate's; a stale page's chat message in the poll window; the double Sign out/leave race; Setting-test leftovers; the demo unit's comment; rail.spec's unawaited promise. Seven were false, among them the splash left open past 120 s (measured: the POST after 135 s answered 303 and `/state` 200).

**Footprint.** Five paths beyond the lead-approved extensions, all `web/**` (Lane B's files, kept by Epic 16) and none in a concurrent epic's footprint: `web/scripts/floor-sources.test.mjs`, `web/scripts/online-demo-anchor.test.mjs`, `web/scripts/reset-schedule.test.mjs`, `web/src/app/app.ts` (one line) and `web/e2e/support/clock.ts`. No contended path and nothing under the spec's Never-edit list was touched.

**Follow-up review recommended: true.** The risk to look at: 8 mediums were patched in one pass, among them the change of `End`'s semantics on failure (the hash is kept) which the page flow only sees through a faked 500 (O3) and in-process tests, never through a real failing End in the browser, and four new timing-based browser cases (L4b, L4c, O3, L3's wider watch) that ran green once on one stack.

**Verification.** Final tree, lane C, tags `e16s4i` and `e16s4iw` (both torn down; nothing tagged is left):
- `npm --prefix web test` 1078 pass; `npm --prefix web run lint`, `bash docker/tests/test-web-build.sh` and `bash ci/checks.sh` pass.
- Warm stack: the 12 listed classes pass on the patched tree (also on the pre-patch tree).
- `live online-session` 306 s, 10 specs and 16 PASS lines with the `MEASURED` lines; `live online-demo` 392 s, 173 PASS, 0 FAIL (both under the 480 s mark).
- `live sign-in --part 1/2` (127 tests, 319 s) and `--part 2/2` (96 tests, 310 s) pass; `shard lane-b` 82 classes in three parts and `shard lane-a` 70 classes in three parts pass; `ci/iris.sh teardown` left nothing.
- Matrix audit: rows 1 to 15 are each covered by a test that ran and passed in these runs (row 1 by `TestOnlineDemoTimeout` and the unit's row 1, 2 and 4 by the unit, 3/5/7/9/9b by L1/L2/L3/L4/L5, 6 by `TestStateIdleSeconds`/`TestIdleSetting`, 8 by `TestPlaceFreedNotice`, 10/11 by O1/O2, 12 to 14 by the End and route tests, 15 by `live sign-in`).
- Mutations: one demonstrated per pinning test, recorded in `## Verification` (the AC 6 and DW-333 ones were run in this pass).

**Residual risks.** The multi-tab case above; End's in-flight work; the 120 s trace-tab timeout is the AD-25 backstop, not a per-tab sign-out (reported to the lead in `For the lead`); `live:online-session` joins `install-fresh` (about 5 minutes locally, the group's CI time grows by about that, as the spec estimated).
