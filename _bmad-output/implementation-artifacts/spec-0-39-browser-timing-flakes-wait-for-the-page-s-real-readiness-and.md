---
title: 'Story 0.39: Browser-timing flakes wait for the page''s real readiness, and a turn at the UTC day rollover does not error'
type: 'bugfix'
created: '2026-11-16'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [multiple-goals, oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nine red CI runs from the 2026-11-16 tally (DW-349, DW-555, DW-1448, DW-1450, DW-1451, DW-1452, DW-1457, DW-1458, DW-1464) were races in tests, not product defects. Each test acted before the page or the stack was ready (a reload whose app never started, a retried navigation that met the first attempt's late error page, a response promise that never settles, a sign-in straight after an IRIS process ended). DW-1464 is different: at the UTC day rollover, the CI model mock found two guide prompts in one message and answered 500. So a red run no longer reliably means a real defect.

**Approach:** Fix each flake at its cause, in test code and test infrastructure only. Each test waits on the real readiness signal it skipped: the reloaded page's own `GET /ocutalon/api/v1/state`, the failed navigation's committed error page, the end (finished or failed) of every matching request, or the public status reading not busy. The CI mock's guide-prompt rule breaks a tie by ignoring quoted context lines (`> `). Each fix is proved by a deterministic repro (old red, fixed green) and by a loop of 10 or more iterations under load, with counts before and after.

**Contest Planner's binding conditions:**
- Fix the cause of each flake.
- Wait on the real readiness signal, never a sleep.
- No blanket timeout raises.
- No added retries that hide a failure.
- No weakened assertions.
- A timeout change is allowed only where it is truly the only fix, and it is justified per test (Design Notes).
- A change to product code is a Planner gate item. None is planned: DW-1464's fix is in the CI mock (`ci/mock/`), which is test infrastructure, not product code.
- Each fix is proved by a loop of the affected spec under load (at least 10 iterations beside a busy stack, counts before and after), plus its deterministic repro as the Rule 19 mutation.

## Boundaries & Constraints

**Always:**
- Group order for implement:
  1. chrome-error (`navigate.ts`);
  2. reload (`floor.ts` `reloadSettled`, then the four specs);
  3. MC3;
  4. row 6;
  5. the DW-1464 mock.
- Every wait is bounded by a bound the test already has: the helper's own bound, the time left in it, or the action wait in force. A bound that passes fails with a message that names the step and the signal it waited for.
- Changed tests stay self-contained: each one creates and removes its own state and passes on a fresh environment, in either order.
- Pins move with their text (search `web/scripts/*.test.mjs` and `docker/tests/*.sh` for every source pin on a changed file). A pin is never deleted or weakened.
- Repro injections and loop harnesses are scratch only. Revert each byte for byte: `git status --short` and `git diff --stat` must read as they did before.

**Never:**
- Change product code: `src/` outside `src/ocutalon/cls/OcuTalon/Test/`, and `web/src/`. If implement finds a product fault, stop with `## Clarification Needed`. Two cases count as a product fault:
  - row 6 still refused after the status read not busy just before S5;
  - an app that does not start after a reload in which every asset loaded.
- Add a sleep, a new retry, `retries:` in `web/playwright.config.ts`, a raised test or expect timeout, or a skip.
- Add the chrome-error interruption to `RETRYABLE`. That would be a hidden second retry.
- Touch `ci/iris.sh`, `ci/units.sh`, `docker/tests/test-sign-in*.sh`, `test-demo-path.sh`, `test-floor.sh` or `web/playwright.config.ts`.
- Touch the other bare `page.reload()` sites, about 45 of them (Planner gate 2).
- Commit a scratch switch, a loop wrapper or a shim.
- Use a dev slot or any instance other than lane A's throwaways (Rule 21).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| N1 (DW-349, DW-555): late error page | First `goto` throws `net::ERR_NETWORK_CHANGED`, and Chromium commits `chrome-error://chromewebdata/` a moment later. | `gotoSettled` waits for that URL (`waitUntil: 'commit'`, current URL checked first), logs `NAV retry <url> after <first error line>`, then makes its one existing retry. The second goto answers. | none |
| N2: error page never shows | `ERR_NETWORK_CHANGED`, and no error page within the time left in the bound. | Throws `gotoSettled: the failed navigation's error page did not show within <s> s from <url>`, with `cause` set to the first error. No second goto. | named error |
| N3: aborted navigation | `net::ERR_ABORTED` (no error page) | Today's behaviour: no wait, then one retry. | unchanged |
| R1 (DW-1448, 1452, 1457, 1458): reload, app never starts | The main bundle is aborted once (repro), or CI's network change. | `loadedAfter(page, () => page.reload())` (main route), or `reloadSettled(page)` (History). No `/state` answer by half the bound gives one `RETRY <spec>:<line> ...` line (counted by `ci/iris.sh`) and one reload, then green. | No answer at the bound: the named bound error plus the `DIAG /state` lines. |
| R2 (DW-1457): heartbeat read fails | The heartbeat GET after the HC8 reload answers 500. | Fails with the message naming "the heartbeat GET answered 500", not as "Today: not found". | named failure |
| M1 (DW-1451): a 500 that is then aborted | Two notes GETs. One answers 500 and the card aborts the other after its headers arrived. | `handled` resolves once every matching request issued since arming has ended (finished or failed), with at least one at the wanted status. No 45 s hang. | A bound pass names the route and the number still open. |
| O1 (DW-1450): connection not yet released | After `set_cap $cap_free`, the halted script's connection is still counted. | Row 6 waits until `status_read` reads `false none 200` (`wait_until`, immediate first check), then signs in once. | Not free in 30 s: fails naming the last status. Still refused after free: stop (a product gate item). |
| K1 (DW-1464): midnight tie | The newest user message holds `> 23:59 message (web): <watch prompt>` (quoted notes) and the unquoted reminder prompt, with mock key `chat`. | The mock selects `guide-reminder`, `selectedBy: prompt`, 200. | none |
| K2: real tie | Two unquoted prompts | 500 `two guide prompts match` (unchanged) | unchanged |
| K3: mail triage | Quoted email bodies that match one prompt | Unchanged: the strip is applied only when 2 or more prompts match. | unchanged |

</intent-contract>

## Code Map

Everything below was verified at `37b55fb8fbbca21a0709feadfbff4207bfb628e3` (feature `1f8733c0e729d7bfc8237c2fb837b2c12b4ee9eb`, plus the charter). The read-only investigation is in `<scratchpad>/e0fl-inv/findings.md` and `host-pattern.md`.

**Group 1: chrome-error**
- `web/e2e/support/navigate.ts`:
  - `Navigable` at L7 is `Pick<Page,'goto'>`. Widen it to `'goto'|'url'|'waitForURL'`.
  - `RETRYABLE` is at L10.
  - The retry in `gotoSettled` is at L58-64: `console.log(\`NAV retry ${url}\`)`, then `return go()`.
  - `go()` recomputes `capToDeadline(own)` on each call. Use the same bound for the error-page wait.
- `web/scripts/goto-settled.test.mjs`:
  - `fakePage` is at L19-30. It needs `url()` and `waitForURL`.
  - The NAV-line pins at L61 and L77 change with the new text.
  - The new rows go in the `describe('gotoSettled')` block.
- `web/scripts/bounded-waits.test.mjs` L227 and L314 pin `navigate.ts` source. Re-check them.

**Group 2: reload**
- `web/e2e/support/floor.ts`:
  - `withOneReload` is at L149-206.
  - `loadedAfter` is at L225-248. Its last check is `mainOf(page)` `data-snapshot=loaded` (L244). `mainOf` (L52) is `main.main`.
  - Extract the `/state` part (arm, `withOneReload`, `diagnosedAtBound`, status 200) into one private function that takes a step label.
  - `loadedAfter` keeps its behaviour and its labels.
  - New `reloadSettled(page)`: the `/state` part around `page.reload()`, labelled `reloadSettled the snapshot GET ${STATE}`, with no `main.main` check, for routes other than the main page. `App` calls `LiveState.load()` on every route (`web/src/app/app.ts` L77).
- Pins on `floor.ts`: `web/scripts/flake-fixes-sources.test.mjs` L72-73 pins the `reportRetry(\`loadedAfter the snapshot GET ${STATE}\`...` text; `bounded-waits.test.mjs` L215; `retry-bounds.test.mjs` L151. The RETRY line regex is `ci/iris.sh` L748 (`^RETRY [A-Za-z0-9._/-]+:[0-9]+ [A-Za-z0-9 ./:_-]+$`).
- Precedent: `loadedAfter(page, () => page.reload())` is already used at `chat/notice.spec.ts` L740 and L768, `files/files.spec.ts` L130 and `floor/guide.spec.ts` L820.
- `web/e2e/demo-path/telegram-page.spec.ts` (project `demo-path`, unit `live demo-path`):
  - The local `loaded()` at L106 is a bare `main.main` wait.
  - Reload sites (each `page.reload()` followed by `loaded(page)`): L219-220 (T2, failed), L287-288 (T1), L590-591, L623-624 and L637-638 (T4), L780-781 (T5).
  - T1 (L300) and T5 (L778) count code requests across a reload; a retried reload asks for none while paused or paired. Check this.
- `web/e2e/history/history.spec.ts` (project `chromium`, unit `live sign-in`): bare reloads at L174 (H2), L218 (H3) and L361 (H7, failed). H7's pre-existing `waitForTimeout(1500)` at L320 is left alone (Design Notes).
- `web/e2e/guide/guide.spec.ts` (project `sign-in-3`): `reopen()` at L112-115 is a bare reload plus a `main.main` wait. It has 16 callers; Q7 failed at L486 via L511. The spec uses `page.clock`; the helper's timers run in Node.
- `web/e2e/heartbeat-card.spec.ts` (project `sign-in-3`):
  - HC8 runs from L369: `nearMidnight` skip, `test.setTimeout(150_000)`.
  - HC8's reloads are at L413, L419 (failed), L425, L430 and L434. `rewriteGet` (L145-152) answers with `route.fetch()` plus `route.fulfill({response, json})`, which keeps the real status. The `HEARTBEAT` constant is the route.
  - The card is on the main page (`withCard` uses `signInReadmeLoaded`).

**Group 3: MC3**
- `web/e2e/memory-card.spec.ts` (project `sign-in-3`):
  - `answerOf` (L110-112) is `waitForResponse` by route, method and status.
  - `handled` (L118-121) is `await (await answer).finished()` plus two frames. `finished()` never settles for a request that fails after its response (Playwright 1.64.1), so the test hit its 45 s timeout.
  - MC3 runs from L219; its 500 phase is at L243-256.
  - Other `handled` callers (single requests): L256, L459, L556, L562, L686, L694, L779. Every caller calls `answerOf` before its action.
  - The card reads both days with `forkJoin` (`web/src/app/rail/memory-card/memory-card.ts` L763; read only).

**Group 4: row 6**
- `docker/tests/test-online-demo.sh` (unit `live online-demo`, about 384 s locally per the 29.9 record):
  - The Story 16.5 busy rows: `cap_free` and `cap_busy` at L1083-1084, S3 and S4 at L1131-1172.
  - Row 6 at L1174-1194: `set_cap "$cap_free"` (L1176), then `conn_before_s5=$(script_connections)` (L1179, an iris process), then `online_signin` S5 at once (L1180). Its fail line is at L1193.
  - `page_outcome` (L606-614) knows only `shell`, `limit` and `other`. `busy_page` is at L1008 and `marker_in` at L1006.
  - `set_cap` (L971) and `script_connections` (L973) each run an iris session.
- `docker/tests/lib-online.sh` L153-164 `status_read`: an HTTP GET of `/ocutalon/public/status`, which takes no licence connection.
- `docker/tests/lib-live.sh` L463-475 `wait_until <max> <cmd>`: the first check is immediate, then every 3 s, bounded by the run's deadline.
- Read only: `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls` L92-116. `Busy()` is `InstanceConnections() - own >= cap - reserve` (plus visitors). Row 6 sets cap = view + reserve + 1 = 3, so a single lingering connection makes the status busy.

**Group 5: DW-1464 (the CI mock)**
- `ci/mock/mock.mjs`:
  - The rule-3 header comment is at L34-36.
  - `select()` runs from L470. The prompt hits are at L492-496, and a tie is a 500 with `ambiguous-prompt` (L493-495).
  - The 500 is refused at L831-834.
- `ci/mock/scenarios/B/guide-watch.json` and `guide-reminder.json` (read only): both have mock key `chat`. Their prompts: "Watch the Orders production and only tell me if something needs me." and "Remind me in 1 minute to stretch."
- `ci/mock/test/server.test.mjs` L274-303 holds the row-7 prompt test, with GUIDE_ONE and GUIDE_TWO and the both-unquoted 500 at L297-301. Run the mock tests with `bash docker/tests/test-mock.sh`.
- Read only: the product quotes every context line with `> `. `src/ocutalon/cls/OcuTalon/Agent/Input.cls` L67 renders `NotesPart` before `item.Text` for a user item. `NotesPart` (L133-153) adds yesterday and today, each `Quoted`, only when `sessionStart` is 1.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` (area Contract, shard lane-b):
  - `Provider(mockKey)` L314 and `LogSince` L545 are public.
  - `Guard()` L580 and `Find` L603 are private.
  - Pattern: `TestDefaultScriptByMockKey` L145-187.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RenderMemory.cls` has the fixtures `Session`, `Turn(session, clock, text)` and `Item`, the days `DAY` 2030-06-15 and `BEFORE`, and `TestNotesLeaveOutCurrentTurn` L273-287 (the `> 09:00 message (web): ...` shape).

## Tasks & Acceptance

**Execution (in this order):**

0. **Task 0: measure and record the before state.** Run on the unchanged tree. Record everything under `## Verification`.
   - (a) Real-browser measurement, no stack. Write a scratch Node script at `<scratchpad>/e0fl/measure.mjs`. It imports `playwright` from `web/node_modules` with `createRequire`.
     - Launch Chromium. Route `**/*` to `abort('internetdisconnected')`.
     - `goto` once and record: the error, `page.url()` right after the reject, and whether `page.waitForURL('chrome-error://chromewebdata/', {waitUntil:'commit', timeout: 5000})` resolves.
     - Over 50 tries, record how often an immediate second `goto` throws `interrupted by another navigation`.
     - If the URL never becomes `chrome-error://chromewebdata/`, stop with `## Clarification Needed`: N1's signal would be wrong.
   - (b) Before loops: the loop commands under Verification on the old tree, one per unit.
   - (c) Each group's repro injection on the old tree: expect red with the CI signature. Revert it.
1. `web/e2e/support/navigate.ts`: N1 to N3 (DW-349, DW-555).
   - Widen `Navigable`.
   - For `ERR_NETWORK_CHANGED` only, wait for the error page within the time left in the bound before the existing single retry.
   - Throw the N2 named error when it does not show.
   - Change the NAV line to `NAV retry <url> after <first line of the first error>`.
   - Update the doc comment (contract only).
2. `web/scripts/goto-settled.test.mjs`:
   - Give `fakePage` `url()` and `waitForURL`.
   - Add these rows:
     - late error page: the old code throws the interruption, the new code answers 200;
     - error page never shows: N2's message and `cause`, one goto;
     - `ERR_ABORTED` does not call `waitForURL`;
     - the NAV line names the first error.
   - Move the NAV-line pins with their text. Re-check the `bounded-waits.test.mjs` pins.
3. `web/e2e/support/floor.ts`: extract the shared `/state` wait from `loadedAfter` (Rule 2: extend, don't copy). `loadedAfter` stays the same, observably and in its labels. Export `reloadSettled(page)` (R1, non-main routes) with its own RETRY step label. Move the `floor.ts` source pins with their text.
4. `web/e2e/demo-path/telegram-page.spec.ts` (DW-1448): replace `await page.reload(); await loaded(page);` with `await loadedAfter(page, () => page.reload());` at the six sites. Delete the local `loaded()`. Confirm that T1's and T5's code-request counts still hold.
5. `web/e2e/history/history.spec.ts` (DW-1458): `await reloadSettled(page);` replaces the bare reload at L174, L218 and L361. The assertions are unchanged.
6. `web/e2e/guide/guide.spec.ts` (DW-1452): `reopen()` becomes `loadedAfter(page, () => page.reload())`.
7. `web/e2e/heartbeat-card.spec.ts` (DW-1457), for HC8's five reloads:
   - before each reload, arm a wait for the heartbeat GET;
   - reload through `loadedAfter(page, () => page.reload())`;
   - assert that GET's status is 200, with a message naming "the heartbeat GET" (R2);
   - then the existing line assertions, unchanged.
8. `web/e2e/memory-card.spec.ts` (DW-1451, M1):
   - `answerOf` arms an end tracker when it is called (requests matching route and method issued from then on, each ended by `requestfinished` or `requestfailed`).
   - `handled` awaits the first response with the wanted status. It then waits until every tracked request has ended, bounded by the action wait in force and named on failure, then the two frames.
   - The same contract serves every caller.
9. `docker/tests/test-online-demo.sh` (DW-1450, O1), in row 6:
   - read `conn_before_s5` before `set_cap "$cap_free"`;
   - add `status_free() { [ "$(status_read)" = "false none 200" ]; }`;
   - `wait_until 30 status_free`, or fail with `row 6: the status did not read free within 30 s after the cap was set to $cap_free (last '<reading>')` and skip the sign-in;
   - sign in once;
   - the fail line also prints the S5 POST status and `busy_page "$jar_s5.b"`, as labels only. `page_outcome` and every pass condition stay unchanged.
10. `ci/mock/mock.mjs` (DW-1464, K1 to K3):
    - In `select()` rule 3, when `hits.length > 1`, match again on the text with every line that starts with `> ` removed.
    - Exactly one hit selects it (`selectedBy: 'prompt'`). Otherwise keep today's 500.
    - Update the rule-3 header comment (L34-36) to say so.
11. `ci/mock/test/server.test.mjs`: next to row 7, add rows K1, K2 and K3. K1's body holds the preamble, the notes opening, `> <day>`, `> 23:59 message (web): <GUIDE_ONE prompt>`, a blank line, then the GUIDE_TWO prompt.
12. `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` (DW-1464, outermost deterministic surface): add `TestMidnightReminderPicksItsPrompt`, guarded like its siblings.
    - Seed its own session and a web `Turn` at `<DAY>T23:59:59Z` with the guide-watch prompt. Reuse RenderMemory's `Session` and `Turn` fixtures; if they are private, make them reusable or write a minimal seed and give its reason in the commit.
    - Render the guide-reminder item with `{"sessionStart":1}` twice: at `<DAY>T23:59:59Z` (the note under today) and at `<DAY+1>T00:00:01Z` (the note under yesterday).
    - At both times: the watch prompt appears only on lines starting `> `, and the text ends with the reminder prompt unquoted.
    - Send each through a `%AI.Agent` on `Provider("chat")`. Assert, from the mock log, scenario `guide-reminder`, `selectedBy` `prompt`, status 200, and no error before the first agent step.
    - Remove the seeds.

**Acceptance Criteria:**
- AC1 (DW-349, DW-555): Given a navigation whose first attempt fails with `ERR_NETWORK_CHANGED` and whose error page commits late, when `gotoSettled` retries, then the retry happens after the error page committed. The navigation answers with no interruption error, and the NAV line names the first error. mutation: delete the error-page wait → the N1 row goes red with the chrome-error interruption.
- AC2 (DW-1448, DW-1458, DW-1452, DW-1457), Integration AC for `reloadSettled` and the reused `loadedAfter`: Given the main bundle aborted once just before the reload under test (T2, H7, Q7's second reopen, HC8 at L419), when the test runs in its unit, then:
  - the old test is red with the CI signature (the element is not found after the reload);
  - the fixed test is green with exactly one `RETRY <spec>:<line> ...` line, and the unit's RETRIES count is 1.
  
  mutation: the repro on the old site → red. Then `reloadSettled` with its retry removed → H7 red under the repro.
- AC3 (DW-1457): Given the heartbeat GET answers 500 once after HC8's reload, when HC8 runs, then it fails with the message naming the heartbeat GET and status 500. mutation: that injection → red with the named message.
- AC4 (DW-1451): Given MC3's 500 phase with the yesterday read's body held after its headers and today answered 500 after yesterday's response event (scratch repro: a local server continued to by `route.continue`), when MC3 runs, then the old `handled` times out at 45 s at L119 and the new one is green, well inside its bound. mutation: the repro on the old `handled` → red.
- AC5 (DW-1450): Given a scratch hold before S5 (a background `iris session` that holds a connection for 5 s, started after `set_cap "$cap_free"`, with a wait until the status reads busy), when row 6 runs, then:
  - the old row is red (`'other'`, no cookie, 0 counter rows);
  - the fixed row is green after its status wait.
  
  mutation: that hold.
- AC6 (DW-1464): Given the reminder item rendered at 23:59:59 and at 00:00:01 UTC after a watch turn at 23:59:59, when it reaches the CI mock through `%AI.Agent`, then the mock answers `guide-reminder` with 200. The day-keyed read that caused the error is named in Design Notes. mutation: remove the tie-break → `TestMidnightReminderPicksItsPrompt` and node row K1 go red with `two guide prompts match`.
- AC7 (all eight timing DWs): Given each affected test, when its loop runs at least 10 iterations beside the lane's busy stack plus one CPU burner per host core, before and after the fix, then both counts are recorded and the after loop is green (all passed).
- AC8: Given CI on this story's head, when it finishes, then every workflow is green.

## Spec Change Log

## Review Triage Log

## Design Notes

**The tally** (runs, runners and hosts from the 2026-11-16/17 tally; heads from `gh run view`):

| DW | Test | Head / run | Runner | Host | Cause | Fix | Gate? |
|----|------|-----------|--------|------|-------|-----|-------|
| DW-1448 | `demo-path/telegram-page.spec.ts:196` T2 | `c321d4680bf1f76d09a885c42df683c7b0046260` / 43934206289 (browser, demo-path) | ocutalon-ci-11 | ci-c | After a bare reload, the app never started (main bundle most likely `ERR_NETWORK_CHANGED`; inference) | `loadedAfter(page, () => page.reload())` at 6 sites | yes (1) |
| DW-1458 | `history/history.spec.ts:316` H7 | `948e17b5b1a0813bc1f802c0fd40de65c54e7428` / 43977036761 (shards-10, sign-in) | ocutalon-ci-19 | ci-d | same as DW-1448 | `reloadSettled` at L174, L218 and L361 | yes (1) |
| DW-349 | `floor/focus.spec.ts:145` P4 | `1f8733c0e729d7bfc8237c2fb837b2c12b4ee9eb` / 43970555894 (shards-3, floor) | ocutalon-ci-19 | ci-d | `gotoSettled`'s retry meets the first attempt's late `chrome-error` commit | Wait for the error page, then the one retry | no |
| DW-555 | `usage/usage.spec.ts:418` U12 | `7a346a99452673a5e37bd6cc481e3a4842b59254` / 43978832236 (shards-10, sign-in) | ocutalon-ci-18 | ci-d | same as DW-349 | same as DW-349 | no |
| DW-1450 | `test-online-demo.sh` row 6 | `d996ffcde711f9a759657cb81fa193c99d80d0fa` / 43939939727 att 1 | ocutalon-ci-31 | ci-f | S5 signed in right after an iris process, whose connection was not yet released, so the status was busy | Wait on `status_read` free, then one sign-in | no (yes if still refused when free) |
| DW-1451 | `memory-card.spec.ts:219` MC3 | `d18c9a55c71b96050b2f8d7fc836b33343a27f54` / 43943159296 | ocutalon-ci-27 | ci-f | `Response.finished()` never settles for a request that fails after its response (forkJoin abort) | End tracker (finished or failed), bounded | no |
| DW-1452 | `guide/guide.spec.ts:486` Q7 | `854346fa1d8bac5130503004463bdcc461ba2800` / 43957453035 (shards-5, sign-in-3) | ocutalon-ci-18 | ci-d | `reopen()` is a bare reload whose app never started | `reopen` uses `loadedAfter` | yes (1) |
| DW-1457 | `heartbeat-card.spec.ts:369` HC8 | `1f8733c0e729d7bfc8237c2fb837b2c12b4ee9eb` / 43970555894 (shards-5) | ocutalon-ci-17 | ci-d | After a bare reload, either the app did not start or the heartbeat GET was late or failed | `loadedAfter` plus the heartbeat GET asserted 200 by name | yes (1) |
| DW-1464 | `live:demo-path` 03-reminder | `b2768afeb8301de3d21bba321ede5da665a06951` / 43982398541 | ocutalon-ci-25 | ci-e | First turn of a new day: the quoted notes held the watch prompt, so the mock found two prompts and answered 500 | Mock tie-break ignores `> ` lines (test infrastructure, not product) | yes (4) |

**Host pattern** (the lead's note):
- Five of these nine DWs ran on host ci-d (runners 17, 18 and 19). The tally as a whole has 8 of 17 rows on ci-d (47%).
- Measured over every completed run since 2026-11-16 (attempt 1, iris jobs), jobs per host are even. First-attempt failures were ci-d 7 against 2 to 5 on each other host. Runners 17 to 19 failed 5 of 37 jobs (13.5%), against about 3 to 4% on ci-b, ci-c and ci-e.
- The samples are small: this is a lead, not proof, and the Planner's host rule fires at about 25 rows.
- These fixes make the tests correct on any host. The host itself is the infra follow-on in gate 1.

**Planner gate** (the lead sends these items before implement; each is planned as the recommended option):
1. **The reload group** (DW-1448, DW-1458, DW-1452, DW-1457).
   - What it means: `loadedAfter` and `reloadSettled` bring Story 32.6 / DW-550's one logged retry to reload sites. The retry is CI-counted and comes with DIAG lines.
   - Recommended: adopt it. The retry is printed, counted by `ci/iris.sh` and diagnosed, so it is not hidden.
   - Alternative: the same wait with no retry, through an option passed by these sites only. A stall then fails sooner, at the half-bound, with the named DIAG.
   - Follow-on, not this story: give Chromium its own network namespace in CI so that host interface changes never reach it (unmeasured).
2. **Scope.** The other bare `page.reload()` sites, about 45 of them (chat 5, notice 5, answers 3, floor/keyboard 4, rail 2, phone 2, demo-switch 4, sources 2, and more), go to a follow-on story, unless the Planner rules otherwise.
3. **Optional confirmation.** Fetch the kept traces by SSH:
   - ci-c `<trace_root>/43934206289-1-browser/demo-path/telegram-page-the-Telegram-bf365-…/trace.zip`;
   - ci-d `<trace_root>/43977036761-1-shards-10/sign-in/history-history-H7-the-tab-275b6-…/trace.zip`.
   
   This is the Planner's call (ci-d is temporary). The story does not depend on it.
4. **Lanes and AD-22, for DW-1464.**
   - AD-22 says Lane A extends the mock only by adding scenario files, and new mock behaviour is Lane B's (AD-33). This Epic 0 story (dispatched on lane A) changes `mock.mjs` `select()`.
   - It also changes other Lane B files: `history.spec.ts`, `test-online-demo.sh` and `Test.Contract.Mock`.
   - Recommended:
     - The Planner confirms the crossing under Epic 0's cross-lane re-open ruling, limited to the files of this spec, as Story 25.8's AD-33 line was recorded.
     - The lead adds the tie-break to AD-22's "How a request picks its scenario" in the bookkeeping commit (Rule 20; veto item 9). Suggested text: "two guide prompts that both match are told apart by ignoring lines that start with `> ` (quoted context); one remaining match is selected, else 500".
   - Alternative: a Lane B story makes the mock change. DW-1464 then stays open, and any demo-path run that crosses midnight after an earlier guide prompt stays red.
   - Not a product change (product code is unchanged). A real model is not keyed by prompt text, so real users are not affected.

**Governing ADs:**
- AD-22: testing, CI and the mock's selection. Group 5 amends it through gate 4. No AC contradicts its Rule.
- AD-12: the snapshot `/state` is the page's readiness signal.
- AD-21: session-start notes are quoted (read only).
- AD-13 and AD-25: the busy splash and the connection cap of the online demo (read only; row 6 changes no behaviour).
- AD-29 and AD-33: lanes (gate 4).

No AC contradicts an AD.

**DW-1464, the day-keyed read on the turn path:**
- The read: `Agent.Input.NotesPart`, through `NoteOf(session, day)` for the local yesterday and today. It is reached when `Core/Conversation` `StartsSession` sends `sessionStart: 1` on the first turn of a new local day.
- What it did: it quoted 02-watch's 23:59 message into 03-reminder's input, which made the mock tie, answer 500, and the turn fall back with `agentStepCount` 0.
- The only other day-keyed read before the model is `Budget.State`, through Decide's Precheck. A capped day gives `daily_cap`, never `error`.

**Integration (Rules 1 and 2):**
- Consumes: `loadedAfter` and `withOneReload` (Story 32.6), and `gotoSettled` (Story 11.9).
- Consumed-by: `reloadSettled` is new. Its consumers are this story's H2, H3 and H7 (AC2 is their integration AC, run against a real stack), and the follow-on story for the other bare reloads (gate 2).
- Extend, don't copy: `reloadSettled` extends `loadedAfter` (`web/e2e/support/floor.ts`) through the extracted `/state` wait. `handled` keeps one contract for every caller.

**Timeouts, per test** (no test or expect timeout is raised):
- T1, T2, T4 and T5; H2, H3 and H7; Q7 (16 reopens); HC8's five reloads: after the reload the wait moves from a bare 10 s expect to the helper's standing bounds. Those are the navigation bound for the reload and the action bound for `/state`, with the logged half-bound retry (gate 1). This is the same bound every `loadedAfter` caller has today.
- MC3 and the other `handled` callers: an unbounded `finished()` becomes a wait bounded by the action wait in force. This tightens it.
- P4 and U12: the error-page wait uses the time left in `gotoSettled`'s existing bound.
- Row 6: a new `wait_until 30` on the status signal.
  - Why 30 s: it is a ceiling, not a sleep. The first check is immediate, it polls every 3 s, and the run deadline also bounds it.
  - The release is expected to take well under a second (inference). 30 s leaves room on a loaded host and is far less than the unit's deadline.

**Decided in-stage:**
1. The epic context `epic-0-context.md` is reused as directed. The planning folder's mtime is newer only because of the Story 0.39 charter commit `77db7217275666f7f66e2440a39be964773b3cac`.
2. Scope inside each failing spec: the failing test's own helper and its sibling sites are fixed (telegram's shared `loaded()`, guide's `reopen()`, history's three reloads, HC8's five). This is the same cause in the same file. Other files' reloads are gate 2.
3. Row 6 gets no new `busy` value in `page_outcome`, which other rows read. The busy label is printed in row 6's fail line only.
4. The loop and hold for row 6 and every repro injection are scratch edits, reverted. No committed test switches (`OCUTALON_ROW6_*`).
5. The chrome-error premise is measured in Task 0 (a), with no stack. No committed real-browser row: the fake-page rows are the Rule 19 evidence once (a) confirms the ordering.
6. DW-1464's outermost deterministic test is in `Test.Contract.Mock`, which owns the mock request seam. A real midnight demo-path run is not deterministic.
7. DW-1464's "loop" is the node row K1 run 10 times (red before the mock change, green after). It is not a timing flake.

**Not in scope (observed):**
- DW-555's `?signedOut=1` variant (run 42406393504, `navigate.ts` first attempt after the sign-out redirect) has a different cause. The lead may ledger it.
- H7's existing `waitForTimeout(1500)` (L320) is not this flake. Removing it is a separate change.

**Ledger inbox (Rule 17):** all nine are addressed here. DW-349 and DW-555 by Tasks 1-2 and AC1. DW-1448, DW-1458, DW-1452 and DW-1457 by Tasks 3-7 and AC2-AC3. DW-1451 by Task 8 and AC4. DW-1450 by Task 9 and AC5. DW-1464 by Tasks 10-12 and AC6. None is declined.

**Rule 5 note:** at least 10 iterations under load, before and after, is measurable as counts. The local rate may be about 0: on macOS, Docker networks live in the VM, so Chromium never sees an interface change (inference). So the loops record counts, and the deterministic repros carry the red. This is not an intent gap.

## Verification

**Arrangement** (lane A only; Rule 21):
- On every `ci/iris.sh` call: `LANE="OCUTALON_LOCK_DIR=<lock-dir>/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'"`, with run tag `e0fli` (implement), `e0flq` (QA) or `e0flr` (review), and warm tag `<tag>w`.
- At most one fresh throwaway plus one warm throwaway (`ci/warm.sh`) at a time.
- Never a dev slot for destructive or live units. The dev slot is `ocutalon-slot-a` (MCP profile `ocutalon-slot-a`), never another instance, never `ocutalon-aihub-test`.
- Any change under `ci/mock` makes warm runs refuse: run `ci/warm.sh down`, then `up`.
- One command per foreground call, with `timeout: 600000`. Never background a run, never raise the cap; split repeats into batches.
- Before the first browser unit, and after any merge: `(once) $LANE OCUTALON_RUN_TAG=e0fli ci/iris.sh build`.

**The repeat harness** (the DW-1388 pattern, scratch, never committed). `ci/iris.sh live` has no grep or repeat, so a shim at `<scratchpad>/e0fl/bin/npm` (mode 755) replaces only the unit's whole-project browser call:

```bash
#!/usr/bin/env bash
[ "$*" = "--prefix web run $E0FL_SCRIPT" ] || exec "$REAL_NPM" "$@"
burn=""; trap 'for p in $burn; do kill "$p" 2>/dev/null; done' EXIT
i=0; while [ "$i" -lt "${E0FL_BURN:-0}" ]; do i=$((i+1)); sh -c 'while :; do :; done' & burn="$burn $!"; done
"$REAL_NPM" --prefix web run "$E0FL_SCRIPT" -- "$E0FL_SPEC" --grep "$E0FL_GREP" --repeat-each "${E0FL_REPEAT:-1}"
```

- Call shape: `$LANE OCUTALON_RUN_TAG=e0fli REAL_NPM="$(command -v npm)" E0FL_SCRIPT=<script> E0FL_SPEC=<spec> E0FL_GREP='<ids>' E0FL_REPEAT=<N> E0FL_BURN="$(sysctl -n hw.ncpu)" PATH="<scratchpad>/e0fl/bin:$PATH" ci/iris.sh live <unit>`.
- Never pass `--part`.
- Record Playwright's passed and failed counts from the unit's e2e log. Record only counts; the log holds the throwaway's passwords.
- Load: one host burner per core, beside the unit's own stack. Record the load used.
- HC8 skips within 40 minutes of midnight UTC, so run its loop outside 23:20-00:40Z.

**Commands:**
- (once) `npm --prefix web run lint`: exit 0. `npm --prefix web test`: all pass. `bash docker/tests/test-mock.sh`: all pass.
- (once) Task 0 (a): `node <scratchpad>/e0fl/measure.mjs`. Record the error, `page.url()`, whether `waitForURL` resolved, and the interruption count out of 50.
- (loop) T2, before and after: script `e2e:demo-path`, spec `telegram-page.spec.ts`, grep `T2:`, N=10, unit `demo-path`, with `OCUTALON_AUDIT_POLL=0`. The unit's step summary and audit checks fail by construction under the shim and are not evidence.
- (loop) H7 and U12, before and after: script `e2e`, specs `history/history.spec.ts` and `usage/usage.spec.ts` (one call each, or both in one call), grep `H7:|H2:|H3:` or `U12:`, N=10, unit `sign-in`.
- (loop) Q7, HC8 and MC3, before and after: script `e2e:sign-in-3`, one call per spec, N=10, unit `sign-in-3`. Split HC8 into batches (150 s per-test bound).
- (loop) P4, before and after: script `e2e:floor`, spec `focus.spec.ts`, grep `P4:`, N=10, unit `floor`.
- (loop) Row 6, before and after:
  - A scratch wrapper repeats the S3-at-`cap_busy` / S5-at-`cap_free` pair 10 times in one `live online-demo` run, with a fresh proxied address each time, `drop_session` and `drop_counter` after each S5, and one `ROW6LOOP <i> s3=<ok> s5=<outcome>` line.
  - Run it with host burners in the same call and `OCUTALON_LIVE_DEADLINE=900`.
  - Revert the wrapper after.
- (loop) K1: `for i in $(seq 10); do node --test ci/mock/test/server.test.mjs; done`. Red 10 of 10 on the old mock with the new row, green 10 of 10 after.
- (once) Repros, old red and fixed green, each reverted byte for byte:
  - N1 (node);
  - the R1 bundle abort for T2, H7, Q7 and HC8 (`page.route('**/ocutalon/main-*.js', r => r.abort('connectionreset'), { times: 1 })` just before the reload under test; for T2, after `changeSnapshot`);
  - R2 (heartbeat GET 500 once);
  - M1 (the held body);
  - O1 (the hold);
  - K1.
  
  Record each as `mutation: <change> → <test> red / green`.
- (once) Fresh: `$LANE OCUTALON_RUN_TAG=e0fli ci/iris.sh class OcuTalon.Test.Contract.Mock`: PASS, with `TestMidnightReminderPicksItsPrompt` listed. With the tie-break removed: red, then reverted.
- (once, no shim): `live demo-path`, `live sign-in-3`, `live floor`, `live online-demo`, and `live sign-in --part k/2` for each part that holds `history.spec.ts` or `usage.spec.ts`: PASS. Record each unit's RETRIES count.
- (once) `git diff --name-only 37b55fb8fbbca21a0709feadfbff4207bfb628e3`: only the files of the Tasks, plus this spec and bookkeeping.
- (once, at the end, also after a failure) `$LANE OCUTALON_RUN_TAG=e0fli ci/iris.sh teardown`, and `ci/warm.sh down` if warm was used. Then remove `<scratchpad>/e0fl/bin/npm`, and confirm that no burner process or container is left.

**Shared surfaces:**
- `web/e2e/support/navigate.ts` `gotoSettled`: every sign-in and trace site, and the NAV line format.
- `web/e2e/support/floor.ts` `loadedAfter` / `reloadSettled`: every `loadedAfter` caller, and the RETRY step labels counted by `ci/iris.sh`.
- `memory-card.spec.ts` `answerOf` / `handled`: eight callers.
- `ci/mock/mock.mjs` `select()`: every mocked unit and every guide-prompt scenario under `B/`.
- `test-online-demo.sh` row 6.
- `Test.Contract.Mock`: the mock log it reads.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Mutations:** one per AC (AC1 to AC6), as listed with each AC. Record the result next to each here during implement.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
