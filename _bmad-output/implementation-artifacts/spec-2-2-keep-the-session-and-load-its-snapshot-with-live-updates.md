---
title: 'Story 2.2: Keep the session and load its snapshot with live updates'
type: 'feature'
created: '2026-10-21'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Story 2.1 the page loads `/state` once and never again, and the parts behind it are interim:
- the snapshot's chat and rail are empty arrays;
- `/state` and `/events` find the caller's session by user name (`Session.ForUser($Username)`, DW-15), outside the ownership API that AD-4 requires;
- nothing creates the session row at sign-in;
- Sign out is a plain `?IRISLogout=end` link, and `POST /session/end` answers 501;
- a 401 leaves the page stuck;
- `ApiClient` can't send a state-changing call (DW-14);
- there is no polling, no skeleton and no load error, so Story 2.1's server button, notice and announcer have never run in a browser (DW-57);
- live events are never purged.

**Approach:** Build the session and the snapshot on the server, and the live path in the page.

- **Server.**
  - `OcuTalon.Web.SessionEvents` attaches the user's durable session to the CSP session at sign-in.
  - `OcuTalon.Data.Ownership` resolves the caller's `SessionRef` from the CSP session, and makes every owner- and scope-checked read the snapshot needs.
  - `Session.Recipients` is implemented.
  - `/state` fills its chat and rail through Ownership, and gains `telegram` and `status`.
  - `POST /session/end` signs out.
  - `Live.Event.Purge` deletes events older than 24 hours.
- **Page.**
  - An `ApiClient` interceptor adds the browser envelope and stops all calls after a 401.
  - `LiveState` polls `/events` and applies events idempotently through a framework-free store.
  - Skeletons, then "Couldn't load your session." with **Retry**.
  - Sign out goes through the API.

## Boundaries & Constraints

**Always:**
- **Session (AD-4).** No endpoint accepts a `SessionRef` from the client. The session comes only from the CSP session, through `Ownership.SessionRef`. On a local install each IRIS user has one durable `Session` row, and signing out ends only the CSP session and its sign-in group.
- **Ownership (AD-4).**
  - Every REST read and command handler goes through `OcuTalon.Data.Ownership`.
  - A session sees its own records. On a local install (`onlineDemo` off) it also sees `instance` incidents, and their approval requests, for the productions it watches.
  - An incident is visible only once `NoticedAt` is set.
  - An `eval`-owned record is never visible.
  - A record the session can't see is indistinguishable from a missing one (404 `not_found`).
- **SQL.** Ownership's queries run as the signed-in user, who holds no SQL grant (AD-13). They are prepared without the privilege check in exactly one private method, `Ownership.Rows`. It is the only new entry in `ALLOW_UNCHECKED`, and every query enforces ownership in its own `WHERE` clause. See `## Clarification Needed`, item 1.
- **Live events (AD-12).**
  - The page reads `/state` once per load, then polls `/events?after=&afterInstance=` with one cursor per stream, waiting 1 s after each answer, so polls come 1 to 2 s apart.
  - Each event's full view replaces the entity with the same key, or is added. An event at or below the cursor is ignored.
  - A `seq` that skips, or a changed epoch, reloads the snapshot.
  - Nothing in the live path moves keyboard focus.
  - `/state` reads the stream cursors before it reads any section.
- **Strings.** Fixed strings match the UX exactly: "Couldn't load your session.", "Retry", "You were signed out. Sign in again to continue." and "Couldn't reach OcuTalon. Try again. Nothing was changed." The sign-in page reuses `ApiBase.MESSAGESIGNEDOUT` and adds no copy of its own.
- **Code (Rule 14).** Source stays ASCII. Comments state the contract, never the history. The Angular code keeps Story 2.1's style: standalone components, OnPush, signals, and only the tokens `tokens.css` declares.
- **Lanes (AD-29, AD-33).** Lane A's tables and classes are read-only: `Incident`, `BackgroundCheck`, `Bridge.Data.*` and `Live.Payload.Check`/`.Incident`. No table gains a property and no storage block changes. Cross-lane signatures stay as `Test.Contract.Ac` pins them.

**Never:**
- Never choose a session by `$Username` after sign-in. `$Username` is read only by `Ownership.Attach`'s find-or-create and by `SessionRef`'s check that the recorded row belongs to the signed-in user.
- Never put a role check that returns an error in `OnLogin`. An error there neither logs out nor shows the sign-in page (Story 0.3 probe).
- Never add a test-only route, global or hook to the product. E2E tests reach IRIS through `docker exec` from the test side.
- Never grant SQL privileges, change roles, or edit a Lane A path:
  - `src/bridge/**`;
  - `Install/**` other than `Install/Step/Web.cls`;
  - `docs/**`;
  - `docker/merge.cpf`.
- Never add an npm dependency, a CDN, or a test runner besides Playwright and `node --test`.
- **Out of scope, each owned by a later story:**
  - rendering the chat (2.5), the decisions (2.6), notice cards (2.7), the rail rows, counts and empty states (2.8) and banners (2.10, 2.11);
  - computing the status conditions and `StatusMonitor` (2.10);
  - the reconnecting banners (2.11);
  - announcer batching and focus replacement (2.12);
  - a turn's text and reply text, and where a notice card is kept (2.4 and 2.7; see `## Clarification Needed`, item 2);
  - the Telegram bot state (10.3);
  - the online demo's resume, splash, epoch return, idle cap and `SessionOps.End` (Epic 16);
  - the WebSocket (31.1);
  - the purge task's registration (30.2).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First sign-in | A user with `OcuTalonUser` and no `Session` row signs in at `/ocutalon` | `OnLogin` creates the one row (`Ref`, `TraceRef`, `Epoch`) and records its `Ref` in the CSP session. `/state`'s `epoch` is the row's | `OnLogin` always returns OK. A failure is written to the console log without the user name, and the lazy attach (next row) covers it |
| Later sign-in | The same user, in another browser or after Sign out | The same row and epoch | — |
| No role | A user without `OcuTalonUser` signs in | No `Session` row is created. The shell's no-role page is shown, as today | — |
| CSP session without a ref | Signed in through the group at a trace application first, then opens `/ocutalon/` | The page loads. `Ownership.SessionRef` attaches the user's durable session on the first API call (local install) | — |
| One account, two OcuTalon sessions (the online-demo case, simulated) | Two CSP sessions bound to two `Session` rows of one IRIS user, one event on each stream | Each `/events` holds only its own session's events, and each `/state` its own epoch (DW-15) | — |
| Sign out | Press **Sign out** | `POST /api/v1/session/end` with `Content-Type: application/json` and `X-OcuTalon-Request: 1` → 204. The CSP session and the group end, and the page shows the sign-in page. Then the API answers 401 and a trace application asks for a password | Any failure other than a 401 sends the page to `/ocutalon/?IRISLogout=end` |
| No envelope | `POST /session/end` without the JSON content type, or without the header | 403 `not_json` or `no_request_header`, and the session stays signed in (DW-14) | — |
| A 401 on any call | The CSP session ended elsewhere | The page makes no further API call and goes to `/ocutalon/?signedOut=1` plus its hash. The sign-in page shows "You were signed out. Sign in again to continue." | A later wrong password shows the credentials error instead |
| Unseen Ref | `POST /approvals/:ref/answer` or `/incidents/:ref/dismiss` with any of: another session's ref, an unnoticed incident, an `eval` record, an unwatched `instance` incident, a missing ref | 404 `{"error": {"code": "not_found", "message"}}`. A visible ref answers 501 `not_built` | The envelope check still comes first |
| Instance incident, local | A noticed `instance` incident on a production that two sessions watch | It is in both sessions' `chat`, and its pending request is in both `rail.approvals`. `Recipients("instance", ref)` lists both | With `onlineDemo` on: visible to neither, and `Recipients` is "" |
| Snapshot sections | Fixture rows for one session | See the snapshot shape in Design Notes | — |
| Event in order | Page loaded, an event with `seq` = cursor + 1 | Applied, the cursor advances, and `main[data-session-seq]` shows it within 2 s. No `/state` reload and no navigation; focus is unchanged | — |
| Duplicate | `seq` ≤ cursor | Ignored | — |
| Skip | `seq` > cursor + 1 on either stream, or a poll's `epoch` differs from the snapshot's | The snapshot is reloaded once and its cursors replace the old ones. `data-snapshot` stays `loaded` | — |
| Poll fails (not 401) | A 5xx or network error | The next poll comes after the same delay; nothing else happens | Banners are Story 2.11's |
| Cold load | `/state` has not answered | Static skeletons: two rows in each rail section and three entries in `main`, `aria-hidden`, with `aria-busy="true"` on the rail and on `main` | — |
| No data by 10 s | `/state` has not answered in 10 s | The skeletons give way to "Couldn't load your session." and a secondary **Retry** server button at the top of `main`, announced once. `data-snapshot="failed"` | A late answer still loads and removes the error |
| Fast failure | `/state` answers with an error | The load error shows at once | — |
| Retry answered | Press **Retry**, and `/state` answers | While busy: spinner, `aria-busy`/`aria-disabled` true, label kept, never `disabled` (DW-57). Then the content | A failed answer restores the button and announces "Couldn't load your session." again |
| Retry, no answer | No answer in 10 s | The button restores, and the warning notice "Couldn't reach OcuTalon. Try again. Nothing was changed." appears under it, announced once (DW-57) | A late answer clears the notice |
| Purge | Events 25 h old and 1 h old, any `daysToKeep` | The older rows are deleted and the newer kept. `^OcuTalonP.LiveEventC` is untouched, so the next `Publish` continues the stream's `seq` | — |
| Restart | Fixture rows; the IRIS container is killed and started | The snapshot's `epoch`, `chat` and `rail` are identical | — |

</intent-contract>

## Code Map

**Server, Lane B (edit)**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`
  - `State` :94 and `Events` :103 call `Session.ForUser($Username)`, the DW-15 interim. Switch both to `Ownership.SessionRef`.
  - `StateBody` :134-156: `streams` comes before `chat` and `rail`; keep that order.
  - The routes :42-55: `/v1/session/end`, `/v1/approvals/:ref/answer` and `/v1/incidents/:ref/dismiss` → `NotBuilt` today.
  - Reuse `Fail`, `ModelName` :160 and `#MESSAGENOTFOUND`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: stubs `TurnCost` and `RunCost` (Story 2.6's; its "Story 2.2" on `RunCost` is stale).
- `src/ocutalon/cls/OcuTalon/Data/Session.cls`
  - `ForUser` :35 is the find-or-create, with an allow-listed unchecked prepare.
  - `Recipients` :78 is a stub that returns "" (pinned at `Test/Contract/Ac.cls:324`).
  - `IrisUserIndex` is not unique.
- `src/ocutalon/cls/OcuTalon/Live/Event.cls`: `Since` :34. Ts is UTC ISO, so string order is time order. Add `Purge`. The counter global is `^OcuTalonP.LiveEventC` (`Publish.cls:4`).
- `src/ocutalon/cls/OcuTalon/Live/Payload/{ChatMessage,Reminder,Approval,Decision,Status}.cls`: Lane B payloads, properties pinned by `Test.Live.Payloads`, so add methods only. Sibling builder: `Payload/Incident.cls:65` `FromRow` (Lane A).
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls`
  - `Common` :143-158 sets `Timeout=28800`, `GroupById="OcuTalon"` and `SessionScope=2` on all four applications.
  - `/ocutalon` :91-98; `/ocutalon/api` :100-107; `TraceApp` :128-140; `/ocutalon/public` :112-121.
  - No `EventClass` is set and there is no `Purge` override.
- `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls`: `Show` :92, `Message(state, code)` :105-117 (`norole`, the credentials error), `OnLoginPage` :121-162 (the `#ocu-error` paragraph).
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`
  - `HasRole()` :113-116 (a public class method).
  - Its no-role path :54-62 does `%session.Logout(1)` with `EndSession=1`, which Story 0.3 measured ends the whole group.
- `src/ocutalon/cls/OcuTalon/Web/Public/ApiBase.cls:14`: `MESSAGESIGNEDOUT` is the catalog key `signIn.signedOut`'s copy, compared by `Test.Web.PublicTexts`.

**Lane A (read only)**
- `Data/Incident.cls`
  - `OwnerRef` is a session Ref, `instance` or `eval`. There is no separate scope field.
  - `Namespace`, `Production`, `NoticedAt`.
  - `Count` has the SQL name `FailureCount`.
- `Data/BackgroundCheck.cls`: `SessionRef`; `Kind` "production"; `Namespace`, `Production`, `LastRunHeaderId`; the index `NamespaceProductionIndex`.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls`: `OwnerRef`, `IncidentRef`, `State` (`pending` is the only pending state), `DryRun` as JSON, `RaisedAt`.
- `.../Bridge/Data/Decision.cls`: `OwnerRef`, `Kind` (`decide` = the attention decision, triage), `Summary`, `Model`, `TraceSessionId`, `RecordedAt`, `CostUSD`.
- `Data/Turn.cls` (Lane B): `SessionRef`, `State`, `Channel`, `FromGuide`, `CreatedAt`. It has no text columns.
- `Data/Reminder.cls` (Lane B): `State` is pending, fired or cancelled.
- `Data/Pairing.cls` (Lane B): `SessionRef`, `DisplayName`.
- `Bridge.Budget.State` and `Bridge.Keys.Status` are stubs (Stories 1.4 and 1.6). `Channel.Telegram.In.Included()` reads its test seam.

**Tests that pin the old shapes**
- `Test/Web/Api.cls`
  - `TestStateBody` :61: the exact key list and empty sections.
  - `TestRoutes` :279: 12 routes with their `Call`s.
  - Helpers: `Call`/`PreDispatch` :381-423 build `%session = %CSP.Session.%New("ZzApiTest",0)`; `PublishReminders` :482; `Clean` :494.
- `Test/Web/Install.cls`: `Expected` :356-403 is checked both ways by `TestDefinitions` :41, so a new `EventClass` key goes into every app's entry.
- `docker/tests/lib-live.sh`: :482 is the expected property string and :521/:819 the key lists of the live application check.
- `Test/Core/Commands.cls:100-106` `TestStubs`: `Recipients` returns "" for unknown refs, and that stays true.
- `Test/Data/Tables.cls` pins every table's properties and indexes; this story changes none.
- `web/e2e/api/api.spec.ts`
  - `UNBUILT` :72 holds `session/end` and the two `:ref` routes.
  - The `/state` key order :136.
  - Rows 13 and 14 count the README session's 2 seeded events and the instance stream's 1, so new specs never publish on either.
- `web/e2e/sign-in/shell.spec.ts`: row 11 :169-187 is Sign out, as `menuitem` "Sign out", then a 401 and the trace app's password prompt. It stays green unchanged. Row 8 is `main`'s contents after the load.
- `web/e2e/frame/frame.spec.ts`
  - F1 :67-94: the exact h2 and h3 lists, so add no heading.
  - The failed snapshot :353: `data-snapshot` "failed" right after a 500.
  - F9: `/state` exactly once.
- `web/e2e/demo-path/01-page.spec.ts:13-27` `@floor`: `/state` once. Its title is pinned by `playwright-projects.test.mjs:92-94`.
- `docker/tests/test-class-rules.sh:28-30` `ALLOW_UNCHECKED`: an entry that matches no call fails as stale.

**Web**
- `web/src/app/api/api-client.ts`: `state()` :15 and `events(after, afterInstance)` :20.
- `web/src/app/api/api-types.ts`: `LiveItem` :4, `LiveEnvelope` :7-11, `StateSnapshot` :14-30, `EventsResponse` :33.
- `web/src/app/app.config.ts:15`: `provideHttpClient()` with no interceptors.
- `web/src/app/live/live-state.ts`: `load()` runs once; `status` is loading, loaded or failed.
- `web/src/app/live/payloads.ts`: generated; it holds `LiveEventType` (16 types) and `LivePayloads`.
- `web/src/app/main-page/main-page.ts`: the rail `h3`s and `main[data-snapshot]`. The component style budget is 4 kB.
- `web/src/app/header/header.ts:83`: the Sign out `<a href="/ocutalon/?IRISLogout=end">`; doc comment :20-21.
- `web/src/app/shared/server-button.ts`
  - `action: () => Observable | Promise`, of which only the first value counts.
  - `BUSY_NOTICE` :10. The notice comes after `BUSY_TIMEOUT_MS` (10 s), with an `announce`.
- `web/src/app/shared/busy-state.ts`: the framework-free pattern to copy for `live-store.ts`.
- `web/src/app/shared/announcer.ts`: CDK `LiveAnnouncer`, polite.
- `web/src/styles/tokens.css:231-232`: `--skeleton-background` and `--skeleton-radius` (dark at :650 and :873).
- `web/src/styles/controls.css`: the global stylesheet for shared looks.

**Throwaway plumbing**
- `docker/tests/test-sign-in.sh`
  - `cid=$(dc ps -q iris)` :41 is not exported.
  - `create_fixture_user` :60-67.
  - The seeding of the README session :94-110.
  - The e2e env :122-134 and the password redaction in `show_log`.
- `docker/tests/lib-live.sh`: `iris_script` :303-315 (`iris session IRIS -U <ns>`, `CHK|` lines).
- `docker/tests/test-production-restart.sh`: row 20 kills IRIS with `docker kill -s KILL` and starts it again.
- `ci/units.sh:15-21`: the `lane-b` shard is the areas `Contract Core Data Demo Live Msg Web`, so new `Test.Data`, `Test.Web` and `Test.Live` classes need no registration.

**IRIS reference**
- `irislib/%CSP/SessionEvents.cls:55-57`: `OnLogin`.
- `irislib/%CSP/Session.cls`: `Logout(force)` :1163, `Data` :646, `EventClass` :113-125.
- `irissys/Security/Applications.cls:135`: `EventClass` (MAXLEN 64).
- Spike `spikes/batch2/s16/src/resume/OcuSpike.S16.Resume.Events.cls`, outside this repository: `OnStartSession` and `OnLogin` ran as the signed-in user, with the application's roles, at the sign-in request (its server log).

## Tasks & Acceptance

**Execution:**

- **Task 0** (implement stage; record each result under `## Verification`).
  - After `SessionEvents` and the `EventClass` key land, run `ci/iris.sh live sign-in` once on tag `e2s22i`. Record two results:
    - the sign-in page still renders and the README sign-in still works (the event class loads at the sign-in request, as S16 measured: inference until this run);
    - whether session.spec S4 (attach at sign-in) and S5 (a group sign-in from a trace application) pass.
  - If the sign-in page or the sign-in breaks because the event class can't load before sign-in, HALT with an `intent gap` naming AD-4 (the class's package). Never move the class on your own.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: rewrite the class comment (AD-4: the one ownership API), keep `TurnCost` and `RunCost` (Story 2.6), and add:
  - `SessionRef(Output sc) As %String`
    - Returns the `Ref` recorded in `%session.Data("OcuTalon.SessionRef")` when that `Session` row exists and its `IrisUser` matches `$Username` (case-insensitive).
    - Otherwise it calls `Attach()` and returns the new value.
    - With no `%session`, it returns "" and an error.
    - This is the one resolution method that Story 16.3 extends (DW-16).
  - `Attach(irisUser = {$Username}) As %Status`: `Session.ForUser(irisUser)`, then records the row's `Ref` in the CSP session.
  - `Rows(class, sql, args...) As %ListOfObjects [ Private ]`: the one unchecked prepare (`%Prepare(sql, 0)`). It selects `ID` and opens each row.
  - The reads, each returning rows in the stated order:
    - `Turns(sessionRef)`: by `CreatedAt`, then ID.
    - `Reminders(sessionRef)`: `State` pending, by `DueAt`.
    - `Checks(sessionRef)`: by ID.
    - `Decisions(sessionRef, max = 20)`: `Kind` decide, newest `RecordedAt` first.
    - `Incidents(sessionRef)`: noticed only, own plus watched `instance` ones when local, by `NoticedAt`.
    - `Approvals(sessionRef)`: pending, own plus those of visible `instance` incidents, by `RaisedAt`.
    - `Pairing(sessionRef)`: the row, or "".
  - The single-record finds, each returning "" when the record isn't visible:
    - `Incident(ref, sessionRef)`;
    - `Approval(ref, sessionRef)`.
  - `Watchers(namespace, production) As %List`: the distinct `SessionRef`s with a `production` check on that production, empty when `onlineDemo` is on.
  - Why: AD-4's one API, and the only unchecked SQL Lane B adds.
- `docker/tests/test-class-rules.sh:28-29`: append `OcuTalon.Data.Ownership:Rows` to `ALLOW_UNCHECKED`, and change nothing else. The lead amends AD-13's sentence (`## Clarification Needed`, item 1).
- `src/ocutalon/cls/OcuTalon/Data/Session.cls`: implement `Recipients(ownerRef, incidentRef)`:
  - `eval` or "" → "";
  - a session `Ref` with a row → `$ListBuild(ownerRef)`;
  - `instance` with an `instance` incident → `Ownership.Watchers` of its production;
  - any other case → "".

  Update the class comment.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls` (new): extends `%CSP.SessionEvents`.
  - `OnLogin()`: when `##class(OcuTalon.Web.Public.Shell).HasRole()`, it calls `Ownership.Attach()`.
  - It always quits OK, and catches and logs any failure through `%SYS.System.WriteToConsoleLog`, with no user name.
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls`
  - Add `EventClass` to every application's definition: `OcuTalon.Web.SessionEvents` for `/ocutalon`, "" for the other three.
  - Add `Purge(daysToKeep)`, which quits `##class(OcuTalon.Live.Event).Purge(daysToKeep)`. This is Lane B's live-event retention, declared in Lane B's one area class in this footprint (Design Notes).
- `src/ocutalon/cls/OcuTalon/Live/Event.cls`: `Purge(daysToKeep As %Integer) As %Status`.
  - It deletes the rows whose `Ts` is older than 24 hours before now, whatever `daysToKeep` is (AD-27), with a checked prepare (it runs as the task).
  - It never touches `^OcuTalonP.LiveEventC`.
  - Fix the class comment.
- `src/ocutalon/cls/OcuTalon/Live/Payload/`: add these class methods, mapping every row property that exists; a field with no source stays empty.
  - `ChatMessage.FromRow(row As OcuTalon.Data.Turn)`: `ref`, `channel`, `fromGuide`, `state`, `createdAt`.
  - `Reminder.FromRow(row As OcuTalon.Data.Reminder)`.
  - `Approval.FromRow(row As OcuTalon.Bridge.Data.ApprovalRequest)`: `dryRun` is parsed into `Part.DryRun`.
  - `Decision.FromRow(row As OcuTalon.Bridge.Data.Decision)`: `itemSummary` ← `Summary`, `model` ← the display name, `traceHeaderId` ← `TraceSessionId`, `traceNamespace` ← `$Namespace`.
  - `Decision.ModelName(id)`: the one display-name table, moved here from `Web.Api.ModelName`, which now delegates to it so its tests stay.
  - `Status.Active(sessionRef) As %DynamicArray`: the active conditions as `Status` payloads. It returns `[]`; Story 2.10 computes them (Design Notes).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`
  - `State` and `Events` resolve the caller through `Ownership.SessionRef`, and a resolution error is a 500 (DW-15). `StateBody` keeps its signature.
  - `StateBody` fills the sections through Ownership (the snapshot shape in Design Notes) and appends `telegram` and `status` after `models`.
  - Add a private `CheckView(row)`, which builds a `Live.Payload.Check`.
  - Routes:
    - `/v1/session/end` → `EndSession()`: `%session.Logout(1)`, `EndSession = 1`, 204 with no body.
    - `/v1/approvals/:ref/answer` → `AnswerApproval(ref)`.
    - `/v1/incidents/:ref/dismiss` → `DismissIncident(ref)`.
    - Both `:ref` routes answer 404 `not_found` when the Ownership find returns "", and otherwise 501 `not_built`.
  - Update the class comment (it still says "the session is the signed-in user's row").
- `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls`: when there is no error code and `%request.Get("signedOut") = 1`, `Message` returns `##class(OcuTalon.Web.Public.ApiBase).#MESSAGESIGNEDOUT`.
  - Thread the state through `OnLoginPage`. It shows in the existing `#ocu-error` paragraph.
  - The credentials and no-role messages take precedence.
  - The splash (online demo) ignores it.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` (new, no `Test` methods): the one helper for fixture rows.
  - It has `Session(user)`, `Turn`, `Reminder`, `Check`, `Incident`, `Approval`, `Decision` and `Pairing` (each returns the row's `Ref`), plus `Clean()`.
  - It records every row it creates under `^OcuTalonTest("Fixture")`, and `Clean()` deletes exactly those rows.
  - `Test.Data.Ownership`, `Test.Data.Session`, `Test.Web.Api`, session.spec and the restart unit use it.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` (new): these tests, each with its own fixture sessions and rows:
  - `TestAttachReuses`: two CSP sessions, one row, one `Ref`.
  - `TestSessionRefFromTheCspSession`: the recorded `Ref` wins; a missing or foreign one is re-attached. A row the test did not create is left alone.
  - `TestOwnRecordsOnly`.
  - `TestInstanceScope`: a watched production is visible, an unwatched one is not, and nothing is visible with `onlineDemo` on.
  - `TestOnlyNoticedIncidents`: one noticed incident, one not.
  - `TestEvalNeverVisible`.
  - `TestFinds`: `Incident` and `Approval` return "" for every unseen case in the matrix.
  - `TestOrders`: the order and the filters of each read.

  Save and restore `onlineDemo` as `Test.Web.Api` does.
- `src/ocutalon/cls/OcuTalon/Test/Data/Session.cls`: `TestRecipients`. It covers:
  - a session-owned record;
  - an `instance` incident watched by two sessions;
  - an unwatched one;
  - `eval`;
  - an unknown `Ref`;
  - `onlineDemo` on.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`
  - `TestStateBody`: the key list gains `telegram` and `status`.
  - New `TestStateSections`: fixture rows give each section's content, order and filters, and the cursors are read before the sections.
  - New `TestPollsResolveTheCspSession` (DW-15): two `Session` rows of one user name and two `%CSP.Session` objects. `Events()` and `State()` through `Call` hold only their own session's events and epoch.
  - New `TestEndSession`: logged out, `EndSession` 1, 204.
  - New `TestUnseenRefIs404`: 404 and its body for each unseen case, 501 for a visible ref.
  - `TestRoutes`: the three new `Call`s.
- `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls`
  - `Expected`: `EventClass` per application.
  - New `TestPurgeDeclaration`: `Install.Step.Web.Purge(90)` deletes an aged fixture event of its own stream.
- `src/ocutalon/cls/OcuTalon/Test/Web/SignIn.cls`: `TestSignedOutNotice`. `signedOut=1` with no code gives the text in `#ocu-error`, and with code 822 the credentials text.
- `src/ocutalon/cls/OcuTalon/Test/Live/Publish.cls`: `TestPurge`.
  - On its own streams, it ages some rows' `Ts` to 25 h ago and calls `Live.Event.Purge(90)`.
  - The aged rows are gone, the fresh ones kept, the counter and `LastSeq` unchanged, and the next `Publish` gets the next `seq`.
  - If a class rule forbids writing `Live.Event` in a test, give `Purge` an optional trailing `now` argument instead, and record the reason.
- `docker/tests/lib-live.sh` :482, :521 and :819: add `EventClass` to the expected string and to both key lists.
- `docker/tests/test-production-restart.sh`: before row 20's kill, and again after its restart, an `iris_script` call prints `Web.Api.StateBody`'s `epoch`, `chat` and `rail` for a session `Test.Data.Fixture` seeded with one of each:
  - a turn;
  - a check;
  - a pending reminder;
  - a pending approval.

  PASS needs the two outputs to be equal and to contain the four fixture refs. Clean afterwards.
- `docker/tests/test-sign-in.sh`
  - Create three more fixture users with `OcuTalonUser`: `OCUTALON_LIVE_USER`, `OCUTALON_SESSION_USER` (also `OcuTalonTraceViewer`) and `OCUTALON_SIGNIN_USER`, which nothing signs in before session.spec S4.
  - Pass their names and passwords to the e2e run, with `OCUTALON_E2E_IRIS_CONTAINER="$cid"`.
  - Redact the new passwords in `show_log`.
- `web/src/app/api/api-types.ts`: `StateSnapshot` gains `telegram: TelegramState` and `status: StatusPayload[]`. Add `TelegramState { included; state: 'off' | 'on' | 'rejected'; botUserName; paired; displayName; pausedUntil }`.
- `web/src/app/api/api-client.ts`: add `endSession(): Observable<void>`, a POST of `{}`.
- `web/src/app/api/envelope.interceptor.ts` (new), registered with `provideHttpClient(withInterceptors([...]))` in `app.config.ts`. For requests under `/ocutalon/api/`:
  - once `SessionGate.signedOut()` is set, it sends nothing and errors at once;
  - on POST, PUT, PATCH and DELETE it sets `Content-Type: application/json` and `X-OcuTalon-Request: 1`;
  - on a 401 it calls `SessionGate.onSignedOut()` and rethrows.

  Addresses DW-14.
- `web/src/app/session/session-gate.ts` (new, root):
  - `signedOut` is a signal.
  - `onSignedOut()` sets it once, stops `LiveState`, and calls `location.replace('/ocutalon/?signedOut=1' + location.hash)`.
  - `signOut()` stops `LiveState` and calls `endSession()`. On success it calls `location.replace('/ocutalon/')`; on any error but a 401 it calls `location.replace('/ocutalon/?IRISLogout=end')`.
- `web/src/app/live/live-store.ts` (new): framework-free, like `busy-state.ts`, with erasable syntax and `import type` only.
  - `fromSnapshot(snapshot)` builds the store.
  - `applyEvents(store, response)` returns `{ store, reload }`. Per stream, an event with `seq` ≤ cursor is ignored, `seq` = cursor + 1 is applied and advances the cursor, and anything above, or a changed epoch, returns `reload: true` without applying.
  - It exports `COLLECTIONS`, the type → collection and key table in Design Notes.
- `web/src/app/live/live-state.ts`
  - Keep `snapshot` and `status`. Add `store`, `sessionSeq` and `instanceSeq` signals, plus `retry()` (an Observable that settles when `/state` answers) and `stop()`.
  - With no answer by `LOAD_TIMEOUT_MS = 10_000`, `status` becomes `failed` and the announcer says "Couldn't load your session." once. An error answer does the same at once, and a 401 is left to the gate. A late answer still loads.
  - After `loaded` it polls with `POLL_DELAY_MS = 1000` after each answer, one poll in flight at a time. A `reload` result fetches the snapshot again while keeping `loaded`.
  - When a Retry answer is a failure, it announces "Couldn't load your session." again.
- `web/src/app/main-page/main-page.ts`
  - While loading: skeletons. Each rail section gets two rows (title, detail and meta blocks), and `main` gets three entries (one right-aligned bubble and two text blocks). All are `aria-hidden`, and `aria-busy="true"` is set on the rail and on `main`.
  - On `failed`: the `div.load-error` at the top of `main`, holding `<p>Couldn't load your session.</p>` and `<app-server-button variant="secondary" [action]="retry">Retry</app-server-button>`, and no skeletons.
  - `main` carries `data-session-seq` and `data-instance-seq` once loaded.
  - Add no heading.
- `web/src/styles/controls.css`: the `.skeleton` block. Background `var(--skeleton-background)`, radius `var(--skeleton-radius)`, no animation or transition. Later stories reuse it.
- `web/src/app/header/header.ts`: Sign out becomes `<button type="button" class="item" cdkMenuItem (cdkMenuItemTriggered)="signOut()">Sign out</button>`, calling `SessionGate.signOut()`. Fix the doc comment.
- `web/scripts/live-store.test.mjs` (new): imports `live-store.ts` with type stripping, like `busy-state.test.mjs`. It covers:
  - the snapshot intake;
  - an in-order apply;
  - duplicates;
  - replacing by key in place, and a new key appended (decisions prepended);
  - a skip on either stream, and a changed epoch;
  - the two streams' independent cursors;
  - every type of `payloads.ts`'s `LiveEventType` union (read from that file) has a `COLLECTIONS` entry.
- `web/e2e/support/iris.ts` (new): `irisScript(script)` runs `docker exec -i $OCUTALON_E2E_IRIS_CONTAINER iris session IRIS -U OCUTALON` and returns its `CHK|` lines.
  - It reads the env only when called, so listing needs no env. It mirrors `lib-live.sh`'s `iris_script`.
  - `publishReminder(user)` publishes one fixture `reminder` on that user's own session stream and returns its `seq`.
- `web/e2e/live/live.spec.ts` (new; signs in as `OCUTALON_LIVE_USER`):
  - **L1:** `/state` is requested once. Each poll carries the current cursors, and three consecutive poll intervals each lie within [1000, 2000] ms.
  - **L2:** a window marker is set, then `publishReminder` runs. `main[data-session-seq]` reaches the new `seq` within 2000 ms of the helper's return. The marker survives, there is no second `/state`, and the measured time is printed.
  - **L3:** a `page.route` adds a fabricated event at cursor + 2 to one real poll answer, and `/state` is requested a second time. A fabricated duplicate (`seq` = cursor) causes neither a reload nor a cursor change.
  - **L4:** with focus on the theme button, after L2's apply, `document.activeElement` is unchanged.
  - **L5:** `/state` held: the skeletons sit in every rail section and in `main`, with the skeleton background and `animation-name` none, `aria-hidden`, and `aria-busy` on both regions.
  - **L6:** `page.clock`, then 10 s with `/state` held: the load error and **Retry**; the announcer region says "Couldn't load your session.".
    - Retry with `/state` held: label kept, spinner, `aria-busy`/`aria-disabled` "true", no `disabled`.
    - 10 s more: the button restores, and the notice text sits under the button, announced once (a page-side `MutationObserver` counts it).
    - Then releasing `/state` loads the page and the error leaves.
  - **L7:** a fast 500: the error at once. A Retry that answers 500 restores the button and announces the error again.
- `web/e2e/session/session.spec.ts` (new; `OCUTALON_SESSION_USER`, except S4):
  - **S1:** the user is seeded through `irisScript` with a fixture turn, check and pending reminder.
    - Sign out sends `POST /session/end` with both envelope headers and gets 204.
    - The sign-in page shows, `/state` answers 401, and the trace application asks for a password.
    - After signing in again, `/state`'s `epoch`, `chat` and `rail` equal those before.
  - **S2:** `POST /session/end` without the JSON type gets 403 `not_json`, without the header 403 `no_request_header`, and then `/state` still answers 200. `APIRequestContext` sends no `Origin` by itself, so every POST a spec makes sets the page's own `Origin` explicitly.
  - **S3:** with the page loaded, `context.request` ends the session with the full envelope (JSON type, header and `Origin`). Then:
    - the page shows the sign-in page with "You were signed out. Sign in again to continue.";
    - after the first 401, no request to `/ocutalon/api/` is made;
    - a wrong password then shows the credentials error.
  - **S4** (`OCUTALON_SIGNIN_USER`): a form POST sign-in with no API call, then `irisScript` finds the user's `Session` row. A second sign-in finds the same `Ref`.
  - **S5:** sign in at `/ocutalon/trace/ocutalon/` first, then open `/ocutalon/`: the page loads with no sign-in form, and `/state` answers 200 for the user.
- `web/e2e/api/api.spec.ts`
  - Remove `session/end` and the `:ref` routes from `UNBUILT`.
  - Add rows: `/state`'s new key order; a random ref on both `:ref` routes answers 404 `not_found` with the error shape.
- `web/e2e/demo-path/01-page.spec.ts`: inside the existing `@floor` test, with no change to its title or tag, add "within 3 s of the load, an `/events` poll carrying the snapshot's two cursors answers 200".

**Acceptance Criteria:**
- **Session at sign-in.**
  - Given a local or IPM install, when an IRIS user with the user role signs in for the first time, then `OcuTalon.Web.SessionEvents` creates that user's one `Session` row with `SessionRef`, `TraceRef` and epoch. Every later sign-in by that user reuses it (S4, `TestAttachReuses`).
  - Given a sign-in carried by the sign-in group, when the page calls the API, then the same durable session is attached (S5).
- **Sign out.** Given the signed-in page, when I choose Sign out, then:
  - `POST /api/v1/session/end`, carrying the browser envelope, ends the CSP session together with every application of the OcuTalon sign-in group;
  - the page shows the sign-in page;
  - after signing in again, the same conversation and rail are there (S1, shell.spec row 11).
- **Lifetime and 401.**
  - Given the four applications, when the install runs, then each keeps `Timeout` 28800 in sign-in group `OcuTalon` (`TestDefinitions` and the live check). That gives at least 8 hours of idle time and the silent sign-in of a timed-out trace application while `/ocutalon` is alive, as S7 measured.
  - Given any API call that answers 401, when the page receives it, then it makes no further API call and shows the sign-in page with "You were signed out. Sign in again to continue." (S3).
- **Ownership.** Given `OcuTalon.Data.Ownership`, when a REST read or command handler looks up a record, then:
  - it uses the `SessionRef` from the CSP session, never one from the client and never the user name;
  - two OcuTalon sessions of one account each poll only their own events (DW-15, `TestPollsResolveTheCspSession`);
  - a `Ref` the session can't see answers 404 with the error shape (`TestUnseenRefIs404`, api.spec).
- **Recipients.** Given `Session.Recipients(ownerRef, incidentRef)`, when it resolves a session-owned record, an `instance` incident or an `eval` record, then it returns the owner, every watcher (on a local install) or none (`TestRecipients`).
- **Snapshot.** Given a signed-in session, when the page calls `GET /api/v1/state`, then the body holds every section in the snapshot shape, read through Ownership (`TestStateSections`). After IRIS is killed and started, `epoch`, `chat` and `rail` are identical (the restart unit).
- **Live path.** Given the loaded page, when `LiveState` polls `/events` every 1 to 2 s with its two cursors, then:
  - every event type is applied idempotently by key, and focus never moves;
  - a `seq` skip reloads the snapshot (`live-store.test.mjs`, L1, L3, L4);
  - an event published after the load is on the page without a reload, within 2 s of being sent, in CI against the mock on every run (L2, in the chromium suite of `live sign-in`, the `browser` group);
  - the demo-path floor sees a poll answered.
- **Purge.** Given live events older and newer than 24 hours, when `OcuTalon.Live.Event.Purge(daysToKeep)` runs, directly or through the Web area's `Purge` declaration that the purge task will call (Story 30.2), then only the older ones are deleted and every stream keeps its counter (`TestPurge`, `TestPurgeDeclaration`).
- **Loading and Retry.** Given a returning session, when the page loads, then:
  - the rail and the chat show static skeletons until data arrives;
  - after 10 seconds without data they give way to "Couldn't load your session." with **Retry** (L5, L6, L7);
  - **Retry** is the first browser test of Story 2.1's server button, inline notice and announcer: busy keeps the label, shows the spinner and sets `aria-busy`/`aria-disabled` without `disabled`; with no answer by 10 s it restores and shows "Couldn't reach OcuTalon. Try again. Nothing was changed." under it, announced once (DW-57, L6).
- **Envelope.** Given `ApiClient`, when it makes a state-changing call, then the interceptor adds `Content-Type: application/json` and `X-OcuTalon-Request: 1`, and without them the server answers 403 `not_json` or `no_request_header` (DW-14, S1, S2).

## Spec Change Log

- 2026-10-22, spec validation (lead):
  - The purge tests run only on throwaways. `Test.Live.Publish` and `Test.Web.Install` left the slot-B loop list and run through `ci/iris.sh class` (Rule 21: `Live.Event.Purge` deletes rows the test did not create).
  - Clarification item 2 is ruled (veto, inbox U-14): turn and reply text go to Story 2.4 (DW-61), the notice-card store to Story 2.7 (DW-62), each with an acceptance bullet in `epics.md`. This story builds the merge, the turn and incident entries, and the builder 2.4 extends, as planned.
  - No split (decide): the intent is one path, from session to snapshot to live updates, and its tests cross that path (S1 to S5, L1 to L7). Story 2.1 was a comparable size and converged in one pass.
  - Clarification item 1 (AD-13's allow-list) goes to the orchestrator, because an AD amendment is a cross-epic matter (U14). The spec is buildable as planned, and its ruling is recorded here before the implement stage runs.

## Review Triage Log

## Design Notes

**Governing ADs and conventions (Rule 6).**
- AD-3: the sign-in page reuses `ApiBase`'s copy, in the same public package.
- AD-4:
  - one durable session per user (locally);
  - the attach in `/ocutalon`'s `SessionEvents.OnLogin`;
  - Ownership as the one API, its scope rules and the 404;
  - `Recipients`;
  - the one resolution method that Story 16.3 extends.
- AD-5: storage is unchanged; the restart check.
- AD-12: the snapshot and its cursors, polling with one cursor per stream, the idempotent full-view apply, the reload on a skip, and the counter the purge keeps.
- AD-13:
  - the browser envelope;
  - the 401 `signed_out`;
  - an 8-hour lifetime with silent trace re-sign-in;
  - `%session.Logout(1)` with `EndSession`;
  - the unchecked-prepare allow-list (item 1 below).
- AD-19: `onlineDemo` through `Setting.Get`.
- AD-22: tests and throwaways.
- AD-23 and AD-27: an area's `Purge(daysToKeep)`; live events are kept 24 hours whatever the number.
- AD-29 and AD-33: lanes, the area rule, Lane A read-only, one publisher per type (this story publishes nothing).
- Conventions rows: REST, Live events, Identifiers, Times, Settings, Angular, Tests.

**The snapshot shape** (`StateBody`, keys in order):
- `version`, `instanceZone`, `epoch`, `streams` (read first), then:
- `chat`: `LiveItem[]`, the session's turns (`chat.message` from `ChatMessage.FromRow`, by `CreatedAt`) and its visible noticed incidents (`incident` from `Incident.FromRow`, by `NoticedAt`), merged by time, then turn before incident, then ID;
- `rail`:
  - `approvals`: pending ones, by `RaisedAt`;
  - `checks`: every one of the session's background checks, by ID, through `CheckView`;
  - `reminders`: pending ones, by `DueAt`;
  - `decisions`: the 20 newest `decide` decisions, newest first;
- `user`, `onlineDemo`, `demoMode`, `models` (Story 2.1);
- `telegram`: `{included: Included(), state: "off", botUserName: "", paired, displayName, pausedUntil: ""}`, with `paired` and `displayName` from the session's `Pairing` row;
- `status`: `Status.Active(sessionRef)`.

**The live store's collections** (`COLLECTIONS`; the key is `type:ref` in `chat`):

| Event type | Collection | Key |
| --- | --- | --- |
| `chat.message`, `notification`, `incident` | `chat` (ordered; replaced in place, new ones appended) | `ref` |
| `decision` | `decisions` (new ones first) | `ref` |
| `approval`, `check`, `reminder`, `phone`, `mailbox`, `watch.progress` | one map each | `ref` |
| `status` | `status` | `condition` |
| `turn.step` | `turnSteps` | `decisionRef` |
| `pairing` | `telegram` (merges `paired`, `displayName`) | — |
| `guide.state`, `reset`, `breakfeed.progress` | one value each, replaced | — |

Views (Stories 2.5 to 2.10) filter by state, for example a fired reminder leaving the list. The store keeps the latest full view.

**Decided in-stage** (small and reversible, within the intent):
1. **Where "on the page" is observed.** No region renders an event until Stories 2.5, 2.7, 2.8 and 2.10. So the 2-second check reads the cursor the page has applied (`main[data-session-seq]`), the same pattern as Story 2.1's `data-snapshot`. The store's replace-by-key semantics are pinned in node. Those stories each check their own entity on screen.
2. **DW-15's "two sign-ins with one account".** On a local install AD-4 gives an account one session, so two real sign-ins share it by design. The two-visitor case (the online demo, Story 16.3) is simulated at the API with two CSP sessions bound to two rows of one user name. That is what proves the resolution comes from the CSP session and not from the user name.
3. **A lazy attach backs up `OnLogin`.** Whether `OnLogin` fires for a sign-in that the group carries is unmeasured. `SessionRef` attaches the durable session on a local install when the CSP session holds no valid `Ref`, so neither path can loop on 401. Story 16.3 replaces this branch on the online demo.
4. **The no-role user gets no session row.** `OnLogin` attaches only with the role, and never returns an error.
5. **Sign out locally.** The API logs out with `Logout(1)` and `EndSession` (Story 0.3's measured pair). The online demo's `SessionOps.End` and its dialog are Epic 16's, so until then the online demo ends only the CSP session. If the call fails, the page falls back to IRIS's own `?IRISLogout=end`, so a user can always sign out.
6. **The signed-out notice** comes through `?signedOut=1`, because the sign-in page is server-rendered (AD-13) and the CSP session is already gone. It is a fixed text and harmless if linked to. The page's hash is kept (DW-4).
7. **The load error** is shown at once on an error answer and at 10 s with no answer. It is one block at the top of `main` (the rail drops its skeletons), so it is announced once. A failed Retry announces it again, which settles 2.1's review note "reopen_if: Story 2.2's Retry shows no feedback on a fast failure".
8. **Skeletons** always show while loading, because the page can't know a fresh session before `/state` answers. A fresh session's empty chat panel is Story 2.5's.
9. **`status`** carries `Status.Active(sessionRef)`, empty here. Story 2.10's criterion "`/state` computes the same conditions on read" fills it, together with `StatusMonitor`. `Active` sits outside Core, because Web may not call Core (dependency rule), so both callers can share it. **`telegram`** reads `included` and the pairing. The bot state, bot name and pause have no writer until Story 10.3 builds `StatusMark.RecordTelegram`, and it adds the reader with the mark names it fixes.
10. **The live-event purge is declared in `Install.Step.Web`.** The registry discovers only `OcuTalon.Install.Step.<Area>` classes, and a new `Install.Step.Live` sits under `Install/**`, which is contended for this epic. Reversal: move the one method to `Install.Step.Live` when that path is cleared (AD-29's area rule makes it Lane B's).
11. **The two `:ref` command routes check ownership before their 501.** They are the only command handlers that look up a record today, so AD-4's 404 is testable at the REST surface. Their stories replace the 501.
12. **`Decision.ModelName`** holds the display-name table, so `Decision.FromRow` (and Story 2.6's `BridgeSink`) never call into `OcuTalon.Web`. `Web.Api.ModelName` delegates to it.
13. **Fixture users.** The new specs sign in as their own fixture users and never publish on the README session or the instance stream, so api.spec's counts hold in either order.
14. **The restart check reads `StateBody` through `iris_script`**, because the restart unit publishes no host port. `StateBody` is the body `GET /state` writes, and S1 pins the HTTP path to the same sections.

**Integration ACs (Rule 1).**
- `Ownership`: `Web.Api.State`/`Events` read through it, and the page shows the user's own snapshot and events (S1, S5, L2).
- `SessionEvents`: the first `/state` after a sign-in answers the session row created at sign-in (S4, then `epoch` in S1).
- `LiveState` polling and the `live-store`: `MainPage` reflects the applied cursor and the load state (L1 to L7).
- `envelope.interceptor` and `SessionGate`: Sign out's POST (S1) and the 401 (S3).
- `Payload.*.FromRow` and `CheckView`: `StateBody` (`TestStateSections`, the restart unit).
- `Live.Event.Purge`: `Install.Step.Web.Purge`, through the registry (`TestPurgeDeclaration`).
- `Session.Recipients`: no consumer in this story. The first consumer will be Story 2.8 (`BridgeSink`'s `approval` events), and Lane A's `IncidentManager` (Epic 5). `Ownership.Watchers`, which it shares, is consumed here.
- `Status.Active`: no consumer beyond `StateBody` in this story. Story 2.10 (`StatusMonitor`) will be the first other one.

**Consumed-by:**
- 2.4: `ChatMessage.FromRow`, extended with the turn's texts.
- 2.5: `LiveState.store.chat`.
- 2.6: `Decision.FromRow`, `ModelName` and the Ownership reads for `BridgeSink`.
- 2.7: the chat merge, for notice cards.
- 2.8: the rail collections, `Recipients`, `Approval.FromRow`, `telegram.included`.
- 2.10: `Status.Active` and `status`.
- 2.11: the poll loop's error path.
- 2.12: focus rules over the store.
- 10.3: the `telegram` block.
- 16.3: `Ownership.SessionRef`'s demo branch (DW-16).
- 30.2: the Web area's `Purge`.
- 31.1: the store, shared by the WebSocket.

**Consumes:**
- `Session.ForUser` and `Live.Publish`/`Event.Since` (Story 0.5);
- `Shell.HasRole` and the sign-in group (Story 0.3);
- Story 2.1's `LiveState`, `ApiClient`, `server-button`, `inline-notice`, `announcer` and `controls.css`;
- `Payload.Incident.FromRow` (Lane A, Epic 0);
- `Setting.Get`;
- `Channel.Telegram.In.Included()`.

Its Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- The `FromRow` builders extend the sibling `Payload.Incident.FromRow`.
- `Attach` reuses `Session.ForUser`.
- `Recipients` reuses `Ownership.Watchers`.
- `live-store.ts` follows `busy-state.ts`'s framework-free pattern.
- The sign-in notice reuses `ApiBase.MESSAGESIGNEDOUT`.
- `Test.Data.Fixture` replaces the per-class inline fixture code that new tests would otherwise copy.
- **Copies, with their reasons:**
  - `Web.Api.CheckView` copies what a `Check.FromRow` would do, because `Live.Payload.Check` is Lane A's (publisher `Checks`). The lead routes it at harvest to the story that builds the `check` publisher (Epic 5), which adds `Check.FromRow` and switches `StateBody` to it.
  - `web/e2e/support/iris.ts` mirrors `lib-live.sh`'s `iris_script` in TypeScript, because a spec can't call a shell function while it runs.

**Ledger (Rule 17).**
- DW-14 is addressed by the interceptor task, the "No envelope" and "Sign out" rows, S1, S2 and the Envelope AC.
- DW-15 is addressed by the Ownership and `Web.Api` tasks, the "One account, two OcuTalon sessions" row, `TestPollsResolveTheCspSession` and the Ownership AC.
- DW-57 is addressed by the Retry rows, L6 and the Loading and Retry AC.
- No entry is declined.

## Clarification Needed

Two questions for the lead's spec validation. The plan follows each recommendation, so the spec is buildable as written, and a reversal re-plans only the named parts.

1. **AD-13's allow-list (veto: amending an AD).**
   - Ownership's reads run as the signed-in user, who holds no SQL grant, so they need prepares without the privilege check.
   - AD-13 currently allows those "only in `Session.ForUser` and `Live.Event.Since`".
   - Granting SQL to `OcuTalonUser` would contradict AD-13. Embedded SQL is unscanned by `test-class-rules.sh`, so using it would evade the rule's intent.
   - **Recommendation:** the light path (Rule 20). Amend the sentence to "only in `Session.ForUser`, `Live.Event.Since` and Ownership's one private query method, `Ownership.Rows`, keyed by class and method". The implement stage then adds the one `ALLOW_UNCHECKED` line.
2. **Conversation content with no store yet (veto: moving part of an AC to not-yet-planned stories of this release).** `Data.Turn` has no message text, reply text or `clientId`, and no table holds a delivered notice card's text (`Delivery` keeps only references). So the snapshot can't carry either today.
   - **Recommendation:** route two `DW-n:` bullets.
     - **To Story 2.4:** it appends `Text`, `ReplyText`, `ClientId` and the trace target to `Turn`, which its recap already needs, and extends `ChatMessage.FromRow`.
     - **To Story 2.7:** it keeps each web notice card where the snapshot can read it, and adds `notification` entries to `StateBody`'s chat merge.
   - This story builds the merge, the turn and incident entries, and the builder that 2.4 extends.
   - The demo-path floor and the release gates depend on neither.

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`, with one `iris_execute_tests` call per message. Every throwaway command is `OCUTALON_RUN_TAG=e2s22i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`, with one piece per call and `timeout: 600000`. End with `teardown` on the same tag.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, ports 1991 and 52791.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`) as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (loop) `iris_execute_tests`, one class per message. Expected: all pass.
  - `OcuTalon.Test.Data.Ownership`
  - `OcuTalon.Test.Data.Session`
  - `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Web.SignIn`
  - `OcuTalon.Test.Web.PublicTexts`
  - `OcuTalon.Test.Live.Payloads`
  - `OcuTalon.Test.Core.Commands`
  - `OcuTalon.Test.Data.Tables`
  - `OcuTalon.Test.Contract.Ac`
- (loop) `npm --prefix web run lint`, then `npm --prefix web test`. Expected: exit 0, with `live-store` among the tests.
- (loop) `npm --prefix web run build`. Expected: exit 0, with no budget warning and `payloads --check` unchanged.
- (loop) `npm --prefix web run e2e -- --list`. Expected: `live/` and `session/` are listed under chromium, and no `demo-path/` line appears.
- (loop) `npm --prefix web run e2e:demo-path -- --list`. Expected: unchanged, 13 tests.
- (loop) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh`, one call each. Expected: exit 0.
- (loop) throwaway: `build`, then `live sign-in`. Expected: every chromium spec passes, L1 to L7 and S1 to S5 included, and L2 prints its measured time. Task 0 is recorded from the first run.
- (loop) throwaway: `live demo-path`. Expected: `STEP 1 page: partly skipped, 1 passed, 4 skipped`, with the floor test's poll assertion green.
- (loop) throwaway: `live production-restart`. Expected: all checks pass, the snapshot comparison included.
- (loop) throwaway: `class OcuTalon.Test.Data.Ownership`. Expected: `CLASS OcuTalon.Test.Data.Ownership passed` on the installed package.
- (loop) throwaway, one call each: `class OcuTalon.Test.Live.Publish`, then `class OcuTalon.Test.Web.Install`. Expected: both pass. **Never run these two classes on slot B** (no `iris_execute_tests` for them): they hold `TestPurge` and `TestPurgeDeclaration`, and `Live.Event.Purge` deletes every live event older than 24 hours, including rows the test did not create, which Rule 21 treats as destructive.
- (loop) throwaway: `teardown`.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) throwaway, one call each: `shard lane-b`, `shard lane-a` (`Test.Install.Registry` now reaches the Web area's `Purge`), `live install-start`, `live install-upgrade` (the `EventClass` key) and `live bundle-folder`, then `teardown`. Expected: every class and unit passes.

**Planned mutations (Rule 19).** For each, the implement stage applies the mutation, records `mutation: … → …` here, and restores a byte-identical tree.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Session at sign-in | `OnLogin` skips `Attach` | S4 |
| Reuse | `Attach` creates a new row instead of calling `ForUser` | `TestAttachReuses`; S1's equal epoch |
| Sign out | `EndSession()` answers 204 without logging out | S1 (`/state` still 200) |
| Lifetime | `Timeout` 900 for `/ocutalon/api` in the definitions | `TestDefinitions` |
| 401 | the interceptor keeps calling after a 401 | S3, "no API call after the 401" |
| Signed-out text | `Login` ignores `signedOut` | `TestSignedOutNotice`; S3 |
| Ownership (DW-15) | `State` and `Events` use `ForUser($Username)` | `TestPollsResolveTheCspSession` |
| 404 | `Ownership.Incident` skips the owner check | `TestFinds`; api.spec's 404 row |
| Noticed only | the `NoticedAt` filter is dropped | `TestOnlyNoticedIncidents` |
| Recipients | the `instance` branch returns every session | `TestRecipients` |
| Snapshot | reminders not filtered to pending | `TestStateSections` |
| Restart | `rail.reminders` is served from an `^IRIS.Temp` copy filled at seed time | the restart unit |
| Live apply, 2 s | `LiveState` drops every event | L2 |
| Idempotent replace | apply appends instead of replacing | `live-store.test.mjs` |
| Skip | a skip is applied, not reloaded | L3; `live-store.test.mjs` |
| Focus | `LiveState` focuses `main` after an apply | L4 |
| Poll pace | `POLL_DELAY_MS = 3000` | L1 |
| Purge | `Purge` keeps `daysToKeep` days instead of 24 hours | `TestPurge` |
| Purge declaration | `Install.Step.Web` without `Purge` | `TestPurgeDeclaration` |
| Skeleton | a shimmer `animation` on `.skeleton` | L5 |
| Load error | `LOAD_TIMEOUT_MS = 30_000` | L6 |
| Retry busy (DW-57) | `server-button` sets `disabled` while busy | L6 |
| Retry notice (DW-57) | the notice is not announced | L6 |
| Envelope (DW-14) | the interceptor omits `X-OcuTalon-Request` | S1's header check |
| Floor | `LiveState` never polls | the `01-page` floor test |

**Shared surfaces:**
- the `/state` key set and sections: `Test.Web.Api` `TestStateBody`, `api.spec.ts` :136, `api-types.ts`;
- the API route table: `TestRoutes`, api.spec's `UNBUILT`;
- the web application property table: `Test.Web.Install` `Expected` (both ways), `lib-live.sh` :482, :521 and :819;
- `ALLOW_UNCHECKED`;
- the README session's and the instance stream's event counts (api.spec rows 13 and 14; untouched by design);
- the fixture users and env of `test-sign-in.sh`;
- the account menu's Sign out item (shell.spec row 11, frame F5);
- `main`'s contents (shell.spec row 8, F1's heading lists);
- the chromium spec list;
- the `@floor` test's body;
- `Registry.Purge`'s areas (`Test.Install.Registry` `TestPurge`).

Every test added or changed passes on a fresh environment, in either order. Each Playwright test runs in its own browser context with its own fixture user, and the `%UnitTest` classes create and clean their own fixture rows and save and restore `onlineDemo`.

**Manual checks:** none beyond the commands. Firefox, WebKit and the accessibility scan are Story 2.12's.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned and halted after planning, as dispatched. Two veto questions for the lead's spec validation are under `## Clarification Needed`: the AD-13 allow-list amendment, and the turn texts and notice cards routed to Stories 2.4 and 2.7. The plan follows each recommendation.
