---
title: 'Story 11.14: The release sequence runs every gate on the pushed candidate'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-5-one-scripted-sequence-cuts-a-release.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 11.5's `release/release.sh` cuts and pushes a candidate, then stops with `no gate has run (not a release)`. Nothing yet runs the gates on the pushed candidate, writes their results into the record, stops at the gate that failed, or refuses a candidate whose enabled production item is still a stub. And no workflow runs on a `release/*` push, so the candidate gets no CI.

**Approach:** Add gate steps to 11.5's `STEPS`. Each step is resumable, and runs at most one gate phase per `next` call:

`cut image stubs push ci eval upgrade rehearsal notes checklist hands-on`

- `stubs`, `ci`, `eval`, `upgrade`, `rehearsal`, `checklist` and `hands-on` are this story's.
- Each gate step calls the gate's real script, or reads its verdict, and judges it. It writes one row into `## Release sequence`, and the gate writes its own section into the same record.
- The first gate that does not pass stops the sequence and is named.
- `"release/*"` joins the push branches of both workflows and of the trigger pin.
- `hands-on` is the last gate. This story puts it in the list as a stop that never passes. Story 11.15 owns its stop and resume.

This story takes epics.md Story 11.14's two criteria (the gates; the "not implemented" refusal), verbatim there.

## Boundaries & Constraints

**Always:**
- **Conventions.** Everything in 11.5's spec still holds:
  - Bash 3.2 and ASCII; mode 100755; `umask 077`; the main guard;
  - `PASS|FAIL <step> <detail>`, then `RECORD` and `RESULT`;
  - the stop routine (record, commit with an explicit pathspec, ASK `record`);
  - answers only on stdin, no value printed, exactly two pushes, never `--force`.
- **New exit code 5** means waiting on work outside the sequence: CI, the author's evaluation, or a busy lane lock.
  - It prints `WAIT <step> <reason>`, writes no record and asks nothing.
  - The step stays current, and the next `next` runs it again.
  - The existing codes keep their meaning: 0 a step or phase done, 1 a gate failed, 2 refused, 4 stopped.
- **Gate verdict.** A gate with its own script and section (`upgrade`, `rehearsal`, `checklist`) passes only when all of these hold:
  - its script exits 0;
  - its own section reads `Result: pass`;
  - that section's `Candidate:` line names this candidate's full SHA;
  - its `Mode:` is the real one: `release` for the upgrade harness, `rehearsal` for the rehearsal.
  - `stubs`, `ci` and `eval` pass only on the conditions in the Matrix.
  - Anything else is `FAIL <gate> <what it said>`, and the record reads `Result: failed at <gate>: <detail>`. No false all-clear.
- **One override.** REL-5's override is the only one, and it lives in the evaluation's result file: `verdict: overridden` with a non-empty `override.reason`, written by `eval/run.sh --override`.
  - No option, environment variable, configuration key or record line skips, forces or overrides a gate.
  - The CLI refuses unknown options with exit 2.
- **Gates run in clones at the candidate.** Both live in the state folder:
  - `<state>/candidate` is for `upgrade`, `rehearsal` and `checklist`;
  - `<state>/eval` is for the author's evaluation.
  - Each clone has full history and tags. Its HEAD must equal the recorded cut SHA and the remote's `release/<v>-rc<n>`.
  - Each gate gets the author's record and notes draft as absolute `--record` / `--notes` paths.
  - The author's checkout is never switched.
- **Extend, don't copy (Rule 2).**
  - Gates are called through their own CLIs, never re-implemented.
  - New helpers go into `release/lib-release.sh`.
- **Phase per call.**
  - `upgrade` runs one harness phase per `next`, in the order of the harness's own `cmd_run`.
  - `rehearsal` runs one `rehearse.sh` phase per `next`.
  - Each phase fits a 10-minute call (Rule 18 (5)).
- **Tests use only throwaway repositories, local bare remotes and a `gh` shim.** The shim answers canned JSON and logs its arguments. The real `gh` and GitHub are never reached.

**Never:**
- Run `release/release.sh` in this worktree, in a real checkout, or against GitHub or any network remote.
- Cut a release or tag, create a `release/*` branch outside a throwaway, push to `main` or `origin`, open a pull request, or publish notes or anything else.
- Call `gh` with anything but read-only `run list` / `run view`: no `rerun`, no `workflow run`, no `api -X`, no `pr` and no `release`.
- Hold, read or pass the model key. The real evaluation is the author's command, run in `<state>/eval`.
- Change anything else in `.github/workflows/*`: no job name, no matrix and no other trigger. Never add `rehearsal/*` (U-203).
- Edit `src/module.xml`, `release/ipm*`, `Install/**`, `README.md`, `docker/tests/lib-live.sh` or `.gitignore`.
- Build 11.15's hands-on pass record or resume refusal, or 11.16 to 11.18's steps.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stub enabled | An enabled item (`Enabled="true"`, or no `Enabled` attribute) of a non-test `XData ProductionDefinition` class under `src/`. Its class, or an in-tree superclass, has `Parameter STUB = 1;` | `FAIL stubs <Production>:<Item> (<Class>) answers "not implemented"`; exit 1; no push ASK | Remote unchanged |
| No stub enabled | The real tree: TelegramIn and TelegramOut are stubs but `Enabled="false"` | `PASS stubs`, with a row giving the item and production counts | -- |
| CI green | Every push run on the SHA (`gh run list --branch release/<v>-rc<n> --commit <sha> --event push`) is completed `success`, `ci` and `lane-a` among them | `PASS ci`; the row names each workflow's run id | -- |
| CI pending or not started | A run in progress, or no run yet within 15 min of the push (clock seam) | `WAIT ci ...`, exit 5 | -- |
| CI red, or missing | A latest run not `success`, or `ci` / `lane-a` absent 15 min after the push | `FAIL ci <workflow> run <id> <conclusion>` or `FAIL ci no <workflow> run on <sha>` | -- |
| Eval not yet run | No `<state>/eval/eval/release-candidate.json` | `WAIT eval`, plus one `RUN cd <clone> && bash eval/run.sh --release-candidate` line | -- |
| Eval pass or overridden | `format` `ocutalon.evalResult/1`; `commit` = candidate SHA; `onMock` false; `treeClean` true; `verdict` `pass`, or `overridden` with a reason | `PASS eval`; the row reads `pass` or `overridden (REL-5): <reason>`; the file is copied to `<state>/release-candidate.json` | -- |
| Eval not acceptable | `blocked`, `incomplete`, on the mock, a commit mismatch, a dirty tree, an unknown format, or `overridden` with no reason | `FAIL eval <which>`. For `blocked` the line names REL-5's `--override` | `next` re-reads the file |
| Upgrade phases | `next` repeatedly | `build`, then `settings seed upgrade restart storage` (each runs even after an earlier failure), then `report`, then `down`, one per call, all with one fixed `OCUTALON_RUN_TAG` | A failed `build` runs `down` and fails. A 75 from a phase gives `WAIT` and the same phase again |
| Rehearsal phases | `next` repeatedly | `install`, then `runs` until 20 runs, then `report`, then `down` | A non-zero `runs` goes straight to `report`, then `down`. A refusal (exit 2, for example no `release.conf`) gives `FAIL rehearsal <reason>`. 75 gives `WAIT` |
| Checklist | After `notes` | `release/checklist.sh --version --rc --candidate release/<v>-rc<n> --record <rec> --notes <draft>` in `<state>/candidate` | `not confirmed` or `fail` gives `FAIL checklist <result>` |
| Hands-on | Every automated gate passed | `STOPPED hands-on the hands-on gate is Story 11.15's`; exit 4; `Result: stopped at hands-on: every automated gate passed; no hands-on pass recorded (not a release)` | Never `pass` |
| Override attempt | `next --skip`, `--force`, `--override x`; a planted `Result: pass` in a section whose gate exited 1; a gate that exits 0 with `Result: fail` | Exit 2 (usage) for the options. The gate still `FAIL`s in the other two cases | -- |

</intent-contract>

## Code Map

**Prerequisites:**
- Stories 11.3, 11.11, 11.4, 11.13 and 11.5 must be merged into this branch, each `ready-for-dev` today. They provide `release/lib-release.sh`, `rehearse.sh`, `checklist.sh`, `notes.sh` and `release.sh`, and 11.5's `docker/tests/test-release-sequence.sh`.
- 11.12 is not planned. Without it, the second `rehearse.sh runs` exits 2 naming 11.12, so a real rehearsal reads `not run` and the gate fails, which is correct.

**Files:**
- `release/release.sh` (11.5) -- extend:
  - add the gate steps to `STEPS` and add their `step_<name>` functions;
  - change the end-of-steps `Result:` text;
  - the `notes` step passes `--eval <state>/release-candidate.json` once `eval` has passed.
- `release/lib-release.sh` -- add:
  - `record_field <file> <section> <field>`: the `Field:` line of one `## ` section. If built `notes.sh` already has such a reader, move it here and reuse it.
  - `production_stubs <tree>`
  - `candidate_clone <dir> <v> <rc> <sha> <remote>`
  - `gh_repo <remote>`: `owner/repo` from a github.com URL, else the test seam `OCUTALON_RELEASE_GH_REPO`, else fail.
  - Keep `record_path`, `record_write`, `notes_path`, `candidate_branch` and `next_rc`.
- `release/upgrade-harness.sh` (built; read only):
  - `cmd_run` `:1630-1653`: the phase order, every phase after `build` running regardless, and `down` always.
  - Options go only to `build` (`:496-540`, `:1583`).
  - The state is keyed by `OCUTALON_RUN_TAG`.
  - Exit codes `:33-34` (0, 1, 2, 75; `plan` exits 0 but is a dry run).
  - The section `:411-443` has `Result:`, `Mode:` (`release` needs a clean tree), `Required:` and `Candidate: <v> at <sha>`.
  - 1.0.0 gives `Required: no` against the pinned pre-release commit `:49`, which needs full history.
  - Timings: seed 109 s, upgrade 293 s. Seed and upgrade must run back to back (R1's 300 s window, spec 11.2 `:398`).
- `release/rehearse.sh` (11.3 and 11.11):
  - phases `install|runs|report|down`;
  - exits 0 real pass, 1, 2, 3 dry run, 75;
  - `## Clean-machine rehearsal` with `Result:`, `Mode:`, `Candidate:`;
  - reads `OCUTALON_RELEASE_CONFIG` or `~/.config/ocutalon/release.conf`.
- `release/checklist.sh` (11.4):
  - `--candidate` must be HEAD;
  - needs the notes draft;
  - exits 0 only for `pass`;
  - reads `## Author confirmations`.
- `release/notes.sh` (11.13):
  - `--eval` takes an `ocutalon.evalResult/1` file;
  - the override reason comes from its `override.reason`;
  - it reads `## Upgrade harness` and `## Clean-machine rehearsal`.
- `eval/run.sh`:
  - `--release-candidate` exits 0 pass or 3 blocked, and copies the pair to `eval/` (`:731-739`); a real run takes about 30 to 60 min (inference);
  - `--on-mock` writes only to its report folder;
  - `--override "<reason>"` needs only Node (`:159-217`).
  - The field names are in `src/ocutalon/cls/OcuTalon/Eval/Gate.cls:300-332`.
  - `docker/tests/test-eval-set.sh:1222` (`rcJson`) is the fixture precedent.
- `src/ocutalon/cls/OcuTalon/Production.cls:16-17`: TelegramIn and TelegramOut are `Enabled="false"`. `Channel/Telegram/In.cls:11` and `Out.cls:7` have `Parameter STUB = 1;`.
- Other non-test productions: `Demo/Orders/Production.cls` and `src/bridge/.../BridgeExample/Production.cls`.
- `Install/Step/Production.cls:136`: a Default Settings `Enabled` row can override the XData (see Design Notes).
- `.github/workflows/ci.yml:13-17` and `lane-a.yml:8-12`: the push branches.
- `docker/tests/test-ci-config.sh`:
  - the pin `:189`;
  - the good sample `:299-302`;
  - the descriptions `:6` and `:459`;
  - the mutation `trigger-extra-branch` `:364`, which shows that the set is exact.
- `docker/tests/test-upgrade-harness.sh:711-734` (`make_run_stub`): the precedent for stubbing a gate script inside a throwaway root.

## Tasks & Acceptance

**Execution:**
- **Task 0** (measure, figures into `## Verification`):
  - Run `production_stubs` on this tree: it must pass, and give the counts. Run it on a scratch copy with TelegramIn `Enabled="true"`: it must report it.
  - One read-only `gh run list --branch feature/OCT_OcuTalon_MVP --commit <a recent pushed sha> --event push --json databaseId,workflowName,status,conclusion,url`, to pin the shim's JSON shape.
  - Confirm that real `rehearse.sh install` with a missing `release.conf` refuses (exit 2) before it touches docker.
  - Time one live upgrade drive (below).
- `release/lib-release.sh`: add the four helpers above.
- `release/release.sh`: the steps and the exit code 5, as in the Matrix and Design Notes. Fixed run tags: `rel<v digits>rc<n>upg` and `rel<v digits>rc<n>reh`.
- `docker/tests/test-release-sequence.sh` (extend 11.5's; no new `CHECK_SCRIPTS` entry):
  - Update 11.5's cases for the new steps.
  - Add gate cases. In the throwaway copy, `upgrade-harness.sh` and `rehearse.sh` are stubs that log their argv and write a section from a fixture; there is a `gh` shim; and the eval clone gets fixtures.
  - Cover every Matrix row, IA1 to IA4, and a pin that release.sh's harness phase list equals `cmd_run`'s.
  - Add `--live-gates prepare|next|check|clean`, one part per call:
    - `prepare`: a throwaway clone of HEAD with full history and a local bare remote, cut and pushed, CI and eval green through fixtures;
    - `next`: one `release.sh next`;
    - `check`, then `clean`.
- `.github/workflows/ci.yml` and `.github/workflows/lane-a.yml`: one line each, `      - "release/*"`, after `"OCT-epic*"`.
- `docker/tests/test-ci-config.sh`: add `release/*` to the pin at `:189` and the matching line to the good sample. Append ` and release/*` to the two descriptions. Nothing else.
- Then run `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml`.

**Acceptance Criteria:**
- **AC1 (gate order, stop and record; REL-1, REL-6):**
  - **Given** a throwaway candidate (cut for `stubs`, pushed for the rest) and gate fixtures where gate G fails, **when** `next` reaches G, **then**:
    - it prints `FAIL G ...` and exits 1;
    - the committed record reads `Result: failed at G: ...` with G's row;
    - no gate after G ran (the stub logs);
    - the next `next` runs G again, never the gate after it.
  - This holds for each G in `stubs ci eval upgrade rehearsal checklist`.
- **AC2 ("not implemented"; REL-1, AD-29):**
  - **Given** a candidate tree with TelegramIn enabled (or with its `Enabled` attribute removed), **when** `next` runs `stubs`, **then** `FAIL stubs OcuTalon.Production:TelegramIn ...` comes before any push ASK, and the bare remote is unchanged.
  - The real tree passes.
  - Classes under `/Test/` are not scanned.
- **AC3 (full CI):** **Given** the `gh` shim, **when** `ci` runs, **then**:
  - all push runs `success` gives `PASS`;
  - in progress, or no run within 15 min, gives `WAIT` with exit 5, and no record commit;
  - a red `lane-a` gives `FAIL ci lane-a run <id> failure`;
  - a missing `ci` after 15 min gives `FAIL`;
  - the shim log holds only `run list` / `run view` calls.
- **AC4 (evaluation and REL-5; CON-2):** **Given** each eval fixture in the Matrix, **when** `eval` runs, **then** its row and exit match.
  - An `overridden` result with a reason passes, and the row names the reason.
  - Every other non-`pass` result fails.
- **AC5 (the only override):**
  - **Given** `--skip`, `--force` or `--override`, **when** `start` or `next` runs, **then** it exits 2.
  - **Given** a gate exit of 1 with a planted `Result: pass`, or an exit of 0 with `Result: fail`, or a section naming another SHA, **when** it is judged, **then** it is `FAIL`.
- **AC6 (upgrade drive; AD-5):** **Given** stub phases, **when** `next` runs repeatedly, **then**:
  - the phases run one per call, in `cmd_run`'s order, all with one `OCUTALON_RUN_TAG`, and only `build` gets `--version --rc --record`;
  - `down` always runs;
  - a 75 repeats the phase;
  - it passes only with `Result: pass`, `Mode: release` and the candidate SHA. `Required: no` does not relax this.
- **AC7 (rehearsal drive; REL-6):** **Given** stub phases, **when** `next` runs repeatedly, **then**:
  - the order is `install`, `runs` x20, `report`, `down`;
  - a failing run skips the remaining runs;
  - exit 3 (`dry run`) is `FAIL`;
  - it passes only on exit 0 with `Result: pass`, `Mode: rehearsal` and the candidate SHA.
- **AC8 (checklist, then hands-on; REL-7, CON-5):**
  - **Given** every automated gate passing, **when** the steps end, **then** `checklist` runs after `notes` in `<state>/candidate`, and `hands-on` stops with exit 4 and the Matrix text.
  - The record is committed by the stop routine.
  - No line or record says `pass` for the release.
- **AC9 (CI on the candidate):** **Given** the edited workflows, **when** `test-ci-config.sh` runs, **then** it passes. With `"release/*"` removed from either workflow, it fails (the `triggers` rule).
- **IA1 (real `checklist.sh`):** **Given** a record with no `## Author confirmations`, **when** `checklist` runs the real script, **then**:
  - the row is `fail` or `not confirmed`, as the script printed;
  - `## Release checklist` is in the record;
  - `## Release sequence` keeps its other rows byte-identical.
- **IA2 (real `eval/run.sh --override`):** **Given** a blocked fixture in `<state>/eval` that the real `eval/run.sh --override "fixture reason"` turns into overridden, **when** `eval` runs, and then the real `notes.sh` with `--eval`, **then** the row reads `overridden (REL-5): fixture reason`, and the draft notes carry the reason.
- **IA3 (real `rehearse.sh`):** **Given** no `release.conf`, **when** `rehearsal` runs the real script, **then** it prints `FAIL rehearsal` naming the script's own refusal, and starts no container.
- **IA4 (`(once)` live, real harness):** **Given** `--live-gates prepare`, **when** `--live-gates next` is called once per phase, **then**:
  - the record's `## Upgrade harness` comes from the real harness, with `Candidate:` the cut SHA;
  - the upgrade row matches its `Result:`;
  - `clean` leaves no container, image tag or folder of the run tag.
- **Standing:** every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- **AD-29:**
  - `Parameter STUB = 1` on every unbuilt item.
  - The sequence refuses a candidate with an enabled one.
  - `release/` and `lane-a.yml` are Lane A's; `ci.yml` is Lane B's (covered by the 2026-11-01 ruling).
- **AD-22:** the eval runs on Haiku 5.5 per candidate, the mock only in CI, and nothing goes to a registry.
- **AD-23:** the version and bundle on the cut.
- **AD-5:** the harness's storage diff.
- No criterion contradicts an AD.

**Decided in-stage (unattended block: small, reversible, in intent):**
1. **The evaluation is the author's command.** The key never passes through the sequence. A real run (about 30 to 60 min, inference) cannot fit one step. The step makes `<state>/eval`, names the command, waits (exit 5) and judges the file.
2. **"Full CI" means every push workflow on the SHA concluded `success`.** Story 32.2's skips are allowed: a group skipped because nothing changed since a green base concludes `success`, which is its designed meaning.
   - A cut from the integration head always changes `src/module.xml` and `src/ocutalon/csp/`, so every group runs.
   - Read with `gh` and jq, not `_bmad/scripts/ci-gate.py`. That one is the kit's, needs uv and ruamel, and the product must not depend on it. The copy is of about 20 lines (the Rule 2 reason).
3. **`stubs` runs before `push`,** so a stub candidate never goes out. The check is static:
   - it reads the XData `Enabled` (missing counts as enabled) and the class or an in-tree superclass;
   - a Default Settings `Enabled` row (`Install/Step/Production.cls:136`) is runtime-only. Today only Epic 12's Telegram step writes one, and Epic 12 removes those items' STUB (inference from `origin/OCT-epic12`).
   - `reopen_if`: any `WriteDefault(..., "Enabled", ...)` on a class with STUB.
4. **Exit 5 is not a stop.** There is no record commit or ASK on each poll, and no hands-on time counts.
5. **A failed gate is run again by `next`.** The candidate cannot change, so a rerun can only be an honest re-read (for example after the author reruns CI, or overrides the eval). The row shows the latest attempt.
6. **The rehearsal uses N = 20,** the bound's denominator (19 of 20).
7. **Two descriptive lines in `test-ci-config.sh`** (`:6`, `:459`) gain `release/*`, so no comment states a stale trigger list (Rule 14). Every edit there adds only `release/*` to one rule. They are reported with the workflow lines.

**Hands-on, shared with 11.15.** This story puts `hands-on` last in the gate list, writes its row (`not run`) and stops. Story 11.15 replaces `step_hands_on`:
- the `## Hands-on pass` grammar;
- the resume refusal;
- carry-over against `Cut from:`;
- for 1.0.0, Epic 38's Stories 38.1 and 38.3 on `release/1.0.0-rc1`.

**Rules 1 and 2:**
- **Consumes:**
  - 11.5's `release.sh` and `lib-release.sh`;
  - 11.2's `upgrade-harness.sh` phases (IA4, real);
  - 11.3/11.11's `rehearse.sh` (IA3, real), and 11.12's later `runs` through the same loop;
  - 11.4's `checklist.sh` (IA1, real);
  - 11.13's `notes.sh --eval` (IA2, real);
  - `eval/run.sh --override` (IA2, real);
  - GitHub runs, through the `gh` shim.
- **Consumed-by:**
  - 11.15: `step_hands_on`;
  - 11.16: "every gate passed";
  - 11.18: the rehearsal runs these steps;
  - Epic 38: the real 1.0.0.

**Ledger inbox (Rule 17):** none (`LEDGER slice` is empty).

**Previous story continuity:** 11.10 (done) touched web e2e only. There is nothing shared.

**Contended paths (U14):**
- `lane-a.yml` (Epics 13 and 15) and `ci/units.sh`, which this story leaves unchanged.
- The workflow lines are a plain union, under the ruling.
- **footprint_extensions:** `ci.yml`, `lane-a.yml` and `test-ci-config.sh`.

**CI budget:** the self-test grows inside the `checks` job, by about 20 to 40 s (inference). The `ci.yml` edit is an IRIS input, so this story's push runs every group once. No unit is added.

## Verification

Run each command in its own foreground call, with `timeout: 600000`, from the worktree root.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh` -- expected: exit 0; the throwaway is removed.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(once)` `test-upgrade-harness.sh`, `test-rehearsal.sh`, `test-release-checklist.sh`, `test-release-notes.sh`, one per call -- expected: exit 0.
- `(once)` With the lane variables, `--live-gates prepare`, then `next` per phase, then `check`, then `clean`, one per call -- expected: IA4.
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-ci-changes.sh`, then `bash ci/changes.sh ci.yml` -- expected: exit 0.
- `(once)` `bash ci/checks.sh` in parts -- expected: no `FAILED`.

**Mutations (Rule 19):**
- AC1: continue past a FAIL.
- AC2: treat a missing `Enabled` as disabled.
- AC3: accept `failure`.
- AC4: accept `onMock`.
- AC5: trust the exit code alone.
- AC6: stop after a failed `seed`.
- AC7: map exit 3 to pass.
- AC8: report `pass` at the end.
- AC9: drop the pin word.
- IA1: write `pass`.
- IA2: ignore `override.reason`.
- IA3: map exit 2 to `WAIT`.

**Shared surfaces:**
- the `STEPS` list, the rows and the `Result:` texts that 11.5's test pins;
- the `lib-release.sh` function list;
- the workflow trigger set pinned by `test-ci-config.sh`.
- Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
