---
title: 'Story 0.8: The demo-path test signs in and loads the page'
type: 'feature'
created: '2026-10-19'
status: 'done'
review_loop_iteration: 0
baseline_revision: 'a375972151fec7213227b11611ed1e83b73057a2'
baseline_commit: a375972151fec7213227b11611ed1e83b73057a2
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      api.spec.ts reads eight sign-in unit variables at import, so `npm --prefix web run e2e -- --list` exits 1 with no test listed unless they are set.
    evidence: |-
      Measured in Task 0: `Error: OCUTALON_E2E_VERSION must be set by docker/tests/test-sign-in.sh`, `Total: 0 tests in 0 files`. The `chromium` project is only listed or run with the variables set (the unit sets them; demo-path-summary.test.mjs sets dummies). Deferring the reads into the tests would change Story 0.5's spec file.
    location: >-
      web/e2e/api/api.spec.ts
    severity: low
  - summary: >-
      On a developer machine the run deadline (540 s) ends the first-start wait before the 720 s WARN threshold can be reached; only CI (deadline 1200 s) can print the WARN line.
    evidence: |-
      live_first_start waits at most 900 s but wait_until stops at the run's deadline, as the spec fixes ("900 s, bounded by the run's deadline"). A local first start measured 47 to 53 s, so the gap shows only on a host about ten times slower than this one.
    location: >-
      docker/tests/test-demo-path.sh
    severity: low
---

<intent-contract>

## Intent

**Problem:** REL-2's demo-path test doesn't exist yet.
- CI runs 0.3's sign-in specs inside `live:sign-in`, on a stack that the script seeds with fixture users and events. No spec follows UJ-1, and no unit gates on it.
- Nothing records which UJ-1 step is built.
- AD-23's first start of the real package has never been timed on x64 for the README.
- Under 0.7's skip rule, a push to `main` can skip the IRIS jobs, although REL-2 says the test runs on every push to `main`.

**Approach:**
- **The specs.** One Playwright spec per UJ-1 step under `web/e2e/demo-path/` (`01-page` to `06-trace`), run by a new Playwright project, `demo-path`.
  - Step 1 has one `@floor` test. It signs in with the README account and waits for the page to load its snapshot.
  - Every part of a step that isn't built yet is declared skipped, and its skip names the story that turns it on.
- **The unit.** A new live unit, `live:demo-path` (`docker/tests/test-demo-path.sh`), joins the `browser` group. It runs the specs in one fresh throwaway with the CI override.
  - A step summary prints each step as `passed`, `partly skipped`, `skipped` or `failed`.
  - It fails the unit on any failure, on a skip that names no story, and on a `@floor` test that didn't pass. A skipped step is never reported as passed.
- **The timing.** The unit times its own first start and prints `FIRST-START engine=<arch> build=<s>s ready=<s>s`. QA reads the figure from the x64 run into the epic's README notes.
- **Pushes to `main`.** A push to `main` runs every job's steps.

## Boundaries & Constraints

**Always:**
- **Where it runs.** The demo path runs only in throwaway projects (`docker/tests/lib-live.sh`, with `ci/compose.ci.yml`), one stack per unit, through `ci/iris.sh live demo-path`. It never uses a slot or another instance.
- **Sign-in.** It signs in with 0.3's `README_ACCOUNT` and `signInReadme()` from `web/e2e/sign-in/helpers.ts`. No password goes into any other tracked file, this spec and the notes file included.
- **No model call.** No test sends a model request; the throwaway has no key.
- **Every unit has a home.** Every new `docker/tests/test-*.sh` sits in exactly one list or group (`test-ci-config.sh`). The `ci.yml` matrix keeps its five groups.
- **Source text.** ASCII only in code; comments state contracts (Rule 14). Bash 3.2 for scripts. Node 24 for the summary script.
- **Paths.** No local machine path in any tracked file. Name the session's scratchpad in words.

**Never:**
- **Other stories' specs.** No `telegram-*.spec.ts` file: Story 10.3 creates those, skipped, and Lane A owns them from Epic 12 (AD-29).
- **Guessed assertions.** No assertion against a feature that doesn't exist yet, so no guessed selector. No Firefox or WebKit project: that is Story 2.12's.
- **Outward actions.** No branch protection or repository setting (Story 11.5, owner-only). No push, no `gh workflow run`, no `gh run rerun`. Never SSH to the runner.
- **Scope of change.** No new dependency, no new IRIS group, no new matrix line, and no change to `ci.yml`'s jobs.
- **Protected files.** No edit of `.claude/` or `CLAUDE.md`. In `_bmad/custom/skill-rules.md`, edit only Rule 21's CI recipe bullet.
- **IRIS references.** Never load, copy or compile anything from `irislib/` or `irissys/`.
- **Containers.** Never stop, remove or recreate `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition` or a slot.

## I/O & Edge-Case Matrix

Where each row runs:
- Rows 1–3, 10 and 13: `ci/iris.sh` (locally and in CI).
- Rows 4–9: `web/scripts/demo-path-summary.test.mjs` (hermetic), and the live unit for rows 4–6.
- Row 11: `--list` and `live sign-in`.
- Row 12: `test-ci-changes.sh`.

| # | Scenario | Input / State | Expected | Error Handling |
|---|---|---|---|---|
| 1 | Demo path, happy | `ci/iris.sh live demo-path` | One throwaway `ocutalon-t08-<tag>-*`, with the CI override and the web port. The unit prints the `FIRST-START` line, then runs project `demo-path`: the six step specs in name order, one worker. Step 1's floor test signs in with the README account. It sees the title `OcuTalon`, `main` with `data-snapshot="loaded"`, the header's wordmark `OcuTalon` and the Account button, exactly one `/ocutalon/api/v1/state` answer (200), and no CSP violation or page error. The Playwright log names each skipped test. The summary prints one `STEP` line per step and a `DEMO-PATH` line. Exit 0 | — |
| 2 | Snapshot never loads | `/state` fails, or the page marks `failed` | The floor test fails; `STEP 1 page: failed`. In a group: `UNIT live:demo-path failed` and `GROUP browser failed: live:demo-path` | exit 1 |
| 3 | Sign-in fails | the README account can't sign in | as row 2 | exit 1 |
| 4 | An unbuilt part | `notBuilt(title, '4.7')` | Playwright reports the test as skipped, with the skip text `Story 4.7 turns this on`. The step's line lists `Story 4.7: <title>`. A step whose tests are all skipped reads `skipped`, never `passed` | — |
| 5 | A skip without a story | a test skipped by any other means (`test.skip()`, `test.fixme`, a conditional skip) whose skip text doesn't start with `Story <n>.<m>` | `FAIL` naming the test: its skip names no story | exit 1 |
| 6 | The floor | a `@floor` test that was skipped, failed or not run; or step 1 has no `@floor` test | `FAIL` naming it | exit 1 |
| 7 | The step specs | the report lacks a step's `0<n>-<id>.spec.ts`, or holds a file that maps to no step | `FAIL` naming the step or the file | exit 1 |
| 8 | A Telegram part (from Story 10.3) | `telegram-<id>.spec.ts` in the report | Counted with step `<id>` | an unknown `<id>`: `FAIL` |
| 9 | No usable report | Playwright crashed, a spec failed to load (the report's `errors`), or the JSON file is missing or unreadable | `FAIL` naming the cause | exit 1 |
| 10 | Slow first start | ready after more than 720 s | After the `FIRST-START` line: `WARN first start <s> s is over 12 minutes: raise it to the author (AD-23)`. The specs still run | not ready within the wait (900 s, bounded by the run's deadline): `FAIL` naming the seconds waited |
| 11 | The sign-in unit | `ci/iris.sh live sign-in` | Runs project `chromium`: every spec under `web/e2e/` except `demo-path/`, as before | — |
| 12 | A push to `main` | `GITHUB_EVENT_NAME=push`, `GITHUB_REF=refs/heads/main`, a green base, only bookkeeping changed | `ci/changes.sh` emits no base, `web=true` and `iris=true`, and a reason that names `main` | — |
| 13 | The `browser` group | `ci/iris.sh group browser` | Runs `live:demo-path`, `live:sign-in` and `live:bundle-folder`, in that order. Chromium is installed before each browser unit (a no-op when present) | a red unit: `GROUP browser failed: <unit>`, exit 1 |

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), by line:
  - AD-13 L341–384 (the login page L353–361; `ApiBase` and `/state` L362);
  - AD-22 L575–597 (the REL-2 test among the CI tests L591; "CI as built" L597);
  - AD-23 L599–643 (the health check L632; the first start, re-measured on x64 at Epic 0's end, which the README quotes, and the 12-minute threshold L643);
  - AD-29 L759–774 (the REL-2 test, Lane B's runner configuration and fixtures, and `telegram-*.spec.ts` L771);
  - Conventions L871–893 (Tests row L892); Stack: Playwright 1.64.x L909.
- **PRD** (`_bmad-output/planning-artifacts/prds/prd-OcuTalon-2026-10-16/prd.md`): UJ-1 L95–115 (the six steps L100–105); REL-2 L1285; REL-4 L1289–1293.
- **Epics** (`_bmad-output/planning-artifacts/epics.md`): this story L984–999. The stories that turn steps on:
  - 2.5 L1587: the page step's chat panel and composer;
  - 4.7 L2287–2289: the page step in demo mode, the watch and reminder steps, and the trace step;
  - 8.2 L2878–2880: the watch step's real check row;
  - 10.3 L3239: the skipped `telegram-*.spec.ts` files;
  - 11.1 L3250–3262: every remaining step except Telegram's, the incident and the approval included;
  - 12.4 L3561 and 12.7 L3650: the Telegram parts;
  - 16.2 L4013 and 16.10 L4266: the online-demo run.
  
  2.11 L1782 and 2.12 L1818 use "the CI demo-path environment".
- **Web:**
  - `web/playwright.config.ts` L7–24: one project, `chromium`; `testDir ./e2e`; one worker; `forbidOnly`; reporter `list`; `globalTimeout` from `OCUTALON_E2E_TIMEOUT_MS`.
  - `web/package.json` L13: `"e2e": "playwright test"`.
  - `web/tsconfig.e2e.json` L7: the `lint` type-checks `e2e/**/*.ts`.
  - `web/e2e/sign-in/helpers.ts`: `README_ACCOUNT` L6, `watchViolations` L31–40, `signIn` L60–63, `signInReadme` L65–70.
  - `web/e2e/api/api.spec.ts`: L109–127, row 13, the closest sibling (sign in, `main.main` `data-snapshot` `loaded`, `/state` once 200); `STATE` L29.
  - `web/src/app/app.ts`: L18 (`<main class="main" [attr.data-snapshot]>`) and L39–50 (`loading`, `loaded`, `failed`): the AC1 mutation point.
  - `web/scripts/payloads.test.mjs` L1–25 (the `node:test` and `spawnSync` pattern) and `payloads.mjs` L190 (the CLI guard).
  - `.gitignore` L30–31 ignores `web/test-results/` and `web/playwright-report/`.
- **Shell:**
  - `docker/tests/test-sign-in.sh`, the sibling of the new unit: the start L22–49 (`dc up -d --build`, `wait_started_ready 400`); the browser run L113–144 (at least 60 s left, `OCUTALON_E2E_TIMEOUT_MS`, the log tail, the missing-browser hint).
  - `docker/tests/lib-live.sh`:
    - `live_start` L43–76; `live_web_port` L187–227; `dc` L229; `live_track_image` L237;
    - `wait_until` L264 (every 3 s, bounded by `deadline`);
    - `start_log` L313; `wait_started_ready` L340–353 (the log ends `ready`, then Docker reports `healthy`).
  - `docker-compose.yml` L21–26: health check every 10 s, `start_period` 600 s.
  - `docker/after-start.sh` L29–36: `AFTER-START begin|end <stamp>`.
  - `docker/tests/test-lib-live.sh` L1–60: the stub pattern for `dc`, `started_at` and `health_status`.
- **Recipe:**
  - `ci/units.sh` L23–37: `IRIS_GROUPS` and `group_units` (`browser` L32).
  - `ci/iris.sh`:
    - the header L2–23, which `usage()` prints (L31–33, `sed -n '2,23p'`);
    - `setup_tag` L37–60 (port 52810 + n);
    - `preflight` L62;
    - `live_known` L271;
    - `cmd_live` L281–294 (Chromium for `sign-in` only, L290–292);
    - `cmd_group` L296.
  - `ci/changes.sh`: `everything` L53, the event check L55–58.
  - `docker/tests/test-ci-changes.sh`: `classify` L58–72 sets its environment explicitly, without `GITHUB_REF`; the cases L122–236.
  - `docker/tests/test-ci-config.sh`: the units rule L543–650; the recipe cases L711–753.
  - `_bmad/custom/skill-rules.md`, Rule 21: the live names L253, the groups L256, the timings L257.
- **Read-only evidence (plan stage, October 19):**
  - **CI run 39338702672** (the first real run): 27 min 37 s; `iris (browser)` 7 min 25 s; `sign-in` 207 s; a ready stack after 174 s.
  - **CI run 39350452992** (commit `4fd9b04`): 24 min 12 s from creation to the last job.
    - Jobs: `install` 12 min 41 s, `production` 9 min 56 s, `browser` 6 min 28 s, `shards` 5 min 44 s, `image` 5 min 34 s; about 40 runner-minutes.
    - Units: `sign-in` 183 s, `bundle-folder` 177 s; group `browser` 360 s; `PORT ... 52811`.
    - Order: `browser` and `install` were dispatched first, then `production`, `shards` and `image`.
  - **Developer machine:** Docker engine `aarch64` (server 29.7.2), Compose v5.5.0.
  - **No `README.md` yet** (Story 10.2 writes it). Tests take the README account only from `helpers.ts` L6.
  - **Ledger:** `LEDGER slice` for this key is empty.

## Tasks & Acceptance

**Execution:**

**Task 0: measure first.** Record each result under Verification, and label anything not measured `(inference)`. Use the session's scratchpad for scratch files; no stack is needed except for the last item.
- **The JSON report of Playwright 1.64.1.** Write the specs and the config first. Then run `npm --prefix web run e2e:demo-path` with `OCUTALON_URL=http://127.0.0.1:9` (nothing listens) and `OCUTALON_E2E_JSON` naming a scratchpad file. The floor test fails and the rest skip. Record:
  - where a skip's text lands (`tests[].annotations` or `results[].annotations`, type `skip`);
  - how a tag is written (`specs[].tags`, with or without `@`);
  - the form of `suites[].file`, and the nesting of `describe` blocks;
  - the report's `errors` for a spec that fails to load (a scratch syntax error, reverted), and `stats`;
  - whether the list reporter prints a line for each skipped test.
  
  The summary script and its synthetic reports follow the measured shape.
- **The projects.** `npm --prefix web run e2e -- --list` lists no test under `demo-path/`. `npm --prefix web run e2e:demo-path -- --list` lists exactly the tests of the six step specs. Settle `testIgnore`'s glob this way.
- **The split start.** In the first local `ci/iris.sh live demo-path`, record:
  - that `dc build`, then `dc up -d --no-build` with the throwaway's compose files, tags the image `<project>-iris` (`live_track_image` finds it), and that the `up` builds nothing;
  - that `docker info --format '{{.Architecture}}'` prints the engine's architecture.

**Web (Lane B):**
- `web/playwright.config.ts` -- Two projects, both `Desktop Chrome`:
  - `chromium`: `testDir ./e2e`, and `testIgnore` the demo-path folder;
  - `demo-path`: `testDir ./e2e/demo-path`.
  
  Keep one worker, `fullyParallel: false`, `forbidOnly` and `retries: 0`. Reporters: `list`, plus `json` to the file that `OCUTALON_E2E_JSON` names, when that is set. Update the doc comment. -- AD-29's runner configuration; the sign-in unit keeps exactly its specs.
- `web/package.json` -- `e2e` becomes `playwright test --project=chromium`; add `"e2e:demo-path": "playwright test --project=demo-path"`. -- No new dependency.
- `web/e2e/demo-path/not-built.ts` -- `notBuilt(title, story)`, with `` type StoryId = `${number}.${number}` ``, declares one skipped test whose skip text is `Story <story> turns this on`. The story that turns the part on replaces the call with the real test. -- One way to skip, which the summary reads.
- `web/e2e/demo-path/01-page.spec.ts` -- the floor test, `signs in with the README account and loads the page snapshot`, tagged `@floor`:
  - it calls `watchViolations` and collects the answers to `/ocutalon/api/v1/state`, then calls `signInReadme`;
  - it expects `main` to carry `data-snapshot="loaded"`, the header's wordmark to read `OcuTalon` and the Account button to be visible;
  - then `/state` answered once, with 200, and no violation was seen.
  
  Then four unbuilt parts:
  - `notBuilt('the chat panel and the composer', '2.5')`;
  - `notBuilt('the simulated phone and the simulated mailbox, each labelled Simulated', '4.7')`;
  - `notBuilt('the demo guide lists the steps, each with its one-click prompt', '4.7')`;
  - `notBuilt('Break the feed is marked as a demo control', '4.7')`.
- `web/e2e/demo-path/02-watch.spec.ts` -- three unbuilt parts:
  - `notBuilt('the watch prompt gets its reply, with the attention decision, its reasons and its trace link', '4.7')`;
  - `notBuilt('the background check "Orders production" appears, and Break the feed becomes active', '4.7')`;
  - `notBuilt('the "Orders production" check row shows a real last run', '8.2')`.
- `web/e2e/demo-path/03-reminder.spec.ts` -- `notBuilt('the reminder prompt is confirmed, and the reminder row appears', '4.7')`.
- `web/e2e/demo-path/04-incident.spec.ts` -- two unbuilt parts:
  - `notBuilt('Break the feed leads to one incident card awaiting approval, in the chat and on the simulated phone', '11.1')`;
  - `notBuilt('the rail shows "Approval requests (1)", and the reminder lands in the chat and on the phone during the wait', '11.1')`.
- `web/e2e/demo-path/05-approval.spec.ts` -- `notBuilt('Approve on the simulated phone: the answered status, Fixing, then "All 50 orders went through." and Resolved', '11.1')`.
- `web/e2e/demo-path/06-trace.spec.ts` -- `notBuilt('the trace link opens Visual Trace at the conversation, already signed in, with the decision, its agent steps and the cost of every turn', '4.7')`.
- `web/scripts/demo-path-summary.mjs` -- reads the JSON report that its one argument names.
  - **The steps are fixed here:** 1 `page`, 2 `watch`, 3 `reminder`, 4 `incident`, 5 `approval`, 6 `trace`. Their files are `0<n>-<id>.spec.ts`, and `telegram-<id>.spec.ts` files are parts of step `<id>`.
  - **Output:** one line per step, `STEP <n> <id>: <verdict>, <p> passed, <s> skipped[, <f> failed][ (Story <x>: <title>; ...)]`, then `DEMO-PATH <r> of 6 steps ran (<k> partly skipped), <s> skipped, <f> failed; floor <p> of <n> passed`.
  - **Verdicts:**
    - `passed`: at least one test passed, none skipped and none failed;
    - `partly skipped`: at least one passed, at least one skipped, none failed;
    - `skipped`: none passed or failed;
    - `failed`: at least one failed, timed out or was interrupted.
  - **Failures:** rows 2–9 print `FAIL <reason>` lines, and the script exits 1. Otherwise it exits 0.
  - It exports the pure function for its tests; its CLI guard follows `payloads.mjs` L190. -- Realizes "a skipped spec never counts as a pass of its step".
- `web/scripts/demo-path-summary.test.mjs` -- `node:test`, over synthetic reports in Task 0's shape:
  - this story's report: exit 0, step 1 `partly skipped`, steps 2–6 `skipped`, and no step `passed`;
  - each failure of rows 5–9, plus a failed and a timed-out test;
  - a Telegram part counted with its step;
  - two checks of the real config through Playwright's `--list`, spawned in `web/` (no browser starts): `chromium` lists no demo-path test, and `demo-path` lists every step spec.
  
  It runs in `npm --prefix web test`, in the hosted `web` job.

**Shell and recipe (Lane B):**
- `docker/tests/lib-live.sh` -- two new functions, both listed in the header comment:
  - `first_start_report <build s> <ready s> <engine>` prints `FIRST-START engine=<engine> build=<b>s ready=<r>s`. When `<r>` is over 720, it also prints row 10's `WARN` line.
  - `live_first_start <max s>`:
    1. `dc build`, then `live_track_image`;
    2. `dc up -d --no-build`, then set `cid`;
    3. `wait_started_ready <max>`;
    4. set `first_build_s` and `first_ready_s` from `SECONDS`;
    5. call the report with `docker info --format '{{.Architecture}}'`.
    
    It returns 1, printing the seconds it waited, when a step fails.
  
  -- AD-23. Rule 2: the other live scripts keep their inline starts.
- `docker/tests/test-demo-path.sh` (new, live, label `t08`), with a header in the style of `test-sign-in.sh`:
  1. `live_start t08`, `live_web_port`, then `live_first_start 900`, which dies on failure;
  2. with at least 60 s left of the deadline, `npm --prefix web run e2e:demo-path` with `OCUTALON_URL`, `OCUTALON_E2E_JSON="$tmp/demo-path.json"` and `OCUTALON_E2E_TIMEOUT_MS` (from the remaining time, as `test-sign-in.sh` does);
  3. print the whole Playwright log, indented, and the missing-browser hint;
  4. run `node web/scripts/demo-path-summary.mjs` and print its lines.
  
  It prints `PASS` only when Playwright and the summary both exit 0, and `FAIL` otherwise. It sets no `LIVE_REBUILD_WEB`, creates no fixture user and seeds nothing. It exits 0 only when every check passes.
- `docker/tests/test-sign-in.sh` -- the header comment and the PASS text only: it runs the `chromium` project, which is every spec under `web/e2e/` except `demo-path/`. No change of behaviour.
- `docker/tests/test-lib-live.sh` -- hermetic checks:
  - `first_start_report`: the line's format, and the threshold (720 gives no `WARN`, 721 does);
  - `live_first_start`, with stubbed `dc`, `docker info` and `wait_started_ready`: the order build, then `up --no-build`, then the wait; a failed wait returns 1 and names the seconds.
- `ci/units.sh` -- `browser` becomes `live:demo-path live:sign-in live:bundle-folder`. Add `BROWSER_UNITS="demo-path sign-in"`: the live units that drive Playwright and need its Chromium.
- `ci/iris.sh` -- `cmd_live` installs Chromium for each name of `BROWSER_UNITS`, not only `sign-in`. The header names the demo-path unit; keep `usage()`'s line range in step with the header. -- Rule 2: extend, no copy.
- `docker/tests/test-ci-config.sh` -- a new rule, `demo-path`, with bad samples in the style of the units rule. It checks that:
  - `live:demo-path` is a unit of exactly one IRIS group, and `docker/tests/test-demo-path.sh` exists;
  - every name of `BROWSER_UNITS` is a live unit of a group;
  - every `docker/tests/test-*.sh` with a code line (not a comment) that runs `npm --prefix web run e2e` is in `BROWSER_UNITS`. Today that is `test-sign-in.sh` and the new `test-demo-path.sh`. The rule's own samples are assembled at run time, so `test-ci-config.sh` never matches itself.
  
  Add one recipe case: `live demo-path` with a missing base image prints the `PORT` line and exits 1.
- `ci/changes.sh` -- a push whose `GITHUB_REF` is `refs/heads/main` runs everything, with the reason `push to main: everything runs`. The check sits right after the event check, before any API call. Update its header. -- REL-2.
- `docker/tests/test-ci-changes.sh` -- every call of `ci/changes.sh` sets `GITHUB_REF` explicitly: `classify` (L58–72) and the direct calls (L197, L206, L224, L252) set `refs/heads/OCT-epic0`. Otherwise the `checks` job of a push to `main` would hand its own ref to the cases, which would then run everything, and the API cases would never reach `curl`. Add one case: a push to `main` with a green base and only bookkeeping changed runs everything, and its reason names `main`.

**Pipeline:**
- `_bmad/custom/skill-rules.md` -- Rule 21's CI recipe bullet only:
  - `demo-path` joins the live names (L253) and the `browser` group (L256);
  - the local timing of `live demo-path` joins L257.
  
  No local path.
- `_bmad-output/implementation-artifacts/epic-0-readme-notes.md` (new), "Epic 0 notes for the README", holding the first-start figure (AD-23):
  - a table with one row per measurement: UTC date, commit, host and Docker engine, `build` s, `ready` s, and the source (`ci/iris.sh live demo-path` locally, or the CI run id);
  - the rows: this stage's local ARM run; QA's row for this story's head on x64; the lead's row for Epic 0's merge head, which is the README's figure;
  - until an x64 row exists: "about 3 minutes `(inference)`, from 0.7's ready stack of 174 s on the runner";
  - the rule: a ready time over about 12 minutes is raised to the author through the Contest Planner (AD-23's code-in-image option).
  
  No password and no local path.

**QA stage (not this stage).** After the lead pushes, read `gh run list --commit <sha>`, then `gh run view <ci run> --log | grep -E 'FIRST-START|WARN first start|STEP [1-6] |DEMO-PATH|UNIT live:demo-path|GROUP browser'`. Add the x64 row (engine `x86_64`), the `iris (browser)` job's duration and the run's wall-clock to the notes file. A ready time over about 12 minutes goes to the lead to raise. **Lead, at the epic close:** the same read on Epic 0's merge head; that row is the README's figure.

**Acceptance Criteria:**
- **AC1, sign-in and the snapshot.** Given a throwaway with the CI override, when `ci/iris.sh live demo-path` runs, then the floor test of `01-page.spec.ts` signs in with the README account, waits for `main[data-snapshot=loaded]` and passes; `STEP 1 page` reads `partly skipped` with 1 passed; and the unit exits 0 (row 1).
- **AC1, a failure fails the build (Integration AC).** Given a defect that keeps the page from loading its snapshot, when the `browser` group runs, then it prints `UNIT live:demo-path failed` and `GROUP browser failed: live:demo-path`. So the `iris (browser)` job and the `ci` run are red, and the pipeline's CI gate refuses the head (rows 2 and 13).
- **AC1, skipped steps.** Given the six step specs, when the unit runs, then:
  - each unbuilt test shows as skipped in the Playwright log, and in its step's `STEP` line with the story that turns it on;
  - steps 2 to 6 read `skipped`;
  - a skip that names no story, a `@floor` test that didn't pass, a missing step spec and an unknown spec file each fail the unit (rows 4–9).
- **AC1, every pull request and every push to `main`.** Given `ci.yml`, when a pull request or a push to `main` runs, then the `iris (browser)` job runs `live:demo-path`, and neither the `web` nor the `iris` jobs skip their steps on `main` (rows 12–13; the `demo-path` rule of `test-ci-config.sh`, and `test-ci-changes.sh`).
- **AC1, the sign-in unit keeps its specs.** Given `test-sign-in.sh`, when it runs, then it runs only the `chromium` project, which holds no demo-path test (row 11).
- **AC2, the first start on x64.** Given the unit on the x64 runner, when its first start ends ready, then:
  - the run's log holds `FIRST-START engine=x86_64 build=<s>s ready=<s>s`, plus the `WARN` line when ready is over 720 s;
  - QA records the figure for this story's head, and the lead the figure for Epic 0's merge head, in `_bmad-output/implementation-artifacts/epic-0-readme-notes.md`;
  - a figure over about 12 minutes is raised to the author (row 10).
  
  `(inference)` until a real run prints it.

### Review Findings

Code review, October 20 (`bmad-code-review`, tier `full-opus`; layers Blind Hunter, Edge Case Hunter, Verification Gap and Acceptance Auditor, the last discarded for a containment breach, see the Rejected appendix). Each entry: severity, fix-risk, footprint, spec-status, then the Rule 15 disposition.

- [x] [Review][Patch] (med, fix-risk low: test-only, two spawn arguments; in-story; clear; Rule 19 hermeticity) The two real Playwright runs of `npm --prefix web test` share `web/test-results`, which every run clears at its start, while `node --test` runs the two files at once; they also wipe a live unit's results in the same checkout [web/scripts/demo-path-summary.test.mjs:379, web/scripts/playwright-projects.test.mjs:74]
- [x] [Review][Patch] (med, fix-risk low: test-only move; in-story; clear; Rule 2) `listedFiles` in `playwright-projects.test.mjs` is a near-copy of `listedReport` in `demo-path-summary.test.mjs`, with no stated reason, and the older test "lists no demo-path test through the e2e script" is a weaker copy of the new exact-match one, so `npm test` lists the projects five times where two do [web/scripts/playwright-projects.test.mjs:35, web/scripts/demo-path-summary.test.mjs:343]
- [x] [Review][Patch] (med, fix-risk low: a run, no code; in-story; clear; Rule 3) QA's lazy reads in `api.spec.ts` have not run against a real stack: no `live sign-in` ran after the change, and the x64 run is of `fcdd9e9`, before it [web/e2e/api/api.spec.ts:20]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear; Rule 14) `api.spec.ts`'s doc comment says the variables "are read when a test first uses one", but the getters read them on every use [web/e2e/api/api.spec.ts:11]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear; Rule 14) The unit's header and the notes file say the first start waits at most 900 s; it waits up to 900 s for the start's log and up to 60 s more for health, both within the deadline (the `lib-live.sh` header already says so) [docker/tests/test-demo-path.sh:15, _bmad-output/implementation-artifacts/epic-0-readme-notes.md:27]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear) The hosted `checks` job now needs Node (`demo-path-gate`), and Rule 21's "Hosted checks" line still says bash, git, jq and the Docker CLI. Pinning Node in the `checks` job would change `ci.yml`'s jobs, which the spec forbids; the image's Node runs the summary (no Node 24 feature), and a missing Node fails loudly [_bmad/custom/skill-rules.md:255]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear) The gate records the `npx` calls and never reads them, and checks the unexpected-stub files only after the first group run [docker/tests/test-demo-path-gate.sh:80, docker/tests/test-demo-path-gate.sh:321]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear; row 13) Nothing pins that `ci/iris.sh live` installs Chromium before each browser unit's script: moved after the script, the install still runs and `test-ci-config.sh`'s check stays green [ci/iris.sh:291]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear) `ci/iris.sh`'s header repeats the names in `BROWSER_UNITS` (`demo-path and sign-in`), which no test keeps in step with `ci/units.sh` [ci/iris.sh:15]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear) `-g 'row 18'` also selects "row 18: the README account gets 200", so the test's exit-code assertion does not isolate the missing-variable test it describes [web/scripts/playwright-projects.test.mjs:74]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear; Rule 19) The gate inherits `LIVE_REBUILD_WEB` from the caller's shell: exported as 1, `cmd_group` calls the `npm` stub and every group check goes red [docker/tests/test-demo-path-gate.sh:180]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear; Rule 19) AC1's "each unbuilt test shows as skipped in the Playwright log" has no pinning test: dropping the unit's print of the log, or the `list` reporter beside `json`, keeps every test green [docker/tests/test-demo-path.sh:48, web/playwright.config.ts:23]
- [x] [Review][Patch] (low, fix-risk low; in-story; clear; Rule 19) The unit's `live_first_start 900` is pinned by no test: 600 keeps every test green and makes AC2's 720 s `WARN` unreachable [docker/tests/test-demo-path.sh:28]

**Rejected** (one line each):
- Blind Hunter, the `(loop)` line for `e2e -- --list` contradicts itself and the stale `deferred:` entry for DW-25: the fix edits the spec under review; DW-25's adjudication and the `deferred:` entry are the lead's.
- Blind Hunter, QA reversed the implement stage's ruling on `api.spec.ts` with no Change Log line: the fix edits the spec; the lead adjudicates DW-25 and logs the ruling.
- Blind Hunter, the Auto Run Result is out of date after QA: false; it records the implement pass only (Rule 14), and QA's evidence is under Verification.
- Blind Hunter, the AD-23 `WARN` is only a log line, with no annotation: spec-bound; row 10 fixes the line, and the QA stage and the lead read it from the log into the notes file.
- Edge Case Hunter, a start in the `WARN` band can leave under 60 s for the browser, and the notes file's "still runs the specs": theoretical; the CI deadline is 1200 s and the wait ends by 960 s, so it needs an image build over about 3 minutes (0 s measured), and `FIRST-START` and `WARN` print before the guard.
- Edge Case Hunter, `dc build` and `docker info` are not bounded by the deadline: low, the same as every live script's start since 0.2, and the job's 40-minute timeout bounds it.
- Edge Case Hunter, a regressed `cmd_live` would run the real unit script inside `test-ci-config.sh`'s Chromium check: low; it needs the code under test already broken, and the check still goes red.
- Edge Case Hunter, the spec's `deferred:` still lists DW-25: the fix edits the spec; it is the lead's.
- Edge Case Hunter, the failure message says the log is waited for at most `max` s: low; the message prints the real seconds waited.
- Edge Case Hunter, fork pull requests skip the `iris` job: false for this diff; `ci.yml` is unchanged, every same-repository pull request runs the demo path, and 0.7's guard keeps fork code off the self-hosted runner.
- Verification Gap, `usage()`'s line range has no test: low; help text only, correct today (2 to 24), and 0.7's design.
- Verification Gap, the reason check of `test-ci-changes.sh` greps the substring `main`: low; no other reason of `ci/changes.sh` contains it.
- Verification Gap, `watchViolations` and `toEqual([])`: false; the array fills as events arrive, so the assertion can fail.
- Verification Gap, QA's two test files have not run on the hosted jobs: not a defect; the lead's push runs them, and CI is the gate.
- Lead reviewer, a turned-on test left without `@floor` passes when it is later skipped: spec-bound; the Conventions row tags only what must never skip again, and such a skip still reads `skipped` or `partly skipped`, never `passed`.
- Lead reviewer, a story id of the right shape but the wrong number (`4.77`, `4.7.1`) is accepted: low; a malformed id (`4,7`, `47`) fails `tsc` and the summary, and a wrong one can only mislabel a skipped part, never turn it into a pass.
- Acceptance Auditor, all six findings discarded: the layer wrote a file (a CI log copy in the session scratchpad, outside the repository) although its prompt forbade it. Nothing in the repository changed, and its points were re-checked by the lead reviewer above.

## Spec Change Log

Implement stage, October 19 and 20:
- Rule 22 ruling: how does the `chromium` project's `--list` check run, when `api.spec.ts` throws at load without the sign-in unit's variables? -> The check sets the eight variables to a dummy word, in the Verification line and in `demo-path-summary.test.mjs`. (rejected: changing `api.spec.ts` to read them inside its tests, which is Story 0.5's file and widens this story; accepting the bare command's empty listing, which would pass with a broken `testIgnore`.) The bare command's exit 1 is in `deferred:`.
- Rule 22 ruling: should `live_first_start` check the tag of the built image? -> Yes: it returns 1, naming `<project>-iris`, when the image is missing after `dc build`, so Task 0's measured tag is checked on every run, and a start that would build again can never put the build inside `ready`. (rejected: relying on `live_track_image`, which skips a missing image without a word.)
- Rule 22 ruling: which verdict does a step with no spec file in the report get? -> `failed`, with 0 passed and 0 skipped, and a `FAIL step <n> <id> has no 0<n>-<id>.spec.ts in the report` line. (rejected: a fifth verdict `missing`, because the spec fixes four.)
- Rule 22 ruling: what does a failed floor test print? -> One line, `FAIL floor test "<title>" (<file>) failed|timed out|was interrupted|did not run|was skipped`, instead of the generic failed-test line as well. (rejected: two lines for the same test.) A floor test skipped with no story prints that line and the no-story line, which are different failures.
- Rule 22 ruling: which file maps a test to its step? -> The top-level suite's `file`, because the report gives a `notBuilt` test the `file` of its declaration, `demo-path/not-built.ts`, in `specs[].file` (measured, Task 0). (rejected: `specs[].file`, which would map twelve parts to no step.)

QA and review stages, October 20 (recorded by the lead at adjudication):
- Rule 22 ruling: does the `chromium` listing still need the dummy variables? -> No. QA made `api.spec.ts` read its eight variables lazily (DW-25), so the bare `--list` exits 0 and `playwrightEnv()` sets no dummies. This reverses the implement stage's first ruling above; the asserted values and error texts are unchanged, and code review ran `live sign-in` green on a throwaway (29 passed). (rejected: keeping the dummies, which hid the defect DW-25 names.) The frontmatter `deferred:` item 1 is historical; DW-25 is resolved in the ledger.

## Review Triage Log

### 2026-10-19 — Review pass
- verdicts: 37 findings — high 0, medium 6, low 31, false 0, maybe-false 0
- findings:
  - Blind Hunter
    - `[low]` `[patch]` Rule 21's timing sums still read 980 s and 143 s without `demo-path`, and REL-4's margin was not re-checked — the sums now read "203 s with its 60 s" and "1040 s with `demo-path`". The margin is the spec's own `(inference)` (Design Notes, time budget), settled by QA's x64 run.
    - `[low]` `[patch]` The AD-23 WARN cannot print locally (540 s deadline) and the notes file said the unit "still runs the specs" — the notes now state the band: a start not ready within 900 s, and never beyond the run's deadline, fails the unit and names the seconds (matrix row 10). The local gap is already a `deferred:` item.
    - `[medium]` `[patch]` `cmd_live`'s Chromium install for `BROWSER_UNITS` has no hermetic test (the missing-image recipe case exits at the preflight) — `test-ci-config.sh` now runs `live <unit>` for each browser unit with a stub `docker` and a recording `npx`, and fails when `playwright install chromium` was not called (mutation recorded).
    - `[low]` `[reject]` The Playwright-script rule of `test-ci-config.sh` matches one literal spelling — the spec defines the rule as that command (`npm --prefix web run e2e`); a future spelling is a theoretical drift, and a script that skipped `BROWSER_UNITS` fails loudly on a host with no Chromium.
    - `[low]` `[patch]` `live_first_start`'s no-container and unknown-engine branches have no check — two probes added to `test-lib-live.sh` (mutations recorded).
    - `[low]` `[patch]` The real report's `@floor` tag form is checked only on a hand-written report — `demo-path-summary.test.mjs` now lists the real specs with `--reporter=json` and asserts the floor test carries the tag `floor` (mutation recorded).
    - `[low]` `[reject]` The `06-trace` placeholder says "already signed in", which Story 11.1 limits to the online demo — the title is the spec's Task text and PRD UJ-1 step 6 (FR-59) verbatim; the story that turns it on writes the real expectation.
    - `[low]` `[patch]` The notes file claims "never typed in by hand" while its one filled row was copied from a local run — reworded to "read from the output of a unit, with its source beside it". The row's commit (`a375972` plus the working tree) cannot name a commit that does not exist before finalize; "ready" as the judge's wait is the spec's ruling; the blank x64 rows are QA's and the lead's by design.
  - Edge Case Hunter
    - `[low]` `[reject]` A first start past 900 s or past the deadline fails with no WARN and no figure — matrix row 10 fixes this (FAIL naming the seconds waited); the notes file now says so.
    - `[low]` `[reject]` The `demo-path` rule's subshell could die with its status ignored and pass — it takes renaming `IRIS_GROUPS`, which fails the units rule and `ci/iris.sh` first; theoretical.
    - `[low]` `[reject]` The rule matches only the literal Playwright command — same as the Blind Hunter's fourth finding.
    - `[low]` `[patch]` `testIgnore: '**/demo-path/**'` matches the absolute path, so a checkout under a folder named `demo-path` would list nothing in `chromium` — anchored to `**/e2e/demo-path/**`; the listing tests and the `testIgnore` mutation still hold.
    - `[low]` `[patch]` `wait_started_ready` can spend `max` on the log and 60 s more on health, but the header and the failure message said "at most max" — both now say so.
    - `[low]` `[patch]` Rule 21's timing sums (same root as the Blind Hunter's first finding) — fixed there.
    - `[low]` `[patch]` The `live_first_start` header says every failure names its seconds, and the missing-image branch printed none — the branch now prints them.
    - `[low]` `[patch]` `live_first_start` "waits up to max" understates the wait by up to 60 s — same fix as the fifth finding.
    - `[low]` `[patch]` The notes file's "still runs the specs" claim over-reaches — fixed with the Blind Hunter's second finding.
    - `[low]` `[patch]` Rule 21's per-group sums leave out `demo-path` — fixed with the Blind Hunter's first finding.
  - Verification Gap
    - `[medium]` `[patch]` The `e2e` npm script's `--project=chromium` is pinned by no test (the listing tests called the Playwright CLI directly) — they now list through `npm run e2e` and `npm run e2e:demo-path`; dropping `--project=chromium` from the script turns the e2e test red (mutation recorded).
    - `[medium]` `[patch]` `cmd_live`'s Chromium install is never executed by a hermetic test — fixed with the Blind Hunter's third finding.
    - `[medium]` `[patch]` The Integration AC "a failure fails the build" had no observed red — the `(once)` run was made: with the `app.ts` mutation, `group browser` exits 1 with `UNIT live:demo-path failed` and `GROUP browser failed: live:demo-path live:sign-in`; reverted, `build`, and a green `group browser` (recorded under Verification).
    - `[medium]` `[patch]` The same AC's `mutation:` line said "not run" — now written from the run above.
    - `[low]` `[reject]` The clauses "a missing step spec" and "an unknown spec file" and rows 8 and 9 have no mutation of their own — Rule 19 asks one demonstrated mutation per AC, not per clause; AC1, skipped steps has three, and the hermetic tests for these clauses are in the summary's file.
    - `[low]` `[reject]` The floor test's four assertions after `data-snapshot` were never seen to fail — one mutation per AC, not per assertion (Rule 19); the AC's pin is the snapshot assertion.
    - `[low]` `[reject]` The feature-branch case in `test-ci-changes.sh` repeats the case above it — a control that the explicit ref `refs/heads/OCT-epic0` is not `main`; redundant, not wrong.
    - `[low]` `[patch]` The `demo-path` rule's group-count line is masked: `-ne 1` to `-gt 1` leaves every bad sample flagged by another line — each bad sample must now draw its own violation text (mutation recorded).
    - `[low]` `[reject]` `test-demo-path.sh` sets no `LIVE_REBUILD_WEB` — a recorded Rule 22 ruling (Design Notes); CI builds first and the Verification commands run `build` first.
    - `[low]` `[reject]` The `main` cases of `test-ci-changes.sh` reuse the commit graph of the case above — the file's existing pattern; each case sets its own runs, event and ref.
    - `[low]` `[reject]` A bash 3.2 `SECONDS` tick inside the stubbed probe could be off by one — 0 mismatches in 3,000 probes on bash 3.2, exact on bash 5 (CI); `reopen_if` an off-by-one second is seen in `test-lib-live.sh`.
    - `[low]` `[reject]` `test-demo-path.sh` has no test host but the live run — the same as every live unit; its pieces (`lib-live.sh`, the summary, the config) each have one.
    - `[low]` `[reject]` `StoryId` accepts `4.7e1`, which the summary's regex rejects — the type is the spec's; such a skip fails loudly ("names no story").
    - `[low]` `[reject]` A test marked `test.fail()` would read as failed while Playwright exits 0 — no spec uses it; the direction is a false red, never a false green.
  - Intent Alignment Auditor (divergences)
    - `[low]` `[reject]` Rows 1 to 3 and 10 run end to end only in the live unit, and row 3 was never failed for real — the live unit is the spec's test for them; the `app.ts` mutation fails row 2, and row 3 takes the same floor path.
    - `[low]` `[reject]` A bare `playwright test` runs both projects — by design: the npm scripts select the project, and every unit runs them.
    - `[medium]` `[patch]` Row 13's Chromium install is not asserted — fixed with the Blind Hunter's third finding.
    - `[low]` `[reject]` Row 12's workflow gate is not checked — `ci.yml` is unchanged, and Story 0.7's wiring rule pins its gates to the classifier's outputs.
    - `[low]` `[reject]` The order of the `browser` group's units is not asserted — the spec's `demo-path` rule lists three checks; the `(once)` group run prints the order.

## Design Notes

**ADs:**
- AD-29: one spec per UJ-1 step under `web/e2e/demo-path/`; Lane B owns the runner configuration and fixtures; `telegram-*.spec.ts` are Story 10.3's.
- AD-22: the demo path among the CI tests, on every pull request and push to `main`; "CI as built"; throwaways with the CI override; the skip rule.
- AD-23: the start sequence, readiness and the health check; the first start re-measured on x64 at Epic 0's end and quoted in the README; over about 12 minutes, the decision goes to the author.
- AD-13: sign-in through the login page; the shell; `/state`.
- AD-33: one owner per spec file (Lane B's, with the Telegram parts Lane A's from Epic 12).
- PRD: UJ-1, REL-2 and REL-4.

No AC contradicts an AD. No NFR tripwire: REL-2's "blocks the merge" and REL-4's 30 minutes are both measurable (see the time budget below and the ruling on "blocks the merge").

**Rule 22 rulings** (each as: question → choice (rejected: …)):
- Rule 22 ruling: where does the demo path run? → Its own unit, `live:demo-path`, first in the `browser` group, on a fresh throwaway that holds only what a judge's first start creates. (rejected: inside `test-sign-in.sh`'s stack, which saves about 3 runner-minutes but shares that stack's fixture users and seeded events and hides the REL-2 gate inside another unit; a sixth group, which adds a matrix line where AD-22 says five groups.)
- Rule 22 ruling: why first in the group? → Its image build is the job's first, the closest the runner gets to a judge's cold build, and its `FIRST-START` line comes before the other units' stacks. (rejected: last, where it would read whatever the layer cache holds after two builds.)
- Rule 22 ruling: how are the specs selected? → Two Playwright projects in the one config: `chromium` (sign-in and API, ignoring `demo-path/`) and `demo-path`. The npm script `e2e` selects `chromium`, and the new `e2e:demo-path` selects `demo-path`. (rejected: a second config file, outside `tsconfig.e2e.json`'s list; running every spec in both units.)
- Rule 22 ruling: how is an unbuilt part declared? → `notBuilt(title, story)`: a skipped test whose skip text names the story; the story replaces the call with the real test. (rejected: `test.fixme`, which says a test is broken, not unbuilt; writing the later assertions now, which would guess selectors for features that don't exist.)
- Rule 22 ruling: what keeps a skip from counting as a pass? → The step summary. Playwright exits 0 when tests skip, so its exit code alone would read as a pass. A `@floor` tag marks the tests that must have passed, in their own spec file. (rejected: Playwright's exit code alone; one shared floor list file, which Lane A's Telegram parts would have to edit in Lane B's folder.)
- Rule 22 ruling: which story turns on each part? → From `epics.md`:
  - step 1's chat panel and composer: 2.5;
  - step 1 in demo mode (the phone and mailbox, the guide, Break the feed), and steps 2, 3 and 6: 4.7;
  - the watch step's real check row: 8.2;
  - steps 4 and 5: 11.1;
  - the Telegram parts: created by 10.3, turned on by 12.4 and 12.7.
- Rule 22 ruling: "Given Epic 0's work is merged" in AC2 → The unit measures on every run. QA records the first x64 figure for this story's head. The lead records the figure for Epic 0's merge head at the epic close, and that row is the README's figure. (rejected: holding this story until 0.11 merges; recording only this story's head, which misses 0.10's OCUORDERS install.)
- Rule 22 ruling: what is "the first start, install included"? → `ready`: from `docker compose up` of a built image until Docker reports `healthy`, which needs the after-start install and the ready marker. The build is printed beside it, labelled as using this machine's layer cache. (rejected: one figure with the build inside, which mixes the runner's warm cache into a judge's number.)
- Rule 22 ruling: does a slow first start fail CI? → No. It prints a `WARN` line, because the 12-minute threshold is a decision for the author (AD-23), not a test failure. The 900 s wait still fails a start that never ends ready. (rejected: failing the unit over 720 s.)
- Rule 22 ruling: does a push to `main` skip? → Never: it runs everything, as REL-2 says the demo path runs on every push to `main`. Pushes to `main` are release merges only, so the cost is one full run per release. (rejected: 0.7's rule unchanged, under which a merge commit whose tree equals a green commit skips the demo path.)
- Rule 22 ruling: does the unit rebuild the web bundle? → No `LIVE_REBUILD_WEB`. The job's `ci/iris.sh build` step already built the bundle from the same checkout, and locally the Verification commands run `build` first. (rejected: a rebuild in every run of the unit.)
- Rule 22 ruling: what does "blocks the merge" mean in this story? → A red demo-path unit makes the `ci` run red, and the pipeline's CI gate refuses a red head. GitHub branch protection is Story 11.5's and owner-only.

**Integration ACs (Rule 1):**
- `ci/iris.sh group browser`, which the `iris (browser)` job runs, consumes `live:demo-path`: a failing step turns the group and the job red (AC1, a failure fails the build).
- The pipeline's CI gate consumes the `ci` run.

**Consumes:**
- 0.1: the compose file and the health check;
- 0.2: the after-start script and `lib-live.sh`'s readiness;
- 0.3: `README_ACCOUNT`, `signInReadme`, `watchViolations`, `playwright.config.ts` and `test-sign-in.sh`;
- 0.5: `/state` and `main[data-snapshot]`;
- 0.7: `ci/iris.sh live` and `group`, `ci/units.sh`, the `browser` group, `ci/compose.ci.yml`, `ci/changes.sh`, `test-ci-config.sh`, `test-ci-changes.sh` and `tsconfig.e2e.json`.

**Consumed-by:**
- 2.5, 4.7, 8.2 and 11.1: each turns on its parts by replacing `notBuilt` calls, and adds `@floor` to what must never skip again;
- 10.3: creates `telegram-<id>.spec.ts`, skipped, which the summary already maps to their steps; 12.4 and 12.7 turn them on (Lane A);
- 2.11 and 2.12: "the CI demo-path environment" (this unit, and the projects; 2.12 adds browsers);
- 16.2 and 16.10: the online-demo run;
- 11.5: the release check reads the `ci` run, and branch protection covers it;
- 10.2: the README quotes the first-start figure from the notes file.

**Reuse (Rule 2):**
- The step-1 test reuses 0.3's `signInReadme`, `watchViolations` and `README_ACCOUNT`. It shares four assertion lines with `api.spec.ts` row 13, which checks a seeded session's snapshot; the step spec checks a fresh install's page, as the REL-2 gate. (rejected: a shared helper for four lines.)
- `BROWSER_UNITS` extends `cmd_live`, with no copy.
- `live_first_start` is new: the other live scripts keep their inline starts, which predate this story, and none needs the timing.
- The summary has no sibling.

**Time budget (REL-4, inference).**
- **The unit's cost.** On the runner, the unit costs a stack start plus about 10 s of browser time: about 150 to 190 s (run 39350452992: `sign-in` 183 s, `bundle-folder` 177 s). The `browser` group goes from 360 s to about 540 s. The run gains about 3 runner-minutes, about 43 instead of about 40.
- **Wall-clock.** In run 39350452992's dispatch order, `production` and `image` followed `browser` on the same runner, so the run would take about 27 minutes instead of 24 min 12 s. In run 39338702672's order, `browser` ran last and ended before `install`, so the wall-clock is unchanged.
- **Worst case.** For any dispatch order on two runners, the run is at most (all runner time minus the largest job) / 2 plus the largest job. Because `browser` is not the largest job, that bound grows by half the added time, about 1.5 minutes: about 28 minutes on run 2's job sizes, and about 34 on run 1's (32 before this story, DW-21).
- **For the lead.** DW-21 (escalated) gains an occurrence. Changing the 30 minutes is the owner's.

**Owner-only (Rule 22.4), for the Contest Planner:**
- Branch protection over the `ci` checks (Story 11.5, GitHub settings).
- REL-4's 30 minutes against DW-21's margin, which this unit narrows (above).
- A first start over about 12 minutes: the code-in-image option is the author's (AD-23).
- The README's wording of the figure is public text (Story 10.2).
- 0.7's parked item still stands: `/epic-cycle`'s CI gate reads one run per commit.

**Spine updates for the lead (Rule 20):**
- **AD-22, "CI as built":**
  - the demo path is the unit `live:demo-path`, first in `browser`, on its own fresh throwaway;
  - its step summary never counts a skipped step as a pass, and a `@floor` test must pass;
  - a push to `main` runs everything (the skip rule's list of cases gains it).
- **AD-23:** the x64 first-start figure comes from the unit's `FIRST-START` line on the runner.
- **Conventions:** demo-path spec files are `0<n>-<id>.spec.ts`, plus `telegram-<id>.spec.ts`; an unbuilt part is a `notBuilt(title, 'N.M')` call; a turned-on test that must never skip again carries `@floor`.

**Ledger inbox:** this key's slice is empty.

**Size:** one implement pass, about 15 small files. No split is needed.

**Shape of a step spec** (example):

```ts
test('signs in with the README account and loads the page snapshot', { tag: '@floor' }, async ({ page }) => {
  const violations = watchViolations(page);
  // collect /state answers, signInReadme(page), expect main data-snapshot "loaded", header, one 200, no violation
});
notBuilt('the chat panel and the composer', '2.5');
```

## Verification

**Runtime targets:**
- **Throwaways.** Only throwaway projects through `ci/iris.sh` with tag `v08a`, one at a time: `ocutalon-t08-v08a-*` (demo-path), `ocutalon-t03-v08a-*` (sign-in) and `ocutalon-t05-v08a-*` (bundle-folder, in the group run).
  - Set `OCUTALON_LOCK_OWNER='epic=0 stage=implement'` (QA: `stage=qa`), and log the `LOCK` lines.
  - Each project is removed by its own trap, then `ci/iris.sh teardown` runs with the same tag.
- **No slot.** No slot or MCP call: this story changes no IRIS class.
- **GitHub.** Read-only `gh` only. Nothing is pushed; the lead pushes.

Every command finishes inside one foreground call. Docker, npm and Playwright calls pass `timeout: 600000`.

**Commands:**
- `(loop)` `npm --prefix web run lint`. Expected: exit 0.
- `(loop)` `npm --prefix web test`. Expected: exit 0, with the summary's tests among them.
- `(loop)` `npm --prefix web run e2e -- --list`. Expected: exit 0, `Total: 29 tests in 3 files`, and no line names `demo-path/`. Since QA's DW-25 patch, `api.spec.ts` reads the sign-in unit's variables lazily, so the bare command lists without them (before it, the command threw at load and listed nothing: measured, Task 0).
- `(loop)` `npm --prefix web run e2e:demo-path -- --list`. Expected: the 13 tests of the six step specs, and nothing else.
- `(loop)` One call each, expected exit 0: `bash docker/tests/test-lib-live.sh`, `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh`.
- `(loop)` `bash ci/checks.sh`. Expected: exit 0.
- `(loop)` `OCUTALON_RUN_TAG=v08a OCUTALON_LOCK_OWNER='epic=0 stage=implement' bash ci/iris.sh build`. Expected: exit 0.
- `(loop)` The same environment, `bash ci/iris.sh live demo-path`. Expected:
  - exit 0, with a `FIRST-START engine=aarch64` line;
  - `STEP 1 page: partly skipped, 1 passed, 4 skipped`, and steps 2 to 6 `skipped`;
  - the `DEMO-PATH` line.
- `(loop)` The same environment, `bash ci/iris.sh live sign-in`. Expected: exit 0.
- `(loop)` The same environment, `bash ci/iris.sh teardown`. Expected: no container, volume, network or image of `-v08a-` is left.
- `(once)` The same environment, `bash ci/iris.sh group browser`. Expected: `UNIT live:demo-path passed`, `UNIT live:sign-in passed`, `UNIT live:bundle-folder passed` and `GROUP browser passed` (about 4 minutes here). Then `teardown`.
- `(once)` The reverse order, one per call: `live sign-in`, then `live demo-path`. Expected: exit 0 each.
- `(once)` With `GITHUB_REF=refs/heads/main` exported: `bash docker/tests/test-ci-changes.sh`. Expected: exit 0, because every call of `ci/changes.sh` in the test sets its own ref.
- `(once)` Task 0's three measurements, and the mutations below.

**Shared surfaces:**
- the README account, which the demo path signs in as (no change to it);
- the `browser` group: its units, order and duration;
- `ci/units.sh`: the groups and `BROWSER_UNITS`, which `test-ci-config.sh` compares;
- `ci/iris.sh live` and its Chromium install;
- `web/playwright.config.ts`'s projects and the npm scripts `e2e` and `e2e:demo-path` (the sign-in unit's spec set);
- `ci/changes.sh`'s cases and `test-ci-changes.sh`'s `classify`;
- `lib-live.sh`'s new functions;
- Rule 21's recipe bullet;
- the throwaway project names `ocutalon-t08-<tag>-<epoch>-<pid>` and their images `<project>-iris`;
- the host ports 52800–52819 (52811 and 52812 on the runner), used in turn by the browser units of one group;
- the notes file `epic-0-readme-notes.md`.

The demo path creates no fixture. Its stack, and the README account's session row on it, are unique to the run and removed with it.

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate** (Rule 19: apply, observe red, revert; `git status --short` and `git diff --stat` unchanged after each):
- AC1, sign-in and the snapshot: `snapshotState.set('failed')` in place of `'loaded'` in `web/src/app/app.ts`, then `ci/iris.sh build` and `live demo-path` → red, with `STEP 1 page: failed`. Revert, and `build` again.
- AC1, a failure fails the build: the same mutation → `group browser` exits 1, with `GROUP browser failed: live:demo-path` (once).
- AC1, skipped steps:
  - `notBuilt` without its story text → `demo-path-summary.test.mjs` red, and `live demo-path` red with "names no story";
  - the summary counting a skipped step as passed → `demo-path-summary.test.mjs` red;
  - `test.skip()` added to the floor test → `live demo-path` red at the floor.
- AC1, every pull request and every push to `main`:
  - the push-to-`main` rule removed from `ci/changes.sh` → `test-ci-changes.sh` red at the `main` case;
  - `live:demo-path` moved from `browser` to `CHECK_SCRIPTS` → `test-ci-config.sh` `demo-path` red.
- AC1, the sign-in unit keeps its specs: `testIgnore` removed from `chromium` → `demo-path-summary.test.mjs` red at its `--list` check.
- AC2:
  - the threshold in `first_start_report` raised to 900 → `test-lib-live.sh` red at the 721 s case;
  - `engine=` dropped from the line → `test-lib-live.sh` red.

**Task 0 results** (implement stage, October 19 and 20; Playwright 1.64.1; measured unless marked `(inference)`):
- **Where a skip's text lands.** In both `tests[].annotations` and `tests[].results[].annotations`, as `{type: "skip", description: "Story 2.5 turns this on", location}`.
  - `test.skip()` with no text gives `description: null`; a declared `test.skip('t', fn)` gives `type: "skip"` and `description: null`; `test.fixme(true, 'because')` gives `type: "fixme"` and the text.
  - A test that never ran (the global timeout) has `status: "skipped"`, no annotation, and an empty or skipped `results`.
- **A tag.** `specs[].tags` holds `["floor"]`, without the `@`. The summary strips a leading `@` anyway.
- **File and nesting.** `suites[].file` is `demo-path/01-page.spec.ts`, relative to the config's `testDir`, with `/`. There is one top-level suite per spec file, and a `describe` block is a nested `suites[]` entry (same `file`) that holds the specs. `specs[].file` is the file of the test's declaration, so a `notBuilt` test has `demo-path/not-built.ts`: the summary maps by the top-level suite's file. A test's `status` is `expected`, `skipped` or `unexpected`; a result's is `passed`, `skipped`, `failed` or `timedOut` (`interrupted` is `(inference)`, handled as a failure).
- **`errors` and `stats`.**
  - A spec that failed to load: `errors: [{message: "SyntaxError: <path>/97-broken.spec.ts: Unexpected token (2:6) ...", location}]`, `suites: []`, every `stats` count 0, Playwright exit 1.
  - The global timeout (`OCUTALON_E2E_TIMEOUT_MS=500`): two `errors` ("Timed out waiting 0.5s for the test suite to run", and the same for the teardown), every test skipped with no annotation, `stats.skipped` 13, exit 1.
  - `stats` is `{startTime, duration, expected, skipped, unexpected, flaky}`.
- **The list reporter** prints one line for each skipped test, `-   2 [demo-path] > e2e/demo-path/not-built.ts:12:7 > the chat panel and the composer` (the location of `notBuilt`'s `test()` call, no skip text), then `12 skipped` and `1 passed`. With `OCUTALON_URL=http://127.0.0.1:9`, Chromium refuses the port (`net::ERR_UNSAFE_PORT`), so the floor test failed at `page.goto` and not on a refused connection; the outcome is the same (exit 1, 12 skipped).
- **The projects.**
  - `npm --prefix web run e2e -- --list` alone: `Error: OCUTALON_E2E_VERSION must be set by docker/tests/test-sign-in.sh`, `Total: 0 tests in 0 files`, exit 1 (see the Spec Change Log).
  - With the variables set: exit 0, `Total: 29 tests in 3 files` (api, shell, sign-in), none under `demo-path/`.
  - `npm --prefix web run e2e:demo-path -- --list`: exit 0, `Total: 13 tests in 2 files` (the floor test in `01-page.spec.ts` and the 12 declared in `not-built.ts`).
  - `testIgnore: '**/demo-path/**'` settles the glob.
- **The split start** (the first local `ci/iris.sh live demo-path`, and a scratch throwaway that ran only `dc build` and `dc up -d --no-build`).
  - After `dc build`, the image `<project>-iris` exists and `live_track_image` tracked it. `live_first_start` checks it on every run.
  - `dc up -d --no-build` printed only Network, Volume and Container lines, none with "build", and took 0 s.
  - `docker info --format '{{.Architecture}}'` printed `aarch64`.
  - The first run printed `FIRST-START engine=aarch64 build=1s ready=53s`, and the whole `live demo-path` call took 60 s. Three more runs the same hour: ready 47, 53 and 47 s, calls of 54 to 60 s. `build` is 0 to 1 s because every layer was cached.
  - No `LOCK` line was printed in any run: this checkout is the main checkout and has no `.worktrees/.coordination/locks/` folder.

**Mutations demonstrated** (implement stage; after each revert `git status --short`, `git diff --stat` and the checksum of every changed or new file equalled the values before):
- AC1, sign-in and the snapshot: mutation: `this.snapshotState.set('failed')` in place of `'loaded'` in `web/src/app/app.ts`, then `ci/iris.sh build` → `live demo-path` exit 1, red at the floor test (`Expected "loaded", Received "failed"`): `STEP 1 page: failed, 0 passed, 4 skipped, 1 failed`, `FAIL floor test "signs in with the README account and loads the page snapshot" (01-page.spec.ts) failed`, `FAIL the demo path: Playwright exit 1, the step summary exit 1`. Reverted, `build` again, and a green `live demo-path` after it.
- AC1, a failure fails the build: mutation: the same `app.ts` change, then `ci/iris.sh build` and `group browser` (review pass) → exit 1: `STEP 1 page: failed`, `UNIT live:demo-path failed 71s`, `UNIT live:sign-in failed 68s`, `UNIT live:bundle-folder passed 66s`, `GROUP browser failed: live:demo-path live:sign-in (205s)`. Reverted (the tree checksum equalled the one before), `build` again, and a green `group browser`: the three units `passed`, `GROUP browser passed (190s)`.
- AC1, skipped steps:
  - mutation: `notBuilt`'s skip text `turns this on` without `Story ${story} ` → `demo-path-summary.test.mjs` red (1 of 30 tests: "the real specs, run without their floor test"), and `live demo-path` exit 1 with 12 `FAIL <file> "<title>": its skip names no story` lines (Playwright itself exited 0);
  - mutation: `verdictOf` returning `passed` for a step with skipped tests and none passed → `demo-path-summary.test.mjs` red (8 of 30 tests, among them "reads steps 2 to 6 as skipped, and no step as passed");
  - mutation: `test.skip();` as the first line of the floor test → `live demo-path` exit 1: `STEP 1 page: skipped, 0 passed, 5 skipped`, `FAIL floor test ... was skipped` and the no-story line; Playwright exited 0.
- AC1, every pull request and every push to `main`:
  - mutation: the push-to-`main` rule removed from `ci/changes.sh` → `test-ci-changes.sh` red at "push to main: with a green base and only bookkeeping changed, no base and everything runs" and "push to main: the reason names main";
  - mutation: `live:demo-path` moved from `browser` to `CHECK_SCRIPTS` → `test-ci-config.sh` red at `demo-path` ("live:demo-path is in 0 groups", "the browser unit 'demo-path' is not a live unit of a group") and at `recipe` (`live demo-path` exits 2).
- AC1, the sign-in unit keeps its specs (the listing tests run `npm run e2e` and `npm run e2e:demo-path`, as the unit scripts do):
  - mutation: `testIgnore` removed from the `chromium` project → `playwright-projects.test.mjs` red at "chromium (the e2e script) lists exactly the spec files outside demo-path/" (code review folded the earlier listing test of `demo-path-summary.test.mjs` into that file and demonstrated the mutation again there);
  - mutation: `--project=chromium` dropped from the `e2e` script in `web/package.json` → the same test red (demonstrated again in code review).
- AC2:
  - mutation: the threshold in `first_start_report` raised from 720 to 900 → `test-lib-live.sh` red at "first start report: 721 s adds the WARN line..." (as "721 s gave ...") and "live_first_start: a start that is ready after 721 s still succeeds, with the WARN line";
  - mutation: `engine=` dropped from the `FIRST-START` line → `test-lib-live.sh` red at 5 checks, among them "first start report: one FIRST-START line with the engine, the build and the ready seconds, and no WARN".

**Mutations demonstrated in the review pass** (each applied, observed red, reverted; the checksum of the tree, tracked diff and untracked files, equalled the one before):
- AC1, every pull request and every push to `main` (Row 13, Chromium before each browser unit): mutation: `cmd_live` installing Chromium for `sign-in` only → `test-ci-config.sh` red at `recipe` ("ci/iris.sh live demo-path does not install Chromium before the unit's script").
- AC1, every unit has a home: mutation: the group-count test `-ne 1` weakened to `-gt 1` in the `demo-path` rule → `test-ci-config.sh` red at `demo-path` (the sample d-none no longer draws "live:demo-path is in 0 groups, wanted 1").
- AC1, the floor: mutation: `{ tag: '@floor' }` removed from the floor test → `playwright-projects.test.mjs` red at "reports the floor test of step 1 with the tag floor, the form that the summary reads" (the test moved there in code review, which demonstrated the mutation again), and, as observed in this pass, the real-specs test of `demo-path-summary.test.mjs`, which then runs the floor test without a stack.
- AC2: mutation: `${engine:-unknown}` replaced by `${engine}` in `live_first_start` → `test-lib-live.sh` red at "an unnamed engine was not printed as unknown"; mutation: the no-container check removed → red at "a start with no container was not reported".

**Implement-stage runs** (all from the repository root; tag `v08a`, owner `epic=0 stage=implement`):
- `(loop)` in order, each in its own call, exit 0: `npm --prefix web run lint`; `npm --prefix web test` (71 tests, 30 of them in the summary's file); `e2e -- --list` (exit 0 with the dummy variables, 29 tests, none under `demo-path/`); `e2e:demo-path -- --list` (13 tests); `bash docker/tests/test-lib-live.sh`; `bash docker/tests/test-ci-config.sh`; `bash docker/tests/test-ci-changes.sh`; `bash ci/checks.sh`; `ci/iris.sh build`; `ci/iris.sh live demo-path` (exit 0, `FIRST-START engine=aarch64 build=1s ready=53s`, `STEP 1 page: partly skipped, 1 passed, 4 skipped (...)`, steps 2 to 6 `skipped`, the `DEMO-PATH` line); `ci/iris.sh live sign-in` (exit 0, 29 passed); `ci/iris.sh teardown` (no container, volume, network or image of `-v08a-` left).
- Also: `docker/tests/test-boundaries.sh` and `docker/tests/test-web-build.sh` (exit 0), and `ci/checks.sh` again after the last edit (exit 0).
- Review pass, after the last patch: the `(loop)` lines again, each in its own call, exit 0 (`npm --prefix web test` 72 tests; `e2e:demo-path -- --list` 13 tests; `ci/checks.sh`; `live demo-path` with `FIRST-START engine=aarch64 build=0s ready=53s`; `live sign-in` 29 passed; `teardown` clean).
- Review pass, `(once)`, one per call, exit as expected: `group browser` with the `app.ts` mutation (exit 1, above) and without it (exit 0, `GROUP browser passed`); the reverse order, `live sign-in` then `live demo-path` (exit 0 each, `FIRST-START engine=aarch64 build=1s ready=46s`); `GITHUB_REF=refs/heads/main bash docker/tests/test-ci-changes.sh` (exit 0, 46 checks passed); `teardown` after each (nothing of `-v08a-` left).

**QA stage (October 20; `bmad-qa-generate-e2e-tests`).** Runtime targets: only throwaway projects through `ci/iris.sh` with tag `v08q` (`ocutalon-t08-v08q-*`), owner `epic=0 stage=qa`, one at a time, torn down by their own trap and then by `ci/iris.sh teardown` (nothing of `-v08q-` left); no slot, no MCP call, no push; GitHub read-only.

**The x64 run (settles the `(inference)` items).** `ci` run 39359136309 and `lane-a` run 39359136280, both `headSha` `fcdd9e9...`, both `success`. Evidence: job `iris (browser)` (job id 118420900237) of the `ci` run.
- **AC2, the first start on x64.** `FIRST-START engine=x86_64 build=0s ready=150s`, no `WARN first start` line (150 s is under 720 s, so nothing is raised to the author). `build` is 0 s because the runner's layer cache held every layer. The row is in `epic-0-readme-notes.md`; the README's figure is the lead's row for Epic 0's merge head. The unit's `WARN` path itself still has no real-run print (only a start over 720 s prints it), and stays pinned by `test-lib-live.sh` and `test-demo-path-gate.sh`.
- **Row 1 on x64.** `Running 13 tests using 1 worker`; the floor test passed in 544 ms; the list reporter named the 12 skipped tests (`-   2 [demo-path] > e2e/demo-path/not-built.ts:12:7 > ...`), then `12 skipped` and `1 passed`; `STEP 1 page: partly skipped, 1 passed, 4 skipped (Story 2.5: ...; Story 4.7: ...)`, `STEP 2` to `STEP 6` `skipped` with their stories, and `DEMO-PATH 1 of 6 steps ran (1 partly skipped), 12 skipped, 0 failed; floor 1 of 1 passed`. Row 13: `UNIT live:demo-path passed 161s`, `UNIT live:sign-in passed 173s` (29 passed, the `chromium` project), `UNIT live:bundle-folder passed 171s`, `GROUP browser passed (505s)`, in that order; the port was 52812 (`ocutalon-ci-2`).
- **REL-4.** Wall-clock 23 min 39 s from creation (02:28:53) to the last job (02:52:32), against 27 min 37 s (run 39338702672) and 24 min 12 s (run 39350452992) before this story, so the 30 minutes hold with 6 min 21 s to spare. Per job: `checks` 29 s, `web` 28 s, `iris (install)` 12 min 21 s, `iris (production)` 10 min 13 s, `iris (browser)` 8 min 43 s, `iris (image)` 6 min 2 s, `iris (shards)` 5 min 40 s (about 43 runner-minutes). Dispatch order: production, image, browser, install, shards. No group is over its share, so no rebalance of `ci/units.sh` was applied.
- **The time budget (Design Notes).** The unit's cost "about 150 to 190 s": measured 161 s. The `browser` group "from 360 s to about 540 s": measured 505 s (the job 8 min 43 s, against 6 min 28 s in run 39350452992). "About 43 runner-minutes instead of about 40": measured about 43. The wall-clock "about 27 minutes in run 2's dispatch order": measured 23 min 39 s, because this run's order put `browser` after `image` and ahead of `install` and `shards`. The worst case "about 28 minutes on run 2's job sizes": from this run's job sizes the bound is (all runner time less the largest job) / 2 plus the largest job, about 27 min 40 s, and the run was under it.
- **Other `(inference)` items.** Residual risk 1 of the Auto Run Result ("everything about the x64 runner"): settled by this run. The two new hermetic tests of the review pass (the stubbed `docker`/`npx` check of `test-ci-config.sh` and the `npm` spawn of `demo-path-summary.test.mjs`) ran green on the hosted `checks` and `web` jobs of this run.

**Tests added or changed by QA** (all in the default suites; Rule 8):
- (QA) `docker/tests/test-demo-path-gate.sh`, in `CHECK_SCRIPTS` of `ci/units.sh` as `demo-path-gate` (the hosted `checks` job, `ci/checks.sh`; needs Node, which the hosted Ubuntu image has). It runs the real `test-demo-path.sh`, `demo-path-summary.mjs` and `ci/iris.sh group` in a scratch tree with the stack stubbed, and pins what no hermetic test did: the unit's exit code and `PASS` line from Playwright's and the summary's exit codes together (a skipped floor test, a skip without a story, an unknown or missing spec file, a Playwright exit 1 beside a green report, and no report each fail the unit although Playwright exits 0 for the skips), the `FIRST-START` line before the `STEP` lines, the `WARN` line followed by the specs, a failed first start that runs no spec, the 60 s deadline guard, the Playwright call (URL, report path, time left less 20 s), and `ci/iris.sh group browser` (the order `live:demo-path`, `live:sign-in`, `live:bundle-folder`; `UNIT live:demo-path failed` and `GROUP browser failed: live:demo-path` with exit 1 for a failed or only-skipped floor test; exit 0 when all pass).
- (QA) `web/scripts/playwright-projects.test.mjs`, in `npm --prefix web test` (the hosted `web` job). With no `OCUTALON_` variable set, the `e2e` script lists exactly the spec files on disk outside `demo-path/` and `e2e:demo-path` lists exactly those inside it (the earlier test only checked that some sign-in and API spec was listed), and a test of `api.spec.ts` that needs a missing variable fails naming it.
- Changed: `web/e2e/api/api.spec.ts` (DW-25: the eight variables are read through a lazy `SEEDED` object when a test uses one, not at import; the asserted values and the texts of the errors are unchanged; the bare `npm --prefix web run e2e -- --list` now exits 0, `Total: 29 tests in 3 files`); `web/scripts/demo-path-summary.test.mjs` (`playwrightEnv()` no longer sets dummy variables); `ci/units.sh` (`demo-path-gate`).
- Shared surfaces added: `CHECK_SCRIPTS` (one more script, about 2 s), and the lazy reads of `api.spec.ts`, which `test-sign-in.sh` still feeds in full.
- DW-25 is closed by the `api.spec.ts` patch (the `deferred:` entry above is the lead's to remove). DW-26 stays: the local deadline still ends the wait before 720 s, but the `WARN` path is exercised through the real `first_start_report` by `test-demo-path-gate.sh` (a start ready after 800 s warns and the specs still run) and by `test-lib-live.sh`.

**Mutations demonstrated by QA** (each applied, observed red, reverted; the checksum of the tree, tracked diff and untracked files, equalled the one before each time):
- AC1, sign-in and the snapshot: mutation: the README account's password in `web/e2e/sign-in/helpers.ts` changed to a wrong one (row 3, never failed for real before) → `ci/iris.sh live demo-path` exit 1 on a real stack: `Expected: "OcuTalon", Received: "Sign in · OcuTalon"`, `STEP 1 page: failed, 0 passed, 4 skipped, 1 failed`, `FAIL floor test ... failed`, `FAIL the demo path: Playwright exit 1, the step summary exit 1`; a green run of the same unit just before it (`ready=47s`).
- AC1, a failure fails the build: mutation: `if [ "$rc" -eq 0 ]` replaced by `if true` in `cmd_group` of `ci/iris.sh` → `test-demo-path-gate.sh` red at 4 checks, among them "group: a failed demo path makes the browser group exit 1 and names the unit".
- AC1, skipped steps: mutation: the line that fails a skipped `@floor` test removed from `demo-path-summary.mjs` → `test-demo-path-gate.sh` red at 3 checks ("unit: a skipped floor test fails the unit although Playwright exits 0", "...draws no PASS...", "group: a skipped floor test makes the browser group exit 1...") and `demo-path-summary.test.mjs` red at 2 tests; mutation: `test-demo-path.sh` deciding on Playwright's exit code alone (`if [ "$e2e_status" -eq 0 ]`) → `test-demo-path-gate.sh` red at 6 checks.
- AC1, every pull request and every push to `main`: mutation: `refs/heads/main` replaced by `refs/heads/mainx` in `ci/changes.sh` → `test-ci-changes.sh` red at "push to main: with a green base and only bookkeeping changed, no base and everything runs" and "push to main: the reason names main".
- AC1, the sign-in unit keeps its specs: mutation: `'**/shell.spec.ts'` added to the `chromium` project's `testIgnore` → `playwright-projects.test.mjs` red at "chromium (the e2e script) lists exactly the spec files outside demo-path/", while the earlier "lists no demo-path test through the e2e script" test stays green (it only asks for some sign-in and API spec).
- AC2: mutation: the `WARN` echo removed from `first_start_report` in `lib-live.sh` → `test-lib-live.sh` red at 2 checks ("first start report: 721 s gave ...", "live_first_start: a slow start did not warn and succeed") and `test-demo-path-gate.sh` red at "unit: a slow first start did not warn and go on".
- DW-25 (extra): mutation: `const AT_LOAD = SEEDED.version;` added at module level of `api.spec.ts` → `playwright-projects.test.mjs` red at the `e2e` listing; mutation: `required()` returning `value ?? ''` instead of throwing → red at "fails a test that needs a missing variable, and names the variable".

**QA runs** (one per call, exit 0 unless noted): `npm --prefix web run lint`; `npm --prefix web test` (the new file adds 4 tests); `bash ci/checks.sh` (12 scripts, the new one in 2 s); `ci/iris.sh build`; `ci/iris.sh live demo-path` (green, `FIRST-START engine=aarch64 build=0s ready=47s`) and with the password mutation (exit 1, above); `ci/iris.sh teardown` (nothing of `-v08q-` left).

**Code review (October 20; `bmad-code-review`).** Runtime targets: only throwaway projects through `ci/iris.sh` with tag `v08r` (`ocutalon-t03-v08r-*`, `ocutalon-t08-v08r-*`), owner `epic=0 stage=code-review`, one at a time, each removed by its own trap, then `ci/iris.sh teardown` (nothing of `-v08r-` left); no slot, no MCP call, no push; GitHub read-only (`gh run view` of run 39359136309).
- **Changed by the review** (the Review Findings above):
  - `web/scripts/playwright-projects.test.mjs` is the one home of the config's listing (Rule 2): one `listedReport` per npm script, made once per run; the two demo-path listing checks moved in from `demo-path-summary.test.mjs` (every step spec listed and no file that maps to no step; the floor test's tag form), and the weaker chromium listing test dropped. The row-18 run selects only the trace-only test, asserts `1 failed`, and writes to its own `--output` folder.
  - `web/scripts/demo-path-summary.test.mjs` keeps the synthetic reports and the real run of the skipped specs, which now writes to its own `--output` folder (Rule 19: the two real runs no longer share and clear `web/test-results`) and asserts that the list reporter printed the skipped tests beside the JSON report.
  - `docker/tests/test-demo-path-gate.sh`: `unset LIVE_REBUILD_WEB`; `npx`, `npm` and the stub units append to one sequence, and the green group run asserts `npx install chromium`, `npm e2e:demo-path`, `npx install chromium`, `ran sign-in`, `ran bundle-folder`, in that order; every unit and group run fails on an unexpected `docker` or `npm` call; the green unit run asserts the indented Playwright log and that the first start waits 900 s.
  - Comments and docs: `api.spec.ts` (read on every use), `test-demo-path.sh`'s header and the notes file (up to 900 s for the log and up to 60 s more for health), `ci/iris.sh`'s header (no copy of `BROWSER_UNITS`), Rule 21's "Hosted checks" (Node).
- **Mutations demonstrated in code review** (each applied, observed red, reverted; the checksum of the tracked diff, the status and every untracked file equalled the one before):
  - AC1, skipped steps (the Playwright log names each skipped test): mutation: `sed 's/^/  /' "$e2e_log"` deleted from `test-demo-path.sh` → `test-demo-path-gate.sh` red at "unit: a floor test that passed and unbuilt parts that skipped give exit 0 and the PASS line" (missing `  Running tests using 1 worker`); mutation: the config's reporter `json` alone when `OCUTALON_E2E_JSON` is set → `demo-path-summary.test.mjs` red at "skip every unbuilt part with a story, so that each step reads skipped".
  - AC1, every pull request and every push to `main` (row 13, Chromium before each browser unit): mutation: `cmd_live` running the unit's script first, keeping its exit code, then installing → `test-demo-path-gate.sh` red at one check only, "group: Chromium is installed before the script of each browser unit, demo-path and sign-in, and before no other" (the calls ran as `npm ...|npx ...|ran sign-in|npx ...|ran bundle-folder|`).
  - AC1, the sign-in unit keeps its specs: mutation: `testIgnore` removed from `chromium` → `playwright-projects.test.mjs` red at "chromium (the e2e script) lists exactly the spec files outside demo-path/"; mutation: `--project=chromium` dropped from the `e2e` script → the same test red.
  - AC1, the floor: mutation: `{ tag: '@floor' }` removed → `playwright-projects.test.mjs` red at "reports the floor test of step 1 with the tag floor, the form that the summary reads".
  - AC2: mutation: `live_first_start 900` → `600` in `test-demo-path.sh` → `test-demo-path-gate.sh` red at "unit: the first start waits '600' s, not 900".
  - DW-25 (the row-18 run): mutation: `-g 'row 18: a trace-only user'` widened back to `-g 'row 18'` → `playwright-projects.test.mjs` red at "fails a test that needs a missing variable, and names the variable".
  - The gate's environment: mutation: `unset LIVE_REBUILD_WEB` removed, the gate run with `LIVE_REBUILD_WEB=1` exported → red (`group (green, npm exit 0): a stub was called in a way the test did not expect (--prefix web run build;)` and the group checks); with the line and the same export → exit 0.
- **Runs** (one per call, exit 0): `npm --prefix web run lint`; `npm --prefix web test` (75 tests, 75 passed; the modification time of `web/test-results` unchanged); `bash ci/checks.sh` (12 scripts passed); `ci/iris.sh build`; `ci/iris.sh live sign-in` (29 passed: QA's lazy reads of `api.spec.ts` on a real stack, which no run had shown before); `ci/iris.sh live demo-path` (`FIRST-START engine=aarch64 build=0s ready=47s`, `STEP 1 page: partly skipped, 1 passed, 4 skipped (...)`, steps 2 to 6 `skipped`, `DEMO-PATH 1 of 6 steps ran (1 partly skipped), 12 skipped, 0 failed; floor 1 of 1 passed`); `ci/iris.sh teardown` (0 projects left). No `LOCK` line: the main checkout has no lock folder.
- **The list reporter's separator** is U+203A, not the `>` that the Task 0 and x64 lines above transcribe; the new assertion matches it as `›` (Rule 14).

## Auto Run Result

Status: done
Blocking condition: none

**Implement and review (October 19 and 20).**
- **Summary.**
  - The six step specs, `notBuilt`, the `demo-path` Playwright project, the step summary with its tests, `live:demo-path`, the split first start with its `FIRST-START` line, the `browser` group's new order, the `BROWSER_UNITS` Chromium install, the push-to-`main` rule, the `demo-path` rule of `test-ci-config.sh`, Rule 21's recipe bullet and the notes file are implemented as specified.
  - Task 0 was measured first (Verification); the report shape, `errors` on a load failure and on the global timeout, and the `--list` of both projects shaped the summary and its tests. No intent gap, no AD conflict, no NFR tripwire.
  - Five Rule 22 rulings are in the Spec Change Log, two low items in `deferred:`.
- **Files changed.**
  - Web: `web/playwright.config.ts` (two projects; `testIgnore` anchored at `e2e/demo-path`), `web/package.json` (`e2e` selects `chromium`; `e2e:demo-path`), `web/e2e/demo-path/` (`not-built.ts` and the `01-page` to `06-trace` specs), `web/scripts/demo-path-summary.mjs` and `web/scripts/demo-path-summary.test.mjs`.
  - Shell and recipe: `docker/tests/test-demo-path.sh` (new), `docker/tests/lib-live.sh` (`first_start_report`, `live_first_start`), `docker/tests/test-lib-live.sh`, `docker/tests/test-sign-in.sh` (header and PASS text), `docker/tests/test-ci-config.sh`, `docker/tests/test-ci-changes.sh`, `ci/units.sh`, `ci/iris.sh`, `ci/changes.sh`.
  - Pipeline: `_bmad/custom/skill-rules.md` (Rule 21's CI recipe bullet only), `_bmad-output/implementation-artifacts/epic-0-readme-notes.md` (new).
- **Review findings (37 from four layers; the triage log has every row).**
  - Patched, high 0 and medium 3 entries (6 findings; the entries are the Chromium install, the `e2e` script's project, and the unobserved red of "a failure fails the build"):
    - `test-ci-config.sh` runs `live <unit>` for each browser unit with a stub `docker` and a recording `npx`;
    - the listing tests in `demo-path-summary.test.mjs` go through `npm run e2e` and `npm run e2e:demo-path`, and check the floor test's tag in the real listing;
    - the `(once)` run of `group browser` with the `app.ts` mutation was made and recorded.
  - Patched, low: each bad sample of the `demo-path` rule must draw its own violation; two branches of `live_first_start` are probed; its header, its two messages and the notes file's two claims state what they do; `testIgnore` is anchored at `e2e/demo-path`; Rule 21's timing sums include `demo-path`.
  - Deferred: none new; the two items from the implement pass stay in `deferred:`.
  - Rejected, all low, each with its reason in the triage log: the literal spelling of the Playwright rule (the spec defines it), the `06-trace` placeholder text (the spec's own), mutations per clause (Rule 19 asks one per AC), a `LIVE_REBUILD_WEB` (a recorded ruling), the bash 3.2 `SECONDS` tick (0 of 3,000 probes; exact on bash 5), and five others.
- **Follow-up review recommendation: true.** Three medium entries were patched. The unverified risk: the two new hermetic tests (the stubbed `docker`/`npx` Chromium check in `test-ci-config.sh`, and the `npm` spawn in `demo-path-summary.test.mjs`) were written in this pass and ran green and red here (macOS, bash 3.2, Node 24) but not yet on the hosted Ubuntu `checks` and `web` jobs.
- **Verification performed.** Every `(loop)` line ran in its own call after the last patch and exited 0; the `(once)` lines ran once after it (Verification, "Implement-stage runs"); every mutation above went red as predicted and was reverted with the tree checksum unchanged. One slip: the reverse-order `live demo-path` and a `teardown` were sent in one message; the teardown reported 0 projects removed, the unit exited 0, and nothing of the tag was left.
- **Residual risks.**
  - Everything about the x64 runner stays `(inference)` until a real run prints it: the `FIRST-START engine=x86_64` figure, the `iris (browser)` job's duration, and REL-4's 30 minutes (Design Notes, time budget).
  - The 720 s `WARN` can print only where the deadline allows it (CI, 1200 s); locally the 540 s deadline ends the wait first (`deferred:`).
  - The skipped tests' list lines name `not-built.ts`, not their spec file; the `STEP` lines carry the story and the title.
  - Nothing was pushed.

**Planning summary (October 19).**
- **Sources.** The plan was made from:
  - the committed `epic-0-context.md`, and Story 0.7's spec (continuity);
  - the spine, by line range: AD-13, AD-22, AD-23 and AD-29;
  - the PRD's UJ-1, REL-2 and REL-4;
  - `epics.md`: 0.8, and the stories that turn steps on;
  - the code named in the Code Map.
- **Read-only measurements.** The two real CI runs' job and unit timings (`gh run view`); the local Docker engine's architecture.
- **Checks.** No intent gap, no AC that contradicts an AD, and no NFR tripwire. REL-4's margin is `(inference)`, settled by QA's run.
