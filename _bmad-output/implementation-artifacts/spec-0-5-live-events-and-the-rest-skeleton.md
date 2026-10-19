---
title: 'Story 0.5: Live events and the REST skeleton'
type: 'feature'
created: '2026-10-19'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
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

## Spec Change Log

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Planning summary (October 19).**
- The spec is planned against the committed `epic-0-context.md`, Story 0.4's spec for continuity, the spine (AD-3, 4, 12, 13, 15, 19, 23, 29 and 33, the Conventions, the event table and the REST surface, read by line range), and `epics.md` (0.5, 0.8, 2.2, 16.5 and 16.8).
- Slot A was probed read-only: build 154; no reserved SQL word among the new persistent names; `%IPM` absent; zero instance connections; zone `UTC`.
- No intent gap was found, and no AC contradicts an AD.
- DW-5 is addressed in rows 20–24 and AC4. The Rule 22 ruling on stale files is: delete only OcuTalon's own files from `csp/ocutalon/`, and only when its `index.html` has the OcuTalon marker.
- The Rule 22 rulings and the VETO WINDOW items are under Design Notes. Design Notes also name the split line, 0.5 and 0.10, for the lead.
- Task 0 holds four throwaway measurements: the API reached through the sign-in group by a trace-only user, the `curl` sign-in, the group sign-in after `Api.Login` is overridden, and `HTTP_HOST`. It holds one slot A measurement: the JSON export of an empty list and a `%Boolean`. The publisher `$TLevel` is labelled `(inference)`.
