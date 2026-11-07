---
title: "Story 32.5: live:sign-in splits again after 4.11's tests"
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

**Problem:** Story 4.11 added 96 more-to-try tests to the chromium Playwright project. Since then `live:sign-in` takes 1,034 s (feature 5b47f052, ci run 42393186349) and 1,170 s (OCT-epic11 623b9cb0, ci run 42392984136). That is over the 1,000 s unit line and close to its 1,200 s deadline, and it pushes the `browser` group to 2,104 s, over REL-4's 35-minute budget.

**Approach:** Split the chromium project's spec files again, the same way the 2026-11-05 split made `live:sign-in-2`:
- a new Playwright project `sign-in-3`;
- a one-line wrapper `docker/tests/test-sign-in-3.sh`;
- a new unit `live:sign-in-3` in `shards-5`;
- every pin that names `live:sign-in-2` extended to cover the new unit.

`sign-in-3` takes `guide/`, `heartbeat/` and the root file `heartbeat-card.spec.ts`, about 429 s of browser run. chromium keeps the rest, about 421 s.

## Boundaries & Constraints

**Always:**
- Every test is kept. The chromium and sign-in-3 listings together equal today's chromium listing, test by test. Every other project's listing, `sign-in-2` included, stays byte-identical.
- Change whole spec files only, and only through the config. No spec file is moved, renamed or edited.
- Extend the 2026-11-05 siblings: follow the shape of `SIGN_IN_2_DIRS`, the `sign-in-2` project, `e2e:sign-in-2`, the `test-sign-in-2.sh` wrapper, the `--project` value in `test-sign-in.sh` and the `live:sign-in-2` case of each pin.
- Keep the hunks a plain union with OCT-epic11 (see Design Notes, "Contention"):
  - in `web/playwright.config.ts`, do not touch lines 37-39 or the `use:` block (lines 59-63, its `trace:` line included);
  - in `ci/iris.sh`, keep line 25 byte-identical;
  - in `web/scripts/e2e-part.test.mjs`, do not touch lines 470-500.
- Make the whole story one commit, which the lead creates.

**Never:**
- Raise or touch any deadline or timeout (`OCUTALON_LIVE_DEADLINE`, `globalTimeout`, the job's `timeout-minutes`).
- Skip, tag or weaken a test.
- Add a group or change the `ci.yml` matrix.
- Edit `docker/tests/test-ci-config.sh`, `web/scripts/ci-results.test.mjs`, any `web/e2e/**` file, `_bmad/` or the spine.
- Give the new project its own `use.trace` (`ci-results.test.mjs` pins that none has one).
- Write an absolute local path into a tracked file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Listing proof | `--list` per project, before and after | sorted(before chromium) = sorted(after chromium + after sign-in-3): 339 = 202 + 137, with no key in both. The other 13 projects' key files are unchanged. | Any diff line fails the story |
| New unit argv | `bash docker/tests/test-sign-in-3.sh --project chromium` | exits 2 with one line `--project is given once, and again as 'chromium'`, and no LOCK line | as sign-in-2's wrapper |
| Listing step | `test-sign-in.sh --project sign-in-3 --part=19/19` (or the wrapper with `--part=19/19`) on a stub npm | the stub records `--silent --prefix web run e2e:sign-in-3 -- --list --reporter=json`, then exit 2 | a failing listing prints `FAIL the sign-in-3 project's spec files could not be listed`, exit 1 |
| Bad project | `--project sign-in-4` | exit 2, one line naming `'sign-in-4'`, the usage line listing `chromium, sign-in-2 or sign-in-3` | before the lock |
| Changed inputs | the push changes only `docker/tests/test-sign-in.sh` | web plus `browser`, `shards-4` and `shards-5` run | — |
| Changed inputs | the push changes only `docker/tests/test-sign-in-3.sh` | web and `shards-5` only | — |
| Integration (Rule 1): `ci/iris.sh` and `ci/changes.sh` read `ci/units.sh` | `bash ci/iris.sh list` | `shards-5` lists `shard:lane-a@Bridge,Agent live:sign-in-3`, and `live sign-in-3` is a known browser unit that installs Chromium | — |

</intent-contract>

## Code Map

- `web/playwright.config.ts`:
  - L9-14: the "Fourteen projects" header, with the chromium and sign-in-2 entries.
  - L40-45: `SIGN_IN_2_DIRS` and its doc.
  - L65-76: the `chromium` project (its `testIgnore` is on L68) and the `sign-in-2` project (its `testMatch` is on L74).
  - Lines Playwright lists in path order: `guide/*`, `heartbeat/heartbeat.spec.ts` and `heartbeat-card.spec.ts` form one contiguous run.
- `web/package.json` L15: `e2e:sign-in-2`.
- `docker/tests/test-sign-in-2.sh`: the wrapper, mode 100755, a header and `exec bash "$(dirname "$0")/test-sign-in.sh" --project sign-in-2 "$@"`.
- `docker/tests/test-sign-in.sh`:
  - L52-56: the header paragraph on the split.
  - L81-127: eight usage and error strings that read `chromium|sign-in-2` or `chromium or sign-in-2`.
  - L95: the accepted values.
  - L134-145: `case $project`. sign-in-2 sets `e2e_script=e2e:sign-in-2 unit_label=t03b unit_name=test-sign-in-2`.
- `ci/units.sh`:
  - L69-86: the comment blocks of the earlier splits.
  - L97-98: the `shards-4` and `shards-5` lines.
  - L150: `BROWSER_UNITS`.
  - L160 and L164: the comment and `WEB_INPUT_PATTERN`, which lists `docker/tests/test-sign-in-2\.sh$`.
  - L196-198 and L212: the comment of `group_input_pattern` and the `live:sign-in-2)` case, which adds `test-sign-in.sh` to the pattern.
- `ci/iris.sh` L24-25: the help text. L24 names the two sign-in scripts. L25, `(and test-sign-in.sh's --project chromium|sign-in-2)`, is OCT-epic11's context line, so it stays byte-identical.
- `docker/tests/test-ci-changes.sh` L177-192: `sign_in_2_group`, plus the `live:sign-in` and `live:sign-in-2` `paths_case` lines. `expect` compares sorted groups.
- `web/scripts/e2e-part.mjs` L2-3 and L9: header comments that name the two projects. The code takes any project.
- `web/scripts/e2e-part.test.mjs`:
  - L236 and L250-259: the bad arguments, and the sign-in-2 wrapper's second `--project`.
  - L335-349: the sign-in-2 listing with the stub npm.
  - L382-390: the sign-in-2 PART-line block run.
  - L529-531: the WEB_INPUT_PATTERN case for `test-sign-in-2.sh`.
- `web/scripts/playwright-projects.test.mjs`:
  - L72-78: a mirror of `SIGN_IN_2_DIRS`.
  - L93-131: the exact listing of chromium and sign-in-2, and the case that the two units are disjoint and their union is complete.
  - L171-174: every spec file on disk is listed by some project.
  - L323-338: the row 18 run stays `--project=chromium` (`api/` stays in chromium).
- Read-only:
  - `docker/tests/test-ci-config.sh` derives everything from `ci/units.sh`. Its synthetic `shards-5` at L1012 is a fixture.
  - `.github/workflows/ci.yml` L111 already has `shards-5`.
  - `web/scripts/ci-results.test.mjs` pins `use.trace`.

## Tasks & Acceptance

**Execution:**
- Before any edit, capture the "before" keys (Verification 1).
- `web/playwright.config.ts`:
  - After L45, add a doc comment and `const SIGN_IN_3_DIRS = ['guide', 'heartbeat'];` and `const SIGN_IN_3_FILES = ['heartbeat-card.spec.ts'];`. The doc says these are a contiguous run of chromium's files in path order; a spec added to these folders joins sign-in-3; and the root file is listed by name because a folder list cannot name it.
  - Add both to chromium's `testIgnore`: `**/e2e/${dir}/**` and `**/e2e/${file}`.
  - After `sign-in-2`, add the project `sign-in-3`: `testDir: './e2e'`, `testMatch` with the dirs' spec glob (as on L74) plus `**/e2e/${file}`, and `use: { ...devices['Desktop Chrome'] }`.
  - In the header, write "Fifteen projects", and add a `sign-in-3` entry in the style of sign-in-2's that cites the 2026-11-07 ruling and the 1,034 s and 1,170 s figures. Update chromium's entry so that it excludes the specs of both.
- `web/package.json`: add `"e2e:sign-in-3": "playwright test --project=sign-in-3"` after `e2e:sign-in-2`.
- `docker/tests/test-sign-in-3.sh` (new, `git add --chmod=+x` or mode 100755): the sign-in-2 wrapper with `--project sign-in-3`, and a header naming the 2026-11-07 ruling, its folders and its file.
- `docker/tests/test-sign-in.sh`:
  - Accept `sign-in-3` on L95.
  - The usage and error strings name `chromium|sign-in-2|sign-in-3`, or `chromium, sign-in-2 or sign-in-3`.
  - Add a `sign-in-3)` case: `e2e_script=e2e:sign-in-3`, `unit_label=t03c`, `unit_name=test-sign-in-3`.
  - Extend the L52-56 paragraph with the third unit.
- `ci/units.sh`:
  - After L86, add a "Split again by the Contest Planner's ruling of 2026-11-07" comment paragraph with the measurements in Design Notes, labelled `(inference)` where they are.
  - Make `shards-5` `shard:lane-a@Bridge,Agent live:sign-in-3`.
  - Add `sign-in-3` after `sign-in-2` in `BROWSER_UNITS`.
  - Add `docker/tests/test-sign-in-3\.sh$` to `WEB_INPUT_PATTERN` after sign-in-2's entry, and name it on L160.
  - Change L212 to `live:sign-in-2 | live:sign-in-3) pattern="$pattern|docker/tests/test-${u#live:}"'\.sh$'"|docker/tests/test-sign-in"'\.sh$' ;;`, and update the L197-198 comment.
- `ci/iris.sh`: change only L24, so that it reads `... only test-sign-in.sh, test-sign-in-2.sh and test-sign-in-3.sh read any: --part k/n, --project sign-in-3`. L25 stays byte-identical, and the two lines together name every value.
- `docker/tests/test-ci-changes.sh`:
  - Find `sign_in_3_group` the same way as `sign_in_2_group`.
  - The `live:sign-in)` case expects `"$grp $sign_in_2_group $sign_in_3_group"`, with a label naming both groups.
  - Make the case `live:sign-in-2 | live:sign-in-3)`.
  - Update the comment at L177-179.
- `web/scripts/e2e-part.mjs`: in the header comments, name sign-in-3, `test-sign-in-3.sh` and `e2e:sign-in-3`.
- `web/scripts/e2e-part.test.mjs`. Extend each sign-in-2 case into a loop over `sign-in-2` and `sign-in-3`; do not paste a copy.
  - Each wrapper's second `--project` exits 2.
  - The stub-npm listing uses `e2e:<project>` for the flag, flag-eq and wrapper forms, and the failing listing names `FAIL the <project> project's...`.
  - The PART block gives `summary=test-sign-in-3[ part k/n]`.
  - `WEB_INPUT_PATTERN` matches `docker/tests/test-sign-in-3.sh`.
- `web/scripts/playwright-projects.test.mjs`:
  - Mirror `SIGN_IN_3_DIRS` and `SIGN_IN_3_FILES`, with an `inSignIn3` helper.
  - chromium's exact list excludes both split projects.
  - Add an exact-list case for `sign-in-3`: each dir holds a spec, each file exists, and the npm script is pinned.
  - Make the disjoint-and-complete case cover three units, at file level and test level (the project names and unique keys).
  - Add `e2e:sign-in-3` to the "every spec file on disk" scripts.

**Acceptance Criteria:**
- **AC1.** Given today's chromium project, when the split is made, then the after-keys of chromium and sign-in-3 together are exactly the before-keys of chromium (202 + 137 = 339, none in both), and every other project's keys are identical.
- **AC2.** Given the new unit, when it is placed and pinned:
  - `shards-5` holds `live:sign-in-3`, and its expected group time stays under 2,100 s (Design Notes);
  - no deadline changed;
  - every pin covers it as it covers `live:sign-in-2`: `BROWSER_UNITS`, `group_units`, `WEB_INPUT_PATTERN`, `group_input_pattern`, test-ci-changes, e2e-part and playwright-projects;
  - `bash ci/iris.sh list` shows it.
- **AC3.** Given the change, when the lead pushes it, then `bash docker/tests/test-boundaries.sh` passed first, and full CI is green on every workflow (lead's gate).
- Standing (Rule 19): every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs.**
- **AD-22:** `ci/iris.sh` stays the one recipe. Every unit runs on its own throwaway, and `ci/units.sh` stays the one list.
- **AD-29:** the files are Lane B's, and `guide/telegram-drawer*.spec.ts` is only routed by the config, not edited.

Neither AD's Rule changes. The spine names no sign-in unit, so it needs no amendment.

**Consumes.**
- The 2026-11-05 split: `test-sign-in.sh --project` and its setup.
- Story 4.11's more-to-try tests.

**Consumed-by:** CI's `iris (shards-5)` job, through `ci/iris.sh group shards-5`, and `ci/changes.sh --group`.

**Extends (Rule 2).**
- `SIGN_IN_3_DIRS` and `SIGN_IN_3_FILES` follow `SIGN_IN_2_DIRS`.
- The wrapper is the sibling's one exec line. Each unit is `docker/tests/test-<name>.sh`, so a copy of the wrapper is required.
- The pins extend each sign-in-2 case into a loop or a `|` case.

**Measurements (the lead's; recorded, not re-derived).**

Groups on 5b47f052 (ci run 42393186349):

| Group | Seconds | Units |
| --- | --- | --- |
| `browser` | 2,104 | demo-path 627, sign-in 1,034, answers 442 |
| `shards-4` | 1,897 | `shard:lane-a@Channel` 729, `live:sign-in-2` 700, `live:memory-offline` 468 |
| `shards-5` | 1,247 | `shard:lane-a@Bridge,Agent` 1,246 |

On 623b9cb0 (ci run 42392984136), `live:sign-in` took 1,170 s. The other groups took, in seconds:

| Group | Seconds |
| --- | --- |
| `shards` | 1,835 |
| `shards-2` | 2,268 |
| `shards-3` | 1,852 |
| `image` | 1,821 |
| `production` | 1,614 |
| `install-fresh` | 1,808 |
| `install-upgrade` | 1,916 |

Per-spec seconds from 623b9cb0's SPEC lines, about 850 s of browser run in all, plus about 260 s of build, start and setup per unit:

| Project | Specs (seconds) | Total |
| --- | --- | --- |
| `sign-in-3` | guide/ 198 (more-to-try 127), heartbeat/ 33, heartbeat-card 198 | about 429 s |
| `chromium` (what stays) | api 23, banners 71, chat 145, documents 30, frame 25, persona-approval 26, persona-card 46, sign-in 12, trace 43 | about 421 s |

**Placement.**
- Each unit is about 690 s (inference).
- `browser` becomes about 1,750 s (inference).
- Only `shards-5` has room for about 700 s. Its 1,247 + about 700 is about 1,950 s, 32.5 minutes (inference until a run measures it); a job adds about 30 to 40 s.
- Every other group plus 700 s passes 2,100 s.
- Flag: Story 19.4's `live:documents`, planned for `shards-5` with an unknown size, then needs another home.

**Listing today (measured at planning, 2026-11-07, this tree):**

| Project | Tests | Spec files |
| --- | --- | --- |
| `chromium` | 339 | 24 (`guide/` 121, `heartbeat/` 1, `heartbeat-card` 15) |
| `sign-in-2` | 129 | 13 |
| `demo-path` | 28 | |
| `demo-switch` | 26 | |
| `floor` | 69 | |
| `answers` | 23 | |
| `cards` | 28 | |
| `floor-firefox` | 19 | |
| `floor-webkit` | 19 | |
| `online-demo` | 53 | |
| `online-session` | 13 | |
| `online-allowance` | 12 | |
| `online-demo-path` | 10 | |
| `online-visitors` | 1 | |

No project has a duplicate key. After the split, chromium has 202 tests in 18 files, and sign-in-3 has 137 in 6.

**Contention (Rule 11).** `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` lists no `ci/`, `docker/tests/`, `web/` or workflow file for OCT-epic4, OCT-epic19 or OCT-epic39. OCT-epic11 (623b9cb0) touches these files:

| File | OCT-epic11's hunks | This story's hunks |
| --- | --- | --- |
| `web/playwright.config.ts` | inserts after L36 and L38, changes L61 (`trace:`) | L9-14, after L45, L68, after L76 |
| `ci/iris.sh` | inserts after L25 | L24 only |
| `web/scripts/e2e-part.test.mjs` | L483-499 | L236-259, L335-390 and L529 |
| `docker/tests/test-ci-config.sh` | its own hunks | untouched |
| `web/scripts/ci-results.test.mjs` | its own hunks | untouched |

The base of these files is identical on both sides (merge base 4c9bed21), so the line numbers hold.

This story's files:
- shared with OCT-epic11: `web/playwright.config.ts`, `ci/iris.sh` and `web/scripts/e2e-part.test.mjs`;
- in no other epic's diff: `web/package.json`, `docker/tests/test-sign-in-3.sh`, `docker/tests/test-sign-in.sh`, `ci/units.sh`, `docker/tests/test-ci-changes.sh`, `web/scripts/e2e-part.mjs` and `web/scripts/playwright-projects.test.mjs`.

**Decided in-stage.**
1. The cut is the lead's balanced one.
2. The project is named `sign-in-3` and its label is `t03c`.
3. The root file is named in a separate `SIGN_IN_3_FILES` list rather than by a glob, because a folder list cannot name it and an explicit name is what a pin can state.
4. Only L24 of the `ci/iris.sh` help changes, so that L25 merges cleanly with OCT-epic11.
5. The repeated spec glob is not factored into a helper, because that would touch sign-in-2's line for no gain.
6. The epic context was reused as the dispatch asked. Its mtime is older than `epics.md`'s checkout mtime, but its content is fresh.

**Known parity gap (not new).** No check pins the wrappers' membership in `BROWSER_UNITS`. That is true for sign-in-2 too, because the wrappers do not call npm themselves. CI's first `shards-5` run proves Chromium is installed.

**Risk (inference).** A sign-in-3 spec that leaned on state left by an earlier chromium file in the same stack would go red in CI. That is a hermeticity defect, and it takes the failed-CI path.

## Verification

**Commands.** Run from the worktree root, in a shell where `env | grep ^OCUTALON_` prints nothing, with `SCR=<scratchpad>/e32s5impl` (`mkdir -p "$SCR"`). Define the helper once per call:

```bash
keys() { (cd web && npx playwright test --project="$1" --list --reporter=json) | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const o=[];const w=(s,t)=>{for(const sp of s.specs??[])for(const x of sp.tests)o.push(`${sp.file} › ${[...t,sp.title].join(" › ")}`);for(const c of s.suites??[])w(c,[...t,c.title])};JSON.parse(d).suites.forEach(s=>w(s,[]));console.log(o.join("\n"))})' | LC_ALL=C sort; }
P="chromium sign-in-2 demo-path demo-switch floor answers cards floor-firefox floor-webkit online-demo online-session online-allowance online-demo-path online-visitors"
```

1. `(once)`, before any edit, about 15 s: `for p in $P; do keys $p > "$SCR/before-$p.keys"; done; wc -l "$SCR"/before-*.keys`. Expected: the counts in Design Notes (chromium 339).
2. `(once)` after the edits, about 15 s: `for p in $P sign-in-3; do keys $p > "$SCR/after-$p.keys"; done; diff "$SCR/before-chromium.keys" <(LC_ALL=C sort "$SCR/after-chromium.keys" "$SCR/after-sign-in-3.keys") && [ -z "$(LC_ALL=C comm -12 "$SCR/after-chromium.keys" "$SCR/after-sign-in-3.keys")" ] && for p in $P; do [ $p = chromium ] || diff -q "$SCR/before-$p.keys" "$SCR/after-$p.keys" || echo "CHANGED $p"; done; wc -l "$SCR/after-chromium.keys" "$SCR/after-sign-in-3.keys"`. Expected: no diff output and no `CHANGED`, with 202 and 137 lines. Record the output in this section.
3. `(loop)`, about 6 s: `node --test web/scripts/playwright-projects.test.mjs web/scripts/e2e-part.test.mjs`. Expected: everything passes.
   - mutation: remove `...SIGN_IN_3_FILES.map(...)` from chromium's `testIgnore`. Then the playwright-projects case "share no spec file" goes red (`heartbeat-card.spec.ts` is in both).
4. `(loop)`, about 20 s: `bash docker/tests/test-ci-changes.sh`. Expected: every PASS, 0 failed.
   - mutation: change L212 of `ci/units.sh` back to `live:sign-in-2)`. Then "the script of live:sign-in runs web, browser, shards-4 and shards-5" goes red.
5. `(once)`, about 35 s: `bash docker/tests/test-ci-config.sh`. Expected: 0 failed, unchanged.
6. `(once)`: `bash docker/tests/test-boundaries.sh` and `npm --prefix web run lint`. Expected: both pass.
7. `(once)`: `bash ci/iris.sh list | grep -n 'sign-in'`. Expected: `live:sign-in-3` appears under `shards-5`.
8. Optional `(once)`, not required (the lead's CI run proves the unit): with lane A's variables (`OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a`, `OCUTALON_TEST_WEB_PORT=52801`, `OCUTALON_LOCK_OWNER='epic=32 stage=implement'`, `OCUTALON_RUN_TAG=e32s5i`), run `ci/iris.sh build`, then `ci/iris.sh live sign-in-3`, one per call with `timeout: 600000`, then `ci/iris.sh teardown`. Expected: PASS within 10 minutes. If it is close to the cap, skip it.

**Shared surfaces:**
- the chromium project's file list;
- the project list of `web/playwright.config.ts`;
- `BROWSER_UNITS`;
- `group_units shards-5`;
- `WEB_INPUT_PATTERN`;
- `group_input_pattern` for `browser`, `shards-4` and `shards-5`;
- the usage line of `test-sign-in.sh`.

Every test that asserts these is listed in the Code Map and updated by the tasks above.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
