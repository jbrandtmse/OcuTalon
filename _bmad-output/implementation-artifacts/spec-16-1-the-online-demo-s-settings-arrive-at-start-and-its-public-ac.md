---
title: 'Story 16.1: The online demo''s settings arrive at start, and its public accounts are safe to publish'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: 'ea1b455e01102a0cc3f2034e64bf20aec75aac6d'
baseline_commit: 'ea1b455e01102a0cc3f2034e64bf20aec75aac6d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-13 "One sign-in group", "Password changes" and the online-demo session lifetime; AD-19 "Online-demo start values" and "Public settings"; AD-24 the trace role, trace applications and the public accounts bullet; AD-25 "The probe" and "Capacity"; AD-12 the snapshot bullet; and the Consistency Conventions row "Online-demo start")'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a.md (read only its Boundaries table of start values and its Design Notes "Measured at planning")'
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      StateBody's doc comment and the class comment of Web/Api.cls do not name the new traceAccount key; only TraceAccount()'s own comment does.
    evidence: |-
      The spec's task list asks for both comments to name the key and its condition, but the lead's spec gate for the shared file Web/Api.cls allows one new method and one call line and no other changed line; StateBody's "keys in this order, ending at status" sentence would have to change, so the review routes it instead of patching.
    location: >-
      src/ocutalon/cls/OcuTalon/Web/Api.cls:1-20 and the StateBody comment
    severity: low
---

<intent-contract>

## Intent

**Problem:** Story 3.8 built the online demo's start values, public accounts and password guard, but proved them only in process: no stack has ever started with the online-demo flag on, no test sends the other password-change forms of spike S17, nothing shows what the read-only account can and cannot open, no test shows the demo account's trace links opening already signed in, and the Visual Trace menu still lacks the read-only credential rows the online demo needs (FR-59, UX-DR39, UX-DR87).

**Approach:**
- A new live unit, `online-demo`, makes the first real flag-on start on a throwaway with test start values and checks the start, the keys, the guard against every S17 form over HTTP, and (in a new Playwright project) both public accounts' reach in a real browser.
- `/state` gains `traceAccount` (the read-only user name and password) on the online demo only, and the header's Visual Trace popover shows it as two credential rows with copy buttons. A local install's snapshot and popover stay exactly as they are.

## Boundaries & Constraints

**Always:**
- **Test start values** (set by the live script in a compose override it writes to its own `$tmp`, never in a tracked compose file): `OCUTALON_ONLINE_DEMO=1`, `OCUTALON_DEMO_USER=DemoVisitor`, `OCUTALON_READONLY_USER=TraceReader`, both passwords random per run (hex, from the script, passed to compose through `${VAR}` interpolation so they are in no file, and redacted in the script's log as `test-sign-in.sh` redacts fixture passwords), `OCUTALON_RESET_INTERVAL_HOURS=4`, `OCUTALON_RESET_ANCHOR=2026-10-18T00:00:00Z`, `OCUTALON_LAST_RESET=2026-10-25T08:00:00Z`, `OCUTALON_LAST_RESET_KIND=scheduled`, `OCUTALON_PROXY_ADDRESS=192.0.2.10` (TEST-NET, so no test request counts as proxied), `OCUTALON_CONNECTION_CAP=8`, `OCUTALON_CONNECTION_RESERVE=2`, `OCUTALON_MESSAGE_ALLOWANCE=50`, `OCUTALON_DAILY_COST_CAP_USD=20`, and no gateway variables.
- **`traceAccount`** is `{"user": <readonlyUser>, "password": <readonlyPassword>}`, the last key of `/state`, present only when `onlineDemo` is 1 and both values are non-empty, read through `OcuTalon.Data.Setting.Get` as `StateBody` reads `onlineDemo`. With the flag off the key is absent, so the local snapshot's key list is unchanged.
- **The popover rows** (header, online demo only): below "Open my conversation in Visual Trace" (and below its reason line when shown), one row per credential: the label ("User name", then "Password"), the value in `mono` on D `credential-card` tokens, and an icon button (Lucide `copy`) named "Copy Visual Trace user name" / "Copy Visual Trace password". The link stays the popover's first focus.
- **Copy:** success writes the exact value with `navigator.clipboard.writeText`, shows "Copied" in that row for 2 seconds and announces "Copied" through `Announcer` (EXPERIENCE.md's announcement table). Failure (a rejected promise or no `navigator.clipboard`) shows "Couldn't copy. Select the text and copy it yourself." under the rows until the next copy or the popover closes, announces it, and selects that row's value text. Every text is a `TRACE_TEXTS` entry, never a template literal.
- **The S17 form set** (all at `/ocutalon/`; F1 and F3 also at `/ocutalon/api/v1/state`, `/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen` and `/ocutalon/trace/ocuorders/EnsPortal.MessageViewer.zen`). Each sends a user name, its current password and a new one:
  - F1 POST URL-encoded body, current names (`IRISUsername`, `IRISOldPassword`, `IRISPassword`, `IRISLogin`); F2 the same with legacy names (`CacheUserName`, `CacheOldPassword`, `CachePassword`, `CacheLogin`);
  - F3 GET with the current names in the query string; F4 GET with the legacy names;
  - F5 POST with the current names in the query string and an empty body;
  - F6 POST body with percent-encoded names (each letter of `OldPassword` and `Password` encoded, e.g. `IRIS%4F%6C%64Password`); F7 GET with percent-encoded names;
  - F8 POST `multipart/form-data`, current names; F9 the same with legacy names;
  - F10 POST URL-encoded body, current names, sent `Transfer-Encoding: chunked`;
  - F11 POST URL-encoded body with the current names in mixed case (`irisusername`, `IrisOldPassword`, `irispassword`, `irislogin`) plus `IRISRepeatPassword`.
- **Each form is sent three times:** for the demo account (name as published), for the read-only account (name in capitals), and for a control fixture user (no public account) whose current password the script tracks. "Signs in" means a plain sign-in POST to `/ocutalon/` (`IRISUsername`, `IRISPassword`, `IRISLogin`) that IRIS accepts: the shell for `DemoVisitor` and the control, the no-role page for `TraceReader`; a refused one returns the sign-in page with its failed-sign-in error. Every request uses its own cookie jar and ends with `?IRISLogout=end` on the same application, so no form leaves a licence connection held. Every page request of the script carries a unique `probe=<n>` query parameter (the web gateway caches per URL, as `test-bundle-folder.sh` notes).
- **Task 0 (implement stage, the unit's first run):** for each form, whether it changes the control's password on build 154. The forms that do are the script's `CHANGE_FORMS` list; the run then asserts both directions (a listed form changes the control, an unlisted one does not), so a change in IRIS's behaviour turns the unit red. Record the measured list and the per-form outcome in `## Verification`.
- **Sign-out discipline in the browser specs:** every spec signs out group-wide (`/ocutalon/?IRISLogout=end`) in `finally`, because a signed-in CSP session holds one of the stack's licence connections until it times out (28,800 s on a throwaway).
- **Self-contained specs:** each spec creates the trace sessions it opens (a turn through the API, one Orders message in OCUORDERS) and reads no other spec's leftovers.
- **Runtime targets** (Rule 21): stacks only through `ci/iris.sh` and `ci/warm.sh` with lane C's variables; `ocutalon-slot-c`, namespace `OCUTALON`, only for `iris_doc_load` compiles after `iris_server_info` shows build 154 on port 52792, with no security or setting change there.

**Never:**
- No edit to Lane A's `Install/Step/{Public,Users,Roles}.cls`, `Install/Registry.cls`, `Test/Install/**`, or to `Demo/**`, `docker/**` other than the new `docker/tests/test-online-demo.sh`, `ci/compose.ci.yml`, `docker/tests/compose.*.yml`, `docker/tests/lib-live.sh` or `.github/**`. If a check can only pass with such an edit (a form that changes a public account's password, a start step that fails with the flag on, a grant the read-only account lacks), stop with `## Clarification Needed` naming the file and the evidence; never work around it.
- No grant, role or application change for either public account, and no change to the trace applications' `PermittedClasses`.
- `traceAccount` never appears with the flag off, and the read-only password never appears in a log line, a live event, a production message or an audit entry.
- No change to the existing chromium project's spec list, to `web/e2e/demo-path/**` (Story 16.2 adds the REL-2 online run there), or to `Web.Public.Login` (the splash is Story 16.2's).
- Out of scope: the Web step reading the flag and the 120-second CSP timeout (Story 16.4), the splash (16.2), the resume session and per-address limit (16.3), busy (16.5).

## I/O & Edge-Case Matrix

Rows 1 to 13 run in the `online-demo` live unit on a fresh flag-on throwaway (row 13 after a restart). Rows 14 to 16 run on the local (flag-off) stacks.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Start order (AC 1) | Fresh volume, the test start values | The log's `STEP` lines equal `expected_run` (`Bridge.Installer`, `Public`, `Roles`, `Users`, `Web`, ... `Ready`), every step OK, `RESULT OK`; readiness 1 | A failed step fails the unit and stops it |
| 2 | Every key (AC 1) | After row 1 | Each of the 13 keys reads back as its start value through `Public.Settings.Get` and through `Setting.Get` (passwords compared inside IRIS, printed as 1 or 0); `/ocutalon/public/status` answers `ready` true, `nextReset` equal to `Public.Settings.NextReset()` and on a 4-hour step of the anchor, later than now and at most 4 hours away, `busy` false, `lastReset` and `lastResetKind` as given | -- |
| 3 | Budget rows (AC 1) | After row 1 | `Decide`'s System Default Settings: `DailyCostCapUSD` 20, `GatewaySpendUSD` and `GatewaySpendDate` empty | -- |
| 4 | Accounts and guard (AC 2) | After row 1 | `DemoVisitor` holds exactly `OcuTalonUser,OcuTalonTraceViewer`, `TraceReader` exactly `OcuTalonTraceViewer`; both enabled, `ChangePassword` 0, password and account never expire; the README account disabled. `PasswordValidationRoutine` is the literal `Check^OcuTalonPasswordGuard`, `OcuTalonPasswordGuard` exists, `OcuTalonPasswordGuardNew` does not, and the routine's source holds neither password. Both names' Visual Trace page size is 100 in OCUTALON and OCUORDERS (DW-160 on a real fresh volume) | -- |
| 5 | Every S17 form (AC 2) | F1 to F11, each for the demo account, the read-only account (name in capitals) and the control | After each form both public accounts still sign in with their published passwords and not with the attempted one; the control's password changed exactly for the forms in `CHANGE_FORMS` | -- |
| 6 | No password-change page (AC 2) [AMENDED 2026-10-25, Story 16.1, unattended ruling (veto), runner C lead: was "`%25CSP.PasswordChange.cls` answers 404 on both trace applications"; measured on build 154, IRIS serves its own page there to a signed-in user whatever `PermittedClasses` says] | No session; then signed in at each trace application | OcuTalon's own pages offer no password change: the sign-in page at `/ocutalon/` has no field named `*OldPassword` or `*RepeatPassword`, and with no session `%25CSP.PasswordChange.cls` at each trace application is IRIS's sign-in page with no such field. Signed in, IRIS's own `%25CSP.PasswordChange.cls` page is served (recorded, not asserted absent); a change posted through it (F12) is refused for both public accounts by the guard (row 5). On the online demo the demo host's proxy blocks every password-change page and every `*OldPassword` / `*RepeatPassword` field (AD-25, Story 29.3) | -- |
| 7 | Read-only at `/ocutalon` (AC 3) | `TraceReader` signs in through the sign-in form | The page shows "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it." and never the shell; `GET /ocutalon/api/v1/state` then answers 401 | -- |
| 8 | Read-only opens trace (AC 3) | `TraceReader` signed in at `/ocutalon/trace/ocutalon/`; a seeded OCUTALON turn session and one seeded OCUORDERS order session | In each namespace Visual Trace draws the seeded session's messages and the message viewer lists at least one row; the second application asks for no sign-in | -- |
| 9 | Read-only refused (AC 3) | `TraceReader` signed in to both trace applications | Each of `EnsPortal.ProductionConfig.zen`, `EnsPortal.Productions.zen`, `EnsPortal.StartStopFrame.zen`, `EnsPortal.MessageResend.zen`, `%25CSP.UI.Portal.SQL.Home.zen`, `EnsPortal.Credentials.zen`, `%25CSP.UI.Portal.Users.zen` and `EnsPortal.DefaultSettings.zen` answers 404 in both applications, and on the Visual Trace page `zenPage.canResend` is false (the property checks the resend resource, `irislib/EnsPortal/VisualTrace.cls:92`) | -- |
| 10 | Demo trace links (AC 4) | `DemoVisitor` signed in on the page; a turn posted through the API | Pressing the turn's Trace link, then the menu's "Open my conversation in Visual Trace", each opens a new tab at the link's `traceUrl` that shows no `IRISPassword` field at any point and draws the turn | -- |
| 11 | Credential rows (AC 4, integration) | `DemoVisitor` opens the Visual Trace menu; clipboard permissions granted | Below the conversation link: "User name" and "Password" rows holding `TraceReader` and its password in `mono`, with the two named copy buttons; each press puts the exact value on the clipboard and shows "Copied" | -- |
| 12 | Copy fails (AC 4) | `navigator.clipboard.writeText` rejects (init script) | "Couldn't copy. Select the text and copy it yourself." is shown and the page's selection is exactly the row's value | -- |
| 13 | Every start (AC 1, AC 2) | Row 1's stack restarted | The second start's `STEP` lines equal `expected_run` for a restart, all OK; readiness 1; the guard setting unchanged; the demo account still signs in with its published password (the installer rewrote it through the live guard) | -- |
| 14 | Snapshot shape (AC 4, AC 5) | `StateBody` in process: flag 0 with both read-only keys set; flag 1 with both; flag 1 with the password empty | Flag 0: no `traceAccount`, keys exactly as today. Flag 1: `traceAccount` last, with both values. Password empty: no `traceAccount` | -- |
| 15 | Local popover (AC 5) | Local stack, links fixture user opens the menu | No credential row, no copy button; the rest of V7 unchanged | -- |
| 16 | Delegation (AC 1) | Each of the 13 keys and `ready` written through `Public.Settings` | `Setting.Get(key, "d")` returns the written value at once, and "d" after the key is removed | -- |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `StateBody` (:250-297) builds the keys at :270-293 (`onlineDemo` from `Setting.Get` at :279) and then calls `TraceLink.Viewer` and `TraceLink.Add(body)` (:294-295); the class comment (:1-20) lists the snapshot's keys. Shared with Epic 4: add a new private method and one line before :294, change nothing else.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- read only: `Get` delegates every public key and `ready` to `Public.Settings.Get` (:26-32, `IsPublic` :58-61).
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` -- read only: `KEYS` (:9), `Get`/`Set`/`ClearReady`/`SetReady` (:19-54), `NextReset` (:60-75).
- `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls:52-57` -- read only: `/status` reads readiness, `NextReset`, the cap and reserve, and the last reset through the accessor.
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls:54-62,113-116` and `Web/Public/Login.cls:28` -- read only: the no-role path and its text (`ERRORNOROLE`).
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls` -- Lane A, read only: `DEMOROLES` (:46), `READONLYROLES` (:49), `Accounts` (:89-121), `Guard` (:161-181), `EnsurePublic` (:342-360), `PinTrace` (:365-379), `GUARDENTRY` (:61).
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- read only: `PERMITTED` (:24), `TraceApp` (:147-159), `Common` (:162-178, group `OcuTalon`, timeout 28800).
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- `TestStateBody` (:93-121) is the model: fixture sessions from `Session.ForUser("zz..."_..Number)`, keys collected with `%GetIterator`; its key-list assertion (:121) stays as it is.
- `src/ocutalon/cls/OcuTalon/Test/Data/Setting.cls` -- `TestPublicKey` (:92-110) is the sibling (one key); `PUBLIC` (:9).
- `web/src/app/header/header.ts` -- popover template `#tracePanel` (:137-164: the conversation link :144-159, its reason :160-162); signals (:345-365); `badge` reads `snapshot?.onlineDemo` (:359-365).
- `web/src/app/shared/trace-link.ts:33-86` -- `TraceHelpBlock` (`app-trace-help`): projects `<ng-content/>` in a flex column; not changed.
- `web/src/app/shared/trace-view.ts:14-25` -- `TRACE_TEXTS`; `web/scripts/trace-view.test.mjs:21-40` pins it exactly.
- `web/scripts/ux-strings.test.mjs` -- `IMPORTED` already holds `shared/trace-view.ts` (:48); `SOURCES.ux` (:143ff) needs one entry per new string. EXPERIENCE.md holds them verbatim (:121, :314, :438, :701).
- `web/src/app/shared/announcer.ts:6-30` -- the one polite live region. `web/src/app/icon/icon.ts:4-25` -- `IconName` (Lucide, ISC) has no `copy`.
- `web/src/styles/tokens.css:524-530` -- `--credential-card-*` (dark at :763-764, :986); `--type-mono-*` (:87-94).
- `web/src/app/api/api-types.ts:31-50` -- `StateSnapshot` (hand-written).
- `web/e2e/trace/links.spec.ts` -- V6 (:460-485, fakes `onlineDemo` with `changeSnapshot` and no `traceAccount`: stays green), V7 (:488-590, the local menu). `opensTab` (:136-141) signs in when asked, which the online case must not.
- `web/e2e/support/trace.ts` -- `TRACE_PAGE` (:13), `postTurn` (:48), `signInToTrace` (:60), `drawnMessages` (:88), `expectDrawn` (:113). `web/e2e/support/iris.ts` -- `FixtureKind` (:15), `fixtureUser` (:18), `irisScript` (:42), `chk` (:60). `web/e2e/sign-in/helpers.ts` -- `fillSignIn` (:43), `signIn` (:60), `signInOverHttp` (:66).
- `web/playwright.config.ts:34-45` (five projects), `web/package.json:14-16` (e2e scripts), `web/scripts/playwright-projects.test.mjs:34-42` (`specFilesOnDisk` reads only `web/e2e/`), :71-90 (per-project lists); `web/tsconfig.e2e.json` (`include` `e2e/**/*.ts`).
- `docker/tests/lib-live.sh` -- `live_start` (:57-88), `live_add_file` (:150-151), `live_web_port` (:201-241), `iris_script` (:307-317), `live_fixture_user` (:320-327), `wait_started_ready` (:372-380), `check_session` (:479-484), `check_security` (:509-538, expects the README account enabled, so it is not called with the flag on), `expected_run` (:589-595), `check_log` (:598-607), `check_no_key` (:648-656).
- `docker/tests/test-sign-in.sh:192-227` and `docker/tests/test-floor.sh:82-87` -- how a unit runs Playwright (`OCUTALON_URL`, fixture variables, `OCUTALON_E2E_IRIS_CONTAINER`, a deadline-derived `OCUTALON_E2E_TIMEOUT_MS`). `docker/tests/test-install-start.sh:105-107` -- the fresh `expected_run` call; its restart rows show the restart call. `docker/tests/test-bundle-folder.sh:39-57,150-152` -- the curl `probe` and form sign-in pattern.
- `ci/units.sh` -- `image)` group (:35), `BROWSER_UNITS` (:41). `docker/tests/test-ci-config.sh` enforces: every test script in one group (:601-652), every script running `npm --prefix web run e2e*` in `BROWSER_UNITS` (:715-748), exactly six groups (:810-838).
- `docker/tests/test-class-rules.sh:78,284` -- the public-global rule (only `Data/Public/Settings.cls` names `^OcuTalonPublic`), already enforced.
- `src/ocutalon/cls/OcuTalon/Test/Install/PasswordGuard.cls:121-136` -- Lane A's F1 helper (POST to 52773 inside IRIS); not reused, because the S17 forms need raw HTTP control (multipart, chunked, encoded names) that only curl from the host gives.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- new private class method `TraceAccount()` returning the object or "" per the Boundaries; `StateBody` sets `traceAccount` from it after `status`, before `TraceLink.Add`; the class comment and `StateBody`'s comment name the key and its condition -- rows 11, 14.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- `TestStateTraceAccount` (row 14): saves and restores `onlineDemo`, `readonlyUser` and `readonlyPassword` through `Public.Settings` (also after a failure), uses its own `ForUser` fixture sessions, and asserts the three cases including the full key list. The header lists it -- row 14.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Setting.cls` -- `TestEveryPublicKeyIsDelegated` (row 16) over `KEYS` plus `ready` (readiness through `SetReady`/`ClearReady`), restoring each value; no existing line changes -- row 16.
- [ ] `web/src/app/api/api-types.ts` -- `traceAccount?: { user: string; password: string }` on `StateSnapshot`, with a comment saying it is present only on the online demo.
- [ ] `web/src/app/shared/trace-view.ts` -- `TRACE_TEXTS` gains `userNameLabel` "User name", `passwordLabel` "Password", `copyUserName` "Copy Visual Trace user name", `copyPassword` "Copy Visual Trace password", `copied` "Copied", `copyFailed` "Couldn't copy. Select the text and copy it yourself." (footprint extension).
- [ ] `web/scripts/trace-view.test.mjs` and `web/scripts/ux-strings.test.mjs` -- the new `TRACE_TEXTS` in the exact-match test; one `ux` entry each in `SOURCES` for any of the six strings not already listed (footprint extension).
- [ ] `web/src/app/icon/icon.ts` -- `copy` in `IconName` with Lucide's `copy` paths (footprint extension).
- [ ] `web/src/app/header/credential-rows.ts` (new) -- standalone `app-credential-rows` component taking the account; renders the rows, the copy buttons, the "Copied" state, the failure line and the selection per the Boundaries; inline template and styles (no `templateUrl`), tokens only.
- [ ] `web/src/app/header/header.ts` -- inside `#tracePanel`, after the conversation link and its reason, render `<app-credential-rows>` only when the snapshot's `traceAccount` is present; the class comment says so -- rows 11, 12, 15.
- [ ] `web/e2e/support/iris.ts` -- `FixtureKind` gains `DEMOACCOUNT` and `READONLYACCOUNT`; `required`'s message also names `docker/tests/test-online-demo.sh` (footprint extension).
- [ ] `web/e2e-online/readonly.spec.ts` (new) -- rows 7, 8, 9 as cases O1 to O3, as `READONLYACCOUNT`; seeds the OCUTALON session through the demo account's API turn (`postTurn`, signed in over HTTP as `DEMOACCOUNT`) and one OCUORDERS order through `irisScript` with the Orders production's own entry (`OcuTalon.Demo.Orders.Partner.Send(1, "YYYY-MM-DD")`, the format the warehouse accepts, `src/ocutalon/cls/OcuTalon/Demo/Orders/Partner.cls:79-83`, run with `$Namespace` set to OCUORDERS in that test script), then reads the new session's header id; it signs out of every application it opened (footprint extension).
- [ ] `web/e2e-online/demo-account.spec.ts` (new) -- rows 10, 11, 12 as O4 to O6, as `DEMOACCOUNT`; its own strict opener asserts that the new tab never shows `input[name=IRISPassword]` (no `signInToTrace`); clipboard through `context.grantPermissions(['clipboard-read','clipboard-write'])` and an init-script rejection for O6 (footprint extension).
- [ ] `web/playwright.config.ts` -- a new project `online-demo` (`testDir: './e2e-online'`, Desktop Chrome) with its own comment beside the new entry; no existing line changes, the header's count word and project list included (shared with Epic 4: new entry only; lead spec gate).
- [ ] `web/package.json` -- script `e2e:online-demo` (`playwright test --project=online-demo`) (shared: new entry).
- [ ] `web/scripts/playwright-projects.test.mjs` -- a new case, one self-contained block appended after the existing cases: `e2e:online-demo` lists exactly the spec files of `web/e2e-online/`; no existing line changes, the header included (shared with Epic 4: new entry only; lead spec gate).
- [ ] `web/tsconfig.e2e.json` -- `include` gains `e2e-online/**/*.ts`, so `npm run lint` type-checks the new specs (footprint extension).
- [ ] `web/e2e/trace/links.spec.ts` -- V7 also asserts that the local popover holds no "Copy Visual Trace user name" or "Copy Visual Trace password" button and no "User name" row (footprint extension) -- row 15.
- [ ] `docker/tests/test-online-demo.sh` (new; footprint extension) -- header states what it checks and needs. Shape of `test-floor.sh`: `live_start`, `live_web_port`, the `$tmp` override through `live_add_file`, `dc up -d --build`, `wait_started_ready`, then rows 1 to 4 (`check_log` with `expected_run`, `check_session` rows, `check_no_key`, curl for `/status`), the control user (`live_fixture_user`, role `OcuTalonUser`), rows 5 and 6 (curl helpers of its own, one per form shape), Playwright (`npm --prefix web run e2e:online-demo` with `OCUTALON_URL`, `OCUTALON_DEMOACCOUNT_*`, `OCUTALON_READONLYACCOUNT_*`, `OCUTALON_E2E_IRIS_CONTAINER`, `OCUTALON_E2E_TIMEOUT_MS`, refusing to start the browser with under 60 s left), then the restart and row 13. Passwords never printed -- rows 1 to 13.
- [ ] `ci/units.sh` -- append `live:online-demo` to the `image` group and `online-demo` to `BROWSER_UNITS`; nothing else (shared by region: own entries).

**Acceptance Criteria:**
- Given AD-19's online-demo start values on a fresh throwaway, when the container starts, then the `Public` step runs right after `Bridge.Installer`, every step succeeds, readiness is set last, every public value reads back through `OcuTalon.Data.Public.Settings` (and through `Setting.Get`, which delegates), `/ocutalon/public/status` reports the next reset that `NextReset` computes with the last reset and its kind, and `Decide`'s cap is 20; no class but the accessor names the global (the existing `class-rules` check). Rows 1, 2, 3, 13 and 16 hold.
- Given the demo and read-only accounts of that start, when any S17 form tries to change either password at any OcuTalon application, then the password stays the published one (the name in capitals included), the control user's password changes exactly where IRIS treats the form as a change, the restart's installer rewrites the published value through the live guard, and no page of OcuTalon's own offers a password change (IRIS's own `%CSP.PasswordChange.cls` at the trace applications reaches no public account's password: the guard refuses it, and the demo host's proxy blocks the page, AD-25) [AMENDED 2026-10-25, unattended ruling (veto)]. Rows 4, 5, 6 and 13 hold.
- Given the read-only account, when it signs in at the two trace applications and at `/ocutalon`, then it opens Visual Trace and the message viewer in both namespaces with one sign-in, is refused production, resend, SQL, security, settings and credential pages, and gets the "no OcuTalon role" message at `/ocutalon`. Rows 7, 8 and 9 hold.
- Given the demo account signed in on the page, when it presses a trace link and "Open my conversation in Visual Trace", then Visual Trace opens in a new tab at the link's target with no second sign-in; and its Visual Trace menu shows the read-only credential rows from `/state` with working copy buttons. Rows 10, 11 and 12 hold (the integration AC: the header reads `traceAccount` from the snapshot on a real flag-on instance).
- Given a local install, when it starts and its page loads, then `/state` has no `traceAccount` and the same keys as before, and the Visual Trace menu shows no credential rows; the existing local tests stay green unchanged. Rows 14 and 15 hold.

### Review Findings

Code review (epic-cycle stage, 2026-10-25, runner C): four layers (blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor), full tier; 29 raw findings, 9 entries after grouping (high 0, medium 2, low 7), 13 rejected. Each entry: severity / fix-risk / footprint / spec-status, then its Rule 15 disposition.

- [x] [Review][Patch] `TestStateTraceAccount` held a second hard-coded copy of the local `/state` key list; Epic 4's branch already adds `guide` after `status` while demo mode is on (its `StateBody` and `TestStateBody` on `OCT-epic4`), so the list goes red at integrate-forward, and the Design Notes' merge note ("only StateBody's body can meet") misses it. Now the flag-0 snapshot's own keys are the baseline (TestStateBody keeps pinning the list), and flag 1 must equal the baseline plus `traceAccount` last, so a merge that puts `guide` after `traceAccount` still turns it red. For the lead at integrate-forward: `traceAccount`'s line goes after Epic 4's `guide` line. [src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:1253] -- medium / low (test-only, warm-stack green, mutation re-shown) / in-story / clear: fixed now.
- [x] [Review][Patch] The accessibility scan never saw the credential rows: floor U2 scans the Visual Trace menu only on a local stack, where the snapshot has no `traceAccount`. New O10 runs `scanPage` (support/scan.ts, the floor's own scan) on the page with the menu and its rows open, in light and dark, once with the failure line and once with "Copied" (held by the page clock). The scheme loop is written in the spec file because the floor's `expectClean` is local to `floor/scan.spec.ts`, and a spec file cannot be imported without registering its tests. [web/e2e-online/demo-account.spec.ts:288] -- medium / low (new case, green, mutation shown) / in-story / clear: fixed now.
- [x] [Review][Patch] The Never line's password scan did not search live events or the audit log (only the logs and `Ens_Util.Log`). `check_logs_clean` now also counts both published passwords in `OcuTalon_Live.Event.Payload` (OCUTALON) and in `%SYS.Audit` `EventData`/`Description`. Production message bodies have no generic search across body classes; that remainder is DW-219 (`wontfix-accepted`, with a `reopen_if` probe). [docker/tests/test-online-demo.sh:488] -- low / low / in-story / clear: patched (two-way door); the remainder is ledgered.
- [x] [Review][Patch] The log scan ran only before the restart, but the restart writes both passwords again and its after-start log replaces the first one (`after-start.sh` truncates it). `check_logs_clean` now runs after the browser and again after row 13. [docker/tests/test-online-demo.sh:535] -- low / low / in-story / clear: patched.
- [x] [Review][Patch] Row 13 compared the guard setting with `validation_before`, a capture that nothing checked: an empty capture and a cleared setting both read `CHK|validation|` and passed. It now compares with the literal `Check^OcuTalonPasswordGuard`, as row 4 does, and the capture is gone. [docker/tests/test-online-demo.sh:519] -- low / low / in-story / clear: patched.
- [x] [Review][Patch] Row 6's no-session check of `%25CSP.PasswordChange.cls` accepted any non-empty body (a 404 or an error page passed), although the restated row says it is IRIS's sign-in page. It now asserts status 200 and an `IRISPassword` field, as well as no old- or repeat-password field. [docker/tests/test-online-demo.sh:424] -- low / low / in-story / clear: patched.
- [x] [Review][Patch] The script's comment claimed that everything it prints passes through `redact`. Only the log tails do; no password is printed because the checks print names, outcomes and counts. The comment now says that. [docker/tests/test-online-demo.sh:65] -- low / low / in-story / clear: patched (Rule 14).
- [x] [Review][Patch] The copy failure line had no `circle-alert` icon, which DESIGN.md's `field-error` component (and its "Field error" rule: "under the field or button it belongs to") requires, as `chat/user-message.ts` does for "Message not sent". The icon is now in the line. [web/src/app/header/credential-rows.ts:54] -- low / low / in-story / clear: patched.
- [x] [Review][Patch] DW-217 (the lead's ruling allows doc-only lines): the class comment of `Web/Api.cls` and `StateBody`'s comment now name `traceAccount`, its condition (online demo only: `onlineDemo` 1 and both read-only values set) and that it follows `status`. No other line of the shared file changed. [src/ocutalon/cls/OcuTalon/Web/Api.cls:10,270] -- low / low / in-story / clear: patched; DW-217's adjudication is the lead's.
- [x] [Review][Defer] `live:online-demo` joined the `image` group on a unit-against-group comparison. `## Verification` calls the unit (116 to 138 s locally) "far below the image group's 600 s guideline", but `image` already took 9 min 42 s to 13 min 50 s on CI (Rule 21). At the measured 2.4 to 3.9 times factor, the unit adds about 280 to 540 s there, so the lead gate's condition ("past about 600 s on CI beside demo-switch") is likely met. Moving the unit changes an existing line of the shared `ci/units.sh`, and the group is the lead's call at commit. [ci/units.sh:35] -- deferred: DW-220 (`wontfix-accepted`; reopen_if the first CI run's `image` job is the longest IRIS job, or the run passes 35 minutes); low / low / in-story / clear.

Rejected (13):
- low -- row 13 cannot tell the installer's rewrite of an unchanged password from no rewrite (blind): the clause is pinned in process (`Test.Install.Users.TestInstallerWritesAChangedPassword`), `STEP Users OK` on the restart shows that the write through the live guard ran, and a live pin needs a third start with a changed password.
- low -- the copy buttons have no tooltip (blind): EXPERIENCE.md asks for a visible or programmatic label (the `aria-label` names action and object), and a tooltip inside the popover overlay is new behaviour, not a direct correction.
- low -- the browser's global timeout can use up the time row 13 needs (blind + edge): this happens only on a run already slower than the deadline, and the browser's FAIL line comes first; the fix would redistribute the deadline.
- low -- O3 opens `SESSIONID=1`, a session it did not create (blind + auditor; verification-gap judged it independent): `canResend` is an InitialExpression from `$system.Security.Check` at page creation (`irislib/EnsPortal/VisualTrace.cls:92`), so the assertion does not depend on that session, and seeding an OCUORDERS order in O3 would race O2's asynchronous downstream headers.
- low -- the forms loop never checks the deadline (edge): it needs an IRIS that hangs during rows 5 and 6, CI's 40-minute job timeout bounds it, and the fix adds a guard.
- low -- F12's sign-in answer is not checked, so a failed sign-in would make F12 an F1-like post (edge): the guard's refusal holds on either path for both public accounts, and asserting the signed-in page present would reverse the U-81 ruling's "recorded, not asserted".
- low -- the 4-hour boundary between `NextReset()` and `/status` (edge): carried from the first review (about 1 s in 14,400; the fix is a retry branch).
- low -- overlapping copy presses (edge): carried from the first review (two presses inside one clipboard write; cosmetic).
- low -- the response watcher's late push and the listener that is never removed (edge): carried from the first review (`drawnMessages` polls for seconds before the assertion, and the final page is checked for the field too).
- low -- the rows' position below the reason line is not pinned (verification-gap): the template renders the rows after the reason line's `@if` (`header.ts`), AC 4's pin is O5, and a pin needs a routed-snapshot case.
- low -- `web/scripts/announce-focus-sources.test.mjs` is missing from the spec's footprint-extension list (auditor): the fix is a spec or contract edit. For the lead: list it under `footprint_extensions:` (two existing lines changed: the silent-file filter and one test title).
- false -- `seedOrder` could read another session's header (edge): the Orders production's partner service has PoolSize 0 (`Demo/Orders/Production.cls:13`), so only the case's own `Send` writes OCUORDERS headers, and its downstream headers get higher ids.
- false -- the credential value's `monospace` fallback is a literal, not a token (auditor): the declared family is the spec's `credential-card` token; the generic keyword applies only when the web font is missing, and without it the fallback would be the browser's default face.

## Spec Change Log

- 2026-10-25, lead (runner C), after the implement stage's `intent gap` halt on row 6: ruling (veto window, recorded in the run's inbox) -- row 6 and AC 2's last clause now say what AD-13, AD-24 and AD-25 already state: OcuTalon's own pages offer no password change; IRIS's own `%CSP.PasswordChange.cls`, which build 154 serves at the trace applications to a signed-in user whatever `PermittedClasses` holds, is covered by the guard (F12 asserts the refusal for both public accounts) and, on the online demo, by the demo host's proxy, which blocks every password-change page (AD-25, Story 29.3; the measured page path is filed in the ledger for Story 29.3). The Never list's ban on a `PermittedClasses` or application change stands. Status reset to `in-review`: the implementation is complete in the working tree and resumes at review.

## Review Triage Log

### 2026-10-25 - Review pass
- verdicts: 30 findings - high 0, medium 5, low 18, false 7, maybe-false 0
- findings:
  - `[low]` `[patch]` blind: sign-out coverage of the trace applications rests on the group-wide logout alone - `signOutGroup` now also sends each trace application's `?IRISLogout=end` (the script's `logout_all` already does both); a failed request is still not a failure of the case.
  - `[medium]` `[patch]` blind: "never in a log line, live event, production message or audit entry" has no test - the unit now searches the container output, messages.log and the after-start log, and the production event log (Ens_Util.Log), for both published passwords (`check_password_not_logged`); mutation recorded.
  - `[low]` `[reject]` blind: copy buttons have no keyboard coverage - they are native buttons, no AC or Boundaries line asks for a keyboard path, and the popover's keyboard cases are the floor project's; the fix is a new test surface for a behaviour the platform gives.
  - `[low]` `[reject]` blind: overlapping copy presses can show a stale result or orphan a timer - needs two presses within the milliseconds a clipboard write takes; cosmetic (a "Copied" cleared early); the fix adds a sequence guard.
  - `[low]` `[patch]` blind: the silent-files filter in `announce-focus-sources.test.mjs` leans on `&&` binding tighter than `||` - parenthesised the `&&` side.
  - `[low]` `[defer]` blind: StateBody's contract is documented only on the private `TraceAccount()` - the lead's gate for the shared `Web/Api.cls` forbids changing its existing lines; routed to `deferred:`.
  - `[low]` `[reject]` blind: a 4-hour reset boundary between `NextReset()` and the `/status` curl gives a false red - the window is about a second in 14,400; the fix is a retry branch.
  - `[low]` `[reject]` blind: `hexpw` and `dc stop`/`dc start` ignore errors - an empty password makes `redact`'s sed fail loudly and the forms' rows red, and a failed restart ends in `die` at `wait_started_ready`; no silent pass.
  - `[false]` `[reject]` blind: the `image` group gets heavier with no recorded timing - `## Verification` records 138 s for the unit and the guideline of 600 s for the group.
  - `[low]` `[reject]` edge: overlapping copy presses (the same claim as the blind row above) - carried to that row's reason.
  - `[low]` `[patch]` edge: an empty `page_token` makes F1, F3 or F12 at a trace application a request that never signs in, which would read as "unchanged" for a public account - each of the three call sites now fails the check when the token is empty.
  - `[low]` `[reject]` edge: `control_now` goes stale after a mismatched control outcome - the mismatch itself is already a FAIL line, which is the cause the reader needs.
  - `[low]` `[reject]` edge: the 4-hour boundary (the same claim as the blind row above) - carried.
  - `[low]` `[reject]` edge: the sign-in-page watcher may read a response body after the assertion - the assertion follows `drawnMessages`, which polls for seconds, so a document's body is long read; the fix adds promise bookkeeping.
  - `[false]` `[reject]` edge: another OCUORDERS header between `before` and the Send makes `seedOrder` open the wrong session - the Orders production has no poller or adapter (its service has PoolSize 0, `Partner.cls`), so no background header exists.
  - `[low]` `[defer]` edge: StateBody's comment does not list traceAccount (the same claim as the blind row above) - carried to the same deferred item.
  - `[medium]` `[patch]` verification-gap: the "Copied" and failure announcements are pinned by no running test - O5 and O6 now record the live region (`recordAnnouncements`) and assert one "Copied" per successful press and one failure text per failed press; mutations recorded.
  - `[medium]` `[patch]` verification-gap: the failure line clearing on the next copy is not pinned - O6 now ends with a successful copy and asserts "Copied" shows and the failure line is gone; mutation recorded.
  - `[low]` `[patch]` verification-gap: V7's local-popover assertions have no recorded mutation - applied "the header's traceAccount falls back to a fixed account", V7 red alone, reverted; line recorded.
  - `[false]` `[reject]` verification-gap: several rows (3, 13, 6, O1, O2) have no mutation of their own - Rule 19 asks one demonstrated mutation per AC and each AC has one; the layer calls it a note.
  - `[low]` `[reject]` verification-gap: overlapping copy presses (the same claim as the blind row above) - carried.
  - `[medium]` `[patch]` intent-alignment: no test reads the announcer for the copy texts - the same defect as the verification-gap announcements row, fixed once.
  - `[low]` `[reject]` intent-alignment: "Copied" is asserted gone within 5 s, not as lasting 2 s; the failure line's clearing on close and a missing `navigator.clipboard` are untested - 2000 ms is a constant a timing assertion would only make flaky, a missing clipboard throws into the same catch the rejection test exercises.
  - `[medium]` `[patch]` intent-alignment: the Never line on logs, events and audit has no scan - the same defect as the blind row, fixed once.
  - `[low]` `[reject]` intent-alignment: row 5 re-checks only the targeted account after its own form - a form carries one user name, so it cannot reach the other account; each public account is checked after its own forms.
  - `[false]` `[reject]` intent-alignment: README account "not enabled" against "disabled" - decided in-stage under `## Design Notes` (a fresh flag-on volume never creates it; absent or disabled both read 0).
  - `[false]` `[reject]` intent-alignment: row 3 must see existing empty rows - a missing row prints `<none>` and fails the check, so the check is strict.
  - `[false]` `[reject]` intent-alignment: Task 0's record is outside the diff - it is in `## Verification` ("Implement-stage results").
  - `[false]` `[reject]` intent-alignment: row 6's signed-in 200 is only a code comment - it is recorded in `## Verification` as the ruling asks (recorded, not asserted).
  - `[low]` `[reject]` intent-alignment: the watcher is never detached - it lives as long as the context, which ends with the case.

## Design Notes

**Architecture decisions:**
- **AD-19:** public values only through `OcuTalon.Data.Public.Settings`; `Setting.Get` delegates; the start values and their homes (already built; this story proves them on a real start).
- **AD-23:** `Public` second, readiness last; a restart reruns every step.
- **AD-13:** one sign-in group for `/ocutalon`, `/ocutalon/api` and the trace applications; password changes refused by the tested fallback; the no-role post-sign-in check; `InvalidLoginAction` 0.
- **AD-24:** the demo account holds `OcuTalonUser` and `OcuTalonTraceViewer`, the read-only account the trace role alone; the trace applications' seven permitted classes; page size pinned to 100.
- **AD-25:** the probe's backstop and the proxy's allow-list are the other layers; capacity is why every test signs out.
- **AD-12:** `/state` is the snapshot the page loads; `traceAccount` is a page-only field with no live event.
- **AD-3:** the public package is not touched. **AD-22:** throwaways only, `ci/iris.sh`. **AD-29, AD-33:** every file stays Lane B's except the read-only Lane A files named under Never.
- No AC contradicts an AD's Rule. The 120-second CSP timeout of AD-13 is Story 16.4's AC, not this story's.

**Already delivered (evidence) and what this story builds:**
- AC 1: the `Public` step and its writes (`Test.Install.Public.TestEveryStartValue`, `TestDefaults`, `TestBadStartValues`, `TestBudgetRows`, `TestReadyPinsThePublicAccounts`); the accessor and `NextReset` (`Test.Data.PublicSettings`); `Setting.Get`'s delegation, tested for one key (`Test.Data.Setting.TestPublicKey`); the global rule (`test-class-rules.sh` public-global). Every product reader of a public key goes through the accessor or `Setting.Get` (grep of `src/`: `Status`, `Users`, `Public`, `Api`, `Ownership`, `Msg.Catalog`); `Allowance.TryConsume` reads no allowance until Story 16.9. Built here: the real flag-on start (rows 1 to 3, 13) and delegation of every key (row 16).
- AC 2: the guard, its staging and self-check, and F1 in process (`Test.Install.Users.TestGuardWithFlagOn`, `TestGuardDecidesByNameAndPassword`, `TestInstallerWritesAChangedPassword`, `TestFailedGuardKeepsTheLiveGuard`; `Test.Install.Public.TestStartValuesReachTheUsersStep`); flag gating (`TestNoGuardWithFlagOff`). Built here: F1 to F11 over HTTP on a real start, the no-change-page check and the restart (rows 4 to 6, 13).
- AC 3: roles, trace applications and the no-role message are built (`Install.Step.Users`, `Web`, `Demo`; `Test.Web.Install.TestTraceApp`, `TestGrants`); only a no-roles user's message (`sign-in.spec.ts` row 12) and one 404 as the README account (`shell.spec.ts` row 10) are tested. Built here: rows 7 to 9 with the real read-only account.
- AC 4: the sign-in group is built; no test presses a link as the demo account without signing in again (`links.spec.ts`' `opensTab` fills the form when asked). The credential rows and the snapshot field do not exist. Built here: rows 10 to 12, 14 and the code.
- AC 5: a local install's flag, accounts, guard and cap seed are tested in process (`Test.Install.Users.TestReadmeAccountWithFlagOff`, `TestNoGuardWithFlagOff`; `Test.Install.Public.TestFlagOffWritesOnlyTheFlag`), and a real local start checks `onlineDemo` 0 (`live:install-start`). Built here: the local snapshot and popover pins (rows 14, 15); the unchanged key lists of `Test.Web.Api.TestStateBody`, `web/e2e/api/api.spec.ts:117` and `web/e2e/frame/frame.spec.ts:498` are the local pins and stay as they are.

**Decided in-stage:**
- **`traceAccount` only on the online demo**, absent otherwise: the local snapshot stays byte-for-byte the same shape (AC 5), and the key-list tests stay as they are. Read through `Setting.Get`, as `StateBody` already reads `onlineDemo`.
- **One live unit for the epic's flag-on stack**, `online-demo` in the `image` group: `browser`'s order is pinned by `test-demo-path-gate.sh`, `production` must stay web-bundle-free, and `image` is the second-smallest web-bundle group locally (255 s) and not the runners' longest (`install-upgrade`). Story 16.2 extends this script for the REL-2 online run.
- **The start values go in a `$tmp` override** through `live_add_file`, so no tracked compose file or contended script changes.
- **A project whose folder lies outside `web/e2e/`** (`web/e2e-online/`, project `online-demo`): the shared Playwright files take only new entries (the lead's rule), the chromium project's list is unchanged, and `tsconfig.e2e.json` gains one include so lint still type-checks the specs.
- **The S17 form set is reconstructed** from the categories that AD-13 and AD-25 name (the spike's eleven forms are not recorded in the repository), and Task 0 measures which forms change a password on build 154; both directions are pinned.
- **The forms run from curl in the script**, not from IRIS (`PasswordGuard.SignInChange`) or Playwright, which cannot send chunked or hand-encoded multipart bodies.
- **Test names** `DemoVisitor` and `TraceReader` (mixed case, so the capitals form tests case-insensitivity); random passwords per run.
- **Copy feedback**: "Copied" in the row for 2 seconds plus one announcement; the failure line stays until the next copy or close. A new `copy` icon from the Lucide set the page already uses.
- **Row labels** "User name" and "Password": the UX mockup's popover rows (`mockups/main-page.html:727-728`) and EXPERIENCE.md's labels (:701); no new public text.
- **No live local-install check is added**: the flag-off steps are the same code the in-process tests run, and a second fresh stack per run would push the unit near CI's 1,200 s deadline on the runner.
- **Implement stage (decided):** on a fresh flag-on volume the README account is never created, so row 4 asserts "not enabled" (absent or disabled). `OCUTALON_RESET_ANCHOR` and `OCUTALON_LAST_RESET` are quoted in the compose override (unquoted, compose rewrites the timestamp into a form the Public step refuses). `web/scripts/announce-focus-sources.test.mjs` exempts `credential-rows.ts` (it must announce "Copied" and the failure; the test required everything under `header/` to be silent). The key's contract is in `TraceAccount()`'s comment only, because the lead gate allows no other line to change in `Web/Api.cls`. `CHANGE_FORMS` entries are `<form>@<where>`, because F1 and F3 go to several URLs. F12 (IRIS's own password-change page at each trace application) was added to the unit as an extra form.
- **`check_security` is not called** on the flag-on stack: its README-account row expects the local install's enabled account.

**Integration ACs:** the header's popover consumes `/state`'s `traceAccount` on a real flag-on instance (row 11); IRIS's password paths consume the guard over HTTP (row 5); the trace applications consume the public accounts' roles through the sign-in group (rows 8 to 10).

**Consumes:** Story 3.8 (the `Public` step, the guard, the public accounts, `PinTrace`); Story 0.2 (the accessor); Stories 2.9 and 2.13 (trace links, the Visual Trace menu, `TRACE_TEXTS`, the trace e2e helpers); Story 2.2 (`Ownership`, one durable session per user until 16.3); Story 2.16 (`ux-strings`); Story 32.4 (warm mode).

**Consumed-by:**
- **Story 16.2:** the `online-demo` live unit and its test start values (the REL-2 online run); the same read-only values on the splash's Visual Trace card.
- **Stories 16.3, 16.5, 16.6, 16.8:** the flag-on stack for resume, busy, the probe and the countdown.
- **Story 29.4:** the flag-on start recipe for isolation under load.

**Rule 2 (extend, don't copy):**
- Extended: `StateBody` (a new method), `TRACE_TEXTS`, `IconName`, `FixtureKind`, links V7, `Test.Web.Api` and `Test.Data.Setting` (new methods beside `TestStateBody` and `TestPublicKey`), `ci/units.sh`.
- Reused: `lib-live.sh` helpers, `postTurn`, `drawnMessages`, `expectDrawn`, `irisScript`, `fillSignIn`/`signInOverHttp`, `Announcer`.
- The live script's shape follows `test-floor.sh`; its curl helpers are its own, because no sibling sends these forms. The cache-busting `probe=<n>` is `test-bundle-folder.sh`'s rule, not a copy of its function.
- The strict tab opener is new beside `links.spec.ts`' `opensTab`, whose contract (sign in when asked) is the opposite of row 10's.
- The Angular copy rows have no sibling. Story 16.2's splash copy buttons are server-rendered under AD-13's hashed inline script and cannot share an Angular component.

**Footprint extensions** (no contended path is edited): `docker/tests/test-online-demo.sh` (new), `web/e2e-online/**` (new), `web/tsconfig.e2e.json`, `web/src/app/shared/trace-view.ts`, `web/scripts/trace-view.test.mjs`, `web/scripts/ux-strings.test.mjs`, `web/src/app/icon/icon.ts`, `web/e2e/support/iris.ts`, `web/e2e/trace/links.spec.ts`. Shared files with new entries only: `web/playwright.config.ts`, `web/package.json`, `web/scripts/playwright-projects.test.mjs`, `ci/units.sh`. In footprint: `Web/Api.cls` (shared with Epic 4: a new method and one line), `Test/Web/Api.cls`, `Test/Data/Setting.cls` (a new method), `web/src/app/header/**`, `web/src/app/api/api-types.ts`.

**For the lead:**
- No veto-window item: no grant or role changes, and every text is already in the UX. `traceAccount` serves the read-only password to signed-in OcuTalon users on the online demo only; AC 4 asks for the rows "from the snapshot", and AD-19 calls the published accounts not secrets.
- Merge note: if Epic 4 also adds a `/state` key, the local key-list lines do not change here, so only `StateBody`'s body can meet.
- Rule 21 candidate after implement: the `online-demo` unit's measured time and its group.

**Ledger inbox:** none.

**Lead ruling on the implement-stage halt (2026-10-25, runner C; unattended, veto window):** the row 6 404 was the plan's own expectation, stricter than AC 2 and the spine. The spine's layering for IRIS's password-change paths is the proxy (AD-25: it blocks every password-change page and every `(IRIS|Cache)(Old|Repeat)?Password` field), the guard (AD-13, tested fallback) and the probe (backstop); AD-24's "no page OcuTalon serves offers it" is OcuTalon's own pages. So row 6 and AC 2 are restated, the unit keeps F12 as an asserted form (refused for both public accounts, measured outcome for the control), and the signed-in page's 200 is recorded in `## Verification`, not asserted absent. Reversal, if the owner wants a fourth layer: a follow-up story measures whether a trace-application setting can make build 154 refuse `%CSP.PasswordChange.cls` and, if so, sets it in `Install/Step/Web.cls`.

**Lead spec gate (2026-10-25, runner C):**
- Shared with Epic 4 by the orchestrator's ruling: `web/playwright.config.ts`, `web/scripts/playwright-projects.test.mjs` and `web/package.json` take new entries only; no existing line changes, header comments and count words included (Epic 4's branch already rewrote those headers; the count reconciles at integrate-forward as a plain union). `ci/units.sh`: your two tokens only (Epic 4 adds `live:demo-switch` to the same `image` line; a plain union at integrate-forward).
- `Web/Api.cls` and `Data/Setting.cls` are shared with Epic 4: a new method plus one call line in `StateBody`, and new test methods only; change none of the existing lines.
- If the `online-demo` unit's measured time would push the `image` group past about 600 s on CI beside Epic 4's `demo-switch`, record the measurement under Verification; the lead decides the group at commit.


## Verification

**Targets and variables:** run every command from the worktree root, in the foreground with `timeout: 600000`, one per call, never two test-runner calls in one message. Every `ci/iris.sh` and `ci/warm.sh` call carries lane C's three variables, written out on each command below for the implement stage; QA and review put their own stage name in `OCUTALON_LOCK_OWNER` and their own tags. Tags: implement `e16s1i` (fresh) and `e16s1iw` (warm); QA `e16s1q`/`e16s1qw`; review `e16s1r`/`e16s1rw`. The destructive checks (the flag on, the public accounts, the guard and every password form) run only in the `online-demo` unit's throwaway compose project of lane C (`ocutalon-<label>-e16s1i-<epoch>-<pid>`), never on `ocutalon-slot-c`. Each stage tears down only its own tags.

**Commands:**
- (loop) `bash ci/checks.sh` -- every block passes (`class-rules`, `ci-config`, `ci-changes`, `demo-path-gate` among them). About 20 s.
- (loop) `npm --prefix web test` -- every node test passes (`trace-view`, `ux-strings`, `playwright-projects`).
- (loop) `npm --prefix web run lint` -- `tsc` passes over `e2e/` and `e2e-online/`.
- (loop) `bash docker/tests/test-web-build.sh` -- the web build passes.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s1iw bash ci/warm.sh up` -- once at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e16s1iw bash ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Data.Setting`, `OcuTalon.Test.Data.PublicSettings` -- `CLASS ... passed` after a `WARM reloaded` line.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s1iw bash ci/warm.sh down` -- at the stage's end and after a failure.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s1i bash ci/iris.sh live online-demo` -- PASS, rows 1 to 13; record its time (expected about 250 to 350 s locally, inside the 540 s default deadline).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s1i bash ci/iris.sh shard lane-a` -- every class passes (about 7 minutes with its stack start; run it alone in its call).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s1i bash ci/iris.sh shard lane-b` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s1i bash ci/iris.sh live sign-in` -- PASS (V7's new assertion; the unchanged key-list specs).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s1i bash ci/iris.sh live floor` -- PASS (the popover's keyboard cases on a local stack).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s1i bash ci/iris.sh teardown` -- nothing tagged `e16s1i` is left.
- The install, production and other image units are left to CI: no installer, production or image input changes beyond `ci/units.sh`'s two entries, which `ci/checks.sh` covers.

**Shared surfaces:**
- `TRACE_TEXTS` (pinned by `web/scripts/trace-view.test.mjs` and `ux-strings.test.mjs`) and `IconName`.
- `/state`: `traceAccount` on the online demo only; the local key list is unchanged (`Test.Web.Api.TestStateBody`, `api.spec.ts:117`, `frame.spec.ts:498`).
- The Visual Trace popover's content: on the online demo it gains the rows; `links.spec.ts` V6 fakes `onlineDemo` without `traceAccount` and stays green; `floor/keyboard.spec.ts:502-528` runs on a local stack.
- The Playwright projects (five become six) and `ci/units.sh`'s `image` group and `BROWSER_UNITS` (`test-ci-config.sh`, `test-ci-changes.sh`).
- The public keys and readiness written by `TestStateTraceAccount` and `TestEveryPublicKeyIsDelegated` (restored).
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19; one per AC, each applied temporarily in the working tree, observed red, reverted byte-identical; a mutation of a Lane A file is such a temporary change, never part of the diff; a live mutation needs a fresh `live online-demo` run, and two mutations may share a run only when each red is attributable to its own row):

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `live online-demo` row 2 (`/status`) | `Status.cls` sets `nextReset` to null |
| AC 1 | `Test.Data.Setting.TestEveryPublicKeyIsDelegated` | `Setting.IsPublic` matches only `ready` |
| AC 2 | `live online-demo` row 5 | `Users.Accounts` skips `Guard` (a public account's password changes) |
| AC 3 | `readonly.spec.ts` O3 | `Web.PERMITTED` gains `EnsPortal.ProductionConfig` |
| AC 4 | `demo-account.spec.ts` O4 | `Users.DEMOROLES` drops `OcuTalonTraceViewer` (the tab cannot draw Visual Trace) |
| AC 4 | `demo-account.spec.ts` O5, O6 | `StateBody` omits `traceAccount`; the failure path skips the selection |
| AC 5 | `Test.Web.Api.TestStateTraceAccount`, links V7 | `TraceAccount()` ignores the flag |

### Implement-stage results (2026-10-25, build 154, lane C, tags `e16s1i` and `e16s1iw`)

**Task 0, the S17 forms on build 154** (the unit's first run, then re-measured with the trace applications' session token). The control user (no public account) is sent each form with its current password and a new one; "changes" means the new password then signs in and the old one is refused. The unit's `CHANGE_FORMS` (a request is `<form>@<where>`; where is `root` = `/ocutalon/`, `state` = `/ocutalon/api/v1/state`, `trace-ocutalon` and `trace-ocuorders` = the message viewers, `pwpage-ocutalon` and `pwpage-ocuorders` = F12):
- Changes the control's password (18 requests): `F1@root F1@state F1@trace-ocutalon F1@trace-ocuorders F2@root F3@root F3@state F3@trace-ocutalon F3@trace-ocuorders F4@root F5@root F6@root F7@root F8@root F9@root F10@root F12@pwpage-ocutalon F12@pwpage-ocuorders`.
- Leaves it: `F11@root` only (the mixed-case names).
- So, per form: F1 (POST, current names) and F3 (GET, current names) change it at every URL tried; F2, F4, F5, F6, F7, F8, F9 and F10 (legacy names, query string, encoded names, multipart, chunked) change it at `/ocutalon/`; F11 does not; F12 (IRIS's own password-change page at each trace application) changes it.
- For the demo account and the read-only account (name in capitals) every one of the 19 request kinds left the published password signing in (shell / no-role page) and the attempted one refused: the guard holds for every form.
- The first measurement posted F1 and F3 to the trace applications without the sign-in page's `IRISSessionToken` and read them as "unchanged"; a form posted without the token does not sign in at all, so that reading was invalid and the unit now sends the token (as a browser does).
- Row 6, signed in: `%25CSP.PasswordChange.cls` answers 200 (IRIS's password-change page: IRISUsername, IRISOldPassword, IRISPassword, IRISRepeatPassword), not 404, at both trace applications; with no session it is IRIS's sign-in page with no such field. Recorded under `deferred:`.

**The `online-demo` unit's measured time:** 138 s wall on this machine through `ci/iris.sh live online-demo` (image layers cached, Chromium installed; 73 PASS lines, rows 1 to 13), of which the six browser cases take about 9 s. Well inside the 540 s default deadline and far below the `image` group's 600 s guideline for CI beside `demo-switch`.

**Mutations (Rule 19; each applied temporarily, observed red, reverted byte-identical, checked by `shasum` against a backup and by `git status --short` / `git diff --stat` equal to the state before):**
- mutation: AC 1, `Status.cls` sets `nextReset` to null: `live online-demo` row 2 red ("nextReset is not what NextReset() computes ...").
- mutation: AC 1, `Setting.IsPublic` matches only `ready`: `Test.Data.Setting.TestEveryPublicKeyIsDelegated` red ("onlineDemo is read at once through Setting.Get").
- mutation: AC 2, `Users.Accounts` skips `Guard` (Lane A file, temporary): `live online-demo` row 5 red for 38 requests (a public account's password changes); reverted byte-identical.
- mutation: AC 3, `Web.PERMITTED` gains `EnsPortal.ProductionConfig`: `readonly.spec.ts` O3 red ("ocutalon: EnsPortal.ProductionConfig.zen answers 404").
- mutation: AC 4, `Users.DEMOROLES` drops `OcuTalonTraceViewer` (Lane A file, temporary): `demo-account.spec.ts` O4 red (the tab cannot draw Visual Trace); row 4 also red.
- mutation: AC 4, `StateBody` omits `traceAccount`: O5 red ("/state carries the read-only account"); and the failure path skips the selection (`this.select(row.key)` removed, web bundle rebuilt): O6 red alone ("the selection is exactly the password"), O5 green.
- mutation: AC 5, `TraceAccount()` ignores the flag: `Test.Web.Api.TestStateTraceAccount` red (flag 0 gives a `traceAccount`). Links V7 does not turn red from this mutation (a local stack has no read-only values), so TestStateTraceAccount is its pin.
The first four mutations shared one live run (rows 2, O3, O4 and the omit of O5 each red for its own mutation; O6 was red there too only because the omit also removes its rows).

**Loop commands run:** `bash ci/checks.sh` (all scripts passed), `npm --prefix web test` (566 pass), `npm --prefix web run lint`, `bash docker/tests/test-web-build.sh`, `ci/warm.sh up` (log `RESULT OK`), `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Data.Setting` and `OcuTalon.Test.Data.PublicSettings` on the warm stack, `ci/warm.sh down`, and the live unit (last clean run: all checks passed). Left for the parent: shard lane-a, shard lane-b, live sign-in, live floor.

### Review-stage results (2026-10-25, build 154, lane C, tag `e16s1i`)

Patches: `web/e2e-online/support.ts` (sign-out of each trace application too), `web/e2e-online/demo-account.spec.ts` (announcements in O5 and O6, a successful copy after the failures in O6), `docker/tests/test-online-demo.sh` (the published passwords searched for in the container output, messages.log, the after-start log and the event log; a missing session token fails the check), `web/scripts/announce-focus-sources.test.mjs` (parentheses). Row 6's code matches the restated row: no field on the sign-in page, none on the trace applications' page with no session, F12 asserted for both public accounts, the signed-in 200 recorded above and asserted nowhere.

- mutation: AC 4, `CredentialRows.copy` no longer announces "Copied" (the web bundle rebuilt): `demo-account.spec.ts` O5 red ("user: Copied is announced once").
- mutation: AC 4, `CredentialRows.copy` no longer clears the failure line (`this.failed.set(false)` removed): O6 red ("and takes the failure line away"); it shared the run with the line above, each red in its own test.
- mutation: AC 4, `CredentialRows.copy` no longer announces the failure: O6 red alone ("the failure is announced"), O5 green.
- mutation: Never (no password in a log), `TraceAccount()` writes the read-only password to the console log and to the event log: `live online-demo` red on two lines, "the read-only account's password: '2' line(s) of the container's output, messages.log or the after-start log hold it" and "the production event log holds neither published password".
- mutation: AC 5, the header's `traceAccount` falls back to a fixed account when the snapshot has none (bundle rebuilt): links V7 red alone ("a local install shows no credential row"), run through `live sign-in` (191 passed, 1 failed).
- Each mutation was reverted from a backup made before it; `shasum`, `git status --short` and `git diff --stat` equal the state before, and the bundle was rebuilt from the restored tree.

**Once lines after the last patch (all green):** `shard lane-a` (47 classes passed), `shard lane-b` (42 classes passed, `Test.Web.Api` and `Test.Data.Setting` among them), `live sign-in` (192 passed), `live floor` (70 passed), then `teardown` (nothing tagged `e16s1i` left). Loop lines after the patches: `bash ci/checks.sh` (all scripts passed), `npm --prefix web test` (566 pass), `npm --prefix web run lint`, and `live online-demo` (76 PASS lines, 116 s through `ci/iris.sh`, the unit's new log checks included).

### QA-stage results (2026-10-25, build 154, lane C, tag `e16s1q`)

Gaps found and closed, all in `web/e2e-online/demo-account.spec.ts` (extended; no new file) and run by the `online-demo` unit (Rule 8: under `web/e2e-online/`, so `ci/iris.sh live online-demo` runs them):
- (QA) O7, `web/e2e-online/demo-account.spec.ts`: the credential rows' keyboard path (row 11): the conversation link is the first focus, Tab reaches "Copy Visual Trace user name" then "Copy Visual Trace password", Shift+Tab goes back, Enter and Space each copy the exact value, focus stays on the button, and a later copy moves "Copied" to its own row.
- (QA) O8, same file: "Copied" lasts about 2 seconds (row 11): still shown 1 second after the press, gone within 2.5 s more (bounds chosen with 1 s of slack each side of 2 s, so the case is not flaky).
- (QA) O9, same file: no `navigator.clipboard` at all (row 12's other branch): the failure line shows, the selection is exactly the user name, the failure is announced; Escape closes the menu and a reopened menu has the rows and no failure line ("until the next copy or the popover closes").
- Row 14's "flag on and the user empty" was already pinned by `Test.Web.Api.TestStateTraceAccount` (checked, not added). The review's rejected items (overlapping presses, 4-hour boundary) were left rejected.

- mutation: AC 4, `CredentialRows` copy buttons get `tabindex="-1"` (bundle rebuilt): O7 red ("Tab reaches the user name button next").
- mutation: AC 4, `COPIED_MS` 2000 to 500: O8 red ("a second later it is still there"); `COPIED_MS` 2000 to 10000: O8 red ("and it is gone well before the timer could be long"; O5's 5 s bound went red too).
- mutation: AC 4, `CredentialRows.copy` returns silently when `navigator.clipboard` is undefined instead of throwing into the failure path: O9 red ("the failure line shows").
- The first three mutations shared one live run (each red in its own test: O7, O8, O9); the 10000 variant had its own run. Each was reverted from a backup made before it: `shasum` of `credential-rows.ts`, `git status --short` and `git diff --stat` equal the state before, and the bundle was rebuilt from the restored tree. Final `live online-demo` run after the last revert: 9 browser cases passed, all checks passed.

### Code-review results (2026-10-25, build 154, lane C, tags `e16s1r` and `e16s1rw`)

Patches (see `### Review Findings`): `Test/Web/Api.cls` (`TestStateTraceAccount` takes the flag-0 keys as its baseline), `web/e2e-online/demo-account.spec.ts` (O10, the scan), `docker/tests/test-online-demo.sh` (`check_logs_clean` with live events and audit, run again after the restart; row 13 against the literal guard; row 6 without a session checks for the sign-in page; the redaction comment), `web/src/app/header/credential-rows.ts` (the failure line's `circle-alert` icon), and `Web/Api.cls` (DW-217's two comments only).

- mutation: AC 5, `TraceAccount()` ignores the flag (its `onlineDemo` line removed), re-shown on the rewritten pin: `Test.Web.Api.TestStateTraceAccount` red ("flag 0 with both read-only values set: traceAccount is absent", "flag 0: no traceAccount among the keys (...,status,traceAccount)" and the three baseline comparisons); green again on the same warm stack after the revert.
- mutation: O10 (not an AC's pin; it shows the scan sees the rows), `.copied` coloured `--credential-card-background` (bundle rebuilt): O10 red alone ("span.copied \"Copied\": text 1.00:1 is under 4.5:1", the light scan after the page clock paused), the other nine cases green.
- AC 3's line (O3, `Web.PERMITTED` gains `EnsPortal.ProductionConfig`) still holds: O3's 404 loop is unchanged.
- Each mutation was reverted from a backup made before it; `shasum`, `git status --short` and `git diff --stat` equal the state before, and the bundle was rebuilt from the restored tree.

**Runs after the last patch:** `npm --prefix web run lint`, `npm --prefix web test` (566 pass), `bash ci/checks.sh` (all scripts passed); `ci/warm.sh up` (after-start log `RESULT OK`), `OcuTalon.Test.Web.Api` warm (passed); `ci/iris.sh build`, `live online-demo` (81 PASS lines, 10 browser cases passed, the new row 6, `after the first start` and `after the restart` checks among them); `ci/warm.sh down` and `teardown` (nothing tagged `e16s1r` or `e16s1rw` left). Not re-run here: `live sign-in` and `live floor` (no local-stack code changed: the rows render only with `traceAccount`), shards (no class but `Web/Api.cls` comments and `Test.Web.Api` changed).

## Auto Run Result

Status: done
Blocking condition: none

Summary: the online demo's flag-on live unit (`live online-demo`, 76 checks: start, keys, budget rows, accounts and guard, 12 password-change forms over HTTP, six browser cases, the log search and the restart), `traceAccount` in `/state` on the online demo only, and the Visual Trace menu's two credential rows with copy buttons. Row 6 and AC 2 follow the lead's restated layering (no OcuTalon page offers a password change; F12 is refused for both public accounts; IRIS's signed-in page is recorded, not asserted absent).

Files changed: `src/ocutalon/cls/OcuTalon/Web/Api.cls` (`TraceAccount()` and one call line), `Test/Web/Api.cls` and `Test/Data/Setting.cls` (new test methods), `web/src/app/header/credential-rows.ts` (new component), `header.ts`, `api-types.ts`, `trace-view.ts`, `icon.ts` (the rows, the key, the texts, the `copy` icon), `web/e2e-online/` (three files: the online-demo project's specs and sign-out helper), `docker/tests/test-online-demo.sh` (new unit), `ci/units.sh`, `web/playwright.config.ts`, `web/package.json`, `web/tsconfig.e2e.json`, `web/e2e/support/iris.ts`, `web/e2e/trace/links.spec.ts` (V7's local pins) and the node tests that pin the strings, the projects and the announcers.

Review: 30 findings from four layers - patches applied for 6 entries (the log search, the announcements, the failure line's clearing, the trace sign-outs, the empty session token, the V7 mutation line) plus one parenthesis fix; deferred 1 entry (StateBody's comment, two findings, shared-file gate); rejected 19 findings (12 low, 7 false) with the reasons in `## Review Triage Log`.

Follow-up review recommended: false. Three medium entries were patched (logs, announcements, failure line); each was verified by a demonstrated mutation and the (once) lines ran green after the last patch, so no unverified risk is left to name.

Verification: see `## Verification` (Implement-stage results and Review-stage results): `ci/checks.sh`, `npm --prefix web test`, `npm --prefix web run lint`, `live online-demo`, `shard lane-a`, `shard lane-b`, `live sign-in`, `live floor` and `teardown` all passed after the last patch.

Residual risks: the 4-hour boundary between `NextReset()` and the `/status` read in row 2 can give a rare false red; `signOutGroup` swallows a failed sign-out, so a held licence connection would show only as a later cap problem; the signed-in `%CSP.PasswordChange.cls` page stays reachable at the trace applications on build 154 (the guard refuses the change for both public accounts, and the demo host's proxy is the layer that blocks the page, Story 29.3).
