---
title: 'Story 11.22: First daily release burn-down'
type: 'bugfix'
created: '2026-11-05'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: [multiple-goals, oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The first daily release left harness reds and one product gap: the item check samples a disabled Telegram item while its Ens.Job entry is still ending (DW-692), no API route refuses an oversized body (DW-687), CI keeps no Playwright results from a failed browser unit (DW-710), the request fixture of the `web/e2e` projects waits without a bound (DW-706), `/state` after a sign-in sometimes never answers with no evidence why (DW-550), and lane-a@rest once leaked a resolved Orders incident (DW-698).

**Approach:** Independent, self-contained fixes in rank order: a bounded wait for disabled items with no Ens.Job entry in any state; a shared 256 KB body limit checked before routing, with a per-route declaration for larger bounds; per-unit Playwright output, traces kept on failure in CI and a failure-only upload; a default timeout for every APIRequestContext from the shared test; a timeboxed `/state` investigation plus a diagnostic dump on the named failure; a timeboxed DW-698 replay. DW-416 and DW-636 are sized and returned to the ledger (Design Notes).

## Boundaries & Constraints

**Always:**
- Every task stands alone: one that cannot be finished is declined back to the ledger in its own words without blocking the others (Design Notes, "Overrun order").
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: never touch the UrlMap and never append at the class end; the only change is the body-limit call inside `OnPreDispatch` (Design Notes, D2). All new body-limit code lives in the new class `OcuTalon.Web.BodyLimit`.
- The 413 answer uses the API's error shape `{"error": {"code": "body_too_large", "message": ...}}`; its message is the only new public text of this story.
- A disabled item counts as quiet only when it has no Ens.Job entry in any state (Alive, Starting, Dead). Nothing in this story cleans up Ens.Job entries.
- Every new bound fails naming its step or item; every new test passes on a fresh environment, in either order.
- Runtime work only on slot B or lane-B throwaways with the lane-B variables (Verification), against the CI model mock.

**Never:**
- No edit of `web/e2e/sign-in/helpers.ts`, `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`, `docker/tests/test-production.sh` line 154, `docker/tests/test-class-rules.sh`, `ci/units.sh` or the `iris` matrix and its job names.
- No count of only Alive jobs for a disabled item; no `CleanUpDeadJobs` call to make a wait pass.
- No upload of anything but `web/test-results`; no `always()` upload; no secret reaching the `iris` job.
- No new public text beyond the 413 message. Out of scope: DW-483, DW-656, DW-657, DW-707, DW-416, DW-636.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Body at the limit (DW-687) | signed-in POST to any API route, body of 262,144 bytes | dispatch continues; the route parses as today (POST /v1/messages with a non-message JSON body answers 400 `bad_message`) | none |
| Body over the limit (DW-687) | same, 262,145 bytes, on every route family (messages, mailbox/incoming, approvals/:ref/answer, guide/markers, settings/<section>, incidents/:ref/dismiss) | 413 `body_too_large` in the error shape; the route never runs and nothing is parsed | none |
| Route-declared bound (DW-687, Integration) | dispatch class with `XData BodyBounds` declaring `POST /v1/messages` at 300,000 bytes | 262,145 to 300,000 bytes pass; 300,001 is 413; another route of the same class is still refused over 262,144 | a malformed declaration is ignored (default bound) |
| Envelope first (DW-687) | oversized body that also breaks the envelope (wrong Origin) | 403 `wrong_origin`, as today | none |
| Disabled item ending (DW-692) | TelegramOut disabled, an Ens.Job entry (any state) clears within 30 s | `check_items_run` waits, then samples; row green | none |
| Disabled item stuck (DW-692) | entry still present after the bound | the row fails naming the item and its entry's State and Status, for example `TelegramOut (Dead, last was: running)` | fail, no clean-up |
| Park (DW-692) | `live_park_telegram` after `PARK done` | waits for no entry in any state before returning success | `FAIL` naming item and state, return 1 |
| Request wait (DW-706) | `request` fixture or `playwright.request.newContext()` call to a server that never answers, no explicit timeout | fails at the action wait in force (2/3 of the test timeout, at most 60 s; the project's `actionTimeout` where set) with Playwright's call name, before the test timeout | an explicit `timeout` option is kept |
| Browser unit fails in CI (DW-710) | a Playwright unit fails in an `iris` job | its `web/test-results/<unit>/` (error-context.md, trace.zip) is uploaded as one artifact per job, 3-day retention | no upload on success or skip |
| `/state` never answers (DW-550) | `loadedAfter`'s snapshot GET passes its bound in a live unit | same named failure as today, preceded by `DIAG /state` lines (licence readings, CSP processes and session-lock waiters) | the dump is bounded and best-effort; its own failure is printed and swallowed |

</intent-contract>

## Code Map

- `docker/tests/lib-live.sh` -- `wait_until` (290-303, the 3 s poll bounded by the run's `deadline`: extend it, do not copy); `iris_script` (316-327, keeps `CHK|` lines, 3 tries); `check_session`/`compare_chk` (489-519); `live_park_telegram` (394-414: `PARK done|skipped`, `FAIL Telegram could not be parked`); `item_jobs` (673-680, Alive only, unchanged); `check_items_run` (682-703: one sample; line 695 reads `Ens.Job:Enumerate`, line 697 flags a disabled item on any entry, line 700 prints only names).
- Callers of `check_items_run`: `test-production.sh:101` (row 14), `:279` (row 21); `test-production-restart.sh:196` (row 19), `:280` (row 20). Callers of `live_park_telegram`: `wait_started_ready` (lib-live.sh:391), `test-production-restart.sh:166`, `ci/warm.sh:143`, `ci/iris.sh:285`; stubbed in `test-ci-warm.sh:498,1206,1495` (unaffected).
- `docker/tests/test-lib-live.sh` -- hermetic; sources lib-live with `dc`/`started_at`/`health_status` stubs (43-67), sets `deadline` (95); park tests (149-239) override `iris_script` in a subshell and capture the script sent (`park_probe_with`). `check_items_run` has no hermetic test yet.
- Ens.Job (read-only): `irislib/Ens/Job.cls:837` `Query Enumerate()` (`Job,ConfigName,Mode,Status,Detail,ActiveMessage,State`); State is `Alive`, `Starting` or `Dead` (865); a Dead row's Status starts `last was: ` (868). Dead entries leave only through `CleanUpDeadJobs` (781-794).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (1219 lines) -- UrlMap 142-166 (do not touch); `OnPreDispatch` 170-186 (role, admin, envelope; the insertion point is before the final `Quit $SYSTEM.Status.OK()` at 185); `BodyText` 358-369 (unchanged; callers `MessageBody` 341, `MailBody` 501, `AnswerBody` 555, `MarkerBody` 681, `SettingsBody` 808 map any failure to 400); `Fail` 1159-1187 (its `$Case` falls through `: status`, so a full status line such as `"413 Content Too Large"` passes as is); `ErrorBody` 1202-1205; messages are `Parameter MESSAGE...` literals (80-137).
- `irislib/%CSP/REST.cls:370` `DispatchRequest` is `Final` and calls `OnPreDispatch` first; `Page` (133) has no other pre-route hook. `%request.Content` is a `%CSP.BinaryStream` already received (CONVERTINPUTSTREAM 0); `.Size` is its byte count without reading.
- `src/ocutalon/cls/OcuTalon/Test/Web/StubRequest.cls` -- `MakeBody(app, json, binary)` (17), `MakeCall(...)` (35); `Test/Web/Api.cls` `PreDispatch` (1317-1340) and `Written` (~1359) show the in-process pattern (read only, Epic 40 edits that file). `Test/Web/ApiProbe.cls` -- Web.Api subclass with the role override through `^OcuTalonTest("ApiProbe","roles")`.
- Test.Web runs in shard `lane-b` (`ci/units.sh:18`, group `image`); `web/e2e/api/*.spec.ts` run in `live:sign-in` (chromium project, group `browser`).
- `web/playwright.config.ts` -- `outputDir: 'test-results'` (46), `trace: 'off'` (49), reporter (45). Every `playwright test` clears its outputDir, so a later browser unit of the same CI job wipes an earlier one's results (`shards` runs `online-session` then `cards`).
- `ci/iris.sh` `cmd_live` (437-459) -- runs `bash docker/tests/test-$name.sh`; the place to give each unit its own output folder. `BROWSER_UNITS` at `ci/units.sh:128`.
- `.github/workflows/ci.yml` `iris` job (101-140): steps Check out, What changed (`id: changes`), Build the web bundle, Run the group, Skipped, Tear down (`always()`); pins are full SHA plus `# vX.Y.Z`; no `upload-artifact` anywhere today. Epic 39 changes only the `checks` job's timeout.
- `docker/tests/test-ci-config.sh` -- header line 16 and rule `image-actions` (232, 254-258, samples 397/400, declaration 467-468) forbid any `upload-artifact` in a self-hosted job; pins (228-229), secrets (111-112, 242-243), teardown order (261-272), facts parser (155-171, `step:with` at 171).
- `web/e2e/support/fixtures.ts` (58-88) -- shared `test` from Story 11.21: auto `testClock`, `page` and `context` overrides (`giveWaits`, `boundedClose`), capped `expect`. `web/e2e/support/bounds.ts` -- `waitsFor` (28), `effectiveWaits` (40), `asCleanup` (113), `capToDeadline` (130), `boundedStep` (160), `runBounded`. Playwright 1.64.1: the built-in `request` fixture calls `playwright.request.newContext()` with no timeout (`node_modules/playwright/lib/index.js:169-183`); `_defaultContextTimeout = actionTimeout || 0` (360); `newContext({ timeout })` is honoured (core bundle 60699-60718); `page.request`/`context.request` already follow `context.setDefaultTimeout`.
- APIRequestContext users: `signInOverHttp` (`web/e2e/sign-in/helpers.ts:68-71`, takes the caller's context, 22 call sites); direct `playwright.request.newContext(` in trace.spec:104, links:88, socket:77, api:261,352,411,450, session:207,213,247,299, e2e-online busy:85, readonly:41, support.ts:280, visitors:112.
- `web/e2e/support/floor.ts` `loadedAfter` (141-156) -- arms the `/state` wait, `boundedStep` names `loadedAfter the snapshot GET /ocutalon/api/v1/state`. `web/e2e/support/iris.ts` `irisScript` (bounded session; `OCUTALON_E2E_IRIS_EXEC` stand-in in hermetic specs).
- Hermetic spec patterns: `web/e2e/live/helper-waits.spec.ts` (node:http server holding `/slow`, `STATE`), `web/e2e/live/deadline-cap.spec.ts` (`OCUTALON_E2E_IRIS_EXEC` stand-in).
- DW-550 server facts: `/state` (`Api.cls` `State` 237-243, `StateBody` 920-977) holds no unbounded wait (locks time out at 5 s). IRIS serializes requests on one CSP session through `^%cspSession(id)` with a 240 s default (`irislib/%CSP/Session.cls:703-708,758,778,847`); OcuTalon never calls `%session.Unlock()`; the WebSocket unlocks before its loop (`irislib/%CSP/WebSocket.cls:441-447`). The page sends no `/events` or socket request before `/state` answers (`web/src/app/live/live-state.ts:129-136,162,247-259`). Licence readers: `$SYSTEM.License.LUAvailable()`, `KeyEnforcedUnits()`, `CSPUsers()`, `InstanceConnections()`.
- DW-698 facts: `ci/iris.sh classes lane-a@rest` lists the piece in CI order (`LC_ALL=C sort`); 86 classes here (Agent, Bridge, Digest, Eval, Fix, Tools); `--part k/4` gives contiguous parts (3/4 holds Eval and Fix.EitherWay, 4/4 Fix.Later to Tools.RecentActivityTurn). `Test/Watch/Case.cls` `DropIncidents` (1655-1662) drops `instance` incidents only above the class's floor; `Test/Tools/RecentActivity.cls` `TestPoisoned` (181-198) and `SortedKeys` (`Case.cls:2167`) dereference the newest incident's approval.

## Tasks & Acceptance

**Execution:**
- [ ] DW-698 first, on a fresh warm stack (`ci/warm.sh up`), timebox 60 minutes from the first replay call: print `ci/iris.sh classes lane-a@rest`, then run `shard lane-a@rest --part 1/4` to `4/4` warm, in order, one per call; between parts 3 and 4 list the warm stack's incidents with `OwnerRef = 'instance'` (state, source item, created and resolved times). A red that matches DW-698 (a leaked resolved Orders incident before RecentActivity) is a reproduction: fix it in the leaking test's clean-up or in RecentActivity's fixture, whichever is smaller and outside every contended path, as a reported footprint extension. Otherwise record what was tried (parts, timings, incident listing) in Design Notes "DW-698 result" and the implement summary; the ledger entry stays on OCT-epic39 (never filed here). -- the replay needs a clean warm stack before other warm runs
- [ ] `docker/tests/lib-live.sh` -- add `DISABLED_QUIET_SECONDS` (default 30, overridable), a probe that prints, for every disabled item of the running production, each Ens.Job entry as `<item> (<State>, <Status>)` from `Ens.Job:Enumerate` with no state filter, and `wait_disabled_quiet <label>`, built on `wait_until`, that returns 0 once the probe lists nothing and otherwise fails with `<label>: <item> still has an Ens.Job entry (<State>, <Status>) <n> s after it was disabled`. `check_items_run` calls it first and samples only after it passed. `live_park_telegram` calls it after `PARK done` (not after `PARK skipped`) and returns 1 with that FAIL text on timeout. -- DW-692, the Planner's strict fix
- [ ] `docker/tests/test-lib-live.sh` -- hermetic cases with an `iris_script` stub answering from a counter file: (a) entries twice then none: the wait passes and the sample runs after it; (b) a `Dead` entry that never clears with `DISABLED_QUIET_SECONDS=1`: the FAIL text names the item, `Dead` and its Status; (c) `live_park_telegram` waits after `PARK done` and fails on a stuck entry; (d) source pin: the probe script sent has no `"Alive"` filter. -- DW-692 pin
- [ ] `src/ocutalon/cls/OcuTalon/Web/BodyLimit.cls` (new) -- `Parameter MAXBYTES = 262144`, `Parameter HTTP413CONTENTTOOLARGE = "413 Content Too Large"`, `Parameter MESSAGEBODYTOOLARGE = "OcuTalon refused this request because its body is larger than it accepts."`; `ClassMethod Size()` (`%request.Content.Size`, 0 when Content is not an object); `ClassMethod Bound(class, url, method)`: `MAXBYTES`, or the larger bound the dispatch class declares in an optional `XData BodyBounds [ MimeType = application/json ]` (`[{"method": "POST", "url": "/v1/documents", "bytes": 14680064}]`, `url` in UrlMap form, `:name` matching one segment), read only when the body is over `MAXBYTES`; a malformed or missing declaration means `MAXBYTES`; `ClassMethod TooLarge(class, url, method) As %Boolean`. Header comment states the contract and that a route declares a larger bound by appending `XData BodyBounds` to its dispatch class. -- DW-687 shared limit
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- inside `OnPreDispatch`, after the envelope block and before the final `Quit`, insert `If ##class(OcuTalon.Web.BodyLimit).TooLarge($classname(), url, method) { Set continue = 0  Quit ..Fail(##class(OcuTalon.Web.BodyLimit).#HTTP413CONTENTTOOLARGE, "body_too_large", ##class(OcuTalon.Web.BodyLimit).#MESSAGEBODYTOOLARGE) }` (or the same as a few short lines), and add ", then the body size (Web.BodyLimit)" to its doc comment's first sentence. Nothing else in the file. -- DW-687, the one hook before routing
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/BodyLimit.cls` (new) and `src/ocutalon/cls/OcuTalon/Test/Web/BodyLimitProbe.cls` (new, extends `OcuTalon.Test.Web.ApiProbe`, adds only `XData BodyBounds` declaring `POST /v1/messages` at 300000 bytes; no Test methods) -- in-process cases through `StubRequest.MakeBody(..., binary 1)` with the envelope set as `MakeCall` sets it, the user and admin roles granted through `^OcuTalonTest("ApiProbe","roles")` (cleared after each test), default-bound cases dispatched through `ApiProbe` (no declaration) and declared-bound cases through `BodyLimitProbe`: 262,144 bytes continue; 262,145 refused on each route family of the Matrix with status `413 Content Too Large`, code `body_too_large` and the message; the probe's declared route takes 300,000 and refuses 300,001 while its `/v1/guide/markers` refuses 262,145; an oversized body with a wrong Origin keeps 403 `wrong_origin`; a GET with no body continues. -- DW-687 pin
- [ ] `web/e2e/api/body-limit.spec.ts` (new, real HTTP in `live:sign-in`) -- signed in through `signInOverHttp` (imported, unchanged), with the API's request header, JSON content type and own Origin: POST `/ocutalon/api/v1/messages` with a JSON body of exactly 262,144 bytes that is not a message answers 400 `bad_message`; the same padded to 262,145 bytes answers 413 with `error.code` `body_too_large`. Imports `test` from `../support/fixtures`. -- DW-687 Integration AC, Rule 3
- [ ] `web/playwright.config.ts` -- `outputDir: process.env.OCUTALON_E2E_OUTPUT || 'test-results'`; `trace: process.env.CI ? 'retain-on-failure' : 'off'` (drop DOM snapshots only if the measurement in Verification says so); one header line on both. `ci/iris.sh` `cmd_live` -- run the unit with `OCUTALON_E2E_OUTPUT="test-results/$name"`. -- DW-710: each unit keeps its own results
- [ ] `.github/workflows/ci.yml` -- in the `iris` job, after `Run the group` and before `Tear down`, a step `Keep the Playwright results` with `if: failure() && steps.changes.outputs.run != 'false'`, `uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2` (the latest release, published 2026-10-07; the tag's commit, read from GitHub in the plan stage), `with:` `name: playwright-results-${{ matrix.group }}-${{ github.run_attempt }}`, `path: web/test-results/`, `retention-days: 3`, `if-no-files-found: ignore`. No `env:`, no secret. -- DW-710
- [ ] `docker/tests/test-ci-config.sh` -- narrow `image-actions`: an `upload-artifact` step in a self-hosted job passes only when its `if:` starts with `failure()`, its `path` is under `web/test-results` and its `retention-days` is 1 to 7; keep the existing bad samples (no `if`), add bad samples for an `always()` upload, another path and a missing or 30-day retention, and one good sample; update the header line 16 and the rule's description. -- DW-710, the rule changed only as far as this artifact needs
- [ ] `web/scripts/ci-results.test.mjs` (new, hosted `web` job) -- loads the config with and without `OCUTALON_E2E_OUTPUT` and `CI` and asserts outputDir and trace; source-pins `cmd_live`'s `OCUTALON_E2E_OUTPUT="test-results/$name"`. -- DW-710 pin
- [ ] `web/e2e/support/fixtures.ts` -- a worker-scoped auto fixture that wraps `playwright.request.newContext` once per worker so a call without `timeout` gets the action wait in force: inside a test, `effectiveWaits(testInfo.timeout, project use).action`; outside a test (hooks), the action cap of `bounds.ts`; an explicit `timeout` (0 included) is kept; restored at worker teardown. The built-in `request` fixture, which calls the same method, is covered with no override of its own. -- DW-706, shared-support alternative; `web/e2e/sign-in/helpers.ts` untouched
- [ ] `web/e2e/live/request-waits.spec.ts` (new, hermetic, node:http server holding `/slow`) -- under `test.setTimeout(9_000)`: the `request` fixture's GET of `/slow` and a `playwright.request.newContext()` GET each reject with Playwright's `apiRequestContext.get` timeout of 6000 ms, well before the test timeout; a context made with `{ timeout: 2_000 }` rejects at 2000 ms; a project with `actionTimeout` set (`test.use`) keeps it. -- DW-706 pin
- [ ] DW-550 investigation, timebox 45 minutes, on one fresh lane-B throwaway with a published web port (the warm stack publishes none): a scratch script, kept in the stage's scratchpad only, sources `docker/tests/lib-live.sh` the way a browser unit script does (`live_start`, `wait_started_ready`, then `live_web_port`, with the lane-B variables and the fresh tag), and the stack is removed with `LANE bash ci/iris.sh teardown` afterwards, also after a failure: (a) sign in over HTTP, time GET `/state` alone; (b) hold the same CSP session with a slow request (a large Shell file read with a throttled client) and time a parallel `/state`; (c) read `LUAvailable`, `KeyEnforcedUnits`, `CSPUsers` and `InstanceConnections` before and after five extra signed-in sessions and an open socket. Record the readings and the conclusion (held session, licence unit, or neither) in Design Notes "DW-550 result" and the implement summary. A fix is in scope only when it lives in `web/e2e/support/**` or is at most 10 lines under `Web/**` with a test; any other fix is recorded as the finding. -- DW-550
- [ ] `web/e2e/support/diagnose.ts` (new) and `web/e2e/support/floor.ts` -- `stateDiagnosis()` runs one `irisScript` under `asCleanup` with an own bound of 15 s and prints `DIAG /state ...` lines: the licence readings of the task above, the CSP processes with their state, and the processes waiting on a `^%cspSession` lock (from what (b) showed to be readable from the unit's namespace; leave out a reading that is not, and say so in its header). `loadedAfter` calls it when the snapshot GET passes its bound, then throws the same named error as today; any failure of the dump is printed as one `DIAG /state unavailable: <reason>` line and swallowed. A hermetic case in `web/e2e/live/helper-waits.spec.ts` (append one test at the end) with the `OCUTALON_E2E_IRIS_EXEC` stand-in shows the dump ran and the error text is unchanged. -- DW-550, the Planner's "record each occurrence" for CI
- [ ] This spec -- record Verification results, the `mutation:` lines, the DW-698 and DW-550 results, and the measured trace overhead.

**Acceptance Criteria:**
- AC1 (DW-692). Given a disabled TelegramIn or TelegramOut whose Ens.Job entry is still ending, when `check_items_run` or `live_park_telegram` samples it, then it first waits up to about 30 s until the item has no entry in any state; on the bound it fails naming the item and the entry's state; `live:production` rows 14 and 21 and `live:production-restart` rows 19 and 20 pass.
- AC2 (DW-687). Given a signed-in request with a body over 262,144 bytes on any API route, when it is dispatched, then it answers 413 `body_too_large` in the error shape before any route reads or parses it; a body of 262,144 bytes reaches the route; `body-limit.spec.ts` shows both over real HTTP.
- AC3 (DW-687, route bound). Given a dispatch class that appends `XData BodyBounds` declaring a larger bound for one route, when a body between 262,144 bytes and that bound reaches that route, then it is accepted with no change to `Web.BodyLimit` or `OnPreDispatch`, and every other route keeps 262,144 bytes.
- AC4 (DW-710). Given a browser unit that fails in an `iris` job, when the job ends, then that unit's `web/test-results/<unit>/` (error-context.md and, under CI, trace.zip) is uploaded with 3-day retention; a passing or skipped job uploads nothing; `test-ci-config.sh` refuses any other upload in a self-hosted job.
- AC5 (DW-706). Given a test of a `web/e2e` project, when an APIRequestContext call without its own timeout never answers, then it fails on the action wait in force with Playwright's call name, before the test timeout, and an explicit timeout is kept; no edit of `web/e2e/sign-in/helpers.ts`.
- AC6 (DW-550). Given `loadedAfter`'s snapshot GET passing its bound in a live unit, when it fails, then `DIAG /state` lines show the licence readings and the session-lock state, and the named error is unchanged; the investigation's finding is recorded.
- AC7 (DW-698). Given the 60-minute replay, when it ends, then either a reproduction has its fix and a green replay, or the implement summary lists what was tried.
- AC8 (footprint). Given the diff since `story_base` without `_bmad-output`, when listed, then it holds only this Code Map's files and the tasks' new files; in `Web/Api.cls` only the `OnPreDispatch` lines changed.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs.** AD-13 (the API surface: OnPreDispatch's checks, the error shape, the browser envelope order kept), AD-22 (test tiers and CI: hermetic checks in the hosted jobs, live units on throwaways, the CI mock; its Rule "the AI Hub image never enters a cache or artifact" is why `image-actions` exists, and the narrowed rule keeps the image out by allowing only `web/test-results`), AD-29 (Lane B files; `Web.Api` is shared-by-entry: see D2), AD-3 (the Public package's reference allow-list: `BodyLimit` is not in `OcuTalon.Web.Public`, and `ApiBase` is untouched), AD-12 (the `/state` snapshot, DW-550), AD-25 (the online demo's licence units, DW-550). Conventions: REST (error shape and codes), Tests, Logging and errors. No AC contradicts an AD's Rule.

**Decided in-stage.**
- D1. 256 KB is 262,144 bytes; a body of exactly that size is accepted. The size is `%request.Content.Size` (bytes; the body is already received but not read or parsed), 0 without content.
- D2. The check sits in `OnPreDispatch`, an in-place insertion of a few lines, not an appended block, because `%CSP.REST.DispatchRequest` is `Final`, `OnPreDispatch` is already defined in `Api.cls`, `Page` has no other pre-route hook, and `BodyText`'s five callers turn any failure into 400, so a 413 from `BodyText` would need every caller changed. Epics 34 and 40 do not touch `OnPreDispatch`; nothing is appended at the class end, so Epic 40's appended block merges without conflict. For the lead: the epics AC says "`Web/Api.cls` gets appended blocks only"; recommended apply-and-report restatement: "`Web/Api.cls` changes only by one call in `OnPreDispatch`; the limit lives in `Web.BodyLimit`". The scope relay allowed "the smallest in-place change" in Api.cls.
- D3. The check runs after the role, admin and envelope checks, so a refused envelope keeps its 403 code; an oversized body without a session still gets 401 `signed_out` from `ApiBase.Login`.
- D4. A route declares a larger bound by appending `XData BodyBounds` to its dispatch class (Story 34.2 appends `[{"method": "POST", "url": "<its route>", "bytes": <about 14 MB>}]` to `Api.cls`). Declarations are read only for bodies over 262,144 bytes, so normal requests pay nothing. Only larger bounds take effect.
- D5. `Fail` receives the full status line `413 Content Too Large` (RFC 9110 wording) through its `$Case` fall-through, so `Fail` itself is unchanged.
- D6. DW-692's wait is a shell-level loop on `wait_until`, not an in-session loop, so the hermetic test can drive it. `check_telegram_off` in `test-production-restart.sh` is not changed (it is not a `check_items_run` caller; out of the ruling's scope). A Dead entry that never clears now fails the row naming `Dead`: the Planner chose this over hiding it; 20 park cycles measured by runner A showed no lingering entry.
- D7. Results per unit: `OCUTALON_E2E_OUTPUT` (Playwright has no output-folder variable, so the config reads it). `demo-switch` runs Playwright several times inside one unit, so its last run's results win (inference; accepted).
- D8. Traces only under `CI`, kept on failure. The `iris` job has no secret (test-ci-config's secrets rule), the stack's only token is the CI dummy (`ci/compose.ci.yml`) and the model key is absent; a trace can hold the per-run random sign-in passwords of the job's own throwaway stack, which is torn down in the same job. Flag for the lead: if those are judged secrets, drop `trace` and keep error-context.md only (one line in the config).
- D9. `actions/upload-artifact` is GitHub's own action, like `actions/checkout` and `actions/setup-node` already pinned; it is the only way to keep a CI artifact.
- D10. DW-706: a wrapper of `playwright.request.newContext`, not a replaced `request` fixture, so the built-in fixture's dispose and `baseURL` handling stay Playwright's. A context's timeout is fixed when it is made, so a test that raises its timeout later keeps the earlier wait for that context (the review's fix-risk); the live units below are the evidence that no green request wait is cut.
- D11. DW-550's dump goes to stdout, never into the error text, so Story 11.21's message pins hold.
- D12. The 413 message text is the story's one sanctioned new public text (scope relay).

**For the lead (Rule 20).** The spine's REST convention row gains `413 body_too_large` (any route; a body over the route's bound, 262,144 bytes unless the dispatch class's `XData BodyBounds` declares more). Story 35.2's webhook "body size cap" (AD-13) has no code yet; it should reuse `Web.BodyLimit`.

**Rule 1/2.**
- Shared component: `OcuTalon.Web.BodyLimit`.
- Integration AC: AC2 and the Matrix's route-declared row. Consumer `POST /v1/messages` (every route through `OnPreDispatch`) reads the limit; a real HTTP POST of 262,145 bytes gets 413 `body_too_large`, and 262,144 bytes reaches the route's own 400 `bad_message` (`body-limit.spec.ts`, live stack, no mock of the API).
- Consumed-by: every API route of `OcuTalon.Web.Api` (this story); Story 34.2 (documents upload route: declares about 14 MB through `XData BodyBounds`, U-285); Story 35.2 (webhook body cap).
- Consumes: `%CSP.REST.OnPreDispatch`, `%request.Content.Size`, `Web.Api.Fail`; Story 11.21's `web/e2e/support/fixtures.ts` and `bounds.ts` (`effectiveWaits`, `asCleanup`, `irisScript`).
- Extend, don't copy: `wait_disabled_quiet` extends `wait_until`; its probe reuses `check_items_run`'s `Ens.Job:Enumerate` read (one probe, called by both functions); the request wrapper extends the shared test's `context` waits (`effectiveWaits`); `stateDiagnosis` extends `irisScript` and `asCleanup`; `BodyLimitProbe` extends `ApiProbe`. `BodyLimit` has no sibling in code (the webhook cap is unbuilt).

**Ledger (Rule 17).** Addressed: DW-692 (AC1), DW-687 (AC2, AC3), DW-710 (AC4), DW-706 (AC5), DW-550 (AC6, investigate and record; fix only if small). DW-698 (AC7) is reported in the implement summary and never filed here.
- Declined DW-416: sized 3.5 to 5 hours, over the 2-hour bound. The owner's conditions (U-255) need an explicit admin setting naming the public origins, which AD-19 does not hold (its environment table and fixed key list would need an amendment, a veto item), an in-place change of the origin check in the contended `Web/Api.cls` (`EnvelopeError` 1147-1155) and `Web/Live.cls:72`, tests in four classes and the online fragment, a README sentence (new public text, a veto item) and a post-deploy re-measure. The host's exact-origin mapping stands meanwhile.
- Declined DW-636: sized about 2 to 2.5 hours, over the bound: `install.sh` (the tag filter at 179 and nine "build 154" messages), new cases in `docker/tests/test-install-script.sh` (nine pinned lines), the README's U-241 text in six places and `docker/tests/test-readme.sh`'s 47 build-109 pins, and a manual run on the local build 109 image (CI has none). The messages and the README would also need new public text (a veto item), so it goes back with its size for a story that carries the approved wording.

**Overrun order.** If the implement pass cannot finish everything, decline back to the ledger in this order, each in its own words with what was done: DW-550's dump (keep the investigation result), DW-706, DW-710. DW-692 and DW-687 are not declined.

**Footprint extensions (to report).** `ci/iris.sh` (`cmd_live`, one variable), `web/playwright.config.ts` (two lines), `web/scripts/ci-results.test.mjs` (new), `web/e2e/live/request-waits.spec.ts` (new), `web/e2e/live/helper-waits.spec.ts` (one appended test), `web/e2e/api/body-limit.spec.ts` (new). No open epic touches them. Any DW-698 fix is reported the same way.

## Verification

Run from the epic worktree root, each command in the foreground with `timeout: 600000`, one test class or live unit per call, never two in one message. `LANE` stands for:

`env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=11 stage=implement' OCUTALON_RUN_TAG=e11s22i`

The warm tag is `e11s22iw` (`LANE OCUTALON_RUN_TAG=e11s22iw ...`; `OCUTALON_WARM=1` on the warm call only). After each fresh live unit, also after a failure, run `LANE bash ci/iris.sh teardown`; at the stage's end run `ci/warm.sh down` with the warm tag. At most one fresh and one warm lane-B throwaway at a time.

**Shared surfaces:** the API's error codes (new 413 `body_too_large`) and `OnPreDispatch`'s check order; `check_items_run`'s and `live_park_telegram`'s output and FAIL texts (`test-production.sh` rows 14 and 21, `test-production-restart.sh` rows 19 and 20, `test-lib-live.sh` park cases, `ci/warm.sh`, `ci/iris.sh`); `web/playwright.config.ts`'s `outputDir` and `trace` (`web/scripts/playwright-projects.test.mjs`, `bounded-waits.test.mjs` load it); the `iris` job's steps and `test-ci-config.sh`'s `image-actions` rule; every APIRequestContext of the `web/e2e` and `web/e2e-online` projects. Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- `(loop)` `bash docker/tests/test-lib-live.sh` -- expected: all cases pass, the new ones included.
- `(loop)` `bash docker/tests/test-ci-config.sh` -- expected: pass, with the new good and bad `image-actions` samples.
- `(loop)` `npm --prefix web run lint` and `npm --prefix web test` -- expected: exit 0; `ci-results.test.mjs` passes.
- `(loop)` `cd web && env -u OCUTALON_URL npx playwright test e2e/live/request-waits.spec.ts e2e/live/helper-waits.spec.ts --project chromium` -- expected: all pass with no stack.
- `(once, first)` `LANE OCUTALON_RUN_TAG=e11s22iw bash ci/warm.sh up`, then `LANE OCUTALON_RUN_TAG=e11s22iw bash ci/iris.sh classes lane-a@rest`, then `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s22iw bash ci/iris.sh shard lane-a@rest --part k/4` for k = 1 to 4, one per call (DW-698; record each part's result and time).
- `(loop)` `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s22iw bash ci/iris.sh class OcuTalon.Test.Web.BodyLimit` -- expected: pass.
- `(once)` `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s22iw bash ci/iris.sh class OcuTalon.Test.Web.Api`, then the same for `OcuTalon.Test.Web.MailboxApi`, `OcuTalon.Test.Web.GuideApi` and `OcuTalon.Test.Web.SettingsApi` -- expected: pass (the routes behind the changed `OnPreDispatch`).
- `(once)` `LANE OCUTALON_RUN_TAG=e11s22iw bash ci/warm.sh down`.
- `(once)` `bash ci/checks.sh` -- expected: every static and hermetic script passes (class rules, boundaries ASCII, ci-config, lib-live, readme).
- `(once)` `LANE bash ci/iris.sh live production` -- expected: pass, rows 14 and 21 green; `LANE bash ci/iris.sh live production-restart` -- expected: pass, rows 19 and 20 green.
- `(once, before any browser unit)` `LANE bash ci/iris.sh build`.
- `(once)` `LANE bash ci/iris.sh live sign-in --part 1/2`, then `--part 2/2` -- expected: both pass (`body-limit.spec.ts`, `request-waits.spec.ts`, `helper-waits.spec.ts` and every `signInOverHttp` caller). Then the same part 1/2 again with `CI=1` added: compare its Playwright time with the first run; if it grew more than 15 %, set `snapshots: false` in the CI trace option and measure again; record both numbers.
- `(once)` `LANE bash ci/iris.sh live online-session` -- expected: pass (online request contexts keep their 30 s).
- `(once)` `LANE bash ci/iris.sh live demo-path` -- expected: pass (`loadedAfter` with the dump path compiled in).
- `git status --short` and `git diff --stat` -- expected: only the Code Map's and the tasks' files, no leftover mutation.

**Mutations (Rule 19; apply, observe red, revert, confirm the tree byte-identical):**
- AC1: remove the `wait_disabled_quiet` call from `check_items_run` -> `test-lib-live.sh` case (a) red. Add an `"Alive"` filter to the probe -> case (d) red.
- AC2: change `MAXBYTES` to 262145 -> `Test.Web.BodyLimit` over-the-limit cases red. Remove the `OnPreDispatch` insertion -> the same cases and `body-limit.spec.ts`'s 413 case red.
- AC3: make `Bound` ignore `XData BodyBounds` -> the probe's 300,000-byte case red.
- AC4: drop `failure()` from the upload step's `if:` -> `test-ci-config.sh` red naming `image-actions`. Drop `OCUTALON_E2E_OUTPUT` from `cmd_live` -> `ci-results.test.mjs` red.
- AC5: remove the `newContext` wrapper -> `request-waits.spec.ts` red (test timeout instead of the 6000 ms call timeout).
- AC6: remove the `stateDiagnosis` call from `loadedAfter` -> the appended `helper-waits.spec.ts` case red.
- AC7 and AC8 carry no mutation (a timeboxed replay and a diff listing).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
