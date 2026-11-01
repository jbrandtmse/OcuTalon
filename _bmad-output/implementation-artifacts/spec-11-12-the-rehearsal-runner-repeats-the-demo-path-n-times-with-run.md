---
title: 'Story 11.12: The rehearsal runner repeats the demo path N times with Run again (runs 2 to N, the replay rule, the tell-now item and its bound; dry runs on throwaways)'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_revision: 'b7a6ee11b2799f6b371134f47d489a30ef58f959'
baseline_commit: 'b7a6ee11b2799f6b371134f47d489a30ef58f959'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-11-the-rehearsal-runner-times-the-demo-path-and-checks-every-bo.md'
warnings: ['oversized']
deferred:
  - summary: >-
      Run 2 cannot press Run again as the spec's Repeat start row says: after 07's pending replay request is rejected and its incident dismissed, the guide still holds run 1's opened trace (GuideState.TraceOpened is cleared only by the run_again marker), shows no finish and so no Run again button, and reads step 5; the next trace step would then show the finish at once, with no step-5 link to open. The repeat posts the page's own run_again marker (POST /ocutalon/api/v1/guide/markers) after the Dismiss, so that runs 2 to N all start with the guide at step 3, current.
    evidence: |-
      Live dry run (tag e11s12d): the first run 2 failed at "Step 3, Break the feed, current" with the guide reading "Next: Open the incident's trace" (step 5); with the marker posted, runs 2 and 3 passed the same specs.
    location: >-
      web/e2e-rehearsal/repeat.spec.ts (again:)
    severity: low
  - summary: >-
      The real-model texts of the repeat are unmeasured: the composer-sent watch and reminder prompts, the reminder notice card ("Reminder: " then the model's text) and the phone message without buttons (counted as "at least one more" on the real model), and the tell-now item's outcome (the eval case is expected to be decided Tell now; another outcome is a miss with its outcome named).
    evidence: |-
      Only the CI mock ran in this build; Story 38.2's first real run (or Story 11.14's candidate gate) confirms the shapes.
    location: >-
      web/e2e-rehearsal/repeat.spec.ts, web/e2e-rehearsal/tell-now.spec.ts
    severity: low
  - summary: >-
      docker/tests/test-rehearsal.sh now takes about 77 s alone on the developer machine (the 11.11 build took about 47 s there, 36 s in the hosted checks job), so the hosted job's share is near the "about 60 s" budget.
    evidence: |-
      Per rule here (s): stub-runs 19, bounds 13, timed-runs 20, run-steps 14 (new), the rest under 5. The 20-run states are not shared between rules; sharing them (or fewer installs in run-steps) is the lever if the job needs the time.
    location: >-
      docker/tests/test-rehearsal.sh
    severity: low
  - summary: >-
      The online demo-path unit (web/e2e-online/demo-path/demo-path.spec.ts) imports watchThroughGuide and approveOnPhone, which this story changed; only the type check and the web demo-path unit (ci/iris.sh live demo-path) were run on them, not ci/iris.sh live online-demo-path.
    evidence: |-
      Both helpers keep their arguments and, with OCUTALON_E2E_MARKS unset, their behaviour (approveOnPhone adds one phone count before the press, which is 0 and so today's 1 on a first run).
    location: >-
      web/e2e/support/demo-path.ts
    severity: low
---

<intent-contract>

## Intent

**Problem:** Story 11.11's `release/rehearse.sh runs` times one run of the REL-2 specs and refuses run 2, and its tell-now row is `not run`. So the 19-of-20 bounds are never measured over a run set, a real rehearsal can never pass, and a miss in a later run cannot be shown.

**Approach:**
- Each `runs` call runs the next run, up to `--runs`.
  - Run 1 is the REL-2 project verbatim on the fresh install (as today), then the new tell-now item.
  - Runs 2 to N run a new rehearsal project (`web/e2e-rehearsal/`) on the same install:
    - it clears what run 1 left pending (DW-522), or presses Run again;
    - it sends guide steps 1 and 2 through the composer;
    - it presses Break the feed under the replay rule, approves on the phone and opens the trace;
    - then it runs the same tell-now item.
- The collector, the marks and `bounds_eval` are reused. The tell-now row gets a real measurement.
- `report --plant <bound>@<run>` plants a missed bound in a later run.
- `run` becomes one phase per call, so no command passes the 10-minute cap (DW-537).
- The collector's names and the page probes get static checks in the hosted jobs (DW-534).

## Boundaries & Constraints

**Always:**
- **Everything 11.3 and 11.11 fixed still holds:**
  - the no-value rule, `host_run`, Bash 3.2, ASCII, `umask 077`, mode 100755 and main only when executed;
  - the FAIL grammar and the Result rules;
  - exit codes 0 / 1 / 2 / 3 / 75;
  - one clock per mark (no value subtracts a mark of one clock from a mark of the other);
  - the collector only reads;
  - dry rows read `dry run`, never `pass`;
  - a missing mark fails its run;
  - specs reach IRIS only through `rehearse.sh exec`;
  - no write to `release/records/` from a test.
- **No false all-clear and no claimed pass that was not seen.** A run whose tell-now item the model did not decide Tell now gives no tell-now sample. It counts against that row's 19-of-20 allowance, with the outcome named, and never as met.
- **CI behaves as before.** The demo-path and online demo-path units run the same assertions:
  - every changed helper keeps today's behaviour with its default arguments and with `OCUTALON_E2E_MARKS` unset;
  - `web/e2e/demo-path/*.spec.ts`, `web/playwright.config.ts` and `ci/units.sh` do not change;
  - no CI unit is added or moved;
  - no job is renamed;
  - the iris matrix is unchanged.
- **Every command fits one 10-minute call.**
  - One `runs` call is one run. Its Playwright time in all is at most `OCUTALON_E2E_TIMEOUT_MS` (default 480000).
  - `run` does one phase per call.

**Never:**
- Contact a real host, use a real model key, use origin, or claim that a real bound passed. The real 20 runs are Story 38.2's.
- Change a product class, product text, or `web/src`.
- Touch an open epic's file: `web/e2e/demo-path/telegram-*.spec.ts` and `docker/tests/lib-live.sh` (Epic 12), `release/standalone-bridge.sh` (Epic 13), `release/ipm*` and `src/module.xml` (Epic 15), `.github/workflows/*`.
- Create a `release/*` branch. A stand-in branch is `rehearsal/...` (U-203).
- Build a second runner. Everything extends `rehearse.sh` (Rule 2).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Run 1 | `runs` after a passed install, no run yet | As 11.11 (`npm --prefix web run e2e:demo-path`, with Playwright time `OCUTALON_E2E_TIMEOUT_MS` minus 90000), then `npm --prefix web run e2e:rehearsal -- tell-now.spec.ts` (90000 ms), each summarised, then the collector. `PASS run 1 demo path: ...` and `RUN 1 ... tell-now=<s>` | A failed spec: `FAIL run 1 step <step> bound -: <reason>`. The collector still runs |
| Run k (2 to N) | `runs` when runs 1..k-1 exist and run k-1 passed | `npm --prefix web run e2e:rehearsal` (`repeat.spec.ts`, then `tell-now.spec.ts`) with 11.11's environment and `OCUTALON_REHEARSAL_RUN=k`; summary `--steps repeat,tell-now`; the collector; `PASS run k ...` and `RUN k ...` | A failed test names its step from its title (`watch: ...`): `FAIL run k step watch bound -: ...` |
| Repeat start | run 2 after run 1 (07's replay request pending) / run 3+ (finish shown) / neither | Run 2: reject the pending request on the phone and Dismiss its incident (DW-522). Run 3 and later: press Run again. Then the guide reads step 3 current and Break the feed is active | Neither state: the `again` test fails |
| Runs done / after a failure | `runs` with `--runs` runs present, or with the newest run failed | One REFUSED line ("N of N runs done; run report" / "run k failed; run report and down"); exit 2 | Nothing starts |
| Tell-now on the mock | the item's body carries `[[mock:mail-tell-now]]` | Decided Tell now (scripted). `tell-now` = (`tellnow_seen` minus `tellnow_sent`, page) minus the decision's `DurationMs` (server) | A missing page mark fails the run (step `tell-now`) |
| Tell-now on the real model | the model decides another outcome | The test records the outcome and passes; the collector reports `CHK|tellnow|<outcome>|<ms>`; that run is not a sample, and the row counts it as a miss with its outcome named | More than floor(N/20) misses: `FAIL run <runs> step tell-now bound tell-now 5 s in 19 of 20: ...` |
| Planted miss in a later run | `report --plant pick-up@3` (or `run ... --plant pick-up@3`), dry run only | That bound's limit is 0 in run 3 only: `FAIL run 3 step incident bound pick-up 15 s (planted): ...`; `Result: fail`; exit 1. A bare `--plant <id>` keeps 11.11's every-run plant | Real mode, an unknown id, `@0`, a non-number, or a run that does not exist: exit 2 |
| `run`, one phase per call | `OCUTALON_RUN_TAG` set; the same options on every call | Each call does one of: install; one run; report then down. Every call but the last prints `NEXT run: <what is due>` and exits 4. The last exits with report's code. A failed install step or a failed run makes report then down the next call's phase | No tag: exit 2. An option that differs from the state's stored value: exit 2, naming it. Install's 2 or 75 pass through |
| Dry run, end to end | install `--dry-run --rc 1 --runs 3 --record <tmp>`, runs x3, report, `report --plant pick-up@3`, down (one call each) | report: `RESULT dry run`, exit 3; every met row reads `dry run`, tell-now included; the runs row reads `3 of 3 runs passed`. The plant prints the run-3 FAIL line, then `RESULT fail` and exit 1 | down leaves no project, container, volume, image, lock or state of the tag |

</intent-contract>

## Code Map

**Built and extended (read their headers first):**
- `release/rehearse.sh`:
  - header `:1-125`, the interface 11.14 and 11.13 read;
  - `REH_ROWS`/`REH_PLANTABLE` `:131-133`;
  - `COLLECTOR` `:175-223` (`@START@`/`@USER@`; first record at or after the server start);
  - `BOUNDS_AWK` `:230-450` (`lim`, `rule`, `stepof`, `what`, `nmark`, the `mode=run` RUN line, the FAIL lines, the rows, the `### Runs` table, and the literal tell-now `not run` row at `:421`);
  - `runs_feed`/`runs_ids`/`bounds_eval`/`bounds_merge` `:1245-1301` (the `runs` row text naming 11.12 at `:1297`);
  - `plant_ok` `:754`, `cmd_report` `:1390`;
  - `need_installed`/`runtime_prepare` `:1425-1454`, `exec_chk` `:1497`, `summary_step` `:1523`, `scrub_origin` `:1533`;
  - `phase_runs` `:1544-1643` (`k=1` is fixed; the Playwright env block `:1570-1576`);
  - `cmd_runs` `:1645-1660` (the run-1-exists refusal);
  - `install_args`/`cmd_run` `:1705-1760` (today a loop in one process).
  - Real-mode guard: `real_guards` `:844`, with the four guarded paths.
- `docker/tests/test-rehearsal.sh` -- rules `t_bounds` `:1128`, `t_timed_runs` `:1358` (stub npm, canned report, stub clean host answering `exec`), `t_guards` `:1564`, `t_dry_report` `:1731`, `t_static` `:1784`. It takes about 36 s in the hosted `checks` job.
- `web/e2e/support/demo-path.ts`:
  - `watchThroughGuide` `:236-266` (the marks: `stripsBefore` behind `marksOn()`, then `step1_sent`, `step1_decision_seen`, and `step1_reply_seen`, whose probe is "the newest reply's `.text` is non-empty": on a repeat that is already true from the earlier run, so it must become relative);
  - `expectIncidentAwaitingApproval(page, card)` `:302`;
  - `pressOnPhone` `:345-357`: its `approval_result_seen` probe reads `incidentCard(page)`, the page's first incident card. On a repeat, that is an earlier, already-approved card, so the probe would be true at once: a false pass;
  - `approveOnPhone` `:369-387`: `incidentCard(page)`, and the phone result `toHaveCount(1)`, a first-run count;
  - `rejectOnPhone(page,key,card)` `:397`, `incidentRows`/`incidentCardOf`/`newIncidentRef` `:426-470`, `pressBreakFeed` `:473`, `openTraceFromGuide` `:542`, `dismissIncident` `:574`, `guideRegion`, `composer` `:54`, `WATCH_PROMPT`, `doneTurn`, `newestClientId`, `expectDecision`.
  - `web/e2e-online/demo-path/demo-path.spec.ts` also imports `watchThroughGuide` and `approveOnPhone(page, key, ' ET')`. It must keep working unchanged.
- `web/e2e/support/rehearsal.ts` -- `mark`, `markWhen`, `marksOn`, `irisSessionCommand`; its header lists the mark names.
- `web/e2e/support/devices.ts` -- `pointKeys`/`restoreKeys` `:188-199`, `mailboxOf` `:205`. `web/e2e/demo-path/08-quiet-outcomes.spec.ts` `afterAll` shows the restore plus the `RunnerFixture.WaitRecords()` check.
- `web/e2e/demo-path/07-failure-paths.spec.ts` -- the Run again press `:50-56`, and Reject, Dismiss and replay `:86-114`. It leaves the replay's request pending; 08 checks it is still pending. Neither spec file changes.
- `web/e2e/demo-switch/mailbox.spec.ts` -- `compose()` `:79-85` (Simulate an incoming email, From, Subject, Body, Send); `cards()` `app-chat-panel app-notice-card`, `phoneMessages()` `app-simulated-phone .notification`; MB3 `:201-215` is the mock's Tell now through `[[mock:mail-tell-now]]` (`ci/mock/scenarios/B/mail-tell-now.json`, marker match, `delayMs` 2000).
- `eval/mail-endpoint-move-tomorrow/case.json` -- an eval-set item whose expected outcome is `tellnow` (not held out). Its sender, subject and text are the real-model tell-now item. Read it with `join(__dirname, '..', '..', 'eval', ...)`, as `web/e2e-online/host-pages.spec.ts:22` does.
- `web/scripts/demo-path-summary.mjs` -- `STEPS` and `stepOfFile` `:37-61`, `summarize(report, {onlyTelegramSkips})` `:94-160`, `main` `:176`. `web/scripts/demo-path-summary.test.mjs` pins it.
- `web/playwright.config.ts` -- not changed. The `chromium` project's `testDir './e2e'` would pick up any folder under `web/e2e/`, so the rehearsal specs live in `web/e2e-rehearsal/`, under a config of their own. `web/tsconfig.e2e.json` `include` lists the type-checked trees (`npm run lint`).
- **Product facts (read only):**
  - `Data/GuideState.cls:67-88` RunAgain;
  - `Demo/Guide.cls:6-15,45` (Break the feed needs no open, awaiting or fixing incident, and a noticed run or a wait of NOTICEWAIT 180 s);
  - `Demo/BreakFeedIn.cls:85-115` (the press closes resolved incidents, `closeForReplay`);
  - `Tools/WatchTools.cls:25,86` (`already_watching` for a second watch);
  - `Core/Intake.cls:166-174` (Summary is "{Sender}: {Subject}", cut at 80 characters, so the run stamp goes at the start of the subject);
  - `Channel/SimMailbox/In.cls` (the row: Kind `mailbox`, Direction `in`, `ItemId`);
  - `Bridge/Data/Decision.cls` (`ItemId`, `Kind` `decide`, `Outcome`, `DurationMs`);
  - `Bridge/Adapter/Agent.cls:417` (`DurationMs` is the model call's own wall time, `$ZHorolog`);
  - `Bridge/Process/Decide.cls:922-946` (the row gets it).
- **The page's sources the probes read (for DW-534's pins):**
  - `web/src/app/chat/decision-strip.ts` (`.reason`);
  - `web/src/app/chat/ocutalon-reply.ts:40` (`data-part="reply"`, `.text`);
  - `web/src/app/msg/catalog.ts:24` (`'answered.approved': 'Approved from {channel} at {time}'`, and the channel name `'phone': 'the simulated phone'` `:129`);
  - `web/src/app/chat/notice-card.ts`, `web/src/app/phone/simulated-phone.ts:51` (`.notification`).

## Tasks & Acceptance

**Execution:**
- `(Task 0, measure)` On the first live dry run, record under Verification:
  - the seconds of each `runs` call, and the Playwright seconds of each call inside it;
  - `exec.count` per run;
  - run 2's start state: the pending request and the guide step after Dismiss;
  - that a composer-sent watch prompt on a watched session gets a decided reply (the mock's `guide-watch` text, `already_watching`) and that the check row stays one;
  - whether the earlier runs' reminders leave the Reminders list;
  - the tell-now item's `DurationMs`, against its `Decide` request and `DecisionResponse` headers (ms; it must lie inside them);
  - the tell-now value per run;
  - that the notice card's and the phone message's text hold the run stamp.
  - If a named locator or record does not exist, use the nearest one that does and name it.
- `web/e2e/support/demo-path.ts` -- extend, never fork:
  - **Factor the marked send.** Factor `watchThroughGuide`'s marked click into one internal `markedSend(page, click)`. It counts the strips and the replies before the click, only when `marksOn()`. Then it marks `step1_sent`, clicks, and runs `markWhen` for `step1_decision_seen` (more strips) and `step1_reply_seen` (more replies, and the newest reply's `.text` is non-empty).
  - **Add `sendThroughComposer(page, prompt, step1Marks)`.**
    - It fills `composer(page)` and presses the composer's Send, through `markedSend` when `step1Marks`.
    - It expects the prompt as the user's message, waits for `doneTurn`, and checks the reply's strip with `expectDecision`. On the mock the chip is Act.
    - It returns the turn.
  - **Give the approval helpers a card.**
    - `pressOnPhone` and `approveOnPhone` take an optional `card` (default `incidentCard(page)`). The `approval_result_seen` probe and every card assertion read that card.
    - The phone's result check becomes "the count before the press plus one". On a first run the count before is 0, so it is today's 1.
    - Every call that exists today keeps its arguments and its behaviour.
  - Update the header in one sentence.
- `web/e2e/support/rehearsal.ts` -- the header adds the marks `tellnow_sent` and `tellnow_seen`. No code change.
- `web/e2e-rehearsal/repeat.spec.ts` -- new; runs 2 to N only (rehearse.sh never runs it in run 1).
  - **Setup:** `describe.configure({ mode: 'serial' })` and skip without `OCUTALON_URL`. On the mock, `pointKeys` in `beforeAll`; in `afterAll`, `restoreKeys` and the `WaitRecords` check, as 08 does (about 4 lines copied: spec files 01 to 08 do not change). Each test signs in with `signInReadmeLoaded`.
  - **Titles:** each test's title starts with its step id and a colon, which names the step in a FAIL line.
  - **The tests, in order:**
    - `again:`
      - If `/state` holds an incident with a pending request, press Reject on the phone (`rejectOnPhone` with its card) and then `dismissIncident` (DW-522).
      - Otherwise, if the guide shows its finish, press Run again and expect "Step 3, Break the feed, current".
      - Otherwise fail, naming the state.
      - Then Break the feed is active.
    - `watch:` `sendThroughComposer(page, WATCH_PROMPT, true)`. The "Orders production" check row is still one.
    - `reminder:` `sendThroughComposer(page, 'Remind me in 1 minute to stretch.', false)`. A Reminders row with its countdown shows.
    - `incident:`
      - Take the refs from `incidentRefs`, then `pressBreakFeed` and `newIncidentRef`.
      - `expectIncidentAwaitingApproval(page, incidentCardOf(page, ref))`.
      - Keep the ref and the key for the next tests.
    - `approval:` `approveOnPhone(page, key, '', incidentCardOf(page, ref))`.
    - `trace:` `openTraceFromGuide(page, context, <the ref's diagnosisHeader from incidentRow>)`. The finish shows.
    - `reminder:` (landed) Within 90 s, the chat has one more notice card than before with "Reminder: stretch." (on the real model, `/Reminder: \S/`), and the phone has one more stretch message (on the real model, a message without buttons).
  - **Counts are relative.** Every count is relative to a count taken in the run, or scoped to the run's incident card.
- `web/e2e-rehearsal/tell-now.spec.ts` -- new; every run.
  - **Setup:** on the mock, `pointKeys`, then restore with `WaitRecords`, as above.
  - **The item:** read the eval case.
    - The subject is `Rehearsal run <OCUTALON_REHEARSAL_RUN>: ` followed by the case's subject.
    - The body is the case's text, plus ` [[mock:mail-tell-now]]` on the mock.
    - From is the case's sender.
  - **The test:** one test, titled `tell-now: ...`.
    - Open `mailboxOf` and fill the compose form.
    - `mark('tellnow_sent')` right before Send.
    - `markWhen('tellnow_seen', ..., 60_000)`. Its probe is true when (the chat has an `app-notice-card` and the phone has a `.notification` that both hold the stamp) or (the row's outcome chip shows an outcome other than Tell now).
    - Then, on the mock, the chip is Tell now. On the real model, the chip shows an outcome.
    - When it is Tell now: one card and one phone message hold the stamp, and the card holds "Why now:".
    - When it is another outcome (the real model only), add a test annotation naming the outcome and pass.
- `web/playwright.rehearsal.config.ts` -- new:
  - it imports the default config of `./playwright.config` and re-exports it with one project, `rehearsal` (`testDir: './e2e-rehearsal'`, Desktop Chrome);
  - the reporters, `globalTimeout`, `workers: 1` and `baseURL` come from the base.
- `web/package.json` -- add `"e2e:rehearsal": "playwright test --config=playwright.rehearsal.config.ts"`.
- `web/tsconfig.e2e.json` -- `include` adds `e2e-rehearsal/**/*.ts` and `playwright.rehearsal.config.ts`.
- `web/scripts/demo-path-summary.mjs` -- add `--steps <id,...>`, the rehearsal's mode:
  - the steps are those ids; each id's file is `<id>.spec.ts`; every test must pass, and any skip is a FAIL;
  - there is no `@floor` rule;
  - the last line is `REHEARSAL <r> of <n> steps ran, <s> skipped, <f> failed`;
  - FAIL reasons keep `<file> "<title>": <state>`.
  - The default and `--only-telegram-skips` stay byte-for-byte the same.
  - Extend `demo-path-summary.test.mjs` to cover this.
- `release/rehearse.sh` -- extend; the header documents every addition (for Stories 11.14, 11.13 and 38.2).
  - **`runs`:**
    - k is the newest run plus one.
    - It refuses (exit 2) when `--runs` runs exist, or when the newest run's `runs/<k>/passed` is not `1`.
    - `phase_runs` takes k. Run 1 makes the two Playwright calls of the Matrix (budget split: the tell-now call gets 90000 ms and the REL-2 call the rest). Run k ≥ 2 makes one call, `e2e:rehearsal`. Each call writes its own `report*.json`.
    - The summaries: `--only-telegram-skips` for the REL-2 report, `--steps tell-now` for run 1's second, and `--steps repeat,tell-now` for k ≥ 2.
    - It writes `passed` (1/0) last.
    - The summary's FAIL lines, the exec check and the verdict stay as today.
  - **`summary_step`:** add `<id>.spec.ts "<step>: ` → `<step>`.
  - **`COLLECTOR`:** add `@RUN@`.
    - The session's newest mailbox `in` row created at or after the start, whose `Subject` starts with `Rehearsal run @RUN@: `.
    - Its `ItemId` → `OcuTalon_Bridge_Data.Decision` (`Kind = 'decide'`).
    - It prints `CHK|tellnow|<Outcome>|<DurationMs>`, or `CHK|missing|tellnow`.
    - `marks_server_write` keeps it as `tellnow <outcome> <ms>`.
  - **`BOUNDS_AWK`:**
    - the step `tell-now` with the page marks `tellnow_sent` and `tellnow_seen` (required only when the outcome is `tellnow`) and the server line (always required);
    - `lim["tell-now"] = 5000`, rule 19 of 20, `what` = "from the decision to the notice on the web chat and the phone (an upper bound)", value = (seen - sent) - DurationMs;
    - an outcome other than `tellnow` is a miss whose detail is `run <k>: decided <outcome> (no tell-now sample)`;
    - the row's met text: `within 5 s in <m> of <n> runs (19 of 20 needed); longest <x> s (run <k>)`;
    - the RUN line and a `Tell now` column of `### Runs`;
    - the literal `not run` tell-now row goes;
    - `plant` takes `<id>` or `<id>@<run>`: with a run, only that run's value misses.
  - **Rows:** the `runs` row text drops "Story 11.12" (`N of N runs passed`; `k of N runs done` while short). `REH_PLANTABLE` gains `tell-now`. `plant_ok` accepts `@<positive integer>`, and `cmd_report` refuses a run that is not in the state.
  - **The real-mode guard** adds `web/e2e-rehearsal`, `web/playwright.rehearsal.config.ts` and `eval/mail-endpoint-move-tomorrow/case.json` to its paths.
  - **`run` (one phase per call):** as in the Matrix row. It needs `OCUTALON_RUN_TAG`, keeps exit 4 for "call again", and an option given on a later call must equal the stored value. `install_args` stays.
- `docker/tests/test-rehearsal.sh` -- extend; hermetic. Update 11.11's cases that pin the run-2 refusal, the `not run` tell-now row and the `run` loop.
  - **`t_bounds`:**
    - 20 synthetic runs with tell-now values: all within (real `pass`, Result `pass`; dry `dry run`);
    - run 12 at 5.1 s, within the allowance;
    - runs 3 and 9 over: FAIL `run 3,9 step tell-now ...`;
    - run 4 decided `digest` beside run 9 over: FAIL naming both, with `decided digest`;
    - `--plant pick-up@17`: only run 17 in the FAIL line, `(planted)`;
    - a missing `tellnow_seen` with the outcome `tellnow`: `FAIL run k step tell-now bound -: missing mark(s) tellnow_seen ...`;
    - a missing `tellnow` server line: run fails.
  - **`t_timed_runs` (stub npm by argv):**
    - run 1 calls `run e2e:demo-path`, then `run e2e:rehearsal -- tell-now.spec.ts`;
    - run 2 calls `run e2e:rehearsal` with `OCUTALON_REHEARSAL_RUN=2`;
    - a failing rehearsal report names its step (`watch`);
    - `runs` after `--runs` runs, and after a failed run: exit 2;
    - the collector script carries the run number.
  - **New rule `run-steps`:**
    - the call sequence install → run 1 → run 2 → report+down, with exits 4, 4, 4 and the report's code;
    - no tag: exit 2;
    - a differing `--rc`: exit 2;
    - a failed run: the next call reports;
    - `--plant` reaches the report call (closes DW-538).
  - **New rule `collector-names` (DW-534):**
    - every `FROM OcuTalon_<pkg>.<Class>` table of `COLLECTOR` maps to a class file under `src/*/cls/`;
    - every column the collector names in its SELECT list and WHERE clause is a `Property` of that class;
    - every `MessageBodyClassName = '<class>'` names an existing class file;
    - every `TargetConfigName = '<item>'` is an item `Name` in `src/ocutalon/cls/OcuTalon/Production.cls`;
    - `Ens.*` is skipped.
    - The names are read from the heredoc, never from a list in the test.
  - **`t_static`:** the collector still holds no write.
- `web/scripts/rehearsal-support.test.mjs` -- extend:
  - **By source:**
    - `markedSend` holds the three step-1 marks next to the click;
    - the reply probe counts replies;
    - the `approval_result_seen` probe reads the `card` parameter, not `incidentCard(page)`;
    - the tell-now spec marks `tellnow_sent` just before its Send.
  - **The probes' page sources (DW-534):**
    - `.reason` in `decision-strip.ts`;
    - `data-part="reply"` and `class="text"` in `ocutalon-reply.ts`;
    - `catalog.ts`'s `answered.approved` web text, with the phone's channel name filled in, starts with "Approved from the simulated phone at";
    - `app-notice-card` and `.notification` in their components;
    - the outcome label "Tell now" (`chipTellNow` in `web/src/app/chat/chat-view.ts:58`).

**Acceptance Criteria:**
- **AC1 (N runs on one install, with Run again and the replay rule; REL-6, UX-DR101).** Given a passed install and `--runs N`, when `runs` is called N times, then:
  - run 1 runs the REL-2 project and the tell-now item;
  - runs 2 to N run the repeat project on the same install (run 2 clears 07's pending replay; runs 3 to N press Run again; every press is accepted under the replay rule);
  - each run gives its own marks.
  - Pinned by the stub-host argv cases, and live in the dry run with `--runs 3`.
- **AC2 (every bound over the whole set, and tell-now; NFR-3, NFR-7 to NFR-10, FR-1, P30, AD-15, UX-DR102).** Given runs 1..N, when `report` runs, then:
  - every 11.11 bound is checked over all N runs with its rule (floor(N/20) misses for 19 of 20);
  - the tell-now row checks the item's notice on the web chat and the phone within 5 s of its decision in at least 19 of 20 runs, as the upper bound defined in Design Notes;
  - a run with no tell-now sample counts against the allowance, with its outcome named.
- **AC3 (a miss in any run blocks; REL-6).** Given a failed test or a missed bound in run k of the set, when the rehearsal ends, then:
  - `FAIL run <k...> step <step> bound <bound>: ...` names the run, the step and the bound;
  - a run after a failed run is refused;
  - `Result: fail` and exit 1.
- **AC4 (dry run with a planted miss in a later run; REL-6, NFR-11).** Given this build and lane A's variables, when install `--dry-run --rc 1 --runs 3 --record <tmp>`, three `runs`, `report`, `report --plant pick-up@3` and `down` run, one per call, then:
  - the first report reads `RESULT dry run`, exit 3, every met row `dry run` (tell-now included) and the runs row `3 of 3 runs passed`;
  - the planted report prints `FAIL run 3 step incident bound pick-up 15 s (planted): ...` naming run 3 only, `RESULT fail`, exit 1;
  - no `ssh` runs;
  - `down` leaves nothing of the tag.
- **AC5 (the record and its consumers; integration).** Given the runs, when `report` writes the section, then:
  - it holds the tell-now row (no longer `not run`) and the `Tell now` column of `### Runs`, which Story 11.13 copies verbatim;
  - a real state with `--runs` runs whose rows all pass reads `Result: pass` and exits 0 (the self-test's synthetic real state), and with fewer runs it reads `not run` and exits 1;
  - the loop Story 11.14 drives (`runs` until N, exit 2 beyond) behaves as its matrix row says.
- **AC6 (interface; DW-537).** Given the header's usage, when `run` is called repeatedly with one tag, then each call does one phase and fits one 10-minute call, exits 4 with `NEXT run: ...` until the last, and `--plant <id>@<run>` and every refusal behave as their matrix rows say. The header documents `runs` k, `run`'s exits, `--plant <id>@<run>`, the tell-now marks and the bound.
- **AC7 (CI unchanged).** Given `OCUTALON_E2E_MARKS` unset and the default arguments, when the demo-path and online demo-path units run, then they make the same assertions as before. `ci/iris.sh live demo-path` passes unchanged, and `demo-path-summary.mjs` without `--steps` prints what it printed before (its existing tests pass unedited).
- **AC8 (DW-534).** Given a collector that names a column, table, body class or production item that `src/` lacks, or a page probe whose selector or wording is gone from `web/src`, when the hosted `checks` and `web` jobs run, then `test-rehearsal.sh` (rule `collector-names`) or `rehearsal-support.test.mjs` fails, naming the name.

### Review Findings

Code review (bmad-code-review, 2026-11-01; four layers at the full tier: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 27 layer rows plus one reviewer check (Rule 2); 0 decision-needed, 6 patch, 5 defer, 12 rejected). Each finding gives its severity, fix-risk, footprint and disposition (Rule 15).

- [x] [Review][Patch] On the real model, the repeat's landed-reminder phone check counted every buttonless phone message. The approval's answered notice and its result message have no buttons, so `toBeGreaterThan(phoneBefore)` held even if the reminder never arrived (a claimed pass that was not seen). It now filters by the catalog's `reminder.due` text, `Reminder: {text}.`, as the chat check does. A node pin ties the filter to `Core.cls`. [web/e2e-rehearsal/repeat.spec.ts:67] (med; fix-risk low, the mock branch is unchanged; in-story; fixed)
- [x] [Review][Patch] `markedSend`'s `step1_reply_seen` probe read the last `[data-part="reply"] .text` on the page. While a turn runs, its reply holds only the indicator, so on runs 2 to N the probe found the earlier run's text and marked early: the recorded `first-reply` value was understated. The probe now reads `replies.last()`'s own `.text`. The source pin requires it. Live: run 2 read `first-reply=1.0` with the decision at 1.0 s. [web/e2e/support/demo-path.ts:196] (med; fix-risk low, it runs only with marks on; in-story; fixed)
- [x] [Review][Patch] Two paths of `e2e_call` had no test: its per-call fallback ("Playwright exited N although the summary found no failed step", the only guard when an `afterAll` fails after its tests passed) and `summary_step`'s new `step <id>` pattern. A `t_timed_runs` case now covers both (`STUB_NPM_RC=1`, and a tell-now report with no suites). [docker/tests/test-rehearsal.sh, t_timed_runs] (med; fix-risk low; in-story; fixed)
- [x] [Review][Patch] The last `reminder:` test used `cardsBefore`/`phoneBefore` without checking that the earlier `reminder:` test had set them. A `reminderSet` guard now does, as `approval:` and `trace:` guard theirs. [web/e2e-rehearsal/repeat.spec.ts] (low; two-way door; fixed)
- [x] [Review][Patch] The QA test title claimed "the specs run in that order" but compared a sorted set. The title is now accurate; `playwright-projects.test.mjs` pins the run order. [web/scripts/rehearsal-support.test.mjs:301] (low; mechanical; fixed)
- [x] [Review][Patch] `cmd_runs` and `cmd_run` repeated the same run-count block (Rule 2). It is now one helper, `runs_count`. [release/rehearse.sh:1759] (low; mechanical; fixed)
- [x] [Review][Defer] Story 11.14's spec (`:103`, `:124-128`) and `epic-11-context.md` still state the pre-11.12 contract: the second `runs` exits 2, and the gate calls `run --version --rc` and accepts exit 0. `run` now needs `OCUTALON_RUN_TAG`, does one phase per call and exits 4 until the last. [_bmad-output/implementation-artifacts/spec-11-14-...md:103] -- deferred: DW-548 `routed owner=11-14-the-release-sequence-runs-every-gate-on-the-pushed-candidate` (med; fix-risk low; in-epic)
- [x] [Review][Defer] Run 2 reaches step 3 through the posted `run_again` marker, not a page press. After Reject and Dismiss, the guide shows step 5 with no link (a product guide behaviour; product classes are out of this story's scope). [web/e2e-rehearsal/repeat.spec.ts:82] -- deferred: DW-545 occurrence (low; out-of-footprint for the product side)
- [x] [Review][Defer] The collector's tell-now query and its mapping of Fallback=1 to `fallback` are pinned only by name and source text. They first execute against a Fallback=1 decision in Story 38.2. [release/rehearse.sh:245-249] -- deferred: DW-534 occurrence (med; by-design: Decided in-stage 11 keeps executed checks out of CI units)
- [x] [Review][Defer] `test-rehearsal.sh` takes about 83 s alone, over the about 60 s budget. [docker/tests/test-rehearsal.sh] -- deferred: DW-535 occurrence (low)
- [x] [Review][Defer] `ci/iris.sh live online-demo-path` has not been run on the changed helpers. [web/e2e/support/demo-path.ts] -- deferred: DW-547 occurrence (low; the lead runs it at smoke)

Rejected:
- `low` `--plant <id>@<run>` beyond `--runs` is refused only at report: a dry-run-only tool, the refusal is loud and keeps the state, and an early check adds a guard.
- `low` The spec's 77 s and 80 s figures disagree: the fix would edit the spec under review. The measured figure is in DW-535.
- `low` A killed install leaves a state that later `run` calls refuse: the refusal is loud, `down` recovers, and install takes about 99 s, well inside the cap.
- `false` `run` after `down` starts a new install on the same tag: that is the design (a tag names one rehearsal; `record_write` replaces only its own section).
- `low` A `--record` spelled differently on a later call is refused: a loud exit 2 with the option named, and nothing is lost.
- `low` The 1 s clamp when `OCUTALON_E2E_TIMEOUT_MS` is under 91 s: nobody uses that configuration (default 480 s). Already rejected in the implement pass.
- `low` A `t_bounds` case ("a collector that found no decision") repeats its neighbour, and the malformed-`tellnow` path is not run: no defect follows, since a missing server line fails the run through `!havetn`.
- `low` `again:` checks the finish once without waiting: the worst case is a false fail, never a false pass, and runs 3 and later were measured passing.
- `false` No automated host runs the rehearsal specs: by design (Decided in-stage 11, DW-534). The live dry run executes them.
- `low` The default-output test of `demo-path-summary.test.mjs` checks only its first word: the five unedited tests are AC7's pin.
- `false` AC4's mutation was half demonstrated: Rule 19 asks for one demonstrated mutation per AC, and `t_bounds` went red.
- `low` (theoretical) The page's tell-now outcome and the server's could differ if one item were decided twice: one `decide` Decision per item. This would become real if an item could be re-decided.
- `low` `playwright-projects.test.mjs` was edited although Design Note 4 says it is untouched: a test case was added and no pin changed (for the lead: a footprint extension).

## Spec Change Log

## Review Triage Log

### 2026-11-01 - Review pass
- verdicts: 27 findings - high 0, medium 2, low 25, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: real-mode phone check satisfied by the approval result alone - the chat-card check on `real` is stricter and covers the reminder landing; the real-model shapes are unmeasured and deferred (item 2); a reminder-specific filter needs the real text.
  - `[low]` `[reject]` Blind: tell-now call's 90 s global budget against 240 s per-test timeouts - the 90000 is the matrix's own figure; a slow decision still FAILs the run (step run), never passes.
  - `[low]` `[reject]` Blind: a killed run has no recovery - spec-bound (a run without `passed` is a failed run: report, then down); not a user-reachable path inside one 10-minute call.
  - `[low]` `[reject]` Blind: `cmd_run` and `cmd_runs` repeat the count and refusal logic - both are tested; a refactor, not a defect; no divergence found.
  - `[low]` `[patch]` Blind: no unit test pins the `e2e:rehearsal` project - added a case to `playwright-projects.test.mjs` (lists exactly repeat and tell-now, chromium lists none, script string); mutation recorded.
  - `[low]` `[reject]` Blind: the bound also measures model determinism - the spec says so (a non-Tell-now outcome is a named miss); the row text names the outcome.
  - `[low]` `[reject]` Blind: `t_collector_names` thresholds and literal values - thresholds are a floor against reading nothing; literal values are the spec's named DW-534 residual.
  - `[low]` `[reject]` Blind: `approveOnPhone` result count - earlier results are old by the time of the press; defaults unchanged for run 1 (0 + 1).
  - `[low]` `[reject]` Edge: `--plant tell-now@k` on a no-sample run changes nothing - that run already counts as a miss, so the plant is moot, not silent.
  - `[low]` `[reject]` Edge: a negative tell-now value passes - needs a decision duration longer than the page window, which the measured runs (2032 ms inside 2035) do not show.
  - `[low]` `[reject]` Edge: the exec.count check with two Playwright calls - stays as 11.11 had it (any read through exec).
  - `[low]` `[reject]` Edge: the 1 s clamp when the timeout is under 91 s - a configuration nobody uses (default 480 s).
  - `[low]` `[reject]` Edge: `approveOnPhone` count (second sighting) - see the Blind row.
  - `[low]` `[reject]` Edge: reminder counts around an earlier reminder - measured stable in runs 2 and 3 (three rows, all fired before the count).
  - `[low]` `[patch]` Edge: collector-names item pattern `[A-Za-z]+` - widened to `[A-Za-z0-9_.-]+`.
  - `[low]` `[reject]` Edge: a plant beyond `--runs` is found at report - the spec has report refuse it (exit 2, state kept).
  - `[medium]` `[patch]` Verification gap: the relative `--record` case under `run` lost its test - restored in `t_run_steps` (four `run` calls from a caller folder); mutation recorded (dropping the `cd` turns run-steps red).
  - `[low]` `[reject]` Verification gap: the two specs have no hosted executed host - the live dry run in the loop executes both on a throwaway; DW-534 chose static checks in the hosted jobs.
  - `[low]` `[reject]` Verification gap: the approval probe is pinned by source text - the live dry run measures it per run (1.0 s); no page harness exists for the helpers.
  - `[low]` `[patch]` Verification gap: `app-chat-panel` and `app-outcome-chip` not in the page-source pins - added, mutation recorded.
  - `[low]` `[reject]` Verification gap: rare branches without a test (`summary_step` pattern, the clamp, `--candidate`) - cosmetic or unused configurations.
  - `[low]` `[reject]` Verification gap: the collector's value literals - the spec's named residual for DW-534, ledgered.
  - `[low]` `[reject]` Other: unused `skippedTitle` parameter in a summary test helper - dead test code, no assertion affected.
  - `[low]` `[reject]` Other: `npm.env.all` accumulates in `t_timed_runs` - each assertion reads the latest call of the run under test; mutations went red.
  - `[medium]` `[patch]` Intent: a fallback decision (Outcome tellnow, Fallback 1) counted as a Tell-now sample, a false all-clear on the bound - the collector reads Fallback and reports the outcome `fallback`; collector-names pins it and two bounds cases cover it; the live dry run still reads tell-now 0.9 to 1.0 s.
  - `[low]` `[defer]` Intent: run 2 posts the run_again marker instead of pressing Run again - already deferred item 1 (the guide's behaviour after Dismiss made the spec's premise false; the result is the spec's expected state).
  - `[low]` `[reject]` Intent: shared helpers changed under CI and the per-call timeouts - defaults unchanged, the live demo-path unit passes unchanged.

## Design Notes

**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-15 | The splits and the notice; unchanged from 11.11, now over N runs. |
| AD-12 | The guide is server-derived: Run again and the replay rule come from `Demo/Guide.cls`, which the repeat only reads through the page; the page's arrival is measured on the page clock. |
| AD-14, AD-30, AD-32 | The tell-now item is an untrusted mailbox Item; its ItemDecision and Notification reach the web chat and the simulated phone. |
| AD-20 | `Decision.DurationMs` is the decision call's own duration; `Usage.LargestRequestTokens` as before. |
| AD-22 | Dry runs on throwaways, the CI mock, no key; the mock's marker scenario; nothing changes in CI's units or matrix. |
| AD-19, AD-25 | No value in the output; every remote action through `host_run`, the specs' IRIS reads through `exec`. |
| AD-29 | `release/` is Lane A's. The new `web/e2e-rehearsal/`, `web/playwright.rehearsal.config.ts`, the `web/package.json` script, `web/tsconfig.e2e.json` and the helper extensions use Epic 11's REL-2 exception; no product class or text changes. |

No AC contradicts an AD.

**The tell-now measurement (Decided in-stage 1).**
- FR-1's 5 s runs from the decision to the notice (Story 2.7's CI check: "within 5 seconds of its decision"), on the web chat and the phone.
- No single clock holds both ends. The decision happens on the server, and the arrival happens on the page.
- So: `tell-now` = (`tellnow_seen` - `tellnow_sent`, both page marks of one page) - `DurationMs` (the decision call's own duration, measured on the server).
- This subtracts a duration from a duration. No mark of one clock meets a mark of the other, so 11.11's rule holds. A clock offset cancels, and a rate difference over a few seconds is negligible.
- The model call lies inside [send, notice]. So the value equals (send to the call's start) + (the call's end to the notice seen). That is an upper bound of the decision-to-page time: a miss can be a false fail, never a false pass. It is also the same kind of bound as `approval-result`.
- The pure page time (send to seen) would include the model's own 2 to 8 s. On the real model it would routinely fail a bound that FR-1 does not set, so it was rejected.
- `tellnow_seen` is the moment both the card and the phone message show, so the bound is the later of the two.

**The tell-now item (Decided in-stage 2).**
- It is an email through the mailbox's compose form, the path MB3 already proves on the mock.
- On the mock, the marker `[[mock:mail-tell-now]]` scripts Tell now. On the real model, it is the eval set's `mail-endpoint-move-tomorrow`, whose expected outcome is `tellnow` and which the release-candidate eval gate (11.14) checks per candidate.
- That the real model decides Tell now for it in each rehearsal run is (inference). When it does not, the run is not a sample, the row says so, and nothing is claimed.
- The run stamp `Rehearsal run <k>: ` goes at the start of the subject, because Intake's Summary cuts "{Sender}: {Subject}" at 80 characters.

**Which specs repeat (DW-522; Decided in-stage 3).**
- Specs 01 to 08 run once, in run 1, on the fresh install. Their first-run counts and 07's and 08's once-per-install paths (the refusal seam, the rejection, the replay, the mailbox samples) need one, and their files do not change.
- Runs 2 to N run `repeat.spec.ts`, which faces the facts the epic context lists:
  - Run again reopens only steps 3 to 5, so steps 1 and 2 go through the composer (the decision and reminder samples per run);
  - the replay rule needs the previous incident resolved, so every run approves its own, and run 2 first rejects and dismisses 07's pending replay;
  - every count is relative or scoped to the run's card.
- The tell-now spec runs in every run.

**Smaller decisions (Decided in-stage).**
4. **The rehearsal project lives outside `web/e2e/`**, with its own Playwright config. So the `chromium` project, `web/playwright.config.ts` and its pin `web/scripts/playwright-projects.test.mjs` are untouched, and CI never runs it.
5. **One summariser.** `demo-path-summary.mjs` gains `--steps` rather than a near-copy (Rule 2). The repeat names its step through its test titles (`watch: ...`), so a FAIL line names the step, as AC3 needs.
6. **`runs` refuses after a failed run.** The install's state is then unknown, and the rehearsal has already failed. Story 11.14 already goes from a non-zero `runs` straight to `report`.
7. **`run` does one phase per call, with exit 4 "call again"** (DW-537: N runs in one process passed the 10-minute call cap, which a dry `--runs 3` would trip). It needs a fixed `OCUTALON_RUN_TAG`. 11.14 drives the phases itself, so no consumer reads `run`'s old loop.
8. **`--plant <id>@<run>`** plants a miss in one later run, as the AC's "planted missed bound in a later run" needs. A bare `<id>` keeps 11.11's meaning.
9. **The approval helpers take a card.** On a repeat, the old probe would read an earlier, approved card and mark at once, which is a false pass. With the default card, today's behaviour is unchanged.
10. **Run 1's Playwright budget is split** (REL-2 `OCUTALON_E2E_TIMEOUT_MS` - 90000, tell-now 90000), so run 1 keeps 11.11's one-call bound. 11.11 measured the REL-2 run at 150 s on the mock; the real model's run 1 within 390 s is (inference). Story 38.2 can raise the variable.

**DW-534 (the collector and the probes; Decided in-stage 11).**
- Running the collector, or the marks, inside a CI unit would change the demo-path unit. The browser group is at 28 to 30 of REL-4's 35 minutes, and the epic forbids a behaviour change there.
- So the check that runs "where a change would show" is static, in the hosted jobs, within the budget:
  - `collector-names` ties every name the collector reads to `src/` (renamed tables, columns, body classes, item names);
  - the node test ties every probe to its page source (selectors and wording).
- Residual, for the lead to ledger: what the queries mean (for example a header order) is still executed only in the live dry run and in each candidate's rehearsal gate. `reopen_if`: a live dry run reports a `CHK|missing|` line with every name check green.

**Interface (Rules 1 and 2).**

| Link | Who |
| --- | --- |
| Consumes | 11.11's `rehearse.sh` (`runs`, `exec`, the collector, `bounds_eval`, `report`, `--runs`, `--plant`), `demo-path.ts`, `rehearsal.ts`, `devices.ts`, `demo-path-summary.mjs`, `iris.ts`; the eval case; the product's guide, Break the feed, mailbox, Decision and Notification records (live, in the dry run) |
| Consumed-by | Story 11.14's rehearsal gate: `install`, `runs` until 20 (exit 2 beyond), `report`, `down`; `Result: pass` only |
| Consumed-by | Story 38.2: the real 20 runs on the droplet, with `--runs 20` (one `runs` per call, or `run` stepped) |
| Consumed-by | Story 11.13's notes: the rows and `### Runs`, copied verbatim |

- **Integration ACs:**
  - AC5: `report` consumes runs 1..N through `bounds_eval`, and 11.14's loop contract is `runs`' refusal beyond N;
  - AC1, live in the dry run: the rehearsal specs consume the extended `demo-path.ts` helpers and the exec channel against a real install.

**Extend, don't copy (Rule 2).**
- **Extended:**
  - `phase_runs`, `cmd_runs`, `cmd_run`, `COLLECTOR`, `BOUNDS_AWK`, `plant_ok`, `summary_step`, `real_guards`;
  - `watchThroughGuide`'s marks (into `markedSend`);
  - `pressOnPhone` and `approveOnPhone`;
  - `demo-path-summary.mjs`;
  - both self-tests.
- **Copied, with reasons:**
  - 08's restore-and-`WaitRecords` `afterAll` (about 4 lines): spec files do not change;
  - `mailbox.spec.ts`'s `compose()` steps (about 5 lines): a private function of a demo-switch spec, which this story does not edit.

**Ledger inbox (Rule 17).**
- **DW-522** is resolved by design (Decided in-stage 3). The adjudication evidence is run 2 of the dry run.
- **DW-534** is addressed by AC8, with the residual named above.
- **DW-537** (related, `wontfix-accepted`) is addressed by Decided in-stage 7. Its `reopen_if` ("a dry `run` call exceeds 600 s") cannot trip, because a call is one phase.
- **DW-538** is closed by rule `run-steps`.

**Contended paths (U14).**
- Re-checked at plan time:
  - open branches are OCT-epic12, 13, 15 and 30;
  - Epic 29 and Epic 31 are merged into the feature branch;
  - OCT-epic4 holds only bookkeeping.
- Only Epic 12's `web/e2e/demo-path/telegram-page.spec.ts` touches this area, and it is unchanged here.
- **Footprint extensions (report them in the completion contract):**
  - `web/e2e-rehearsal/**` (new);
  - `web/playwright.rehearsal.config.ts` (new);
  - `web/package.json` (one script);
  - `web/tsconfig.e2e.json` (two includes);
  - `web/scripts/demo-path-summary.mjs` and its test.

**CI budget (REL-4).**
- No unit is added, and `ci/units.sh` is unchanged.
- The hosted `checks` job's `test-rehearsal.sh` grows from about 36 s; keep it under about 60 s alone, sharing the 20-run states between rules.
- The `web` job gains a few node tests (about 1 s).
- The browser units are unchanged. A `web/` change runs the bundle-reading groups as any web change does (`ci/changes.sh`).

**Split check.** One implement pass holds this (the shape of 11.11), so no split is proposed. 11.3's line keeps 2 of its 6 children used.

## Verification

All commands run from the worktree root, each in its own foreground call with `timeout: 600000`.

Live calls carry lane A's variables, with tag `e11s12d` for the dry run and `e11s12p` for the CI unit:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a"
OCUTALON_TEST_WEB_PORT=52801
OCUTALON_LOCK_OWNER='epic=11 stage=implement'
OCUTALON_RUN_TAG=e11s12d
```

Run `ci/iris.sh build` once first if `web/src` changed since the bundle was built.

**Commands:**
- `(loop)` `bash docker/tests/test-rehearsal.sh` -- expected: every rule passes (`run-steps` and `collector-names` among them), exit 0.
- `(loop)` `node --test web/scripts/rehearsal-support.test.mjs web/scripts/demo-path-summary.test.mjs` -- expected: exit 0.
- `(loop)` `npm --prefix web run lint` -- expected: exit 0 (tsc covers `e2e-rehearsal/`).
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(loop)` The live dry run, one call per phase:
  1. `bash release/rehearse.sh install --dry-run --rc 1 --runs 3 --record "${TMPDIR:-/tmp}/e11s12-dry/rc1.md"` -- expected: every install row passes.
  2. `bash release/rehearse.sh runs` -- expected: `PASS run 1`, and a `RUN 1` line with `tell-now=`.
  3. `bash release/rehearse.sh runs` -- expected: `PASS run 2`.
  4. `bash release/rehearse.sh runs` -- expected: `PASS run 3`. A fourth `runs` refuses, exit 2.
  5. `bash release/rehearse.sh report` -- expected: `RESULT dry run`, exit 3.
  6. `bash release/rehearse.sh report --plant pick-up@3` -- expected: the run-3 FAIL line, `RESULT fail`, exit 1.
  7. `bash release/rehearse.sh down` -- expected: `TEARDOWN`.
  - Then `docker ps -a --format '{{.Names}}' | grep -c e11s12d` prints 0, and the lane folder holds no lock of the run. If anything is left, run `ci/iris.sh teardown` with the same tag and lane variables.
  - Record Task 0's figures here.
- `(once)` `npm --prefix web test` -- expected: every node test passes.
- `(once)` `ci/iris.sh live demo-path` (a fresh throwaway, tag `e11s12p`) -- expected: passes unchanged (AC7).
- `(once)` `bash ci/checks.sh`, split by script if one call would pass the cap (11.11 measured about 14 minutes in one call) -- expected: every script passes.

**Mutations to demonstrate (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**
- AC1: run k ≥ 2 calls `e2e:demo-path` again -> `t_timed_runs` argv case red.
- AC2: the tell-now value without the `DurationMs` subtraction -> `t_bounds` tell-now cases red.
- AC2b: an outcome other than `tellnow` counted as met -> the `decided digest` case red.
- AC3: `runs` allowed after a failed run -> `t_timed_runs` refusal red.
- AC4: `@<run>` ignored (every run planted) -> the live planted report names `run 1,2,3`, and `t_bounds` plant case red.
- AC5: the tell-now row left `not run` -> the real all-pass case reads `not run`.
- AC6: `run` doing two phases in one call -> `run-steps` red.
- AC7: `approval_result_seen` reading `incidentCard(page)` again -> the node source pin red. Separately, `demo-path-summary.mjs`'s default output changed -> its existing tests red.
- AC8: a collector column renamed to a missing name -> `collector-names` red. A probe wording changed -> the node pin red.

**Shared surfaces:**
- `watchThroughGuide`, `pressOnPhone` and `approveOnPhone` (the demo-path and online demo-path units).
- `demo-path-summary.mjs` (the demo-path unit).
- `rehearse.sh`'s `runs` and `run` interface and its section rows and table (Stories 11.14, 11.13, 38.2).
- `web/tsconfig.e2e.json` (lint) and `web/package.json` scripts.
- Every test added or changed passes on a fresh environment, in either order: the self-test builds its own repository, stubs and run folders; the node tests use their own files; the dry run brings up its own throwaway and removes it.

### Implement stage (2026-11-01; lane A, `ocutalon-slot-a` untouched, throwaway tags e11s12d and e11s12p)

Loop results at hand-off:
- `bash docker/tests/test-rehearsal.sh`: all 19 rules pass (`run-steps` and `collector-names` among them), about 77 s alone on the developer machine.
- `node --test web/scripts/rehearsal-support.test.mjs web/scripts/demo-path-summary.test.mjs`: 68 tests pass. `npm --prefix web test`: 1185 tests pass. `npm --prefix web run lint` and `bash docker/tests/test-boundaries.sh`: exit 0.
- Every script of `ci/checks.sh` passed, run by script in two calls (boundaries, storage, class-rules, ci-config, ci-changes, compose-file, pinned-sources, after-start, healthcheck, lib-live, bootstrap, demo-path-gate; then ci-warm, probe, install-script, readme, eval-set, online-host, online-load, upgrade-harness; rehearsal above).
- `ci/iris.sh build` once, then `ci/iris.sh live demo-path` (fresh throwaway, tag e11s12p, 4 min 16 s): `20 passed`, 2 skipped (the Telegram parts), `test-demo-path: all checks passed` (AC7). No container, image or lock of either tag remained.
- The live dry run, one call per phase (`install --dry-run --rc 1 --runs 3 --record <tmp>/rc1.md`, `runs` x3, a fourth `runs`, `report`, `report --plant pick-up@3`, `report --plant pick-up@4`, `down`): install 88 s, every row passes; `PASS run 1 demo path: ...; REHEARSAL 1 of 1 steps ran ...` with `RUN 1 ... tell-now=1.0 ...`; `PASS run 2 rehearsal` and `PASS run 3 rehearsal`; the fourth `runs` printed `REFUSED runs: 3 of 3 runs done; run report`, exit 2; `report` printed `RESULT dry run`, exit 3, every met row `dry run` (tell-now included), the runs row `3 of 3 runs passed` and the `### Runs` table with its `Tell now` column; `report --plant pick-up@3` printed `FAIL run 3 step incident bound pick-up 15 s (planted): 1.2 s in run 3 ...`, `RESULT fail`, exit 1, the record holding one section; `--plant pick-up@4` exit 2; `down` printed `TEARDOWN`, then 0 containers, 0 images, no state folder and an empty lane folder for the tag. No `ssh` ran.

**Task 0, measured on the dry run (developer machine, Docker Desktop, arm64, tag e11s12d, lane A, CI mock):**
- Seconds: `runs` call 1 took 3 min 12 s (the REL-2 Playwright call 3.0 min, the tell-now call 10.4 s inside it); call 2 took 1 min 24 s (Playwright 1.4 min); call 3 took 1 min 20 s (1.3 min). Install 88 s. `report` and `down` under 7 s each.
- `exec.count`: run 1 30 (both Playwright calls), run 2 10, run 3 8.
- Run 2's start state: 07's replay request pending (the one pending request on the phone). `again:` rejected it on the phone and dismissed its incident; Break the feed was then active (Dismiss asserts it), but the guide read step 5 ("Next: Open the incident's trace") with no finish and no Run again button, because run 1's opened trace is still set. The spec's "guide reads step 3 current" holds only after Run again, so run 2 posts the run_again marker (deferred item 1); runs 3 and later press the Run again button on the finish, and the guide reads "Step 3, Break the feed, current".
- A composer-sent watch prompt on a watched session gets a decided reply (strip with the Act chip and the mock's reason), and the "Orders production" check row stays one (`watch:` passed in runs 2 and 3).
- The reminders: three rows in the end, all fired, none pending, so the Reminders list (pending ones) holds only the run's own reminder; the repeat's count is relative anyway (`reminder:` passed). The reminder landed in the chat and on the phone within 90 s in runs 2 and 3 (46 s after the call that set it).
- The tell-now item's `DurationMs` against its headers (ms): run 1 2032 inside `Decide` request 01.630 to `DecisionResponse` 03.665 (2035); run 2 2032 inside 29.962 to 31.998 (2036); run 3 2031 inside 54.469 to 56.505 (2036). The tell-now value per run: 0.9 s (first attempt), 1.0 s, 1.0 s, 1.0 s.
- The notice card and the phone message hold the run stamp (`Rehearsal run <k>: `) in all three runs (`tell-now:` asserts one card and one phone message that hold it, and the card holds "Why now:").
- Run values of the reported set: notice 10.6 to 10.8 s, pick-up 1.1 to 2.8 s, settle-end 10.1 to 10.4 s, largest request 3,657 to 4,247 tokens; reminder minus result is -1.0 s in run 1 and +47.0 s in runs 2 and 3 (the repeat sets its reminder before the incident, so it lands after the result; recorded only).
- The reminder-result phone message and the result message matched on the mock in all three runs (no `CHK|missing|` line). The collector's reminder and result text matches (11.11 deferral) remain mock-only.

**Mutations demonstrated (Rule 19; each applied from a backup, red observed, reverted byte-identical by md5):**
- mutation: AC1: run k >= 2 calls `e2e:demo-path` again -> `test-rehearsal.sh` rules timed-runs and run-steps red (the argv case).
- mutation: AC2: the tell-now value without the `DurationMs` subtraction -> rule bounds red (the tell-now cases).
- mutation: AC2b: an outcome other than `tellnow` counted as met -> rule bounds red (the `decided digest` cases).
- mutation: AC3: `runs` allowed after a failed run -> rule timed-runs red (the refusal).
- mutation: AC4: `@<run>` ignored (every run planted) -> rule bounds red (`pick-up@17` and `notice@3`); the live planted report was run with the right plant only.
- mutation: AC5: the tell-now row left `not run` -> rules bounds, timed-runs and run-steps red (the real all-pass case reads `not run`).
- mutation: AC6: `run` doing two phases in one call (`exit 4` of `run_next` made a return) -> rule run-steps red.
- mutation: AC7: `approval_result_seen` reading `incidentCard(page)` again -> `rehearsal-support.test.mjs` source pin red; `demo-path-summary.mjs`'s default `DEMO-PATH` line changed -> six tests of `demo-path-summary.test.mjs` red (five existing, unedited, and the new default-output test); the `--steps` summary counting a skip as ok -> its test red.
- mutation: AC8: a collector column, table, message body class or production item renamed to a missing name (four mutations) -> rule collector-names red each time; the wording of `answered.approved` in `catalog.ts` changed and `class="text"` in `ocutalon-reply.ts` changed -> the page-source pins red.
- mutation: the reply probe no longer counting replies, and `mark('tellnow_sent')` moved off the Send click -> their source pins red; the collector's `@RUN@` substitution dropped -> rule timed-runs red; the tell-now server line's missing-mark branch dropped -> rule bounds red.
- mutation (review pass): the collector's tell-now outcome read from Outcome alone (the Fallback column dropped) -> rule collector-names red; a `fallback` outcome beside 19 samples is within the allowance and two fail the row (rule bounds, new cases).
- mutation (review pass): `run`'s first call without `cd "$reh_caller_pwd"` -> rule run-steps red (the relative --record case: the second call is refused and the record is not in the caller's folder).
- mutation (review pass): `playwright.rehearsal.config.ts` with `testDir: './e2e'` -> `playwright-projects.test.mjs` rehearsal case red; `app-outcome-chip`'s selector renamed in `web/src` -> the page-source pin red (reverted, `web/src` byte-identical).
- Review pass, after the patches: the live dry run again (install, `runs` x3, a fourth `runs` refused with exit 2, `report` `RESULT dry run` exit 3, `report --plant pick-up@3` the run-3 FAIL line, `down`) with the changed collector: `tell-now=1.0`, `0.9`, `0.9` (Fallback 0 on the mock reads as `tellnow`); no container or lock left. `npm --prefix web test` 1186 pass; `ci/iris.sh live demo-path` passes; every script of `ci/checks.sh` passes, run by script.

### QA stage (2026-11-01; hermetic only, no IRIS, no live run; each mutation applied from a backup in the scratchpad, red observed, restored, tree checked unchanged)

- `(QA)` `web/scripts/rehearsal-support.test.mjs` -- new describe "(QA) the rehearsal specs agree with release/rehearse.sh" (3 tests, in the default `npm --prefix web test`): the tell-now spec's subject stamp equals the prefix the collector selects the email by (`Rehearsal run <k>: `, which no test tied across the two files); every `--steps` id of `rehearse.sh` is a spec file of the rehearsal project; every test title of `repeat.spec.ts` and `tell-now.spec.ts` starts with the step id a FAIL line names, in order, and the bound steps are read from the script's `nsteps`.
- mutation (AC1): `runs` k >= 2 calls `e2e:demo-path` -> `test-rehearsal.sh` rules timed-runs and run-steps red.
- mutation (AC2): the tell-now value without the `DurationMs` subtraction -> rule bounds red ("the decision's duration is subtracted").
- mutation (AC3): `runs` allowed after a failed run -> rule timed-runs red ("a run after a failed run is refused").
- mutation (AC4): `@<run>` ignored in the plant -> rule bounds red (`pick-up@17`, `notice@3`, tell-now plant in run 2).
- mutation (AC5): the tell-now row's met status left `not run` -> rules bounds, timed-runs, dry-report and run-steps red (the real all-pass case).
- mutation (AC6): `run_next` returns instead of `exit 4` (two phases in one call) -> rule run-steps red.
- mutation (AC7): `approval_result_seen` reading `incidentCard(page)` -> `rehearsal-support.test.mjs` source pin red. Separately the default `DEMO-PATH` line changed in `demo-path-summary.mjs` -> six `demo-path-summary.test.mjs` tests red.
- mutation (AC8): a collector column renamed (`DurationMs` -> `DurationMz`) -> rule collector-names red; `answered.approved` reworded in `catalog.ts` -> the page-source pin red (`web/src` restored byte-identical).
- mutation (QA pin): the tell-now spec's stamp changed -> the new stamp test red.
- After restoring: `node --test` 71 pass, `npm --prefix web test` 1189 pass, `test-rehearsal.sh` all 19 rules pass, `test-boundaries.sh` pass.

### Code review stage (2026-11-01; lane A, throwaway tag e11s12c; each mutation applied from a backup in the scratchpad, red observed, restored byte-identical by md5)

- mutation (review, AC3): `e2e_call`'s `elif "$e2e_rc"` branch disabled, and `summary_step`'s `step <id>` line deleted -> rule timed-runs red (both new assertions: "Playwright exited 1 although the summary found no failed step" and "step tell-now has no tell-now.spec.ts in the report").
- mutation (review, the reply probe): `step1_reply_seen` reading the page's last `[data-part="reply"] .text` again -> `rehearsal-support.test.mjs` "the reply probe counts replies" red.
- mutation (review, the landed reminder on the real model): `landedPhone` back to `hasNot: page.getByRole('button')` -> `rehearsal-support.test.mjs` "a fired reminder reads \"Reminder: {text}.\"" red.
- After restoring: `node --test` on rehearsal-support, demo-path-summary and playwright-projects: 99 pass. `npm --prefix web run lint`: exit 0. `test-rehearsal.sh`: all 19 rules pass, 83 s alone.
- Live, after the patches: `install --dry-run --rc 1 --runs 2` (99 s, every row passed); `runs` run 1 (2 min 27 s: `PASS run 1`, `tell-now=0.9`, `first-reply=1.1`); `runs` run 2 (1 min 24 s: `PASS run 2 rehearsal`, `first-reply=1.0`, decision 1.0 s); a third `runs` refused, exit 2; `report` `RESULT dry run`, exit 3, runs row `2 of 2 runs passed`; `down` `TEARDOWN`. No container, volume, image or lock of the tag remained.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented.** `release/rehearse.sh runs` runs the next run per call (run 1: the REL-2 project then the tell-now spec; runs 2 to N: the new rehearsal project, `repeat.spec.ts` then `tell-now.spec.ts`), refuses beyond `--runs` or after a failed run, and writes `passed` last. The collector reports the tell-now item's outcome and duration; the tell-now bound is measured (page time between `tellnow_sent` and `tellnow_seen` less the decision's `DurationMs`), and an outcome other than `tellnow` is a named miss, never met. `report --plant <id>@<run>` plants a miss in one run. `run` does one phase per call (exit 4, `NEXT run:`). DW-534: `collector-names` (rehearsal check) and the page-source pins tie the collector's names and the probes to their sources. DW-522: run 2 rejects and dismisses 07's pending replay (and posts the page's `run_again` marker, deferred item 1); runs 3 and later press Run again.

**Files changed.**
- `release/rehearse.sh`: `runs`, `run`, the collector, `BOUNDS_AWK`, `--plant <id>@<run>`.
- `docker/tests/test-rehearsal.sh`: rules `run-steps` and `collector-names`; updated and new cases.
- `web/e2e-rehearsal/repeat.spec.ts`, `web/e2e-rehearsal/tell-now.spec.ts`, `web/playwright.rehearsal.config.ts`, `web/package.json` (`e2e:rehearsal`), `web/tsconfig.e2e.json`: the rehearsal project.
- `web/e2e/support/demo-path.ts`, `web/e2e/support/rehearsal.ts`: `markedSend`, `sendThroughComposer`, optional card parameters (defaults unchanged).
- `web/scripts/demo-path-summary.mjs` (`--steps`), `web/scripts/demo-path-summary.test.mjs`, `web/scripts/rehearsal-support.test.mjs`, `web/scripts/playwright-projects.test.mjs`: tests and pins.

**Review (first pass, four layers, 27 findings: high 0, medium 2, low 25).** Patched: a fallback decision no longer counts as a tell-now sample (the collector reports the outcome `fallback` when the decision's Fallback flag is set; medium); the relative `--record` case under `run` is back in `run-steps` (medium); the rehearsal Playwright project's listing is pinned; the page-source pins cover `app-chat-panel` and `app-outcome-chip`; the collector-names item pattern accepts digits, dots, hyphens and underscores. Deferred: none new (the four implement-stage items stay). Rejected, each with its reason in the triage log: low, rare, spec-bound or covered by the live dry run.

**Verification.** Loop commands green after the patches (`test-rehearsal.sh` all 19 rules, node tests, lint, boundaries, the live dry run on a lane-A throwaway). Once-lines: `npm --prefix web test` 1186 pass, `ci/iris.sh live demo-path` passes unchanged, every `ci/checks.sh` script passes (by script). Mutations are recorded under Verification.

**Follow-up review recommended: true.** Two medium findings were patched in the first pass. The unverified risk: the `fallback` route of the collector runs only on the CI mock, where Fallback is 0; the first real-model rehearsal (Story 38.2) is the first time it sees a Fallback=1 decision.

**Residual risks.** Real-model texts and the collector's value literals are unmeasured until Story 38.2 (deferred items 2 and the DW-534 residual in Design Notes); `test-rehearsal.sh` takes about 80 s alone (deferred item 3); `ci/iris.sh live online-demo-path` was not run (deferred item 4).
