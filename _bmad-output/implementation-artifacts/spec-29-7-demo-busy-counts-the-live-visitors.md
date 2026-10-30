---
title: 'Story 29.7: Demo busy counts the live visitors'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: 'aa0027824465948397eff87c84e6d557a2f01501'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [multiple-goals, oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 29.4's plan measured that a signed-in online-demo visitor holds no licence connection on build 154. So AD-13's busy checks (`/ocutalon/public/status`, the splash and the post-sign-in reserve) never engage on visitors who stay out of Visual Trace, and a 7th visitor gets in (DW-251). Owner decision U-163 amended AD-13: busy also counts OcuTalon's own live visitor sessions against a visitor cap of about 6.

**Approach:** This story becomes the AD-13 visitor count. A proxied sign-in that attaches a visitor marks its own CSP session. The sessionless status and the login page count the marked CSP sessions that have not timed out, read from IRIS's own CSP session store without taking a session. Busy is reached at 6 counted visitors, the post-sign-in check refuses the 7th, and `OWNCONNECTIONS` is 0. The page's trace check reads `/status` in its trace form (`?for=trace`, whose `busy` comes from the connection check alone; U-169). The author's load run is Story 29.8's.

## Boundaries & Constraints

**Always:**
- Owner decisions U-163, U-169 and `epic29_brief` bind. U-163 and U-169 are quoted under Design Notes.
- No new global, table, property or storage definition. No grant to the demo, trace or public accounts.
- The count's reader takes no connection and no session, and reads only what any process may read.

**Never:**
- Connect to, configure or probe the demo host. Run `ocutalon-demo`, SSH or DNS commands.
- Edit `Install/**`, `src/cpf/**`, `docker/merge.cpf` or any other contended path. Write the spine.

</intent-contract>

## I/O & Edge-Case Matrix

Rows 1 to 6 and 9 run in the new live unit `live:online-visitors` (its browser step, `web/e2e-online/visitors/visitors.spec.ts`, case V1), with the proxy address set to the address IRIS sees for the host's requests, so every browser and API request is proxied and counted under its `X-Forwarded-For`. Row 7 runs in the same unit's bash part, row 8 in `live:online-demo` (`busy.spec.ts` B1 and B3), rows 10 to 12 in `Test.Web.Status` and `Test.Web.SessionEvents`, and row 13 in `live:online-demo` (rows 5 and 6). "Plain" is `/status` with no `for`; "trace" is `/status?for=trace`. The connection cap is 8 and the reserve 2 throughout, except row 8.

| # | Scenario | Input / State | Expected | Error handling |
|---|---|---|---|---|
| 1 | The 6th gets in (U-163 4) | Five browser visitors V1-V5 signed in from five addresses and polling. Plain and trace both report not busy, with no marker header. V6 signs in from the splash from a sixth address | V6 gets the shell. Then plain reports `busy: true` with `X-OcuTalon-Busy: 1` and status 200. Trace reports `busy: false` with no marker header. A fresh browser context's splash shows the busy error with the header | none |
| 2 | The 7th sees Demo busy (U-163 4) | The full house of row 1. A new browser context from a seventh address opens the splash and presses Sign in and start | Before sign-in the splash shows the busy error. The sign-in's answer is 200 with the busy error and the marker header: no shell, no resume cookie, `/state` 401, no new Session row and no counter row for the address | none |
| 3 | The probe's path is exempt (U-163 2) | The full house. The proxy address is set to one that no request comes from, a sign-in is made over HTTP, then the proxy address is put back and read back | The direct sign-in gets the shell and `/state` 200, and is not counted (row 4) | `setPublic` throws on a read-back mismatch; `finally` restores the address |
| 4 | Sign-out leaves the count (U-163 1) | The full house plus the direct session D. V6 signs out with the page's Sign out (account menu, then the dialog) | Plain reports not busy at the first read after V6 lands on the splash, while D is still signed in. D then signs out | none |
| 5 | Visual Trace at a full house (U-169 1) | V1-V5 and T (an API visitor from its own address that makes no request after its one `/state`). Plain busy, trace not busy. V1 presses Open my conversation in Visual Trace | The page asks `/ocutalon/public/status?for=trace&t=<13 digits>`, the trace window opens at the link's page and session, and no Demo busy banner shows | the case fails if no trace request was seen |
| 6 | The timeout leaves the count (U-163 1, 2) | Row 5's state. T makes no request after its `/state`. V1's trace session is alive | 110 s after T's last request plain still reports busy. By 140 s it reports not busy, while V1's trace session is still alive (another application's session never counts). Then a proxied sign-in from a new address gets in | the MEASURED line names the seconds |
| 7 | Every reset starts at 0 (U-163 3) | `/ocutalon`'s timeout set to 3600 s. Six proxied curl sign-ins from six addresses. Plain busy. Timeout back to 120 and read back. IRIS restarts | After ready, plain reports not busy with no header. The proxy address is set again and a proxied sign-in gets the shell. The six jars' `/state` answer 401 | the unit puts the timeout and the proxy address back on every path |
| 8 | Connection-busy with fewer than 6 visitors (U-169 2) | B1: two sessions, not proxied (count 0), the connection cap at the HTTP view plus the reserve | Plain and trace both report `busy: true` with the header. The page's trace press shows the banner and opens nothing. With the cap one higher both report not busy and the banner clears. B3's press asks with exactly the keys `for` (`trace`) and `t`, and so do its quiet re-checks | none |
| 9 | The query forms (U-169 3) | Row 5's full house. GETs with: `for=trace`; no `for`; `for=`; `for=Trace`; `for=trace%20`; `for=other`; `for=trace&for=trace`; `FOR=trace` | Only the exact single `for=trace` reports not busy. Every other form answers the plain form (busy). Every answer is 200 with exactly the keys `ready, nextReset, busy, lastReset, lastResetKind` and no `Set-Cookie` | none |
| 10 | The marker (unit) | In-process sign-ins (stand-in `%CSP.Session`) | A proxied create, and a proxied resume, set `Shell.VISITORKEY` to 1. The marker is not set on: a sign-in that is not proxied, a busy refusal, an address-limit refusal, the flag off, a user without the role | none |
| 11 | The count (unit) | `Visitors(store)` over a process-private fixture store: index nodes -2, -1 and 0; a marked session whose timeout is ahead; a marked one whose timeout has passed; an unmarked one ahead; a marked one with other data keys | Counts exactly the marked sessions whose stored timeout is ahead | none |
| 12 | The rule (unit) | `IsBusy(connections, cap, reserve, visitors)` and `Form()` | Visitors 5 is not busy, 6 and 7 are busy. The connection rule is unchanged. Without a valid cap the answer is never busy, at any visitor count. `Form()` is `trace` only for exactly one `for` whose value is `trace`. `OWNCONNECTIONS` is 0 | none |
| 13 | OWNCONNECTIONS 0 (live) | `test-online-demo.sh` rows 5 and 6: the cap at the HTTP view plus the reserve (status busy) | A proxied sign-in, and one with a valid resume cookie, are refused with the busy splash. With the cap one higher, a proxied sign-in is let in: the boundary is the status's own | none |

## Code Map

Line numbers are at `85719c93`.

**The busy rule and its consumers**
- `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls`:
  - the class doc (:1-10, AD-3's references);
  - `BUSYHEADER` :21; the UrlMap :23-28;
  - `Show` :46-53, which sets the header when `body.busy`;
  - `Body` :57-66;
  - `Busy(own)` :71-74;
  - `IsBusy(connections, cap, reserve)` :78-83: 0 without a valid cap.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`:
  - its doc :8-23 (the busy bullet :10-14);
  - `OWNCONNECTIONS = 1` :35;
  - `AttachVisitor` :64-100: the busy refusal first (:66-70, `REFUSALKEY`), then the resume (:71-75, `Quit sc` when a row resumes), then the creation, counted when proxied (:77-95), then the cookie (:96-98);
  - `ClientAddress` :114-120.
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`:
  - `REFUSALKEY` :25-27, the sibling of the new marker key;
  - `OnPreDispatch` :66-82 reads only `REFUSALKEY`.
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`:
  - :124 shows busy when `Status.Busy()` is 1;
  - :12-14 doc: "Without a valid connection cap Busy answers 0, so a local install never shows it". It stays unchanged.
- `web/src/app/api/api-client.ts`:
  - `PUBLIC_STATUS` :26;
  - `publicStatus()` :116-122 (`?t=${Date.now()}`). Its only caller is `DemoBusyState`.
- `web/src/app/live/demo-busy-state.ts`:
  - the module doc :15-23;
  - `openTrace` :44-53, `recheck` :56-63, `check` :66-75.
  - The callers `shared/trace-link.ts:199` and `header/header.ts:454` stay unchanged.
- Unchanged consumers of `/status`:
  - `docker/probe.sh` (plain form, the marker header, the splash text);
  - `release/demo-host-check.sh` (the five keys);
  - `web/src/app/live/reset-schedule.ts:33` (the reset pill).

**IRIS's CSP session store (read-only source, the same build)**
- `irislib/%CSP/Session.cls`:
  - `%SaveData` :874-929 writes `^%cspSession(id)` as a `$ListBuild` and the session's `Data` under `^%cspSession(id,0)`;
  - `UpdateTimeout` :798-838 moves the stored timeout on each request;
  - the index `^%cspSession(0,<timeoutAt>,id)`. Subscripts -2 and -1 hold other system nodes.
- `irislib/%cspBuild.inc:154-166`: `$$$sesOldTimeout` 3 (the absolute time the session ends) and `$$$sesApplication` 13.
- `irissys/%CSP/Daemon.cls`: `Run` :52-80 times sessions out from the index, and `SessionTimeout` :84-125.
- `irissys/%SYSTEM/CSP.cls`: `ClearSessionsOnRestart`, default 1 (:184), and `SetConfig` :170.

**Measured in this plan's Task 0** (a fresh lane-C online-demo throwaway, tag `e29s7plan`, build 154). A scratch script, not tracked, loaded two scratch class variants into that throwaway only: a marker after a proxied attach, and a sessionless `/zzt0` count with a scratch `Busy()` that is 1 at one marked session. It printed no password, session id or session data. The stack was torn down by its EXIT trap (nothing tagged `e29s7plan` is left).
- MEASURED (a): after a proxied sign-in, three `/api/v1/state` requests and one `/ocutalon/` GET, the store holds the marked session (application `/ocutalon/`, 119 s left), and the sessionless reader counts 1.
- MEASURED (b): after the group sign-out (`/ocutalon/?IRISLogout=end`, which the page's Sign out and the idle cap send), the session's node is gone (`$Data` 0) and the count reads 0.
- MEASURED (c): `ClearSessionsOnRestart` is 1. After a restart (18 s to ready), a marked session with a 3600 s timeout is gone, the count reads 0, and its jar's `/state` answers 401. So every IRIS start, and therefore every reset, empties the store whatever the golden copy holds.
- MEASURED (d): `/ocutalon/public` reads the store as `UnknownUser`, with roles "" and namespace OCUTALON. With one marked session, the scratch rule made `/status` busy with the header, and a fresh jar's splash showed the busy text with the header.
  - `^%cspSession` resolves to IRISLOCALDATA, on the durable volume, from both OCUTALON and %SYS.
  - `%DB_IRISLOCALDATA`'s public permission is R.
- MEASURED (timeout): the count dropped 121 s after the session's last request, and the daemon deleted the node at 124 s. Story 16.4 measured 152-153 s for the delete, so the daemon's delay varies, and the count follows the stored timeout, not the daemon.

**Tests that pin today's shapes** (Shared surfaces, Verification)
- `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls`:
  - `TestBodyWithSettings` :31 and `TestBodyWithoutSettings` :58 (the five keys);
  - `TestIsBusy` :73;
  - `TestBusyHeader` :114;
  - `TestBusyOwn` :139 (the `own` arithmetic; it stays);
  - `TestReferencesOnlyThePublicAllowList` :209, which scans `##class`, `$SYSTEM` and dynamic calls, not globals or includes.
- `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls`:
  - `SignIn` :719-732 (a stand-in `%CSP.Session.%New(id, 0)`, so `session.Data` is readable);
  - `ForceBusy` :361 (cap 1, reserve 9);
  - the busy cases :252, :290, :312, :338;
  - `TestFirstSignIn` :71, `TestResume` :129, `TestLimit` :207, `TestNoRoleOnTheOnlineDemo` :606.
- `docker/tests/test-online-demo.sh`:
  - the header's busy paragraph :48-55;
  - `set_proxy` :813, `host_address` :816-818 and the proxied precondition :822-850;
  - `counter_rows` :590;
  - `status_read` :945-957;
  - rows 1 and 2 :1046-1100 (`cap_busy` = view + reserve, `cap_free` = cap_busy + 1);
  - rows 5 and 6 :1116-1186 (S5 at `cap_busy` let in, S3 and S4 at `cap_refuse` = cap_busy - 1 refused, `OWNCONNECTIONS` read at :1119);
  - the cap and proxy restore :1196-1210.
  - Story 29.6, ready-for-dev and built first, edits only the probe phase.
- `web/e2e-online/busy.spec.ts`: B1 :81-178 (`readStatus` at :104 and :159), and B3 :287-327 (`['t']` at :306; the re-check route :312-317).
- `web/e2e-online/support.ts`:
  - `openVisitor` :229-244 and `leaveVisitor` :246-251 (Story 29.4);
  - `signInOverHttpFrom` :258-262, `readStatus` :295-300, `httpConnections` :308-325, `setPublic` :279-286, `removeSession` :202;
  - `opensTabStrict` :421 and `expectOpenedDirectly` :435;
  - `pressSignOut` :522 and `confirmSignOut` :529.

**The new unit's siblings**
- `docker/tests/test-online-allowance.sh`: the start :25-44 and `run_e2e` :75-85.
- `docker/tests/lib-online.sh`: the header :1-17, `online_signin` :88-106 and `logout_all` :77-82.
- `docker/tests/lib-live.sh`: `wait_started_ready` :377 and `check_session`.
- `web/playwright.config.ts` :62-80, the online projects; the online-demo project's `testIgnore` is at :69.
- `web/package.json` :20-23.
- `ci/units.sh`: `install-fresh` :40, `BROWSER_UNITS` :98 and the group comment :25-30.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` -- add `Parameter VISITORKEY = "OcuTalon.Visitor"` beside `REFUSALKEY`. Its doc says it is the CSP session data key that the sign-in hook sets to 1 for a proxied visitor and that `Status` counts; the class doc's online-demo bullet names it -- the marker lives in the public class that both the hook and the status may name (AD-3), the `REFUSALKEY` mechanism of lead ruling 2.
- `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls` -- extend the rule in place (Rule 2: the siblings are `Busy` and `IsBusy`):
  - `Parameter VISITORCAP = 6`.
  - `Form()`: `"trace"` when the request's query holds `for` exactly once with the value `trace`, else `""`.
  - `Body(form As %String = "")` with `busy` = `Busy(0, form)`. `Show` passes `..Form()` and keeps the header rule (the header whenever `body.busy`).
  - `Busy(own As %Integer = 0, form As %String = "")`:
    - 0 without a valid cap, so the store is never read on a local install;
    - else 1 when the connection check holds;
    - else, in the trace form, 0;
    - else 1 when `Visitors() >= VISITORCAP`;
    - a store read that throws counts as busy.
  - `IsBusy(connections, cap, reserve, visitors As %String = "")`: the pure rule, with the visitor clause added.
  - `Visitors(store As %String = "^%cspSession")`: counts the store's sessions (from subscript 0 onward, so that -2, -1 and 0 are skipped) whose `$ListGet(data, $$$sesOldTimeout)` is ahead of now (`$ZTimeStamp` in whole seconds) and that hold `(id, 0, Shell.#VISITORKEY)`. The positions come from `Include %cspBuild`.
  - The class doc states the two forms, the rule and the reader, and adds IRIS's CSP session store (%CSP's) to the references -- U-163 and U-169 as AD-13 now reads.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls` -- `OWNCONNECTIONS = 0`, with its doc: the new session holds no licence connection when OnLogin runs (Story 29.4's measurement), so the check leaves none out. After a proxied attach that succeeds, the resume and the creation alike, set `%session.Data(Shell.#VISITORKEY) = 1`. Never set it on a refusal or on an exempt (not proxied) sign-in. Update the class doc's bullets -- U-163's OWNCONNECTIONS and condition 2.
- `web/src/app/api/api-client.ts` -- `publicStatus()` asks the trace form, `${PUBLIC_STATUS}?for=trace&t=${Date.now()}`, and its doc says so. In `web/src/app/live/demo-busy-state.ts`, only the module doc changes: the check and its re-check read the trace form -- U-169: `openTrace` and its re-check.
- `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls` -- covers rows 11 and 12 and the trace form:
  - `TestIsBusy` gains the visitor cases (5, 6 and 7; no valid cap at 6);
  - new `TestVisitorCount`, over a `^||` fixture store with row 11's nodes;
  - new `TestTraceForm`: `Form()` for each of row 9's query forms, set through `%request.Data`. `Body("trace")` and `Body("")` both have exactly the five keys. With `ForceBusy`-style settings, both forms are busy and `Show` sets the header. With a high cap, neither is busy and there is no header;
  - the header doc names them.
- `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls` -- new `TestVisitorMarker` (row 10's seven cases, read from `session.Data`), plus a one-line `OWNCONNECTIONS` = 0 assertion. Search the class for any assertion on the whole of `session.Data` and update it. The header lists the test.
- `docker/tests/lib-online.sh` -- move `host_address`, `set_proxy`, `status_read` and `counter_rows` here from `test-online-demo.sh`, unchanged, and list them in the header's stack helpers -- Rule 2: the new unit needs them. `test-online-host.sh` and `release/demo-host-check.sh` source this file and call none of them.
- `docker/tests/test-online-demo.sh` -- use the moved helpers and delete its copies. Rows 5 and 6 re-pin at `OWNCONNECTIONS` 0 (row 13):
  - S3, and S4 with S2's cookie, are refused at `cap_busy`;
  - S5 at `cap_free` is let in (the shell, a cookie, one counter row);
  - the pass texts say that the boundary is the status's own (the check leaves out no own connection);
  - `cap_refuse` goes;
  - the header :48-55 and the Task 0 (d) MEASURED line say so.
- `web/e2e-online/support.ts` -- extend, don't copy:
  - `openVisitor(browser, address?)` sets `extraHTTPHeaders: {'X-Forwarded-For': address}` when an address is given;
  - `readStatus(api, form?: 'trace')` adds `for=trace` before its probe query;
  - add `statusAnswer(api, query)`, which returns the code, the parsed keys, `busy`, the marker header and whether `set-cookie` is present;
  - add `counterRows(address)` and `removeCounterRows(address)` (irisScript over `AddressCounter.AddressHash`), and `sessionRowCount()`.
- `web/e2e-online/busy.spec.ts` -- row 8. B1: at the busy cap, `readStatus(status, 'trace')` is `{busy: true, header: '1', code: 200}` beside plain's; after the cap is raised, both are not busy. B3: the press asks with the keys `['for', 't']` and `for` = `trace`, and every recorded re-check URL carries `for=trace`. The header doc says so.
- `web/e2e-online/visitors/visitors.spec.ts` (new) -- case V1 runs rows 1 to 6 and 9 in that order, in one test, as the row texts say:
  - The test timeout is 360 s. It runs in full Chromium with its popup blocker on, as `busy.spec.ts` does.
  - Addresses are `198.51.100.71` to `.80`, one per visitor.
  - V1 posts one turn (`postTurn`) for its trace link.
  - T's last request is its one `/state`, and its clock starts after it.
  - The 140 s bound is polled every 2 s and prints `MEASURED V1: T left the count <s> s after its last request`.
  - `finally`: sign every context out (`signOutGroup`), `removeSession` every epoch, `removeCounterRows` every address, and put the proxy address back.
  - The header says what it pins and needs.
- `docker/tests/test-online-visitors.sh` (new) -- the `live:online-visitors` unit, modeled on `test-online-allowance.sh`:
  - the start; `set_proxy "$(host_address)"`;
  - a proxied precondition: one curl sign-in writes one counter row for its forwarded address, or the unit dies naming the address;
  - the browser step `npm --prefix web run e2e:online-visitors` with `OCUTALON_URL`, the two accounts and the container;
  - row 7: `check_session %SYS` reads `ClearSessionsOnRestart` 1, then the restart case as the row says (`dc restart iris`, `wait_started_ready`), timed;
  - the proxy address back to `$proxy_start` and read back;
  - MEASURED lines (the browser step's seconds, the restart's seconds, the unit's seconds);
  - header per Rule 14. No password is printed.
- `web/playwright.config.ts`, `web/package.json` -- add the project `online-visitors` (`testDir: './e2e-online/visitors'`, Desktop Chrome) and add `'**/e2e-online/visitors/**'` to online-demo's `testIgnore`. Add the script `e2e:online-visitors`. Both are footprint_extensions.
- `ci/units.sh` -- `install-fresh` becomes `live:install-start live:bundle-folder live:cards live:online-visitors`, `online-visitors` joins `BROWSER_UNITS`, and the group comment gains one sentence (the unit and its expected time) -- the lead's CI ruling; a minimal edit to one group line.

- **DW-333 (routed to this story by the lead after CI run 41116344208, 2026-10-30; a lead edit of the validated spec):** `web/e2e/demo-path/01-page.spec.ts:92` failed in `live:demo-path` waiting 10 s for `main.main` `data-snapshot` right after `signInReadme`, the DW-333 pattern Story 29.4 fixed elsewhere. Give `signInReadme` (and every other sign-in the demo-path specs and the online reset, resume, splash and session specs still make without it) the `loadedAfter` wait from `web/e2e/support/floor.ts`; no assertion changes. Verify with `live demo-path` and `live online-session` once (fresh), and record a `mutation:` (the old wait with a held GET `/state` goes red; `loadedAfter` stays green).

**Acceptance Criteria:**
- **AC1 (U-163 4; Integration ACs: the status, the login page and the post-sign-in check consume the count).** Given `live:online-visitors` with five proxied visitors signed in, when a sixth and then a seventh visitor sign in from their own addresses, then the sixth gets the shell, plain `/status` and a fresh splash report busy with the marker header, and the seventh sees the busy text before and after pressing Sign in, with no shell, cookie, session, Session row or counter row (rows 1 and 2).
- **AC2 (U-163 2).** Given the full house, when a sign-in that is not proxied (the probe's path) signs in, and later a counted visitor signs out, then the direct sign-in gets the shell and plain `/status` reports not busy while it is still signed in. A visitor's open trace session never counts (rows 3, 4 and 6).
- **AC3 (U-163 1).** Given six counted visitors, when one signs out with the page's Sign out, then plain `/status` reports not busy at once. When one makes no request, then it is still counted 110 s after its last request and not counted by 140 s, and a new proxied visitor then gets in (rows 4 and 6).
- **AC4 (U-163 3).** Given six counted sessions with a 3600 s CSP timeout, when IRIS restarts, then plain `/status` reports not busy, a proxied sign-in gets the shell, and the six sessions are gone (row 7).
- **AC5 (U-169 1; Integration AC: the page's trace check consumes the trace form).** Given the full house with connections under the cap minus the reserve, when a signed-in visitor presses Open my conversation in Visual Trace, then the page asks `/status?for=trace`, the trace window opens at the link's page with no banner, the trace form reports not busy, and plain `/status` reports busy (row 5).
- **AC6 (U-169 2).** Given connections at the cap minus the reserve and fewer than 6 visitors, when the status is read and a visitor presses a trace link, then both forms report busy with the header, and the page shows the busy text and opens nothing. One cap higher, both are free and the banner clears (row 8).
- **AC7 (U-169 3).** Given the full house, when `/status` is asked with each query form of row 9, then only exactly one `for=trace` answers the trace form, and every answer has exactly the five keys and no `Set-Cookie` (rows 9 and 12).
- **AC8 (U-163: OWNCONNECTIONS 0).** Given `live:online-demo`'s busy rows with the status busy from connections, when a proxied sign-in arrives, then it is refused with the busy splash, and with the cap one higher it is let in (row 13).
- **AC9 (unchanged surfaces).** Given the story's diff, when it is listed, then `docker/probe.sh`, `release/demo-host-check.sh`, `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls` and the spine are unchanged.
- **AC10 (standing, Rule 19).** Given a fresh environment, when the story's added and changed tests run forward and then in reverse order, then every one passes.

## Spec Change Log

- 2026-10-30, lead: the plan HALTed (split recommended; AD-13's trace-window bullet). Rulings 1 and 2 applied (story retitled and split, 29.8 added; the count's home accepted); ruling 3 is with the orchestrator. The spec stays `blocked` until that ruling.

- 2026-10-30, lead: ruling 3 answered (U-169, kept with three test conditions); status reset to `draft` for the re-plan.

- 2026-10-30, re-plan (runner C, plan stage), lead ruling 1:
  - The intent block was edited where it named the load run, the split or the old scope:
    - Problem: the sentence on the author's load run (DW-286) was removed; it is Story 29.8's;
    - Approach: "(as proposed in the split, Design Notes "HALT")" was removed, the sentence on the load script was replaced by the trace form (U-169) and "The author's load run is Story 29.8's.";
    - Always: U-169 now binds beside U-163 and `epic29_brief`, and the quote of `epic29_brief`'s load-run bullet left with it.
  - The HALT section, the load script's Code Map part and the Design Notes on 29.8's plan were removed: they are Story 29.8's input, in the git history of this file.
  - The I/O matrix sits after the intent block, because the preserved block had none.
  - Task 0 measured ruling 2's four points and the timeout. All held, so the design is the ruled one.
  - KEEP: the count derived on read from the CSP session store, no new storage, the marker only on a proxied attach.

- 2026-10-30, lead: DW-333 routed here (a Tasks & Acceptance item added) after a CI red in `live:demo-path` on Story 29.6's head.

## Review Triage Log

### 2026-10-30 - Review pass
- verdicts: 24 rows (the layers' findings, one row per root cause with the layers named) - high 0, medium 4, low 20, false 0, maybe-false 0; 5 patched, 19 rejected with reasons
- findings:
  - `[medium]` `patch` (edge-case) `web/scripts/playwright-projects.test.mjs` pins the four online scripts and goes red with the new project - confirmed by `npm --prefix web test` (2 failures, CI's `web` job); the test now lists the fifth project, with its own case; green (1127 pass).
  - `[medium]` `patch` (verification-gap) `Busy`'s fail-closed catch and its no-cap short-circuit have no observing test - added `TestBusyStoreFailure` (one unparseable node in the instance's store; removed also on a throw); two mutations red, recorded.
  - `[low]` `patch` (verification-gap) a resume that is not proxied is never checked for the marker - added the case to `TestVisitorMarker`; mutation red, recorded.
  - `[low]` `patch` (blind-hunter, edge-case, verification-gap) `Include %cspBuild` sits between the class description and `Class` in `Web/Public/Status.cls` and `Test/Web/Status.cls`, where the repo puts `Include` first - moved to line 1 of both; both classes compile and pass.
  - `[low]` `patch` (blind-hunter) `test-online-visitors.sh` header says the proxy address and timeout are put back "on every path" but a `die` before the restore skips it - the header now states the paths.
  - `[medium]` `reject` (blind-hunter, edge-case, verification-gap) `live:online-visitors` in `install-fresh` leaves little headroom against the 40-minute timeout - the group is the lead's CI ruling named in the spec's task and Design Notes 14; the expected 35 to 37 min is an inference the next full CI run measures (local run: 240 s). Spec-bound, closed by-design; to be watched at the CI run.
  - `[medium]` `reject` (blind-hunter) `OWNCONNECTIONS` 1 to 0 rests on thin evidence - the spec rules it (U-163; Story 29.4's measurement, row 13) and the re-pinned rows 5 and 6 observe the boundary live (185 PASS in `live:online-demo`). By-design.
  - `[low]` `reject` (blind-hunter, edge-case) a store node that is not a list makes the status busy with no log - fail-closed is Design Notes 4 (no false all-clear, the probe's `busy` alert tells the author); every `^%cspSession(id)` node is a `$ListBuild` that IRIS writes. wontfix-theoretical; the path is now tested.
  - `[low]` `reject` (blind-hunter, edge-case) `Visitors` scans the whole session store per unauthenticated request - a demo instance holds a few dozen sessions, and the derived-on-read count with no new storage is the ruled design (lead ruling 2). wontfix-theoretical.
  - `[low]` `reject` (blind-hunter, edge-case) two sign-ins at 5 visitors can both get in - Design Notes 8 (AD-13's "about 6"). By-design.
  - `[low]` `reject` (blind-hunter) `visitors.spec.ts` reads the session list at positions 13 and 3 as a literal - the helper's doc names the positions, and an oracle that does not share the product's macro is the point of a live check. Cosmetic.
  - `[low]` `reject` (blind-hunter, edge-case) DW-333 edits ~20 existing specs in this change - the spec's task item routes it here. By-design.
  - `[low]` `reject` (blind-hunter, verification-gap) V1 row 1's `sessionRowCount() >= 6` is weak - row 2 pins the count by equality across the 7th's sign-in (`rowsBefore`), so a vacuous row 1 cannot hide a defect.
  - `[low]` `reject` (edge-case) a re-save of a session's data briefly drops the key (`SaveData` kills and merges node 0) - a window of microseconds that can undercount by one in a count that is "about 6"; wontfix-theoretical.
  - `[low]` `reject` (edge-case) other callers of `signInReadme` (demo-switch, frame) keep the DW-333 race - the spec names the demo-path specs and the online specs; the other callers are outside the footprint and no red is recorded for them.
  - `[low]` `reject` (verification-gap) AC9 and AC10 have no `mutation:` line - neither has a pinning test that could be mutated (a diff listing; run order). By-design.
  - `[low]` `reject` (verification-gap) `TestTraceForm`'s not-busy cases read the real store and need fewer than 6 live marked sessions - no test class creates a marked session in the real store; the throwaway starts empty. wontfix-theoretical.
  - `[low]` `reject` (intent-alignment, descriptive) the splash and the login page are exercised only by the live units, not by a unit - the splash is unchanged by AC9 and live row 1 and the 7th's splash pin it.
  - `[low]` `reject` (intent-alignment, descriptive) a `?for` parsing contract, fail-closed, row 7 and the CI group go beyond the intent's words - each is named in the spec (U-169, Design Notes 4, task list).
  - `[low]` `reject` (intent-alignment, descriptive) `signInReadmeLoaded` edits are unrelated to the visitor count - DW-333.
  - `[low]` `reject` (intent-alignment, descriptive) the unit tests use a private store and `ForceBusy`, not six real visitors - the live unit's V1 is the real-visitor proof (AC1).
  - `[low]` `reject` (intent-alignment, descriptive) the real store layout is exercised only live - Task 0 measured it and V1's row 6 and row 7 observe it.
  - `[low]` `reject` (intent-alignment, descriptive) the page's trace query is asserted only by Playwright - B3 and V1 row 5 observe it on the real bundle.
  - `[low]` `reject` (intent-alignment, descriptive) assumptions about `^%cspSession` and `%session.Data` at OnLogin were not run by the auditor - they are the live unit's passing marker and count, measured.

## Design Notes

**Owner decision U-163** (`apply U-163 at=2026-10-30T09:33:18Z#496`, the Contest Planner under the owner's delegation). It binds, quoted:
> option (a): amend AD-13 so busy also counts OcuTalon's own live demo visitor sessions against a cap of about 6 (the owner's figure, P12/NFR-23, unchanged), kept where the sessionless `/status` and the login page can read it. OWNCONNECTIONS becomes 0, and the InstanceConnections check stays as the trace-licence guard. Conditions: (1) a session leaves the count on sign-out and on its timeout (about 120 s, as measured), so a crashed tab can't hold a place; (2) the probe and the admin path never count; (3) the count starts at 0 at every reset; (4) the tests prove a 7th visitor sees Demo busy while a 6th gets in.

**Owner decision U-169** (`apply U-169 at=2026-10-30T16:49:58Z#512`, the Contest Planner under the owner's delegation; condition (2) clarified by the Planner, `1a087baa`): the trace form as lead ruling 3 states it, with the Planner's three test conditions (AC5 to AC7). `epic29_brief` binds here through its hard boundary (the demo host is the owner's; Never). Its load-run bullet is Story 29.8's.

**Architecture decisions that govern this story (Rule 6):**
- AD-13, as amended under U-163 and U-169: the visitor count, busy, the post-sign-in check, the trace form and `/status`'s five keys.
- AD-3: the public package's references. Status names Shell (its own package) and %CSP's store.
- AD-4: visitor sessions and the sign-out.
- AD-19: no new public key. The visitor cap is a class parameter.
- AD-22: tests, throwaways and CI groups.
- AD-25: the probe's direct connection, resets and capacity.
- Never edit AD-13 or the "(inference ...)" lines of AD-13 and AD-25: the orchestrator writes Task 0's measured facts there at the merge.

**Lead rulings (2026-10-30; runner C, unattended policy 6df0676):**
1. **The split is accepted (decide; Rule 5 tier 2 within `split_children`).** This story is retitled "Demo busy counts the live visitors" (key `29-7-demo-busy-counts-the-live-visitors`; this spec file renamed to match) and keeps U-163's conditions 1 to 4 and DW-251; Story 29.8, "The author's load run measures the demo's capacity" (key `29-8-the-author-s-load-run-measures-the-demo-s-capacity`), takes the real-proxy load criterion verbatim and DW-286 (re-owned). The load-script part of this plan is 29.8's input; remove it from this spec at the re-plan.
2. **The count's home is accepted (decide; within the orchestrator's rule):** derived on read from IRIS's own CSP session store, each proxied visitor's CSP session carrying one marker in its session data (the `REFUSALKEY` mechanism); no new global, key, table or mapping. The re-plan's Task 0 measures the four unmeasured points (the marker survives to the next request; sign-out deletes the session; a restart empties the store; a sessionless request can read it) on a lane-C throwaway before any code; a failed measurement is a new intent gap.
3. **AD-13's trace-window bullet is amended (orchestrator ruling, veto U-169, kept by the Contest Planner with three test conditions; `apply U-169 at=2026-10-30T16:49:58Z#512`; the amendment arrived by the integrate-forward of 2026-10-30, never edit AD-13 here):** the page's trace check (`openTrace` and its re-check) uses `/status?for=trace`, whose `busy` comes from the connection check alone; `/status` keeps the same five keys in both forms; the `for` value is an exact match, and any other or missing value, or a repeated parameter, answers the plain form; the endpoint stays unauthenticated and sessionless. The Planner's conditions, now criteria in `epics.md`: (1) with 6 visitors signed in and connections under cap minus reserve, `/status?for=trace` reports not busy and a REAL signed-in visitor opens Visual Trace (not only the `/status` answer); (2) with connections at cap minus reserve and fewer than 6 visitors, the trace form reports busy and the page shows the busy text, while plain `/status` keeps its own rule (busy from the connection check OR the visitor count, so it is busy here too) — plus a case with the visitor count at the cap and connections low, where plain is busy and trace is not; (3) any other or missing `for` value answers the plain form, and both forms keep the same five keys with no extra field. The probe, the splash and `release/demo-host-check.sh` stay unchanged.
4. **Order:** this story is re-planned now (during Story 29.5's CI rerun) and built after Story 29.6. The re-plan's Task 0 measures the four points of ruling 2 on a lane-C throwaway first; if any fails, it is an intent gap (the lead returns to the orchestrator before any other store is chosen).

Task 0 result: all four points of ruling 2 held (Code Map, MEASURED (a) to (d)), so no intent gap.

**Decided in-stage:**
1. The marker is `Shell.VISITORKEY = "OcuTalon.Visitor"`, value 1: a CSP session data key beside `REFUSALKEY`, not a settings key, global or table.
2. The visitor cap is `Status.VISITORCAP = 6`, a class parameter (ruling 2: no new key). It is independent of the connection cap, so lowering `connectionCap` in a test (row 8) leaves it alone.
3. Without a valid connection cap, both clauses answer 0 and the store is never read. So a local install never shows busy (Splash's existing guarantee), and the connection check runs first.
4. A store read that throws counts as busy: fail closed, so there is no false all-clear and the probe's `busy` alert tells the author. Measured to work for `UnknownUser`.
5. A busy answer carries the marker header in both forms (the proxy counts busy answers per day).
6. `for` is matched exactly (`trace`, case-sensitive, untrimmed, exactly once). Other query names (`t`, `probe`) are ignored.
7. The count reads the session's stored timeout. So a session leaves at about 120 s (measured 121 s) whether or not the daemon has deleted it yet (124 s here, 152 s in Story 16.4). Row 6's bounds (still counted at 110 s, gone by 140 s) leave margin on both sides.
8. Two sign-ins in the same instant at 5 counted visitors can both get in, because the marker is saved at the end of the sign-in request and no lock can span to that save. AD-13's "about 6" covers it, and the tests are sequential.
9. AD-13's post-sign-in sentence says "when connections exceed the cap minus the reserve" and also "the new session holds no connection of its own, so the connection check counts none for it". With `OWNCONNECTIONS` 0 (U-163, named), the post-sign-in check is `Busy(0)`, the status's own rule (connections reach the cap minus the reserve). The old "exceed" counted the new session's own connection, which U-163 removed. This is noted for the orchestrator's merge-time AD-13 update, not edited here.
10. The admin path never counts by construction: only `AttachVisitor`'s proxied branch writes the marker. The live proofs are the probe's path (a direct sign-in, row 3) and another application's session (V1's trace session, row 6).
11. Row 7 gives its sessions a 3600 s timeout, so only an emptied store reads 0 whatever the restart's duration. The unit puts the timeout back to 120 and reads it back.
12. Condition (2)'s live case extends `busy.spec.ts` B1 (it already sets connections at the cap minus the reserve with fewer than 6 visitors) rather than repeating it.
13. The store's positions come from `%cspBuild.inc` (`$$$sesOldTimeout`) through the class's `Include`. Data's subscript 0 has no macro and is pinned by Task 0 and the live unit. If the include cannot be used in the public class, a `Status` parameter of 3 is pinned by a `Test.Web.Status` assertion against `$$$sesOldTimeout` (Rule 2, a copy with its reason).
14. The new unit is `live:online-visitors`, with its own throwaway, in `install-fresh` (the lead's CI ruling).

**Integration ACs (Rule 1):** AC1 (the status, the splash and the post-sign-in check), AC5 (the page's trace check) and AC2 (the probe's exempt path), each against a real stack.

**Consumes:**
- IRIS's CSP session store on build 154 (`^%cspSession`: `$$$sesOldTimeout`, Data under subscript 0) and `ClearSessionsOnRestart` 1.
- Story 16.3's `AttachVisitor` and `ClientAddress`.
- Story 16.5's busy rule, `BUSYHEADER`, the splash's busy state and `DemoBusyState`.
- Story 16.4's 120 s CSP timeout and the group sign-out.

**Consumed-by:**
- Story 29.8: the author's load run, whose "one more visitor sees the busy text" step reads the splash and plain `/status`.
- `docker/probe.sh` (Story 16.6, unchanged): plain `/status`, so a full house alerts `busy` (alert only).
- `release/demo-host-check.sh` (Story 29.3, unchanged): the five keys.

**Extends (Rule 2):** each new helper extends the sibling the Tasks name:
- `Status.Busy` and `IsBusy`, in place;
- `Shell.REFUSALKEY`'s mechanism;
- `AttachVisitor`'s existing branches;
- `support.ts`'s `openVisitor` and `readStatus`;
- the four bash helpers, moved into `lib-online.sh`;
- `test-online-allowance.sh`'s unit shape.

**Ledger inbox (Rule 17):** DW-251 is addressed: the visitor count engages busy with no connection held (AC1, AC3; rows 1 to 6). It closes at adjudication.

**CI:**
- `live:online-visitors` is expected to take about 8 to 10 min on CI (inference):
  - a start of 160 to 230 s;
  - a browser step of about 210 s, mostly V1's 140 s bound after T plus six sign-ins;
  - the restart case, about 100 s;
  - set-up and teardown.
- `install-fresh` (about 27 min expected after the lead's move) becomes about 35 to 37 min (inference). That is inside the 40-minute job timeout and at or below `install-upgrade`'s measured 37, which already sets the run's wall-clock. It returns to about 29 to 31 min when Epic 9's merge moves `live:cards` (346 s on run 40961979510) to `shards`.
- `live:online-demo` gains about 5 s (B1's two status reads).
- MEASURED locally (lane C, `OCUTALON_LIVE_DEADLINE=1200`, as CI sets it; implement stage):
  - `live:online-visitors`: the unit took 240 s, of which the start took about 90 s; the browser step took 129 s (V1 2.1 min); `MEASURED V1: T left the count 121 s after its last request`; the restart took 18 s to ready. So the unit is about 4 min locally, under the 8 to 10 min CI inference above (the inference stays for the slower CI host);
  - `live:online-demo`: 7 min 22 s end to end locally (the browser step 206 s, 362 s at that point), all checks passing with rows 5 and 6 re-pinned;
  - `live:demo-path` 2 min 42 s and `live:online-session` 5 min 40 s locally, with DW-333's `loadedAfter` waits.
- The push changes `src/`, `ci/` and `web/`, so every IRIS group runs.

**footprint_extensions:** none of these is contended:
- `web/playwright.config.ts`: one project, and one `testIgnore` entry of online-demo;
- `web/package.json`: one script.
- `web/scripts/playwright-projects.test.mjs`: the node test that pins the Playwright projects' listing gains the `online-visitors` project and its case (the story's config change turns it red otherwise).
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls`: pins each public class's parameters, so it lists `VISITORKEY` and `VISITORCAP`.

The rest is in the footprint: `Web/Public/**`, `Web/SessionEvents.cls`, `Test/Web/**`, `web/src/app/**`, `web/e2e-online/**`, `docker/tests/test-online-*.sh` and `lib-online.sh`. `ci/units.sh` changes only its own entries.

## Verification

Run every call in the foreground with `timeout: 600000`, one test call per message, against named lane-C targets.
- `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement'`.
- The fresh tag is `e29s7i` and the warm tag `e29s7iw`.

**Commands:**
- (loop) `for f in docker/tests/lib-online.sh docker/tests/test-online-demo.sh docker/tests/test-online-visitors.sh; do bash -n "$f" || echo "$f"; done`. Expected: no output.
- (loop) `npm --prefix web run lint`. Expected: exit 0.
- (loop) `bash docker/tests/test-ci-config.sh`. Expected: every check passes.
- (loop) `LANE OCUTALON_RUN_TAG=e29s7iw bash ci/warm.sh up` once. Then, one per call:
  - `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e29s7iw bash ci/iris.sh class OcuTalon.Test.Web.Status`;
  - `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e29s7iw bash ci/iris.sh class OcuTalon.Test.Web.SessionEvents`.
  - Expected: `CLASS ... passed`.
  - At the stage's end, also after a failure: `LANE OCUTALON_RUN_TAG=e29s7iw bash ci/warm.sh down`.
- (once) `LANE OCUTALON_RUN_TAG=e29s7i bash ci/iris.sh build`. Expected: the web bundle is built from this `web/src` (Rule 21).
- (once) `LANE OCUTALON_RUN_TAG=e29s7i bash ci/iris.sh class OcuTalon.Test.Web.Status`, then, in its own call, the same for `OcuTalon.Test.Web.SessionEvents`. Expected: each `CLASS ... passed` on a fresh throwaway (about 90 s each).
- (once) `LANE OCUTALON_RUN_TAG=e29s7i bash ci/iris.sh live online-visitors`. Expected: every PASS, V1 passed and the MEASURED lines. It takes about 6 min (inference: Task 0's start took 109 s and its restart 18 s).
- (once) `LANE OCUTALON_RUN_TAG=e29s7i bash ci/iris.sh live online-demo`. Expected: every PASS, including rows 5 and 6 at `OWNCONNECTIONS = 0`, B1 and B3 (about 310 to 370 s, Story 29.6's figure).
- (once) `bash docker/tests/test-online-host.sh`. Expected: it passes with the moved helpers in `lib-online.sh`.
- (once) `bash ci/checks.sh`. Expected: every block passes, `ci-config`, `class-rules`, `boundaries`, `lib-live` and `online-host` included (about 4 min).
- (once, before the finalize commit) `git diff --stat HEAD -- docker/probe.sh release/demo-host-check.sh src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls _bmad-output/planning-artifacts/architecture`. Expected: no output (AC9).
- (once, at the end, also after a failure) `LANE OCUTALON_RUN_TAG=e29s7i bash ci/iris.sh teardown` and `LANE OCUTALON_RUN_TAG=e29s7iw bash ci/iris.sh teardown`. Expected: nothing tagged `e29s7i` or `e29s7iw` is left.

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> → <test red>` when run:**
- AC1: `VISITORCAP = 7`. V1 goes red at "plain busy after the sixth"; so does `TestIsBusy`'s 6 case.
  - mutation: `VISITORCAP = 7` -> `Test.Web.Status` red at `TestIsBusy` ("6 visitors are busy", "the visitor cap is 6"), observed on the warm stack; tree restored byte-identical.
- AC1, the post-sign-in check: `AttachVisitor` calls `Busy(..#OWNCONNECTIONS, "trace")`. V1 goes red at "the seventh gets the busy splash".
  - mutation: `AttachVisitor` calls `Busy(..#OWNCONNECTIONS, "trace")` -> V1 red at row 2, "the sign-in is answered with 200" (received 303, the shell); tree restored byte-identical.
- AC2: mark every attach, the exempt ones included. V1 goes red at "not busy after V6's sign-out while D is signed in"; so does `TestVisitorMarker`.
  - mutation: also mark the not-proxied creation -> V1 red at row 4, "the plain status is not busy at the first read after V6 lands on the splash" (live), and `TestVisitorMarker` red ("a sign-in that is not proxied is not marked", warm); tree restored byte-identical.
- AC3, sign-out: the step's mutation is that V6 closes its context without Sign out. V1 goes red at "not busy at once". The condition rests on IRIS deleting the node, so no product line can keep a signed-out session.
  - mutation: V6 closes its context in place of pressing Sign out -> V1 red at row 4, "the plain status is not busy at the first read after V6 lands on the splash" (the session stays counted until its timeout; row 7 of that run also read 5 of 6 shells for the same reason); the spec file restored byte-identical.
- AC3, the timeout: `AttachVisitor` also sets `%session.AppTimeout = 900` with the marker. V1 goes red at "not busy by 140 s". `TestVisitorCount` without the timeout comparison goes red too.
  - mutation: `%session.AppTimeout = 900` set with each marker -> V1 red at row 6, "by 140 s the plain status reports not busy" (live); `Visitors` without the `> now` comparison -> `TestVisitorCount` red ("the marked sessions whose timeout is ahead are counted, and nothing else", warm); tree restored byte-identical.
- AC4: a temporary line in the unit, after its `ClearSessionsOnRestart` check and before the restart, runs `$SYSTEM.CSP.SetConfig("ClearSessionsOnRestart", 0)` in %SYS. Row 7 goes red: plain is busy after the restart.
  - mutation: that line added to `test-online-visitors.sh` -> V1 passed and row 7 red: "after the restart the plain status read 'true 1 200'", no shell for the proxied sign-in, 0 of 6 jars answering 401; script restored byte-identical.
- AC5: `Form()` always answers `""`. V1 goes red at "the trace window opens". `publicStatus` without `for=trace` turns B3's keys red.
  - mutation: `Form()` always answers `""` -> V1 red already at row 1, "with the sixth in ... the trace form is not busy" (before the trace window is reached); `publicStatus` without `for=trace` -> B3 red at "the press: the query holds exactly for and t"; tree restored byte-identical (the web bundle was rebuilt after the restore).
- AC6: `Busy` answers 0 in the trace form. B1 goes red: the trace form is not busy, and a window opens.
  - mutation: `Busy` answers 0 in the trace form before the connection check -> B1 red at "the trace form is busy as well, with the marker header and the status code 200" (run together with the AC5 web and AC8 mutations in one `live online-demo` run, each failing in its own test); tree restored byte-identical.
- AC7: `Form()` compares with `$ZConvert(...,"L")`. `TestTraceForm` (the `for=Trace` case) and V1's row 9 go red. A sixth key in `Body` turns `TestTraceForm`'s keys red.
  - mutation: `Form()` compares with `$ZConvert(...,"L")` -> `TestTraceForm` red ("for=Trace is the plain form", warm) and V1 red at row 9 (`?for=Trace`, live); a sixth key `extra` in `Body` -> `TestTraceForm` red ("exactly the five keys in the form ''" and 'trace', also `TestBodyWithSettings` and `TestBodyWithoutSettings`); tree restored byte-identical.
- AC8: `OWNCONNECTIONS = 1`. `test-online-demo.sh` row 6 goes red: at `cap_busy` the proxied sign-in is let in.
  - mutation: `OWNCONNECTIONS = 1` -> `test-online-demo.sh` rows 5 and 6 red: at `cap_busy` S3 and the cookie sign-in (S4) are let in ("status '303'"), so "the sign-in past the boundary was refused=0"; tree restored byte-identical.
- AC2, a resume that is not proxied (review patch): `AttachVisitor`'s resume line without the `proxied` condition.
  - mutation: the resume marks every attach, the exempt included -> `TestVisitorMarker` red ("a resume that is not proxied is not marked", warm); tree restored byte-identical.
- Fail-closed and no-cap (Design Notes 3 and 4; review patch): `Busy`'s `Catch` sets busy to 0, or its no-cap early return is removed.
  - mutation: `Catch` sets `busy = 0` -> `TestBusyStoreFailure` red ("a store that cannot be read counts as busy"); the no-cap early return removed -> `TestBusyStoreFailure` red ("without a valid cap the store is not read"), both on the warm stack; tree restored byte-identical.
- The projects list (review patch): `web/scripts/playwright-projects.test.mjs` without the `online-visitors` case and listing failed on the first `npm --prefix web test` after the story's config change (two cases red: online-demo's list and "every spec file ... is listed"); green after.
- DW-333: the old wait (`signInReadme`, then `main.main` `data-snapshot` loaded at the default 10 s) with a GET `/state` held for 12 s goes red (10.2 s); `signInReadmeLoaded` (`loadedAfter`) with the same held `/state` stays green (12.3 s). Observed with a scratch spec in `live demo-path`, removed afterwards; tree byte-identical.

**Shared surfaces:**
- `/status`'s shape and query, read by:
  - `release/demo-host-check.sh` and `test-online-host.sh`;
  - `docker/probe.sh` and `test-probe.sh`'s stub;
  - `test-online-demo.sh`'s `status_read`;
  - `support.ts`'s `readStatus`;
  - `busy.spec.ts` B3's query keys.
- The busy rule:
  - `Test.Web.Status`, `Test.Web.SessionEvents`;
  - `test-online-demo.sh` rows 1 to 6 and the probe's P4;
  - `busy.spec.ts` B1 to B3.
- `OWNCONNECTIONS`: `test-online-demo.sh` rows 5 and 6 and its header.
- The page's trace check: B1 and B3, `trace-link.ts` and `header.ts`.
- The probe's markers (`X-OcuTalon-Busy`, the splash's busy text), unchanged.
- `%session.Data`'s keys: `Test.Web.SessionEvents`.
- The visitor count itself: any online unit that holds 6 or more proxied sessions at once. Today none does (inference: `test-online-demo.sh`'s busy rows hold S1, S2 and one more at once, and its other proxied sign-ins sign out one by one). The implement stage searches `docker/tests` and `web/e2e-online` to confirm it.
- `lib-online.sh`'s function set: `test-online-host.sh` and `release/demo-host-check.sh` source it.
- `ci/units.sh`'s groups and `BROWSER_UNITS`: `test-ci-config.sh`.
- The online-demo project's `testIgnore`.

The implement stage searches `docker/tests`, `web/e2e-online`, `web/e2e`, `release/` and `src/ocutalon/cls/OcuTalon/Test` for each of these. Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage, re-dispatch 1 (2026-10-30, runner C, unattended).** Planned only; nothing was implemented.
- Task 0 ran on one fresh lane-C online-demo throwaway (tag `e29s7plan`, port 52803, lane-C lock), with scratch class variants loaded into that throwaway only.
- All four points of lead ruling 2, and the timeout, held (Code Map, MEASURED lines).
- The throwaway was torn down by its EXIT trap, and nothing tagged `e29s7plan` remains.
- No slot or MCP target was used.

**Implement and review (2026-10-30, runner C, unattended; the stage that finalizes this spec).**
- Summary: the visitor count. `Shell.VISITORKEY` marks the CSP session of a proxied attach (resume and creation); `Status` gains `VISITORCAP = 6`, `Form()`, `Body(form)`, `Busy(own, form)`, the visitor clause of `IsBusy` and `Visitors(store)`; `SessionEvents.OWNCONNECTIONS` is 0; the page's trace check asks `?for=trace`. New unit `live:online-visitors` (case V1: rows 1 to 6 and 9; row 7 in the bash part) in `install-fresh`; the four bash helpers moved to `lib-online.sh`; `test-online-demo.sh` rows 5 and 6 re-pinned; B1 and B3 extended. DW-333: `signInReadmeLoaded` (floor.ts) and the sign-ins of the demo-path and online specs wait for the loaded snapshot.
- Files changed: `Web/Public/Shell.cls`, `Web/Public/Status.cls`, `Web/SessionEvents.cls`; `Test/Web/Status.cls`, `Test/Web/SessionEvents.cls`, `Test/Web/PublicTexts.cls`; `web/src/app/api/api-client.ts`, `web/src/app/live/demo-busy-state.ts`; `web/e2e-online/support.ts`, `busy.spec.ts`, `visitors/visitors.spec.ts` (new), and the sign-ins of `reset`, `resume`, `splash`, `session/*`; `web/e2e/support/floor.ts` and `web/e2e/demo-path/*`; `web/playwright.config.ts`, `web/package.json`, `web/scripts/playwright-projects.test.mjs`; `docker/tests/lib-online.sh`, `test-online-demo.sh`, `test-online-visitors.sh` (new, executable); `ci/units.sh`.
- Review: 5 patches applied (the projects node test, the fail-closed/no-cap test, the non-proxied resume case, `Include` placement, the unit header) and 19 rows rejected with reasons (Review Triage Log). Patched by verdict: medium 2, low 3. Nothing deferred.
- Follow-up review recommended: false (no HIGH patched; two MEDs patched, both test-side).
- Verification (all green): `bash -n`, `npm --prefix web run lint`, `npm --prefix web test` (1127 pass), `test-ci-config.sh`; warm `Test.Web.Status`, `Test.Web.SessionEvents`, `Test.Web.PublicTexts`; fresh `Test.Web.Status` and `Test.Web.SessionEvents` after the last patch; `live online-visitors` (240 s), `live online-demo` (185 PASS, 7 min 22 s), `live demo-path`, `live online-session` and `test-online-host.sh` (before the review patches, which touch only tests, `Include` placement and a header comment); `ci/checks.sh` after the last patch; AC9's `git diff --stat` empty. Every AC has a recorded mutation.
- footprint_extensions: `web/playwright.config.ts`, `web/package.json`, `web/scripts/playwright-projects.test.mjs`, `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls`, and for DW-333 `web/e2e/demo-path/**`, `web/e2e/support/floor.ts`, and the sign-ins of `web/e2e-online/**`.
- Residual risks: `install-fresh` is expected at 35 to 37 min against its 40-minute timeout (inference; the next full CI run measures it). `live:online-visitors` is unmeasured on CI. Row 7 assumes V1 signed every context out; a silent sign-out failure could skew its reading. The live units were run with `OCUTALON_LIVE_DEADLINE=1200`, as CI sets it.
