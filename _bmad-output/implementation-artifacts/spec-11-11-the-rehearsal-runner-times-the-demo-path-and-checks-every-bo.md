---
title: 'Story 11.11: The rehearsal runner times the demo path and checks every bound (one timed run, the splits and every bound; dry runs on throwaways)'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_revision: '5e6e7a528527c4cdfdff6e124aa75ce171c6aa36'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-3-the-clean-machine-rehearsal-installs-and-times-the-demo-path.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The collector finds the reminder's phone message by the reminder row's Text inside the phone message text and the result message by "went through."; both were measured on the CI mock only, so on the real model a different rendering makes a run fail with a missing reminder_msg mark rather than pass.
    evidence: |-
      Story 38.2's first real run (or Story 11.12) confirms the match.
    location: >-
      release/rehearse.sh (COLLECTOR)
    severity: low
  - summary: >-
      The collector's queries and the page-mark probes (the strip's .reason count, the newest reply's .text, the status wording "Approved from the simulated phone at") run only in the manual live dry run; no CI unit executes them, so a product schema, message-body or wording change breaks the rehearsal's marks unseen until someone runs a dry run.
    evidence: |-
      Every hermetic test answers the collector with a canned file, and every CI browser unit runs with OCUTALON_E2E_MARKS unset, so markWhen never calls its probe there.
    location: >-
      release/rehearse.sh (COLLECTOR), web/e2e/support/demo-path.ts
    severity: medium (unverified)
  - summary: >-
      docker/tests/test-rehearsal.sh takes about 36 s alone (48 s inside ci/checks.sh) against the roughly 5 to 10 s the CI budget note inferred.
    evidence: |-
      The stub installs, the 20-run states and the bounds rule that runs twice for its synthetic break. It stays in the hosted checks job; Story 11.12 may share the 20-run states if the job needs the time.
    location: >-
      docker/tests/test-rehearsal.sh
    severity: low
---

<intent-contract>

## Intent

**Problem:** Story 11.3's `release/rehearse.sh` installs a candidate and records the first start, but its `demo path runs` row is `not run`: nothing drives the REL-2 specs against the installed candidate, times them, splits Break the feed to the incident notice, or checks a bound. A real rehearsal therefore cannot pass, and this build has no clean host and no real key, so the timing machinery must be proved on throwaways without ever claiming a bound passed.

**Approach:** Add a `runs` phase between `install` and `report`. Each call runs one timed run:
- The driver (this machine) runs the REL-2 project (`web/e2e/demo-path/`) against the installed candidate's address. The specs reach IRIS only through a new `rehearse.sh exec` channel, which goes through `host_run clean`.
- Two helpers in `web/e2e/support/demo-path.ts` leave page marks in a file, and only when the rehearsal asks for them.
- A read-only collector then reads the run's production message headers and records through the same channel.
- `report` turns every run's marks into the splits and every bound. It writes the rows and a per-run table, prints `FAIL run <run> step <step> bound <bound>: <detail>` for each miss, and fails the rehearsal.
- A dry run proves this on lane A's throwaway with the CI mock and N = 1, and `report --plant <bound>` plants a missed bound.

The repeats (runs 2 to N with Run again and the replay rule) and the per-run tell-now item go to a proposed sibling, Story 11.12 (Design Notes, Proposed split).

## Boundaries & Constraints

**Always:**
- **Everything 11.3 fixed still holds:**
  - the no-value rule: no `.env` or configuration value in the output or the record; `docker compose config` only with `--quiet`, `docker inspect` only with `--format`;
  - `host_run` for every remote action, with strict host keys;
  - Bash 3.2, ASCII only, `umask 077`, mode 100755, main only when executed;
  - the FAIL grammar;
  - the Result rules and exit codes (0 a real pass only; 1 fail or not run; 2 refusal; 3 dry run; 75 lane lock busy);
  - machines named only by OS, CPU architecture and memory.
- **One clock per measurement.** Every derived time subtracts two marks of the same clock:
  - `server`: production message headers and rows, read in the clean host's IRIS;
  - `page`: `Date.now()` on the driver, in one Playwright page.
  - No value ever subtracts a page mark from a server mark.
- **No false all-clear.**
  - A missing mark, an unreadable value, or a run with no noticed incident fails the run's step: `FAIL ... bound -: <what is missing>`.
  - In a dry run, a bound row whose measurement is within its limit reads `dry run`, never `pass`.
  - In real mode, `Result: pass` needs the required number of runs (at least 20) and every row passed. The tell-now row is `not run` until Story 11.12, so a real run cannot pass before then.
- **The marks are inert unless asked for.** With `OCUTALON_E2E_MARKS` unset, the two helpers wait for nothing new and write nothing, and `iris.ts` with `OCUTALON_E2E_IRIS_EXEC` unset spawns exactly today's `docker exec`. So every CI browser unit (demo-path, online-demo-path) behaves as before.
- **The collector only reads.** It runs SQL `SELECT`s and property reads, and prints `CHK|` lines. It never writes a row, a global or a setting.
- **Every command fits one 10-minute call.** One `runs` call is one run, bounded by `OCUTALON_E2E_TIMEOUT_MS` (default 480000).

**Never:**
- Contact a real host, use a real model key, or claim that a real bound passed. The real 20 runs are Story 38.2's.
- Build runs 2 to N, Run again, the replay rule between runs, or a tell-now item. These are the proposed Story 11.12's.
- Change a demo-path spec file (`web/e2e/demo-path/*.spec.ts`), `web/playwright.config.ts`, `web/package.json`, any product class, or any user-visible text.
- Touch an open epic's file: `docker/tests/lib-live.sh` (Epic 12), `web/e2e/demo-path/telegram-page.spec.ts` (Epic 12), `release/standalone-bridge.sh` (Epic 13), `release/ipm-install.sh`, `release/ipm/**`, `src/module.xml` (Epic 15), `.github/workflows/*`. `ci/units.sh` is not changed at all.
- Write into `release/records/` from a test or a verification run (always pass `--record <tmp file>`). Make the rehearsal a CI unit.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Timed run | `runs` after a passed `install`, no run yet | Runs run 1: `npm --prefix web run e2e:demo-path` on this machine with `OCUTALON_URL=<origin>`, `OCUTALON_E2E_JSON`, `OCUTALON_E2E_MARKS`, `OCUTALON_E2E_IRIS_EXEC`, `OCUTALON_DEMO_PATH_MODEL` (`mock` in a dry run, `real` in real mode) and `OCUTALON_E2E_TIMEOUT_MS`. Then `node web/scripts/demo-path-summary.mjs --only-telegram-skips` on the report, then the collector. Prints `PASS run 1 demo path: <summary's DEMO-PATH line>` and one `RUN 1 <bound>=<value> ...` line | A summary FAIL: `FAIL run 1 step <step id of the failed spec> bound -: <its reason>`, and the run's collector still runs. Nothing read through `exec`: `FAIL run 1 step run bound -: the specs read nothing through the rehearsal's exec channel` |
| Next run | `runs` when run 1 exists | One refusal line: run 2 and later (Run again and the replay rule) come with Story 11.12; exit 2 | Nothing starts |
| Order | `runs` or `exec` with no state, or after a failed install | One refusal line; exit 2 | `report` and `down` behave as in 11.3 |
| Real-mode guards | real mode and `REHEARSAL_DRIVER_SSH` is not `local`; or `web/e2e`, `web/playwright.config.ts`, `web/package.json` or `web/package-lock.json` differ from the candidate commit (HEAD or working tree); or `--runs` below 20 | Refused at option parsing (`plan`, `install`, `run`), naming the key, the paths or the option; exit 2 | Nothing starts |
| Exec channel | `printf 'Write !,"CHK|x|1"\nHalt\n' \| bash release/rehearse.sh exec [<namespace>]` | `host_run clean "cd ocutalon-rehearsal/candidate && docker compose exec -T iris iris session IRIS -U <namespace, default OCUTALON>"` with the script on stdin. Its output goes to stdout, not to `output.log`, and the run's `exec.count` grows by one | A bad namespace (not `[A-Z][A-Z0-9]*`): exit 2 |
| Splits | the run's marks | `notice`, `pick-up`, `settle-end`, `diagnosis` and `delivery` from the Bounds table (Design Notes), in seconds with one decimal | A missing mark fails that bound's step for that run |
| Bounds over N runs | marks of runs 1..N | "Every run" bounds fail on any miss. "19 of 20" bounds fail when more than floor(N/20) runs miss. The median of `notice` is recorded against the typical 35 s | The FAIL line names every run that missed, comma-separated, ascending, as `run 3,9` |
| Planted bound | `report --plant <bound id>` (or `run --plant`), dry run only | That bound's limit becomes 0 (0 tokens for `largest-request`). The row and the FAIL line add `(planted)`. `Result: fail`; exit 1 | `--plant` in real mode, or an unknown id: exit 2 |
| Report again | `report` after an earlier `report` with the same tag | The section is rebuilt from the state and replaces itself. `install` stays once per tag | -- |
| Dry run, end to end | install, runs, report, `report --plant pick-up`, down (each its own call; the `--dry-run --rc 1 --record <tmp>` given to install) | report: `RESULT dry run`, exit 3. The runs row passes, every met bound row reads `dry run`, and tell-now reads `not run`. Then `--plant pick-up`: `FAIL run 1 step incident bound pick-up 0 s (planted): ...`, `RESULT fail`, exit 1 | down leaves no project, container, volume, image, lock or state of the tag |

</intent-contract>

## Code Map

**Story 11.3's interface (planned, built before this story; read its spec's Tasks and Design Notes):**
- `release/rehearse.sh`:
  - phases, state folder (`options`, `results`, `output.log`, `phase.<name>`, `standin/`);
  - the `install` steps and the sign-in URL mapping (`http://<REHEARSAL_CLEAN_WEB>:<port>`, `127.0.0.1` in a dry run);
  - the section builder (`demo path runs` row `not run`) and the Result rules.
- `release/lib-release.sh` -- `host_run`, `REHEARSAL_MODE`, `record_write`.
- `docker/tests/test-rehearsal.sh` -- the hermetic self-test: its synthetic repository, its stub hosts (`OCUTALON_REHEARSAL_SSH`), its phase-order case and its section case. These are extended here.
- In the dry clean stand-in, `host_run clean` runs `sh -c` in `<state>/standin/clean/` with the throwaway's `COMPOSE_PROJECT_NAME` and `COMPOSE_FILE`. So `docker compose exec -T iris` in `ocutalon-rehearsal/candidate` reaches the throwaway, as it reaches the real install (project `ocutalon`) on a host.

**The REL-2 specs and helpers (read; only the two helpers change):**
- `web/e2e/demo-path/01-page.spec.ts` to `06-trace.spec.ts` assume a first run on a blank install:
  - 01 entirely;
  - `02-watch.spec.ts:39-53`;
  - `03-reminder` (one Reminders row);
  - `04-incident.spec.ts:57-62` (`failed` 50, warehouse 0);
  - `toHaveCount(1)` throughout.
  - So only run 1 runs them verbatim, on the fresh install.
- Their order: `web/playwright.config.ts:34-37` (`workers:1`, `fullyParallel:false`) and the `demo-path` project at :55, in name order, then the `telegram-*` files.
- `web/e2e/support/demo-path.ts`:
  - :173-197 `watchThroughGuide`: the guide Send click at :177, `doneTurn` at :184, the strip at :181-183, the reply `.text` at :187;
  - :282-309 `approveOnPhone`: the phone Approve click at :291, then `readApproval` polling through IRIS at :292, then the card's `p.status` at :298.
  - Both are also imported by `web/e2e-online/demo-path/demo-path.spec.ts:169,190`.
- `web/e2e/support/iris.ts`:
  - :26-41 `irisContainer`;
  - :71-87 `runOnce` (`spawn('docker', ['exec','-i',<c>,'iris','session','IRIS','-U','OCUTALON'])`, script plus `Halt` on stdin);
  - :94-104 `irisScript` (`CHK|` filter, 3 tries).
  - Every spec's IRIS read goes through `runOnce`.
  - `web/scripts/floor-fixtures.test.mjs:21-30` pins other lines of `iris.ts`, which must stay.
- `web/e2e/support/navigate.ts` with `web/scripts/goto-settled.test.mjs:1-14` -- the precedent for a `web/scripts` node test that imports an e2e `.ts` module with Node's type stripping (erasable syntax only).
- `web/scripts/demo-path-summary.mjs:1-30` -- the step verdicts (`STEP <n> <id>`, `DEMO-PATH ...`, `FAIL <reason>`, exit 1). Steps: 1 page, 2 watch, 3 reminder, 4 incident, 5 approval, 6 trace.
- `docker/tests/test-demo-path.sh:73-88` -- the Playwright call and the summary call that the `runs` phase follows (about 6 lines copied: a top-level script).

**Server records the collector reads (all in OCUTALON unless named):**
- `Ens.MessageHeader.TimeCreated` / `TimeProcessed`:
  - `Ens.DataType.UTC`, milliseconds (`irislib/Ens/MessageHeaderBase.cls:25,28`; `irislib/EnsUtil.inc:24`).
  - Every OcuTalon `*At` column and `Live.Event.Ts` is whole seconds (`Data/Time.cls:18-20`, `Bridge/Time.cls:18-20`).
- **Press:**
  - the newest header whose body is `OcuTalon.Demo.Msg.SendOrders` (to `PartnerTrigger`; `Demo/BreakFeedIn.cls:60-139`), created at or after the run's server start;
  - `TimeCreated`.
- **The incident:**
  - `OcuTalon.Data.Incident` (`Data/Incident.cls:9-72`): the newest Orders incident of the session (`OwnerRef` = the printed user's `OcuTalon.Data.Session.ForUser(...)` Ref) with `NoticedAt` at or after the run's server start;
  - it gives `Namespace`, `FirstHeaderId`, `TraceHeaderId` and `DecisionRef`.
- **First failure:** header `FirstHeaderId` in the incident's `Namespace` (OCUORDERS), `TimeProcessed` (`Watch/Reader.cls:290,380`).
- **Pick-up:**
  - the first header whose body is `OcuTalon.Watch.Msg.FailureBatch` (`FailurePoller` to `IncidentManager`; `Watch/FailurePoller.cls:95-119`), with `SuperSession` = the session's `TraceRef`, created at or after the first failure;
  - `TimeCreated`.
- **Settle end (proxy):**
  - the first `OcuTalon.Bridge.Msg.Request` header to `Decide` in `SessionId` = `TraceHeaderId` (`Watch/IncidentManager.cls:631-684`), `TimeCreated`. The settle rule (`Watch/Settle.cls:24-26,72-80`) records no end time.
  - This header is also the diagnosis start.
- **Diagnosis end:** the response header whose `CorrespondingMessageId` is that request's ID (body `OcuTalon.Bridge.Msg.DecisionResponse`), `TimeCreated`.
- **Delivered:** the first header in `SessionId` = `TraceHeaderId` whose `TargetConfigName` is `SimPhoneOut` (an `OcuTalon.Msg.Notification`; `IncidentManager.cls:1346-1372`, `Channel/SimPhone/Out.cls:64,103`), `TimeProcessed`.
- **Reminder:**
  - `OcuTalon.Data.Reminder` (`Data/Reminder.cls:17-31`): the session's rows created at or after the run's server start, with `State` `fired`;
  - `DueAt` is whole seconds;
  - fired = the first `OcuTalon.Msg.Notification` header in `SessionId` = its `TraceHeaderId` (`Schedule/Reminder.cls:123-163`), `TimeCreated`;
  - also its `Late`.
- **Reminder vs the result:**
  - `OcuTalon.Data.SimMessage` (`Data/SimMessage.cls:13-40`) `CreatedAt` (whole seconds) of the session's phone message for the reminder;
  - and of the one whose `Text` holds "All 50 orders went through." (on the real model, the result message of the run's approval request).
- **Largest request:** `OcuTalon.Bridge.Data.Usage` (`Bridge/Data/Usage.cls:11-59`), `MAX(LargestRequestTokens)` over rows with `OwnerRef` = the session's Ref and `RecordedAt` at or after the run's server start. No HTTP route exposes it.
- **Epoch milliseconds in ObjectScript:**
  - `$ZDATETIMEH(<ts>,3)` gives `$H`-style days and seconds with a fraction;
  - epoch ms = ((days - 47117) * 86400 + seconds) * 1000, rounded;
  - the `Z`-suffixed whole-second strings are read with `$ZDATETIMEH(<ts>,3,7)` or by replacing `T`/`Z` first (Task 0 confirms the form).

**Not reused, with reason:**
- `release/demo-load.sh:433-517` (Epic 29) times the online demo's notice through HTTP in whole seconds (phone `createdAt` minus `startedAt`). The rehearsal's splits need millisecond headers that HTTP does not expose.

## Tasks & Acceptance

**Execution:**
- `(Task 0, measure)` On the first live dry run, record under Verification:
  - each mark's value for run 1 and the record it came from; where a named source does not exist or is empty, the nearest header that does, used and named;
  - the gap between the settle waiter's last `Ens.AlarmResponse` header in `TraceHeaderId` and the diagnosis request (it justifies the proxy);
  - whether the `SimPhoneOut` header's `TimeProcessed` is at or after the phone `SimMessage.CreatedAt` second;
  - the mock's `LargestRequestTokens`;
  - the `runs` call's seconds, the Playwright run's seconds and `exec.count`;
  - whether the REL-2 project passes unchanged on the stand-in after 11.3's sign-in step. If 01-page's blank-install checks fail because of it, stop and report under `deferred:`; do not edit a spec.
- `web/e2e/support/rehearsal.ts` -- new, erasable TypeScript, no Playwright import:
  - `marksOn()`: true when `OCUTALON_E2E_MARKS` names a file.
  - `mark(name)`: appends `<name> <Date.now()>\n` with `appendFileSync`; a no-op when marks are off.
  - `markWhen(name, probe, timeoutMs)`: when marks are on, polls the async `probe` every 100 ms until it is true, then marks; on timeout it marks nothing and returns. When marks are off, it returns at once and never calls `probe`.
  - `irisSessionCommand(env, container)`: `{cmd:'sh', args:['-c', env.OCUTALON_E2E_IRIS_EXEC]}` when that is set, else today's `docker exec` argv with `container()` called only then.
  - The header states the contract and the mark names.
- `web/e2e/support/iris.ts` -- `runOnce` spawns `irisSessionCommand(process.env, irisContainer)`. Nothing else changes, so `irisContainer` is never called when the exec variable is set.
- `web/e2e/support/demo-path.ts` -- extend two helpers. Each insertion sits right after the click and before any IRIS read:
  - `watchThroughGuide`:
    - `mark('step1_sent')` immediately before the guide Send click;
    - then `markWhen('step1_decision_seen', ...)`: the page has more `[data-part="reply"] app-decision-strip .reason` elements than before the click;
    - then `markWhen('step1_reply_seen', ...)`: the newest reply's `.text` is non-empty. "Before" is counted only when marks are on.
  - `approveOnPhone`:
    - `mark('approve_pressed')` immediately before the phone's Approve click;
    - then `markWhen('approval_result_seen', ...)`: the card's `[data-part="approval"] p.status` starts with "Approved from the simulated phone at".
  - The timeouts are the helpers' own (90 s, `CARD_MS`).
  - Update the module header in one sentence. Pure addition, no assertion changed.
- `web/scripts/rehearsal-support.test.mjs` -- new node test, the `goto-settled.test.mjs` pattern, importing `rehearsal.ts`. It pins:
  - off: `mark` writes nothing, and `markWhen` resolves without calling the probe;
  - on: lines in the grammar; `markWhen` polls about every 100 ms and marks once the probe turns true; a timeout writes no line;
  - `irisSessionCommand` in both cases, with `container` not called when exec is set;
  - by source: `iris.ts`'s `runOnce` calls `irisSessionCommand`, and the five mark names sit in `demo-path.ts` next to their clicks (the two `*_sent`/`*_pressed` marks just before, the three `*_seen` marks just after).
- `release/rehearse.sh` -- extend 11.3's script. The header documents every addition for Story 11.5 and Story 11.12.
  - **Options:**
    - `--runs <n>` (taken by `plan`, `install`, `run`; stored): the default is 20 in real mode (it must be at least 20) and 1 in a dry run (1 to 20);
    - `--plant <bound id>` (taken by `report` and `run`; dry run only).
  - **Real-mode guards:** the Real-mode guards row of the matrix.
  - **`install`:** also saves the clean host's web origin (`<state>/origin`) and the printed user (`<state>/user`), from the sign-in step. These are not configuration values, and the user is install.sh's printed default.
  - **`exec [<namespace>]`:** the Exec channel row. It reads `OCUTALON_REHEARSAL_RUN` to pick `runs/<k>/exec.count`.
  - **`runs`:** the Timed run row.
    - It first takes the run's server start through `exec` (`CHK|now|` in UTC with milliseconds).
    - The Playwright environment: `OCUTALON_E2E_IRIS_EXEC="bash '<this script>' exec"`, `OCUTALON_RUN_TAG`, `OCUTALON_REHEARSAL_RUN=<k>`. Only the Playwright environment sets `OCUTALON_REHEARSAL_RUN`, so the phase's own `exec` calls (the server start and the collector) do not count in `exec.count`.
    - Files go under `<state>/runs/<k>/`: `report.json`, `e2e.log` (also appended to `output.log`), `summary.log`, `marks.page`, `marks.server`, `verdict` (`pass|fail|<detail>`), `exec.count`.
    - The collector is one heredoc ObjectScript script sent through `exec`. It prints `CHK|mark|<name>|<epoch ms>`, `CHK|late|0|1`, `CHK|tokens|<n>` and `CHK|missing|<name>`, from the Code Map's sources.
    - The phase is followed by `RUN <k> ...` and the PASS or FAIL line.
  - **Bounds:** a sourced function `bounds_eval <state> [<planted id>]`, Bash plus awk, with the median through `sort -n`. It reads every `runs/*/marks.*` and `verdict`, applies the Bounds table, and writes `<state>/bounds` (`id|step|result|detail`), `<state>/runs.table`, and the FAIL lines.
  - **`report`:**
    - It may run again.
    - It calls `bounds_eval` (passing `--plant`), prints the FAIL lines, and adds the rows and the `### Runs` table to the section (Design Notes).
    - It replaces the `demo path runs` row's text with the run count.
    - It extends the Result rule: `fail` on any FAIL line; `dry run` in a dry run; real `not run` while runs < `--runs` or any row is `not run`; else `pass`.
  - **`run`:** install, then `runs` until `--runs` runs exist, a run fails, or `runs` refuses; then report (with `--plant`), then always down.
  - **`down`:** also removes `runs/`.
- `docker/tests/test-rehearsal.sh` -- extend; keep it hermetic (no container, no network; `node` is allowed, as the hosted `checks` job has it).
  - Update 11.3's cases that pin the old `demo path runs | not run` text and the refusal of a second `report`.
  - **`bounds_eval` on synthetic `runs/1..20` folders:**
    - all within: real rows `pass`, Result `not run` with only tell-now `not run`; dry rows `dry run`;
    - run 7's pick-up 16.0 s: `FAIL run 7 step incident bound pick-up 15 s: ...`;
    - notice over 60 s in 1 of 20 runs: pass; in runs 3 and 9: `FAIL run 3,9 step incident bound notice 60 s in 19 of 20: ...`;
    - decision 10.1 s in two runs: fail;
    - approval result 2.1 s in two runs: fail;
    - one reminder 11 s late: fail;
    - largest request 100000: fail, and 99999: pass;
    - a missing `delivered` mark: `FAIL run 4 step incident bound -: ...`;
    - a failed verdict: the run's FAIL;
    - the median for odd and even N;
    - `--plant pick-up` on a dry state: `(planted)` and Result `fail`, and on a real state: exit 2.
  - **`runs` in the synthetic repository, on stub hosts:**
    - the stub clean host answers `exec` scripts with canned `CHK` lines;
    - a stub `npm` on `PATH` writes a canned `report.json` (copied from a passing or a failing summary fixture), appends `marks.page` and calls `exec` once;
    - `node` stays real for `demo-path-summary.mjs`, copied into the repository.
  - **Cases:**
    - a passing run gives `PASS run 1` and the files;
    - a failing report gives `FAIL run 1 step approval bound -:`;
    - a stub npm that never calls `exec` gives the exec-channel FAIL;
    - a second `runs` refuses naming Story 11.12, exit 2;
    - `runs` with no state, exit 2;
    - the real-mode guards: a driver that is not local, a spec-tree difference, `--runs 5`; exit 2 each;
    - `exec`'s argv through the stub ssh: the compose exec command, the namespace refusal, and no env-file value.
  - **Static rules:** the collector heredoc holds no `Set ^`, `Kill`, `%Save`, `INSERT`, `UPDATE` or `DELETE`.

**Acceptance Criteria:**
- **AC1 (one timed run on the REL-2 specs; REL-6).** Given a passed install, when `rehearse.sh runs` runs, then:
  - the REL-2 project runs once from this machine against the clean host's address, with every IRIS read through `rehearse.sh exec` and `host_run clean`;
  - the run's verdict is `demo-path-summary.mjs --only-telegram-skips`;
  - a failed spec fails the run, naming its step;
  - a run that read nothing through the channel fails.
  - Pinned in the self-test on stub hosts, and live in the dry run (`exec.count` above 0).
- **AC2 (the splits from production message timestamps; NFR-7, AD-15).** Given a run's marks, when the report is written, then:
  - the Break the feed to notice time and its pick-up, settle end, diagnosis and delivery come from millisecond production message headers, as the Bounds table says;
  - each split is checked in every run;
  - the notice is checked at 60 s in at least 19 of 20 runs;
  - the median notice is recorded against the typical 35 s.
- **AC3 (every other bound; NFR-3, NFR-8, NFR-9, NFR-10, P30, UX-DR102).** Given the same runs, when the report is written, then it records and checks:
  - step 1's decision time (10 s, 19 of 20, page clock);
  - the first reply's time;
  - the approval result reaching the page (2 s, 19 of 20, measured from the Approve press as an upper bound);
  - each reminder's firing against its due time (10 s, every reminder);
  - when the reminder lands relative to "All 50 orders went through.";
  - the largest model request (under 100,000 input tokens, every run);
  - and a tell-now row that reads `not run`, naming Story 11.12.
- **AC4 (a failed run or a missed bound; REL-6).** Given any failed run, missed bound or missing measurement, when the rehearsal ends, then:
  - each miss prints `FAIL run <runs> step <step> bound <bound>: <detail>` (every missing run listed);
  - the row reads `fail`;
  - `Result: fail` and exit 1 block the release.
- **AC5 (dry run with a planted missed bound; REL-6, NFR-11).** Given this build and lane A's variables, when install, runs, report, `report --plant pick-up` and down run with `--dry-run --rc 1 --runs 1 --record <tmp>`, then:
  - the first report reads `Result: dry run`, exit 3, with every met bound row reading `dry run`;
  - the planted report prints `FAIL run 1 step incident bound pick-up 0 s (planted): ...`, `Result: fail`, exit 1;
  - no `ssh` runs;
  - down leaves nothing of the tag.
- **AC6 (the record; integration: consumers `report` and Story 11.5's gate).** Given the runs, when `report` writes the section, then:
  - it holds the bound rows and the `### Runs` table of Design Notes, and replaces itself on a second report;
  - a real state whose rows all pass still reads `Result: not run` and exits 1 while the tell-now row is `not run` or fewer than `--runs` runs exist, so Story 11.5's gate cannot pass early.
- **AC7 (interface).** Given the header's usage, when `runs` repeats, `runs` or `exec` runs out of order, `--plant` runs in real mode, or a real-mode guard trips, then each behaves as its matrix row says, and the header documents `runs`, `exec`, `--runs`, `--plant`, the mark names, the Bounds table's ids and the exit codes.
- **AC8 (inert in CI).** Given `OCUTALON_E2E_MARKS` and `OCUTALON_E2E_IRIS_EXEC` unset, when the demo-path helpers and `irisScript` run, then they add no wait, write no file and spawn today's `docker exec`. Pinned by `rehearsal-support.test.mjs`; `ci/iris.sh live demo-path` passes.

## Spec Change Log

## Review Triage Log

### 2026-11-01 - Review pass
- verdicts: 33 findings - high 0, medium 10, low 23, false 0, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: FAIL reasons from summary.log bypass the host scrub - the reason was printed and written to `verdict` unscrubbed; fixed: summary.log is rewritten through `scrub_origin` before the FAIL lines are read; self-test case added (a failing report that names the host).
  - `[low]` `[patch]` Blind: install-only report gets a header-only Runs table - `bounds_eval` now empties `runs.table` when no run exists; self-test case added.
  - `[medium]` `[patch]` Blind: `runs` does not re-apply the spec-tree guard (c_sha unset) - `runtime_prepare guard` takes the saved `cand_sha` for `runs`; the guarded paths stay the spec's four.
  - `[medium]` `[patch]` Blind: the "missing collector" marker is never read - the bounds awk now fails the run's step (`missing mark(s) collector`); self-test case added.
  - `[low]` `[reject]` Blind: no wall-clock bound on the remote calls - the bound is Playwright's globalTimeout (OCUTALON_E2E_TIMEOUT_MS), which the header states; an ssh hang is `host_run`'s concern and not this story's.
  - `[low]` `[reject]` Blind: operator environment passes into the browser run - the run's output goes through the secrets scan and no value is added by the run; `wontfix-accepted`, reopen_if a rehearsal host's environment holds a variable the scan cannot know.
  - `[low]` `[reject]` Blind: the collector is brittle (text matches, hard-coded names, no real-IRIS test) - the text match is already in `deferred:` (first item) and the live dry run exercises the rest.
  - `[low]` `[patch]` Blind: leftover `rargs` and an unused `step` - `rargs` removed; `step` is a field of the bounds line that `read` needs.
  - `[low]` `[patch]` Blind: the `markWhen` gap assertion can flake - the upper bound is now 2000 ms.
  - `[low]` `[reject]` Blind: dry `--runs` above 1 prints a refusal - the spec's Decided in-stage 10 and the matrix make 1 to 20 valid in a dry run; the repeats are Story 11.12's.
  - `[medium]` `[patch]` Edge: `scrub_origin` never ends when the host name occurs in `<clean host>` - rewritten as a single pass; self-test case added (host name `host`).
  - `[medium]` `[patch]` Edge: FAIL reasons keep the host - same root cause as the first row.
  - `[medium]` `[patch]` Edge: the spec-tree guard is skipped in `runs` and `exec` - same root cause as the third row; `exec` is not guarded (it runs 20+ times per run).
  - `[low]` `[patch]` Edge: `plant_ok` matches a substring (`notice pick-up`) - exact word match; covered by the dry-report case.
  - `[low]` `[patch]` Edge: a namespace with a newline passes the line-wise grep - `namespace_ok` matches the whole string in the C locale; case added to the refusal list.
  - `[low]` `[patch]` Edge: `OCUTALON_E2E_TIMEOUT_MS=0` disables Playwright's timeout - zero and leading-zero values fall back to 480000.
  - `[medium]` `[patch]` Edge: the missing-collector marker is never read - same root cause as the fourth row.
  - `[low]` `[reject]` Edge: first-wins pairing of `approve_pressed` after a timed-out result - `wontfix-theoretical`: the REL-2 specs press Approve once per run; a second press would show as a spec failure.
  - `[low]` `[reject]` Edge: `step1_reply_seen` is marked at once if an earlier reply exists - `by-design`: the spec fixes the probe as "the newest reply's .text is non-empty", and run 1 starts from a fresh install.
  - `[low]` `[reject]` Edge: origin and user are saved although the host is a configuration value - `by-design`: the state folder is outside the repository (umask 077), the output is scrubbed and scanned, and the spec says so.
  - `[low]` `[reject]` Edge: "bounded by OCUTALON_E2E_TIMEOUT_MS" claim - same as the fifth row.
  - `[low]` `[reject]` Edge: the static collector scan misses abbreviated writes (`S ^G`) - a keyword scan is a guard, not a parser; the collector is written by this story and the live dry run reads only.
  - `[medium]` `[defer]` Gap: the collector's queries are never executed by a hermetic test - recorded under `deferred:` (second item), marked unverified; the live dry run is the proof the spec names.
  - `[medium]` `[defer]` Gap: the page-mark probes run only in the manual dry run - grouped with the previous row.
  - `[medium]` `[patch]` Gap: `report --plant` wiring on a dry state has no hermetic test - new rule `dry-report` runs `report` and `report --plant pick-up` on a dry state through the command.
  - `[low]` `[reject]` Gap: dry-mode `runs` and `exec` (`model=mock`, stand-in reload) are not pinned by the self-test - `wontfix-accepted`, reopen_if the dry run's model stops being the mock; the live dry run covers it.
  - `[low]` `[reject]` Gap: `existsSync` in the off tests is vacuous - the probe count and the elapsed time carry those cases.
  - `[low]` `[patch]` Gap: wall-clock thresholds in the node test - loosened (see the `markWhen` row above).
  - `[low]` `[reject]` Gap: `timed-runs` and `guards` have no synthetic break - the header's claim is for the rules that have one; the AC mutations cover them (Verification).
  - `[low]` `[patch]` Gap: `scrub_origin` has no test - added with the host-name case.
  - `[low]` `[reject]` Gap: real-mode `run` prints a spurious refusal for run 2 - same as the dry `--runs` row.
  - `[low]` `[reject]` Gap: the spec's Auto Run Result read ready-for-dev - rewritten at finalize.
  - `[low]` `[reject]` Intent: the live dry-run surface is not exercised by the diff's tests - the diff excluded the spec; the live dry run and Task 0 are recorded in Verification and were run again after the patches.

## Design Notes

**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-15 | The splits: `FailurePoller` (3 s), the settle rule (10 s quiet or 30 s), `IncidentManager`'s diagnosis request and the notice. Its time budget (pick-up under 3 s, settle about 12 s, diagnosis under 12 s, delivery under 2 s) is the design target; the NFR-7 bounds are what is checked. |
| AD-22 | Dry runs on throwaways with the CI override and the mock, no key; the docker-call rules. |
| AD-25 | Remote actions only over SSH through `host_run`, with the author's configuration outside the repository. The exec channel is one more `host_run`. |
| AD-19 | No key or configuration value in the output, the record or a mark. |
| AD-18 and AD-32 | The reminder's waiter and its `Notification`; the notification contract. |
| AD-20 | `Usage.LargestRequestTokens` is the per-request size. |
| AD-12 | The page receives events; its arrival is measured only on the page clock. |
| AD-29 | `release/` is Lane A's. The `web/e2e/support` changes use Epic 11's exception, and no product class or text changes. |

No AC contradicts an AD.

**The Bounds table** (limits are "at most", except `largest-request`, which is "under"):

| Id | Step | From, to (clock) | Limit | Rule |
| --- | --- | --- | --- | --- |
| notice | incident | press, delivered (server) | 60 s | 19 of 20 |
| pick-up | incident | first failure, pick-up (server) | 15 s | every run |
| settle-end | incident | first failure, diagnosis start (server) | 30 s | every run |
| diagnosis | incident | diagnosis start, diagnosis end (server) | 20 s | every run |
| delivery | incident | diagnosis end, delivered (server) | 5 s | every run |
| median | incident | the median of `notice` | about 35 s | recorded |
| decision | watch | step1_sent, step1_decision_seen (page) | 10 s | 19 of 20 |
| first-reply | watch | step1_sent, step1_reply_seen (page) | - | recorded |
| approval-result | approval | approve_pressed, approval_result_seen (page) | 2 s | 19 of 20 |
| reminder | reminder | due, fired (server; due in whole seconds) | 10 s | every reminder |
| reminder-result | reminder | the result's phone message, the reminder's (server, whole seconds) | - | recorded, signed |
| largest-request | run | max `LargestRequestTokens` (server) | 100,000 | every run |
| tell-now | tell-now | - | 5 s | `not run` until Story 11.12 |

"19 of 20" allows floor(N/20) misses, so N = 1 allows none.

**The section's additions** (indented two spaces here; in the record each line starts at column 1). After 11.3's `Candidate:` line:
```
  Specs: the REL-2 specs (web/e2e/demo-path) at <full sha>
```
Rows replacing and following 11.3's `demo path runs` row (dry run, N = 1):
```
  | demo path runs | pass | 1 of 1 runs passed the REL-2 specs |
  | notice | dry run | within 60 s in 1 of 1 runs (19 of 20 needed); longest 31.4 s (run 1) |
  | pick-up | dry run | within 15 s of the first failure in every run; longest 2.9 s (run 1) |
  | settle-end | dry run | within 30 s of the first failure in every run; longest 12.6 s (run 1) |
  | diagnosis | dry run | within 20 s in every run; longest 0.8 s (run 1) |
  | delivery | dry run | within 5 s in every run; longest 0.2 s (run 1) |
  | median | recorded | median notice 31.4 s against the typical 35 s |
  | decision | dry run | within 10 s in 1 of 1 runs (19 of 20 needed); longest 2.1 s (run 1) |
  | first-reply | recorded | median 2.3 s, longest 2.3 s (run 1) |
  | approval-result | dry run | within 2 s of the Approve press in 1 of 1 runs (19 of 20 needed); longest 0.6 s (run 1) |
  | reminder | dry run | every reminder within 10 s of its due time; latest 1 s (run 1) |
  | reminder-result | recorded | run 1: the reminder landed 14 s before "All 50 orders went through." |
  | largest-request | dry run | under 100,000 input tokens in every run; largest 1,520 (run 1) |
  | tell-now | not run | the demo path has no tell-now item yet; Story 11.12 adds one to each run |

  ### Runs

  | Run | Result | Notice | Pick-up | Settle end | Diagnosis | Delivery | Decision | First reply | Approval result | Reminder | Reminder to result | Largest request |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | 1 | pass | 31.4 s | 2.9 s | 12.6 s | 0.8 s | 0.2 s | 2.1 s | 2.3 s | 0.6 s | 1 s | -14 s | 1,520 |
```
- In real mode the met rows read `pass`.
- `### Runs` does not match 11.3's `## ` section scan (its third character is `#`).
- The figures above are illustrations; Task 0 gives the real ones.

**Decided in-stage.**
1. **One run per `runs` call, and run 1 is the REL-2 project verbatim** on the fresh install. The specs assume a first run, and changing them is out of scope.
2. **The timed runs drive Playwright on this machine** (`REHEARSAL_DRIVER_SSH=local`). The 1.0.0 driver is the Contest Planner's Mac, and a remote driver would need its own checkout and browser. Real mode also refuses a spec tree that differs from the candidate's, so the record's `Specs:` line is the candidate's.
3. **One IRIS channel.** The specs' reads and the collector both go through `rehearse.sh exec` and `host_run clean`. This is the documented exec path in real mode, and no product surface is added. `exec.count` proves the channel was used in the dry run, where the port lookup would also have worked.
4. **One clock per value.**
   - The splits use server headers in milliseconds, as the AC says ("from production message timestamps").
   - The page-side bounds (decision, first reply, approval result) use the page clock inside one test's page.
   - Delivery ends at the `SimPhoneOut` header, not at the page: 05's page opens after 04's press, so a page mark would be a load time, not an arrival time.
   - The approval result is timed from the press, which bounds NFR-9's "from being sent" from above. A miss can be a false fail, never a false pass.
5. **Settle end** is the diagnosis request's header. No record holds the rule's end, and the request follows it at once (Task 0 measures the gap).
6. **Rule per bound.** NFR-7's 60 s, NFR-8 and NFR-9 are "19 of 20" (their own words). The split bounds are "at most" in every run (Story 38.2's wording), as are each reminder (NFR-10's "a reminder fires within 10 seconds") and NFR-3 ("no model request").
7. **Recorded, not failing:** the median (UX-DR102 and Story 38.2 call 35 s "the typical target"), the first reply's time and the reminder against the result (Story 38.2: "which the deferred reminder-prompt decision needs"). No number is invented for them.
8. **Dry-run rows read `dry run`** when met, so the mock never shows a timing `pass`. Bounds on the mock are plumbing only.
9. **`report` may run again** (it rebuilds from the state), and `--plant` lowers one limit to 0 in dry runs only. This proves the miss path live without fabricating a measurement. The self-test also plants a synthetic over-limit run. This changes 11.3's "report once" rule, and the self-test case is updated.
10. **Real mode needs at least 20 runs**, and allows floor(N/20) misses for "19 of 20" (a stricter or equal ratio).

**Interface (Rule 1/2).**

| Link | Who |
| --- | --- |
| Consumed-by | Story 11.12: the repeats call `runs` for runs 2 to N (one per call), reuse the collector, the marks and `bounds_eval`, and fill the tell-now row |
| Consumed-by | Story 11.5's gate: `run --version <v> --rc <n>` (`--dry-run` for its rehearsal candidate); exit 0 with `Result: pass` only |
| Consumed-by | Story 38.2: the real 20 runs from the Contest Planner's Mac |
| Consumed-by | Story 11.4's notes: the bound rows and the `### Runs` table |
| Consumes | Story 11.3's `rehearse.sh` and `lib-release.sh` (`host_run`, state, `record_write`); the REL-2 specs and `demo-path.ts`; `demo-path-summary.mjs`; `iris.ts`; the production's headers and the Incident, Reminder, SimMessage and Usage rows |

- **Integration ACs:** AC6 (`report` consumes `bounds_eval`'s rows; Story 11.5's gate reads `Result:`), and AC1's live dry run (the REL-2 specs consume the exec channel).

**Extend, don't copy (Rule 2).**
- **Extended:**
  - 11.3's `rehearse.sh` phases, state and section;
  - `host_run` for the exec channel;
  - `iris.ts`'s `runOnce` (one command choice);
  - the two step helpers of `demo-path.ts`;
  - `demo-path-summary.mjs` for the run verdict;
  - 11.3's self-test.
- **Copied, with reasons:**
  - about 6 lines of `test-demo-path.sh`'s Playwright and summary calls (a top-level script);
  - the `CHK|` filter (about 3 lines) of `lib-live.sh`'s `iris_script`. It is Epic 12's contended file, and the rehearsal's channel is `host_run`, not `dc exec`.

**Rule 5 check (each bound measurable).**
- Every bound has a measurement point, labelled where it is a proxy (settle end), an upper bound (approval result) or whole seconds (reminder due).
- The tell-now 5 s has no item in the demo path, so it moves with the repeats to Story 11.12, which must add one tell-now item to each run. If the real model cannot be relied on to decide tell now for it, that is Story 11.12's tripwire. No intent gap is raised here.

**Proposed split (smaller is better; for the lead).**
- **Story 11.12, "The rehearsal runner repeats the demo path N times with Run again (dry runs on throwaways)",** planned next. It takes verbatim:
  - from this story's first criterion, "N times (20 for a real rehearsal), using Run again and the replay rule between runs" and "the tell-now notice's 5 seconds in at least 19 of 20 runs";
  - and, from the third, the same throwaway proof for those parts.
- It must face these facts:
  - Run again reopens only steps 3 to 5 (`Data/GuideState.cls:67-88`, `Demo/Guide.cls:6-8`). So each repeat must also send step 1's and step 2's prompts through the composer, to give 20 decision and reminder samples.
  - The replay rule needs the previous incident resolved (`Demo/BreakFeedIn.cls:94-113`), and a press within 180 s of an unnoticed run is refused (`Demo/Guide.cls:45,160-172`).
  - The REL-2 assertions are first-run counts, so a repeat spec under a new folder, or the demo-path folder gated by an environment variable, needs relative counts.
  - No spec presses Run again outside `web/e2e/floor/guide.spec.ts:600-650`.
- Story 11.5 then composes 11.3, 11.11 and 11.12.

**Decided in-stage (implement).**
11. **The two page marks of the Approve press sit in `pressOnPhone`**, the click that `approveOnPhone` and `rejectOnPhone` share, guarded by `action === 'approve'`, because the click is not in `approveOnPhone` itself. `approve_pressed` is the line before the Approve click and `approval_result_seen` follows the click and comes before the first IRIS read (the node test pins both positions).
12. **The collector takes the first record at or after the run's server start**, not the newest: the REL-2 project also holds 07-failure-paths and 08-quiet-outcomes, which press Break the feed again and open later incidents, so the newest would be 07's. Run 1 is 04's press, 04's incident and 03's reminder.
13. **Marks, rows and files.** `marks.server` holds `mark <name> <ms>`, `reminder <due ms> <fired ms>`, `late <n> <n>`, `tokens <n>` and `missing <name>`; `marks.page` holds `<name> <ms>`; `verdict` is `pass`, or `fail` and then `<step>|<detail>`. The collector's last line `CHK|done|1` proves it ran to its end (a script without it is tried again, three tries 5 s apart). A `recorded` row counts as met in the Result rule; `runs` is a row of its own (`not run` below `--runs`, `fail` when a run failed or lacks a mark). The median is taken in awk (insertion sort), not through `sort -n`, because the runs are few.
14. **Real-mode stub tests moved to a local driver.** The new real-mode guard refuses a driver that is not local, so 11.3's stub runs use a local driver (a stub `curl` on `PATH` stands in for the page), and their ssh-call counts fell from 7 to 5.
15. **The clean host's address is scrubbed from the specs' text in real mode** (`<clean host>`) before it reaches `output.log`, because it is a configuration value that the secrets scan would otherwise find in a Playwright error message.
16. **A missing mark fails the run and its rows, whatever the rule.** A bound with "19 of 20" allows misses only of measured values; a run that could not be measured fails the row.

**Ledger (Rule 17).** This story owns no entries.

**Contended paths (U14).**
- Checked at plan time with `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` for 12, 13, 15, 30 and 31. Epic 29 has no open branch.
- No planned file is listed. Epic 12 changes `web/e2e/demo-path/telegram-page.spec.ts`, which runs in run 1 unchanged.
- **New files:** `web/e2e/support/rehearsal.ts`, `web/scripts/rehearsal-support.test.mjs`.
- **Changed files:** `release/rehearse.sh`, `docker/tests/test-rehearsal.sh` (this epic's), `web/e2e/support/iris.ts` and `web/e2e/support/demo-path.ts` (not contended).

**CI budget (REL-4; measured at implement).**
- No unit is added and `ci/units.sh` is unchanged.
- The hosted `checks` job (`test-rehearsal.sh`) takes about 36 s alone and 48 s inside `ci/checks.sh` (11.3's was about 18 s), and the hosted `web` job one more node test file (about 1 s).
- The browser units are unchanged, because the helpers are inert there. A `web/e2e` change still runs the groups that read the bundle (`ci/changes.sh`).

## Clarification Needed (non-blocking: the plan does not depend on the answer)

1. Accept the proposed split into Story 11.12 (decide, product default 6, as at 11.3). If it is rejected, re-plan 11.11 with the repeats; this spec stays valid as its first part.

## Verification

All commands run from the worktree root, each in its own foreground call with `timeout: 600000`. Live calls carry lane A's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement' OCUTALON_RUN_TAG=e11s11d`.

**Commands:**
- `(loop)` `bash docker/tests/test-rehearsal.sh` -- expected: every PASS line, exit 0.
- `(loop)` `node --test web/scripts/rehearsal-support.test.mjs` -- expected: exit 0.
- `(loop)` `npm --prefix web run lint` -- expected: exit 0 (tsc over e2e, `node --check` over scripts).
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(loop)` the live dry run, one call per phase, with the lane variables above:
  1. `bash release/rehearse.sh install --dry-run --rc 1 --runs 1 --record "${TMPDIR:-/tmp}/e11s11-dry/rc1.md"` -- expected: every install row passes.
  2. `bash release/rehearse.sh runs` -- expected: `PASS run 1`, a `RUN 1` line, `exec.count` above 0.
  3. `bash release/rehearse.sh report` -- expected: `RESULT dry run`, exit 3, the section as in Design Notes.
  4. `bash release/rehearse.sh report --plant pick-up` -- expected: `FAIL run 1 step incident bound pick-up 0 s (planted): ...`, `RESULT fail`, exit 1.
  5. `bash release/rehearse.sh down` -- expected: `TEARDOWN`.
  - Then `docker ps -a --format '{{.Names}}' | grep -c e11s11d` prints 0, and the lane folder holds no lock of this run. If anything is left, run `ci/iris.sh teardown` with the same tag and lane variables.
  - After any merge that brings in `web/` changes, run `ci/iris.sh build` once first. Record Task 0's figures here.
- `(once)` `npm --prefix web test` -- expected: every node test passes.
- `(once)` `ci/iris.sh live demo-path` (a fresh throwaway, lane variables, tag `e11s11p`) -- expected: passes unchanged, which proves AC8 in the CI unit.
- `(once)` `bash ci/checks.sh` -- expected: every check script passes.

**Mutations to demonstrate (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**
- AC1: ignore `demo-path-summary.mjs`'s exit, so the failing-report case reads PASS.
- AC2: time pick-up from the press instead of the first failure, so run 7's synthetic case does not fail.
- AC3: time `approval-result` from `step1_sent` instead of `approve_pressed`, so the approval two-miss case's FAIL line changes.
- AC4: skip a run with a missing mark, so the missing-`delivered` case fails.
- AC5: ignore `--plant`, so the live planted report exits 3, and the planted self-test case fails.
- AC6: drop the tell-now row, so the real all-pass case reads `pass`.
- AC7: let `runs` start run 2, so the repeat-refusal case fails.
- AC8: let `markWhen` call the probe with marks off, so the node test's off case fails.

**Implement stage (2026-11-01; lane A, `ocutalon-slot-a` untouched, throwaway tags e11s11d and e11s11p):**

Loop results at hand-off:
- `bash docker/tests/test-rehearsal.sh`: all 16 rules pass (36 s alone; the new rules are `bounds`, `timed-runs` and `guards`, and `results`, `dry-section`, `stub-runs`, `candidate` and `static` are updated).
- `node --test web/scripts/rehearsal-support.test.mjs`: 12 tests pass. `npm --prefix web run lint`: exit 0. `bash docker/tests/test-boundaries.sh`: exit 0. `ci/iris.sh build` ran once after the `web/` changes.
- The live dry run, one call per phase (`install --dry-run --rc 1 --runs 1 --record <tmp>/rc1.md`, `runs`, `report`, `report --plant pick-up`, `down`): install `PHASE install done 88s`, every install row passes (first start 82 s); `runs` printed `PASS run 1 demo path: DEMO-PATH 8 of 8 steps ran (2 partly skipped), 2 skipped, 0 failed; floor 7 of 7 passed` and `RUN 1 notice=11.1 pick-up=2.1 settle-end=10.4 diagnosis=0.3 delivery=0.3 decision=1.1 approval-result=1.0 reminder=0.3 largest-request=3657 first-reply=1.1 reminder-result=-2.0`; `report` printed `RESULT dry run`, exit 3, with every met bound row `dry run`, the runs row `pass | 1 of 1 runs passed the REL-2 specs`, `tell-now | not run` and the `### Runs` table; `report --plant pick-up` printed `FAIL run 1 step incident bound pick-up 0 s (planted): 2.1 s in run 1 from the first failure to the pick-up`, `RESULT fail`, exit 1, and the record still holds one section; `down` printed `TEARDOWN`, and afterwards `docker ps -a | grep -c e11s11d` printed 0, no image of the tag and no state folder remained, and the lane folder held no lock. No `ssh` ran (dry mode never calls it).

Once-only commands:
- `npm --prefix web test`: 1166 tests pass.
- `ci/iris.sh live demo-path` (tag e11s11p, fresh throwaway, 4 min 47 s in all): `20 passed`, 2 skipped (the Telegram parts), `test-demo-path: all checks passed`, so AC8's CI unit passes unchanged. No container or lock of the tag remained.
- `bash ci/checks.sh`: `checks: all scripts passed`. In one call it took about 14 minutes (eval-set 227 s, online-host 123 s, ci-config 47 s, ci-warm 47 s, probe 54 s, install-script 46 s, online-load about 95 s, rehearsal 48 s), past the 10-minute call cap, so the harness moved it to the background and it ran to its end; `test-online-load.sh` was also run by itself afterwards (exit 0). Split it by script when a call must stay under the cap.

**Task 0, measured on the first live dry run (developer machine, Docker Desktop, arm64, tag e11s11d, lane A):**
- Every named source existed and was non-empty; no nearest-header substitute was needed. Run 1's marks (server clock UTC, 2026-11-01; the `runs` call took the server start 15:47:28.897):
  - `press`: `Ens.MessageHeader` 46, body `OcuTalon.Demo.Msg.SendOrders`, `TimeCreated` 15:48:06.637 (the later presses are 92, 110 and 142 from 07, so the collector takes the first).
  - `first_failure`: header 2 of the incident's namespace (OCUORDERS), `TimeProcessed` 15:48:06.718 (the incident's `FirstHeaderId`).
  - `pickup`: the first `OcuTalon.Watch.Msg.FailureBatch` header with the session's `TraceRef` as `SuperSession` at or after the first failure, `TimeCreated` 15:48:08.786 (2.1 s after the first failure).
  - `settle_end` (also the diagnosis start): header 52, `OcuTalon.Bridge.Msg.Request` to `Decide` in session 49 (the incident's `TraceHeaderId`), `TimeCreated` 15:48:17.123 (10.4 s after the first failure).
  - `diagnosis_end`: header 59, `OcuTalon.Bridge.Msg.DecisionResponse` with `CorrespondingMessageId` 52, `TimeCreated` 15:48:17.405 (0.3 s).
  - `delivered`: header 68, the first header to `SimPhoneOut` in session 49, `TimeProcessed` 15:48:17.750 (0.3 s after the answer; the notice came 11.1 s after the press).
  - Reminder: the row's `DueAt` 15:49:05Z (whole seconds), fired = the `OcuTalon.Msg.Notification` header in its `TraceHeaderId` session, `TimeCreated` 15:49:05.328 (0.3 s); `Late` 0. The reminder's phone message `CreatedAt` is 15:49:05Z and "All 50 orders went through." is 15:49:07Z, so the reminder landed 2.0 s before the result on the mock.
  - Page marks (one clock): `step1_sent` to `step1_decision_seen` 1054 ms, to `step1_reply_seen` 1061 ms; `approve_pressed` to `approval_result_seen` 976 ms.
  - Largest request: `MAX(LargestRequestTokens)` is 3657 on the mock (all four incidents of the REL-2 project included).
- The gap between the settle waiter's last `Ens.AlarmResponse` header in session 49 (header 51, `TimeCreated` 15:48:16.909) and the diagnosis request (header 52, 15:48:17.123) is 0.214 s, so the request is a good proxy for the settle rule's end (it follows at once, under a quarter of a second).
- The `SimPhoneOut` header's `TimeProcessed` (15:48:17.750) is at or after the phone `SimMessage.CreatedAt` second (15:48:17Z): the same second, so the whole-second row never reads later than the header.
- The `runs` call took 2 min 29 s, the Playwright run 2.5 min (`20 passed (2.5m)`, 2 skipped), and `exec.count` ended at 27. A second call of `exec` costs about a second.
- The REL-2 project passes unchanged on the stand-in after 11.3's sign-in step (all of 01-page's blank-install checks included); no spec was edited and nothing is deferred for it.
- Phases (install, runs, report, down): 88 s, 149 s, under 1 s and 7 s.

**Mutations demonstrated (Rule 19; each applied, red observed, reverted byte-identical by checksum; `git status --short` shows only this story's files):**
- mutation: AC1: `demo-path-summary.mjs`'s exit and FAIL lines ignored in `phase_runs` -> `test-rehearsal.sh` rule timed-runs red (the failing-report case reads PASS: no FAIL for step approval, verdict `pass`, no `RESULT fail`).
- mutation: AC2: pick-up timed from the press instead of the first failure -> rule bounds red (run 7's FAIL text, the pick-up row text and the RUN line change; 3.9 s instead of 2.9 s).
- mutation: AC3: `approval-result` timed from `step1_sent` instead of `approve_pressed` -> rules bounds and stub-runs red (the approval two-miss case's FAIL line changes, and twenty runs within every limit now print an approval FAIL of 8.6 s).
- mutation: AC4: the FAIL line of a run with a missing mark skipped -> rule bounds red (the missing-`delivered` case and the page, server and session cases).
- mutation: AC5: `--plant` ignored (`if (0) lim[plant] = 0`) -> the live planted report exited 3 with `RESULT dry run` (not 1), and rule bounds red (the planted FAIL text, row, result and exit).
- mutation: AC6: the tell-now row dropped (from the row list and the bounds) -> rules results and bounds red (the real all-pass case reads `pass`, not `not run`).
- mutation: AC7: `runs` allowed to start again (the run-1-exists refusal switched off) -> rule timed-runs red (no REFUSED line naming Story 11.12, exit not 2, and the second call started npm again).
- mutation: AC8: `markWhen` no longer returns at once with marks off -> `rehearsal-support.test.mjs` red ("writes nothing and calls no probe": the probe is called and 5 s are waited). A second mutation (`runOnce` given `{}` instead of `process.env`) turns the source pin red.

- mutation (review patches): the `collector` miss line removed from the bounds awk, `report_plant` forced empty and `plant_ok` reverted to a substring match, all at once -> `test-rehearsal.sh` rules timed-runs (a collector without its done line reads PASS) and dry-report (no planted FAIL, no `(planted)`, a two-id plant not refused) red; the file restored byte-identical (md5).
- After the review patches: `bash docker/tests/test-rehearsal.sh` all 17 rules, the node test (12), lint, `test-boundaries.sh` and `npm --prefix web test` (1166) pass; the live dry run was repeated (install 112 s, `PASS run 1`, `RESULT dry run` exit 3, the planted `FAIL run 1 step incident bound pick-up 0 s (planted)` exit 1, down: 0 containers, 0 images, empty lane folder). `ci/checks.sh` and `ci/iris.sh live demo-path` were not repeated: only `test-rehearsal.sh` and `test-boundaries.sh` read the files the patches changed, and `web/` is unchanged since their green run.

**Shared surfaces, checked:**
- `watchThroughGuide` and `pressOnPhone` (so `approveOnPhone` and `rejectOnPhone`) keep every assertion; `ci/iris.sh live demo-path` passes unchanged. `web/e2e/support/iris.ts` differs only in `runOnce` (and its import); `web/scripts/floor-fixtures.test.mjs` is in the 1166 passing tests.
- 11.3's phase order and rows: `report` already ran again; the `demo path runs` row and its text, the real-mode stub cases (a local driver now) and the ssh-call counts are updated in the self-test.

**Shared surfaces:**
- `watchThroughGuide` and `approveOnPhone` (the web demo-path and online demo-path units).
- `iris.ts`'s `runOnce` (every browser unit).
- 11.3's phase order (report may repeat) and its section rows (Story 11.4 and Story 11.5 read them; 11.3's self-test cases are updated).
- `rehearse.sh`'s header interface.
- Every test added or changed passes on a fresh environment, in either order. The self-test builds its own repository, stubs and run folders; the node test uses its own temporary files; the dry run brings up its own throwaway and removes it.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `release/rehearse.sh` gains the `runs` and `exec` commands and the `--runs` and `--plant` options: run 1 drives the REL-2 specs through the `exec` channel, the read-only collector reads the production headers, and `bounds_eval` applies the Bounds table. `report` may repeat, writes the bound rows and the `### Runs` table, and keeps a real `Result: not run` while fewer than `--runs` runs exist or tell-now is `not run`. The two `demo-path.ts` helpers leave page marks only when `OCUTALON_E2E_MARKS` is set, and `iris.ts` spawns `docker exec` unless `OCUTALON_E2E_IRIS_EXEC` is set.

**Files changed.**
- `release/rehearse.sh` - the new phase, channel, options, guards, collector and bounds evaluation.
- `docker/tests/test-rehearsal.sh` - rules bounds, timed-runs, guards and dry-report, and 11.3's updated cases.
- `web/e2e/support/rehearsal.ts` (new) - `mark`, `markWhen`, `marksOn`, `irisSessionCommand`.
- `web/e2e/support/iris.ts` - `runOnce` takes its command from `irisSessionCommand`.
- `web/e2e/support/demo-path.ts` - five marks beside the clicks of `watchThroughGuide` and `pressOnPhone`.
- `web/scripts/rehearsal-support.test.mjs` (new) - 12 node tests.

**Review.** 33 findings: high 0, medium 10, low 23. Patched (8 medium rows in 5 root causes, 6 low): host scrub of FAIL reasons, the scrub loop, the spec-tree guard in `runs`, the unread missing-collector marker, the `--plant` wiring test, the empty Runs table, an exact `--plant` match, a whole-string namespace check, a zero timeout, a flaky timing bound, an unused local and a scrub test. Deferred: one item (the collector and the probes run only in the live dry run), beside the two the implementation recorded. Rejected: 15 low or descriptive rows with their reasons in the Review Triage Log.

**Follow-up review recommended: true.** Two or more medium entries were patched (five root causes); the patches sit in `phase_runs`, `runtime_prepare` and the bounds awk and were checked by the self-test, one mutation run and the repeated live dry run, but no review layer re-read them.

**Residual risks.** Real mode is proved on stub hosts only (the real 20 runs are Story 38.2's); the real-model text matches are unmeasured; a real rehearsal cannot pass before Story 11.12 fills the tell-now row.
