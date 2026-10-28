---
title: 'Story 8.7: Epic 8 burn-down'
type: 'chore'
created: '2026-10-27'
status: 'done'
baseline_revision: '1d6c98b3a75249e90aa2b81fee6777bac5b0167a'
baseline_commit: '1d6c98b3a75249e90aa2b81fee6777bac5b0167a'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      api.spec's per-test baseline could still see an instance event published between its baseline read and a later read, when a spec that publishes (heartbeat) ran just before it.
    evidence: |-
      The spec lists it as residual risk (inference): StatusMonitor publishes only on a change, and nothing changes while api.spec runs. The one heartbeat-first run (0-heartbeat, 21 of 21) passed. Standing runs never put heartbeat before api.spec, so the window is not exercised.
      Would settle it: a heartbeat-first run repeated several times on a fresh stack, or a StatusMonitor check that its clear event lands before heartbeat.spec ends.
    location: >-
      web/e2e/api/api.spec.ts:103
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** `live sign-in` (`docker/tests/test-sign-in.sh`) runs all 18 spec files of the Playwright `chromium` project (222 tests) in one call. In planning that took 521 s on the developer machine, and it passes only with `OCUTALON_LIVE_DEADLINE=900`, against the 10-minute foreground cap every stage works under (DW-314). Separately, `web/e2e/api/api.spec.ts` pins the instance stream at exactly one event. It passes only because `api/` sorts before `heartbeat/`, whose case adds two status events to that stream (DW-204).

**Approach:**
- The script takes `--part k/n` and runs only part k of n of the project's spec files, on its own fresh stack with the same setup. The recipe runs `ci/iris.sh live sign-in --part 1/2`, then `--part 2/2`, one per call.
- A part is a contiguous run of whole spec files, in path order. The cut follows `ci/iris.sh shard --part k/n`'s rule, but counts tests instead of files (Decided 1).
- A new dependency-free helper, `web/scripts/e2e-part.mjs`, makes the cut from Playwright's own listing, so a new spec file joins a part with no change.
- With no argument, the script runs the whole unit exactly as today, and CI's `browser` group doesn't change.
- api.spec reads the instance stream against a baseline that each test takes itself.

## Boundaries & Constraints

**Always:**
- **Every spec once.** For one n, the parts taken in order run every spec file of the `chromium` project's listing exactly once. Each file stays whole, and the order is the order the whole unit runs them.
- **The listing comes from Playwright** (`npm --silent --prefix web run e2e -- --list --reporter=json`), never from a hand-kept list or from folder names. That keeps `playwright.config.ts`'s `testIgnore` as the one source; Epic 6 adds `**/e2e/answers/**` there.
- **The split rule.**
  - With T tests listed in run order, cut them into n contiguous ranges whose sizes differ by at most one, the first T mod n being the larger. This is `shard_part`'s rule, counted in tests.
  - A spec file goes to the part whose range holds its first test.
  - Today, with n = 2, part 1 is `api/` to `guide/` (7 files, 126 tests) and part 2 is `heartbeat/` to `trace/trace` (11 files, 96 tests).
- **The same setup in every part.** Each part pays the whole setup: build, first start, security checks, all 14 fixture users and the three seeded events.
  - Only the browser step changes. It runs `npm --prefix web run e2e -- --test-list <file>`, where the file holds the part's spec files as the listing names them. Playwright matches those names exactly.
- **No false all-clear.** A part passes only when its run's passed plus skipped tests equal the tests its part lists.
- **Bad arguments fail early.** A bad argument exits 2 before the lock, the bundle build or any stack.
- **Deadline.** Each part runs inside the default local deadline of 540 s, with no `OCUTALON_LIVE_DEADLINE`.
- **What api.spec still pins exactly** is what test-sign-in.sh seeded:
  - the README session's two reminder events;
  - the instance stream's first event, `instance:1`, a `noModelKey` status.

  Every other instance-stream expectation is relative to the stream's events as that test reads them when it starts.
- **Source text.** Comments state the contract (Rule 14), and code holds no non-ASCII byte. No committed file holds a local absolute path (`test-boundaries.sh`).

**Never:**
- **Don't edit these files.** They are contended or out of scope:
  - `ci/units.sh` (the `browser` group line and `BROWSER_UNITS`);
  - `docker/tests/test-demo-path-gate.sh`, `docker/tests/test-ci-config.sh` and `docker/tests/lib-live.sh`;
  - `.github/**`, `web/src/**`;
  - `web/playwright.config.ts`, `web/package.json` and `web/scripts/playwright-projects.test.mjs`;
  - any spec under `web/e2e/` other than `api/api.spec.ts`. The one exception is heartbeat.spec.ts's header comment.
- Add no new unit name, group entry, CI job or npm script.
- Don't make a second copy of `test-sign-in.sh`.
- Don't use Playwright's `--shard`, and don't pass file filters as regular expressions (Decided 1 and 4).
- Change no product code, no setup step of the unit, no seeded event and no fixture user.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Part 1 of 2 | `ci/iris.sh live sign-in --part 1/2`, with today's listing (18 files, 222 tests) | Before the stack starts: `PART 1/2: 7 of 18 spec files, 126 of 222 tests: api/api.spec.ts ... guide/guide.spec.ts`. Its own stack and the full setup, then 126 passed, ending `test-sign-in part 1/2: all checks passed` | none |
| Part 2 of 2 | `--part 2/2` | `PART 2/2: 11 of 18 spec files, 96 of 222 tests: heartbeat/heartbeat.spec.ts ... trace/trace.spec.ts`, then 96 passed (planning measured 305 s on a fresh stack) | none |
| No part | `ci/iris.sh live sign-in` (CI's `browser` group) | The whole unit as today: no listing, no PART line, every spec in one run | none |
| A new spec file | A spec added under the chromium project | Playwright lists it, and it joins the part whose range holds its first test. The parts still cover every file once | none |
| Bad value | `--part` alone, `--part=`, `x`, `0/2`, `3/2`, `1/0`, `1/2/3`, `19/19` (n above the 18 files), or an unknown argument | Exit 2 with one line naming the value. No `LOCK` line, no bundle build, no stack | none |
| Empty part | A listing where part k gets no file (tests 1 and 100, n = 2: part 2) | Exit 2: part k/n holds no spec file, so use fewer parts | none |
| Broken listing | A spec that fails to load, an unreadable or non-JSON listing, or a listing with `errors[]` | Exit 1 with Playwright's message, before any stack | none |
| Short run | The part's Playwright run exits 0 but ran fewer tests than its part lists | A `FAIL` line naming both counts, and the script exits 1 | none |
| Heartbeat first | heartbeat.spec's onset and clear land on the instance stream before api.spec, on the same stack | api.spec passes: the seeded `instance:1` comes first, and every cursor is relative to the stream's last Seq | none |

</intent-contract>

## Code Map

No product code changes.

**The unit and the recipe** (Lane B's):
- `docker/tests/test-sign-in.sh`:
  - the header, `:1-52`, which gets the `--part` contract;
  - `. lib-live.sh` at `:56`, then `live_start t03` at `:57`. `live_start` claims the lane lock, sets `deadline`, `cd`s to the root, makes `$tmp` and rebuilds the bundle. Argument parsing, the listing and the split go before it;
  - the setup, `:91-180`, which doesn't change;
  - the browser step, `:184-240`: `npm --prefix web run e2e > "$e2e_log"` at `:227`, and the PASS/FAIL lines at `:233` and `:239`;
  - the final lines, `:242-246`.
- `ci/iris.sh`:
  - `cmd_live`, `:370-394`, checks `$1` and runs `bash "docker/tests/test-$name.sh"` with no argument (`:393`). Its header entry is `:15-17`.
  - Story 5.3's change to this file touches neither. That change is on the integration branch: `shard --part`, header `:12-13` and `shard_part`.
  - No open epic branch edits `ci/iris.sh`.
  - `cmd_group`, `:400-429`, calls `bash ci/iris.sh live <name>` with no further argument, so CI keeps running the whole unit.
- `ci/units.sh` (read only):
  - `:33` and `:41`: the `browser` group is `live:demo-path live:sign-in`, and `BROWSER_UNITS` lists the browser units;
  - `group_input_pattern`: the browser group's pattern claims `web/` (`WEB_BUNDLE_INPUT`), so the new helper is an input of the group.
- `docker/tests/test-ci-config.sh` (read only; contended, since Epic 10 and Story 5.3 edit it):
  - `demo_path_violations`, `:719-750`: a script with a code line holding `npm --prefix web run e2e` must be in `BROWSER_UNITS`. Keep the run line's text;
  - `unit_reads`, `:927-931`: a file named through `$root/...` must be claimed by the group's pattern.
- `docker/tests/test-demo-path-gate.sh` (read only) stubs `test-sign-in.sh` and runs `group browser`, so this story doesn't affect it.

**Helper siblings:**
- `web/scripts/demo-path-summary.mjs` and its `demo-path-summary.test.mjs` are the pattern for the new helper and its test. The helper is a dependency-free CLI with exported functions, used by `docker/tests/test-demo-path.sh:52`. The test has `playwrightEnv()` at `:331`.
- `web/scripts/playwright-projects.test.mjs:27-55`, `bareEnv()` and `listedReport()`, hold the listing command. Read it only: Epics 6 and 16 edit this file.

**Playwright 1.64.1** (`web/node_modules/playwright/lib/runner/index.js`, read only):
- `loadTestList` (about `:2746`):
  - a line is `[project] › file › titles`, or a bare file;
  - the file must equal `path.relative(config.rootDir, file)`, and `rootDir` is `web/e2e`;
  - checked in planning: `chat/chat.spec.ts` matches that file only, not `reminder/chat.spec.ts`;
  - a run whose test list matches nothing exits 0.
- `filterForShard` (about `:2462`): `--shard` cuts by counting only the tests that aren't skipped at load (Decided 1).
- The JSON listing:
  - `suites[]` at the top level has one entry per file, in run order, with `file` relative to `e2e/`;
  - count the `specs[].tests[]` through nested `suites[]`;
  - `errors[]` is set when a spec fails to load.

**Specs:**
- `web/e2e/api/api.spec.ts` (Epic 2's; no open branch edits it):
  - `ids()` is at `:95`;
  - row 13 is at `:100`, with `streams` `{session: 2, instance: 1}` at `:114`;
  - rows 13 and 14 are at `:147`, with `['instance:1']` at `:161`;
  - row 14 is at `:166`: all events at `:174-189`, the cursors at `:191-192`;
  - the cursors test is at `:202`, with its expectations at `:210-213`;
  - the `request` and `page.request` contexts are signed in through `signInOverHttp` and `signInReadme`; `EVENTS` and `STATE` come from `support/api.ts`.
- `web/e2e/heartbeat/heartbeat.spec.ts:18-19` holds the sentence "The two events it causes on the instance stream come after api.spec, which pins that stream at one event (...path order, with one worker)". This story makes it false.
- Other specs' doc comments say "api.spec pins their counts": `chat/chat.spec.ts:11`, `chat/decision.spec.ts:10`, `chat/notice.spec.ts:11`, `banners/banners.spec.ts:22` and `live/live.spec.ts:12`. They stay as they are (Decided 8).

**Rule 21:** `_bmad/custom/skill-rules.md:291` is the last CI-recipe bullet ("`live:sign-in` near its local deadline"). The new bullet goes right after it.

## Tasks & Acceptance

**Execution:**
- [ ] `web/scripts/e2e-part.mjs` (new; dependency-free; header in the style of `demo-path-summary.mjs`) -- the split, one rule in one place:
  - `parsePart(text)` returns `{k, n}`. It accepts `^[0-9]{1,6}/[0-9]{1,6}$` with 1 ≤ k ≤ n, and otherwise throws a bad-value error.
  - `partOf(report, k, n)` returns `{files: [{file, tests}], totalFiles, totalTests}`. It reads the listing's files in order, with their test counts, and applies the split rule.
    - These are bad values: n above the file count, and a part k that holds no file.
    - These are a broken listing: a report with no suites, or with `errors[]`.
  - The CLI is `node web/scripts/e2e-part.mjs <k/n> <listing.json>`.
    - The first line of stdout is `PART k/n: <f> of <F> spec files, <t> of <T> tests: <file> <file> ...`.
    - Then comes one line per file of the part, named as the listing names it.
    - It exits 2 on a bad value, and 1 on a missing, unreadable or broken listing, with the message on stderr.
- [ ] `web/scripts/e2e-part.test.mjs` (new; `node:test`; its own scratch folder; no stack and no browser) -- AC 1 and AC 2:
  - **Synthetic listings**, in Playwright 1.64.1's JSON shape:
    - today's counts, `[20,19,20,14,15,20,18,1,14,6,19,2,2,9,5,15,19,4]`, with n = 2 give 7 + 11 files and 126 + 96 tests;
    - `[2,2]` with n = 2 gives file 1, then file 2;
    - for several listings and every n from 1 to F, the parts put together equal the listing, each file once, or a part is refused as empty;
    - a file whose tests cross a range end stays whole, in the part of its first test;
    - `[1,100]` with n = 2 refuses part 2;
    - every bad value of the matrix exits 2 through the CLI, and a broken listing exits 1.
  - **The real listing**, made the way test-sign-in.sh makes it, with every `OCUTALON_` variable removed as `bareEnv()` does: for n = 2 and n = 3, the parts' files in order are the listing's files, each exactly once, and their tests add up to the listing's total. The CLI's PART line agrees.
- [ ] `docker/tests/test-sign-in.sh` -- AC 2 and AC 3:
  - **Arguments.** Parse `--part k/n` or `--part=k/n`. `--part` with no value, or any other argument, exits 2 with a usage line.
  - **Before `live_start`**, when a part is given, from the repository root:
    1. List the project into a temporary file with `npm --silent --prefix web run e2e -- --list --reporter=json`. A failed listing prints its tail and exits 1.
    2. Run the helper, and pass its exit code 2 or 1 through.
    3. Print the helper's PART line and keep its file lines.
  - **After `live_start`**, write the file lines to `$tmp/part.list`.
  - **The browser step** adds `-- --test-list "$tmp/part.list"` to the existing `npm --prefix web run e2e` line. Keep that text as it is, for test-ci-config's rule.
  - **The guard.** When the run exits 0, read the list reporter's summary lines (`<x> passed` and `<y> skipped`, anchored, with any ANSI stripped). If x + y isn't the part's `t`, call `fail "part k/n ran <x+y> of its <t> tests"`.
  - **The output with a part.** The PASS/FAIL line says "the specs of part k/n of the chromium project", and the final lines read `test-sign-in part k/n: ...`.
  - **With no part**, every line, the run and the output stay byte for byte as today.
  - Add the `--part` contract to the header.
- [ ] `ci/iris.sh` -- the minimal pass-through (Decided 2), and nothing else:
  - In `cmd_live`, after the checks, `shift`, then run `bash "docker/tests/test-$name.sh" "$@"`, so the arguments after the unit name reach its script.
  - In the header's `live` entry, add one line after `:17`: the arguments after `<name>` go to the script, and `test-sign-in.sh` takes `--part k/n`.
- [ ] `web/e2e/api/api.spec.ts` -- AC 4:
  - **A new helper, `instanceBaseline(request)`.**
    - It polls `${EVENTS}?after=999999999999999&afterInstance=0`, which returns instance events only.
    - It asserts the ids are `instance:1` to `instance:N`, contiguous, with N ≥ 1, and returns them.
    - Each test that names the instance stream takes it right after it signs in, and the helper's doc comment says why.
  - **Row 13:** `streams` equals `{session: 2, instance: N}`.
  - **Rows 13 and 14:** the first-call user's `?after=0&afterInstance=0` poll equals the baseline, so no session event is there.
  - **Row 14:**
    - all events are `session:1:reminder`, `session:2:reminder` and then the baseline, whose first event is `instance:1:status` with the seeded payload;
    - `?after=2&afterInstance=N` gives `[]`;
    - `?after=1&afterInstance=N` gives `['session:2']`;
    - new: `?after=2&afterInstance=1` gives the baseline after its first id, which may be no id at all.
  - **The cursors test:**
    - `after=2&afterInstance=0` gives the baseline;
    - `after=0&afterInstance=N` gives both session events;
    - `after=1&afterInstance=0` and `after=001&afterInstance=00` give `session:2`, then the baseline.
  - Every other assertion stays as it is. The file's header says the instance stream is read against each test's own baseline.
- [ ] `web/e2e/heartbeat/heartbeat.spec.ts` -- comment only, `:18-19`: the two events stay on the instance stream, and api.spec reads that stream against its own baseline, so the order of the two files doesn't matter.
- [ ] `_bmad/custom/skill-rules.md` -- append one bullet after `:291`, in the style of its neighbours, headed "**`live:sign-in` in two parts (the date of the measurement, Story 8.7, the developer machine, lane C).**". Appending a measured recipe to Rule 21 is decide. The bullet says:
  - a stage runs `ci/iris.sh live sign-in --part 1/2`, then `--part 2/2`, one per call, with the lane's variables and the default deadline;
  - each part starts its own fresh stack with the whole setup and runs about half the spec files: whole files, in path order, cut by tests (`web/scripts/e2e-part.mjs`). Together the parts run every spec once;
  - the measured times of each part and of the one whole run;
  - the whole unit (no `--part`) is what CI's `browser` group runs; locally a stage runs it at most once, with `OCUTALON_LIVE_DEADLINE=900`;
  - when a part nears 8 minutes, use `--part k/3`. Epic 6's `cards/` specs will join part 1.

**Acceptance Criteria:**
- **AC 1 (the split).** **Given** the `chromium` project's JSON listing, **when** `e2e-part.mjs` gives part k of n for every k (n = 2 and 3 on the real listing, and every n on the synthetic ones), **then**:
  - the parts' spec files, put together in k order, are the listing's files in run order, each exactly once and whole;
  - their test counts add up to the listing's total;
  - each file sits in the part whose test range holds its first test (the ranges are contiguous, their sizes differ by at most one, and the first T mod n are the larger);
  - **and** a spec file added to the project joins a part with no change to any list.
- **AC 2 (bad values).** **Given** a `--part` value that is malformed, has k outside 1 to n, has n above the listed file count, or names a part that holds no file, or an unknown argument, **when** `bash docker/tests/test-sign-in.sh` or `ci/iris.sh live sign-in` gets it, **then** it exits 2 with one line naming the value, before any `LOCK` line, bundle build or stack.
- **AC 3 (two parts through the recipe).** **Given** lane C on the developer machine, **when** a stage runs `ci/iris.sh live sign-in --part 1/2` and then `--part 2/2`, one per call with the default deadline, as Rule 21's new bullet says, **then** each part:
  - prints its PART line before its stack starts;
  - starts its own fresh throwaway with every fixture user and seeded event;
  - runs exactly its part's spec files;
  - passes only when its passed and skipped tests equal the part's test count;
  - ends `test-sign-in part k/2: all checks passed` in about 5 minutes (recorded).

  Together the two PART lines name every file of the listing once. **And** without `--part`, the unit runs every spec in one run as before, with no PART line: in CI's `browser` group, and in one local run with `OCUTALON_LIVE_DEADLINE=900`.
- **AC 4 (DW-204).** **Given** heartbeat.spec.ts has run before api.spec.ts on the same stack, leaving its onset and clear on the instance stream, **when** api.spec.ts runs, **then** every case passes.
  - **And** api.spec.ts passes in part 1/2, where no heartbeat runs before it, and in the whole unit, where heartbeat runs after it.
  - **And** the same heartbeat-first run, with api.spec.ts as it was before this story, fails rows 13, 13-14 and 14.

### Review Findings

Code review, 2026-10-27: Tier 1 on this spec, baseline `182f222`, full mode, four layers (blind, edge, verification gap, acceptance), all on the session model. 38 raw findings, 11 entries after grouping: high 1, medium 4 (one maybe-false), low 6. Decision-needed 0, patch 8, defer 3, rejected 21. Each entry gives severity / fix-risk / footprint / spec-status (Rule 15).

- [x] [Review][Patch] The real-listing bad-argument case `--part=19/19` depends on the repository's file count: once a 19th chromium spec file exists (Epic 6's `cards/`), 19/19 is a valid part, so `npm --prefix web test` runs `live_start` (lock, bundle, stack) with no OCUTALON_ variable. Use an n no listing reaches, 999999/999999 [web/scripts/e2e-part.test.mjs:220] (medium / low / in-story / clear; Rule 19 hermeticity)
- [x] [Review][Patch] The `ci/iris.sh live` pass-through harness inherits the caller's environment, so with `OCUTALON_TEST_WEB_PORT` set (the lane's variables) its exact `PORT ...: auto` checks fail. Give it `bareEnv()` like every other spawn of the file [web/scripts/e2e-part.test.mjs:393] (medium / low / in-story / clear; Rule 19 hermeticity)
- [x] [Review][Patch] The stub-npm case loops three times over one `refuse.args` file and never removes it, so passes 2 and 3 can pass the "lists the project with Playwright" check on pass 1's file. Remove the file before each run [web/scripts/e2e-part.test.mjs:285] (medium / low / in-story / clear; Rule 19, an assertion that cannot fail)
- [x] [Review][Patch] A repeated `--part` in the spaced form says "--part needs one value k/n", and neither repeat message names the value. Report the repeat on its own and name the second value [docker/tests/test-sign-in.sh:71] (low / low / in-story / clear; AC 2 "one line naming the value")
- [x] [Review][Patch] The script-level bad-argument cases assert exit 2, one line and no LOCK, but not that the line names the value, so dropping `'$1'` from a message stays green [web/scripts/e2e-part.test.mjs:223] (low / low / in-story / clear; AC 2)
- [x] [Review][Patch] No test runs the part block's `echo "$part_line"` or its two texts (`chromium_specs`, `summary`), with a part or without one, so a part with no PART line, or a whole run that reads "part  of", would ship [docker/tests/test-sign-in.sh:123] (low / low / in-story / clear; AC 3, and "no part: byte for byte")
- [x] [Review][Patch] A part's PASS and FAIL lines still list every row of the unit, so part 2's log claims Story 0.5's rows 13-19 (api/) passed. With a part, the line says only the rows in the part's spec files ran [docker/tests/test-sign-in.sh:126] (low / low / in-story / clear)
- [x] [Review][Patch] The Rule 21 bullet leaves out `OCUTALON_LIVE_DEADLINE=900` where it says a stage runs the whole unit locally at most once (Task 7), against measured 513 to 521 s and the 540 s default [_bmad/custom/skill-rules.md:292] (low / low / in-story / clear)
- [x] [Review][Defer] AD-22's skip rule is broken for the hosted `web` job: `e2e-part.test.mjs` runs and cuts `docker/tests/test-sign-in.sh`, but `WEB_INPUT_PATTERN` (`ci/units.sh:54`) doesn't declare that script, so a push that changes only it skips the job's unit tests while the `browser` group runs the whole unit, with no `--part`. The skip turns a red into a green on branch pushes. The fix is one alternation, `docker/tests/test-sign-in\.sh$`, in `ci/units.sh`, which is contended (Epic 6) and in this story's Never list [ci/units.sh:54] — deferred: DW-335, `routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test`, out-of-footprint (high / low / out-of-footprint / clear; Rule 6). It stays unresolved in this story, so the story stays open until the orchestrator rules on the contended edit.
- [x] [Review][Defer] The baseline race has a second window: in row 13 the page's `/state` is answered during sign-in, before `instanceBaseline`, so an instance event between the two would differ from `streams.instance` [web/e2e/api/api.spec.ts:121] — deferred: an occurrence appended to DW-334 (maybe-false, medium if real; still `open`, owned by this story); a heartbeat-first run repeated on fresh stacks would settle it
- [x] [Review][Defer] Five other specs' headers still say api.spec pins the instance stream's count (`chat/chat.spec.ts:11`, `chat/decision.spec.ts:10`, `chat/notice.spec.ts:11`, `live/live.spec.ts:12`, `banners/banners.spec.ts:22`). The banners one also says no spec publishes on that stream, which is false since Story 8.2 [web/e2e/banners/banners.spec.ts:22] — deferred: DW-336, wontfix-accepted, out-of-footprint (Decided 8 and the Never list); reopen when a story edits one of those files (low / low / out-of-footprint / spec-bound)

**Rejected** (21 raw findings):
- Blind 4 (low): in rows 13-14, the baseline poll is now the first call before `/state`. Sign-in creates the row (AD-4), the header's "first call" names no endpoint, no assertion is lost, and Task 5 puts the baseline right after sign-in.
- Blind 7, Edge 7, Gap other 3 (low, theoretical): the flaky fixture counts 127 tests for a part of 126, and a flaky test would make a green part read as short. `retries: 0` (`web/playwright.config.ts:25`), so no flaky line can occur, and the guard fails closed. It becomes real if a `--part` run ever retries.
- Blind 6, second claim (low): the Story 8.3 bullet's "re-run with 900" conflicts with the new one. The new bullet, right after it, gives the recipe; the old one is a measurement record, and editing older bullet text is not an append.
- Edge 1, Acceptance 4 (low): a malformed value exits 1, not 2, when the listing itself fails. Tasks list first and then cut, the run fails closed, and the fix adds a shell parser.
- Edge 2 (theoretical): the listing has no timeout. It takes about 0.4 s, and nothing shows it can hang.
- Edge 3 (low): an interrupt during the listing leaves two temporary files. Negligible, as at implement.
- Edge 4 (theoretical): `PLAYWRIGHT_JSON_OUTPUT_*` set in the caller's environment empties the listing. Nothing sets it, and the run fails closed with exit 1.
- Edge 5 (low): the tree changes between part 1 and part 2. The recipe runs both parts on one tree, each PART line names its files, and the fix needs listing hashes.
- Edge 6, Acceptance 2, Gap other 1 (by-design): other live units ignore arguments, and through `ci/iris.sh live` the PORT line, preflight and the Chromium install come before the script refuses a value. Decided 2 and Task 4 ("nothing else") make the pass-through two lines; no lock, bundle or stack comes first.
- Edge 10 (theoretical): `realpathSync(process.argv[1])` throws on a non-path argv. It is the same idiom as every sibling CLI (`catalog`, `demo-path-summary`, `payloads`, `tokens`), and nothing imports the module that way.
- Edge 11, Gap 6 (by-design): nothing pins the instance stream at only the seeded event any more. The Boundaries ("What api.spec still pins exactly") and DW-204 chose this, and test-sign-in.sh checks `instance-seq` 1 at the seed.
- Edge 12 (false): the header cites `ci/iris.sh shard --part`, which this branch lacks. It is on the integration branch (`shard_part`, Story 5.3), where this lands.
- Gap 5 (by-design): AC 4 rests on a one-off order run. Decided 9 makes that run the evidence, and a standing check needs a seeded-event change, which is not allowed.
- Gap roll call 2 (low): `!/LOCK/` cannot fail on the hosted runner, which has no lock folder. The exit-2 and one-line checks stand for "before the lock" everywhere, and the LOCK check can fail on the developer machine.
- Acceptance 6 (process): QA's tests are uncommitted. The lead commits them.
- Acceptance 7 (bookkeeping): the Auto Run Result says 24 tests. The fix would edit the spec's result section.

- [x] [Review] DW-335 (HIGH, AD-22; orchestrator ruling 2026-10-28: option (a) allowed, decide): add exactly one alternation, `|docker/tests/test-sign-in\.sh$`, to `WEB_INPUT_PATTERN` in `ci/units.sh` (line 54; shared by entry, a plain union at integrate-forward), so a push that changes only `docker/tests/test-sign-in.sh` runs the hosted `web` job's unit tests that read and run it; and add a check that pins it (a hermetic test that fails if the pattern stops matching `docker/tests/test-sign-in.sh`, preferably in `web/scripts/e2e-part.test.mjs`), with an observed mutation and its `mutation:` line. Nothing else in `ci/units.sh`.

Code review (rework 1), 2026-10-28: Tier 1 on this spec, baseline `1d6c98b` (the rework's), full mode, four layers (blind, edge, verification gap, acceptance), all on the session model with no override. 8 raw findings, 4 entries after grouping: high 0, medium 1, low 3. Decision-needed 0, patch 3, defer 1, rejected 2. DW-335 is fixed. `ci/units.sh:54` holds the one ruled alternation and nothing else changed there. `ci/changes.sh:186` sets `web=true` from that pattern, and `ci.yml` runs `npm --prefix web test` only on `web == 'true'`. `test-ci-changes.sh`'s classifier case expects `web=true` and only `browser` for the script. The pin sources the real `ci/units.sh` and goes red when the alternation is dropped or loosened (the mutation lines below).

- [x] [Review][Patch] The pin checks the literal `'docker/tests/test-sign-in.sh'`, not the path the file reads and runs (`unitPath`). After a rename of the script and of `unitPath`, which the file must update, the old alternation still matches the literal, and the classifier's `live:*` arm expects `web=false`. Both checks stay green while the renamed script is no web input. Take the path from `unitPath` [web/scripts/e2e-part.test.mjs:465] (medium / low / in-story / clear; Rule 19, AD-22)
- [x] [Review][Patch] The file's header doesn't say that the file also pins `WEB_INPUT_PATTERN` [web/scripts/e2e-part.test.mjs:1] (low / low / in-story / clear; Rule 14)
- [x] [Review][Patch] DW-335's latest ledger trailer still routes it to `11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test`, so Story 11.1's plan would receive an item that is already fixed. Append `resolved-by:8-7-epic-8-burn-down` through the ledger tool [_bmad-output/implementation-artifacts/deferred-work.md] (low / low / in-story / clear)
- [x] [Review][Defer] The comment above `WEB_INPUT_PATTERN` names "the scripts that build the web and run the mock's tests". `docker/tests/test-sign-in.sh` is neither, so the comment no longer names every input of the pattern [ci/units.sh:50] — deferred: DW-338, wontfix-accepted, because the ruling allows only the alternation in that file; reopen when a story edits that comment or the pattern (low / low / out-of-footprint / clear; Rule 14)

**Rejected** (2 raw findings, and one half of an entry):
- Edge 1 (low): `matches()` reads a failed source of `ci/units.sh` as "no match", so the near-miss case would pass with no pattern read. The positive case goes red in the same situation, so the suite can't pass, and the fix adds a guard.
- Acceptance 3 (low): the cycle-log ruling on the `test-ci-changes.sh` case has no `by=`, and the Spec Change Log doesn't name that file. The ruling is recorded (`category=decide`, `policy=36abb05`), and the Rework 1 result names the file. The fix would edit the cycle log or the spec.
- The ledger entry's other half (Blind 1, Acceptance 2): the round-1 Defer bullet above still says DW-335 stays unresolved. Changing it would edit an earlier review record. This block and the ledger trailer record the resolution.

## Spec Change Log

- 2026-10-28 (lead): rework iteration 1 opened after code review (HIGH DW-335); the orchestrator allowed the one `WEB_INPUT_PATTERN` alternation (option (a)); one `[Review]` item under Tasks & Acceptance.

## Review Triage Log

### 2026-10-27 — Review pass
- verdicts: 31 findings — high 0, medium 1, low 19, false 7, maybe-false 4
- findings:
  - `[low]` `[reject]` Blind 1: a bad `--part` through `ci/iris.sh live` is refused only after preflight and the Chromium install — the contract says before the lock, the bundle build or any stack, and that holds; a pre-check in `cmd_live` would grow the allowed two-line pass-through (Decided 2).
  - `[low]` `[reject]` Blind 2: other live units ignore arguments, so `live floor --part 1/2` runs whole — Decided 2 states it, and a guard edits more of the contended ci/iris.sh.
  - `[maybe-false]` `[defer]` Blind 3: an instance event between a test's baseline read and a later read fails it when heartbeat ran just before — deferred as medium (unverified); the spec names it residual risk (inference) and the one heartbeat-first run passed.
  - `[false]` `[reject]` Blind 4: the listing is made in a different environment from the run — playwright.config.ts reads OCUTALON_URL, the JSON path and the timeout only, its testIgnore and file set do not depend on any variable, and every live part run passed the guard against the listing's counts.
  - `[false]` `[reject]` Blind 5: the guard ignores flaky counts and no mutation exercises it — `retries: 0` in playwright.config.ts, and the AC 3 mutation ran red on `FAIL part 1/18 ran 0 of its 20 tests`.
  - `[low]` `[patch]` Blind 6: no shell-level test of the argument parser, and `cd "$(dirname "$0")/../.."` before the source breaks for a relative path from another directory — a node:test now runs the script with eight bad arguments (rc 2, one line, no LOCK), and the script takes its own absolute directory first and uses it for the cd and the source.
  - `[low]` `[reject]` Blind 7: the spec's Auto Run Result is stale and the recipe has no advice for a red part — the result is written at finalize, and a red part is re-run alone by the same recipe.
  - `[false]` `[reject]` Edge 1: a flaky test makes a green part read as short — `retries: 0`, so none can occur.
  - `[false]` `[reject]` Edge 2: no summary line gives part_ran 0 with an unclear message — it fails closed with "ran 0 of its N tests"; the real exposure is the PART-line drift (Gap 3).
  - `[false]` `[reject]` Edge 3: the listing's environment differs from the run's — same refutation as Blind 4.
  - `[low]` `[reject]` Edge 4: an interrupt during the listing leaves two temp files — negligible.
  - `[low]` `[reject]` Edge 5: arguments to a unit that reads none — same as Blind 2.
  - `[low]` `[reject]` Edge 6: bad values are refused late through `ci/iris.sh live` — same as Blind 1.
  - `[maybe-false]` `[defer]` Edge 7: the api.spec.ts:121-133 baseline race — same root as Blind 3.
  - `[maybe-false]` `[defer]` Edge 8: the api.spec.ts:166-180 baseline race — same root as Blind 3.
  - `[low]` `[reject]` Edge 9: `partOf` called with k outside 1 to n — its only caller is the CLI behind parsePart.
  - `[low]` `[reject]` Edge 10: a part whose files hold no test — Playwright runs the files, the guard reads 0 of 0, and no real file has none.
  - `[low]` `[reject]` Edge 11: file names with a space or newline — no such spec file exists, and Playwright's test list uses the same line format.
  - `[false]` `[reject]` Edge 12 (claim): part 1 might pass 540 s before the 8-minute advice — measured 307 to 318 s, about 220 s of headroom, and the bullet says to move to `--part k/3` as it grows.
  - `[low]` `[patch]` Gap 1: `|| k === n` (trailing files with no test) is pinned by no test — `[3,3,0]`, `[3,0,0]` and `[2,4,0,0]` joined the every-n list, a direct test was added, and a mutation line records red.
  - `[low]` `[patch]` Gap 2: the shell side of AC 2 has no standing test — covered by the bad-argument node:test and its mutation line (same root as Blind 6).
  - `[medium]` `[patch]` Gap 3: the guard fails open if the PART line drifts (a non-numeric part_tests makes `[ -ne ]` error out and the script passes) — the script now exits 1 unless the part label and its count are numeric; the mutation line records the live check (exit 1 in seconds).
  - `[low]` `[reject]` Gap 4: the DW-204 fix is verified only by the one-off order run — Decided 9 makes that run the agreed evidence, and a standing check needs a second order or another seeded event (not allowed).
  - `[maybe-false]` `[defer]` Gap other 1: the baseline-to-later-read race — same root as Blind 3.
  - `[low]` `[reject]` Gap other 2: the real-listing test takes its total from the same function — the 222 total is pinned by the synthetic `TODAY` case and by every live guard.
  - `[low]` `[reject]` Gap other 3: the real-listing suite lists at collection time and needs web/node_modules — the hosted web job installs them, as playwright-projects.test.mjs also assumes.
  - `[low]` `[patch]` Intent 1: no committed test at the script surface — same root as Blind 6 and Gap 2.
  - `[low]` `[reject]` Intent 2: preflight and the Chromium install run before a bad value is refused — same as Blind 1.
  - `[low]` `[reject]` Intent 3: manual runs, not tests, are the evidence for the short run, the heartbeat-first row and the timings — live stacks cannot run in a hosted test; each has a recorded mutation or measurement.
  - `[low]` `[reject]` Intent 4: the baseline helper relies on `?after=999999999999999` serving instance events only — every live run exercised it, and the cursors test pins that cursor.
  - `[false]` `[reject]` Intent 5: flaky counts are not summed — same as Edge 1.

### 2026-10-28 — Review pass (rework 1, DW-335)
- verdicts: 12 findings — high 0, medium 0, low 10, false 2, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1: the comment above `WEB_INPUT_PATTERN` does not name `test-sign-in.sh` — the orchestrator's ruling is one alternation and nothing else in the contended `ci/units.sh`; a comment edit beside line 54 only raises the integrate-forward conflict risk, and the pattern is pinned by a test.
  - `[low]` `[patch]` Blind 2: the mutation block header names one runner for all three mutations — the header now names `docker/tests/test-ci-changes.sh` for the third.
  - `[low]` `[reject]` Blind 3: the `live:sign-in` arm of the classifier case would go stale on a rename — the unit's name is also read by `ci/iris.sh` and `e2e-part.test.mjs` reads the script by path, so a rename is not silent.
  - `[low]` `[reject]` Blind 4: the test pins one path with no completeness scan of the files the web tests read — the item asks to pin this path; a scan is a wider check than the ruling allows.
  - `[low]` `[reject]` Edge 1: same root as Blind 1.
  - `[false]` `[reject]` Edge 2: the helper repeats `ci/changes.sh`'s grep call — the classifier case in `test-ci-changes.sh` (`web=true`) is the cross-check, and its mutation was observed red.
  - `[low]` `[reject]` Edge 3: no upper-case or trailing-space near miss — theoretical; nobody makes the pattern case-insensitive, and the fix adds paths for no named harm.
  - `[low]` `[patch]` Gap 1: nothing pins the `\.` escape of the alternation — `docker/tests/test-sign-inXsh` joined the near misses; the mutation (escape dropped) was observed red and recorded.
  - `[low]` `[reject]` Gap other 1: same root as Blind 1.
  - `[low]` `[reject]` Gap other 2: `matches()` reads status 1 as "no match" even when sourcing fails — the positive case goes red in that situation, so the suite cannot pass; a guard adds branches for no reachable green.
  - `[false]` `[reject]` Intent 1: the `test-ci-changes.sh` edit is outside "nothing else in `ci/units.sh`" — the item limits that one file; the old `web=false` expectation for the script contradicted the ruling, so the case had to change.
  - `[low]` `[reject]` Intent 2: nothing tests the workflow's gating on `web=true`, and no scan covers every file the web tests read — both are wider than the item; `ci/changes.sh`'s verdict is pinned by the classifier case.

## Design Notes

**Rulings in force (dispatch, 2026-10-27):**
- DW-314 is the owner's decision, through the Contest Planner: two runs of about 4 to 5 minutes each, before Epic 8 merges, as test infrastructure only.
- The orchestrator ruled:
  - the part argument goes in `test-sign-in.sh`, which no open branch edits;
  - the split is by spec file, like `shard --part`;
  - CI's `browser` group keeps running the whole unit.
- Epic 6 is editing `ci/units.sh`'s group line, `BROWSER_UNITS` and the demo-path gate right now, so all three stay untouched.
- A change to `ci/iris.sh` must be one self-contained, minimal pass-through. No open epic branch edits that file, and the change is kept minimal anyway.

**Governing ADs:**
- AD-22: the test recipe and its throwaways, the six CI groups, and `browser` running `live:sign-in` whole.
- AD-12: the instance stream's `Seq` is per stream and comes from a counter the purge never resets, and `/state` gives each stream's last `Seq` for the cursors. That is why `instance:1` to `instance:N` is contiguous.
- AD-18: heartbeat.spec's onset and clear come from StatusMonitor (read only).
- AD-29: these are Lane B's files, and runner C keeps Lane B's.
- Conventions: "Tests" (Playwright specs live under `web/e2e/`).
- Checked: no AC contradicts an AD's Rule.

**Measured in planning.** On throwaway `e8s7plan`, lane C; each stack was torn down by its EXIT trap, and the tree was clean afterwards.
- **The whole unit.** `ci/iris.sh live sign-in` with `OCUTALON_LIVE_DEADLINE=900` took 521 s. Playwright took 427.9 s of it: 222 passed, in 18 files.
- **Time per file** (Playwright's span, in seconds):

  | File | Seconds |
  |---|---|
  | `api/` | 7.5 |
  | `banners/` | 84.8 |
  | `chat/chat` | 65.5 |
  | `chat/decision` | 11.5 |
  | `chat/notice` | 23.7 |
  | `frame/` | 9.8 |
  | `guide/` | 22.7 |
  | `heartbeat/` | 27.1 |
  | `live/` | 52.3 |
  | `phone/` | 1.6 |
  | `rail/` | 37.3 |
  | `reminder/chat` | 13.2 |
  | `reminder/reminder` | 27.3 |
  | `session/` | 8.8 |
  | `sign-in/shell` | 1.3 |
  | `sign-in/sign-in` | 2.4 |
  | `trace/links` | 23.5 |
  | `trace/trace` | 7.2 |

- **Part 2 alone on a fresh stack.** It ran through a temporary one-line `--test-list` edit of the script, reverted byte for byte (sha checked).
  - The 11 files from `heartbeat/` on took 305 s with the default deadline. Playwright took 213.6 s of it, and 96 passed.
  - On the young stack heartbeat took 38 s, against 27 s in the whole run, and it passed.
  - The setup costs about 91 to 95 s per part, so part 1 should take about 225.5 + 93 ≈ 318 s. That figure is an inference: part 1 is a prefix of the whole run, so its specs see the same state.
- **The listing.** `npm --silent --prefix web run e2e -- --list --reporter=json`, with no `OCUTALON_` variable set, takes about 0.4 s. It gives the same 18 files and 222 tests as the live run, and its `rootDir` is `web/e2e`.
  - A `--test-list` line `chat/chat.spec.ts` selects that file alone.

**Decided in-stage:**
1. **Cut by tests: not by files, and not with `--shard`.**
   - Cut literally as `shard_part` cuts, 9 files and 9 files, part 1 gets 305 s of Playwright: about 400 s with the setup, or 6.7 minutes. Part 2 gets about 216 s. That misses the owner's "about 4 to 5 minutes".
   - The same contiguous rule counted in tests gives about 318 s and 305 s. That is the best contiguous cut; cutting after `frame/` gives about 296 s and 329 s.
   - Each part pays about 93 s of setup, so two parts can't both come in under about 5.1 minutes. "About 4 to 5 minutes" is therefore read as about 5, with the default 540 s deadline as the hard bound. This is not an NFR tripwire.
   - Playwright's `--shard` uses the same rule but counts only the tests that aren't skipped at load. Its cut would then depend on the environment the listing ran in. `e2e-part.mjs` counts every listed test, so the hermetic test and the live run cut in the same place.
2. **An argument, not a variable.**
   - `--part k/n` mirrors `shard --part`, and the ruling says "part argument".
   - `cmd_live` forwards its arguments, a two-line pass-through.
   - Other live scripts ignore arguments; only `test-sign-in.sh` reads them.
3. **Playwright's listing is where the files come from.** So Epic 6's `testIgnore` addition and its new `cards/` specs change nothing here.
4. **`--test-list`, not filters.** It matches relative paths exactly. A filter such as `chat/chat.spec.ts` is a regular expression, in which `.` matches any character.
5. **The guard.** In Playwright, a test list that matches nothing exits 0. Without the count check, a broken part would read as passed (product default 2).
6. **Exit codes as `shard --part` has them.** Exit 2 for a bad value or too many parts. Exit 1 for a broken listing, a failed check or a short run.
7. **No new rule in `test-ci-config.sh`.** That file is contended (Epic 10, Story 5.3). `e2e-part.test.mjs` pins the split in the hosted `web` job, through `npm --prefix web test`.
8. **Comments.**
   - heartbeat.spec's sentence is Epic 8's own and becomes false, so it is replaced.
   - The other specs' "api.spec pins their counts" notes stay. Each states that spec's own rule, that it publishes nothing on those streams, and that still holds. Also, `chat/decision.spec.ts` is edited on the integration branch.
9. **The DW-204 evidence.**
   - For one run of `--part 1/18`, `heartbeat/` moves to `web/e2e/0-heartbeat/`; its imports keep their depth. With 222 tests and n = 18, part 1 then holds only `0-heartbeat/heartbeat.spec.ts` and `api/api.spec.ts`, about 140 s.
   - It runs once with the old api.spec (red) and once with the new one (green). Then the folder moves back.
   - Playwright has no reverse file order, so this run is api.spec's reversed-order evidence (Rule 19).

**Ledger inbox:**
- DW-314: addressed by Tasks 1 to 4 and 7, AC 1 to AC 3, and the matrix.
- DW-204: addressed by Task 5, AC 4, the matrix row "Heartbeat first", and heartbeat.spec's comment (Task 6).

**Integration ACs.** The part argument and `e2e-part.mjs` have two consumers:
- Rule 21's recipe, as a stage runs it: `ci/iris.sh live sign-in --part k/2` forwards the part, and the script runs that part on its own stack. Observable: the PART line, and a pass with the part's test count (AC 3).
- `npm --prefix web test`, which runs the helper on the real listing (AC 1).

**Consumes:**
- Playwright 1.64.1's listing and `--test-list`;
- `lib-live.sh`'s `live_start`;
- Story 5.3's `shard --part` rule, as a rule;
- Story 8.2's heartbeat.spec;
- Story 0.5's seeded events.

**Consumed-by:**
- every later stage that runs `live:sign-in`, through the Rule 21 bullet;
- Epic 6's `cards/` specs, which join a part when that epic merges, with no change.

**Extend, don't copy:**
- The script is extended in place; there is no second script.
- `shard_part` is in `ci/iris.sh` on the integration branch only. It splits a class list inside a script that `test-sign-in.sh` doesn't source, and it counts items. Here the items are files weighted by their tests, so the helper restates the rule in about 10 lines, for the reason in Decided 1.
- `listedReport()` is local to `playwright-projects.test.mjs`, which is contended. The new test runs the same command in a few lines of its own.

**Footprint extensions to report:**
- `ci/iris.sh`: the `cmd_live` pass-through and one header line;
- `web/scripts/e2e-part.mjs` and `web/scripts/e2e-part.test.mjs`, both new;
- `web/e2e/heartbeat/heartbeat.spec.ts`: a comment only, in Epic 8's own file.

**Residual risk:**
- A status event published between a test's baseline and its assertions would still fail api.spec. StatusMonitor publishes only on a change, and nothing changes while api.spec runs (inference).
- Epic 6's `cards/` specs will make part 1 longer. The recipe says when to move to three parts.

## Verification

**Shared values.**
- `<L>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=<stage>'`. Write it out in full on each call.
- Tags: implement uses `e8s7i`, and other stages use `e8s7<stage>`. `live` never runs warm.
- Each call is its own foreground call with `timeout: 600000`.

**Commands:**
- `(loop)` `node --test web/scripts/e2e-part.test.mjs` and `npm --prefix web run lint`. Expected: pass, within seconds.
- `(loop)` One per call: `<L> OCUTALON_RUN_TAG=e8s7i bash docker/tests/test-sign-in.sh --part 3/2; echo "rc=$?"`, and the same with `--part x`, `--part 19/19`, `--part` and `--bogus`. Expected: `rc=2` within seconds, one line naming the value, and no `LOCK` line.
- `(once)` `<L> OCUTALON_RUN_TAG=e8s7i ci/iris.sh live sign-in --part 1/2`. Expected: `PART 1/2: 7 of 18 spec files, 126 of 222 tests: ...` (or the listing's figures at the time), then `all checks passed`. Record the time; about 318 s is expected.
- `(once)` The same with `--part 2/2`. Expected: `PART 2/2: 11 of 18 ..., 96 of 222 tests`, then passed. Record the time; about 305 s is expected.
- `(once)` The DW-204 order run (Decided 9), before Task 5 and then after it:
  1. Run `mv web/e2e/heartbeat web/e2e/0-heartbeat`.
  2. Run `<L> OCUTALON_RUN_TAG=e8s7i ci/iris.sh live sign-in --part 1/18`. Expected: the PART line names `0-heartbeat/heartbeat.spec.ts` and `api/api.spec.ts`. With the old api.spec it is red in rows 13, 13-14 and 14.
  3. After Task 5, make the same call. Expected: green.
  4. Move the folder back. Then `git status --short` and `git diff --stat` show only the story's own changes.
- `(once)` The whole unit, at most once: `<L> OCUTALON_LIVE_DEADLINE=900 OCUTALON_RUN_TAG=e8s7i ci/iris.sh live sign-in`. Expected: no PART line, `222 passed` (or the listing's total), and passed. Record the time; about 521 s is expected.
- `(once)` `npm --prefix web test`, then `bash ci/checks.sh` (which includes `test-ci-config.sh` and `test-demo-path-gate.sh`), then `bash docker/tests/test-boundaries.sh`. Expected: pass.
- `(once, last, also after a failure)` `<L> OCUTALON_RUN_TAG=e8s7i ci/iris.sh teardown`.

**Mutations (Rule 19).** Apply each mutation, observe red, revert, and confirm the tree is byte-identical. Record each as `mutation: <change> -> <red test>`.
- AC 1: in `partOf`, the range end `p < end` becomes `p <= end`. Red: `e2e-part.test.mjs`'s synthetic cases, "`[2,2]`, n = 2" and the every-n case among them. Today's real listing has no file whose first test sits exactly on a range end, so its case stays green under this mutation.
- AC 2: `partOf` drops the check for n above the file count. Red: the CLI bad-value case `19/19`.
- AC 3: the script writes each test-list line with an `e2e/` prefix, so it matches no file. Red: `<L> OCUTALON_RUN_TAG=e8s7i ci/iris.sh live sign-in --part 1/18` (today `api/` alone, 20 tests) ends `FAIL part 1/18 ran 0 of its 20 tests` and exits 1 instead of passing (about 100 s).
- AC 4: api.spec as it was before Task 5. Red: step 2 of the order run, in rows 13, 13-14 and 14.

**Shared surfaces:**
- the instance stream's events: api.spec now reads them against its own baseline, and heartbeat.spec and `reminder/chat.spec.ts` publish on that stream;
- the sign-in unit's spec-file order and its one setup, which every part runs again;
- `ci/iris.sh live`'s arguments, which go to every live script and which only `test-sign-in.sh` reads;
- the hosted `web` job's test set, which `e2e-part.test.mjs` joins;
- the run times of `live:sign-in`, parts and whole, and Rule 21's recipe.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutation results (implement stage).**
- mutation: in `partOf` of `web/scripts/e2e-part.mjs`, the range end `first < end` becomes `first <= end` -> red: `e2e-part.test.mjs` "gives file 1 to part 1 and file 2 to part 2 for two files of two tests", "puts the parts together into the listing, each file once, for every n from 1 to the file count" and "sizes the ranges to differ by at most one, the first T mod n being the larger" (3 failed; the real-listing cases stayed green, as predicted); reverted from backup, file byte-identical.
- mutation: `partOf` drops the check for n above the file count (`if (n > all.length)` becomes `if (false)`) -> red: `e2e-part.test.mjs` "refuses part 2 of [1,100] as empty, and n above the file count" and the CLI case "exits 2 with one line naming the value, for every bad value of the matrix" (19/19 no longer exits 2); reverted from backup, file byte-identical.
- mutation: in `partOf` of `web/scripts/e2e-part.mjs`, `(first < end || k === n)` becomes `(first < end)` -> red: `e2e-part.test.mjs` "gives the files with no test after the last test to the last part" and "puts the parts together into the listing, each file once, for every n from 1 to the file count" (the `[3,3,0]` family). Reverted from backup, sha identical.
- mutation: in `docker/tests/test-sign-in.sh`, the `--part` branch's needs-a-value exit is `exit 0` instead of `exit 2` -> red: `e2e-part.test.mjs` "exits 2 with one line naming the value and no LOCK line for --part" (re-observed at code review; the repeat case now has its own branch, below). Reverted from backup, sha identical.
- mutation: in `describePart` of `web/scripts/e2e-part.mjs`, "spec files" becomes "specs" in the PART line -> red: `bash docker/tests/test-sign-in.sh --part 1/2` exits 1 in seconds with "cannot read the part and its test count", before the lock, where the guard would otherwise have been silently off. Reverted from backup, sha identical.
- mutation: `docker/tests/test-sign-in.sh` writes each test-list line with an `e2e/` prefix (`printf 'e2e/%s\n' "$part_files" > "$tmp/part.list"`) -> red: `ci/iris.sh live sign-in --part 1/18` (api/ alone, 20 tests) printed `FAIL part 1/18 ran 0 of its 20 tests` and exited 1 after 83 s (implement stage, lane C); reverted from backup, sha identical.
- mutation: `web/e2e/api/api.spec.ts` as it was before this story, with `heartbeat/` moved to `0-heartbeat/` so that it runs first -> red: `ci/iris.sh live sign-in --part 1/18` (`0-heartbeat/heartbeat.spec.ts` then `api/api.spec.ts`, 21 tests) failed 4 tests: row 13, rows 13-14, row 14 `/events` by cursor and row 14 cursors; with the new api.spec the same run passed 21 of 21. The folder was moved back.

**QA gap audit (QA stage).** Gaps found: the script's listing step (stub-npm), its PART-line parse, its passed-plus-skipped guard and `ci/iris.sh live`'s pass-through had no hermetic pin; their only evidence was live runs or a mutation seen once. Closed in `web/scripts/e2e-part.test.mjs` (QA, 10 tests added; 34 in all; no new file, so `npm --prefix web test` picks it up as before). No stack was started, so no teardown was needed.
- `web/scripts/e2e-part.test.mjs` (QA): stub-npm tests of the script's listing step (exit 2 and 1 pass-through, no LOCK line, the exact listing command, temporary files removed); the PART-line parse cut out of the script and run on the helper's own line; the script's verdict block cut out and run on fixture logs (colour codes, durations, skipped counted, flaky ignored, short and long runs, non-zero exit, no part); `cmd_live` cut out of `ci/iris.sh` and run with stubbed checks (no argument, arguments kept whole, unknown unit).
- mutation: `test-sign-in.sh` guard counts passed only (`part_ran` drops `part_skipped`) -> red: "counts skipped tests with the passed ones, and ignores a flaky line" and "fails a part that ran fewer or more tests than it lists"; reverted from backup, sha identical.
- mutation: `ci/iris.sh` `cmd_live` loses its `shift` -> red: "gives the script no argument when there is none after the unit name, as before" and "gives the script the arguments after the unit name, each whole"; reverted, sha identical.
- mutation: `describePart`'s "spec files" becomes "specs" -> red: "reads the part and its test count from the line the helper prints", plus the PART-line and real-listing cases; reverted, sha identical.
- mutation: `test-sign-in.sh` exits 1 instead of the helper's status (`|| exit "$part_status"` becomes `|| exit 1`) -> red: the six bad-value script cases and "lists the project with Playwright, removes its temporary files, and exits 2 ..."; reverted, sha identical.
- mutation: `test-sign-in.sh` stops removing the listing files (`rm -f "$part_listing" "$part_errors"` becomes `:`) -> red: both stub-npm cases; reverted, sha identical.
- mutation: `test-sign-in.sh` lists with `--reporter=list` -> red: the `--part=999999/999999` bad-argument case and the stub-npm command check (re-observed at code review, after the case's value changed); reverted, sha identical.
- Audit result for the rest: AC 1 (split, new spec joins, every n) and AC 2 (helper and script bad values, empty part, broken listing) were already pinned with observed mutations; the live-only rows (AC 3 stack, short run on a real log, AC 4 heartbeat-first) keep their implement-stage observed mutations and are not re-run (no part script was changed). Unpinned and left so: the `--test-list` file's content against Playwright's matching, the hosted-test-impossible live path (observed live at implement: the `e2e/` prefix mutation).

**Mutation results (code review).** Each was applied to the patched tree, observed red with `node --test web/scripts/e2e-part.test.mjs`, then reverted from the reviewer's own backup, sha identical.
- mutation: the unknown-argument message drops `'$1'` -> red: "exits 2 with one line naming the value and no LOCK line for --bogus".
- mutation: the spaced repeat's message drops `'${2:-}'` -> red: the same case for `--part 1/2 --part 2/2`.
- mutation: the part block's `echo "$part_line"` becomes `:` -> red: "prints the PART line and names the part in its texts, and with no part prints nothing and keeps the whole unit's texts".
- mutation: `[ -z "$part_label" ] || summary=` becomes `[ -n ...` -> red: the same test, in its no-part half.
- mutation: the part's `chromium_specs` text goes back to "the specs of part k/n of the chromium project" -> red: the same test.
- mutation: the `--part` branch refuses `19/19` with one line before the listing -> red: "lists the project with Playwright, removes its temporary files, and exits 2 for a part the listing refuses" (no args file). With the test as it was before the review, the same mutation stayed green, 34 of 34: pass 1's args file answered for passes 2 and 3.
- The pass-through harness with `OCUTALON_TEST_WEB_PORT=52803` set: 2 failed before `env: bareEnv()`, 35 of 35 after.
- Live, lane C, tag `e8s7c`: `ci/iris.sh live sign-in --part 2/2` on a fresh stack, 307 s, 96 passed, ending `test-sign-in part 2/2: all checks passed`. Its PASS line ends "of these rows, those in the spec files of part 2/2 of the chromium project pass (96 passed)". Part 1/2 was not re-run: the patched lines are the same for every k, and the hermetic test runs them.

**Mutation results (rework 1, DW-335).** Each was applied to the patched tree, observed red with the runner named on its line (`node --test web/scripts/e2e-part.test.mjs`, or `bash docker/tests/test-ci-changes.sh` for the third), then reverted from its own backup, sha identical.
- mutation: `ci/units.sh` without the `|docker/tests/test-sign-in\.sh$` alternation (the file as it was before the rework) -> red: "matches docker/tests/test-sign-in.sh, the script that this file reads and runs" (1 failed of 37).
- mutation: the alternation's `$` dropped (`test-sign-in\.sh|`) -> red: "does not match a near miss of that path" (`docker/tests/test-sign-in.sh.bak` matches; 1 failed of 37).
- mutation: `ci/units.sh` without the alternation, run against `docker/tests/test-ci-changes.sh` (whose live-script classifier case for `live:sign-in` now expects `web=true`) -> red: "classifier: the script of live:sign-in runs web and only browser"; reverted, sha identical.
- mutation: the alternation's `\.` becomes `.` (`test-sign-in.sh$`, the escape dropped) -> red: "does not match a near miss of that path" (`docker/tests/test-sign-inXsh` matches; 1 failed of 37, code review); `ci/units.sh` reverted from backup, sha identical.
- mutation: `ci/units.sh` without the alternation, re-run on the pin as patched at the rework's code review (it takes its path from `unitPath`) -> red: "matches docker/tests/test-sign-in.sh, the script that this file reads and runs" (`AssertionError: docker/tests/test-sign-in.sh`; 1 failed of 37); `ci/units.sh` reverted from backup, sha identical.
- mutation: a rename that leaves the pattern behind: a copy of the script as `docker/tests/test-sign-on.sh`, with `unitPath` pointed at it -> red: "matches docker/tests/test-sign-in.sh, the script that this file reads and runs" (`AssertionError: docker/tests/test-sign-on.sh`; 1 failed of 37). With the pin as it was before the rework's code review, the same change stayed green, 37 of 37. The copy was removed and the test file restored from backup, sha identical.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented.** `live sign-in` takes `--part k/n` and runs part k of n of the chromium project's spec files on its own fresh stack; without an argument it runs the whole unit as before. api.spec reads the instance stream against a baseline that each test takes itself (DW-204).

**Files changed.**
- `web/scripts/e2e-part.mjs` (new): the split helper, cutting Playwright's own listing by tests, with a CLI.
- `web/scripts/e2e-part.test.mjs` (new): 24 tests: synthetic listings, the CLI, the script's bad arguments, and the real listing for n = 2 and 3.
- `docker/tests/test-sign-in.sh`: argument parsing, the listing and PART line before the lock, `--test-list`, the passed-plus-skipped guard, and the `--part` header.
- `ci/iris.sh`: `cmd_live` forwards the arguments after the unit name, plus one header line.
- `web/e2e/api/api.spec.ts`: `instanceBaseline` and relative instance-stream expectations.
- `web/e2e/heartbeat/heartbeat.spec.ts`: header comment only.
- `_bmad/custom/skill-rules.md`: one Rule 21 bullet appended, the two-part recipe with the measured times.

**Review.** 31 findings, one pass. Patches applied (5 rows, 3 fixes): a bad-argument test of the script, an absolute script directory, a numeric check on the PART line before the guard, and trailing-file tests. Deferred: 1 (the baseline race, medium unverified). Rejected: 22 with their reasons in the triage log. Follow-up review recommended: false (one medium patched).

**Measured (developer machine, lane C, fresh stacks).**
- Part 1/2 (7 files, 126 tests): 318 s before the review patches, 307 s after.
- Part 2/2 (11 files, 96 tests): 301 s both times.
- The whole unit with `OCUTALON_LIVE_DEADLINE=900`: 513 s, 222 passed, no PART line (run once, before the review patches; the patches touch only the `--part` block and the library path, which parts re-ran).
- DW-204 order run: old api.spec red in 4 tests with heartbeat first, new api.spec green (21 of 21).

**Verification performed.** `node --test web/scripts/e2e-part.test.mjs` 24 of 24; `npm --prefix web test` 715 of 715; `npm --prefix web run lint`; `bash ci/checks.sh` (all scripts passed, including test-ci-config and the demo-path gate); `bash docker/tests/test-boundaries.sh`; the bad-argument runs return rc 2 with no LOCK line; every mutation in `## Verification` was applied, observed red and reverted byte-identical; tag e8s7i torn down.

**Residual risks.** The baseline race (deferred). Epic 6's `cards/` specs will lengthen part 1; the recipe says when to move to three parts.

### Rework 1 (DW-335)

Status: done
Blocking condition: none

**Implemented.** `ci/units.sh`: one alternation, `|docker/tests/test-sign-in\.sh$`, in `WEB_INPUT_PATTERN`, so a push that changes only `docker/tests/test-sign-in.sh` runs the hosted `web` job. `web/scripts/e2e-part.test.mjs`: a describe block that sources `ci/units.sh` and applies the pattern with `LC_ALL=C grep -Eq`, as `ci/changes.sh` does, asserting the path matches and six near misses do not. `docker/tests/test-ci-changes.sh`: the classifier case for the script of `live:sign-in` now expects `web=true` with only `browser` (decided in-stage: the old `web=false` expectation contradicted the ruling).

**Review.** 12 findings: patched 2 (both low: the `\.` escape pin and the mutation block header), rejected 10 with reasons in the triage log, deferred 0. Follow-up review recommended: false (patched counts: high 0, medium 0, low 2).

**Verification performed.** `node --test web/scripts/e2e-part.test.mjs` 37 of 37; `npm --prefix web test` 728 of 728; `bash ci/checks.sh` all scripts passed (it includes `test-ci-changes.sh`); `bash docker/tests/test-boundaries.sh` all rules passed; four mutations observed red and reverted sha-identical. No stack was started.

**Residual risks.** None named.
