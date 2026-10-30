---
title: 'Story 29.4: Sessions stay isolated under load'
type: 'feature'
created: '2026-10-30'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the online demo every visitor signs in with the same demo account. No test yet follows a real Break the feed (incident, notice, approval request) while a second visitor watches the same Orders production, so nothing proves that one visitor's run stays out of another visitor's views and answers. REL-2's online run still skips its trace step and has no second visitor. Four small ledger entries wait on this story: DW-252, DW-333, DW-413 and DW-236.

**Approach:** Give REL-2's online run its own Playwright project and live unit, with the model keys pointed at the CI mock. Turn on its step 6 (the trace link) and add a second visitor: A and B each watch Orders from the guide, and A presses Break the feed. The test asserts that A's incident, notice and approval request reach only A; that B's page, `/state`, `/events` and an answer with A's reference get nothing and change nothing; and that A then answers. The paired-chat cases stay present and skipped for Story 31.4. The fourth criterion (the author's real-proxy load case), DW-286 and DW-251 are proposed for a sibling, Story 29.7, and this plan HALTs on AD-13 for them (Design Notes, "HALT").

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
  - `docker/tests/lib-live.sh`, which is contended (Epic 12's branch changes it);
  - `web/e2e/demo-path/**`, the web run, which is Story 11.1's;
  - any Lane A class;
  - any contended path.
- Change product behaviour. If the isolation test finds a leak whose fix lies outside this story's footprint, stop with a clarification that names it (Rule 11).
- Build the fourth criterion's load script or its procedure here. They belong to the proposed sibling, 29.7.

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
- `web/e2e-online/demo-path.spec.ts`: REL-2's online run (Story 16.2). Step 1 is real; steps 2-6 are `notBuilt(..., '11.1')` at :29-33. It moves to `web/e2e-online/demo-path/demo-path.spec.ts`.
- `web/e2e/demo-path/not-built.ts:11-14`: `notBuilt(title, story)` runs `test.skip(true, 'Story <id> turns this on')`.
- `web/e2e/demo-path/04-incident.spec.ts`, `05-approval.spec.ts`, `06-trace.spec.ts` (read-only). They give the selectors and the step-6 title:
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
- The watch prompt:
  - `web/src/app/guide/guide-view.ts:32` holds its text.
  - In `web/src/app/guide/demo-guide.ts`, the button `app-demo-guide [data-guide-focus="action"]` (:179-187) calls `outbox.send(text, true)` (:571-580).
  - The mock answers it with `ci/mock/scenarios/B/guide-watch.json` (prompt match).
  - `ci/mock/scenarios/A/diagnosis.json` (mockkey `diagnosis`) returns the `repair_resend` fix.
- Break the feed: the button `app-break-feed-box app-server-button button` (`web/e2e-online/allowance/daily-cap.spec.ts:196-200`). Count orders with `Test.Demo.Production.Count(trace,"OrdersFromPartner",8)`, which `04-incident.spec.ts` polls.
- `web/src/app/chat/decision-details.ts:76,81`: the decision's steps and cost rows, used by step 6.

**Server side (read-only) and existing isolation tests**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `AnswerApproval` (:478-492) calls `Ownership.Approval(ref, sessionRef)`. A request the caller can't see gets 404 `not_found`, with the unknown-ref body, before the body is read.
  - `State` is at :182 and `Events` at :191.
- Mutation targets: `Data/Session.cls:171-183` (`Recipients`), and `Data/Ownership.cls` (`Approval`; the `Rows` statements at :685-817).
- Existing isolation tests that this story builds on. None runs a real Break the feed on one account:
  - `Test/Core/AnswersInProduction.cls:186-255`
  - `Test/Watch/Incidents.cls` `TestTwoSessions`
  - `Test/Demo/BreakFeedProduction.cls:353-388`
  - `web/e2e-online/resume.spec.ts:217` (R5)

**Unit and CI**
- `docker/tests/test-online-allowance.sh:1-110` is the template for the new unit:
  - start: `live_start`, `live_web_port`, `online_values`, `online_override`, `dc up`, `wait_started_ready 400`;
  - keys: `keys_point`;
  - browser step: `run_e2e`, with its env (`OCUTALON_URL`, the two accounts, `OCUTALON_E2E_IRIS_CONTAINER`, `OCUTALON_E2E_TIMEOUT_MS`);
  - the MEASURED browser seconds.
- `docker/tests/lib-online.sh`: `online_values` :24, `online_override` :47, `keys_point` :111.
- `docker/tests/test-online-demo.sh:761-786`: `run_e2e` of the online-demo project.
- `web/scripts/demo-path-summary.mjs`: the web run's report reader. Its `Story <n>.<m>` skip-text rule is the model for the new unit's report check.
- Playwright projects:
  - `web/playwright.config.ts:59-72`: the online projects.
  - `web/package.json:20-22`: the `e2e:online-*` scripts.
  - `web/scripts/playwright-projects.test.mjs:290-310`: pins each online project's file list (`inOwnFolder`).
- CI lists:
  - `ci/units.sh`: `shards-2` at :42 (`shard:lane-a@rest` only), `BROWSER_UNITS` at :95, and the grouping comment at :26-34.
  - `docker/tests/test-ci-config.sh`: the BROWSER_UNITS rule (:828-851) and the groups rule (:912-940, which pins only the anchors).
  - `docker/tests/test-ci-changes.sh:177-186`: each live script runs only its own group.

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
- `docker/tests/test-online-demo.sh`: comments that name the online run now point at the new unit. Nothing else changes.

**CI**
- `ci/units.sh`:
  - `shards-2) echo "shard:lane-a@rest live:online-demo-path"`;
  - add `online-demo-path` to `BROWSER_UNITS`;
  - the grouping comment names the unit with its expected time.
- `docker/tests/test-ci-config.sh`: update any pin that names `shards-2`'s units or the `BROWSER_UNITS` list. Nothing else.

**Acceptance Criteria:**
- Given the online-demo throwaway with the keys pointed at the mock, when `live:online-demo-path` runs, then step 1, step 6 and the second-visitor case pass (matrix rows 1-6), and the report holds exactly the four `11.1` skipped cases and the three `31.4` skipped cases (row 7).
- Given a mutation that lets a session see or answer another session's request (`Ownership.Approval` returns the row whatever its owner), when the second-visitor case runs, then it fails at row 4.
- Given a commit that changes `docker/tests/test-online-demo-path.sh` or the online run's spec, when CI classifies it, then `shards-2` runs the unit, and `test-ci-config.sh` and `test-ci-changes.sh` pass with the unit registered.
- Given the moved file, when `npm --prefix web test` runs, then the online projects' file lists are exact and disjoint: the `online-demo` project no longer lists the online run.
- Given `live:online-demo`, `live:online-allowance`, `live:floor` and `live:sign-in --part 1/2`, when each runs once, then each passes with DW-252's case, D0, the changed D1, D2 and AP, and the `loadedAfter` waits.

## Spec Change Log

- 2026-10-30, lead, re-dispatch 1 of the plan: the plan HALTed on AD-13 (the busy rule against the fourth criterion's case 1) and proposed a split. The lead ruled (Design Notes, "Lead rulings"): the split into Story 29.7 accepted; DW-236's decline accepted; the AD-13 question sent to the orchestrator, not blocking this story. Status reset to `draft` for the re-plan.

## Review Triage Log

## Design Notes

**Owner decision for Epic 29.** The Contest Planner decided it under the owner's delegation on 2026-10-30 (`owner_decision id=epic29_brief`). It binds. The parts that concern 29.4, quoted:
> - **The demo host is owner-only (policy).** Never connect to, deploy to, configure or probe the demo host. Never run `ocutalon-demo`, SSH or DNS commands. Never look for the host's deployment configuration or runbook; they stay outside this repository. Opening the access gate is the author's.
> - **Host-only criteria** are recorded as release checks for the Contest Planner's hands-on pass on the gated host, never faked as passing. [...] Relevant to 29.4: one licence unit was in use at idle, the host's settings are CONNECTION_CAP=8 and RESERVE=2, and busy was measured one connection lenient (a signed-in CSP session is not counted, so a proxied sign-in was admitted while busy; DW-251's note).
> - **29.4's real-proxy load case** is the author's (the Planner's pass) on the adapted host, as its amendment says. Write it so that it does not spend the $20 daily cost cap: either a load that makes no model calls, or a brief, bounded run. Keep it within the 8-licence-unit ceiling (DW-287). Its measured results go into the 1.0.0 release notes, not into sharded CI.
> - **Anything that needs a host action** is an escalation (an intent gap HALT, in this stage).

**Lead rulings (re-dispatch 1, 2026-10-30; runner C, unattended policy 6df0676). Re-plan around them:**
1. **The split is accepted (decide; doctrine U5, Rule 5 tier 2 within `split_children`).** Story 29.7, "The author's load run measures the demo's capacity" (key `29-7-the-author-s-load-run-measures-the-demo-s-capacity`), now holds this story's former fourth criterion verbatim with DW-286 and DW-251 (re-owned to it; the measured facts of this plan's Task 0 are in their ledger notes and stay in the "Task 0" notes below for 29.7's plan). This story keeps criteria 1 to 3 (the third stays skipped for Story 31.4), DW-252, DW-333 and DW-413. Remove the "HALT" section's intent gap and the split proposal from this spec, keep the Task 0 measurement notes (marked as 29.7's input), and plan only what this story keeps.
2. **DW-236's decline is accepted:** `docker/tests/lib-live.sh` is changed by Epic 12's unmerged branch (verified: `git diff origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic12 -- docker/tests/lib-live.sh` is not empty), so the dedupe waits; the lead re-owns DW-236 at adjudication.
3. **The AD-13 question (busy against signed-in visitors) is with the orchestrator** (doctrine U14: AD amendments are the orchestrator's). It does not block this story: criteria 1 to 3 do not depend on the busy rule. Do not plan Option A or B here.

### HALT: an intent gap on AD-13, and a proposed split

**1. AD-13 against the fourth criterion's case 1 (Rule 6 and Rule 5; the lead's guidance names AD-13).**
- **AD-13's rule.** `/status`, the splash and the post-sign-in check report busy from `$SYSTEM.License.InstanceConnections()` against the cap minus the reserve (8 − 2 = 6). See `Web/Public/Status.cls:71-83` and `Web/SessionEvents.cls:35,67`.
- **The criterion.** "6 scripted visitors without Visual Trace, then 3 with Visual Trace open", and in each case "one more visitor sees the busy text".
- **The measurements.** Task 0 below, the Story 16.5 measurement and the Planner's measurement on the gated host all agree: a signed-in visitor holds no connection and no licence unit.
- **The contradiction.** With 6 visitors who don't open Visual Trace, InstanceConnections stays at its baseline (1 on the gated host), so a 7th visitor is admitted and never sees the busy text. Case 1's expected result can't happen under AD-13 as written. Case 2 reaches busy only when the visitors' open trace sessions plus the baseline reach 6:
  - 3 visitors with both trace applications open: 7, busy;
  - 3 visitors with one each: 4, not busy.
- **What it also misses.** P12, NFR-23 and owner-fixed value 5 ("about 6 visitors per instance, with Demo busy beyond that") aren't delivered for visitors who never open Visual Trace.
- **The busy checks can still engage.** Each open trace session raises InstanceConnections, so this is not the "never engage" case. It is a criterion that contradicts the AD's rule.
- **Recommendation.** The orchestrator rules on AD amendments (veto window). A changed capacity number is owner-only.
  - **Option A (recommended).** Amend AD-13 so that busy also counts a number OcuTalon controls:
    - The number is the online-demo visitor sessions that hold a live CSP session. They are freed by sign-out, by the idle cap and by the 120 s timeout.
    - It is checked against a visitor cap of about 6 (P12).
    - It sits beside today's InstanceConnections check, which keeps guarding the licence for trace sessions.
    - The count must live where the sessionless `/status` and login page can read it. They run with no roles and read only `OCUTALON_PUBLIC` (AD-13, AD-19). So the session events and StatusMonitor's tick would keep it there.
    - The post-sign-in check refuses a new visitor over the visitor cap.
    - With it, `OWNCONNECTIONS` becomes 0, which is measured: a sign-in adds no connection. Then status busy and the sign-in refusal agree. This is the Planner's "one connection lenient".

    Option A keeps P12, NFR-23, owner-fixed value 5 and the criterion as written. The work fits Lane B's Epic 29 footprint (`Web/Public/**`, `Web/SessionEvents.cls`, `Data/Public/**`, `Core/StatusMonitor*.cls`), and the proposed sibling 29.7 can carry it.
  - **Option B.** Keep AD-13, and amend NFR-23, P12 and the criterion's case 1 by the measurement:
    - capacity is bounded by open trace sessions (about 5 at the reserve), and visitors without Visual Trace are not licence-limited;
    - case 1's "one more visitor sees the busy text" is dropped or reworded.

    This is owner-only, because it changes a product target number.
- **Under either option.** AD-13's and AD-25's "(inference, until Story 29.4 measures ...)" lines get the measured facts below (Rule 20, the lead's).

**2. The proposed split (Rule 5 tier 2; the lead decides).** The AD-13 question blocks only the fourth criterion. The rest is ready to build, and the whole story is more than one reviewable story. Proposal:
- **Story 29.4, "Sessions stay isolated under load"** (unchanged title and key). It keeps:
  - criteria 1 to 3 (the third stays skipped for Story 31.4);
  - DW-252, DW-333 and DW-413;
  - DW-236, declined below.

  This spec is that story's plan. If the split is accepted, the re-plan only removes this HALT section.
- **Story 29.7, "The author's load run measures the demo's capacity"** (new, the next number in Epic 29). It takes:
  - the fourth criterion, verbatim, with the AD-13 ruling applied;
  - DW-286 and DW-251, with this plan's measured facts;
  - Option A's code, if Option A is ruled.

  The plan, for its plan stage:
  - **The script: `release/demo-load.sh <base-url> --visitors N [--trace] [--max-turns M] [--interface ADDR]...`** It runs on bash 3.2 with curl and jq. It holds no host literal, and gate credentials come from the environment, as in `release/demo-host-check.sh`. Each visitor:
    1. signs in from the splash;
    2. sends the guide's watch prompt (one model turn);
    3. presses Break the feed;
    4. times the press to the phone notice from `/events` (NFR-7);
    5. approves on the phone channel (no model turn);
    6. with `--trace`, opens its trace link;
    7. signs out (`POST /session/end`, then `?IRISLogout=end`).

    Then "one more visitor" reads `/status` and the splash. It records the busy text and `X-OcuTalon-Busy` against any 5xx or error page.
  - **Reporting.** One line per visitor, and a Markdown table for the 1.0.0 notes. Every decision's `fallbackReason` is listed, so a `rate_limited` fallback is visible: that is the "retried with back-off before any fallback" measurement, through Decide's re-sends.
  - **Cost.** The script refuses to start more than `--max-turns` model turns (default 3 per visitor, so about 30 for both cases). That is far below $20 at the PRD's per-decision target (inference).
  - **Client addresses.** Each visitor's own address comes from a driver host, or from `--interface` addresses that the author provides. The script never uses `X-Forwarded-For`, because the proxy overwrites it.
  - **The CI proof** is a bounded run on the `online-demo-path` unit's stack after its browser step: 2 visitors, `--max-turns 6`, the mock. Busy is reached by the cap set from the baseline, as Story 16.5's rows do. Two more pieces:
    - a hosted check in `CHECK_SCRIPTS` for usage, exit codes and the publish-safety scan, as in `test-online-host.sh` row 15;
    - the unit's group input pattern claims `release/demo-load.sh` (the inputs rule of `test-ci-config.sh`), because `release/` is a declared non-input.
  - **The check list.** A "Load run" section in `release/demo-host-checks.md`, with the two cases, the settings, the turn budget and where the results go. H8 names it.
  - **Licence.** The script never holds more than its visitors' trace sessions, and it signs every one out (DW-287).

**Task 0, measured in this plan.** Measured on a lane-C throwaway, Community key; the gated host is the author's to measure. The setup:
- the online-demo start values and build 154, with the key `InterSystems IRIS Community`, 8 units, 8 enforced;
- `proxyAddress` set to the address IRIS sees for the test host's requests;
- visitors are curl jars of the demo account, each with its own `X-Forwarded-For`.

Readings are connections / licence units, read by an `iris_script` whose own terminal is the baseline's one:

| Step | What happened | Connections / units | Licence user list | `status.busy` |
|---|---|---|---|---|
| M0 | Baseline, no visitor | 1/1 | | false |
| M1 | A signs in (303) and polls `/state` three times | 1/1, no change (DW-251) | | false |
| M2 | A opens a Visual Trace page (OCUTALON) | 2/2 | `DemoVisitor@<the TCP peer address>`, CSPCon 1, LU 1. The unit is keyed by the TCP peer, never by the forwarded address | false |
| M3 | A also opens the OCUORDERS trace page | 3/2 | CSPCon 2, LU 1 | false |
| M4, M5 | B (another forwarded address, same TCP peer) signs in, then opens a trace page | 3/2 after sign-in, 4/2 after the trace page | CSPCon 3, LU 1 | false |
| M6 | C does the same | 5/2 | CSPCon 4, LU 1 | false |
| M8 | A signs out of the group (`?IRISLogout=end` on both trace applications and `/ocutalon/`) | 3/2 | A's two trace sessions freed at once | false |
| M10 | B and C left without signing out | Back to 1/1 between 111 and 121 s after the leave mark (taken a few seconds after their last request; 10 s sampling) | | false |
| M11 | End | 1/1 | | false |

The iris image has no curl, so a visitor from a second TCP peer was not measured here. Story 4.7 measured that each distinct user and client address takes its own unit. The run took 314 s; the stack was ready after 91 s.

Consequences (inference for the gated host, where IRIS sees the proxy as every visitor's TCP peer):
- Every visitor behind the proxy shares one licence unit, `DemoVisitor@<proxy>`, so visitor load does not reach the 8-unit ceiling, and IRIS's own 503 at the cap won't come from visitors.
- InstanceConnections counts each open trace application session and no sign-in, so AD-13's busy check engages at about 5 open trace sessions over the measured idle unit.

**Architecture decisions that govern this story (Rule 6):**
- AD-4: session ownership, `Recipients`, no `SessionRef` from the client.
- AD-11: approvals and `AnswersIn` refusing a request another session can't see.
- AD-12: `/state`, polling, the guide and Break the feed per session.
- AD-13: sign-in, the 404 envelope, busy (the HALT above).
- AD-15: watch, incident and notice.
- AD-22: testing and CI groups.
- AD-25: the topology and capacity (the HALT above).
- AD-26: Visual Trace links and the trace step.
- AD-29: the Epic 29 exception and the lanes.
- AD-32: the notification contract.
- AD-33: one owner per item.

**Integration ACs (Rule 1).** No service is introduced. The shared test helpers have consumers in this story:
- `loadedAfter`: `live:floor` (`openFloor`, 10 floor specs), `live:sign-in` (banners), and the online run (`openVisitor`).
- `opensTabStrict` and `expectOpenedDirectly`: O4 and step 6.
- `clearOfMidnight`: D1, D2, AP and D0.

The first AC and the last AC run those consumers.
- **Consumed-by:**
  - Story 11.1 turns on steps 2 to 5 in the moved file.
  - Story 31.4 turns on the three `31.4` cases.
  - The proposed Story 29.7 runs its CI proof on this unit's stack.
- **Consumes:**
  - Lane A's real watch, incident, diagnosis and approval path (Epics 5 and 7).
  - Story 16.2's splash and online run.
  - Story 16.3's visitor sessions.
  - Story 16.1's demo account and O4.
  - Story 16.9's allowance specs.
  - The mock's `guide-watch` and `diagnosis` scenarios.

**Extend, don't copy (Rule 2):**
- `loadedAfter` extends `rail.spec.ts` `open()`'s Story 16.4 wait (:82-89). Rail keeps its inline copy: it is Story 2.8's spec, it lies in `live:sign-in`'s part 2 (path order: `rail/` comes after `guide/`, near the middle of about 219 tests), and switching it would cost a run with no change in behaviour.
- `openVisitor` builds on `signInFromSplash` and `sessionRow`.
- `populate` gains options instead of being copied.
- `opensTabStrict` and `expectOpenedDirectly` move to `support.ts` and are shared.
- The unit is `test-online-allowance.sh`'s pattern with its own project.
- The report check reuses `demo-path-summary.mjs`'s skip-text rule. A new reader is needed because the online run is one file, not six step files.

**Ledger inbox (Rule 17):**
- **DW-252:** addressed by matrix row 8 and the busy.spec.ts task. Its premise is outdated, because the guide now sends prompts (`demo-guide.ts:571-580`).
- **DW-333:** addressed by matrix row 10 and the `loadedAfter` task:
  - `openFloor` is the residual that the routing note names;
  - banners' `open()` is the B17 occurrence recorded after Story 16.4's fix.
- **DW-413:** addressed by matrix row 9 and the daily-cap task (D0, and D1, D2 and AP).
- **Declined DW-236:** the ruled fix edits `iris_script` in place in `docker/tests/lib-live.sh`, and Epic 12's unmerged branch (OCT-epic12, live on runner A) changes that file (`live_no_bot_token`, `live_key_count`). That makes it a contended path where an in-place edit is an escalation, not an appended block. Recommendation: re-route it to Epic 29's burn-down once Epic 12 has merged.
- **DW-286 and DW-251:** measured in Task 0 above. They move with the fourth criterion to the proposed sibling 29.7. If the split is not accepted, they return to this spec with the load script.

**footprint_extensions:**
- `web/e2e/support/floor.ts`
- `web/e2e/banners/banners.spec.ts`
- `web/playwright.config.ts`
- `web/package.json`
- `web/scripts/playwright-projects.test.mjs`
- `docker/tests/test-ci-config.sh`, only if a pin follows

None of these is contended, and no other branch changes them. `ci/units.sh` gets only this story's own unit and list entries. The rest is in the footprint: `web/e2e-online/**`, `docker/tests/test-online-*.sh` and `docker/tests/test-online-demo-path.sh`.

**Decided in-stage:**
1. **REL-2's online run moves to its own project and unit** (`web/e2e-online/demo-path/`, `online-demo-path`, `live:online-demo-path` in `shards-2`). There are two reasons:
   - The second visitor needs the keys pointed at the mock. Without them every decision is a `no_key` fallback, and no approval request is raised. The `online-demo` unit keeps them unpointed during its browser step.
   - `install-upgrade` (30.9 min) has no room, and `shards-2` has about 14 min.

   Expected: about 5 to 6 min locally and 7 to 8 min on CI, so `shards-2` becomes about 28 min (inference).
2. **Watches come from each visitor's own guide watch prompt**, the demo path's step-2 action, so that step 6 traces a real decision with agent steps. The reminder, the pairing (a fixture row) and the mail are seeded. The paired chat's messages are Story 31.4's.
3. **"Any of A's channels"** means this: A's card offers Approve and Reject (the web channel), and A answers on the simulated phone (REL-2's step-5 channel). One request takes one answer. Telegram is 31.4's.
4. **The third criterion stays skipped as a whole.** Its Given is a paired mock Telegram chat.
5. **Only step 6 and the second visitor are turned on**, in the criterion's words. Steps 2 to 5 stay with Story 11.1.
6. **Step 6's oracle:**
   - the tab is at `traceUrl`;
   - no trace document is a sign-in page;
   - Visual Trace draws the turn's header and at least `agentStepCount` other messages (AD-26: the chain shares the thread's session);
   - the decision details show the steps and the cost.
7. **DW-413's guard is a pure function** with an injectable read and sleep, pinned by a browserless case. The real midnight path can't be scheduled.
8. **IRIS mutations run on the unit's fresh stack** with `-g`, one case at a time.
9. **Task 0 ran in this plan** on a throwaway (tag `e29s4plan`, torn down by its own EXIT trap).

## Verification

Every call runs in the foreground with `timeout: 600000`, one test call per message, against named lane-C targets. `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement'`. There are no class or shard runs, so there is no warm mode: live units refuse it.

**Commands:**
- (once, first) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh build`. Expected: the web bundle matches `web/src` after the merge (Rule 21). Repeat it after any change under `web/src`.
- (loop) `npm --prefix web run lint`. Expected: the e2e TypeScript compiles.
- (loop) `npm --prefix web test`. Expected: the project pins pass, `online-demo-path` included.
- (loop) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live online-demo-path`. Expected: PASS, with the report set of row 7. Record the unit's seconds and the browser step's seconds (about 5 to 6 min, inference).
- (once) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live online-demo`. Expected: PASS with DW-252's case, and the project no longer runs the online run (about 310 s).
- (once) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live online-allowance`. Expected: PASS with D0 and the changed D1, D2 and AP (237 to 244 s).
- (once) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live floor`. Expected: PASS with `loadedAfter` (235 to 244 s).
- (once) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh live sign-in --part 1/2`. Expected: PASS. Its listing holds `banners/banners.spec.ts`; if it doesn't, run `--part 2/2` instead.
- (once) `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-ci-changes.sh`. Expected: both pass. The latter's loop proves that `docker/tests/test-online-demo-path.sh` runs only `shards-2` through `ci/changes.sh`.
- (once) `bash ci/checks.sh`. Expected: every block passes (about 4 min).
- (once, at the end, also after a failure) `LANE OCUTALON_RUN_TAG=e29s4i bash ci/iris.sh teardown`. Expected: nothing tagged `e29s4i` is left.

**Shared surfaces:**
- the `online-demo` project's file list: it loses the online run (`playwright-projects.test.mjs`);
- the new `online-demo-path` project and its npm script;
- `shards-2`'s units and `BROWSER_UNITS` (`test-ci-config.sh`, `test-ci-changes.sh`);
- `populate`'s signature (every caller under `web/e2e-online/`);
- `cappedMarked` and `unmarkCapped`'s signatures (every caller under `web/e2e-online/allowance/`);
- `openFloor` (10 floor specs);
- the O4 helpers' home (`demo-account.spec.ts`).

The implement stage searches the test trees for each of these.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. Each online-run case creates and removes its own sessions and rows, and the mutation runs below run single cases alone.

**Mutations (Rule 19), one per AC.** Each is applied, observed red, reverted, and the tree confirmed byte-identical:
- AC1: mutation: `Data/Session.cls` `Recipients` also returns every other session of the same IRIS user. Expected red: the second-visitor case at row 2 (B's phone gets A's notice). Run with `live online-demo-path -g "second visitor"`.
- AC1, step 6: mutation: `Web/TraceLink.cls` adds 1 to `SESSIONID`. Expected red: step 6 (the turn is not drawn).
- AC1, row 7: mutation: one `notBuilt(..., '31.4')` becomes an empty passing test. Expected red: the unit's report check.
- AC2: mutation: `Data/Ownership.cls` `Approval` returns the row whatever its owner. Expected red: the second-visitor case at row 4.
- AC3 (CI): mutation: `online-demo-path` is left out of `BROWSER_UNITS`. Expected red: `test-ci-config.sh` ("it runs Playwright, but online-demo-path is not in BROWSER_UNITS").
- AC4: mutation: `online-demo` without the `demo-path/` ignore. Expected red: `npm --prefix web test`.
- AC5, DW-252: mutation: `chat-outbox.ts` `refuse()` without `!entry.fromGuide &&`. Expected red: the new busy case (the prompt lands in the composer). Run `ci/iris.sh build` before the mutation run and after the revert.
- AC5, DW-413: mutation: `clearOfMidnight` never sleeps. Expected red: D0.
- AC5, DW-333: mutation: `loadedAfter` waits for the snapshot only, with a temporary 12 s hold on GET `/state` in one floor case. Expected red: that case. With the fix and the hold, it is green.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: AD-13 (the busy rule) contradicts the fourth criterion's case 1 ("6 scripted visitors without Visual Trace ... one more visitor sees the busy text"). MEASURED on a lane-C throwaway (Community key; the gated host is the author's to measure): a signed-in visitor holds no connection and no licence unit (DW-251); each open Visual Trace application session raises InstanceConnections by one, while the licence unit is keyed by user and TCP peer, so visitors behind one address share one unit. So 6 visitors without Visual Trace leave InstanceConnections at the baseline, and a 7th is admitted and never shown the busy text (case 2 reaches busy only with about 5 open trace sessions). Recommendation (orchestrator; owner-only if a capacity number changes): Option A, amend AD-13 so busy also counts OcuTalon's own live visitor sessions against a visitor cap of about 6 (P12), kept where the sessionless status can read it, with OWNCONNECTIONS 0; or Option B, keep AD-13 and amend NFR-23/P12 and case 1 by the measurement. Also proposed (Rule 5 tier 2, the lead decides): split the fourth criterion, DW-286 and DW-251 into a new sibling, Story 29.7 "The author's load run measures the demo's capacity", so that 29.4 (criteria 1 to 3, DW-252, DW-333, DW-413; DW-236 declined because docker/tests/lib-live.sh is contended by Epic 12) is planned and can proceed as soon as the split is accepted.
