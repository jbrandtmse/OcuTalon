---
title: 'Story 32.7: The remaining CI flakes either find their cause or are contained, logged'
type: 'chore'
created: '2026-11-08'
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

**Problem:** Five CI flakes still turn green heads red. Each one fails only on a loaded CI host and passes on an unchanged rerun:
- G1, DW-211: `Test.Agent.Runners` `TestStartRefused`. The refusal row is written, but TriageAgent keeps an alive job past `WAITSECONDS` (120 s).
- G2, DW-639: `Test.Schedule.Heartbeat` `TestAfterAllTestsNothingSaved`. `NotRunning()` names TelegramIn with row 0, runtime flag 1 and no jobs.
- G3, DW-774 (the `page.close` half): leave.spec L5 and L6 get no answer from `page.close` within 30 s, although the page is open and the renderer and the browser answer in milliseconds.
- G4, DW-973: `Test.Docs.ExtractMore` `TestTimeLeft` misses its timing bound: elapsed 15.89 s and 15.16 s, against `< 15`.
- G5, DW-966: `Test.Checks.BeatOutcomes` waits for any channel's row and then reads only the web rows. Nobody has measured whether this race happens.

A separate problem, DW-911: when a retried test passes, its retry-time `DIAG` lines never leave the runner.

**Approach:**
- Task 0: the lead investigates each group for at most 90 minutes and writes one `### Investigation result` per group. It has one of three outcomes:
  - `cause:` (Branch A): the fix is in the tests;
  - `none_in_timebox` (Branch B): diagnostics plus at most one logged retry per wait;
  - `product:`: the investigation of that group stops, and the lead reports the evidence to the Planner. No task is built for that group.
- G5 is measured first. Its fix is built only if the measurement shows the race.
- The implement stage builds only what each result names, plus the common tasks:
  - DW-911: the retry-time `DIAG` lines are printed next to the `RETRY` lines;
  - a one-method `class` run, which the proofs need.

## Boundaries & Constraints

**Always:**
- The Planner's terms apply, stated once here:
  - The story is test-only.
  - No blind timeout raise. A longer wait or bound must quote, in that group's result, its own diagnostics: what the test waited on, and that the wait ended late on the loaded host rather than being lost or failing in the product.
  - The fallback is at most one retry per wait. The total bound stays as it is today: the retry fires at `floor(B/2)` and the retry's wait gets the rest of B.
  - A second miss fails exactly as today, with the same assertions and messages and the same step named.
  - Every retry prints `RETRY <spec-or-class>:<line> <step>` in the shape that `ci/iris.sh` `retry_lines` matches, and is counted in its group's `RETRIES` line.
  - The proof for each fixed entry: the old code goes red under the load harness (or under an injected stall, where plain load does not reproduce the failure), and the fix passes 20 of 20 under the same load. Both results are recorded as `(lead)` lines.
  - Never a real model key and never a real Telegram bot.
- What `src/**` may change: only the named test classes, and in them only:
  - their wait and timing lines;
  - the retry's `$$$LogMessage` lines;
  - the text of their wait assertions' messages (diagnostics).

  The step text uses only `[A-Za-z0-9 ./:_-]`.
- What a `DIAG` line may hold:
  - printable ASCII, at most 300 characters after `DIAG `;
  - counts, seconds, states, item names and validated error classes only.

  It never holds a key, a token, a cookie, a session id, a password, a URL query or a host path. Web lines go through `redactLine` before they are appended.
- `ci/iris.sh`:
  - It stays bash 3.2 compatible.
  - New helpers go between `traces_prune` and `cmd_live`.
  - With no retry, it prints nothing new.
  - The exit codes are unchanged.
  - The run line, `traces_keep`, `exit "$rc"`, `setup_tag` and `traces_prune` stay as `test-ci-config.sh` pins them.
- 32.6's `RETRY` and `RETRIES` lines and the step summary stay as they are (DW-911 decision).
- `web/e2e/support/bounds.ts` stays erasable TypeScript.
- A test that retries on purpose captures `console.log` and points `OCUTALON_E2E_RETRY_LOG` at its own output folder.
- Every test added or changed passes on a fresh environment, in either order.
- The story is one commit, and the lead creates it.

**Never:**
- Any product file, which includes `Install/Step/Production.cls`, `Docs/**`, `Bridge/**`, `Core/**`, `Agent/**` and `Channel/**`. A product cause stops the group.
- `OcuTalon.Test.Core.Observe` and `OcuTalon.Test.Agent.RunnerFixture`. The tests read them only.
- Any new ObjectScript class.
- Any release tool: `release/**`, `eval/run.sh`, the upgrade harness, demo-host-check and the IPM scripts.
- Tags or `main`.
- `.github/workflows/*.yml`, `web/playwright.config.ts`, `ci/units.sh` (no new group: U-307) and `docker/tests/lib-live.sh`.
- Any `docker/tests/test-*.sh`, except a pin in `test-ci-config.sh` that a task names.
- No test may be skipped, tagged, removed or weakened, and no pin deleted or loosened. A pin that is updated pins the new line as tightly as the old one did.
- No change to `WAITSECONDS`, `RECORDSECONDS`, `WAITDIAGNOSIS`, `QUIETWAIT`, the 4 s and 15 s of `TestTimeLeft`, `WAIT_SHARE`, `WAIT_CAPS`, `ONLINE_WAITS`, `WAIT_SLACK_MS`, `DIAG_BOUND_MS`, `PROBE_BOUND_MS`, the project waits, the test timeouts or `OCUTALON_LIVE_DEADLINE`, except in Branch A with the quoted evidence.
- No trace copied off a CI host.
- No absolute local path in a committed file.
- No IRIS MCP call and no dev slot. Lane A throwaways only.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| ObjectScript retry (B) | G1, G2 or G4 has a first miss (AC3). The test logs `$$$LogMessage("RETRY <step>")`, then one or more `$$$LogMessage("DIAG <text>")` | `run_class` prints, after its `CLASS` line, `RETRY <Class>:<line> <step>`, where `<line>` is the line of the `$$$LogMessage` call in the class's `.cls` file. Then it prints the `DIAG` lines. It appends all of them to the unit's retries file. The class verdict is unchanged | A location that cannot be mapped prints `<Class>:0`. A line that fails the shape is dropped and never counted |
| Shard counted (B) | `cmd_group` runs `shard:lane-a@rest`, and one class logged one retry | `cmd_shard` prints `RETRIES 1 in shard:lane-a@rest` before its `SHARD` line. `cmd_group` prints `RETRIES 1 in group shards-2 (shard:lane-a@rest 1)`. The step summary gets the `RETRY` line when the total is above 0 | A stale file from an earlier run is removed when the shard or class unit starts |
| No retry | Any unit, with no retry | No new line. `RETRIES 0 in group <g>`, as today | — |
| DW-911 | A live or shard unit retried, and its file holds the `RETRY` and `DIAG` lines | `retries_report` (and the shard's report) prints the `RETRY` lines, then the `DIAG` lines, then `RETRIES <n> in <kind>:<unit>`. The count holds only `RETRY` lines | Only lines matching `^DIAG [ -~]{1,300}$` are printed |
| Web retry diag (DW-911) | `loadedAfter` retries (32.6) | `reportRetry(step, lines)` appends the `RETRY` line and then the retry-time page lines (`pageSideLines`, after `redactLine`) to `$OCUTALON_E2E_RETRY_LOG`. Stdout is as today | It never throws |
| Close retry (G3 B) | A Chromium fixture page. B = `waitMs()` is at least 20 s. The first close has no answer by `floor(B/2)` | One `RETRY <spec>:<line> page.close` line, with the close-diagnosis lines as its `DIAG` lines. One `Target.closeTarget` for the page's target, sent through a browser CDP session. The close resolves when the page's `close` event fires, or when the first close settles, within B | A CDP failure prints `DIAG page.close re-close failed: <class>`, and B decides |
| Close second miss (G3 B) | The page is still open at B | The same `page.close: no answer within <B> s` and the same close diagnosis as today. One `RETRY` line | — |
| Close, no retry | B < 20 s, a page that is not Chromium, or a page that closes before `floor(B/2)` | Exactly today's behaviour. No `RETRY` | — |
| One-method run | `ci/iris.sh class OcuTalon.Test.Docs.ExtractMore:TestTimeLeft` | The manager runs only that method. Output: `CLASS OcuTalon.Test.Docs.ExtractMore:TestTimeLeft passed\|failed <s>s` | An unknown class, or a method that is not `Test[A-Za-z0-9]+` in the class's file, gives today's `unknown test class` exit 2 |

</intent-contract>

## Code Map

**G1, DW-211: `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls`** (a Lane A test area. Before implement, the lead checks it against Epic 41's in-flight diffs.)
- The header, at 1-40.
- `WAITSECONDS = 120`, at 81.
- `TestStartRefused`, at 239-282. It calls `AssertRefused` at 258 and 270.
- `AssertRefused`, at 596-613: one poll up to WAITSECONDS on three things: the row, no alive job, and `NotRunning() [ item`. Then three assertions.
- `AssertOthersRun`, at 629-640.

Read-only helpers in `Test/Agent/RunnerFixture.cls`:
- `Restart(name, wait)`, at 119-125: `TempStopConfigItem` 1, then 0;
- `NotRunningNow`, at 142-160: it leaves out items whose `Enabled` row is 0 (DW-591);
- `StateOf`, at 165-182: row, flag and jobs as text;
- `Jobs`, at 185-195: `State="Alive"`, whatever the `Status`.

The product `Install/Step/Production.cls` `NotRunning`, at 154-177, skips the `DEADSTATUSES` jobs and reads `$$$ConfigIsEnabled`. It is read-only.

**G2, DW-639: `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls`**
- `TestAfterAllTestsNothingSaved`, at 597-614: one read of the product `NotRunning()` at 612, with no wait. The message at 613 already names the items and their `StateOf` (Story 39.10).
- `Restore`, at 180, reads it the same way.
- `RECORDSECONDS = 30`, at 62.
- The throwaway parks Telegram at start: `docker/tests/lib-live.sh` `live_park_telegram`, at 448-468, through `OcuTalon.Test.Channel.BotApi.Park()`.
- The classes that touch TelegramIn's rows: `rg -l TelegramIn src/ocutalon/cls/OcuTalon/Test`. In lane-b these are Core (`TelegramCalls`, `AnswersTelegramProduction`, `SessionOps*`, `GotItProduction`, `PersonaAnswers`, `Routing`), Web (`Api`, `PairingApi`), `Msg/Contracts`, `Demo/Guide` and `Schedule/Reminders`.

**G3, DW-774 close:**
- `web/e2e/support/fixtures.ts`:
  - `boundedClose`, at 36-40: `page.close = (options) => diagnosedAtBound(boundedStep(close(options), waitMs(), 'page.close'), 'page.close', () => closeDiagnosis(page, watch));`;
  - the fourth contract comment, at 24-27, says "A close is never retried". It is rewritten in Branch B.
- `web/e2e/support/diagnose.ts`: `closeDiagnosis`, at 484 and after, `probePage`, `probeBrowser` (`browser.newBrowserCDPSession()`) and `printDiagnosis`.
- `web/e2e/support/bounds.ts`: `firstAttemptMs`, at 192; `reportRetry`, at 174; `retryLocation`, at 161.
- `web/e2e-online/session/leave.spec.ts`: L5 `second.close()`, at 342; L6 `signOutGroup(context)`, then `page.close()`, at 366-367.
- `web/e2e-online/support.ts:33` `signOutGroup`.
- The app registers no `pagehide`, `beforeunload` or `unload` handler outside `settings-page.ts:209`. See `web/src/app/session/session-gate.ts:40`.
- The pins:
  - `web/scripts/bounded-waits.test.mjs` pins `boundedClose`'s line (32.6). Branch B updates that pin.
  - `web/e2e/live/helper-waits.spec.ts` has the describe `page.close: the close diagnosis`: a real page of its own `browser.newContext()`, its close replaced by a promise that never settles, then `boundedClose(page, () => 1_000)`.
- Playwright 1.64.1 (read-only): `web/node_modules/playwright-core/lib/server/page.js` (`close`, `_closedPromise`), `.../chromium/crPage.js` (`closePage`) and `.../chromium/crBrowser.js` (`_closePage`, `Target.closeTarget`).

**G4, DW-973: `src/ocutalon/cls/OcuTalon/Test/Docs/ExtractMore.cls`**
- `TestTimeLeft`, at 252-272: elapsed is measured around `ReadSample(stream, "pdf", 6)`, and line 265 asserts `(elapsed > 4) && (elapsed < 15)`.
- `HoldLock`, at 163-173, writes `^OcuTalonTest("ExtractMore", key, "end")` when it releases the lock. That is the split point between the lock wait and the read after it.
- `WaitNode`, at 176, and `WaitEnd`, at 186.
- Read-only product code: `Docs/Extract.cls` `Read`, at 72-118. Its lock wait counts within the timeout, `left` is at least 1, and then `Extractor.Submit("Read", left, ...)`.

**G5, DW-966: `src/ocutalon/cls/OcuTalon/Test/Checks/BeatOutcomes.cls`**
- `TestTellNow`, at 106-108, and `TestAllClearIsGuarded`, at 254-256: `Observe.WaitDeliveries(case.session, 1, WAITDIAGNOSIS)`, then `Quiet(item)`, then `WebNotices`.
- `Quiet`, at 359-370: the decision has reached OutcomeRouter, plus `QUIETWAIT` (4 s).
- `WebNotices`, at 372-380.
- The sibling to extend in shape: the DW-964 fix in `Test/Checks/Heartbeat.cls:201-211`, a poll of `DeliveryRows` for the web channel up to `WAITDIAGNOSIS`.
- The lead's forced row comes from `Test.Data.Fixture`'s Delivery creator. It records the row, and `Clean` deletes it.

**CI recipe: `ci/iris.sh`**
- `class_script`, at 180-190. It prints a `CHK|assert|` line only for `Status'=1`.
- `run_class`, at 194-245, parses the `CHK|` lines.
- `run_classes`, at 292-316; `cmd_shard`, at 369-432; `cmd_class`, at 434-442.
- The retry helpers, at 586-632: `retry_log_of`, `retry_lines`, `retry_count`, `retries_report` and `retries_summary`. The summary strips `live:` from each unit.
- `cmd_live`, at 634-675; `cmd_group`, at 683-721. Only `kind = live` is counted today.
- `%UnitTest`'s `LogMessage` stores an assert with `Action` `LogMessage` and with `Location` mapped to `label+offset^<Class>.cls` (`irislib/%UnitTest/TestCase.cls:712-743`). Whether that offset counts from the declaration line of the method is an inference: the implement stage measures it on its warm stack, as described in the tasks.
- The pins:
  - `docker/tests/test-ci-config.sh`, at 1743-1780 (`verdict_case`, matched line by line) and 2111-2117;
  - `web/scripts/state-wait.test.mjs`, 32.6's bash harness, which cuts regions of `ci/iris.sh`;
  - `web/scripts/e2e-part.test.mjs`, at 485-525;
  - `web/scripts/ci-results.test.mjs`, at 74-80.
- `.github/workflows/ci.yml:133-139` uploads `web/test-results/` only on `failure()`. It is not changed (see Design Notes).

**Contention (Rule 11; the local remote refs, as of plan time):** no `origin/OCT-epic*` branch changes any planned file since its merge-base with `origin/feature/OCT_OcuTalon_MVP` (`ef05d35e`).

## Tasks & Acceptance

**Task 0 (lead; 90 minutes per group, from the spec gate; no source change; it writes only the `### Investigation result` subsections).** The method for every group:
- Read the occurrences with `gh run view --log` / `gh api` (read-only):
  - the `FAIL` and `CLASS` lines, the unit times and the runner's name (the host);
  - the order of the classes before the failing one;
  - how many runs ran at the same time.
- Read the code that the Code Map names.
- The old-code batches of `## Verification` L-G<n> may run inside the timebox as reproduction attempts.
- Record counts, states and times only.
- A cause found in product code gives `product: <evidence>`, and that group's investigation stops there.

**G1, DW-211.**
- Read: run 42454441383, job 128650353188 (`c5a71ed4`, `shards-5`), and run 40209749982 attempt 1. Also read irislib `Ens/Director.cls` `TempStopConfigItem` and `Ens/Job.cls` states.
- Questions:
  - (a) Was the alive job the one from before the restart, or a new start? The `refused '= before` assertion passed or failed, and that answers it.
  - (b) What were its `State` and `Status`?
  - (c) Does Ens start a refused item again by itself?
  - (d) Does the product runner's refused `OnInit` end its job? If it does not, the result is `product:`.

**G2, DW-639.**
- Read the post-39.10 occurrences, which name TelegramIn with row 0, flag 1 and jobs none: 42442077870, 42475836390 and 42353010024. Also read `live_park_telegram` and the lane-b classes that touch TelegramIn's rows and runtime flag.
- Questions:
  - (a) Is row 0, flag 1 and no job the parked state that something leaves behind (which class, and how)?
  - (b) Why is it intermittent?
  - (c) Is it the product `NotRunning()` that misreports an item whose `Enabled` row is 0? Then the result is `product:`. The Planner report then also offers the test-side option: read `RunnerFixture.NotRunningNow` at 612, the DW-591 sibling. That is a check-line change, which is the Planner's call.
  - (d) Is it a transient that ends on its own?

**G3, DW-774 close.**
- Read:
  - the close diagnosis at `57b1acec` (run 42464338633, job 128680241418);
  - run 42480549642 (`f6290959`), and runs 42425470320 and 42419117439;
  - the kept traces, in place on the runner's host (`$HOME/ocutalon-traces/<tag>/online-session/`; ci-b is runners 3-8, ci-c 9-14, ci-d 15-20);
  - Playwright's close path (Code Map).
- Questions:
  - (a) Does the trace show the close action with no end?
  - (b) Did the page close later, at the context's teardown?
  - (c) What does the close wait on: `Target.closeTarget` not acted on, a `targetDestroyed` that never came, or a handler?
  - (d) Why does the stall follow the CSP group sign-out in both L5 and L6?

**G4, DW-973.**
- Read: run 42495328974, job 128776327087 (15.89 s); run 42507818397 (15.16 s); `Docs/Extract.cls` `Read`; `Docs/Extractor.cls` `Submit`; irislib `%SYSTEM/WorkMgr` Wait timeout.
- Questions:
  - (a) How much of the elapsed time is the lock wait (the `end` node), and how much comes after it?
  - (b) Does `Submit` return at `left` (1 s), or about 10 s later? Where does that time go: the worker start, a Python import, or the cleanup?
  - (c) Was the answer correct (`timed_out`), and is the late part platform scheduling on a loaded host (that is evidence for a bound), or product code (`product:`)?

**G5, DW-966 (measure first).**
- Run each of `TestTellNow` and `TestAllClearIsGuarded` once, on old code, with a second channel's Delivery row for `case.session` recorded first. The row comes from `Test.Data.Fixture`, through a scratch edit that is reverted byte-identical.
- The result is `race shown` (Branch A: build A5) or `race not shown`. The latter means no change, and DW-966 is declined, with the measurement as its evidence.

Write the five groups' results (G1 to G5) into `### Investigation result` before the implement spawn. For each B group, also name the stall injection that the proof uses.

**Common tasks (always built).**
- C1, DW-911: `web/e2e/support/bounds.ts`.
  - `reportRetry(step, lines: readonly string[] = [])` appends the `RETRY` line, and then each line of `lines` that matches `^DIAG [ -~]{1,300}$`, to the log file.
  - Stdout is unchanged.
  - Update the header.
- C1, `web/e2e/support/floor.ts`: compute the retry-time `pageSideLines` before `reportRetry`, put them through `redactLine`, and pass them to it. The `printDiagnosis` call stays.
- C2, DW-911: `ci/iris.sh`.
  - Add `retry_diag_lines <name>`.
  - `retries_report` prints the `RETRY` lines, then the `DIAG` lines, then the `RETRIES` line.
  - The counts are unchanged.
  - Update the header paragraph "Retries".
- C3, the one-method run: `ci/iris.sh`.
  - `cmd_class` accepts `<Class>:<Method>`, where the method matches `^Test[A-Za-z0-9]+$` and is a `Method <name>(` line of the class's file.
  - `class_script` takes the spec. `CHK|compiled|` checks the class part, and `RunTest(":<Class>:<Method>", ...)` runs the method.
  - The `CLASS` line names the spec.
- C4, `web/scripts/state-wait.test.mjs`:
  - harness cases for C2, covering the order and the count, and a non-`DIAG` line that is not printed;
  - cases for C3, covering a valid method, an unknown method and a malformed spec;
  - C1's append, through a temporary `OCUTALON_E2E_RETRY_LOG`.
  - The harness also cuts `class_script`, `cmd_class` and `run_class`.

**Common diagnostics (built for every group whose result is not `product:`).**
- D1, G1, `Runners.cls`: `AssertRefused`'s "has no alive job" and "names it as not running" messages append `RunnerFixture.StateOf(item)`.
- D4, G4, `ExtractMore.cls`: line 265's message holds the split as `(lock <s> s, after the release <s> s)`, taken from the holder's `end` node.

**Branch B, ObjectScript plumbing (built when G1, G2 or G4 is B).**
- B0, `ci/iris.sh`.
  - `class_script` also writes `CHK|retry|<Location>|<Description>` for each assert whose `Action` is `LogMessage` and whose `Description` starts `RETRY ` or `DIAG `.
  - `run_class` maps `<Location>` (`label+offset^<Class>.cls`) to the file line: the line of the method's declaration in `src/*/cls/<Class path>.cls`, plus the offset, as measured. It prints and appends the lines (matrix rows 1 and 4).
  - `cmd_shard` and `cmd_class` remove the stale retries file of `shard-<arg>` or `class-<spec>` (`@`, `,` and `:` become `_`), and print `RETRIES <n> in shard:<arg>` or `class:<spec>` before their `SHARD`/`RUN` line, when n is above 0.
  - `cmd_group` counts `shard` units as it counts `live` ones. `retries_summary` maps each `<kind>:<unit>` to its file, with one helper.
  - The implement stage measures the offset semantics: it runs one warm class that logs a planted `$$$LogMessage` in a scratch edit, reverted byte-identical, and records the mapping under `## Verification`.
- B0, `web/scripts/state-wait.test.mjs`: planted `CHK|retry|` lines:
  - mapped against a real class file of the repo;
  - an unmappable location gives `:0`;
  - a bad shape is dropped;
  - the shard count and the group detail.

**Branch B per group.** B1 and B3 split an existing bound B: the retry fires at `floor(B/2)`, and the rest of B is the retry's wait. B2 and B4 guard a check that runs once and has no bound to split, so their one retry runs after the first miss, in the window stated for each:
- B1, G1, `Runners.cls` `AssertRefused`. Unsettled at 60 s:
  - `$$$LogMessage("RETRY AssertRefused the refused start ends")`;
  - `$$$LogMessage("DIAG "_item_": refusal row "_found_", alive jobs "_n_"; "_StateOf(item))`;
  - then `RunnerFixture.Restart(name, 0)` once, then the poll goes on to the same deadline.
- B2, G2, `Heartbeat.cls:612`. When the one read names an item:
  - `RETRY TestAfterAllTestsNothingSaved the production runs every item`, and a `DIAG` line holding the missing items and `StateOf`;
  - then one more read, after a poll of up to `RECORDSECONDS` for `NotRunning() = ""`.

  This poll is the retry's window: the read had no wait before, and `RECORDSECONDS` is the class's own existing number. The assertion and its message are unchanged.
- B3, G3:
  - `diagnose.ts`: add `closeTargetAgain(page)`. Through `page.context().newCDPSession(page)` it gets the page's own `Target.getTargetInfo`; through `browser.newBrowserCDPSession()` it sends `Target.closeTarget`; it detaches both. It is bounded by `PROBE_BOUND_MS` and never throws, and it gives `sent`, `not measured (not Chromium)` or `failed (<class>)`. Add a line builder that gives `closeDiagnosis`'s lines without printing them.
  - `fixtures.ts` `boundedClose` takes `firstAttemptMs(waitMs())`. At that point, if the page is still open and the close has not settled:
    - `reportRetry('page.close', <redacted close lines>)`;
    - `closeTargetAgain`;
    - then the close settles on the first close or on the page's `close` event.
    The outer `boundedStep(..., waitMs(), 'page.close')` and the `diagnosedAtBound` keep B, the message and the diagnosis at the bound.
  - Rewrite the fourth contract comment.
  - `bounded-waits.test.mjs`: the `boundedClose` pin pins the new line exactly.
  - `helper-waits.spec.ts`, a new describe `page.close: one more close of the page`, with 20 s waits as in 32.6's own-wait cases and `console.log` captured:
    - R1: the first close never settles, and the real `Target.closeTarget` closes the page between 10 s and 20 s. One `RETRY e2e/live/helper-waits.spec.ts:<line> page.close`, the file holds the line and the `DIAG` lines, and `page.isClosed()` is true.
    - R2: both closes are stubbed. It rejects with `^page\.close: no answer within 20 s$`, with one `RETRY` line and the close diagnosis once.
    - R3: a bound under 20 s gives no `RETRY`.
- B4, G4, `ExtractMore.cls` `TestTimeLeft`. When the answer is `0|timed_out` but elapsed is outside `(4, 15)`:
  - `RETRY TestTimeLeft the timed read ends in time`, and `DIAG lock <s> s, after the release <s> s, elapsed <s> s`;
  - then `WaitEnd(holder)`, and the whole hold-and-read once more, with a new holder and fresh nodes.

  The second miss gives today's assertions with D4's message.

**Branch A per group (A1 to A5).**
- Build the fix that the group's result names, in the files it names, inside this story's footprint. A changed bound quotes its evidence.
- Add the pinning test and its `mutation:` line.
- Build none of that group's B task.
- A5 (DW-966, race shown): a private poll of `WebNotices(case.session)` up to `WAITDIAGNOSIS` before each `Quiet`, in the shape of DW-964's loop in `Test.Checks.Heartbeat:201-211`. It replaces the two `WaitDeliveries` calls.

**Acceptance Criteria:**
- **AC0.** Given the spec gate, when each group's 90 minutes end, then its `### Investigation result` holds `cause:` with its evidence and fix, `none_in_timebox` with what was read and ruled out, or `product:` with the evidence that was sent to the Planner. G5 holds the measurement. The implement stage builds only the named branches, and it stops `blocked` when a subsection holds none of these.
- **AC1 (DW-911).** Given a unit with retries, when `ci/iris.sh` reports them, then its `RETRY` lines, its retry-time `DIAG` lines and `RETRIES <n> in <kind>:<unit>` appear in the job log, and the counts and the step summary are unchanged in shape.
- **AC2 (B, ObjectScript).** Given a class that logs a retry, when it runs in a shard or `class` unit, then the `RETRY <Class>:<line> <step>` line names the file line of the call, the `DIAG` lines follow it, and the shard's and the group's `RETRIES` lines count it.
- **AC3 (B per group).** Given a first miss (B1 and B3: unsettled at `floor(B/2)`; B2: a read that names an item; B4: a `timed_out` read whose elapsed is outside `(4, 15)`), when the retry fires, then there is exactly one `RETRY` line and one repeated action (B1 restart, B2 read, B3 re-close, B4 hold-and-read). B1 and B3 settle within B, and B2 within `RECORDSECONDS`. A second miss fails as today, with the step named.
- **AC4 (C3).** Given `ci/iris.sh class <Class>:<Method>`, when it runs, then only that method runs, and the `CLASS` line names it.
- **AC5 (Rule 1 integration, lead).** Given a lane A throwaway, when the injected stall of a B group runs through `ci/iris.sh class` (for ObjectScript) or the helper-waits R1 against a real Chromium (for G3), then the real output shows the `RETRY` line and its `DIAG` lines.
- **AC6 (proof, lead).** Given each group that is fixed (A) or contained (B), when the lead runs L-G<n> under the load harness, then `## Verification` records the old code's red count (plain load, and the injected stall where plain load gives 0) and the fix's 20 of 20 under the same load, with the counts.
- **AC7 (scope).** Given the diff, when it is reviewed, then it holds no product file and no file from the Never list, `src/**` changes only the named classes' wait, timing, retry-log and message lines, and no bound changes without the evidence quoted in its group's result.
- **AC8 (push, lead).** Given the change, when it is pushed, then `bash docker/tests/test-boundaries.sh` passed first, and full CI is green on every workflow.
- Standing (Rule 19): every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

- 2026-11-08 (lead, Task 0): `### Investigation result` filled for G1 to G5. G1 cause (AssertRefused wait), G3 cause (close during the 401 exit to the splash), G4 cause (the post-release part of TestTimeLeft's bound), G5 race not shown (DW-966 to be declined at adjudication), G2 product (`Install.Step.Production.NotRunning()` reads only the runtime flag): G2 stopped and reported to the Planner before any fix (PLANNER REPORT); its branch waits for the ruling.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6).**
- **AD-22:** `ci/iris.sh` stays the one recipe; units run on throwaways; ObjectScript tests stay `%UnitTest` classes sharded by area; no secret reaches an artifact or the log.
- **AD-19:** no key, cookie or token in any line.
- **AD-29:** each test area stays its lane's. The edits are wait lines in other lanes' test classes, as the charter allows.
- **AD-6/AD-7** (G1, runners and the allow-list), **AD-18** (G2, the heartbeat), **AD-21** (G4, the extraction lock and timeout), **AD-14/AD-32** (G5, delivery rows per channel) and **AD-13** (G3, the browser envelope): each is read, never changed.

No AC contradicts an AD's Rule or its Prevents line. No NFR is unmeasurable: the timebox is a duration, and the proofs are counts.

**Rule 1/2.**
- Integration: AC5. The consumers are `ci/iris.sh` `run_class`, `cmd_shard` and `cmd_group`, which read the test's `LogMessage` lines, and `boundedClose`'s callers, which are every fixture page close (L5, L6).
- Consumed-by: CI's `iris` job, through `ci/iris.sh group`; the lead's proofs.
- Consumes: 32.6's `retry_lines`, `retries_report`, `retries_summary`, `reportRetry`, `retryLocation`, `firstAttemptMs`, `diagnosedAtBound`, `closeDiagnosis`, `probeBrowser`, `redactLine` and `pageSideLines`; `RunnerFixture.Restart`, `StateOf` and `NotRunningNow` (read); `Test.Data.Fixture` (the lead's forced row).
- Extends, never copies:
  - the ObjectScript retry rides on `%UnitTest`'s own `LogMessage` and 32.6's file and counting, and needs no new class;
  - `closeTargetAgain` sits beside `probeBrowser`;
  - B3 reuses `firstAttemptMs` and `reportRetry`;
  - A5 follows the DW-964 loop, as a private method of BeatOutcomes, because the only shared home, `Test.Core.Observe`, is contended (Epic 41, `Core/**`);
  - C3 extends `cmd_class` and `class_script`.

**Ledger (Rule 17).** Every entry is addressed:
- DW-211: Task 0 G1, D1, B1 or A1.
- DW-639: Task 0 G2, B2 or A2. A `product:` result goes to the Planner.
- DW-774 (the close half): Task 0 G3, B3 or A3.
- DW-973: Task 0 G4, D4, B4 or A4.
- DW-966: Task 0 G5, A5 when the race is shown. Otherwise the result declines it with the measurement.
- DW-911: C1 and C2.

Nothing is declined at plan time.

**Decided in-stage.**
1. **DW-911 prints; it does not upload.** The retry-time `DIAG` lines go into the retries file and are printed by `ci/iris.sh`. Uploading the whole `web/test-results/` of a green job would ship more than is needed. So `ci.yml` stays unchanged: the Planner's permission to change it is not used.
2. **The ObjectScript location is mapped in bash, from the `Location` of `%UnitTest`.** A new helper class under `src/**` would break the AC "nothing under `src/**` beyond the named classes' wait and timing lines".
3. **Shard and class retries share 32.6's file scheme** (`web/test-results/<kind>-<unit>-retries.txt`), so the step summary and the failure artifact carry them unchanged.
4. **B2's window is `RECORDSECONDS`.** The read had no wait, and no new number is introduced. If the state is the parked row-0 state, the retry cannot help, and the second miss reports it honestly.
5. **The G3 retry re-sends `Target.closeTarget`, Chromium only.** A second `page.close()` would wait on the same close (32.6's inference). A re-sent CDP close is a real second attempt, and whether it closes the page is itself evidence about where the stall is.
6. **C3, the one-method `class` run, is common.** Without it, Heartbeat (140-206 s for each class run) and Runners cannot get 20 runs inside the 150 s per-call rule.
7. **The proofs' load for ObjectScript** is 32.6's burn block alone (`LOAD_BURN` busy loops on the host and in the Docker VM), wrapped around one warm one-method run. Live units are not used.
8. **The epic context is reused**, as the dispatch asked: no planning file is newer. The continuity story is 32.6.

**Risk.**
- As in 32.6, plain local load may not reproduce any of the groups. The injected stall then carries the old red, and its counts are recorded.
- G2 is likely `product:` (the ledger names the product `NotRunning()`).

**Expected CI cost (inference).** Nothing changes when no test retries. B3's cases in `live:sign-in-2` add about 45 s (`shards-4`).

### Investigation result

#### G1 (DW-211)
_(lead, Task 0, 2026-11-08 20:00Z to about 20:15Z; timebox to 21:30:52Z)_

**Result: cause: AssertRefused's poll ends on the first instant the three conditions hold, but Ens starts the refused item once more after that (a deferred UpdateProduction), and the re-reads catch that second refused start alive.**
- 3 occurrences, each attempt 1 and green on rerun: 40209749982 (ci-13, class 35.93 s, only "not running" failed); 42454441383 job 128650353188 (ci-18, 41.96 s, "no alive job" and "not running"); new, 42461088729 job 128670335503 (`1cb64cdf`, ci-5, 41.58 s, only "no alive job").
- The wait did not time out. In 34 passing Runners runs (failed shard jobs) the class took 35.81-46.27 s, and every failed run took under 46 s. A missed 120 s poll takes at least 120 s, so the poll read `settled` = true and the next reads differed. The ledger's "past WAITSECONDS" is wrong.
- (a) A new start. The event-log assertion and `refused '= before` passed in all 3. The 3 patterns are one transient job caught at different points between the two reads: it registers Alive, it is Alive, then it ends.
- (b) Not logged: there is no StateOf in the messages, and the logs do not say whether line 258 or 270 failed. From Ens source: during OnInit the job is State Alive with a status outside DEADSTATUSES, and its interim `X` row is State Starting.
- (c) Yes, Ens does. `findProductionDifferences` starts any enabled item that has fewer jobs than its pool. An update that finds a changed checksum (SDS rows feed `ModifiedSettings`) sets `pToUpdateScheduler`, which sends an async request to Ens.ScheduleHandler (auto-added), and that handler runs one more UpdateProduction. Which call started the job in CI is not measured: no event log was kept. (inference) It is this deferred update. No product code updates the production on this path.
- (d) Yes, the refused job ends. The adapter's OnInit returns the error, and `Ens.Job` Start goes to Exit (LOGERROR, a Dead ghost row, UnRegister). So this is not `product:`.
- Fix (A1, wait lines of `AssertRefused` only; WAITSECONDS, the assertions and the messages unchanged): `settled` also needs (1) no Ens.Job row of the item in State Starting or Alive; (2) Ens.ScheduleHandler idle (queue empty, no active message, e.g. `RunnerFixture.Idle`); (3) all of this on 2 polls in a row. Plus D1.
- Proof injection (throwaway scratch, reverted): when the poll first sees the three conditions, call `Ens.ScheduleService.CallScheduleService()`, then wait up to 10 s for an Alive job of the item. Old code: red (inference: every run). Fix: it settles after the second start ends. Plain load gives a window of only milliseconds (inference).
- Note: `gh run view --job` returned attempt 2's log. Use `gh api .../jobs/<id>/logs`.

#### G2 (DW-639)
_(lead, Task 0, 2026-11-08 20:00Z to about 20:15Z; timebox to 21:30:52Z)_

**Result: product: `NotRunning()` reads only Ens's runtime flag, so it names TelegramIn, whose SDS row 0 makes its effective Enabled 0**
- Runs (lane-b, image): 42442077870 attempts 1 and 2 (the rerun was red too) and 42475836390. Each gives one FAIL: `TelegramIn row 0, runtime flag 1, jobs none`. Run 42353010024 predates 39.10 and names no item.
- Order: classes run alphabetically, and Heartbeat is the 81st. The other runs differ by 1-4 classes, none of them Telegram classes. The failing method runs first in its class (`%UnitTest.Manager` 1340-1365), right after `OnBeforeAllTests`, whose `UpdateProduction(60)` and `WaitAllRun` (`NotRunningNow`) succeeded.
- (c) Yes. Ens takes effective Enabled from the SDS row when one exists (`Director` `getProductionItems` ~1084, `EnableConfigItem` 1572-1580, `Item.Checksum`). Row 0 means the item is not meant to run. `NotRunning()` (154-177) checks only `$$$ConfigIsEnabled`, while `Runners` in the same file honours the row. `TelegramParked` pins this divergence (DW-591).
- (d) Not a transient (inference from code). Ens writes `IsEnabled` and `Checksum` only when it registers an item (Director 1347-1348). An update with an unchanged checksum and job count leaves the item alone. The state survived the successful update just before the read, so B2's poll would not clear it (Design Note 4 agrees).
- (a) No lane-b class before Heartbeat writes the flag. Its writers are `TelegramParked` (lane-a) and `DocumentsApi` (after Heartbeat, its own item). Only `PersonaAnswers` (LiveCase `Enable`/`Disable`) and the stack-start park toggle TelegramIn. Both restore row 0 and wait until there is no job; neither touches the flag. How Ens comes to hold flag 1 with a row-0 checksum is unmeasured (inference: a row write inside another update).
- (b) The order is fixed, so the cause is timing (inference). Durations show no signal: PersonaAnswers took 20.75-21.45 s red and 20.94-21.07 s green.
- Options for the Planner:
  1. Product fix in Epic 19's `Install/Step/Production.cls`: `NotRunning()` skips items whose Enabled row is 0.
  2. Test-side check-line change at `Heartbeat.cls:612`: read `RunnerFixture.NotRunningNow` (the DW-591 sibling) and keep the message at 613. `Restore` (180) is exposed the same way. This is a check-line change, not a wait line, so it is the Planner's call.
- Proof injection: on a parked stack, set `$$$ConfigIsEnabled("TelegramIn")=1` before the read. The old check goes red; `NotRunningNow` stays green.

#### G3 (DW-774, page.close)
_(lead, Task 0, 2026-11-08 20:00Z to about 20:15Z; timebox to 21:30:52Z)_

**Result: cause: the test closes the page while the page's own 401 exit to the splash is in flight; the group sign-out just before starts that exit, and Chromium does not act on that close (inference for the mechanism)**

- Read: 4 failed jobs (L6 on ci-d 15 and 17 and on ci-b 5; L5 on ci-c 12), with units of 454-508 s. The 2 ci-d traces were read in place. The older runs kept none.
- (a) Yes. In both traces `Page.close` (`leave.spec.ts:367`, after `signOutGroup` at 366) has a `before` and no `after`.
- The timeline from the start of the sign-out GET, trace 1 / trace 2, in ms:
  - the page's `/events` poll gets a 401: +5 / +19;
  - the page requests the splash document: +15 / +31;
  - `Page.close` is sent: +39 / +37;
  - the splash's first subresource: +45 / +51.
  - So the close is sent inside the navigation in 2 of 2 traces.
- (b) Not measurable: the trace ends before the teardown. `Close context` took 11 ms with no error.
- (c) The close waits only on `closedPromise`, which `Target.detachedFromTarget` resolves. Before `Target.closeTarget` it waits only on coverage and screencast clients, and this config has neither.
  - No handler: there is no `dialog` event, and the app adds `beforeunload` only on the settings page.
  - At +30 s the target was alive: a fresh CDP session answered in 23 ms. So `Target.closeTarget` was not acted on, and the cause is not a lost `targetDestroyed`.
- (d) Both lines close a page whose CSP session a group sign-out has just ended. Its next poll (1 s delay) gets a 401, and the page leaves with `location.replace`. L6: the test's own `signOutGroup`. L5: the first page's `IRISLogout=end` ends the session of `second` too, since the two share cookies (inference: no L5 trace).
- Fix (A, test only): close only a page that has settled.
  - L6: close before `signOutGroup`, or first wait for the `Sign in and start` button and `waitForLoadState('load')`.
  - L5: the same wait on `second` before it closes.
  - Not `landedOnSplash`: it asserts the plain address, which was not measured for a 401 exit.
  - No bound changes.
- Proof: hold the splash document with a route for about 2 s after the 401, and close inside that hold. The old code should go red, and the fix should pass 20 of 20 under load. If the hold does not reproduce the stall, the result falls back to `none_in_timebox` and B3.
- B3 is sound by the code. A second `page.close()` sends nothing and only awaits `closedPromise`. A `Target.closeTarget` re-sent from a browser session settles the first close once the target detaches.

#### G4 (DW-973)
_(lead, Task 0, 2026-11-08 20:00Z to about 20:15Z; timebox to 21:30:52Z)_

**Result: cause: `< 15` leaves about 10 s after the 5 s hold for the 1 s wait plus the stop of the busy worker. 19.6 measured that stop at 6 to 10 s loaded (2.3 s quiet); sibling `Test.Docs.Extract` TestTimeLimit (same path, timeout 1) bounds it at 20 s.**

- (c) The answer was right: each miss has one `FAIL`, the elapsed line (15.89, 15.16). `0|timed_out` passed, since `class_script` prints only failed asserts. Class times were 47.60 s and 46.90 s, inside the green range of 44.85 to 49.96 s (5 runs), so nothing hung.
- Load: 26 and 23 self-hosted jobs ran at the misses (9 and 5 on the host of the miss), against 18 at the 3 green runs read in the same window.
- (a) The CI message has no split. From the code, the lock part is about 5.0 s: `HoldLock` releases 5 s after `held`, and `began` comes after `held` is seen. That leaves about 10.2 s and 10.9 s after the release (inference).
- (b) `left` = 1, and `Submit` honours it with `WaitOne(left)`, which returns at 1.00 s (19.6 M3). Then `Clear(0)` runs: per irislib `AbstractWorkMgr`, a `DeleteGroup` with timeout 0 that stops the worker busy in Python, then a new `CreateWorkers`. `Kill queue` runs a second `DeleteGroup` (`DeleteTimeout` 1), then come `ReleaseGroupLocks` and the file delete. Measured in 19.6: `Clear(0)` takes 1.3 s quiet, and the stop takes 6 to 10 s from the call at load average 8 to 13. The worker start and the import are inside the 1 s wait. The source of `%SYS.WorkQueueMgr` is not in irislib.
- Not product: `Read` and `Submit` honour `left`, and the cleanup is AD-21's chosen stop. The 15 s is a test bound added in 19.7's review (DW-928), not a product target. The AC is pinned by the `timed_out` assert: with `timeout` in place of `left`, that assert goes red, not the bound.
- Fix (A4, `TestTimeLeft` timing lines only): take the split from the holder's `end` node (the D4 message). Keep `elapsed > 4` and keep the lock part `< 15`. Bound the part after the release at `< 20`, TestTimeLimit's bound for the same 1 s Submit and stop. Evidence: the two misses above (answer right, more load) and 19.6's loaded stop of 6 to 10 s.
- Mutation: `Hang 21` after `ReadSample`, in a scratch copy, turns the new bound red.
- Decided here: the split on CI is an inference. The AC6 proof must show it in D4's message under load. If the lock part is the late part, G4 falls back to B4.

#### G5 (DW-966, measurement)
_(lead, Task 0, 2026-11-08 20:00Z to about 20:15Z; timebox to 21:30:52Z)_

**Result: race not shown: with a phone Delivery row forced first, both tests read the one web row and passed; DW-966 is declined, no change.**

- Setup: old code (HEAD), one lane A warm throwaway. A scratch edit put `Fixture.Delivery(session, {"Channel": "phone"})` before `Start` in both tests (in `TestAllClearIsGuarded`, the session is made first and passed to `Start`). It also recorded the Delivery rows before the wait, after `WaitDeliveries` and after `Quiet`. The file was restored byte-identical (`cmp` OK; `git status --short` and `git diff --stat` the same as before).
- Run: `class OcuTalon.Test.Checks.BeatOutcomes`, the whole class, because `class` cannot run one method yet. Passed in 28.29 s with no FAIL or SKIP line.
- Rows in ID order, the same for both tests: the forced phone row, then the product's own phone `tellnow` row, then the web `tellnow` row, all in the same second.
- `WaitDeliveries` returned after 0.024 s (`TestAllClearIsGuarded`) and 0.0004 s (`TestTellNow`). The web row was already there before the wait (3 rows, 1 web). `Quiet` took 4.01 s in each test, and the rows did not change during it.
- Asserted after the wait, all of it green:
  - `TestTellNow`: exactly 1 web row, `web|tellnow`, and its text is `notice.tellNow` with the beat's subject and the first reason;
  - `TestAllClearIsGuarded`: exactly 1 web row, with no "everything is fine", and its text is `notice.tellNow` with the second reason.
- Finding: the product records its own phone row before the web row even without the forced row. So the wait already returns on a non-web row in every run, and forcing one changes nothing. What keeps the web count correct is `Quiet` (the decision at OutcomeRouter, plus `QUIETWAIT` 4 s), and here the web row came well inside it.
- Not measured: what happens under CI load. If the web row ever came more than 4 s after OutcomeRouter, the red would come from `Quiet`'s bound, not from the order of the rows.

## Verification

The setup for every command:
- Run from the worktree, after `git rev-parse --show-toplevel` matches it, with `env | grep ^OCUTALON_` printing nothing.
- One command per foreground call, with `timeout: 600000`, sized to about 150 s.
- One test runner per call. No IRIS MCP call and no slot.
- `<laneA>` stands for `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=32 stage=<stage>'`.
- The warm tag is `e32s7iw` for implement and `e32s7pw` for the lead. Start with `<laneA> OCUTALON_RUN_TAG=<warm tag> ci/warm.sh up` once, and end with `ci/warm.sh down`, also after a failure.
- For a pass with fewer branches, drop the names that the built branches do not include.

**Commands:**
1. `(loop)`, about 10 s: `node --test web/scripts/state-wait.test.mjs web/scripts/retry-bounds.test.mjs web/scripts/bounded-waits.test.mjs web/scripts/e2e-part.test.mjs web/scripts/ci-results.test.mjs`. Expected: all pass.
2. `(loop)`, B3 only: `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/helper-waits.spec.ts --project sign-in-2 --grep 'one more close of the page|the close diagnosis')`. Expected: all pass, with no stack.
3. `(loop)`: `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/helper-waits.spec.ts --project sign-in-2 --grep-invert 'one more close of the page|the close diagnosis')`. Expected: all pass. Split it by `--grep` if it nears 150 s.
4. `(loop)`, about 35 s: `bash docker/tests/test-ci-config.sh`. Expected: every rule passes.
5. `(loop)`, warm, one per call, for each class this pass changed (built tasks only):
   - `<laneA> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e32s7iw ci/iris.sh class OcuTalon.Test.Agent.Runners:TestStartRefused`;
   - `... class OcuTalon.Test.Schedule.Heartbeat:TestAfterAllTestsNothingSaved`;
   - `... class OcuTalon.Test.Docs.ExtractMore:TestTimeLeft`;
   - `... class OcuTalon.Test.Checks.BeatOutcomes:TestTellNow`, then `:TestAllClearIsGuarded`.

   Expected: each prints `CLASS ... passed` and no `RETRY`.
6. `(once)`: `npm --prefix web run lint`, then `bash docker/tests/test-boundaries.sh`. Expected: exit 0.
7. `(once)`: `npm --prefix web test`. Expected: exit 0. If it nears 150 s, run `node --test` over `web/scripts/*.test.mjs` in two halves.
8. `(once)`: lines 3 and 2 again, in that order, then the line 5 runs in reverse order. Expected: all pass.
9. `(once)`: `git diff --stat -- . ':(exclude)_bmad-output'`. Expected: only the files of the built tasks.

**Mutations (Rule 19).** For each: apply it, observe red, restore byte-identical, and write a `mutation:` line here.
- AC1: `retries_report` without the `DIAG` lines → `state-wait.test.mjs` goes red.
- AC1: `reportRetry` drops `lines` → its append case goes red.
- AC2: `run_class` without the offset → the mapping case goes red.
- AC2: `cmd_group` skips `shard` units → the count case goes red.
- AC3, B3: skip `closeTargetAgain` → R1 goes red at 20 s.
- AC3, B3: give the second wait a fresh B → R2 goes red.
- AC3, B1, B2 and B4 (lead's stall runs): remove the repeated action → the stall run goes red.
- AC4: `class_script` ignores the method → the one-method case goes red.
- A1 to A5: the mutation that the result's pinning test names.

**Lead-side (`(lead)`; after implement, unless stated).**
- **Scratch and load.**
  - `SCR=<scratchpad>/e32s7proof`.
  - `$SCR/loaded.sh <cmd...>` starts `LOAD_BURN` host loops and `LOAD_BURN` `docker run -d --rm --cpus 1 --name e32s7burn-<tag>-<i> <mock image> node -e 'for(;;){}'` containers, runs the command, and removes all of them in an EXIT trap. This is 32.6's burn block. It is never committed.
  - After each batch, `docker ps -aq --filter name=e32s7burn` is empty.
  - `LOAD_BURN` is 4, or 8 at most (the Mac is shared with the other lanes).
- **L-G1, L-G2, L-G4** (ObjectScript, B or A):
  - 20 calls of `$SCR/loaded.sh env <laneA> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e32s7pw bash ci/iris.sh class <Class>:<Method>` on the old class (`git show <story_base>:<path>` put in place from the lead's backup, then restored byte-identical, with `git status --short` checked). Record `old: <red> of 20`.
  - If that is 0: the same 20 with the group's injected stall, recorded as `stall old: <red> of 20`.
  - Then 20 calls on the fix under the same load, plus the stall: `fix: <passed> of 20, <n> RETRY`.
  - AC5's real-runtime evidence is one stall run's `RETRY`/`DIAG` lines.
- **L-G3:**
  - `$SCR/loaded.sh` around `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/helper-waits.spec.ts --project sign-in-2 --grep 'R1' --repeat-each 5 --workers 4)` on the old `web/e2e/support/` files: `stall old`, expected 20 of 20 red at the bound.
  - Then the same on the fix: `stall fix: 20 of 20, 20 RETRY`.
  - A plain-load L5/L6 run (`ci/iris.sh live online-session`) runs only if one call fits in about 150 s. Measure that first with one process.
- **L-G5:** the Task 0 measurement. When A5 is built, the forced-row run is the old red (`old: <red> of 20`) and the fix must pass 20 of 20 with the forced row.
- **L-fresh (Rule 19):**
  - on a fresh throwaway, `<laneA> OCUTALON_RUN_TAG=e32s7pf ci/iris.sh class <Class>:<Method>` for each changed method, one per call, forward and then reversed, each followed by its teardown;
  - lines 1 to 3, forward and then reversed.
- **L-ci:** after the push, full CI is green on every workflow. Record each group's `RETRIES` line.

**Shared surfaces:**
- `run_class`'s stdout (new lines only on a retry);
- `cmd_shard`'s and `cmd_class`'s stdout;
- `cmd_class`'s argument shape;
- `class_script`'s IRIS lines;
- `cmd_group`'s `RETRIES` detail, which now counts `shard` units;
- the retries files in `web/test-results/` (new `shard-*` and `class-*` names, and `DIAG` lines);
- `reportRetry`'s signature;
- `boundedClose`'s line and its pin in `bounded-waits.test.mjs`;
- the close-diagnosis line set;
- sign-in-2's case list (helper-waits).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (HALT after planning).**
- What the plan holds:
  - Task 0 for the lead, with five investigation groups, a reading list and questions for each, and a `product:` stop outcome;
  - the common tasks: DW-911 printing (C1, C2) and the one-method `class` run (C3, C4);
  - per-group diagnostics (D1, D4);
  - Branch B: the ObjectScript `RETRY` plumbing through `%UnitTest` `LogMessage` (B0), and the retries B1 to B4;
  - Branch A, generic, with A5 named for DW-966.
- All six ledger entries are addressed, and none is declined at plan time.
- `ci.yml` is not changed: DW-911 prints the lines instead of uploading them.
- The footprint extensions to report:
  - `web/scripts/state-wait.test.mjs`;
  - `web/e2e/live/helper-waits.spec.ts`;
  - in B3, `web/scripts/bounded-waits.test.mjs` (one pin).
- `Runners.cls` (Test/Agent, Lane A) is named for the lead's contention check against Epic 41.
