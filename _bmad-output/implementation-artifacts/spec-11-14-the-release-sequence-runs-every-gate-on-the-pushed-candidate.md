---
title: 'Story 11.14: The release sequence runs every gate on the pushed candidate'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
baseline_revision: '10f83005265a3e04535d2d63a429f9511e08d89c'
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-5-one-scripted-sequence-cuts-a-release.md'
warnings: ['oversized']
deferred:
  - summary: >-
      Self-test cost: docker/tests/test-release-sequence.sh takes about 4 minutes on a loaded dev Mac against the spec's +20 to 40 s inference for the hosted checks job.
    evidence: |-
      503 release.sh calls over 25 rules; measured 3 min 52 s on this machine in the final pass. The hosted figure is unmeasured. Measure it from this story's push run; if the checks job is too long, split the gate rules into a second script in a story that may add a CHECK_SCRIPTS entry (this spec forbids one).
    location: >-
      docker/tests/test-release-sequence.sh
    severity: low
  - summary: >-
      IA4 (--live-gates) has no mutation line and no CI run, and its clean part trusts docker for its zero counts.
    evidence: |-
      The live drive takes about 12 minutes of real docker and npm, so a mutation run (for example the Candidate: check dropped, or the row forced to pass, then --live-gates check red) was not paid for. clean now fails when docker is unreachable. Add the mutation line the next time the live drive is run.
    location: >-
      docker/tests/test-release-sequence.sh (--live-gates)
    severity: low
  - summary: >-
      The end-of-steps Result text and the DONE every step branch of release.sh are unreachable until Story 11.15 replaces step_hands_on, so no test pins them.
    evidence: |-
      step_hands_on always returns 6, so the state never reaches done. Story 11.15 must restore the assertion on the end text and on DONE when it makes the pass reachable.
    location: >-
      release/release.sh (stop_routine end kind, cmd_next)
    severity: low
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
- **DW-548 (lead update, rehearse.sh `run`) -- met.** `step_rehearsal` calls `rehearse.sh run --version --rc --candidate release/<v>-rc<n> --record <abs> --runs 20` once per `next`, in `<state>/candidate`, with the fixed tag `rel<v digits>rc<n>reh` and the same options on every call. Exit 4 prints `WAIT rehearsal <the NEXT run line>` and exits 5 (the `<state>/candidate` clone is kept); 75 is a `WAIT` too; 2 is `FAIL rehearsal release/rehearse.sh refused: ...` followed by `rehearse.sh down`; 3 (dry run), 1 and any other code are `FAIL`. Only exit 0 with `Result: pass`, `Mode: rehearsal` and the candidate's full sha passes. `--plant` is never passed. A pin in the self-test (`static`) names the one `run` call and the one `down` call. The older install/runs/report/down wording of the Matrix and of AC7 is met by the `run` command's own phases.

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

### 2026-11-02 -- Review pass
- verdicts: 38 findings -- high 0, medium 13, low 24, false 1, maybe-false 0
- findings:
  - `[low]` `[patch]` blind: a failed ci check names only the first missing workflow -- now every missing workflow is named; test added.
  - `[medium]` `[patch]` blind: ci loses its 15-minute ceiling when pushed_at is absent -- the first clock read is kept as pushed_at; test and mutation added.
  - `[medium]` `[patch]` blind: a mid-drive clone failure resets upg_phase to build and orphans the harness resources -- the phase now stays; test and mutation added.
  - `[low]` `[patch]` blind: a failing down phase is ignored -- WARN line added, gate still judged on the report; test added.
  - `[low]` `[patch]` blind: gate_verdict with an empty sha -- refuses; the substring match is the Candidate: line of the gate's own section.
  - `[low]` `[reject]` blind: rehearsal runs down only for exit 2 -- spec-bound (Matrix); rehearse.sh runs report and down itself on its normal failures.
  - `[medium]` `[patch]` blind: production_stubs misses (continued Extends, single quotes, spaces, STUB = 0 subclass) -- all four handled; test and mutation added.
  - `[low]` `[reject]` blind: the eval WAIT line prints a local path -- a console line for the author to copy, never written to a record or committed.
  - `[low]` `[patch]` blind: spec contradicts itself (status, Decision 14 wording, AC5 mutation note) -- status set at finalize, Decision 14 reworded; the AC5 note stands (checks live in override).
  - `[low]` `[reject]` blind: release.sh header next description stale -- the header states exit 5 and the gates paragraph states the NEXT behaviour.
  - `[medium]` `[patch]` edge: awk fails or prints nothing in production_stubs -- status 3 and FAIL stubs.
  - `[medium]` `[patch]` edge: a path with a space is skipped by the unquoted file list -- one file per line now; test added.
  - `[low]` `[patch]` edge: a STUB = 0 subclass of a stub is judged a stub -- the class's own value wins; test and mutation added.
  - `[medium]` `[patch]` edge: continued Extends, CRLF, single quotes -- continued Extends and single quotes handled; CRLF was already read correctly; tests added.
  - `[low]` `[patch]` edge: node failing in step_eval prints a bare FAIL eval -- a reason is given.
  - `[low]` `[patch]` edge: gate_verdict with an empty sha matches everything -- refuses (same patch as above).
  - `[medium]` `[patch]` edge: pushed_at absent waits forever -- same patch as the blind row.
  - `[low]` `[reject]` edge: ci_runs with a non-numeric databaseId -- wontfix-theoretical: gh prints integers.
  - `[medium]` `[patch]` edge: mid-drive clone failure -- same patch as the blind row.
  - `[low]` `[patch]` edge: down status discarded -- same patch as the blind row.
  - `[low]` `[reject]` edge: run tag 1.10.0 and 11.0.0 collide -- by-design: the spec fixes the tag as rel<v digits>rc<n>; only 1.x is released.
  - `[low]` `[reject]` edge: OCUTALON_RELEASE_GH_REPO seam chooses the repo read -- by-design: the spec names the seam; it names a repository to read, and skips no gate.
  - `[low]` `[patch]` edge: --live-gates clean passes when docker is unreachable -- clean fails when docker info fails.
  - `[false]` `[reject]` edge: clean checks only rel100rc1upg, never the given tag -- the given tag names the throwaway folder only; the gate always runs under the fixed run tag, which clean checks.
  - `[low]` `[patch]` edge: the unrelated local branch no longer pinned out of the pushes -- scratch-branch added to t_pushes.
  - `[medium]` `[patch]` verification-gap: the no-section upgrade case saw a leftover rehearsal section -- cases for a section with no Result and for near-miss and short shas added; the stale pass case cannot arise (a passed gate does not rerun).
  - `[medium]` `[patch]` verification-gap: an extra --plant is invisible to the options assertion -- the whole argv is compared.
  - `[medium]` `[patch]` verification-gap: the full-sha rule is pinned only against an all-zero sha -- near-miss and short fixtures for upgrade, rehearsal and checklist; mutation added.
  - `[medium]` `[patch]` verification-gap: the AC7 exit-3 mutation went red on wording only -- a row of exit 3 with a passing rehearsal section added.
  - `[low]` `[defer]` verification-gap: IA4 has no mutation line and no CI run -- a live mutation costs about 12 minutes; deferred.
  - `[low]` `[defer]` verification-gap: the end Result text and DONE are unreachable and unpinned -- Story 11.15 makes them reachable; deferred.
  - `[low]` `[patch]` verification-gap: t_secret scans before the real-gate rules ran -- the same scan runs again in static, after every rule.
  - `[low]` `[patch]` verification-gap: IA1 compares four of the nine rows -- each row of push to notes is checked against the sequence's state.
  - `[low]` `[reject]` verification-gap: no bad sample for AC9 in test-ci-config.sh -- by-design: the ruling allows only release/* in that file; the pin fails when it is removed (mutation shown).
  - `[medium]` `[patch]` verification-gap other: pushed_at absent -- same patch as the blind row.
  - `[low]` `[patch]` verification-gap other: down status ignored -- same patch as the blind row.
  - `[low]` `[defer]` verification-gap other: self-test runtime -- already in deferred.
  - `[low]` `[reject]` verification-gap other: static pins match wording -- the spec asks for them and the dynamic rules cover the behaviour.
  - intent-alignment: no finding; it reported readings only (R1b rehearsal through `run` as DW-548 says, R2b enabled unless false/0, R3b one verdict over the drive, R4b hermetic stand-ins with real scripts in `real` and the live part); no divergence from the intent.

## Design Notes

**Lead update 2026-11-01 (DW-548, from Story 11.12's review).** Story 11.12 changed `release/rehearse.sh`'s `run`: it needs `OCUTALON_RUN_TAG`, does one phase per call and exits 4 ("call again") until the last phase; `runs` does the next run and refuses once all `--runs` are done or after a failed run; `--plant <id>@<run>` plants a miss in one run. The rehearsal gate step calls `run` once per `next` call (exit 4 = waiting on the next phase, mapped to this story's exit 5 "waiting") and judges only exit 0 with `Result: pass`. Where this spec describes the older contract, this note wins.


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

**Decided in-stage (implement stage, small, reversible, in intent):**
8. **`record_field` is new, not moved.** Built `notes.sh` has `notes_section` (a section reader) but no field reader, so `record_field` in `lib-release.sh` is its own 8-line awk (it ends a section at the next `# ` or `## ` line, as `notes_section` does) and `notes.sh` is untouched.
9. **JSON is read with node, not jq.** `start` already needs node, so the `ci` and `eval` steps read their JSON with `node -e` and no step needs jq. The `gh` shim answers canned JSON and the node shim of the self-test passes `-e` through to the real node.
10. **Step return codes.** A step returns 0 (passed, or with `STEP_MORE=1` a phase done and the step stays current: `NEXT <step>`), 1 (failed), 4 (the author's word not given), 5 (waiting: `WAIT`, nothing written) or 6 (the hands-on stop). The function of `hands-on` is `step_hands_on` (`${step//-/_}`).
11. **The push time is read from the sequence clock at the push** (`pushed_at` in the state, one clock read), so the 15 minutes of the `ci` step run on the seam clock. A run found for one of the two required workflows, a red run and a missing workflow are judged in that order: red first, then missing after 15 minutes, then pending or not yet started (`WAIT`).
12. **The evaluation clone and the candidate clone are cloned from the remote** (`git clone --branch release/<v>-rc<n> <remote url>`), reused only when HEAD is the cut commit, and checked against the remote's branch. The upgrade harness `build`, the rehearsal's first call and the checklist each start from a fresh clone; a rehearsal in progress keeps its clone between the calls.
13. **A harness phase done exits 0** (`NEXT upgrade`), because the Matrix says 0 is a step or phase done; only the rehearsal's exit 4 maps to the waiting exit 5, as DW-548 says. Phase output is printed behind a `upgrade:` / `rehearsal:` / `checklist:` label and kept in `<state>/<gate>.log`.
14. **The `ci` check reads the newest run of each workflow** (highest `databaseId`), so a later run of a workflow supersedes an earlier one (a re-run of one run keeps its id: `gh run list` shows that run's latest attempt). Any workflow that ran for the commit counts, not only `ci` and `lane-a`; those two must be present.
15. **`test-ci-config.sh` descriptions** read "main, feature/OCT_OcuTalon_MVP, OCT-epic* and release/*" (a comma list, not a bare append), so no comment states a stale trigger list.
16. **The self-test seeds** are made once per variant from one archive of HEAD (`stub`, `chk` with the real checklist, `reh` with the real rehearsal, `real`), and the gate chain is built once as snapshots (`pushed`, `cleared`, `evalwait`, `evaled`, `upgraded`, `rehearsed`, `noted`) that the gate rules fork. A gate stub (`gatestub.sh`, written into the throwaway at run time) logs its argv, tag, directory and head, and writes its section from a fixture or a default.

**Decided in-stage (review patches, implement stage):**
17. **`production_stubs`** reads single- or double-quoted attributes, an `Extends (...)` list continued over lines and files whose path holds a space, and a class's own `Parameter STUB` value wins over its superclasses (a subclass with `STUB = 0` is built). A scan that prints no `COUNTS` line is status 3 and `FAIL stubs`, never a pass.
18. **`step_ci`** keeps the first clock read as `pushed_at` when the state has none, so the 15 minutes still end; a missing workflow check names every missing workflow (`no ci, lane-a run on <sha>`).
19. **`step_upgrade`** leaves the phase as it is when the candidate clone fails mid-drive (the harness of the run tag is still in that clone and `down` must reach it); a `down` that exits non-zero prints `WARN upgrade the down phase exited <n>; leftovers of run tag <tag> may remain`, and the gate is still judged on the report. `gate_verdict` fails on a state with no candidate sha, and `eval` fails on a result it could not judge (node failed).

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

**Task 0 figures (this pass, Apple-silicon dev machine, load average 4 to 8):**
- `production_stubs` on this tree: status 0, `COUNTS|45|3|2|0` (45 items in 3 productions, 2 stub items, both disabled, none enabled). On a scratch copy of `src/` with TelegramIn `Enabled="true"`, and again with the attribute removed: status 1, `FOUND|OcuTalon.Production|TelegramIn|OcuTalon.Channel.Telegram.In`.
- `gh run list --branch feature/OCT_OcuTalon_MVP --commit <pushed sha> --event push --json databaseId,workflowName,status,conclusion,url` (read only): a list of `{"conclusion","databaseId","status","url","workflowName"}`; `conclusion` is the empty string while a run is not completed, `status` is `queued`, `in_progress` or `completed`, the workflow names are `ci` and `lane-a`. The self-test's `gh` shim answers this shape.
- Real `rehearse.sh` with no `release.conf`: in this worktree it refuses a candidate without the built bundle first (exit 2, before any docker call); in the sequence's throwaway, whose candidate holds the bundle, `rehearse.sh run` refuses with `REFUSED config: the configuration file is missing or not readable` (exit 2), starts no container and leaves no state (IA3).
- One live upgrade drive (IA4), run tag `e11s14lg`, lane A: prepare (start, cut, image, stubs, push, ci, eval; real npm and docker) 20 s; then one `next` per phase: build 6 s, settings 167 s, seed 126 s, upgrade 285 s (started right after the seed; the reminder R1 fired on time, due 235 s after the candidate was ready), restart 26 s, storage 12 s, report 0 s, down 9 s, so every call fits the 10-minute cap. The harness section read `Result: pass`, `Mode: release`, `Required: no`, `Candidate: 1.0.0 at <the cut sha>`; the upgrade row read `pass`; `clean` left no container, image tag or folder of the run tag, and the lane-A lock folder was empty.
- The hermetic self-test: 25 rules, 503 `release.sh` calls, about 4 min 20 s on this loaded machine (the 11.5 version was about 80 s), also green under `/bin/bash` 3.2 for the gate rules. The hosted figure is unmeasured (see `deferred:`).

**Results of the commands (this pass):** `test-release-sequence.sh` all 25 rules PASS (each of `fail`, `notes`, `override`, `secret` also alone; `libs stubs ci eval upgrade rehearsal checklist fail real push` under `/bin/bash` 3.2); `test-boundaries.sh`, `test-upgrade-harness.sh`, `test-rehearsal.sh`, `test-release-checklist.sh`, `test-release-notes.sh`, `test-ci-config.sh` and `test-ci-changes.sh` exit 0; `ci/changes.sh ci.yml` exits 0; with a push payload, release-only paths (`release/release.sh`, `release/lib-release.sh`, `docker/tests/test-release-sequence.sh`) run no IRIS group and a `ci.yml` path runs all seven; the other 15 scripts of `CHECK_SCRIPTS` (storage, class-rules, compose-file, pinned-sources, after-start, healthcheck, lib-live, bootstrap, demo-path-gate, ci-warm, probe, install-script, readme, eval-set, online-host, online-load) print no `FAILED`. `--live-gates prepare`, nine `next` calls, `check` and `clean` passed (IA4).

**Mutations demonstrated (Rule 19; each applied to one file, the rule named run red, then the file restored from a backup in the scratchpad and confirmed identical with `cmp`):**
- mutation: AC1 a failed gate advances the state (`sset next "$(next_step "$step")"` before the failed stop) -> `fail` red (the next call no longer runs the gate again).
- mutation: AC2 a missing `Enabled` counts as disabled (`en != "true"`) -> `stubs` red (the removed-attribute candidate passes the gate).
- mutation: AC3 `failure` accepted as a green conclusion -> `ci` red (a red `lane-a` passes).
- mutation: AC4 the `onMock` check removed -> `eval` red (the mock and missing-field results pass).
- mutation: AC5 `gate_verdict` trusts the exit status alone (returns 0 after it) -> `override` red (the planted fail, dry run, other-sha and other-mode sections pass) and `rehearsal` unchanged green (its checks are in `override`).
- mutation: AC6 a failed `seed` jumps to `down` -> `upgrade` red (`restart storage report` do not run).
- mutation: AC7 exit 3 passes the rehearsal gate -> `rehearsal` red (the dry run is no longer a `FAIL ... dry run`).
- mutation: AC8 `hands-on` prints `PASS` and returns 0 -> `checklist` red (no stop, no `Result: stopped at hands-on`).
- mutation: AC9 `release/*` removed from the pin in `test-ci-config.sh` -> every rule flags the good sample (`triggers`); and `release/*` removed from `lane-a.yml` -> `FAIL triggers`.
- mutation: IA1 the checklist verdict skipped (`if false`) -> `real` red (the real checklist's `fail` or `not confirmed` passes the gate).
- mutation: IA2 `override.reason` replaced by a fixed text -> `eval` and `real` red (the row and the draft lack `fixture reason`).
- mutation: review patch, `pushed_at` not kept when absent -> `ci` red (the 15 minutes never end).
- mutation: review patch, the phase reset to `build` on a clone failure -> `upgrade` red (the phase no longer stays at `seed`).
- mutation: review patch, a class's `STUB = 0` ignored -> `stubs` red (the built subclass is reported).
- mutation: review patch, `gate_verdict` compares the first seven characters of the sha -> `override` red (the near-miss sha passes).
- mutation: IA3 exit 2 of the rehearsal mapped to `WAIT` -> `real` red (no `FAIL rehearsal ... REFUSED config`).

**Shared surfaces touched:** the `STEPS` list, the `Result:` text at the end of the steps and the stop kinds of `release.sh` (11.5's `record`, `hands`, `resume`, `notes`, `gate`, `push`, `image` and `pushes` rules were updated for the new steps); `lib-release.sh` gains `record_field`, `production_stubs`, `candidate_clone` and `gh_repo`; both workflows and `test-ci-config.sh` gain `release/*` (`ci.yml` is an IRIS input, so this story's push runs every group once).


## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `release/release.sh` gains the gate steps (`stubs ci eval upgrade rehearsal checklist hands-on`), the waiting exit 5 and the hands-on stop that never passes; `release/lib-release.sh` gains `record_field`, `production_stubs`, `candidate_clone` and `gh_repo`; both workflows and the trigger pin gain `release/*`. DW-548 is met: the rehearsal gate calls `rehearse.sh run` once per `next`, exit 4 and 75 give exit 5, and only exit 0 with `Result: pass`, `Mode: rehearsal` and the candidate sha passes.

**Files.** `release/release.sh` (steps, verdicts, exit 5); `release/lib-release.sh` (four helpers); `docker/tests/test-release-sequence.sh` (rules for every Matrix row, IA1 to IA3, `--live-gates` for IA4); `.github/workflows/ci.yml` and `lane-a.yml` (one line each); `docker/tests/test-ci-config.sh` (pin, good sample, two descriptions).

**Review.** 38 findings, 0 high, 13 medium, 24 low, 1 false. Patches applied: 26 rows (some share one fix; the medium ones: the `pushed_at` ceiling, the mid-drive clone failure, `production_stubs` robustness, and the test-strength gaps for `--plant`, near-miss shas, exit 3 and the no-section case; the rest low). Deferred: 3 (IA4 mutation, 11.15's unreachable end text, self-test runtime). Rejected: 9, each with its reason in the log above.

**Follow-up review recommended: true.** Patched medium entries: 13 (two or more). The unverified risk is the `production_stubs` awk rewrite (a `getline` continuation, one file per line with globbing off, STUB precedence) and the `step_upgrade` phase handling after a clone failure: each has a new test and a mutation, but no second reviewer has read them.

**Verification.** `test-release-sequence.sh` all 25 rules PASS (3 min 52 s); `test-boundaries.sh` exit 0; the four mutations of the patches went red and the files were restored (`cmp`); the earlier pass's figures stand: `test-upgrade-harness.sh`, `test-rehearsal.sh`, `test-release-checklist.sh`, `test-release-notes.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `ci/changes.sh ci.yml` exit 0, the other `CHECK_SCRIPTS` scripts print no `FAILED`, and IA4 ran live (prepare, eight phases, check, clean) with the lane-A lock folder empty.

**Residual risks.** The real rehearsal (20 runs), checklist, evaluation and hands-on passes are untested end to end (no clean host, author confirmations or model key); they are covered through stubs and the real scripts' refusals. The hosted checks-job time of the self-test is unmeasured.
