---
title: 'Story 29.4: Sessions stay isolated under load'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: '23e7b0461e34bed64768a43ca951075a2be83399'
baseline_commit: '23e7b0461e34bed64768a43ca951075a2be83399'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [oversized]
deferred:
  - summary: >-
      Two more online visitors still sign in with the pre-DW-333 order (sign-in, then a 10 s wait for data-snapshot), so a slow GET /state can still fail them.
    evidence: |-
      web/e2e-online/allowance/daily-cap.spec.ts visit() and web/e2e-online/allowance/messages.spec.ts open() call signInFromSplash and then expect data-snapshot="loaded". Matrix row 10 and the task list name openFloor, banners' open() and openVisitor only, so loadedAfter was not applied to them. Pre-existing, found by the verification-gap layer.
    location: >-
      web/e2e-online/allowance/daily-cap.spec.ts:69, web/e2e-online/allowance/messages.spec.ts:50
    severity: low
---

<intent-contract>

## Intent

**Problem:** On the online demo every visitor signs in with the same demo account. No test yet follows a real Break the feed (incident, notice, approval request) while a second visitor watches the same Orders production, so nothing proves that one visitor's run stays out of another visitor's views and answers. REL-2's online run still skips its trace step and has no second visitor. Four small ledger entries wait on this story: DW-252, DW-333, DW-413 and DW-236.

**Approach:** Give REL-2's online run its own Playwright project and live unit, with the model keys pointed at the CI mock. Turn on its step 6 (the trace link) and add a second visitor: A and B each watch Orders from the guide, and A presses Break the feed. The test asserts that A's incident, notice and approval request reach only A; that B's page, `/state`, `/events` and an answer with A's reference get nothing and change nothing; and that A then answers. The paired-chat cases stay present and skipped for Story 31.4. The fourth criterion (the author's real-proxy load case), DW-286 and DW-251 moved to Story 29.7. The four ledger entries are fixed beside the run, DW-236 by an environment pass-through in `lib-live.sh`'s `iris_script` and `check_session`.

## Boundaries & Constraints

**Always:**
- Owner decision `epic29_brief` binds. It is quoted under Design Notes.
- The stack is a fresh online-demo throwaway with `lib-online.sh`'s test start values and the CI override (the model mock and the mock Telegram API). The runners' keys point at the mock (`keys_point`) for the browser step.
- Two visitors are two browser contexts that sign in from the splash with the demo account. Each waits for its GET `/api/v1/state` answer (200) before using the page.
- The incident path is the real one: A's page button, the real IncidentManager and the real diagnosis (the mock's `diagnosis` scenario). No double, and no seeded incident or request.
- Each case creates and removes its own state. In `finally` it signs every context out of the sign-in group (`signOutGroup`), removes its sessions (`removeSession`) and cleans the rows it seeded.
- These parts are `notBuilt(..., '31.4')` and never pass: A's paired chat, a press from B's paired chat, and the third criterion's message search.
- Steps 2 to 5 of the online run stay `notBuilt(..., '11.1')`.
- The new live unit goes into `shards-2` only. `production` and `browser` take nothing.
- Files under `docker/tests/` are ASCII. No tracked file holds a local path, host, address or key.

**Never:**
- Connect to, deploy to, configure or probe the demo host. Run `ocutalon-demo`, SSH or DNS commands.
- Edit these:
  - `docker/tests/lib-live.sh` outside `iris_script` and `check_session` (Epic 12's branch changes it at lines 18-19, after `check_log` and in `live_ci_bot_token`);
  - `web/e2e/demo-path/**`, the web run, which is Story 11.1's;
  - any Lane A class;
  - any contended path.
- Change product behaviour. If the isolation test finds a leak whose fix lies outside this story's footprint, stop with a clarification that names it (Rule 11).
- Build the fourth criterion's load script or its procedure, or change AD-13, AD-25 or the busy rule (`OWNCONNECTIONS`). They belong to Story 29.7 (parked, U-163).

## I/O & Edge-Case Matrix

The online run is `web/e2e-online/demo-path/demo-path.spec.ts`, in the unit `live:online-demo-path`.

| # | Scenario | Input / State | Expected | Error handling |
|---|---|---|---|---|
| 1 | A's run (AC1) | A and B are signed in. Each watches Orders, started from its own guide watch prompt. A presses Break the feed on its page | Within 90 s, A has: the incident card awaiting approval (Approve and Reject) in the chat; the notification with A's request ref on the simulated phone; "Approval requests (1)" in the rail | none |
| 2 | B untouched (AC1) | After A's card shows: B's page, `/state`, and `/events` from B's cursors read before the press | B's page has no incident card, phone notification, approval row or new phone message. B's `/state` `guide` deep-equals the one read before, and B's Break the feed is still enabled. Since the cursor, no B-stream event has type `incident`, `approval`, `phone`, `breakfeed.progress` or `watch.progress`. A's incident and request Refs appear nowhere in B's `/state` or `/events` bodies | none |
| 3 | Rows stay their own (AC1) | Each session has a seeded reminder, a fixture pairing (A "Ana", B "Ben") and one incoming mail, plus its own watch turn and Orders check | Before and after the press, each `/state` shows exactly its own turn, reminder, check, pairing name and mail item. A has 50 orders under A's TraceRef, B has 0 | none |
| 4 | B answers A's request (AC2) | B sends `POST /api/v1/approvals/<A's ref>/answer` `{action: approve, channel: web}` with the envelope headers | 404 with the unknown-ref body `{"error":{"code":"not_found",...}}`. A's row stays `pending`, and A's card still offers Approve and Reject. No `approval` event on either stream since | none |
| 5 | A still answers (AC2) | A's card offers Approve and Reject (the web channel). A presses Approve on its simulated phone | The phone and the card show the phone channel's answered status, and the row leaves `pending`. The case waits for the row to leave `executing` before cleanup | none |
| 6 | Step 6, the trace (AC1) | The Trace link on A's watch turn's decision | A new tab opens at the link's `traceUrl` (path and `SESSIONID`), and no trace document holds a sign-in field. Visual Trace draws the turn's header and at least `agentStepCount` other messages. The decision details show the turn's steps and cost | none |
| 7 | Paired chat and message search (AC1, AC2, AC3) | none | Three skipped cases, each saying "Story 31.4 turns this on". The unit fails if any of them passes or is missing | none |
| 8 | DW-252 | Online demo. The guide's prompt button is pressed while `POST /api/v1/messages` answers 503 once | The entry leaves: no bubble, no `.failed`, no "Retry sending", the composer stays empty, and nothing announces "Message not sent". The demo-busy banner shows, as in B2 | none |
| 9 | DW-413 | A daily-cap case (D1, D2 or AP) starts with fewer seconds left before instance midnight than its budget | It waits past midnight, then reads the instance day once and uses that day for every mark, check and cleanup | A browserless case, D0, pins the guard with a fake clock |
| 10 | DW-333 | `openFloor`, banners' `open()` and the online visitors sign in | Each waits for the GET `/state` answer (200), then for `data-snapshot="loaded"` | With `/state` held for 12 s, the wait still passes |

</intent-contract>

## Code Map

**The online run and the web run's steps**
- `web/e2e-online/demo-path.spec.ts`: REL-2's online run (Story 16.2). Step 1 is real; steps 2-6 are `notBuilt(..., '11.1')` at :29-33, imported from `../e2e/demo-path/not-built` (:3). It moves to `web/e2e-online/demo-path/demo-path.spec.ts` (the import becomes `../../e2e/demo-path/not-built`).
- `web/e2e/demo-path/not-built.ts:11-14`: `notBuilt(title, story)` runs `test.skip(true, 'Story <id> turns this on')`.
- `web/e2e/demo-path/04-incident.spec.ts`, `05-approval.spec.ts`, `06-trace.spec.ts` (read-only) give the selectors and the step-6 title:
  - card: `app-chat-panel [data-part="approval"][data-key="<ref>"]`
  - phone: `app-simulated-phone .notification[data-key="<ref>"]`
  - rail row: `app-status-rail li.row[data-row-key="approvals:<ref>"]`
  - rail count: `app-status-rail [data-section="approvals"] h3 .visually-hidden`
  - answer: `p[data-part="answer"]`

  Their helpers find the session by user name (`Session.ForUser`), which the online demo cannot use. Use `support.ts`'s epoch-based helpers instead.

**Online helpers**
- `web/e2e-online/support.ts`:
  - `signInFromSplash` :51 waits for the POST only. Also `epochOf` :84 and `openSession` :91.
  - `sessionRow(epoch)` :177 returns `ref` and `traceRef`. `removeSession` :201.
  - `populate` :344 makes a reminder, a StartWatch, a fixture approval and a fixture pairing. `cleanPopulated` :411.
  - `seedIncomingMail(epoch, count, oldestAge)` :510.
  - `localToday` :563, `cappedMarked` :568, `unmarkCapped` :573, `seedUsage` :588.
  - `irisScript` and `chk` come from `web/e2e/support/iris.ts`.
- `web/e2e-online/demo-account.spec.ts:57-80`: `opensTabStrict` and `expectOpenedDirectly`. In O4 they check that the trace tab is at `traceUrl`, no document is a sign-in page, and the turn is drawn. Also `web/e2e/support/trace.ts:103` `postTurn` and `:143` `drawnMessages`.

**The demo path's pieces**
- The watch prompt: its text at `web/src/app/guide/guide-view.ts:32`; the button `app-demo-guide [data-guide-focus="action"]` (`web/src/app/guide/demo-guide.ts:179-187`) calls `outbox.send(text, true)` (:571-580). The mock answers it with `ci/mock/scenarios/B/guide-watch.json` (prompt match); `ci/mock/scenarios/A/diagnosis.json` (mockkey `diagnosis`) returns the `repair_resend` fix.
- Break the feed: the button `app-break-feed-box app-server-button button` (`web/e2e-online/allowance/daily-cap.spec.ts:196-200`). Count orders with `Test.Demo.Production.Count(trace,"OrdersFromPartner",8)`, which `04-incident.spec.ts` polls.
- `web/src/app/chat/decision-details.ts:76,81`: the decision's steps and cost rows, used by step 6.

**Server side (read-only) and existing isolation tests**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: `AnswerApproval` (:478-492) calls `Ownership.Approval(ref, sessionRef)`; a request the caller can't see gets 404 `not_found`, with the unknown-ref body, before the body is read. `State` :182, `Events` :191.
- Mutation targets: `Data/Session.cls:171-183` (`Recipients`), and `Data/Ownership.cls` (`Approval`; the `Rows` statements at :685-817).
- Existing isolation tests this story builds on (none runs a real Break the feed on one account): `Test/Core/AnswersInProduction.cls:186-255`, `Test/Watch/Incidents.cls` `TestTwoSessions`, `Test/Demo/BreakFeedProduction.cls:353-388`, `web/e2e-online/resume.spec.ts:217` (R5).

**Unit and CI**
- `docker/tests/test-online-allowance.sh:1-125` is the template for the new unit: start (`live_start`, `live_web_port`, `online_values`, `online_override`, `dc up`, `wait_started_ready 400`); keys (`keys_point`); the browser step (`run_e2e` with its env: `OCUTALON_URL`, the two accounts, `OCUTALON_E2E_IRIS_CONTAINER`, `OCUTALON_E2E_TIMEOUT_MS`); the MEASURED lines.
- `docker/tests/lib-online.sh`: `online_values` :24, `online_override` :47, `keys_point` :111.
- `web/scripts/demo-path-summary.mjs`: the web run's report reader. Its `Story <n>.<m>` skip-text rule is the model for the new unit's report check.
- Playwright projects: `web/playwright.config.ts:59-72` (the online projects); `web/package.json:20-22` (the `e2e:online-*` scripts); `web/scripts/playwright-projects.test.mjs:290-320` pins each online project's file list (`inOwnFolder` :294). Its `OWN_PROJECT_DIRS` (:69) reads `web/e2e/` only, so the new folder under `web/e2e-online/` does not touch it.
- `ci/units.sh`: `shards-2` at :42 (`shard:lane-a@rest` only), `BROWSER_UNITS` at :95, the grouping comment at :26-34. Epics 9 and 12 change only the `lane-a` areas line and `CHECK_SCRIPTS`; Epics 13 and 15 only `CHECK_SCRIPTS`.
- `docker/tests/test-ci-config.sh`: the BROWSER_UNITS rule (:828-851) and the groups rule (:912-940, which pins only the anchors). `docker/tests/test-ci-changes.sh:177-186`: each live script runs only its own group.
- `.github/workflows/ci.yml:127-132`: every `iris` job builds the web bundle and runs its group, and `ci/iris.sh live` installs Chromium before each `BROWSER_UNITS` unit, so `shards-2` needs no workflow change.
- CI times (run 41027546659, head `468654f`, 2026-10-30): the `shards-2` job 20 min 1 s (`shard:lane-a@rest` 1173 s); `live:online-allowance` 380 s with a 150 s browser step (149-151 s locally), so its start and checks are about 230 s; `live:online-demo` 661 s with a 279 s browser step.

**DW-236: the shell helpers**
- `docker/tests/lib-live.sh`:
  - `iris_script` :306-318: three tries 5 s apart, keeps the `CHK|` lines. `check_session` :477-485 pipes its script lines into it.
  - Epic 12's unmerged hunks: :18-24 (the header), after `check_log` (:610-615) and in `live_ci_bot_token` (:650-670). Every edit stays clear of them.
  - `live_fixture_user` :321-329 hands a password over with its own `-e` and a one-line filter; it stays as it is (outside the two functions).
- `docker/tests/test-online-demo.sh`:
  - `ref_script` :1704-1716 is `iris_script` with `OCUTALON_T16_REF="$resume_ref" dc exec -T -e OCUTALON_T16_REF`; `check_ref_session` :1717-1723 is `check_session` over it. Both go.
  - `check_records_clean` :1724-1750 takes its runner as an argument. Callers: :1794 (`check_session`, the two passwords) and :1804 (`check_ref_session`, the resume reference); the globals check at :1805-1808.
- 14 scripts under `docker/tests/` call `iris_script` or `check_session`; no static test pins their command line.
- Measured on the developer machine's `/bin/bash` (3.2.57) with `set -u`: a prefix assignment on a function call (`FOO=x LIVE_SESSION_ENV=FOO outer inner`) reaches nested functions, pipeline subshells and child processes, and is gone after the call; `${a[@]+"${a[@]}"}` expands an empty array without an unbound-variable error.

**DW-252, DW-413, DW-333**
- `web/e2e-online/busy.spec.ts:178-246`: B2. `page.route('**/ocutalon/api/v1/messages')` fulfils 503 once. The DW-252 case goes beside it.
- `web/e2e-online/allowance/messages.spec.ts:188-212`: A3 presses the guide prompt (`guideSend`).
- `web/src/app/chat/chat-outbox.ts:101,126-136`: the 503 rule. A guide entry is dropped silently.
- `web/e2e-online/allowance/daily-cap.spec.ts`: D1 (:105-141), D2 (:153-168) and AP (:177-204) read the day through `cappedMarked`, `localToday` and `unmarkCapped`, and each of those computes `LocalDate(NowUtc())` again. `Bridge.Time.DayEndUtc(day)` and `SecondsUntil` give the seconds left in the day.
- `web/e2e/support/floor.ts:135-140`: `openFloor`, used by 10 floor specs.
- `web/e2e/banners/banners.spec.ts:91-95`: `open()`.
- `web/e2e/rail/rail.spec.ts:82-89`: Story 16.4's fix (wait for the GET `/state` response, then for the snapshot). The new helper extends it.

## Tasks & Acceptance

**Execution:**

**Helpers**
- `web/e2e/support/floor.ts`: add `loadedAfter(page, signIn)` (DW-333). It registers a wait for the GET `/ocutalon/api/v1/state` response, runs the sign-in action, expects 200, then waits for `data-snapshot="loaded"`. `openFloor` uses it.
- `web/e2e/banners/banners.spec.ts`: `open()` uses `loadedAfter`. This is DW-333's later occurrence (B17).
- `web/e2e-online/support.ts`:
  - (a) `openVisitor(browser)`: opens a new context with the base URL and signs in with `signInFromSplash` through `loadedAfter`. It returns `{context, page, epoch, ref, trace}`, read with `sessionRow`.
  - (b) `populate(session, options)` gains `{watch, approval, pairing}` options. The defaults keep every caller as it is.
  - (c) `ordersOf(trace)`.
  - (d) `opensTabStrict` and `expectOpenedDirectly`, moved here from `demo-account.spec.ts`.
  - (e) DW-413:
    - `instanceDay()` returns `{day, secondsLeft}` from one `NowUtc` read.
    - `clearOfMidnight(budgetS, read = instanceDay, sleep)` waits `secondsLeft + 2` s and reads again when `secondsLeft < budgetS`, then returns the day.
    - `cappedMarked(day)` and `unmarkCapped(day)` take the day as an argument.
- `web/e2e-online/demo-account.spec.ts`: imports the moved helpers, with no change in behaviour.

**Shell helpers (DW-236)**
- `docker/tests/lib-live.sh`, `iris_script` and `check_session` only: `iris_script` reads an optional `LIVE_SESSION_ENV`, a space-separated list of variable names, and passes each as `-e <name>` to `dc exec`, so the session reads the value with `$SYSTEM.Util.GetEnviron` and no script text holds it. With it unset, the command is the same as today. Expand the list with `${args[@]+"${args[@]}"}` (bash 3.2, `set -u`). `check_session`'s comment says that it passes `LIVE_SESSION_ENV` through; its body needs no other change.
- `docker/tests/test-online-demo.sh`: remove `ref_script` and `check_ref_session`. `check_records_clean` loses its runner argument and calls `check_session`. Row 6's two searches become `OCUTALON_T16_REF="$resume_ref" LIVE_SESSION_ENV=OCUTALON_T16_REF check_records_clean ...` and the same prefix on the globals `check_session`. `LIVE_SESSION_ENV` is set only as the prefix of one call, never exported.

**Specs**
- `web/e2e-online/demo-path/demo-path.spec.ts` (moved with `git mv`). Fix the imports. Step 1 stays as it is, and steps 2-5 stay `notBuilt(..., '11.1')`. Then add:
  - **Step 6, real** (matrix row 6): A signs in, presses the guide's watch prompt and opens the reply's Trace link.
  - **"Second visitor"** (rows 1-5), with `test.setTimeout(300_000)`:
    1. Open A and B with `openVisitor`.
    2. Seed each with `populate(ref, {watch: false, approval: false, pairing: 'Ana'|'Ben'})` and `seedIncomingMail`.
    3. Each presses its guide watch prompt and waits for its Orders check row.
    4. Read B's `/state` and cursors.
    5. A presses Break the feed.
    6. Assert rows 1-5 in order.
  - **Three `notBuilt(..., '31.4')` cases**:
    - A's paired chat gets the incident, and B's gets none;
    - a press from B's paired chat is refused;
    - no Telegram value or IRIS user name appears in any OCUTALON or OCUORDERS message body or header.
- `web/e2e-online/busy.spec.ts`: DW-252. A case beside B2 (matrix row 8) that presses `guideSend` instead of typing.
- `web/e2e-online/allowance/daily-cap.spec.ts`: DW-413.
  - D1, D2 and AP call `clearOfMidnight` first. They pass its day to `cappedMarked`, to `unmarkCapped` and to the `DailyCapDay` comparison, and call no `localToday()` inside a case.
  - A browserless case, D0, drives `clearOfMidnight` with a fake read (2 s left, then the next day) and a recording sleep. It expects one sleep of 4 s and the second day.

**Projects and the unit**
- `web/playwright.config.ts`: add the project `online-demo-path` (`testDir: './e2e-online/demo-path'`, Desktop Chrome). `online-demo` also ignores `**/e2e-online/demo-path/**`.
- `web/package.json`: `"e2e:online-demo-path": "playwright test --project=online-demo-path"`.
- `web/scripts/playwright-projects.test.mjs`: `inOwnFolder` includes `demo-path/`. A new case pins the file list and the script of `e2e:online-demo-path`.
- `docker/tests/test-online-demo-path.sh` (new, mode 755, ASCII). It follows `test-online-allowance.sh`'s pattern: start, `keys_point`, then `run_e2e "$@"` for `e2e:online-demo-path` with `OCUTALON_E2E_JSON`.
  - With no arguments, it checks the JSON report:
    - step 1, step 6 and the second-visitor case passed;
    - the four `11.1` cases and the three `31.4` cases are `skipped`, each with its "Story <id> turns this on" text;
    - nothing else is skipped.
  - With arguments (a mutation run, `-g <title>`), it runs only those tests and skips the set check.
  - MEASURED lines: the browser step's seconds and the unit's seconds.
- `docker/tests/test-online-demo.sh`: the comment at :35 that names the online run's step 1 points at the new unit (besides the DW-236 change above).

**CI**
- `ci/units.sh`:
  - `shards-2) echo "shard:lane-a@rest live:online-demo-path"`;
  - add `online-demo-path` to `BROWSER_UNITS`;
  - the grouping comment names the unit with its expected CI time.
- `docker/tests/test-ci-config.sh`: update any pin that names `shards-2`'s units or the `BROWSER_UNITS` list. Nothing else.

**Acceptance Criteria:**
- Given the online-demo throwaway with the keys pointed at the mock, when `live:online-demo-path` runs, then step 1, step 6 and the second-visitor case pass (matrix rows 1-6), and the report holds exactly the four `11.1` skipped cases and the three `31.4` skipped cases (row 7).
- Given a mutation that lets a session see or answer another session's request (`Ownership.Approval` returns the row whatever its owner), when the second-visitor case runs, then it fails at row 4.
- Given a commit that changes `docker/tests/test-online-demo-path.sh` or the online run's spec, when CI classifies it, then `shards-2` runs the unit, and `test-ci-config.sh` and `test-ci-changes.sh` pass with the unit registered.
- Given the moved file, when `npm --prefix web test` runs, then the online projects' file lists are exact and disjoint: the `online-demo` project no longer lists the online run.
- Given `live:online-demo`, `live:online-allowance`, `live:floor` and `live:sign-in --part 1/2`, when each runs once, then each passes with DW-252's case, D0, the changed D1, D2 and AP, and the `loadedAfter` waits.
- Given `test-online-demo.sh` with no `ref_script` or `check_ref_session` (DW-236), when `live:online-demo` runs, then row 6's searches for the resume reference pass through `check_session` with `LIVE_SESSION_ENV=OCUTALON_T16_REF`, no script text holds the reference, and the live units that call `iris_script` without `LIVE_SESSION_ENV` pass as before.

## Spec Change Log

- 2026-10-30, lead, re-dispatch 1 of the plan: the plan HALTed on AD-13 (the busy rule against the fourth criterion's case 1) and proposed a split. The lead ruled (Design Notes, "Lead rulings"): the split into Story 29.7 accepted; DW-236's decline accepted; the AD-13 question sent to the orchestrator, not blocking this story. Status reset to `draft` for the re-plan. Then the orchestrator's rulings: Story 29.7 parked (U-163); DW-236 back in this story (only `iris_script` / `check_session` in `lib-live.sh` and `test-online-demo.sh`).
- 2026-10-30, plan, re-dispatch 1: the intent block was edited only where the rulings made it stale. (a) Approach, last sentence: it read "...are proposed for a sibling, Story 29.7, and this plan HALTs on AD-13 for them (Design Notes, "HALT")"; it now says they moved to Story 29.7 and names DW-236's pass-through. (b) Never, the first edit bullet: it read "`docker/tests/lib-live.sh`, which is contended (Epic 12's branch changes it)"; it now forbids edits outside `iris_script` and `check_session`. (c) Never, the last bullet: it read "Build the fourth criterion's load script or its procedure here. They belong to the proposed sibling, 29.7."; it now also forbids changing AD-13, AD-25 or `OWNCONNECTIONS`, and names Story 29.7 as parked (U-163). The HALT section and the split proposal were removed; the DW-236 task, its AC and its mutation were added. KEEP: the matrix, the online-run unit in `shards-2`, the keys at the mock, step 6, the second visitor, B's refused answer, A's answer from the phone, `loadedAfter`, `clearOfMidnight`, the 503 guide-prompt case.

## Review Triage Log

### 2026-10-30 - Review pass
- verdicts: 32 findings - high 0, medium 2, low 20, false 10, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: clearOfMidnight re-reads once and does not loop - the host and instance clocks are the same machine; a loop adds a branch for a skew that was not shown
  - `[low]` `[reject]` Blind: step 6 does not require agentStepCount above 0 - matrix row 6 says "at least agentStepCount"; the guide-watch mock turn may legitimately have none
  - `[low]` `[reject]` Blind: Decided-in-stage item 2 is stale next to item 0 - the fix edits this spec; item 0 is the later account
  - `[low]` `[reject]` Blind: the second-visitor finally has no per-item guard - the stack is a throwaway torn down at the end; a throw there already fails the case
  - `[low]` `[patch]` Blind: weak oracles in the baseline (circular check and mail refs, guide may be absent) - added `expect(bBefore.guide).toBeDefined()`; the check and mail refs are guarded by the 1/1/1/1 count and the cross-containment searches
  - `[low]` `[reject]` Blind: report check pins counts per story, not titles - a swap needs a deliberate edit and the row 7 mutation went red on a count
  - `[low]` `[patch]` Blind: the cleanPopulated comment is wrong (Clean(",") deletes nothing) - the guard and its comment were removed; the hunk is back to the baseline line
  - `[false]` `[reject]` Blind: units.sh header omits online-demo-path in the Lane B list - the unit is not Lane B's; the next sentence names it
  - `[false]` `[reject]` Blind: shards-2 becomes the longest group - Decided in-stage 1 chose it for headroom, the merge gate re-checks REL-4; measured 141 to 162 s locally
  - `[medium]` `[patch]` Edge: report_check that cannot run prints nothing and reads as no problems - `|| problems="the report check could not run"` added
  - `[low]` `[reject]` Edge: finally cleanup loops stop at the first throw - same as the Blind finding on per-item guards
  - `[low]` `[reject]` Edge: step 6 finally, sessionRow throw - same class
  - `[low]` `[reject]` Edge: populate() of B throws before populated.push - same class
  - `[low]` `[reject]` Edge: eventsSince stops after 20 polls - 20 pages of events after a cursor is far above what one Break the feed produces
  - `[false]` `[reject]` Edge: B's own watch.progress would flag a false leak - watch.progress is published only by IncidentManager for incidents; B has none
  - `[false]` `[reject]` Edge: loadedAfter may take an early non-200 /state - the splash polls no /state; a non-200 is named by the status expectation, which is the point
  - `[low]` `[reject]` Edge: clearOfMidnight loop - same as the first Blind finding
  - `[low]` `[reject]` Edge: budgets of 240/150/200 s against 300 s timeouts - measured case times are 18 to 34 s; the budget is a margin, not a limit
  - `[false]` `[reject]` Edge: setTimeout raised by only the budget - the midnight wait is at most budget plus 2 s and the cases run 18 to 34 s
  - `[false]` `[reject]` Edge: LIVE_SESSION_ENV naming an unset variable - the check prints `<unset>` and fails; the DW-236 mutation run shows it
  - `[false]` `[reject]` Edge: retried flake counts as passed - playwright.config.ts sets retries 0
  - `[low]` `[reject]` Edge: step 1 leaves its session row - step 1 "stays as it is" (spec); the throwaway is torn down
  - `[medium]` `[patch]` Gap: step 6 clicks the guide button before it is usable (Rule 19 hermeticity) - `not.toHaveAttribute('aria-disabled','true')` added before the click, as B2b has it
  - `[low]` `[reject]` Gap: agent steps not required above 0 in step 6 - same as the second Blind finding
  - `[low]` `[reject]` Gap: circular baseline fields - covered by the patch above and the count and containment guards
  - `[false]` `[reject]` Gap: the shards-2 placement is unpinned - mutation run: removing the unit from shards-2 turns test-ci-config.sh and test-ci-changes.sh red
  - `[low]` `[reject]` Gap: D1/D2/AP use of the day has no mutation - `day` is a string argument checked by tsc; a midnight straddle cannot be scheduled
  - `[low]` `[defer]` Gap: allowance visit() and messages open() keep the old sign-in wait - pre-existing, outside matrix row 10's list; deferred
  - `[low]` `[reject]` Other: unused costUSD in the decision cast - cosmetic
  - `[low]` `[reject]` Other: step 6 finally runs removeSession before cleanPopulated - same class as the per-item guards
  - `[false]` `[reject]` Other: the report check is skipped with -g - by design (matrix and Tasks: arguments run only those tests)
  - `[false]` `[reject]` Intent audit: divergences (watch started by the mock marker in the composer, A's rows after the press checked with toContain, separate waits inside the 90 s row, the 12 s hold run as a mutation check only, clearOfMidnight's second read) - descriptive; each is the spec's own Decided in-stage 0 or its Verification text, none is a defect

## Design Notes

**Owner decision for Epic 29** (`owner_decision id=epic29_brief`, the Contest Planner under the owner's delegation, 2026-10-30). It binds. The parts that concern 29.4, quoted:
> - **The demo host is owner-only (policy).** Never connect to, deploy to, configure or probe the demo host. Never run `ocutalon-demo`, SSH or DNS commands. Never look for the host's deployment configuration or runbook; they stay outside this repository. Opening the access gate is the author's.
> - **Host-only criteria** are recorded as release checks for the Contest Planner's hands-on pass on the gated host, never faked as passing. [...]
> - **Anything that needs a host action** is an escalation (an intent gap HALT, in this stage).

Its bullet on the real-proxy load case now binds Story 29.7.

**Lead and orchestrator rulings (re-dispatch 1, 2026-10-30; runner C, unattended policy 6df0676).** This plan is built around them:
1. **The split is accepted** (decide; doctrine U5, Rule 5 tier 2). Story 29.7 (`29-7-the-author-s-load-run-measures-the-demo-s-capacity`) holds the former fourth criterion with DW-286 and DW-251. This story keeps criteria 1 to 3 (the third skipped for Story 31.4), DW-252, DW-333, DW-413 and DW-236.
2. **DW-236 is this story's** (orchestrator). Only `iris_script` and `check_session` in `lib-live.sh` change, plus the copies in `test-online-demo.sh`. The edits stay clear of Epic 12's three spots, so a later integrate-forward is a plain union, and `lib-live.sh` is listed under `footprint_extensions:`.
3. **The AD-13 question** (busy against signed-in visitors) is Story 29.7's, parked as owner-only inbox item U-163. Criteria 1 to 3 do not depend on the busy rule, and nothing here plans it or changes AD-13, AD-25 or `OWNCONNECTIONS`.

**Task 0 of the first plan pass: Story 29.7's input.** This is not this story's work. It is kept for 29.7's plan (DW-286's and DW-251's ledger notes carry the same facts). Measured on a lane-C throwaway: the online-demo start values, build 154 with the key `InterSystems IRIS Community` (8 units, 8 enforced), `proxyAddress` set to the address IRIS sees for the test host's requests, and visitors as curl jars of the demo account, each with its own `X-Forwarded-For`. Readings are connections / licence units, read by an `iris_script` whose own terminal is the baseline's one:

| Step | What happened | Connections / units | Licence user list | `status.busy` |
|---|---|---|---|---|
| M0 | Baseline, no visitor | 1/1 | | false |
| M1 | A signs in (303) and polls `/state` three times | 1/1, no change (DW-251) | | false |
| M2 | A opens a Visual Trace page (OCUTALON) | 2/2 | `DemoVisitor@<the TCP peer address>`, CSPCon 1, LU 1. The unit is keyed by the TCP peer, never by the forwarded address | false |
| M3 | A also opens the OCUORDERS trace page | 3/2 | CSPCon 2, LU 1 | false |
| M4, M5 | B (another forwarded address, same TCP peer) signs in, then opens a trace page | 3/2 after sign-in, 4/2 after the trace page | CSPCon 3, LU 1 | false |
| M6 | C does the same | 5/2 | CSPCon 4, LU 1 | false |
| M8 | A signs out of the group (`?IRISLogout=end` on both trace applications and `/ocutalon/`) | 3/2 | A's two trace sessions freed at once | false |
| M10 | B and C left without signing out | Back to 1/1 between 111 and 121 s after the leave mark (10 s sampling) | | false |
| M11 | End | 1/1 | | false |

The iris image has no curl, so a visitor from a second TCP peer was not measured; Story 4.7 measured that each distinct user and client address takes its own unit. The run took 314 s; the stack was ready after 91 s. Consequences (inference for the gated host, where IRIS sees the proxy as every visitor's TCP peer): every proxied visitor shares one licence unit, `DemoVisitor@<proxy>`; InstanceConnections counts each open trace application session and no sign-in.

**Architecture decisions that govern this story (Rule 6):**
- AD-4: session ownership, `Recipients`, no `SessionRef` from the client.
- AD-11: approvals; `AnswersIn` refuses a request another session can't see.
- AD-12: `/state`, polling, the guide and Break the feed per session.
- AD-13: sign-in and the 404 envelope. Its busy rule is not this story's (U-163, Story 29.7).
- AD-15: watch, incident and notice.
- AD-22: testing, throwaways and CI groups.
- AD-25: the online demo's topology; the host stays the author's.
- AD-26: Visual Trace links and the trace step.
- AD-29: the Epic 29 exception and the lanes.
- AD-32: the notification contract.
- AD-33: one owner per item.

No AC contradicts an AD's Rule.

**Integration ACs (Rule 1).** No service is introduced. The shared test helpers have consumers in this story:
- `loadedAfter`: `live:floor` (`openFloor`, 10 floor specs), `live:sign-in` (banners), and the online run (`openVisitor`).
- `opensTabStrict` and `expectOpenedDirectly`: O4 and step 6.
- `clearOfMidnight`: D1, D2, AP and D0.
- `iris_script` and `check_session` with `LIVE_SESSION_ENV`: `live:online-demo`'s row 6 searches (the last AC).

The first, fifth and last ACs run those consumers.
- **Consumed-by:**
  - Story 11.1 turns on steps 2 to 5 in the moved file.
  - Story 31.4 turns on the three `31.4` cases.
  - Story 29.7 (parked, U-163) may reuse this unit's stack for its local proof; its plan decides.
- **Consumes:**
  - Lane A's real watch, incident, diagnosis and approval path (Epics 5 and 7).
  - Story 16.2's splash and online run.
  - Story 16.3's visitor sessions and `test-online-demo.sh`'s row 6.
  - Story 16.1's demo account and O4.
  - Story 16.9's allowance specs.
  - The mock's `guide-watch` and `diagnosis` scenarios.

**Extend, don't copy (Rule 2):**
- `loadedAfter` extends `rail.spec.ts` `open()`'s Story 16.4 wait (:82-89). Rail keeps its inline copy: it is Story 2.8's spec, it lies in `live:sign-in`'s part 2 (`rail/` comes after `guide/`, near the middle of about 219 tests), and switching it would cost a run with no change in behaviour.
- `openVisitor` builds on `signInFromSplash` and `sessionRow`.
- `populate` gains options instead of being copied.
- `opensTabStrict` and `expectOpenedDirectly` move to `support.ts` and are shared.
- DW-236: `ref_script` and `check_ref_session` give way to `iris_script` and `check_session`, which gain the pass-through. `live_fixture_user` (`lib-live.sh:321-329`) and `test-demo-switch.sh:150` keep their own `-e`: the first lies outside the two functions the ruling allows, and the second keeps the session's raw output, not its `CHK|` lines.
- The unit is `test-online-allowance.sh`'s pattern with its own project.
- The report check reuses `demo-path-summary.mjs`'s skip-text rule. A new reader is needed because the online run is one file, not six step files.

**Ledger inbox (Rule 17):**
- **DW-252:** addressed by matrix row 8 and the busy.spec.ts task. Its premise is outdated, because the guide now sends prompts (`demo-guide.ts:571-580`).
- **DW-333:** addressed by matrix row 10 and the `loadedAfter` task. `openFloor` is the residual that the routing note names; banners' `open()` is the B17 occurrence recorded after Story 16.4's fix.
- **DW-413:** addressed by matrix row 9 and the daily-cap task (D0, and D1, D2 and AP).
- **DW-236:** addressed by the "Shell helpers (DW-236)" tasks, the last AC and its mutation.
- DW-286 and DW-251 are Story 29.7's.

**footprint_extensions:**
- `docker/tests/lib-live.sh` (`iris_script` and `check_session` only; DW-236, by the orchestrator's ruling)
- `web/e2e/support/floor.ts`
- `web/e2e/banners/banners.spec.ts`
- `web/playwright.config.ts`
- `web/package.json`
- `web/scripts/playwright-projects.test.mjs`
- `docker/tests/test-ci-config.sh`, only if a pin follows

Apart from `lib-live.sh` (Epic 12's three hunks, kept clear of), none of these is contended, and no other epic branch changes them. `ci/units.sh` gets only this story's own unit and list entries, on lines no other branch changes. The rest is in the footprint: `web/e2e-online/**`, `docker/tests/test-online-*.sh` and `docker/tests/test-online-demo-path.sh`.

**Decided in-stage:**
0. (implement) **The second visitor starts its watch with the mock's marker** (this supersedes item 2's "from each visitor's own guide watch prompt" and its agent-steps remark for the second visitor). `ci/mock/scenarios/B/guide-watch.json` answers the guide's watch prompt with text only and calls no `start_watch`, so no Orders check is made and Break the feed would answer 409. The case sends `[[mock:watch-start-orders]]` plus the guide's watch prompt text through the composer (the real StartWatch tool). Step 6 presses the guide button, since it needs only a turn with a decision. The mock stays as it is (outside the footprint). The phone's answer line is matched with its optional zone suffix. `eventsSince` in the spec reads `/events` from a cursor on both streams until nothing new arrives.
1. **REL-2's online run moves to its own project and unit** (`web/e2e-online/demo-path/`, `online-demo-path`, `live:online-demo-path` in `shards-2`):
   - The second visitor needs the keys pointed at the mock. Without them every decision is a `no_key` fallback, and no approval request is raised. The `online-demo` unit keeps them unpointed during its browser step.
   - `shards-2` has the largest headroom (20.0 min measured; `shards` 20.9).
   - Expected: about 4 to 5.5 min locally (a start of about 90 s and a browser step of 2.5 to 4 min, against the 540 s local deadline), and 7 to 9 min on CI (about 230 s of start and checks, as `live:online-allowance`'s 380 s with its 150 s browser step, plus the browser step). So `shards-2` becomes about 27 to 29 min, inside REL-4's 35 and the 40-minute job limit (inference). Epics 9 and 12 add their areas to `lane-a`, whose `@rest` piece is `shards-2`'s, so their merges add to it; the merge gate re-checks REL-4.
2. **Watches come from each visitor's own guide watch prompt**, the demo path's step-2 action, so that step 6 traces a real decision with agent steps. The reminder, the pairing (a fixture row) and the mail are seeded. The paired chat's messages are Story 31.4's.
3. **"Any of A's channels"** means this: A's card offers Approve and Reject (the web channel), and A answers on the simulated phone (REL-2's step-5 channel). One request takes one answer. Telegram is 31.4's.
4. **The third criterion stays skipped as a whole.** Its Given is a paired mock Telegram chat.
5. **Only step 6 and the second visitor are turned on**, in the criterion's words. Steps 2 to 5 stay with Story 11.1.
6. **Step 6's oracle:** the tab is at `traceUrl`; no trace document is a sign-in page; Visual Trace draws the turn's header and at least `agentStepCount` other messages (AD-26: the chain shares the thread's session); the decision details show the steps and the cost.
7. **DW-413's guard is a pure function** with an injectable read and sleep, pinned by a browserless case. The real midnight path can't be scheduled.
8. **IRIS mutations run on the unit's fresh stack** with `-g`, one case at a time.
9. **DW-236's pass-through is a variable of names (`LIVE_SESSION_ENV`), not a new argument.** `check_session`'s positional signature and its callers in 14 scripts stay as they are, and the name follows `lib-live.sh`'s `LIVE_` globals. `check_records_clean` loses its runner argument, because both callers would pass `check_session`.
10. **DW-236's pin is the consumer's real check, not a new `test-lib-live.sh` case.** Epic 12's branch changes `test-lib-live.sh` (44 lines), so a new case there risks an overlap; `live:online-demo`'s row 6 already prints `<unset>` when the variable does not reach the session.

## Verification

Every call runs in the foreground with `timeout: 600000`, one test call per message, against named lane-C targets. `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement'`. There are no class or shard runs, so there is no warm mode (tag `e29s4iw` unused): live units refuse it. A local live run that dies of the deadline with no failed test is that deadline: re-run it once with `OCUTALON_LIVE_DEADLINE=900` on the call.

**Commands:**
- (once, first) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh build`. Expected: the web bundle matches `web/src` after the merge (Rule 21). Repeat it after any change under `web/src`.
- (loop) `bash -n docker/tests/lib-live.sh && bash -n docker/tests/test-online-demo.sh && bash -n docker/tests/test-online-demo-path.sh`. Expected: no output.
- (loop) `npm --prefix web run lint`. Expected: the e2e TypeScript compiles.
- (loop) `npm --prefix web test`. Expected: the project pins pass, `online-demo-path` included.
- (loop) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live online-demo-path`. Expected: PASS, with the report set of row 7. Record the unit's seconds and the browser step's seconds (about 4 to 5.5 min, inference).
- (once) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live online-demo`. Expected: PASS with DW-252's case and row 6 through `LIVE_SESSION_ENV` (DW-236); the project no longer runs the online run (about 310 to 360 s).
- (once) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live online-allowance`. Expected: PASS with D0 and the changed D1, D2 and AP (237 to 253 s).
- (once) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live floor`. Expected: PASS with `loadedAfter` (235 to 244 s).
- (once) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live sign-in --part 1/2`. Expected: PASS. Its listing holds `banners/banners.spec.ts`; if it doesn't, run `--part 2/2` instead.
- (once) `grep -nE 'ref_script|check_ref_session' docker/tests/*.sh`. Expected: no output (no copy is left).
- (once) `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-ci-changes.sh`. Expected: both pass; the second's per-unit loop proves that `docker/tests/test-online-demo-path.sh` runs only `shards-2`.
- (once) `bash ci/changes.sh ci.yml --group shards-2`. Expected: exit 0 and one `GROUP` line for each of the seven groups. With no push payload every group runs, so this only proves that the classifier reads the new lists; the classification is the previous command's.
- (once) `bash ci/checks.sh`. Expected: every block passes (about 4 min); its `boundaries` block holds the ASCII rule for `docker/`.
- (once, at the end, also after a failure) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh teardown`. Expected: nothing tagged `e29s4i` is left.

**Shared surfaces:**
- the `online-demo` project's file list: it loses the online run (`playwright-projects.test.mjs`);
- the new `online-demo-path` project and its npm script;
- `shards-2`'s units and `BROWSER_UNITS` (`test-ci-config.sh`, `test-ci-changes.sh`);
- `populate`'s signature (every caller under `web/e2e-online/`);
- `cappedMarked` and `unmarkCapped`'s signatures (every caller under `web/e2e-online/allowance/`);
- `openFloor` (10 floor specs);
- the O4 helpers' home (`demo-account.spec.ts`);
- `iris_script` and `check_session` (14 scripts under `docker/tests/`): additive, since an unset `LIVE_SESSION_ENV` keeps today's command;
- `check_records_clean`'s signature (its two callers in `test-online-demo.sh`).

The implement stage searches the test trees for each of these.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. Each online-run case creates and removes its own sessions and rows, and the mutation runs below run single cases alone.

**Mutations (Rule 19), one per AC.** Each is applied, observed red, reverted, and the tree confirmed byte-identical:
- AC1: mutation: `Data/Session.cls` `Recipients` returns every session's Ref when it is called with an incident Ref (the incident path of `IncidentManager`). Red (observed): the second-visitor case at row 2 ("B's chat has no incident card": expected 0, received 1). Run with `live online-demo-path -g "second visitor"`. Two variants were also run: returning every session on every call goes red at row 1 (A's phone gets no notice, because `IsSession` checks for exactly one Ref), and the same extra Refs in `Core/BridgeSink.cls` `Recipients` stay green (the approval row is read through `Ownership.Approval`, which refuses B's).
- AC1, step 6: mutation: `Web/TraceLink.cls` `Url` adds 1000000 to `SESSIONID`. Red (observed): step 6 ("the page draws messages": expected > 0, received 0). Adding 1 stays green, because the next header lies in the same session and Visual Trace still draws the turn.
- AC1, row 7: mutation: one `notBuilt(..., '31.4')` becomes an empty passing test. Red (observed): the unit's report check ("wanted 3 passed cases, found 4" and "wanted 3 skipped cases of Story 31.4, found 2").
- AC2: mutation: `Data/Ownership.cls` `Approval` returns the row whatever its owner (`ApprovalRequest.RefIndexOpen(ref)`). Red (observed): the second-visitor case at row 4 (B's answer: expected 404, received 200).
- AC3 (CI): mutation: `online-demo-path` is left out of `BROWSER_UNITS`. Red (observed): `test-ci-config.sh` ("it runs Playwright, but online-demo-path is not in BROWSER_UNITS").
- AC4: mutation: `online-demo` without the `demo-path/` ignore. Red (observed): `npm --prefix web test` (the `online-demo` and `online-demo-path` list pins, 2 failures).
- AC5, DW-252: mutation: `chat-outbox.ts` `refuse()` without `!entry.fromGuide &&`. Red (observed): B2b (the prompt lands in the composer; `live online-demo` has no case filter, so the whole unit ran). `ci/iris.sh build` ran before the mutation run and after the revert.
- AC5, DW-413: mutation: `clearOfMidnight` never sleeps. Red (observed): D0 ("one sleep of the 2 seconds left plus 2": expected [4000], received []). D0 is browserless, so it ran alone with `playwright test --project=online-allowance -g D0` and no stack.
- AC5, DW-333: mutation: `loadedAfter` waits for the snapshot only, with a temporary 12 s hold on GET `/state` in one floor case. Red (observed): the hold was put on the first GET `/state` of step 6 in the online run instead of a floor case (the same `loadedAfter`, and a 2.5-minute stack); with the mutation, "data-snapshot" stayed unloaded for the 10 s expect timeout. With the fix and the hold, step 6 is green (14.6 s).
- AC6, DW-236: mutation: `iris_script` ignores `LIVE_SESSION_ENV` (no `-e`). Red (observed): `live online-demo`'s row 6 searches (`CHK|eventlog|OCUTALON_T16_REF|<unset>` instead of `0`, and the same for the live events, the audit log and the globals).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** REL-2's online run moved to its own project and unit, `live:online-demo-path` (`shards-2`). Step 6 is real, and a "second visitor" case shows that A's incident, notice and approval request reach only A, that B's page, `/state` and `/events` get nothing, that B's answer to A's request is refused with 404 `not_found`, and that A then answers on its phone. Four steps stay `notBuilt('11.1')` and three cases `notBuilt('31.4')`, checked by the unit's report check. DW-252 (B2b), DW-333 (`loadedAfter`), DW-413 (`clearOfMidnight`, D0) and DW-236 (`LIVE_SESSION_ENV`) are fixed beside it.

**Files changed.**
- `web/e2e-online/demo-path/demo-path.spec.ts`: the moved online run, step 6 and the second-visitor case.
- `web/e2e-online/support.ts`: `openVisitor`, `populate` options, `ordersOf`, the moved O4 helpers, `instanceDay` and `clearOfMidnight`; `cappedMarked` and `unmarkCapped` take a day.
- `web/e2e-online/allowance/daily-cap.spec.ts`: D0, and D1, D2 and AP on one day.
- `web/e2e-online/busy.spec.ts`: B2b (DW-252).
- `web/e2e-online/demo-account.spec.ts`: imports the moved helpers.
- `web/e2e/support/floor.ts`, `web/e2e/banners/banners.spec.ts`: `loadedAfter` (DW-333).
- `web/playwright.config.ts`, `web/package.json`, `web/scripts/playwright-projects.test.mjs`: the project, its script and its pins.
- `docker/tests/test-online-demo-path.sh` (new): the unit and its report check.
- `docker/tests/lib-live.sh`: `iris_script` and `check_session` pass `LIVE_SESSION_ENV` (DW-236).
- `docker/tests/test-online-demo.sh`: no `ref_script` or `check_ref_session`; row 6 uses the pass-through.
- `ci/units.sh`: `shards-2`, `BROWSER_UNITS` and the grouping comment.

**Review.** One pass, 32 findings: high 0, medium 2, low 20, false 10. Four patched (2 medium, 2 low): the report check that cannot run now fails, step 6 waits for the guide button to be usable, the baseline asserts B's guide is served, and the `cleanPopulated` guard and its wrong comment are gone. One low deferred (the allowance `visit()` and messages `open()` sign-in wait). Every rejected finding and its reason is in the Review Triage Log.

**Follow-up review recommended: true** (two medium entries patched). Unverified risk: the failure branch of the patched report-check call (`|| problems=...`) was not exercised; the other patches ran in two unit reruns.

**Verification.** `bash -n` of the three scripts, `npm --prefix web run lint` and `npm --prefix web test` (1126 of 1126): pass. `live online-demo-path`: PASS twice (154 s then 141 s for the unit; the browser step 49 s and 48 s; step 1 1.2 s, step 6 2.1 s, second visitor 44 s). Once-only units: `live online-demo` PASS (the browser step 203 s; the unit about 360 s), `live online-allowance` PASS (266 s, rerun after the patches 224 s), `live floor` PASS (105 passed, 4.5 min), `live sign-in --part 1/2` PASS (127 passed, 3.8 min), `test-ci-config.sh`, `test-ci-changes.sh`, `ci/changes.sh ci.yml --group shards-2`, `ci/checks.sh` (twice) and the `ref_script|check_ref_session` grep: pass or empty. Teardown of tag `e29s4i`: nothing left. All ten Rule 19 mutations were applied, observed red and reverted with the tree byte-identical (see the `mutation:` lines).

**Residual risks.**
- `live:online-demo-path` is measured at 141 to 162 s locally, below the plan's 4 to 5.5 min; the CI time for `shards-2` (plan: 27 to 29 min) is not measured here.
- The second visitor starts its watch with the mock's `[[mock:watch-start-orders]]` marker, not the guide's button (Decided in-stage 0), because the `guide-watch` mock calls no tool.
- Two mutations in the plan did not go red as worded and were corrected in `## Verification`: `Recipients` returning other sessions on every call breaks `IsSession` first (red at row 1), and `SESSIONID` plus 1 still draws the turn.
