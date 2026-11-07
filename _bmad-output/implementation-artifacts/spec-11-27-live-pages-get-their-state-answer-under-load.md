---
title: 'Story 11.27: Live pages get their /state answer under load (test-only diagnostics)'
type: 'chore'
created: '2026-11-07'
status: 'done'
baseline_revision: '5352d39d991a20c58f17068f46815f57ed5fe562'
baseline_commit: '5352d39d991a20c58f17068f46815f57ed5fe562'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Live browser tests on a loaded CI host fail with no answer to `GET /state` (DW-550: cards I10 and others, in `loadedAfter`) or to `page.close` (DW-774: online-session L5/L6; sign-in-2 W3). The lead's Step 1 ruled out the per-session gateway cap. CI has no trace of a failing test. 11.22's `DIAG /state` dump never reaches CI output, because the live scripts print only the tail of the e2e log (DW-756). The dump also cannot show whether the request waited in the web gateway.

**Approach:** Test and CI scripts only (the amended ACs, option (b)). (1) On a self-hosted CI runner, live units keep Playwright traces of failing tests only. `ci/iris.sh` moves those traces out of `web/test-results/` to a folder on the runner's own disk and deletes run folders older than 7 days. A pin keeps every artifact upload off traces. (2) `loadedAfter`'s diagnosis adds `DIAG /state gateway ...` lines (counts and states only). It also writes every DIAG line to the test's own output folder, which the failure artifact uploads. (3) The lead measures what traces add to the browser group's time.

## Boundaries & Constraints

**Always:**
- Owner rulings (the Contest Planner, 2026-11-07 about 10:55Z) bind.
  - (1) A trace never leaves the CI host.
    - Traces are on only for live units, only when `GITHUB_ACTIONS=true` and `RUNNER_ENVIRONMENT=self-hosted` (both checked in `ci/iris.sh` and again in `web/playwright.config.ts`).
    - Each trace is moved to the trace root outside `GITHUB_WORKSPACE` and outside the checkout, before the `Run the group` step ends, so before any upload step.
    - Run folders older than 7 days are deleted by the job.
    - A pin refuses any upload-artifact path that names the trace folder or a trace file.
  - (2) The gateway dump prints counts and states only. It never prints a request body, cookie, session id, token, PID, IP address, port or server name.
  - (3) The browser group's added time is measured, lead-side. More than 2 minutes goes to the Planner before the merge.
  - (4) Workflow edits are allowed but kept minimal: this plan makes none (D4).
- The trace mode is `{ mode: 'retain-on-failure', screenshots: false }`. Every other run keeps `trace: 'off'`.
- The trace root is `${OCUTALON_TRACE_DIR:-$HOME/ocutalon-traces}`.
  - It is created with umask 077.
  - It is refused (traces off) when it is not absolute, or when it lies inside `GITHUB_WORKSPACE` or the checkout (both resolved with `pwd -P`).
  - A kept trace sits at `<root>/<OCUTALON_RUN_TAG>/<path below web/test-results>`, which begins with `<unit>/`.
  - Log lines name only `<tag>/<unit>`, never the host path.
- In CI (`GITHUB_ACTIONS=true`), after every live unit, `web/test-results/` holds no `trace*.zip` and no `.playwright-artifacts-*` folder. A trace that is found when traces are off, or that cannot be moved, is deleted. `cmd_live` exits with the unit script's own status.
- The diagnosis keeps 11.22's contract: best effort, never throws, never takes longer than `DIAG_BOUND_MS` (15 s, unchanged), and is not part of any error text.
  - The gateway read is a second `irisScript`, run concurrently with 11.22's read, each under its own `boundedStep(..., DIAG_BOUND_MS, ...)` inside `asCleanup`.
  - The printed order is: 11.22's lines, then the gateway lines.
  - A failed gateway read prints one `DIAG /state gateway unavailable: <reason>` line and costs none of 11.22's lines.
- The DIAG file is `state-diagnosis.txt` under `test.info().outputPath()`. It is appended with exactly the DIAG lines printed, and is registered as a `state-diagnosis` path attachment (`text/plain`). Outside a test, no file is written.
- Every test added or changed passes on a fresh environment, in either order.

**Never:**
- No product code: nothing under `src/**` changes.
- No change to:
  - `.github/workflows/ci.yml` or `lane-a.yml`
  - `docker/tests/lib-live.sh` or `ci/units.sh` (Epic 19 edits both)
  - any `docker/tests/test-<unit>.sh`
- No pin is deleted or weakened.
- No timeout, deadline, bound or wait is raised: `DIAG_BOUND_MS`, the project waits, the test timeouts and `OCUTALON_LIVE_DEADLINE` stay as they are.
- The failing specs (I10, L5, L6 and W3) stay unchanged.
- No trace on a developer machine or a hosted runner. No cleanup of `web/test-results/` outside CI.
- No absolute path, lock folder, scratchpad or worktree path in any committed file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Self-hosted CI, failing test | `GITHUB_ACTIONS=true`, `RUNNER_ENVIRONMENT=self-hosted`, root outside the workspace; the unit leaves `web/test-results/<unit>/<test>/trace.zip` and `.playwright-artifacts-0/traces/x.trace` | `OCUTALON_E2E_TRACE=retain-on-failure` reaches the unit. Afterwards the trace is at `<root>/<tag>/<unit>/<test>/trace.zip` (root mode 700), and no trace or artifacts folder remains under `web/test-results`. Other files (`state-diagnosis.txt`, `error-context.md`) stay. `TRACE kept 1 of <unit> under <tag>/<unit>`. The unit's exit code is kept. | A failed move deletes the trace and prints `TRACE removed ...` |
| Hosted or other runner | `RUNNER_ENVIRONMENT=github-hosted` (or unset) with `GITHUB_ACTIONS=true` | `OCUTALON_E2E_TRACE` is not set. The config gives `trace: 'off'`. A stray trace is deleted, and nothing is written under the trace root. The `TRACE off: <reason>` line is printed. | none |
| Root inside the workspace | `OCUTALON_TRACE_DIR` under `GITHUB_WORKSPACE` or the checkout | Same as hosted: traces off, any trace deleted | none |
| Developer machine | `GITHUB_ACTIONS` unset | No trace switch. `web/test-results` is untouched by the sweep. | none |
| Prune | Run folders in the root aged 8 days and 6 days; one entry that is not a valid run tag (e.g. `Keep Me`) | At `cmd_group` start with traces on, the 8-day folder is removed. The 6-day folder and the non-tag entry are kept. | Removal errors ignored (another job may prune at once) |
| Gateway read | stand-in prints `CHK\|gw\|1`, `CHK\|gwserver\|1\|1\|6\|1\|0\|0`, `CHK\|gwconn\|1\|Free\|4`, `CHK\|gwconn\|1\|InUse\|1`, `CHK\|done\|1` | `DIAG /state gateway 1 server 1: TotalConnections=6, ConnectionsInUse=1, PrivateConnections=0, QueuedRequests=0` and `DIAG /state gateway 1 connections: Free=4, InUse=1` (states in name order) | none |
| No gateway | `CHK\|gw\|0`, `CHK\|done\|1` | `DIAG /state gateway: none registered` | none |
| Refused or odd reading | `CHK\|error\|gateway\|<PROTECT> ...`; a count that is not digits; a state outside `[A-Za-z][A-Za-z0-9 ()-]{0,29}`; no CHK line | `DIAG /state gateway unavailable: <PROTECT> ...`, or `... unavailable: an unexpected reading` (the odd value is never printed), or `... unavailable: the session printed no reading` | never throws |
| DIAG file | any diagnosis inside a test | `state-diagnosis.txt` holds exactly the logged DIAG lines, unavailable ones included, and the `state-diagnosis` attachment names it | write failure swallowed |

</intent-contract>

## Code Map

**Diagnosis, web side:**
- `web/e2e/support/diagnose.ts` (94 lines), 11.22's dump. Extend in place (Rule 2).
  - `DIAG_BOUND_MS` (20) and `MAX_LINES` (22).
  - `diagnosisScript()` (44-55) is the sibling of the new `gatewayScript()`; follow its `CHK|...` convention and its `CHK|error|<kind>|` text sanitising (`$Translate(...,$Char(10,13,124),"  /")`).
  - `describeDiagnosis()` (63-81) is the sibling of the new `describeGateway()`.
  - `stateDiagnosis()` (84-94) gains the concurrent gateway read and the file.
  - The header (4-16) lists the line kinds: add the gateway lines and the file.
- `web/e2e/support/floor.ts`. `loadedAfter` 147-162 calls `stateDiagnosis()` at 157. Only its doc comment (137-146), which names the DIAG contents, changes.
- `web/e2e/support/iris.ts`:
  - `irisScript(script, ms)` at 105: keeps the `CHK|` lines, up to 3 tries.
  - `currentBound()` at 85-91 is the `test.info()`-outside-a-test pattern to reuse for the file.
  - `web/e2e/support/rehearsal.ts:68-72` `irisSessionCommand`: `OCUTALON_E2E_IRIS_EXEC` is the hermetic stand-in (`sh -c`, the script on stdin), else `docker exec -i <c> iris session IRIS -U OCUTALON`.
- IRIS API (read-only reference):
  - `$SYSTEM.CSP.GetGatewayRegistry()` (`irislib/%SYSTEM/CSP.cls:278`) `.GetGatewayMgrs("a")` (`%CSP/Mgr/GatewayRegistry.cls:26`, needs %Admin_Manage:Use), a `%ListOfObjects`.
  - Each manager's `GetSystemStatus(.st, "object")` (`%CSP/Mgr/GatewayMgr.cls:592`) gives a `%CSP.Mgr.GatewaySystemStatus`:
    - `CacheServers` is an array of `%CSP.Mgr.Helper.CacheServer` with `TotalConnections`, `ConnectionsInUse`, `PrivateConnections` and `QueuedRequests` (Integer).
    - `Connections` is an array of `%CSP.Mgr.Helper.Connection` with `Status` (Free/InUse/WebSocket/Server...).
  - Read only those five properties. The lead read the same data as XML (`"stream"`) via `iris session IRIS -U %SYS`. If the object form fails on the real stack (the live spec), parse the stream with `%XML.TextReader` into the same CHK lines.

**Hermetic and live specs:**
- `web/e2e/live/helper-waits.spec.ts`: the diagnosis describe (202-295) and its console capture (213-222).
  - The stand-ins ignore stdin today. The two reads would both get the same output, so the stand-ins that feed gateway lines branch on the script text: `s=$(cat); case $s in *GetGatewayRegistry*) printf ...;; *) printf ...;; esac`.
  - The file-level stand-in (297-311) prints only `CHK|done|1`.
- `web/e2e/live/socket.spec.ts:31-34` `open()` is `loadedAfter(page, () => signIn(page, fixtureUser('LIVE')...))`, so W3 goes through `loadedAfter`.
- `web/e2e/support/api.ts:114-129` `holdState(page)` holds `/state` at the browser route. `live.spec.ts:211` uses it, and the fixtures unroute at teardown (`support/fixtures.ts:57-128`, 11.21).
- The new live spec runs in project sign-in-2 (`SIGN_IN_2_DIRS` holds `live`), in the unit `live:sign-in-2` of group `shards-4`.

**Traces and CI:**
- `web/playwright.config.ts:61` `trace: 'off'`. Line 58 `outputDir` comes from `OCUTALON_E2E_OUTPUT`. The rehearsal and capture configs spread this base.
- `web/scripts/ci-results.test.mjs` (hosted `web` job, `npm --prefix web test`):
  - `loadConfig` (19-28) loads the config in a child node with an env. It must also delete `OCUTALON_E2E_TRACE` and `RUNNER_ENVIRONMENT`, which a hosted job sets to `github-hosted`.
  - 11.22's pin "keeps traces off, with and without CI" (38-49) is extended here.
  - The source pin of `cmd_live`'s exact line `OCUTALON_E2E_OUTPUT="test-results/$name" bash "docker/tests/test-$name.sh"` (51-57) must still hold.
  - The upload pin `path: web/test-results/` (70-80) and "the only upload-artifact" (82-84) are why ci.yml stays unchanged.
- Playwright 1.64.1 (`web/node_modules/playwright`):
  - `retain-on-failure` records every test and keeps `testInfo.outputPath('trace.zip')` for a failed one (`lib/worker/workerProcessEntry.js:682`).
  - Its live files live in `<outputDir>/.playwright-artifacts-<n>/traces/`, removed when the worker stops (`lib/runner/index.js:5653-5666`).
  - The trace options default to `screenshots: true` (`workerProcessEntry.js:561`).
  - The list reporter prints a failed test's path attachments in the failure summary (`lib/runner/index.js:1362-1381`), at the end of the e2e log, inside the printed tail.
- `ci/iris.sh` (595 lines; bash 3.2; when sourced, it defines functions and runs nothing):
  - header and usage (1-43).
  - `setup_tag` (55-83): the `RUNNER_NAME` env-decision sibling.
  - `cmd_live` (438-461): line 460 runs the unit, and `cmd_live` ends there today.
  - `cmd_group` (470-499).
  - `warm_state_dir` and `cmd_teardown` (516-575): the folder-cleanup siblings.
  - `live_tag_ok` / `LIVE_TAG_RULE` (`docker/tests/lib-live.sh:55-56`, sourced) is to be reused for the prune's name check.
- `.github/workflows/ci.yml:133-140` `Keep the Playwright results`: `if: failure() && ...`, `path: web/test-results/`, retention 3. upload-artifact v7.0.2 leaves hidden folders out unless `include-hidden-files: true`. The `iris` job is `runs-on: [self-hosted, ocutalon]` and runs every live unit. `lane-a.yml` has no upload and runs no Playwright.
- `docker/tests/test-ci-config.sh` (2015 lines, in `CHECK_SCRIPTS`, hosted `checks` job, where `GITHUB_ACTIONS=true` and `RUNNER_ENVIRONMENT=github-hosted`):
  - header rule list (2-69).
  - `facts.awk`'s `step:with` facts (237-241); `upl[]` is every upload-artifact step of any job (234).
  - the self-hosted-only upload check in rules.awk (260-272).
  - `upload_sample` (415-442).
  - `rule()` runs the samples and then every real workflow file (468-497).
  - the `image-actions` rule (509-520).
  - the sourced-`ci/iris.sh`-with-stubs precedent, `preflight_run` (1552+).

**Contention (checked at plan time).** None of the planned files changed on `origin/OCT-epic19`, `OCT-epic4` or `OCT-epic39` since `origin/feature/OCT_OcuTalon_MVP`. Epic 19 touches `ci/units.sh` and `docker/tests/lib-live.sh`, which this story leaves alone. None of them changed on the feature since this branch's merge base.

## Tasks & Acceptance

**Execution:**
- [ ] `web/e2e/support/diagnose.ts`:
  - Add `gatewayScript()`: read-only, wrapped in Try/Catch.
    - It prints `CHK|gw|<n>`, the number of active gateway managers (at most 5 read).
    - Per manager g, then per server s (at most `MAX_LINES`): `CHK|gwserver|g|s|<Total>|<InUse>|<Private>|<Queued>`, each as `+value`.
    - Per manager: `CHK|gwconn|g|<state>|<count>`, the connections counted by `Status` with its characters outside `[A-Za-z0-9 ()-]` stripped and cut to 30.
    - A failed status read or an error prints `CHK|error|gateway|<text>` (sanitised, at most 200 characters).
    - It ends with `CHK|done|1`.
  - Add `describeGateway(lines)` for the matrix's rows. Any value that fails its pattern turns the whole reading into one `... unavailable: an unexpected reading` line.
  - `stateDiagnosis()` runs both reads concurrently. It prints 11.22's lines, then the gateway lines. It appends them to `state-diagnosis.txt` and pushes the attachment.
  - Update the header to the new contract. AC3. DW-550, DW-756.
- [ ] `web/e2e/support/floor.ts`. Only `loadedAfter`'s doc comment changes: the gateway lines and the file. AC3.
- [ ] `web/e2e/live/helper-waits.spec.ts`. Extend the diagnosis describe.
  - The first case's stand-in also answers the gateway script. It expects 11.22's three lines, then the gateway server and connections lines. It asserts that `state-diagnosis.txt` in `test.info().outputPath()` holds exactly the logged lines, and that `test.info().attachments` has `state-diagnosis`.
  - "No lock" adds `DIAG /state gateway: none registered`.
  - "Cannot run" expects two lines: `DIAG /state unavailable: OCUTALON_URL must be set...` and `DIAG /state gateway unavailable: OCUTALON_URL must be set...`.
  - New case: a gateway read that hangs past its bound (stand-in `sleep`) still yields 11.22's lines and one gateway-unavailable line, within the test's 12 s.
  - New pure cases of `describeGateway`: refused, odd count, odd state (a cookie-like `CSPSESSIONID=abc`), no reading.
  - New case: `gatewayScript()`'s text names no `WebServerPID`, `CacheServerPID`, `IPAddress`, `TCPPort`, `CacheServerName`, `IdleTime` or `Activity`.
  - Keep every existing assertion. AC3.
- [ ] `web/e2e/live/state-diagnosis.spec.ts` (new; live, sign-in-2). One test, capturing `console.log` as helper-waits does:
  - In the test body, set only `test.info().project.use.actionTimeout = 3_000`, restoring the old value in `finally`. `loadedAfter` reads it at entry for the snapshot bound. The sign-in keeps the shared default bound, and the page's own action timeouts are already set, so a loaded host does not make the sign-in a new flake.
  - `holdState(page)`, then `loadedAfter(page, () => signIn(page, LIVE user))` rejects with `loadedAfter the snapshot GET ...: no answer within 3 s`.
  - The log holds a `DIAG /state licence:` line, at least one `DIAG /state gateway \d+ server \d+: TotalConnections=\d+, ConnectionsInUse=\d+, PrivateConnections=\d+, QueuedRequests=\d+` line and a `DIAG /state gateway \d+ connections: ` line, and no `unavailable` line.
  - `state-diagnosis.txt` equals the logged DIAG lines.
  - No line contains `CSPSESSIONID` or the value of any cookie of the page's context.
  - Release the hold in `finally`. AC5.
- [ ] `web/playwright.config.ts`:
  - Set `trace` to `{ mode: 'retain-on-failure', screenshots: false }` when `OCUTALON_E2E_TRACE === 'retain-on-failure'` and `RUNNER_ENVIRONMENT === 'self-hosted'`, else `'off'`.
  - Add one header line on the switch. AC1.
- [ ] `web/scripts/ci-results.test.mjs`:
  - `loadConfig` also deletes `OCUTALON_E2E_TRACE` and `RUNNER_ENVIRONMENT`.
  - The trace test asserts `'off'` (top level and every project) for `{}`, `CI`, `CI`+output, the switch alone, `RUNNER_ENVIRONMENT=self-hosted` alone, the switch with `github-hosted`, and the switch with another value (`on`). It asserts the exact ruled object for the ruled pair.
  - The header states the new contract. AC1.
- [ ] `ci/iris.sh`:
  - Add `TRACE_FOLDER_NAME=ocutalon-traces` and `TRACE_KEEP_DAYS=7`.
  - Add `trace_root`.
  - Add `traces_on`: prints a reason and returns 1 unless CI, self-hosted, and the root valid and outside (see Always).
  - Add `trace_mode`: prints `retain-on-failure` or nothing.
  - Add `traces_keep <results dir> <unit>`, CI-only: move or delete as in the Matrix, and print one `TRACE ...` line.
  - Add `traces_prune`, used only when traces are on: the direct children of the root that pass `live_tag_ok` and have `-mmin +$((TRACE_KEEP_DAYS*24*60))` are removed with `rm -rf`, and errors are ignored.
  - `cmd_live`: print `TRACE on` / `TRACE off: <reason>`. Run the unit with `OCUTALON_E2E_TRACE` set only when on, keeping the pinned `OCUTALON_E2E_OUTPUT="test-results/$name" bash "docker/tests/test-$name.sh"` text. Then `rc=$?`, then `traces_keep "$root/web/test-results" "$name"`, then `exit "$rc"`.
  - `cmd_group`: call `traces_prune` after `setup_tag`.
  - Update the header (the trace lines). AC1, AC2.
- [ ] `docker/tests/test-ci-config.sh`:
  - (a) A rule `traces` in rules.awk, for every upload-artifact step of any job in every workflow file:
    - A missing path, a block-scalar path (`|`/`>`), or a path whose lower case holds the trace folder name (passed in with `-v`, read from a sourced `ci/iris.sh`; FAIL when it cannot be read), `trace`, `~`, `home` or `..` is flagged.
    - So is `include-hidden-files: true`. Capture it in the `step:with` facts.
    - Bad samples, via `upload_sample` and a hosted-job variant: `~/ocutalon-traces/`, `${{ env.HOME }}/ocutalon-traces`, `web/test-results/**/trace.zip`, a hosted job uploading the runner's home-folder trace folder, `path: |`, and hidden files true.
    - The good sample stays clean, and so do the real files.
  - (b) A block `traces kept`, with one PASS/FAIL line, in subshells that set every variable explicitly (`GITHUB_ACTIONS`, `RUNNER_ENVIRONMENT`, `GITHUB_WORKSPACE`, `OCUTALON_TRACE_DIR`, `OCUTALON_RUN_TAG`, `HOME` under `$tmp`):
    - Each Matrix trace row through the real `cmd_live`, sourced with `root` set to a fake checkout under `$tmp` and `live_known`, `preflight`, `warm_check` and `setup_tag` stubbed. The fake `docker/tests/test-fake.sh` records `OCUTALON_E2E_TRACE`, writes `web/$OCUTALON_E2E_OUTPUT/t1/trace.zip`, `.../t2/state-diagnosis.txt` and `.../.playwright-artifacts-0/traces/x.trace`, then exits 1.
    - Assert exit 1, the recorded switch, the kept or removed files and the root's mode 700.
    - Then the prune row, calling `traces_prune` directly, with ages set by `touch -t "$(date -u -d "@$t" +%Y%m%d%H%M 2>/dev/null || date -u -r "$t" +%Y%m%d%H%M)"`. Also assert that `cmd_group`'s body calls `traces_prune` after `setup_tag`, a source check like `ci-results.test.mjs`'s check of `cmd_live`.
  - (c) Header lines for both. AC1, AC2.
- [ ] This spec: record Verification results and one `mutation:` line per AC.

**Acceptance Criteria:**
- AC1 (traces kept on failure, off the workspace). Given `ci/iris.sh live <unit>` in CI, when the unit's Playwright run fails a test, then:
  - On a self-hosted runner with a valid trace root, Playwright ran with `{ mode: 'retain-on-failure', screenshots: false }`. Each trace now sits under `<root>/<tag>/<unit>/`, `web/test-results/` holds no trace, and the unit's exit code is unchanged.
  - With `RUNNER_ENVIRONMENT` anything but `self-hosted`, or with the root inside the workspace or the checkout, the unit runs with `trace: 'off'`, any trace is deleted, and nothing is written to the root.
  - Pinned by `traces kept` and `ci-results.test.mjs`.
- AC2 (retention and the upload pin). Given the trace root, when an `iris` job runs its group with traces on, then every run folder older than 7 days is removed and younger ones are kept. Given any `.github/workflows/*.yml`, when `test-ci-config.sh` runs, then an upload-artifact step whose path names the trace folder, a trace file or a home path, or that includes hidden files, fails rule `traces`. The real files pass.
- AC3 (gateway lines and DW-756; consumer `loadedAfter`). Given `loadedAfter`'s snapshot GET passing its bound, when the diagnosis runs, then:
  - after 11.22's unchanged lines, it prints the Matrix's `DIAG /state gateway ...` lines, counts and states only;
  - a hung or refused gateway read costs none of 11.22's lines and keeps the 15 s ceiling;
  - every DIAG line is also in `state-diagnosis.txt` in the test's output folder, named by a `state-diagnosis` attachment;
  - the thrown error text is unchanged.
- AC4 (cost; lead-side measurement). Given the browser group on CI with traces on and no failures, when its time is compared with the same group's time on the last green run before this story, then the added time is recorded here. More than 2 minutes is reported to the Planner before the merge. Every group stays under REL-4's 35 minutes.
- AC5 (Integration: consumer `loadedAfter` against a real stack). Given a live sign-in-2 stack whose `/state` is held at the browser, when `loadedAfter` passes its bound, then the real IRIS answers with a licence line, gateway server and connections lines with integer counts, and no unavailable line. The output file holds the same lines, and no line holds a cookie value or `CSPSESSIONID`.

### Review Findings

Code review 2026-11-07 (bmad-code-review, full mode, four layers, review tier full-opus: `_bmad/custom/model-overrides.yaml` absent). Each entry: severity, fix-risk, footprint, spec-status, disposition.

- [x] [Review][Patch] HIGH: 11.22's real-stack case "a stack that cannot be reached" still expected one `DIAG /state` line; the gateway read now adds a second, so the sign-in unit (browser group) would go red [web/e2e/api/state-diagnosis.spec.ts:49] — fix-risk low, in-story (D11 not carried to this spec), clear. Red observed before the patch (2 lines, length 1 expected); now expects the licence read's and the gateway read's unavailable lines, header and title updated.
- [x] [Review][Patch] MED: the `traces` rule's `~`, `home` and trace-folder-name checks, and its "folder name unread" FAIL, had no sample that only they flag (every bad sample also held "trace"), so AC2's home-path clause was unpinned [docker/tests/test-ci-config.sh:302] — fix-risk low, in-story, clear. Added samples `traces-home-plain`, `traces-home-env-plain`, `traces-hosted-home-plain` (built like D20) and a check with `tracename=keepme` and `tracename=` empty.
- [x] [Review][Patch] LOW: the `trlink` row caught a removed `! -L` guard only when `find` listed the link before the real trace (directory order) [docker/tests/test-ci-config.sh:2031] — fix-risk low, in-story. The link now points at a file outside the results folder; the target is asserted untouched.
- [x] [Review][Patch] LOW: the `link` row did not assert that the root was not made inside the workspace, as its sibling rows do [docker/tests/test-ci-config.sh:2063] — fix-risk low, in-story.
- [x] [Review][Patch] LOW: diagnose.ts's header said "no ... session id, PID" for the whole dump, while 11.22's lines print pids and four characters of a session id (content kept by U-300; the claim is narrowed to the gateway lines) [web/e2e/support/diagnose.ts:12] — fix-risk low, in-story.
- [x] [Review][Patch] LOW: the `STATE_CHARS` comment said describeGateway uses it; describeGateway uses `STATE_NAME`, which also needs a leading letter [web/e2e/support/diagnose.ts:76] — fix-risk low, in-story.
- [x] [Review][Patch] LOW: a helper-waits title still said "one unavailable line" for a case that asserts two [web/e2e/live/helper-waits.spec.ts:277] — fix-risk low, in-story.
- [x] [Review][Patch] LOW: the `traces kept` header and PASS line did not name the move-failure, link and `..` rows or the 600/700 modes [docker/tests/test-ci-config.sh:23] — fix-risk low, in-story.
- [x] [Review][Defer] LOW: no hermetic case observes the gateway read's own 15 s ceiling; the hang case is capped first by its 12 s test timeout [web/e2e/support/diagnose.ts:171] — deferred: wontfix-accepted DW-875 (both reads share `read()` and `DIAG_BOUND_MS`; reopen_if the gateway read gets a bound of its own).
- [x] [Review][Defer] LOW: "the two reads run at once" leaves 1.6 s of headroom on a loaded host [web/e2e/live/helper-waits.spec.ts:298] — deferred: wontfix-accepted DW-876 (reopen_if it fails in CI with an elapsed time under 4000 ms).

**Rejected.**
- `by-design` (U-300): the 11.22 DIAG lines (lock pid, four-character session prefix, csp pid) and the sanitised `gateway unavailable: <text>` error line in `state-diagnosis.txt`. The NEW gateway lines were checked: ordinals, `COUNT`-validated integers and `STATE_NAME` states only, and an odd value is never echoed.
- `by-design`: AC4 has no mutation and is not measured yet. The spec makes it a lead-side measurement after the push (Verification), not a code defect.
- `by-design` (D8, AC2): pruning runs only when a later group starts with traces on, so an idle runner keeps folders longer than 7 days.
- `by-design` (Matrix "Refused or odd reading"): a state that fails `STATE_NAME`, or an over-long count, turns the whole reading into `an unexpected reading`.
- `by-design` (Tasks, D6): the config checks the switch and `RUNNER_ENVIRONMENT`, not `GITHUB_ACTIONS`. `ci/iris.sh` checks both.
- `by-design`: D19 (`e2e-part.test.mjs`, a ninth file) and D16 (cookie values under 8 characters are not checked).
- `wontfix-theoretical`: the sweep does not check that `rm -f` worked. This is real only if Playwright's own output under `web/test-results` could not be deleted by the same runner user.
- `wontfix-theoretical`: the `traces` rule does not know a custom `OCUTALON_TRACE_DIR` or absolute upload paths. This is real only if a runner sets that variable and a workflow uploads that path; neither exists.
- `wontfix-theoretical`: a trace root that is an ancestor of the workspace could have tag-named folders pruned. This is real only if `OCUTALON_TRACE_DIR` is set to such a folder, and no runner sets it.
- `wontfix-theoretical`: `GITHUB_WORKSPACE` is set but missing. Actions creates it before a step runs.
- `wontfix-theoretical`: `OCUTALON_E2E_TRACE` is set outside `cmd_live` on a self-hosted runner. No workflow step sets it or runs Playwright outside `cmd_live`.
- `wontfix-theoretical`: the pure "cookie-like state" case uses an input that the script's strip cannot produce. `Status` is a gateway-defined word; this is real only if the gateway put a token in `Status`.
- `false`: "DW-756 is closed with no CI evidence". The ledger shows DW-756 still `routed` to this story; closing it is the lead's call.
- `low`, rejected (the fix edits the spec under review): the stale "part 1/3" in the planned mutation list and in the live command, and "ten `cmd_live` rows" in the Auto Run Result. D17 and the recorded mutation line are correct.
- `low`, rejected: the `link` row's setup `mkdir` is removed again by `tk_live`, which is harmless. `tk_prune` also judges the root against the real checkout, which is correct while `TMPDIR` is outside the repository.

## Spec Change Log

## Review Triage Log

### 2026-11-07 — Review pass
- verdicts: 32 rows (the verification-gap layer's four 'other findings' share the last of its rows) — high 0, medium 5, low 27, false 0, maybe-false 0; 7 patched (4 medium, 3 low), 25 rejected, 0 deferred, 0 intent_gap, 0 bad_spec
- findings:
  - Blind Hunter
    - `[low]` `reject` traces stay when the unit is killed before `traces_keep` — the upload step is `if: failure()`, and a cancelled or timed-out job (the `iris` job has a 40-minute `timeout-minutes`) does not reach it; spec D4 chose this guard; a trap would change nothing for a SIGKILL
    - `[low]` `patch` `traces_keep` removed `$dest` with an empty root when traces are off (a root-level path) — fixed: `$dest` is removed only when traces are on
    - `[low]` `reject` `trace_mode` does not check the run tag that `traces_keep` checks — `setup_tag` refuses an invalid tag before `cmd_live` reaches `trace_mode`, so no user-reachable case
    - `[low]` `reject` gateway error text could name an address — the text is the spec's own `CHK|error|gateway|<text>` contract (sanitised, 200 characters), from a local gateway status read; spec-bound
    - `[low]` `reject` one error line discards good gateway lines — the spec's one-unavailable-line contract; the throwaway has one gateway
    - `[low]` `reject` more than 5 gateways are not reported as cut — the stack has one; the fix adds a branch for no reachable case
    - `[medium]` `reject` two concurrent sessions cost a licence unit — decided in D1 and recorded; the licence line may include the second session
    - `[medium]` `patch` test gaps in `traces kept` (link row, symlink trace, failed move, modes) — added rows `unmovable` and `trlink` and the mode 600/700 assertions; tag-unset and rerun-overwrite are the next two rows' kin and stay unpinned (no user-reachable case: `setup_tag` sets the tag; a rerun in a new job has a new tag)
    - `[low]` `reject` retention is by age only, `group` only, with no size cap — D8; a size cap is a new product number
    - `[low]` `reject` the `traces` rule flags any path with `home` or `trace` — the spec's own rule text
  - Edge Case Hunter
    - `[low]` `patch` same root cause as the empty-root `rm` above
    - `[low]` `reject` a trace root set to a broad folder is pruned by `rm -rf` of tag-named children — the operator names the root; only names that pass the run-tag rule go
    - `[low]` `reject` prune follows links or races between `find` and `rm` — theoretical on a runner-owned folder
    - `[low]` `reject` kill before the sweep — as above
    - `[low]` `reject` a link named `.playwright-artifacts-*` is not removed — Playwright makes folders; theoretical
    - `[low]` `reject` a pre-existing root with a looser mode — the contents are mode 600/700 and the root is made 700 by us
    - `[low]` `reject` an odd state fails the whole reading — the spec's own matrix row ("a state outside the pattern")
    - `[low]` `reject` a count above 9 digits or negative fails the reading, and gateways beyond 5 are unreported — spec matrix; theoretical
    - `[low]` `reject` an error line with no text prints an empty reason — the script always prints the status text
    - `[low]` `reject` two concurrent sessions — as above
    - `[low]` `reject` a second diagnosis in one test appends twice — the spec says the file is appended with the lines printed
    - `[low]` `reject` an expression path to the trace folder passes the pin — beyond the rule's text; theoretical
    - `[low]` `reject` other exit routes (not upload-artifact) are not pinned — the rule's scope is upload-artifact
    - `[low]` `reject` `touch -t` with `date -u` shifts local time — the command is the spec's; 6 and 8 days stay on their sides
    - `[low]` `reject` retention is by folder mtime — D8
  - Verification Gap
    - `[medium]` `patch` kept modes 600/700 were not asserted — added to the `on` row; mutation: the `chmod 600` removed -> `FAIL traces kept` (mode 644), restored byte-identical
    - `[medium]` `patch` the move-fails and trace-link branches never ran — rows `unmovable` and `trlink`; mutation: the `! -L` guard removed -> `FAIL traces kept` (trace link rows), restored byte-identical
    - `[medium]` `patch` the concurrency of the two reads was not observable — a case with two 2 s reads asserts under 3.6 s; mutation: the reads made sequential -> red (4047 ms), restored byte-identical
    - `[low]` `patch` the "registered, no server or connection" line (D12) was unpinned — one `toEqual` line in the pure case
    - `[low]` `reject` `cmd_group` is only source-checked — the spec chose it; `traces_prune` itself runs in the prune rows
    - `[low]` `reject` invalid run tag mismatch, grep-style source checks, the `Quit` test being a regex, AC4 without a mutation — as above; AC4 is a measurement by the spec; the live spec is the real guard and runs in `live:sign-in-2`
  - Intent Alignment
    - `[low]` `reject` descriptive report: the diff implements the per-surface reading; the cross-surface chain is the live run (part 2/3 passed) and AC4; the report names the sign-in unit, but the spec runs in sign-in-2

## Design Notes

**Lead's findings (recorded, not re-derived).**
- Step 1 (2026-11-07, cycle log `lead_investigation`, DW-550's trailers) ruled out the per-session gateway cap. Many pages in one CSP session answer `/state` in milliseconds to seconds, even at a cap of 1 or with IRIS CPU-starved. In the CI failures IRIS was idle, and the request never reached a CSP process.
- The gateway status is readable with `GetGatewayRegistry().GetGatewayMgrs().GetAt(1).GetSystemStatus(.s, "stream")`, read in the throwaway's container.
- DW-756's cause: the `docker/tests/test-*.sh` scripts print only `tail -n 30|80` of the e2e log.
- The `iris` job is `runs-on: [self-hosted, ocutalon]`. It runs every live unit, through `cmd_live` (`OCUTALON_E2E_OUTPUT=test-results/$name`).

**Governing ADs.**
- AD-22 (CI as built: the self-hosted IRIS runner, throwaway projects, `ci/iris.sh` the one recipe, nothing in a cache or artifact that must not leave the host). Its Prevents line is untouched.
- AD-19 (no key or secret in a log): the gateway dump prints counts and states only.
- AD-29: these are Lane B files (`web/`, `docker/tests/`, CI scripts), and Epic 11 may change either lane.
- AD-13 (web gateway and application settings) is not changed: test-only.
- No AC contradicts an AD's Rule or Prevents line.
- NFRs: none is unmeasurable. AC4 is a measurement with a fixed threshold.

**Rule 1/2.**
- Integration ACs: AC3 (consumer `loadedAfter`, hermetic stand-in) and AC5 (`loadedAfter` against the real IRIS of a live stack).
- Consumed-by:
  - every `loadedAfter` caller (cards, answers, chat, settings, socket W3, ...), through the diagnosis;
  - every live unit's Playwright run, through the trace switch;
  - the `iris` job, through `traces_prune`.
- Consumes:
  - `irisScript` (support/iris.ts);
  - `asCleanup` and `boundedStep` (support/bounds.ts);
  - `holdState` (support/api.ts);
  - `signIn` and `fixtureUser('LIVE')`;
  - `live_tag_ok` (lib-live.sh);
  - `setup_tag`'s `OCUTALON_RUN_TAG`.
- Extend, don't copy:
  - `gatewayScript` and `describeGateway` are siblings of `diagnosisScript` and `describeDiagnosis` in the same file, with the same CHK grammar. `stateDiagnosis` is extended in place.
  - The file write reuses `currentBound`'s `test.info()` guard.
  - The `traces` rule extends `image-actions`' upload facts and `upload_sample`.
  - `traces kept` follows `preflight_run`'s sourced-with-stubs pattern.
  - `traces_prune` reuses `live_tag_ok`.
  - The trace functions in `ci/iris.sh` are new: no sibling moves files to a host folder.
  - `state-diagnosis.spec.ts` is a new file because it needs a stack, while `helper-waits.spec.ts` stays stack-free.

**Ledger (Rule 17).**
- DW-550: diagnostics attached. The AC3 gateway lines and file, and the AC1 trace of the failing test. It stays OPEN (the Planner's ruling).
- DW-774: diagnostics attached. The AC1 traces cover L5/L6 `page.close` and W3. W3 goes through `loadedAfter`, so it also gets the AC3 lines. It stays OPEN.
- DW-756: closed by AC3. The DIAG lines land in the uploaded output folder, and the failure summary in the printed tail names the file.
- Nothing is declined.

**Expected added time per group (inference, to be replaced by AC4's measurement).**
- Assumption: a trace without the screencast costs about 3 to 10% of a unit's browser-run seconds (its unit seconds less about 260 s of stack setup).
- Unit seconds come from `ci/units.sh`'s notes.
- Per group:

| Group | Added time |
|---|---|
| browser (demo-path, sign-in, answers; about 900 s of browser run) | +30 to 90 s |
| shards-3 (floor, demo-switch) | +20 to 75 s |
| shards (online-session, cards) | +12 to 40 s |
| install-fresh (online-demo) | +12 to 40 s |
| shards-4 (sign-in-2, plus about 10 s for AC5's test) | +20 to 50 s |
| install-upgrade (online-allowance, online-visitors) | +10 to 30 s |
| image (online-demo-path) | +4 to 13 s |
| production, shards-2 | 0 |

- The sweep and the prune add under 1 s per unit.
- The groups were packed to at most about 33 minutes, so all are expected under 35.

**Decided in-stage.**
- D1. The gateway read is a second `irisScript`, concurrent with 11.22's. One hung gateway management call can then neither cost 11.22's lines nor lift the dump's 15 s ceiling. The licence counts may now include the second diagnosis session.
- D2. Output labels are ordinals (gateway g, server s), never names, IPs, ports or PIDs. Values are validated, and an odd one is not echoed. The object form of `GetSystemStatus` is used, with the stream form as the named fallback.
- D3. The DIAG file is `state-diagnosis.txt`, and a path attachment carries it, so the failure summary (at the end of the log, inside the printed tail) names it in CI output.
- D4. No workflow edit.
  - `ci-results.test.mjs` pins the single-line `path: web/test-results/`, and the facts parser reads one-line `with:` values. So the optional `!**/trace.zip` second guard would cost two pin rewrites.
  - The guards taken instead: the move inside `Run the group`; upload-artifact's default exclusion of hidden folders, pinned by `traces`; and an upload that runs only on `failure()`, which a cancelled or timed-out job does not reach.
- D5. `screenshots: false`: DOM snapshots and the network log show what was pending, and the screencast is the largest recording cost, against the 2-minute line.
- D6. `OCUTALON_E2E_TRACE=retain-on-failure` is the switch. The config also requires `RUNNER_ENVIRONMENT=self-hosted`, so a hand-set variable on a laptop or a hosted runner turns nothing on.
- D7. The sweep runs only in CI, so a developer's own results are never touched.
- D8. Pruning runs once per job, at `cmd_group` (each `iris` job runs one group), and only on folders named like a run tag. 7 days means 10080 minutes.
- D9. 11.22's "traces off" pin (D8 of 11.22) is replaced by the owner's ruling (1), and its test is extended, not weakened. It is still `off` in every case but the ruled one.
- D10. `cmd_live` prints `TRACE on` / `TRACE off: <reason>`, so AC4's CI run shows the switch on the real self-hosted runner. Until a real failure happens, the hermetic `traces kept` case is AC1's evidence for the move.
- D11. In 11.22's hermetic pins, the stand-ins branch on the script text. Each exact list gains the gateway lines, and "one unavailable line" becomes one per read.
- D12. `describeGateway` with a `CHK|gw|n` (n above 0) but no server or connection line prints `DIAG /state gateway: <n> registered, no server or connection reported`, so a reading is never silently empty. A script output with no `CHK|gw|` line (for example only `CHK|done|1`) is `unavailable: the session printed no reading`.
- D13. The gateway script prints each count with ObjectScript's unary `+` (a number, never text), and a state with an empty name after stripping is counted as `Unknown`. The connection lines of one gateway are printed after its server lines, in `$Order` (name) order.
- D14. The hermetic hang case asserts `no answer within \d+(\.\d+)? s`: the bound inside a clean-up is the test's time left less the margin, so it prints as a decimal (for example 4.9 s). The file-level stand-in of helper-waits answers the gateway script with `CHK|gw|0`, so the other cases print no stray unavailable line.
- D15. `traces_on` makes the root (umask 077) when it returns 0, so `trace_mode` and `traces_keep` each call it; a refused root is never created. `traces_keep` resolves the root again (same inputs, same answer) rather than passing it. A symbolic link named `trace*.zip` is deleted, never moved. `TRACE removed <n> of <unit> (...)` is printed beside `TRACE kept` when both happen, and nothing is printed when the unit left no trace. The `traces` rule's `-v tracename` is read in a subshell that sources `ci/iris.sh`.
- D16. The new live spec filters cookie values of fewer than 8 characters out of its no-cookie check, since a short flag such as `1` would match ordinary words.
- D17. `state-diagnosis.spec.ts` sorts into sign-in-2 part 2/3 (`live/request-waits` ... `rail/rail`), not part 1/3 as the Verification command assumed; part 2/3 is the AC5 run (about 4 minutes). Part 1/3 holds helper-waits and live.spec.
- D18. The first live run found that the gateway script was not valid ObjectScript: an argumentless `Quit:cond` needs two spaces before the next command, or that command is read as its argument (`<SYNTAX>`). The three `Quit:` in `gatewayScript` now have two spaces, and helper-waits pins the spacing. The fixed script ran against the lane-A dev instance (read-only) and against the throwaway.
- D19. `web/scripts/e2e-part.test.mjs` (not among the eight files) cuts `cmd_live` out of `ci/iris.sh` and asserted its exact stdout. Its harness now cuts the trace helpers out with it, clears `GITHUB_ACTIONS` and `RUNNER_ENVIRONMENT`, and expects the one added `TRACE off: not a CI run` line. The pass-through assertions are unchanged.
- D20. The sample for a hosted upload of a home-folder trace path builds the path from `ho` and `me` and `$trace_folder`, so that no tracked file holds a literal `/home/<name>` path (the boundaries rule).

## Verification

Every command runs from the worktree root after `git rev-parse --show-toplevel` matches it, each in its own foreground call with `timeout: 600000`. One test runner per call; never two at once. `<lane>` stands for `OCUTALON_LOCK_DIR=<lock-dir>/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_RUN_TAG=e11s27i OCUTALON_LOCK_OWNER='epic=11 stage=implement'`. No IRIS MCP call is needed.

**Commands:**
- (loop) `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/helper-waits.spec.ts e2e/live/request-waits.spec.ts --project sign-in-2)`. Expected: all pass with no stack (AC3).
- (loop) `node --test web/scripts/ci-results.test.mjs`. Expected: pass (AC1 config).
- (loop) `bash docker/tests/test-ci-config.sh`. Expected: every rule PASS, `PASS traces` and `PASS traces kept` among them (AC1, AC2). About 35 s.
- (once) `npm --prefix web run lint` and `npm --prefix web test`. Expected: exit 0.
- (once) `bash ci/checks.sh`. Expected: every script passes.
- (once) `(cd web && env -u OCUTALON_URL npx playwright test e2e/live/request-waits.spec.ts e2e/live/helper-waits.spec.ts --project sign-in-2)`, the files in reverse order. Expected: all pass (either order).
- (once) `<lane> bash ci/iris.sh build`, then `<lane> bash ci/iris.sh live sign-in-2 --part 1/3`, each in its own call. Use the part whose SPEC lines include `e2e/live/state-diagnosis.spec.ts`: e2e/live/ sorts first, so part 1. Expected: pass, with AC5's test green and its `DIAG /state gateway` lines in `web/test-results/sign-in-2/` (about 4 to 6 minutes). Then `<lane> bash ci/iris.sh teardown`.
- (once) `git diff --stat -- . ':(exclude)_bmad-output'`. Expected: only the eight files of the Tasks (seven changed, one new).
- (once, lead-side, after the push) AC4. On the story's green `ci` run:
  - Read `GROUP browser passed (<s>s)` and the job time, and compare them with the last green run before the story.
  - Record every group's job time. More than 120 s added to browser, or any group at or over 35 minutes, goes to the Planner before the merge.
  - Confirm that `TRACE on` appears in the iris jobs' live units and that no `TRACE kept` line appears (no failures).

**Rule 19.**
- Shared surfaces:
  - the `DIAG /state` line set (helper-waits' exact lists);
  - `web/playwright.config.ts` `use.trace` (`ci-results.test.mjs`, and the rehearsal and capture configs that spread it);
  - `cmd_live`'s pinned run line and exit status (`ci-results.test.mjs`);
  - `test-ci-config.sh`'s rule list and the real workflows' upload steps;
  - the contents of `web/test-results/` (the failure artifact);
  - the runner host's trace root, shared by the services of one host and keyed by run tag;
  - sign-in-2's spec list, which shifts its `--part` cuts.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.
- Mutations to demonstrate. For each one, observe red, restore byte-identical, and write it as a `mutation:` line:
  - AC1: `traces_keep`'s move replaced by `:` (nothing moved or deleted) → `FAIL traces kept` (a trace stays under the fake `web/test-results`).
  - AC1: the config's `RUNNER_ENVIRONMENT` condition dropped → `ci-results.test.mjs` red (the switch with `github-hosted`).
  - AC2: `TRACE_KEEP_DAYS=30` → `FAIL traces kept` (the 8-day folder kept).
  - AC2: ci.yml's upload `path:` set to `~/ocutalon-traces/` → `FAIL traces` (restore).
  - AC3: `describeGateway` drops `QueuedRequests` → helper-waits' first diagnosis case red.
  - AC3: the file append removed → helper-waits red on `state-diagnosis.txt`.
  - AC5: `gatewayScript` reads a misspelt property (`TotalConnection`) → the live test red on the server line, or on the unavailable line (part 1/3, once).
  - AC4: a measurement, with no pinning test. Its evidence is the two run ids and their numbers.

**Results (implement pass; the stack commands are left to the lead).**
- (loop) `helper-waits.spec.ts` + `request-waits.spec.ts`, project sign-in-2, no stack: 30 passed.
- (loop) `node --test web/scripts/ci-results.test.mjs`: 6 passed.
- (loop) `bash docker/tests/test-ci-config.sh` (and `/bin/bash`, 3.2): all rules passed, `PASS traces` and `PASS traces kept` among them.
- `npm --prefix web run lint` (tsc over the e2e files, node --check of the scripts): exit 0.
- `npm --prefix web run lint`: exit 0 (re-run after the last edit of diagnose.ts and helper-waits).
- `npm --prefix web test`: 1495 passed, also with `GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted`.
- `bash ci/checks.sh`: every script passed except `boundaries` (a literal home path in the new test and spec text, fixed); `bash docker/tests/test-boundaries.sh` and `test-ci-config.sh` pass after the fix.
- Reverse order (request-waits, then helper-waits), project sign-in-2, no stack: 30 passed.
- `ci/iris.sh build`, then `live sign-in-2 --part 2/3` (lane A, fresh throwaway, tag e11s27impl): 55 passed, `state-diagnosis.spec.ts` green. `state-diagnosis.txt` held the licence, the CSP lines, `DIAG /state gateway 1 server 1: TotalConnections=4, ConnectionsInUse=1, PrivateConnections=0, QueuedRequests=0` and `DIAG /state gateway 1 connections: Free=2, InUse=1, Server=1`. `live sign-in-2 --part 1/3` also passed (48 tests, helper-waits among them). `TRACE off: not a CI run` printed by both.

mutation: AC1 `traces_keep`'s `mv` replaced by `:` (ci/iris.sh) -> `FAIL traces kept` ([on: the trace is not at <root>/<tag>/<unit>/<test>/trace.zip] [on: a trace or artifacts folder stays below web/test-results]); restored byte-identical.
mutation: AC1 the config's `RUNNER_ENVIRONMENT === 'self-hosted'` condition dropped (web/playwright.config.ts) -> `ci-results.test.mjs` red on "keeps traces off ... unless the switch and a self-hosted runner both say otherwise" (the switch with github-hosted); restored byte-identical.
mutation: AC2 `TRACE_KEEP_DAYS=30` (ci/iris.sh) -> `FAIL traces kept` ([prune: the 8-day run folder stays]); restored byte-identical.
mutation: AC2 ci.yml upload `path:` set to `~/ocutalon-traces/` -> `FAIL traces` (and `FAIL image-actions`) at ci.yml:135; restored byte-identical.
mutation: AC3 `describeGateway` drops `QueuedRequests` (diagnose.ts) -> helper-waits' first diagnosis case red, and the pure `describeGateway` case; restored byte-identical.
mutation: AC3 the `state-diagnosis.txt` append removed (diagnose.ts) -> helper-waits' first diagnosis case red (ENOENT on `state-diagnosis.txt`); restored byte-identical.
mutation: AC5 `gatewayScript` reads `+cs.TotalConnection` (diagnose.ts) -> `state-diagnosis.spec.ts` red on "a gateway server line with whole-number counts" (live sign-in-2 part 2/3, once); restored byte-identical (cmp against the backup).
mutation: AC1 `chmod 600 "$dest"` removed (ci/iris.sh) -> `FAIL traces kept` (the kept trace's mode is 644); restored byte-identical.
mutation: AC1 the `! -L "$f"` guard removed (ci/iris.sh) -> `FAIL traces kept` (the trace link row); restored byte-identical.
mutation: AC3 the two reads made sequential (diagnose.ts) -> helper-waits "the two reads run at once" red (4047 ms against 3600); restored byte-identical.

**QA gap audit (QA stage).** Every Matrix row and AC has a pinning assertion that can fail, except one found: `traces_on`'s `..` refusal (a root such as `<tmp>/nope/../work/deep/traces` is not resolved by `pwd -P` when `nope` does not exist, so `mkdir -p` would have made the root inside the workspace) had no row. Added the `dotdot` row to `traces kept` in `docker/tests/test-ci-config.sh` (no new file). Hermetic runs at QA: helper-waits + request-waits (sign-in-2, no stack) 32 passed; `node --test web/scripts/ci-results.test.mjs web/scripts/e2e-part.test.mjs` 51 passed; `bash docker/tests/test-ci-config.sh` all rules passed.

mutation: QA the `..` branch of `traces_on` removed (ci/iris.sh) -> `FAIL traces kept` (the dotdot row: the unit got an OCUTALON_E2E_TRACE, no `TRACE off:` line, the root was made); restored byte-identical.

**Code review (2026-11-07).** The review's patches were run: `web/e2e/api/state-diagnosis.spec.ts -g "cannot be reached"` (chromium, no stack: red before the patch, 1 passed after); helper-waits and request-waits (sign-in-2, no stack) 32 passed; `npm --prefix web run lint` exit 0; `bash docker/tests/test-ci-config.sh` all rules passed (also under `/bin/bash` 3.2); `bash docker/tests/test-boundaries.sh` all rules passed.

mutation: CR AC3 the gateway read's lines dropped from `stateDiagnosis` (`gateway.slice(1)`, diagnose.ts) -> `e2e/api/state-diagnosis.spec.ts` "a stack that cannot be reached prints one unavailable line per read" red (length 1, 2 expected); restored byte-identical.
mutation: CR AC2 the `~` and `home` checks removed from rule `traces` (test-ci-config.sh rules.awk) -> `FAIL traces: the rule does not flag the sample traces-home-plain`; restored byte-identical.
mutation: CR AC2 the trace-folder-name term and the `tracename == ""` FAIL removed (rules.awk) -> `FAIL traces: [the trace folder own name is not flagged] [an unread folder name does not fail the rule]`; restored byte-identical.
mutation: CR AC1 the `! -L "$f"` guard removed (ci/iris.sh), with the link now pointing outside the results folder -> `FAIL traces kept` ([trace link: the file was not kept, or the link was moved] [trace link: no 'TRACE removed 1 of fake' line]); restored byte-identical.
mutation: CR AC1 the workspace check of `traces_on` disabled (ci/iris.sh) -> `FAIL traces kept` (among others [a root behind a link: the root was made]); restored byte-identical.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Live units on a self-hosted CI runner keep Playwright traces of failing tests only (`retain-on-failure`, no screenshots); `ci/iris.sh` moves them to `<root>/<tag>/<unit>/` outside the workspace and checkout (root mode 700, files 600), deletes any other trace and every artifacts folder, keeps the unit's exit code, and prunes run folders older than 7 days at the start of a group. A `traces` rule in `test-ci-config.sh` refuses any upload-artifact step that names the trace folder, a trace file, a home or `..` path, or includes hidden files. `loadedAfter`'s diagnosis now adds `DIAG /state gateway ...` lines (counts and states) from a second, concurrent read, and writes every DIAG line to `state-diagnosis.txt`, attached as `state-diagnosis`. No product code, workflow, `lib-live.sh` or `units.sh` change.

**Files changed.**
- `ci/iris.sh`: trace root, `traces_on`, `trace_mode`, `traces_keep`, `traces_prune`; `cmd_live` and `cmd_group` calls; header.
- `docker/tests/test-ci-config.sh`: rule `traces` (real workflows and samples) and block `traces kept` (ten `cmd_live` rows, prune rows, source checks).
- `web/e2e/support/diagnose.ts`: `gatewayScript`, `describeGateway`, concurrent reads, the DIAG file and attachment; header.
- `web/e2e/support/floor.ts`: `loadedAfter` doc comment.
- `web/e2e/live/helper-waits.spec.ts`: stand-ins that branch on the script text; gateway, file, hang, concurrency, pure and script-text cases.
- `web/e2e/live/state-diagnosis.spec.ts` (new): AC5 against a real stack (sign-in-2 part 2/3).
- `web/playwright.config.ts`: the trace switch (needs the env switch and `RUNNER_ENVIRONMENT=self-hosted`).
- `web/scripts/ci-results.test.mjs`: the trace pin extended, not weakened.
- `web/scripts/e2e-part.test.mjs`: the `cmd_live` pass-through harness follows the new `TRACE off` line (D19).

**Review.** 32 triage rows: 7 patched (4 medium, 3 low), 25 rejected with their reasons in the log, 0 deferred. Patches: no `rm` of a root-level path when traces are off; mode 600/700, move-failure and trace-link rows in `traces kept`; a timing case for the concurrent reads; the "registered, no server" line pinned. Mutations for each patched test are in the log and in `## Verification`.

**Follow-up review recommended: true** (first pass, 4 medium entries patched). Unverified risk: the added `traces kept` rows (`unmovable`, `trlink`, mode checks) and the timing case were written after the review layers read the diff.

**Verification.** (loop) helper-waits and request-waits 32 passed (also in reverse order); `ci-results.test.mjs` 6 passed; `test-ci-config.sh` all rules passed. (once, after the last patch) `npm --prefix web run lint` exit 0; `npm --prefix web test` 1495 passed; all 31 `CHECK_SCRIPTS` passed (run in two halves, `boundaries` among them); `ci/iris.sh build` and `live sign-in-2 --part 2/3` on a fresh lane-A throwaway (tag e11s27impl): 55 passed with `state-diagnosis.spec.ts` green, the throwaway removed by the script. The first live run found that the gateway script was not valid ObjectScript (D18); the fixed script returned real counts.

**Residual risks.**
- AC4 (the cost of traces per group) is lead-side and not measured here. `TRACE on` on the real self-hosted runner and the `iris` job's real trace move after a real failing test are first seen on CI.
- The trace sweep runs at the end of `cmd_live`; a job killed before it is not uploaded (the upload runs on `failure()` only), per D4.
- D1: the second diagnosis session may add one licence unit to the licence line.
