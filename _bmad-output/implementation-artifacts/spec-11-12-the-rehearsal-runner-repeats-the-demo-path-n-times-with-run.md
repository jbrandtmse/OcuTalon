---
title: 'Story 11.12: The rehearsal runner repeats the demo path N times with Run again (runs 2 to N, the replay rule, the tell-now item and its bound; dry runs on throwaways)'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-11-the-rehearsal-runner-times-the-demo-path-and-checks-every-bo.md'
warnings: ['oversized']
deferred: []
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

## Spec Change Log

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only; nothing is implemented. The spec passes the READY-FOR-DEVELOPMENT standard. No intent gap: every bound, tell-now included, has a measurement point (Design Notes, "The tell-now measurement"), so the Rule 5 tripwire did not fire. The ledger inbox is addressed: DW-522 by design, DW-534 by AC8 with a named residual, and DW-537 and DW-538 by `run`'s one phase per call. Eleven choices are recorded under Design Notes as "Decided in-stage". The footprint extensions are listed there for the completion contract.
