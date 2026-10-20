---
title: 'Story 0.8: The demo-path test signs in and loads the page'
type: 'feature'
created: '2026-10-19'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
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

## Spec Change Log

## Review Triage Log

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
- `(loop)` `npm --prefix web run e2e -- --list`. Expected: no line names `demo-path/`.
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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Planning summary (October 19).**
- **Sources.** The plan was made from:
  - the committed `epic-0-context.md`, and Story 0.7's spec (continuity);
  - the spine, by line range: AD-13, AD-22, AD-23 and AD-29;
  - the PRD's UJ-1, REL-2 and REL-4;
  - `epics.md`: 0.8, and the stories that turn steps on;
  - the code named in the Code Map.
- **Read-only measurements.** The two real CI runs' job and unit timings (`gh run view`); the local Docker engine's architecture.
- **Checks.** No intent gap, no AC that contradicts an AD, and no NFR tripwire. REL-4's margin is `(inference)`, settled by QA's run.
