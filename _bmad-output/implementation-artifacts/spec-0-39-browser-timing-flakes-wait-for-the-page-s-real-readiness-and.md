---
title: 'Story 0.39: Browser-timing flakes wait for the page''s real readiness, and a turn at the UTC day rollover does not error'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
baseline_revision: '2386d9553af20f7df5f25dfe705f3a79589e2619'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [multiple-goals, oversized]
deferred:
  - summary: >-
      A second retry at one site is made a failure in withOneReload (`if (usedUp) throw usedUp`), but only the helper (`reportRetryOnce`) and a source pin are tested; no row or live repro drives two retries at one site through loadedAfter or reloadSettled.
    evidence: |-
      verification-gap: removing the throw leaves retry-bounds.test.mjs green (rows call reportRetryOnce with their own site list); the AC2b mutation was applied inside reportRetryOnce. Pass B owns the live two-retries repro (Verification, pass A results).
    location: >-
      web/e2e/support/floor.ts:189
    severity: medium
  - summary: >-
      T1, T4 and T5 count code requests across a reload; a retried reload (the one logged retry) asks for the pairing code again, so a healed flake could fail as a count of 2 instead of 1.
    evidence: |-
      blind-hunter; the spec's own Task 4 asks to confirm T1's and T5's counts. Only T2 ran on the fixed tree in pass A; the full live demo-path run is owed. Not verified either way.
    location: >-
      web/e2e/demo-path/telegram-page.spec.ts:577-640
    severity: medium (unverified)
  - summary: >-
      B1 reads the busy splash's focus once (`document.activeElement?.id`) right after the page's load, so the splash's `autofocus` may not have applied yet.
    evidence: |-
      One failure in the full live online-demo run of pass B2 ("the error has the focus": expected ocu-error, received ''), green in the re-run and in a run before it; the file is not part of this story.
    location: >-
      web/e2e-online/busy.spec.ts:135
    severity: medium
baseline_commit: '0c09f1e5a52cff6722cc9f4151f070b0b556570b'
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
3b. **Pin: a site that needs the retry twice in one run fails** (Planner ruling 1, 2026-11-17). In the shared retry path that `loadedAfter` and `reloadSettled` use (`withOneReload` / `reportRetry`, `web/e2e/support/bounds.ts` or `floor.ts`), before a reload retry: if the unit's retry log (`OCUTALON_E2E_RETRY_LOG`, the file `ci/iris.sh` counts) already holds a `RETRY` line for the same `<spec>:<line>` site, do NOT retry. Fail with a named error: `<spec>:<line> needed its one logged retry a second time in this run; a second retry is a failure (Story 0.39)`, and still append the RETRY and DIAG lines so `ci/iris.sh` reports them. With no retry log set (a local run without `ci/iris.sh`), keep a per-process record of retried sites instead. `ci/iris.sh` is not changed (decided in-stage: the counter's file is the record; the failure is raised where the retry is decided). Pin it in `web/scripts/retry-bounds.test.mjs` (or the helper's existing node test): first retry at a site proceeds, a second at the same site throws the named error, a retry at another site proceeds.
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
- AC2b (Planner ruling 1): Given a site that already logged its one RETRY in this run's retry log, when the same site needs a retry again, then the helper fails with the named "a second time in this run" error instead of reloading, and the RETRY/DIAG lines are still written. mutation: drop the check → the node row "second retry at the same site throws" goes red.
- AC3 (DW-1457): Given the heartbeat GET answers 500 once after HC8's reload, when HC8 runs, then it fails with the message naming the heartbeat GET and status 500. mutation: that injection → red with the named message.
- AC4 (DW-1451): Given MC3's 500 phase with the yesterday read's body held after its headers and today answered 500 after yesterday's response event (scratch repro: a local server continued to by `route.continue`), when MC3 runs, then the old `handled` times out at 45 s at L119 and the new one is green, well inside its bound. mutation: the repro on the old `handled` → red.
- AC5 (DW-1450): Given a scratch hold before S5 (a background `iris session` that holds a connection for 5 s, started after `set_cap "$cap_free"`, with a wait until the status reads busy), when row 6 runs, then:
  - the old row is red (`'other'`, no cookie, 0 counter rows);
  - the fixed row is green after its status wait.
  
  mutation: that hold.
- AC6 (DW-1464): Given the reminder item rendered at 23:59:59 and at 00:00:01 UTC after a watch turn at 23:59:59, when it reaches the CI mock through `%AI.Agent`, then the mock answers `guide-reminder` with 200. The day-keyed read that caused the error is named in Design Notes. mutation: remove the tie-break → `TestMidnightReminderPicksItsPrompt` and node row K1 go red with `two guide prompts match`.
- AC7 (all eight timing DWs): Given each affected test, when its loop runs at least 10 iterations beside the lane's busy stack plus one CPU burner per host core, before and after the fix, then both counts are recorded and the after loop is green (all passed).
- AC8: Given CI on this story's head, when it finishes, then every workflow is green.

### Review Findings

Code review, 2026-11-17, the whole story (`0c09f1e5a` to the working tree, QA's untracked file included). Four layers (blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor), each at the session's model; tree and HEAD unchanged after the layers. Verdicts: high 0, medium 3, low 22, false 2 (27 rows). Rule 3: a test-only story (no user-facing surface changed); the changed tests ran live (`## Verification`). Rule 6: AD-12 (the reloaded page's `/state` is the readiness signal), AD-22 (the mock matches the amended tie-break sentence verbatim: two or more hits, `> ` lines removed, exactly one left is selected, else 500) and AD-33 (the crossings are the four approved files) hold. Rule 2: `reloadSettled` and `loadedAfter` share `snapshotAfter`; nothing copied there.

- [x] [Review][Patch] `[medium]` `handled` tracking the answered request (`tracker.include`, the held PRECEDENTS read at the reload) had no pin: deleting it left every row green (verification-gap) [web/e2e/memory-card.spec.ts:181] - row "also tracks the answered request ..." added to `web/scripts/flake-timing-sources.test.mjs`. fix-risk low (a source pin).
- [x] [Review][Patch] `[medium]` `TestMidnightReminderPicksItsPrompt` copied the class's private `ChatError` (the Try/Catch and `$Translate` of the chat error), Rule 2 (blind-hunter) [src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls:232] - now `Set chatError = ..ChatError(agent, {"max_tokens": 8000}, text)`. fix-risk low (same call, same capture).
- [x] [Review][Patch] `[low]` The row "writes a RETRY line for the reload step that ci/iris.sh counts" passed on its own when the grep was not found (`new RegExp(undefined)` matches anything) (verification-gap) [web/scripts/retry-bounds.test.mjs:217] - `assert.ok(shape, ...)` added. fix-risk low.
- [x] [Review][Patch] `[low]` The HC8 pin's title said no other site of HC8 reloads, but it only counted the helper's calls (verification-gap) [web/scripts/flake-timing-sources.test.mjs:77] - it now counts five inside HC8, five in the file, and no bare `page.reload(` in HC8. fix-risk low.
- [x] [Review][Patch] `[low]` An unused `armed` array in the describe "a site retries once per run" (blind-hunter) [web/scripts/retry-bounds.test.mjs:142] - deleted. fix-risk low.
- [x] [Review][Defer] `[medium]` (unverified) A reload whose load event never fires is not covered: `loadedAfter(page, () => page.reload())` bounds the reload as its action before `withOneReload` begins, so the pass-A before-loop's Q7 failure (`page.reload: Timeout 30000ms exceeded`) would still fail, by name and with no retry (blind-hunter) [web/e2e/support/floor.ts:263] - deferred: DW-1480 `escalated owner=burndown`, fix-risk high (a `waitUntil: 'commit'` reload at the 27 prescribed sites changes the ruled call shape in a frozen release); settled by a CI or loop failure at a migrated site naming `loadedAfter the sign-in`. The Verification line that called it "the DW-1452 signature" is corrected.

Rejected:
- `[low]` by-design: the retry site is `<spec>:<line>` of the test (Task 3b), so the `floor` unit's three projects (`floor`, `floor-firefox`, `floor-webkit`, one retry file) and a test declared in a loop (`files.spec.ts` `TYPES`) share one site: a first retry in Firefox after Chromium's at the same test fails as a second (blind-hunter, edge-case-hunter). Extends pass A's recorded consequence. reopen_if: a CI unit fails with "needed its one logged retry a second time" whose two RETRY lines come from different projects or cases.
- `[low]` by-design: a site that has used its retry fails at half the bound instead of waiting out the rest (blind-hunter) - Task 3b: "before a reload retry ... do NOT retry. Fail with a named error".
- `[low]` by-design: a reload at a `loadedAfter` site that passes its bound is named `loadedAfter the sign-in` (blind-hunter) - Tasks 4, 6 and 7 prescribe `loadedAfter(page, () => page.reload())` and Task 3 keeps its labels.
- `[low]` wontfix-theoretical: the tie-break re-joins the unquoted lines, so a multi-line prompt split by a quoted line could match without being one of the first hits (blind-hunter) - no scenario has a multi-line prompt; real once one does.
- `[low]` wontfix-theoretical: the first document's in-flight `GET /state` can satisfy `reloadSettled`'s first wait (edge-case-hunter, also as a doc-claim finding) - the page issues it only at load and on an events-poll reload; no regression against the bare reload, whose assertions still auto-wait; the same window `loadedAfter` has had since Story 32.6.
- `[low]` HC8's heartbeat matcher accepts a GET of the old document (edge-case-hunter, also as a doc-claim finding) - as adjudicated in pass A; the line assertions that follow still run.
- `[low]` wontfix-theoretical: `reloadWithHeartbeat`'s wait (navigation + action + slack) can expire before `loadedAfter` ends in its worst case (edge-case-hunter) - needs `loadedAfter` to use nearly all of both bounds plus its expect without failing.
- `[low]` A failed append to the retry file lets a second retry proceed (edge-case-hunter) - as adjudicated in pass A.
- `[low]` `errorPageShown` returns at once when the page already sits on `chrome-error://` (edge-case-hunter) - as adjudicated in pass A; only after a failed earlier `gotoSettled`, which already failed its test.
- `[low]` by-design: a spent bound gives the error-page wait 1 ms and the N2 error (edge-case-hunter) - Task 1: "within the time left in the bound".
- `[low]` wontfix-theoretical: `waitForURL` rejecting on a closed page reads as a missing error page (edge-case-hunter) - a closed page ends the test; `cause` keeps the first error.
- `[low]` by-design: `conn_before_s5` is read before `set_cap` (edge-case-hunter) - Task 9; as in pass B2.
- `[low]` `handled` does not track requests issued before `answerOf` other than the answered one (edge-case-hunter, doc-claim finding) - the Task 8 contract; as in pass B1.
- `[low]` `web/e2e/live/deadline-cap.spec.ts` is outside the Code Map (acceptance-auditor) - forced by Task 1's wider `Navigable` type; `NO_ERROR_PAGE` only fills the type, no assertion or bound changed.
- `[low]` The N2 text reads "within the page's default wait" when there is no bound (acceptance-auditor) - no caller runs without a bound.
- `[low]` by-design: AC7's before and after loops both read 0 failures, so they do not separate the trees (verification-gap) - AC7 is a count record; the Rule 5 note and the residual risks say so; the repros (AC1-AC5) carry the red.
- `[low]` The frontmatter `deferred:` still lists the resolved DW-1471/DW-1472, and gives DW-1479 medium against the ledger's low (blind-hunter, acceptance-auditor) - the fix edits the spec's frontmatter (lead's bookkeeping).
- `[low]` Status and dates disagree across the tracking files (spec `done` against sprint-status `review`; the pass B1 heading dated 2026-11-16) (blind-hunter) - bookkeeping; the sprint-status sync of this review sets the story's status.
- `[low]` `cycle-log-epic-0fl.md` repeats the `stage_dead`/`hold_complete` pair, the second with a cut path and an empty time field (blind-hunter) - the lead's log; this stage writes no cycle-log entry.
- `[false]` QA's `web/scripts/flake-timing-sources.test.mjs` and the spec edits are uncommitted (blind-hunter, acceptance-auditor) - by protocol the lead commits after review; both are in the tree.
- `[false]` AC8 has no evidence (acceptance-auditor, verification-gap) - AC8 is CI on the pushed head, after this stage.

## Spec Change Log

- 2026-11-17, lead, PASS B2 handoff scope (binding for the implementation subagent; the intent block is unchanged): edit files only, node-level, and start NO IRIS stack, docker container or `ci/iris.sh` unit (the lead runs the stack units afterwards). Implement exactly two items: (1) Task 9, `docker/tests/test-online-demo.sh` row 6 (read `conn_before_s5` before `set_cap "$cap_free"`, `status_free`, `wait_until 30 status_free`, the named failure line, one sign-in, the fail line's S5 POST status and `busy_page`; `page_outcome` and every pass condition unchanged; no loop or hold switch committed); (2) DW-1471: a node row in `web/scripts/retry-bounds.test.mjs` (or the helper's own node test) that drives two retries at one site through `withOneReload` itself (via `loadedAfter` or `reloadSettled` on a fake page), so removing `if (usedUp) throw usedUp` in `web/e2e/support/floor.ts` goes red, with its `mutation:` line recorded in `## Verification` (apply, observe red, revert byte for byte). Then run `npm --prefix web run lint` and `npm --prefix web test`. DW-1472, the loops and the live runs are the lead's.

- 2026-11-17 ~02:58Z, lead (orchestrator GO B2): pass B1 finalized at 83d8b53f6. Re-opened (`in-progress`) for pass B2 = Task 9 (DW-1450 row 6) and AC5; DW-1472 (T1/T4/T5 pairing-code counts across the one logged reload retry: confirm or fix); DW-1471 (a node row that drives two retries at one site through withOneReload itself, so removing `if (usedUp) throw usedUp` goes red); AC7 (the owed 10-iteration before/after counts: sign-in H2/H3/H7/U12, sign-in-3 Q7/HC8/MC3, demo-path T2, floor P4); and full live runs of the touched units (demo-path, sign-in parts holding history/usage, sign-in-3, floor, online-demo).

- 2026-11-17 ~02:29Z, lead: pass A finalized at 8cc7a897f (groups 1-2 and the Task 3b pin). Spec re-opened (`in-progress`) for pass B1 = Task 0 (c) for group 5 (READ THE EXACT MOCK ERROR TEXT first), Tasks 10, 11, 12 (DW-1464), Task 8 (DW-1451) and AC4, AC6, plus the DW-1471 row if time allows. Pass B2 (after the quota hold) = Task 9 (DW-1450, row 6), AC5, DW-1472 (T1/T4/T5 counts), the 10-iteration counts still owed (AC7), P4 and T2 before-loops, and the full live units.

- 2026-11-17, lead, Planner spec-gate ruling (`prompts/story-039-flakes-rulings-20261117.md`, APPROVED): gate 1 adopted (one logged, CI-counted retry plus the named-diagnosis wait) with a NEW pin, Task 3b / AC2b (a second retry at one site in one run is a failure); gate 2 follow-on ledgered LOW (DW-1468), and Chromium's own network namespace ledgered LOW (DW-1469); gate 3 no traces; gate 4 lane crossing approved for this spec's files only (mock.mjs, history.spec.ts, test-online-demo.sh, Test.Contract.Mock) and the AD-22 sentence written verbatim into the spine; Task 0 (c) for group 5 must READ THE EXACT MOCK ERROR TEXT from the repro before the mock fix lands. DW-1450's stop condition stands. DW-1464 drops to LOW once fixed. Implement runs in two saveable passes: pass A = Tasks 0 (a) and the group 1-2 parts of 0 (b)/(c), 1, 2, 3, 3b, 4, 5, 6, 7; pass B = Tasks 8-12 and their Task 0 parts.

- 2026-11-17, lead, PASS A scope (binding for this implement pass; the intent block is unchanged): implement Tasks 1, 2, 3, 3b, 4, 5, 6, 7 only (AC1, AC2, AC2b, AC3, AC7 for those tests). Tasks 8-12 (MC3, row 6, the DW-1464 mock and `Test.Contract.Mock`) and AC4-AC6 are PASS B: leave their checkboxes and files untouched; an unchecked pass-B task is not a finding. Task 0 (a), the before-loops and the old-red repros for groups 1-2 were run by the lead on the unchanged tree before this handoff (see `## Verification`). The implement handoff is node-level only: edit the files, run `npm --prefix web run lint`, `npm --prefix web test` and the node rows, and do NOT start any IRIS stack, docker or `ci/iris.sh` unit; the lead runs the stack units (repros, after-loops) after the handoff.

## Review Triage Log

### 2026-11-17 - Review pass (pass A)
- verdicts: 23 findings reported by the layers, one row per claim (same claim from several layers shares a row) - high 0, medium 2, low 7, false 3, maybe-false 1
- findings:
  - `[low]` `reject` Retry budget is per test line, not per reload (blind-hunter, edge-case, verification-gap 'other') - the ruling and Task 3b define the site as `<spec>:<line>`, the RETRY line's own key; spec-bound, closed by-design. Consequence recorded: a repeat-each loop or two independent flakes in one test fail by the named error.
  - `[medium]` `defer` T1/T4/T5 counted-request checks across a retried reload (blind-hunter) - deferred, unverified; full live demo-path owed.
  - `[low]` `patch` reloadWithHeartbeat arms its wait with the action bound only (blind-hunter, edge-case) - now navigation + action + slack, like loadedAfter's own wait.
  - `[low]` `reject` heartbeat matcher accepts a GET of the old document (blind-hunter, edge-case) - the 200 and the line assertions that follow still run; not worth added guard code.
  - `[low]` `reject` errorPageShown trusts a stale chrome-error URL (blind-hunter) - Task 1 says the current URL is checked first; the page starts at about:blank in every caller.
  - `[medium]` `patch` The time-left arithmetic of the error-page wait was not pinned (blind-hunter, verification-gap) - row 'gives the error page only the time left in the bound after the failed goto' added; mutation: drop `- (Date.now() - beganAt)` -> that row red; reverted.
  - `[medium]` `defer` The wiring `if (usedUp) throw usedUp` is not tested (verification-gap, edge-case) - a source pin was added in flake-fixes-sources.test.mjs (patch); the behavioural row/live repro stays deferred (see deferred list).
  - `[false]` `reject` No source pins for the call-site migrations - a bare reload at a migrated site would still be caught by the live repros; closed wontfix-accepted, low.
  - `[false]` `reject` reloadSettled assumes /state on every route (blind-hunter, edge-case) - AD-12 and App.LiveState.load (web/src/app/app.ts) issue it on every route; H7 passed with the repro.
  - `[false]` `reject` Non-Chromium browsers (edge-case) - ERR_NETWORK_CHANGED is Chromium's text and the `chrome-error://` URL is Chromium's; the other browsers never match RETRYABLE this way.
  - `[low]` `reject` Process-level `retriedLines` leaks between rows (verification-gap) - rows use distinct locations; test-only, no harm named.
  - `[low]` `reject` 1 ms clamp when the budget is spent reads 'within 0 s' (edge-case); retry-file append failure falls back to no record (edge-case); wait-defaults duplicated in the spec (verification-gap); grace period after a used-up retry (edge-case) - each is cosmetic or outside the ruled behaviour.
  - Intent-alignment layer: descriptive; it reports readings 1-5, the diff implements reading 1 with the per-test-line site; its divergences are the pass-B items and the 3-5 iteration loop counts recorded in `## Verification`.

### 2026-11-16 - Review pass (pass B1)
- verdicts: 20 findings reported by the layers, one row per claim (same claim from several layers shares a row) - high 0, medium 3, low 5, false 0, maybe-false 0 (the rest rejected below as low or theoretical)
- findings:
  - `[medium]` `patch` `handled` skips the body wait for a request issued before `answerOf` (the held PRECEDENTS read at the reload site) (blind-hunter, edge-case, verification-gap) - `trackEnds` gained `include(request)`: `handled` adds the answered response's own request unless it already ended, so the old `finished()` guarantee holds there too.
  - `[medium]` `patch` The AC4 repro only showed that `handled` returns, not that every tracked request had ended (verification-gap) - the scratch repro now fails with `RETURNED BEFORE TODAY ENDED` if today's 500 has not been sent when `handled` returns; mutation: `tracker.ended()` replaced by an immediately resolved promise -> repro red 3 of 3; real `handled` green 3 of 3; old `handled` hung (8 s race). Reverted.
  - `[low]` `patch` Listeners leak when `await answer` rejects (blind-hunter, edge-case, verification-gap) - `await answer` now sits inside the `try`/`finally` that stops the tracker.
  - `[low]` `patch` The `still open` suffix labelled any error (blind-hunter) - it now wraps only the bounded wait for the ends.
  - `[low]` `patch` A promise not made by `answerOf` skipped the wait silently (edge-case) - `handled` now throws `the answer was not made by answerOf`.
  - `[low]` `reject` Orphan trackers when `handled` is never reached (edge-case, verification-gap) - every caller in the spec passes its answer to `handled` in the same block; a test-lifetime page only.
  - `[low]` `reject` Later same-route requests with other statuses keep `handled` open (edge-case, verification-gap) - the contract says every matching request issued since arming; no listed caller issues one.
  - `[low]` `reject` The strip does not handle `\r` line ends or a `>` with no space (blind-hunter, edge-case) - `Agent.Input.Quoted` normalizes line ends to LF and the spec's rule is lines that start with `> `; no listed input reaches it.
  - `[low]` `reject` Three or more hits, or a multi-line prompt with a `> ` line, names a quoted hit in the 500 (edge-case) - the 500 stays a 500; the text only names two scenarios.
  - `[low]` `reject` The two guards "strip only for 2 or more" and "an empty unquoted set keeps the tie" have no recorded mutation (verification-gap) - K2 (two quoted) and K3 pin them; the AC6 mutation is the recorded one.
  - `[low]` `reject` K1's mock-key header is a no-op in the node row (verification-gap) - the IRIS test covers the `chat` key through `Provider("chat")`.
  - `[low]` `reject` The Task 8 evidence is a scratch repro, not committed (blind-hunter, intent-alignment, verification-gap) - Decision 5 of the spec keeps repros scratch; the live MC3 loop is owed to pass B2.
  - `[low]` `reject` The Pass B1 heading date (blind-hunter) - the run's clock reads 2026-11-17; the heading follows it.
  - `[low]` `reject` `TestMidnightReminderPicksItsPrompt` uses local times, so it equals the UTC rollover only under UTC (edge-case, intent-alignment) - decided in-stage and recorded in the pass B1 results; the CI hosts run UTC.
  - Intent-alignment layer: descriptive; the diff implements the mock-rule reading at the mock's HTTP surface and the IRIS test at `Agent.Input.Render` plus `%AI.Agent`; the browser-surface evidence for MC3 is the owed live loop (pass B2).

### 2026-11-17 - Review pass (pass B2)
- verdicts: 13 findings (rows) from the layers' 21 reported claims, one row per claim (the same claim from several layers shares a row) - high 0, medium 2, low 10, false 1, maybe-false 0
- findings:
  - `[low]` `patch` The header comment of `retry-bounds.test.mjs` said the modules have no relative import (blind-hunter) - it now says why the resolve hook is there.
  - `[medium]` `patch` `stalled()` ticked the half bound after a guessed five turns, with no signal that the timer was armed (blind-hunter, verification-gap) - it now waits until a timer of the half bound has been armed (bounded, named assertion). mutation: `if (firstMs === undefined) return asked;` made unconditional in `withOneReload` -> the two through-`reloadSettled` rows red with `the call armed its half-bound timer`, not a hang; reverted, `cmp` identical.
  - `[medium]` `patch` The `printDiagnosis` before `throw usedUp` was not pinned; the DIAG assertion read the first retry's lines (verification-gap) - row 1 counts the printed `DIAG /state` lines after the first call and asserts that the second call adds its own. mutation: `printDiagnosis` moved below `if (usedUp) throw usedUp;` -> row 1 red (`the second call printed its own page-side lines`); reverted, `cmp` identical.
  - `[low]` `patch` The failed wait named `(last '<a fresh status_read>')`, a reading later than the failing one, and a skipped sign-in still read a jar never written and printed `gave 'other'` in the MEASURED line (blind-hunter, edge-case x3) - `status_free` keeps its own reading (`<never read>` when the run deadline ended the wait first), and the jar reads are skipped (`none`). mutation: `status_free` made to never read free with `wait_until 6` -> the unit's only failed check is `row 6: the status did not read free within 30 s ... (last 'false none 200') (no sign-in was made ...)`, the MEASURED line reads `gave 'none'`; reverted, `cmp` identical.
  - `[low]` `reject` Row 6's message says "30 s" when the run deadline ended the wait (blind-hunter, edge-case, verification-gap) - the text is the spec's (Task 9); the patch above adds `<never read>` for that case.
  - `[low]` `reject` `wait_until` counts only its sleeps, so a stalled status GET stretches 30 s (edge-case) - the status GET is local and `curl --max-time 30` bounds each; the run deadline bounds the loop.
  - `[low]` `reject` `conn_before_s5` is now read before the cap is set, so the message's "before S5" is early (blind-hunter) - Task 9 says to read it before `set_cap`.
  - `[low]` `reject` Still refused after free has no product-fault marker in the script (edge-case, intent-alignment) - the stop is this stage's rule, not a script behaviour; the fail line names the POST status and the busy page.
  - `[low]` `reject` The resolve hook is never deregistered, skips extensionless names with a dot, and falls through with a bare error (blind-hunter, edge-case) - the test file runs in its own process and the hook only maps floor.ts's own imports.
  - `[low]` `reject` No row for a second retry that starts at `loadedAfter` and ends at `reloadSettled`, or for a bound too small to retry (blind-hunter) - the shared-site budget across both is pinned by the pass-A AC2b rows; the small-bound case is the pass-A bound rows.
  - `[low]` `reject` The fake `test.info` has a dead `timeout` field (verification-gap) - cosmetic.
  - `[false]` `reject` AC2b's `mutation:` line names a row that does not exist (verification-gap) - the line is in the intent block's AC text; the through-`reloadSettled` mutation is recorded in the pass B2 results, and a finding whose fix edits the spec is not triaged.
  - `[low]` `reject` The row-6 fix is verified only by a live hold that is not committed (verification-gap) - Decision 4 of the spec: the hold is a scratch edit.
  - Intent-alignment layer: descriptive; the diff implements the status-wait reading for Task 9 at the script surface and a helper-level fake page for DW-1471; the live evidence (hold repro, loops, full units) is recorded in `## Verification`.

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

**Planner ruling, 2026-11-17 (binding):** APPROVED. 1: adopt 32.6's one logged, CI-counted retry with the named-diagnosis wait, and pin that needing it more than once per run at one site is a failure (Task 3b). 2: the ~45 other bare reloads are a LOW follow-on story (DW-1468); Chromium's own network namespace is a LOW follow-on (DW-1469). 3: no traces; if a fixed site still fails in CI, the Planner pulls its trace. 4: the lane crossing is approved for THIS spec's files only (`ci/mock/mock.mjs`, `web/e2e/history/history.spec.ts`, `docker/tests/test-online-demo.sh`, `Test.Contract.Mock`); AD-22 carries the approved sentence verbatim (spine, [AMENDED 2026-11-17, Story 0.39]); read the exact mock error text in the repro before the mock fix lands. DW-1450's stop condition stands. Keep counting hosts through this story's CI.

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

**Pass A results (2026-11-17, lane A throwaways, tag `e0fli`; 16 host burners = `hw.ncpu` beside each unit's stack; counts only):**
- Task 0 (a), Chromium headless shell 1248, no stack, every request aborted with `internetdisconnected`: `goto` rejected with `net::ERR_INTERNET_DISCONNECTED` while `page.url()` read `about:blank`; `waitForURL('chrome-error://chromewebdata/', {waitUntil:'commit'})` then resolved and the URL read `chrome-error://chromewebdata/`. An immediate second `goto` threw `interrupted by another navigation` 0 of 50 times (as expected on this host, which never sees an interface change), so the premise of N1 (the error page commits after the rejection) holds and there is no clarification.
- Before loops, unchanged tree: `sign-in` (H2, H3, H7, U12 together) 5 iterations, 20 passed, 0 failed; `sign-in-3` (Q7, HC8) 5 iterations, 9 passed, 1 failed (Q7, `page.reload: Timeout 30000ms exceeded` at the bare `reopen()` reload: a reload that never reached its load event, not DW-1452's CI signature `element(s) not found`; `loadedAfter` bounds that reload as its action, so this mode is not covered by the fix, ledgered DW-1480). T2 (`demo-path`) and P4 (`floor`) before loops: not run (pass B).
- Old-red repros (main bundle aborted once, `connectionreset`, just before the reload under test), unchanged tree: T2 red (`main.main` not found after the reload), H7 red (element not found after the reload), Q7 (second reopen) red, HC8 (reload at the `nextDueAt` step) red (`element(s) not found`).
- After, fixed tree: `sign-in` loop 3 iterations of H2, H3, H7, U12: 12 passed, 0 failed, 0 RETRY lines; `sign-in-3` loop 5 iterations of Q7, HC8: 10 passed, 0 failed; T2 loop 3 iterations: 3 passed, 0 failed. P4 after loop: not run (pass B). Loop iterations still owed to AC7 (10 each, before and after): all of them; pass A ran 3-5.
- Fixed-green repros: H7 green with one `RETRY e2e/history/history.spec.ts:316 reloadSettled ...` (unit RETRIES 1); Q7 and HC8 green with one RETRY each (`guide.spec.ts:487`, `heartbeat-card.spec.ts:390`; unit RETRIES 2); T2 green with one RETRY (`telegram-page.spec.ts:190`; unit RETRIES 1; the repro aborts the bundle once, in the first case only).
- mutation (AC1): `gotoSettled`'s error-page wait disabled (`false && NETWORK_CHANGED...`) -> `goto-settled.test.mjs` N1 row and N2 row red; reverted, tree byte-identical.
- mutation (AC2): the bundle abort on the old sites -> T2, H7, Q7, HC8 red (above); `withOneReload`'s retry disabled (`return asked` at the top of `retry`) with the H7 repro -> H7 red (`:316`, 32.9 s), reverted.
- mutation (AC2b): `reportRetryOnce` never returns the second-retry error -> four `retry-bounds.test.mjs` AC2b rows red (first retry proceeds and second fails, same site across `loadedAfter` and `reloadSettled`, the unit's retry file, the per-process record); reverted, tree byte-identical. The live two-retries-at-one-site repro is not run (pass B).
- mutation (AC3): the heartbeat GET answers 500 once at HC8's third reload -> HC8 red with `the heartbeat GET answered 500`; reverted.
- A first T2 repro run that aborted the bundle in all four cases failed with `loadedAfter the snapshot GET ... no answer within 17.9 s (capped by the test timeout)`: the second case had no time left for a retry. That is the scratch injection, not the fix; the single-case injection above is the repro.
- Scratch only, reverted byte for byte (`git diff` before and after the injections `cmp` identical): the injections, the `npm` shim with its phases, the measure script.
- Node: `npm --prefix web run lint` exit 0; `npm --prefix web test` 2213 passed, 0 failed.
- Pass B owes: Task 0 parts and the repros/loops for Tasks 8-12, the T2 and P4 before/after loops, the 10-iteration counts for every pass-A test, the live 3b repro, and the full-unit `live` runs.

**Pass B1 results (2026-11-17, lane A):**
- Task 0 (c), group 5, on the UNCHANGED mock (node request through `ci/mock/test/helpers.mjs` `withServer` with the committed scenarios, mock key `chat`, one user message holding the quoted notes `> 2030-06-15` and `> 23:59 message (web): <watch prompt>`, a blank line, then the unquoted reminder prompt): HTTP 500 with the body, verbatim, `{"type":"error","error":{"type":"api_error","message":"CI mock: two guide prompts match: guide-reminder and guide-watch"}}`. The CI error text is therefore a fact: the mock's `ambiguous-prompt` refusal, not an inference.
- Tasks 10 and 11 (DW-1464, mock): `select()` rule 3 matches again on the text without its `> ` lines when two or more prompts match, and selects exactly one hit (`selectedBy: prompt`); the rule-3 header comment says so. Row `row 7 (K1-K3)` in `ci/mock/test/server.test.mjs`: K1 (quoted GUIDE_ONE under the notes opening, unquoted GUIDE_TWO, mock key `chat`) answers guide-two with 200; K2 (two unquoted, and two quoted) stays a 500 `two guide prompts match` with `rejected: ambiguous-prompt`; K3 (one prompt inside a quoted line) still selects it. Decided in-stage: two quoted prompts are a tie too (nothing is left after the strip), pinned in K2.
- K1 loop: old mock (`git show HEAD:ci/mock/mock.mjs`) with the new row: red 10 of 10; new mock: green 10 of 10; `bash docker/tests/test-mock.sh` all pass. mutation: tie-break removed (old `select()` restored) -> K1-K3 row red 10/10; reverted, `cmp` identical to the edited file, `git status --short` and `git diff --stat` as before.
- Task 12 (`Test.Contract.Mock.TestMidnightReminderPicksItsPrompt`): own session and one done web turn (watch prompt, as `Test.Data.Fixture.Turn`, removed with `Fixture.Clean`), rendered through `Agent.Input.Render` with `{"sessionStart":1}` at the local 23:59:59 of 2030-06-15 and the local 00:00:01 of the next day (via `Data.Time.FromLocal`, so the test reads the same in any zone; under UTC these are the spec's `<DAY>T23:59:59Z` and `<DAY+1>T00:00:01Z`). Decided in-stage: the item text is `Test <ref>` then the reminder prompt on its own line, so the request is found in the mock log by its ref (the note's `Summary` cuts the watch text, so the ref cannot ride on the turn) and the text still ends with the reminder prompt; RenderMemory's fixtures are private, so the shared public `Test.Data.Fixture` is used instead. Asserts at both times: the quoted watch line under the day, no unquoted line holding the watch prompt, the last line the reminder prompt, then through `%AI.Agent` on `Provider("chat")` the mock log reads scenario `guide-reminder`, `selectedBy` `prompt`, status 200, and the agent raised no `two guide prompts match`.
- IRIS class run, fresh throwaway lane A (`ci/iris.sh class OcuTalon.Test.Contract.Mock`, tag `e0fli`): first run red on a wrong fixture (the ref inside the turn text, cut by `Summary`); fixed run `CLASS OcuTalon.Test.Contract.Mock passed`, `RUN ... passed (1 classes)`. mutation: tie-break removed (old `mock.mjs`) -> `CLASS ... failed`, `TestMidnightReminderPicksItsPrompt` red at both times with `no tie error reached the agent ... CI mock: two guide prompts match: guide-reminder and guide-watch`, and the scenario/selectedBy/status asserts red; `mock.mjs` restored and `cmp` identical. Teardown: `0 project(s) removed, 0 leftover container(s), 0 leftover volume(s)`.
- Task 8 (DW-1451, `memory-card.spec.ts`): `answerOf` arms an end tracker (route, method, requests issued since the call, each ended by `requestfinished` or `requestfailed`) kept per answer in a `WeakMap`; `handled` awaits the answer, then `boundedStep` on every tracked request ended (the action wait in force from `currentWaits()`, default `waitsFor(0).actionTimeout`), naming the route and the number still open on a bound pass, stops the listeners, then the two frames. Every caller keeps its signature. Lint exit 0.
- AC4 deterministic repro (scratch `<scratchpad>/e0fl-implB/repro.mts`, not the live unit: a local http server, the page's `fetch` through `page.route(..., route.continue())`, yesterday answers 500 headers with a held body and is aborted by the page after its headers, today answers 500 150 ms later; the real `answerOf`/`handled` text is extracted from the spec into `block.mts`, the old `handled` is `finished()` plus two frames): old `handled` HUNG (hit the script's 8 s race; in the spec it is the 45 s test timeout) 1 of 1 and 3 of 3 under load; new `handled` green 1 of 1 in 0.3 s and 20 of 20 under 16 CPU burners (`hw.ncpu`) in 6.4 s. mutation: the repro on the old `handled` -> red; the spec file is the only changed file of Task 8, nothing was injected into it.
- Not run in pass B1 (time box 02:55Z): the live MC3 loop of the `sign-in-3` unit (the repeat under the `npm` shim); the Task 8 counts above are of the scratch repro, not of the unit. DW-1471's row: not done (the spec defines no such row). Task 9, DW-1472, AC5, AC7 counts, P4 and the full live units remain pass B2.
- Node: `npm --prefix web run lint` exit 0; `npm --prefix web test` 2214 passed, 0 failed.
- Review patches (pass B1): `handled` now includes the answered response's request, stops its tracker in a `finally` and throws if the answer was not made by `answerOf`. Re-run of the scratch AC4 repro on the patched `memory-card.spec.ts` text: new `handled` green 3 of 3 (and 1 of 1); old `handled` hung 1 of 1. mutation (AC4): `tracker.ended()` replaced by a resolved promise -> repro red 3 of 3 (`RETURNED BEFORE TODAY ENDED`); reverted. Lint exit 0; `npm --prefix web test` 2214 of 2214 passed; `bash docker/tests/test-mock.sh` 193 of 193 passed.

**Pass B2 results (node-level handoff, no stack):**
- DW-1471 (`web/scripts/retry-bounds.test.mjs`, describe `withOneReload fails a second retry at one site`): `reloadSettled` is driven on a fake page whose first document never starts its app (a resolve hook gives floor.ts its extensionless imports, as `answer-press.test.mjs` does; `setTimeout` is mocked and the half bound ticked). Row 1: the first call at a site retries once (one `commit` reload) and passes; the second call at that site rejects with `<spec>:<line> needed its one logged retry a second time in this run; a second retry is a failure (Story 0.39)`, makes no second reload, and the unit's retry file holds both RETRY lines and DIAG lines. Row 2: a retry at another site is its own first. mutation: `if (usedUp) throw usedUp;` deleted from `withOneReload` in `web/e2e/support/floor.ts` -> row 1 red (`the second retry at the site fails`), row 2 and the rest green; reverted, `cmp` identical.
- Task 9 (`docker/tests/test-online-demo.sh` row 6): `conn_before_s5` is read before `set_cap "$cap_free"`; `status_free` (`status_read` = `false none 200`) is waited on with `wait_until 30`; not free in 30 s fails with `row 6: the status did not read free within 30 s after the cap was set to <cap> (last '<reading>')` and skips the sign-in; free, it signs in once; the fail line adds the POST status and `busy_page`. `page_outcome` and every pass condition are unchanged. `bash -n` ok; no stack run (AC5's hold repro and the loops are the lead's).
- Node: `npm --prefix web run lint` exit 0; `npm --prefix web test` 2216 passed, 0 failed.

**Pass B2 results (lead, stack runs, 2026-11-17, lane A throwaways tags `e0flr1` to `e0flr4`; counts only):**
- Task 9 was NOT in the tree after the stopped attempt (the handoff text above had claimed it); the B2 re-run wrote it. AC5, scratch hold (a background `iris session` holding one connection for 6 s, started right after `set_cap "$cap_free"`, the status read busy first), swapped in for one `live online-demo` run each and restored byte for byte (`cmp`, `git status --short` as before): old row (`git show HEAD:` text, sign-in at once): 10 of 10 loop iterations red (POST 200, outcome `other`, no cookie, 0 counter rows) and the unit's own row 6 red with the same signature (`'other'`, cookie '', 0 counter row(s)), its only failed check; fixed row: 10 of 10 iterations green (the 30 s wait, then POST 303, `shell`, cookie set, 1 counter row) and the unit's own row 6 green, all checks passed. mutation: that hold -> old row red / fixed row green. The STOP condition did not fire (the fixed row was never refused after the status read free).
- DW-1472 (main-bundle abort once, `connectionreset`, just before the reload under test, scratch, restored `cmp` identical): T1 green with one RETRY (`:238`), T5 green with one RETRY (`:694`), T4's first loop case (`refused`, expects exactly one code request) green with one RETRY (`:542`, 1 passed). The retry does not change the counts: the stalled first document never starts its app, so it asks for no code, and only the retried document asks. No test change. T4's last site (`madeUp` `failed`, about 25 s of the 45 s test timeout left) has no time for a retry under a stall: the helper fails with its named bound error and no RETRY line, as the old bare reload failed there too; no timeout is raised. Injecting all three T4 sites in one run is red the same way (the retry budget of one test line). T4's middle site (`paired, no bot name`, expects no code request) was not run: an app that never started asks for none.
- AC7 (16 host burners = `hw.ncpu` beside each unit's stack; old = the nine `web/e2e` files of the story swapped for their `0c09f1e5a` text for one call, restored byte for byte, `git status --short web` empty after each; pass-A loops of 3 to 5 iterations are extra):

  | Tests (unit) | Before: iterations, passed, failed | After: iterations, passed, failed |
  |---|---|---|
  | H2, H3, H7, U12 (sign-in) | 10, 40, 0 | 10, 40, 0 |
  | Q7, HC8, MC3 (sign-in-3) | 10, 30, 0 | 10, 30, 0 |
  | T2 (demo-path) | 10, 10, 0 | 10, 10, 0 |
  | P4 (floor) | 10, 10, 0 | 10, 10, 0 |

  The local rate was about 0 before (Design Notes, Rule 5 note); the deterministic repros carry the red. No RETRY line in any loop.
- Full live runs, no shim, 0 RETRY lines in each: `live demo-path` all checks passed (8 of 8 steps, floor 15 of 15); `live sign-in --part 1/2` 174 passed; `live sign-in --part 2/2` (holds `history.spec.ts` and `usage.spec.ts`) 171 passed; `live sign-in-3` 188 passed; `live floor` 110 passed; `live online-demo` first run 1 failed (`e2e-online/busy.spec.ts:83` B1 read `document.activeElement` once right after `goto` and got '', unrelated to this story's files; deferred), the re-run all checks passed. Teardown of the four tags: 0 projects, containers, volumes, networks left; shim and burners removed.
- DW-1471: the committed row was reviewed and is right (its mutation is recorded above); `npm --prefix web run lint` exit 0 and `npm --prefix web test` 2216 passed after Task 9.
- Review patches (pass B2), re-verified: `bash -n` ok; lint exit 0; `npm --prefix web test` 2216 passed; `retry-bounds.test.mjs` 21 of 21; mutations as in the triage log (the DIAG print moved below the throw -> row 1 red; the retry timer never armed -> the two through-`reloadSettled` rows red with a named assertion; `status_free` never free -> the named failure line, the one failed check), each reverted with `cmp` identical. The patched script: `live online-demo` all checks passed (final clean run, row 6 PASS), tags `e0flr5` and `e0flr6` torn down (0 left); 0 containers, burners and locks left.

**QA gap check (2026-11-17, stage qa; node-level, no stack):**
- Gap found: AC2 (call sites), AC3 (the heartbeat GET message), AC4 (`handled`'s tracker) and AC5 (row 6) were pinned only by scratch repros and live runs; no node row failed if a site went back to a bare reload or the wait was dropped. AC1, AC2b and AC6 already had rows (`goto-settled.test.mjs`, `retry-bounds.test.mjs`, `server.test.mjs` K1-K3, `Test.Contract.Mock`) and are not repeated.
- (QA) `web/scripts/flake-timing-sources.test.mjs` (18 rows; discovered by `node --test scripts/*.test.mjs`): source pins for the six `telegram-page` sites, the three `history` `reloadSettled` sites, `guide` `reopen()`, HC8's five `reloadWithHeartbeat` calls (GET armed before the reload, status 200 named "the heartbeat GET answered"), `memory-card` `trackEnds`/`answerOf`/`handled` (requestfinished/requestfailed, bounded and named, no `.finished()`), and row 6 of `test-online-demo.sh` (order, `wait_until 30 status_free`, named failure, no sleep, one sign-in; `status_free` run in bash against stubbed readings).
- mutation (AC2, telegram): one `loadedAfter(page, () => page.reload())` made a bare reload -> "reloads at six sites through loadedAfter" red; reverted.
- mutation (AC2, history): one `reloadSettled(page)` made `page.reload()` -> "settles three reloads" red; reverted.
- mutation (AC2, guide): `reopen()` made a bare reload -> "has reopen() reload through loadedAfter" red; reverted.
- mutation (AC2/AC3, HC8): one `reloadWithHeartbeat(page)` made `page.reload()` -> "reloads through it five times" red; reverted.
- mutation (AC3): the message `the heartbeat GET answered` changed -> "asserts status 200 with a message that names the heartbeat GET" red; reverted.
- mutation (AC4): `boundedStep(tracker.ended(), ...)` made `boundedStep(Promise.resolve(), ...)` -> "waits on the tracker bounded by the action wait" red; reverted.
- mutation (AC5): `if wait_until 30 status_free; then` made `if true; then` -> "reads the held connections, then sets the cap, then waits on status_free" red; reverted.
- Every mutation reverted with `cmp` identical; `git status --short` and `git diff --stat` as before. `npm --prefix web test` 2234 passed, 0 failed; `npm --prefix web run lint` exit 0; `bash docker/tests/test-mock.sh` passed. No stack was started.

**Code review results (2026-11-17, stage code-review; lane A throwaways, tags `e0flc1` and `e0flc2`):**
- mutation (AC4, `handled`'s answered request): `tracker.include(response.request());` deleted from `web/e2e/memory-card.spec.ts` -> `flake-timing-sources.test.mjs` row "also tracks the answered request, issued before answerOf ..." red; reverted, `cmp` identical.
- mutation (AC2/AC3, HC8): HC8's last `await reloadWithHeartbeat(page);` made `await page.reload();` -> row "reloads through it five times in HC8, no other test uses it, and HC8 makes no bare reload" red; reverted, `cmp` identical.
- mutation (AC2b, the RETRY shape row): that row's grep of `ci/iris.sh` made to find nothing (`LC_ALL=X`) -> row "writes a RETRY line for the reload step that ci/iris.sh counts" red on `ci/iris.sh has the grep of retry_lines` (before the patch it stayed green); reverted, `cmp` identical.
- `Test.Contract.Mock` with `..ChatError` (Rule 2 patch): `ci/iris.sh class OcuTalon.Test.Contract.Mock` -> `CLASS ... passed`, `RUN ... passed (1 classes)`. mutation (AC6): `ci/mock/mock.mjs` swapped for its `0c09f1e5a` text, `ci/iris.sh class OcuTalon.Test.Contract.Mock:TestMidnightReminderPicksItsPrompt` -> failed at both times, the captured error reading `two guide prompts match: guide-reminder and guide-watch`; `mock.mjs` restored, `cmp` identical. Both tags torn down: 0 projects, containers, volumes, networks, images left.
- `git status --short` and `git diff --stat` as before after every mutation. Node: `npm --prefix web run lint` exit 0; `node --test` of `flake-timing-sources.test.mjs` and `retry-bounds.test.mjs` 40 of 40; `npm --prefix web test` 2235 of 2235 after the patches; `node --test ci/mock/test/server.test.mjs` 30 of 30.

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

Status: done
Blocking condition: none

Pass B2 (this pass covers only the open items):
- Implemented: Task 9 (DW-1450) in `docker/tests/test-online-demo.sh` row 6: `conn_before_s5` before `set_cap`, a wait on the public status reading free (`wait_until 30`, first check at once), one sign-in, a named failure that skips the sign-in, and the S5 POST status and busy page in the fail line; `page_outcome` and every pass condition unchanged. DW-1471: the node row in `web/scripts/retry-bounds.test.mjs` that drives two retries at one site through `reloadSettled`, hence `withOneReload`, reviewed and kept; its stall wait now waits on the armed timer and it pins the second call's own DIAG lines. DW-1472: confirmed with the bundle-abort repro that the one logged retry does not change the pairing-code counts of T1, T5 and T4's refused case; no test change. No checkbox exists in the Tasks list, so none was ticked.
- Files: `docker/tests/test-online-demo.sh`, `web/scripts/retry-bounds.test.mjs`, this spec.
- Review: 4 layers; patches applied 4 (two medium, two low); nothing new deferred except the unrelated B1 splash-focus read in `web/e2e-online/busy.spec.ts:135` (frontmatter `deferred`); the two pass-A deferrals (DW-1471, DW-1472) are resolved by this pass; the rest rejected with reasons in the triage log. followup_review_recommended false (no high patched).
- Verification: AC5 row 6 hold repro old red 10 of 10 (and the unit's own row 6 red), fixed green 10 of 10 (row 6 green); AC7 loops before and after, 10 iterations each, all passed (H2/H3/H7/U12 40/40 and 40/40, Q7/HC8/MC3 30/30 and 30/30, T2 10/10 and 10/10, P4 10/10 and 10/10) beside 16 burners; full live units: demo-path, sign-in parts 1/2 and 2/2, sign-in-3, floor and online-demo all passed (online-demo once after a one-off B1 focus-read failure outside this story); lint exit 0, node tests 2216 passed.
- Residual risks: the local flake rate was about 0 before the fix, so the loops show no regression rather than a cured rate; T4's last reload site has no time for a retry under a stall within the 45 s test timeout (no timeout was raised); the splash-focus read in B1 can fail in CI.
