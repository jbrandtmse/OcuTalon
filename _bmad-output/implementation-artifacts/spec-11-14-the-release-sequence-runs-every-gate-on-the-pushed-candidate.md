---
title: 'Story 11.14: The release sequence runs every gate on the pushed candidate'
type: 'feature'
created: '2026-11-08'
status: 'done'
baseline_revision: '99871262b4641bce095097efd3727fdb8ab2805f'
baseline_commit: '99871262b4641bce095097efd3727fdb8ab2805f'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `release/release.sh` cuts, checks and pushes a candidate (`cut image overview ipm ipmcheck push notes`), then stops with `no gate has run (not a release)`. For 1.0.0 to 1.0.4 the Contest Planner ran every gate by hand (`release/records/1.0.0/rc4.md`, "Hand gates"), and `notes` fails on 1.0.3 and 1.0.4 because no gate ran (`release/records/1.0.4/rc1.md`). Nothing runs the gates on the pushed candidate, writes their results into the record, stops at the gate that failed, or refuses a candidate with an enabled stub. No workflow runs on a `release/*` push either, so the pushed candidate gets no CI run.

**Approach:** Add the gate steps to `STEPS`. The new order is `cut stubs image overview ipm ipmcheck push ci eval upgrade rehearsal notes checklist hands-on`.
- Each gate step calls the gate's own script from the candidate's tree, or reads its verdict, and judges it. One call does at most one gate phase. The step writes its row into `## Release sequence`, and the gate writes its own section.
- The first gate that does not pass stops the sequence and names that gate. This uses the stop routine that already exists.
- `hands-on` is a stop that never passes. Story 11.15 makes it resumable.
- `"release/*"` joins the push branches of both workflows. This story takes epics.md Story 11.14's two criteria and DW-548.

## Boundaries & Constraints

**Always:**
- **Conventions of `release.sh` stay** (its header, lines 1-50):
  - Bash 3.2, ASCII, mode 100755, `umask 077` and the main guard.
  - Each step prints one line: `PASS|FAIL|WAIT <step> <detail>`.
  - The stop routine records and commits only the record (explicit pathspec), then asks `record`.
  - Answers come only from stdin. No value of the environment is printed.
  - Exactly two pushes, never a force push, a tag or `main`. A gate step asks nothing and pushes nothing.
- **Exit codes keep their meaning:** 0, 1, 2, 4 and 5 (`WAIT`, nothing recorded, the step runs again).
  - Exit 5 also covers CI that has not finished and an evaluation that has not run yet.
  - A gate phase that is done exits 0 with `NEXT <step>`, and the step stays current.
- **Gate verdict (no false all-clear).** A gate with its own script and section (`upgrade`, `rehearsal`, `checklist`) passes only when all of these hold:
  - the script exits 0;
  - its section reads `Result: pass`;
  - the section's `Candidate:` line ends with ` at <the cut's full sha>`;
  - for `upgrade` the section reads `Mode: release`, and for `rehearsal` it reads `Mode: rehearsal`.
  - Anything else is `FAIL <gate> ...`. A gate that did not run, or a CI run that was not found, is never a pass.
- **One override.** REL-5's override is the only one. It lives in the evaluation's result file (`verdict: overridden` with a non-blank `override.reason`, written by `eval/run.sh --override`). No option, environment variable, configuration key or record line skips, forces or passes a gate.
- **Gates run the candidate's own scripts in clones of the author's repository.** Each gate uses its own folder in the state folder: `<state>/gate-upgrade`, `<state>/gate-rehearsal`, `<state>/gate-checklist` and `<state>/eval`.
  - Each clone is made with `git clone --branch release/<v>-rc<n>` from the author's repository (no network). All local tags are copied in, and HEAD must equal the cut's sha.
  - Each gate gets the record and the notes draft as absolute paths. The author's checkout is never switched.
- **The evaluation is the author's command.** The sequence never reads, holds or passes a model key.
- **Tests run only against throwaway repositories with local bare remotes, the existing npm, node and docker shims, and a `gh` shim** that answers from fixture files and logs its arguments. Neither the real `gh` nor GitHub is ever reached.

**Never:**
- Act outward in any form, here or in any test:
  - no pull request, push to origin, `main`, `release/**` or `rehearsal/**`, tag or publish;
  - no contact with the demo host;
  - no run of the real release sequence;
  - no real model key (`ANTHROPIC_API_KEY` stays unset);
  - no install from the public IPM registry.
- Record a hands-on pass, or let `hands-on` pass (11.15's gate; REL-7 belongs to the Planner and the owner).
- Call `gh` with anything but `run list`.
- Depend on `_bmad/`, for example `_bmad/scripts/ci-gate.py`.
- Change `release/upgrade-harness.sh`, `release/rehearse.sh`, `release/checklist.sh`, `eval/`, `ci/units.sh`, `ci/iris.sh`, `ci/warm.sh` or `docker/tests/lib-live.sh`.
- Rewrite lines that Epic 0 edits: `release/release.sh` `step_image` (around line 575), and `docker/tests/test-release-sequence.sh` line 511 (mkseed's archive list) and line 200 (the shim's Dockerfile message).
- Change anything in `.github/workflows/*` except the one push-branch line in each file. Never add `rehearsal/*` (U-203).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stub enabled | An item of a non-test `XData ProductionDefinition` (path without `/Test/`) under `src/`, enabled (`Enabled` is `true` or `1`, or absent). Its `ClassName` class, or an in-tree superclass, carries `Parameter STUB = 1`. Superclasses go left to right, depth-first; a class's own value wins | `FAIL stubs <Production>:<Item> (<Class>) answers "not implemented"; ...` for each such item. Exit 1, record committed, no `push` ASK, remote unchanged | A scan that prints no `COUNTS` line: `FAIL stubs the production classes could not be read` |
| No stub enabled | The real tree (no product class has `STUB = 1`) | `PASS stubs` with the item and production counts | -- |
| CI green | `gh run list --repo <r> --branch release/<v>-rc<n> --commit <sha> --event push --limit 50 --json databaseId,workflowName,status,conclusion,headSha`. Newest run of each workflow (highest `databaseId`); every one is `completed`/`success`, and `ci` and `lane-a` are among them | `PASS ci` naming each `<workflow> run <id>` | -- |
| CI pending | A run that is not `completed`, or `ci`/`lane-a` absent less than 900 s after the step's first check (state `ci_first`, seam clock) | `WAIT ci ...`, exit 5, nothing recorded, no ASK | `gh` exits non-zero: `WAIT ci gh could not read the runs ...` |
| CI red or missing | A completed run that is not `success` (judged first); or `ci`/`lane-a` absent 900 s or more after the first check | `FAIL ci <wf> run <id> concluded <c>` / `FAIL ci no <wf> push run on <sha> ...` | `gh` missing: FAIL. The repo is not GitHub and there is no seam: FAIL |
| Eval not run | No `<state>/eval/eval/release-candidate.json` | The clone is made once (never replaced while the step is current). `WAIT eval ...` and one `RUN` line with the author's command; exit 5 | -- |
| Eval acceptable | `format` `ocutalon.evalResult/1`; `commit` the full cut sha; `onMock` false; `treeClean` true; `verdict` `pass`, or `overridden` with a non-blank `override.reason` | `PASS eval`. The row reads `pass: <decidedBy>` or `overridden (REL-5): <reason>`. The file is copied to `<state>/release-candidate.json`, which `notes` passes as `--eval` | -- |
| Eval not acceptable | `blocked`; `incomplete`; on the mock; another commit; a dirty tree; another format; unreadable; `overridden` with no reason | `FAIL eval <which>`. For `blocked`, a `RUN` line names `eval/run.sh --override "<reason>"` in the clone | The next `next` reads the file again |
| Upgrade drive | `next` repeatedly; fixed tag `rel-<v with dots as hyphens>-rc<n>-upg` | One phase per call in `<state>/gate-upgrade`: `build` (with `--version --rc --record <abs>`), then `settings`, `seed`, `upgrade`, `restart`, `storage`, then `report` and `down` in one call. Each phase after build runs even after an earlier failure. A phase call prints `PHASE upgrade <phase> exit <n>` and exits 0 with `NEXT upgrade`; after `seed` it also prints the NOTE line | Remote `v*` tags missing locally: FAIL before `build`. A failed `build`, or exit 2 from any phase: `down`, then FAIL. 75: WAIT, same phase. `down` non-zero: WARN line |
| Rehearsal drive (DW-548) | `next` repeatedly; fixed tag `...-reh`; the clone `<state>/gate-rehearsal` | `rehearse.sh run --version <v> --rc <n> --candidate release/<v>-rc<n> --record <abs> --runs 20`, the same options on every call, never `--plant` or `--dry-run`. Exit 4: `PHASE rehearsal <its NEXT run: text>`, exit 0, `NEXT rehearsal` | 75: WAIT. 2: FAIL with the REFUSED text, then `rehearse.sh down`. 3: FAIL (a dry run is never a pass). 1 or other: FAIL |
| Checklist | After `notes`, in a fresh `<state>/gate-checklist` | `checklist.sh --version --rc --candidate release/<v>-rc<n> --record <abs> --notes <abs draft>`. Its `CONFIRM` and `LATER` lines are printed as they are | Exit 1: `FAIL checklist Result: <fail or not confirmed>: <first FAIL line or count>`. Exit 2: FAIL refused |
| Hands-on | Every automated gate passed | The STOPPED line (Public text), exit 4. Row `hands-on \| waiting`, record `Result:` hands-on text, committed, ASK `record` | Never PASS; each later `next` stops the same way |
| Override attempt | `start` or `next` with `--skip`, `--force` or `--override x`; a planted `Result: pass` in a section whose gate exited 1; exit 0 with `Result: fail`; another sha; another `Mode:` | Exit 2 for the options (already met). FAIL for the rest | -- |

</intent-contract>

## Code Map

**`release/release.sh`** (1376 lines; the Planner reviews every hunk):
- `:1-50` header. `:59` `STEPS`.
- `:91` `next_step`. `:106` `clock` (the seam).
- `:205-241` `record_render`. It renders a row for every id in `kit $STEPS record`, so new steps' rows appear with no change.
- `:337-425` `stop_routine` (kinds `end|stopped|failed`; end text `:342`).
- `:443` `step_fail`, which strips local paths from details.
- `:611` `candidate_export`, which `stubs` reuses.
- `:629` `candidate_lock_dir`. `:643-690` `step_overview`: the template for running a candidate's own unit (lock dir, 75 gives WAIT, the log kept on failure with a `LOG` line).
- `:959-1018` `step_ipmcheck`: run tag and teardown.
- `:1020-1059` `step_push`. `:1061-1093` `step_notes` (`:1064`: add `--eval`).
- `:1172-1212` `cmd_next`: 0 advances, 4 stops, 5 exits 5, anything else fails.
- `:1242` and `:1362`: unknown options are refused.
- Sources `docker/tests/lib-live.sh`, which has `ensure_web_bundle` `:165-193` (`npm ci` when `web/node_modules` is missing) and `live_lock_dir`.

**`release/lib-release.sh`** (424 lines):
- `env_get` and `env_set` `:69-77`; `detail_clean` `:79`; `release_state_dir` `:85`.
- `record_path`, `notes_path` and `candidate_branch` `:342-346`.
- `release_tags [<remote>]` `:349`: local tags plus the remote's.
- `release_previous_tag` `:376`; `record_write` `:392`.

**`release/notes.sh`:** `notes_section` `:280-286` is a `## ` section reader. It moves to `lib-release.sh` as `record_section`. `--eval <file>` takes an `ocutalon.evalResult/1` result and prints the override reason (REL-5).

**Gate contracts (read only):**
- `release/upgrade-harness.sh`:
  - header `:1-50`: phases, `OCUTALON_RUN_TAG`, 540 s per phase, exits 0/1/2/75.
  - `cmd_run` `:1955-1978`, the phase order: build, then settings to storage regardless, then report and down.
  - the previous build: the highest `v*` tag merged into HEAD, so the clone needs the tags.
  - the section `:437`: `Candidate: <v> at <sha>`. `Mode: release` needs a clean tree (`:172`, `:544`).
  - R1 fails when the upgrade begins after its due time (`:1528`), so `seed` and `upgrade` run back to back.
- `release/rehearse.sh`:
  - header `:1-150`: `run` does one phase per call and needs `OCUTALON_RUN_TAG`. It exits 4 until the last phase. Exits are 0 real pass, 1, 2, 3 dry run and 75.
  - real mode needs `release.conf`, a local driver and `--runs` of 20 or more. The runs need `web/node_modules`.
  - the section's `Candidate:` is at `:1252`.
- `release/checklist.sh` header `:1-50`: `--candidate` is HEAD; absolute paths are allowed (`:586-587`); `Candidate:` is at `:509`; exits 0, 1, 2; `CONFIRM` and `LATER` lines.
- `eval/run.sh` header `:1-125`: `--release-candidate` writes `eval/release-candidate.json` (exits 0, 3 blocked, 4); `--override "<reason>"` needs only Node and starts no container.
- `src/ocutalon/cls/OcuTalon/Eval/Gate.cls:25,316-325`: fields `format, commit, branch, treeClean, onMock, verdict, decidedBy`.
- Productions: `src/ocutalon/cls/OcuTalon/Production.cls`, `Demo/Orders/Production.cls`, `src/bridge/cls/OcuTalon/BridgeExample/Production.cls`. Today no product class has `Parameter STUB = 1` (only `Test/Schedule/ChecksStub.cls`), and no production class uses `Inheritance = right`.

**CI:**
- `.github/workflows/ci.yml:13-17` and `lane-a.yml:16-20`: the push branches.
- `docker/tests/test-ci-config.sh`: description `:6`, required set `:204`, good sample `:339-342`, bad samples `:402-409`, rule text `:550`.
- `gh` 2.98 `run list` JSON fields include `databaseId, workflowName, status, conclusion, headSha` (`gh run list --help`, offline). `conclusion` is empty until the run is completed (measured 2026-11-02 by the set-aside pass).

**Self-test `docker/tests/test-release-sequence.sh`** (3060 lines, 29 rules; named rules run alone):
- `mkshims` `:152-401`: node only answers `--version` (`:171-178`); gh is a network marker (`:397-400`).
- `stub_text` and `set_stub` `:427-502`: the pattern for the gate stubs. `mkseed` `:504-539`. `newcase` `:557`. `rs` `:583`. `to_step` `:609-623`.
- `t_gate` `:1478` (end text `:1506`). `forbidden_scan` `:1511`. `t_secret` (`:1566`: no network marker). `t_static` `:2866` (STEPS pin around `:2880`). The rule list is at `:3027-3053`.

**For reference only, never applied:** `_bmad-output/implementation-artifacts/set-aside/11-14-...-1.patch`. Its `production_stubs`, `step_ci` and `gate_verdict` met an earlier review (Design Notes, "Harvested"). Its intent block states rehearse.sh's old contract (DW-548).

## Tasks & Acceptance

**Execution:**
- **Task 0 (implement; the figures go into `## Verification`):**
  - Run `production_stubs src` on the real tree: give its counts and confirm it passes. Then on a scratch copy where `Channel/Telegram/In.cls` has `Parameter STUB = 1;` and TelegramIn is `Enabled="true"`, and again with the attribute removed: it must report the item.
  - In a throwaway of the self-test, record the exit code, the line and the docker calls of the real `rehearse.sh run` with no `release.conf`.
  - Time the real `upgrade-harness.sh build` with the shims. If `build` finishes within 20 s with the existing shims, IA4 uses the real harness; otherwise IA4 uses the stub and the pinned phase list.
- `release/lib-release.sh` -- add these, each with a header line, and leave the existing functions unchanged:
  - `record_section <file> <heading>` (moved from `notes_section`) and `record_field <file> <heading> <field>`, which prints the text after `<field>: ` on the section's first such line;
  - `production_stubs <tree>`: `FOUND|<production>|<item>|<class>` lines, then `COUNTS|<items>|<productions>|<stub items>|<enabled stubs>`. Status 1 when an enabled stub is found, 3 when the scan failed;
  - `candidate_clone <dir> <branch> <sha> [web]`: the clone as described under Always, with `web/node_modules` through `ensure_web_bundle` when `web` is given;
  - `gh_repo <remote>`: `owner/repo` from a github.com https or ssh URL. When the remote's URL is a local path, it uses `OCUTALON_RELEASE_GH_REPO` (`owner/repo`); otherwise it fails;
  - `ci_runs <repo> <sha> <event> <branch>`: the `gh run list` call of the Matrix, parsed with `node -e` into `id<TAB>workflow<TAB>status<TAB>conclusion` lines, only those with `headSha` equal to `<sha>`.
- `release/notes.sh` -- `notes_section() { record_section "$@"; }`. Nothing else changes.
- `release/release.sh` -- make these changes:
  - the header: the steps line, the exit lines and a new "The gates" paragraph (Public text);
  - `STEPS`;
  - the functions `step_stubs`, `step_ci`, `step_eval`, `step_upgrade`, `step_rehearsal`, `step_checklist` and `step_hands_on` (`${step//-/_}`), with `gate_verdict <section> <mode|->`. Add them as new functions after `step_notes`;
  - in `cmd_next`: the step's function is looked up and called as `step_${step//-/_}` (both the `type` check and the call); return 3 prints `NEXT <step>` and exits 0 with no `row_set`; return 6 calls `stop_routine hands`;
  - in `stop_routine`: the `hands` kind (exit 4) and the new end text;
  - in `step_notes`: `--eval "$sdir/release-candidate.json"`.
  - Each gate keeps its output in `<state>/<gate>.log` and prints `LOG <gate> <absolute path>` after a FAIL line, as `step_overview` does. A clone is removed when its gate ends; the eval clone is removed only after `eval` passes. Every row and detail goes through `step_fail` and `detail_clean`.
- `.github/workflows/ci.yml`, `.github/workflows/lane-a.yml` -- add `      - "release/*"` after `"OCT-epic*"`.
- `docker/tests/test-ci-config.sh` -- add `release/*` to the required set (`:204`), the good sample and the descriptions (`:6`, `:550`), and add the bad sample `trigger-no-release` to the `triggers` rule.
- `docker/tests/test-release-sequence.sh` -- extend it; no new `CHECK_SCRIPTS` entry:
  - **Shims.** The node shim runs the real node for `-e`. The gh shim answers `run list` from `$SHIMSTATE/gh-runs.json`, logs to `$SHIMLOG/gh.log`, and marks the network marker for any other form.
  - **The seed's integration branch holds stub gate scripts.** Stubs for `upgrade-harness.sh`, `rehearse.sh` and `checklist.sh` log their argv, tag, folder and HEAD, and write their section from a flag-selected fixture. Seed variants keep the real scripts for the IA rules. New lines in mkseed go after line 535 (`eval/run.sh` is added there for IA2).
  - **The fixture driver `to_gate <step>`** takes a case to any step, gates included (green `gh` runs, a passing eval file in `<state>/eval/eval/`). Update `to_step` for `stubs`, and update every rule that passes `push` (`notes`, `gate`, `secret`, `pushes`, `word`, `resume`, `record`, `hands`) for the new steps. Update the STEPS pin in `t_static` and the end text in `t_gate`.
  - **New rules:** `stubs`, `ci`, `eval`, `upgrade`, `rehearsal`, `checklist`, `handson`, `gates` (AC1, AC5) and `realgates` (IA1 to IA4). A static pin checks that `step_upgrade`'s phase list equals `cmd_run`'s, that the `CI_WORKFLOWS` names equal the `name:` lines of the real workflows, that no gate step ASKs, and that `gh` appears only as `gh run list`.
- After the edits, run `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml`.

**Acceptance Criteria:**
- **AC1 (order, stop, record; REL-1, REL-6).**
  - Given a throwaway candidate and fixtures where gate G fails, for each G in `stubs ci eval upgrade rehearsal checklist`, when `next` reaches G, then:
    - it prints `FAIL G ...` and exits 1;
    - the committed record reads `Result: failed at G: ...` with G's row;
    - no later gate ran (stub logs);
    - the next `next` runs G again.
  - Given every gate green, the rows `stubs` to `checklist` read `pass`, in STEPS order.
- **AC2 ("not implemented"; REL-1, AD-29).** Given a candidate tree with an enabled stub item (the Matrix's three forms), when `stubs` runs, then its FAIL line comes before any `push` ASK and the bare remote is unchanged. The real tree passes, and classes under `/Test/` are not scanned.
- **AC3 (full CI).** Given the `gh` shim, when `ci` runs, then the rows CI green, CI pending and CI red or missing hold. The clock seam drives the 900 s, and `gh.log` holds only `run list` calls that name `--repo`, `--branch release/1.0.0-rc1` and `--commit <cut sha>`.
- **AC4 (evaluation and REL-5; CON-2).** Given each eval fixture of the Matrix, when `eval` runs, then its row and exit follow the Matrix. Only `pass` and `overridden` with a reason pass.
- **AC5 (the only override).** Given the Matrix's override attempts, when they are made, then the options exit 2, and every planted, mismatched or wrong-mode section FAILs its gate.
- **AC6 (upgrade drive; AD-5).** Given stub phases, when `next` runs repeatedly, then:
  - the phases run one per call in `cmd_run`'s order under one tag, and only `build` gets the options;
  - `down` always runs, a 75 repeats the phase, and missing tags fail before `build`;
  - it passes only on the verdict rule (`Required: no` relaxes nothing).
- **AC7 (rehearsal drive; DW-548, REL-6).** Given a stub `rehearse.sh run` that exits 4 three times, then 0, when `next` runs repeatedly, then:
  - each call passes the same argv and tag, and exit 4 gives `PHASE` and exit 0;
  - exits 2, 3, 1 and 75 follow the Matrix;
  - only exit 0 with the verdict rule passes.
- **AC8 (checklist, then hands-on; REL-7, CON-5).** Given every gate before it passing, when the steps run, then:
  - `checklist` runs after `notes`, in its clone, with the absolute record and draft;
  - `hands-on` prints the STOPPED line, exits 4 and commits the record with the hands-on `Result:`;
  - no output or record line says the release passed.
- **AC9 (CI on the candidate).** Given the edited workflows, when `test-ci-config.sh` runs, then it passes. With `"release/*"` removed from either workflow, `triggers` fails.
- **IA1 (consumes the real `checklist.sh`).** Given a record with no `## Author confirmations`, when `checklist` runs the real script, then:
  - the row is the script's own `fail` or `not confirmed`;
  - `## Release checklist` is in the record;
  - the other rows of `## Release sequence` are unchanged.
- **IA2 (consumes the real `eval/run.sh --override` and `notes.sh`).** Given a blocked fixture in `<state>/eval` that the real `eval/run.sh --override "fixture reason"` turns into overridden, when `eval` runs and then `notes`, then the row reads `overridden (REL-5): fixture reason`, and the real draft carries that reason.
- **IA3 (consumes the real `rehearse.sh`).** Given no `release.conf`, when `rehearsal` runs the real script, then it prints `FAIL rehearsal` with the script's own refusal and starts no container (the docker shim log).
- **IA4 (consumes the real harness phases, per Task 0).** Given the real `upgrade-harness.sh` with the shims, when `upgrade` runs, then `build` passes, the other phases' failures are the harness's own, `## Upgrade harness` reads `Result: fail` with the cut sha, the gate FAILs, and `down` ran. If Task 0 rules out the real harness: the stub with the pinned phase list.
- **Standing.** Every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

- **planner-2026-11-09-11.14** (the Contest Planner's rulings, relayed by the orchestrator, 2026-11-09):
  1. PUBLIC TEXT approved as written (`### Public text`), with one change, applied: the STOPPED hands-on line and the hands-on record row say "the author's hands-on pass (REL-7)" instead of "the Contest Planner's hands-on pass (REL-7)", matching the file's existing "the author" wording. The existing ipmcheck WARN line is left alone.
  2. The `release/*` push trigger on `ci.yml` and `lane-a.yml`: yes. `release/*` only, never `rehearsal/*` (U-203); the `test-ci-config.sh` descriptions exactly as in `### Public text`.
  3. Timing: Epic 11 part 2 targets 1.0.6. This story's merge is held until after the 1.0.5 cut; every release/** hunk and the two workflow hunks go to the Planner verbatim once the head is green.
  4. Contended: Epic 0's Story 0.15 edits `release/release.sh` around line 575, `release/upgrade-harness.sh` and `ci/warm.sh`; the gate functions stay off those lines (as planned).

## Review Triage Log

### 2026-11-08 — Review pass
- verdicts: 39 findings (grouped by root cause in the rows below; layers: blind 10, edge 15, gap 11, intent 3) — high 0, medium 4, low 35, false 0, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind 1, Edge 1, Gap "other": an empty scan (class files, no production definition) passed `stubs` with "0 enabled items in 0 productions" — verified: `COUNTS|0|0|0|0`, status 0. Fixed: no `COUNTS` line when no production is read (status 3); new `stubs` case "no production"; mutation line added.
  - `[medium]` `[patch]` Edge 2, Gap 1: a `Parameter STUB = 1;` line with a trailing `//` comment, with `[ ... ]` keywords or indented was missed — verified by the gap layer's scratch run (3 of 4 forms unreported). Fixed in `production_stubs`; three forms added to the `stubs` rule; mutation line added.
  - `[medium]` `[patch]` Gap 4 (IA4 text unobservable; its mutation not caught by its own test): the Matrix ("down, then FAIL") and IA4 (`## Upgrade harness` reads `Result: fail`) are both met when `report` runs before `down` on exit 2 of a phase after `build`. Fixed in `step_upgrade`; the stub test now expects `build settings seed report down`; IA4 asserts the section; the IA4 mutation line points at the skipped `report`.
  - `[medium]` `[patch]` Gap 2: `candidate_clone`'s "HEAD must equal the cut's sha" was pinned by no test. Added a moved-branch case to `checklist` (FAIL before the gate script runs); mutation line added.
  - `[low]` `[patch]` Gap hermeticity: `t_gates` unset ambient `CI` and other names. Fixed: the values are saved and restored.
  - `[low]` `[patch]` Gap weak assertions, Blind 9: `gate_ran eval` could not see the eval clone; unused `later` and `to_gate`. Fixed (clone or result file counts as "ran"; the unused variable and alias removed).
  - `[low]` `[patch]` Gap IA3: `has "config"` matched any line. Tightened to `refused: config: `.
  - `[low]` `[patch]` Blind 6, Edge 13, Gap "other": the "one read command" pin lost its bite. Now matches `read` in command position.
  - `[low]` `[patch]` Edge 14 (claim): the PASS ci detail from `gh` data skipped `detail_clean`. Fixed in `step_ci`.
  - `[low]` `[reject]` Blind 2, Edge 4: a missing `node` in `ci_runs` reads as a missing gh, a bad JSON answer waits — node is a precondition of the whole sequence (`step_eval` needs it too); a wrong word in a message that fails closed.
  - `[low]` `[reject]` Blind 3, Edge 8, Gap "other": `rehearse.sh down` only after exit 2 — the Matrix lists exit 3, 1 and other as FAIL without `down` (spec-bound, by-design); the script tears down its own run at its last phase.
  - `[low]` `[reject]` Blind 3 (exit 4 without a bound or without a `NEXT run:` line), Edge 9: no realistic path; `rehearse.sh` exits 4 only with a `NEXT run:` line and ends after its fixed phases.
  - `[low]` `[reject]` Blind 4, Edge 6, Gap "other": `ci_first` is never cleared and is set before the first gh read — the Matrix counts the 900 s from the step's first check (spec-bound); a push that starts no run is re-cut, as the Planner's notes say.
  - `[low]` `[reject]` Edge 5: gh failing for good waits forever — the Matrix says `WAIT ci gh could not read the runs` (spec-bound).
  - `[low]` `[reject]` Blind 5: malformed eval fields give a misleading message — the gate fails closed either way; the fix adds branches for a message.
  - `[low]` `[reject]` Blind 7: `gh_repo` rejects ssh host aliases and Enterprise hosts — the spec names github.com https and ssh forms; a failing gate says the remote is not a GitHub repository.
  - `[low]` `[reject]` Blind 8, Edge 11: only the first stub item reaches the record row — the Matrix prints a FAIL line for each item on the console; the record keeps the first and the author fixes all from the console.
  - `[low]` `[reject]` Blind 9 (`stop_routine end` unreachable until Story 11.15) — by design, Design Notes 11; Blind 10 (candidate_clone and checklist 75 untested) covered for the clone by the new case; checklist.sh takes no lock (exit 75 not reachable).
  - `[low]` `[reject]` Edge 3 (`Inheritance = right`, an unclosed `Extends (` on a file's last line): no production class uses either (Code Map); theoretical.
  - `[low]` `[reject]` Edge 7 (a gate script that hangs), Edge 10 (local and remote tags with one name on other commits): the harness bounds its phases at 540 s; the tag case is theoretical.
  - `[low]` `[reject]` Edge 12 (an unusual checklist exit): the LOG line points at the kept output; the row is `Result: -`, a FAIL either way.
  - `[low]` `[reject]` Edge 15 (claim): stubs, ci and eval write no script log; `LOG` is printed where a gate script ran (`gate_fail`).
  - `[low]` `[reject]` Gap 3: the gate readers are tested against hand-made sections, not the real `report` output — acknowledged in PLANNER REPORT; a drift fails closed; cannot run without the real phases.
  - `[low]` `[reject]` Gap AC5 mutation scope, `run_steps` silent after 40 passes, model key pinned by a source grep: the option refusals are "already met" (the main script); the other assertions after a stuck gate fail; the key has no read path in `release.sh`.
  - `[low]` `[reject]` Intent 1 to 3 (descriptive): extra lines beside the one `PASS|FAIL|WAIT` line, `report` plus `down` in one call and the read-the-verdict gates are Design Notes 6 and 7 and the Matrix; the second push on a `release/*` branch is read by sha, so it adds no confusion.

## Design Notes

**Already met (not rebuilt):**
- Stop naming the gate, record and commit: `release.sh:349-351` (`failed at <step>: <detail>`) and `cmd_next:1206-1209`, for any step.
- The gates write their own record sections when given `--record`: `upgrade-harness.sh` `report`, `rehearse.sh` `report` and `checklist.sh` (`record_write`).
- No option overrides: `release.sh:1242` and `:1362` refuse unknown options (exit 2). REL-5's override exists as `eval/run.sh --override` (`eval/run.sh` header).
- The override reason is shown in the notes: `release/notes.sh` `notes_eval` (Story 11.13).
- `WAIT`, exit 5 and nothing recorded: `release.sh:5-6` and `:1205` (Stories 11.17 and 15.4).
- Rows render for every step id with no change: `record_render:232`.
- Hands-on time counts only ASK windows, so CI and the pass are not counted: `release.sh:135-147` and `:190`.
- For 1.0.0: Stories 38.1 and 38.3 passed on rc4, and every gate was run by hand (`release/records/1.0.0/rc4.md`, "Hand gates" and "Release result"). `v1.0.0` is tagged, so `start` refuses 1.0.0 (`:1267`) and that clause cannot recur.

**Built here.** What the Planner did by hand, as the sequence's steps: the stub refusal, reading the full CI on the candidate's sha, judging the evaluation result, the upgrade and rehearsal drives one phase per call, the checklist, the stop at hands-on, and the push trigger.

**Governing ADs (Rule 6):**
- **AD-29:** `Parameter STUB = 1` on unbuilt items, and the release refuses an enabled one. `release/` and `lane-a.yml` are Lane A's, `ci.yml` is Lane B's, and Epic 11 may change either lane's files.
- **AD-22:** the release-candidate evaluation (`ocutalon.evalResult/1`, REL-5) and CI. Tests use the CI mock only, and nothing goes to a registry.
- **AD-19:** no key or environment value is read, printed or recorded. The key stays in the author's own `eval/run.sh` call.
- **AD-23:** the cut's version and bundle are unchanged. The harness proves the upgrade at start.
- **AD-25:** not used. The demo host is Story 11.18's.
- **AD-5:** the harness's checks.
- No AC contradicts an AD.

**Decided in-stage (small, reversible, within intent):**
1. **Step order.** The AC's order, with `stubs` right after `cut`: it is the cheapest check and must run before `push`, so a stub candidate never goes out. `notes` comes after `rehearsal`, because it reads their sections. `checklist` comes after `notes`, because it reads the draft. `hands-on` is last.
2. **"Full CI" means the newest push run of each workflow on the sha concluded `success`, with `ci` and `lane-a` required.** Story 32.2's skipped groups conclude `success` by design. `CI_WORKFLOWS="ci lane-a"` is pinned against the workflow names.
3. **`release/*` push trigger** in both workflows. Without it the pushed candidate gets no run (1.0.0's CI was read from its pull request). This is a footprint extension.
4. **The 900 s "no run yet" window counts from the `ci` step's first check** (`ci_first` in the state), so `step_push` and its clock reads stay unchanged.
5. **Per-gate clones of the author's repository.** They need no network and run the candidate's own gate code. The clone for `upgrade` and `rehearsal` gets `web/node_modules` through `ensure_web_bundle`.
6. **A phase done is exit 0 with `NEXT <step>`**, not exit 5: it is progress, not waiting. Exit 4 of `rehearse.sh run` maps to it, as DW-548 asks.
7. **`report` and `down` run in one upgrade call** (0 s and 9 s on 2026-11-02). After `seed`, a NOTE asks for the next call at once, because R1 must still be pending when the upgrade begins.
8. **Missing remote tags fail `upgrade` before `build`**, so the harness can never pick an older previous release.
9. **The `gh` repo seam applies only to a local-path remote** (tests and Story 11.18's rehearsal). A GitHub remote always reads its own repository.
10. **Fixed run tags with hyphens** (`rel-1-0-5-rc1-upg`), so that 1.10.5 and 11.0.5 never collide. The tag is stored in the state.
11. **The end text** becomes `stopped after <last>: no step after the gates has run (not a release)`, the text Story 11.16 expects. It is unreachable until 11.15, so a test reaches it by setting the state's `next=done`.
12. **`--runs 20`**, the bound's denominator.

**Decided in the implement pass (small ambiguities; none changes the intent contract):**
1. `COUNTS|<items>|...` counts the enabled items only, so the PASS text "(<n> enabled items in <m> productions)" is exact. `<stub items>` includes disabled ones.
2. An `Enabled` value other than `false` or `0` counts as enabled (the conservative side of "true, 1 or absent").
3. STUB resolution: the first class in the order (own value, then each superclass left to right, depth first) that sets `Parameter STUB` decides. A leftmost superclass with `STUB = 0` therefore wins over a later one with `STUB = 1`, as IRIS parameter inheritance does.
4. A value that is empty in a FAIL detail shows as `-` (a section that is missing reads `Result: -, Mode: -`). Remote tags that cannot be read show as `missing: unreadable` in the tags FAIL. These two placeholders are the only text beyond `### Public text`; they replace a value, not a message.
5. The NOTE after `seed` is printed exactly as written in `### Public text`.
6. `PHASE rehearsal <text>` prints the text after `NEXT run: ` of the script's line.
7. With the real harness, a failed `seed` makes `upgrade` exit 2 ("seed is not done for this tag"). The gate then runs `report` (so the harness writes its `## Upgrade harness` section, `Result: fail` with the cut sha), then `down`, and fails with `the harness refused upgrade: ...`. The Matrix's "down, then FAIL" order of `down` and FAIL holds, and `report` after a refused phase is the only addition; a failed `build` runs `down` alone. This is what IA4 asks for.
8. A record push that fails at the hands-on stop keeps exit 4 (a stopped kind keeps its code, as `stopped` does today); the FAIL record line is printed.
9. Usage text: `cli_usage` prints header lines 2 to 7 (the exit lines are now three).
10. Self-test pins that moved with the public text: the "one read command" pin matches `read -<flag>` commands (the mandated text "could not read the runs" contains the word), and `t_hands` counts one clock read for the `ci` step's first check.
11. The seed gets stub gate scripts, fixture productions under `src/fixture/` (a `Test` one is not scanned) and the working tree's `release/notes.sh` and `eval/run.sh`; the rules of the real scripts copy the real ones over (`set_real`).
12. A scan that finds class files but no production definition prints no `COUNTS` line (status 3, `FAIL stubs the production classes could not be read`): there was nothing to judge. A `Parameter STUB` line may be indented, carry `[ ... ]` keywords or `As <type>`, and end in `;` or a `//` comment.

**Harvested from the set-aside pass:** the reviewed robustness of `production_stubs`:
- single and double quotes;
- an `Extends (...)` continued over lines;
- a path with a space;
- a class's own `STUB = 0` wins;
- no `COUNTS` line counts as a failure.

Also harvested: `ci_first` kept on the first read, and the near-miss sha fixtures. `reopen_if` for the static scan: any `WriteDefault(..., "Enabled", ...)` on a class with `STUB`, because a Default Settings row is runtime-only.

**Extend, don't copy (Rule 2):**
- `record_section` is `notes.sh`'s reader, moved.
- `stubs` reuses `candidate_export`. The gates reuse `candidate_lock_dir`, the WAIT and LOG pattern of `step_overview`, and `ensure_web_bundle`.
- `candidate_clone` is new, and `step_cut`'s inline clone stays: the cut checks out a start commit, not a branch, and its lines are not reformatted (contended file).
- `ci_runs` is written here rather than reusing `_bmad/scripts/ci-gate.py`, because `release/` must not depend on `_bmad/`. Story 11.16 adds its `pull_request` reads through the event argument.
- The gate stubs extend the self-test's `stub_text`/`set_stub` pattern.

**Rules 1 and 2:**
- **Consumes:** `checklist.sh` (IA1), `eval/run.sh --override` and `notes.sh --eval` (IA2), `rehearse.sh run` (IA3), `upgrade-harness.sh` phases (IA4), GitHub runs (through the `gh` shim).
- **Consumed-by:**
  - 11.15: `step_hands_on`, `record_field`, `candidate_clone`;
  - 11.16: "every gate passed", `ci_runs`, `gh_repo`;
  - 11.18: the gate steps on a rehearsal candidate, through the seam;
  - the Contest Planner's daily releases.

**Ledger (Rule 17):** DW-548 is addressed by the Rehearsal drive row, AC7 and the `release.sh` task.

**release/** files changed (for the Planner's review):** `release/release.sh` (header, `STEPS`, two `cmd_next` cases, one `stop_routine` kind and the end text, one argument in `step_notes`, new gate functions after `step_notes`), `release/lib-release.sh` (additions only), `release/notes.sh` (one line).

**Shared files and where (contended):**
- `release/release.sh`: as listed above, not near `:575`.
- `docker/tests/test-release-sequence.sh`: the header rule list, the node and gh shims (`:171-178`, `:397-400`), new mkseed lines after `:535`, `to_step`, `t_gate:1506`, the `t_static` pin, and new functions and rules. Lines `:200` and `:511` are not touched.
- `.github/workflows/ci.yml` and `lane-a.yml`: one line each.
- `docker/tests/test-ci-config.sh`: `:6`, `:204`, the good sample, the bad samples and `:550`.
- On 2026-11-08, no listed path differs on `origin/OCT-epic0`, `-epic17` or `-epic32`. `origin/OCT-epic41` changes `ci/units.sh`, which this story does not touch.
- `footprint_extensions:` `.github/workflows/ci.yml`, `.github/workflows/lane-a.yml`, `docker/tests/test-ci-config.sh`.

**CI budget (REL-4):**
- No unit or group changes. The `release-sequence` self-test grows inside the hosted `checks` job, from about 4 min to about 6-7 min (inference from the set-aside pass: 80 s to 4 min 20 s). The job's limit is 20 minutes.
- The `ci.yml` edit is an IRIS input, so this story's push runs every group once, as any `ci.yml` change does.
- From now on each candidate push adds one full CI run on the runners (the product's intent).

**PLANNER REPORT:** each of these cannot be proved without acting outward, and nothing is built around it:
- That the `release/*` trigger fires and the `ci` gate reads real runs: this needs a candidate pushed to origin.
- That the real gates pass on a real candidate: the evaluation needs the model key, the rehearsal needs a clean host and 20 runs, and the live upgrade drive has phases of up to about 300 s, past this plan's 150-s command limit (measured once on 2026-11-02: every phase within 10 minutes).
- The Contest Planner proves them at the next daily release.

**Size.** One implement pass. The same scope was implemented in one pass on 2026-11-02 (set-aside patch: `release.sh` +436 lines, `lib-release.sh` +190, self-test +1300). The upgrade and rehearsal drives share the phase mechanism with the other gates, so no split is proposed. If the lead wants one, the natural cut is a sibling taking those two drives (the upgrade harness and clean-machine rehearsal parts of the first criterion, and DW-548).

### Public text

New or changed strings, verbatim; `<...>` are values. File: `release/release.sh`, printed to the author's console, and in rows and `Result:` lines of `release/records/<v>/rc<n>.md`.

- Header steps line: `# Steps, in order: cut, stubs, image, overview, ipm, ipmcheck, push, ci, eval, upgrade, rehearsal, notes, checklist, hands-on  (Stories 11.15, 11.16 and 11.18 extend STEPS)`
- Header exit lines: `# Exit: 0 step done, a gate phase done (NEXT <step>: the step stays current) or end of steps, 1 a step failed, 2 refused (nothing written),` / `#       4 stopped for the author's word, 5 waited: the lane's throwaway lock is busy, CI has not finished or the evaluation has not run`
  `#       (nothing recorded; the next call runs the step again)`
- Header paragraph: `# The gates (Story 11.14; REL-1, REL-5, REL-6, REL-7, AD-29). stubs refuses an enabled production item whose class carries Parameter STUB = 1. ci reads, with gh run list, the push runs of ci and lane-a on the cut commit; each must succeed. eval judges the author's eval/run.sh --release-candidate result in <state>/eval; REL-5's override (eval/run.sh --override) is the only override. upgrade and rehearsal run release/upgrade-harness.sh and release/rehearse.sh of the candidate, one phase per call. checklist runs release/checklist.sh. A gate passes only when its script exits 0 and its own section reads Result: pass for this commit. hands-on stops: the Contest Planner's pass is not recorded by this sequence.`
- `PASS stubs no enabled item answers "not implemented" (<n> enabled items in <m> productions)`
- `FAIL stubs <Production>:<Item> (<Class>) answers "not implemented"; disable it in its production, or build it, and cut the next candidate`
- `FAIL stubs the production classes could not be read`
- `PASS ci every push run on <short sha> succeeded: <workflow> run <id>, ...`
- `WAIT ci <workflow> run <id> is <status>`
- `WAIT ci no <workflow> push run on <short sha> yet (<s> s of 900 s)`
- `WAIT ci gh could not read the runs (exit <n>); the next call reads them again`
- `FAIL ci <workflow> run <id> concluded <conclusion>`
- `FAIL ci no <workflow> push run on <sha> 15 minutes after the first check`
- `FAIL ci gh is not installed`
- `FAIL ci the remote <name> is not a GitHub repository, so its runs cannot be read`
- `WAIT eval no evaluation result for <short sha> yet; the author runs the evaluation`
- `RUN cd <absolute clone path> && bash eval/run.sh --release-candidate`
- `PASS eval pass: <decidedBy>`
- `PASS eval overridden (REL-5): <reason>`
- `FAIL eval blocked: <decidedBy>; REL-5's override is the author's: eval/run.sh --override "<reason>" in the evaluation clone`
- `RUN cd <absolute clone path> && bash eval/run.sh --override "<reason>"`
- `FAIL eval incomplete: <decidedBy>`
- `FAIL eval the result was made on the CI mock, not on the model`
- `FAIL eval the result is of commit <short>, not of the candidate <short>`
- `FAIL eval the result was made on a tree with uncommitted changes`
- `FAIL eval the result is not an ocutalon.evalResult/1 file`
- `FAIL eval overridden with no reason`
- `PHASE upgrade <phase> exit <n>`
- `NOTE upgrade run the next call now: the reminder that the seed set must still be pending when the upgrade begins`
- `WAIT upgrade the lane's throwaway lock is busy` (and the same for `rehearsal`)
- `PASS upgrade Result: pass, Mode: release, Previous: <Previous line>`
- `FAIL upgrade the harness's section reads Result: <r>, Mode: <m>`
- `FAIL upgrade the harness refused <phase>: <its line>`
- `FAIL upgrade the tags of <remote> are not all in this repository (missing: <tags>); run git fetch --tags <remote>, then release.sh next`
- `FAIL upgrade the section names another commit than the candidate` (and the same for `rehearsal` and `checklist`)
- `WARN upgrade the down phase exited <n>; containers or volumes of run tag <tag> may remain`
- `PHASE rehearsal <the NEXT run: text of release/rehearse.sh>`
- `PASS rehearsal Result: pass, Mode: rehearsal, <N of N runs passed>`
- `FAIL rehearsal release/rehearse.sh refused: <its REFUSED text>`
- `FAIL rehearsal a dry run is never a pass`
- `FAIL rehearsal the section reads Result: <r>, Mode: <m>: <its first FAIL line>`
- `PASS checklist Result: pass`
- `FAIL checklist Result: <fail|not confirmed>: <first FAIL line, or "<k> author rows not confirmed">`
- `FAIL checklist release/checklist.sh refused: <its line>`
- `LOG <gate> <absolute log path>`
- `STOPPED hands-on every automated gate passed; install release/<v>-rc<n> (<short sha>) for the author's hands-on pass (REL-7); this sequence does not record that pass`
- Record row: `| hands-on | waiting | the author's hands-on pass (REL-7) on release/<v>-rc<n> is not recorded |`
- Record `Result:` (hands-on): `stopped at hands-on: every automated gate passed; no hands-on pass is recorded (not a release)`
- Record `Result:` (end, changed): `stopped after <last>: no step after the gates has run (not a release)`
- Rows (`| <step> | pass\|fail | <detail> |`): each detail is its PASS or FAIL text without the leading `PASS <step> ` or `FAIL <step> `.
- `docker/tests/test-ci-config.sh` descriptions: `push.branches is main, feature/OCT_OcuTalon_MVP, OCT-epic* and release/*` and `push on main, feature/OCT_OcuTalon_MVP, OCT-epic* and release/*, every pull request, ...`
- No README or docs line changes.

## Verification

Run each command in its own foreground call with `timeout: 600000`, from the worktree root, with `TMPDIR` in the stage's scratch folder. Each must finish in about 150 s. Measured on 2026-11-08 (plan, the dev Mac, current tree, one rule per run): `notes` 15 s, `push` 13 s, `gate` 5 s; the whole script is about 4 min. If a batch nears 120 s, split it and record the new batches here.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh stubs ci eval` -- expected: `PASS all rules`.
- `(loop)` `bash docker/tests/test-release-sequence.sh upgrade rehearsal` -- expected: `PASS all rules`.
- `(loop)` `bash docker/tests/test-release-sequence.sh checklist handson static` -- expected: `PASS all rules`.
- `(loop)` `bash docker/tests/test-release-sequence.sh gates` -- expected: `PASS all rules`.
- `(loop)` `bash docker/tests/test-release-sequence.sh realgates` -- expected: `PASS all rules`.
- `(once)` the existing rules in batches, one per call: `libs refusals cut`, `recut image overview`, `ipmcheck push record`, `hands resume notes`, `gate secret first`, `word pushes`, `ipm ipmfail`, `ipmwait ipmnet ipmlib`, `overviewunit overviewdrift overviewdoc` -- expected: `PASS all rules` each.
- `(once)` `bash docker/tests/test-release-notes.sh`, `bash docker/tests/test-release-checklist.sh`, `bash docker/tests/test-upgrade-harness.sh`, `bash docker/tests/test-rehearsal.sh` (they source `lib-release.sh`), one per call, by their own rules if a whole run passes 150 s -- expected: exit 0.
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-ci-changes.sh`, then `bash ci/changes.sh ci.yml` -- expected: exit 0.
- `(once)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.

**Task 0 figures (implement pass, 2026-11-08):**
- `production_stubs` on the real tree: `COUNTS|58|3|0|0`, status 0 (58 enabled items in 3 productions, 0 stub items), under 1 s. The first field counts enabled items only.
- On a scratch copy of `src/` where `Channel/Telegram/In.cls` has `Parameter STUB = 1;`:
  - TelegramIn as it is (`Enabled="false"`): `COUNTS|58|3|1|0`, status 0 (a disabled stub is not refused).
  - `Enabled="true"`: `FOUND|OcuTalon.Production|TelegramIn|OcuTalon.Channel.Telegram.In` and `COUNTS|59|3|1|1`, status 1.
  - the attribute removed: the same `FOUND` and `COUNTS|59|3|1|1`, status 1.
  - `Enabled="1"`: the same, status 1.
- The real `rehearse.sh run` with no `release.conf` (in a throwaway of the self-test, with `--version 1.0.0 --rc 1 --candidate release/1.0.0-rc1 --record <file> --runs 20`): exit 2, the line `REFUSED config: the configuration file is missing or not readable`, and the docker shim log gains no line (24 lines before and after). `rehearse.sh down` after it prints `TEARDOWN nothing to remove for tag <tag> (no state)`.
- The real `upgrade-harness.sh build` with the shims (previous release a tag whose tree has a built page): the call (clone with `web/node_modules` through the npm shim, then `build`) took 1 s, exit 0, so IA4 uses the real harness.

**Measured, one batch per call, on the dev Mac under load from other agents (wall time):**
- `stubs ci eval` 88 s; `upgrade rehearsal` 110 s (split to one rule per call when the host is busy); `checklist handson static` 39 s; `gates` 100 s; `realgates` 62 s.
- Existing rules: `libs refusals cut` 29 s; `recut image overview` 49 s; `ipmcheck push record` 116 s; `hands resume notes` 110 s; `gate secret first` 35 s; `word pushes` 46 s; `ipm ipmfail` 74 s; `ipmwait ipmnet ipmlib` 12 s; `overviewunit overviewdrift overviewdoc` 9 s. Every batch printed `PASS all rules`.
- `test-release-notes.sh` 39 s, `test-release-checklist.sh` 47 s, `test-upgrade-harness.sh` 52 s, `test-rehearsal.sh` about 2.5 min (moved to the background by the harness and waited for; exit 0; it needs no lane variables), `test-ci-config.sh` 79 to 89 s, `test-ci-changes.sh` 36 s, `ci/changes.sh ci.yml` under 1 s, `test-boundaries.sh` 11 s: all exit 0.

**Mutations (Rule 19; one per AC, applied, observed red, reverted; the four edited files hashed equal before and after):**
- AC1: advance the state on a failed gate.
  - mutation: `sset next "$(next_step "$step")"` added to the failure branch of `cmd_next`; red in `gates` ("the state still names it" and every check after it).
- AC2: a missing `Enabled` counts as disabled.
  - mutation: `en == ""` added to the disabled test in `production_stubs`; red in `stubs` (form with no `Enabled`).
  - mutation: `nprod > 0` guard of the `COUNTS` line removed in `production_stubs`; red in `stubs` ("no production: exit", "no production: the line").
  - mutation: the `Parameter STUB` match anchored at column 0 again; red in `stubs` ("forms: an indented Parameter line"). The trailing-comment and keyword forms are red when their parts of the match are removed.
- Matrix, clone guard (Always: HEAD must equal the cut's sha): the check skipped in `candidate_clone`.
  - mutation: `if [ "$head" != "$sha" ]` replaced by `if false` in `candidate_clone`; red in `checklist` ("moved branch: the line", "moved branch: the gate script did not run").
- AC3: accept `failure`.
  - mutation: `$4 != "failure"` added to the red test of `step_ci`; red in `ci` ("red: exit", "red: the line").
- AC4: accept `onMock` true.
  - mutation: `onMock` true accepted in `step_eval`; red in `eval` ("pass: the line" and the kept result).
- AC5: `gate_verdict` trusts the exit code alone.
  - mutation: `return 0` in place of the `Result: pass` test in `gate_verdict`; red in `gates` (upgrade, rehearsal and checklist variants).
- AC6: skip the phases after a failed `seed`.
  - mutation: `next=report` after a failed `seed` in `step_upgrade`; red in `upgrade` ("a failed seed: every phase ran, then down").
- AC7: map exit 3 to pass.
  - mutation: the exit 3 branch of `step_rehearsal` returns a PASS; red in `rehearsal` ("exit 3: exit", "exit 3: the line").
- AC8: `hands-on` returns 0.
  - mutation: `return 0` in place of `return 6` in `step_hands_on`; red in `handson` (the state no longer names hands-on, the exit is 0).
- AC9: drop `release/*` from `lane-a.yml`.
  - mutation: the line removed; red in `test-ci-config.sh` (`triggers` fails).
- IA1: write `pass` for the checklist row.
  - mutation: `STEP_ROW=pass` before the failing return of `step_checklist`; red in `realgates` ("IA1: the checklist row is the script's own result").
- IA2: replace `override.reason` with a fixed text.
  - mutation: `fixed text` in the overridden detail of `step_eval`; red in `realgates` ("IA2: the row").
- IA3: map exit 2 to WAIT.
  - mutation: the exit 2 branch of `step_rehearsal` prints a WAIT and returns 5; red in `realgates` (IA3).
- IA4: do not write the harness's section when it refuses a phase.
  - mutation: the `report` call before `down` on exit 2 of a phase after `build` skipped in `step_upgrade`; red in `realgates` (IA4: "the report ran after the refusal", "the harness section is in the record", "the section reads Result: fail", "the section names the cut commit").
- IA4 (verdict half): judge the harness on its exit code only.
  - mutation: `[ "$ra" -eq 0 ]` alone decides the pass in `step_upgrade`; red in `gates` (the upgrade variants and the control).

**Shared surfaces:**
- the `STEPS` list (the `t_static` pin; the specs of 11.15, 11.16 and 11.18);
- the stop kinds and the end `Result:` text (`t_gate`);
- the record's step rows;
- `to_step` and mkseed;
- the self-test's gh and node shims and the network-marker check (`t_secret`);
- the `lib-release.sh` function list;
- the workflow trigger set pinned by `test-ci-config.sh`.
- Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The release sequence now runs `cut stubs image overview ipm ipmcheck push ci eval upgrade rehearsal notes checklist hands-on`: the stub refusal, the full-CI read, the evaluation verdict (REL-5), the upgrade and rehearsal drives one phase per call, the checklist, and a `hands-on` stop that never passes. `release/*` joins the push branches of `ci.yml` and `lane-a.yml`.

**Files changed.**
- `release/release.sh`: header, `STEPS`, the gate functions after `step_notes`, `cmd_next` cases 3 and 6, the `hands` stop kind and end text, `--eval` in `step_notes`, usage lines 2 to 7.
- `release/lib-release.sh`: `record_section`, `record_field`, `production_stubs`, `candidate_clone`, `gh_repo`, `ci_runs` (additions only).
- `release/notes.sh`: `notes_section` calls `record_section`.
- `.github/workflows/ci.yml`, `.github/workflows/lane-a.yml`: the `"release/*"` push branch.
- `docker/tests/test-ci-config.sh`: the required set, good sample, `trigger-no-release` bad sample, descriptions.
- `docker/tests/test-release-sequence.sh`: shims, seed, drivers, the rules `stubs ci eval upgrade rehearsal checklist handson gates realgates`, static pins, updated existing rules.
- this spec: Task 0 figures, batch times, mutation lines, decisions, triage log.

**Review.** 39 findings from four layers: 4 medium and 5 low rows patched (grouping 9 patch rows), 0 deferred, the remaining low findings rejected with reasons (see the triage log). Patched medium entries: empty scan passing `stubs`; `Parameter STUB` line forms; `report` before `down` after a refused phase (IA4); the clone's HEAD guard test.

**Follow-up review recommended: true.** Two or more medium entries were patched, and these patched paths had only the self-test behind them: the `production_stubs` awk match (the layout of real production classes beyond the fixtures) and the `report` call after exit 2 in `step_upgrade` against the real harness.

**Verification (final tree).** Each of these passed: `stubs ci eval` (74 s), `upgrade rehearsal` (75 s), `checklist handson static` (32 s), `gates` (78 s), `realgates` (50 s); the existing batches `libs refusals cut` (25 s), `recut image overview` (41 s), `ipmcheck push record` (95 s), `hands resume notes` (81 s), `gate secret first` (21 s), `word pushes` (33 s), `ipm ipmfail` (54 s), `ipmwait ipmnet ipmlib overviewunit overviewdrift overviewdoc` (21 s); `test-release-notes.sh` 36 s, `test-release-checklist.sh` 43 s, `test-upgrade-harness.sh` 38 s, `test-rehearsal.sh` 133 s, `test-ci-config.sh` 87 s, `test-ci-changes.sh` 30 s, `ci/changes.sh ci.yml` under 1 s, `test-boundaries.sh` 9 s. Hosted-checks estimate for the whole `release-sequence` self-test: the rule batches sum to about 11 minutes on the loaded dev Mac, so about 8 to 11 minutes on the runner (inference), inside the job's 20 minutes.

**Residual risks.** The `release/*` trigger firing, the `ci` gate reading real runs, and the real gates passing on a real candidate are not provable offline (PLANNER REPORT). The gate readers are tested against hand-made sections plus the real checklist, so a format drift in the real `report` output fails closed at the next real release. Rows of the Matrix that the Planner may rule on: the two placeholders (`-` for an empty value, `missing: unreadable`) from Design Notes 4.
