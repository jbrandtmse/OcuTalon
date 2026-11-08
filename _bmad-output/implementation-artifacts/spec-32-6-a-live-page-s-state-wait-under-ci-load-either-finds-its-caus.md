---
title: "Story 32.6: A live page's /state wait under CI load either finds its cause or retries once, logged"
type: 'chore'
created: '2026-11-07'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-32-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On a loaded CI host, live browser tests fail in two ways and then pass on an unchanged rerun, so a host-load flake turns a green head red:
- No answer to `loadedAfter`'s snapshot `GET /ocutalon/api/v1/state` (DW-550: cards I10 and I8, socket W2 and W3, chat C1, session S3, answers X9 and X12, decision D2 and D4, layout G2).
- No answer to `page.close` (DW-774: online-session leave L5 and L6).

Story 11.27 ruled out the gateway's per-session cap and found IRIS idle in every failure. It also landed traces and `DIAG` lines, but nobody has read them for a cause yet. The diagnostics also cannot say what the page and the browser did.

**Approach:**
- The lead investigates for at most 90 minutes (Task 0). The result is either `cause:` (Branch A: a fix in the tests) or `none_in_timebox` (Branch B).
- Both branches add page-side diagnostics:
  - for `/state`: whether the page issued the request, what is in flight, and whether the renderer answers;
  - for `page.close`: the same readings, plus whether the browser answers.
- Branch B also adds one logged reload inside `loadedAfter`'s existing snapshot bound. `ci/iris.sh` counts the retries per unit and per group.
- The implement stage builds only the branch that the lead's result names.

## Boundaries & Constraints

**Always:**
- The Planner's terms bind, as the charter's ACs state them:
  - test-only;
  - no blind timeout raise;
  - the fallback is the diagnostics plus at most one logged retry;
  - the proof is the old code red and the fix 20 of 20 under the load harness;
  - never a real key;
  - other epics' specs change only through the shared support files.
- These bounds stay unchanged:
  - `WAIT_SHARE`, `WAIT_CAPS`, `ONLINE_WAITS` and `WAIT_SLACK_MS`;
  - the clean-up reserve and `DIAG_BOUND_MS`;
  - every project's waits and every test timeout;
  - `OCUTALON_LIVE_DEADLINE`.

  Branch A may change one of them only when `### Investigation result` quotes evidence that the page issued `/state` and that the answer was queued on the CI host, not lost in IRIS.
- The retry splits today's bound. Let B be the snapshot bound that `boundedStep` computes today (`capToDeadline(waits.action)` at the start of the wait).
  - The first attempt waits `floor(B/2)`. The reload's own `/state` gets the rest of B.
  - The total never exceeds B.
  - The retry happens only when B ≥ 2 × `RETRY_MIN_ATTEMPT_MS` (10 s).
  - At most one retry per `loadedAfter` call.
  - The only trigger is the first attempt's timer. A sign-in that fails, a closed page or a non-200 answer gets no retry.
- A second miss fails exactly as today:
  - the same message, `loadedAfter the snapshot GET /ocutalon/api/v1/state: no answer within <B> s<note>`;
  - `stateDiagnosis()` runs once;
  - the same `the snapshot is served` and `data-snapshot` checks.
- The two lines of `loadedAfter` that `web/scripts/bounded-waits.test.mjs` pins stay byte-identical: `boundedStep(signInAction(), waits.navigation, 'loadedAfter the sign-in')` and `boundedStep(state, waits.action, \`loadedAfter the snapshot GET ${STATE}\`)`.
- What a new line may and may not hold:
  - New lines carry counts, seconds, states, Playwright resource types and validated error classes only. Every line goes through `redactLine`.
  - They never carry a URL query, a request body, a header, a cookie, a session id, a token, a PID, an IP address, a port, a server name or a host path.
- The retry line is `RETRY <spec>:<line> loadedAfter the snapshot GET /ocutalon/api/v1/state`:
  - `<spec>` is the test's file relative to the folder of the Playwright config (`web/`), for example `e2e/cards/incident-card.spec.ts:454`;
  - one line per retry, on stdout and appended to the file named by `OCUTALON_E2E_RETRY_LOG` when that variable is set.
- `ci/iris.sh`:
  - It stays bash 3.2 compatible.
  - The new helpers go between `traces_prune` and `cmd_live`. The cut that `web/scripts/e2e-part.test.mjs` makes then carries them.
  - The run line that `ci-results.test.mjs` pins, `traces_keep`, `exit "$rc"`, `setup_tag` and `traces_prune` stay as `test-ci-config.sh` pins them.
  - `cmd_live` prints nothing new when no test retried.
  - No line names a host path.
- `web/e2e/support/bounds.ts` stays erasable TypeScript: `bounded-waits.test.mjs` imports it into Node as it is.
- A test that retries on purpose captures `console.log` and points `OCUTALON_E2E_RETRY_LOG` at its own output folder, so CI's counts hold only real retries.
- The whole story is one commit, and the lead creates it.
- Every test added or changed passes on a fresh environment, in either order.

**Never:**
- Nothing under `src/**`.
- No release tool: `release/*.sh`, `eval/run.sh`, the upgrade harness, demo-host-check and the IPM scripts are frozen.
- No real model key.
- No edit to:
  - `.github/workflows/*.yml`, `web/playwright.config.ts`, `ci/units.sh`, `docker/tests/lib-live.sh` or any `docker/tests/test-*.sh`;
  - `docker/tests/test-ci-config.sh`, `web/scripts/e2e-part.test.mjs` or `web/scripts/ci-results.test.mjs`;
  - Epic 17's files: `web/e2e-online/demo-path/**`, `docker/tests/test-online-demo-path.sh`, `web/e2e/chat/notice.spec.ts`, `web/scripts/approval-sources.test.mjs` and `web/scripts/chat-view.test.mjs`;
  - `_bmad/` or the spine.
- No retry of `page.close`, and no bound raised as the fix.
- No test skipped, tagged, removed or weakened, and no pin deleted or loosened. An updated pin pins the new line as tightly as the old one pinned the old line.
- The named specs (`incident-card`, `decision`, `socket`, `leave`):
  - unchanged in Branch B;
  - in Branch A, only their wait-related lines, and only when the result names them.
- No trace copied off a CI host (11.27's ruling (1)).
- No absolute local path in any committed file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Retry, the reload answers (B) | B=30 s (a 45 s test). The first `/state` has no answer by 15 s, and the reload's `/state` answers 200 | One `RETRY e2e/live/socket.spec.ts:151 loadedAfter the snapshot GET /ocutalon/api/v1/state`, then the first-miss page lines (row "Page lines"). One `page.reload`. `loadedAfter` resolves within 30 s, with the usual `SLOW` line of a step of 10 s or more. The line is also appended to `$OCUTALON_E2E_RETRY_LOG` | — |
| Second miss (B) | Neither `/state` answers | At B, the same error as today. Then 11.27's lines once, then the page lines (both `/state` requests). One `RETRY` line in all | as today |
| Short bound | B < 20 s (the deadline cap, or an own wait of 3 to 15 s) | One wait, as today, and no `RETRY`. At the miss: 11.27's lines, then the page lines | as today |
| Not a bound miss | The sign-in never ends, the page closes, or `/state` answers 500 | No retry and no page lines. The same error as today: `loadedAfter the sign-in: ...`, the closed error, or `the snapshot is served` | — |
| Reload throws (B) | `page.reload` rejects | One `DIAG /state reload failed: <class>`. The wait goes on, and B decides. A page that closed before the reload is not reloaded and fails as a closed page does today | never throws |
| Page lines | Any snapshot bound miss | `DIAG /state request: none issued by the page since the sign-in began`, or up to 5 newest lines `DIAG /state request <i> of <n>: issued <s> s after the sign-in began, no answer yet` (`answered <status> at <s> s`, `failed at <s> s (<class>)`). Then `DIAG /state page: <n> request(s) in flight (<type>=<k>, ... in name order), the oldest issued <s> s ago` (or `no request in flight`). Then `DIAG /state page: the page answered in <ms> ms (readyState <complete\|interactive\|loading\|other>)` (or `gave no answer within 2 s`, or `is closed`) | A class outside `^[A-Za-z][A-Za-z0-9_:.]{0,39}$` prints as `another error`, and a type outside `^[a-z]{1,20}$` as `other`. The odd value is never echoed |
| `page.close` bound (DW-774) | A fixture page's close has no answer within the action wait | `page.close: no answer within <s> s`, as today. Before it, four lines go to stdout and to `close-diagnosis.txt` (attachment `close-diagnosis`): `DIAG page.close: the page is <closed\|open>, <n> page(s) in its context, the browser is <connected\|not connected>`; `DIAG page.close requests: <in-flight phrase>`; `DIAG page.close renderer: answered in <ms> ms (readyState x)` / `gave no answer within 2 s` / `is closed`; `DIAG page.close browser: answered in <ms> ms` / `gave no answer within 2 s` / `not measured (not Chromium)` | No retry. The diagnosis never throws |
| `cmd_live` with retries (B) | The unit's Playwright wrote 2 lines to `web/test-results/<unit>-retries.txt` | After the unit's own output and the TRACE lines, both `RETRY` lines, then `RETRIES 2 in live:<unit>`. The exit code is the unit's | Only lines of the `RETRY` shape are printed and counted |
| `cmd_live` without retries | No file, or a stale file from an earlier run | The stale file is removed before the unit starts. No new stdout line | — |
| `cmd_group` (B) | The units leave 1 and 0 retries | `RETRIES 1 in group <g> (live:a 1)` just before `GROUP <g> passed\|failed ...`. With no retries, `RETRIES 0 in group <g>`. When `GITHUB_STEP_SUMMARY` is set and the total is above 0, the step summary gets the `RETRIES` line and each `RETRY` line with its unit | A summary file that cannot be written is ignored |
| Integration (Rule 1, B, real runtime) | `web/e2e/live/state-retry.spec.ts` on a live stack. Only the first `/state` is held at the browser (`holdState(page, 1)`), and the action wait is 20 s | The real app re-sends `/state` after the reload. `loadedAfter` resolves after one `RETRY e2e/live/state-retry.spec.ts:<line> ...`. `main.main` shows `data-snapshot="loaded"` | — |

</intent-contract>

## Code Map

**The wait and its diagnosis (web/e2e/support):**
- `floor.ts`:
  - the doc comment at 138-148 and `loadedAfter` at 149-164;
  - the arming at 151-155, then the two pinned `boundedStep` lines (156, 157);
  - the catch-and-diagnose at 157-161, which becomes `diagnosedAtBound`;
  - the checks at 162-163.
  - The wrappers `signInReadmeLoaded` (167) and `openFloor` (172) carry `loadedAfter` to more callers.
- `bounds.ts`:
  - the header says "Every number lives here only" and "Erasable TypeScript only";
  - `WAIT_SLACK_MS` (34), `capToDeadline` (130-141) and `secs` (71);
  - `slowLine`/`reportSlow` (143-152), the sibling pair that `retryLine`/`reportRetry` follow;
  - `boundedStep` (160-183).
- `navigate.ts:57-64`: `gotoSettled`'s `NAV retry <url>`, the existing single logged retry, under the bound of the time left.
- `diagnose.ts`:
  - the header (9-37) lists the line kinds;
  - `DIAG_BOUND_MS` (40);
  - `describeGateway` (116-148) and `describeDiagnosis` (153-171): the validated-values discipline that the new describers follow;
  - `read` (174-182);
  - `keepLines` (185-197), which writes `state-diagnosis.txt` and the `state-diagnosis` attachment;
  - `redactLine` (213-215);
  - `stateDiagnosis` (218-226), which prints its lines itself.
- `fixtures.ts`:
  - `boundedClose` (35-39) and the fourth contract comment (24-25);
  - `context.on('page', (page) => boundedClose(page, closeWait))` (120), which only fixture-context pages get.
  - `browser.newContext()` pages are not bounded today and stay so.
- `api.ts:113-130` `holdState(page)`: holds every `/state` until `release()`. Today's callers are `live.spec.ts` (L5, L6 through `signIn`) and `web/e2e/live/state-diagnosis.spec.ts:22`.

**Pins that read these files (read-only unless a task says so):**
- `web/scripts/bounded-waits.test.mjs`:
  - 214-218 pin the two `loadedAfter` lines, which are kept;
  - 318-324 pin `page\.close = \(options\) => boundedStep\(close\(options\), waitMs\(\), 'page\.close'\);` and the `context.on('page'` line. The common task for `bounded-waits.test.mjs` updates the first.
- `web/scripts/e2e-part.test.mjs:485-525`:
  - it evals `ci/iris.sh` from `TRACE_FOLDER_NAME=` up to `cmd_live() {`, plus `cmd_live`, with `root=$PWD`;
  - it asserts the exact stdout `PORT ...\nTRACE off: not a CI run\nargc=0\n`.
- `web/scripts/ci-results.test.mjs:74-80`: `cmd_live` holds `OCUTALON_E2E_OUTPUT="test-results/$name" bash "docker/tests/test-$name.sh"`.
- `docker/tests/test-ci-config.sh`:
  - 2111-2117: `^  setup_tag$` comes before `^  traces_prune$` in `cmd_group`, `cmd_live` calls `traces_keep `, and `cmd_live` ends with `^  exit "\$rc"$`;
  - the rule `traces kept` sources the real `cmd_live` and checks that no line names a host path.
- `web/e2e/live/state-diagnosis.spec.ts` (live, sign-in-2, action wait 3 s):
  - it filters the `DIAG /state` lines;
  - it expects no line with `unavailable`;
  - it expects the file to equal those lines.
  - The new page lines start with `DIAG /state`, never say `unavailable`, and go to the same file, so it stays green unchanged.

**CI recipe:**
- `ci/iris.sh`:
  - the header (1-50), with the traces paragraph at 44-50;
  - `TRACE_FOLDER_NAME=` (450) through `traces_prune` (564-576): the cut region;
  - `cmd_live` (578-612); `cmd_group` (621-651), which prints `UNIT ...` and then `GROUP ...`;
  - `mock_image` (94-101);
  - when the file is sourced, it only defines functions.
- The live scripts print only `tail -n 30|80` of the e2e log (DW-756's cause), so a `console.log` of a passing test does not reach CI output. Example: `docker/tests/test-cards.sh:66-79`.
- `docker/tests/test-sign-in.sh:340-366` runs `npm --prefix web run "$e2e_script"`, which is `e2e:sign-in-2` for sign-in-2. The users' passwords are in the environment.
- The `iris` job's `Run the group` step runs `bash ci/iris.sh group <g>`. Nothing in `ci/` writes `GITHUB_STEP_SUMMARY` today: the only writer is `docker/tests/test-eval-set.sh`, a release-path test.

**Application facts (read-only, from the investigation):**
- Every new document sends `/state`:
  - `web/src/app/app.ts:76-77` calls `LiveState.load()`;
  - in `web/src/app/live/live-state.ts:162-173`, only an in-memory flag gates it;
  - `web/src/app/api/api-client.ts:41-42` makes the request.
- No service worker and no `history.replaceState` get in the way.
- The page reloads to the same session:
  - sign-in POSTs get `303 See Other` to a GET of the same URL (`src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls:48,109-114,158-167`);
  - `index.html` is `no-cache`;
  - so a reload GETs the app page with the session cookie and never re-POSTs.
- Nothing runs on unload. Online-session's leave L1 already reloads twice in one session.
- `loadedAfter` has 87 call sites in 38 files: `signIn`, `signInFromSplash`, `signInReadme`, goto, reload, a button press, and custom blocks.
  - A reload is valid at each of them: the page ends on the app page of the same session.
  - Some tests still go red after a retried load, because they assert something about the first load:
    - they count `/state`: `live.spec.ts` L1-L3, L8-L10 and L13, `banners.spec.ts` B15, `api.spec.ts:131`, `frame.spec.ts` F9 and `demo-path/01-page.spec.ts:44`;
    - or they expect the narrow note of the first load: `floor/layout.spec.ts` G6.
- `web/node_modules/playwright` is 1.64.1:
  - `FullConfig.rootDir` is the top-level `testDir` (`web/e2e`; `lib/common/index.js:508`), not the config's folder;
  - `config.configFile` is optional (`types/test.d.ts:2115`).

**Hermetic test host:**
- `web/e2e/live/helper-waits.spec.ts`:
  - the stand-in server (30-53) holds `/state`, `/post`, `/slow` and `IRISLogout` forever, and matches `request.url === STATE` exactly;
  - `withPage` (61-68);
  - the "own waits" describe mutates `project.use` in `beforeEach`/`afterEach` (97-113), which is the pattern for setting a 20 s action wait;
  - the diagnosis describe (218-328) captures `console.log`, uses the `OCUTALON_E2E_IRIS_EXEC` stand-in (`standIn`, `printing`; 211-216), and has the exact lists 244-296.
- It runs without a stack: `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/helper-waits.spec.ts --project sign-in-2)`.
- It also runs in CI's `live:sign-in-2` (group `shards-4`).

**Contention (Rule 11; local remote refs at plan time):** no `origin/OCT-epic*` branch changes any planned file since `origin/feature/OCT_OcuTalon_MVP` (`71a2312e`). The planned files are `web/e2e/support/`, `ci/iris.sh`, `web/e2e/live/` and `web/scripts/bounded-waits.test.mjs`.

## Tasks & Acceptance

**Task 0 (lead, timeboxed: 90 minutes from the spec gate; no source change, only `### Investigation result` is written; lead-side only, the plan stage reads no CI host).** Read in this order:
1. The occurrences since Story 11.27's code reached a branch (`eca467b0`): every `loadedAfter` or `page.close` failure on a head that contains it (`git merge-base --is-ancestor eca467b0 <head>`). The ledger names two:
   - D2, `decision.spec.ts:139`: run 42417271582 on OCT-epic0 `85b479e0`;
   - L6, `leave.spec.ts:354`: run 42419117439, job 128543515301, on feature `bed23f1d`.

   `gh run list` may show more.
2. Each job's log:
   - `TRACE on` or `TRACE off: <reason>` (was tracing on?), and `TRACE kept <n> of <unit> under <tag>/<unit>`;
   - the `DIAG /state` and `DIAG /state gateway` lines;
   - the `UNIT ... <s>s` times;
   - how many runs ran at the same time, for the host load.
3. The failure artifact (`playwright-results-<group>-<attempt>`): `state-diagnosis.txt` and `error-context.md`.
4. The kept trace, read in place on the runner's host (never copied off it): `$HOME/ocutalon-traces/<run tag>/<unit>/<test>/trace.zip`. The runner's name in the job log gives the host: ci-b runs 3-8, ci-c runs 9-14, ci-d runs 15-20. Read:
   - the network entry for `GET /ocutalon/api/v1/state`: whether it exists, its queueing or blocked time, its sent time, and whether it has a response;
   - the actions around the sign-in;
   - for `page.close`: the close action and any event or request after it.

   Record counts, states and times only.

The questions to answer:
- (a) Did the page send `/state`? If there is no entry, it was never issued.
- (b) Was it queued in the browser? An entry with a long queueing or blocked time and no send means yes.
- (c) Was it queued at the web gateway? Yes if `QueuedRequests>0` at the bound, or if the request was sent while IRIS was idle.
- (d) Was it held in IRIS? Yes if a CSP process was not `READ`, a session lock was held, or the licence units were near the limit.
- (e) For `page.close`: did the browser answer at all?

Also, as a measurement the plan could not take (inference): the Verification L3 run shows that the real app reloads to the same session and re-sends `/state`.

Write the result into `### Investigation result` before the implement spawn. The old-code batches (Verification L1) may run inside the timebox as reproduction attempts.

**Common tasks (both branches):**
- `web/e2e/support/bounds.ts`: add `diagnosedAtBound(work, step, diagnose)`.
  - It settles like `work`.
  - When `work` rejects with a message that starts `${step}: no answer within`, it first awaits `diagnose()`, swallowing any throw, then rejects with the same error.
  - It is the existing catch-and-diagnose of `loadedAfter`, moved here so that `boundedClose` reuses it (Rule 2).
- `web/e2e/support/diagnose.ts`. DW-550 and DW-774. Update the header.
  - Add `watchRequests(page)`:
    - per request of the page: the time it was issued, `resourceType()`, whether it is a GET of `STATE`, and its outcome (a response status, `requestfinished`, or `requestfailed` with its error text);
    - at most 200 records, dropping finished ones first;
    - `stop()` removes its listeners.
  - Add the pure describers `describeStateRequests(records, began, now)`, `describeInFlight(prefix, records, now)` and `describeProbe(prefix, probe)`, with the shapes and validation of the matrix rows "Page lines" and "`page.close` bound". Times use `secs`.
  - Add `probePage(page, ms)`, bounded at `PROBE_BOUND_MS = 2_000`: `page.evaluate(() => document.readyState)`, resolving to answered, no answer, closed or failed. It never throws.
  - Add `printDiagnosis(lines, name)`: `redactLine`, then `console.log`, then `keepLines(lines, name)`.
  - `keepLines` gains the base name, with default `state-diagnosis`; the file is `<name>.txt` and the attachment `<name>`.
  - `stateDiagnosis` ends through `printDiagnosis`, with the same lines in the same order and the same file.
  - Add `closeDiagnosis(page, watch)`. It runs under `asCleanup` and prints its four lines to `close-diagnosis`. The renderer probe and the browser probe run at once, each with a 2 s bound. The browser probe is `browser.newBrowserCDPSession()` with `Browser.getVersion` and then `detach()`; only the elapsed ms is printed. When the page has no browser or the session cannot be opened, it prints `not measured (not Chromium)`.
- `web/e2e/support/floor.ts`:
  - `loadedAfter` takes `began = Date.now()` and starts `watchRequests(page)` before the action, and stops it in a `finally`.
  - The snapshot wait goes through `diagnosedAtBound(<the pinned boundedStep line>, \`loadedAfter the snapshot GET ${STATE}\`, ...)`.
  - The diagnosis runs `stateDiagnosis()` and `asCleanup(() => probePage(page, PROBE_BOUND_MS))` at once. When both are done, it prints the request lines and the page lines through `printDiagnosis(..., 'state-diagnosis')`, after 11.27's lines.
  - Update the doc comment. DW-550 and DW-774 (D2, D4 and W3 go through it).
- `web/e2e/support/fixtures.ts`:
  - `boundedClose` starts `const watch = watchRequests(page)`.
  - The close becomes `page.close = (options) => diagnosedAtBound(boundedStep(close(options), waitMs(), 'page.close'), 'page.close', () => closeDiagnosis(page, watch));`.
  - Rewrite the fourth contract comment to include the diagnosis. DW-774 (L5, L6).
- `web/scripts/bounded-waits.test.mjs` (footprint extension): in "the close of a page", the `boundedClose` regex pins the new line exactly. The `context.on('page'` pin and the two `loadedAfter` pins are unchanged.
- `web/scripts/state-wait.test.mjs` (new, node): tests for `diagnosedAtBound`.
  - It resolves like `work`.
  - Another error is not diagnosed.
  - A bound message is diagnosed once, then rethrown unchanged.
  - A `diagnose` that throws still gives the original error.
- `web/e2e/live/helper-waits.spec.ts`:
  - 11.27's diagnosis cases (244, 268, 277, 287, `runPlanted`) assert their exact lists as the first lines of `logged`. They then assert exactly three page lines by pattern: request 1 of 1 `no answer yet`; `1 request in flight (fetch=1)`; `answered ... (readyState complete)`. The file still equals `logged`.
  - New describe `the page-side DIAG lines` (pure, no browser): every row of "Page lines". An error text holding a planted cookie pair prints `another error`, and an odd type prints `other`.
  - New describe `page.close: the close diagnosis`:
    1. a real page of its own `browser.newContext()`;
    2. its `page.close` is replaced by a promise that never settles, then `boundedClose(page, () => 1_000)`;
    3. the close rejects with `/^page\.close: no answer within 1 s$/`;
    4. the four lines, in order and by pattern (the renderer answered, the browser answered), are in `logged` and in `close-diagnosis.txt`, and there is one `close-diagnosis` attachment;
    5. the context is closed in a `finally`.
  - Update the header.

**Branch B only (built when the result is `none_in_timebox`):**
- `web/e2e/support/bounds.ts`:
  - `RETRY_MIN_ATTEMPT_MS = 10_000`;
  - `firstAttemptMs(boundMs)`: `Math.floor(boundMs / 2)` when the bound is finite and at least `2 * RETRY_MIN_ATTEMPT_MS`, else `undefined`;
  - `RETRY_LOG_VARIABLE = 'OCUTALON_E2E_RETRY_LOG'`;
  - `retryLocation()`: `test.info().file` relative to `dirname(test.info().config.configFile)`, else relative to `process.cwd()`. Use `/` separators, then `:` and `test.info().line`. A result that is absolute or starts with `..` becomes the base name, and outside a test it is `unknown:0`;
  - `retryLine(location, step)`;
  - `reportRetry(step)`: `console.log`, then a best-effort `appendFileSync` of the line to the variable's file (after `mkdirSync` of its folder) when the variable is set. It never throws;
  - update the header.
- `web/e2e/support/floor.ts`:
  - Rename the armed wait to `asked`, which keeps its `.catch(() => undefined)`. Compute `whole = capToDeadline(waits.action).ms` and `firstMs = firstAttemptMs(whole)`, and set `const state = firstMs === undefined ? asked : withOneReload(...)`, so that the pinned line is unchanged.
  - The local `withOneReload` settles with `asked` when it settles before `firstMs`. At `firstMs`, unless the page is closed, it does this in order:
    1. `reportRetry(\`loadedAfter the snapshot GET ${STATE}\`)`;
    2. prints the request lines and the page lines (`probePage`, 2 s, a main step inside B);
    3. arms `page.waitForResponse(<same predicate>, { timeout: whole + WAIT_SLACK_MS })`;
    4. calls `page.reload({ waitUntil: 'commit', timeout: whole + WAIT_SLACK_MS })`. A rejection of the reload prints `DIAG /state reload failed: <class>`;
    5. settles with that new wait.
  - The outer pinned `boundedStep` keeps B and the message.
  - Update the doc comment. DW-550 and DW-774.
- `web/e2e/support/api.ts`: `holdState(page, first?: number)` holds only the first `first` requests when it is given. Later requests go straight to the server, and `held()` counts the waiting ones. Without the argument it is unchanged.
- `ci/iris.sh`. Add the header paragraph "Retries (Story 32.6, DW-550, DW-774)".
  - The helpers, between `traces_prune` and `cmd_live`:
    - `retry_log_of <name>`, which is `$root/web/test-results/<name>-retries.txt`;
    - `retry_lines <name>`, the lines that match `^RETRY [A-Za-z0-9._/-]+:[0-9]+ [A-Za-z0-9 ./:_-]+$`;
    - `retry_count <name>`;
    - `retries_report <name>`, which prints those lines and `RETRIES <n> in live:<name>` when n is above 0;
    - `retries_summary <group> <total> <detail>`, which prints the `RETRIES` line and appends it with the `RETRY` lines to `$GITHUB_STEP_SUMMARY` when that is set and the total is above 0. It ignores a write failure.
  - `cmd_live`: before the pinned run line, `rm -f` the unit's file and `export OCUTALON_E2E_RETRY_LOG=<it>`. After `traces_keep`, call `retries_report "$name"`.
  - `cmd_group`: after each `live` unit, add its count. Call `retries_summary` before either `GROUP` line.
- `web/scripts/state-wait.test.mjs`. Add:
  - `firstAttemptMs` for 30 000 (15 000), 20 000 (10 000), 19 999 (undefined) and `Infinity` (undefined);
  - `retryLine`;
  - `reportRetry` outside a test: `unknown:0`, the line appended to a temporary `OCUTALON_E2E_RETRY_LOG`, and an unwritable path swallowed.
  - A bash harness in the shape of `e2e-part.test.mjs`'s `live()`: cut the `TRACE_FOLDER_NAME=`-to-`cmd_live` region, `cmd_live` and `cmd_group`; stub the rest; delete `GITHUB_ACTIONS`, `RUNNER_ENVIRONMENT`, `GITHUB_STEP_SUMMARY`, `GITHUB_WORKSPACE` and `OCUTALON_*` from the environment. It covers the matrix rows `cmd_live` with and without retries (a stale file, the exit code kept) and `cmd_group` (1 and 0 retries, a temporary `GITHUB_STEP_SUMMARY` written only above 0).
- `web/e2e/live/helper-waits.spec.ts`. New describe `loadedAfter: one reload of the page`:
  - The server answers `/retry?mode=once|hold&id=<id>` with `<main class="main"></main>` and a script. The script fetches `STATE + location.search` and, on an ok answer, sets `data-snapshot="loaded"`.
  - For `mode=once`, the first `/state` of an id is held and later ones get 200 `{}`. For `mode=hold`, every one is held. It parses `new URL(request.url, origin)`, ahead of the existing exact match.
  - Each case sets own waits `{ actionTimeout: 20_000, navigationTimeout: 10_000 }` as at 101-113, uses `test.setTimeout(60_000)`, captures `console.log`, and points `OCUTALON_E2E_RETRY_LOG` at `outputPath('retries.txt')`, restored afterwards.
  - R1 (`once`):
    - it resolves after 10 to 20 s;
    - `logged` holds exactly five lines:
      - the exact `RETRY e2e/live/helper-waits.spec.ts:<test.info().line> loadedAfter the snapshot GET /ocutalon/api/v1/state`;
      - the three page lines, matched by pattern;
      - `SLOW loadedAfter the snapshot GET /ocutalon/api/v1/state <s> s`, which `boundedStep` prints for any step of 10 s or more that settles in time;
    - the file holds that one line;
    - the server saw two `/state` requests for the id;
    - the page shows `data-snapshot="loaded"`.
  - R2 (`hold`, with the 11.27 stand-in `CHK|licence|LUAvailable=7`, `CHK|done|1` / `CHK|gw|0`):
    - it rejects with `^loadedAfter the snapshot GET \/ocutalon\/api\/v1\/state: no answer within 20 s$` after at least 20 s and within 37 s;
    - there is exactly one `RETRY` line;
    - 11.27's lines appear once;
    - the request lines name `1 of 2` and `2 of 2`, and the second has `no answer yet`;
    - there were two server requests.
- `web/e2e/live/state-retry.spec.ts` (new, sign-in-2, live; footprint extension): the Integration row.
  - It follows `state-diagnosis.spec.ts`'s shape: `holdState(page, 1)`, `use.actionTimeout = 20_000` and `test.setTimeout(60_000)`, with `fixtureUser('LIVE')` and `signIn`.
  - It captures `console.log` and points `OCUTALON_E2E_RETRY_LOG` at its own output file.
  - It asserts:
    - one exact `RETRY e2e/live/state-retry.spec.ts:<line> ...` line, and the file;
    - a `DIAG /state request 1 of 1: issued .* no answer yet` line;
    - `data-snapshot="loaded"`;
    - `hold.held()` is 1;
    - at least 10 s elapsed;
    - no cookie name or value of at least 8 characters in any line.
  - It restores everything in a `finally`.
- The implement stage's `## Auto Run Result` states that a bounded retry landed, with the `RETRY` and `RETRIES` line shapes, so the lead can report it in the completion contract. In either branch it also lists the footprint extensions (Rule 11 (b)): `web/scripts/bounded-waits.test.mjs`, and in Branch B `web/e2e/live/state-retry.spec.ts`.

**Branch A only (built when the result is `cause: ...`):**
- A1. Build the fix that `### Investigation result` names, in the files it names. They must lie inside this story's footprint (Boundaries). A changed bound must quote the evidence there.
- A2. Add the pinning test that the result names, hermetic where the cause allows. Record its mutation.
- A3. Build none of the Branch B tasks. The common tasks are built.

**Acceptance Criteria:**
- **AC0.** Given the spec gate, when the lead's 90 minutes end, then `### Investigation result` holds `cause: <...>` with its evidence and the fix (Branch A), or `none_in_timebox` with what was read and ruled out (Branch B). The implement stage builds only that branch, and stops `blocked` when the subsection holds neither.
- **AC1 (DW-550, DW-774).** Given a snapshot GET that passes its bound, when the bound fires, then the unit's stdout and `state-diagnosis.txt` hold 11.27's lines, then the request and page lines of the matrix, and the same error is thrown.
- **AC2 (DW-774).** Given a fixture page whose `page.close` passes its bound, when the bound fires:
  - stdout, `close-diagnosis.txt` and the `close-diagnosis` attachment hold the four `DIAG page.close` lines;
  - the same `page.close: no answer within <s> s` is thrown;
  - close is never retried, and its bound is unchanged.
- **AC3 (Branch B).** Given B ≥ 20 s and a first `/state` with no answer at `floor(B/2)`, when `loadedAfter` retries, then:
  - exactly one `RETRY <spec>:<line> loadedAfter the snapshot GET /ocutalon/api/v1/state` is printed and appended to `$OCUTALON_E2E_RETRY_LOG`;
  - the page reloads once;
  - the call resolves when the reload's `/state` answers 200 and `data-snapshot` is `loaded`, all within B.
- **AC4 (Branch B).** Given the reload's `/state` also unanswered, or B < 20 s, when B ends, then the call fails exactly as today: the same message with B, `stateDiagnosis` once, and the same checks. The first case has one `RETRY` line, the second none.
- **AC5 (Branch B).** Given a live unit run through `ci/iris.sh`, when its tests retried:
  - `cmd_live` prints their `RETRY` lines and `RETRIES <n> in live:<unit>`;
  - `cmd_group` prints `RETRIES <total> in group <name>[ (<unit> <n>, ...)]` before its `GROUP` line on every run, 0 included, and writes the step summary when the total is above 0;
  - no line names a host path, and the exit codes are unchanged.
- **AC6 (Branch B, Rule 1/3).** Given a live stack, when `state-retry.spec.ts` holds only the first `/state`, then the real page reloads, re-sends `/state` and loads, after exactly one `RETRY` line.
- **AC7 (proof, lead).** Given the load harness of Verification L1/L2, when it runs on one lane-D throwaway at a time, then the old code's red count and the fix's 20 of 20 are recorded with their counts under `## Verification`. A Branch A fix uses the same harness on the targets the result names.
- **AC8 (scope).** Given the diff, when it is reviewed, then:
  - nothing under `src/**`, no release tool and no file of Boundaries' never-edit list changed;
  - no real key is used;
  - no other epic's spec changed beyond `web/e2e/support/**`;
  - in Branch B no named spec changed;
  - no bound changed, except in Branch A with the quoted evidence.
- **AC9 (push, lead).** Given the change, when it is pushed, then `bash docker/tests/test-boundaries.sh` passed first, and full CI is green on every workflow.
- Standing (Rule 19): every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

## Review Triage Log

## Design Notes

**Decided by the lead** (the plan stage's framing, binding):
1. Two branches in one spec. The investigation is lead-side and timeboxed (Task 0). The lead fills `### Investigation result`, and the implement stage builds only the branch it names.
2. Branch B is the default: one reload inside the same total bound. `page.close` gets diagnostics only. The plan says whether a retry of close is meaningful (below: it is not).
3. The count goes through a `ci/` script that is not a release tool, with no workflow edit where one can be avoided.
4. The load harness is lead-side: one fresh lane-D throwaway at a time, four concurrent Playwright processes against it, optionally a host CPU load beside them, the old code first and then the fix 20 of 20. It is sized for the 150 s rule, with scratch in `<scratchpad>/e32s6proof/`.
5. The implement stage's own verification is hermetic and fast. Live units are left to the lead's proof and to CI.

**Ruling (the lead, 2026-11-08 about 05:58Z, category veto; the Planner may reverse it): the proof's "old red" half.** The Planner's proof asks that the old code go red under the load harness. Locally it does not: 0 of 164 at a 1-minute load up to 49.5 on 16 cores (L1), as 11.27 also found. So L2 keeps the plain load harness for the fix (expected all green), and adds L2s, the same harness with an injected stall: in each run the first `/state` GET of the sign-in is held at the browser for the whole bound. The old code must go red on it, and the fix must pass 20 of 20. Rejected: stopping the story until a CI-host reproduction exists (it idles the release's fix for a flake that recurs about daily); claiming the load harness red (false). Reversal: the Planner asks for a CI-host reproduction, and the retry waits, or is reverted, until it exists.

### Investigation result

**`none_in_timebox`** (the lead, Task 0, 2026-11-08 05:32Z to 05:43Z, then the old-code batches of Verification L1 from 05:43Z to 05:57Z; the timebox ran from 05:32Z, the spec gate, to 07:02Z). Branch B is built, with the one addition below. Counts, states and times only.

What was read:
1. **Occurrences on a head with 11.27's code: none.** `gh run list --workflow ci.yml` since 2026-11-07T16:00Z gave 51 runs (26 success, 19 cancelled, 6 failure). Three runs on heads that contain `eca467b0` had a red attempt, and none of them is this class:
   - 42406393504 att 1 (OCT-epic11 `882b6d4b`, `browser`): `live:demo-path` failed on `page.goto ... is interrupted by another navigation to ...?signedOut=1` inside `signInReadme`, before `loadedAfter`'s wait; `live:sign-in` hit its 905 s suite timeout (the class Story 32.5 split); `TRACE kept 2 of demo-path` and `TRACE kept 1 of sign-in` under `42406393504-1-browser`, on ci-b.
   - 42392984136 att 1 (OCT-epic11 `623b9cb0`, `shards-4`): `the first start did not end ready within 400 s` (infra).
   - 42442077870 (OCT-epic17 `596eb1f7`): the `image` job only.

   The occurrences the ledger names since then (D2 at OCT-epic0 `85b479e0`, L6 at feature `bed23f1d`, L5 at OCT-epic17 `b52d069b`) all predate 11.27's merge (`git merge-base --is-ancestor eca467b0 <head>` fails for each), so no trace and no `DIAG /state gateway` line exists for any of them. D2's job log holds no `DIAG` line (DW-756's class, fixed by 11.27).
2. **The failure artifacts of the three newest occurrences** (`playwright-results-browser-1` of 42417271582; `playwright-results-shards-1` of 42419117439 and of 42425470320):
   - D2 (`loadedAfter the snapshot GET ... no answer within 30 s`): `error-context.md` has no `# Page snapshot`, as in the five that 11.27 read. D2 has no clean-up that closes its page. A renderer crash is excluded: Playwright 1.64.1's `_waitForEvent` (behind `waitForResponse`) rejects at once with `Page crashed` on a crash, never at the bound. So after the miss the page did not answer Playwright's snapshot (inference: an unresponsive renderer, or a page caught between documents).
   - L5 and L6 (`page.close: no answer within 30 s`): both files HAVE a page snapshot, taken after the bound, showing the online demo's splash ("your place was freed ... Sign in again"). The page that would not close was open and rendering. Both closes follow a CSP group sign-out in the same context (L6: `signOutGroup(context)` then `page.close()`; L5: the first page's `IRISLogout=end`, then `second.close()`).
3. **The CI hosts' own history** (read-only over SSH: `sar` 10-minute samples for 2026-11-05 to -08, `/proc/pressure`, `/proc/vmstat`, `docker ps`; nothing changed on any host). The 11 occurrences whose job logs name a host and a unit window (runs 41983575716, 42086496017, 42102775939, 42373379335, 42417271582, 42158625231 twice, 42158693602, 42161844768, 42419117439, 42425470320) fall on all three hosts (ci-b 3, ci-c 2, ci-d 6).
   - All three hosts swap all the time under CI load: in busy samples (1-minute load at least 4) the median swap-in is 56 to 71 pages/s and swap-out about 1,500 to 2,000 pages/s; `%commit` reaches 2.1 to 3.3 times the RAM; direct reclaim runs. Since boot (17 days): about 130 million pages swapped out per host, and about 6 hours of `io full` pressure.
   - **But the failures do not follow the swapping.** Ranked against windows of the same length made of busy samples on the same host, the occurrence windows' highest swap-in sits at a mean of p52 (5 of 11 above the median). And C1 of 41983575716 (2026-11-05 07:05Z to 07:21Z, ci-d) failed on a quiet host: 1-minute load at most 1.9, swap-in at most 1 page/s, 9.5 GB available, `%commit` 89.
   - Host facts for the Planner, not a cause of this story: ci-b and ci-c each still run one throwaway stack of an old run (6 and 4 days old, holding about 2 GB of swap between them; ci-d has none and 0.56 GB of swap in use). This run did not start them, so it leaves them alone.

What each question ruled out:
- (a) Did the page send `/state`? Not answerable: no trace exists. The missing page snapshot in all 6 `loadedAfter` artifacts points at a page that did not answer at the bound (inference).
- (b) Queued in the browser? Not answerable without a trace.
- (c) Queued at the web gateway? 11.27 ruled out the per-session cap. The gateway counts at the bound do not exist yet for any occurrence.
- (d) Held in IRIS? Ruled out, as 11.22 and 11.27 found (CSP processes `READ`, no session lock, licence 1 of 8). Host memory pressure is ruled out as the explanation: the failures do not rank above other busy windows, and one failed on a quiet host.
- (e) `page.close`: the browser rendered the page and answered Playwright's snapshot after the bound, but did not close it within 30 s. No request is involved.

The fix to build: **Branch B, exactly as planned**, plus one line in the common page diagnostics, because the 10-minute `sar` samples cannot show what the host did during the 30 s that matter:
- `DIAG /state host: ...` and `DIAG page.close host: ...`, after the page lines. They come from Linux's own counters, read by the Playwright worker on its own host:
  - the 1-minute load and the CPU count (`os.loadavg()`, `os.cpus().length`);
  - `/proc/pressure/{cpu,memory,io}` `some`/`full` `avg10`;
  - the swap-ins (`pswpin` of `/proc/vmstat`) between the wait's start and the bound, as pages per second.
- Numbers only. Where a file is missing (macOS, a developer machine), the line reads `... host: not measured (no /proc/pressure)`. The reads are bounded, never throw, and print no path, PID or host name.
- The `watchRequests` start reads the first `pswpin`. A unit test of the describer takes a stand-in reading.

**Governing ADs (Rule 6).**
- **AD-22:**
  - `ci/iris.sh` stays the one recipe, and every unit keeps its own throwaway.
  - Nothing secret enters an artifact: the `RETRY`/`RETRIES` lines and the step summary hold a spec path, a line number and a fixed step name only.
  - No trace leaves the host.
- **AD-12:** the page reads `GET /state` on every load and then polls. The reload relies on this and does not change it.
- **AD-13:** sign-in ends with a 303 to a GET, which is why a reload re-loads the same signed-in page. This is not changed.
- **AD-19:** no key, cookie or token in any log. Every new line passes `redactLine` and holds only validated values.
- **AD-29:** these are Lane B files, and Epic 32 is Lane B's. Other lanes' specs change only through `web/e2e/support/**`.

No AC contradicts an AD's Rule or Prevents line. No NFR is unmeasurable: AC7's 20 of 20 is a count, and the timebox is a duration. The old code's red under local load is not certain, so see the risk below.

**Rule 1/2.**
- Integration ACs:
  - AC6 (consumer: the real application page through `loadedAfter`);
  - AC5 (consumer: `cmd_live` and `cmd_group` read the file that the Playwright helper writes). Both sides of that seam are pinned: R1 pins the file, and `state-wait.test.mjs` pins the reader.
- Consumed-by:
  - every `loadedAfter` caller (87 call sites in 38 files, and through `openFloor`, `signInReadmeLoaded`, `openSession` and `openVisitor`), among them I10, D2, D4, W3 and L5's two calls;
  - every fixture-context page's close (L5, L6);
  - CI's `iris` job, through `ci/iris.sh group`;
  - the lead's harness.
- Consumes:
  - `boundedStep`, `capToDeadline`, `secs`, `asCleanup` and `WAIT_SLACK_MS` (bounds.ts); `currentWaits` (navigate.ts);
  - `stateDiagnosis`, `keepLines` and `redactLine` (11.27); `holdState`;
  - `signIn` and `fixtureUser('LIVE')`;
  - 11.27's `cmd_live` and `traces_keep`;
  - helper-waits' stand-in server and `OCUTALON_E2E_IRIS_EXEC`.
- Extends (Rule 2):
  - `retryLine`/`reportRetry` follow `slowLine`/`reportSlow` in the same file.
  - The single logged retry follows `gotoSettled`'s `NAV retry`. It is no copy: it splits a bound and reloads.
  - `diagnosedAtBound` is `loadedAfter`'s existing catch moved out and reused by `boundedClose`.
  - `keepLines` gains a name instead of getting a second writer.
  - `holdState` gains a count instead of getting a second hold helper.
  - The describers follow `describeGateway`'s validation.
  - The retry functions of `ci/iris.sh` sit with the trace helpers. No sibling reads a per-unit file, and `traces_keep` is the nearest.
  - The bash harness of `state-wait.test.mjs` follows `e2e-part.test.mjs`'s `live()`. It is a new file because the never-edit list keeps `e2e-part.test.mjs` untouched.
  - `state-retry.spec.ts` is new, beside `state-diagnosis.spec.ts`, because it needs a stack, and helper-waits stays stack-free.

**Ledger (Rule 17).**
- **DW-550: addressed.**
  - Common tasks: diagnosis, floor, `diagnosedAtBound`. Every snapshot miss now also says what the page and browser did.
  - Branch B: the retry contains the flake for every `loadedAfter` caller (I10, I8, W2, W3, C1, S3, X9, X12, D2, D4, G2).
  - Branch A: the result's fix.
- **DW-774: addressed.**
  - Its `/state` part (D2, W3) is as DW-550's.
  - Its `page.close` part (L5, L6) gets the close diagnosis (AC2). It gets no retry, by design (below), so the lead's adjudication may keep that part open on the new evidence.
- Nothing is declined.

**Decided in-stage.**
1. **The split.**
   - The first attempt is `floor(B/2)`, and the retry happens only when B ≥ 20 s.
   - 11.27 measured normal answers of 21-1252 ms, and 3.6-6.8 s from the click under a 40x renderer throttle. Every CI failure ran its whole 30 to 90 s bound with no answer.
   - Half of 30 s, the common B of a 45 s test or an online project, gives each load at least 2.2 times the worst measured answer.
   - A least attempt of 10 s still gives 1.5 times. Below 20 s a split would leave too little for a page load, so the wait stays single.
   - A `/state` that would have answered between B/2 and B now takes a reload. That is the price of the fallback.
2. **The reload is `page.reload({ waitUntil: 'commit' })`, after a fresh `waitForResponse` is armed.**
   - Any `/state` answer after the reload counts, and `data-snapshot` on the current document decides.
   - A closed page is never reloaded.
   - A failed reload is logged and the bound decides, so "a second miss fails as today" holds.
3. **First-miss diagnostics are page-side only:** the request lines and a 2 s renderer probe, counted inside B.
   - 11.27's IRIS reads run only at the second miss. They can take up to 15 s of the reload's share, and 11.22 and 11.27 found IRIS idle in every failure.
   - A retried test that passes keeps no trace (`retain-on-failure`), so these lines are the only record of a covered miss.
4. **Page lines at every bound miss, retry or not,** after 11.27's lines.
   - 11.27's exact lists in helper-waits become exact prefixes plus exact page-line patterns, so they are not weakened.
   - `state-diagnosis.spec.ts` stays green unchanged, because its filters include them.
5. **No retry of `page.close`.**
   - Playwright's close asks the browser to close the target and waits for its close event. A second call waits on the same close (inference), so it would be a bound raise in disguise.
   - The close diagnosis says whether the page, its renderer and the browser still answer, which is question (e).
6. **The count goes through a file.**
   - The live scripts print only the e2e log's tail, so a `RETRY` line on a passing test's stdout would not reach CI.
   - So the helper also appends to `OCUTALON_E2E_RETRY_LOG`, which `cmd_live` sets to `web/test-results/<unit>-retries.txt` (it is in the failure artifact, and holds no secret).
   - `cmd_live` reprints the lines and counts them. `cmd_group` prints `RETRIES` on every run, so 0 is evidence too, and writes `GITHUB_STEP_SUMMARY` only above 0.
   - No workflow edit is needed, so there is no open question for the lead.
7. **The location is relative to the config's folder.** `config.rootDir` is the top `testDir`, which would print online specs as `../e2e-online/...`.
8. **Real-runtime evidence is a new live spec,** not a fault switch in `loadedAfter`. The harness can only exercise the retry when the load produces a miss.
9. **One pin updated, two kept.** The `boundedClose` pin in `bounded-waits.test.mjs` is updated (a footprint extension, reported) rather than keeping the pinned line by wrapping `page.close` twice. `loadedAfter`'s two pinned lines are kept byte-identical by naming the retrying promise `state`.
10. **The harness target is `live:sign-in-2` W3.**
    - It has 45 s tests and a setup of about 93 s (Rule 21). One batch is the stack, setup and four W3 runs, about 110 to 145 s (inference), so it fits the 150 s rule.
    - The `live:cards` unit's 90 s tests do not fit.
    - I10, D2 and D4 run the same `loadedAfter` code.
    - L5 and L6 have no fix to prove: AC2's hermetic case proves their lines.
11. **The common diagnostics land in Branch A too.** They are test-only and cheap, and they serve whichever entry the cause leaves open.
12. **The epic context is reused** as the dispatch asked. It is valid (no planning file is newer). The continuity story is 32.5: its Contention and footprint style are followed.

**Risk.**
- 11.27 found no local setting that reproduces a 30-90 s miss. So the old code may stay green under the harness, and AC7's red is an empirical question.
- If L1 gives 0 reds of 20 at `LOAD_BURN=16`, the lead records the counts and takes the proof AC to the Planner as a Rule 5 question. The plan does not decide it.
- Callers that count `/state` or expect the first load's narrow note (Code Map) still go red after a covered miss. That is no worse than today's red, and those specs lie outside this story's footprint. The `RETRY` line before their failure names the cause.

**Expected CI cost (inference).** About 50 s more in `live:sign-in-2` (`shards-4`, 1,897 s on `5b47f052`): R1 about 11 s, R2 about 22 s, the close case about 2 s, `state-retry.spec.ts` about 15 s. Nothing else changes when no test retries.

## Verification

Run from the worktree root after `git rev-parse --show-toplevel` matches it, with `env | grep ^OCUTALON_` printing nothing. Each command runs in its own foreground call with `timeout: 600000`, sized to about 150 s, and one test runner per call. No IRIS MCP call, slot or stack is needed for `(loop)` and `(once)`. The `(lead)` lines use lane D only. For a Branch A pass, drop the Branch B-only names.

**Commands:**
1. `(loop)`, about 10 s: `node --test web/scripts/state-wait.test.mjs web/scripts/bounded-waits.test.mjs web/scripts/e2e-part.test.mjs web/scripts/ci-results.test.mjs`. Expected: all pass. `e2e-part` and `ci-results` stay unchanged and green.
2. `(loop)`: `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/helper-waits.spec.ts --project sign-in-2 --grep 'the /state diagnosis')`. Expected: all pass with no stack.
3. `(loop)`, about 40 s: `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/helper-waits.spec.ts --project sign-in-2 --grep 'one reload of the page|the close diagnosis|the page-side DIAG lines')`. Expected: all pass.
4. `(loop)`: `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/helper-waits.spec.ts --project sign-in-2 --grep-invert 'the /state diagnosis|one reload of the page|the close diagnosis|the page-side DIAG lines')`. Expected: all pass.

   For lines 2 to 4: if one nears 150 s, split it further by `--grep`.
5. `(loop)`, Branch B, about 35 s: `bash docker/tests/test-ci-config.sh`. Expected: every rule PASS, `traces kept` among them.
6. `(once)`: `npm --prefix web run lint`, then `bash docker/tests/test-boundaries.sh`. Expected: exit 0.
7. `(once)`: `npm --prefix web test`. Expected: exit 0. If it nears 150 s, run `node --test` over `web/scripts/*.test.mjs` in two halves.
8. `(once)`: lines 4, 3 and 2 again, in that order. Expected: all pass, in either order.
9. `(once)`: `git diff --stat -- . ':(exclude)_bmad-output'`. Expected: only the files of the tasks of the built branch.

**Mutations (Rule 19).** For each one: apply it, observe red, restore byte-identical, and write a `mutation:` line here.
- AC1: drop the page lines from the snapshot diagnosis → the diagnosis cases of line 2 go red.
- AC2: drop `diagnosedAtBound` from `boundedClose` → the close case goes red (no line; ENOENT on `close-diagnosis.txt`).
- AC3: skip the `page.reload` call → R1 goes red (it rejects at 20 s).
- AC4: give the reload a fresh whole B (the outer `waits.action` doubled) → R2 goes red (message and time).
- AC3: drop `reportRetry`'s append → R1 goes red on the file.
- AC5: drop `retries_report`'s count line, or make `cmd_group` skip `retries_summary` → `state-wait.test.mjs` goes red.
- AC6, lead: skip the reload → `state-retry.spec.ts` goes red on L3.

**Lead-side (`(lead)`; after implement unless stated).**
- `<laneD>` stands for `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=32 stage=proof'`.
- Each call first runs `SCR=<scratchpad>/e32s6proof; export SCR REAL_NPM=$(command -v npm) MOCK_IMAGE=$(bash -c '. ci/iris.sh && mock_image')`. Then it runs its command with `PATH="$SCR/bin:$PATH"`.
- Once, write the scratch shim `$SCR/bin/npm` (mode 755; never committed).
  - When a unit script makes its browser call, `npm --prefix web run $LOAD_SCRIPT`, the shim runs `LOAD_PROCS` concurrent Playwright processes against the unit's one stack instead.
  - Each process has its own output folder, retries file and log.
  - Beside them run `LOAD_BURN` busy loops on the host and `LOAD_BURN` in the Docker VM. An EXIT trap removes them all.
  - Any other npm call goes to the real npm.
  - The logs hold the stack's throwaway passwords. They stay in the scratchpad, are never committed or pasted, and only the counts are recorded.

  ```bash
  #!/usr/bin/env bash
  [ "$*" = "--prefix web run $LOAD_SCRIPT" ] || exec "$REAL_NPM" "$@"
  burn=""
  stop() {
    for p in $burn; do kill "$p" 2>/dev/null; done
    for c in $(docker ps -aq --filter "name=e32s6burn-$LOAD_TAG-"); do docker rm -f "$c" >/dev/null 2>&1; done
  }
  trap stop EXIT
  i=0
  while [ "$i" -lt "${LOAD_BURN:-0}" ]; do
    i=$((i + 1))
    sh -c 'while :; do :; done' &
    burn="$burn $!"
    docker run -d --rm --name "e32s6burn-$LOAD_TAG-$i" --cpus 1 "$MOCK_IMAGE" node -e 'for(;;){}' >/dev/null
  done
  pids=""
  k=0
  while [ "$k" -lt "${LOAD_PROCS:-4}" ]; do
    k=$((k + 1))
    OCUTALON_E2E_OUTPUT="test-results/e32s6-$LOAD_TAG-$k" OCUTALON_E2E_RETRY_LOG="$SCR/$LOAD_TAG-$k.retries" \
      "$REAL_NPM" --prefix web run "$LOAD_SCRIPT" -- $LOAD_ARGS > "$SCR/$LOAD_TAG-$k.log" 2>&1 &
    pids="$pids $!"
  done
  bad=0
  k=0
  for p in $pids; do
    k=$((k + 1))
    wait "$p"
    rc=$?
    [ "$rc" -eq 0 ] || bad=1
    log="$SCR/$LOAD_TAG-$k.log"
    passed=$(grep -Eo '[0-9]+ passed' "$log" | tail -n 1 | grep -Eo '[0-9]+')
    failed=$(grep -Eo '[0-9]+ failed' "$log" | tail -n 1 | grep -Eo '[0-9]+')
    retries=0
    [ -f "$SCR/$LOAD_TAG-$k.retries" ] && retries=$(grep -c '^RETRY ' "$SCR/$LOAD_TAG-$k.retries")
    echo "LOAD $LOAD_TAG/$k exit=$rc passed=${passed:-0} failed=${failed:-0} retries=$retries"
  done
  exit "$bad"
  ```
- L0, once: `<laneD> OCUTALON_RUN_TAG=e32s6pb bash ci/iris.sh build`.
- L1, the old code, before the implement spawn, on the unchanged tree; five calls, b = 1 to 5:
  1. `<laneD> OCUTALON_RUN_TAG=e32s6po<b> LOAD_SCRIPT=e2e:sign-in-2 LOAD_ARGS='--grep W3: --repeat-each 1' LOAD_PROCS=4 LOAD_BURN=16 LOAD_TAG=old-<b> PATH="$SCR/bin:$PATH" bash ci/iris.sh live sign-in-2`, about 110 to 145 s (inference);
  2. in its own call, `<laneD> OCUTALON_RUN_TAG=e32s6po<b> bash ci/iris.sh teardown`, and `docker ps -aq --filter name=e32s6burn` prints nothing.

  Record the 20 `LOAD old-*` lines as `old: <failed> of 20 red`. Name each red by the failing step in its `$SCR/old-<b>-<k>.log`. Only a `loadedAfter the snapshot GET ... no answer within` red counts as the occurrence class. Record the others by their step. Expected: at least one red of the occurrence class. See the Risk.
  **Result (the lead, 2026-11-08 05:43Z to 05:57Z, before the implement spawn): `old: 0 of 164 red`.**
  - Batch 1 ran `--repeat-each 1` (4 runs); batches 2 to 5 ran `--repeat-each 10` (40 runs each), so that the four processes sign in back to back for about 20 s instead of overlapping for 1 s (decided by the lead).
  - `LOAD_BURN` was 4 for batches 1 to 4 and 8 for batch 5, not 16: the Mac's 16 cores are shared with lanes A to C, whose own runs a 32-loop burn could make flake (decided by the lead). The Mac's 1-minute load went from 10.5 to 49.5 during batch 5.
  - Every W3 answered `/state` in about 1 s; no `RETRY` (none possible on the old code); every stack and burner gone after each batch (`docker ps -aq --filter name=e32s6` empty).
- L2, the fix: the same five batch pairs with `OCUTALON_RUN_TAG=e32s6pf<b>` and `LOAD_TAG=fix-<b>`. Record them as `fix: <passed> of 20, <retries> RETRY lines`. Expected: 20 of 20.
- L3, Branch B, AC6 on a real stack: `<laneD> OCUTALON_RUN_TAG=e32s6pl LOAD_SCRIPT=e2e:sign-in-2 LOAD_ARGS='e2e/live/state-retry.spec.ts' LOAD_PROCS=1 LOAD_BURN=0 LOAD_TAG=live PATH="$SCR/bin:$PATH" bash ci/iris.sh live sign-in-2`, then its teardown. Expected: `passed=1 failed=0`. Run it again with AC6's mutation for the red, and restore byte-identical.
- L4: the fresh-environment check (Rule 19) of the added and changed tests (lines 1 to 4), forward and reversed.
- L5: after the push, full CI is green on every workflow.
  - Each `iris` job prints a `RETRIES <n> in group <g>` line before its `GROUP` line. Record the counts (expected 0 on a quiet run).
  - Record `shards-4`'s job time against the last green run (expected about +50 s, under 35 minutes).

**Shared surfaces:**
- the `DIAG /state` line set of a snapshot miss (helper-waits' exact lists; `state-diagnosis.spec.ts`'s filters);
- `stateDiagnosis`'s file and the new `close-diagnosis` attachment;
- `cmd_live`'s stdout (`e2e-part.test.mjs`'s exact lines; unchanged when nothing retried);
- `cmd_group`'s stdout (the new `RETRIES` line before `GROUP`);
- `web/test-results/` (the new `<unit>-retries.txt`, in the failure artifact);
- the `iris` job's step summary;
- `bounded-waits.test.mjs`'s source pins;
- `holdState`'s signature;
- sign-in-2's spec list (the new `state-retry.spec.ts` shifts its `--part` cuts; the folder-based pins of `playwright-projects.test.mjs` hold).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (HALT after planning).**
- The spec carries:
  - Task 0, for the lead (90 minutes);
  - an empty `### Investigation result`;
  - common page-side diagnostics, for `/state` and for `page.close`;
  - Branch B: one reload inside the same bound, the `RETRY` line, and the `RETRIES` count in `ci/iris.sh`;
  - Branch A, stated generically.
- DW-550 and DW-774 are both addressed, and none is declined.
- Footprint extensions to report: `web/scripts/bounded-waits.test.mjs` (one regex), and in Branch B `web/e2e/live/state-retry.spec.ts`.
- No workflow edit is needed.
- Risk: the old code may not go red under local load (11.27 could not reproduce the miss). Verification L1 records the count, and AC7 goes to the Planner if it is 0 of 20.
