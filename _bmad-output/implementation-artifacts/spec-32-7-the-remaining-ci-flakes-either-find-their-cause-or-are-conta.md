---
title: 'Story 32.7: The remaining CI flakes either find their cause or are contained, logged'
type: 'chore'
created: '2026-11-08'
status: 'done'
baseline_revision: '7a11682032eec394ad6d4356a8a95921a6355b1f'
baseline_commit: '7a116820'
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

**Build list (the lead, after Task 0 and the Planner's ruling `planner-2026-11-08-32.7`; binding for the implement stage).** Build exactly these; build NO Branch B task (B0 to B4) and no A5:
- C1 to C4 (DW-911, by printing in `ci/iris.sh`; `.github/workflows/ci.yml` stays untouched) and C3 (the one-method run).
- D1 (G1) and D4 (G4).
- A1, G1, DW-211, `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls` `AssertRefused`, wait lines only: `settled` also requires no `Ens.Job` row of the item in State Starting or Alive and `Ens.ScheduleHandler` idle (through the existing `RunnerFixture.Idle` or its sibling; extend, do not copy), both true on 2 polls in a row. `WAITSECONDS`, the assertions and their messages stay (plus D1).
- A2, G2, DW-639 (approved check-line change): `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` line 612's check reads `RunnerFixture.NotRunningNow` instead of the product `Install.Step.Production.NotRunning()`, and the message at 613 is kept; the same change at `Restore` (about line 180). Never touch `Install/Step/Production.cls` (the product fix is DW-978, a later story).
- A3, G3, DW-774 page.close: `web/e2e-online/session/leave.spec.ts` close lines only. L6: before `page.close()`, after `signOutGroup(context)`, wait for the page's exit to the splash to finish (the `Sign in and start` control visible, then `waitForLoadState('load')`), or close before the sign-out where the test's intent allows; L5: the same wait on `second` before `second.close()`. Do not use `landedOnSplash` as it is (it asserts the plain address). `boundedClose`, its bound and its diagnosis stay unchanged.
- A4, G4, DW-973: `src/ocutalon/cls/OcuTalon/Test/Docs/ExtractMore.cls` `TestTimeLeft` timing lines only: take the split from the holder's `end` node (D4); keep `elapsed > 4`; keep `< 15` on the lock wait; bound the part after the release at `< 20` (the sibling `Test.Docs.Extract` `TestTimeLimit`'s bound for the same path; evidence in G4's result, confirmed by the lead's proof).
- Each A task gets its hermetic pinning test where one is possible without a stack and its `mutation:` line; the lead runs the stack proofs (below).
- Lead proofs (not the implement stage), lane A throwaways, old code red and the fix 20 of 20 under load, recorded under `## Verification`: G1, a scratch injection that calls `Ens.ScheduleService.CallScheduleService()` when the poll first settles; G2, on a parked stack TelegramIn's runtime flag set to 1 before the read (old check red, `NotRunningNow` green); G3, a route that holds the splash document about 2 s after the 401 with the close inside the hold; G4, the class under the CPU-burn load with D4's split read (and `Hang 21` after `ReadSample` as the new bound's mutation). A group whose proof does not confirm its cause falls back to its B task in a further pass.

- [x] [Smoke] G3 fallback (lead proof L-G3: old 0 of 120 red under the held-splash stall, so the cause is not confirmed; `planner-2026-11-08-32.7`): build **B3 exactly as specified under "Branch B per group"** — `diagnose.ts` `closeTargetAgain(page)` and the close-lines builder; `fixtures.ts` `boundedClose` at `firstAttemptMs(waitMs())`: if the page is still open and the close has not settled, `reportRetry('page.close', <redacted close lines>)`, `closeTargetAgain`, then settle on the first close or the page's `close` event; the outer `boundedStep(..., waitMs(), 'page.close')` and `diagnosedAtBound` keep B, the message and the diagnosis; rewrite the fourth contract comment; the `bounded-waits.test.mjs` `boundedClose` pin pins the new line exactly; `helper-waits.spec.ts` describe `page.close: one more close of the page` with R1 to R3. The Build list's "build NO Branch B task" is lifted for B3 only. Keep A3's splash wait in `leave.spec.ts`. Write each pinning test's `mutation:` line.

- [x] [CI] iris(shards-4) live:sign-in-2: `web/e2e/live/state-retry.spec.ts:41` "the file holds that line" red on `c21f64fd` (ci run 42541161624): since C1 (DW-911) the retry file holds the `RETRY` line followed by its retry-time `DIAG` lines, while the pin still expects the `RETRY` line alone — https://github.com/jbrandtmse/OcuTalon/actions/runs/42541161624 — fix by option (ii), the narrower one (orchestrator, 2026-11-09): the pin reads the file's `RETRY` lines only and expects exactly `[retry]`, and every other line of the file must match `^DIAG [ -~]{1,300}$` (as tight as before: no other shape allowed); C1's writer and `ci/iris.sh` stay as built. Check that `RETRIES` per unit and per group counts `RETRY` lines only when the unit's file also holds `DIAG` lines (a `state-wait.test.mjs` case if none pins it yet), with a demonstrated mutation for each changed pin. Search `web/e2e/**` and `web/scripts/**` for any other reader that pins a retry file's exact content and treat it the same way.

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

### Review Findings

_(code review, 2026-11-08, first review; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 21 rows, 16 entries after grouping: 4 patch, 0 decision-needed, 0 defer, 12 rejected. Each entry: severity, fix-risk, footprint, disposition.)_

- [x] [Review][Patch] close-settled C-1/C-2 start the `/splash` wait after `goto` returns, so a splash request that comes before it (the page asks about 150 ms after its script runs) is missed and the case times out on a loaded host (edge+verification-gap; medium, fix-risk low: the promise moves before the navigation; in-story) [web/e2e/live/close-settled.spec.ts:126]
- [x] [Review][Patch] The DIAG writer/reader agreement case compares `[]` with `[]` for every refused candidate, because the writer drops them before the file exists: the reader's refusal of tab, control, DEL and CR lines was pinned by nothing (verification-gap; medium, Rule 19 unfalsifiable assertion, fix-risk low; in-story). Added a raw-file case that writes the one-line refused candidates straight into the unit's file; mutation line under `## Verification` [web/scripts/flake-fixes-behaviour.test.mjs:184]
- [x] [Review][Patch] Near-copied test helpers with no stated reason (Rule 2): the `.cls` method cutter and repo reader in `flake-fixes-sources.test.mjs:16-22` and `flake-fixes-behaviour.test.mjs:21-27`, and the bash function cutter in `state-wait.test.mjs:422` and `flake-fixes-behaviour.test.mjs:163,188` (acceptance-auditor; medium, fix-risk low: pure move, suite green; in-story). Moved to the new `web/scripts/repo-sources.mjs` (`readRepo`, `clsMethod`, `shellFunction`), which the three files import [web/scripts/repo-sources.mjs:1]
- [x] [Review][Patch] The L-G3 `(lead)` proof line was B3's (helper-waits `--grep 'R1'` on the old `web/e2e/support/` files): as built it matches only 32.6's `loadedAfter` R1 and would record "old red, fix green" from C1's changed expectation, not from page.close; the Build list's held-splash proof had no runnable line (acceptance-auditor; medium, fix-risk low; in-story, tracking section). Restated for A3 through the QA stand-in, with the red criterion, the fallback to B3 and the L5/L6 `--grep` pass-through [spec `## Verification` L-G3]

**Rejected** (with the Rule 15 disposition each takes):
- low, by-design (fix-risk med): A1's `Ens.Job:Enumerate` loop near-copies `RunnerFixture.Jobs`, and its Alive half overlaps the `Jobs(item)` term (blind+acceptance). `RunnerFixture` is on the Never list, so `Jobs` cannot gain the Starting state; the sibling the spec names, `Idle`, is reused.
- low, by-design (fix-risk med): `AssertRefused` passes without a sign when its poll reaches the deadline unsettled (blind+edge). A1 keeps "WAITSECONDS, the assertions and their messages"; a new assertion or `$$$LogMessage` is outside it. The three assertions still re-read and fail loudly on a live job, and QA's stack run settled in 11.73 s. Reopens only through a spec amendment; probe: a CI `TestStartRefused` run of 120 s or more.
- low, wontfix-accepted (fix-risk med): close-settled cuts `closeSettled` out of leave.spec.ts and strips its types with `node:module` `stripTypeScriptTypes`, which prints an ExperimentalWarning (blind). Exporting the helper would move it outside A3's "leave.spec.ts close lines only"; CI's Node 24 has the API. reopen_if=a Node upgrade under which close-settled.spec.ts fails before its first case on `stripTypeScriptTypes`.
- low, wontfix-accepted (fix-risk low): `closeSettled`'s empty `catch` leaves no line when the page never reaches the splash (blind). Not spec-clear: A3 names close lines only, and DIAG content is constrained. reopen_if=a CI L5/L6 failure whose log cannot tell a page that never left from a close stall.
- low, by-design (fix-risk med): `closeSettled` can add up to 30 s plus 60 s (the action and navigation defaults), not 30 s (acceptance). A3 names the two waits with no bound, so they take the project defaults and no number changes; the test timeout still bounds the test.
- low, wontfix-accepted (fix-risk low): Heartbeat `Restore`'s error names the missing items without `StateOf` (blind). The message is unchanged from before the story, and neither D1 nor D4 covers it. reopen_if=a CI OnAfterAllTests "does not run every item after the tests" failure that the item names alone do not explain.
- low, wontfix-theoretical: `released` could come after `finished` (edge). That needs more than 1 s between HoldLock's `Lock -` and its next `Set`, while the reader runs its 1 s Submit and its stop. Even then, every bound is judged on true facts (`elapsed > 4` unchanged). It would become real if a D4 message showed a negative "after the release".
- low, by-design: with two or more retries, the DIAG lines are not tied to their own RETRY (edge). Matrix row DW-911 prints the RETRY lines, then the DIAG lines, then the count.
- false: `cmd_class` says `unknown test class` for a bad method (blind). Matrix row "One-method run" prescribes exactly that, with exit 2.
- false: the spec says `done` while the story is in review (blind+acceptance). The frontmatter `status:` is build-auto's machine state, and the story's state is sprint-status. The fix would also edit the spec.
- false: `Restore`'s `NotRunningNow` hides Enabled-0 items (edge). That is A2, approved by the Planner: an item whose Enabled row is 0 is not meant to run.
- false: `src/**` lines go beyond AC7's line kinds (acceptance). The `$$$AssertTrue` wraps the new end-node wait, which is a wait line; without it A4's split would be vacuous. The comment lines document the changed waits (Rule 14).

### Review Findings (rework 1)

_(code review, 2026-11-08, re-review of rework 1 (B3), diff `e1b344b8` plus the working tree; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all at the session's model (`full-opus`); 28 rows, 17 entries after grouping: 4 patch (1 medium, 3 low), 0 decision-needed, 0 defer, 13 rejected; no high. Each entry: severity, fix-risk, footprint, disposition.)_

Checklist `[Smoke] G3 fallback`: confirmed fixed. B3 is built as "Branch B per group" specifies: one logged re-close at `floor(B/2)` (`firstAttemptMs`, Chromium only, B of 20 s or more) through `closeTargetAgain`, at most one per close; a second miss rejects `page.close: no answer within <B> s` with the close diagnosis once (R2); the outer `boundedStep(..., waitMs(), 'page.close')` and `diagnosedAtBound` keep B; no bound changed; the retry-time lines go through `lines.map(redactLine)` and `reportRetry`'s DIAG filter, the re-close line through `printDiagnosis`; the `bounded-waits.test.mjs` pin pins the new `boundedClose` line in full; R1 to R3 present (plus R4, R5); A3's `closeSettled` kept at leave.spec L5 and L6. No product file, no Never-list file, no absolute local path.

- [x] [Review][Patch] `closeTargetAgain` used a session or a target that answered after its bound: a page or browser session that opened after the timeout was never detached, and `Target.closeTarget` could still be sent after `DIAG page.close re-close failed: TimeoutError` was printed, so the containment's only evidence could say "failed" for a re-close that went out (blind+edge+verification-gap+acceptance; medium, fix-risk low: an `over` flag set in `finally`, checked after each await, a late session detached at once; in-story). New R4 case `a session or a target that answers after the bound is not used`; mutation line under `## Verification` [web/e2e/support/diagnose.ts:494]
- [x] [Review][Patch] R5 set no test timeout of its own, so its path through `closeWithOneMore` (and its `reject(error)` mutation) held only while the project timeout left 20 s after the clean-up reserve (verification-gap; low, fix-risk low: `test.setTimeout(60_000)` as R1 to R4; in-story) [web/e2e/live/helper-waits.spec.ts:927]
- [x] [Review][Patch] Two comments overstated or misdescribed: `diagnose.ts`'s header named only "a refusal" as printing the re-close line (it also prints `TimeoutError` and `not measured (not Chromium)`), and the new describe's comment said every page's close never settles (only R1 and R2; R3, R4 and R5 differ) (blind; low, fix-risk low, comment-only; in-story) [web/e2e/support/diagnose.ts:56]
- [x] [Review][Patch] Matrix row "Close, no retry" for a page that closes before `floor(B/2)` had no `mutation:` line, and the verification-gap layer held R3's quick half unable to fail (verification-gap; low, Rule 19 missing mutation line, closed in-pass): the clause is falsifiable through R3 as a whole (the stray timer's `RETRY` lands in its 19 s half); mutation applied, observed red, restored byte-identical, line written under `## Verification` [web/e2e/live/helper-waits.spec.ts:863]

**Rejected** (with the Rule 15 disposition each takes):
- low, wontfix-accepted (fix-risk low): R3 (not Chromium) settles its stub close at 11 s, 1 s after the retry timer, so the gate mutation is caught only while the retry path ends inside 1 s (blind+verification-gap). With a Firefox-named type the browser probe is unmeasured and the renderer probe is a millisecond read, and the gate mutation was observed red. reopen_if=a rerun of the gate mutation (`!== 'nothing'`) that leaves R3 (not Chromium) green.
- low, wontfix-accepted (fix-risk low): the fixture's print of a refused or timed-out re-close is pinned by a source regex, not by a run through `boundedClose` (verification-gap; the self-review's Blind 2). The regex has a mutation line and R4 runs `describeReclose` and `closeTargetAgain`; a run-through case costs about 20 s of `live:sign-in-2`. reopen_if=a CI log with `RETRY ... page.close`, the bound's failure and no `DIAG page.close re-close` line while R4 is green.
- low, wontfix-accepted (fix-risk low): B3's cases add about 70 s to `live:sign-in-2`, above the plan's 45 s inference (blind+acceptance). An inference, not a target; the cases are the spec's R1 to R3 with their 20 s bounds. reopen_if=`live:sign-in-2` reaches its split threshold or a CI run passes REL-4's 35 minutes with these cases in the margin.
- low, by-design: R1 stubs the first close, so Playwright's own close is never in flight when the re-close is sent (verification-gap). That is the spec's R1 ("the first close never settles"); the real stall was not reproduced (L-G3 0 of 120), and AC5 and AC6 are the lead's runs.
- low, by-design: two concurrent `page.close()` calls on one page give two `RETRY` lines (edge). Each close is its own wait, and the Boundaries allow one retry per wait; no caller closes a page twice at once.
- low, wontfix-theoretical: a page that closes while `closeTargetAgain` runs can print `re-close failed: TargetClosedError` (edge). The line reports the re-close attempt truly; it would become real if a CI log showed that line for a page that the first close had closed.
- low, wontfix-theoretical: the page's `close` event is listened to from the start, so a first close that rejected after the event would resolve (acceptance). Playwright resolves a close whose target is gone; it would become real if a Playwright upgrade made `page.close` reject after `close` fired.
- low, wontfix-accepted (fix-risk low): `ci/iris.sh` and `bounds.ts` headers name only 32.6's snapshot retry (blind). They state what 32.6 added and stay true; the close retry's contract is fixtures.ts's fourth contract, and `ci/iris.sh` counts every `RETRY` line. reopen_if=a later story reads the iris.sh header as the list of retried steps.
- low, wontfix-accepted (fix-risk low): the test restores leave own-property copies (`newBrowserCDPSession`, `browserType`) on the worker's browser (verification-gap; the self-review's Edge 7). They behave as the originals, and each test wraps the copy again. reopen_if=a later test in the same worker that asserts on the browser object's own properties.
- low, wontfix-accepted (fix-risk low): the triage log's "Review pass (rework 1, B3; follow-up pass)" heading reads as an independent review (blind). It is build-auto's own review section, and the fix edits the spec under review. reopen_if=a gate reads the build-auto triage log as the code-review record.
- false: the spec says `done` while the story is in review, and `baseline_commit` is short (blind+edge+acceptance). The same as the first review: the frontmatter `status:` is build-auto's machine state, the story's state is sprint-status, and the short sha resolves.
- false: `closeTargetAgain`'s comment says a page that does not answer cannot hold the request, though the target id comes from the page's session (blind). `Target.getTargetInfo` on a page session is answered by the browser's Target domain, not by the renderer, and the close itself goes through the browser session (R4 pins the split).
- false: the retry decision reads `capToDeadline(boundMs)` and not `waitMs()` (acceptance; the self-review's Intent 5). The outer `boundedStep` caps the same bound the same way, so the retry fires at half of the bound in force.

### Review Findings (rework 2)

_(code review, 2026-11-09, re-review of rework 2 (the `[CI]` state-retry pin), diff `7a116820` plus the working tree; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all at the session's model (`full-opus`); 13 rows, 8 entries after grouping: 2 patch (low), 0 decision-needed, 0 defer, 6 rejected; no high, no medium. Each entry: severity, fix-risk, footprint, disposition.)_

Checklist `[CI]` iris(shards-4) live:sign-in-2 `state-retry.spec.ts:41`: confirmed fixed (pending the next head's CI run, the case needs a stack). Option (ii) as ruled: the pin's RETRY-shaped lines (the `ci/iris.sh` `retry_lines` shape) equal exactly `[retry]`, every other line matches `^DIAG [ -~]{1,300}$`, the file ends with a newline; `bounds.ts` and `ci/iris.sh` are not in the diff; `RETRIES` per unit and per group counts RETRY lines only, pinned by `state-wait.test.mjs` (`cmd_live prints the RETRY lines, then the DIAG lines, then the count, which holds only the RETRY lines`; `cmd_group counts and summarises the RETRY lines only, whatever DIAG lines follow them`; 39 of 39 pass); the other readers of a retry file (`helper-waits.spec.ts` R1/R2 and the close-retries file, `retry-bounds.test.mjs`, the `state-wait` and `flake-fixes-behaviour` stand-ins) already expect C1's content. The pin's block, run as written, is GREEN on the real retries file of CI run 42541161624. No product file, workflow, `ci/units.sh`, release tool, bound or absolute local path; no line can carry a cookie name or value that the scan does not check (AD-19/AD-22).

- [x] [Review][Patch] The live pin no longer showed that DW-911's DIAG lines reach the file, nor that the RETRY line comes first: a file holding the RETRY line alone, or its DIAG lines before it, stayed green, while the header and the inline comment say the file holds the RETRY line and, after it, the first miss's page-side lines (blind+edge+acceptance; low, fix-risk low: two assertions, evidenced by the real CI file; in-story). Added `the RETRY line comes first` and `the file holds the page-side line of the first miss`; mutation lines under `## Verification` [web/e2e/live/state-retry.spec.ts:48]
- [x] [Review][Patch] Two rework-2 `mutation:` lines were ambiguous or overstated: the DIAG boundary did not say whether 300/301 counts the `DIAG ` prefix, and the cookie-loop mutation was shown by a source-text simulation, not by running the loop (blind+verification-gap; low, Rule 19 stale mutation line, closed in-pass): both re-shown by executing the spec's own lines, observed red, lines corrected and added under `## Verification` [spec `## Verification`]

**Rejected** (with the Rule 15 disposition each takes):
- low, wontfix-accepted (fix-risk med): the secrets scan's `fileLines` half sees nothing that `logged` does not on today's path, since `floor.ts` passes the same `redactLine`d lines to `reportRetry` and `printDiagnosis`, and the file-side redaction is pinned only by `flake-fixes-sources.test.mjs`'s source regex (verification-gap). Today's page-side lines are built from counts, states and error classes (the real file holds no free text); a planted-secret stand-in case in `helper-waits.spec.ts` is beyond option (ii) and outside this rework's range. reopen_if=a retry-time page-side line built from free text (a URL, a header or an error message), or a CI retries file holding a line that the unit's printed DIAG lines do not.
- low, wontfix-accepted (fix-risk low): the live case was not run on a stack in this pass, and its mutations were shown off the live run (blind+acceptance+verification-gap). The "copy may differ" half is refuted: the harnesses execute the block cut from the live spec's own text, GREEN on the real CI file. reopen_if=the next head's CI run of `live:sign-in-2` reds on `state-retry.spec.ts`.
- low, wontfix-accepted (fix-risk low): the spec keeps its own copy of `retry_lines`'s RETRY shape, and no test ties the two (edge+acceptance; Rule 2: a copy with a reason, as the self-review recorded: `bounds.ts` and `ci/iris.sh` stay as built). A narrowing of `ci/iris.sh` reds the `state-wait.test.mjs` cases whose RETRY lines use the real line's characters, and `retry-bounds.test.mjs` checks the shell shape against the writer. reopen_if=a change of either shape that leaves this spec and `state-wait.test.mjs` green on a line the shell does not count.
- low, wontfix-accepted (fix-risk low): the rework-2 summary says no other reader "pins its exact content", though `helper-waits.spec.ts` R1/R2 do pin exact bytes (that already hold the DIAG lines) (blind). The meaning holds (no reader pins the pre-C1 RETRY-only content; the acceptance layer's search found every reader aligned with C1), and the fix edits the spec's build summary. reopen_if=a reader of a retry file found red against C1's content.
- low, wontfix-accepted (fix-risk low): the new `dev_complete` cycle-log row gives `0_high,0_med` without the low and false counts (blind). The cycle log is the lead's record, not this review's to write. reopen_if=a gate that reads the low or false counts from a `dev_complete` row.
- low, wontfix-theoretical: the secrets list reads the context's cookies at the end, so a value rotated before then is not checked (edge). Unchanged by this rework; the CSP session cookie is not rotated within the case. It would become real if the sign-in rotated the session cookie after the retry.

## Spec Change Log

- 2026-11-09 (lead, rework iteration 2, trigger ci): CI story red on `c21f64fd` (state-retry.spec.ts:41 exact-file pin vs C1's DIAG lines); fixed by option (ii), the pin reads RETRY lines only (orchestrator ruling).
- 2026-11-08 (lead, rework iteration 1, trigger smoke/proof): G3's cause was not confirmed by its proof; B3 (the single logged re-close) is built per the Planner's fallback, A3 kept. G1, G2, G4 confirmed.
- planner-2026-11-08-32.7 (the Contest Planner under the owner's delegation, relayed by the orchestrator, 2026-11-08 about 20:2xZ): DW-639 option (2) APPROVED inside 32.7: `Heartbeat.cls:612`'s check reads `RunnerFixture.NotRunningNow` with the message at 613 kept, and the same at `Restore` (:180); proof on a parked stack with TelegramIn's flag set to 1 (old red, new green), then 20 of 20 under load. The product fix (option 1) is NOT in 32.7: ledgered as DW-978 (`owner=burndown`, its own story later); `Install/Step/Production.cls` is never touched. DW-211, DW-774's page.close half and DW-973: the fixes as described in `### Investigation result` APPROVED, each with its proof (old red, fix 20 of 20 under load); DW-973's post-release bound is 20 s, as `TestTimeLimit`. A group whose proof does not confirm its cause falls back to the single logged retry. DW-966: declined (no race; G5), closed terminal. DW-911: the DIAG lines go in `ci/iris.sh`; `.github/workflows/ci.yml` stays untouched (`ci_yml_hunk: none`). One push at the end, after the integrate-forward onto the newest green feature head; the release-tool freeze holds. AC7's "wait, timing, retry-log and message lines" is widened by this ruling to A2's two check lines only.
- 2026-11-08 (lead, Task 0): `### Investigation result` filled for G1 to G5. G1 cause (AssertRefused wait), G3 cause (close during the 401 exit to the splash), G4 cause (the post-release part of TestTimeLeft's bound), G5 race not shown (DW-966 to be declined at adjudication), G2 product (`Install.Step.Production.NotRunning()` reads only the runtime flag): G2 stopped and reported to the Planner before any fix (PLANNER REPORT); its branch waits for the ruling.

## Review Triage Log

### 2026-11-08 - Review pass
- verdicts: 19 findings - high 0, medium 1, low 15, false 3, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1: TestTimeLeft no longer bounds `elapsed` from above (total up to 35 s) - A4 states exactly this split (`elapsed > 4`, lock `< 15`, after the release `< 20`), approved by the Planner ruling; altering it alters specified behaviour.
  - `[low]` `[patch]` Blind 2: the result of `WaitNode("left", "end", 10)` is ignored, so the post-release bound is vacuous when the end node never comes - the call is now an AssertTrue ("the holder set its end node when it released the lock"); pin and `mutation:` line updated.
  - `[low]` `[reject]` Blind 3: `reportRetry` drops DIAG lines over 300 characters or non-ASCII - the shape is the spec's (`^DIAG [ -~]{1,300}$`); the page-side lines R1 and R2 write are in shape (checked on the stack-free cases).
  - `[low]` `[reject]` Blind 4: DIAG lines print after all RETRY lines and are not in the step summary - the order and the unchanged summary are matrix row DW-911 and Design Note 1.
  - `[false]` `[reject]` Blind 5: the one-method run is covered only by stubbed shell tests - the three warm one-method runs on the lane A throwaway ran `RunTest(":Class:Method")` through `%UnitTest.Manager` and printed `CLASS <spec> passed`; an inherited method is outside the spec (a `Method <name>(` line of the class's file).
  - `[low]` `[reject]` Blind 6: A1-A4 pinned by regexes over source text - falsifiable (each has a mutation line that goes red); the behavioural proof is the lead's AC6 stack proof, which the spec assigns to the lead; no stack-free test of an ObjectScript wait exists.
  - `[low]` `[reject]` Blind 7: `closeSettled` swallows every error - the wait is bounded by the online projects' 30 s `actionTimeout` and the close below it stays the bounded, diagnosed step; best effort is the A3 text ("or close before the sign-out").
  - `[low]` `[patch]` Edge 1: `WaitNode` result ignored in TestTimeLeft - same root cause as Blind 2; patched together.
  - `[low]` `[reject]` Edge 2: a failed `Ens.Job:Enumerate` Execute counts as no starting job, and a missing ScheduleHandler row spins to the deadline - the same pattern as `RunnerFixture.Jobs` and `Idle`, which the spec names; the handler row is present on the production, and the quiet runs settled in about 10 s.
  - `[low]` `[reject]` Edge 3: over-long or non-ASCII DIAG line dropped - same as Blind 3.
  - `[false]` `[reject]` Edge 4: `closeSettled`'s waitFor uses the default timeout - the online projects set `actionTimeout: 30_000` (`ONLINE_WAITS`), so it is bounded.
  - `[low]` `[reject]` Edge 5: `class_method_ok` rejects an inherited Test method - the spec defines the method as a `Method <name>(` line of the class's file; the error line names the shape.
  - `[low]` `[reject]` Edge 6: nothing bounds `elapsed` from above - same as Blind 1.
  - `[low]` `[reject]` Verification-gap 1: A1-A4 pinned only by source-text assertions - same as Blind 6.
  - `[medium]` `[patch]` Verification-gap 2: the redaction at `floor.ts`'s `reportRetry` call is pinned by no test (AD-19) - `flake-fixes-sources.test.mjs` pins `retryLines.map(redactLine)` at the call and the unchanged `printDiagnosis`; mutation line added (removing the map goes red).
  - `[low]` `[patch]` Verification-gap 3: TestTimeLeft's `< 20` term acts without the end node - same as Blind 2.
  - `[low]` `[reject]` Verification-gap 4: nothing checks that real page-side lines stay within 300 characters - R1 and R2 write the real four page-side lines to the file and compare them; a longer line would fail them on the stack.
  - `[low]` `[patch]` Intent 1: `class_method_ok` sits before `cmd_class`, outside the "between `traces_prune` and `cmd_live`" zone the Boundaries name - moved to just before `cmd_live`; `bash -n`, the node tests and `test-ci-config.sh` pass.
  - `[false]` `[reject]` Intent 2: no Branch B, no ObjectScript RETRY plumbing, no G5 change, no Investigation text in the diff - the Build list excludes B0-B4 and A5 by the Planner's ruling; the Investigation result is in the spec, not the diff.

### 2026-11-08 - Review pass (rework 1, B3; follow-up pass)
- verdicts: 25 findings - high 0, medium 1, low 17, false 5, maybe-false 2
- findings:
  - `[low]` `[patch]` Blind 1: the fixtures comment says the retry-time lines are not printed, but a refused or unmeasured re-close prints one `DIAG page.close re-close ...` line (matrix row "Close retry") - the fourth contract comment now says so.
  - `[low]` `[patch]` Edge 6: the same root cause as Blind 1 (a lone re-close line in stdout) - patched with it.
  - `[low]` `[patch]` Edge 8: the same root cause as Blind 1 (the comment's claim) - patched with it.
  - `[low]` `[reject]` Blind 2: the fixture's turning of a failed re-close into a printed line is pinned by a source regex only - the line is in the matrix, R4 runs `describeReclose` and `closeTargetAgain` on stand-ins, and the regex has a mutation line.
  - `[low]` `[reject]` Blind 3: the retry can outlive the bound - the timer fires at B/2 (10 s at the least) and its probes and the re-close are bounded at 2 s each, so it ends before B.
  - `[low]` `[reject]` Edge 2: the retry can report after the bound error - the same timing as Blind 3.
  - `[low]` `[reject]` Edge 3: the `close` listener stays on a hung page - released with the page when the failed test closes its context.
  - `[low]` `[reject]` Blind 4: a failed `closeLines` logs a bare RETRY - `closeLines` throws only when a page read does; the RETRY line is the count and the second miss prints the full diagnosis.
  - `[false]` `[reject]` Blind 5: `waitMs()` is read twice and `unmeasured` is dead - both reads sit in one synchronous expression, and `unmeasured` is `closeTargetAgain`'s own contract for any caller (R4 runs it).
  - `[false]` `[reject]` Blind 6: no lead proof for B3 - the spec assigns the stack proofs (AC5, AC6) to the lead, not to the implement stage; R1's 10 s to 20 s margin is the bound itself.
  - `[maybe-false]` `[reject]` Edge 1: `Target.closeTarget` can answer `{success:false}` and be reported as sent - not shown for Chromium, and the fix adds a branch for an unshown state (low if true).
  - `[low]` `[reject]` Edge 4: `close({runBeforeUnload: true})` is re-closed without beforeunload - the re-close fires only after a hang of 10 s or more of a close that has not settled, and the one caller (`deadline-cap.spec.ts`) has a 1 s bound.
  - `[false]` `[reject]` Edge 5: a close line over 300 characters is dropped by `reportRetry` - by design, the spec's `^DIAG [ -~]{1,300}$` shape.
  - `[low]` `[reject]` Edge 7: `restoreBrowser` leaves a bound copy of `newBrowserCDPSession` on the worker's browser - the next test wraps that copy, so wrappers do not stack, and it is replaced again after each test.
  - `[medium]` `[patch]` Gap 1: no test makes the first close reject, so `reject(error)` could become `resolve()` unseen and a real close failure would be swallowed - R5 added, with a mutation line.
  - `[low]` `[reject]` Gap 2: the `ended || page.isClosed()` guard after the probes has no test - the effect of its absence is one spurious RETRY line in a window of at most 2 s, and a test needs a close inside the probe window.
  - `[low]` `[patch]` Gap 3: the non-Chromium gate of `closeWithOneMore` (matrix row "Close, no retry") is pinned only by source text - R3 (not Chromium) added, with a mutation line.
  - `[low]` `[patch]` Gap 4: `closeTargetAgain` does not detach its sessions on the timeout path although its comment says it does - the detach moved out of the inner async, R4 asserts it on the timed-out path.
  - `[low]` `[reject]` Gap 5: R1 and R2's wall-clock margins are 4 s to 6 s on a loaded host - the bounds are the retry's contract (10 s to 20 s, 20 s to 26 s) and the run has no stack.
  - `[false]` `[reject]` Intent 1 (no stack proof): AC5 and AC6 are the lead's proofs, outside this pass.
  - `[low]` `[reject]` Intent 2: the re-close is sent after the retry-time probes, up to 2 s after B/2 - the order is the spec's (reportRetry, then closeTargetAgain), and the send is still inside B.
  - `[maybe-false]` `[reject]` Intent 3 (the re-close travels the path that Playwright's own close uses): not decidable without the real stall (L-G3 did not reproduce it); the spec records B3 as a containment and the lead's runs decide.
  - `[false]` `[reject]` Intent 4 (R2 swallows the re-close instead of a browser that ignores it): that is the spec's R2 ("both closes are stubbed").
  - `[low]` `[reject]` Intent 5 (the retry decision uses `capToDeadline(boundMs)`, the matrix says `waitMs()`): the cap is `firstAttemptMs`'s own input, shared with 32.6's retries, and the outer bound stays `waitMs()`.
  - `[low]` `[reject]` Intent 6 (a close that ends during the probes logs no RETRY, a case the matrix does not list): the matrix row "close before `floor(B/2)`" implies it, and the guard keeps the count honest.

### 2026-11-09 - Review pass (rework 2, state-retry pin; follow-up pass)
- verdicts: 14 findings (blind 4, edge 4, verification-gap 2, intent 4) - high 0, medium 0, low 12, false 2, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind 1 / Edge 1: the cookie-name and cookie-value check scanned `logged` only, so a secret in a DIAG line of the retries file (the file `ci/iris.sh` prints into the job log) would pass the shape check - the loop now scans `[...logged, ...fileLines]`; hermetic mutation line added under `## Verification`.
  - `[low]` `[reject]` Blind 2 / Edge 2 / Edge 3 / Edge 4: the pin requires neither a DIAG line nor the RETRY line first - the ruling is "RETRY lines only, exactly `[retry]`, every other line DIAG-shaped, no other shape allowed", which the pin states; the writer's append and order are pinned by `helper-waits.spec.ts` R1 and the `state-wait.test.mjs` writer cases, and the page-side line is asserted in `logged`; the ruling defines "as tight as before" as "no other shape allowed" (the old exact-bytes pin could not hold the DIAG lines C1 writes); an extra order/presence assert would be unrun on a stack in this pass and beyond the ruling. reopen_if=a CI log where `reportRetry` stops appending DIAG lines while R1 and `state-wait.test.mjs` stay green.
  - `[low]` `[reject]` Blind 3 / VG 2 / Intent 2 (shape duplication): the spec holds its own copies of `retry_lines`'s RETRY shape and `RETRY_DIAG_LINE` - exporting the latter edits `bounds.ts`, which the ruling keeps as built; a drifted copy fails closed (a conforming line goes red, noisily). reopen_if=a change of either source shape that leaves this spec green on a line the source refuses.
  - `[false]` `[reject]` Blind 4: the header still says the RETRY line is appended - the header already says "appended to the file ... with the first miss's page-side lines", and the new inline comment states the file's contents.
  - `[low]` `[reject]` VG 1: the live pin stays green when no DIAG line is written - same as Blind 2; the stand-in cases carry it.
  - `[low]` `[reject]` Intent (file shape versus the printed shape): the pin reads the file, not `retries_report`'s output - the printed order and count are pinned by `state-wait.test.mjs` (`cmd_live prints the RETRY lines, then the DIAG lines, then the count ...`, `cmd_group counts ... RETRY lines only`) and `flake-fixes-behaviour.test.mjs`; the open item names the file pin.
  - `[low]` `[reject]` Intent (the label "the file holds that line" now checks the RETRY-shaped lines): the label stays true of the one RETRY line and the next assertion names the DIAG rule; no harm named.
  - `[false]` `[reject]` Intent (live versus hermetic): the live project runs the case in CI; the item asks for a pin fix, not new coverage.
  - Mutation wording from VG (the three file expressions were shown on a scratch copy, not on the live spec): taken into the `mutation:` lines; no finding.

## Design Notes

**Ruling (the Planner, `planner-2026-11-08-32.7`).** G2's product cause stays out of this story (DW-978); the test-side check-line change A2 is approved. `Declined DW-966: race not shown (G5's measurement); closed terminal at the ruling.`

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

**Mutation results (implement stage; each applied in the tree, observed red, restored with `cmp` identical and `git status --short` unchanged).**
- mutation: AC1, `retries_report` without its `retry_diag_lines` call → `state-wait.test.mjs` red (`cmd_live prints the RETRY lines, then the DIAG lines, then the count`, 1 of 39).
- mutation: AC1, `reportRetry` with its `diag` filter replaced by an empty list → `state-wait.test.mjs` red (the 2 append cases) and `helper-waits.spec.ts` R1 red (`the RETRY line, then the retry-time page lines`).
- mutation: AC4, `class_script`'s `RunTest` given the class part of the spec only → `state-wait.test.mjs` red (`checks the class part for compilation, runs the method, and names the spec on the CLASS line`, 1 of 39).
- mutation: A1, `'starting` removed from `settled`, or the `Idle("Ens.ScheduleHandler", 0)` term removed, or `steady > 1` changed to `steady > 0` → `flake-fixes-sources.test.mjs` red (1 of 10 each).
- mutation: A2, `Restore`'s check put back to the product `NotRunning()` → `flake-fixes-sources.test.mjs` red (1 of 10).
- mutation: A3, `closeSettled(page)` put back to `page.close()` at L6 → `flake-fixes-sources.test.mjs` red (1 of 10).
- mutation: A4, `afterSeconds < 20` changed to `< 30` → `flake-fixes-sources.test.mjs` red (1 of 10); and `Hang 21` after `ReadSample` on a warm throwaway (`ci/iris.sh class OcuTalon.Test.Docs.ExtractMore:TestTimeLeft`) → `failed`, `FAIL TestTimeLeft: ... (29.54 s in all; lock 5.01 s, after the release 24.53 s)`; restored, the next run passed.
- mutation: C1/AD-19, `floor.ts` passing `retryLines` to `reportRetry` without `.map(redactLine)` → `flake-fixes-sources.test.mjs` red (1 of 11).
- mutation: A4, the `AssertTrue` on `WaitNode("left", "end", 10)` put back to a bare call → `flake-fixes-sources.test.mjs` red (1 of 11).

**QA stage (QA; gap-closing tests, no stack except one warm one-method run; each mutation applied in the tree, observed red, restored with `cmp` identical and `git status --short` unchanged).**
- (QA) `web/scripts/flake-fixes-behaviour.test.mjs` (new, node `--test`, 14 cases, about 9 s, picked up by `npm --prefix web test`): A4's boundaries evaluated on the class's own Set lines and condition (15.89 s and 15.16 s pass; lock 15 s, after the release 20 s and elapsed 4 s fail; the end node absent falls back to the old bound; `Set finished` is taken before the node wait); the fixture calls of A1/A2 exist with their arity (and `Idle(item, 0)` checks once); `reportRetry`'s writer and `retries_report`'s reader agree on the DIAG shape for 22 candidate lines (lengths 0, 1, 300, 301; control, DEL and non-ASCII characters; embedded newline and CR; a forged RETRY line); `class_method_ok` against the repo's real class files; the real `ci/iris.sh class <bad spec>` exits 2 with the unknown test class line before any runtime.
- (QA) `web/e2e/live/close-settled.spec.ts` (new, Playwright, sign-in-2 project through `e2e/live`, 3 cases, about 5 s, local Chromium only): A3's hermetic stand-in. It cuts `closeSettled` out of `leave.spec.ts` as written and runs it on a page that is answered 401 and `location.replace`s to a splash that the stand-in holds for 1.5 s. C-1: the close comes after the splash document was served and with no splash request held. C-2: the close comes after the splash page's own image was served (`load`), though its button showed before that. C-3: a page that does not leave is closed after the default wait and the helper does not throw.
- (QA) Command: `node --test web/scripts/flake-fixes-behaviour.test.mjs`; `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/close-settled.spec.ts --project sign-in-2)`, also 3 times with `--repeat-each 3` (9 of 9, three runs). Then lint, `docker/tests/test-boundaries.sh`, `docker/tests/test-ci-config.sh` and `npm --prefix web test` (1621 of 1621) pass.
- (QA) Stack evidence for A1 (the residual risk of the Auto Run Result: an `Ens.ScheduleHandler` that never idles would run the poll to 120 s): one warm throwaway (`e32s7q1`, lane A, torn down, `docker ps -a --filter name=e32s7` empty), `ci/iris.sh class OcuTalon.Test.Agent.Runners:TestStartRefused` gave `CLASS ... passed 11.73s`, with two `AssertRefused` polls, so `Idle("Ens.ScheduleHandler", 0)` does turn true on a running production; it is also a real run of C3 (only that method ran, the `CLASS` line names the spec).
- mutation: A4, `(afterSeconds < 20)` changed to `(afterSeconds < 30)` in `ExtractMore.cls` → `flake-fixes-behaviour.test.mjs` red (`fails the part after the release at 20 s, and passes it just below`).
- mutation: A4, `Set finished = $ZHorolog` moved after the `WaitNode("left", "end", 10)` call → `flake-fixes-behaviour.test.mjs` red (`takes the end time right after the read, before the wait for the node`).
- mutation: A4, `(lockSeconds < 15)` changed to `< 25` → `flake-fixes-behaviour.test.mjs` red (2 cases).
- mutation: A3, the `Sign in and start` wait removed from `closeSettled` → `close-settled.spec.ts` red (C-1, C-2 and C-3).
- mutation: A3, `waitForLoadState('load')` removed → `close-settled.spec.ts` red (C-2 only).
- mutation: A3, the `try`/`catch` of `closeSettled` removed → `close-settled.spec.ts` red (C-3 only).
- mutation: AC1/C1, `RETRY_DIAG_LINE`'s `{1,300}` changed to `{1,400}` in `bounds.ts` → `flake-fixes-behaviour.test.mjs` red (the 2 agreement cases).
- mutation: AC1/C2, `retry_diag_lines`'s `awk 'length($0) <= 305'` changed to `<= 300` in `ci/iris.sh` → `flake-fixes-behaviour.test.mjs` red (the 2 agreement cases).
- mutation: AC4/C3, `class_method_ok`'s `grep -q "^Method $2("` changed to `"Method $2("` in `ci/iris.sh` → `flake-fixes-behaviour.test.mjs` red (`accepts the Test methods of the three classes ...`; a ClassMethod named Test... is no test).
- mutation: A2, `Parameter FIXTURE` of `Heartbeat.cls` pointed at a class that does not exist → `flake-fixes-behaviour.test.mjs` red (`Heartbeat's FIXTURE names the class that holds NotRunningNow and StateOf`).
- mutation (code review): AC1/C2, `retry_diag_lines`'s reader pattern `'^DIAG [ -~]+$'` loosened to `'^DIAG [[:print:][:cntrl:]]+$'` (it then takes tab, control and DEL bytes) in `ci/iris.sh` → `flake-fixes-behaviour.test.mjs` red (`the reader on its own prints none of the refused one-line candidates that reach its file raw, and every accepted one`, 1 of 15; `state-wait.test.mjs` stays green); restored, `cmp` identical, `git status --short` unchanged.
- mutation (rework 1, B3; each applied in the tree, observed red, restored with `cmp` against a scratch backup identical, `git status --short` and `git diff --stat` unchanged):
  - mutation: B3, `describeReclose(await closeTargetAgain(page))` in `fixtures.ts` replaced by `describeReclose({ kind: 'sent' })` (the re-close skipped) → `helper-waits.spec.ts` R1 red (`page.close: no answer within 20 s`, 20.1 s).
  - mutation: B3, the outer `boundedStep(..., waitMs(), 'page.close')` given `waitMs() * 3 / 2` (the retry's wait gets a fresh bound) → R2 red (`no answer within 30 s` against `20 s`).
  - mutation: B3, `firstAttemptMs(capToDeadline(boundMs).ms)` replaced by `Math.floor(capToDeadline(boundMs).ms / 2)` (a bound of 19 s retries too) → R3 red (a `RETRY` line printed).
  - mutation: B3, `reportRetry('page.close', lines.map(redactLine))` changed to `reportRetry('page.close', [])` → R1 red (the file holds no close-diagnosis lines).
  - mutation: B3/AD-19, `lines.map(redactLine)` changed to `lines` → `bounded-waits.test.mjs` red (`retries a close once at half of the bound, logs the redacted close lines (AD-19) and re-closes the target`).
  - mutation: B3, `boundedClose`'s line put back to `close(options)` in place of `closeWithOneMore(page, close(options), waitMs(), watch)` → `bounded-waits.test.mjs` red (`goes through boundedClose for every page of the context`).
  - mutation: B3, the `if (line !== undefined) printDiagnosis([line], 'close-diagnosis');` line removed → `bounded-waits.test.mjs` red (the same retry case).
  - mutation: B3, `closeTargetAgain` sending `Target.closeTarget` through the page's own session (`own.send`) in place of the browser session → R4 red (both R4 cases; the call list reads `page Target.closeTarget T1`).
  - mutation: B3, `closeTargetAgain`'s `browserType().name() !== 'chromium'` term removed → R4 red (the Firefox stand-in is asked).
  - mutation (code review): B3, `reject(error)` of the first close's rejection in `closeWithOneMore` changed to `resolve()` → `helper-waits.spec.ts` R5 red (the failure is `undefined`, not the close's own error).
  - mutation (code review): B3, the gate `browserType().name() === 'chromium'` in `closeWithOneMore` changed to `!== 'nothing'` → `helper-waits.spec.ts` R3 (not Chromium) red (a `RETRY` line is logged).
  - mutation (code review): B3, the `finally` that detaches the sessions in `closeTargetAgain` removed → `helper-waits.spec.ts` R4 red (both R4 cases: the detaches are missing, on the answered and on the timed-out path).
  - mutation (code review, rework 1): B3, `closeTargetAgain`'s late-answer guards removed (`if (!kept(own)) return late;` and `if (!kept(session)) return late;` put back to `sessions.push(...)`, `if (over) return late;` deleted) → `helper-waits.spec.ts` R4 red (`a session or a target that answers after the bound is not used`: the late page session is not detached, and the late target gets a browser session and a `Target.closeTarget`); restored, `cmp` identical, `git status --short` and `git diff --stat` unchanged.
  - mutation (code review, rework 1): B3, matrix row "Close, no retry" (a page that closes before `floor(B/2)`): `clearTimeout(timer);` removed from `end` and the guard `if (ended || page.isClosed()) return;` removed in `closeWithOneMore` → `helper-waits.spec.ts` R3 (`a bound under 20 s, or a close that ends before half of the bound`) red (`no RETRY line`: the quick close's timer logs `RETRY e2e/live/helper-waits.spec.ts:863 page.close` at 10 s); either one alone stays green, because the other (and the page's `close` event) still stops the retry; restored, `cmp` identical, `git status --short` and `git diff --stat` unchanged.
- mutation (rework 2, state-retry pin; `web/e2e/live/state-retry.spec.ts` needs a stack, so each is shown hermetically on a scratch node copy of the pin's expressions fed with candidate file texts built from the real writer's output; scratch under the e32s7impl3 folder; the live spec was not run):
  - mutation: a writer that appends a non-DIAG, non-RETRY line (`a note`) -> RED on `every other line of the file is a DIAG line`.
  - mutation: a file with two RETRY lines (an `appendFileSync`-level duplicate; a second `reportRetry` call is caught earlier by `exactly one RETRY line`) -> RED on `the file holds that line`.
  - mutation: no RETRY line, a DIAG line of 301 characters after `DIAG `, a missing trailing newline, a blank line -> each RED; a DIAG line of 300 characters after `DIAG ` stays GREEN (the boundary; the whole line is 305, as `ci/iris.sh` cuts it); the unmutated writer output (RETRY, then a DIAG line) -> GREEN.
  - mutation: the cookie loop put back to `logged` only (the pre-patch loop) with a file line holding `CSPSESSIONID` -> GREEN (the leak is missed); with `[...logged, ...fileLines]` -> RED. (Shown here by a source-text simulation, `leak.mjs`; the code review re-ran it by executing the spec's own loop, below.)
- mutation (code review, rework 2; `state-retry.spec.ts` needs a stack, so each is shown by executing the live spec's own lines - the block from `const fileText` to `the file holds the page-side line of the first miss`, then the secrets loop - with `new Function` on candidate file texts, scratch `pin3.mjs` under the e32s7cr3 folder; the unmutated block is GREEN on the real retries file of CI run 42541161624: the RETRY line, then 4 DIAG lines):
  - mutation: a writer that writes the RETRY line alone (no DIAG line) -> RED on `the file holds the page-side line of the first miss`; the first-miss DIAG line dropped from the real file -> RED on the same; the DIAG lines written before the RETRY line -> RED on `the RETRY line comes first`. Each of the three was GREEN under the pin as the implement stage left it.
  - mutation: a DIAG line of 300 characters after `DIAG ` -> GREEN; of 301 -> RED on `every other line of the file is a DIAG line`; a non-DIAG line appended to the real file -> RED on the same.
  - mutation: a file DIAG line holding `CSPSESSIONID`, the loop executed -> RED on `no line holds a cookie name or value`; the loop put back to `logged` only (on a scratch copy of the spec, `sed`) -> GREEN (the leak is missed). The live spec was not edited for any mutation; `cmp` of the spec against its pre-run copy identical, `git status --short` unchanged.
  - mutation: `ci/iris.sh` `retry_lines` changed to a `cat` of the whole file (counting every line) -> `state-wait.test.mjs` and `flake-fixes-behaviour.test.mjs` RED, 7 cases (`cmd_live prints the unit's RETRY lines after its output, then the count, and keeps the unit's exit code`; `cmd_live prints the RETRY lines, then the DIAG lines, then the count, which holds only the RETRY lines`; `cmd_live prints no DIAG line of a file that holds no RETRY line`; `cmd_group counts and summarises the RETRY lines only, whatever DIAG lines follow them`; three writer/reader round-trip cases); restored, `cmp` identical, `git diff --stat` unchanged.
- (QA) Not pinned without a stack: A1's two-polls-in-a-row logic and the `Ens.Job` Starting/Alive read, and A2's `NotRunningNow` against a flag-1/row-0 item, rest on the source pins and the lead's proofs (L-G1, L-G2).

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
- **L-G3** (A3, as built; restated at code review because the B3 form, helper-waits `--grep 'R1'` on the old `web/e2e/support/` files, matches only 32.6's `loadedAfter` R1 and would go red on C1's changed expectation, not on page.close). The stall injection is the Build list's held splash, through the QA stand-in `web/e2e/live/close-settled.spec.ts` (its `/splash` is held `SPLASH_HOLD_MS` after the 401):
  - `stall old`: a scratch edit of `close-settled.spec.ts` (restored byte-identical, `cmp` and `git status --short` checked) with `SPLASH_HOLD_MS = 2_000` and C-1's `await closeSettled(page)` replaced by `await page.close()` (the old L5/L6 close, inside the hold); `$SCR/loaded.sh` around `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/close-settled.spec.ts --project sign-in-2 --grep 'C-1' --repeat-each 20 --workers 4)`. Count as red only a run whose `page.close()` gave no answer (C-1's 30 s test timeout inside the close); a red from C-1's order assertions alone is not the stall. Record `stall old: <red> of 20`. If it is 0, the hold does not reproduce the stall, and G3 falls back to B3 in a further pass (Build list).
  - `fix`: the file as it is, under the same load, `--grep 'C-1|C-2' --repeat-each 10 --workers 4`: `fix: 20 of 20`.
  - A plain-load L5/L6 run, `<laneA> OCUTALON_RUN_TAG=e32s7pl ci/iris.sh live online-session --grep 'L5|L6'` (the arguments reach Playwright through `docker/tests/test-online-session.sh`), runs only if one call fits in about 150 s; measure that first with one process. Otherwise L-ci's runs carry L5 and L6.
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

**Lead proofs, results (2026-11-08 21:39Z to 23:35Z, lane A throwaways; the reviewed tree).**

*L-G1, L-G2, L-G4 (ObjectScript; one warm lane-A throwaway, CPU burners beside it):*

- **(lead) L-G1, L-G2, L-G4 results** (2026-11-08 21:43Z to 23:34Z; one lane A warm throwaway `e32s7pw`; `class <Class>:<Method>` per run; load `LOAD_BURN`=8: 8 host loops plus 8 `--cpus 1` containers, which an EXIT trap removed after each batch, host load 45 to 144; "old" = the file at `7d0a57f2`; scratch edits restored byte-identical; 0 `RETRY` lines in 180 runs):
  - **G1** (`Runners:TestStartRefused`). Injection: the first time a poll sees the old three conditions, `Ens.ScheduleService.CallScheduleService()`, then a no-Hang wait of up to 10 s for an Alive job of TriageAgent (read from the job-status global). **old: 0 of 10 red (plain load); 6 of 10 red (injected)**. 12 of 20 injected calls saw the Alive job, and 8 of those went red: `TriageAgent has no alive job` (8), `names it as not running` (2). Tuning runs with looser waits (2 of 9 red) are not counted. **fix: 20 of 20** with the same injection. In all 40 calls a second refused start wrote a second refusal row after the first settle (18 seen Alive); the poll then took 2 or 3 polls. Cause confirmed: Ens.ScheduleHandler's deferred update starts the refused item again.
  - **G2** (`Heartbeat:TestAfterAllTestsNothingSaved`). Injection at the start of the method: `$$$ConfigIsEnabled("TelegramIn")=1`, put back right after the read. The stack was parked: `TelegramIn row 0, runtime flag 0, jobs none` before, `flag 1` at the read. **old: 5 of 5 red (injected)**: `NotRunning()` named TelegramIn. **new check: green; fix: 20 of 20** under load, and `NotRunningNow` read "". Cause confirmed.
  - **G4** (`ExtractMore:TestTimeLeft`; split printed by a scratch skipped assert at the method's end; min/median/max in s):
    - **old: 0 of 20 red (plain load**: 8 runs at `LOAD_BURN` 4, 12 at 8). Lock 4.94/5.01/5.10, after the release 3.44/4.72/9.12, total 8.43/9.80/14.19.
    - **fix, plain load: 20 of 20**. Lock 4.95/5.01/5.08, after 4.41/5.61/6.82, total 9.35/10.63/11.86.
    - Injection: `Hang 8` after `ReadSample`. **old: 20 of 20 red (injected)**: after 13.59/14.48/18.07, total 18.58/19.50/23.04 (`< 15` fails). **fix: 20 of 20** with the same injection: after 12.50/12.96/13.51 (`< 20` holds), lock 4.94/4.99/5.09.
    - (A first `Hang 10`: 5 of 5 old red, but after 15.88 to 18.04 s, too near 19; replaced.)
    - mutation: `Hang 21` after `ReadSample`, under load: `failed`, `(31.35 s in all; lock 5.01 s, after the release 26.34 s)`.
    - The lock part held at about 5.0 s in all 86 runs, and all the spread fell after the release: G4's inferred split is confirmed. Cause confirmed.
- **(lead) Smoke** (fixed tree, no load of mine, no injection, warm): `Runners` passed 44.11 s, `Heartbeat` 129.20 s, `ExtractMore` 22.21 s. After the restore, reversed (`ExtractMore` 23.08 s, `Heartbeat` 84.93 s, `Runners` 42.21 s): all passed.
- **(lead) Fresh check: not run.** The stack start alone took 176 s here (`WARM up ... ready 176s`), so a fresh `class` run does not fit 150 s; left to CI's fresh instances.
- Restore: `cmp` identical for the four files; their `git diff --stat` was empty before and after. Teardown: `warm.sh down` removed 1 project; `docker ps -a --filter name=e32s7p` and `--filter name=e32s7burn-p1` print nothing.

*L-G3 (page.close; stand-in under load) and the fresh check:*

- **L-G3 result (P2, 2026-11-08 21:41Z to 22:39Z; stand-in, no IRIS):**
  - Load: 32.6's burn block, 4 host loops + 4 `--cpus 1` mock containers (8 + 8 in one batch), 4 concurrent Playwright processes. The 1-minute load peaked at 113.
  - `stall old` (`SPLASH_HOLD_MS = 2_000`; C-1's `closeSettled(page)` replaced by `page.close()`; `--grep 'C-1'`): 4x5 (burn 4), 4x10 (burn 4), 4x10 (burn 8) and 1x20 `--workers 4` (burn 4). **`stall old: 0 of 120 red`.** Every close answered inside the hold (each run took 0.59 s at most). All 120 failed only on the order check `the splash document was served`. No test timeout and no `no answer within`. **G3's cause is not confirmed**, so G3 falls back to B3 (the lead decides).
  - `fix` (file as is, same load, `--grep 'C-1|C-2' --repeat-each 5`, 4 processes): **`fix: 20 of 20`** for C-1 and 20 of 20 for C-2 (40 of 40 tests).
  - Real L5/L6: **not run, left to L-ci.** Rows 2 and 4 wait 150 s to 180 s whatever the `--grep` (the unit takes 439 to 530 s in CI), `live` has no split steps, and it never runs warm. No throwaway was started.
  - Restore: `close-settled.spec.ts` was restored (`cmp` identical). `leave.spec.ts` was never edited (`cmp` identical). `git diff --stat` and `git status --short` are unchanged. The `e32s7g3` and `e32s7burn-p2` containers are empty.
- **L-fresh (P2):** no stack, `env | grep ^OCUTALON_` empty, results removed first.
  - Forward: the node tests 159 of 159; `close-settled` 3 of 3; helper-waits line 3 53 of 53; line 2 8 of 8.
  - Reversed: line 2 8 of 8; line 3 30 + 23 of 53 (split by `loadedAfter`); `close-settled` 3 of 3; the node tests in reversed order 151 of 159. The 8 reds are all `TestTimeLeft` pins, caused by P1's old-`ExtractMore.cls` put-back. On a `git archive HEAD` copy plus the story's 5 uncommitted test files, the result was 159 of 159.
- **`(once)` (P2):**
  - lint exit 0.
  - `test-ci-config.sh` exit 0 (40 PASS).
  - `test-boundaries.sh` all rules passed (run during P1's put-back).
  - `npm --prefix web test`: P1's put-back stayed in the tree for more than 35 min, so the test ran in 2 halves on the same copy: 915 of 915 and 701 of 702. The one red is `retired-demo-path-names` (it needs git); it passed 6 of 6 in the tree. Rerun in the tree after P1 restores.

**Lead decision after the proofs:** G1, G2 and G4 confirm their causes (A1, A2, A4 stand). G3's injected stall gave 0 reds, so its cause is not confirmed: by `planner-2026-11-08-32.7` G3 falls back to its single logged retry (B3), built in rework iteration 1; A3's splash wait stays (it matches the traces and costs nothing).

**L-G3, B3 (the fallback), the lead, 2026-11-09 about 00:24Z to 00:32Z, after the rework's re-review.** Load: 4 concurrent Playwright processes (sign-in-2 project, stand-in pages, no stack) with 4 CPU burners on the host; `--grep 'R1: the real Target.closeTarget closes the page'` (the injected stall: the first close never settles).
- **old: 8 of 8 red** (`fixtures.ts` put back from `e1b344b8`, i.e. A3 without B3; each red `page.close: no answer within 20 s`); restored byte-identical (`cmp` against the lead's backup; `git status --short` unchanged).
- **fix: 20 of 20 passed** (4 processes x `--repeat-each 5`; each test counts its one `RETRY` line in its own `retries.txt`).
- Fresh check after the rework (no stack, `env | grep ^OCUTALON_` empty, e32s7 result folders removed): node `state-wait`, `flake-fixes-sources`, `flake-fixes-behaviour`, `bounded-waits`, `e2e-part`, `ci-results` 160 of 160 forward and reversed; Playwright `close-settled.spec.ts` 3 of 3 and helper-waits `one more close of the page|the close diagnosis` 16 of 16, both orders (20 of 20 together forward).
- Real L5/L6 (`live:online-session`, 439 to 530 s a unit) and the ObjectScript classes' fresh-stack runs are left to CI's fresh instances (a stack start alone took 176 s on this host).

## Auto Run Result

Status: done
Blocking condition: none

**Rework 2 (build-auto, 2026-11-09; this pass only).**
- Summary: the `[CI]` item (state-retry pin vs C1's DIAG lines, CI run 42541161624) is fixed by option (ii). `web/e2e/live/state-retry.spec.ts` now requires the file to end with a newline, its RETRY-shaped lines (the shape `ci/iris.sh` `retry_lines` counts) to equal exactly `[retry]`, and every other line to match `^DIAG [ -~]{1,300}$`; the cookie-name and cookie-value check also scans the file's lines. `bounds.ts` and `ci/iris.sh` are as built.
- Files changed: `web/e2e/live/state-retry.spec.ts` (the pin and the secrets scan). The RETRIES-per-unit and per-group case already exists (`state-wait.test.mjs`: `cmd_live prints the RETRY lines, then the DIAG lines, then the count, which holds only the RETRY lines`; `cmd_group counts and summarises the RETRY lines only, whatever DIAG lines follow them`), so no case was added; no other reader of a retry file pins its exact content (`helper-waits.spec.ts` R1/R2 already expect RETRY plus the page lines).
- Review: 14 findings (low 12, false 2), no high or medium. Patched: 1 (the secrets scan covers the file's lines, low). Deferred: none. Rejections and reasons: see the Review Triage Log.
- Follow-up review recommended: false (this follow-up pass patched no high).
- Verification: the node tests (`state-wait`, `retry-bounds`, `bounded-waits`, `e2e-part`, `ci-results`, `flake-fixes-sources`, `flake-fixes-behaviour`: 172 of 172), `npm --prefix web run lint`, `bash docker/tests/test-ci-config.sh` and `bash docker/tests/test-boundaries.sh` pass; `playwright test e2e/live/state-retry.spec.ts --list` parses. Mutations: under `## Verification` (rework 2).
- Residual risks: the live case needs a stack and was not run; the first real check of the pin is CI on the next head (the lead's push). The RETRY shape in the spec is a copy of `ci/iris.sh` `retry_lines`'s and fails closed if the shell shape changes.

(Earlier passes follow.)

**Rework 1 (B3, build-auto, 2026-11-08).**
- Built the G3 fallback: `closeTargetAgain` and `closeLines` in `diagnose.ts`; `boundedClose` retries once at half of a bound of 20 s or more (`closeWithOneMore`, Chromium only), inside the same bound; the fourth contract comment is rewritten; the `bounded-waits.test.mjs` pin pins the new line; `helper-waits.spec.ts` has R1 to R5. A3 is kept.
- Review: 25 findings (medium 1, low 17, false 5, maybe-false 2), no high. Patched: R5 (a first close that rejects keeps its error), R3 for a browser that is not Chromium, `closeTargetAgain` detaches its sessions on the timeout path, and the comment on the printed re-close line. Deferred: none. Rejections: see the Review Triage Log.
- Follow-up review recommended: false (this pass patched no high).
- Verification: the node tests (146 of 146), `npm --prefix web test` (1623 of 1623), `npm --prefix web run lint`, `bash docker/tests/test-boundaries.sh` and `test-ci-config.sh` pass; `helper-waits.spec.ts` passes in full (the B3 and diagnosis cases 15 of 15, the rest 53 of 53). Mutations: under `## Verification`.
- Residual risks: the real stall was never reproduced, so B3 is a containment shown against a stand-in; the lead's runs carry AC5 and AC6. B3's cases add about 70 s to `live:sign-in-2`.

**Implement and review (build-auto, 2026-11-08).**
- Summary: the Build list is built (C1-C4, D1, D4, A1-A4); no Branch B task and no A5.
  - DW-911: `reportRetry(step, lines)` appends the redacted retry-time page lines after the RETRY line, and `ci/iris.sh` prints them (`retry_diag_lines`) between the RETRY lines and the RETRIES line. Counts and the step summary are unchanged.
  - C3: `ci/iris.sh class <Class>:<Method>` runs one `Test...` method.
  - A1 (G1, DW-211): `AssertRefused` settles only with no Starting or Alive Ens.Job row of the item and an idle Ens.ScheduleHandler, on 2 polls in a row; D1 appends `StateOf(item)` to its two messages.
  - A2 (G2, DW-639): Heartbeat's check and `Restore` read `RunnerFixture.NotRunningNow`.
  - A3 (G3, DW-774): leave.spec L5 and L6 wait for the splash button and `load` before closing.
  - A4 and D4 (G4, DW-973): `TestTimeLeft` splits at the holder's end node: elapsed `> 4`, lock `< 15`, after the release `< 20`, split in the message.
- Files changed:
  - `ci/iris.sh`: the DIAG print, the one-method run, `class_method_ok`.
  - `web/e2e/support/bounds.ts`, `web/e2e/support/floor.ts`: C1.
  - `web/e2e-online/session/leave.spec.ts`: A3.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls`, `Test/Schedule/Heartbeat.cls`, `Test/Docs/ExtractMore.cls`: A1/D1, A2, A4/D4.
  - `web/scripts/state-wait.test.mjs`: C4 cases.
  - Footprint extensions: `web/e2e/live/helper-waits.spec.ts` (two retries.txt expectations now hold the RETRY line plus the page lines) and the new `web/scripts/flake-fixes-sources.test.mjs` (source pins for A1-A4 and floor.ts's redaction).
- Review: 19 findings (medium 1, low 15, false 3). Patched: TestTimeLeft asserts the end node (3 findings), floor.ts redaction pin (1), `class_method_ok` moved into the helper zone (1). Deferred: none. Rejected with reasons: see the Review Triage Log.
- Follow-up review recommended: false (one medium patched, no high).
- Verification:
  - `(loop)`: the node tests (156 of 156), `test-ci-config.sh`, `helper-waits.spec.ts` (61 of 61, in three runs), and the three warm one-method runs (Runners, Heartbeat, ExtractMore; no RETRY printed).
  - `(once)`: `npm --prefix web run lint` (exit 0), `bash docker/tests/test-boundaries.sh` (first red on a literal test-global name in the new test file, fixed; all rules passed), `npm --prefix web test` (1607 of 1607), the line 3 and 2 reruns, the line 5 runs in reverse order, `git diff --stat`.
  - Mutations: recorded under `## Verification`.
- Residual risks: the lead's stack proofs (old red, fix 20 of 20 under load) are not run; A1-A4 rest on source pins plus those proofs. `closeSettled` is best effort and was not run against a stack. A scheduler that never idles would run A1's poll to the 120 s deadline.

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
