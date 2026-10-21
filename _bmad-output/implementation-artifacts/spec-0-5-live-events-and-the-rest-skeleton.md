---
title: 'Story 0.5: Live events and the REST skeleton'
type: 'feature'
created: '2026-10-19'
status: 'done'
baseline_revision: '0e2fcb3c7034ec38f2dcf9f287ab177a7e803882'
baseline_commit: '0e2fcb3c7034ec38f2dcf9f287ab177a7e803882'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      ApiClient has no support for the browser envelope: a non-GET call (a body-less DELETE included) needs Content-Type: application/json and X-OcuTalon-Request: 1, and Angular sends neither by default.
    evidence: |-
      The server refuses a state-changing call without both (403 not_json, 403 no_request_header); api.spec.ts sets the headers by hand. ApiClient has no POST or DELETE yet, so nothing is broken in this story; the first story that adds one (2.2's live-event service and the POST routes) must add an interceptor or helper.
    location: >-
      web/src/app/api/api-client.ts, web/src/app/app.config.ts
    severity: low
---

<intent-contract>

## Intent

**Problem:** The page has no snapshot, no live events and no REST routes yet. `OcuTalon.Web.Api` has an empty `UrlMap`, no event store or publisher exists, and only the decision payload exists. So no Lane B story can load a page or poll for updates, and no Lane A story can publish an incident. Two more gaps: the unauthenticated `/ocutalon/public/status` that AD-13 promises doesn't exist, and on the non-Health image the web bundle sits in `csp/ocutalon/`, which the namespace's default application `/csp/ocutalon` serves without sign-in (DW-5).

**Approach:**
- **Live events.** Add `Live.Event`, `Live.Publish` with the spine's event table, one `Live.Payload.<Type>` per event type, and TypeScript interfaces generated from those classes.
- **REST.** Fill `Api` with every release-1 route: a real `/state` and `/events`, the role and browser-envelope checks, and 501 for the routes that aren't built. A minimal typed client lets the page load its snapshot.
- **Public status.** Add `/ocutalon/public` and its status class.
- **DW-5.** Move the bundle to `csp/ocutalon-web/`, and remove OcuTalon's own stale files from the old folder at every start.

## Boundaries & Constraints

**Always:**
- **Event store (AD-12).**
  - `Live.Event` rows are written only by `Live.Publish`.
  - `Publish` refuses any type outside the event table and any payload object that isn't that type's class.
  - `Seq` is allocated per stream under a lock held across the allocation, the insert and the commit, so it has no gaps and commits in order.
  - A payload is the full current view of one entity. Its JSON keys are the property names with a lower-case first letter (camelCase).
- **Lanes (AD-29, AD-33).**
  - Each payload class follows its publisher's lane: `Incident`, `WatchProgress`, `Check` and their part classes are Lane A's; everything else is Lane B's.
  - Epic 0 fixes every property used across lanes (Design Notes tables). The owning lane appends the rest later.
- **The browser envelope (AD-13).**
  - Every state-changing call (any method except GET, HEAD and OPTIONS) needs `Content-Type: application/json`, `X-OcuTalon-Request: 1` and an `Origin` equal to the request's own origin.
  - The API never accepts a `SessionRef` from the client (AD-4).
  - Every API error uses `{"error": {"code", "message"}}`, in plain English.
- **The public package (AD-3).** `OcuTalon.Web.Public.Status` references only `%CSP` (including `%CSP.REST`), dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, its own package and `OcuTalon.Data.Public.Settings`. It overrides `AccessCheck`.
- **Persistent classes (AD-3, AD-5).**
  - A new persistent class gets `DEFAULTGLOBAL`, a row in `src/short-names.tsv` and its compiler-generated `Storage Default` block, copied in verbatim.
  - `Session` gains one property, appended. Its storage block is the compiler's, never edited by hand.
- **Times and refs.** Times are `Utc` strings from `Data.Time.NowUtc()`. Refs come from `Bridge.Ids.NewRef()`.
- **Runtime targets (Rules 13 and 21).**
  - On slot A, every MCP call names `server: ocutalon-slot-a` and `namespace: OCUTALON`.
  - Slot A tests create only per-run `Zz`/`zz` fixtures, from `$Increment(^OcuTalonTest(<area>,"n"))` (never reset), plus fresh `NewRef` streams. They remove everything they create, restore every public setting they change, and never publish on the `instance` stream.
  - HTTP and browser tests run only in throwaway projects through `lib-live.sh`, one IRIS stack at a time.
- **Source text.** ASCII only, with escapes for anything else. Comments state contracts, never history (Rule 14).

**Never:**
- **Owned by later stories:**
  - the WebSocket `OcuTalon.Web.Live` and `Publish`'s `$SYSTEM.Event` signal (2.11);
  - `Publish`'s guide recompute hook and `Guide.Compute` (4.2);
  - trace URLs through `Web.TraceLink` (2.9);
  - `Data.Ownership` (stubbed in 0.6, built in 2.2);
  - `Web.SessionEvents`, filled chat and rail sections, the live-event service, the error and skeleton UI, and `Live`'s `Purge` (2.2);
  - every publisher, and every POST or DELETE route body (their own stories);
  - the pairing endpoints' behaviour (10.3);
  - busy's header and splash (16.5), the resume cookie and online-demo sessions (16.3), epoch changes on sign-out or reset (16.4), and the countdown (16.8).
- **No new npm package.** `HttpClient` comes from `@angular/common`, already pinned.
- **References and secrets.** Never load or compile anything from `irislib/` or `irissys/`, and never read `.env`.
- **Containers and slots.** Never stop, recreate or reconfigure a slot or a container you didn't start.
- **The old bundle folder.** Never delete the old folder itself, or any file in it that isn't OcuTalon's.

## I/O & Edge-Case Matrix

Where each row runs:
- Rows 1–12 and 19–21: slot A `%UnitTest` classes.
- Row 7: `node --test web/scripts/`.
- Rows 13–19: `test-sign-in.sh`, through Playwright (`web/e2e/api/api.spec.ts`).
- Rows 22 and 24: `test-install-start.sh` and `test-install-upgrade.sh`.
- Row 23: `test-bundle-folder.sh`.

| # | Scenario | Input / State | Expected | Error Handling |
|---|---|---|---|---|
| 1 | Publish | fixture stream S; `reminder`, `status`, `incident` payloads; then a second stream S2 | `Seq` 1, 2, 3 on S. Each row has `Stream` S, `Ts` in `Utc` form, the `Type`, and `Payload` equal to the object's `%JSONExportToString`. `Publish.LastSeq(S)` is 3, and S2 starts at 1 | none |
| 2 | Publish refuses | type `zz.type`; type `reminder` with a `Payload.Status` object; stream `""` or `bad stream`; a call inside `TSTART` | each returns an error status naming the problem; no row is written and `LastSeq` is unchanged | error status |
| 3 | Seq under load | two jobs publish 50 events each to one fixture stream | `Seq` runs 1..100 with no gap and no duplicate, and row-id order equals `Seq` order | none |
| 4 | Event table | `Publish`'s `TYPES`; the classes directly in `OcuTalon.Live.Payload` | exactly the 16 spine types, each mapped to its class. The package's direct classes are exactly those 16, each `Extends (%RegisteredObject, %JSON.Adaptor)` | none |
| 5 | Payload contracts | the type and part classes | properties and types as in the Design Notes tables; every `%JSONFIELDNAME` is the name with a lower-case first letter. `WatchProgress.STAGES` = `noticed,settling,diagnosing`; `Status.CONDITIONS` = the six spine conditions | none |
| 6 | Incident payload | a fully set `Payload.Incident` (2 groups, 1 request with a result, evidence with 2 items, 3 trace targets); `FromRow` on a fixture `Data.Incident` row | the AC's keys, nested as the tables give (`traceTargets.firstFailure.traceHeaderId`, `requests[0].result.failedAgain`, `itemNoun.other`). `FromRow` copies every row-backed field and leaves `groups`, `requests`, `evidence` and `traceTargets` absent | none |
| 7 | TS generator | the real tree; fixtures | the real tree: `payloads.mjs --check` exits 0. A fixture property with no `%JSONFIELDNAME`, with a key that isn't camelCase, or with an unmapped type makes the script exit 1 naming `file:line`. A fixture renamed without regenerating makes `--check` exit 1 naming `payloads.ts` | exit 1 |
| 8 | Session | `ForUser("zzuser<n>")` twice, then `ForUser("ZZUSER<n>")`, then `ForUser("")` | the first call creates one row: `Ref` and `TraceRef` are distinct 22-character base64url strings, `CreatedAt` is `Utc`, `Epoch` has 22 characters. The later calls return the same row and `Epoch` | `""` gives an error status |
| 9 | `/state` body | `Api.StateBody(session)` | keys `version` (the IPM module's version, `""` on slot A), `instanceZone` (= `Data.Time.Zone()`), `epoch` (the row's), `streams` {`session`: `LastSeq(ref)`, `instance`: `LastSeq("instance")`}, `chat` [], `rail` {`approvals`, `checks`, `reminders`, `decisions`}, all [] | none |
| 10 | `/events` body | fixture session with 250 events; `EventsBody(session, a, b)` with `b` = `LastSeq("instance")` | `a`=0: events 1–200 in order, each `{seq, stream:"session", ts, type, payload}` with `payload` an object. `a`=248: 249 and 250. Another session's events never appear. `epoch` is set | none |
| 11 | Envelope check | `Api.EnvelopeError(method, contentType, header, origin, host, secure)` | `""` for GET/HEAD/OPTIONS whatever the headers, and for POST with `application/json; charset=utf-8`, `1` and `http://h:1` against host `h:1`. Otherwise: `text/plain` gives `not_json`; header absent or `0` gives `no_request_header`; Origin absent, `http://h:2`, `https://h:1`, or `http://h:1` with secure 1, gives `wrong_origin` | code |
| 12 | Routes | the compiled `UrlMap` | exactly the 12 routes in the Design Notes table (method and URL), nothing else | none |
| 13 | Snapshot over HTTP | README account signed in; script seeded 2 session events and 1 instance event | the page's load requests `GET /ocutalon/api/v1/state`, which answers 200, and `main[data-snapshot=loaded]` appears. Body: `version` = the manifest's, `instanceZone` and `epoch` = the values the script read, `streams` {2, 1}, empty `chat` and `rail` | none |
| 14 | Events over HTTP | cursors (0,0), (2,1), (1,1); bad cursors | (0,0): the 3 seeded events, session ones first, each with its marker. (2,1): `[]`. (1,1): only session `seq` 2. `epoch` matches. A missing, negative or non-numeric `after`/`afterInstance` gives 400 | `bad_cursor` |
| 15 | 403 envelope over HTTP | `POST /v1/messages` with a valid envelope; then each of: `text/plain`, no header, Origin `http://evil.example`, no Origin | valid: 501 `not_built`. Each failure: 403 with the error shape and the matching code. `GET /v1/state` with no extra headers: 200 | 403 |
| 16 | Unbuilt routes | each POST/DELETE route with a valid envelope | 501 `not_built` with "This part of OcuTalon isn't built yet."; both pairing routes give 404 `not_found` while `Included()` is 0 | 501 / 404 |
| 17 | Other errors | signed in: `GET /v1/zz`, `GET /v1/messages`; no session: `GET /v1/state` | 404 `not_found` and 405 `method_not_allowed` in the error shape. Without a session: 401 `signed_out` with "You were signed out. Sign in again to continue." and no `WWW-Authenticate` header | shown |
| 18 | No role | throwaway fixture `ZzTraceOnly` (trace role only) signs in to the trace application, then calls `GET /ocutalon/api/v1/state` (Task 0's route) | 403 `no_role` with `Login.#ERRORNOROLE`'s text; the README account gets 200 | 403 |
| 19 | Public status | no session: `GET /ocutalon/public/status`; signed in: the same, then `/state`; `/ocutalon/public/zz`. On slot A: `Status.Body()` with public settings set and restored, and `IsBusy` | 200 JSON with exactly `ready` (true), `nextReset`, `busy` (false), `lastReset`, `lastResetKind` (`null` when unset), and `Cache-Control: no-store`. The signed-in `/state` still answers 200 afterwards. Unknown paths: 404. `IsBusy(6,8,2)`=1, `(5,8,2)`=0, `(9,"",2)`=0, `(9,"x",2)`=0, `(1,1,"")`=1 | none |
| 20 | Web step | `Definitions` | four applications. `/ocutalon`'s `Path` is `DataDirectory()_"csp/ocutalon-web/"`, and `/ocutalon/public` has the Design Notes properties. `Run`'s `BundleCheck` reads the new folder | `%Status` |
| 21 | Old-bundle cleanup | temp folders under `GetTempDir()`, `zzbundle<n>` | an old folder holding OcuTalon's `index.html` (with `<base href="/ocutalon/">`), `main-AB12CD34.js`, `chunk-EF56GH78.js`, `styles-IJ90KL12.css`, `3rdpartylicenses.txt`, `assets/fonts/Inter-Regular.woff2` (also in the new folder), `zz-keep.txt` and `assets/zz/keep.txt`: after `RemoveOldBundle`, only the two `zz` files and their folders remain. An `index.html` without the marker: nothing is removed. No old folder: OK. A second run: OK | `%Status` naming the file |
| 22 | Bundle installed | first start | `/durable/iris/csp/ocutalon-web/` equals the image's bundle byte for byte; `/durable/iris/csp/ocutalon/index.html` is absent; the STEP list is unchanged | none |
| 23 | DW-5, both sides | first start, then old files seeded into `csp/ocutalon/` with `zz-keep.txt`, then a restart; Health and non-Health images | before seeding, `/csp/ocutalon/index.html` and `/csp/ocutalon/<main>.js` answer 404 with no session. Seeded, on non-Health only, `index.html` answers 200, which shows the exposure. After the restart both answer 404 on both images, OcuTalon's files are gone from the folder, and `zz-keep.txt` remains. Signed in, `/ocutalon/` and `/ocutalon/<main>.js` answer 200, and the js equals `csp/ocutalon-web/`'s byte for byte | FAIL names the probe |
| 24 | Upgrade | `test-install-upgrade.sh` | after the upgrade, `csp/ocutalon-web/index.html` equals the new image's and differs from the first; `check_security` reads the four applications | none |

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), by line range:
  - AD-3 L121–148 (public package allow-list, `AccessCheck`); AD-4 L150–173 (one durable session per IRIS user, no client `SessionRef`); AD-12 L325–338 (incident fields L333); AD-13 L340–383 (envelope L361, public application L350, epoch L371); AD-15 L396–436; AD-19 L475–515; AD-23 static files L628; AD-29 L754–768; AD-33 L820–828.
  - Conventions L864–887 (REST L875, live events L876); event table L1049–1064; REST surface L1151–1167.
- **Epics** (`epics.md`): this story L880–907. Consumers: 0.8 L988–1003 (waits for the snapshot); 2.2 L1429–1465 (`SessionEvents` creates the row, the full `/state`, the live-event service, 24-hour purge); 16.5 L4052–4066 (busy); 16.8 L4153–4165.
- **UX** (`EXPERIENCE.md`): L340 is the signed-out text.
- **Existing code:**
  - `src/ocutalon/cls/OcuTalon/Web/Api.cls`: empty map, `UseSession` 1, JSON.
  - `Web/Public/Shell.cls`: `AccessCheck` :33 (the pattern for `Status`), `HasRole()` :113 (reuse in `Api`).
  - `Web/Public/Login.cls:28`: `ERRORNOROLE`.
  - `Install/Step/Web.cls`: `Run` :30 (`BundleCheck` on `csp/ocutalon/`), `Definitions` :61 (`Path` :66), `Common` :105 (forces `AutheEnabled` 32 and `GroupById`), `Apply` :123, `BundleCheck` :134.
  - `Data/Public/Settings.cls`: `Get` :16, `NextReset` :57.
  - `Data/Session.cls`: 4 properties, `IrisUserIndex`.
  - `Data/Incident.cls`: the row behind `FromRow`; `ItemNoun` is JSON text.
  - `Live/Payload/Decision.cls`: the model every payload class follows.
  - `Data/Time.cls`: `NowUtc`, `Zone`.
  - `src/module.xml:11`: the `FileCopy` target.
- **Tests to keep green or update:**
  - `Test/Web/Install.cls`: `TestDefinitions` :40 (names :51), `Expected` :206–242.
  - `Test/Web/Shell.cls`: `Serve` :109 shows the in-process pattern (`New %request,%response`; `StubRequest.Make`; output to a temp file).
  - `Test/Data/Tables.cls`: Session contract :220–233, `Registry` XData :456–570.
  - `Test/Contract.cls:16`: `ORACLES`. `Test/Msg/Contracts.cls:351` already pins `Live.Payload.Decision`.
  - `web/e2e/sign-in/sign-in.spec.ts:64–66`: the empty 401 body changes. `shell.spec.ts:143–176`: rows 10 and 11 keep 404 and 401.
  - `docker/tests/lib-live.sh`:
    - `security_app_props` :332, which hard-codes `AutheEnabled=32` and `GroupById=OcuTalon`;
    - `check_security` :343, with `Path` at :346 and three applications at :356–364;
    - `live_start` :20, `live_web_port` :94, `dc` :136, `iris_script` :190, `wait_started_ready` :245, `container_sha256` :256, `container_tree_hashes` :260.
  - `test-install-start.sh:90–100` (row 14 paths). `test-install-upgrade.sh:126` and `:167–168`; its second-start wait is the pattern for a restart.
  - `test-compose-file.sh:121–122` (the exact `FileCopy` line).
  - `test-sign-in.sh`: user creation :49–58, the Playwright env :71–75, `e2e` runs every spec under `web/e2e/`.
  - `test-web-build.sh:86–92`: the tree must be clean after a build, so the generated TS is committed.
- **Web:**
  - `web/scripts/tokens.mjs`: `generate()` :381, `--check` :396–401, main guard :412. `tokens.test.mjs` shows the `spawnSync` and stale-check tests.
  - `web/package.json:9–13`: `build` chains `tokens.mjs --check`.
  - `web/src/app/app.config.ts`: no `HttpClient` yet. `app.ts`: `<main class="main">`.
  - `tsconfig.json`: strict, with `noPropertyAccessFromIndexSignature`.
  - `web/e2e/sign-in/helpers.ts:60–70`: `signIn`, `signInReadme`.
- **IRIS reference** (read only):
  - `irislib/%CSP/REST.cls`:
    - `Page` :133, where `AccessCheck` runs and its failure gives a bodiless 403 (:181–193);
    - `DispatchRequest` :370, with `OnPreDispatch` :377 before matching;
    - 404 :424, 405 `Http405` :574;
    - `ReportHttpStatusCode` :550 (overridable);
    - `Login` :245–308, which gives 401 with `WWW-Authenticate` from `GetAuthChallenge` :315;
    - `:ref` becomes a positional argument (:772–787, :898);
    - `HandleCorsRequest` :116;
    - no 501, 503 or 429 parameter.
  - `irislib/%CSP/Request.cls`: `ContentType` :47, `Secure` :89, `Get` :421, `GetCgiEnv` :702 (`HTTP_ORIGIN`, `HTTP_X_OCUTALON_REQUEST`, `HTTP_HOST`).
  - `irislib/%SYSTEM/License.cls:890`: `InstanceConnections()`.
  - `irislib/%JSON/Generator.cls`: an empty string is omitted :1161; an empty list is omitted even with `%JSONNULL` :1076; `%Boolean` exports `true`/`false` :1271. An object property's class must extend `%JSON.Adaptor`.
  - `irissys/Security/Applications.cls:38–49`: `AutheEnabled` 64 = unauthenticated.
  - IPM: `##class(%IPM.Storage.Module).NameOpen("ocutalon").VersionString` (`docker/ipm/zpm-0.10.10.xml:410`), as `test-install-start.sh:53` reads it.
- **S16 precedent** (`../spikes/batch2/s16/src/pub/OcuSpike.S16.Web.Public.Status.cls`): `UseSession` 0, `AccessCheck` authorises, the application `AutheEnabled=64` with no `MatchRoles`; a sessionless status takes no licence connection.
- **Measured on slot A, October 19** (build 154 Health ARM64, profile port 52773 in the container, user `_SYSTEM`):
  - `$SYSTEM.SQL.IsReservedWord` is 0 for EVENT, STREAM, SEQ, TS, TYPE, PAYLOAD and EPOCH, and 1 for TIME (only a non-persistent part uses `Time`);
  - `%IPM.Storage.Module` is absent;
  - `InstanceConnections()` is 0;
  - `Zone()` is `UTC`; `$TLevel` is 0.
- **Bundle layout** (`src/ocutalon/csp/`, local build): `index.html` (holds `<base href="/ocutalon/">`), `3rdpartylicenses.txt`, `main-<8 chars>.js`, `styles-<8 chars>.css` (and `chunk-*`/`polyfills-*` when emitted), `assets/{brand,fonts,licenses}/`.

## Tasks & Acceptance

**Execution:**

**Task 0, measure.** Record each result under Verification; anything left unmeasured is `(inference)`.
- **Throwaway, Health image:**
  - Does a trace-only user signed in at `/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen` reach `/ocutalon/api/v1/state` through the sign-in group, and get `no_role`? If not, row 18 uses a POST of the CSP sign-in fields (`IRISUsername`, `IRISPassword`, `IRISLogin`) to `/ocutalon/api/v1/state` instead. Record which route works.
  - Does a `curl` sign-in work: GET `/ocutalon/`, then POST of the three fields with a cookie jar? It is row 23's sign-in.
  - Does overriding `Api.Login` keep shell row 10's group sign-in?
  - Is `HTTP_HOST` present?
- **Slot A:** does `%JSONExportToString` omit an empty list, and export `false` for a `%Boolean` whose `InitialExpression` is 0?
- **Not measurable before 0.6:** `$TLevel` is 0 in a business host's `OnMessage` `(inference)`. Publishers in a transaction get `Publish`'s error, which is the intended failure.

IRIS (`src/ocutalon/cls/OcuTalon/`):
- `Live/Event.cls` (B), a `%Persistent` row written only through `Live.Publish` (AD-12):
  - `DEFAULTGLOBAL = "^OcuTalonP.LiveEvent"`;
  - properties `Seq` Int, `Stream` Ref, `Ts` Utc, `Type` Word, `Payload` Long;
  - `Index StreamSeqIndex On (Stream, Seq) [ Unique ]`;
  - `Parameter MAXEVENTS = 200`, the most events one poll returns per stream;
  - `ClassMethod Since(stream, after As %Integer, max As %Integer, label) As %DynamicArray`: the envelopes `{seq, stream: label, ts, type, payload: <object>}` with `Seq > after`, in `Seq` order, at most `max`.
- `Live/Publish.cls` (B):
  - `Parameter TYPES`, the 16 `type:Class` pairs of the Design Notes;
  - `PayloadClass(type) As %String`: `""` when the type is unknown;
  - `LastSeq(stream) As %Integer`: the stream's counter, 0 when none;
  - `Publish(stream, type, payload, Output seq) As %Status`:
    1. Refuse when `$TLevel > 0`, when the type is unknown, when `$ClassName(payload)` isn't the type's class, or when the stream isn't `instance` or a 22-character ref.
    2. Then `Lock +^OcuTalonP.LiveEventC(stream):5`, `TSTART`, set the counter to its value plus 1, insert the row with `Ts` = `NowUtc()` and `Payload` = the export, `TCOMMIT`, unlock.
    3. On failure, `TROLLBACK` and unlock, and return the error.
- `Live/Payload/<Type>.cls` and `Live/Payload/Part/<Name>.cls`: the 15 new type classes and 10 part classes in the Design Notes tables. Each `Extends (%RegisteredObject, %JSON.Adaptor)`; every property sets `%JSONFIELDNAME`; every `%Boolean` has `InitialExpression = 0`. `Payload.Incident` adds `ClassMethod FromRow(row As OcuTalon.Data.Incident) As OcuTalon.Live.Payload.Incident`. AD-12, AD-15, AD-29.
- `Data/Session.cls`:
  - append `Property Epoch As %String(MAXLEN = 22)`;
  - `ClassMethod ForUser(irisUser As %String, Output sc As %Status) As OcuTalon.Data.Session`: under `Lock +^OcuTalon.Data.Session($ZConvert(irisUser,"U")):5`, find the row through `IrisUserIndex` (SQL lookup is case-insensitive), or create it with `Ref`, `TraceRef` and `Epoch` from `NewRef` and `CreatedAt`; `""` is refused;
  - then load, compile and copy the new storage block in. AD-4, AD-13.
- `Web/Api.cls` (B), using the routes, codes and messages of the Design Notes:
  - parameters `CHARSET = "utf-8"`, `HandleCorsRequest = 0` and `HTTP501NOTIMPLEMENTED`;
  - the 12-route `UrlMap`;
  - `Login` answers 401 `signed_out` with no `WWW-Authenticate`;
  - `OnPreDispatch`: first the role check (`##class(OcuTalon.Web.Public.Shell).HasRole()`; otherwise 403 `no_role`, and the session is not ended), then `EnvelopeError` from `%request`, and 403 when it gives a code;
  - `ReportHttpStatusCode` writes the error shape for 404, 405 and 500 (resetting `ContentType` to JSON);
  - `State()`, `Events()`, `NotBuilt(arg = "")`, `Pairing()` (404 while `##class(OcuTalon.Channel.Telegram.In).Included()` is 0, else 501);
  - `StateBody(session) As %DynamicObject`, `EventsBody(session, after, afterInstance) As %DynamicObject`, `EnvelopeError(...) As %String`, `Fail(status, code, message)`;
  - `Version()`: `$ClassMethod("%IPM.Storage.Module","NameOpen","ocutalon").VersionString` inside a `Try`, `""` when it fails;
  - the session comes from `Session.ForUser($Username)`.
  - AD-4, AD-12, AD-13.
- `Web/Public/Status.cls` (B, public package):
  - `%CSP.REST` with `UseSession = 0`, JSON and `HandleCorsRequest = 0`;
  - `AccessCheck` authorises;
  - route `GET /status`, which writes `Body()` with `Cache-Control: no-store`;
  - `Body() As %DynamicObject` reads `Public.Settings` (`ready`, `NextReset()`, `lastReset`, `lastResetKind`, `connectionCap`, `connectionReserve`) and `$SYSTEM.License.InstanceConnections()`;
  - `IsBusy(connections, cap, reserve) As %Boolean`.
  - AD-3, AD-13, AD-19.
- `Install/Step/Web.cls` (B):
  - `Parameter BUNDLEFOLDER = "csp/ocutalon-web/"` and `OLDBUNDLEFOLDER = "csp/ocutalon/"`;
  - `Run` = `BundleCheck(new)`, `RemoveOldBundle(old, new)`, `Apply` of the four definitions, `GrantTraceSql`;
  - `Definitions` gains `/ocutalon/public` (Design Notes);
  - `RemoveOldBundle(oldDir, newDir) As %Status` follows the DW-5 ruling.
  - Update the class doc. DW-5, AD-13, AD-23.

Package, repository and web:
- `src/module.xml`: `<FileCopy Name="ocutalon/csp/" Target="${dataDir}csp/ocutalon-web/"/>`. DW-5.
- `src/short-names.tsv`: add `LiveEvent	^OcuTalonP.LiveEvent	OcuTalon.Live.Event	B`.
- `web/scripts/payloads.mjs`:
  - reads `Publish.cls`'s `TYPES` and every `.cls` under `Live/Payload/` (parts included);
  - writes `web/src/app/live/payloads.ts`, ASCII, starting with a "generated" header line;
  - type mapping: `%String`→`string`; `%Integer`/`%Numeric`→`number`; `%Boolean`→`boolean`; `list Of %String`→`string[]`; a part class or a list of one → its interface;
  - every field is optional;
  - type classes are named `<Name>Payload`, and parts by their short name;
  - it also emits `LiveEventType` (a union) and `LivePayloads` (type → interface);
  - it fails closed (exit 1, `file:line`) on a missing `%JSONFIELDNAME`, a key that isn't the property name with a lower-case first letter, or an unmapped type;
  - `--check` follows `tokens.mjs`.
- `web/scripts/payloads.test.mjs`: row 7, with fixtures in a temporary folder and the real tree.
- `web/package.json`: script `payloads`. `build` becomes `node scripts/tokens.mjs --check && node scripts/payloads.mjs --check && node scripts/brand.mjs && ng build`.
- `web/src/app/live/payloads.ts`: generated and committed.
- `web/src/app/api/api-types.ts`: `LiveItem`, `LiveEnvelope`, `StateSnapshot`, `EventsResponse`, `ApiError` and `PublicStatus`, as in the Design Notes.
- `web/src/app/api/api-client.ts`: `ApiClient` (`providedIn: 'root'`) with `state()` and `events(after, afterInstance)`, on `/ocutalon/api/v1/...`.
- `web/src/app/app.config.ts`: add `provideHttpClient()`.
- `web/src/app/app.ts`: load the snapshot once into a signal, and set `main`'s `data-snapshot` to `loading`, `loaded` or `failed`. No visible text changes.

Tests:
- New slot A test classes:
  - `Test/Live/Publish.cls`: rows 1–3. `Burst(stream, n)` runs in the `Job`s.
  - `Test/Live/Payloads.cls`: rows 4–6. Its contract XData covers the 25 new classes; add it to `Test.Contract.ORACLES`.
  - `Test/Data/Session.cls`: row 8.
  - `Test/Web/Api.cls`: rows 9–12.
  - `Test/Web/Status.cls`: row 19's slot A part.
- Updated slot A tests:
  - `Test/Web/Install.cls`: four names, and an `Expected` branch for `/ocutalon/public` and the new `Path`; add `TestRemoveOldBundle` (rows 20–21).
  - `Test/Data/Tables.cls`: add `"Epoch": "%String(MAXLEN=22)"` to Session, and the `LiveEvent` row to `Registry`.
- `web/e2e/api/api.spec.ts`: rows 13–19 over HTTP. It reads `OCUTALON_E2E_VERSION`, `_ZONE`, `_EPOCH`, `_MARKER` and `OCUTALON_TRACEONLY_USER`/`_PASSWORD`, and fails when any is missing.
- `web/e2e/sign-in/sign-in.spec.ts` row 4: expect 401 with body `{"error":{"code":"signed_out",…}}` and no `www-authenticate`.
- `docker/tests/test-sign-in.sh`:
  - create `ZzTraceOnly` (random password, role `OcuTalonTraceViewer`) beside `ZzNoRole`;
  - through `iris_script OCUTALON`, call `Session.ForUser("ocutalon")`, publish two `reminder` payloads (texts `zz-$P-1`, `zz-$P-2`) on its `Ref` and one `status` payload (`noModelKey`, active) on `instance`, and read back `Epoch` and `Zone()`;
  - pass those values and `manifest_version` to Playwright, and redact both passwords.
- `docker/tests/lib-live.sh`:
  - `security_app_props` takes `AutheEnabled` and `GroupById` (defaults 32 and `OcuTalon`);
  - `check_security` expects `/durable/iris/csp/ocutalon-web/` and four applications.
- `docker/tests/test-install-start.sh` row 14: the new path, plus "`csp/ocutalon/index.html` absent" (row 22).
- `docker/tests/test-install-upgrade.sh:126,167`: the new path (row 24).
- `docker/tests/test-compose-file.sh:121–122`: the new `FileCopy` line.
- `docker/tests/test-bundle-folder.sh` (new, label `t05`): row 23.
  - Setup: `live_start`, `live_web_port`, `dc up -d --build`, `wait_started_ready`.
  - Probes: `curl` against `127.0.0.1:$web_port`. The main js name comes from `ls /durable/iris/csp/ocutalon-web`.
  - Seeding: `dc exec` copies the new folder into `/durable/iris/csp/ocutalon/` with `zz-keep.txt`.
  - The application `/csp/ocutalon` is detected through `iris_script %SYS` `Security.Applications.Exists`, which decides whether the seeded probe must answer 200.
  - Restart with `dc restart iris`, and wait as `test-install-upgrade.sh` does after a second start.
  - It must finish within `lib-live`'s 540 s deadline.

**Acceptance Criteria:**
- Given both trees loaded and compiled on slot A, when the slot A test classes run one per call, then rows 1–12 and 19–21 hold, and every existing class in the Verification list still passes.
- Given the web tree, when `node --test web/scripts/` and `npm --prefix web run build` run, then row 7 holds, the generated interfaces are current for every payload (`Live.Payload.Decision` included), and `test-web-build.sh` passes.
- Given a first start in a throwaway project, when `test-sign-in.sh` runs, then rows 13–19 hold over real HTTP, and Story 0.3's sign-in specs still pass, with row 4's 401 now in the error shape.
- Given the Health image and then `IRIS_IMAGE=iris-community:2026.3.0AI.154.0`, when `test-bundle-folder.sh` runs, then row 23 holds on both: no bundle file answers under `/csp/ocutalon/` without a session, stale OcuTalon files are removed at the next start, and the bundle loads from `csp/ocutalon-web/` through `/ocutalon/` after sign-in (DW-5).
- Given `test-install-start.sh` and `test-install-upgrade.sh`, when they run, then rows 22 and 24 hold, with the STEP list unchanged.
- Given the committed storage blocks of `Session` and `Live.Event`, when the trees are loaded, compiled and exported again on slot A, then no tracked file changes.

### Review Findings

Code review, October 19 (four layers, full-opus tier; Rule 22 standing grant). 37 rows (36 from the layers, 1 from the reviewer's Rule 2 check) became 12 entries (high 0, medium 4, low 8) and 18 rejections. Each finding carries severity, fix-risk, footprint and spec-status (Rule 15).

- [x] [Review][Patch] (medium; fix-risk low, a test-only change plus an optional argument; in-story; clear) The instance stream's 200-event cap and its place after the session stream are unpinned, and `TestStateBody`/`TestEventsBody` read the shared `instance` stream. `StateBody` and `EventsBody` hard-wire the instance stream, and slot A tests may not publish on it, so the instance half has no state of its own in any slot A test. A cap shared with the session stream, or no cap at all, stays green (Verification gap 1; 5a) [src/ocutalon/cls/OcuTalon/Web/Api.cls:150]
- [x] [Review][Patch] (medium; fix-risk low; in-story; clear) Rule 19 hermeticity: "row 13: the first /state of a user without a session row creates one" exercises the create branch only because it runs before "row 14: a user's poll holds the instance events...", which signs in as the same `ZzFirstCall` user and creates its row if it runs first. In reverse order the first test stays green and creates nothing [web/e2e/api/api.spec.ts:136]
- [x] [Review][Patch] (medium; fix-risk low, tests only; in-story; clear) Rule 2: the capture-to-a-temporary-file block of `Test.Web.Shell.Serve` (Story 0.3) is copied three times with no stated reason: `Test.Web.Api` `Run` and `PreDispatch`, and `Test.Web.Status` `TestRouteAndAccess` (the copies already differ: read limits of 100000 and 10000, and `If '$Test Quit ""` skips the assertion). `Shell.Serve` keeps its own copy for a stated reason: it reads binary bodies [src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:309]
- [x] [Review][Patch] (low; fix-risk low; in-story; clear) On any error, the public status class sends the `%Status` text (routine, line, global, database path) to the anonymous caller, because `%CSP.REST.Page` passes it to `Http500` and `outputStatus`. `Web.Api` keeps causes out of its answers; `Status` doesn't override `ReportHttpStatusCode` [src/ocutalon/cls/OcuTalon/Web/Public/Status.cls:7]
- [x] [Review][Patch] (low; fix-risk low; in-story; clear) `Live.Event.Stream`'s `COLLATION = "EXACT"` (AD-12 as amended) is unpinned: `Test.Contract` doesn't compare collation, and no test uses two references that differ only in case, so removing it stays green [src/ocutalon/cls/OcuTalon/Live/Event.cls:17]
- [x] [Review][Patch] (low; fix-risk low; in-story; clear) `TestEveryTableIsRegistered` queries only `OcuTalon.Data.` and `OcuTalon.Bridge.Data.`, so `Live.Event`, the first persistent class outside those packages, and any later one in `OcuTalon.Live`, is not checked for a registry row [src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls:46]
- [x] [Review][Patch] (low; fix-risk low; in-story; clear) `Web.Api` declares `CONTENTTYPE` and `CHARSET` again with the values it inherits from `Web.Public.ApiBase`, whose `Login` reads both: two sources of truth for the parameters of the one method that must run from the public routine [src/ocutalon/cls/OcuTalon/Web/Api.cls:18]
- [x] [Review][Patch] (low; fix-risk low; in-story; clear) `State` and `Events` build the whole answer as one string (`Write ....%ToJSON()`), so a poll whose 400 events exceed about 3.6 MB raises `<MAXSTRING>` on every retry from that cursor [src/ocutalon/cls/OcuTalon/Web/Api.cls:100]
- [x] [Review][Patch] (low; fix-risk low; in-story; clear) `TestRefuses` "leaves LastSeq alone" cannot fail for the empty, malformed and 21-character streams: `LastSeq` returns 0 for anything that isn't a stream. The row count in the same cases can still fail [src/ocutalon/cls/OcuTalon/Test/Live/Publish.cls:298]
- [x] [Review][Patch] (low; fix-risk low; in-story; clear) `post()` in `api.spec.ts` discards `originOf(baseURL)`; its `baseURL` parameter is unused, and `call()` already does the work [web/e2e/api/api.spec.ts:105]
- [x] [Review][Patch] (low; fix-risk low; in-story; clear) Rule 14: two comments narrate history: `OLDBUNDLEFOLDER` "The folder that earlier builds used", and "(measured October 19)" in `test-bundle-folder.sh` [src/ocutalon/cls/OcuTalon/Install/Step/Web.cls:28]
- [x] [Review][Defer] (medium; fix-risk low; out-of-footprint; clear) `Web.Api` `State` and `Events` resolve the caller's session with `Session.ForUser($Username)` and read the streams outside `Data.Ownership`. AD-4's last bullet says REST reads go through Ownership, while AD-13's October 19 amendment says the API's own queries enforce ownership. Stories 2.2 (AC 17) and 16.3 expect Ownership to resolve the caller's `SessionRef` from the CSP session, never the IRIS user name, and this story leaves two direct lookups for 16.3 to find. Isolation holds today (one durable session per user; QA's cross-user poll test) [src/ocutalon/cls/OcuTalon/Web/Api.cls:98] — deferred: DW-15, `routed owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates`; Ownership is 2.2's (this spec's Never list), and the lead reconciles AD-4's last bullet with AD-13's amendment (Rule 20)

The lead's questions:
- Security posture (Rule 22.3), all confirmed against the code:
  - `/state` and `/events` read only the row that `ForUser($Username)` returns, its `Ref` stream and the `instance` stream. The two queries prepared without the privilege check have fixed text with parameters only. No route reads a client ref (the `:ref` routes all go to `NotBuilt`).
  - QA's cross-user poll test can fail: QA's `ForUser("ocutalon")` mutation turned it red, and this review shows it again on the merged test (Verification).
  - The envelope applies to every method except GET, HEAD and OPTIONS, in `OnPreDispatch`, which `%CSP.REST.DispatchRequest` runs before `DispatchMap` (REST.cls:377-383).
  - The no-role 403 comes first and never touches `%session`.
  - `/ocutalon/public` answers only `GET /status`, uses no session (`UseSession` 0), and references only the allow-list.
  - `ApiBase.Login` sends no `WWW-Authenticate`.
- `RemoveOldBundle`: it matches the ruling. It deletes only OcuTalon's files, only behind the marker, `index.html` last, and never the folder itself: the top level deletes files only. The same-path guard is not a Fix Pack item; it is rejected below (R17).
- The instance stream's cap: in-story, patched now by a refactor (first entry above). No throwaway test is needed.
- `LastSeq`'s 5-second wait: acceptable for release 1, with no retry. `Publish` holds the stream lock only across one counter set, one `%Save` and the commit, and it refuses to run inside a caller's transaction. A wait over 5 seconds therefore needs an instance-wide stall (a journal or write-daemon freeze). There a 500 is the honest answer, and a retry would only hold the browser's request longer. Reopen if `messages.log` shows the lock-timeout error from `LastSeq` under normal load.

Rejected (18):
- R1 (low) The allow-list scan misses `Extends`, routine calls, `$Parameter` and `$ZObj*` (Blind Hunter). HTTP rows 17 and 19 run both public classes as the anonymous user, so a reference that user can't read fails there; extending the scan adds parsing for no reachable case.
- R2 (low) No sessionless probe of `/csp/ocutalon-web/` (Blind Hunter). No application's name covers that URL: CSP matches application names by path, and `/csp/ocutalon` is a sibling. `check_security` pins the four OcuTalon applications, and AC4 is about `/csp/ocutalon/`.
- R3 (low) `IrisUser` holds 128 characters and an IRIS user name 160 (Edge Case Hunter). 0.4's contract fixes 128, no such user exists in the product, and the failure is a logged 500; also rejected in the implement-stage review.
- R4 (low) A poll can read a row whose `Publish` then rolls back (Edge Case Hunter). Nothing between `%Save` and `TCOMMIT` can fail; only a process killed in that window could cause it, and committed reads would add locking to every poll.
- R5 (spec-bound) The origin check behind a TLS proxy (Edge Case Hunter). The Design Notes ruling: 16.3 adds the forwarded scheme.
- R6 (spec-bound) `STALEFILES` misses unhashed development names and `media/` (Edge Case Hunter). The DW-5 ruling fixes the pattern, and the package ships the hashed production build.
- R7 (spec-bound) `Publish` doesn't check closed catalogs (Edge Case Hunter). Row 2 and the Design Notes limit refusals to the type and the class.
- R8 (false) `ApiBase.Login` drops the language guard (Edge Case Hunter). Measured in the implement-stage review: the answer is unchanged with `Accept-Language`.
- R9 (low) A disabled `UnknownUser` gives a Basic challenge on `/ocutalon/public` (Edge Case Hunter). Both images enable it and row 19 passes on both; disabling it changes the instance's security model.
- R10 (false) Nested `Part/` folders give invalid TypeScript (Edge Case Hunter). None exists, and the invalid file fails `ng build` loudly.
- R11 (false) Rows 1, 2, 5, 6, 9, 16, 17 and 20 have no `mutation:` line (Verification gap 3). Rule 19 asks for one demonstrated mutation per AC, and every AC has one.
- R12 (low) `TestLastSeqWaitsForAnOpenPublish` keys on a flag set before the lock (Verification gap 4b). Under the mutation, the reader would have to stall over 1 second in a window of microseconds; closing that gap needs process-state introspection.
- R13 (false) `TestStateBody`'s version and instance values (Verification gap 4c). The layer itself found no gap, and HTTP row 13 pins both.
- R14 (low) `TestNoRoleIsRefusedFirstAndKeepsTheSession` passes without checking in a process that holds the role (Verification gap 4d). It ran on slot A (QA's mutations went red), and HTTP row 18 pins the same behaviour.
- R15 (false) `Test.Live.Publish` streams are not `Zz`-named (Verification gap 5c). The Boundaries allow fresh `NewRef` streams.
- R16 (low) `ApiClient.events()` never runs (Verification gap 6). Its first caller, 2.2's poll, fails loudly (400 `bad_cursor`) on a wrong name, and there is no unit-test host under `web/src`.
- R17 (low) `RemoveOldBundle` has no guard for the same old and new folder, or for a symlink (Verification gap, other; Edge Case Hunter; Acceptance Auditor). It is unreachable with the shipped code: `Prepare` passes two constants that `Test.Web.Install` pins, and QA's equal-constants mutation turns `test-install-start.sh` red. The symlink case needs an operator-made link inside IRIS's `csp/` folder, and the fix adds a guard. Also noted there: an already-empty folder under `assets/` is removed. No file is deleted, and the ruling removes "each folder that is left empty".
- R18 (spec-bound) `api.spec.ts` throws at load when a variable is missing (Acceptance Auditor). The spec says it "fails when any is missing", and only `test-sign-in.sh` runs `web/e2e/`.

## Spec Change Log

Implement pass, October 19 (unattended; every ruling is Rule 22, standing grant).

- Rule 22 ruling: where does the API's 401 `signed_out` answer live? -> in a new abstract class `OcuTalon.Web.Public.ApiBase` (`%CSP.REST`, in the public package), which `OcuTalon.Web.Api` extends. `Api` has no `Login` of its own. Measured: a `Login` override in `Api` (OCUTALON_CODE) is never run for a request without a session, because that request runs as a user with no role and cannot read the code database's routine; the CSP server logs `ISCLOG: CSPServer Error displaying login page` and answers a bodiless `404 Not Found` page. (rejected: the override in `Api`, measured as above; the superclass's default `Login`, which answers a bodiless 401 and not the error shape.) The class references only `%CSP` and dynamic objects, and `Test.Web.Status` scans its source with `Status`'s. VETO WINDOW item (security posture: a new class in the pre-sign-in database; it only returns the static 401 body).
- Rule 22 ruling: SQL privilege of the signed-in user on `Data.Session` and `Live.Event` -> `Session.ForUser` and `Live.Event.Since` prepare their two fixed queries with `%Prepare(text, 0)` (no privilege check at prepare). Measured: the README account gets SQLCODE -99 from a dynamic `SELECT` on either table, so `/v1/state` answered 500 (the cause is in `messages.log`). The query texts hold no user input; the user name and cursors are parameters. (rejected: granting SELECT on the two tables to `OcuTalonUser`, a new grant to a role, VETO WINDOW; walking the index globals by hand, which hard-codes the storage layout.) VETO WINDOW item (security posture).
- Rule 22 ruling: row 18's route -> the CSP sign-in fields posted to `/ocutalon/api/v1/state`, as Task 0 measured (the trace-window cookie does not reach the API).
- Rule 22 ruling: `Step.Web.Run` -> split into `Prepare(dataDirectory)` (`BundleCheck` of the new folder, then `RemoveOldBundle`) and the rest, so that rows 20 and 21 test what `Run` does to the files on a fixture data directory and never on the slot's real one. Rejected: a test that calls `Run` on slot A, which would Modify the real applications once the slot holds a bundle.
- Rule 22 ruling: `tokens.mjs` -> exports `emitOutputs(name, outputs, check)`, the write-or-check routine; `payloads.mjs` imports it. Its messages are unchanged (the existing tokens tests pass).
- Rule 22 ruling: `Live.Event.Stream` -> `COLLATION = "EXACT"`, because a reference is case-sensitive base64url and the default collation would treat two references that differ only in case as one stream. `Session.IrisUser` keeps the default collation, which is what `ForUser` needs.
- Rule 22 ruling: row 3 -> the two jobs wait for a go signal and start together; without it the first job finished its 50 events before the second began and the no-lock mutation stayed green.
- Rule 22 ruling: `test-bundle-folder.sh` probes -> each probe asks a URL of its own (a counter in the query string). Measured: the web gateway keeps the answer to a URL, 404 and 200 alike, also after the file is removed; a probe of the same URL before and after seeding or the restart would read the gateway and not IRIS. Row 23 itself is unchanged: the same two files, before seeding, seeded, and after the restart.
- Rule 22 ruling: `/events` cursor -> a whole number of 1 to 15 digits; `bad_cursor` for anything else. The envelope compares the media type of `Content-Type` and the origin without regard to case, and allows parameters such as the charset.
- Rule 22 ruling: `LiveItem<T>` in `api-types.ts` is distributive over the event types, so `LiveItem` (all types) is a discriminated union and `LiveItem<'reminder'>` is the spec's `{type, payload}`.
- Task 0 order: the throwaway measurements ran after the IRIS classes existed, against a stack built from the tree, so that they exercised the real `Api`; nothing in them changed the design except the two findings above.

Review pass, October 19 (Rule 22 rulings):
- Rule 22 ruling: `Live.Publish.LastSeq` and a page's cursor -> `LastSeq` takes the stream's lock shared and waits for an open `Publish`, so `/state` never hands out a Seq that is not committed; it throws when the lock is not free in 5 seconds (a 500, not a wrong cursor). (rejected: writing the counter after the row is saved, which narrows the window and does not close it; reading with a lock-free retry.) The Seq contract of AD-12 is unchanged.
- Rule 22 ruling: `Step.Web.RemoveOldBundle` -> `index.html`, the marker, is deleted last, so a run that stops early is repeated by the next start. The set of files deleted is unchanged.
- Rule 22 ruling: the first-call path -> a fixture user `ZzFirstCall` (user role, no session row) is created by `test-sign-in.sh`, and `api.spec.ts` calls `/state` as that user; the README account's session is still made by the script, so the create branch needed a user of its own.
- Rule 22 ruling: `ApiBase.Login` and `Accept-Language` -> no language guard (measured, see Verification); the anonymous requests of `api.spec.ts` rows 17 and 19 carry the header of a browser.

Spine updates for the lead (Rule 20), in addition to those under Design Notes:
- AD-3: the contents of `OcuTalon.Web.Public` gain `ApiBase`, the API's answer to a request without a session; the reason is that code which answers before sign-in must be in OCUTALON_PUBLIC.
- AD-13: the API's 401 comes from `OcuTalon.Web.Public.ApiBase`; the signed-in user's queries on `Session` and `Live.Event` are prepared without the SQL privilege check, because the user holds no SQL privilege on OcuTalon's tables.
- AD-12: `Live.Event.Stream` is exact-collated; `LastSeq` waits, under a shared lock on the stream, for an open `Publish`, so a snapshot's cursor is never ahead of the committed rows.

## Review Triage Log

### 2026-10-19 - Review pass
- verdicts: 43 findings - high 0, medium 9, low 22, false 12, maybe-false 0
- patch groups (fixed in this pass): `RemoveOldBundle` order; `LastSeq` lock; `Publish` failure test; `ForUser` open status, concurrency test and unprivileged first call; allow-list scan case; generator guard; curl limit; two test clean-ups.
- findings:
  - Blind Hunter:
    - `[medium]` `[patch]` `RemoveOldBundle` deletes its own marker (`index.html`) first, so a failed later delete leaves files that no later start removes - verified in `Web.cls`: a run that stops after `index.html` is gone is not repeated, the leftover scripts stay served by the default application. Fix applied: `index.html` is deleted last; `TestRemoveOldBundleKeepsAndFails` now asserts it stays, and that the next run removes the rest.
    - `[medium]` `[patch]` `LastSeq` reads the counter with no lock while `Publish` raises it inside its open transaction - verified: global reads are dirty, so `/state` could hand out Seq N before event N commits and the page would never receive it. Fix applied: `LastSeq` takes the stream's lock shared (waits for an open publish; throws when the lock is not free in 5 s); `TestLastSeqWaitsForAnOpenPublish` pins it with a job that holds the lock.
    - `[false]` `[reject]` `ApiBase.Login` drops the language guard of `%CSP.REST.Login` - measured on build 154 with the guard removed and `Accept-Language: en-US,en;q=0.9` on the anonymous requests of `api.spec.ts` row 17: the answer is still 401 `signed_out` with the body. The guard was not added; the header stays in the spec rows 17 and 19 as a browser-like probe.
    - `[low]` `[patch]` `Session.ForUser` ignores the status of `%OpenId` - the row can vanish between the SELECT and the open; it returned "" with an OK status. Fix applied: the open's status is kept, and an empty result gives an error status (no pinning test: the vanished row cannot be made on purpose; a direct 3-line correction).
    - `[medium]` `[patch]` the failure path inside `Publish`'s lock (rollback, counter, lock) is untested - same root cause as the verification gap below. Fix applied: `TestFailureLeavesNoGap`.
    - `[low]` `[defer]` `ApiClient` has no support for the browser envelope (`Content-Type: application/json` and `X-OcuTalon-Request: 1` on non-GET calls, body-less DELETE included) - no POST exists in the client yet, so nothing is broken here; the first story that adds one fails loudly with 403 `not_json`. Deferred to the story that adds the first POST, which is 2.2's live-event service area.
    - `[low]` `[reject]` the closed catalogs (`Status.CONDITIONS`, `WatchProgress.STAGES`, `Msg.Enum` values) are not enforced by `Publish` and are `string` in `payloads.ts` - spec-bound: `Publish` refuses a type outside the event table and a payload of another class, nothing more (Design Notes, Row 2), and the TypeScript mapping is the spec's; each catalog belongs to its publisher's story.
    - `[low]` `[patch]` the source scan of the public classes is case-sensitive and misses dynamic dispatch - `##Class(` or `$system.` would pass. Fix applied: the scan upper-cases the source, and flags `$ClassMethod(` and `$Method(`; the test also feeds the scan a probe string.
    - `[false]` `[reject]` `/v1/state` and `/v1/events` send no cache headers, and the gateway keeps one answer per URL - the gateway keeps the answer to a static file's URL; `api.spec.ts` asks `/v1/state` signed out (401), signed in (200) and as the trace-only user (403) on the same URL in one stack, and each gets its own answer.
    - `[low]` `[reject]` DW-5 leaves the default `/csp/ocutalon` application unauthenticated - the DW-5 ruling (Design Notes) chose to move the bundle and remove OcuTalon's own files, and rejected touching the application; `test-bundle-folder.sh` observes the closure on the non-Health image.
  - Edge Case Hunter:
    - `[medium]` `[patch]` `RemoveOldBundle` deletes `index.html` first - same root cause as the first Blind Hunter finding.
    - `[medium]` `[patch]` `LastSeq` and `Since` read while a publish is uncommitted - same root cause as the `LastSeq` finding. (`Since` reads a row only after its `%Save`, inside the same millisecond window as the commit; a rollback after a successful save is not a case this code reaches.)
    - `[low]` `[patch]` `ForUser` ignores the `%OpenId` status - same root cause as the `ForUser` finding above.
    - `[low]` `[reject]` an IRIS user name may be up to 160 characters while `IrisUser` is 128 - the contract (Row 8, `Test.Data.Tables`) fixes 128; no such user exists in the product, and widening the property changes a frozen contract for no reachable case.
    - `[low]` `[reject]` behind a TLS-terminating proxy `%request.Secure` is 0 and every non-GET call gets 403 `wrong_origin` - spec-bound: the Design Notes ruling reads the scheme from `%request.Secure` and says that 16.3 adds the proxy's forwarded scheme.
    - `[false]` `[reject]` cookie-less requests to `/ocutalon/public/status` each hold a licence connection for about ten seconds - AD-13 (spine L355, L375) records, from S16 and S13, that the sessionless status takes no connection; `InstanceConnections()` was 0 on every measurement here.
    - `[low]` `[reject]` `Publish` does not check the values of closed lists, nor that a type goes to the right kind of stream - spec-bound, as above.
    - `[low]` `[patch]` `payloads.mjs` silently skips an indented or lower-case `property` line - the field would be dropped from `payloads.ts` with `--check` green. Fix applied: such a line must match the property form or the generator exits 1 naming `file:line`; two fixtures in `payloads.test.mjs`.
    - `[low]` `[patch]` the `curl` calls of `test-bundle-folder.sh` have no time limit - the header promises a 9-minute bound. Fix applied: `--max-time 30` on every call.
    - `[low]` `[patch]` the allow-list scan is case-sensitive - same root cause as the Blind Hunter scan finding.
    - `[low]` `[patch]` the cleanup is skipped when the old `index.html` is absent - the failed-run case is the `RemoveOldBundle` finding above (fixed by the order); a folder whose marker was deleted by hand is out of scope.
  - Verification Gap:
    - `[medium]` `[patch]` `Publish`'s failure path has no test - fix applied: `TestFailureLeavesNoGap` (a clashing row; error, no open transaction, counter unchanged, then Seq 1).
    - `[medium]` `[patch]` `ForUser`'s lock has no concurrency test - fix applied: `TestConcurrentFirstCall` (two jobs, 20 users, in step).
    - `[medium]` `[patch]` the create branch of `ForUser` never runs as the unprivileged signed-in user - fix applied: fixture user `ZzFirstCall` (user role, no session row) in `test-sign-in.sh`, and a first-call row in `api.spec.ts` (200, a 22-character epoch, the same epoch on the second call).
    - `[low]` `[patch]` `TestBodyWithSettings` asserts `busy` false against the live connection count with a cap of 8 - fix applied: a cap of 100000.
    - `[low]` `[patch]` four assertions of `TestFromRow` cannot fail (`Payload.Incident` has no such properties) - fix applied: removed; the other four keys stay.
    - `[false]` `[reject]` the instance half of `StateBody` and `EventsBody` is only exercised over HTTP - `api.spec.ts` rows 13 and 14 pin `instance: 1` and `instance:1:status`, and the Rule 22 boundary forbids slot A tests from publishing on `instance`.
    - `[low]` `[reject]` the Health 404 probes of `test-bundle-folder.sh` pass with or without the fix - the 200-to-404 transition is the `(once)` non-Health run, which ran green; the Health run pins the file listing.
    - `[low]` `[patch]` `TestBadCursors` says "before any session is touched" and asserts nothing about it - fix applied: the claim is removed from its doc.
    - `[low]` `[reject]` `ApiClient.events()` has no executed test host - there is no unit-test host under `web/src`; its consumer is Story 2.2.
    - `[low]` `[reject]` the `loading` and `failed` values of `data-snapshot` are not observed - Row 13 pins `loaded`; the other two are one `signal` each.
    - `[false]` `[reject]` pinning tests without a `mutation:` line - Rule 19 asks one demonstrated mutation per AC, and every AC has one; the tests added in this pass carry theirs.
    - `[false]` `[reject]` `api.spec.ts` rows 13 and 14 need the events that `test-sign-in.sh` seeds - by design: `required()` fails loudly without them, and the stack is the test's own.
    - `[low]` `[patch]` (Other findings) the `curl` calls have no time limit - same fix as above.
  - Intent Alignment (divergences reported):
    - `[false]` `[reject]` S1, DW-5 is observed on the non-Health image only when `IRIS_IMAGE` is set - the spec's `(once)` command sets it, and it ran green with the seeded 200 observed.
    - `[medium]` `[patch]` S2, the cleanup keys on the marker it deletes first - same root cause as the first Blind Hunter finding.
    - `[false]` `[reject]` S3, `ApiBase` is not in the intent text - it is in the Spec Change Log (a Rule 22 ruling) and in the spine updates for the lead; `TestSignedOut` and the anonymous HTTP checks pin it.
    - `[false]` `[reject]` S4, row 18 signs in at the API itself - Task 0's own branch ("If not, row 18 uses a POST of the CSP sign-in fields"); measured.
    - `[low]` `[reject]` S5, the unit test's version oracle is the same IPM lookup - `api.spec.ts` row 13 compares with the manifest's version over HTTP.
    - `[false]` `[reject]` S6, rows 20 and 21 test `Prepare` - `Run` calls `Prepare`; the install and bundle-folder scripts run `Run` on the real data directory.
    - `[false]` `[reject]` S7, row 14's marker is on the session events only - the instance event is identified by `condition`, which `api.spec.ts` asserts.
    - `[low]` `[reject]` S8, `events()`, `EventsResponse`, `LiveEnvelope` and `PublicStatus` have no consumer in the page - the spec scopes the client to `state()` and `events()` and the types of the Design Notes; the consumer is Story 2.2.
    - `[false]` `[reject]` S9, `ItemNoun` and `TraceTarget` are Lane B's - the Design Notes table says so ("shared and Lane B's").

## Design Notes

**ADs:**
- AD-3: the public package's allow-list; `Status` overrides `AccessCheck`; the private `DEFAULTGLOBAL`.
- AD-4: one durable session per IRIS user; no client `SessionRef`.
- AD-5: append-only storage.
- AD-12: the event table, `Seq`, `Publish`, payloads, polling, the incident fields.
- AD-13: the applications, the envelope, the public status, the epoch.
- AD-15: the incident's public view; `NoticedAt` filtering stays with `Ownership`.
- AD-18: times.
- AD-19: public settings through the accessor.
- AD-22: tests in throwaways.
- AD-23: `csp/ocutalon-web/`, as amended October 19.
- AD-29 and AD-33: lanes, cross-lane fields.
- Conventions: REST, live events, identifiers, times.

**Event table** (`Publish.TYPES`; each class is `OcuTalon.Live.Payload.<Class>`; lane = publisher's):
- **Lane B:**
  - `chat.message:ChatMessage`
  - `notification:Notification`
  - `phone:Phone`
  - `mailbox:Mailbox`
  - `decision:Decision`
  - `approval:Approval`
  - `turn.step:TurnStep`
  - `reminder:Reminder`
  - `pairing:Pairing`
  - `status:Status`
  - `reset:Reset`
  - `breakfeed.progress:BreakFeedProgress`
  - `guide.state:GuideState`
- **Lane A:**
  - `incident:Incident`
  - `watch.progress:WatchProgress`
  - `check:Check`

**Payload properties.** Types use 0.4's shorthand: Ref 22, Utc 20, Word 32, Name 128, Line 1000, Long unlimited, Int, Bool, Hdr `%Integer`, Usd `%Numeric(SCALE = 6)`. The JSON key is always the property name with a lower-case first letter.

| Class | Properties |
|---|---|
| `ChatMessage` | `Ref` (the turn's), `ClientId` Name, `Channel` Word, `FromGuide` Bool, `State` Word (`queued, running, done`), `Text` Long, `ReplyText` Long, `CreatedAt` Utc, `TraceHeaderId` Hdr, `TraceNamespace` Name |
| `Notification` | `Ref`, `Kind` Word, `Text` Long (rendered by `WebChatOut`), `WhyNow` Line, `DecisionRef`, `IncidentRef`, `ApprovalRef` Ref, `DueAt`, `CreatedAt` Utc |
| `Phone` | `Ref`, `Direction` Word (`in, out`), `Text` Long, `ApprovalRef` Ref, `CreatedAt` Utc |
| `Mailbox` | `Ref`, `Direction` Word, `ItemId` Ref, `Sender` Line, `Subject` Line, `Text` Long, `Unread` Bool, `CreatedAt` Utc |
| `Approval` | `Ref`, `Kind` Word, `State` Word, `IncidentRef` Ref, `ToolName` Name, `Reason` Line, `DryRun` Part.DryRun, `RaisedAt`, `ExpiresAt` Utc, `AnsweredAction`, `AnsweredChannel` Word, `AnsweredBy` Name, `AnsweredAt` Utc, `Result` Word, `FinishedAt` Utc, `TraceHeaderId` Hdr, `TraceNamespace` Name |
| `TurnStep` | `DecisionRef` Ref, `Label` Line |
| `Incident` (A) | `Ref`, `State`, `OpenVariant` Word, `Count`, `NoticeCount` Int, `FirstAt`, `LastAt` Utc, `ItemNoun` Part.ItemNoun, `Cause` Line, `FixSummary` Line, `CauseCategory` Word, `Element` Name, `Fallback` Bool, `FallbackReason` Word, `DecisionRef` Ref, `Groups` list Of Part.IncidentGroup, `Requests` list Of Part.IncidentRequest, `Evidence` Part.IncidentEvidence, `TraceTargets` Part.IncidentTraceTargets |
| `WatchProgress` (A) | `Ref` (the incident's), `Stage` Word; `Parameter STAGES = "noticed,settling,diagnosing"` |
| `Check` (A) | `Ref`, `Kind` Word, `Namespace`, `Production`, `DisplayName` Name, `Stopped` Bool, `NextDueAt`, `LastRunAt` Utc, `Result` Word, `Finding` Line, `TraceHeaderId` Hdr, `TraceNamespace` Name |
| `Reminder` | `Ref`, `Text` Line, `DueAt` Utc, `State` Word, `Late` Bool, `TraceHeaderId` Hdr, `TraceNamespace` Name |
| `Pairing` | `Paired` Bool, `DisplayName` Name |
| `Status` | `Condition` Word, `Active` Bool, `Slots` Part.StatusSlots; `Parameter CONDITIONS = "allowance,dailyCap,noModelKey,heartbeatStalled,telegramPaused,resetSoon"` |
| `Reset` | `NextReset` Utc |
| `BreakFeedProgress` | `State` Word (`sending, sent`), `StartedAt` Utc |
| `GuideState` | `RunEpoch` Int, `Step` Int, `Finished` Bool |

Parts (`OcuTalon.Live.Payload.Part.<Name>`):

| Part (lane) | Properties |
|---|---|
| `ItemNoun` (B) | `One`, `Other` Name |
| `TraceTarget` (B) | `TraceHeaderId` Hdr, `TraceNamespace` Name |
| `IncidentGroup` (A) | `ItemName` Name, `Count` Int, `ErrorSummary` Line, `FirstAt` Utc |
| `IncidentRequest` (A) | `Ref`, `State` Word, `Result` Part.IncidentRequestResult |
| `IncidentRequestResult` (A) | `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted` Int, `Reason` Line |
| `IncidentEvidence` (A) | `SampleHeaderId` Hdr, `SampleError` Line, `Items` list Of Part.IncidentEvidenceItem |
| `IncidentEvidenceItem` (A) | `ItemName` Name, `Count` Int, `FirstAt`, `LastAt` Utc |
| `IncidentTraceTargets` (A) | `Diagnosis`, `Sample`, `FirstFailure` (Part.TraceTarget) |
| `DryRun` (B) | `Affected`, `Resend`, `LeftOut` Int, `Field` Name, `Before`, `After` Line, `ItemNoun` Part.ItemNoun (the keys of `ApprovalRequest.DRYRUNKEYS`) |
| `StatusSlots` (B) | `Limit` Int, `Cap` Usd, `Time` Utc |

**Routes** (`Api` `UrlMap`):

| Method | URL | Call |
|---|---|---|
| GET | `/v1/state` | `State` (200) |
| GET | `/v1/events` | `Events` (200) |
| POST | `/v1/messages` | `NotBuilt` |
| POST | `/v1/approvals/:ref/answer` | `NotBuilt` |
| POST | `/v1/incidents/:ref/dismiss` | `NotBuilt` |
| POST | `/v1/demo/break-feed` | `NotBuilt` |
| POST | `/v1/mailbox/incoming` | `NotBuilt` |
| POST | `/v1/mailbox/samples/:name` | `NotBuilt` |
| POST | `/v1/guide/markers` | `NotBuilt` |
| POST | `/v1/session/end` | `NotBuilt` |
| POST | `/v1/pairing/code` | `Pairing` |
| DELETE | `/v1/pairing` | `Pairing` |

**Error codes and texts** (all `{"error": {"code", "message"}}`):

| Status | Code | Message |
|---|---|---|
| 400 | `bad_cursor` | "The after and afterInstance values must be whole numbers of zero or more." |
| 401 | `signed_out` | "You were signed out. Sign in again to continue." (UX L340) |
| 403 | `no_role` | `OcuTalon.Web.Public.Login.#ERRORNOROLE` |
| 403 | `not_json` | "OcuTalon refused this request because it wasn't sent as JSON." |
| 403 | `no_request_header` | "OcuTalon refused this request because it didn't come from the OcuTalon page." |
| 403 | `wrong_origin` | "OcuTalon refused this request because it came from another site." |
| 404 | `not_found` | "OcuTalon has nothing at this address." |
| 405 | `method_not_allowed` | "This address doesn't accept that kind of request." |
| 500 | `server_error` | "Something went wrong inside OcuTalon. Try again." |
| 501 | `not_built` | "This part of OcuTalon isn't built yet." |

**JSON shapes:**
- `/state`: `{version, instanceZone, epoch, streams: {session, instance}, chat: [], rail: {approvals: [], checks: [], reminders: [], decisions: []}}`.
- `/events`: `{epoch, events: [{seq, stream: "session"|"instance", ts, type, payload}]}`. The session events come first, then the instance ones, each in `Seq` order, at most 200 per stream (`Live.Event` `Parameter MAXEVENTS = 200`).
- `/ocutalon/public/status`: `{ready, nextReset, busy, lastReset, lastResetKind}`, every key always present, `null` when unset.
- TypeScript:
  - `LiveItem<T> = {type: T; payload: LivePayloads[T]}`;
  - `LiveEnvelope<T> = LiveItem<T> & {seq: number; stream: 'session' | 'instance'; ts: string}`;
  - `StateSnapshot.chat: LiveItem[]`, with `rail`'s arrays typed by their payloads.

**`/ocutalon/public` application:** the `Common` values, except:
- `AutheEnabled` 64, `GroupById` "";
- `DispatchClass` `OcuTalon.Web.Public.Status`;
- `CookiePath` `/ocutalon/public/`;
- `MatchRoles` "", `Path` "", `ServeFiles` 0, `PermittedClasses` "", `CSPZENEnabled` 1.

**Rule 22 rulings:**
- **The envelope's `stream`:** what does the browser receive? → `session` or `instance`, the cursor the event advances; the `/state` `streams` keys match. Rejected: the stored `SessionRef`, which the page has no other use for (AD-4 keeps refs out of client requests).
- **Allocating `Seq`:** → a per-stream counter, `^OcuTalonP.LiveEventC(stream)`, mapped private by `OcuTalonP.*`. It is set under the stream's lock inside the transaction, so a rollback undoes it. Purge (2.2) deletes rows, never the counter, so `Seq` never restarts and an open page's cursor stays valid. Rejected: the stream's highest `Seq` plus 1, which restarts after 2.2's 24-hour purge empties a stream; and a `Live.Stream` table, which is one more class, registry row and spine ownership entry for a counter.
- **`Publish` inside a transaction:** → refused. AD-12 says "after the publisher's own change has committed", and a nested commit would release the lock before the outer commit. Rejected: nesting.
- **Payload fields:** → the cross-lane payloads (`incident`, `watch.progress`, `check`, and `pairing` for Lane A's later Telegram card) fix every field the spine and the consumer stories name. Lane B's own payloads fix their key and the fields the epics name, and their owner stories append. Rejected: guessing every display field now.
- **Nested shapes:** → part classes in `OcuTalon.Live.Payload.Part`, so the package's direct classes stay one per type. Each part's lane is its payload's; `ItemNoun` and `TraceTarget` are shared and Lane B's. Rejected: subpackages per type, and flattening the AC's nested fields.
- **Empty values:** → IRIS's defaults (`%JSONNULL` 0). Every TypeScript field is optional, because IRIS omits an empty string and an empty list (Generator.cls:1161, :1076). A full-view replace treats a missing key as empty. Rejected: `%JSONNULL = 1`, which still omits empty lists, so the TypeScript would mix `null` and missing.
- **Keeping TypeScript and ObjectScript in step:** → generated (`payloads.mjs`, `--check` in `build`). The generator also enforces the camelCase key rule. Rejected: a test that parses both, which can drift from the build.
- **The session the API reads:** → `Session.ForUser($Username)` finds or creates the user's one durable row, with `Epoch`. 2.2's `SessionEvents` calls the same method at sign-in. Rejected: building `SessionEvents` now (2.2), and an epoch not kept on the row (AD-13).
- **Version:** → the installed IPM module's `VersionString`, which is the same source as the version gate; `""` without IPM (slot A). Rejected: a version parameter in code, a second place to bump.
- **The snapshot shape:** → `chat` holds `LiveItem`s and `rail` holds four typed arrays, empty in 0.5. 2.2 fills them through `Ownership`.
- **`/events`:** → a 200-per-stream cap, and 400 `bad_cursor` for a missing or invalid cursor. `epoch` is in every poll (16.4 compares it). The rows are read through `Live.Event.Since`, not through `Ownership`: the stream is the ownership.
- **The API's 401:** → the error shape, with no `WWW-Authenticate`. A Basic challenge makes browsers open their own password prompt (REST.cls:310). This changes 0.3's row 4 empty-body assertion (a shared surface).
- **No role:** → 403 `no_role`, and the session is not ended. Rejected: ending it like the shell, which would also sign a trace-only user out of the trace windows.
- **The origin:** → the scheme from `%request.Secure`, plus `HTTP_HOST`, compared case-insensitively. GET, HEAD and OPTIONS are exempt. 16.3 adds the proxy's forwarded scheme.
- **The pairing routes:** → 404 while `Included()` is 0, otherwise 501 (the REST surface).
- **The WebSocket route:** → not in this story (2.11), because it lives outside `/ocutalon/api`.
- **The public status:**
  - a separate application outside the sign-in group, with `UseSession` 0 (S16), `no-store`, and every key present;
  - busy follows AD-13's formula, with the stored cap and reserve, and is false without a valid cap;
  - 16.5 owns the busy header and the splash.
- **DW-5, stale files in the old folder:**
  - At every run, the Web step deletes OcuTalon's own files from `${dataDir}csp/ocutalon/`, and only when that folder's `index.html` holds `<base href="/ocutalon/">`.
  - It deletes `index.html`, `3rdpartylicenses.txt`, and the top-level files matching `^(main|chunk|polyfills|styles)-[A-Za-z0-9]+\.(js|css)(\.map)?$`.
  - Under `assets/`, it deletes each file whose relative path also exists in the new folder, then each folder that is left empty. It never deletes the folder itself or any other file.
  - Rejected: leaving the files, which keeps an upgraded volume's code served without sign-in on the non-Health image; and deleting the whole folder, which is the namespace's default-application folder and may hold files that aren't OcuTalon's.
  - Only pre-release volumes hold the old folder, because no release has shipped it.
- **One incident builder:** → `Payload.Incident.FromRow`, the builder both `IncidentManager` (5.4) and `/state` (2.2) use, so an event and the snapshot can't drift. `/state` lists only the noticed incidents, through `Ownership` (AD-15, 2.2).
- **The page and `/state`:** → 0.5 adds the typed client and loads the snapshot, because no story creates the client and 0.8 waits for the snapshot. The live-event service and the error UI stay 2.2's.
- **Declined here:** `Publish`'s guide hook → 4.2; its `$SYSTEM.Event` signal → 2.11.

**VETO WINDOW items (Rule 22.3), for the lead's FYI:**
- the envelope and no-role 403 rules;
- the unauthenticated `/ocutalon/public` application;
- `Session` rows created by the API;
- deleting old bundle files at start;
- the API's error texts.

**Spine updates for the lead (Rule 20):**
- AD-12: the browser `stream` labels; the per-stream counter that survives purge; `Publish` refuses inside a transaction; part classes under `Live.Payload.Part`; TypeScript generated by `web/scripts/payloads.mjs`.
- REST conventions: the error codes table, 400 `bad_cursor`, 501 `not_built`, a 401 without a Basic challenge.
- AD-13: the `/ocutalon/public` application's properties and the status keys.

**Reuse (Rule 2):**
- `Api` reuses `Shell.HasRole()` and `Login.#ERRORNOROLE`.
- `Status` follows `Shell`'s `AccessCheck` override; it is a separate class because it serves a separate, unauthenticated application.
- The payload classes follow `Live.Payload.Decision`.
- `ForUser` has no sibling.
- `payloads.mjs` follows `tokens.mjs`. If `tokens.mjs` can export its check routine without changing its behaviour, `payloads.mjs` imports it; otherwise the about 8-line loop is copied, because `tokens.mjs` exports nothing today.
- The Web step's public application is built from `Common` plus overrides. `security_app_props` is extended, not copied.
- The new live test uses `lib-live.sh`; the API tests use `StubRequest` and the fixture counter.

**Integration ACs:**
- The page (consumer) loads `/state` and marks `main[data-snapshot=loaded]` (row 13).
- `/events` (consumer of `Publish`) serves the seeded events over HTTP (row 14).
- `Status` (consumer of `Public.Settings`) answers over HTTP (row 19).
- The Web step (consumer of `RemoveOldBundle`) leaves nothing served at the next start (row 23).
- The generator (consumer of the payload classes) keeps `payloads.ts` current (row 7).

**Consumes:**
- 0.2: `Public.Settings`, the registry, `lib-live.sh`.
- 0.3: `Shell`, `Login`, `Step.Web`, `test-sign-in.sh`, the Angular shell.
- 0.4: `Session`, `Incident`, `Data.Time`, `Bridge.Ids`, `Telegram.In.Included()`, `Live.Payload.Decision`, `Test.Contract`.

**Consumed-by:**
- **0.6:** the stub items' publishers-to-be; `Ownership` stubs.
- **0.7:** CI runs the new tests and `--check`.
- **0.8:** `data-snapshot`.
- **2.2:** `ForUser` from `SessionEvents`; filling `chat`/`rail`; the live-event service on `ApiClient`; `Purge` (rows only, never the counter).
- **2.4–2.10:** the publishers of their types.
- **2.9:** trace URLs.
- **2.11:** the WebSocket, and the signal in `Publish`.
- **4.2:** the guide hook and `GuideState`'s fields.
- **5.3–5.6 and 6.1:** `Incident` (`FromRow`, the groups, requests, evidence and targets), `WatchProgress`, `Check`.
- **8.3:** `Reminder`.
- **10.3:** the pairing routes, `Pairing`.
- **16.3:** the forwarded scheme in the origin check.
- **16.4:** epoch changes.
- **16.5 and 16.8:** `/ocutalon/public/status`.

**Ledger inbox:** DW-5 is addressed in rows 20–24, the Web step and `module.xml` tasks, the DW-5 ruling, and AC4.

**Size, and where to split it (for the lead):** this story has several goals and is oversized. The clean line:
- **0.5:** live events, the payloads and generator, `Session.ForUser`, the API and the Angular client; rows 1–18.
- **0.10:** `/ocutalon/public` with `Status`, and DW-5 (the bundle move and cleanup, `test-bundle-folder.sh`, and the path updates in `module.xml`, `Step.Web`, `lib-live.sh`, `test-install-*.sh` and `test-compose-file.sh`); rows 19–24.

## Verification

**Commands:**
- `(loop)` `iris_server_info` (`server: ocutalon-slot-a`). Expected: build 154.
- `(loop)` `iris_doc_load` with `server: ocutalon-slot-a`, `namespace: OCUTALON`, `compile: true`, `flags: "ck"`, as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- `(loop)` `iris_execute_tests`, one class per call, each waiting for the last:
  - new: `OcuTalon.Test.Live.Publish`, `.Test.Live.Payloads`, `.Test.Data.Session`, `.Test.Web.Api`, `.Test.Web.Status`;
  - updated or kept green: `.Test.Web.Install`, `.Test.Web.Shell`, `.Test.Web.SignIn`, `.Test.Data.Tables`, `.Test.Msg.Contracts`, `.Test.Contract.Ac`, `.Test.Contract.Checker`, `.Test.Install.PrivateData`, `.Test.Install.Registry`, `.Test.Data.PublicSettings`.
  - Expected: 0 failed. No `Zz` session, stream, incident, temp folder or public-setting change is left behind.
- `(loop)` `node --test web/scripts/`. Expected: pass.
- `(loop)` `npm --prefix web run build` (`timeout: 600000`). Expected: exit 0, and `git status --short web/` unchanged.
- `(loop)` One call each: `bash docker/tests/test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-pinned-sources.sh`. Expected: exit 0.
- `(loop)` `bash docker/tests/test-web-build.sh` (`timeout: 600000`). Expected: exit 0.
- `(loop)` `bash docker/tests/test-sign-in.sh` (`timeout: 600000`). Expected: exit 0, and no `ocutalon-t03-*` project left.
- `(loop)` `bash docker/tests/test-bundle-folder.sh` (`timeout: 600000`). Expected: exit 0 (Health).
- `(loop)` `bash docker/tests/test-install-start.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` `bash docker/tests/test-install-upgrade.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 bash docker/tests/test-bundle-folder.sh` (`timeout: 600000`). Expected: exit 0, with the seeded 200 observed before the restart.
- `(once)` `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 bash docker/tests/test-sign-in.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` Load, compile and export the trees on slot A again, then `git status --short` and `git diff --stat`. Expected: only the files under Tasks, and no storage-block change after a second round trip.

**Shared surfaces:**
- the `Session` table (the `Epoch` slot; `Test.Data.Tables`' contract);
- `src/short-names.tsv` and the `Registry` XData (23 rows);
- `Test.Contract.ORACLES`, which `Checker` sweeps;
- `Step.Web.Definitions` (four applications), `check_security`, `security_app_props` and `Test.Web.Install`;
- the durable bundle path (`module.xml`, `test-install-start.sh` row 14, `test-install-upgrade.sh`, `test-compose-file.sh`);
- the API's answers without a session or route (`sign-in.spec.ts` row 4, `shell.spec.ts` rows 10 and 11);
- `web/package.json`'s `build`, `app.config.ts`'s providers, and `app.ts`'s `main`;
- `^OcuTalonP.LiveEventC`, and the `instance` stream (throwaways only);
- the public settings on slot A (`Test.Web.Status` restores them);
- the throwaway users `ZzNoRole` and `ZzTraceOnly`.

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate** (Rule 19: apply, see red, revert, `git status --short` unchanged):
- AC1:
  - `Publish` without the lock → row 3 red (a duplicate or a gap);
  - `watch.progress` dropped from `TYPES` → row 4 red;
  - `Session.ForUser` always creates → row 8 red;
  - `EventsBody` ignores `after` → row 10 red;
  - `EnvelopeError` ignores `Origin` → row 11 red;
  - a route removed → row 12 red;
  - `IsBusy` uses `>` → row 19 red;
  - `RemoveOldBundle` ignores the marker → row 21 red.
- AC2: `Incident.ItemNoun`'s `%JSONFIELDNAME` set to `item_noun` → `payloads.mjs` exits 1 (row 7). A renamed `Reminder.DueAt` without regenerating → `--check` red, and `test-web-build.sh` red.
- AC3:
  - `StateBody` omits `epoch` → row 13 red;
  - `Since` ignores the cursor → row 14 red;
  - `OnPreDispatch` skips the envelope → row 15 red;
  - `Status.AccessCheck` removed → row 19 red (403).
- AC4: `Run` without `RemoveOldBundle`, on non-Health → row 23 red (200 after the restart).
- AC5: `Step.Web` `Path` back to `csp/ocutalon/` → rows 22 and 24 red.
- AC6: one slot removed by hand from `Session`'s storage block → the export differs.

**Shared surfaces, additions:** the public database's classes (`Web.Public.Status`, `Web.Public.ApiBase`), which `after-start.sh` lists from the shipped files and the `public-classes` step checks; `Test.Contract.ORACLES` (now four oracles).

**Results (implement pass, October 19).** Every command below ran on the final tree unless a note says otherwise.

Task 0 (measured; throwaway Health stack built from the tree, `curl` with a cookie jar):
- Trace-only user through the sign-in group: no. A user signed in at `/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen` holds the trace application's cookie (path `/ocutalon/trace/ocutalon/`) and `IRISSessionToken`, not the cookie the API reads, so `GET /ocutalon/api/v1/state` with that jar is a request without a session (401 `signed_out`). The route that works, and the one row 18 uses: a POST of `IRISUsername`, `IRISPassword` and `IRISLogin` to `/ocutalon/api/v1/state` gives 403 `no_role` with `ERRORNOROLE`'s text, and the session stays open (a later GET is 403 `no_role`, and the trace window opens).
- `curl` sign-in: works. GET `/ocutalon/` (200, the sign-in form, no hidden input), POST of the three fields with the jar (303 to `/ocutalon/`), GET `/ocutalon/` serves the Angular `index.html`. Without a session `/ocutalon/<main>.js` is the sign-in page; signed in it is the script, byte for byte.
- Overriding `Api.Login` and the group sign-in: an override inside `OcuTalon.Web.Api` breaks the request without a session (bodiless 404, see the Spec Change Log); the same override in the public superclass `ApiBase` answers 401 `signed_out` without `WWW-Authenticate`, and the group sign-in is kept: with the `CSPSESSIONID-...` cookie removed from the README jar (`CSPBrowserId` left), `GET /v1/zz` is 404 `not_found`, which is shell row 10's case.
- `HTTP_HOST` is present (`127.0.0.1:<port>`): a POST with `Origin: http://127.0.0.1:<port>` and a valid envelope passes the origin check (501), another Origin or none gives 403 `wrong_origin`.
- Slot A: `%JSONExportToString` omits an empty list (`items` is absent after `Clear()`), omits an empty string, and exports `false` for a `%Boolean` whose `InitialExpression` is 0.
- Also measured: the README account gets SQLCODE -99 from a dynamic `SELECT` on `Data.Session` (see the ruling); the web gateway keeps the answer to a URL after the file changes; on the non-Health image the default application `/csp/ocutalon` (`Path` `/durable/iris/csp/ocutalon`, `ServeFiles` 2) serves a seeded `index.html` and `main-*.js` with 200 and no session (DW-5's exposure), until the restart removes them; on the Health image there is no such application and the same probes are 404.
- `$TLevel` is 0 in a business host's `OnMessage` `(inference)`; not measurable before 0.6.

Commands:
- `(loop)` `iris_server_info` (slot A): build 154.
- `(loop)` `iris_doc_load` with `compile: true`, `flags: "ck"`, bridge then ocutalon: 16 and 110 documents, 0 errors.
- `(loop)` `iris_execute_tests`, one class per call, all 0 failed: Live.Publish 3, Live.Payloads 4, Data.Session 2, Web.Api 8, Web.Status 5, Web.Install 9, Web.Shell 5, Web.SignIn 9, Data.Tables 5, Msg.Contracts 6, Contract.Ac 6, Contract.Checker 5, Install.PrivateData 5, Install.Registry 11, Data.PublicSettings 5 tests. Afterwards slot A holds no session, event, counter, incident, `/zz` application or public setting that the tests made.
- `(loop)` `node --test web/scripts/`: 40 tests pass (14 new, in `payloads.test.mjs`).
- `(loop)` `npm --prefix web run build`: exit 0; `git status --short web/` is unchanged by the build.
- `(loop)` `test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-pinned-sources.sh`, `test-web-build.sh`: each exit 0.
- `(loop)` `test-sign-in.sh`: exit 0 (21 Playwright tests: the 8 of `api.spec.ts` and Story 0.3's 13); no `ocutalon-t03-*` project left.
- `(loop)` `test-bundle-folder.sh` (Health): exit 0.
- `(loop)` `test-install-start.sh`: exit 0.
- `(once)`, run because every `(loop)` command was green: `test-install-upgrade.sh` exit 0; `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 test-bundle-folder.sh` exit 0, with the seeded 200 observed before the restart; `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 test-sign-in.sh` exit 0.
- `(once)` round trip on slot A: the trees were loaded and compiled again after the last mutation and exported (`iris_doc_export`, prefix `OcuTalon`, 126 classes) into a scratch folder: every file equals the tree byte for byte, the storage blocks of `Session` and `Live.Event` included, so no tracked file would change. (The export went to a scratch folder, not over the tree.)

Mutations (Rule 19; each applied to a scratch copy loaded on slot A or the throwaway, or, where the live script builds from the tree, to the tree with a backup; reverted; `git status --short` and `git diff --stat` unchanged afterwards):
- mutation: `Publish` without the lock (the `Lock` line removed) -> `Test.Live.Publish` `TestSeqUnderLoad` red ("Key not unique", fewer than 100 rows). With the first version of the test (the two jobs started one after the other) this mutation stayed green; the start barrier fixed that.
- mutation: `watch.progress` dropped from `TYPES` -> `Test.Live.Payloads` `TestEventTable` red.
- mutation: `Session.ForUser` never finds the row (always creates) -> `Test.Data.Session` `TestFindsOrCreates` red.
- mutation: `EventsBody` passes cursor 0 to `Since` -> `Test.Web.Api` `TestEventsBody` red.
- mutation: `EnvelopeError` without the Origin rule -> `Test.Web.Api` `TestEnvelopeError` red.
- mutation: the `/v1/guide/markers` route removed -> `Test.Web.Api` `TestRoutes` red.
- mutation: `IsBusy` with `>` -> `Test.Web.Status` `TestIsBusy` and `TestBodyWithSettings` red.
- mutation: `RemoveOldBundle` without the marker check -> `Test.Web.Install` `TestRemoveOldBundle` red.
- mutation: `Incident.ItemNoun`'s `%JSONFIELDNAME` set to `item_noun` -> `payloads.mjs` exits 1 naming `Incident.cls:27` (and `npm --prefix web run build` exits 1); `payloads.test.mjs` pins the same on a copy.
- mutation: `Reminder.DueAt` renamed without regenerating -> `payloads.mjs --check` exits 1 ("payloads.ts is stale") and `test-web-build.sh` red ("npm --prefix web run build failed").
- mutation: `StateBody` without `epoch` -> `api.spec.ts` row 13 red.
- mutation: `Live.Event.Since` passes cursor 0 -> `api.spec.ts` row 14 red.
- mutation: `OnPreDispatch` without the envelope check -> `api.spec.ts` row 15 red (the `text/plain` call answers 501, not 403).
- mutation: `Status.AccessCheck` removed -> `api.spec.ts` row 19 red (not 200).
- mutation: the Web step without `RemoveOldBundle`, non-Health image -> `test-bundle-folder.sh` row 23 red (200 for `index.html`, `main-*.js` and `3rdpartylicenses.txt` after the restart, and the old folder still holds the bundle).
- mutation: the shell application's `Path` back to `csp/ocutalon/` -> `test-install-upgrade.sh` red at `check_security` (row 24). The `FileCopy` target back to `csp/ocutalon/` -> `test-install-start.sh` aborts at row 1, because `BundleCheck` refuses the start; row 22's own lines were not reached.
- mutation: the slot for `TraceRef` removed from `Session`'s storage block -> the export differs (the compiler adds `TraceRef` as slot 7, where the committed block has slot 3); the tree was loaded again afterwards.

Not done, or open:
- AC5's row 22 mutation reaches the first-start abort, not row 22's own assertions.
- The Task 0 results hold for build 154 as measured; the browser (Playwright Chromium) was used for rows 13 and the Story 0.3 specs, `curl` for the measurements above.

**Results (review pass, October 19).** Every command ran on the final tree.
- `(loop)` `iris_server_info` (slot A): build 154. `iris_doc_load` with `compile: true`, `flags: "ck"`: 16 and 110 documents, 0 errors.
- `(loop)` `iris_execute_tests`, one class per call, all 0 failed: Live.Publish 5, Live.Payloads 4, Data.Session 3, Web.Api 8, Web.Status 5, Web.Install 9, Web.Shell 5, Web.SignIn 9, Data.Tables 5, Msg.Contracts 6, Contract.Ac 6, Contract.Checker 5, Install.PrivateData 5, Install.Registry 11, Data.PublicSettings 5 tests. Slot A holds no session, event, incident or counter afterwards.
- `(loop)` `node --test web/scripts/`: 41 tests pass. `npm --prefix web run build`: exit 0, `git status --short` unchanged. `test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-pinned-sources.sh`, `test-web-build.sh`: each exit 0.
- `(loop)` `test-sign-in.sh`: exit 0, 22 Playwright tests (9 of `api.spec.ts`). `test-bundle-folder.sh` (Health): exit 0, 22 checks. `test-install-start.sh`: exit 0. No `ocutalon-t0*` project is left.
- `(once)`, after the last patch: `test-install-upgrade.sh` exit 0; `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 test-bundle-folder.sh` exit 0 with the seeded 200 observed for `index.html` and `main-*.js` before the restart; the same image with `test-sign-in.sh` exit 0 (22 passed).
- `(once)` round trip: the trees were loaded and compiled on slot A, then exported (`iris_doc_export`, prefix `OcuTalon`, 126 classes) into a scratch folder: every file equals its file in the tree byte for byte, so the storage blocks of `Session` and `Live.Event` do not change.

Mutations of the review pass (Rule 19; applied to the tree with a backup and loaded on slot A, or, for the live script, built from the tree; reverted; every file's checksum equals its backup afterwards):
- mutation: `RemoveOldBundle` deletes `index.html` first (the old order) -> `Test.Web.Install` `TestRemoveOldBundleKeepsAndFails` red ("index.html stays, so the next start repeats the removal", "removes the rest of OcuTalon's files").
- mutation: `LastSeq` without the shared lock -> `Test.Live.Publish` `TestLastSeqWaitsForAnOpenPublish` red ("the reader is still waiting while the publisher's transaction is open").
- mutation: `Publish` without `If $TLevel > 0 TROLLBACK` -> `Test.Live.Publish` `TestFailureLeavesNoGap` red ("no transaction is left open").
- mutation: `Session.ForUser` without its lock -> `Test.Data.Session` `TestConcurrentFirstCall` red. With the first version of the test (one user, two jobs) this mutation stayed green; the 20 users with a barrier before each fixed that.
- mutation: the allow-list scan of `Test.Web.Status` without upper-casing the source -> `TestReferencesOnlyThePublicAllowList` red.
- mutation: `payloads.mjs` reads only lines that start with `Property` in that case and column -> `payloads.test.mjs` "a property that is indented or not written as Property" red.
- mutation: the create branch of `Session.ForUser` runs a `SELECT` on the table, prepared with the privilege check, before it creates the row -> `api.spec.ts` "rows 13 and 14: a user's first /state creates its session..." red (500); rows 13 and 14 of the README account stayed green, which is the gap that the new test closes. Measured with `test-sign-in.sh` on the test's first form ("row 13: the first /state of a user without a session row creates one"); the code review merged it with the cross-user poll test, and the merged test opens with the same assertions.
- measured, no mutation: `ApiBase.Login` without a language guard answers 401 `signed_out` with the body for a request that carries `Accept-Language: en-US,en;q=0.9` (`api.spec.ts` row 17 green with the guard removed), so the guard was not added.

**QA stage** (October 19; slot A build 154 and throwaway projects `ocutalon-t02s`, `t03` and `t05`; nothing committed). The implement and review passes' tests were read against the Tasks & Acceptance and the matrix, and the gaps below were closed. Each mutation was applied to the tree (or, for slot A, to the tree and loaded), shown red, reverted from a backup, and the working tree's digest (every tracked and untracked file) was equal to the one before the mutation.

Tests added (QA) (no new file; the test cases are new methods or specs in these files):
- `web/e2e/api/api.spec.ts` (QA), run through `test-sign-in.sh` (30 Playwright tests, 8 more than before):
  - `row 15: the browser envelope`, a describe block of 7 tests with one signed-in context: the whole envelope; only the Content-Type wrong (`text/plain`, `application/x-www-form-urlencoded`, `application/jsonx`); only `X-OcuTalon-Request` wrong (absent, `0`, `true`, `11`); only the Origin wrong (absent, another site, `null`, `https`, a suffixed host, a suffixed port); two or three rules broken (the first in the order names the refusal); `DELETE`, `PUT`, `PATCH` and an unknown route are refused for the envelope before the route; a `GET` needs none. Every refusal checks the status, the code and the exact text.
  - `row 14: the two cursors are independent...`: `(2,0)` gives the instance event, `(0,1)` the session events, `(1,0)` and `(001,00)` give session first, 15 digits past the end is empty, five more `bad_cursor` forms (16 digits, `+1`, `1e2`, `0x1`).
  - `row 14: a user's poll holds the instance events and not another user's session events` (AD-4).
  - Extended: row 16 (the `DELETE` through the shared helper), row 17 (anonymous `POST` and `DELETE` are 401 `signed_out` whatever the envelope), row 18 (the trace-only user is refused `no_role` first for a `POST` with a whole or a broken envelope, a `DELETE` and an unknown route, then still has its session: `GET` answers 403, not 401, and the trace window opens).
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` (QA): `TestNoRoleIsRefusedFirstAndKeepsTheSession` (`OnPreDispatch` for a `GET`, a `POST` with a whole and with no envelope, and a `DELETE` with the wrong origin, as the test process, which holds no OcuTalon role: 403, `no_role` with the sign-in page's text, `continue` 0, `%session.EndSession` 0; it says so and stops in a process that holds the role), `TestErrorTexts` (every message of the error table), and `TestEventsBody` extended (the cap counts from the cursor: after 10 gives 11 to 210; past the end is empty; the instance cursor does not move the session's).
- `src/ocutalon/cls/OcuTalon/Test/Web/StubRequest.cls` (QA): `MakeCall`, a stand-in request with the method, Content-Type, the three envelope headers and `Secure`.
- `src/ocutalon/cls/OcuTalon/Test/Live/Publish.cls` (QA): `TestSeqUnderLoad` hardened (see below).

Gaps shown open before they were closed (the existing test stayed green):
- `Events` passes `after` as the instance stream's cursor: `api.spec.ts` "row 14: /events serves the seeded events by cursor" green (its cursors `(0,0)`, `(2,1)` and `(1,1)` cannot tell the two cursors apart).
- `Events` reads the README account's session whatever the signed-in user is: the same test green (it signs in as that account).
- `Publish` without mutual exclusion: `TestSeqUnderLoad` was red in 1 of 2 runs (the jobs' 50 publishes each ran one after the other often enough that no two met). It is now in lockstep, one round at a time, and red in 6 of 6 runs.
- The text of each envelope refusal was not compared (the old row 15 asserted only that a message exists), so swapped texts passed; not mutation-shown.

Job-based tests (run three times in a row each, on the final code): `Test.Live.Publish` 5 of 5 on every run (`TestSeqUnderLoad` 58 to 71 ms, `TestLastSeqWaitsForAnOpenPublish` about 1.1 s) and `Test.Data.Session` 3 of 3 on every run; stable. Hardened all the same: `TestSeqUnderLoad` runs in lockstep (round `i` starts when both jobs have reached it), asserts that the jobs stayed in step, and on a timeout tells the jobs to stop and waits for them, so a failing run no longer leaves a job publishing after the clean-up (a run that timed out left 52 rows, which were removed by hand). Detection of the race mutations: `TestSeqUnderLoad` red 6 of 6 (lockstep), `TestLastSeqWaitsForAnOpenPublish` red 3 of 3, `TestConcurrentFirstCall` (`ForUser` without its lock) red 3 of 3. `TestLastSeqWaitsForAnOpenPublish` still asserts a negative after a fixed `Hang 1` and relies on the reader's 5-second lock wait to outlast it; a stall of more than 4 seconds in the test process could make it fail on a very loaded host.

Mutations demonstrated (QA, Rule 19; mutations_demonstrated=18, which are 16 distinct mutations, two of them shown on slot A and again over HTTP):
- mutation: AC1, `OnPreDispatch` ends the session on `no_role` (`Set %session.EndSession = 1`) -> `Test.Web.Api` `TestNoRoleIsRefusedFirstAndKeepsTheSession` red ("the session is not ended", four cases).
- mutation: AC1, `OnPreDispatch` checks the envelope before the role -> the same test red ("no_role with the sign-in page's text, not an envelope code" for the broken-envelope `POST` and the `DELETE`).
- mutation: AC1, `Data.Session.ForUser` without its lock -> `Test.Data.Session` `TestConcurrentFirstCall` red ("every user has one row, and both jobs got its Ref"), 3 of 3 runs.
- mutation: AC1, `Publish` locks a per-job name instead of the stream's (no mutual exclusion) -> `Test.Live.Publish` `TestSeqUnderLoad` red ("Key not unique", "100 rows"), 6 of 6 runs with the lockstep test.
- mutation: AC1, `LastSeq` takes its shared lock on a per-job name -> `Test.Live.Publish` `TestLastSeqWaitsForAnOpenPublish` red ("the reader is still waiting while the publisher's transaction is open"), 3 of 3 runs.
- mutation: AC1, `Status.SetOrNull` writes no key for an unset value -> `Test.Web.Status` `TestBodyWithoutSettings` red ("exactly the five keys", the three nulls and the JSON).
- mutation: AC2, the JSON key check of `payloads.mjs` disabled (`if (false && json[1] !== expected)`) -> `node --test web/scripts/` red in "a key that is not the property name with a lower-case first letter" and "Incident.ItemNoun with the key item_noun is refused" (39 of 41 pass).
- mutation: AC3, seven applied together to the tree and run once through `test-sign-in.sh` (9 of 30 Playwright tests red, the 21 others green, including the old row 14 test): the Content-Type rule removed from `EnvelopeError` -> "only the Content-Type is wrong" red; the `X-OcuTalon-Request` rule removed -> "only the X-OcuTalon-Request header is wrong" red; the Origin rule removed -> "only the Origin is wrong" red (each of these three tests breaks one rule and no other, so the red can only come from its own rule; "more than one rule broken" and "every state-changing method" go red as well); the instance cursor taken from `after` -> "row 14: the two cursors are independent" red; `Events` reading `ForUser("ocutalon")` -> "row 14: a user's poll holds the instance events..." red (now part of "rows 13 and 14: a user's first /state creates its session...", where the code review showed the same mutation red again); `no_role` ending the session -> "row 18: a trace-only user gets 403 no_role..." red (the next call answers 401 `signed_out`); `SetOrNull` writing no key -> "row 19" red (`ready` and `busy` only).
- mutation: AC4, `Step.Web.Prepare` without `RemoveOldBundle`, Health image -> `test-bundle-folder.sh` red at "/durable/iris/csp/ocutalon holds '. ./3rdpartylicenses.txt ./assets ...', wanted only ./zz-keep.txt and ./assets/zz/keep.txt" (one FAIL; the 404 probes pass on Health, as designed). The non-Health image's 200 after the restart is the implement pass's mutation.
- mutation: AC5 (row 22, byte for byte), `Step.Web` `OLDBUNDLEFOLDER` set to `csp/ocutalon-web/` (the cleanup deletes the new bundle) -> `test-install-start.sh` red at "row 14: /durable/iris/csp/ocutalon-web/ differs from /opt/ocutalon/src/ocutalon/csp/" and "row 14: index.html differs from the image's, or is missing"; row 1's log and step list pass, so the first start gets past the abort and reaches row 22's own assertions (the restart then does not end ready).
- mutation: AC5 (row 22, old folder), `src/module.xml` also copies `index.html` to `${dataDir}csp/ocutalon/index.html` and `Prepare` skips `RemoveOldBundle` -> `test-install-start.sh` red at "row 22: /durable/iris/csp/ocutalon/index.html exists" and nowhere else (every other check passes). The second `FileCopy` of the whole folder is refused by IPM ("Resource 'ocutalon/csp/' is listed more than once"), so the copy is of the one file.
- mutation: AC6, the `Payload` slot removed by hand from `Live.Event`'s storage block -> the export of the compiled class differs from the edited file (the compiler adds the slot back, so the export equals the committed file); loaded again from the committed file, the exports of `Live.Event` and `Data.Session` equal the tree byte for byte.

The 200-event cap of the instance stream and "session first" with more than 200 events: pinned by `TestEventsBody` since the code review, with a fixture session's stream passed to `EventsBody` in place of the instance stream (see the code review's results below), so no slot A test publishes on `instance`.

Final state: `Test.Web.Api` 10 of 10, `Test.Live.Publish` 5 of 5 (three runs), `Test.Data.Session` 3 of 3, `Test.Web.Status` 5 of 5, `Test.Web.Shell` 5 of 5 on slot A; `node --test web/scripts/` 41 of 41; `test-sign-in.sh` exit 0 with 30 Playwright tests; `test-boundaries.sh` and `test-storage.sh` exit 0. Slot A holds no event, session, counter or stream the tests made, and no `ocutalon-t0*` project, volume or image is left.

**Results (code review, October 19).** Slot A (`ocutalon-slot-a`, port 52790, build 154, namespace `OCUTALON`), one class per call; the throwaway through `lib-live.sh`. Each mutation was applied to the tree from a saved copy, loaded on slot A (or built by `test-sign-in.sh`), seen red, and reverted; the files' checksums equal the saved copies afterwards, and `Live/Event.cls` equals HEAD.
- Loaded and compiled with `ck`, one document per call: `Test/Web/Api.cls`, `Test/Web/Status.cls`, `Web/Public/Status.cls`, `Web/Api.cls`, `Test/Live/Publish.cls`, `Test/Data/Tables.cls`, `Install/Step/Web.cls`; 0 errors.
- `iris_execute_tests`, all 0 failed: `Test.Web.Status` 6, `Test.Web.Api` 10, `Test.Live.Publish` 6, `Test.Data.Tables` 5, `Test.Web.Install` 9, `Test.Web.SignIn` 9. Slot A holds no `zz` session, event row, index entry or counter afterwards.
- `test-sign-in.sh`: exit 0, 29 Playwright tests (the merged first-call test replaces two); no `ocutalon-t03-*` project left. `test-boundaries.sh` and `test-storage.sh`: all rules pass. `bash -n docker/tests/test-bundle-folder.sh`: OK (a comment changed).
- Round trip: the 126 `OcuTalon` classes exported from slot A equal the tree byte for byte (`src/ocutalon/cls` and `src/bridge/cls`).

Mutations of the code review (Rule 19):
- mutation: `Web.Public.Status` without `ReportHttpStatusCode` (the class before the patch) -> `Test.Web.Status` `TestErrorSendsNoCause` red ("and no body, so the cause is not sent").
- mutation: `EventsBody` gives the instance stream what is left of one shared cap (`MAXEVENTS - events.%Size()`) -> `Test.Web.Api` `TestEventsBody` red ("with both streams behind, 200 of each").
- mutation: `EventsBody` without a cap on the instance stream -> `Test.Web.Api` `TestEventsBody` red ("with both streams behind, 200 of each", "the instance stream's cap counts from its own cursor").
- mutation: `Live.Event.Stream` without `COLLATION = "EXACT"` -> `Test.Live.Publish` `TestStreamsThatDifferOnlyInCase` red ("Key not unique" on `StreamSeqIndex`, "each stream reads only its own event").
- mutation: `Events` reads `ForUser("ocutalon")` whoever is signed in -> `api.spec.ts` "rows 13 and 14: a user's first /state creates its session, and its poll holds the instance events and not another user's session events" red (the poll held `session:1`, `session:2` and `instance:1`), the other 28 green; through `test-sign-in.sh`.
- Not shown by a mutation, each a direct correction checked by the green runs above: the counter check of `AssertRefused`, the `OcuTalon.Live` scope of `TestEveryTableIsRegistered`, `Do ... %ToJSON()` in `State` and `Events`, the parameters that `Api` now inherits from `ApiBase`, the removal of `post()`, and the two comments.

## Auto Run Result

Status: done
Blocking condition: none

**Implementation summary (October 19).**
- Live events: `Live.Event` (private, exact-collated stream, unique `(Stream, Seq)`), `Live.Publish` (the 16-type table, per-stream counter under a lock held across insert and commit, refused inside a transaction; `LastSeq` waits for an open publish), 15 type classes and 10 part classes under `Live.Payload`, and `web/scripts/payloads.mjs` with the committed `web/src/app/live/payloads.ts` and `--check` in `npm run build`.
- REST: `Data.Session` gains `Epoch` and `ForUser`; `Web.Api` has the 12 routes, the role check, the browser-envelope check, the error shape, a real `/state` and `/events`; the 401 `signed_out` comes from the new public `Web.Public.ApiBase`. The page loads the snapshot through `ApiClient` and sets `main[data-snapshot]`.
- Public status and DW-5: `Web.Public.Status` and the `/ocutalon/public` application (four applications now); the bundle lives in `csp/ocutalon-web/`; `Step.Web` removes OcuTalon's own files from `csp/ocutalon/` at every start (`index.html` last).

**Files changed.** `src/ocutalon/cls/OcuTalon/`: `Live/Event.cls`, `Live/Publish.cls`, 25 `Live/Payload/**` classes, `Data/Session.cls`, `Web/Api.cls`, `Web/Public/ApiBase.cls`, `Web/Public/Status.cls`, `Install/Step/Web.cls`, and the tests `Test/Live/{Publish,Payloads}.cls`, `Test/Data/Session.cls`, `Test/Web/{Api,Status,Install}.cls`, `Test/Data/Tables.cls`, `Test/Contract.cls`. `src/module.xml`, `src/short-names.tsv`. `web/`: `scripts/payloads.mjs`, `scripts/payloads.test.mjs`, `scripts/tokens.mjs` (exports `emitOutputs`), `package.json`, `src/app/{live,api}/`, `app.config.ts`, `app.ts`, `e2e/api/api.spec.ts`, `e2e/sign-in/sign-in.spec.ts`. `docker/tests/`: `lib-live.sh`, `test-sign-in.sh`, `test-install-start.sh`, `test-install-upgrade.sh`, `test-compose-file.sh`, `test-bundle-folder.sh` (new).

**Review (one pass, four layers).** 43 findings: high 0, medium 9, low 22, false 12.
- Patched (5 medium entries, 7 low entries): `RemoveOldBundle` now deletes `index.html` last; `LastSeq` waits under a shared lock for an open publish; tests for `Publish`'s failure path, `ForUser`'s lock under two jobs, and the first `/state` of a user with no session row (`ZzFirstCall`); `ForUser` keeps the status of `%OpenId`; the allow-list scan is case-insensitive and flags dynamic dispatch; the generator refuses an indented or lower-case property line; `--max-time` on the `curl` calls; the busy assertion no longer reads the live connection count; four vacuous assertions removed; one doc claim removed.
- Deferred (1, low): the `ApiClient` envelope interceptor for the first POST (see `deferred:`).
- Rejected with reasons (in the Review Triage Log): the language guard for `ApiBase.Login` (measured not needed), cache headers (measured), the licence-connection claim for the public status (AD-13, S16), the closed catalogs, the user-name length, the TLS-proxy origin, the default application, the descriptive divergences of the intent audit, and the coverage notes that the `(once)` runs or Rule 19's per-AC scope already answer.
- Follow-up review recommended: true. Unverified risks: (1) `LastSeq` now waits on a lock, so a publisher that holds a stream's lock for more than 5 seconds makes `/state` answer 500; nothing in this story holds a lock that long, and the first publishers (2.x) should keep the publish call short and outside long transactions; (2) the three job-based tests (`TestSeqUnderLoad`, `TestLastSeqWaitsForAnOpenPublish`, `TestConcurrentFirstCall`) depend on `Job` start-up and `Hang`, with 60 to 120 second ceilings; they passed on every run here, and `TestConcurrentFirstCall`'s red was shown on a mutation but is a race, so it can in principle stay green against the no-lock mutation.

**Verification performed.** See `## Verification`: the implement-pass results, the review-pass results, and the mutations. Every `(loop)` command and every `(once)` command is green on the final tree; the trees round-trip through slot A byte for byte.

**Residual risks and items for the lead.**
- Spine updates (Rule 20) are the lead's: the Design Notes list, and the Spec Change Log adds AD-3 (`ApiBase` in `OcuTalon.Web.Public`), AD-13 (the 401 from `ApiBase`; the signed-in user's two queries prepared without the SQL privilege check) and AD-12 (`Stream` exact-collated; `LastSeq` waits for an open publish).
- VETO WINDOW items (Rule 22.3), for the FYI: the browser-envelope and no-role 403 rules; the unauthenticated `/ocutalon/public` application; `Session` rows created by the API; deleting old bundle files at start; the API's error texts; the new class `OcuTalon.Web.Public.ApiBase` in the pre-sign-in database (static 401 body only); `Session.ForUser` and `Live.Event.Since` prepared without the SQL privilege check (fixed query text, parameters only; no grant to `OcuTalonUser` was added).
- The spec is oversized and has several goals; the Design Notes name the split line (0.5 and 0.10). It was implemented whole, as dispatched.
- AC5's row 22 mutation (`FileCopy` target back to `csp/ocutalon/`) stops at the first-start abort of `BundleCheck`, not at row 22's own lines.

**Planning summary (October 19).**
- The spec is planned against the committed `epic-0-context.md`, Story 0.4's spec for continuity, the spine (AD-3, 4, 12, 13, 15, 19, 23, 29 and 33, the Conventions, the event table and the REST surface, read by line range), and `epics.md` (0.5, 0.8, 2.2, 16.5 and 16.8).
- Slot A was probed read-only: build 154; no reserved SQL word among the new persistent names; `%IPM` absent; zero instance connections; zone `UTC`.
- No intent gap was found, and no AC contradicts an AD.
- DW-5 is addressed in rows 20–24 and AC4. The Rule 22 ruling on stale files is: delete only OcuTalon's own files from `csp/ocutalon/`, and only when its `index.html` has the OcuTalon marker.
- The Rule 22 rulings and the VETO WINDOW items are under Design Notes. Design Notes also name the split line, 0.5 and 0.10, for the lead.
- Task 0 holds four throwaway measurements: the API reached through the sign-in group by a trace-only user, the `curl` sign-in, the group sign-in after `Api.Login` is overridden, and `HTTP_HOST`. It holds one slot A measurement: the JSON export of an empty list and a `%Boolean`. The publisher `$TLevel` is labelled `(inference)`.
